require_relative '../router/phone-dns/settings'
def check(message)
 raise message unless yield
end
def rejects(message)
 begin;yield;rescue;return;end
 raise message
end
defaults=PhoneSettings.validate({})
PhoneSettings.instance_variable_set(:@values,defaults)
check('router cannot be assigned'){!PhoneSettings.usable?('192.168.1.1')}
check('broadcast cannot be assigned'){!PhoneSettings.usable?('192.168.1.255')}
check('normal host allowed'){PhoneSettings.usable?('192.168.1.101')}
rejects('overlapping ports accepted'){PhoneSettings.validate('socks_base'=>'15300')}
rejects('invalid bridge accepted'){PhoneSettings.validate('bridge'=>'br-lan;cmd')}
rejects('noncanonical CIDR accepted'){PhoneSettings.validate('lan_cidr'=>'192.168.1.1/24')}
rejects('out-of-range generated ports accepted'){PhoneSettings.validate('dns_base'=>'65530')}
PhoneSettings.validate('dns_base'=>'65400')
wide=PhoneSettings.validate('lan_cidr'=>'192.168.0.0/16')
PhoneSettings.instance_variable_set(:@values,wide)
check('wide subnet usable host'){PhoneSettings.usable?('192.168.2.101')}
check('sections must not collide across subnets') do
 PhoneSettings.lease_section('phone_panel','192.168.1.101')!=PhoneSettings.lease_section('phone_panel','192.168.2.101')
end
leases=[['0','02:11:22:33:44:55','192.168.1.101','permanent'],
 ['101','02:11:22:33:44:55','192.168.1.102','current'],
 ['100','02:11:22:33:44:55','192.168.1.103','expired'],
 ['bad','02:11:22:33:44:55','192.168.1.104','invalid'],
 ['0','bad','192.168.1.105','invalid'],['0','02:11:22:33:44:55','999.1.1.1','invalid'],[]]
check('expired and malformed leases must be ignored'){PhoneSettings.active_leases(leases,100).map{|l|l[3]}==%w[permanent current]}
line='time="2026-01-01T12:00:00Z" level=warning msg="192.168.1.101:1234 -> https://user:private-password@example.invalid/path?secret=private-token connection refused"'
summary=PhoneSettings.warning_summary(line,['192.168.1.101'])
check('warning classification'){summary=='2026-01-01T12:00:00Z | 192.168.1.101 | connection refused'}
check('credentials and destination omitted'){!summary.match?(/private-|example.invalid/)}
check('unmanaged log ignored'){PhoneSettings.warning_summary(line,['192.168.1.102']).nil?}
check('nonwarning ignored'){PhoneSettings.warning_summary(line.sub('warning','info'),['192.168.1.101']).nil?}
PhoneSettings.instance_variable_set(:@values,defaults)
puts 'Settings, lease filtering, unique DHCP sections and log redaction PASS'
