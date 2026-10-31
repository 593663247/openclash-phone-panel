require_relative 'settings'
require_relative 'device-edit'
require_relative 'apply-engine'
require_relative 'panel-store'
def ip_elements(ips)
 a=ips.map{|ip|ip.split('.').map(&:to_i).inject(0){|n,v|n*256+v}}.uniq.sort
 ranges=[];a.each{|n|if ranges.last && ranges.last[1]+1==n; ranges.last[1]=n;else;ranges<<[n,n];end}
 fmt=->(n){[24,16,8,0].map{|b|(n>>b)&255}.join('.')}
 ranges.map{|x,y|x==y ? fmt.call(x) : fmt.call(x)+'-'+fmt.call(y)}.join(', ')
end
require 'yaml'
BASE=PanelStore.path('/etc/phone-dns')
JOBS=BASE+'/jobs'
def json(x)
 case x
 when Hash;'{'+x.map{|k,v|json(k.to_s)+':'+json(v)}.join(',')+'}'
 when Array;'['+x.map{|v|json(v)}.join(',')+']'
 when String;'"'+x.gsub(/["\\\x00-\x1f]/){|c|c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
 when TrueClass;'true';when FalseClass;'false';when NilClass;'null';else;x.to_s;end
end
def atomic(path,data)
 PhoneApply.atomic(path,data)
end
def run(*args)
 o=IO.popen(args+[{err:[:child,:out]}],&:read)
 status=$?.exitstatus
 if @command_log
  File.open(@command_log,File::WRONLY|File::CREAT|File::APPEND,0600){|f|
   f.puts("[#{Time.now.utc}] #{args.first} exit=#{status}");f.write(o);f.puts
  }
 end
 raise "命令执行失败：#{args.first}（exit=#{status}，详细输出仅保存在路由器私密诊断日志）" unless status==0
 o
end
def quiet(*args)
 IO.popen(args+[{err:File::NULL}],&:read).to_s
end
def source_path
 p=quiet('uci','-q','get','openclash.config.config_path').strip
 raise '当前配置路径不在 OpenClash 配置目录中' unless p.start_with?('/etc/openclash/config/') && p.end_with?('.yaml') && !p.include?('..')
 p
end
def router_path(path);PanelStore.path(path);end

def tracked
 [source_path,router_path('/etc/config/dhcp'),BASE+'/mapping.yaml',BASE+'/devices.yaml',router_path('/etc/nftables.d/90-phone-fixed-egress.nft'),BASE+'/config.json',BASE+'/listeners.yaml']+Dir.glob(BASE+'/group-*.conf')
end
def revision_data
 s=PhoneSettings.values.to_yaml+"\0"+(File.exist?(router_path('/etc/config/phone_panel')) ? File.read(router_path('/etc/config/phone_panel')) : '')+"\0"+tracked.map{|p|p+"\0"+(File.exist?(p) ? File.read(p) : '')}.join("\0")
 s
end

def revision
 IO.popen(['sha256sum'],'r+') {|i|i.write(revision_data);i.close_write;i.read.split.first}
end
def hosts
 out=[];h=nil
 quiet('uci','export','dhcp').each_line do |l|
  if l =~ /^config\s+(\w+)(?:\s+'([^']+)')?/
   h=$1=='host' ? {} : nil;out<<h if h
  elsif h && l =~ /^\s*(?:option|list)\s+(\w+)\s+'([^']*)'/
   h[$1]=[h[$1],$2].compact.join(' ')
  end
 end
 out
end
def valid_input(req)
 raise '请求格式无效' unless req.is_a?(Hash)
 name=req['name'].to_s.strip;ip=req['ip'].to_s.strip;mac=req['mac'].to_s.strip.downcase;gid=req['group'].to_s
 raise '设备名称需要 1～40 个字符，不能包含控制字符' unless (1..40).include?(name.length) && !name.match?(/[\x00-\x1f\x7f]/)
 raise '固定 IP 必须位于配置网段内，且不能是路由器、网络或广播地址' unless PhoneSettings.usable?(ip)
 raise 'MAC 地址格式无效，请填写六组十六进制（冒号分隔）' unless mac.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/)
 raise '不能使用组播、广播或全零 MAC' if mac=='00:00:00:00:00:00' || mac[0,2].to_i(16).odd?
 raise '请选择已有独立 DNS 分组' unless gid.match?(/\A[1-9][0-9]{0,2}\z/) && gid.to_i<=PhoneSettings.port('max_groups')
 {'name'=>name,'ip'=>ip,'mac'=>mac,'group'=>gid.to_i}
end
def catalog
 mapping=YAML.load_file(BASE+'/mapping.yaml')
 source=YAML.load_file(source_path,aliases:true)
 names=(source['proxies']||[]).map{|n|n['name']}.select{|name|PhoneSettings.phone?(name)}.uniq
 id=mapping.map{|g|g['id']}.max.to_i
 names.each do |name|
  next if mapping.any?{|g|g['node']==name}
  id+=1;raise '手机节点数量超过支持范围' if id>PhoneSettings.port('max_groups')
  mapping<<{'id'=>id,'node'=>name,'ips'=>[],'dns_port'=>PhoneSettings.port('dns_base')+id,'socks_port'=>PhoneSettings.port('socks_base')+id}
 end
 mapping
