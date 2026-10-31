require_relative 'panel-store'

# LuCI rebuilds its menu on the next request. Do not restart web/network services.
module PhoneLuciCache
 def self.clear
  Dir.glob(PanelStore.path('/tmp/luci-indexcache')+'*').each do |file|
   File.delete(file) if File.file?(file) && !File.symlink?(file)
  end
  directory=PanelStore.path('/tmp/luci-modulecache')
  return unless File.directory?(directory) && !File.symlink?(directory)
  root=File.realpath(directory)+'/'
  Dir.glob(directory+'/**/*phone_panel*').each do |file|
   next unless File.file?(file) && !File.symlink?(file) && File.realpath(file).start_with?(root)
   File.delete(file)
  end
 end
end

PhoneLuciCache.clear if __FILE__==$PROGRAM_NAME
