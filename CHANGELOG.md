# 更新日志 / Changelog

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
