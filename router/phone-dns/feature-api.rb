require_relative 'status-lib'
require_relative 'device-discovery'
require_relative 'releases'
require_relative 'tasks'

module PhoneFeatures
 def self.group(id)
  snapshot=PhoneStatus.collect
  raise '面板状态不可读' if snapshot['error']
  group=snapshot['groups'].find{|g|g['id']==PanelStore.group_id(id)}
  raise '分组不存在' unless group
  group
 end
 def self.execute(action,arg=nil)
  case action
  when 'candidates';PhoneDiscovery.available
  when 'probe';PhoneProbe.run(group(arg))
  when 'health'
   g=group(arg);data=PhoneHealth.summary(g);data['history']=PhoneHealth.read(g).fetch('history',[])
   {'group'=>g['id'],'node'=>g['node'],'health'=>data}
  when 'versions';PhoneRelease.info
  when 'persistence';PhoneBindings.info
  when 'latest_release';{'ok'=>true,'published_release'=>PhoneRelease.published_release(refresh:arg=='refresh')}
  else
   request=YAML.safe_load(File.read(arg),aliases:false)
   raise 'Invalid feature request' unless request.is_a?(Hash)
   case action
   when 'ack';PhoneHealth.acknowledge(group(request['group']),request['exit_ip'])
   when 'check_update'
    PhoneOperations.start('check_update',{})
   when 'upgrade'
    cached=PhoneRelease.info['update']
    raise '请先检查更新并等待 CI 通过' unless cached['can_upgrade'] && cached['latest']==request['target']&&cached['fingerprint']==request['fingerprint']
    raise '请确认升级及本地备份' unless request['confirm']=='UPGRADE'
    PhoneOperations.start('upgrade',{'target'=>request['target'],'fingerprint'=>request['fingerprint'],'tag'=>cached['tag']})
   when 'restore_release'
    raise '请确认只恢复程序、保留设备配置' unless request['confirm']=='RESTORE_CODE'
    PhoneOperations.start('restore_release',{'release'=>request['release']})
   else;raise 'Unsupported feature operation'
   end
  end
 end
end
if $0==__FILE__
 begin;puts PanelStore.json(PhoneFeatures.execute(ARGV[0],ARGV[1]))
 rescue=>e;puts PanelStore.json({'error'=>e.message})
 end
end
