#!/usr/bin/env python3
"""Build a deterministic opkg IPK and a Windows Explorer-compatible ZIP."""
import argparse, hashlib, io, os, pathlib, subprocess, tarfile, zipfile, json
ROOT=pathlib.Path(__file__).resolve().parents[1]
def archive(files,sort=True):
 out=io.BytesIO()
 import gzip
 with gzip.GzipFile(fileobj=out,mode='wb',mtime=0,filename='') as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as tar:
   dirs=set()
   for name in files:
    parent=pathlib.PurePosixPath(name).parent
    while str(parent)!='.': dirs.add(str(parent));parent=parent.parent
   for name in sorted(dirs):
    info=tarfile.TarInfo('./'+name);info.type=tarfile.DIRTYPE;info.mode=0o755;info.uid=info.gid=0;info.mtime=0;tar.addfile(info)
   for name,(data,mode) in (sorted(files.items()) if sort else files.items()):
    info=tarfile.TarInfo('./'+name);info.size=len(data);info.mode=mode;info.uid=info.gid=0;info.mtime=0;tar.addfile(info,io.BytesIO(data))
 return out.getvalue()
def build(version,output):
 output.mkdir(parents=True,exist_ok=True)
 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 tracked=subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
 sources={}
 for name in tracked:
  if not name or not (name.startswith(('router/','scripts/','docs/','tests/')) or name in ['README.md','README.en.md','CHANGELOG.md','LICENSE','SECURITY.md','package.json','package-lock.json','VERSION']):continue
  p=ROOT/name
  if p.is_symlink() or not p.is_file():raise ValueError('Invalid source: '+name)
  sources[name]=(p.read_bytes(),0o644)
 payload={'usr/share/phone-panel/'+name:entry for name,entry in sources.items()}
 for p in sorted((ROOT/'router/phone-dns').glob('*')):
  if p.suffix in ['.rb','.lua']:payload['etc/phone-dns/'+p.name]=(p.read_bytes(),0o600)
 pairs={
 'router/phone-dns/status.rb':('etc/phone-dns/panel-status.rb',0o600),
 'router/phone-dns/phone-dns.init':('etc/init.d/phone-dns',0o755),
 'router/phone-dns/phone-panel-monitor.init':('etc/init.d/phone-panel-monitor',0o755),
 'router/config/phone_panel':('etc/config/phone_panel',0o600),
 'router/luci/controller/phone_panel.lua':('usr/lib/lua/luci/controller/phone_panel.lua',0o644),
 'router/luci/view/phone_panel.htm':('usr/lib/lua/luci/view/phone_panel.htm',0o644),
 'router/luci/model/cbi/phone_panel_settings.lua':('usr/lib/lua/luci/model/cbi/phone_panel_settings.lua',0o644),
 'router/openclash/phone-routing.sh':('etc/openclash/custom/phone-routing.sh',0o700),
 'router/nftables/90-phone-fixed-egress.nft':('etc/nftables.d/90-phone-fixed-egress.nft',0o600)}
 for source,(dest,mode) in pairs.items():payload[dest]=((ROOT/source).read_bytes(),mode)
 for name in ['mapping.yaml','devices.yaml','listeners.yaml','managed-nodes.yaml']:payload['etc/phone-dns/'+name]=(b'--- []\n',0o600)
 payload['etc/phone-dns/config.json']=(b'{}\n',0o600)
 payload['usr/share/phone-panel/deployed-commit']=(commit.encode()+b'\n',0o644)
 # Empty private working directories must exist before LuCI can accept requests.
 for name in ['jobs/.keep','panel-requests/.keep']:payload['etc/phone-dns/'+name]=(b'',0o600)
 control=f'''Package: luci-app-phone-panel
Version: {version}
Architecture: all
Maintainer: 593663247
Section: luci
Priority: optional
Depends: ruby, ruby-yaml, ruby-digest, lua, luci-compat, curl, sing-box, firewall4
Description: Experimental OpenClash device egress, DNS and SOCKS5 node management
Installed-Size: {sum(len(v[0]) for v in payload.values())//1024+1}
'''
 pre='''#!/bin/sh
set -eu
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
[ -x /etc/openclash/clash ] && [ -d /etc/openclash/custom ] || { echo 'Install OpenClash first'; exit 1; }
if [ -d /etc/phone-dns ] && ! opkg status luci-app-phone-panel 2>/dev/null | grep -q '^Status:.*installed'; then
 echo 'Existing manual installation detected; refusing overwrite. Back up and migrate first.'; exit 1
fi
ruby -ryaml -rdigest -e 'abort "Ruby >= 3.1 required" if (RUBY_VERSION.split(".").first(2).map(&:to_i) <=> [3,1]) < 0'
'''
 post='''#!/bin/sh
set -eu
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
chmod 700 /etc/phone-dns /etc/phone-dns/jobs /etc/phone-dns/panel-requests
chmod 600 /etc/phone-dns/*.yaml /etc/phone-dns/config.json
ruby /usr/share/phone-panel/scripts/hooks.rb install || { echo 'Hook integration failed; original hooks retained. Resolve before initialization.'; exit 1; }
rm -f /tmp/luci-indexcache
echo 'Installed without network activation. Open Services > Phone panel > Settings; confirm subnet/bridge, check hooks, then preview and initialize from Maintenance. OpenClash custom hooks must be enabled.'
'''
 prerm='''#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
if [ "${1:-}" = remove ]; then
 echo 'Removal blocked to protect networking. Back up, remove managed hooks, restore firewall/DHCP and use the documented disable/recovery procedure before manual cleanup.'
 exit 1
fi
exit 0
'''
 conffiles='\n'.join('/'+p for p in ['etc/config/phone_panel','etc/phone-dns/mapping.yaml','etc/phone-dns/managed-nodes.yaml','etc/phone-dns/devices.yaml','etc/phone-dns/listeners.yaml','etc/phone-dns/config.json','etc/nftables.d/90-phone-fixed-egress.nft'])+'\n'
 controls={name:(data.encode(),0o755 if name in ['preinst','postinst','prerm'] else 0o644) for name,data in {'control':control,'preinst':pre,'postinst':post,'prerm':prerm,'conffiles':conffiles}.items()}
 ipkname=f'luci-app-phone-panel_{version}_all.ipk'
 ipk=archive({'debian-binary':(b'2.0\n',0o644),'control.tar.gz':(archive(controls),0o644),'data.tar.gz':(archive(payload),0o644)},sort=False)
 (output/ipkname).write_bytes(ipk)
 zh=f'''手机出口与 DNS 面板 {version}

Windows：右键 ZIP → 全部解压。把里面的 {ipkname} 上传到路由器：系统 → 软件包 → 上传软件包。
不要继续解压或改名 .ipk；它不是 Windows 程序，不能双击安装。

适用：使用 opkg、fw4 与 LuCI 的 OpenWrt / ImmortalWrt，已有 OpenClash，Ruby >= 3.1。
不适用：apk 软件包管理器系统、fw3/iptables 旧版系统。依赖由路由器软件源提供，ZIP 不含依赖二进制。
安装后不会自动接管网络。先在“服务 → 手机出口与 DNS → 设置”确认网段、路由器 IP、网桥，再在“管理维护”检查并预览初始化，确认后应用。
安装会尝试以标记块接入 OpenClash 钩子，但仍需确认 OpenClash 已启用对应自定义脚本。旧手动部署/未标记钩子将拒绝覆盖，避免破坏已有配置。

新增 SOCKS5 落地节点位于“管理维护”。填写服务商提供的真实服务器、端口、账号密码和前置代理；预览后确认。随后在设备绑定中选择节点。
只检查语法不代表真实出口/UDP可用；真实新节点仍需绑定后检测。

卸载保护：普通移除会被阻止，避免突然失去防直连保护；请先按源码 docs/MAINTENANCE.md 的停用/恢复流程处理。
本安装包通过结构、校验和、脚本语法及自动化回归验证，尚未完成路由器实机安装验收。

GitHub: https://github.com/593663247/openclash-phone-panel
Source commit: {commit}
'''
 en=f'''Phone egress and DNS panel {version}

Windows: Right-click this ZIP > Extract All. Upload {ipkname} through the router's System > Software > Upload Package.
Do not rename or extract the IPK. It is a router package, not a Windows application.

Requires opkg, fw4, LuCI, OpenClash and Ruby >= 3.1. Not for apk-based or legacy fw3 systems. Dependencies come from router feeds and are NOT bundled.
Installation does not activate routing. Configure subnet, router IP and bridge under Settings, then check/preview initialization under Maintenance before confirming.
Marked OpenClash hooks are integrated automatically; enable the corresponding custom hooks in OpenClash. Existing manual deployments or ambiguous legacy hooks are rejected.
SOCKS5 node creation is under Maintenance. Real provider connectivity and UDP require validation after binding.
Normal removal is blocked for safety: follow docs/MAINTENANCE.md to disable/recover first.
Package structure, checksums, script syntax and automated regressions are verified; physical router installation remains unverified.

Source: https://github.com/593663247/openclash-phone-panel
Commit: {commit}
'''
 sourcezip=io.BytesIO()
 with zipfile.ZipFile(sourcezip,'w',zipfile.ZIP_DEFLATED) as z:
  for name,(data,_) in sorted(sources.items()):
   info=zipfile.ZipInfo('source/'+name,(2026,10,31,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,data)
 (output/'phone-panel-source.zip').write_bytes(sourcezip.getvalue())
 entries={ipkname:ipk,'README_ZH_CN.txt':b'\xef\xbb\xbf'+zh.replace('\n','\r\n').encode(),'README_EN.txt':en.replace('\n','\r\n').encode(),'phone-panel-source.zip':sourcezip.getvalue()}
 checksum=''.join(hashlib.sha256(v).hexdigest()+'  '+k+'\r\n' for k,v in entries.items())
 entries['SHA256SUMS.txt']=checksum.encode()
 (output/'SHA256SUMS.txt').write_bytes(checksum.encode())
 zipname=f'phone-panel-{version}-Windows.zip'
 with zipfile.ZipFile(output/zipname,'w',zipfile.ZIP_DEFLATED,allowZip64=False) as z:
  for name,data in entries.items():
   info=zipfile.ZipInfo(name,(2026,10,31,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,data)
 print(json.dumps({'ipk':str(output/ipkname),'windows_zip':str(output/zipname),'sha256':hashlib.sha256((output/zipname).read_bytes()).hexdigest(),'source_commit':commit},ensure_ascii=False))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--version',default=(ROOT/'VERSION').read_text().strip()+'-1');p.add_argument('--output',required=True);a=p.parse_args()
 import re
 if not re.fullmatch(r'[0-9][0-9A-Za-z.+~-]*',a.version):p.error('Invalid package version')
 build(a.version,pathlib.Path(a.output).resolve())
