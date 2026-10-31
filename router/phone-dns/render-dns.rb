require_relative 'settings'
require_relative 'panel-store'
require 'yaml'
def json(x)
 case x
 when Hash;'{'+x.map{|k,v|json(k.to_s)+':'+json(v)}.join(',')+'}'
 when Array;'['+x.map{|v|json(v)}.join(',')+']'
 when String;'"'+x.gsub(/["\\\x00-\x1f]/){|c|c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
 when TrueClass;'true';when FalseClass;'false';when NilClass;'null';else;x.to_s;end
end

mapping=YAML.load_file(PanelStore.path('/etc/phone-dns/mapping.yaml'))
cfg={'log'=>{'level'=>'warn'},'dns'=>{'servers'=>[],'rules'=>[],'independent_cache'=>true,'strategy'=>'ipv4_only'},'inbounds'=>[],'outbounds'=>[],'route'=>{'rules'=>[{'action'=>'hijack-dns'}]}}
listeners=[]
mapping.each do |g|
 id=g['id'];proxyport=g['socks_port']
 listeners<<{'name'=>"phone-dns-#{id}",'type'=>'socks','listen'=>'127.0.0.1','port'=>proxyport,'udp'=>true,'users'=>[],'proxy'=>g['node']}
 cfg['outbounds']<<{'type'=>'socks','tag'=>"node-#{id}",'server'=>'127.0.0.1','server_port'=>proxyport,'version'=>'5'}
 [1,2].each do |n|
  tag="g#{id}-#{n}";port=PhoneSettings.port('internal_base')+id*10+n
  cfg['inbounds']<<{'type'=>'direct','tag'=>tag,'listen'=>'127.0.0.1','listen_port'=>port}
  cfg['dns']['servers']<<{'type'=>'https','tag'=>tag,'server'=>n==1 ? PhoneSettings['upstream_primary'] : PhoneSettings['upstream_secondary'],'server_port'=>443,'path'=>'/dns-query','tls'=>{'enabled'=>true,'server_name'=>PhoneSettings['tls_name']},'detour'=>"node-#{id}"}
  cfg['dns']['rules']<<{'inbound'=>[tag],'action'=>'route','server'=>tag}
 end
 PanelStore.atomic(PanelStore.path("/etc/phone-dns/group-#{id}.conf"), "port=#{g['dns_port']}\nlisten-address=127.0.0.1,#{PhoneSettings['router_ip']}\nbind-interfaces\nno-resolv\nno-hosts\ncache-size=512\nstrict-order\nserver=127.0.0.1##{PhoneSettings.port('internal_base')+id*10+1}\nserver=127.0.0.1##{PhoneSettings.port('internal_base')+id*10+2}\nuser=root\n")
end
if mapping.empty?
 cfg.delete('dns');cfg['route']={'rules'=>[]}
else
 cfg['dns']['final']="g#{mapping.first['id']}-1"
end
PanelStore.atomic(PanelStore.path('/etc/phone-dns/config.json'),json(cfg))
PanelStore.atomic(PanelStore.path('/etc/phone-dns/listeners.yaml'),listeners.to_yaml)
