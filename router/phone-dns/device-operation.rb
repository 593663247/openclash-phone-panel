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
base='/etc/phone-dns'
begin
 mode=ARGV.shift;req=YAML.safe_load(File.read(ARGV.fetch(0)));raise 'Invalid request' unless req.is_a?(Hash)
 f=IO.popen(['uci','-q','get','openclash.config.config_path'],&:read).strip
 raise 'Invalid config path' unless f.start_with?('/etc/openclash/config/') && f.end_with?('.yaml') && !f.include?('..')
 raise 'Save or discard pending panel settings first' unless IO.popen(['uci','changes','phone_panel'],&:read).strip.empty?
 saved_settings=File.exist?('/etc/config/phone_panel') ? File.binread('/etc/config/phone_panel') : ''
 files=[f,base+'/mapping.yaml',base+'/devices.yaml','/etc/config/dhcp'];snap=files.to_h{|p|[p,File.exist?(p) ? File.binread(p) : "--- []\n"]}
 digest=IO.popen(['sha256sum'],'r+'){|i|i.write(DeviceEdit.revision_data(snap.values,saved_settings));i.close_write;i.read.split.first}
 lease_sections=lambda do
  raise '请先保存或撤销尚未提交的 DHCP 修改' unless IO.popen(['uci','changes','dhcp'],&:read).strip.empty?
  sections=[]
  IO.popen(['uci','show','dhcp'],&:read).each_line do |line|
   next unless line =~ /\Adhcp\.([a-zA-Z0-9_]+|@host\[\d+\])=host\s*$/
   section=$1
   sections<<{'section'=>section,'ip'=>IO.popen(['uci','-q','get',"dhcp.#{section}.ip"],&:read).strip,'mac'=>IO.popen(['uci','-q','get',"dhcp.#{section}.mac"],&:read).strip}
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
 result=DeviceEdit.transform(YAML.load_file(f,aliases:true),YAML.load_file(files[1]),YAML.safe_load(snap[files[2]])||[],req)
 if mode=='preview'
  puts PanelTasks.json({'ok'=>true,'revision'=>digest,'summary'=>req.merge(migration || {}).merge('dhcp_name'=>name_update && name_update['name']),'warning'=>'英文、数字、连字符组成的设备名称会同步到 DHCP；其他名称只作面板显示。改绑/删除/修改 IP 会重启代理。修改 IP 保留 MAC、节点，更新静态租约；手机需重新连接 Wi-Fi 获取新 IP，手动静态 IP 须在手机同步修改。不会清空或强制撤销其他租约。删除会解除防直连保护。'});exit
 end
 raise 'Unsupported mode' unless mode=='apply'
 lock=File.open('/var/lock/phone-panel.lock','w',0600);raise 'Other task running' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
 # Recheck after acquiring the lock, not just before preview.
 live=files.map{|p|File.exist?(p) ? File.binread(p) : "--- []\n"}
 now=IO.popen(['sha256sum'],'r+'){|i|i.write(DeviceEdit.revision_data(live,saved_settings));i.close_write;i.read.split.first}
 raise 'Configuration changed; preview again' unless req['revision']==now && now==digest
 migration=migration_check.call if migration
 name_update=name_check.call if name_update
 dir='/root/phone-panel-device-edits';Dir.mkdir(dir,0700) unless Dir.exist?(dir)
 id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+Process.pid.to_s
 @edit_log=dir+'/'+id+'.log'
 File.open(dir+'/'+id+'.request.yaml','w',0600){|o|o.write(req.to_yaml)}
 extras=Dir.glob(base+'/*.yaml')+Dir.glob(base+'/group-*.conf')+[base+'/config.json','/etc/config/dhcp','/etc/nftables.d/90-phone-fixed-egress.nft']
  extras.each{|p|snap[p]=File.binread(p) if File.file?(p)}
  File.open(dir+'/'+id+'.yaml','w',0600){|o|o.write(snap.to_yaml)}
 begin
  files.first(3).zip([result['config'],result['mapping'],result['devices']]).each{|p,v|File.open(p,'w',0600){|o|o.write(v.to_yaml)}}
  if migration
   device=result['devices'].find{|d|d['ip']==migration['new_ip']}
   hostname=DeviceEdit.dhcp_hostname(device && device['name'])
   if hostname
    raise '更新 DHCP 名称失败' unless edit_run('uci','set',"dhcp.#{migration['section']}.name=#{hostname}")
   end
   raise '更新静态租约失败'  unless edit_run('uci','set',"dhcp.#{migration['section']}.ip=#{migration['new_ip']}",out:File::NULL,err:File::NULL)
   raise '保存静态租约失败' unless edit_run('uci','commit','dhcp',out:File::NULL,err:File::NULL)
  end
  if name_update
   raise '更新 DHCP 名称失败' unless edit_run('uci','set',"dhcp.#{name_update['section']}.name=#{name_update['name']}")
   raise '保存 DHCP 名称失败' unless edit_run('uci','commit','dhcp')
   raise 'DHCP 重载失败' unless edit_run('/etc/init.d/dnsmasq','reload')
  end
  if req['operation']!='rename'
   raise 'Source validation failed' unless edit_run('/etc/openclash/clash','-t','-d','/etc/openclash','-f',f,out:File::NULL,err:File::NULL)
   raise 'Alignment failed' unless edit_run('/usr/bin/ruby',base+'/align-dns.rb',f,out:File::NULL,err:File::NULL)
   raise 'Firewall validation failed' unless edit_run('fw4','check',out:File::NULL,err:File::NULL)
   raise 'Firewall reload failed' unless edit_run('/etc/init.d/firewall','reload',out:File::NULL,err:File::NULL)
   raise 'Proxy restart failed' unless edit_restart_proxy
  end
  if migration
   runtime=YAML.load_file('/etc/openclash/'+File.basename(f),aliases:true)
   target_rule=result['config']['rules'].find{|r|r.start_with?("SRC-IP-CIDR,#{migration['new_ip']}/32,")}
   raise '运行绑定规则未同步' unless target_rule && runtime.fetch('rules',[]).include?(target_rule) && !runtime.fetch('rules',[]).any?{|r|r.start_with?("SRC-IP-CIDR,#{migration['old_ip']}/32,")}
   raise '运行嗅探排除未同步' unless runtime.dig('sniffer','skip-src-address').to_a.include?(migration['new_ip']+'/32')
   raise '防直连保护未同步' unless edit_run('nft','get','element','inet','fw4','codex_phone4','{',migration['new_ip'],'}')
   dns=IO.popen(['nft','list','chain','inet','fw4','codex_phone_dns'],err:File::NULL,&:read)
   raise 'DNS 接管规则未同步' unless dns.include?(migration['new_ip'])
   raise 'DHCP 重载失败'  unless edit_run('/etc/init.d/dnsmasq','reload',out:File::NULL,err:File::NULL)
  end
  puts PanelTasks.json({'ok'=>true,'diagnostic_log'=>@edit_log,'message'=>migration ? "IP 已更新为 #{migration['new_ip']}；请让手机重新连接 Wi-Fi 获取新租约，再检测 DNS 和出口。手动静态 IP 须同步修改。" : '操作完成；请检测对应设备。','backup'=>id})
 rescue => failure
  snap.each{|p,v|File.binwrite(p,v)}
  edit_run('uci','revert','dhcp',out:File::NULL,err:File::NULL) if migration || name_update
  restored=true
  if req['operation']!='rename'
   [['fw4','check'],['/etc/init.d/firewall','reload'],['/etc/init.d/phone-dns','restart'],['/etc/init.d/dnsmasq','reload']].each do |cmd|
    restored=false unless edit_run(*cmd,out:File::NULL,err:File::NULL)
   end
   restored=false unless edit_restart_proxy
  end
  if req['operation']=='rename' && name_update
   restored=false unless edit_run('/etc/init.d/dnsmasq','reload')
  end
  raise "#{failure.message}；原文件已恢复，运行态恢复#{restored ? '通过' : '失败，请检查路由器'}。"

 end
rescue=>e
 puts PanelTasks.json({'error'=>e.message,'diagnostic_log'=>@edit_log})
ensure
 lock.close if defined?(lock) && lock
end
