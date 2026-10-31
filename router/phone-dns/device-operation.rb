require_relative 'device-edit'
require_relative 'tasks'
require 'yaml'
def edit_run(*args,**_options)
 output=IO.popen(args+[{err:[:child,:out]}],&:read)
 status=$?.exitstatus
 if @edit_log
  File.open(@edit_log,File::WRONLY|File::CREAT|File::APPEND,0600){|o|o.puts("[#{Time.now.utc}] #{args.first} exit=#{status}");o.write(output);o.puts}
 end
 status==0
end
def edit_restart_proxy
 return false unless edit_run('/etc/init.d/openclash','stop')
 # OpenClash's quick-start marker otherwise reuses the previous generated YAML.
 if File.exist?('/tmp/openclash.change')
  File.open(@edit_log+'.quickstart','wb',0600){|o|o.write(File.binread('/tmp/openclash.change'))}
  File.delete('/tmp/openclash.change')
 end
 edit_run('/etc/init.d/openclash','start')
end
require_relative 'apply-engine'
base='/etc/phone-dns'
begin
 mode=ARGV.shift;req=YAML.safe_load(File.read(ARGV.fetch(0)));raise 'Invalid request' unless req.is_a?(Hash)
 f=IO.popen(['uci','-q','get','openclash.config.config_path'],&:read).strip
 raise 'Invalid config path' unless f.start_with?('/etc/openclash/config/') && f.end_with?('.yaml') && !f.include?('..')
 raise 'Save or discard pending panel settings first' unless IO.popen(['uci','changes','phone_panel'],&:read).strip.empty?
 saved_settings=File.exist?('/etc/config/phone_panel') ? File.binread('/etc/config/phone_panel') : ''
 files=[f,base+'/mapping.yaml',base+'/devices.yaml','/etc/config/dhcp',base+'/managed-bindings.yaml'];snap=files.to_h{|p|[p,File.exist?(p) ? File.binread(p) : "--- []\n"]}
 digest=IO.popen(['sha256sum'],'r+'){|i|i.write(DeviceEdit.revision_data(snap.values,saved_settings));i.close_write;i.read.split.first}
 lease_sections=lambda do
  raise '请先保存或撤销尚未提交的 DHCP 修改' unless IO.popen(['uci','changes','dhcp'],&:read).strip.empty?
  sections=[]
  IO.popen(['uci','show','dhcp'],&:read).each_line do |line|
   next unless line =~ /\Adhcp\.([a-zA-Z0-9_]+|@host\[\d+\])=host\s*$/
   section=$1
   sections<<{'section'=>section,'ip'=>IO.popen(['uci','-q','get',"dhcp.#{section}.ip"],&:read).strip,'mac'=>IO.popen(['uci','-q','get',"dhcp.#{section}.mac"],&:read).strip,'name'=>IO.popen(['uci','-q','get',"dhcp.#{section}.name"],err:File::NULL,&:read).strip}
  end
  sections
 end
 migration_check=lambda do
  next nil unless req['operation']=='change_ip'
  DeviceEdit.ip_migration(req,lease_sections.call,(File.readlines('/tmp/dhcp.leases') rescue []),IO.popen(['ip','neigh','show','dev',PhoneSettings['bridge']],&:read))
 end
 name_check=lambda do
  next nil unless req['operation']=='rename' && DeviceEdit.dhcp_hostname(req['name'])
  DeviceEdit.name_lease(req['ip'],lease_sections.call).merge('name'=>DeviceEdit.dhcp_hostname(req['name']))
 end
 migration=migration_check.call;name_update=name_check.call
 mapping=YAML.load_file(files[1]);document=PhoneBindings.require_migrated(mapping);PhoneBindings.assert_mapping(document,mapping)
 result=DeviceEdit.transform(PhoneBindings.compose(YAML.load_file(f,aliases:true)),mapping,YAML.safe_load(snap[files[2]])||[],req)
 if mode=='preview'
  puts PanelTasks.json({'ok'=>true,'revision'=>digest,'summary'=>req.merge(migration || {}).merge('dhcp_name'=>name_update && name_update['name']),'warning'=>'确认后在后台应用；名称同步 DHCP，修改 IP 后手机需重连 Wi-Fi。删除会解除防直连保护。'});exit
 end
 raise 'Unsupported mode' unless mode=='apply'
 revision=lambda {DeviceEdit.revision_data(files.map{|p|File.exist?(p) ? File.binread(p) : "--- []\n"},(File.file?('/etc/config/phone_panel') ? File.binread('/etc/config/phone_panel') : '')).then{|data|require 'digest';Digest::SHA256.hexdigest(data)}}
 expected_lease=nil
 postcheck=lambda {DeviceEdit.verify_lease(expected_lease,lambda{|key|PanelStore.run('uci','-q','get',key)})}
 outcome=PhoneApply.transaction(f,expected_revision:req['revision'],revision:revision,network:req['operation']!='rename',postcheck:postcheck) do
  migration=migration_check.call if migration;name_update=name_check.call if name_update
  files.first(3).zip([result['config'],result['mapping'],result['devices']]).each{|p,v|PhoneApply.atomic(p,v.to_yaml)}
  if migration
   device=result['devices'].find{|d|d['ip']==migration['new_ip']};name=DeviceEdit.dhcp_hostname(device && device['name'])
   expected_lease={'section'=>migration['section'],'ip'=>migration['new_ip'],'mac'=>migration['mac']}
   expected_lease['name']=name if name
   PhoneApply.command('uci','set',"dhcp.#{migration['section']}.name=#{name}") if name
   PhoneApply.command('uci','set',"dhcp.#{migration['section']}.ip=#{migration['new_ip']}")
  elsif name_update
   expected_lease=name_update
   PhoneApply.command('uci','set',"dhcp.#{name_update['section']}.name=#{name_update['name']}")
  end
  PhoneApply.command('uci','commit','dhcp') if migration || name_update
  if migration
   actual=PanelStore.run('uci','-q','get',"dhcp.#{migration['section']}.ip").strip
   raise '静态租约 IP 未写入' unless actual==migration['new_ip']
  end
  if name_update
   raise '静态租约名称未写入' unless PanelStore.run('uci','-q','get',"dhcp.#{name_update['section']}.name").strip==name_update['name']
  end
  PhoneBindings.write(PhoneBindings.capture(result['config'],result['mapping'],result['devices'],lease_sections.call,previous:PhoneBindings.read,expected_names:(migration&&name ? {migration['new_ip']=>name} : name_update ? {req['ip']=>name_update['name']} : {})))
  {}
 end
 puts PanelTasks.json(outcome)
rescue=>e
 puts PanelTasks.json({'error'=>e.message})
end