end
def active_dhcp_leases
 PhoneSettings.active_leases(File.readlines(router_path('/tmp/dhcp.leases')))
rescue Errno::ENOENT
 []
end

def plan(req)
 d=valid_input(req)
 raise '存在未保存的 DHCP 配置，请先保存或撤销后重试' unless quiet('uci','changes','dhcp').strip.empty?
 raise '存在未保存的面板设置，请先保存或撤销后重试' unless quiet('uci','changes','phone_panel').strip.empty?
 mapping=catalog;g=mapping.find{|x|x['id']==d['group']};raise 'DNS 分组不存在' unless g
 raise '该 IP 已在面板管理范围内，请勿重复添加' if mapping.any?{|x|x['ips'].include?(d['ip'])}
 source=YAML.load_file(source_path,aliases:true)
 existing=(source['rules']||[]).select{|r|r.start_with?('SRC-IP-CIDR,') && r.split(',')[1]==d['ip']+'/32'}
 raise '已有来源规则重复或绑定了其他节点' unless existing.empty? || (existing.size==1 && existing.first.split(',')[2]==g['node'])
 raise '所选节点已不存在' unless (source['proxies']||[]).any?{|n|n['name']==g['node']}
 unless existing.empty?
  first_other=(source['rules']||[]).index{|r|!r.to_s.start_with?('SRC-IP-CIDR,')}
  raise '来源绑定位于其他规则之后，请移至规则顶部' if first_other && source['rules'].index(existing.first)>first_other
 end
 hs=hosts;adopt=false;matches=0
 hs.each do |h|
  macs=h.fetch('mac','').downcase.split(/\s+/)
  if h['ip']==d['ip'] || macs.include?(d['mac'])
   raise 'IP 或 MAC 与已有静态租约冲突' unless h['ip']==d['ip'] && macs.include?(d['mac'])
   matches+=1
   raise 'IP 或 MAC 存在重复静态租约' if matches>1 || macs.uniq!=[d['mac']]
   adopt=true
  end
 end
 leases=active_dhcp_leases
 raise '该 IP 当前租给了其他设备，请换一个空闲 IP' if leases.any?{|l|l[2]==d['ip'] && l[1].downcase!=d['mac']}
 raise '该 MAC 当前使用其他 IP，请先在 DHCP 中迁移租约，避免断网' if leases.any?{|l|l[1].downcase==d['mac'] && l[2]!=d['ip']}
 neighbors=quiet('ip','neigh','show','dev',PhoneSettings['bridge'])
 neighbors.each_line do |line|
  a=line.split; next unless a.first==d['ip'] && a.include?('lladdr')
  seen=a[a.index('lladdr')+1].downcase
  raise '邻居表显示该 IP 被其他 MAC 占用' if seen!=d['mac']
 end
 d.merge('node'=>g['node'],'dns_port'=>g['dns_port'],'adopt_lease'=>adopt,'revision'=>revision,
 'warning'=>'可选择全部手机节点，缺少的独立 DNS 分组会在应用时创建；应用会重载防火墙并短暂重启 OpenClash。请确保手机使用固定的 Wi-Fi MAC，地址未被静态配置的离线设备占用。')
end
def batch_plan(req)
 rows=req.is_a?(Hash) ? req['devices'] : nil
 raise '每批请选择 1～32 台设备' unless rows.is_a?(Array) && (1..32).include?(rows.size)
 normalized=rows.map{|row|valid_input(row)}
 raise '批量设备中有重复 IP 或 MAC' unless normalized.map{|d|d['ip']}.uniq.size==rows.size && normalized.map{|d|d['mac']}.uniq.size==rows.size
 plans=normalized.each_with_index.map do |row,index|
  begin;plan(row);rescue=>e;raise "第 #{index+1} 台：#{e.message}";end
 end
 rev=plans.first['revision']
 raise '预览期间配置有变化，请重试' unless plans.all?{|p|p['revision']==rev}
 {'devices'=>plans,'revision'=>rev,'batch'=>true,'warning'=>'统一备份、校验和应用；整批只重启一次代理。请核对固定 MAC 与 IP，应用期间会短暂中断代理网络。'}
end

