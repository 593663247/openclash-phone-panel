# Windows-friendly distribution

Build from a clean tracked checkout:

```sh
python3 scripts/build-package.py --version 2026.10.31-2 --output /tmp/phone-panel-release
python3 tests/test-package.py
```

The outer `*-Windows.zip` uses standard DEFLATE, ASCII file names, regular files only and no macOS resource forks. Windows Explorer can use **Extract All**. Chinese instructions use UTF-8 BOM and CRLF. The source is separately available as a nested standard ZIP. No Windows runtime or executable installer is required.

Upload the extracted `.ipk` directly to **System → Software → Upload Package** on an opkg-based OpenWrt/ImmortalWrt router. Do not rename it to ZIP or keep extracting it. It is not a Windows application. The IPK uses the nested gzip/USTAR format accepted by the tested OpenWrt opkg build (not an ar-only Debian container).

Requires existing OpenClash, LuCI, fw4 and Ruby >=3.1; dependencies are provided by router feeds, not bundled. Not for apk-based firmware or legacy fw3 systems. Installation integrates marked hooks but does not activate networking. Configure the new router's subnet, address and bridge, then use Maintenance to check and initialize. Old manual installations or ambiguous unmarked hooks are rejected. Removal is deliberately blocked until networking has been safely disabled/restored; see maintenance documentation.

Validation: ZIP extraction/CRC, SHA256, complete payload, maintainer-script shell syntax, and an isolated opkg installation using the current router's installed-dependency status. No actual Windows machine or second physical router was used; offline installation does not validate live initialization or hardware compatibility.

## 中文

下载 `*-Windows.zip`，在 Windows 右键选择“全部解压”；把其中 `.ipk` 上传到路由器软件包页面，不要继续解压或修改扩展名。压缩包同时提供中英文说明、源码 ZIP 和 SHA256 校验。

适用于 opkg + fw4 + LuCI、已安装 OpenClash 的系统；不支持 apk 包管理器或 fw3。安装后先配置新设备实际网段/网桥并检查钩子，再用网页初始化。不会自动接管网络；旧手动部署拒绝覆盖；卸载前必须按维护说明安全停用/恢复网络。
