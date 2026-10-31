require_relative 'support'
require_relative '../router/phone-dns/releases'

fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 stage=root+'/stage';PanelStore.mkdir(stage)
 target='b'*40;tag='v1.3.0'
 rows=PhoneUpdatePackage::REQUIRED.map do |destination|
  file=stage+'/files'+destination;PanelStore.mkdir(File.dirname(file))
  File.binwrite(file,destination.end_with?('/VERSION') ? '1.3.0' : 'fixture code')
  {'source'=>'files'+destination,'destination'=>destination,'mode'=>destination.start_with?('/etc/init.d/') ? 0755 : 0600,'sha256'=>Digest::SHA256.file(file).hexdigest}
 end
 manifest={'schema'=>1,'min_updater'=>1,'commit'=>target,'version'=>'1.3.0','files'=>rows}
 save=lambda{|data|PanelStore.write(stage+'/update-manifest.json',data)};save.call(manifest)
 pairs=PhoneUpdatePackage.entries(stage,target,tag)
 assert(pairs.size==rows.size+1,'manifest itself must be recorded and installed')
 variants=[manifest.merge('schema'=>2),manifest.merge('min_updater'=>2),manifest.merge('commit'=>'c'*40),manifest.merge('version'=>'1.3.1'),manifest.merge('files'=>rows+[rows.first]),manifest.merge('files'=>rows.drop(1))]
 variants.each{|data|save.call(data);rejects('incompatible/incomplete manifest accepted'){PhoneUpdatePackage.entries(stage,target,tag)}}
 ['../escape','files/../../escape'].each do |path|
  changed=Marshal.load(Marshal.dump(manifest));changed['files'][0]['source']=path;save.call(changed)
  rejects('manifest traversal accepted'){PhoneUpdatePackage.entries(stage,target,tag)}
 end
 changed=Marshal.load(Marshal.dump(manifest));changed['files'][0].merge!('source'=>'files/etc/config/dhcp','destination'=>'/etc/config/dhcp');save.call(changed)
 rejects('update manifest may not overwrite live device configuration'){PhoneUpdatePackage.entries(stage,target,tag)}
 changed=Marshal.load(Marshal.dump(manifest));changed['files'].find{|r|r['destination'].start_with?('/etc/init.d/')}['mode']=0600;save.call(changed)
 rejects('non-executable boot service accepted'){PhoneUpdatePackage.entries(stage,target,tag)}
 save.call(manifest);File.binwrite(stage+'/unexpected','extra')
 rejects('undeclared payload accepted'){PhoneUpdatePackage.entries(stage,target,tag)};File.delete(stage+'/unexpected')
 file=pairs.first[0];bytes=File.binread(file);File.binwrite(file,'altered')
 rejects('corrupt staged file accepted'){PhoneUpdatePackage.entries(stage,target,tag)};File.binwrite(file,bytes)

 %w[/var/lock /etc/config /usr/share/phone-panel].each{|p|PanelStore.mkdir(PanelStore.path(p))}
 marker=PanelStore.path('/usr/share/phone-panel/deployed-commit');PanelStore.atomic(marker,'a'*40)
 live=PanelStore.path(rows.first['destination']);PanelStore.mkdir(File.dirname(live));File.binwrite(live,'old code')
 config='/etc/config/dhcp';PanelStore.atomic(PanelStore.path(config),'unchanged leases')
 PhoneRelease.define_singleton_method(:file_hash){|p|Digest::SHA256.file(p).hexdigest}
 PhoneRelease.define_singleton_method(:activate){true}
 PhoneRelease.define_singleton_method(:health_check){{'groups'=>[],'device_count'=>1,'guard_ready'=>true}}
 PhoneRelease.define_singleton_method(:protected_paths){[config]}
 original_atomic=PhoneRelease.method(:atomic_code);failed=false
 begin
  PhoneRelease.define_singleton_method(:atomic_code) do |path,data,mode|
   if !failed&&path==PanelStore.path(rows[1]['destination']);failed=true;raise Errno::ENOSPC;end
   original_atomic.call(path,data,mode)
  end
  begin
   PhoneRelease.transaction(pairs,target,protected:[config],recovery_validator:->{PhoneRelease.health_check})
   raise 'disk-full injection did not fail'
  rescue PhoneRelease::InstallError=>e
   assert(e.result['files_restored']&&e.result['runtime_restored']&&!e.result['recovery_required'],'partial install must verify complete recovery')
  end
 ensure;PhoneRelease.define_singleton_method(:atomic_code,original_atomic);end
 assert(File.binread(live)=='old code'&&PhoneRelease.current=='a'*40)
 assert(File.binread(PanelStore.path(config))=='unchanged leases')
 assert(!File.exist?(PanelStore.path('/etc/init.d/phone-panel-guard')),'new files must be removed on rollback')
 begin
  PhoneRelease.transaction(pairs,target,protected:[config],validator:->{raise 'bad new service'},recovery_validator:->{raise 'old service not ready'})
 rescue PhoneRelease::InstallError=>e
  assert(e.result['files_restored']&&!e.result['runtime_restored']&&e.result['recovery_required'],'file restoration must not imply service recovery')
  id=e.result['program_backup'];record_path=PhoneRelease.root+'/'+id+'/record.yaml'
  record=PanelStore.read(record_path,{}).merge('boot'=>'previous-boot');PanelStore.write(record_path,record)
  assert(PhoneRelease.pending_recovery.any?{|r|r['id']==id&&r['recoverable']})
  assert(PhoneRelease.restore(id)['ok'],'an interrupted/failed recovery must offer explicit code restoration')
  assert(PhoneRelease.pending_recovery.empty?)
 end
 # Simulate power loss after some files and the version marker were replaced.
 record=PhoneRelease.snapshot(pairs,target);id=record['id']
 original_atomic.call(live,'partial new code',0600);original_atomic.call(marker,target,0600)
 PanelStore.write(PhoneRelease.root+'/'+id+'/record.yaml',record.merge('status'=>'installing','boot'=>'previous-boot','protected_before'=>PhoneRelease.hashes([config])))
 assert(PhoneRelease.info['update']['can_upgrade']==false,'unfinished installs must disable another upgrade')
 assert(PhoneRelease.restore(id)['ok']&&PhoneRelease.current=='a'*40&&File.binread(live)=='old code')
 File.binwrite(PhoneRelease.root+'/'+id+'/record.yaml','broken: [')
 assert(PhoneRelease.pending_recovery.any?{|r|r['status']=='invalid_record'},'damaged journals must not silently permit another upgrade')
 assert(PhoneRelease.info['update']['can_upgrade']==false)
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Release manifests: completeness, checksums, modes, compatibility, disk-full rollback, unverified services and interrupted-install recovery PASS'
