require_relative 'settings'
require_relative 'panel-store'
require 'yaml'
f=ARGV.fetch(0);p=YAML.load_file(f,aliases:true);ls=YAML.load_file('/etc/phone-dns/listeners.yaml',aliases:true)
# Default UDP on for phone SOCKS5 nodes; preserve an explicit administrator choice.
(p['proxies']||[]).each{|n|n['udp']=true if n['type']=='socks5' && PhoneSettings.phone?(n['name']) && !n.key?('udp')}
names=(p['proxies']||[]).map{|n|n['name']}+(p['proxy-groups']||[]).map{|n|n['name']}
raise 'DNS binding node missing' unless ls.all?{|l|names.include?(l['proxy'])}
p['listeners']=(p['listeners']||[]).reject{|l|l['name'].to_s.start_with?('phone-dns-')}+ls
if p['sniffer']
 p['sniffer']['skip-domain']=((p['sniffer']['skip-domain']||[])+[PhoneSettings['tls_name']]).uniq
 ips=YAML.load_file('/etc/phone-dns/mapping.yaml').flat_map{|g|g['ips']}.map{|ip|ip+'/32'}
 p['sniffer']['skip-src-address']=((p['sniffer']['skip-src-address']||[])+ips).uniq
end
PanelStore.atomic(f,p.to_yaml)
