require_relative 'support'

module BatchRouterDouble
def source_path;router_path('/etc/openclash/config/source.yaml');end
def hosts;@uci_hosts.values;end
def revision
 # The external SHA implementation is not under test; retain deterministic configuration change detection.
 revision_data.bytes.inject(0){|n,b|(n*31+b)%0xffffffffffffffff}.to_s(16).rjust(40,'0')
end
def quiet(*args)
 if args==['uci','revert','dhcp']
  @uci_hosts=YAML.safe_load(File.read(router_path('/etc/config/dhcp')))||{};return ''
 end
 return '123' if args==['pidof','clash']
 return YAML.load_file(BASE+'/mapping.yaml').flat_map{|g|g['ips']}.join(' ') if args[0,2]==['nft','list']
 ''
end
def run(*args)
 @commands<<args
 if (@fail_once==:validation && args.first=='/usr/bin/sing-box') || (@fail_once==:runtime && args[0,3]==['nft','get','element'])
  @fail_once=false;raise 'Injected application failure'
 end
 if args[0,2]==['uci','set']
  key,value=args[2].split('=',2);_,section,option=key.split('.')
  @uci_hosts[section]||={};@uci_hosts[section][option]=value if option
 elsif args==['uci','commit','dhcp']
  File.write(router_path('/etc/config/dhcp'),@uci_hosts.to_yaml)
 elsif args.first=='/usr/bin/ruby'
  YAML.load_file(BASE+'/mapping.yaml').each{|g|File.write(BASE+"/group-#{g['id']}.conf",'generated')}
 elsif args==['/etc/init.d/openclash','start']
  cfg=YAML.load_file(source_path);mapping=YAML.load_file(BASE+'/mapping.yaml')
  cfg['sniffer']={'skip-src-address'=>mapping.flat_map{|g|g['ips']}.map{|ip|ip+'/32'}}
  File.write(router_path('/etc/openclash/source.yaml'),cfg.to_yaml)
 end
 'ok'
end

end

fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 require_relative '../router/phone-dns/device-manager'
 extend BatchRouterDouble
 PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
 ['/etc/openclash/config','/etc/config','/etc/nftables.d','/var/lock','/tmp','/root', '/etc/phone-dns/jobs'].each{|p|PanelStore.mkdir(router_path(p))}
 nodes=['手机-01-示例','手机-02-示例']
 rows=[{'name'=>'First','ip'=>'192.168.1.101','mac'=>'02:11:22:33:44:55','group'=>1},
 {'name'=>'Second','ip'=>'192.168.1.102','mac'=>'02:11:22:33:44:66','group'=>2}]
 [false,:validation,:runtime].each_with_index do |failure,index|
  @commands=[];@uci_hosts={};@fail_once=failure
  File.write(source_path,{'proxies'=>nodes.map{|name|{'name'=>name}},'rules'=>['MATCH,DIRECT']}.to_yaml)
  File.write(router_path('/etc/config/dhcp'),{}.to_yaml)
  File.write(router_path('/tmp/dhcp.leases'),'')
  File.write(router_path('/etc/nftables.d/90-phone-fixed-egress.nft'),'original rules')
  File.write(BASE+'/mapping.yaml',nodes.each_with_index.map{|name,i|PhoneSettings.group(i+1,name)}.to_yaml)
  File.write(BASE+'/devices.yaml',[].to_yaml);File.write(BASE+'/config.json','{}');File.write(BASE+'/listeners.yaml',[].to_yaml)
  Dir.glob(BASE+'/group-*.conf').each{|p|File.delete(p)}
  original=tracked.to_h{|p|[p,File.binread(p)]}
  plan=batch_plan({'devices'=>rows});id="2026103012000#{index}-abcdef123456"
  jobwrite(id,{'request'=>plan,'status'=>'queued'})
  apply_worker(id)
  result=YAML.safe_load(File.read(JOBS+'/'+id+'.yaml'))
  if failure
   assert(result['status']=='failed'&&result['rolled_back'],'failed batch must report rollback')
   original.each{|p,bytes|assert(File.binread(p)==bytes,'failed batch left modified configuration: '+p)}
   assert(Dir.glob(BASE+'/group-*.conf').empty?,'failed batch left newly generated group files')
  else
   assert(result['status']=='done','successful batch must complete')
   assert(File.read(router_path('/etc/nftables.d/90-phone-fixed-egress.nft')).include?("flags interval\n auto-merge\n"),'interval sets must auto-merge against retained live elements')
   assert(YAML.load_file(BASE+'/devices.yaml').size==2)
   assert(YAML.load_file(BASE+'/mapping.yaml').flat_map{|g|g['ips']}.sort==rows.map{|r|r['ip']}.sort)
   assert(@commands.count{|a|a==['uci','commit','dhcp']}==1,'batch must commit DHCP once')
   assert(@commands.count{|a|a==['/etc/init.d/openclash','stop']}==1&&@commands.count{|a|a==['/etc/init.d/openclash','start']}==1,'batch must restart proxy once')
  end
 end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Batch worker end-to-end: one restart/commit, alias-free jobs and complete preflight-failure rollback PASS'
