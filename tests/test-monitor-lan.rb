require_relative 'support'
require_relative '../router/phone-dns/monitor'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 managed={'ip'=>'192.168.1.101','mac'=>'02:11:22:33:44:01'}
 other={'ip'=>'192.168.1.120','mac'=>'02:11:22:33:44:02','hostname'=>'laptop'}
 PhoneStatus.define_singleton_method(:collect){{'groups'=>[{'phones'=>[managed]}],'other_devices'=>[other]}}
 rows=nil;synced=[]
 PhoneCounters.define_singleton_method(:read){rows}
 PhoneCounters.define_singleton_method(:sync) do |ips|
  synced<<ips;rows=ips.to_h{|ip|[ip,{'up'=>100,'down'=>200}]}
 end
 # Windows has no /proc boot_id; only replace this one observation.
 original_read=File.method(:read)
 begin
  File.define_singleton_method(:read){|p,*args|p=='/proc/sys/kernel/random/boot_id' ? 'fixture-boot' : original_read.call(p,*args)}
  state,_=PhoneMonitor.sample({},100)
  assert(synced.first==%w[192.168.1.101 192.168.1.120],'both bound and other devices must receive count-only rules')
  rows['192.168.1.120']={'up'=>250,'down'=>650}
  state,_=PhoneMonitor.sample(state,115)
  assert(state['devices']['192.168.1.120']['rate_up']==10&&state['devices']['192.168.1.120']['rate_down']==30)
  assert(synced.size==1,'stable discovery must not rebuild the nft counter chains each sample')
  assert(PanelStore.read(PanelStore.ram+'/metrics.yaml',{})['devices'].key?('192.168.1.120'))
 ensure;File.define_singleton_method(:read,original_read);end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Monitor sample: bound and other LAN devices share stable count-only sampling and persisted metrics PASS'
