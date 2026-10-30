# 安装 / Installation

## 中文

### 1. 适配与备份（必读）

此版本是参考源码，不是 `.ipk`。需要 root SSH、路由器本地/有线恢复通道，以及自行安装并可运行的 OpenClash/Mihomo、sing-box 1.12.x、Ruby 3.1+ 和 YAML/Psych、LuCI Lua/nixio、dnsmasq、curl、fw4/nftables。

默认假定 LAN=`192.168.1.1/24`、网桥=`br-lan`，业务代理为真实存在且支持 TCP/UDP 的 SOCKS5。安装后可在 LuCI 设置或 `/etc/config/phone_panel` 配置单个 LAN 的 CIDR、路由器地址、网桥、端口、节点前缀与 DoH。其他拓扑必须先审查所有脚本：

```sh
grep -R -n '192\.168\.1\|br-lan\|0x162\|9090' router
```

设置保存仅更新参数；须先运行 `sh scripts/maintenance.sh doctor` 校验，审查钩子后在维护窗口执行 `sh scripts/maintenance.sh initialize --apply` 才重新生成并应用网络配置。参考路由依赖 OpenClash 的 `openclash`、`openclash_mangle`、`localnetwork` 以及 `0x162` 策略路由，须先核对本机。不提供自动兼容探测。

先通过 LuCI 导出系统备份，另行保存活动 OpenClash 源配置、自定义脚本、`/etc/config/dhcp`、`/etc/nftables.d/`。这些都是私密数据，不要放进仓库。

### 2. 获取并检查

在电脑下载本仓库，审查并适配后将源码目录传至路由器。进入该目录执行：

```sh
sh scripts/install.sh --check
```

默认检查不会安装依赖；如需显式安装缺失依赖，使用 `sh scripts/install.sh --install-deps`，仅使用已配置的 opkg 软件源。用 `netstat -ln` 确认以下端口未被其他应用占用（也要检查每组内部 DoH 入口）：

| 用途 | 第 g 组端口（1≤g≤100） |
|---|---|
| LAN DNS 缓存 | 15300+g，TCP/UDP |
| 固定节点 SOCKS | 18000+g，仅 127.0.0.1 |
| sing-box DNS 入口 | 15400+10g+1 / +2，仅 127.0.0.1 |

源配置必须已有至少一个符合条件的 `手机-` 代理和顶部 `/32` 来源规则，且相应设备有唯一静态租约。建议先只纳管一台测试手机。

### 3. 暂存文件

```sh
sh scripts/install.sh --install
```

它只写入项目专用路径，拒绝覆盖已有安装，不改现有钩子、不重启网络。中途失败请人工检查已暂存文件。暂存完成后不要立刻启动 `phone-dns`：初始配置是占位文件。

生成实际配置并校验：

```sh
CFG=$(uci -q get openclash.config.config_path)
ruby /etc/phone-dns/align-dns.rb "$CFG"
cat /etc/phone-dns/import-status.yaml
fw4 check
sing-box check -c /etc/phone-dns/config.json
```

检查 `mapping.yaml` 至少包含一个已识别设备，且节点、MAC、IP 匹配。如果没有有效设备，先修复租约/规则，不继续激活。检查安装后的脚本依赖和 LuCI ACL 与本机兼容。

### 4. 手动接入 OpenClash（不要覆盖原钩子）

在 `/etc/openclash/custom/openclash_custom_overwrite.sh` 的最终 `exit 0` **之前**合并：

```sh
ruby /etc/phone-dns/align-dns.rb "$1" || exit 1
ruby /etc/phone-dns/add-listeners.rb "$1" || exit 1
```

在 `/etc/openclash/custom/openclash_custom_firewall_rules.sh` 的最终 `exit 0` **之前**合并：

```sh
/etc/openclash/custom/phone-routing.sh || logger -t phone-panel 'Routing integration failed'
CFG=$(uci -q get openclash.config.config_path)
ruby /etc/phone-dns/align-dns.rb "/etc/openclash/${CFG##*/}" live || logger -t phone-panel 'Alignment failed'
```

在 OpenClash 中启用对应自定义覆写/防火墙钩子。两个钩子必须都正常执行；只改源码不意味着已经启用。

### 5. 激活和验证（会短暂断网）

维护窗口内、保留本地管理连接：

```sh
/etc/init.d/openclash stop
/etc/init.d/firewall reload
/etc/init.d/phone-dns enable
/etc/init.d/openclash start
```

若插件使用快速启动缓存，确认按本机版本的方法强制完整生成配置；否则新监听/嗅探设置可能没有进入运行配置。不要依赖修改未知内部缓存路径。

打开 `/cgi-bin/luci/admin/services/phone_panel`，检查待处理项、各组绑定及监听，再逐组检测 DNS/出口。检查：

```sh
nft list set inet fw4 codex_phone4
nft list set inet fw4 codex_phone_mac
nft list chain inet fw4 codex_phone_dns
nft list chain inet fw4 codex_phone_guard
logread | grep phone-panel
```

手机重新连接 Wi-Fi，并实际测试 TCP、UDP、DNS 和 IPv6 行为。上游支持 UDP 还需要 SOCKS5 UDP ASSOCIATE、链式拨号和防火墙均可用；面板不验证全部链路。

