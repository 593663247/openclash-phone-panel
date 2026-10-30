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
