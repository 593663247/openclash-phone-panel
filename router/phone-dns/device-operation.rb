require_relative 'device-edit'
require_relative 'tasks'
require 'yaml'
base='/etc/phone-dns'
begin
 mode=ARGV.shift;req=YAML.safe_load(File.read(ARGV.fetch(0)));raise 'Invalid request' unless req.is_a?(Hash)
 f=IO.popen(['uci','-q','get','openclash.config.config_path'],&:read).strip
 raise 'Invalid config path' unless f.start_with?('/etc/openclash/config/') && f.end_with?('.yaml') && !f.include?('..')
 raise 'Save or discard pending panel settings first' unless IO.popen(['uci','changes','phone_panel'],&:read).strip.empty?
 seed=PhoneSettings.values.to_yaml+"\0"+(File.exist?('/etc/config/phone_panel') ? File.read('/etc/config/phone_panel') : '')+"\0"
 files=[f,base+'/mapping.yaml',base+'/devices.yaml'];snap=files.to_h{|p|[p,File.exist?(p) ? File.binread(p) : "--- []\n"]}
 digest=IO.popen(['sha256sum'],'r+'){|i|i.write(seed+snap.values.join("\0"));i.close_write;i.read.split.first}
 result=DeviceEdit.transform(YAML.load_file(f,aliases:true),YAML.load_file(files[1]),YAML.safe_load(snap[files[2]])||[],req)
 if mode=='preview'
  puts PanelTasks.json({'ok'=>true,'revision'=>digest,'summary'=>req,'warning'=>'改绑/删除会重启代理；删除解除此设备的面板防直连保护，保留DHCP租约。'});exit
 end
 raise 'Unsupported mode' unless mode=='apply'
 lock=File.open('/var/lock/phone-panel.lock','w',0600);raise 'Other task running' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
 # Recheck after acquiring the lock, not just before preview.
 live=files.map{|p|File.exist?(p) ? File.binread(p) : "--- []\n"}
 now=IO.popen(['sha256sum'],'r+'){|i|i.write(seed+live.join("\0"));i.close_write;i.read.split.first}
 raise 'Configuration changed; preview again' unless req['revision']==now && now==digest
 dir='/root/phone-panel-device-edits';Dir.mkdir(dir,0700) unless Dir.exist?(dir)
 id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+Process.pid.to_s
 extras=Dir.glob(base+'/*.yaml')+Dir.glob(base+'/group-*.conf')+[base+'/config.json','/etc/config/dhcp','/etc/nftables.d/90-phone-fixed-egress.nft']
  extras.each{|p|snap[p]=File.binread(p) if File.file?(p)}
  File.open(dir+'/'+id+'.yaml','w',0600){|o|o.write(snap.to_yaml)}
 begin
  files.zip([result['config'],result['mapping'],result['devices']]).each{|p,v|File.open(p,'w',0600){|o|o.write(v.to_yaml)}}
  if req['operation']!='rename'
   raise 'Source validation failed' unless system('/etc/openclash/clash','-t','-d','/etc/openclash','-f',f,out:File::NULL,err:File::NULL)
   raise 'Alignment failed' unless system('/usr/bin/ruby',base+'/align-dns.rb',f,out:File::NULL,err:File::NULL)
   raise 'Firewall validation failed' unless system('fw4','check',out:File::NULL,err:File::NULL)
   raise 'Firewall reload failed' unless system('/etc/init.d/firewall','reload',out:File::NULL,err:File::NULL)
   raise 'Proxy restart failed' unless system('/etc/init.d/openclash','restart',out:File::NULL,err:File::NULL)
  end
  puts PanelTasks.json({'ok'=>true,'message'=>'操作完成；请检测对应设备。','backup'=>id})
 rescue
  snap.each{|p,v|File.binwrite(p,v)}
  raise 'Operation failed; primary files restored. Inspect runtime before retrying.'
 end
rescue=>e
 puts PanelTasks.json({'error'=>e.message})
ensure
 lock.close if defined?(lock) && lock
end
