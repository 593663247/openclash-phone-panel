# 更新日志 / Changelog

## [1.4.1] — 2026-11-04

- 修复 DNS 重定向就绪判断的子串误匹配：改为按 `redirect to :端口` 精确匹配，避免 :530 误命中 :5301。
- 防护就绪判断不再只看是否出现 drop：要求防护链同时引用手机 IP 集合与 MAC 集合，并至少有两条 drop 规则。
- 任务中心：临时文件使用含进程号和随机数的唯一后缀，避免并发写入互相覆盖；任务列表遇到单个损坏文件时跳过，不再导致整体报错。
- 新增 DNS 优先级与状态判断回归测试，并将 Python 回归测试纳入 npm test；本机 Ruby 低于 2.7 时跳过更新包 Ruby 检查。
- DNS 重定向链优先级保持 -101（dstnat - 1），早于 OpenClash DNS 劫持，未做改动。

## [1.4.0] — 2026-11-02

- 主页新增“其他局域网设备流量”，自动观察当前配置网段的有效 DHCP 租约、静态租约与 IPv4 邻居记录，排除已绑定手机节点的 IP/MAC 以及身份冲突，最多 256 台。
- 复用独立计数表统计其他设备的实时上传/下载、今日和本月累计；仅增加计数，不修改代理绑定、DHCP 或业务转发规则。硬件/软件卸载及未经过路由器的交换流量可能漏计。
- 支持设备名称/IP/MAC 搜索、按速率/今日流量/IP 排序、默认十条与分批展开；缺少采样时明确显示等待，不伪装成零速率。
- 防止 IP 换设备后展示前一 MAC 的历史累计；新增发现冲突、身份隔离、采样和页面回归。

## [1.3.2] — 2026-11-01

- 修复启用 fw4 流量分载时，live 合并钩子执行不受支持的 `nft flush flowtable` 导致运行态验收中断的问题。
- live 钩子仅维护面板自己的集合与 DNS 链，不再尝试修改 fw4 共享 flowtable；完整配置应用仍保留原有防火墙重载流程。本修复不承诺清除现存加速连接缓存。
- 增加 flowtable 存在时执行真实 live 分支的回归，覆盖 DNS 服务重启、运行态验收和持久化检查点，防止只测离线生成遗漏此类错误。

## [1.3.1] — 2026-11-01

- 修复实机发现的 OpenClash 临时生成路径兼容问题：自定义覆写使用 `/tmp/<当前配置名>.yaml`，旧白名单误拒后会跳过 SOCKS 入口生成，导致 DNS/出口检测和持久化验收失败。
- 仅允许当前配置同名、普通、非链接且权限受控的临时文件参与生成，不允许临时文件执行 live 防火墙应用；持久快照不再包含 OpenClash 自有临时文件。
- 使用真实监听器生成逻辑覆盖临时生成回归；配置没有 sniffer 时保持其关闭并记录设备排除项，避免后续验收因字段缺失失败。
- 识别并备份迁移早期发布的精确旧钩子正文，保留其他自定义内容；未知或重复的旧集成仍拒绝覆盖。
- 在用户路由器的独立临时副本上生成 17 个 SOCKS 入口，并通过现有 Mihomo 核心配置检查；未因此重载用户运行配置。

## [1.3.0] — 2026-11-01

- 在线升级只选择固定仓库的正式 Release，解析实际标签提交，并核对快进关系、版本、CI、发布附件身份、大小与 SHA-256；不再直接追随 main。
- 发布独立在线升级包，声明完整文件、目标路径、权限、逐文件校验和及升级器格式要求。安装前检查所有文件，安装后再次核验内容和权限，新文件不再依赖旧版硬编码安装列表。
- 将升级及程序恢复接入统一后台任务和阶段记录；网页关闭后继续执行，失败明确报告文件和服务恢复结果。
- 持久记录安装前程序快照、受保护配置摘要和服务基线。未完成安装或恢复未验收时阻止后续升级，并提供程序恢复入口；不自动重放迁移。
- 为安装、备份与恢复核对空间，下载/校验失败不修改原程序。程序升级不修改设备、节点、DHCP 和 OpenClash 配置，不自动执行设备持久化迁移。
- 增加七个旧版布局的打包升级夹具、损坏下载、发布变化、缺少文件、权限/格式冲突、磁盘写满、服务恢复失败及真实 SIGKILL 中断回归。
- 标签发布必须先通过完整 Linux CI，再构建同一提交的安装包，上传完整草稿后发布；已正式发布的版本不覆盖。物理路由器断电、重启和业务验证仍需部署验收。

