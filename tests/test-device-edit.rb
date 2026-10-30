require_relative '../router/phone-dns/device-edit'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
def fixture
 [{'rules'=>['SRC-IP-CIDR,192.168.1.101/32,手机-A'],'proxies'=>[{'name'=>'手机-A'},{'name'=>'手机-B'}]},[{'id'=>1,'node'=>'手机-A','ips'=>['192.168.1.101']},{'id'=>2,'node'=>'手机-B','ips'=>[]}],[]]
end
r=DeviceEdit.transform(*fixture,{'operation'=>'rebind','ip'=>'192.168.1.101','group'=>'2'});raise unless r['config']['rules'][0].end_with?('手机-B') && r['mapping'][1]['ips'].size==1
r=DeviceEdit.transform(*fixture,{'operation'=>'delete','ip'=>'192.168.1.101'});raise unless r['config']['rules'].empty? && r['mapping'].all?{|g|g['ips'].empty?}
r=DeviceEdit.transform(*fixture,{'operation'=>'rename','ip'=>'192.168.1.101','name'=>'example'});raise unless r['devices'][0]['name']=='example'
begin;DeviceEdit.transform(*fixture,{'operation'=>'delete','ip'=>'192.168.1.102'});raise 'accepted unmanaged';rescue RuntimeError=>e;raise if e.message=='accepted unmanaged';end
puts '4 device transformation cases PASS'
