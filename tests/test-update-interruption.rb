require_relative 'support'
require_relative '../router/phone-dns/releases'
if RUBY_PLATFORM.match?(/mswin|mingw/)
 puts 'Update SIGKILL recovery: requires Unix fork; verified by Linux CI';exit
end
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PhoneRelease.define_singleton_method(:file_hash){|p|Digest::SHA256.file(p).hexdigest}
 PhoneRelease.define_singleton_method(:activate){true}
 PhoneRelease.define_singleton_method(:health_check){{'groups'=>[],'device_count'=>0}}
 code='/etc/phone-dns/releases.rb';actual=PanelStore.path(code)
 marker=PanelStore.path('/usr/share/phone-panel/deployed-commit')
 PanelStore.atomic(actual,'old code');PanelStore.atomic(marker,'a'*40)
 incoming=root+'/new.rb';File.binwrite(incoming,'new code')
 ready,signal=IO.pipe
 pid=fork do
  ready.close;original=PhoneRelease.method(:atomic_code)
  PhoneRelease.define_singleton_method(:atomic_code) do |path,data,mode|
   original.call(path,data,mode)
   if path==actual
    signal.write('installed-first-file');signal.flush;sleep 30
   end
  end
  PhoneRelease.transaction([[incoming,code,0600]],'b'*40)
  exit! 2
 end
 signal.close
 begin
  assert(IO.select([ready],nil,nil,10),'installer did not reach write checkpoint')
  assert(ready.readpartial(64)=='installed-first-file')
  Process.kill('KILL',pid);Process.waitpid(pid);pid=nil
  assert(File.binread(actual)=='new code'&&PhoneRelease.current=='a'*40,'failure must occur between program copy and version commit')
  pending=PhoneRelease.pending_recovery
  assert(pending.size==1&&pending.first['recoverable'],'dead installer must leave a recoverable durable checkpoint')
  assert(PhoneRelease.info['update']['can_upgrade']==false)
  assert(PhoneRelease.restore(pending.first['id'])['ok'])
  assert(File.binread(actual)=='old code'&&PhoneRelease.current=='a'*40&&PhoneRelease.pending_recovery.empty?)
 ensure
  Process.kill('KILL',pid) rescue nil if pid
  Process.waitpid(pid) rescue nil if pid
  ready.close
 end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Actual SIGKILL during program installation: durable checkpoint, upgrade block and verified original-code recovery PASS'
