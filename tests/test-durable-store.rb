require_relative 'support'
require_relative '../router/phone-dns/panel-store'
unless Process.respond_to?(:fork)
 puts 'SKIP: forced-process-stop atomic-write test runs on Linux CI (fork unavailable here)'
 exit
end
fixture_directory do |root|
 target=root+'/registry';PanelStore.atomic(target,'old-complete')
 reader,writer=IO.pipe
 pid=Process.fork do
  reader.close;original=File.method(:rename)
  File.define_singleton_method(:rename) do |from,to|
   if to==target;writer.write('ready');writer.close;sleep 30;end
   original.call(from,to)
  end
  PanelStore.atomic(target,'new-complete');exit! 0
 end
 writer.close
 begin
  assert(IO.select([reader],nil,nil,5),'child did not reach the pre-rename checkpoint')
  assert(reader.read(5)=='ready')
  Process.kill('KILL',pid);Process.wait(pid);pid=nil
  assert(File.binread(target)=='old-complete','a killed writer must leave the committed registry intact')
  Dir.glob(target+'.tmp-*').each{|file|File.delete(file)}
  PanelStore.atomic(target,'new-complete')
  assert(File.binread(target)=='new-complete'&&File.stat(target).mode&0777==0600)
 ensure
  Process.kill('KILL',pid) if pid
  Process.wait(pid) if pid
  reader.close
 end
end
puts 'PASS: forced writer termination, complete old/new commit, private permissions and restart write'