## [1.2.1] — 2026-11-01

- Repair the independent boot guard omitted by older online updater processes, using only the SHA-256 verified script from the installed source bundle. Enable it before activating persistent bindings; reject missing, altered or linked repair sources.
- Avoid restarting an untouched OpenClash/DNS runtime when configuration preparation fails. Restore files and guard state, then independently verify the existing runtime; failures after service activation still trigger a full recovery restart.
- Add upgrade-omission, tampered/missing helper and rollback regressions. Router service availability and phone traffic still require physical acceptance.

## [1.2.0] — 2026-11-01

- Add a versioned independent device-binding registry, stable MAC identity and exact owned-rule history, preserving rename/rebind/IP changes and explicit deletions across configuration replacements.
- Add read-only migration previews with source/settings/DHCP/registry revision gates and explicit background application. Conflicting legacy state cannot be silently imported.
- Reconcile independent nodes and bindings into both the active source and generated runtime before loading, preserving unowned rules and rejecting missing/conflicting nodes, duplicate rules, corrupt registries and DHCP identity/name mismatches.
- Add an independent nft forwarding guard and early-boot helper, with a separate saved guard fallback. Protection survives replacement of fw4 or a failed OpenClash load; local proxy delivery is not dropped.
- Flush and atomically replace private configuration/journal files and synchronize directories. Report generation, runtime verification, conflicts and interrupted processes separately; derivation can rerun without replaying user mutations.
- Save protected complete last-verified snapshots, restore configuration selection/settings/node/device/DHCP state with runtime checks, and retain explicit file/runtime recovery results. Referenced recovery snapshots cannot be recycled.
- Preserve registry data through program upgrades and reject program recovery to snapshots predating the registry format. Legacy installations must preview and confirm migration under Maintenance.
- Add pure, workflow, failure-injection, browser and isolated real-nft regression coverage. Physical router reboot/power-loss, subscription integration and network-traffic acceptance remain required deployment checks.

## [1.1.1] — 2026-10-31

- Display the installed version alongside the actual latest published GitHub Release tag, comparison and check time, with a link to release notes.
- Query release information separately when Maintenance opens; cache successful lookups for one hour, throttle failed automatic retries for one minute, and force refresh when checking updates.
- Preserve failed-query results as explicitly labelled previous records; never infer a latest version from the installed version, main SHA or a failed request.
- Keep main-branch fast-forward, CI and local preflight upgrade gates unchanged, and explain the distinction from formal Release information.
- Add backend and DOM regressions for cache/manual refresh, failures, draft/prerelease/tag validation and unchanged CI gating.

## [1.1.0] — 2026-10-31

- Replace persistent device/node forms with searchable lists and focused native modal editors. Show ten entries initially, with explicit load-more controls.
- Display configured IP, current lease and recent exit separately. Show device before/after changes and readable previews; hand submitted work back to the shared task center.
- Add per-node edit/test/reference-checked delete actions, managed/source labels and timestamp-aware diagnostic states. UDP configuration remains distinct from measured UDP results.
- Preserve open drafts during status/catalog refreshes, invalidate previews when relevant data changes, and clear node credentials when closing an editor. Support Escape, focus return and a single primary action per step.
- Simplify the home device overview, collapse traffic/technical details and extra filters, retain visible network-protection warnings, and collapse the add-device form until needed.
- Group initialization, environment maintenance, updates and backups. Collapse raw execution history and program recovery controls.
- Standardize form labels, spacing, theme-scoped controls, dangerous/disabled actions and 390px mobile layouts without adding another navigation bar.
- Extend interaction regressions for list actions, pagination, draft preservation and late-preview rejection. Validate desktop/mobile rendering and native dialogs using real Chrome with synthetic local APIs; no physical router or real network mutation was used for this release.

