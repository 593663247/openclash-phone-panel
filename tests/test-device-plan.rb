require_relative '../router/phone-dns/device-manager'

# Stub router reads only; exercise the production planner against a temporary YAML.
def source_path;@source;end
def catalog;@mapping;end
def hosts;@hosts;end
def active_dhcp_leases;PhoneSettings.active_leases(@leases);end
def quiet(*args);args==['uci','changes','phone_panel'] ? @pending_settings : '';end
def revision;'test-revision';end
def tracked;[@source];end
def rejects(message)
 begin;yield;rescue =>e;raise "Unexpected rejection: #{e.message}" unless e.message.include?(message);return;end
 raise "Expected rejection: #{message}"
end

PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
dir=File.join(Dir.pwd,".phone-panel-plan-#{Process.pid}-#{rand(1<<32)}")
Dir.mkdir(dir,0700)
begin
 @source=File.join(dir,'source.yaml')
 node='手机-01-示例'
 @mapping=[PhoneSettings.group(1,node)]
 @hosts=[];@leases=[];@pending_settings=''
 source={'proxies'=>[{'name'=>node}],'rules'=>['MATCH,DIRECT']}
 File.write(@source,source.to_yaml)
 request={'name'=>'Device','ip'=>'192.168.1.101','mac'=>'02:11:22:33:44:55','group'=>'1'}
 raise unless plan(request)['adopt_lease']==false
 host={'ip'=>request['ip'],'mac'=>request['mac']}
 @hosts=[host]
 raise unless plan(request)['adopt_lease']==true
 @hosts=[host,host.dup]
 rejects('重复静态租约'){plan(request)}
 @hosts=[host.merge('mac'=>request['mac']+' 02:11:22:33:44:66')]
 rejects('重复静态租约'){plan(request)}
 @hosts=[];@pending_settings='pending'
 rejects('未保存的面板设置'){plan(request)}
 @pending_settings=''
 source['rules']=['MATCH,DIRECT',"SRC-IP-CIDR,#{request['ip']}/32,#{node}"]
 File.write(@source,source.to_yaml)
 rejects('移至规则顶部'){plan(request)}
 source['rules'].reverse!;File.write(@source,source.to_yaml)
 raise unless plan(request)['node']==node
 @leases=[['1','02:11:22:33:44:66',request['ip'],'expired']]
 raise unless plan(request)['node']==node
 @leases=[['0','02:11:22:33:44:66',request['ip'],'active']]
 rejects('租给了其他设备'){plan(request)}
 @leases=[]
 before=revision_data
 PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate('bridge'=>'br-test'))
 raise 'settings must invalidate revision' if revision_data==before
 nft=nft_text([PhoneSettings.group(1,node,[request['ip']])],[host])
 raise 'guard must use configured bridge' unless nft.include?('iifname "br-test"') && !nft.include?('br-lan')
ensure
 File.delete(@source) if @source && File.file?(@source)
 Dir.rmdir(dir)
end
puts 'Device planner conflicts, rule precedence, settings revision and bridge guard PASS'
