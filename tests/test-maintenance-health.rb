require_relative 'support'
require_relative '../router/phone-dns/maintenance-health'
fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 PanelStore.mkdir(PanelStore.path('/root/phone-panel-transactions'));PanelStore.mkdir(PanelStore.path('/var/lock'))
 5.times do |i|
  dir=PanelStore.path('/root/phone-panel-transactions/2026010100000000000000'+i.to_s+'-123');PanelStore.mkdir(dir);File.write(dir+'/manifest.json','{}');File.utime(Time.now-i*86400*10,Time.now-i*86400*10,dir)
 end
 link=PanelStore.path('/root/phone-panel-transactions/123-link');File.symlink('/etc',link)
 PhoneMaintenanceHealth.define_singleton_method(:space){|p|512*1024*1024}
 PanelStore.define_singleton_method(:capture){|*args|['',0]}
 core=PanelStore.path('/etc/openclash/clash');PanelStore.mkdir(File.dirname(core));File.write(core,'fixture');File.chmod(0700,core)
 assert(PhoneMaintenanceHealth.preflight['ok'])
 PhoneMaintenanceHealth.define_singleton_method(:space){|p|0};assert(!PhoneMaintenanceHealth.preflight['ok'],'low disk must block update')
 rows=PhoneMaintenanceHealth.info
 assert(rows['count']==5,'symlinks must not enter inventory');assert(rows['items'].count{|r|r['recyclable']}==2)
 id=rows['items'].last['id'];plan=PhoneMaintenanceHealth.cleanup_plan({'ids'=>[id]})
 rejects{PhoneMaintenanceHealth.cleanup({'ids'=>[id],'revision'=>'stale'})}
 result=PhoneMaintenanceHealth.cleanup({'ids'=>[id],'revision'=>plan['revision']})
 assert(result['ok']&&!File.exist?(PanelStore.path(id)));assert(File.file?(result['recycle']+'/restore-manifest.json'))
 rejects{PhoneMaintenanceHealth.cleanup_plan({'ids'=>['/etc/config/dhcp']})}
 rejects{PhoneMaintenanceHealth.cleanup_plan({'ids'=>[rows['items'].first['id']]})}
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Backup inventory, retention, path rejection, revision checks and reversible recycling PASS'
