require_relative 'panel-store'
module PhoneHealth
 LIMIT=96
 def self.file(id);PanelStore.state+"/health-#{PanelStore.group_id(id)}.yaml";end
 def self.identity(group);group.values_at('node','dns_port','socks_port');end
 def self.read(group)
  value=PanelStore.read(file(group['id']),{})
  value['identity']==identity(group) ? value : {'identity'=>identity(group),'history'=>[],'events'=>[]}
 end
 def self.update(value,result)
  value['history']=(value.fetch('history',[])+[result]).last(LIMIT)
  if result['exit_ok']
   current=result['exit_ip'];previous=value['last_exit_ip']
   value['acknowledged_ip']||=current
   if previous && previous!=current
    value['events']=(value.fetch('events',[])+[{'at'=>result['at'],'previous'=>previous,'current'=>current}]).last(24)
   end
   value['last_exit_ip']=current
  end
  value['last']=result
  value['exit_changed']=!!(value['last_exit_ip'] && value['last_exit_ip']!=value['acknowledged_ip'])
  value
 end
 def self.summary(group)
  data=read(group);history=data.fetch('history',[])
  good=history.count{|r|r['dns_ok']&&r['exit_ok']}
  {'last'=>data['last'],'exit_ip'=>data['last_exit_ip'],'exit_changed'=>data['exit_changed']==true,
   'baseline_ip'=>data['acknowledged_ip'],'events'=>data.fetch('events',[]),'history'=>history.last(24),
   'checks'=>history.size,'failures'=>history.size-good,'success_percent'=>history.empty? ? nil : (good*100.0/history.size).round(1)}
 end
 def self.acknowledge(group,expected_ip)
  PanelStore.with_lock(file(group['id'])+'.lock') do
   data=read(group)
   raise '出口状态已变化，请刷新后再确认' unless data['last_exit_ip'] && data['last_exit_ip']==expected_ip
   data['acknowledged_ip']=data['last_exit_ip'];data['exit_changed']=false
   PanelStore.write(file(group['id']),data)
  end
  {'ok'=>true}
 end
end

module PhoneProbe
 def self.evaluate(group,dns,curl_body,curl_code,http_code,dns_ms,exit_ms,now=Time.now.to_i)
  ip=curl_body.to_s.strip
  valid_ip=begin;PhoneSettings.ipnum(ip);true;rescue;false;end
  exit_ok=curl_code==0 && http_code==200 && valid_ip
  category=if !group['socks_listening'];'socks_not_listening'
   elsif !group['binding_ok'];'binding_mismatch'
   elsif curl_code==28;'timeout'
   elsif curl_code==97;'proxy_or_auth_failed'
   elsif curl_code==60;'tls_failed'
   elsif !exit_ok;'egress_failed'
   elsif !dns['dns_ok'];'dns_failed'
   else;'ok';end
  checks=[{'layer'=>'DNS 入口','ok'=>group['dns_listening']==true},
   {'layer'=>'SOCKS 入口','ok'=>dns['socks_tcp_ok']==true},
   {'layer'=>'节点绑定','ok'=>group['binding_ok']==true},
   {'layer'=>'DNS 实际解析','ok'=>dns['dns_ok']==true,'ms'=>dns_ms},
   {'layer'=>'代理 HTTPS 出口','ok'=>exit_ok,'ms'=>exit_ms},
   {'layer'=>'UDP 业务','ok'=>nil,'note'=>'未测试 UDP ASSOCIATE，不据此判断业务可用'}]
  {'id'=>group['id'],'at'=>now,'time'=>Time.at(now).strftime('%Y-%m-%d %H:%M:%S %z'),
   'dns_ok'=>dns['dns_ok']==true,'exit_ok'=>exit_ok,'exit_ip'=>exit_ok ? ip : nil,
   'dns_ms'=>dns_ms,'exit_ms'=>exit_ms,'category'=>category,'checks'=>checks}
 end
 def self.run(group)
  id=PanelStore.group_id(group['id'])
  result=PanelStore.with_lock(PhoneHealth.file(id)+'.probe-lock',true) do
   start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
   raw,code=PanelStore.capture('lua',PanelStore.path('/etc/phone-dns/probe-dns.lua'),group['dns_port'].to_s,group['socks_port'].to_s)
   dns=code==0 ? (YAML.safe_load(raw) rescue {}) : {}
   dns={} unless dns.is_a?(Hash)
   dns_ms=((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round
   start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
   output,curl_code=PanelStore.capture('curl','--noproxy','','--socks5-hostname',"127.0.0.1:#{group['socks_port']}",
    '-fsS','--connect-timeout','3','--max-time','7','-w',"\n%{http_code}",'https://api.ipify.org')
   exit_ms=((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round
   body,_,http=output.rpartition("\n")
   result=evaluate(group,dns,body,curl_code,http.to_i,dns_ms,exit_ms)
   PanelStore.with_lock(PhoneHealth.file(id)+'.lock') do
    PanelStore.write(PhoneHealth.file(id),PhoneHealth.update(PhoneHealth.read(group),result))
   end
   result
  end
  result || (PhoneHealth.read(group)['last']||{'id'=>id,'error'=>'该组正在检测，请稍后刷新'}).merge('busy'=>true)
 end
end
