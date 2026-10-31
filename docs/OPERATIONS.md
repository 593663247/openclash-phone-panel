# Three workflow improvements / 三项流程优化

## 1. Background tasks and shared apply/recovery

Device add/batch, rename/rebind/IP changes, node CRUD, node tests and initialization are submitted as persistent background operations. The unified task view also includes existing maintenance and legacy device jobs. Refreshing a page does not resubmit work. Running/queued operations with a different boot ID or a dead worker are marked interrupted; **no automatic replay** occurs.

Configuration mutations use a common lock and apply engine: check unsaved UCI changes and revision, create a private snapshot, atomically update configuration, generate DNS/firewall, validate core/configuration, invalidate OpenClash quick-start cache, reload, then check runtime node definitions, source bindings, DNS/SOCKS listeners, sniff exclusions and firewall protection. File recovery and runtime recovery are reported separately. This is structural runtime verification, not proof that every phone application works.

Backups reside in `/root/phone-panel-transactions/`. The task page offers confirmed restoration for compatible snapshots. Restoration creates another snapshot first and rejects paths outside the configured source and managed configuration files. Switching to a different active YAML may make an older snapshot incompatible; select the matching configuration before recovery. Snapshots contain credentials and must remain private. Uninstall, arbitrary backup upload, destructive power-loss tests and full hardware compatibility are outside this feature.

## 2. Device selection and three IP meanings

Devices & Nodes → Managed devices → Edit device: select a row by name, fixed IPv4 and MAC. The form fills the old IP, name and node. It separately displays **configured fixed IP**, **current DHCP lease matched by MAC**, and **last measured public egress IP**. A different lease is shown as waiting for Wi-Fi reconnection. A detected public IP is historical measurement, not a permanent guarantee.

## 3. Node management, diagnostics and independent storage

The landing-node list under Devices & Nodes supports SOCKS5 create/update/delete through row actions and modal editors. Editing retains old credentials when the password is blank and preserves advanced fields not exposed by the form. Clearing authentication requires an explicit checkbox. Renaming a node is intentionally unsupported. Deletion is refused when source rules, groups, listeners, dialer proxies or managed devices reference it.

Nodes created/edited through this page are stored privately in `/etc/phone-dns/managed-nodes.yaml` and merged during OpenClash generation. Existing source-only nodes are **not silently imported**. On a new configuration, missing managed nodes are added; same-name/different-parameter conflicts fail instead of overwriting either side. This preserves panel-managed nodes across source replacement, not arbitrary manual source edits. Back up this registry; never upload it to public GitHub.

The test button runs DNS/TCP/HTTPS egress checks and a separate **SOCKS5 UDP ASSOCIATE → UDP DNS query → matching answer** test via a loopback core listener bound to the selected node. It never falls back to direct UDP. A pass demonstrates this datagram path to the fixed test destination, not all UDP services, geographic eligibility or application support. A failure does not alone prove the provider lacks UDP.

## 中文使用流程

- 改设备：选择设备 → 选操作 → 预览 → 确认 → 到统一任务中心查看阶段和验收结果。
- 改 IP：手机重连 Wi-Fi 后才能获得新租约；固定配置、当前租约、最近公网出口分别显示。
- 改节点：选择编辑 → 选择节点 → 修改参数；密码空白保留旧认证；引用中的节点不能删除。
- 独立节点：通过面板新增/编辑后纳入私密节点库；应用 OpenClash 时自动合并，同名冲突停止，不静默覆盖。
- 检测节点：结果分别显示 DNS、代理出口、UDP 回包，不能把配置开关当作实测结果。
- 任务中断：不会自动重新执行；先核对状态和备份，再决定是否恢复。不要看到失败就连续提交。

## Verification boundaries

Automated fixtures cover transactions, stale runtime rejection, file/runtime recovery distinction, registry merging/conflicts, reference-blocked deletion, credential handling, device autofill and operation interruption classification. Real-router checks are non-destructive: loading the UI, read-only diagnostics, an idempotent reload and preservation of existing bindings. Full real-device deletion, deliberate live failure, power-loss/reboot recovery and cross-subscription migration are not production-tested.

## Durable binding state (1.2.0)

Preview and confirm the initial migration under Maintenance. The independent MAC-keyed registry, rather than a transient subscription rule, controls managed bindings. Derived source/runtime rules are rebuilt with exact ownership and conflict checks; independent startup protection is retained on load failures. Full last-verified snapshots include selected configuration, settings, DHCP and private node/binding data, with integrity checks and referenced-backup retention. Pre-registry program recovery is refused after migration. See [PERSISTENCE.md](PERSISTENCE.md) for deployment steps and validation limits.