def nft_text(mapping,hs)
 ips=mapping.flat_map{|g|g['ips']}.uniq.sort_by{|ip|ip.split('.').map(&:to_i)}
 macs=ips.flat_map{|ip|h=hs.find{|x|x['ip']==ip};raise "缺少 #{ip} 的静态租约 MAC" unless h;h.fetch('mac','').downcase.split}.uniq
 raise 'MAC 数据异常' unless macs.all?{|m|m.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/)}
 s="set codex_phone4 {\n type ipv4_addr\n flags interval\n auto-merge\n elements = { #{ip_elements(ips)} }\n}\n"
 s+="set codex_phone_mac {\n type ether_addr\n elements = { #{macs.join(', ')} }\n}\n"
 s+="chain codex_phone_guard {\n type filter hook forward priority -10; policy accept;\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ip saddr @codex_phone4 counter drop comment \"Phone fixed egress: no direct forwarding\"\n iifname \"#{PhoneSettings['bridge']}\" oifname != \"#{PhoneSettings['bridge']}\" ether saddr @codex_phone_mac counter drop comment \"Phone fixed egress: IPv6 and address-change guard\"\n}\n"
 s+="chain codex_phone_dns {\n type nat hook prerouting priority -101; policy accept;\n"
 mapping.reject{|g|g['ips'].empty?}.each{|g|s+=" iifname \"#{PhoneSettings['bridge']}\" ip saddr { #{g['ips'].join(', ')} } meta l4proto { tcp, udp } th dport 53 counter redirect to :#{g['dns_port']} comment \"Phone DNS group #{g['id']}\"\n"}
 s+"}\n"
end
def jobwrite(id,data)
 atomic(JOBS+'/'+id+'.yaml',json(data))
end
def apply_worker(id)
 job=YAML.load_file(JOBS+'/'+id+'.yaml');req=job.fetch('request');cfg=source_path
 outcome=PhoneApply.transaction(cfg,expected_revision:req['revision'],revision:lambda{revision}) do
  checked=req['batch'] ? batch_plan(req) : plan(req);plans=req['batch'] ? checked['devices'] : [checked]
  a=YAML.load_file(cfg,aliases:true);mapping=catalog
  devices=File.exist?(BASE+'/devices.yaml') ? (YAML.load_file(BASE+'/devices.yaml') || []) : []
  changed=false
  plans.each do |p|
   mapping.find{|g|g['id']==p['group']}['ips']<<p['ip']
   rule="SRC-IP-CIDR,#{p['ip']}/32,#{p['node']}";idx=a['rules'].index{|r|!r.start_with?('SRC-IP-CIDR,')}||0
   a['rules'].insert(idx,rule) unless a['rules'].include?(rule)
   unless p['adopt_lease']
    sec=PhoneSettings.lease_section('phone_panel',p['ip']);raise 'DHCP 配置段名称冲突' unless quiet('uci','-q','get','dhcp.'+sec).empty?
    PhoneApply.command('uci','set',"dhcp.#{sec}=host")
    {'mac'=>p['mac'],'ip'=>p['ip'],'name'=>(DeviceEdit.dhcp_hostname(p['name']) || 'phone-'+p['ip'].tr('.','-'))}.each{|k,v|PhoneApply.command('uci','set',"dhcp.#{sec}.#{k}=#{v}")};changed=true
   end
   devices<<p.select{|k,v|%w[name ip mac group].include?(k)}
  end
  PhoneApply.command('uci','commit','dhcp') if changed
  atomic(cfg,a.to_yaml);atomic(BASE+'/mapping.yaml',mapping.to_yaml);atomic(BASE+'/devices.yaml',devices.to_yaml)
  atomic(router_path('/etc/nftables.d/90-phone-fixed-egress.nft'),nft_text(mapping,hosts))
  {'devices'=>plans.map{|p|p.select{|k,v|%w[name ip mac group node].include?(k)}}}
 end
 jobwrite(id,outcome.merge('status'=>outcome['ok'] ? 'done' : 'failed'))
rescue=>e
 jobwrite(id,{'status'=>'failed','message'=>e.message})
end
if __FILE__==$PROGRAM_NAME
begin
 mode=ARGV.shift
 if mode=='worker'
  id=ARGV.shift;raise 'invalid job' unless id.to_s.match?(/\A\d{14}-[a-f0-9]{12}\z/);apply_worker(id);exit
 elsif mode=='job'
  id=ARGV.shift;raise '任务 ID 无效' unless id.to_s.match?(/\A\d{14}-[a-f0-9]{12}\z/)
  p=YAML.load_file(JOBS+'/'+id+'.yaml');p.delete('request');puts json(p);exit
 end
 input=YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false);p=%w[batch-preview batch-apply].include?(mode) ? batch_plan(input) : plan(input)
 if %w[preview batch-preview].include?(mode)
  puts json({'ok'=>true,'plan'=>p})
 elsif %w[apply batch-apply].include?(mode)
  raise '请先预览配置' unless input['revision']==p['revision']
  Dir.mkdir(JOBS,0700) unless Dir.exist?(JOBS)
  id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+File.binread('/dev/urandom',6).unpack1('H*')
  jobwrite(id,{'status'=>'queued','message'=>'等待应用','request'=>p})
  pid=Process.spawn('/usr/bin/ruby',__FILE__,'worker',id,in:File::NULL,out:File::NULL,err:File::NULL,pgroup:true)
  Process.detach(pid);puts json({'ok'=>true,'job'=>id})
 else;raise '不支持的操作';end
rescue =>e
 puts json({'error'=>e.message})
end

end
