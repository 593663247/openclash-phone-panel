require_relative 'panel-store'
require_relative 'node-registry'
module PhoneApply
 def self.path(p);PanelStore.path(p);end
 def self.source
  path=PanelStore.run('uci','-q','get','openclash.config.config_path').strip
  raise '源配置路径无效' unless path.start_with?('/etc/openclash/config/') && path.end_with?('.yaml') && !path.include?('..') && File.realpath(path).start_with?('/etc/openclash/config/')
  path
 end
 def self.atomic(file,data)
  temporary=file+".apply-tmp-#{Process.pid}-#{rand(1<<32)}"
  File.open(temporary,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.binmode;f.write(data);f.flush;f.fsync}
  File.rename(temporary,file)
 ensure
  File.delete(temporary) if temporary && File.file?(temporary)
 end
 def self.phase(label,extra={})
  id=ENV['PHONE_PANEL_OPERATION_ID'];return unless id && id.match?(/\A\d{14}-[a-f0-9]{12}\z/)
  path=PanelStore.path('/etc/phone-dns/operations/'+id+'.json');record=PanelStore.read(path,{})
  return if record.empty?
  record.merge!(extra);record['stage']=label;record['updated_at']=Time.now.to_i;PanelStore.write(path,record)
 end
 def self.command(*args)
  output=IO.popen(args+[{err:[:child,:out]}],&:read);code=$?.exitstatus
  if @log
   File.open(@log,File::WRONLY|File::CREAT|File::APPEND,0600){|f|f.puts("#{Time.now.utc} #{args.first} exit=#{code}");f.write(output);f.puts}
  end
  raise "#{File.basename(args.first)} 执行失败（exit=#{code}，详情保存在路由器私密日志）" unless code==0
  output
 end
 def self.restart
  phase('停止核心并清除快速启动缓存');command('/etc/init.d/openclash','stop')
  if File.file?(path('/tmp/openclash.change'))
   File.open(@log+'.quickstart','wb',0600){|f|f.write(File.binread(path('/tmp/openclash.change')))};File.delete(path('/tmp/openclash.change'))
  end
  command('/etc/init.d/firewall','reload');command('/etc/init.d/openclash','start')
  command('/etc/init.d/phone-dns','restart');command('/etc/init.d/dnsmasq','reload')
  wait_ready
 end
 def self.wait_ready
  ports=PanelStore.read(path('/etc/phone-dns/mapping.yaml'),[]).select{|g|!g.fetch('ips',[]).empty?}.flat_map{|g|[g['dns_port'],g['socks_port']]}
  30.times do
   begin
    pid=command('pidof','clash');sockets=command('netstat','-ln')
    return if !pid.strip.empty? && ports.all?{|p|sockets.match?(/(?:127\.0\.0\.1|0\.0\.0\.0):#{p}\s/)}
   rescue;end
   sleep 1
  end
  raise '核心或受管入口在 30 秒内未就绪'
 end
 def self.verify(path)
  phase('验收核心、绑定、DNS 监听和防直连')
  raise '核心未运行' if command('pidof','clash').strip.empty?
  source=YAML.safe_load(File.binread(path),aliases:true)
  runtime=YAML.safe_load(File.binread(self.path('/etc/openclash/'+File.basename(path))),aliases:true)
  PhoneNodeRegistry.read.each do |node|
   actual=runtime.fetch('proxies',[]).find{|p|p['name']==node['name']}
   raise "托管节点 #{node['name']} 未正确加载" unless actual && node.all?{|k,v|actual[k]==v}
  end
  mapping=PanelStore.read(self.path('/etc/phone-dns/mapping.yaml'),[])
  sockets=command('netstat','-ln');dns=command('nft','list','chain','inet','fw4','codex_phone_dns')
  guard=command('nft','list','chain','inet','fw4','codex_phone_guard');raise '防直连保护缺失' unless guard.include?('drop')
  mapping.each do |g|
   next if g.fetch('ips',[]).empty?
   raise "分组 #{g['id']} DNS 或代理入口未监听" unless [g['dns_port'],g['socks_port']].all?{|p|sockets.match?(/(?:127\.0\.0\.1|0\.0\.0\.0):#{p}\s/)}
   g['ips'].each do |ip|
    rule="SRC-IP-CIDR,#{ip}/32,#{g['node']}"
    raise "#{ip} 源/运行绑定不一致" unless [source,runtime].all?{|c|c.fetch('rules',[]).include?(rule)}
    raise "#{ip} 嗅探排除未生效" unless runtime.dig('sniffer','skip-src-address').to_a.include?(ip+'/32')
    raise "#{ip} DNS 接管未生效" unless dns.include?(ip)
    command('nft','get','element','inet','fw4','codex_phone4','{',ip,'}')
   end
  end
  command('fw4','check')
  {'core'=>true,'bindings'=>true,'dns_listeners'=>true,'guard'=>true,'business'=>'未验证手机实际业务及完整 UDP'}
 end
 def self.restore_files(snapshots,files)
  errors=[]
  snapshots.each do |p,v|
   begin
    v ? atomic(p,v) : (File.delete(p) if File.file?(p))
    raise 'Snapshot mismatch' unless v ? (File.file?(p) && File.binread(p)==v) : !File.exist?(p)
   rescue=>e
    errors<<File.basename(p)+' ('+e.class.to_s+')'
   end
  end
  (Dir.glob(self.path('/etc/phone-dns/group-*.conf'))-files).each do |p|
   begin;File.delete(p);rescue=>e;errors<<File.basename(p)+' ('+e.class.to_s+')';end
  end
  errors
 end
 def self.transaction(path,expected_revision:nil,revision:nil,network:true,postcheck:nil)
  lock=File.open(self.path('/var/lock/phone-panel.lock'),'w',0600)
  raise '另一个配置任务正在运行' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
  phase('检查配置版本与未保存修改')
  %w[dhcp phone_panel openclash].each{|s|raise "#{s} 有未保存修改" unless PanelStore.run('uci','changes',s).strip.empty?}
  if revision
   raise '请先预览配置后再确认应用' unless expected_revision.is_a?(String) && !expected_revision.empty?
   raise '配置已变化，请重新预览' unless revision.call==expected_revision
  elsif expected_revision
   raise '缺少配置版本检查'
  end
  root=self.path('/root/phone-panel-transactions');PanelStore.mkdir(root)
  dir=root+'/'+Time.now.strftime('%Y%m%d%H%M%S%9N')+'-'+Process.pid.to_s;PanelStore.mkdir(dir);@log=dir+'/commands.log'
  files=([path,'/etc/openclash/'+File.basename(path),'/etc/config/dhcp','/etc/nftables.d/90-phone-fixed-egress.nft','/etc/phone-dns/config.json','/etc/phone-dns/managed-nodes.yaml']+Dir.glob(self.path('/etc/phone-dns/*.yaml'))+Dir.glob(self.path('/etc/phone-dns/group-*.conf'))).uniq
  files=files.map{|f|ENV['PHONE_PANEL_TEST_ROOT'] && f.start_with?(ENV['PHONE_PANEL_TEST_ROOT']) ? f : self.path(f)}
  snapshots=files.to_h{|p|[p,File.file?(p) ? File.binread(p) : nil]}
  # JSON text avoids binary-tagged YAML snapshots and alias-dependent recovery.
  PanelStore.write(dir+'/manifest.json',snapshots.transform_values{|v|v && [v].pack('m0')})
  phase('备份已完成，更新配置',{'backup'=>dir})
  begin
   result=yield
   if network
   phase('验证源配置与生成 DNS/防火墙')
   command('/usr/bin/ruby','/etc/phone-dns/align-dns.rb',path)
   command('/etc/openclash/clash','-t','-d','/etc/openclash','-f',path)
   command('sing-box','check','-c','/etc/phone-dns/config.json');command('fw4','check')
   restart
   else
    command('/etc/init.d/dnsmasq','reload')
   end
   checks=verify(path)
   checks.merge!(postcheck.call) if postcheck
   if result && result['removed_node']
    runtime=YAML.safe_load(File.binread(self.path('/etc/openclash/'+File.basename(path))),aliases:true)
    raise '删除节点仍存在于运行配置' if runtime.fetch('proxies',[]).any?{|n|n['name']==result['removed_node']}
   end
   {'ok'=>true,'message'=>'应用及运行配置验收通过；手机换址后请重连 Wi-Fi，实际业务及 UDP 另行检测。','backup'=>dir,'checks'=>checks}.merge(result || {})
  rescue => failure
   phase('应用失败，恢复文件与网络')
   errors=restore_files(snapshots,files)
   file_ok=errors.empty?;runtime_ok=false;restore_error=errors.empty? ? nil : '文件恢复未完成：'+errors.join('、')
   if file_ok
    begin
     command('uci','revert','dhcp');restart;verify(path);runtime_ok=true
    rescue=>e;restore_error=e.message;end
   end
   {'error'=>failure.message,'files_restored'=>file_ok,'runtime_restored'=>runtime_ok,'rolled_back'=>file_ok&&runtime_ok,'recovery_required'=>!(file_ok&&runtime_ok),'rollback_error'=>restore_error,'backup'=>dir,'diagnostic_log'=>@log}
  end
 ensure
  @log=nil;lock.close if lock
 end
end

if __FILE__==$PROGRAM_NAME
 begin
  mode=ARGV.shift
  if mode=='initialize'
   result=PhoneApply.transaction(PhoneApply.source){{}}
   puts PanelStore.json(result);exit(result['ok'] ? 0 : 1)
  end
  raise 'Unsupported operation' unless mode=='restore'
  request=YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false);backup=request.fetch('backup')
  raise '恢复路径无效' unless backup.match?(%r{\A/root/phone-panel-transactions/\d{23}-\d+\z})
  manifest=PanelStore.read(backup+'/manifest.json',{})
  source=PhoneApply.source
  allowed=lambda{|p|p==source || p=='/etc/openclash/'+File.basename(source) || %w[/etc/config/dhcp /etc/nftables.d/90-phone-fixed-egress.nft /etc/phone-dns/config.json].include?(p) || p.match?(%r{\A/etc/phone-dns/[a-z0-9-]+\.(yaml|conf)\z})}
  raise '备份包含不允许的目标路径' if manifest.empty? || !manifest.keys.all?{|p|allowed.call(p)}
  result=PhoneApply.transaction(source) do
   manifest.each{|p,data|data ? PhoneApply.atomic(p,data.unpack1('m0')) : (File.delete(p) if File.file?(p))}
   {'message'=>'指定备份已恢复并通过运行配置验收；实际业务需复测。'}
  end
  puts PanelStore.json(result)
 rescue=>e;puts PanelStore.json({'error'=>e.message});end
end
