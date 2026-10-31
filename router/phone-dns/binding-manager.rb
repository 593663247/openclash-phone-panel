require_relative 'apply-engine'

module PhoneBindingManager
 def self.files
  [PhoneApply.source,PanelStore.path('/etc/config/dhcp'),PanelStore.path('/etc/config/phone_panel'),PhoneBindings.path,PhoneNodeRegistry.path,PanelStore.path('/etc/phone-dns/mapping.yaml'),PanelStore.path('/etc/phone-dns/devices.yaml')]
 end
 def self.revision
  Digest::SHA256.hexdigest(PhoneSettings.values.to_yaml.b+files.map{|file|file.b+"\0".b+(File.file?(file) ? File.binread(file) : ''.b)}.join("\0".b))
 end
 def self.plan
  %w[dhcp phone_panel openclash].each{|section|raise "#{section} 有未保存修改" unless PanelStore.run('uci','changes',section).strip.empty?}
  mapping=PanelStore.read(PanelStore.path('/etc/phone-dns/mapping.yaml'),[])
  cfg=PhoneBindings.compose(YAML.safe_load(File.binread(PhoneApply.source),aliases:true))
  previous=PhoneBindings.read
  document=previous || PhoneBindings.capture(cfg,mapping,PanelStore.read(PanelStore.path('/etc/phone-dns/devices.yaml'),[]),PhoneBindings.hosts)
  PhoneBindings.check_hosts(document,PhoneBindings.hosts)
  composed=PhoneBindings.compose(cfg,document)
  {'ok'=>true,'revision'=>revision,'count'=>document['devices'].size,'devices'=>document['devices'],'document'=>document,'already_initialized'=>!previous.nil?,'warning'=>'确认后保存独立绑定并合并当前配置，备份后重载并验收。仅维护面板拥有的精确规则；实际手机租约及出口另行验证。'}
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
