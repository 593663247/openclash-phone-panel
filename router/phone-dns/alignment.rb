require_relative 'apply-engine'
require_relative 'auto-import'

module PhoneAlignment
 def self.command(*args);PhoneApply.command(*args);end
 def self.ip_elements(ips)
  numbers=ips.map{|ip|PhoneSettings.ipnum(ip)}.uniq.sort;ranges=[]
  numbers.each{|n|if ranges.last&&ranges.last[1]+1==n;ranges.last[1]=n;else;ranges<<[n,n];end}
  format=lambda{|n|[24,16,8,0].map{|bits|(n>>bits)&255}.join('.')}
  ranges.map{|a,b|a==b ? format.call(a) : format.call(a)+'-'+format.call(b)}.join(', ')
 end
 def self.valid_target?(source,file,live:false)
  runtime=PanelStore.path('/etc/openclash/'+File.basename(source))
  temporary=PanelStore.path('/tmp/'+File.basename(source))
  return false unless [source,runtime].include?(file)||(!live&&file==temporary)
  return false unless File.file?(file)&&!File.symlink?(file)&&File.realpath(file)==File.expand_path(file)
  if file==temporary
   stat=File.stat(file)
   return false unless stat.uid==Process.euid
   return false if !RUBY_PLATFORM.match?(/mswin|mingw/)&&(stat.mode&0022)!=0
  end
  true
 rescue SystemCallError;false
 end
 def self.run(file,live:false)
  base=PanelStore.path('/etc/phone-dns');PanelStore.mkdir(PanelStore.path('/var/lock'))
  unless PhoneBindings.parent_apply?
   global=File.open(PanelStore.path('/var/lock/phone-panel.lock'),'a',0600)
   raise '另一个配置任务正在应用，外部合并已阻止；请稍后重试' unless global.flock(File::LOCK_EX|File::LOCK_NB)
  end
  lock=File.open(PanelStore.path('/var/lock/phone-dns-align.lock'),'a',0600);lock.flock(File::LOCK_EX)
  source=PhoneApply.source
  raise '配置合并路径不属于当前源配置、运行配置或受信任的生成临时文件' unless valid_target?(source,file,live:live)
  document=PhoneBindings.read
  # Install protection before parsing potentially broken subscription YAML.
  PhoneBindings.guard(document) if document
  originals=[source,file].uniq.select{|p|File.file?(p)}.to_h{|p|[p,File.binread(p)]}
  raise '待合并配置不存在' unless originals[file]
  configs=originals.to_h{|p,raw|[p,PhoneBindings.compose(YAML.safe_load(raw,aliases:true),document)]}
  cfg=configs.fetch(file)
  mapping=PanelStore.read(base+'/mapping.yaml',[])
  if document
   PhoneBindings.check_hosts(document,PhoneBindings.hosts)
   PhoneBindings.check_network(document,*PhoneBindings.network_state)
   mapping=PhoneBindings.mapping(document,mapping)
  end
  files=(PhoneApply.config_files(source)+[file]).uniq
  # OpenClash owns its temporary generation file; durable recovery must never recreate it.
  ephemeral=file==PanelStore.path('/tmp/'+File.basename(source))
  backup,snapshots=PhoneApply.snapshot(ephemeral ? files-[file] : files)
  snapshots[file]=File.binread(file) if ephemeral
  written_sources={}
  boot=(File.read('/proc/sys/kernel/random/boot_id').strip rescue 'test')
  PhoneBindings.status('generating',{'pid'=>Process.pid,'boot'=>boot,'backup'=>backup,'message'=>'正在合并节点和设备绑定'})
  begin
   if document
    PanelStore.write(base+'/devices.yaml',PhoneBindings.devices(document,mapping))
    PanelStore.write(base+'/import-status.yaml',{'time'=>Time.now.to_s,'pending'=>[],'source'=>'independent-bindings'})
   else
    mapping=PhoneImport.run(cfg,mapping)
   end
   ips=mapping.flat_map{|g|g.fetch('ips',[])}
   raise '设备出现在多个分组中' unless ips.uniq.size==ips.size
   nodes=(cfg['proxies']||[]).map{|n|n['name']}
   mapping.reject!{|g|g.fetch('ips',[]).empty?&&!nodes.include?(g['node'])}
   assigned={}
   ips.each do |ip|
    rules=cfg.fetch('rules',[]).select{|r|r.to_s.start_with?("SRC-IP-CIDR,#{ip}/32,")}
    raise "#{ip} 缺少或存在重复来源规则，已停止应用" unless rules.size==1
    node=rules.first.split(',')[2]
    raise "#{ip} 不是可直接绑定的手机节点" unless PhoneSettings.phone?(node)&&nodes.count(node)==1
    assigned[ip]=node
   end
   nodes.select{|name|PhoneSettings.phone?(name)}.uniq.each do |name|
    next if mapping.any?{|g|g['node']==name}
    id=PhoneSettings.next_group_id(mapping)
    mapping<<PhoneSettings.group(id,name)
   end
   raise '分组标识重复或超过上限' if mapping.size>PhoneSettings.port('max_groups')||mapping.map{|g|g['id']}.uniq.size!=mapping.size
   mapping.each{|g|g.merge!(PhoneSettings.group(g['id'],g['node'],ips.select{|ip|assigned[ip]==g['node']}))}
   # Abort before overwriting a subscription edited while planning.
   originals.each{|p,bytes|raise '配置在合并期间变化，请重新应用' unless File.file?(p)&&File.binread(p)==bytes}
   configs.each do |p,config|
    bytes=config.to_yaml;next if bytes.b==originals[p]
    PhoneApply.atomic(p,bytes);written_sources[p]=bytes.b
   end
   keep=mapping.map{|g|base+"/group-#{g['id']}.conf"}
   (Dir.glob(base+'/group-*.conf')-keep).each{|p|File.delete(p)}
   PanelStore.write(base+'/mapping.yaml',mapping)
   command('/usr/bin/ruby','/etc/phone-dns/render-dns.rb')
   command('sing-box','check','-c','/etc/phone-dns/config.json')
   rules=mapping.reject{|g|g['ips'].empty?}.map{|g|" iifname \"#{PhoneSettings['bridge']}\" ip saddr { #{g['ips'].join(', ')} } meta l4proto { tcp, udp } th dport 53 counter redirect to :#{g['dns_port']} comment \"Phone DNS group #{g['id']}\""}
   nft_file=PanelStore.path('/etc/nftables.d/90-phone-fixed-egress.nft');nft=File.binread(nft_file).force_encoding('UTF-8')
   raise 'DNS 或防直连防火墙链格式异常' unless %w[codex_phone_dns codex_phone_guard].all?{|name|nft.match?(/chain #{name} \{.*?^\}/m)}
   nft=nft.sub(/chain codex_phone_guard \{.*?^\}/m,"chain codex_phone_guard {\n type filter hook forward priority -10; policy accept;\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ip saddr @codex_phone4 counter drop comment \"Phone fixed egress: no direct forwarding\"\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ether saddr @codex_phone_mac counter drop comment \"Phone fixed egress: IPv6 and address-change guard\"\n}")
   nft=nft.sub(/chain codex_phone_dns \{.*?^\}/m,"chain codex_phone_dns {\n type nat hook prerouting priority -101; policy accept;\n"+rules.join("\n")+"\n}")
   hosts=document ? PhoneBindings.hosts : PhoneImport.hosts
   macs=ips.flat_map{|ip|h=hosts.find{|row|row['ip']==ip};raise "缺少静态租约 #{ip}" unless h;h.fetch('mac','').downcase.split}.uniq
   macs.each{|m|PhoneBindings.mac(m)}
   nft=nft.sub(/set codex_phone4 \{.*?^\}/m,"set codex_phone4 {\n type ipv4_addr\n flags interval\n auto-merge\n elements = { #{ip_elements(ips)} }\n}")
   nft=nft.sub(/set codex_phone_mac \{.*?^\}/m,"set codex_phone_mac {\n type ether_addr\n elements = { #{macs.join(', ')} }\n}")
   nft=nft.gsub(/^ elements = \{  \}\n/,'') if ips.empty?
   PhoneApply.atomic(nft_file,nft);command('fw4','check')
   PhoneBindings.status('generated',{'backup'=>backup,'message'=>'文件已合并并通过语法检查；等待运行态验收'})
   if live
    text="flush set inet fw4 codex_phone4\nflush set inet fw4 codex_phone_mac\nflush chain inet fw4 codex_phone_dns\n"
    text+="add element inet fw4 codex_phone4 { #{ip_elements(ips)} }\n" unless ips.empty?
    text+="add element inet fw4 codex_phone_mac { #{macs.join(', ')} }\n" unless macs.empty?
    text+=rules.map{|r|'add rule inet fw4 codex_phone_dns '+r.strip}.join("\n")+"\n"
    IO.popen(['nft','-f','-'],'w'){|io|io.write(text)};raise 'DNS 接管规则应用失败' unless $?.success?
    command('/etc/init.d/phone-dns','restart');command('/etc/init.d/dnsmasq','reload')
    command('nft','flush','flowtable','inet','fw4','ft') if PanelStore.capture('nft','list','flowtable','inet','fw4','ft')[1]==0
    PhoneApply.wait_ready;PhoneApply.verify(source);PhoneApply.checkpoint(source) if document
   end
   {'ok'=>true,'count'=>ips.size}
  rescue=>failure
   restore=snapshots.reject{|p,_|originals.key?(p)&&!written_sources.key?(p)}
   # A concurrent external edit is never overwritten during alignment rollback.
   written_sources.each{|p,bytes|restore.delete(p) if !File.file?(p)||File.binread(p)!=bytes}
   errors=PhoneApply.restore_files(restore,files)
   PanelStore.capture('uci','revert','dhcp')
   PhoneBindings.status('blocked',{'message'=>failure.message,'backup'=>backup,'files_restored'=>errors.empty?,'restore_errors'=>errors,'runtime_verified'=>false})
   raise
  end
 rescue=>failure
  PhoneBindings.status('blocked',{'message'=>failure.message,'runtime_verified'=>false}) unless defined?(backup)&&backup
  raise
 ensure
  lock.close if lock
  global.close if global
 end
end
