require_relative 'settings'
# Pure document transformation, separately tested; no DHCP identity is changed.
module DeviceEdit
 def self.transform(cfg,mapping,devices,req)
  operation=req.fetch('operation');ip=req.fetch('ip');raise 'Invalid IP' unless PhoneSettings.usable?(ip)
  raise 'Unsupported operation' unless %w[rename rebind delete].include?(operation)
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
  else
   # Explicitly releases this IP from panel protection, retaining its DHCP lease.
   rules.delete(matches.first);mapping.each{|g|g['ips'].delete(ip)};devices.reject!{|d|d['ip']==ip}
  end
  {'config'=>cfg,'mapping'=>mapping,'devices'=>devices}
 end
end
