require 'yaml'
def json(x)
 case x
 when Hash;'{'+x.map{|k,v|json(k.to_s)+':'+json(v)}.join(',')+'}'
 when Array;'['+x.map{|v|json(v)}.join(',')+']'
 when String;'"'+x.gsub(/["\\\x00-\x1f]/){|c|c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
 when TrueClass;'true';when FalseClass;'false';when NilClass;'null';else;x.to_s;end
end

mapping=YAML.load_file('/etc/phone-dns/mapping.yaml')
cfg={'log'=>{'level'=>'warn'},'dns'=>{'servers'=>[],'rules'=>[],'independent_cache'=>true,'strategy'=>'ipv4_only'},'inbounds'=>[],'outbounds'=>[],'route'=>{'rules'=>[{'action'=>'hijack-dns'}]}}
listeners=[]
mapping.each do |g|
 id=g['id'];proxyport=g['socks_port']
 listeners<<{'name'=>"phone-dns-#{id}",'type'=>'socks','listen'=>'127.0.0.1','port'=>proxyport,'udp'=>false,'users'=>[],'proxy'=>g['node']}
 cfg['outbounds']<<{'type'=>'socks','tag'=>"node-#{id}",'server'=>'127.0.0.1','server_port'=>proxyport,'version'=>'5'}
 [1,2].each do |n|
  tag="g#{id}-#{n}";port=15400+id*10+n
  cfg['inbounds']<<{'type'=>'direct','tag'=>tag,'listen'=>'127.0.0.1','listen_port'=>port}
  cfg['dns']['servers']<<{'type'=>'https','tag'=>tag,'server'=>n==1 ? '8.8.8.8' : '8.8.4.4','server_port'=>443,'path'=>'/dns-query','tls'=>{'enabled'=>true,'server_name'=>'dns.google'},'detour'=>"node-#{id}"}
  cfg['dns']['rules']<<{'inbound'=>[tag],'action'=>'route','server'=>tag}
 end
 File.write("/etc/phone-dns/group-#{id}.conf", "port=#{g['dns_port']}\nlisten-address=127.0.0.1,192.168.1.1\nbind-interfaces\nno-resolv\nno-hosts\ncache-size=512\nstrict-order\nserver=127.0.0.1##{15400+id*10+1}\nserver=127.0.0.1##{15400+id*10+2}\nuser=root\n")
end
cfg['dns']['final']='g1-1'
File.write('/etc/phone-dns/config.json',json(cfg))
File.write('/etc/phone-dns/listeners.yaml',listeners.to_yaml)
