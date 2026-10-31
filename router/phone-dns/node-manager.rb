require_relative 'settings'
require_relative 'tasks'
require 'digest'
require_relative 'node-registry'
require_relative 'apply-engine'
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
  node.select{|k,_|%w[name type server port udp dialer-proxy].include?(k)}.merge('authentication'=>node.key?('password') ? '已填写（不回显）' : '无认证')
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
 def self.references(cfg,name,mapping=[])
  refs=[]
  (cfg['rules']||[]).each{|r|refs<<'分流规则' if r.to_s.split(',').include?(name)}
  (cfg['proxy-groups']||[]).each{|g|refs<<"策略组：#{g['name']}" if g.fetch('proxies',[]).include?(name)}
  (cfg['proxies']||[]).each{|n|refs<<"前置引用：#{n['name']}" if n['dialer-proxy']==name}
  (cfg['listeners']||[]).each{|l|refs<<"监听入口：#{l['name']}" if l['proxy']==name}
  mapping.each{|g|refs<<"设备：#{g['ips'].join(', ')}" if g['node']==name && !g.fetch('ips',[]).empty?}
  refs.uniq
 end
 def self.change(cfg,req,mapping=[],registry=[])
  op=req.fetch('operation','create');raise '不支持的节点操作' unless %w[create update delete].include?(op)
  cfg=Marshal.load(Marshal.dump(cfg));registry=Marshal.load(Marshal.dump(registry))
  original=req['original_name'].to_s;old=cfg.fetch('proxies',[]).find{|n|n['name']==original}
  if op!='create'
   raise '只能编辑或删除手机 SOCKS5 节点' unless old && old['type']=='socks5' && PhoneSettings.phone?(original)
   if op=='delete'
    refs=references(cfg,original,mapping);raise '节点仍被使用：'+refs.join('；') unless refs.empty?
    cfg['proxies'].reject!{|n|n['name']==original};registry.reject!{|n|n['name']==original}
    return {'config'=>cfg,'registry'=>registry,'summary'=>{'operation'=>op,'name'=>original,'references'=>refs}}
   end
   raise '修改节点暂不支持改名，避免破坏引用' unless req['name'].to_s.strip==original
   if req['password'].to_s.empty? && req['clear_auth']!=true
    req=req.merge('username'=>old.fetch('username',''),'password'=>old.fetch('password',''))
   end
   req=req.merge('username'=>'','password'=>'') if req['clear_auth']==true
   cfg['proxies'].reject!{|n|n['name']==original}
  end
  node=plan(cfg,req);node=old.reject{|k,_|%w[username password dialer-proxy].include?(k)}.merge(node) if old
  cfg['proxies']||=[];cfg['proxies']<<node
  registry.reject!{|n|n['name']==node['name']};registry<<node
  {'config'=>cfg,'registry'=>registry,'summary'=>summary(node).merge('operation'=>op)}
 end
 def self.state_fingerprint(raw)
  fingerprint(raw+"\0"+(File.file?(PhoneNodeRegistry.path) ? File.binread(PhoneNodeRegistry.path) : '')+"\0"+(File.file?('/etc/phone-dns/mapping.yaml') ? File.binread('/etc/phone-dns/mapping.yaml') : ''))
 end
 def self.apply(path,req)
  PhoneApply.transaction(path,expected_revision:req['revision'],revision:lambda{state_fingerprint(File.binread(path))}) do
   cfg=YAML.safe_load(File.binread(path),aliases:true);mapping=PanelStore.read('/etc/phone-dns/mapping.yaml',[])
   change=change(cfg,req,mapping,PhoneNodeRegistry.read)
   # A newly introduced registry must be removed by rollback if it did not exist.
   PhoneNodeRegistry.write(change['registry'])
   PhoneApply.atomic(path,change['config'].to_yaml)
   if req['operation']=='delete'
    mapping.reject!{|g|g['node']==req['original_name']&&g.fetch('ips',[]).empty?};PanelStore.write('/etc/phone-dns/mapping.yaml',mapping)
   end
   {'node'=>change['summary'],'removed_node'=>req['operation']=='delete' ? req['original_name'] : nil}
  end
 end
 def self.test(name)
  require_relative 'health'
  mapping=PanelStore.read('/etc/phone-dns/mapping.yaml',[]);group=mapping.find{|g|g['node']==name};raise '节点尚未加载为独立入口，请先应用节点配置' unless group
  sockets=PanelStore.run('netstat','-ln');runtime=YAML.safe_load(File.binread('/etc/openclash/'+File.basename(source)),aliases:true)
  bound=runtime.fetch('listeners',[]).any?{|l|l['name']=="phone-dns-#{group['id']}"&&l['proxy']==name}
  result=PhoneProbe.run(group.merge('socks_listening'=>sockets.match?(/127\.0\.0\.1:#{group['socks_port']}\s/),'dns_listening'=>sockets.match?(/127\.0\.0\.1:#{group['dns_port']}\s/),'binding_ok'=>bound))
  udp,code=PanelStore.capture('lua','/etc/phone-dns/probe-udp.lua',group['socks_port'].to_s)
  extra=code==0 ? (YAML.safe_load(udp) rescue {}) : {}
  result=result.merge('udp'=>extra,'warning'=>'有限连通性检测；并非全部应用或风控状态验收')
  result['checks']=result.fetch('checks',[]).map{|c|c['layer']=='UDP 业务' ? {'layer'=>'UDP DNS 回包实测','ok'=>extra['udp_ok'],'note'=>extra['note']} : c}
  PanelStore.with_lock(PhoneHealth.file(group['id'])+'.lock') do
   record=PhoneHealth.read(group);record['last']=result
   record['history']=record.fetch('history',[]).map{|r|r['at']==result['at'] ? result : r}
   PanelStore.write(PhoneHealth.file(group['id']),record)
  end
  result
 end
 def self.cli(mode,request=nil)
  path=source;raw=File.binread(path);cfg=YAML.safe_load(raw,aliases:true)
  return {'ok'=>true,'prefix'=>PhoneSettings['node_prefix'],'nodes'=>(cfg['proxies']||[]).map{|n|summary(n).merge('editable'=>n['type']=='socks5'&&PhoneSettings.phone?(n['name']),'managed'=>PhoneNodeRegistry.read.any?{|m|m['name']==n['name']},'references'=>references(cfg,n['name'],PanelStore.read('/etc/phone-dns/mapping.yaml',[])))}} if mode=='catalog'
  req=YAML.safe_load(File.read(request),aliases:false)
  if mode=='preview'
   change=change(cfg,req,PanelStore.read('/etc/phone-dns/mapping.yaml',[]),PhoneNodeRegistry.read)
   {'ok'=>true,'revision'=>state_fingerprint(raw),'summary'=>change['summary'],'warning'=>'确认后将备份并重载 OpenClash，代理可能短暂中断；不会自动绑定设备。UDP 开启不代表服务端已实测支持。'}
  elsif mode=='test';{'ok'=>true,'message'=>'TCP、DNS、出口及 UDP 检测已完成，请查看各项结果','result'=>test(req.fetch('name'))}
  elsif mode=='apply';apply(path,req)
  else;raise '不支持的操作';end
 end
end
if __FILE__==$PROGRAM_NAME
 begin;puts PanelTasks.json(PhoneNodes.cli(ARGV.fetch(0),ARGV[1]));rescue=>e;puts PanelTasks.json({'error'=>e.message});end
end
