require_relative 'support'
require_relative '../router/phone-dns/device-discovery'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
leases=[['0','02:11:22:33:44:55','192.168.1.101','device'],['0','02:11:22:33:44:66','192.168.1.102','*']]
assert(PhoneDiscovery.candidates(leases,[],['192.168.1.101']).map{|d|d['ip']}==['192.168.1.102'])
conflict=PhoneDiscovery.candidates(leases,[{'ip'=>'192.168.1.101','mac'=>'02:11:22:33:44:77'}],[])
assert(conflict.first['conflict'],'static lease conflict must be visible before selection')
duplicate=leases+[leases.first.dup.tap{|l|l[2]='192.168.1.103'}]
assert(PhoneDiscovery.candidates(duplicate,[],[]).find{|d|d['ip']=='192.168.1.101'}['conflict'])
puts 'DHCP discovery, exclusion of managed devices and conflict visibility PASS'
