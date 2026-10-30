local n=require('nixio')
local j=require('luci.jsonc')
local dp,sp=tonumber(arg[1]),tonumber(arg[2])
assert(dp and sp and dp==math.floor(dp) and sp==math.floor(sp) and dp>=1024 and dp<=65535 and sp>=1024 and sp<=65535)
local result={dns_ok=false,socks_tcp_ok=false}
local tcp=n.socket('inet','stream')
if tcp then
 tcp:setopt('socket','sndtimeo',1)
 result.socks_tcp_ok=tcp:connect('127.0.0.1',sp) and true or false
 tcp:close()
end
local s=n.socket('inet','dgram')
if s then
 s:setopt('socket','rcvtimeo',3)
 s:connect('127.0.0.1',dp)
 local id=os.time()%65536
 local a,b=math.floor(id/256),id%256
 local query=string.char(a,b,1,0,0,1,0,0,0,0,0,0,7)..'example'..string.char(3)..'com'..string.char(0,0,1,0,1)
 s:send(query)
 local r=s:recv(4096)
 s:close()
 if r and #r>=12 and r:byte(1)==a and r:byte(2)==b and r:byte(3)>=128 then
  result.rcode=r:byte(4)%16
  result.answers=r:byte(7)*256+r:byte(8)
  result.dns_ok=result.rcode==0 and result.answers>0
 end
end
io.write(j.stringify(result))
