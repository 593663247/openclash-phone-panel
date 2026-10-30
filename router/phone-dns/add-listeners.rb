require 'yaml'
f=ARGV.fetch(0);p=YAML.load_file(f,aliases:true);ls=YAML.load_file('/etc/phone-dns/listeners.yaml',aliases:true)
# Phone SOCKS5 business nodes support UDP; DNS-only local listeners stay TCP-only.
(p['proxies']||[]).each{|n|n['udp']=true if n['type']=='socks5' && n['name'].to_s.start_with?('手机-')}
names=(p['proxies']||[]).map{|n|n['name']}+(p['proxy-groups']||[]).map{|n|n['name']}
raise 'DNS binding node missing' unless ls.all?{|l|names.include?(l['proxy'])}
p['listeners']=(p['listeners']||[]).reject{|l|l['name'].to_s.start_with?('phone-dns-')}+ls
if p['sniffer']
 p['sniffer']['skip-domain']=((p['sniffer']['skip-domain']||[])+['dns.google']).uniq
 ips=YAML.load_file('/etc/phone-dns/mapping.yaml').flat_map{|g|g['ips']}.map{|ip|ip+'/32'}
 p['sniffer']['skip-src-address']=((p['sniffer']['skip-src-address']||[])+ips).uniq
end
File.write(f,p.to_yaml)
