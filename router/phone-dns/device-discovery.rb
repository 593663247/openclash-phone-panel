require_relative 'panel-store'
require_relative 'auto-import'
module PhoneDiscovery
 def self.candidates(leases,hosts,managed)
  leases=PhoneSettings.active_leases(leases)
  leases.group_by{|l|l[2]}.filter_map do |ip,rows|
   next if managed.include?(ip) || !PhoneSettings.usable?(ip)
   macs=rows.map{|l|l[1].downcase}.uniq;mac=macs.first
   static=hosts.select{|h|h['ip']==ip}
   reason=nil
   reason='同一 IP 存在多个租约 MAC' if macs.size!=1
   reason||='同一 MAC 当前租给多个 IP' if leases.any?{|l|l[1].downcase==mac && l[2]!=ip}
   reason||='与静态租约冲突，请先处理 DHCP' if static.size>1 || static.any?{|h|h.fetch('mac','').downcase.split!=[mac]} || hosts.any?{|h|h['ip']!=ip && h.fetch('mac','').downcase.split.include?(mac)}
   name=(static.first.to_h['name'] || rows.first[3]).to_s
   name='phone-'+ip.tr('.','-') if name.empty? || name=='*' || name.match?(/[\x00-\x1f\x7f]/)
   {'ip'=>ip,'mac'=>mac,'name'=>name[0,40],'conflict'=>reason}
  end.sort_by{|d|PhoneSettings.ipnum(d['ip'])}.first(256)
 end
 def self.available
  leases=File.readlines('/tmp/dhcp.leases') rescue []
  mapping=YAML.safe_load(File.read('/etc/phone-dns/mapping.yaml'))||[]
  {'devices'=>candidates(leases,PhoneImport.hosts,mapping.flat_map{|g|g['ips']})}
 end
end
