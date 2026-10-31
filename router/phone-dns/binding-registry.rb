require_relative 'panel-store'
require_relative 'node-registry'
require 'digest'

# Durable desired bindings; mapping/listeners/YAML rules are derived outputs.
module PhoneBindings
 SCHEMA=1
 def self.path;PanelStore.path('/etc/phone-dns/managed-bindings.yaml');end
 def self.raw;File.file?(path) ? File.binread(path) : ''.b;end
 def self.mac(value)
  text=value.to_s.downcase
  raise '设备 MAC 无效或包含多个地址' unless text.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/) && text!='00:00:00:00:00:00' && text[0,2].to_i(16).even?
  text
 end
 def self.rule(device);"SRC-IP-CIDR,#{device.fetch('ip')}/32,#{device.fetch('node')}";end
 def self.validate(document)
  raise '设备绑定库格式或版本不受支持，请从备份恢复' unless document.is_a?(Hash) && document['schema']==SCHEMA && document['revision'].is_a?(Integer) && document['revision']>0 && document['devices'].is_a?(Array) && document['owned_rules'].is_a?(Array)
  rows=document['devices'];owned=document['owned_rules']
  raise '设备绑定库超过安全容量限制' if rows.size>2048 || owned.size>8192
  rows.each do |d|
   raise '设备绑定记录格式无效' unless d.is_a?(Hash)
   m=mac(d['mac']);raise '设备稳定标识无效' unless d['id']=='mac-'+m.delete(':') && d['mac']==m
   raise '受管 IP 不在当前网段，请恢复设置或迁移配置' unless PhoneSettings.usable?(d['ip'])
   raise '设备名称无效' unless d['name'].is_a?(String) && (1..40).include?(d['name'].length) && !d['name'].match?(/[\x00-\x1f\x7f]/)
   raise '静态租约名称记录无效' if d.key?('dhcp_name') && (!d['dhcp_name'].is_a?(String)||d['dhcp_name'].bytesize>253||d['dhcp_name'].match?(/[\x00-\x1f\x7f]/))
   raise '绑定节点名称无效，请恢复节点前缀设置' unless d['node'].is_a?(String) && PhoneSettings.phone?(d['node']) && !d['node'].match?(/[,\x00-\x1f\x7f]/)
  end
  %w[id mac ip].each{|key|raise "设备绑定库 #{key} 重复" unless rows.map{|d|d[key]}.uniq.size==rows.size}
  raise '规则所有权记录无效' unless owned.uniq.size==owned.size && owned.all?{|r|r.is_a?(String)&&r.match?(/\ASRC-IP-CIDR,(?:\d{1,3}\.){3}\d{1,3}\/32,[^,\x00-\x1f\x7f]+\z/)}
  owned.each{|r|PhoneSettings.ipnum(r.split(',')[1].delete_suffix('/32'))}
  raise '设备绑定缺少规则所有权记录' unless (rows.map{|d|rule(d)}-owned).empty?
  document
 end
 def self.read
  unless File.exist?(path)
   raise '独立绑定库丢失，请恢复上次验收快照；未退回旧导入模式' if has_policy?
   return nil
  end
  raise '设备绑定库不安全或体积异常' if File.symlink?(path) || !File.file?(path) || File.size(path)>2*1024*1024
  validate(YAML.safe_load(File.binread(path),aliases:false))
 rescue Psych::Exception
  raise '设备绑定库损坏，已停止合并；请从备份恢复'
 end
 def self.has_policy?
  return true if File.exist?(path)||File.exist?(PanelStore.state+'/bindings-last-good.yaml')
  file=PanelStore.path('/etc/phone-dns/persistent-guard.yaml');return false unless File.file?(file)
  return true if File.symlink?(file)||File.size(file)>256*1024
  record=YAML.safe_load(File.binread(file),aliases:false)
  !record.is_a?(Hash)||!record['devices'].is_a?(Array)||!record['devices'].empty?
 rescue;true
 end
 def self.check_hosts(document,hosts)
  document['devices'].each do |d|
   matches=hosts.select{|h|h['ip']==d['ip']}
   raise "#{d['ip']} 必须有唯一 DHCP 静态租约，请先解决冲突" unless matches.size==1 && matches.first.fetch('mac','').downcase.split==[d['mac']]
   raise "#{d['ip']} 的 MAC 与其他静态地址冲突" if hosts.any?{|h|h['ip']!=d['ip'] && h.fetch('mac','').downcase.split.include?(d['mac'])}
   raise "#{d['ip']} 的 DHCP 名称与独立记录不一致" if d.key?('dhcp_name')&&matches.first.fetch('name','')!=d['dhcp_name']
  end
  true
 end
 def self.hosts
  result=[];host=nil
  PanelStore.run('uci','export','dhcp').each_line do |line|
   if line =~ /^config\s+(\w+)/;host=$1=='host' ? {} : nil;result<<host if host
   elsif host && line =~ /^\s*(?:option|list)\s+(\w+)\s+'([^']*)'/;host[$1]=[host[$1],$2].compact.join(' ')
   end
  end
  result
 end
 def self.network_state
  leases=File.file?(PanelStore.path('/tmp/dhcp.leases')) ? File.readlines(PanelStore.path('/tmp/dhcp.leases')) : []
  [PhoneSettings.active_leases(leases),PanelStore.run('ip','neigh','show','dev',PhoneSettings['bridge'])]
 end
 def self.check_network(document,leases,neighbors)
  document['devices'].each do |d|
   raise "#{d['ip']} 仍租给其他 MAC，请先释放地址冲突" if leases.any?{|l|l[2]==d['ip']&&l[1].downcase!=d['mac']}
   neighbors.each_line do |line|
    fields=line.split;next unless fields.first==d['ip']&&fields.include?('lladdr')
    seen=fields[fields.index('lladdr')+1].to_s.downcase
    raise "#{d['ip']} 在邻居表中被其他 MAC 占用" unless seen==d['mac']
   end
  end
  true
 end
 def self.guard_text(document,exists:false)
  validate(document);guard_program(document['devices'],PhoneSettings['bridge'],exists:exists)
 end
 def self.guard_program(rows,bridge,exists:false)
  raise '独立保护数据格式无效' unless rows.is_a?(Array)&&rows.size<=2048&&bridge.is_a?(String)&&bridge.match?(/\A[a-zA-Z0-9_.:-]{1,15}\z/)
  rows.each{|d|PhoneSettings.ipnum(d.fetch('ip'));mac(d.fetch('mac'))}
  prefix=exists ? "delete table inet phone_panel_persistent\n" : ''
  rules=rows.empty? ? '' : "iifname \"#{bridge}\" oifname != \"#{bridge}\" ip saddr { #{rows.map{|d|d['ip']}.join(', ')} } counter drop\niifname \"#{bridge}\" oifname != \"#{bridge}\" ether saddr { #{rows.map{|d|d['mac']}.join(', ')} } counter drop\n"
  prefix+"table inet phone_panel_persistent {\nchain guard {\ntype filter hook forward priority -20; policy accept;\n"+rules+"}\n}\n"
 end
 def self.guard(document=read)
  return unless document
  validate(document)
  apply_guard(document['devices'],PhoneSettings['bridge'])
  PanelStore.write(PanelStore.path('/etc/phone-dns/persistent-guard.yaml'),{'schema'=>1,'bridge'=>PhoneSettings['bridge'],'devices'=>document['devices'].map{|d|d.slice('ip','mac')}})
  true
 end
 def self.apply_guard(rows,bridge)
  _,code=PanelStore.capture('nft','list','table','inet','phone_panel_persistent')
  text=guard_program(rows,bridge,exists:code==0)
  output=IO.popen(['nft','-f','-',{err:[:child,:out]}],'r+'){|io|io.write(text);io.close_write;io.read}
  raise '独立防直连保护加载失败，已停止配置应用' unless $?.success?
  true
 end
 def self.boot_guard
  begin
   document=read
   return guard(document) if document
  rescue=>failure
   warn '独立绑定库不可读，尝试加载上次保存的保护；配置合并仍会阻止生效'
  end
  file=PanelStore.path('/etc/phone-dns/persistent-guard.yaml');return unless File.file?(file)
  raise '独立保护备份不安全' if File.symlink?(file)||File.size(file)>256*1024
  record=YAML.safe_load(File.binread(file),aliases:false)
  raise '独立保护备份版本无效' unless record.is_a?(Hash)&&record['schema']==1
  apply_guard(record.fetch('devices'),record.fetch('bridge'))
 end
 def self.capture(cfg,mapping,devices,hosts,previous:nil,expected_names:{})
  rows=mapping.flat_map do |group|
   group.fetch('ips',[]).map do |ip|
    names=(cfg['proxies']||[]).select{|n|n['name']==group['node']};raise "节点 #{group['node']} 缺失或重名" unless names.size==1
    rules=(cfg['rules']||[]).select{|r|r.to_s.start_with?("SRC-IP-CIDR,#{ip}/32,")}
    expected="SRC-IP-CIDR,#{ip}/32,#{group['node']}";raise "#{ip} 的来源规则与面板绑定不一致" unless rules==[expected]
    meta=devices.select{|d|d['ip']==ip};raise "#{ip} 有重复设备记录" if meta.size>1
    leases=hosts.select{|h|h['ip']==ip};raise "#{ip} 缺少唯一静态租约" unless leases.size==1
    m=mac(leases.first['mac']);d=meta.first||{}
    raise "#{ip} 的设备 MAC 与静态租约不同" if d['mac'] && mac(d['mac'])!=m
    name=d['name'] || leases.first['name'] || 'phone-'+ip.tr('.','-')
    row={'id'=>'mac-'+m.delete(':'),'mac'=>m,'ip'=>ip,'name'=>name,'node'=>group['node']}
    row['dhcp_name']=expected_names.key?(ip) ? expected_names.fetch(ip) : leases.first.fetch('name','')
    row
   end
  end
  raise '设备记录含未归属分组的地址，请先核对后再迁移' unless (devices.map{|d|d['ip']}-rows.map{|d|d['ip']}).empty?
  old=previous ? validate(previous) : nil
  document={'schema'=>SCHEMA,'revision'=>(old ? old['revision']+1 : 1),'devices'=>rows.sort_by{|d|d['id']},'owned_rules'=>((old ? old['owned_rules'] : [])+rows.map{|d|rule(d)}).uniq}
  validate(document);check_hosts(document,hosts);document
 end
 def self.write(document);PanelStore.write(path,validate(document));end
 def self.require_migrated(mapping)
  document=read
  raise '请先在管理维护预览并迁移设备绑定，再修改已有设备' if !document && mapping.any?{|g|!g.fetch('ips',[]).empty?}
  document
 end
 def self.compose(cfg,document=read)
  raise 'OpenClash 配置必须是对象' unless cfg.is_a?(Hash)
  raise 'OpenClash 节点列表格式无效' unless cfg['proxies'].nil?||(cfg['proxies'].is_a?(Array)&&cfg['proxies'].all?{|n|n.is_a?(Hash)&&n['name'].is_a?(String)})
  output=Marshal.load(Marshal.dump(cfg));PhoneNodeRegistry.merge(output)
  return output unless document
  validate(document);rules=output['rules']||[]
  raise 'OpenClash rules 格式无效' unless rules.is_a?(Array) && rules.all?{|r|r.is_a?(String)}
  document['devices'].each do |d|
   raise "持久化绑定 #{d['ip']} 的节点 #{d['node']} 缺失或重名；拒绝退回直连" unless (output['proxies']||[]).count{|n|n['name']==d['node']}==1
   matches=rules.select{|r|r.start_with?("SRC-IP-CIDR,#{d['ip']}/32,")}
   raise "#{d['ip']} 存在非面板拥有的冲突来源规则" if matches.any?{|r|!document['owned_rules'].include?(r)}
   raise "#{d['ip']} 存在重复来源规则，请人工核对" unless matches.uniq.size==matches.size
  end
  # Exact owned tuples only: preserve all unrelated rule types, CIDRs and targets.
  output['rules']=document['devices'].map{|d|rule(d)}+rules.reject{|r|document['owned_rules'].include?(r)}
  output
 end
 def self.mapping(document,mapping)
  output=Marshal.load(Marshal.dump(mapping));output.each{|g|g['ips']=[]}
  document['devices'].each do |d|
   matches=output.select{|g|g['node']==d['node']};raise '同名分组重复，请先核对' if matches.size>1
   group=matches.first
   unless group
    id=output.map{|g|g['id'].to_i}.max.to_i+1;raise '持久化分组超过上限' if id>PhoneSettings.port('max_groups')
    group=PhoneSettings.group(id,d['node']);output<<group
   end
   group['ips']<<d['ip']
  end
  output
 end
 def self.devices(document,mapping)
  document['devices'].map{|d|d.slice('id','mac','ip','name').merge('group'=>mapping.find{|g|g['node']==d['node']}.fetch('id'))}
 end
 def self.assert_mapping(document,mapping)
  return unless document
  expected=document['devices'].map{|d|[d['ip'],d['node']]}.sort
  actual=mapping.flat_map{|g|g.fetch('ips',[]).map{|ip|[ip,g['node']]}}.sort
  raise '运行分组与独立绑定库不一致，请先检查并应用持久化配置' unless expected==actual
 end
 def self.status_file;PanelStore.state+'/persistence-status.yaml';end
 def self.process_token(pid)
  File.read("/proc/#{pid}/stat").split(')',2).last.split[19]
 rescue;nil
 end
 def self.parent_apply?
  token=ENV['PHONE_PANEL_APPLY_TOKEN'];return false unless token
  owner=PanelStore.read(PanelStore.path('/var/lock/phone-panel-owner.json'),{})
  return false unless owner['token']==token&&owner['pid'].is_a?(Integer)&&owner['pid']>1
  Process.kill(0,owner['pid'])
  owner['process_token']==process_token(owner['pid'])
 rescue;false
 end
 def self.status(state,extra={})
  extra=extra.merge('process_token'=>process_token(Process.pid)) if state=='generating'
  PanelStore.write(status_file,{'state'=>state,'at'=>Time.now.to_i}.merge(extra))
 end
 def self.info
  document=read;record=PanelStore.read(status_file,{})
  if record['state']=='generating'
   alive=begin;Process.kill(0,record['pid'].to_i);record['pid'].to_i>1;rescue;false;end
   alive=false if record['process_token']&&record['process_token']!=process_token(record['pid'])
   boot=(File.read('/proc/sys/kernel/random/boot_id').strip rescue 'test')
   record=record.merge('state'=>'interrupted','message'=>'上次合并进程中断；请检查或恢复上次验收快照') if !alive || record['boot']!=boot
  end
  {'ok'=>true,'initialized'=>!document.nil?,'schema'=>document && document['schema'],'revision'=>document && document['revision'],'count'=>document ? document['devices'].size : 0,'status'=>record,'last_good'=>PanelStore.read(PanelStore.state+'/bindings-last-good.yaml',{})}
 rescue=>e
  {'ok'=>true,'initialized'=>false,'blocked'=>true,'message'=>e.message,'last_good'=>PanelStore.read(PanelStore.state+'/bindings-last-good.yaml',{})}
 end
end

if __FILE__==$PROGRAM_NAME
 begin
  raise '不支持的持久化操作' unless ARGV.shift=='guard'
  PhoneBindings.boot_guard
 rescue=>e;warn e.message;exit 1
 end
end
