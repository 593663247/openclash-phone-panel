# Upgrade preflight, backup capacity and freshness

Upgrade checks now require readable free-space values (96 MiB in /tmp, 64 MiB in /root), required commands, Ruby >=3.1, an executable OpenClash core, no pending DHCP/panel/OpenClash UCI edits and an available configuration lock. Checks run on update discovery and again before upgrade. These are conservative local gates, not proof of provider/library compatibility; missing dependencies are never installed implicitly.

Backup capacity shows only known backup roots, item sizes, timestamps and recycle-directory size. Recent three transaction backups are protected; only standalone transactions older than seven days can be selected for preview and moved to a private recycle directory. No permanent deletion is performed and moving does not free space. The recycle directory contains a restore manifest of original/destination paths. Permanent cleanup is deliberately not exposed. Known release snapshots and referenced maintenance backups cannot be selected.

Measurements older than max(15 minutes, twice the configured probe interval) are marked stale and lose the primary green success emphasis. Historical data remains available; a failed old measurement is not silently turned into success. UDP datagram tests do not prove all UDP applications are available.

The UI uses scoped card styling, compact task rows, clear status badges, keyboard focus outlines and mobile form layout. The release tag v1.0.0 remains immutable; these changes are unversioned working changes pending a later release.
