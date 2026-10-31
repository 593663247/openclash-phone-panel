require_relative 'settings'
require_relative 'panel-store'
require 'yaml'
module PhoneListeners
 def self.apply(file)
  config=YAML.load_file(file,aliases:true)
  listeners=YAML.load_file(PanelStore.path('/etc/phone-dns/listeners.yaml'),aliases:true)
  (config['proxies']||[]).each{|node|node['udp']=true if node['type']=='socks5'&&PhoneSettings.phone?(node['name'])&&!node.key?('udp')}
  names=(config['proxies']||[]).map{|node|node['name']}+(config['proxy-groups']||[]).map{|group|group['name']}
  raise 'DNS binding node missing' unless listeners.all?{|listener|names.include?(listener['proxy'])}
  config['listeners']=(config['listeners']||[]).reject{|listener|listener['name'].to_s.start_with?('phone-dns-')}+listeners
  # Record exclusions even when sniffing was absent, without enabling it.
  config['sniffer']||={'enable'=>false}
  raise 'Sniffer configuration must be an object' unless config['sniffer'].is_a?(Hash)
  config['sniffer']['skip-domain']=((config['sniffer']['skip-domain']||[])+[PhoneSettings['tls_name']]).uniq
  ips=YAML.load_file(PanelStore.path('/etc/phone-dns/mapping.yaml')).flat_map{|group|group['ips']}.map{|ip|ip+'/32'}
  config['sniffer']['skip-src-address']=((config['sniffer']['skip-src-address']||[])+ips).uniq
  PanelStore.atomic(file,config.to_yaml)
 end
end
PhoneListeners.apply(ARGV.fetch(0)) if __FILE__==$PROGRAM_NAME
