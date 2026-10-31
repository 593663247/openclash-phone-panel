require_relative 'support'
require_relative '../router/phone-dns/binding-registry'
require_relative '../router/phone-dns/device-edit'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))

fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 a='手机-01-示例';b='手机-02-示例';ip='192.168.1.101';mac='02:11:22:33:44:55'
 proxies=[a,b].map{|name|{'name'=>name,'type'=>'socks5','server'=>'192.0.2.10','port'=>1080}}
 cfg={'proxies'=>proxies,'rules'=>["SRC-IP-CIDR,#{ip}/32,#{a}",'DOMAIN,example.com,DIRECT','MATCH,DIRECT']}
 mapping=[PhoneSettings.group(1,a,[ip]),PhoneSettings.group(2,b)]
 devices=[{'ip'=>ip,'mac'=>mac,'name'=>'us-13','group'=>1}];hosts=[{'ip'=>ip,'mac'=>mac,'name'=>'us-13'}]
 document=PhoneBindings.capture(cfg,mapping,devices,hosts);PhoneBindings.write(document);PhoneNodeRegistry.write(proxies)
 assert(document['devices'].first['id']=='mac-021122334455')
 replacement={'proxies'=>[],'rules'=>['DOMAIN,example.net,DIRECT','MATCH,DIRECT']}
 merged=PhoneBindings.compose(replacement)
 assert(merged['rules'].first==PhoneBindings.rule(document['devices'].first),'subscription replacements must regain desired binding')
 assert(merged['proxies'].map{|n|n['name']}.include?(a),'independent nodes must merge before binding validation')
 assert(PhoneBindings.compose(merged)==merged&&replacement['rules'].size==2,'merge must be idempotent and must not mutate its input')
 changed=DeviceEdit.transform(Marshal.load(Marshal.dump(cfg)),Marshal.load(Marshal.dump(mapping)),Marshal.load(Marshal.dump(devices)),{'operation'=>'rebind','ip'=>ip,'group'=>'2'})
 rebound=PhoneBindings.capture(changed['config'],changed['mapping'],changed['devices'],hosts,previous:document)
 assert(rebound['devices'].first['id']==document['devices'].first['id'])
 assert(PhoneBindings.compose(cfg,rebound)['rules'].first.end_with?(b),'previous exact owned tuples must be replaced')
 changed=DeviceEdit.transform(changed['config'],changed['mapping'],changed['devices'],{'operation'=>'change_ip','ip'=>ip,'new_ip'=>'192.168.1.113'})
 moved=PhoneBindings.capture(changed['config'],changed['mapping'],changed['devices'],[hosts.first.merge('ip'=>'192.168.1.113')],previous:rebound)
 assert(moved['devices'].first['id']==document['devices'].first['id'],'IP changes must retain device identity')
 final=PhoneBindings.compose(cfg,moved);assert(!final['rules'].any?{|r|r.start_with?("SRC-IP-CIDR,#{ip}/32,")})
 changed=DeviceEdit.transform(changed['config'],changed['mapping'],changed['devices'],{'operation'=>'delete','ip'=>'192.168.1.113'})
 deleted=PhoneBindings.capture(changed['config'],changed['mapping'],changed['devices'],hosts,previous:moved)
 extra='SRC-IP-CIDR,192.168.1.222/32,DIRECT';broad='SRC-IP-CIDR,192.168.1.0/24,DIRECT'
 old=Marshal.load(Marshal.dump(cfg));old['rules']+=[extra,broad]
 clean=PhoneBindings.compose(old,deleted)
 assert(clean['rules'].include?(extra)&&clean['rules'].include?(broad)&&clean['rules'].include?('DOMAIN,example.com,DIRECT'),'unowned rules must survive deletion')
 assert(!clean['rules'].include?(cfg['rules'].first),'deleted bindings must not reappear from an older config')
 conflict=Marshal.load(Marshal.dump(cfg));conflict['rules'][0]="SRC-IP-CIDR,#{ip}/32,DIRECT"
 rejects('unowned same-IP rules must block application'){PhoneBindings.compose(conflict,document)}
 duplicate=Marshal.load(Marshal.dump(cfg));duplicate['rules'].unshift(duplicate['rules'].first)
 rejects{PhoneBindings.compose(duplicate,document)}
 PhoneNodeRegistry.write([]);rejects('missing target must not become DIRECT'){PhoneBindings.compose(replacement,document)}
 rejects('migration cannot guess mismatched DHCP MAC'){PhoneBindings.capture(cfg,mapping,devices,[hosts.first.merge('mac'=>'02:11:22:33:44:66')])}
 rejects{PhoneBindings.capture(cfg,mapping,devices,hosts+hosts)}
 rejects{PhoneBindings.capture(cfg,mapping,devices+[{'ip'=>'192.168.1.200'}],hosts)}
 rejects{PhoneBindings.capture(cfg,mapping+[PhoneSettings.group(3,b,[ip])],devices,hosts)}
 rejects{PhoneBindings.validate(document.merge('schema'=>99))}
 File.binwrite(PhoneBindings.path,'broken: [');rejects('corrupt registries must fail closed'){PhoneBindings.read}
 PhoneBindings.check_network(document,[['0',mac,'192.168.1.193','fixture']], '');rejects{PhoneBindings.check_network(document,[['0','02:11:22:33:44:66',ip,'other']], '')};rejects{PhoneBindings.check_network(document,[],ip+' dev br-lan lladdr 02:11:22:33:44:66 REACHABLE')}
 PhoneBindings.write(document);assert(PhoneBindings.read==document,'new processes can reload the complete desired state')
 guard=PhoneBindings.guard_text(document);assert(guard.include?('hook forward priority -20')&&guard.include?(mac)&&guard.include?(ip))
 assert(!guard.include?('hook input'),'persistent protection must not block local proxy delivery')
 regenerated=PhoneBindings.mapping(document,[PhoneSettings.group(7,a),PhoneSettings.group(8,b)])
 assert(regenerated.first['id']==7&&PhoneBindings.devices(document,regenerated).first['group']==7,'desired node names cannot depend on old numeric group IDs')
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Binding persistence: migration, subscription/config switch, stable identity, exact ownership, rename/rebind/IP/delete and conflict/corruption rejection PASS'
