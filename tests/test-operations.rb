require_relative 'support'
require_relative '../router/phone-dns/operations'
PhoneOperations.define_singleton_method(:boot){'boot-now'}
PhoneOperations.define_singleton_method(:alive?){|pid|pid==123}
base={'id'=>'20261031120000-abcdef123456','status'=>'running','boot'=>'boot-now','pid'=>123,'at'=>Time.now.to_i}
assert(PhoneOperations.reconcile(base.dup)['status']=='running')
a=PhoneOperations.reconcile(base.merge('boot'=>'boot-before'));assert(a['status']=='interrupted'&&a['recovery_required'])
b=PhoneOperations.reconcile(base.merge('pid'=>999));assert(b['status']=='interrupted')
assert(PhoneOperations.reconcile(base.merge('status'=>'done','boot'=>'old'))['status']=='done')
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.mkdir(PhoneOperations.directory)
 PanelStore.write(PhoneOperations.directory+'/'+base['id']+'.json',base.merge('request'=>{'password'=>'fixture-only'},'log'=>'private'))
 public=PhoneOperations.list.first
 assert(!public.key?('request')&&!public.key?('pid')&&!public.key?('log'))
 assert(!public.to_s.include?('fixture-only'))
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Operation journal: live jobs, reboot/process-exit interruption and credential-free listing PASS'
