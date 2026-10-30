require 'yaml'
module PhoneSettings
 DEFAULTS={'lan_cidr'=>'192.168.1.0/24','router_ip'=>'192.168.1.1','bridge'=>'br-lan','node_prefix'=>'手机-',
 'dns_base'=>'15300','socks_base'=>'18000','internal_base'=>'15400','max_groups'=>'100','controller_port'=>'9090',
 'upstream_primary'=>'8.8.8.8','upstream_secondary'=>'8.8.4.4','tls_name'=>'dns.google','fwmark'=>'0x162',
 'monitor_enabled'=>'1','sample_interval'=>'15','probe_interval'=>'900','traffic_daily_mb'=>'10240','traffic_rate_mbps'=>'50'}
 def self.ipnum(ip)
  a=ip.to_s.split('.');raise 'Invalid IPv4 address' unless a.size==4 && a.all?{|x|x.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && x.to_i<=255}
  a.inject(0){|n,x|(n<<8)+x.to_i}
 end
 def self.validate(input)
  v=DEFAULTS.merge(input.transform_keys(&:to_s).transform_values(&:to_s))
  cidr=v['lan_cidr'].split('/');raise 'CIDR prefix must be 8..30' unless cidr.size==2 && cidr[1].match?(/\A\d+\z/) && (8..30).include?(cidr[1].to_i)
  mask=((1<<32)-1)^((1<<(32-cidr[1].to_i))-1);net=ipnum(cidr[0]);raise 'Use canonical network CIDR' unless (net&mask)==net
  rip=ipnum(v['router_ip']);raise 'Router IP is not a usable LAN address' unless (rip&mask)==net && rip!=net && rip!=(net|(~mask&0xffffffff))
  raise 'Invalid bridge name' unless v['bridge'].match?(/\A[a-zA-Z0-9_.:-]{1,15}\z/)
  raise 'Invalid node prefix' unless (1..40).include?(v['node_prefix'].length) && !v['node_prefix'].match?(/[\x00-\x1f\x7f,]/)
  %w[dns_base socks_base internal_base max_groups controller_port].each{|k|raise "Invalid #{k}" unless v[k].match?(/\A[1-9][0-9]*\z/)}
  raise 'max_groups must be 1..100' unless (1..100).include?(v['max_groups'].to_i)
  n=v['max_groups'].to_i;ports=(1..n).flat_map{|i|[v['dns_base'].to_i+i,v['socks_base'].to_i+i,v['internal_base'].to_i+10*i+1,v['internal_base'].to_i+10*i+2]}+[v['controller_port'].to_i]
  raise 'Port ranges overlap or are invalid' unless ports.uniq.size==ports.size && ports.all?{|p|(1024..65535).include?(p)}
  %w[upstream_primary upstream_secondary].each{|k|ipnum(v[k])}
  raise 'Invalid TLS name' unless v['tls_name'].match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?\z/)
  raise 'Invalid fwmark' unless v['fwmark'].match?(/\A0x[0-9a-fA-F]{1,8}\z/)
  raise 'Invalid monitoring flag' unless %w[0 1].include?(v['monitor_enabled'])
  {'sample_interval'=>5..300,'probe_interval'=>60..86400,'traffic_daily_mb'=>1..1048576,'traffic_rate_mbps'=>1..100000}.each do |key,range|
   raise "Invalid #{key}" unless v[key].match?(/\A[1-9][0-9]*\z/) && range.include?(v[key].to_i)
  end
  v
 end
 def self.values
  @values ||= begin
   input={}
   if ENV['PHONE_PANEL_TEST_CONFIG']
    raise 'Test configuration requires PHONE_PANEL_TEST=1' unless ENV['PHONE_PANEL_TEST']=='1'
    input=YAML.load_file(ENV.fetch('PHONE_PANEL_TEST_CONFIG'))
   else
    raw=IO.popen(['uci','-q','export','phone_panel'],err:File::NULL,&:read)
    raw.each_line{|l|input[$1]=$2 if l =~ /^\s*option\s+(\w+)\s+'([^']*)'/}
   end
   validate(input)
  end
 end
 def self.[](k);values.fetch(k);end
 def self.port(k);self[k].to_i;end
 def self.phone?(name);name.to_s.start_with?(self['node_prefix']);end
 def self.usable?(ip)
  n=ipnum(ip);a,b=self['lan_cidr'].split('/');net=ipnum(a);size=1<<(32-b.to_i)
  n>net && n<net+size-1 && ip!=self['router_ip']
 rescue;false;end
 def self.group(id,node,ips=[])
  raise 'Group ID outside configured limit' unless (1..port('max_groups')).include?(id)
  {'id'=>id,'node'=>node,'ips'=>ips,'dns_port'=>port('dns_base')+id,'socks_port'=>port('socks_base')+id}
 end
 def self.active_leases(lines,now=Time.now.to_i)
  lines.map{|line|line.is_a?(Array) ? line : line.split}.select do |l|
   next false unless l.size>=4 && l[0].match?(/\A\d+\z/)
   next false unless l[0].to_i==0 || l[0].to_i>now
   next false unless l[1].match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/i)
   begin;ipnum(l[2]);true;rescue;false;end
  end
 end
 def self.lease_section(prefix,ip)
  ipnum(ip)
  prefix+'_'+ip.tr('.','_')
 end
 # Never return raw proxy log text: it can contain credentials and destination URLs.
 def self.warning_summary(line,ips)
  ip=ips.find{|address|line.include?(address+':')}
  return nil unless ip && line.match?(/level=(?:warning|error)\b/)
  time=line[/time="([0-9T:Z.+-]+)"/,1] || 'unknown time'
  reason=case line
   when /connection refused/i;'connection refused'
   when /username|password|authentication|unauthorized/i;'authentication failed'
   when /timeout|timed out|deadline exceeded/i;'connection timeout'
   when /no such host|dns.*failed/i;'DNS lookup failed'
   when /network is unreachable|no route to host/i;'network unreachable'
   else;'connection warning (inspect private router logs)'
  end
  time+' | '+ip+' | '+reason
 end
end
