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
fixture_directory do |root|
 fs=Class.new
 fs.const_set(:LOCK_EX,File::LOCK_EX);fs.const_set(:LOCK_NB,File::LOCK_NB)
 fs.define_singleton_method(:basename){|p|File.basename(p)}
 fs.define_singleton_method(:path){|p|p.start_with?('/') ? root+p : p}
 [:binread,:binwrite,:exist?,:file?,:delete].each{|m|fs.define_singleton_method(m){|p,*a|File.public_send(m,path(p),*a)}}
 fs.define_singleton_method(:open){|p,*a,&b|File.open(path(p),*a,&b)}
 fs.define_singleton_method(:rename){|a,b|File.rename(path(a),path(b))}
 ds=Class.new
 ds.define_singleton_method(:exist?){|p|Dir.exist?(fs.path(p))}
 ds.define_singleton_method(:mkdir){|p,*a|Dir.mkdir(fs.path(p),*a)}
 ds.define_singleton_method(:glob){|p|Dir.glob(fs.path(p)).map{|s|s.delete_prefix(root)}}
 io=Class.new
 io.define_singleton_method(:popen){|args,*_|args==['pidof','clash'] ? '123' : ''}
 PhoneNodes.const_set(:File,fs);PhoneNodes.const_set(:Dir,ds);PhoneNodes.const_set(:IO,io)
 ['/root','/var','/var/lock','/etc','/etc/openclash','/etc/openclash/config','/etc/phone-dns','/etc/nftables.d','/etc/config','/tmp'].each{|p|Dir.mkdir(root+p)}
 path='/etc/openclash/config/source.yaml';runtime='/etc/openclash/source.yaml'
 %w[success validation_failure stale_runtime].each do |scenario|
  initial=cfg.to_yaml;fs.binwrite(path,initial);fs.binwrite(runtime,initial)
  fs.binwrite('/etc/config/dhcp','original DHCP');fs.binwrite('/etc/nftables.d/90-phone-fixed-egress.nft','original nft')
  fs.binwrite('/etc/phone-dns/mapping.yaml','--- []');fs.binwrite('/tmp/openclash.change','marker')
  commands=[];failed=false
  PhoneNodes.define_singleton_method(:command) do |args,log|
   commands<<args
   if scenario=='validation_failure' && args.first.end_with?('/clash') && !failed
    failed=true;raise 'Injected validation failure'
   end
   if args==['/etc/init.d/openclash','start'] && scenario!='stale_runtime'
    fs.binwrite(runtime,fs.binread(path))
   end
   'ok'
  end
  result=PhoneNodes.apply(path,request.merge('revision'=>PhoneNodes.fingerprint(initial)))
  if scenario=='success'
   assert(result['ok']&&YAML.safe_load(fs.binread(path))['proxies'].size==2)
   assert(!result.to_s.include?(request['password']),'response leaked credentials')
   assert(!fs.exist?('/tmp/openclash.change'),'quick-start marker must be invalidated')
  else
   assert(result['error']&&result['rolled_back'],'failure must report rollback')
   assert(fs.binread(path)==initial.b,'failed node creation changed source')
   assert(fs.binread('/etc/config/dhcp')=='original DHCP')
  end
 end
end
puts 'SOCKS5 node validation, credential redaction, source revision, apply/rollback and stale-runtime rejection PASS'
# Keep the admin's explicit UDP setting when generated listeners are appended.
source=File.read(File.expand_path('../router/phone-dns/add-listeners.rb',__dir__))
raise 'Explicit UDP choice would be overwritten' unless source.include?("!n.key?('udp')")
