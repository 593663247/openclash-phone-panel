require_relative 'support'
require_relative '../router/phone-dns/luci-cache'

fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.mkdir(PanelStore.path('/tmp/luci-modulecache/nested'))
 removed=%w[/tmp/luci-indexcache /tmp/luci-indexcache.fixture.json /tmp/luci-modulecache/luci.controller.phone_panel /tmp/luci-modulecache/nested/phone_panel_settings.luc]
 retained=%w[/tmp/luci-modulecache/luci.controller.other /tmp/unrelated]
 (removed+retained).each{|name|File.binwrite(PanelStore.path(name),'fixture')}
 PhoneLuciCache.clear
 removed.each{|name|assert(!File.exist?(PanelStore.path(name)),'stale menu/module cache remains: '+name)}
 retained.each{|name|assert(File.binread(PanelStore.path(name))=='fixture','unrelated file must be preserved')}
 PhoneLuciCache.clear # Repeated installation is safe without existing cache files.
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'LuCI cache refresh: legacy/suffixed menu caches, panel modules and unrelated-file preservation PASS'
