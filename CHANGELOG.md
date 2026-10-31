# Changes

## Unreleased — device operations and observability

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

## Unreleased — web node creation and device fixes
- Add SOCKS5 node creation with redacted previews, explicit UDP choice, concrete dialer selection, source revision checks, private backups, core validation and runtime verification.
- Preserve explicitly configured UDP settings instead of overwriting them during listener generation.
- Add device IP migration and DHCP hostname synchronization; invalidate quick-start cache and verify generated runtime bindings.
- Replace numeric rebind group entry with named node selection and operation-specific fields.
- Retain private firewall diagnostics; enable interval-set auto-merge to avoid range extension conflicts.
- Add backend transaction/rollback, credential-redaction and browser DOM regression tests. Real newly provisioned paid-node connectivity/UDP remains unverified.
