require 'yaml'
def js(x)
 case x
 when Hash; '{'+x.map{|k,v|js(k.to_s)+':'+js(v)}.join(',')+'}'
 when Array; '['+x.map{|v|js(v)}.join(',')+']'
 when String; '"'+x.gsub(/["\\\x00-\x1f]/){|c| c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
 when TrueClass;'true';when FalseClass;'false';when NilClass;'null';else;x.to_s;end
end
begin
 mapping=YAML.load_file('/etc/phone-dns/mapping.yaml')
 devices=File.exist?('/etc/phone-dns/devices.yaml') ? YAML.load_file('/etc/phone-dns/devices.yaml') : []
 managed_ips=mapping.flat_map{|g|g['ips']}
 cfgpath=IO.popen(['uci','-q','get','openclash.config.config_path'], &:read).strip
 p=YAML.load_file('/etc/openclash/'+File.basename(cfgpath),aliases:true)
 source=YAML.load_file(cfgpath,aliases:true)
 id=mapping.map{|g|g['id']}.max.to_i
 (source['proxies']||[]).map{|n|n['name']}.grep(/\A手机[-－]/).uniq.each do |name|
  next if mapping.any?{|g|g['node']==name}
  id+=1;mapping<<{'id'=>id,'node'=>name,'ips'=>[],'dns_port'=>15300+id,'socks_port'=>18000+id}
 end
 sockets=IO.popen(['netstat','-ln'], &:read)
 leases=File.readlines('/tmp/dhcp.leases').map{|l|l.split} rescue []
 connections=[]
 begin
  raw=IO.popen(['curl','-s','--max-time','2','-H','@-','http://127.0.0.1:9090/connections'],'r+') do |io|
   io.write("Authorization: Bearer #{p['secret']}\n");io.close_write;io.read
  end
  connections=YAML.load(raw)['connections']||[]
 rescue;end
 groups=mapping.map do |g|
  active=connections.select{|c|g['ips'].include?(c.dig('metadata','sourceIP'))}
  listener=(p['listeners']||[]).find{|l|l['name']=="phone-dns-#{g['id']}"}
  node=(p['proxies']||[]).find{|n|n['name']==g['node']}
  {'id'=>g['id'],'node'=>g['node'],'ips'=>g['ips'],'dns_port'=>g['dns_port'],'socks_port'=>g['socks_port'],
   'dns_listening'=>sockets.match?(/127\.0\.0\.1:#{g['dns_port']}\s/),'socks_listening'=>sockets.match?(/127\.0\.0\.1:#{g['socks_port']}\s/),
   'binding_ok'=>listener && listener['proxy']==g['node'],'udp_enabled'=>node && node['udp']==true,
   'connections'=>active.size,'udp_connections'=>active.count{|c|c.dig('metadata','network')=='udp'},
   'phones'=>g['ips'].map{|ip|l=leases.find{|a|a[2]==ip};{'ip'=>ip,'hostname'=>((devices.find{|d|d['ip']==ip}||{})['name'] || (l ? l[3] : nil)),'lease_present'=>!l.nil?}},
   'upload'=>active.sum{|c|c['upload'].to_i},'download'=>active.sum{|c|c['download'].to_i}}
 end
 nft=IO.popen(['nft','list','chain','inet','fw4','codex_phone_dns'], &:read)
 guard=IO.popen(['nft','list','chain','inet','fw4','codex_phone_guard'], &:read)
 lines=File.readlines('/tmp/openclash.log').last(600).select{|l|managed_ips.any?{|ip|l.include?(ip+':')}}.last(12).map{|l|l.strip} rescue []
 imports=File.exist?('/etc/phone-dns/import-status.yaml') ? YAML.load_file('/etc/phone-dns/import-status.yaml') : {}
 result={'pending_imports'=>imports.fetch('pending',[]),'time'=>Time.now.strftime('%Y-%m-%d %H:%M:%S %z'),'groups'=>groups,'dns_redirect_ready'=>nft.include?('15301')&&nft.include?('15306'),
 'guard_ready'=>guard.include?('drop'),'logs'=>lines,'scope'=>managed_ips.join(', '),'device_count'=>managed_ips.size,'read_only'=>false}
 puts js(result)
rescue =>e
 puts js({'error'=>'无法读取面板状态，请检查独立DNS配置和OpenClash运行状态','detail'=>e.class.to_s})
end
