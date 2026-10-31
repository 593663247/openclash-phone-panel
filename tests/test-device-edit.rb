require_relative '../router/phone-dns/device-edit'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
binary="手机节点\n".b
revision=DeviceEdit.revision_data([binary],"节点前缀\n")
raise 'Unicode/binary fingerprint is unsafe' unless revision.encoding==Encoding::BINARY && revision.include?(binary)
raise 'Saved settings must invalidate preview' if revision==DeviceEdit.revision_data([binary],'changed')
def fixture
 cfg={'proxies'=>[{'name'=>'手机-01-示例'},{'name'=>'手机-02-示例'}],
 'rules'=>['SRC-IP-CIDR,192.168.1.101/32,手机-01-示例','MATCH,DIRECT']}
 mapping=[PhoneSettings.group(1,'手机-01-示例',['192.168.1.101']),PhoneSettings.group(2,'手机-02-示例')]
 [cfg,mapping,[{'ip'=>'192.168.1.101','name'=>'Old','group'=>1}]]
end
def edit(operation,extras={})
 DeviceEdit.transform(*fixture,{'ip'=>'192.168.1.101','operation'=>operation}.merge(extras))
end
renamed=edit('rename','name'=>'New')
raise unless renamed['devices'].first['name']=='New' && renamed['mapping'].first['ips']==['192.168.1.101']
rebound=edit('rebind','group'=>'2')
raise unless rebound['mapping'].first['ips'].empty? && rebound['mapping'][1]['ips']==['192.168.1.101']
raise unless rebound['devices'].first['group']==2 && rebound['config']['rules'].first.end_with?('手机-02-示例')
deleted=edit('delete')
raise unless deleted['devices'].empty? && deleted['mapping'].all?{|g|g['ips'].empty?} && deleted['config']['rules']==['MATCH,DIRECT']
[['rename',{'name'=>"bad\nname"}],['rebind',{'group'=>'999'}],['other',{}]].each do |op,extra|
 rejected=false;begin;edit(op,extra);rescue;rejected=true;end
 raise "Unsafe edit accepted: #{op}" unless rejected
end
cfg,mapping,devices=fixture;cfg['rules'].unshift(cfg['rules'].first)
rejected=false
begin;DeviceEdit.transform(cfg,mapping,devices,{'ip'=>'192.168.1.101','operation'=>'delete'});rescue;rejected=true;end
raise 'Ambiguous source rules accepted' unless rejected
puts 'Device rename, rebind, deletion and invalid edit rejection PASS'
changed=edit('change_ip','new_ip'=>'192.168.1.120')
raise unless changed['mapping'].first['ips']==['192.168.1.120'] && changed['devices'].first['ip']=='192.168.1.120'
raise unless changed['config']['rules'].first=='SRC-IP-CIDR,192.168.1.120/32,手机-01-示例'
raise unless changed['devices'].first['group']==1 && changed['devices'].first['name']=='Old'
%w[192.168.1.101 192.168.1.1 192.168.1.0 192.168.1.255 192.168.2.120 bad].each do |target|
 rejected=false;begin;edit('change_ip','new_ip'=>target);rescue;rejected=true;end
 raise "Invalid IP accepted: #{target}" unless rejected
end
cfg,mapping,devices=fixture;mapping[1]['ips']<<'192.168.1.120'
rejected=false;begin;DeviceEdit.transform(cfg,mapping,devices,{'ip'=>'192.168.1.101','operation'=>'change_ip','new_ip'=>'192.168.1.120'});rescue;rejected=true;end
raise 'Managed IP collision accepted' unless rejected
req={'ip'=>'192.168.1.101','new_ip'=>'192.168.1.120'}
host={'section'=>'cfg123abc','ip'=>req['ip'],'mac'=>'02:11:22:33:44:55'}
lease="#{Time.now.to_i+3600} #{host['mac']} #{req['ip']} phone *"
plan=DeviceEdit.ip_migration(req,[host],[lease],'')
raise unless plan['mac']==host['mac'] && plan['section']==host['section']
[
 [[],[], ''],
 [[host,host.dup],[], ''],
 [[host,{'section'=>'other','ip'=>req['new_ip'],'mac'=>'02:11:22:33:44:66'}],[], ''],
 [[host,{'section'=>'other','ip'=>'192.168.1.121','mac'=>host['mac']}],[], ''],
 [[host],["#{Time.now.to_i+3600} 02:11:22:33:44:66 #{req['new_ip']} phone *"], ''],
 [[host],["#{Time.now.to_i+3600} 02:11:22:33:44:66 #{req['ip']} phone *"], ''],
 [[host],[], "#{req['new_ip']} dev br-lan lladdr 02:11:22:33:44:66 STALE"]
].each do |hs,ls,ns|
 rejected=false;begin;DeviceEdit.ip_migration(req,hs,ls,ns);rescue;rejected=true;end
 raise 'Unsafe DHCP migration accepted' unless rejected
end
puts 'IP migration: preserves node/name, rejects invalid/managed addresses and DHCP/MAC/neighbor conflicts PASS'
raise unless DeviceEdit.dhcp_hostname('us-13')=='us-13'
raise unless DeviceEdit.dhcp_hostname('US-13')=='US-13'
['手机13','bad.name','bad name','-bad','bad-','a'*64,"bad\nname"].each{|n|raise 'Invalid DNS hostname accepted' if DeviceEdit.dhcp_hostname(n)}
raise unless DeviceEdit.name_lease(req['ip'],[host])['section']=='cfg123abc'
rejected=false;begin;DeviceEdit.name_lease(req['ip'],[host,host.dup]);rescue;rejected=true;end
raise 'Ambiguous DHCP name target accepted' unless rejected
puts 'DHCP hostname validation and unique static-lease selection PASS'

expected={'section'=>'phone_13','ip'=>'192.168.1.113','mac'=>'02:AA:BB:CC:DD:EE','name'=>'us-13'}
saved={'dhcp.phone_13'=>'host','dhcp.phone_13.ip'=>expected['ip'],'dhcp.phone_13.mac'=>expected['mac'].downcase,'dhcp.phone_13.name'=>'us-13'}
reader=lambda{|key|saved.fetch(key)}
raise unless DeviceEdit.verify_lease(expected,reader)['dhcp_static']
%w[ip mac name].each do |field|
 key='dhcp.phone_13.'+field;original=saved[key];saved[key]='incorrect'
 rejected=false
 begin;DeviceEdit.verify_lease(expected,reader);rescue;rejected=true;end
 raise "DHCP #{field} mismatch accepted" unless rejected
 saved[key]=original
end
raise unless DeviceEdit.verify_lease(nil,reader)=={}
puts 'Post-reload DHCP acceptance: IP, case-insensitive MAC and hostname mismatches rejected PASS'
