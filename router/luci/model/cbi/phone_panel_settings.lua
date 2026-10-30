local m=Map('phone_panel','手机面板设置 / Phone panel settings',
 '保存不会立即修改网络。请在源码目录运行 sh scripts/maintenance.sh doctor，再在维护窗口运行 sh scripts/maintenance.sh initialize --apply。更改 fwmark 必须与 OpenClash 策略路由一致。')
local s=m:section(NamedSection,'main','main','网络与 DNS / Network and DNS')
s.addremove=false
local fields={
 {'lan_cidr','LAN 网段 / CIDR','cidr4'}, {'router_ip','路由器地址 / Router IPv4','ip4addr'},
 {'bridge','网桥 / Bridge','string'}, {'node_prefix','节点前缀 / Node prefix','string'},
 {'dns_base','DNS 基础端口 / DNS base','port'}, {'socks_base','SOCKS 基础端口 / SOCKS base','port'},
 {'internal_base','内部 DNS 基础端口 / Internal base','port'}, {'max_groups','分组上限 / Group limit','range(1,100)'},
 {'controller_port','内核 API 端口 / Controller port','port'},
 {'upstream_primary','主 DoH IPv4 / Primary','ip4addr'}, {'upstream_secondary','备 DoH IPv4 / Secondary','ip4addr'},
 {'tls_name','DoH TLS 主机名 / TLS name','hostname'}, {'fwmark','TPROXY 标记 / Mark','string'}}
for _,f in ipairs(fields) do local o=s:option(Value,f[1],f[2]);o.datatype=f[3];o.rmempty=false end
return m
