require_relative 'panel-store'

module PhoneTelemetry
 REGIONS={'美国'=>/纽约|美国|洛杉矶|西雅图|芝加哥|\bUS\b|New.?York/i,'法国'=>/法国|巴黎|\bFR\b|France/i,
 '英国'=>/英国|伦敦|\bUK\b|London/i,'墨西哥'=>/墨西哥|Mexico|\bMX\b/i,'日本'=>/日本|东京|Japan|\bJP\b/i,
 '德国'=>/德国|法兰克福|Germany|\bDE\b/i,'新加坡'=>/新加坡|Singapore|\bSG\b/i,'加拿大'=>/加拿大|Canada|\bCA\b/i}
 def self.region(name);(REGIONS.find{|_,pattern|name.to_s.match?(pattern)}||['未分类']).first;end
 def self.neighbors(text)
  text.each_line.each_with_object({}) do |line,result|
   fields=line.split;ip=fields.first
   next unless PhoneSettings.usable?(ip)
   state=fields.find{|s|%w[REACHABLE STALE DELAY PROBE FAILED INCOMPLETE PERMANENT NOARP].include?(s)}
   result[ip]=state || 'UNKNOWN'
  end
 end
 def self.online(connections,neighbor,last_seen,now)
  return ['active','有活动连接',now] if connections.to_i>0
  return ['active','邻居近期可达',now] if neighbor=='REACHABLE'
  return ['recent','近期可达，当前待确认',last_seen] if last_seen.to_i>0 && now-last_seen.to_i<=120
  return ['offline','邻居探测失败',last_seen] if %w[FAILED INCOMPLETE].include?(neighbor)
  ['unknown','未确认在线',last_seen]
 end
 # Observe other LAN devices without creating proxy bindings or DHCP entries.
 def self.lan_devices(leases,hosts,neighbors,managed)
  excluded_ips=managed.map{|p|p['ip']};excluded_macs=managed.map{|p|p['mac'].to_s.downcase}.reject(&:empty?)
  active=PhoneSettings.active_leases(leases)
  rows=active.map{|l|{'ip'=>l[2],'mac'=>l[1].downcase,'hostname'=>l[3],'source'=>'DHCP 租约'}}
  hosts.each do |h|
   macs=h.fetch('mac','').downcase.split;next unless macs.size==1
   next if active.any?{|l|l[1].downcase==macs.first&&l[2]!=h['ip']}
   rows<<{'ip'=>h['ip'],'mac'=>macs.first,'hostname'=>h['name'],'source'=>'静态租约'}
  end
  neighbors.each_line do |line|
   fields=line.split;index=fields.index('lladdr');next unless index
   rows<<{'ip'=>fields.first,'mac'=>fields[index+1].to_s.downcase,'source'=>'邻居表'}
  end
  states=self.neighbors(neighbors)
  rows=rows.select{|r|PhoneSettings.usable?(r['ip'])&&r['mac'].match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/)&&r['mac']!='00:00:00:00:00:00'&&!excluded_ips.include?(r['ip'])&&!excluded_macs.include?(r['mac'])}
  rows.group_by{|r|r['ip']}.filter_map do |ip,items|
   next if items.map{|r|r['mac']}.uniq.size!=1
   mac=items.first['mac'];next if rows.any?{|r|r['mac']==mac&&r['ip']!=ip}
   label=items.map{|r|r['hostname'].to_s}.find{|v|!v.empty?&&v!='*'&&!v.match?(/[\x00-\x1f\x7f]/)}
   items.first.merge('hostname'=>(label||'未命名设备')[0,80],'neighbor'=>states[ip],'connections'=>0)
  end.sort_by{|r|PhoneSettings.ipnum(r['ip'])}.first(256)
 end
 def self.tick(state,phones,counters,now,boot)
  state={'started_at'=>now,'devices'=>{}} unless state.is_a?(Hash) && state['devices'].is_a?(Hash)
  day=Time.at(now).strftime('%Y-%m-%d');month=day[0,7]
  phones.each do |phone|
   ip=phone['ip'];d=state['devices'][ip];identity=phone['mac'].to_s.downcase
   d=nil if d && d['mac'] && !identity.empty? && d['mac']!=identity
   d=state['devices'][ip]=d||{'days'=>{},'months'=>{},'last_seen'=>0}
   d['mac']=identity unless identity.empty?
   row=counters && counters[ip]
   elapsed=now-d.fetch('counter_at',now).to_i
   same_boot=d['counter_boot']==boot
   valid=row && elapsed>0 && same_boot && d['counter']
   delta={'up'=>0,'down'=>0}
   if valid
    %w[up down].each do |key|
     current=row[key].to_i;previous=d['counter'][key].to_i
     delta[key]=current>=previous ? current-previous : current
     d['counter_resets']=d.fetch('counter_resets',0)+1 if current<previous
    end
   end
   [d['days'][day]||={'up'=>0,'down'=>0},d['months'][month]||={'up'=>0,'down'=>0}].each do |bucket|
    %w[up down].each{|key|bucket[key]+=delta[key]}
   end
   if row;d['counter']=row;d['counter_at']=now;d['counter_boot']=boot;end
   d['available']=!row.nil?
   d['rate_up']=valid && elapsed<=600 ? delta['up'].to_f/elapsed : nil
   d['rate_down']=valid && elapsed<=600 ? delta['down'].to_f/elapsed : nil
   _,_,seen=online(phone['connections'],phone['neighbor'],d['last_seen'],now)
   d['last_seen']=seen.to_i
   d['days']=d['days'].sort.last(35).to_h;d['months']=d['months'].sort.last(13).to_h
  end
  # Retain recent totals for removed devices for 35 days, without unbounded growth.
  managed=phones.map{|p|p['ip']}
  state['devices'].delete_if{|ip,d|!managed.include?(ip) && now-d.fetch('last_seen',0).to_i>35*86400}
  state.merge('sample_at'=>now,'boot'=>boot,'counter_available'=>!counters.nil?)
 end
 def self.decorate(groups,now=Time.now.to_i)
  state=PanelStore.read(PanelStore.ram+'/metrics.yaml',{})
  state=PanelStore.read(PanelStore.state+'/traffic.yaml',{}) if state.empty?
  enabled=PhoneSettings['monitor_enabled']=='1'
  sample_at=state.fetch('sample_at',0).to_i;fresh=enabled && sample_at>0 && now-sample_at<=PhoneSettings.port('sample_interval')*3+30
  day=Time.at(now).strftime('%Y-%m-%d');month=day[0,7]
  groups.each do |group|
   group['region']=region(group['node'])
   group['phones'].each do |phone|
    d=state.fetch('devices',{}).fetch(phone['ip'],{})
    d={} if !phone['mac'].to_s.empty?&&d['mac']&&d['mac']!=phone['mac'].downcase
    key,evidence,seen=online(phone['connections'],phone['neighbor'],d['last_seen'],now)
    phone.merge!('online_state'=>key,'online_evidence'=>evidence,'last_seen'=>seen.to_i,'node'=>group['node'],'group'=>group['id'],'region'=>group['region'])
    today=d.fetch('days',{}).fetch(day,{'up'=>0,'down'=>0});monthly=d.fetch('months',{}).fetch(month,{'up'=>0,'down'=>0})
    available=d['available']==true && fresh
    phone['traffic']={'available'=>available,'sample_at'=>sample_at,'started_at'=>state['started_at'],'today'=>today,'month'=>monthly,
     'today_available'=>d.fetch('counter_at',0).to_i>0&&d.fetch('days',{}).key?(day),'month_available'=>d.fetch('counter_at',0).to_i>0&&d.fetch('months',{}).key?(month),
     'rate_up'=>available ? d['rate_up'] : nil,'rate_down'=>available ? d['rate_down'] : nil,
     'alert'=>(today.values.sum>=PhoneSettings.port('traffic_daily_mb')*1048576 || (available && [d['rate_up'].to_f,d['rate_down'].to_f].max*8>=PhoneSettings.port('traffic_rate_mbps')*1000000))}
   end
  end
  {'enabled'=>enabled,'sample_at'=>sample_at,'fresh'=>fresh,'started_at'=>state['started_at'],'counter_available'=>fresh && state['counter_available']==true,
   'note'=>'IPv4 路由器收发字节，从启用监测开始累计；硬件/流量卸载可能漏计转发流量，不包含手机外部 IPv6。'}
 end
