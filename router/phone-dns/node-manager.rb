require_relative 'settings'
require_relative 'tasks'
require 'digest'
module PhoneNodes
 def self.plan(cfg,req)
  raise '请求格式无效' unless req.is_a?(Hash)
  name=req['name'].to_s.strip;server=req['server'].to_s.strip;port=req['port'].to_s
  raise '节点名称须使用手机节点前缀，且不能包含逗号或控制字符' unless PhoneSettings.phone?(name) && name.length<=80 && !name.match?(/[,\x00-\x1f\x7f]/)
  names=(cfg['proxies']||[]).map{|n|n['name']}
  reserved=names+(cfg['proxy-groups']||[]).map{|g|g['name']}+%w[DIRECT REJECT GLOBAL PASS COMPATIBLE]
  raise '节点名称已存在或为保留名称' if reserved.include?(name)
  raise '服务器须为有效 IP 或域名，不含协议、路径或端口' unless server.length.between?(1,253) && (server.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/) || server.match?(/\A[0-9a-fA-F:]+\z/) && server.include?(':'))
  if server.match?(/\A[0-9.]+\z/)
   PhoneSettings.ipnum(server)
  elsif server.include?(':')
   chunks=server.split('::',-1);groups=chunks.flat_map{|c|c.empty? ? [] : c.split(':',-1)}
   valid=chunks.size<=2 && groups.all?{|g|g.match?(/\A[0-9a-fA-F]{1,4}\z/)} && (chunks.size==1 ? groups.size==8 : groups.size<8)
   raise 'IPv6 地址无效' unless valid
  else
   raise '服务器域名格式无效' unless server.split('.').all?{|l|l.length.between?(1,63) && l.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/)}
  end
  raise '端口须为 1～65535' unless port.match?(/\A[1-9][0-9]{0,4}\z/) && port.to_i<=65535
  user=req.fetch('username','');pass=req.fetch('password','')
  raise '账号密码格式无效' unless [user,pass].all?{|s|s.is_a?(String)&&s.bytesize<=255&&!s.match?(/[\x00-\x1f\x7f]/)}
  raise '账号和密码应同时填写，或同时留空' unless user.empty? == pass.empty?
  raise 'UDP 开关无效' unless [true,false].include?(req['udp'])
  front=req.fetch('dialer_proxy','').to_s
  raise '前置代理不存在，只能选择现有具体节点' unless front.empty? || names.include?(front)
  raise '节点数量超过分组上限' if names.count{|n|PhoneSettings.phone?(n)}>=PhoneSettings.port('max_groups')
  node={'name'=>name,'type'=>'socks5','server'=>server,'port'=>port.to_i,'udp'=>req['udp']}
  node.merge!('username'=>user,'password'=>pass) unless user.empty?
  node['dialer-proxy']=front unless front.empty?
  node
 end
 def self.fingerprint(text);Digest::SHA256.hexdigest(text.b+"\0"+PhoneSettings.values.to_yaml.b);end
 def self.summary(node)
  node.reject{|k,_|%w[username password].include?(k)}.merge('authentication'=>node.key?('password') ? '已填写（不回显）' : '无认证')
 end
 def self.source
  path=IO.popen(['uci','-q','get','openclash.config.config_path'],&:read).strip
  raise 'OpenClash 源配置路径无效' unless path.start_with?('/etc/openclash/config/') && path.end_with?('.yaml') && !path.include?('..') && File.realpath(path).start_with?('/etc/openclash/config/')
  path
 end
 def self.command(args,log)
  output=IO.popen(args+[{err:[:child,:out]}],&:read);status=$?.exitstatus
  File.open(log,File::WRONLY|File::CREAT|File::APPEND,0600){|f|f.puts("#{args.first} exit=#{status}");f.write(output);f.puts}
  raise "#{args.first} 执行失败（exit=#{status}），详细日志仅保存在路由器" unless status==0
  output
 end
 def self.restart(log)
  command(['/etc/init.d/openclash','stop'],log)
  if File.exist?('/tmp/openclash.change')
   File.open(log+'.quickstart','wb',0600){|f|f.write(File.binread('/tmp/openclash.change'))};File.delete('/tmp/openclash.change')
  end
  command(['/etc/init.d/openclash','start'],log)
 end
 def self.apply(path,req)
  lock=File.open('/var/lock/phone-panel.lock','w',0600)
  raise '另一个配置操作正在运行' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
  text=File.binread(path);raise '配置已变化，请重新预览' unless req['revision']==fingerprint(text)
  %w[phone_panel dhcp openclash].each{|section|raise "请先保存或撤销 #{section} 的未提交设置" unless IO.popen(['uci','changes',section],&:read).strip.empty?}
  cfg=YAML.safe_load(text,aliases:true);node=plan(cfg,req)
  root='/root/phone-panel-node-changes';Dir.mkdir(root,0700) unless Dir.exist?(root)
  dir=root+'/'+Time.now.strftime('%Y%m%d%H%M%S%9N')+'-'+Process.pid.to_s;Dir.mkdir(dir,0700);log=dir+'/commands.log'
  files=([path,'/etc/openclash/'+File.basename(path),'/etc/config/dhcp','/etc/nftables.d/90-phone-fixed-egress.nft']+Dir.glob('/etc/phone-dns/*.yaml')+Dir.glob('/etc/phone-dns/group-*.conf')+['/etc/phone-dns/config.json']).uniq
  snap=files.to_h{|f|[f,File.file?(f) ? File.binread(f) : nil]}
  File.open(dir+'/snapshot.yaml','w',0600){|f|f.write(snap.to_yaml)}
  begin
   cfg['proxies']||=[];cfg['proxies']<<node
   tmp=path+'.phone-node-tmp';File.open(tmp,'w',0600){|f|f.write(cfg.to_yaml)};File.rename(tmp,path)
   command(['/etc/openclash/clash','-t','-d','/etc/openclash','-f',path],log)
   restart(log)
   runtime=YAML.safe_load(File.binread('/etc/openclash/'+File.basename(path)),aliases:true)
   actual=runtime.fetch('proxies',[]).find{|p|p['name']==node['name']}
   raise '运行配置未加载新节点' unless actual && node.all?{|k,v|actual[k]==v}
   raise '代理核心未运行' if IO.popen(['pidof','clash'],&:read).strip.empty?
   command(['fw4','check'],log)
   {'ok'=>true,'message'=>'节点已写入源配置并加载；可在设备绑定列表选择。尚未验证实际出口或 UDP，请绑定后检测。','node'=>summary(node),'backup'=>dir}
  rescue => failure
   snap.each{|f,v|v ? File.binwrite(f,v) : (File.delete(f) if File.file?(f))}
   (Dir.glob('/etc/phone-dns/group-*.conf')-files).each{|f|File.delete(f)}
   recovered=true
   begin
    restart(log);command(['/etc/init.d/firewall','reload'],log);command(['/etc/init.d/phone-dns','restart'],log);command(['/etc/init.d/dnsmasq','reload'],log)
   rescue;recovered=false;end
   {'error'=>failure.message,'rolled_back'=>recovered,'backup'=>dir,'diagnostic_log'=>log}
  ensure
   File.delete(tmp) if tmp && File.file?(tmp)
  end
 ensure
  lock.close if lock
 end
 def self.cli(mode,request=nil)
  path=source;raw=File.binread(path);cfg=YAML.safe_load(raw,aliases:true)
  return {'ok'=>true,'prefix'=>PhoneSettings['node_prefix'],'nodes'=>(cfg['proxies']||[]).map{|n|{'name'=>n['name'],'type'=>n['type']}}} if mode=='catalog'
  req=YAML.safe_load(File.read(request),aliases:false)
  if mode=='preview'
   node=plan(cfg,req)
   {'ok'=>true,'revision'=>fingerprint(raw),'summary'=>summary(node),'warning'=>'确认后将备份并重载 OpenClash，代理可能短暂中断；不会自动绑定设备。UDP 开启不代表服务端已实测支持。'}
  elsif mode=='apply';apply(path,req)
  else;raise '不支持的操作';end
 end
end
if __FILE__==$PROGRAM_NAME
 begin;puts PanelTasks.json(PhoneNodes.cli(ARGV.fetch(0),ARGV[1]));rescue=>e;puts PanelTasks.json({'error'=>e.message});end
end
