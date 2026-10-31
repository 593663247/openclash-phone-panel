require 'yaml'
require_relative 'settings'

module PanelStore
 def self.path(path)
  root=ENV['PHONE_PANEL_TEST_ROOT']
  return path unless root
  raise 'Test root requires explicit test mode' unless ENV['PHONE_PANEL_TEST']=='1'
  File.join(root,path.sub(%r{\A/},''))
 end
 def self.mkdir(path)
  return if Dir.exist?(path)
  parent=File.dirname(path);mkdir(parent) unless parent==path
  Dir.mkdir(path,0700)
  sync_directory(parent)
 end
 def self.read(path,default={})
  return default unless File.file?(path)
  value=YAML.safe_load(File.binread(path),aliases:false)
  value.is_a?(default.class) ? value : default
 rescue Psych::Exception
  default
 end
 def self.write(path,value)
  atomic(path,json(value))
 end
 def self.atomic(path,data)
  mkdir(File.dirname(path))
  temporary=path+".tmp-#{Process.pid}-#{rand(1<<32)}"
  File.open(temporary,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.binmode;f.write(data);f.flush;f.fsync}
  File.rename(temporary,path)
  sync_directory(File.dirname(path))
 ensure
  File.delete(temporary) if defined?(temporary) && temporary && File.file?(temporary)
 end
 def self.sync_directory(directory)
  return if RUBY_PLATFORM.match?(/mswin|mingw/)
  File.open(directory,File::RDONLY){|file|file.fsync}
 end
 def self.capture(*args)
  output=IO.popen(args+[{err:File::NULL}],&:read)
  [output,$?.exitstatus]
 rescue Errno::ENOENT
  ['',127]
 end
 def self.run(*args)
  output,code=capture(*args)
  raise "Command failed: #{File.basename(args.first)} (#{code})" unless code==0
  output
 end
 def self.json(value)
  case value
  when Hash;'{'+value.map{|k,v|json(k.to_s)+':'+json(v)}.join(',')+'}'
  when Array;'['+value.map{|v|json(v)}.join(',')+']'
  when String;'"'+value.gsub(/["\\\x00-\x1f]/){|c|c=='"' ? '\\"' : c=='\\' ? '\\\\' : '\\u%04x'%c.ord}+'"'
  when TrueClass;'true';when FalseClass;'false';when NilClass;'null';else;value.to_s;end
 end
 def self.state;path('/etc/phone-dns/state');end
 def self.ram;path('/tmp/phone-panel');end
 def self.group_id(value)
  text=value.to_s
  raise 'Invalid group ID' unless text.match?(/\A[1-9][0-9]{0,2}\z/) && text.to_i<=PhoneSettings.port('max_groups')
  text.to_i
 end
 def self.with_lock(path,nonblock=false)
  mkdir(File.dirname(path));file=File.open(path,'w',0600)
  return nil unless file.flock(File::LOCK_EX|(nonblock ? File::LOCK_NB : 0))
  yield
 ensure
  file.close if file
 end
end