end

module PhoneCounters
 TABLE='phone_panel_stats'
 def self.read
  text,code=PanelStore.capture('nft','-j','list','table','inet',TABLE)
  return nil unless code==0
  values=YAML.safe_load(text).fetch('nftables',[])
  result={}
  values.each do |item|
   counter=item['counter'];next unless counter && counter['name'].to_s.match?(/\A(up|down)_\d+_\d+_\d+_\d+\z/)
   direction,*parts=counter['name'].split('_');ip=parts.join('.')
   (result[ip]||={'up'=>0,'down'=>0})[direction]=counter['bytes'].to_i
  end
  result
 rescue Psych::Exception,NoMethodError
  nil
 end
 def self.script(ips,bridge,existing)
  raise 'Invalid statistics interface' unless bridge.match?(/\A[a-zA-Z0-9_.:-]{1,15}\z/)
  raise 'Invalid statistics IP' unless ips.all?{|ip|PhoneSettings.usable?(ip)}
  lines=[]
  if existing.nil?
   lines<<"add table inet #{TABLE}"
   lines<<"add chain inet #{TABLE} upload { type filter hook prerouting priority -300; policy accept; }"
   lines<<"add chain inet #{TABLE} download { type filter hook postrouting priority 300; policy accept; }"
  else
   lines<<"flush chain inet #{TABLE} upload"<<"flush chain inet #{TABLE} download"
   (existing.keys-ips).each do |ip|
    %w[up down].each{|direction|lines<<"delete counter inet #{TABLE} #{direction}_#{ip.tr('.','_')}"}
   end
  end
  ips.uniq.sort.each do |ip|
   %w[up down].each do |direction|
    name=direction+'_'+ip.tr('.','_')
    lines<<"add counter inet #{TABLE} #{name}" unless existing && existing.key?(ip)
    chain=direction=='up' ? 'upload' : 'download'
    match=direction=='up' ? "iifname \"#{bridge}\" ip saddr #{ip}" : "oifname \"#{bridge}\" ip daddr #{ip}"
    lines<<"add rule inet #{TABLE} #{chain} #{match} counter name #{name}"
   end
  end
  lines.join("\n")+"\n"
 end
 def self.sync(ips)
  text=script(ips,PhoneSettings['bridge'],read)
  [['nft','-c','-f','-'],['nft','-f','-']].each do |args|
   IO.popen(args+[{err:File::NULL}],'w'){|io|io.write(text)}
   raise 'Statistics counters could not be installed' unless $?.success?
  end
 end
end