### 恢复 / 卸载

安装脚本不接管已有文件，因此不要用递归删除 `/etc/openclash` 等方式卸载。先备份当前故障状态并保留本地连接；停止 OpenClash 与 `phone-dns`，撤销本项目添加的两处钩子，恢复原 DHCP、源配置及 nftables 备份，重载防火墙并重新启动原 OpenClash。核对旧网络正常后，才移除项目专属文件并禁用其 init 服务。卸载会解除本项目的 fail-closed 保护，应由你明确选择何时恢复普通转发。

任务恢复记录位于 `/root/phone-panel-changes/<job>/`，`manifest.yaml` 与 `file-N` 按顺序对应；不存在的原文件没有备份实体。不要盲目执行自动恢复命令。对齐器失败主要恢复文件快照，已加载的 nft/service 状态仍需人工核对。**不要将恢复目录或配置上传到 Issue。**

## English

### Prerequisites and scope

This is reference source, not an `.ipk`. Require root SSH, wired/local recovery access, working OpenClash/Mihomo, sing-box 1.12.x, Ruby 3.1+ with YAML/Psych, LuCI Lua/nixio, dnsmasq, curl and fw4/nftables. Defaults are `192.168.1.1/24` and `br-lan`.

Configure one IPv4 LAN, bridge, proxy prefix, port ranges, DoH and mark in `/etc/config/phone_panel` or LuCI settings. Saving does not apply networking. Run `sh scripts/maintenance.sh doctor` before `initialize --apply` in a maintenance window. Review routing compatibility before adapting. Routing integration assumes the existing `openclash`, `openclash_mangle`, `localnetwork` objects and working policy routing. No universal topology detection is implemented. Back up the system, active source YAML, DHCP, custom hooks and nftables privately. Keep local recovery access throughout deployment.

### Staging and activation

1. Download/review the repository, adapt the source if necessary, transfer it to the router.
2. Run `sh scripts/install.sh --check`. Missing dependencies are not automatically installed.
3. Check port availability: group g uses DNS `15300+g`, SOCKS `18000+g`, internal DNS `15400+10g+1` and `+2`, with g=1..100.
4. Configure at least one real `手机-` proxy, a top-level `/32` source rule and a unique static DHCP lease. Start with one test phone.
5. Run `sh scripts/install.sh --install`. It stages dedicated files only, refuses existing installations, and does not restart networking. Do not start the placeholder DNS configuration.
6. Run the generation/check commands shown in section 3. Verify `mapping.yaml` contains at least one correctly matched device; resolve pending imports before activation.
7. Merge, rather than replace, the two hook snippets in section 4 before each existing `exit 0`. Enable those custom hooks in OpenClash. Both hooks are required.
8. In a maintenance window, execute the activation commands in section 5. This interrupts OpenClash traffic. Force complete config generation using the mechanism appropriate to your plugin version if quick-start caching is active.
9. Open the LuCI panel, inspect pending items/listeners/bindings, run DNS/egress checks, reconnect the phone and test actual TCP/UDP/DNS/IPv6 behavior. A successful status check is not proof of UDP delivery or absence of leaks.

### Recovery and upgrades

The staging installer refuses existing installations. Use `sh scripts/maintenance.sh upgrade` to snapshot and stage code while preserving settings; review hooks and run doctor before explicit activation. See MAINTENANCE.md. There is no universal runtime migration or complete uninstaller. Restore original DHCP, source configuration, nftables files and remove only the hook additions belonging to this project. Stop affected services first, reload the firewall, restart the original OpenClash setup, and verify recovery before removing dedicated project files. Disabling/removing the project can remove fail-closed protection.

Job snapshots under `/root/phone-panel-changes/<job>/` use `manifest.yaml` and ordered `file-N` files. File rollback is not a guarantee of runtime rollback or crash safety. Inspect running services/nftables manually after a failure. Never publish snapshots or unsanitized configuration.

## 维护版本更新 / Maintenance updates

见 [MAINTENANCE.md](MAINTENANCE.md) 与 [CHANGELOG.md](../CHANGELOG.md)。备份包含活动 OpenClash 源配置、两处自定义钩子和路由集成脚本。恢复前会再做快照；恢复的是所选快照文件，不会自动启动服务，也不删除快照中不存在的额外文件。恢复后必须人工核对生成文件与运行态。

Backups include the active source YAML, both custom hooks and routing script. Restore makes another snapshot first, restores the selected snapshot, and leaves services stopped. It merges saved files and does not remove extra files absent from the snapshot; inspect generated files and runtime state manually.

## 新版监测服务与版本标记

代码暂存后，完成本说明的网络激活流程，再启用独立监测服务：

```sh
/etc/init.d/phone-panel-monitor enable
/etc/init.d/phone-panel-monitor start
```

`maintenance.sh initialize --apply` 会一并启动监测。通过版本管理或 `releases.rb install-local SOURCE FULL_SHA` 安装时自动写入部署提交并启动监测；仅手动复制源码无法推断其精确版本，版本页会拒绝未知来源的自动升级，需先核对实际来源的完整 Git 提交。

After staging and networking activation, enable/start the separate monitor service as above. Managed installation writes the exact source commit. A manually copied source tree without a verified commit marker cannot use automatic upgrades; identify its actual full Git SHA first.
