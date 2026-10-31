require_relative 'support'
# Exercise the actual restart helper with a remapped marker and stubbed init calls.
fixture_directory do |root|
 marker=root+'/marker';log=root+'/private-log'
 file_proxy=Class.new
 file_proxy.define_singleton_method(:path){|p|p=='/tmp/openclash.change' ? marker : p}
 [:exist?,:binread,:delete].each{|method|file_proxy.define_singleton_method(method){|p|File.public_send(method,path(p))}}
 file_proxy.define_singleton_method(:open){|p,*args,&block|File.open(path(p),*args,&block)}
 mod=Module.new;mod.const_set(:File,file_proxy)
 path=File.expand_path('../router/phone-dns/device-operation.rb',__dir__)
 code=File.read(path).split(/^base=/).first.lines.reject{|l|l.start_with?('require')}.join
 mod.module_eval(code,path)
 runner=Object.new.extend(mod)
 commands=[]
 runner.define_singleton_method(:edit_run){|*args|commands<<args;true}
 runner.instance_variable_set(:@edit_log,log)
 File.write(marker,'old generated configuration marker')
 assert(runner.send(:edit_restart_proxy))
 assert(!File.exist?(marker),'quick-start marker must be invalidated')
 assert(File.read(log+'.quickstart')=='old generated configuration marker','marker must be copied before removal, not renamed across mounts')
 assert(File.stat(log+'.quickstart').mode & 0777 == 0600,'marker backup must be private')
 assert(commands==[['/etc/init.d/openclash','stop'],['/etc/init.d/openclash','start']])
 File.write(marker,'still needed')
 runner.define_singleton_method(:edit_run){|*args|false}
 assert(!runner.send(:edit_restart_proxy))
 assert(File.read(marker)=='still needed','failed stop must not invalidate marker')
end
puts 'Edit restart: invalidates quick-start, uses private cross-filesystem-safe backup, preserves marker on failed stop PASS'
