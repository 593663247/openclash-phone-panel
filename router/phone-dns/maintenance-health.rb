require_relative 'panel-store'
require 'digest'
module PhoneMaintenanceHealth
 ROOTS=%w[/root/phone-panel-transactions /root/phone-panel-releases /root/phone-panel-changes /root/phone-panel-device-edits /root/phone-panel-node-changes /root/phone-panel-maintenance].freeze
 def self.bytes(path)
  return 0 if File.symlink?(path)
  return File.size(path) if File.file?(path)
  Dir.children(path).sum{|n|bytes(File.join(path,n))}
 rescue Errno::ENOENT;0
 end
 def self.inventory
  ROOTS.flat_map do |base|
   actual=PanelStore.path(base);next [] unless Dir.exist?(actual)
   Dir.children(actual).filter_map do |name|
    next unless name.match?(/\A[0-9][a-zA-Z0-9_.-]*\z/)
    p=actual+'/'+name;next if File.symlink?(p)
    {'id'=>base+'/'+name,'bytes'=>bytes(p),'at'=>File.mtime(p).to_i,'kind'=>base.split('/').last,'directory'=>File.directory?(p)}
   end
  end.sort_by{|x|-x['at']}
 end
 def self.space(path)
  out,code=PanelStore.capture('df','-Pk',PanelStore.path(path));row=out.lines.last.to_s.split
  code==0 && row.size>=6 ? row[3].to_i*1024 : nil
 end
 def self.preflight
  checks=[]
  [['/tmp',96*1024*1024],['/root',64*1024*1024]].each do |path,min|
   free=space(path);checks<<{'name'=>path+' 可用空间','ok'=>!free.nil?&&free>=min,'detail'=>free ? "#{free/1024/1024} MiB 可用；至少 #{min/1024/1024} MiB" : '无法读取空间'}
  end
  %w[ruby lua uci nft fw4 curl sha256sum sing-box dnsmasq].each do |name|
   _,code=PanelStore.capture('sh','-c','command -v "$1" >/dev/null','sh',name)
   checks<<{'name'=>'依赖 '+name,'ok'=>code==0,'detail'=>code==0 ? '已安装' : '缺失'}
  end
  checks<<{'name'=>'Ruby 版本','ok'=>(RUBY_VERSION.split('.').first(2).map(&:to_i)<=>[3,1])>=0,'detail'=>RUBY_VERSION}
  checks<<{'name'=>'OpenClash 核心','ok'=>File.executable?(PanelStore.path('/etc/openclash/clash')),'detail'=>'必须已有可执行核心'}
  %w[dhcp phone_panel openclash].each do |s|
   text,code=PanelStore.capture('uci','changes',s);checks<<{'name'=>s+' 未提交修改','ok'=>code==0&&text.strip.empty?,'detail'=>text.strip.empty? ? '无待保存修改' : '请先保存或撤销'}
  end
  # Probe the common lock without acquiring it for the entire status request.
  lock=File.open(PanelStore.path('/var/lock/phone-panel.lock'),'a',0600)
  available=lock.flock(File::LOCK_EX|File::LOCK_NB);lock.close
  checks<<{'name'=>'配置操作锁','ok'=>!!available,'detail'=>available ? '空闲' : '其他配置任务运行中'}
  {'ok'=>checks.all?{|c|c['ok']},'at'=>Time.now.to_i,'checks'=>checks,'policy'=>'空间为保守下限；下载体积及依赖兼容仍由安装器校验。不会自动安装依赖。'}
 end
 def self.cleanup_plan(req)
  rows=inventory;selected=req['ids'];raise '请选择 1～20 条备份' unless selected.is_a?(Array)&&(1..20).include?(selected.size)&&selected.uniq.size==selected.size
  # Keep recent snapshots and any release/linked maintenance backup. Only standalone old transactions qualify.
  candidates=rows.select{|r|r['kind']=='phone-panel-transactions'&&r['directory']}.drop(3).select{|r|r['at']<Time.now.to_i-7*86400}
  chosen=selected.map{|id|candidates.find{|r|r['id']==id}||raise('仅可整理超过七天、且不属于最近三条的独立事务备份')}
  live=(Dir.glob(PanelStore.path('/etc/phone-dns/operations/*.json'))+Dir.glob(PanelStore.path('/etc/phone-dns/tasks/*.yaml'))).any?{|p|%w[running queued].include?(PanelStore.read(p,{})['status'])}
  raise '有活动任务，请等待完成后整理' if live
  {'ok'=>true,'items'=>chosen,'revision'=>Digest::SHA256.hexdigest(PanelStore.json(chosen)),'bytes'=>chosen.sum{|r|r['bytes']},'warning'=>'仅移到路由器回收目录，不删除、不立即释放磁盘。至少保留最近三条，且只处理超过七天的独立事务备份。'}
 end
 def self.cleanup(req)
  lock=File.open(PanelStore.path('/var/lock/phone-panel.lock'),'a',0600);raise '配置操作中' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
  plan=cleanup_plan(req);raise '备份状态变化，请重新预览' unless req['revision']==plan['revision']
  trash=PanelStore.path('/root/phone-panel-backup-recycle');PanelStore.mkdir(trash)
  destination=trash+'/'+Time.now.strftime('%Y%m%d%H%M%S%9N');PanelStore.mkdir(destination)
  moved=[]
  begin
   plan['items'].each do |row|
    source=PanelStore.path(row['id']);raise '不安全备份路径' if File.symlink?(source)||File.realpath(source)!=File.expand_path(source)
    dest=destination+'/'+File.basename(source);File.rename(source,dest);moved<<[source,dest]
   end
   PanelStore.write(destination+'/restore-manifest.json',moved)
  rescue
   moved.reverse_each{|source,dest|File.rename(dest,source)};raise
  end
  {'ok'=>true,'message'=>'已移入回收目录，未永久删除，未释放磁盘；可按清单恢复。','recycle'=>destination}
 ensure
  lock.close if lock
 end
 def self.info
  rows=inventory
  recent=rows.select{|r|r['kind']=='phone-panel-transactions'&&r['directory']}.first(3).map{|r|r['id']}
  recycle=PanelStore.path('/root/phone-panel-backup-recycle');recycle_bytes=Dir.exist?(recycle) ? bytes(recycle) : 0
  rows.each do |r|
   r['protection_reason']=if r['kind']!='phone-panel-transactions'||!r['directory'];'旧版记录或关联备份，不支持回收'
   elsif recent.include?(r['id']);'最近三条保护'
   elsif r['at']>=Time.now.to_i-7*86400;'未满七天'
   end
   r['recyclable']=r['protection_reason'].nil?
  end
  {'ok'=>true,'items'=>rows,'recycle_bytes'=>recycle_bytes,'total_bytes'=>rows.sum{|x|x['bytes']},'count'=>rows.size,'at'=>Time.now.to_i,'note'=>'仅统计已知备份目录；不含任意手动备份。暂不自动删除，恢复快照可能相互引用。'}
 end
end
if __FILE__==$PROGRAM_NAME
 begin
  mode=ARGV.shift
  result=case mode
  when 'preflight';PhoneMaintenanceHealth.preflight
  when 'cleanup-preview';PhoneMaintenanceHealth.cleanup_plan(YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false))
  when 'cleanup';PhoneMaintenanceHealth.cleanup(YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false))
  else;PhoneMaintenanceHealth.info
  end
  puts PanelStore.json(result)
 rescue=>e;puts PanelStore.json({'error'=>'维护状态读取失败：'+e.class.to_s});end
end
