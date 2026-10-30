# 配置与维护 / Configuration and maintenance (development)

本次开发新增 `/etc/config/phone_panel`，LuCI 面板设置入口支持 LAN CIDR（/8 到 /30）、路由器地址、网桥、节点前缀、端口范围、DoH 上游、TLS 主机名与防火墙标记。保存仅保存参数，不立即改动网络。fwmark 必须与现有 OpenClash 策略路由匹配。

New UCI settings cover LAN CIDR, router IPv4, bridge, node prefix, port ranges, DoH servers/TLS name and firewall mark. Saving settings does not apply networking. The mark must match OpenClash policy routing.

维护脚本 / Maintenance commands (run from reviewed source on router):

```sh
sh scripts/maintenance.sh doctor
sh scripts/maintenance.sh backup
sh scripts/maintenance.sh upgrade
# Review settings/hooks first; interrupts networking:
sh scripts/maintenance.sh initialize --apply
# Stops services, restores files, requires manual runtime validation:
sh scripts/maintenance.sh restore /root/phone-panel-maintenance/SNAPSHOT --apply
# Conservative uninstall: disables service but retains files/guards:
sh scripts/maintenance.sh uninstall --disable
```

依赖检查仅报告缺失项，不自动安装软件。升级保留配置，恢复前再次备份；恢复不保证跨版本或运行态事务回滚。卸载采用保留数据和保护规则的停用方式，完整清理由管理员按 INSTALL.md 完成。

Dependency checks report missing tools without installing packages. Upgrade preserves configuration. Restore snapshots files again before restoring; runtime rollback is not transactional. Uninstall conservatively disables the service and retains data/guards; follow INSTALL.md for manual removal.

**状态：开发版。仅完成语法和纯逻辑测试，维护流程尚未在隔离路由器端完整验证。不要直接替换生产安装；旧安装说明中的固定网段描述尚待统一更新。**

**Development status:** syntax and pure planning tests only; maintenance flows still need isolated router integration tests. Do not deploy directly to production. Legacy fixed-subnet installation documentation still needs reconciliation.

## 可选依赖安装 / Optional dependency installation

```sh
sh scripts/install-deps.sh --check
sh scripts/install.sh --install-deps
sh scripts/maintenance.sh doctor
```

只使用已配置的 opkg 软件源，安装缺失命令或 Ruby YAML 模块对应软件包；不更新已存在依赖、不执行系统升级、不修改软件源、不关闭签名检查。安装前要求 overlay 至少32MiB空闲，但这不保证所有软件包都能装下。下载/安装失败立即停止，已成功安装的软件包不会自动卸载。OpenClash/Mihomo和LuCI本身仍由用户准备；系统使用apk时明确停止，不猜测包名。

Only configured opkg feeds are used. Missing commands/Ruby YAML modules are mapped to packages. No full upgrade, feed changes, signature bypass or third-party installer is performed. A 32MiB overlay-space floor is checked but is not a guarantee of sufficient capacity. Failures stop immediately; already installed packages are retained. OpenClash/Mihomo and LuCI remain manual prerequisites. APK-based systems are rejected explicitly. Package availability and supported versions must still pass doctor; installing sing-box does not guarantee the required version.

此安装入口需要管理员主动执行，不会在打开面板时自动下载。尚未在真实路由器执行下载/安装测试。
This is an explicit administrator command, not an automatic dashboard side effect. Real-router download/install integration is not yet tested.
