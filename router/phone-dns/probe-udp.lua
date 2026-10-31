-- Test a DNS datagram through a loopback SOCKS5 listener, never direct fallback.
local n=require('nixio');local json=require('luci.jsonc');local port=tonumber(arg[1]);assert(port and port>=1024 and port<=65535 and port==math.floor(port))
local result={udp_tested=true,udp_ok=false};local tcp,udp
local function exact(s,count)local v='';while #v<count do local b=s:recv(count-#v);if not b or #b==0 then error('SOCKS reply timeout') end;v=v..b end;return v end
local ok,err=pcall(function()
 tcp=assert(n.socket('inet','stream'));tcp:setopt('socket','sndtimeo',3);tcp:setopt('socket','rcvtimeo',3)
 assert(tcp:connect('127.0.0.1',port),'local listener unavailable');tcp:send(string.char(5,1,0));assert(exact(tcp,2)==string.char(5,0),'SOCKS negotiation failed')
 tcp:send(string.char(5,3,0,1,0,0,0,0,0,0));local h=exact(tcp,4);assert(h:byte(1)==5 and h:byte(2)==0,'UDP ASSOCIATE rejected')
 local host
 if h:byte(4)==1 then local a=exact(tcp,4);host=table.concat({a:byte(1,4)},'.')
 elseif h:byte(4)==3 then host=exact(tcp,exact(tcp,1):byte(1))
 else error('unsupported relay address') end
 local p=exact(tcp,2);local relayport=p:byte(1)*256+p:byte(2);if host=='0.0.0.0' then host='127.0.0.1' end
 assert(host=='127.0.0.1','non-loopback relay rejected')
 udp=assert(n.socket('inet','dgram'));udp:setopt('socket','rcvtimeo',3);assert(udp:connect(host,relayport))
 local id=os.time()%65536;local a,b=math.floor(id/256),id%256
 local query=string.char(a,b,1,0,0,1,0,0,0,0,0,0,7)..'example'..string.char(3)..'com'..string.char(0,0,1,0,1)
 udp:send(string.char(0,0,0,1,8,8,8,8,0,53)..query)
 local response=assert(udp:recv(4096),'UDP relay timeout');assert(#response>=22 and response:byte(3)==0,'invalid UDP response')
 local at=response:byte(4);local offset=at==1 and 11 or at==4 and 23 or at==3 and 8+response:byte(5) or 0
 assert(offset>0,'unknown UDP response');local r=response:sub(offset)
 assert(#r>=12 and r:byte(1)==a and r:byte(2)==b and r:byte(3)>=128 and r:byte(4)%16==0 and r:byte(7)*256+r:byte(8)>0,'no matching DNS answer')
 result.udp_ok=true;result.note='通过绑定节点收到 UDP DNS 回包；不代表所有 UDP 应用可用'
end)
if udp then udp:close() end;if tcp then tcp:close() end
if not ok then result.note=tostring(err):gsub('^.-:%d+: ','') end
io.write(json.stringify(result))
