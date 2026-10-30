def assert(value,message='Assertion failed');raise message unless value;end
def rejects(message='Expected rejection')
 rejected=false
 begin;yield;rescue StandardError;rejected=true;end
 assert(rejected,message)
end
def fixture_directory
 path=File.join(Dir.pwd,".panel-fixture-#{Process.pid}-#{rand(1<<32)}")
 Dir.mkdir(path,0700)
 yield path
ensure
 if path && Dir.exist?(path)
  raise 'Unsafe fixture cleanup' unless File.dirname(File.expand_path(path))==File.expand_path(Dir.pwd)
  Dir.glob(path+'/**/*',File::FNM_DOTMATCH).sort_by{|p|-p.count('/').to_i}.each do |p|
   next if %w[. ..].include?(File.basename(p))
   File.directory?(p) && !File.symlink?(p) ? Dir.rmdir(p) : File.delete(p)
  end
  Dir.rmdir(path)
 end
end
