module('luci.controller.phone_panel', package.seeall)
local function feature_json(action,arg)
 local h=require('luci.http')
 local command='/usr/bin/ruby /etc/phone-dns/feature-api.rb '..require('luci.util').shellquote(action)
 if arg then command=command..' '..require('luci.util').shellquote(arg) end
 local output=require('luci.sys').exec(command..' 2>/dev/null')
 h.header('Cache-Control','no-store');h.prepare_content('application/json')
 if not require('luci.jsonc').parse(output) then h.status(500,'Internal Server Error');h.write('{"error":"功能服务未返回有效响应"}');return end
 h.write(output)
end
function index()
 local p=entry({'admin','services','phone_panel'},alias('admin','services','phone_panel','home'),'手机出口与 DNS',55)
 entry({'admin','services','phone_panel','home'},template('phone_panel'),'主页',10)
 entry({'admin','services','phone_panel','maintenance'},template('phone_panel'),'管理维护',20)
 entry({'admin','services','phone_panel','settings'},cbi('phone_panel_settings'),'设置 / Settings',60)
 entry({'admin','services','phone_panel','initialize'},post('initialize_panel')).leaf=true
 entry({'admin','services','phone_panel','tasks'},call('panel_tasks')).leaf=true
 entry({'admin','services','phone_panel','task_start'},post('panel_task_start')).leaf=true
 entry({'admin','services','phone_panel','device_preview'},post('device_edit_preview')).leaf=true
 entry({'admin','services','phone_panel','device_apply'},post('device_edit_apply')).leaf=true
 entry({'admin','services','phone_panel','node_catalog'},call('node_catalog')).leaf=true
 entry({'admin','services','phone_panel','node_assets'},call('node_assets')).leaf=true
 entry({'admin','services','phone_panel','node_preview'},post('node_preview')).leaf=true
 entry({'admin','services','phone_panel','node_apply'},post('node_apply')).leaf=true
 entry({'admin','services','phone_panel','node_test'},post('node_test')).leaf=true
 entry({'admin','services','phone_panel','operation_restore'},post('operation_restore')).leaf=true
 entry({'admin','services','phone_panel','operations'},call('operations')).leaf=true
 entry({'admin','services','phone_panel','workflow_assets'},call('workflow_assets')).leaf=true
 entry({'admin','services','phone_panel','maintenance_health'},call('maintenance_health')).leaf=true
 entry({'admin','services','phone_panel','backup_preview'},post('backup_preview')).leaf=true
 entry({'admin','services','phone_panel','backup_recycle'},post('backup_recycle')).leaf=true
 p.dependent=true
 p.acl_depends={'luci-app-openclash'}
 entry({'admin','services','phone_panel','status'},call('status')).leaf=true
 entry({'admin','services','phone_panel','probe'},call('probe')).leaf=true
 entry({'admin','services','phone_panel','preview'},post('preview_device')).leaf=true
 entry({'admin','services','phone_panel','apply'},post('apply_device')).leaf=true
 entry({'admin','services','phone_panel','job'},call('job_status')).leaf=true
 entry({'admin','services','phone_panel','assets'},call('feature_asset')).leaf=true
 entry({'admin','services','phone_panel','candidates'},call('feature_candidates')).leaf=true
 entry({'admin','services','phone_panel','health'},call('feature_health')).leaf=true
 entry({'admin','services','phone_panel','versions'},call('feature_versions')).leaf=true
 entry({'admin','services','phone_panel','bulk_preview'},post('bulk_preview')).leaf=true
 entry({'admin','services','phone_panel','bulk_apply'},post('bulk_apply')).leaf=true
 entry({'admin','services','phone_panel','ack'},post('feature_ack')).leaf=true
 entry({'admin','services','phone_panel','check_update'},post('feature_check_update')).leaf=true
 entry({'admin','services','phone_panel','upgrade'},post('feature_upgrade')).leaf=true
 entry({'admin','services','phone_panel','restore_release'},post('feature_restore')).leaf=true
end
function status()
 local h=require('luci.http')
 h.header('Cache-Control','no-store')
 h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/panel-status.rb 2>/dev/null'))
end
function probe()
 local id=require('luci.http').formvalue('id') or ''
 if not id:match('^%d+$') or #id>3 then require('luci.http').status(400,'Bad Request');return end
 feature_json('probe',id)
end

