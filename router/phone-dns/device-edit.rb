require_relative 'settings'
# Pure document transformation; DHCP migration is validated separately.
module DeviceEdit
 def self.revision_data(parts,saved_settings='')
  PhoneSettings.values.to_yaml.b+"\0".b+saved_settings.b+"\0".b+parts.map(&:b).join("\0".b)
 end
 def self.dhcp_hostname(name)
  name=name.to_s.strip
  name.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/) ? name : nil
 end
 def self.name_lease(ip,sections)
  owners=sections.select{|h|h['ip']==ip}
  raise '名称同步需要唯一的 DHCP 静态租约' unless owners.size==1
  owner=owners.first
  raise '租约标识无效' unless owner.fetch('section','').match?(/\A(?:[a-zA-Z0-9_]+|@host\[\d+\])\z/)
  owner
 end
 def self.verify_lease(expected,reader)
  return {} unless expected
  section=expected.fetch('section')
  raise '租约标识无效' unless section.match?(/\A(?:[a-zA-Z0-9_]+|@host\[\d+\])\z/)
  raise '静态租约配置段未生效' unless reader.call("dhcp.#{section}").strip=='host'
  %w[ip mac name].each do |key|
   next unless expected.key?(key)
   actual=reader.call("dhcp.#{section}.#{key}").strip
   wanted=expected.fetch(key).to_s
   actual=actual.downcase.split.sort.join(' ') if key=='mac'
   wanted=wanted.downcase.split.sort.join(' ') if key=='mac'
   raise "静态租约 #{key} 验收失败，请检查恢复结果" unless actual==wanted
  end
  {'dhcp_static'=>true,'device_lease'=>'未验证手机是否已获取新租约，请重连 Wi-Fi 后确认'}
 end
 # sections contain explicit UCI section identifiers, never caller-supplied paths.
 def self.ip_migration(req,sections,leases,neighbors)
  old=req.fetch('ip');target=req.fetch('new_ip').to_s.strip
  raise '新 IP 无效或与旧 IP 相同' unless PhoneSettings.usable?(target) && target!=old
  owners=sections.select{|h|h['ip']==old}
  raise '旧 IP 必须有唯一静态租约' unless owners.size==1
  owner=owners.first;macs=owner.fetch('mac','').downcase.split
  raise '旧租约必须只包含一个有效 MAC' unless macs.size==1 && macs.first.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/) && macs.first!='00:00:00:00:00:00' && macs.first[0,2].to_i(16).even?
  mac=macs.first
  raise '租约标识无效' unless owner.fetch('section','').match?(/\A(?:[a-zA-Z0-9_]+|@host\[\d+\])\z/)
  raise '新 IP 已有静态租约或 MAC 与其他租约冲突' if sections.any?{|h|h!=owner && (h['ip']==target || h.fetch('mac','').downcase.split.include?(mac))}
  active=PhoneSettings.active_leases(leases)
  raise '新 IP 当前仍有 DHCP 租约，请等租约释放或换地址' if active.any?{|l|l[2]==target}
  raise '设备 MAC 与当前 DHCP 租约不一致' if active.any?{|l|(l[2]==old && l[1].downcase!=mac)||(l[1].downcase==mac && l[2]!=old)}
  neighbors.each_line do |line|
   a=line.split
   raise '新 IP 在邻居表中仍被占用' if a.first==target && a.include?('lladdr')
  end
  {'section'=>owner['section'],'mac'=>mac,'old_ip'=>old,'new_ip'=>target}
 end
 def self.transform(cfg,mapping,devices,req)
  operation=req.fetch('operation');ip=req.fetch('ip');raise 'Invalid IP' unless PhoneSettings.usable?(ip)
  raise 'Unsupported operation' unless %w[rename rebind delete change_ip].include?(operation)
  current=mapping.find{|g|g.fetch('ips',[]).include?(ip)};raise 'Unmanaged device' unless current
  rules=cfg.fetch('rules');matches=rules.select{|r|r.start_with?("SRC-IP-CIDR,#{ip}/32,")};raise 'Ambiguous source rule' unless matches.size==1
  if operation=='rename'
   name=req.fetch('name').strip;raise 'Invalid name' unless (1..40).include?(name.length) && !name.match?(/[\x00-\x1f\x7f]/)
   d=devices.find{|x|x['ip']==ip};unless d;d={'ip'=>ip};devices<<d;end;d['name']=name
  elsif operation=='rebind'
   target=mapping.find{|g|g['id'].to_s==req['group'].to_s};raise 'Node missing' unless target && (cfg['proxies']||[]).any?{|n|n['name']==target['node']}
   rules[rules.index(matches.first)]="SRC-IP-CIDR,#{ip}/32,#{target['node']}"
   mapping.each{|g|g['ips'].delete(ip)};target['ips']<<ip
   devices.each{|d|d['group']=target['id'] if d['ip']==ip}
  elsif operation=='change_ip'
   target=req.fetch('new_ip').to_s.strip
   raise '新 IP 必须是网段内可用地址，且不能与旧 IP 相同' unless PhoneSettings.usable?(target) && target!=ip
   raise '新 IP 已纳管' if mapping.any?{|g|g.fetch('ips',[]).include?(target)} || devices.any?{|d|d['ip']==target}
   raise '新 IP 已有来源绑定规则' if rules.any?{|r|r.to_s.start_with?("SRC-IP-CIDR,#{target}/32,")}
   raise '旧 IP 存在重复分组' unless mapping.count{|g|g.fetch('ips',[]).include?(ip)}==1
   rules[rules.index(matches.first)]=matches.first.sub("SRC-IP-CIDR,#{ip}/32,","SRC-IP-CIDR,#{target}/32,")
   current['ips'][current['ips'].index(ip)]=target
   devices.each{|d|d['ip']=target if d['ip']==ip}
  else
   # Explicitly releases this IP from panel protection, retaining its DHCP lease.
   rules.delete(matches.first);mapping.each{|g|g['ips'].delete(ip)};devices.reject!{|d|d['ip']==ip}
  end
  {'config'=>cfg,'mapping'=>mapping,'devices'=>devices}
 end
end
