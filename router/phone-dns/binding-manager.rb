require_relative 'apply-engine'

module PhoneBindingManager
 def self.files
  [PhoneApply.source,PanelStore.path('/etc/config/dhcp'),PanelStore.path('/etc/config/phone_panel'),PhoneBindings.path,PhoneNodeRegistry.path,PanelStore.path('/etc/phone-dns/mapping.yaml'),PanelStore.path('/etc/phone-dns/devices.yaml')]
 end
 def self.revision
  Digest::SHA256.hexdigest(PhoneSettings.values.to_yaml.b+files.map{|file|file.b+"\0".b+(File.file?(file) ? File.binread(file) : ''.b)}.join("\0".b))
 end
 def self.legacy_rows(file,label)
  return [] unless File.exist?(file)
  rows=YAML.safe_load(File.binread(file),aliases:false)
  raise "#{label} 必须是列表，不能忽略后重建" unless rows.is_a?(Array)&&rows.all?{|r|r.is_a?(Hash)}
  rows
 rescue Psych::Exception
  raise "#{label} 损坏，已停止迁移，请先恢复或核对"
 end
 def self.plan
  baseline=revision
  %w[dhcp phone_panel openclash].each{|section|raise "#{section} 有未保存修改" unless PanelStore.run('uci','changes',section).strip.empty?}
  cfg=PhoneBindings.compose(YAML.safe_load(File.binread(PhoneApply.source),aliases:true))
  previous=PhoneBindings.read
  if previous
   document=previous
  else
   mapping=legacy_rows(PanelStore.path('/etc/phone-dns/mapping.yaml'),'旧分组记录')
   devices=legacy_rows(PanelStore.path('/etc/phone-dns/devices.yaml'),'旧设备记录')
   raise '旧分组记录字段无效，请先核对' unless mapping.all?{|g|g['id'].is_a?(Integer)&&g['node'].is_a?(String)&&g['ips'].is_a?(Array)}
   raise '源配置规则格式无效' unless cfg.fetch('rules',[]).is_a?(Array)
   cfg.fetch('rules',[]).each do |rule|
    fields=rule.to_s.split(',');next unless fields.size==3&&fields[0]=='SRC-IP-CIDR'&&fields[1].end_with?('/32')&&PhoneSettings.phone?(fields[2])
    ip=fields[1].delete_suffix('/32');next unless PhoneSettings.usable?(ip)
    next if mapping.any?{|g|g.fetch('ips',[]).include?(ip)}
    group=mapping.find{|g|g['node']==fields[2]}
    unless group
     id=PhoneSettings.next_group_id(mapping)
     group=PhoneSettings.group(id,fields[2]);mapping<<group
    end
    group['ips']<<ip
   end
   document=PhoneBindings.capture(cfg,mapping,devices,PhoneBindings.hosts)
  end
  PhoneBindings.check_hosts(document,PhoneBindings.hosts)
  leases,neighbors=PhoneBindings.network_state;PhoneBindings.check_network(document,leases,neighbors)
  composed=PhoneBindings.compose(cfg,document)
  raise '预览期间配置发生变化，请重新检查' unless revision==baseline
  summary=document['devices'].map{|d|d.merge('current_lease_ip'=>leases.find{|l|l[1].downcase==d['mac']}&.[](2))}
  {'ok'=>true,'revision'=>baseline,'count'=>document['devices'].size,'devices'=>summary,'document'=>document,'already_initialized'=>!previous.nil?,'warning'=>'确认后保存独立绑定并合并当前配置，备份后重载并验收。仅维护面板拥有的精确规则；租约与固定 IP 不同时需重连 Wi-Fi。实际出口另行验证。'}
 end
 def self.apply(request)
  PhoneApply.transaction(PhoneApply.source,expected_revision:request['revision'],revision:method(:revision)) do
   checked=plan;PhoneBindings.write(checked.fetch('document'))
   {'message'=>'独立设备绑定已保存，配置与运行态验收通过；实际手机业务需复测。'}
  end
 end
end

if __FILE__==$PROGRAM_NAME
 begin
  mode=ARGV.shift
  result=case mode
  when 'info';PhoneBindings.info
  when 'preview';PhoneBindingManager.plan.reject{|key,_|key=='document'}
  when 'apply';PhoneBindingManager.apply(YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false))
  else;raise '不支持的持久化操作'
  end
  puts PanelStore.json(result)
 rescue=>e;puts PanelStore.json({'error'=>e.message})
 end
end
