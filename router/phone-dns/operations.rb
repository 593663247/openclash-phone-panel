require_relative 'panel-store'
require_relative 'binding-registry'
module PhoneOperations
 ACTIONS={'check_update'=>['releases.rb','check-request'],'upgrade'=>['releases.rb','upgrade-request'],'restore_release'=>['releases.rb','restore-request'],'binding_migrate'=>['binding-manager.rb','apply'],'device_edit'=>['device-operation.rb','apply'],'node_change'=>['node-manager.rb','apply'],'node_test'=>['node-manager.rb','test'],'device_add'=>['device-manager.rb','apply'],'device_batch'=>['device-manager.rb','batch-apply'],'restore'=>['apply-engine.rb','restore'],'initialize'=>['apply-engine.rb','initialize']}.freeze
 ID=/\A\d{14}-[a-f0-9]{12}\z/
 def self.directory;PanelStore.path('/etc/phone-dns/operations');end
 def self.boot;File.read('/proc/sys/kernel/random/boot_id').strip;end
 def self.alive?(pid)
  return false unless pid.is_a?(Integer)&&pid>1
  Process.kill(0,pid);true
 rescue Errno::ESRCH;false
 rescue Errno::EPERM;true
 end
 def self.reconcile(record,current_boot=boot)
  return record unless %w[queued running].include?(record['status'])
  if record['boot']!=current_boot || (record['pid'] && (!alive?(record['pid'])||(record['process_token']&&record['process_token']!=PhoneBindings.process_token(record['pid'])))) || (!record['pid'] && Time.now.to_i-record['at'].to_i>30)
   record.merge!('status'=>'interrupted','stage'=>'执行已中断','message'=>'任务进程退出或路由器重启；未自动重试。检查设备状态和备份后再操作。','recovery_required'=>record['status']=='running'&&record['action']!='check_update')
  end
  record
 end
 def self.list
  PanelStore.mkdir(directory)
  Dir.glob(directory+'/*.json').sort.reverse.first(50).map do |p|
   record=PanelStore.read(p,{});next if record.empty?
   old=record['status'];reconcile(record)
   if record['status']!=old
    PanelStore.write(p,record)
    if record['action']=='check_update'
     cache=PanelStore.read(PanelStore.state+'/update-cache.yaml',{})
     PanelStore.write(PanelStore.state+'/update-cache.yaml',cache.merge('can_upgrade'=>false,'message'=>'上次检查已中断，请重新检查正式发布'))
    end
   end
   record.reject{|k,_|%w[request log pid boot process_token].include?(k)}
  end.compact
 end
 def self.all
  current=list;children=current.map{|r|r['child_job']}.compact
  legacy=[]
  [['/etc/phone-dns/jobs/*.yaml','设备添加'],['/etc/phone-dns/tasks/*.yaml','维护']].each do |pattern,label|
   Dir.glob(PanelStore.path(pattern)).sort.reverse.first(30).each do |p|
    r=PanelStore.read(p,{});if r['boot'];old=r['status'];reconcile(r);PanelStore.write(p,r) if old!=r['status'];end;id=File.basename(p,'.yaml');next if children.include?(id)
    legacy<<{'id'=>label+':'+id,'action'=>r['action'] || label,'status'=>r['status'],'stage'=>r['message'],'message'=>r['message'],'backup'=>r['backup'],'rolled_back'=>r['rolled_back'],'historical'=>true,'at'=>(Time.local(*[id[0,4],id[4,2],id[6,2],id[8,2],id[10,2],id[12,2]].map(&:to_i)).to_i rescue File.mtime(p).to_i)}
   end
  end
  (current+legacy).sort_by{|r|-r.fetch('at',0).to_i}.first(70)
 end
 def self.start(action,request)
  raise '不支持的操作' unless ACTIONS.key?(action)
  raise '请求格式无效' unless request.is_a?(Hash)
  raise '升级请求无效，请重新检查正式发布' if action=='upgrade'&&(!request['target'].to_s.match?(/\A[a-f0-9]{40}\z/)||!request['fingerprint'].to_s.match?(/\A[a-f0-9]{64}\z/))
  raise '程序恢复编号无效' if action=='restore_release'&&!request['release'].to_s.match?(ID)
  PanelStore.mkdir(directory)
  result=PanelStore.with_lock(directory+'/.submit-lock') do
   raise '已有配置任务，请等待完成' if list.any?{|r|%w[queued running].include?(r['status'])}
   id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+Random.bytes(6).unpack1('H*');path=directory+'/'+id+'.json'
   PanelStore.write(directory+'/'+id+'.request',request)
   PanelStore.write(path,{'id'=>id,'action'=>action,'subject'=>request.values_at('ip','new_ip','name','original_name','tag').compact.map(&:to_s).uniq.join(' → ')[0,180],'status'=>'queued','stage'=>'等待执行','message'=>'已提交后台任务，可安全刷新页面','at'=>Time.now.to_i,'boot'=>boot})
   if action=='check_update'
    marker=PanelStore.path('/usr/share/phone-panel/deployed-commit')
    PanelStore.write(PanelStore.state+'/update-cache.yaml',{'current'=>File.file?(marker) ? File.read(marker).strip : '', 'checked_at'=>Time.now.to_i,'can_upgrade'=>false,'message'=>'正在后台核对正式发布，请在任务与恢复中查看进度'})
   end
   pid=Process.spawn({'PHONE_PANEL_OPERATION_ID'=>id},'/usr/bin/ruby',__FILE__,'worker',id,in:File::NULL,out:File::NULL,err:File::NULL,pgroup:true)
   r=PanelStore.read(path,{});r['pid']=pid;r['process_token']=PhoneBindings.process_token(pid);PanelStore.write(path,r);Process.detach(pid)
   {'ok'=>true,'operation_id'=>id,'message'=>'后台任务已提交，请查看统一任务中心'}
  end
  result
 end
 def self.worker(id)
  raise '任务编号无效' unless id.to_s.match?(ID)
  path=directory+'/'+id+'.json';request=directory+'/'+id+'.request'
  # Wait for submission checkpoint before writing running status.
  PanelStore.with_lock(directory+'/.submit-lock'){}
  record=PanelStore.read(path,{});record.merge!('status'=>'running','stage'=>'检查并准备应用','pid'=>Process.pid,'process_token'=>PhoneBindings.process_token(Process.pid));PanelStore.write(path,record)
  script,mode=ACTIONS.fetch(record.fetch('action'));log=directory+'/'+id+'.private-log'
  output=IO.popen(['/usr/bin/ruby',PanelStore.path('/etc/phone-dns/'+script),mode,request,{err:File::NULL}],&:read)
  result=YAML.safe_load(output,aliases:false);raise '后台服务未返回有效结果' unless result.is_a?(Hash)
  record=PanelStore.read(path,record)
  if result['job']
   record['child_job']=result['job'];PanelStore.write(path,record)
   1800.times do
    child=PanelStore.read(PanelStore.path('/etc/phone-dns/jobs/'+result['job']+'.yaml'),{})
    if %w[done failed].include?(child['status']);result=child.merge('ok'=>child['status']=='done');break;end
    record['stage']=child['message'] || '正在添加设备';PanelStore.write(path,record);sleep 1
   end
  end
  if result['job']
   record=PanelStore.read(path,record);record.merge!('status'=>'interrupted','recovery_required'=>true,'stage'=>'子任务超时','message'=>'设备子任务状态未确认，请检查后再操作');PanelStore.write(path,record);return
  end
  record=PanelStore.read(path,record)
  if record['action']=='check_update'&&!result['ok']
   cache=PanelStore.read(PanelStore.state+'/update-cache.yaml',{})
   PanelStore.write(PanelStore.state+'/update-cache.yaml',cache.merge('can_upgrade'=>false,'message'=>'检查正式发布失败：'+result.fetch('error','请查看任务记录').to_s))
  end
  record.merge!('result'=>result['result'],'status'=>result['ok'] ? 'done' : 'failed','stage'=>result['ok'] ? '完成' : '失败','message'=>result['message'] || result['error'],
   'backup'=>result['backup'],'program_backup'=>result['program_backup']||record['program_backup'],'files_restored'=>result['files_restored'],'runtime_restored'=>result['runtime_restored'],'recovery_required'=>result['recovery_required'],'rollback_error'=>result['rollback_error'],'checks'=>result['checks'],'finished_at'=>Time.now.to_i)
  PanelStore.write(path,record)
 rescue=>e
  record=path ? PanelStore.read(path,record || {'id'=>id}) : {'id'=>id};record.merge!('status'=>'interrupted','recovery_required'=>record['action']!='check_update','stage'=>'任务异常','message'=>e.class.to_s+'：后台任务未正常返回，请核对运行状态与备份，切勿重复提交');PanelStore.write(path,record) if path
 ensure
  File.delete(request) if request && File.file?(request)
 end
end
if __FILE__==$PROGRAM_NAME
 begin
  action=ARGV.shift
  result=case action
  when 'list';{'ok'=>true,'operations'=>PhoneOperations.all}
  when 'worker';PhoneOperations.worker(ARGV.fetch(0));{'ok'=>true}
  else;PhoneOperations.start(action,YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false))
  end
  puts PanelStore.json(result)
 rescue=>e;puts PanelStore.json({'error'=>e.message});end
end
