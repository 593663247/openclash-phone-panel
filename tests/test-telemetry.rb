require_relative 'support'
require_relative '../router/phone-dns/telemetry'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
phone={'ip'=>'192.168.1.101','connections'=>1,'neighbor'=>'STALE'}
now=Time.local(2026,10,30,12).to_i
first=PhoneTelemetry.tick({},[phone],{'192.168.1.101'=>{'up'=>1000,'down'=>2000}},now,'boot-a')
second=PhoneTelemetry.tick(first,[phone],{'192.168.1.101'=>{'up'=>4000,'down'=>8000}},now+15,'boot-a')
device=second['devices'][phone['ip']]
assert(device['days']['2026-10-30']=={'up'=>3000,'down'=>6000},'must account cumulative counter differences')
assert(device['rate_up']==200.0 && device['rate_down']==400.0,'must report byte rates')
assert(device['last_seen']==now+15)
reset=PhoneTelemetry.tick(second,[phone],{'192.168.1.101'=>{'up'=>100,'down'=>200}},now+30,'boot-a')
assert(reset['devices'][phone['ip']]['days']['2026-10-30']['up']==3100,'counter reset must not subtract traffic')
reboot=PhoneTelemetry.tick(reset,[phone],{'192.168.1.101'=>{'up'=>10,'down'=>20}},now+45,'boot-b')
assert(reboot['devices'][phone['ip']]['days']['2026-10-30']['up']==3100,'reboot must retain totals without fake deltas')
midnight=Time.local(2026,10,31,0).to_i
rolled=PhoneTelemetry.tick(reboot,[phone],{'192.168.1.101'=>{'up'=>40,'down'=>50}},midnight,'boot-b')
assert(rolled['devices'][phone['ip']]['days'].key?('2026-10-31'),'new day bucket required')
assert(rolled['devices'][phone['ip']]['months']['2026-10']['up']==3130,'surviving kernel counters recover bytes across sampling gaps')
assert(rolled['devices'][phone['ip']]['rate_up'].nil?,'sampling gaps must not pretend to be current rates')
assert(PhoneTelemetry.online(0,'STALE',0,now).first=='unknown','a stale ARP entry is not online proof')
assert(PhoneTelemetry.online(0,'FAILED',now-300,now).first=='offline')
assert(PhoneTelemetry.online(0,'REACHABLE',0,now).first=='active')
assert(PhoneTelemetry.online(0,nil,now-30,now).first=='recent')
assert(PhoneTelemetry.region('手机-01-纽约')=='美国')
script=PhoneCounters.script([phone['ip']],'br-lan',nil)
assert(script.include?('hook prerouting')&&script.include?('hook postrouting')&&script.include?('counter name up_192_168_1_101'))
assert(!script.match?(/\bdrop\b|\bredirect\b|\btproxy\b/),'traffic table must never route or block')
existing=PhoneCounters.script([phone['ip']],'br-lan',{phone['ip']=>{'up'=>1,'down'=>2}})
assert(!existing.include?('add counter'),'rule sync must preserve existing counters')
rejects{PhoneCounters.script(['192.168.1.101;drop'],'br-lan',nil)}
rejects{PhoneCounters.script([phone['ip']],'br-lan;cmd',nil)}
puts 'Traffic deltas, rates, counter reset/reboot, online evidence and counter-only rules PASS'

managed=[{'ip'=>'192.168.1.101','mac'=>'02:11:22:33:44:01'}]
leases=["0 02:11:22:33:44:01 192.168.1.101 phone *", "0 02:11:22:33:44:02 192.168.1.120 laptop *", "0 02:11:22:33:44:03 192.168.1.121 tv *", "0 02:11:22:33:44:04 192.168.1.121 conflict *"]
hosts=[{'ip'=>'192.168.1.119','mac'=>'02:11:22:33:44:02','name'=>'old lease'}, {'ip'=>'192.168.1.122','mac'=>'02:11:22:33:44:05','name'=>'printer'}]
neighbors="192.168.1.120 dev br-lan lladdr 02:11:22:33:44:02 REACHABLE\n192.168.1.123 dev br-lan lladdr 02:11:22:33:44:06 STALE\n192.168.2.4 dev br-lan lladdr 02:11:22:33:44:07 REACHABLE\n"
other=PhoneTelemetry.lan_devices(leases,hosts,neighbors,managed)
assert(other.map{|r|r['ip']}==%w[192.168.1.120 192.168.1.122 192.168.1.123],'discovery must exclude managed identities, old addresses, conflicting occupants and other subnets')
assert(other.first['hostname']=='laptop'&&other.first['neighbor']=='REACHABLE')
a=PhoneTelemetry.tick({},other,{'192.168.1.120'=>{'up'=>100,'down'=>200}},now,'boot-a')
b=PhoneTelemetry.tick(a,other,{'192.168.1.120'=>{'up'=>250,'down'=>500}},now+15,'boot-a')
assert(b['devices']['192.168.1.120']['rate_up']==10&&b['devices']['192.168.1.120']['rate_down']==20)
replacement=other.map{|r|r['ip']=='192.168.1.120' ? r.merge('mac'=>'02:11:22:33:44:09') : r}
c=PhoneTelemetry.tick(Marshal.load(Marshal.dump(b)),replacement,{'192.168.1.120'=>{'up'=>1000,'down'=>2000}},now+30,'boot-a')
assert(c['devices']['192.168.1.120']['days'].values.first=={'up'=>0,'down'=>0},'IP reuse must not inherit another MAC totals')
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.write(PanelStore.ram+'/metrics.yaml',b)
 groups=[{'node'=>'other','phones'=>replacement}];PhoneTelemetry.decorate(groups,now+30)
 assert(!groups[0]['phones'][0]['traffic']['today_available'],'stale IP identity must not display prior occupant totals before the next sample')
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Other LAN discovery: DHCP/static/neighbors, conflicts, managed exclusions, real counter deltas and IP identity isolation PASS'