local function device_request(mode)
 local h=require('luci.http');local j=require('luci.jsonc');local d=require('luci.dispatcher')
 if not d.test_post_security() then return end
 local raw=h.formvalue('payload') or ''
 h.header('Cache-Control','no-store');h.prepare_content('application/json')
 if #raw>32768 then h.status(400,'Bad Request');h.write('{"error":"request too large"}');return end
 local p=j.parse(raw)
 if type(p)~='table' then h.status(400,'Bad Request');h.write('{"error":"请求格式无效"}');return end
 local rand=io.open('/dev/urandom','rb');local bytes=rand:read(16);rand:close()
 local path='/etc/phone-dns/panel-requests/'..bytes:gsub('.',function(c)return string.format('%02x',c:byte())end)..'.json'
 local fd=io.open(path,'w')
 if not fd then h.status(500,'Internal Server Error');h.write('{"error":"无法创建安全请求文件"}');return end
 -- Preserve object/array/null distinctions: Lua's empty table would serialize {} as [].
 require('nixio.fs').chmod(path,'600');fd:write(raw);fd:close()
 local feature_modes={ack=true,check_update=true,upgrade=true,restore_release=true}
 local async_modes={['edit-apply']='device_edit',['node-apply']='node_change',['node-test']='node_test',restore='restore',apply='device_add',['batch-apply']='device_batch'}
 local node_modes={['node-preview']=true,['node-apply']=true}
 local backup_modes={['cleanup-preview']=true,cleanup=true}
 local backend=backup_modes[mode] and 'maintenance-health.rb' or async_modes[mode] and 'operations.rb' or node_modes[mode] and 'node-manager.rb' or feature_modes[mode] and 'feature-api.rb' or ((mode=='edit-preview' or mode=='edit-apply') and 'device-operation.rb' or 'device-manager.rb')
 local commandmode=async_modes[mode] or mode=='node-preview' and 'preview' or mode=='node-apply' and 'apply' or mode=='edit-preview' and 'preview' or mode=='edit-apply' and 'apply' or mode
 local output=require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/'..backend..' '..commandmode..' '..require('luci.util').shellquote(path)..' 2>/dev/null')
 require('nixio.fs').remove(path)
 if not j.parse(output) then h.status(500,'Internal Server Error');h.write('{"error":"设备管理服务未返回有效响应"}');return end
 h.write(output)
end
function preview_device() device_request('preview') end
function apply_device() device_request('apply') end
function job_status()
 local h=require('luci.http');local id=h.formvalue('id') or ''
 h.header('Cache-Control','no-store');h.prepare_content('application/json')
 if not id:match('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%-%x%x%x%x%x%x%x%x%x%x%x%x$') then h.status(400,'Bad Request');h.write('{"error":"任务 ID 无效"}');return end
 local output=require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/device-manager.rb job '..require('luci.util').shellquote(id)..' 2>/dev/null')
 h.write(output)
end

function initialize_panel()
 local h=require('luci.http');local d=require('luci.dispatcher');local j=require('luci.jsonc')
 if not d.test_post_security() then return end
 local s=require('luci.sys')
 local check=s.exec('sh /usr/share/phone-panel/scripts/maintenance.sh doctor 2>&1; echo CHECK_EXIT:$?')
 h.header('Cache-Control','no-store');h.prepare_content('application/json')
 if h.formvalue('confirm')~='INITIALIZE' then
  h.write(j.stringify({ok=check:match('CHECK_EXIT:0%s*$')~=nil,preview=check,warning='初始化会重启 OpenClash，短暂中断代理网络；请保留本地管理连接。'}));return
 end
 if not check:match('CHECK_EXIT:0%s*$') then h.write(j.stringify({error=check}));return end
 h.write(s.exec('/usr/bin/ruby /etc/phone-dns/tasks.rb start initialize 2>/dev/null'))
end

function panel_tasks()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/tasks.rb list 2>/dev/null'))
end
function panel_task_start()
 local h=require('luci.http')
 if not require('luci.dispatcher').test_post_security() then return end
 local a=h.formvalue('action') or ''
 local allowed={doctor=true,backup=true,initialize=true,dependencies=true,repair_hooks=true}
 h.prepare_content('application/json')
 if not allowed[a] or h.formvalue('confirm')~='CONFIRM' then h.status(400,'Bad Request');h.write('{"error":"操作未确认"}');return end
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/tasks.rb start '..require('luci.util').shellquote(a)..' 2>/dev/null'))
end

function device_edit_preview() device_request('edit-preview') end
function device_edit_apply() device_request('edit-apply') end

function feature_asset()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('text/javascript; charset=utf-8')
 h.write(require('nixio.fs').readfile('/usr/share/phone-panel/router/luci/resources/features.js') or '')
end
function feature_candidates() feature_json('candidates') end
function feature_versions() feature_json('versions') end
function feature_health() feature_json('health',require('luci.http').formvalue('id') or '') end
function bulk_preview() device_request('batch-preview') end
function bulk_apply() device_request('batch-apply') end
function feature_ack() device_request('ack') end
function feature_check_update() device_request('check_update') end
function feature_upgrade() device_request('upgrade') end
function feature_restore() device_request('restore_release') end

function node_preview() device_request('node-preview') end
function node_apply() device_request('node-apply') end
function node_catalog()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/node-manager.rb catalog 2>/dev/null'))
end
function node_assets()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('text/javascript; charset=utf-8')
 h.write(require('nixio.fs').readfile('/usr/share/phone-panel/router/luci/resources/nodes.js') or '')
end

function node_test() device_request('node-test') end
function operations()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/operations.rb list 2>/dev/null'))
end

function workflow_assets()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('text/javascript; charset=utf-8')
 h.write(require('nixio.fs').readfile('/usr/share/phone-panel/router/luci/resources/workflow.js') or '')
end

function operation_restore() device_request('restore') end

function maintenance_health()
 local h=require('luci.http');h.header('Cache-Control','no-store');h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/maintenance-health.rb inventory 2>/dev/null'))
end

function backup_preview() device_request('cleanup-preview') end
function backup_recycle() device_request('cleanup') end
