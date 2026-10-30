require_relative '../router/phone-dns/device-edit'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
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
