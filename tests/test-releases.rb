require_relative 'support'
require 'stringio'
require_relative '../router/phone-dns/releases'
PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
def tar_entry(name,data='',type='0')
 header="\0".b*512;header[0,name.bytesize]=name.b
 header[124,12]="%011o\0"%data.bytesize;header[148,8]=' '*8;header[156,1]=type
 header[148,8]="%06o\0 "%header.bytes.sum
 header+data.b+"\0".b*((512-data.bytesize%512)%512)
end
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 source=root+'/archive';PanelStore.mkdir(source)
 PhoneRelease.unpack_stream(StringIO.new(tar_entry('release/router/example.rb','safe')),source)
 assert(File.read(source+'/router/example.rb')=='safe')
 ['release/../../escape','/absolute/path','release/..\\escape'].each do |name|
  rejects('Unsafe archive accepted'){PhoneRelease.unpack_stream(StringIO.new(tar_entry(name,'x')),root+'/bad')}
 end
 rejects('Archive symlink accepted'){PhoneRelease.unpack_stream(StringIO.new(tar_entry('release/link','target','2')),root+'/links')}
 rejects('Multiple archive roots accepted'){PhoneRelease.unpack_stream(StringIO.new(tar_entry('a/file','x')+tar_entry('b/file','y')),root+'/roots')}
 rejects('Duplicate file accepted'){PhoneRelease.unpack_stream(StringIO.new(tar_entry('a/file','x')+tar_entry('a/file','y')),root+'/duplicate')}
 assert(!PhoneRelease.allowed_destination?('/etc/config/dhcp'),'rollback must not overwrite device/network configuration')
 assert(!PhoneRelease.allowed_destination?('/usr/share/phone-panel/../../etc/shadow'))
 # Deterministic content fingerprints isolate transaction tests from OS command availability.
 def PhoneRelease.hashes(paths)
  paths.to_h{|p|[p,File.binread(PanelStore.path(p)).unpack1('H*')]}
 end
 def PhoneRelease.file_hash(path);File.binread(path).unpack1('H*');end
 def PhoneRelease.protected_paths;['/etc/config/dhcp'];end
 def PhoneRelease.activate;true;end
 def PhoneRelease.health_check;{'groups'=>[]};end
 code='/etc/phone-dns/example.rb';actual=PanelStore.path(code);PanelStore.mkdir(File.dirname(actual));File.write(actual,'old')
 config=PanelStore.path('/etc/config/dhcp');PanelStore.mkdir(File.dirname(config));File.write(config,'original device lease')
 marker=PanelStore.path('/usr/share/phone-panel/deployed-commit');PanelStore.mkdir(File.dirname(marker));File.write(marker,'a'*40)
 incoming=root+'/incoming.rb';File.write(incoming,'new')
 record=PhoneRelease.transaction([[incoming,code,0600]],'b'*40,protected:['/etc/config/dhcp'],validator:->{assert(File.read(actual)=='new')})
 assert(record['status']=='installed'&&PhoneRelease.current=='b'*40)
 File.write(config,'a later legitimate device edit')
 PhoneRelease.restore(record['id'])
 assert(File.read(actual)=='old'&&PhoneRelease.current=='a'*40)
 assert(File.read(config)=='a later legitimate device edit','program rollback must preserve later device edits')
 rejects('Failed activation was not rejected') do
  PhoneRelease.transaction([[incoming,code,0600]],'c'*40,protected:['/etc/config/dhcp'],validator:->{raise 'new program failed'})
 end
 assert(File.read(actual)=='old'&&PhoneRelease.current=='a'*40,'failed install must restore code and marker')
 File.write(PhoneRelease.root+'/'+record['id']+'/file-0','corrupted snapshot')
 rejects('Corrupted snapshot was restored'){PhoneRelease.restore_files(record['id'])}
 assert(File.read(actual)=='old','integrity failure must happen before changing any program file')
 def PhoneRelease.http_json(path)
  return {'sha'=>'b'*40} if path=='/commits/main'
  return {'status'=>@test_comparison||'ahead'} if path.start_with?('/compare/')
  {'workflow_runs'=>[{'path'=>'.github/workflows/ci.yml','head_sha'=>'b'*40,'status'=>'completed','conclusion'=>@test_ci||'success','run_number'=>1}]}
 end
 assert(PhoneRelease.check['can_upgrade'])
 PhoneRelease.instance_variable_set(:@test_ci,'failure');assert(!PhoneRelease.check['can_upgrade'],'CI failure must block installation')
 PhoneRelease.instance_variable_set(:@test_ci,'success');PhoneRelease.instance_variable_set(:@test_comparison,'diverged')
 assert(!PhoneRelease.check['can_upgrade'],'divergent history must not silently overwrite')
 rejects('Arbitrary SHA accepted'){PhoneRelease.upgrade('; arbitrary shell')}
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Bounded archive extraction, code-only recovery, failed-install rollback and pinned CI update gate PASS'
