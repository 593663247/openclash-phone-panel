require_relative 'support'
require_relative '../router/phone-dns/apply-engine'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 %w[/etc/openclash/config /etc/phone-dns /etc/config /etc/nftables.d /var/lock /tmp /root].each{|p|PanelStore.mkdir(PanelStore.path(p))}
 source=PanelStore.path('/etc/openclash/config/source.yaml');runtime=PanelStore.path('/etc/openclash/source.yaml')
 cfg={'rules'=>['SRC-IP-CIDR,192.168.1.101/32,手机-01-示例'],'proxies'=>[],'sniffer'=>{'skip-src-address'=>['192.168.1.101/32']}}
 PanelStore.define_singleton_method(:run){|*args|''}
 %w[success validation_failure stale_runtime recovery_failure].each do |scenario|
  File.write(source,cfg.to_yaml);File.write(runtime,cfg.to_yaml)
  PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(1,'手机-01-示例',['192.168.1.101'])])
  registry=PanelStore.path('/etc/phone-dns/managed-nodes.yaml');File.delete(registry) if File.file?(registry)
  File.write(PanelStore.path('/etc/config/dhcp'),'original DHCP');File.write(PanelStore.path('/tmp/openclash.change'),'quickstart')
  commands=[];failed=false
  PhoneApply.define_singleton_method(:command) do |*args|
   commands<<args
   if %w[validation_failure recovery_failure].include?(scenario) && args.first=='sing-box'
    failed=true;raise 'Injected preflight failure'
   end
   raise 'Injected recovery failure' if scenario=='recovery_failure' && failed && args==['/etc/init.d/openclash','start']
   if args==['/etc/init.d/openclash','start'] && scenario!='stale_runtime';File.binwrite(runtime,File.binread(source));end
   case args.first
   when 'pidof';'123'
   when 'netstat';"tcp 0 0 127.0.0.1:15301 LISTEN\ntcp 0 0 127.0.0.1:18001 LISTEN\n"
   when 'nft';args.include?('codex_phone_guard') ? 'drop' : '192.168.1.101'
   else;'ok';end
  end
  result=PhoneApply.transaction(source,expected_revision:'r',revision:lambda{'r'}) do
   modified=Marshal.load(Marshal.dump(cfg));modified['rules']=['SRC-IP-CIDR,192.168.1.101/32,手机-02-示例']
   File.write(source,modified.to_yaml)
   PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(1,'手机-02-示例',['192.168.1.101'])])
   File.write(registry,'[]');{'example'=>true}
  end
  if scenario=='success'
   assert(result['ok']&&result['checks']['bindings']);assert(commands.count{|a|a==['/etc/init.d/openclash','stop']}==1)
  else
   assert(result['error']&&result['files_restored'],'file recovery must be explicit')
   assert(File.binread(source)==cfg.to_yaml.b,'source must be restored')
   assert(!File.exist?(registry),'new registry must be removed on rollback')
   assert(result['runtime_restored']==(scenario!='recovery_failure'),'never claim runtime recovery from file restore alone')
  end
 end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Shared apply engine: successful validation, preflight failure, stale runtime, file/runtime rollback distinction PASS'