## [1.0.3] — 2026-10-31

- Remove the duplicate in-page navigation introduced in 1.0.2. Use the native LuCI tabs, keeping Devices & Nodes immediately after Home.
- Refresh legacy and suffixed LuCI menu caches plus panel-specific compiled module caches after IPK/manual installation and program activation/recovery; do not restart web or network services.
- Refresh menu caches before optional hook integration so hook errors cannot leave the old menu visible after new templates are installed.
- Add regression coverage for native tab ordering, single navigation, cache invalidation and preservation of unrelated files.

## [1.0.2] — 2026-10-31

- Add a dedicated Devices & Nodes category immediately to the right of Home, with consistent horizontal navigation and LuCI route ordering.
- Move device editing, SOCKS5 node management and DHCP batch addition out of Maintenance; initialize the node catalog on its new route.
- Collapse task history and backup management by default. Open tasks for new active/recovery events, while respecting manual collapse during unchanged polling.
- Separate active tasks, recovery-review records and past failures; omit missing subject placeholders.
- Show five backup entries initially, preserve selection when showing more, explain protected entries and hide full paths behind details. Ignore stale backup previews after selection changes.
- Keep backup retention and recycling restrictions unchanged; fix checkbox height under global input styles.
- Add route/DOM and backup interaction regressions, and update entry-point documentation.

## [1.0.1] — 2026-10-31

- Verify the committed DHCP section, fixed IP, preserved MAC and supported hostname again after service reload for device edits; mismatches trigger the shared rollback. A committed static assignment does not establish that the phone has renewed its lease.
- Require a nonempty preview revision for versioned transactions; reject missing or stale previews before mutation.
- Continue restoring remaining snapshot files after one restore fails, compare restored bytes, and still clean newly generated DNS files. Incomplete file recovery does not restart partially restored networking.
- Surface rollback failure details and required manual recovery in the task center; show DHCP acceptance separately from phone business/UDP validation.
- Add regressions for preview gating, post-reload DHCP mismatch, partial restore failure, snapshot mismatch and recovery UI. Use the current Python interpreter for portable package tests.
- Include the maintenance checks and UI polish below from the previously unreleased main branch.

### Maintenance checks and UI polish

- Gate update discovery and installation on conservative disk-space, command dependency, Ruby version, core, pending UCI edit and operation-lock checks.
- Add backup size/time inventory and previewed reversible recycling of standalone transaction backups older than seven days, keeping at least three recent snapshots. Recycling does not free disk space or permanently delete data.
- Mark old diagnostic measurements stale after max(15 minutes, twice the probe interval), removing primary green success emphasis.
- Polish scoped cards, status labels, spacing, keyboard focus and narrow-screen form layout.
- Add backup retention/path/revision/recycling tests and update-preflight failure regression coverage.
- Validation: frontend tests, isolated router backend tests and firewall checks passed. Final rendered visual QA remains blocked by local browser permissions. Existing v1.0.0 tag/assets remain unchanged.

## [1.0.0] — 2026-10-31

首个正式编号版本。Git tag: `v1.0.0`；opkg 包版本: `1.0.0-1`。

### 功能 / Features
- 设备固定出口、独立 DNS 分组与防直连规则；设备新增、改名、改绑与 IP 修改，DHCP 名称同步。
- SOCKS5 节点新增/编辑/引用检查删除、私密节点库、显式 UDP 设置与前置代理。
- 统一后台任务、配置版本检查、备份与恢复、共享应用引擎和文件/运行态分别验收。
- 设备在线/流量、固定 IP/当前租约/最近出口区分；TCP、DNS、HTTPS 出口和 UDP DNS 回包检测。
- 中文紧凑任务列表、时间排序、筛选、分页显示和自动刷新保留展开状态。
- GitHub CI 门控更新、程序回退；Windows 可直接解压的 ZIP、IPK 和 SHA256 校验。

### 验证边界 / Validation limits
已有路由器上的有限验证及隔离测试通过。不代表所有 OpenWrt 设备兼容；另机完整安装、真实删除、断电恢复、跨订阅迁移与全部 UDP 应用未完成实机验收。仅适用于 opkg + fw4 + LuCI，已有 OpenClash，Ruby >=3.1。**版本号 1.0.0 不取消这些限制。**

