require_relative 'support'
require_relative '../router/phone-dns/health'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
group={'id'=>1,'node'=>'手机-01-示例','dns_port'=>15301,'socks_port'=>18001,'dns_listening'=>true,'socks_listening'=>true,'binding_ok'=>true}
good=PhoneProbe.evaluate(group,{'dns_ok'=>true,'socks_tcp_ok'=>true},'203.0.113.10',0,200,12,80,100)
assert(good['dns_ok']&&good['exit_ok']&&good['category']=='ok')
value={'identity'=>PhoneHealth.identity(group)}
PhoneHealth.update(value,good)
assert(!value['exit_changed'],'first successful check establishes baseline without a false alert')
changed=good.merge('exit_ip'=>'203.0.113.11','at'=>200)
PhoneHealth.update(value,changed)
assert(value['exit_changed']&&value['events'].last['previous']=='203.0.113.10')
failure=PhoneProbe.evaluate(group,{'dns_ok'=>false},'',28,0,3000,7000,300)
PhoneHealth.update(value,failure)
assert(value['last_exit_ip']=='203.0.113.11','failure must not erase last successful exit')
assert(failure['category']=='timeout'&&failure['checks'].last['ok'].nil?)
malformed=PhoneProbe.evaluate(group,{'dns_ok'=>true},'<secret>not an IP</secret>',0,200,1,1)
assert(!malformed['exit_ok']&&malformed['exit_ip'].nil?,'never display raw upstream response')
100.times{|i|PhoneHealth.update(value,good.merge('at'=>400+i))}
assert(value['history'].size==96)
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.write(PhoneHealth.file(1),value)
 assert(PhoneHealth.read(group)['history'].size==96,'checkpoints must round-trip without YAML alias failures')
 PhoneHealth.acknowledge(group,'203.0.113.10')
 assert(!PhoneHealth.read(group)['exit_changed'])
 rejects{PhoneHealth.acknowledge(group,'203.0.113.99')}
 assert(PhoneHealth.read(group.merge('node'=>'手机-02-示例'))['history'].empty?,'renamed/rebound node must not inherit another baseline')
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Health history, exit changes/acknowledgement, bounded persistence and diagnosis classification PASS'
