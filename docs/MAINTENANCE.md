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

**状态：开发版。仅完成语法和纯逻辑测试，维护流程尚未在隔离路由器端完整验证。不要直接替换生产安装；更宽网段与其他拓扑仍需隔离路由器验证。**

**Development status:** syntax and pure planning tests only; maintenance flows still need isolated router integration tests. Do not deploy directly to production. Wider subnets and alternate topologies still require isolated router validation.

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

## 本轮修复 / Reliability updates

备份新增活动源 YAML、覆写/防火墙钩子和路由脚本。恢复前快照在独立子进程中创建，避免覆盖用户选择的恢复目标；恢复目录须为维护目录下的单个真实子目录。升级同步 init 和路由脚本，并保留 UCI 设置与用户钩子。initialize 在重启 OpenClash 前重新加载防火墙。

Backups now include source YAML, custom hooks and routing integration. A pre-restore backup cannot replace the selected snapshot variable. Restore resolves and checks its directory boundary. Upgrade refreshes init/routing code while retaining UCI settings and custom hooks. Initialization reloads the firewall before starting OpenClash.

`doctor` 验证依赖和设置，不代表已验证端口占用、TPROXY 策略路由、钩子执行或真实网络连通性。恢复仍为文件合并，不自动移除新增文件或恢复服务启用状态。

Doctor checks dependencies and settings, not occupied ports, policy routing, hook execution or connectivity. Restore remains a file merge; it does not delete newly created files or restore service enablement state.

管理页依赖 `/usr/share/phone-panel` 中的维护运行时；安装和升级会暂存 router/scripts 源码，备份也包含该目录。已有安装更新程序文件即可使用本轮界面修复；只有设置或生成网络配置需要改变时才执行 initialize。

Dashboard jobs use the maintenance runtime under `/usr/share/phone-panel`. Installation and upgrade stage router/scripts sources, and snapshots include that runtime. Updating code alone does not require network initialization when settings and generated networking remain unchanged.

## 监测与程序版本恢复

参见 [FEATURES.zh-CN.md](FEATURES.zh-CN.md)。升级会更新并重启独立监测服务，监测只新增自己的计数表，不更改业务规则；原 OpenClash/DNS 服务继续运行。网页程序恢复保留现有设备配置，完整文件合并恢复仍是维护命令的单独操作。
