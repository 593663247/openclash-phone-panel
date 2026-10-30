require_relative 'settings'
def ip_elements(ips)
 a=ips.map{|ip|ip.split('.').map(&:to_i).inject(0){|n,v|n*256+v}}.uniq.sort
 ranges=[];a.each{|n|if ranges.last && ranges.last[1]+1==n; ranges.last[1]=n;else;ranges<<[n,n];end}
 fmt=->(n){[24,16,8,0].map{|b|(n>>b)&255}.join('.')}
 ranges.map{|x,y|x==y ? fmt.call(x) : fmt.call(x)+'-'+fmt.call(y)}.join(', ')
end
require 'yaml'
base='/etc/phone-dns'
lock=File.open('/var/lock/phone-dns-align.lock','w',0600)
lock.flock(File::LOCK_EX)
f=ARGV.fetch(0);cfg=YAML.load_file(f,aliases:true)
snap_paths=(Dir.glob(base+'/*.yaml')+Dir.glob(base+'/group-*.conf')+[base+'/devices.yaml',base+'/import-status.yaml',base+'/listeners.yaml',base+'/config.json','/etc/config/dhcp','/etc/nftables.d/90-phone-fixed-egress.nft']).uniq
snapshots=snap_paths.to_h{|p|[p,File.exist?(p) ? File.binread(p) : nil]}
begin
require base+'/auto-import.rb'
mapping=PhoneImport.run(cfg,YAML.load_file(base+'/mapping.yaml'))
ips=mapping.flat_map{|g|g['ips']}.uniq.sort_by{|ip|ip.split('.').map(&:to_i)}
nodes=(cfg['proxies']||[]).map{|n|n['name']}
assign={}
ips.each do |ip|
 rules=(cfg['rules']||[]).select{|r|r.start_with?('SRC-IP-CIDR,') && r.split(',')[1]==ip+'/32'}
 raise "#{ip} 缺少或存在重复来源规则，拒绝自动修改" unless rules.size==1
 node=rules.first.split(',')[2]
 raise "#{ip} 不是可直接绑定的手机节点" unless PhoneSettings.phone?(node) && nodes.include?(node)
 assign[ip]=node
end
(cfg['proxies']||[]).map{|n|n['name']}.select{|name|PhoneSettings.phone?(name)}.uniq.each do |name|
 next if mapping.any?{|g|g['node']==name}
 id=mapping.map{|g|g['id']}.max.to_i+1;raise '分组超过100' if id>PhoneSettings.port('max_groups')
 mapping<<{'id'=>id,'node'=>name,'ips'=>[],'dns_port'=>PhoneSettings.port('dns_base')+id,'socks_port'=>PhoneSettings.port('socks_base')+id}
end
mapping.each{|g|g.merge!(PhoneSettings.group(g['id'],g['node'],g['ips']))}
mapping.each{|g|g['ips']=ips.select{|ip|assign[ip]==g['node']}}
File.write(base+'/mapping.yaml',mapping.to_yaml)
raise 'DNS 配置生成失败' unless system('/usr/bin/ruby',base+'/render-dns.rb')
raise 'DNS 配置校验失败' unless system('/usr/bin/sing-box','check','-c',base+'/config.json')
rules=mapping.reject{|g|g['ips'].empty?}.map{|g|" iifname \"#{PhoneSettings['bridge']}\" ip saddr { #{g['ips'].join(', ')} } meta l4proto { tcp, udp } th dport 53 counter redirect to :#{g['dns_port']} comment \"Phone DNS group #{g['id']}\""}
path='/etc/nftables.d/90-phone-fixed-egress.nft'
nft=File.read(path)
raise 'DNS 防火墙链格式异常' unless nft.match?(/chain codex_phone_dns \{.*?^\}/m)
raise '固定出口保护链格式异常' unless nft.match?(/chain codex_phone_guard \{.*?^\}/m)
nft=nft.sub(/chain codex_phone_guard \{.*?^\}/m,"chain codex_phone_guard {\n type filter hook forward priority -10; policy accept;\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ip saddr @codex_phone4 counter drop comment \"Phone fixed egress: no direct forwarding\"\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ether saddr @codex_phone_mac counter drop comment \"Phone fixed egress: IPv6 and address-change guard\"\n}")
nft=nft.sub(/chain codex_phone_dns \{.*?^\}/m,"chain codex_phone_dns {\n type nat hook prerouting priority -101; policy accept;\n"+rules.join("\n")+"\n}")
hs=PhoneImport.hosts
macs=ips.flat_map{|ip|h=hs.find{|x|x['ip']==ip};raise "缺少静态租约 #{ip}" unless h;h.fetch('mac','').downcase.split}.uniq
raise 'MAC 数据异常' unless macs.all?{|m|m.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/)}
nft=nft.sub(/set codex_phone4 \{.*?^\}/m,"set codex_phone4 {\n type ipv4_addr\n flags interval\n elements = { #{ip_elements(ips)} }\n}")
nft=nft.sub(/set codex_phone_mac \{.*?^\}/m,"set codex_phone_mac {\n type ether_addr\n elements = { #{macs.join(', ')} }\n}")
File.write(path,nft)
if ARGV[1]=='live'
 text="flush set inet fw4 codex_phone4\nadd element inet fw4 codex_phone4 { #{ip_elements(ips)} }\nflush set inet fw4 codex_phone_mac\nadd element inet fw4 codex_phone_mac { #{macs.join(', ')} }\nflush chain inet fw4 codex_phone_dns\n"+rules.map{|r|'add rule inet fw4 codex_phone_dns '+r.strip}.join("\n")+"\n"
 IO.popen(['nft','-f','-'],'w'){|i|i.write(text)}
 raise 'DNS 接管规则应用失败' unless $?.success?
 raise 'DNS 服务启动失败' unless system('/etc/init.d/phone-dns','restart')
 system('/etc/init.d/dnsmasq','reload')
 system('nft','flush','flowtable','inet','fw4','ft',err:File::NULL)
end
puts "Aligned #{ips.size} devices / #{mapping.size} nodes"

rescue =>e
 snapshots.each{|p,data|data ? File.binwrite(p,data) : (File.delete(p) if File.exist?(p))}
 (Dir.glob(base+'/group-*.conf')-snap_paths).each{|p|File.delete(p)}
 system('uci','revert','dhcp')
 warn "Automatic import/alignment failed; restored saved configuration: #{e.message}"
 raise
end
