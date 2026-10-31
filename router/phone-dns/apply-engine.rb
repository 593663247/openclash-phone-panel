require_relative 'panel-store'
require_relative 'node-registry'
require_relative 'binding-registry'
module PhoneApply
 def self.path(p);PanelStore.path(p);end
 def self.source(allow_missing:false)
  path=PanelStore.run('uci','-q','get','openclash.config.config_path').strip
  raise '源配置路径无效' unless path.start_with?('/etc/openclash/config/') && path.end_with?('.yaml') && !path.include?('..') && !File.symlink?(path) && (allow_missing ? File.realpath(File.dirname(path))=='/etc/openclash/config' : File.realpath(path).start_with?('/etc/openclash/config/'))
  path
 end
 def self.atomic(file,data)
  PanelStore.atomic(file,data)
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
  PhoneBindings.guard
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
  document=PhoneBindings.read
  if document
   PhoneBindings.assert_mapping(document,mapping)
   PhoneBindings.check_hosts(document,PhoneBindings.hosts)
   document['devices'].each{|d|raise "#{d['ip']} 持久化绑定未加载" unless [source,runtime].all?{|c|c.fetch('rules',[]).include?(PhoneBindings.rule(d))}}
   guard_state=command('nft','list','chain','inet','phone_panel_persistent','guard')
   raise '独立持久化防直连保护未通过验收' unless document['devices'].all?{|d|guard_state.include?(d['mac'])&&guard_state.include?(d['ip'])} && (document['devices'].empty? || guard_state.include?('drop'))
  end
  checks={'core'=>true,'bindings'=>true,'dns_listeners'=>true,'guard'=>true,'persistent_bindings'=>!document.nil?,'business'=>'未验证手机实际业务及完整 UDP'}
  checks
 end
 def self.config_files(source)
  ([source,'/etc/openclash/'+File.basename(source),'/etc/config/dhcp','/etc/config/phone_panel','/etc/config/openclash','/etc/nftables.d/90-phone-fixed-egress.nft','/etc/phone-dns/config.json','/etc/phone-dns/managed-nodes.yaml','/etc/phone-dns/managed-bindings.yaml','/etc/phone-dns/persistent-guard.yaml','/etc/phone-dns/mapping.yaml','/etc/phone-dns/devices.yaml','/etc/phone-dns/listeners.yaml','/etc/phone-dns/import-status.yaml']+Dir.glob(self.path('/etc/phone-dns/*.yaml'))+Dir.glob(self.path('/etc/phone-dns/group-*.conf'))).uniq.map{|f|ENV['PHONE_PANEL_TEST_ROOT'] && f.start_with?(ENV['PHONE_PANEL_TEST_ROOT']) ? f : self.path(f)}
 end
 def self.snapshot(files)
  root=self.path('/root/phone-panel-transactions');PanelStore.mkdir(root)
  dir=root+'/'+Time.now.strftime('%Y%m%d%H%M%S%9N')+'-'+Process.pid.to_s;PanelStore.mkdir(dir)
  snapshots=files.to_h{|p|[p,File.file?(p) ? File.binread(p) : nil]}
  manifest=snapshots.to_h{|p,v|[ENV['PHONE_PANEL_TEST_ROOT'] ? p.delete_prefix(ENV['PHONE_PANEL_TEST_ROOT']) : p,v && [v].pack('m0')]}
  PanelStore.write(dir+'/manifest.json',manifest)
  PanelStore.atomic(dir+'/manifest.sha256',Digest::SHA256.file(dir+'/manifest.json').hexdigest+"\n")
  [dir,snapshots]
 end
 def self.checkpoint(source)
  files=config_files(source);fingerprint=Digest::SHA256.hexdigest(files.sort.map{|p|p.b+"\0".b+(File.file?(p) ? File.binread(p) : ''.b)}.join("\0".b))
  old=PanelStore.read(PanelStore.state+'/bindings-last-good.yaml',{})
  old_manifest=self.path(old.fetch('backup',''))+'/manifest.json'
  if old['fingerprint']==fingerprint && File.file?(old_manifest) && old['manifest_sha256']==Digest::SHA256.file(old_manifest).hexdigest
   backup=old['backup']
  else
   backup,_=snapshot(files)
   backup=backup.sub(ENV['PHONE_PANEL_TEST_ROOT'].to_s,'') if ENV['PHONE_PANEL_TEST_ROOT']
   PanelStore.write(PanelStore.state+'/bindings-last-good.yaml',{'backup'=>backup,'fingerprint'=>fingerprint,'manifest_sha256'=>Digest::SHA256.file(self.path(backup)+'/manifest.json').hexdigest,'source'=>source,'at'=>Time.now.to_i})
  end
  PhoneBindings.status('verified',{'message'=>'配置与运行态验收通过；手机租约及实际业务另行验证','backup'=>backup})
 end
 def self.allowed_restore?(file)
  return false unless file.is_a?(String) && !file.include?('..') && !file.include?("\0")
  return true if %w[/etc/config/dhcp /etc/config/phone_panel /etc/config/openclash /etc/nftables.d/90-phone-fixed-egress.nft /etc/phone-dns/config.json].include?(file)
  return true if file.match?(%r{\A/etc/phone-dns/[a-z0-9-]+\.(yaml|conf)\z})
  %w[/etc/openclash/config/ /etc/openclash/].any?{|prefix|file.start_with?(prefix) && File.basename(file)==file.delete_prefix(prefix) && file.end_with?('.yaml')}
 end
 def self.restore(backup)
  raise '恢复路径无效' unless backup.is_a?(String)&&backup.match?(%r{\A/root/phone-panel-transactions/\d{23}-\d+\z})
  directory=self.path(backup);raise '恢复目录不安全' if File.symlink?(directory)||File.realpath(directory)!=File.expand_path(directory)
  raise '备份清单体积异常' if File.size(directory+'/manifest.json')>128*1024*1024
  raise '备份清单路径不安全' if File.symlink?(directory+'/manifest.json')||File.symlink?(directory+'/manifest.sha256')
  if File.file?(directory+'/manifest.sha256')
   expected=File.read(directory+'/manifest.sha256').strip
   raise '备份完整性校验失败，未修改当前配置' unless expected.match?(/\A[a-f0-9]{64}\z/)&&Digest::SHA256.file(directory+'/manifest.json').hexdigest==expected
  end
  manifest=PanelStore.read(directory+'/manifest.json',{})
  raise '独立绑定快照缺少完整性校验文件' if manifest['/etc/phone-dns/managed-bindings.yaml']&&!File.file?(directory+'/manifest.sha256')
  raise '备份包含不允许的目标路径' if manifest.empty?||manifest.size>512||!manifest.keys.all?{|p|allowed_restore?(p)}
  if File.exist?(PhoneBindings.path)
   raise '旧备份不包含独立绑定库，不能覆盖已迁移设备；请选择迁移后的完整快照' unless manifest['/etc/phone-dns/managed-bindings.yaml']
  end
  decoded=manifest.to_h do |file,data|
   raise '备份内容格式无效' unless data.nil?||data.is_a?(String)
   [self.path(file),data && data.unpack1('m0')]
  end
  raise '备份内容超过恢复容量限制' if decoded.values.compact.sum(&:bytesize)>96*1024*1024
  begin
   source=self.source(allow_missing:true)
  rescue
   candidates=manifest.keys.select{|p|p.start_with?('/etc/openclash/config/')&&allowed_restore?(p)}
   raise '当前配置选择无效，备份中也没有唯一源配置可恢复' unless candidates.size==1
   source=self.path(candidates.first)
  end
  transaction(source,extra_files:decoded.keys,resolve_source:lambda{self.source},recovery:true) do
   decoded.each{|file,data|data ? atomic(file,data) : (File.delete(file) if File.file?(file))}
   (Dir.glob(self.path('/etc/phone-dns/group-*.conf'))-decoded.keys).each{|file|File.delete(file)}
   %w[dhcp phone_panel openclash].each{|section|command('uci','revert',section)}
   PhoneSettings.instance_variable_set(:@values,nil)
   {'message'=>'完整配置快照已恢复并通过运行态验收；手机租约及实际业务需复测。'}
  end
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
 def self.transaction(path,expected_revision:nil,revision:nil,network:true,postcheck:nil,extra_files:[],resolve_source:nil,recovery:false)
  original_path=path
  lock=File.open(self.path('/var/lock/phone-panel.lock'),'w',0600)
  raise '另一个配置任务正在运行' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
  previous_token=ENV['PHONE_PANEL_APPLY_TOKEN'];apply_token=Random.bytes(16).unpack1('H*')
  ENV['PHONE_PANEL_APPLY_TOKEN']=apply_token
  owner_file=self.path('/var/lock/phone-panel-owner.json')
  PanelStore.write(owner_file,{'token'=>apply_token,'pid'=>Process.pid,'process_token'=>PhoneBindings.process_token(Process.pid)})
  phase('检查配置版本与未保存修改')
  %w[dhcp phone_panel openclash].each do |section|
   if recovery
    text,code=PanelStore.capture('uci','changes',section)
    raise "#{section} 有未保存修改" if code==0&&!text.strip.empty?
   else
    raise "#{section} 有未保存修改" unless PanelStore.run('uci','changes',section).strip.empty?
   end
  end
  if revision
   raise '请先预览配置后再确认应用' unless expected_revision.is_a?(String) && !expected_revision.empty?
   raise '配置已变化，请重新预览' unless revision.call==expected_revision
  elsif expected_revision
   raise '缺少配置版本检查'
  end
  files=(config_files(path)+extra_files).uniq;dir,snapshots=snapshot(files);@log=dir+'/commands.log'
  phase('备份已完成，更新配置',{'backup'=>dir})
  guard_touched=false
  begin
   result=yield
   if PhoneBindings.read;guard_touched=true;PhoneBindings.guard;end
   path=resolve_source.call if resolve_source
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
   checkpoint(path) if PhoneBindings.read
   {'ok'=>true,'message'=>'应用及运行配置验收通过；手机换址后请重连 Wi-Fi，实际业务及 UDP 另行检测。','backup'=>dir,'checks'=>checks}.merge(result || {})
  rescue => failure
   phase('应用失败，恢复文件与网络')
   errors=restore_files(snapshots,files)
   path=original_path
   file_ok=errors.empty?;runtime_ok=false;restore_error=errors.empty? ? nil : '文件恢复未完成：'+errors.join('、')
   if file_ok
    begin
     %w[dhcp phone_panel openclash].each{|section|command('uci','revert',section)};PhoneSettings.instance_variable_set(:@values,nil) if resolve_source;PhoneBindings.guard(PhoneBindings.read || {'schema'=>1,'revision'=>1,'devices'=>[],'owned_rules'=>[]}) if guard_touched;restart;verify(path);checkpoint(path) if PhoneBindings.read;runtime_ok=true
    rescue=>e;restore_error=e.message;end
   end
   {'error'=>failure.message,'files_restored'=>file_ok,'runtime_restored'=>runtime_ok,'rolled_back'=>file_ok&&runtime_ok,'recovery_required'=>!(file_ok&&runtime_ok),'rollback_error'=>restore_error,'backup'=>dir,'diagnostic_log'=>@log}
  end
 ensure
  if defined?(apply_token)&&apply_token
   previous_token ? ENV['PHONE_PANEL_APPLY_TOKEN']=previous_token : ENV.delete('PHONE_PANEL_APPLY_TOKEN')
   File.delete(owner_file) if owner_file&&File.file?(owner_file)&&PanelStore.read(owner_file,{})['token']==apply_token
  end
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
  request=YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false)
  result=PhoneApply.restore(request.fetch('backup'))
  puts PanelStore.json(result)
 rescue=>e;puts PanelStore.json({'error'=>e.message});end
end
