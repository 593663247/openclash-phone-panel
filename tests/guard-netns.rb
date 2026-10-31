# Run only inside a disposable network namespace, never against the host firewall.
require_relative 'support'
require_relative '../router/phone-dns/binding-registry'
raise 'Explicit isolated nft test required' unless ENV['PHONE_PANEL_NFT_TEST']=='1'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 mac='02:11:22:33:44:55';ip='192.168.1.101'
 device={'id'=>'mac-'+mac.delete(':'),'mac'=>mac,'ip'=>ip,'name'=>'fixture','node'=>'手机-01-示例'}
 doc={'schema'=>1,'revision'=>1,'devices'=>[device],'owned_rules'=>[PhoneBindings.rule(device)]}
 PhoneBindings.write(doc);PhoneBindings.guard;PhoneBindings.guard
 text=PanelStore.run('nft','list','chain','inet','phone_panel_persistent','guard')
 assert(text.include?(mac)&&text.include?(ip)&&text.scan(/counter packets/).size==2,'guard must load idempotently with IP and all-family MAC forwarding drops')
 PanelStore.run('nft','add','table','inet','fw4');PanelStore.run('nft','delete','table','inet','fw4')
 assert(PanelStore.run('nft','list','table','inet','phone_panel_persistent').include?(mac),'fw4 replacement must not remove independent protection')
 File.binwrite(PhoneBindings.path,'broken: [');PhoneBindings.boot_guard
 assert(PanelStore.run('nft','list','table','inet','phone_panel_persistent').include?(mac),'boot recovery must retain the last saved guard even if the registry is corrupt')
 File.delete(PhoneBindings.path);PhoneBindings.boot_guard
 assert(PanelStore.run('nft','list','table','inet','phone_panel_persistent').include?(mac),'missing desired state must not discard saved protection')
 PhoneBindings.guard(doc.merge('revision'=>2,'devices'=>[]))
 assert(!PanelStore.run('nft','list','table','inet','phone_panel_persistent').include?(mac),'explicit device removal releases its independent protection')
end
puts 'PASS: real isolated nft syntax, idempotent apply, fw4 replacement, reboot fallback and explicit guard removal'
