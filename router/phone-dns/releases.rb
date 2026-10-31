require_relative 'panel-store'
require_relative 'maintenance-health'
require_relative 'luci-cache'
require_relative 'binding-registry'
require_relative 'update-package'

module PhoneRelease
 REPOSITORY='593663247/openclash-phone-panel'
 SHA=/\A[a-f0-9]{40}\z/
 ID=/\A\d{14}-[a-f0-9]{12}\z/
 def self.current
  path=PanelStore.path('/usr/share/phone-panel/deployed-commit')
  File.file?(path) ? File.read(path).strip : ''
 end
 def self.root;PanelStore.path('/root/phone-panel-releases');end
 def self.http_json(path,timeout:20)
  raise 'Invalid repository API path' unless path.start_with?('/') && !path.include?("\n")
  body=PanelStore.run('curl','--noproxy','', '-fsS','--proto','=https','--connect-timeout','5','--max-time',timeout.to_s,
   '-H','Accept: application/vnd.github+json','-H','User-Agent: OpenClash-Phone-Panel',"https://api.github.com/repos/#{REPOSITORY}#{path}")
  value=YAML.safe_load(body)
  raise 'Invalid GitHub response' unless value.is_a?(Hash)
  value
 end
 def self.published_release(refresh:false)
  file=PanelStore.state+'/published-release.yaml';cached=PanelStore.read(file,{});now=Time.now.to_i
  age=now-cached.fetch('checked_at',0).to_i
  retry_age=now-cached.fetch('attempted_at',0).to_i
  return cached if !refresh && ((cached['status']=='available'&&age.between?(0,3599)) || (cached['status']=='unavailable'&&retry_age.between?(0,59)))
  begin
   release=http_json('/releases/latest',timeout:10);tag=release['tag_name'].to_s
   raise 'Invalid published release' unless tag.match?(/\Av?\d+\.\d+\.\d+\z/) && release['draft']==false && release['prerelease']==false
   result={'status'=>'available','tag'=>tag,'checked_at'=>now,'attempted_at'=>now}
  rescue
   result=cached.merge('status'=>'unavailable','attempted_at'=>now,'message'=>'暂时无法读取 GitHub 最新发布，请稍后重试。')
  end
  PanelStore.write(file,result);result
 end
 def self.phase(label,extra={})
  id=ENV['PHONE_PANEL_OPERATION_ID'];return unless id.to_s.match?(ID)
  file=PanelStore.path('/etc/phone-dns/operations/'+id+'.json');record=PanelStore.read(file,{})
  return if record.empty?
  PanelStore.write(file,record.merge(extra).merge('stage'=>label,'updated_at'=>Time.now.to_i))
 end
 def self.version
  file=PanelStore.path('/usr/share/phone-panel/VERSION');File.file?(file) ? File.read(file).strip : ''
 end
 def self.check
  candidate=PhoneUpdatePackage.candidate;latest=candidate['latest'];installed=current
  comparison=installed.match?(SHA)&&installed!=latest ? http_json("/compare/#{installed}...#{latest}")['status'] : 'identical'
  runs=http_json("/actions/runs?head_sha=#{latest}&per_page=20").fetch('workflow_runs',[])
  workflow=runs.select{|r|r['path'].to_s.split('@').first=='.github/workflows/ci.yml'&&r['head_sha']==latest&&r['event']=='push'}.max_by{|r|r.fetch('run_number',0).to_i}
  ci=workflow&&workflow['status']=='completed'&&workflow['conclusion']=='success'
  newer=version.match?(/\A\d+\.\d+\.\d+\z/)&&(candidate['tag'].delete_prefix('v').split('.').map(&:to_i)<=>version.split('.').map(&:to_i))==1
  data=candidate.merge('repository'=>REPOSITORY,'current'=>installed,'checked_at'=>Time.now.to_i,'ci_ok'=>!!ci,'ci_url'=>workflow&&workflow['html_url'],'comparison'=>comparison,
   'can_upgrade'=>installed.match?(SHA)&&comparison=='ahead'&&ci==true&&newer,
   'message'=>installed==latest ? '已是最新正式发布版本' : (!newer ? '正式发布版本没有更新，未允许降级或覆盖' : comparison!='ahead' ? '版本历史不兼容，请人工核对' : ci ? '发现已通过 CI 的正式发布 '+candidate['tag'] : '正式发布的 CI 尚未通过，暂不可升级'))
  data['preflight']=PhoneMaintenanceHealth.preflight
  data['can_upgrade']&&=data['preflight']['ok']
  data['message']='升级预检查未通过，请处理下方项目' unless data['preflight']['ok']
  unless pending_recovery.empty?
   data['can_upgrade']=false;data['message']='上次程序升级未完成，请先在程序恢复中恢复操作前版本'
  end
  PanelStore.write(PanelStore.state+'/update-cache.yaml',data);data
 end
 def self.boot_id;File.read('/proc/sys/kernel/random/boot_id').strip;rescue Errno::ENOENT;'test';end
 def self.pending_recovery
  return [] unless Dir.exist?(root)
  Dir.glob(root+'/*/record.yaml').filter_map do |file|
   r=PanelStore.read(file,{})
   next unless r['id'].to_s.match?(ID)&&%w[prepared installing recovering recovery_required].include?(r['status'])
   live=r['pid'].is_a?(Integer)&&r['process_token']&&PhoneBindings.process_token(r['pid'])==r['process_token']&&r['boot']==boot_id
   r.merge('recoverable'=>!live)
  end
 end
 def self.records
  return [] unless Dir.exist?(root)
  Dir.glob(root+'/*/record.yaml').sort.reverse.first(12).filter_map do |path|
   r=PanelStore.read(path,{})
   next unless r['id'].to_s.match?(ID)
   pending=pending_recovery.find{|item|item['id']==r['id']}
   r.merge('recoverable'=>pending&&pending['recoverable']).select{|k,_|%w[id from to at status config_backup recoverable files_restored runtime_restored rollback_error].include?(k)}
  end
 end
 def self.info
  cache=PanelStore.read(PanelStore.state+'/update-cache.yaml',{})
  if cache['current']!=current || Time.now.to_i-cache.fetch('checked_at',0).to_i>3600
   cache['can_upgrade']=false;cache['message']='版本或检查时间已变化，请重新检查更新'
  end
  unless pending_recovery.empty?
   cache['can_upgrade']=false;cache['message']='上次程序升级未完成，请先在程序恢复中恢复操作前版本'
  end
  version_path=PanelStore.path('/usr/share/phone-panel/VERSION')
  version=File.file?(version_path) ? File.read(version_path).strip : nil
  version=nil unless version.to_s.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/)
  {'version'=>version,'current'=>current,'repository'=>REPOSITORY,'update'=>cache,'pending_recovery'=>pending_recovery.map{|r|r.slice('id','status','recoverable')},'published_release'=>PanelStore.read(PanelStore.state+'/published-release.yaml',{}),'releases'=>records}
 end
 # A bounded TAR reader: no links, devices, traversal, arbitrary archive roots or unbounded expansion.
 def self.unpack_stream(io,destination)
  PanelStore.mkdir(destination);root_name=nil;pending={};count=0;total=0;files=[]
  loop do
   header=io.read(512)
   break if header.nil? || header=="\0"*512
   raise 'Truncated release archive' unless header.bytesize==512
   expected=header.byteslice(148,8).delete("\0 ").to_i(8)
   checksum=header.dup;checksum[148,8]=' '*8
   raise 'Invalid TAR checksum' unless checksum.bytes.sum==expected
   count+=1;raise 'Release has too many files' if count>2000
   size_text=header.byteslice(124,12).delete("\0 ")
   raise 'Invalid TAR size' unless size_text.match?(/\A[0-7]*\z/)
   size=size_text.to_i(8);total+=size
   raise 'Release exceeds extraction limit' if size>4*1024*1024 || total>32*1024*1024
   type=header.byteslice(156,1)
   body=io.read(size)||'';raise 'Truncated archive entry' unless body.bytesize==size
   padding=(512-size%512)%512;raise 'Truncated archive padding' unless (io.read(padding)||'').bytesize==padding
   if %w[x g].include?(type)
    data=body.dup
    until data.empty?
     match=data.match(/\A(\d+) /);raise 'Malformed PAX entry' unless match
     length=match[1].to_i;raise 'Malformed PAX length' unless length>match[0].bytesize && length<=data.bytesize
     field=data.byteslice(match[0].bytesize,length-match[0].bytesize).chomp("\n")
     key,value=field.split('=',2);raise 'PAX links unsupported' if key=='linkpath'
     pending[key]=value if type=='x' && key=='path'
     data=data.byteslice(length..-1)||''
    end
    next
   end
   raise 'Only ordinary files and directories may be installed' unless ["0","\0","5"].include?(type)
   name=header.byteslice(0,100).split("\0").first.to_s
   prefix=header.byteslice(345,155).split("\0").first.to_s
   name=prefix+'/'+name unless prefix.empty?
   name=pending.delete('path')||name
   raise 'Unsafe release path' if name.start_with?('/') || name.include?('\\') || name.split('/').any?{|s|s=='.'||s=='..'} || name.match?(/[\x00-\x1f\x7f]/)
   parts=name.split('/').reject(&:empty?)
   raise 'Invalid portable release path' if parts.any?{|part|part.include?(':')}
   root_name||=parts.first
   raise 'Release must have one top-level directory' unless parts.first==root_name
   relative=parts.drop(1).join('/');next if relative.empty?
   path=File.join(destination,relative)
   if type=='5';PanelStore.mkdir(path)
   else
    raise 'Duplicate release entry' if files.include?(relative)
    PanelStore.mkdir(File.dirname(path));File.open(path,'wb',0600){|f|f.write(body)};files<<relative
   end
  end
  raise 'Empty release archive' if files.empty?
  files
 end
 def self.extract(archive,destination)
  files=nil
  IO.popen(['gzip','-dc',archive,{err:File::NULL}],'rb') do |io|
   files=unpack_stream(io,destination)
   trailing=0
   while (chunk=io.read(4096)) && !chunk.empty?
    trailing+=chunk.bytesize
    raise 'Invalid archive trailing data' if trailing>1048576 || chunk.bytes.any?{|b|b!=0}
   end
  end
  raise 'Release gzip checksum failed' unless $?.success?
  files
 end
 def self.allowed_destination?(path)
  return false if path.split('/').include?('..')
  path.start_with?('/usr/share/phone-panel/') || path.match?(%r{\A/etc/phone-dns/[a-z0-9-]+\.(?:rb|lua)\z}) ||
   %w[/etc/init.d/phone-dns /etc/init.d/phone-panel-monitor /etc/init.d/phone-panel-guard /usr/lib/lua/luci/controller/phone_panel.lua /usr/lib/lua/luci/view/phone_panel.htm /usr/lib/lua/luci/model/cbi/phone_panel_settings.lua /etc/openclash/custom/phone-routing.sh].include?(path)
 end
 def self.entries(source)
  pairs=[]
  Dir.glob(source+'/**/*',File::FNM_DOTMATCH).each do |file|
   next if File.directory?(file)
   raise 'Links cannot be installed' if File.symlink?(file)
   relative=file[(source.length+1)..-1]
   raise 'Private or unsupported release path' if relative.split('/').include?('.git') || relative.start_with?('work/','outputs/')
   pairs<<[file,'/usr/share/phone-panel/'+relative,0600]
  end
  Dir.glob(source+'/router/phone-dns/*.{rb,lua}').each{|f|pairs<<[f,'/etc/phone-dns/'+File.basename(f),0600]}
  pairs<<[source+'/router/phone-dns/status.rb','/etc/phone-dns/panel-status.rb',0600]
  {'router/phone-dns/phone-dns.init'=>'/etc/init.d/phone-dns','router/phone-dns/phone-panel-monitor.init'=>'/etc/init.d/phone-panel-monitor','router/phone-dns/phone-panel-guard.init'=>'/etc/init.d/phone-panel-guard',
   'router/luci/controller/phone_panel.lua'=>'/usr/lib/lua/luci/controller/phone_panel.lua','router/luci/view/phone_panel.htm'=>'/usr/lib/lua/luci/view/phone_panel.htm',
   'router/luci/model/cbi/phone_panel_settings.lua'=>'/usr/lib/lua/luci/model/cbi/phone_panel_settings.lua','router/openclash/phone-routing.sh'=>'/etc/openclash/custom/phone-routing.sh'}.each do |from,to|
   pairs<<[source+'/'+from,to,to.start_with?('/etc/init.d/','/etc/openclash/custom/') ? 0755 : 0644]
  end
  raise 'Incomplete release' unless pairs.all?{|from,to,_|File.file?(from)&&allowed_destination?(to)}
  pairs
 end
 def self.atomic_code(path,data,mode)
  ancestor=path
  loop do
   raise 'Program destination cannot contain symbolic links' if File.symlink?(ancestor)
   parent=File.dirname(ancestor);break if parent==ancestor;ancestor=parent
  end
  PanelStore.mkdir(File.dirname(path));temporary=path+".release-tmp-#{Process.pid}-#{rand(1<<32)}"
  File.open(temporary,File::WRONLY|File::CREAT|File::EXCL,mode){|f|f.binmode;f.write(data);f.flush;f.fsync};File.chmod(mode,temporary);File.rename(temporary,path);PanelStore.sync_directory(File.dirname(path))
 ensure
  File.delete(temporary) if defined?(temporary) && temporary && File.file?(temporary)
 end
 def self.snapshot(pairs,target,config_backup='')
  id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+Random.bytes(6).unpack1('H*')
  directory=root+'/'+id;PanelStore.mkdir(directory)
  manifest=pairs.map.with_index do |(_,destination,_),index|
   raise 'Unsafe rollback destination' unless allowed_destination?(destination)
   actual=PanelStore.path(destination);raise 'Linked program destination cannot be backed up' if File.symlink?(actual)
   present=File.file?(actual)
   PanelStore.atomic(directory+"/file-#{index}",File.binread(actual)) if present
   {'destination'=>destination,'present'=>present,'mode'=>present ? File.stat(actual).mode&0777 : 0600,'file'=>"file-#{index}",
    'sha256'=>present ? file_hash(directory+"/file-#{index}") : nil}
  end
  record={'id'=>id,'from'=>current,'to'=>target,'at'=>Time.now.to_i,'status'=>'prepared','config_backup'=>config_backup,'pid'=>Process.pid,'process_token'=>PhoneBindings.process_token(Process.pid),'boot'=>boot_id}
  PanelStore.write(directory+'/manifest.yaml',manifest);PanelStore.write(directory+'/record.yaml',record)
  record
 end
 def self.restore_files(id)
  raise 'Invalid recovery ID' unless id.to_s.match?(ID)
  directory=root+'/'+id;manifest=PanelStore.read(directory+'/manifest.yaml',[])
  raise 'Recovery manifest missing' if manifest.empty?
  manifest.each do |entry|
   destination=entry['destination'];raise 'Unsafe rollback destination' unless allowed_destination?(destination)
   raise 'Invalid snapshot file' unless entry['file'].to_s.match?(/\Afile-\d+\z/)
   raise 'Recovery snapshot integrity check failed' if entry['present'] && file_hash(directory+'/'+entry['file'])!=entry['sha256']
  end
  manifest.each do |entry|
   destination=entry['destination']
   actual=PanelStore.path(destination)
   if entry['present'];atomic_code(actual,File.binread(directory+'/'+entry['file']),entry['mode'])
   elsif File.file?(actual);File.delete(actual)
   end
   raise 'Restored program file failed verification' unless entry['present'] ? File.file?(actual)&&file_hash(actual)==entry['sha256']&&(RUBY_PLATFORM.match?(/mswin|mingw/)||(File.stat(actual).mode&0777)==entry['mode']) : !File.exist?(actual)
  end
 end
 def self.protected_paths
  config=PanelStore.capture('uci','-q','get','openclash.config.config_path').first.strip
  raise 'Invalid active proxy configuration path' unless config.start_with?('/etc/openclash/config/') && config.end_with?('.yaml') && !config.include?('..')
  [config,'/etc/openclash/'+File.basename(config),'/etc/config/dhcp','/etc/config/phone_panel','/etc/config/openclash','/etc/phone-dns/persistent-guard.yaml','/etc/phone-dns/mapping.yaml',
   '/etc/phone-dns/devices.yaml','/etc/phone-dns/managed-nodes.yaml','/etc/phone-dns/managed-bindings.yaml','/etc/phone-dns/config.json','/etc/phone-dns/listeners.yaml','/etc/nftables.d/90-phone-fixed-egress.nft']+
   Dir.glob('/etc/phone-dns/group-*.conf')+Dir.glob('/etc/openclash/custom/*').select{|p|File.file?(p)&&p!='/etc/openclash/custom/phone-routing.sh'}
 end
 def self.hashes(paths)
  paths.select{|p|File.file?(PanelStore.path(p))}.to_h{|p|[p,file_hash(PanelStore.path(p))]}
 end
 def self.file_hash(path);PanelStore.run('sha256sum',path).split.first;end
 def self.activate
  service=PanelStore.path('/etc/init.d/phone-panel-monitor')
  if File.file?(service)
   PanelStore.run(service,'enable');PanelStore.run(service,'restart')
  elsif !ENV['PHONE_PANEL_TEST_ROOT']
   PanelStore.capture('nft','delete','table','inet','phone_panel_stats')
  end
  guard=PanelStore.path('/etc/init.d/phone-panel-guard');PanelStore.run(guard,'enable') if File.file?(guard)
  PhoneLuciCache.clear
 end
 def self.stop_monitor_for_restore(id)
  manifest=PanelStore.read(root+'/'+id+'/manifest.yaml',[])
  %w[phone-panel-monitor phone-panel-guard].each do |name|
   service=PanelStore.path('/etc/init.d/'+name);next unless File.file?(service)
   previous=manifest.find{|entry|entry['destination']=='/etc/init.d/'+name}
   PanelStore.capture(service,'disable') if previous&&!previous['present']
   PanelStore.capture(service,'stop') if name=='phone-panel-monitor'
  end
 end
 def self.assert_health(data,baseline)
  return unless baseline
  raise 'Managed devices changed during program operation' unless data['device_count']==baseline['device_count']&&data['groups'].map{|g|g['id']}.sort==baseline['groups'].map{|g|g['id']}.sort
  baseline['groups'].each do |old|
   fresh=data['groups'].find{|g|g['id']==old['id']}
   %w[dns_listening socks_listening binding_ok].each{|key|raise 'Listener readiness regressed' if old[key]&&!fresh[key]}
  end
  %w[guard_ready dns_redirect_ready].each{|key|raise 'Network protection regressed' if baseline[key]&&!data[key]}
 end
 def self.health_check
  raw=PanelStore.run('/usr/bin/ruby',PanelStore.path('/etc/phone-dns/panel-status.rb'))
  data=YAML.safe_load(raw)
  raise 'New panel did not return a valid status' unless data.is_a?(Hash) && data['groups'].is_a?(Array) && !data['error']
  # Listener state need not be healthy before an update; code updates must not disable it.
  data
 end
 class InstallError < StandardError
  attr_reader :result
  def initialize(result);@result=result;super(result['error']);end
 end
 def self.transaction(pairs,target,config_backup:'',protected:[],activator:nil,validator:nil,recovery_validator:nil,baseline:nil)
  before=hashes(protected);record=snapshot(pairs,target,config_backup);directory=root+'/'+record['id']
  marker=PanelStore.path('/usr/share/phone-panel/deployed-commit');previous=current
  record.merge!('status'=>'installing','protected_before'=>before,'baseline'=>baseline);PanelStore.write(directory+'/record.yaml',record)
  phase('备份完成，安装程序文件',{'program_backup'=>record['id']})
  begin
   pairs.each{|from,to,mode|atomic_code(PanelStore.path(to),File.binread(from),mode)}
   phase('核对所有已安装文件与权限');PhoneUpdatePackage.verify_installed(pairs)
   atomic_code(marker,target+"\n",0600)
   phase('启用程序服务并验收')
   activator.call if activator
   validator.call if validator
   raise 'Protected network configuration changed during update' unless hashes(protected)==before
   record['status']='installed';PanelStore.write(directory+'/record.yaml',record);record
  rescue=>failure
   phase('升级失败，恢复操作前程序')
   record.merge!('status'=>'recovering','error'=>failure.message);PanelStore.write(directory+'/record.yaml',record)
   files_ok=false;runtime_ok=false;recovery_error=nil
   begin
    stop_monitor_for_restore(record['id']) if activator
    restore_files(record['id']);atomic_code(marker,previous+"\n",0600)
    files_ok=current==previous
    raise 'Original version marker was not restored' unless files_ok
    activator.call if activator
    recovery_validator.call if recovery_validator
    raise 'Protected network configuration changed during recovery' unless hashes(protected)==before
    runtime_ok=true
   rescue=>e;recovery_error=e.message;end
   record.merge!('status'=>files_ok&&runtime_ok ? 'rolled_back' : 'recovery_required','files_restored'=>files_ok,'runtime_restored'=>runtime_ok,'rollback_error'=>recovery_error)
   PanelStore.write(directory+'/record.yaml',record)
   raise InstallError.new({'error'=>failure.message,'program_backup'=>record['id'],'files_restored'=>files_ok,'runtime_restored'=>runtime_ok,'recovery_required'=>!(files_ok&&runtime_ok),'rollback_error'=>recovery_error})
  end
 end
 def self.validate_source(source)
  entries(source)
  Dir.glob(source+'/{router/phone-dns,scripts}/*.rb').each{|p|PanelStore.run('/usr/bin/ruby','-c',p)}
  Dir.glob(source+'/router/phone-dns/*.init').each{|p|PanelStore.run('sh','-n',p)}
  Dir.glob(source+'/scripts/*.sh').each{|p|PanelStore.run('sh','-n',p)}
  %w[controller/phone_panel.lua model/cbi/phone_panel_settings.lua].each do |file|
   path=source+'/router/luci/'+file
   PanelStore.run('lua','-e',"assert(loadfile(#{PanelStore.json(path)}))")
  end
  Dir.glob(source+'/router/phone-dns/*.lua').each{|path|PanelStore.run('lua','-e',"assert(loadfile(#{PanelStore.json(path)}))")}
  PanelStore.run('sh',source+'/scripts/maintenance.sh','doctor')
 end
 def self.install_local(source,target,pairs:nil,expected_current:nil)
  raise 'Invalid source commit' unless target.to_s.match?(SHA)
  PanelStore.with_lock(PanelStore.path('/var/lock/phone-panel.lock'),true) do
   raise '安装版本已变化，请重新检查更新' if expected_current&&current!=expected_current
   raise '上次程序升级尚未恢复，请先恢复操作前版本' unless pending_recovery.empty?
   phase('检查程序语法、依赖与可用空间');validate_source(source)
   protected=protected_paths;install_pairs=pairs||entries(source)
   new_bytes=install_pairs.sum{|from,_,_|File.size(from)}
   old_bytes=install_pairs.sum{|_,to,_|f=PanelStore.path(to);File.file?(f) ? File.size(f) : 0}
   protected_bytes=protected.sum{|p|f=PanelStore.path(p);File.file?(f) ? File.size(f) : 0}
   free=PhoneMaintenanceHealth.space('/root')
   raise '安装、备份和恢复所需空间不足，原版本未修改' unless free&&free>=new_bytes+old_bytes*2+protected_bytes+16*1024*1024
   backup=PanelStore.run('sh',source+'/scripts/maintenance.sh','backup').strip
   protected=protected_paths
   old=health_check;old_groups=old['groups'].map{|g|g['id']};old_devices=old['device_count']
   pids=PanelStore.capture('pidof','clash','sing-box','dnsmasq').first.split.sort
   validate_runtime=lambda do
    data=health_check
    raise 'Managed devices changed during update' unless data['device_count']==old_devices&&data['groups'].map{|g|g['id']}==old_groups
    old['groups'].each do |group|
     new_group=data['groups'].find{|g|g['id']==group['id']}
     %w[dns_listening socks_listening binding_ok].each{|key|raise 'Listener readiness regressed' if group[key]&&!new_group[key]}
    end
    %w[guard_ready dns_redirect_ready].each{|key|raise 'Network protection regressed' if old[key]&&!data[key]}
    raise 'Network services were unexpectedly restarted' unless PanelStore.capture('pidof','clash','sing-box','dnsmasq').first.split.sort==pids
   end
   transaction(install_pairs,target,config_backup:backup,protected:protected,activator:method(:activate),validator:validate_runtime,recovery_validator:validate_runtime,baseline:old.slice('device_count','groups','guard_ready','dns_redirect_ready'))
  end || raise('Another configuration task is running')
 end
 def self.discard_stage(directory)
  Dir.children(directory).each do |name|
   file=directory+'/'+name
   File.directory?(file)&&!File.symlink?(file) ? discard_stage(file) : File.delete(file)
  end
  Dir.rmdir(directory)
 end
 def self.upgrade(target,fingerprint:nil)
  raise 'Invalid target commit' unless target.to_s.match?(SHA)
  phase('核对正式 Release、版本与 CI')
  checked=check
  raise '正式发布已变化或未通过检查，请重新检查更新' unless checked['can_upgrade']&&checked['latest']==target&&fingerprint.to_s.match?(/\A[a-f0-9]{64}\z/)&&checked['fingerprint']==fingerprint
  temp=PanelStore.ram+'/release-'+target+'-'+Random.bytes(6).unpack1('H*');PanelStore.mkdir(temp)
  archive=temp+'/update.tgz';phase('下载正式发布安装包')
  PanelStore.run('curl','--noproxy','','-fLsS','--proto','=https','--proto-redir','=https','--connect-timeout','5','--max-time','90',
   '--max-filesize','20971520','-o',archive,checked['asset_url'])
  phase('校验下载大小与 SHA-256')
  raise '下载包大小或 SHA-256 不符，原版本未修改' unless File.size(archive)==checked['asset_size']&&Digest::SHA256.file(archive).hexdigest==checked['asset_sha256']
  source=temp+'/package';extract(archive,source);phase('验证完整文件清单与版本兼容性')
  pairs=PhoneUpdatePackage.entries(source,target,checked['tag'])
  record=install_local(source+'/files/usr/share/phone-panel',target,pairs:pairs,expected_current:checked['current'])
  {'ok'=>true,'message'=>'正式发布已安装，文件、权限及服务验收通过；设备配置保持不变。','program_backup'=>record['id'],'checks'=>{'program_files'=>true,'program_runtime'=>true}}
 ensure
  if defined?(temp)&&temp&&File.directory?(temp)
   begin
    raise 'Unsafe temporary release directory' unless File.dirname(temp)==PanelStore.ram&&File.basename(temp).match?(/\Arelease-[a-f0-9]{40}-[a-f0-9]{12}\z/)&&!File.symlink?(temp)
    discard_stage(temp)
   rescue=>cleanup_error
    phase('临时目录清理未完成',{'cleanup_warning'=>'请检查路由器临时空间；安装结果以验收记录为准'})
   end
  end
 end
 def self.recover_interrupted(id)
  PanelStore.with_lock(PanelStore.path('/var/lock/phone-panel.lock'),true) do
   record=pending_recovery.find{|r|r['id']==id&&r['recoverable']}
   raise '此记录不可恢复或升级进程仍在运行' unless record&&record['from'].to_s.match?(SHA)
   phase('恢复未完成升级之前的程序')
   files_ok=false
   begin
    stop_monitor_for_restore(id);restore_files(id)
    atomic_code(PanelStore.path('/usr/share/phone-panel/deployed-commit'),record['from']+"\n",0600);files_ok=true
    activate;assert_health(health_check,record['baseline'])
    before=record['protected_before'];raise 'Network configuration changed since upgrade; inspect manually' if before.is_a?(Hash)&&hashes(before.keys)!=before
    record.merge!('status'=>'rolled_back','files_restored'=>true,'runtime_restored'=>true,'rollback_error'=>nil)
    PanelStore.write(root+'/'+id+'/record.yaml',record)
    {'ok'=>true,'message'=>'操作前程序文件已恢复，服务状态检查通过。','files_restored'=>true,'runtime_restored'=>true}
   rescue=>e
    record.merge!('status'=>'recovery_required','files_restored'=>files_ok,'runtime_restored'=>false,'rollback_error'=>e.message)
    PanelStore.write(root+'/'+id+'/record.yaml',record)
    raise InstallError.new({'error'=>e.message,'files_restored'=>files_ok,'runtime_restored'=>false,'recovery_required'=>true,'program_backup'=>id})
   end
  end || raise('Another configuration task is running')
 end
 def self.restore(id)
  raise 'Invalid recovery ID' unless id.to_s.match?(ID)
  record=PanelStore.read(root+'/'+id+'/record.yaml',{})
  if PhoneBindings.has_policy?
   entries=PanelStore.read(root+'/'+id+'/manifest.yaml',[])
   compatible=%w[/etc/phone-dns/binding-registry.rb /etc/init.d/phone-panel-guard].all?{|path|entries.any?{|e|e['destination']==path&&e['present']}}
   raise '此程序快照早于独立绑定格式，不允许降级；请保留当前保护并恢复兼容快照' unless compatible
  end
  return recover_interrupted(id) if %w[prepared installing recovering recovery_required].include?(record['status'])
  raise 'Recovery record is unavailable' unless record['status']=='installed' && record['from'].to_s.match?(SHA)
  PanelStore.with_lock(PanelStore.path('/var/lock/phone-panel.lock'),true) do
   # Only program files are restored; later DHCP/device edits are preserved.
   paths=protected_paths;before=hashes(paths)
   manifest=PanelStore.read(root+'/'+id+'/manifest.yaml',[])
   live_pairs=manifest.map{|e|[nil,e['destination'],e['mode']]}
   rescue_record=snapshot(live_pairs,record['from']);baseline=health_check
   rescue_record.merge!('status'=>'installing','protected_before'=>before,'baseline'=>baseline.slice('device_count','groups','guard_ready','dns_redirect_ready'));PanelStore.write(root+'/'+rescue_record['id']+'/record.yaml',rescue_record)
   begin
    stop_monitor_for_restore(id)
    restore_files(id);atomic_code(PanelStore.path('/usr/share/phone-panel/deployed-commit'),record['from']+"\n",0600)
    activate;assert_health(health_check,baseline)
    raise 'Network configuration changed' unless hashes(paths)==before
    record['status']='restored';PanelStore.write(root+'/'+id+'/record.yaml',record)
    rescue_record['status']='installed';PanelStore.write(root+'/'+rescue_record['id']+'/record.yaml',rescue_record)
    {'ok'=>true,'restored'=>id,'version'=>record['from'],'message'=>'程序版本已恢复并通过状态验收；当前设备配置保留。'}
   rescue=>failure
    files_ok=false;runtime_ok=false;recovery_error=nil
    begin
     restore_files(rescue_record['id']);atomic_code(PanelStore.path('/usr/share/phone-panel/deployed-commit'),rescue_record['from']+"\n",0600);files_ok=true
     activate;assert_health(health_check,baseline)
     raise 'Network configuration changed during recovery' unless hashes(paths)==before
     runtime_ok=true
    rescue=>e;recovery_error=e.message;end
    rescue_record.merge!('status'=>files_ok&&runtime_ok ? 'rolled_back' : 'recovery_required','files_restored'=>files_ok,'runtime_restored'=>runtime_ok,'rollback_error'=>recovery_error)
    PanelStore.write(root+'/'+rescue_record['id']+'/record.yaml',rescue_record)
    raise InstallError.new({'error'=>failure.message,'files_restored'=>files_ok,'runtime_restored'=>runtime_ok,'recovery_required'=>!(files_ok&&runtime_ok),'program_backup'=>rescue_record['id'],'rollback_error'=>recovery_error})
   end
  end || raise('Another configuration task is running')
 end
end

if $0==__FILE__
 begin
  action=ARGV.shift
  result=case action
   when 'check';PhoneRelease.check
   when 'check-request'
    PhoneRelease.phase('核对正式发布、完整安装包及 CI');data=PhoneRelease.check;{'ok'=>true,'message'=>data['message']}
   when 'upgrade';PhoneRelease.upgrade(ARGV.fetch(0),fingerprint:ARGV[1])
   when 'upgrade-request'
    request=YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false);PhoneRelease.upgrade(request.fetch('target'),fingerprint:request.fetch('fingerprint'))
   when 'restore-request'
    request=YAML.safe_load(File.read(ARGV.fetch(0)),aliases:false);PhoneRelease.restore(request.fetch('release'))
   when 'restore';PhoneRelease.restore(ARGV.fetch(0))
   when 'install-local';PhoneRelease.install_local(ARGV.fetch(0),ARGV.fetch(1))
   else;raise 'Unsupported release action'
  end
  puts PanelStore.json(result)
 rescue =>e
  if %w[check-request upgrade-request restore-request].include?(action)
   puts PanelStore.json(e.is_a?(PhoneRelease::InstallError) ? e.result : {'error'=>e.message});exit 1
  end
  warn e.message
  exit 1
 end
end
