module('luci.controller.phone_panel', package.seeall)
function index()
 local p=entry({'admin','services','phone_panel'},template('phone_panel'),'手机出口与 DNS',55)
 entry({'admin','services','phone_panel','settings'},cbi('phone_panel_settings'),'设置 / Settings',60)
 p.dependent=true
 p.acl_depends={'luci-app-openclash'}
 entry({'admin','services','phone_panel','status'},call('status')).leaf=true
 entry({'admin','services','phone_panel','probe'},call('probe')).leaf=true
 entry({'admin','services','phone_panel','preview'},post('preview_device')).leaf=true
 entry({'admin','services','phone_panel','apply'},post('apply_device')).leaf=true
 entry({'admin','services','phone_panel','job'},call('job_status')).leaf=true
end
function status()
 local h=require('luci.http')
 h.header('Cache-Control','no-store')
 h.prepare_content('application/json')
 h.write(require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/panel-status.rb 2>/dev/null'))
end
function probe()
 local h=require('luci.http');local j=require('luci.jsonc');local n=require('nixio')
 local id=h.formvalue('id')
 if not id or not id:match('^%d+$') or tonumber(id)<1 or tonumber(id)>100 then h.status(400,'Bad Request');h.prepare_content('application/json');h.write('{"error":"invalid group"}');return end
 local function port(k,default) local v=tonumber(require('luci.model.uci').cursor():get('phone_panel','main',k)) or default;if v~=math.floor(v) or v+tonumber(id)<1024 or v+tonumber(id)>65535 then error('invalid port setting') end;return v end
 local db=port('dns_base',15300);local sb=port('socks_base',18000)
 local i=tonumber(id);local result={id=i,time=os.date('%Y-%m-%d %H:%M:%S'),dns_ok=false}
 local s=n.socket('inet','dgram')
 if s then
  s:setopt('socket','rcvtimeo',3);s:connect('127.0.0.1',db+i)
  local q=string.char(122,i,1,0,0,1,0,0,0,0,0,0,7)..'example'..string.char(3)..'com'..string.char(0,0,1,0,1)
  s:send(q);local r=s:recv(4096);s:close()
  if r and #r>=12 and r:byte(1)==122 and r:byte(2)==i then result.rcode=r:byte(4)%16;result.answers=r:byte(7)*256+r:byte(8);result.dns_ok=result.rcode==0 and result.answers>0 end
 end
 local ip=require('luci.sys').exec('/usr/bin/curl --noproxy "" --socks5-hostname 127.0.0.1:'..(sb+i)..' -fsS --connect-timeout 3 --max-time 7 https://api.ipify.org 2>/dev/null'):match('^%s*([%d%.]+)%s*$')
 result.exit_ip=ip;result.exit_ok=ip~=nil
 h.header('Cache-Control','no-store');h.prepare_content('application/json');h.write(j.stringify(result))
end

local function device_request(mode)
 local h=require('luci.http');local j=require('luci.jsonc');local d=require('luci.dispatcher')
 if not d.test_post_security() then return end
 local raw=h.formvalue('payload') or ''
 h.header('Cache-Control','no-store');h.prepare_content('application/json')
 if #raw>4096 then h.status(400,'Bad Request');h.write('{"error":"request too large"}');return end
 local p=j.parse(raw)
 if type(p)~='table' then h.status(400,'Bad Request');h.write('{"error":"请求格式无效"}');return end
 local rand=io.open('/dev/urandom','rb');local bytes=rand:read(16);rand:close()
 local path='/etc/phone-dns/panel-requests/'..bytes:gsub('.',function(c)return string.format('%02x',c:byte())end)..'.json'
 local fd=io.open(path,'w')
 if not fd then h.status(500,'Internal Server Error');h.write('{"error":"无法创建安全请求文件"}');return end
 require('nixio.fs').chmod(path,'600');fd:write(j.stringify(p));fd:close()
 local output=require('luci.sys').exec('/usr/bin/ruby /etc/phone-dns/device-manager.rb '..mode..' '..require('luci.util').shellquote(path)..' 2>/dev/null')
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
