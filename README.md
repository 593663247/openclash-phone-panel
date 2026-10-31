> Release: **v1.0.0** · opkg: **1.0.0-1** · [Changelog](CHANGELOG.md) · [Downloads](https://github.com/593663247/openclash-phone-panel/releases/tag/v1.0.0)

# OpenClash Phone Panel

[English](README.en.md) · [安装 / Installation](docs/INSTALL.md) · [中文使用手册](docs/USER_GUIDE.zh-CN.md) · [English User Guide](docs/USER_GUIDE.en.md)

为 ImmortalWrt / OpenWrt LuCI 提供手机设备固定出口、分组加密 DNS 与配置同步面板。

> **实验性参考实现，不是官方 OpenClash 插件，也不是通用一键安装包。**
> 代码由特定 fw4 + REDIRECT/TPROXY 环境整理而来。发布版本已移除部署实例数据，默认示例改为 `192.168.1.0/24`、网桥 `br-lan`。其他单 LAN 网段可通过 UCI 设置配置；更换网络拓扑仍需适配。安装辅助脚本仅暂存文件，不接管网络。

## 功能

新增设备在线依据、出口 IP 变化提醒、搜索/地区/异常筛选、健康历史、独立 IPv4 流量统计、DHCP 批量添加、逐层诊断和 CI 门控的版本升级/程序恢复。见 [完整功能说明](docs/FEATURES.zh-CN.md)。

- 在已有 LuCI 登录保护内显示设备、节点、DNS 监听与连接计数；每 15 秒刷新状态。
- 从活动 OpenClash 源配置读取 `手机-` 开头的代理节点。
- 识别规则顶部的 `SRC-IP-CIDR,<IPv4>/32,<手机节点>`，匹配唯一静态/当前 DHCP 租约并自动导入。
- 缺失 MAC、冲突、重复规则等列为待处理；不猜测 MAC，不静默覆盖设备。
- 按业务流量节点重新分组 DNS；每个节点独立 dnsmasq 缓存，通过固定 SOCKS 入口访问 Google DoH。
- 手动添加设备：名称 / MAC / IP / 节点 → 预览 → 确认应用；生成任务与恢复记录。
- 为 `手机-` SOCKS5 业务节点自动开启 `udp: true`；DNS 专用本地 SOCKS 入口保持 TCP-only。
- IP/MAC 防直连集合、53 端口 DNS 接管、嗅探来源排除及可选参考路由脚本。

管理维护页保留线上已有的初始化预览、白名单维护任务和设备编辑功能；维护任务记录留在路由器本地。

## 快速了解

```yaml
# 示例片段，不是完整配置；节点由用户自行提供，仓库不包含代理凭据。
rules:
  - SRC-IP-CIDR,192.168.1.101/32,手机-01-示例
  # 将此类规则放在域名规则、规则集及 MATCH 之前。
```

在 DHCP 中为示例设备配置唯一静态租约，按[安装说明](docs/INSTALL.md)接入覆写和防火墙钩子，应用 OpenClash 后到：

```text
LuCI → 服务 → 手机出口与 DNS
/cgi-bin/luci/admin/services/phone_panel
```

**未应用配置时，不会自动改网络；15 秒刷新仅是读状态。**

## 支持边界

- 曾验证的部署基线：ImmortalWrt 24.10.2、LuCI Lua 兼容层、fw4/nftables、Mihomo、sing-box 1.12.8。
- Ruby 3.1+（需 YAML/Psych）、Lua/nixio、curl、dnsmasq、nft/fw4；代码假定命令在默认路径。
- 单个可配置 IPv4 LAN（CIDR 参数允许 /8～/30，默认 /24），最多 100 个节点分组；默认节点前缀为 `手机-`，可在设置中修改。更宽网段尚需路由器实测。
- 自动导入仅识别独立代理项，不支持代理组目标、IPv6 来源规则、跨网段或任意 CIDR。
- 管理维护页提供设备改名、改绑和显式删除；删除保留 DHCP 租约并解除该设备面板保护。删除/重命名仍被使用的节点前必须迁移设备。
- 不保证 TUN、iptables、旁路由、多 VLAN、其他防火墙标记或任意版本兼容。
- 开启 UDP 不证明上游 UDP 可用；已有连接/监听状态也不是泄漏审计。
- 客户端私人 DNS、内置 DoH 不受 53 端口接管；默认 fail-closed MAC 规则可能阻断手机外部 IPv6。
- 恢复机制以文件快照为主，不保证跨进程崩溃、并发修改或运行态完整回滚；详见使用手册。

## 项目结构

| 路径 | 内容 |
|---|---|
| `router/luci/` | LuCI 控制器及模板 |
| `router/phone-dns/` | 导入、对齐、DNS 生成、任务管理、状态与 procd 服务 |
| `router/nftables/` | 不包含真实设备的 fw4 模板 |
| `router/openclash/` | 参考 REDIRECT/TPROXY 接入脚本 |
| `scripts/` | 依赖检查、文件暂存与发布隐私检查 |
| `tests/` | 无网络、无路由器写入的规划测试 |
| `docs/` | 中英文安装和使用文档 |

## 本地验证

```sh
ruby tests/test-auto-import.rb
ruby tests/test-settings.rb
ruby tests/test-device-plan.rb
ruby tests/test-device-edit.rb
python3 tests/test-maintenance.py
npm ci --ignore-scripts
npm test
python3 scripts/privacy_check.py
find router tests -name '*.rb' -exec ruby -c {} \;
sh -n scripts/install.sh
```

CI 检查语法、规划逻辑、界面异步状态、隔离文件备份恢复及发布文件，不代表路由器端集成测试。不要在生产路由器盲目运行安装脚本。

## 隐私与许可

仓库不包含实际节点配置、密码、密钥、租约、运行日志、截图或备份；示例地址/MAC 为合成数据。不要在 Issue 中附带未经脱敏的 YAML、Cookie 或日志。见 [SECURITY.md](SECURITY.md)。

MIT License。无 OpenClash / ImmortalWrt 官方背书。

### 新增：落地节点网页录入

管理维护页支持新增 SOCKS5 节点：账号密码、UDP、具体前置节点、脱敏预览、确认加载与失败恢复。设备绑定节点下拉框同步更新。参见 [节点管理说明](docs/NODE_MANAGEMENT.md)。同时修复 IP 修改、DHCP 名称同步、改绑节点选择及 interval 集合合并。

### 统一任务、设备选择与节点生命周期

新增后台任务阶段和中断识别、统一应用/回滚验收、设备下拉选择与三类 IP 状态、节点编辑/引用检查/删除、私密独立节点库及 UDP 回包实测。见 [运维与验证边界](docs/OPERATIONS.md)。真实设备删除、故意断电恢复和跨订阅迁移仍未完成生产验收。
