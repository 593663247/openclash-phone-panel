require_relative '../router/phone-dns/auto-import'
n='手机-01-示例';c={'proxies'=>[{'name'=>n}],'rules'=>["SRC-IP-CIDR,192.168.1.171/32,#{n}","MATCH,DIRECT"]};h=[{'ip'=>'192.168.1.171','mac'=>'02:11:22:33:44:55','name'=>'device-01'}]
a,p=PhoneImport.plan(c,[],h,[]);raise unless a.size==1 && p.empty? && !a[0]['needs_lease']
a,p=PhoneImport.plan(c,[],[],[]);raise unless a.empty? && p.size==1
a,p=PhoneImport.plan(c,[],[],[['0','02:11:22:33:44:55','192.168.1.171','device-01']]);raise unless a.size==1 && a[0]['needs_lease']
a,p=PhoneImport.plan(c,[],h,[['0','02:00:00:00:00:01','192.168.1.171','x']]);raise unless a.empty? && p.size==1
a,p=PhoneImport.plan(c,[],h,[],true);raise unless a.empty? && p.size==1
c['rules'].unshift(c['rules'][0]);a,p=PhoneImport.plan(c,[],h,[]);raise unless a.empty? && p.size==1
puts '6 import planner cases PASS'
