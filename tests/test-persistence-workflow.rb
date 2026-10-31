require_relative 'support'
require_relative '../router/phone-dns/binding-manager'
require_relative '../router/phone-dns/alignment'

PhoneSettings.define_singleton_method(:values){@fixture_settings ||= validate({})}
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 %w[/etc/openclash/config /etc/config /etc/nftables.d /var/lock /etc/phone-dns].each{|dir|PanelStore.mkdir(PanelStore.path(dir))}
 a='手机-01-示例';b='手机-02-示例';ip='192.168.1.101';mac='02:11:22:33:44:55'
 proxy={'name'=>a,'type'=>'socks5','server'=>'192.0.2.10','port'=>1080}
 cfg={'proxies'=>[proxy],'rules'=>["SRC-IP-CIDR,#{ip}/32,#{a}",'MATCH,DIRECT'],'sniffer'=>{}}
 source=PanelStore.path('/etc/openclash/config/a.yaml');runtime=PanelStore.path('/etc/openclash/a.yaml')
 source_b=PanelStore.path('/etc/openclash/config/b.yaml');runtime_b=PanelStore.path('/etc/openclash/b.yaml')
 File.binwrite(source,cfg.to_yaml);File.binwrite(runtime,cfg.to_yaml)
 selected=PanelStore.path('/etc/config/openclash');File.binwrite(selected,source)
 File.binwrite(PanelStore.path('/etc/config/phone_panel'),'fixture settings')
 File.binwrite(PanelStore.path('/etc/config/dhcp'),[{'ip'=>ip,'mac'=>mac,'name'=>'us-13'}].to_yaml)
 PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(1,a,[ip])])
 PanelStore.write(PanelStore.path('/etc/phone-dns/devices.yaml'),[{'ip'=>ip,'mac'=>mac,'name'=>'us-13','group'=>1}])
 File.binwrite(PanelStore.path('/etc/nftables.d/90-phone-fixed-egress.nft'),File.binread(File.expand_path('../router/nftables/90-phone-fixed-egress.nft',__dir__)))
 PhoneNodeRegistry.write([proxy]);calls=[];guarded=nil;failure=nil
 PhoneApply.define_singleton_method(:source){|**_|File.binread(selected).force_encoding('UTF-8')}
 PanelStore.define_singleton_method(:run) do |*args|
  if args==['uci','export','dhcp']
   YAML.safe_load(File.binread(PanelStore.path('/etc/config/dhcp'))).map{|h|"config host\n"+h.map{|k,v|" option #{k} '#{v}'\n"}.join}.join
  else;'';end
 end
 PanelStore.define_singleton_method(:capture){|*args|['',1]}
 PhoneBindings.define_singleton_method(:guard) do |doc=PhoneBindings.read|
  if doc
   PhoneBindings.validate(doc);guarded=Marshal.load(Marshal.dump(doc))
   PanelStore.write(PanelStore.path('/etc/phone-dns/persistent-guard.yaml'),doc)
  end
  true
 end
 finalize=lambda do |file|
  config=YAML.safe_load(File.binread(file),aliases:true);mapping=PanelStore.read(PanelStore.path('/etc/phone-dns/mapping.yaml'),[])
  config['sniffer']={'skip-src-address'=>mapping.flat_map{|g|g['ips']}.map{|addr|addr+'/32'}}
  config['listeners']=mapping.map{|g|{'name'=>"phone-dns-#{g['id']}",'proxy'=>g['node']}}
  PanelStore.atomic(file,config.to_yaml)
 end
 PhoneApply.define_singleton_method(:command) do |*args|
  calls<<args
  raise 'Injected renderer failure' if failure==:render && args==['/usr/bin/ruby','/etc/phone-dns/render-dns.rb']
  if args[0,2]==['/usr/bin/ruby','/etc/phone-dns/align-dns.rb']
   PhoneAlignment.run(args[2])
  elsif args==['/usr/bin/ruby','/etc/phone-dns/render-dns.rb']
   PanelStore.atomic(PanelStore.path('/etc/phone-dns/config.json'),'{}')
   PanelStore.write(PanelStore.path('/etc/phone-dns/listeners.yaml'),[])
   PanelStore.read(PanelStore.path('/etc/phone-dns/mapping.yaml'),[]).each{|g|PanelStore.atomic(PanelStore.path("/etc/phone-dns/group-#{g['id']}.conf"),'generated')}
  elsif args==['/etc/init.d/openclash','start']
   active=File.binread(selected).force_encoding('UTF-8');running=PanelStore.path('/etc/openclash/'+File.basename(active))
   PanelStore.atomic(running,File.binread(active));PhoneAlignment.run(running);finalize.call(running)
  elsif args.first=='pidof';'123'
  elsif args.first=='netstat'
   PanelStore.read(PanelStore.path('/etc/phone-dns/mapping.yaml'),[]).flat_map{|g|[g['dns_port'],g['socks_port']]}.map{|port|"tcp 0 0 127.0.0.1:#{port} LISTEN"}.join("\n")
  elsif args.first=='nft'
   if args.include?('phone_panel_persistent');PhoneBindings.guard_text(guarded)
   elsif args.include?('codex_phone_guard');'drop'
   else;ip;end
  else;'ok';end
 end
 preview=PhoneBindingManager.plan
 assert(preview['count']==1&&!File.exist?(PhoneBindings.path),'migration preview must be read-only')
 stale=preview['revision'];File.binwrite(PanelStore.path('/etc/config/phone_panel'),'changed fixture settings')
 rejects('migration preview must be revision gated'){PhoneBindingManager.apply({'revision'=>stale})}
 preview=PhoneBindingManager.plan;result=PhoneBindingManager.apply({'revision'=>preview['revision']})
 assert(result['ok'],'migration must persist and validate the running configuration: '+result.to_s)
 assert(PhoneBindings.info.dig('status','state')=='verified')
 assert(PhoneBindings.read['devices'].first['mac']==mac)
 base={'proxies'=>[],'rules'=>['DOMAIN,example.net,DIRECT','MATCH,DIRECT'],'sniffer'=>{}}
 File.binwrite(source,base.to_yaml);File.binwrite(runtime,base.to_yaml)
 PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),[PhoneSettings.group(7,a)])
 PhoneAlignment.run(runtime);finalize.call(runtime);PhoneApply.verify(source);PhoneApply.checkpoint(source)
 assert(YAML.safe_load(File.binread(source))['rules'].first=="SRC-IP-CIDR,#{ip}/32,#{a}",'subscription replacement must repair the source too')
 assert(PanelStore.read(PanelStore.path('/etc/phone-dns/devices.yaml'),[]).first['group']==7,'group rebuild must not change desired node identity')
 good=PhoneBindings.info['last_good']['backup'];assert(good,'verified complete snapshot must be available')
 before_guard=PhoneBindings.guard_text(guarded);before_nft=File.binread(PanelStore.path('/etc/nftables.d/90-phone-fixed-egress.nft'))
 File.binwrite(source_b,base.to_yaml);File.binwrite(runtime_b,base.to_yaml);File.binwrite(selected,source_b);PhoneNodeRegistry.write([])
 rejects('missing subscription node must block the switch'){PhoneAlignment.run(runtime_b)}
 assert(File.binread(source_b)==base.to_yaml.b&&File.binread(runtime_b)==base.to_yaml.b,'conflict must not modify the new config')
 assert(File.binread(PanelStore.path('/etc/nftables.d/90-phone-fixed-egress.nft'))==before_nft&&PhoneBindings.guard_text(guarded)==before_guard,'last protection must remain on failure')
 assert(PhoneBindings.info.dig('status','state')=='blocked')
 restored=PhoneApply.restore(good)
 assert(restored['ok'],'complete restore must also restore config selection and node storage: '+restored.to_s)
 assert(File.binread(selected).force_encoding('UTF-8')==source&&PhoneNodeRegistry.read.first['name']==a)
 assert(PhoneBindings.info.dig('status','state')=='verified')
 File.binwrite(source,base.to_yaml);failure=:render
 rejects('partial generation must report failure'){PhoneAlignment.run(source)}
 assert(File.binread(source)==base.to_yaml.b,'failed generation must restore the pre-apply source')
 assert(PhoneBindings.read['devices'].size==1&&PhoneBindings.guard_text(guarded).include?(mac))
 failure=nil;PhoneAlignment.run(source);assert(YAML.safe_load(File.binread(source))['rules'].first==PhoneBindings.rule(PhoneBindings.read['devices'].first))
 PhoneBindings.status('generating',{'pid'=>999999999,'boot'=>'previous-boot','message'=>'fixture interrupted'})
 assert(PhoneBindings.info.dig('status','state')=='interrupted','power/process interruption must be observable')
 PhoneAlignment.run(source);assert(PhoneBindings.info.dig('status','state')=='generated','reboot derivation is idempotent and does not replay user mutations')
 assert(PhoneBindings.read['revision']==1,'configuration regeneration must not invent device revisions')
 assert(calls.any?{|args|args==['fw4','check']})
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Persistence workflow: read-only migration, stale preview, subscription/source/runtime rebuild, missing-node guard, complete cross-config restore, injected failure and reboot recovery PASS'