First numbered release, including per-device egress/DNS, SOCKS5 lifecycle management, asynchronous operations and recovery, diagnostics, localized task history and Windows-friendly packaging. Destructive recovery and cross-device/subscription compatibility remain unverified; see documentation.

## 历史开发记录 / Historical development notes

## Development history — — device operations and observability

- Add evidence-based online states, persistent last-seen data and region/search/health filtering.
- Add authenticated exit baseline acknowledgement, 96-entry per-node history, latency and layered diagnostics.
- Add counter-only IPv4 accounting, per-device rates, daily/monthly totals, thresholds and reboot/reset handling.
- Add a separate procd monitoring service with bounded, staggered automatic probes and low-frequency flash checkpoints.
- Add DHCP discovery and batch preview/apply (up to 32), with cross-device conflict checks and one transaction/restart.
- Add pinned-repository/commit/CI update checks, bounded archive extraction, automatic pre-update snapshots and code-only recovery preserving later device edits.
- Add real DOM and isolated backend/archive/recovery regression tests.

## Previous reliability and maintenance

- Reconcile deployed home/maintenance pages, allowlisted jobs, hook repair and device editing with repository code; protect edit previews from stale responses.
- Stage maintenance runtime sources on installation and upgrade so dashboard tasks retain their backend dependencies.

- Invalidate device previews after edits and catalog changes; ignore obsolete responses.
- Refresh available nodes without losing a valid selection. Clear obsolete probe results.
- Bound status requests to 15 seconds. Distinguish controller failure from zero connections.
- Resume pending device jobs after tab reload; offer another polling cycle after timeout and prevent new submissions while unresolved.
- Ignore expired/malformed DHCP leases, reject duplicate static assignments and shadowed source rules.
- Use full IPv4 addresses in generated DHCP section names, avoiding collisions across wider LAN subnets.
- Include effective settings and saved UCI settings in preview revisions; reject pending settings edits.
- Show only allowlisted warning summaries instead of raw proxy log text.
- Regenerate fail-closed guards for the configured bridge; remove newly generated DNS files on rollback.
- Back up active source YAML, custom hooks and routing integration. Preserve the chosen restore target when taking a pre-restore snapshot; validate restore paths.
- Upgrade init/routing code, retain existing settings/hooks, and reload firewall rules during explicit initialization.
- Refuse staging over existing settings/model files. Accept the configured high-port range in probes.
- Extend UI, backend planning, settings, lease and isolated maintenance regression tests; reconcile bilingual setup/operation documentation.

Validation covers source syntax and isolated behavior. No production router deployment, provider UDP test or complete runtime rollback guarantee is included.

## Development history — web node creation and device fixes
- Add SOCKS5 node creation with redacted previews, explicit UDP choice, concrete dialer selection, source revision checks, private backups, core validation and runtime verification.
- Preserve explicitly configured UDP settings instead of overwriting them during listener generation.
- Add device IP migration and DHCP hostname synchronization; invalidate quick-start cache and verify generated runtime bindings.
- Replace numeric rebind group entry with named node selection and operation-specific fields.
- Retain private firewall diagnostics; enable interval-set auto-merge to avoid range extension conflicts.
- Add backend transaction/rollback, credential-redaction and browser DOM regression tests. Real newly provisioned paid-node connectivity/UDP remains unverified.

## Development history — unified operations, device selection and node lifecycle
- Persistent operation journal, stage tracking, reboot/dead-worker interruption classification and confirmed snapshot recovery.
- Shared lock/apply/verification/rollback engine for device mutation, node mutation and initialization; atomic configuration writes and separate file/runtime restoration status.
- Managed-device dropdown with auto-filled fields, configured/leased/public-IP distinction.
- SOCKS5 update/delete with reference checks, preservation of advanced fields and blank-password retention.
- Private managed-node registry, source-switch merge and explicit collision refusal.
- Real per-node SOCKS5 UDP ASSOCIATE/DNS-datagram testing with no direct fallback; display measured UDP status separately from the configuration flag.
- Extended fixture and DOM regression suites. Destructive live recovery and cross-device migration remain unverified.
