require 'yaml'
# Persisted, allow-listed maintenance jobs. Never accept shell commands from HTTP.
module PanelTasks
 DIR='/etc/phone-dns/tasks'
 ACTIONS={
 'doctor'=>['sh','/usr/share/phone-panel/scripts/maintenance.sh','doctor'],
 'backup'=>['sh','/usr/share/phone-panel/scripts/maintenance.sh','backup'],
 'initialize'=>['sh','/usr/share/phone-panel/scripts/maintenance.sh','initialize','--apply'],
 'dependencies'=>['sh','/usr/share/phone-panel/scripts/install-deps.sh','--install-deps'],
 'repair_hooks'=>['ruby','/usr/share/phone-panel/scripts/hooks.rb','install']}
 def self.json(x)
  case x
  when Hash;'{'+x.map{|k,v|json(k.to_s)+':'+json(v)}.join(',')+'}'
  when Array;'['+x.map{|v|json(v)}.join(',')+']'
  when String;'"'+x.gsub(/["\\\x00-\x1f]/){|c|c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
  when NilClass;'null';when TrueClass;'true';when FalseClass;'false';else;x.to_s;end
 end
 def self.write(id,d)
  p=DIR+'/'+id+'.yaml';File.open(p+'.tmp','w',0600){|f|f.write(d.to_yaml)};File.rename(p+'.tmp',p)
 end
 def self.execute(mode,arg,parameters={})
  Dir.mkdir(DIR,0700) unless Dir.exist?(DIR)
  if mode=='list'
   return {'tasks'=>Dir.glob(DIR+'/*.yaml').sort.reverse.first(20).map{|f|YAML.safe_load(File.read(f)).reject{|k,_|k=='parameters'}}}
  end
  if mode=='start'
   raise 'Unsupported action' unless ACTIONS.key?(arg) || %w[upgrade restore_release].include?(arg)
   if arg=='upgrade';raise 'Invalid target version' unless parameters['target'].to_s.match?(/\A[a-f0-9]{40}\z/);end
   if arg=='restore_release';raise 'Invalid recovery ID' unless parameters['release'].to_s.match?(/\A\d{14}-[a-f0-9]{12}\z/);end
   id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+File.binread('/dev/urandom',6).unpack1('H*')
   write(id,{'id'=>id,'action'=>arg,'status'=>'queued','message'=>'等待执行','parameters'=>parameters})
   pid=Process.spawn('/usr/bin/ruby',__FILE__,'worker',id,in:File::NULL,out:File::NULL,err:File::NULL,pgroup:true);Process.detach(pid)
   return {'ok'=>true,'id'=>id}
  end
  raise 'Invalid job ID' unless arg.to_s.match?(/\A\d{14}-[a-f0-9]{12}\z/)
  d=YAML.safe_load(File.read(DIR+'/'+arg+'.yaml'))
  lock=File.open('/var/lock/phone-panel.lock','w',0600)
  begin
   release_action=%w[upgrade restore_release].include?(d['action'])
   raise '其他配置任务运行中，请稍后重试' unless release_action || lock.flock(File::LOCK_EX|File::LOCK_NB)
   d.merge!('status'=>'running','message'=>'正在执行；请勿断电');write(arg,d)
   log=DIR+'/'+arg+'.log'
   args=case d['action']
    when 'upgrade';['/usr/bin/ruby','/etc/phone-dns/releases.rb','upgrade',d.fetch('parameters').fetch('target')]
    when 'restore_release';['/usr/bin/ruby','/etc/phone-dns/releases.rb','restore',d.fetch('parameters').fetch('release')]
    else;ACTIONS.fetch(d['action'])
   end
   ok=File.open(log,'w',0600){|f|system(*args,out:f,err:f)}
   d.merge!('status'=>ok ? 'done' : 'failed','message'=>ok ? '任务完成' : '任务失败；详细记录保留在路由器本地，未自动回滚')
  rescue=>e
   d.merge!('status'=>'failed','message'=>e.message)
  ensure
   lock.close;write(arg,d)
  end
  {'ok'=>true}
 end
end
if $0==__FILE__
 begin;puts PanelTasks.json(PanelTasks.execute(ARGV[0],ARGV[1]));rescue;puts PanelTasks.json({'error'=>'任务操作失败，请检查路由器状态'});end
end
