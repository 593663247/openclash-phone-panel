require_relative 'support'
require_relative '../router/phone-dns/node-manager'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
cfg={'proxies'=>[{'name'=>'前置-示例','type'=>'socks5'}],'proxy-groups'=>[{'name'=>'已有策略组'}]}
request={'name'=>'手机-测试节点','server'=>'192.0.2.10','port'=>'1080','username'=>'fixture-user','password'=>'fixture-only','udp'=>true,'dialer_proxy'=>'前置-示例'}
node=PhoneNodes.plan(cfg,request)
assert(node['dialer-proxy']=='前置-示例'&&node['port']==1080&&node['udp'])
assert(!PhoneNodes.summary(node).keys.any?{|k|%w[password username].include?(k)},'preview must redact authentication')
assert(!PhoneNodes.summary(node).to_s.include?(request['password']))
assert(!cfg['proxies'].any?{|n|n['name']==request['name']},'preview must not mutate source')
assert(PhoneNodes.plan(cfg,request.merge('server'=>'2001:db8::1','username'=>'','password'=>'','dialer_proxy'=>''))['type']=='socks5')
[
 {'name'=>'other'}, {'name'=>'手机-坏,名称'}, {'server'=>'https://example.invalid/path'}, {'server'=>'999.1.1.1'}, {'server'=>'bad..invalid'},
 {'port'=>'0'},{'port'=>'65536'},{'port'=>'1080;id'}, {'udp'=>'true'}, {'dialer_proxy'=>'不存在'}, {'username'=>''}, {'password'=>"bad\npassword"}
].each{|extra|rejects{PhoneNodes.plan(cfg,request.merge(extra))}}
rejects{PhoneNodes.plan(cfg.merge('proxies'=>[node]),request)}
rejects{PhoneNodes.plan(cfg.merge('proxy-groups'=>[{'name'=>request['name']}]),request)}
assert(PhoneNodes.fingerprint('one')!=PhoneNodes.fingerprint('two'))
updated=PhoneNodes.change({'proxies'=>cfg['proxies']+[node.merge('tls'=>true)]},request.merge('operation'=>'update','original_name'=>node['name'],'password'=>'','username'=>'','server'=>'192.0.2.20'),[],[node])
assert(updated['config']['proxies'].find{|n|n['name']==node['name']}['password']==node['password'],'blank edit must preserve credentials')
assert(updated['registry'].first['server']=='192.0.2.20'&&updated['registry'].first['tls']==true,'unexposed advanced fields must survive editing')
rejects{PhoneNodes.change({'proxies'=>[node],'rules'=>['MATCH,'+node['name']]},{'operation'=>'delete','original_name'=>node['name']},[],[node])}
rejects{PhoneNodes.change({'proxies'=>[node]},{'operation'=>'delete','original_name'=>node['name']},[{'node'=>node['name'],'ips'=>['192.168.1.101']}],[node])}
deleted=PhoneNodes.change({'proxies'=>[node]},{'operation'=>'delete','original_name'=>node['name']},[],[node]);assert(deleted['registry'].empty?&&deleted['config']['proxies'].empty?)
redacted=PhoneNodes.summary({'name'=>'wireguard-example','type'=>'wireguard','private-key'=>'fixture-secret-key','preshared-key'=>'fixture-secret-key'})
assert(!redacted.to_s.include?('fixture-secret-key'),'catalog must never leak non-SOCKS credentials')
PhoneNodeRegistry.merge({'proxies'=>[]},[node]).tap{|c|assert(c['proxies'].first==node)}
rejects{PhoneNodeRegistry.merge({'proxies'=>[node.merge('server'=>'192.0.2.99')]},[node])}
puts 'SOCKS5 CRUD validation, references, credential retention/redaction and registry merge PASS'
# Exercise the actual generator rather than matching its local variable names.
require_relative '../router/phone-dns/add-listeners'
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.mkdir(PanelStore.path('/etc/phone-dns'))
 PanelStore.write(PanelStore.path('/etc/phone-dns/listeners.yaml'),[])
 PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[])
 file=root+'/runtime.yaml'
 sample={'proxies'=>[{'name'=>PhoneSettings['node_prefix']+'explicit','type'=>'socks5','udp'=>false},{'name'=>PhoneSettings['node_prefix']+'default','type'=>'socks5'}]}
 PanelStore.atomic(file,sample.to_yaml);PhoneListeners.apply(file)
 result=YAML.safe_load(File.binread(file))
 assert(result['proxies'][0]['udp']==false,'explicit UDP choice must survive')
 assert(result['proxies'][1]['udp']==true,'missing phone UDP choice should receive its default')
 assert(result.dig('sniffer','enable')==false,'adding exclusions must not enable sniffing')
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
