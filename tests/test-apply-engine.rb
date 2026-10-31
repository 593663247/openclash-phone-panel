require_relative 'support'
require_relative '../router/phone-dns/apply-engine'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 %w[/etc/openclash/config /etc/phone-dns /etc/config /etc/nftables.d /var/lock /tmp /root].each{|p|PanelStore.mkdir(PanelStore.path(p))}
 source=PanelStore.path('/etc/openclash/config/source.yaml');runtime=PanelStore.path('/etc/openclash/source.yaml')
 PhoneApply.define_singleton_method(:source){|**_|source}
 cfg={'rules'=>['SRC-IP-CIDR,192.168.1.101/32,手机-01-示例'],'proxies'=>[],'sniffer'=>{'skip-src-address'=>['192.168.1.101/32']}}
 PanelStore.define_singleton_method(:run){|*args|''}
 [nil,'','stale'].each do |token|
  called=false
  rejects('missing or stale preview must not apply') do
   PhoneApply.transaction(source,expected_revision:token,revision:lambda{'current'}){called=true;{}}
  end
  assert(!called,'preview rejection must happen before mutation')
 end
 %w[success validation_failure stale_runtime recovery_failure dhcp_mismatch].each do |scenario|
  File.binwrite(source,cfg.to_yaml);File.binwrite(runtime,cfg.to_yaml)
  PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(1,'手机-01-示例',['192.168.1.101'])])
  registry=PanelStore.path('/etc/phone-dns/managed-nodes.yaml');File.delete(registry) if File.file?(registry)
  File.binwrite(PanelStore.path('/etc/config/dhcp'),'original DHCP');File.binwrite(PanelStore.path('/tmp/openclash.change'),'quickstart')
  commands=[];failed=false
  PhoneApply.define_singleton_method(:command) do |*args|
   commands<<args
   if scenario=='validation_failure' && args.first=='sing-box'
    failed=true;raise 'Injected preflight failure'
   end
   raise 'Injected recovery failure' if scenario=='recovery_failure' && args==['/etc/init.d/openclash','start']
   if args==['/etc/init.d/openclash','start'] && scenario!='stale_runtime';File.binwrite(runtime,File.binread(source));end
   case args.first
   when 'pidof';'123'
   when 'netstat';"tcp 0 0 127.0.0.1:15301 LISTEN\ntcp 0 0 127.0.0.1:18001 LISTEN\n"
   when 'nft';args.include?('codex_phone_guard') ? 'drop' : '192.168.1.101'
   else;'ok';end
  end
  postcheck=lambda {raise 'DHCP post-reload mismatch' if scenario=='dhcp_mismatch';{'dhcp_static'=>true}}
  result=PhoneApply.transaction(source,expected_revision:'r',revision:lambda{'r'},postcheck:postcheck) do
   modified=Marshal.load(Marshal.dump(cfg));modified['rules']=['SRC-IP-CIDR,192.168.1.101/32,手机-02-示例']
   File.binwrite(source,modified.to_yaml)
   PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(1,'手机-02-示例',['192.168.1.101'])])
   File.binwrite(registry,'[]');{'example'=>true}
  end
  if scenario=='success'
   assert(result['ok']&&result['checks']['bindings']&&result['checks']['dhcp_static']);assert(commands.count{|a|a==['/etc/init.d/openclash','stop']}==1)
  else
   assert(result['error']&&result['files_restored'],'file recovery must be explicit')
   assert(File.binread(source)==cfg.to_yaml.b,'source must be restored')
   assert(!File.exist?(registry),'new registry must be removed on rollback')
   assert(result['runtime_restored']==(scenario!='recovery_failure'),'never claim runtime recovery from file restore alone')
   assert(result['recovery_required']==(scenario=='recovery_failure'))
   assert(!commands.any?{|a|a==['/etc/init.d/openclash','stop']},'preflight failure must not restart the untouched core') if scenario=='validation_failure'
  end
 end
 unless RUBY_PLATFORM.match?(/mswin|mingw/)
  PanelStore.mkdir(PanelStore.path('/etc/init.d'))
  helper=PanelStore.path('/etc/init.d/phone-panel-guard');File.symlink(source,helper)
  rejects('existing helper symlinks must be rejected'){PhoneApply.ensure_boot_guard}
  assert(File.binread(source)==cfg.to_yaml.b,'repair must never write through an existing helper link')
  File.delete(helper)
 end
 first=PanelStore.path('/etc/phone-dns/first.yaml');last=PanelStore.path('/etc/phone-dns/last.yaml')
 generated=PanelStore.path('/etc/phone-dns/group-99.conf')
 File.binwrite(first,'modified');File.binwrite(last,'modified');File.binwrite(generated,'generated')
 original_atomic=PhoneApply.method(:atomic)
 begin
  PhoneApply.define_singleton_method(:atomic){|file,data|raise Errno::EACCES if file==first;original_atomic.call(file,data)}
  errors=PhoneApply.restore_files({first=>'original',last=>'original'},[first,last])
  assert(errors.size==1&&errors.first.include?('first.yaml'),'failed path must be identified')
  assert(File.read(last)=='original','one failed file must not prevent remaining restoration')
  assert(!File.exist?(generated),'generated files must be cleaned even after a restore failure')
 ensure
  PhoneApply.define_singleton_method(:atomic,original_atomic)
 end
 begin
  PhoneApply.define_singleton_method(:atomic){|file,data|File.binwrite(file,'wrong bytes')}
  assert(!PhoneApply.restore_files({last=>'original'},[first,last]).empty?,'restored bytes must match snapshot')
 ensure
  PhoneApply.define_singleton_method(:atomic,original_atomic)
 end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Shared apply engine: successful validation, preflight failure, stale runtime, file/runtime rollback distinction PASS'
