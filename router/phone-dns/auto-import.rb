require_relative 'settings'
require 'yaml'
module PhoneImport
 def self.plan(cfg,mapping,hosts,leases,pending_changes=false)
  leases=PhoneSettings.active_leases(leases)
  nodes=(cfg['proxies']||[]).map{|n|n['name']}.select{|name|PhoneSettings.phone?(name)}
  candidates=(cfg['rules']||[]).map do |r|
   a=r.to_s.split(',');next unless a[0]=='SRC-IP-CIDR' && a[1].to_s.end_with?('/32') && nodes.include?(a[2])
   ip=a[1].split('/')[0];next unless PhoneSettings.usable?(ip)
   [ip,a[2]]
  end
  candidates.compact!
  managed=mapping.flat_map{|g|g['ips']};accepted=[];pending=[]
  candidates.map(&:first).uniq.each do |ip|
   next if managed.include?(ip)
   node=candidates.find{|a|a[0]==ip}[1];reason=nil
   all=(cfg['rules']||[]).select{|r|r.to_s.start_with?("SRC-IP-CIDR,#{ip}/32,")}
   reason='来源规则重复，请保留唯一绑定' unless all.size==1
   idx=(cfg['rules']||[]).index(all.first);first_other=(cfg['rules']||[]).index{|r|!r.to_s.start_with?('SRC-IP-CIDR,')}
   reason='来源绑定位于其他规则之后，请移至规则顶部' if first_other && idx && idx>first_other
   reason='存在尚未保存的 DHCP 修改' if pending_changes
   hs=hosts.select{|h|h['ip']==ip};ls=leases.select{|l|l[2]==ip}
   macs=hs.flat_map{|h|h.fetch('mac','').downcase.split}.uniq
   reason='静态租约存在多个 MAC 或重复 IP' if hs.size>1 || macs.size>1
   mac=macs.first || ls.map{|l|l[1].downcase}.uniq.then{|a|a.size==1 ? a.first : nil}
   reason||='未找到唯一 MAC，请添加静态租约或让手机联网后重新应用' unless mac
   if mac
    reason||='MAC 无效或为组播地址' unless mac.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/) && mac!='00:00:00:00:00:00' && mac[0,2].to_i(16).even?
    reason||='MAC 与其他静态 IP 冲突' if hosts.any?{|h|h['ip']!=ip && h.fetch('mac','').downcase.split.include?(mac)}
    reason||='当前 DHCP 租约与绑定不一致' if leases.any?{|l|(l[2]==ip && l[1].downcase!=mac)||(l[1].downcase==mac && l[2]!=ip)}
   end
   if reason;pending<<{'ip'=>ip,'node'=>node,'reason'=>reason};next;end
   name=hs.first.to_h['name'] || ls.first.to_a[3] || 'phone-'+ip.split('.').last
   name='phone-'+ip.split('.').last if name=='*' || name.match?(/[\x00-\x1f\x7f]/)
   accepted<<{'ip'=>ip,'node'=>node,'mac'=>mac,'name'=>name,'needs_lease'=>hs.empty?}
  end
  [accepted,pending]
 end
 def self.hosts
  hs=[];h=nil
  IO.popen(['uci','export','dhcp'],&:read).each_line do |l|
   if l =~ /^config\s+(\w+)/;h=$1=='host' ? {} : nil;hs<<h if h
   elsif h && l =~ /^\s*(?:option|list)\s+(\w+)\s+'([^']*)'/;h[$1]=[h[$1],$2].compact.join(' ');end
  end;hs
 end
 def self.run(cfg,mapping)
  base='/etc/phone-dns';hs=hosts
  ls=PhoneSettings.active_leases((File.readlines('/tmp/dhcp.leases') rescue []))
  changes=IO.popen(['uci','changes','dhcp'],&:read).strip
  accepted,pending=plan(cfg,mapping,hs,ls,!changes.empty?)
  devices=File.exist?(base+'/devices.yaml') ? (YAML.load_file(base+'/devices.yaml')||[]) : []
  accepted.each do |d|
   if d['needs_lease']
    sec=PhoneSettings.lease_section('phone_import',d['ip'])
    used=IO.popen(['uci','-q','get','dhcp.'+sec],err:File::NULL,&:read).strip
    if !used.empty?;pending<<d.slice('ip','node').merge('reason'=>'自动租约段名冲突');next;end
    args=[["dhcp.#{sec}=host"],["dhcp.#{sec}.ip=#{d['ip']}"],["dhcp.#{sec}.mac=#{d['mac']}"],["dhcp.#{sec}.name=phone-#{d['ip'].split('.').last}"]]
    args.each{|a|raise '创建静态租约失败' unless system('uci','set',*a)}
    raise '保存静态租约失败' unless system('uci','commit','dhcp')
   end
   g=mapping.find{|x|x['node']==d['node']}
   unless g
    id=PhoneSettings.next_group_id(mapping)
    g={'id'=>id,'node'=>d['node'],'ips'=>[],'dns_port'=>PhoneSettings.port('dns_base')+id,'socks_port'=>PhoneSettings.port('socks_base')+id};mapping<<g
   end
   g['ips']<<d['ip'];devices.reject!{|x|x['ip']==d['ip']};devices<<d.slice('ip','mac','name').merge('group'=>g['id'],'source'=>'auto-import')
  end
  File.write(base+'/devices.yaml',devices.to_yaml)
  File.write(base+'/import-status.yaml',{'time'=>Time.now.to_s,'pending'=>pending}.to_yaml)
  mapping
 end
end
