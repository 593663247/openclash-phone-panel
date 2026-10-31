> Release: **v1.0.0** · opkg: **1.0.0-1** · [Changelog](CHANGELOG.md) · [Downloads](https://github.com/593663247/openclash-phone-panel/releases/tag/v1.0.0)

# OpenClash Phone Panel

[简体中文](README.md) · [Installation](docs/INSTALL.md) · [User Guide](docs/USER_GUIDE.en.md)

A LuCI dashboard for device-specific proxy egress, per-node encrypted DNS and OpenClash configuration synchronization.

> **Experimental reference implementation, not an official OpenClash plugin or a universal one-click installer.**
> Extracted from a specific fw4 + REDIRECT/TPROXY deployment. Deployment data is excluded. The public reference defaults to `192.168.1.0/24` and `br-lan`; configure other single-LAN subnets through UCI settings; different topologies still need review. The staging script does not activate networking.

## Features

Includes observed device presence, exit-IP change alerts, search/region/health filters, persistent health history, per-device IPv4 traffic accounting, transactional DHCP batch addition, layered diagnostics, and CI-gated updates with code-only rollback. [Detailed feature guide](docs/FEATURES.zh-CN.md).

- Device/node cards, DNS listener status and connection counters inside existing LuCI authentication; 15-second read-only refresh.
- Discover proxies named with the literal `手机-` prefix (Chinese for “phone”).
- Import top-of-list `SRC-IP-CIDR,<IPv4>/32,<phone-proxy>` rules using an unambiguous static or current DHCP lease.
- Report missing MACs, conflicting leases and duplicate rules as pending instead of guessing or overwriting devices.
- Align per-node dnsmasq caches and Google DoH detours with business egress rules.
- Preview/confirm device addition with job status and configuration recovery records.
- Automatically enable UDP on `手机-` SOCKS5 business proxies, while keeping DNS-only loopback SOCKS listeners TCP-only.
- Reference IP/MAC fail-closed forwarding protection, DNS port-53 interception, sniffing exclusions and routing integration.

## Usage overview

Provide your own proxies and an explicit rule such as:

```yaml
rules:
  - SRC-IP-CIDR,192.168.1.101/32,手机-01-示例
  # Place device bindings before domain rules, rule sets and MATCH.
```

Create a unique static DHCP lease for that device. Follow [Installation](docs/INSTALL.md), integrate the hooks, apply OpenClash, then visit **LuCI → Services → 手机出口与 DNS**:

```text
/cgi-bin/luci/admin/services/phone_panel
```

**Refreshing the dashboard does not apply changes. Synchronization runs when OpenClash generates/applies its configuration.**

## Compatibility and limitations

Deployment baseline previously checked: ImmortalWrt 24.10.2, LuCI Lua compatibility layer, fw4/nftables, Mihomo and sing-box 1.12.8. Requires Ruby 3.1+ with YAML/Psych, Lua/nixio, curl and dnsmasq. The sanitized public staging procedure has not been fresh-installed on every platform.

The reference supports one configurable IPv4 LAN (CIDR /8 through /30, default /24), a configurable proxy prefix (default `手机-`), direct proxy targets and at most 100 node groups. It is not validated for TUN, iptables, multiple VLANs, arbitrary firewall marks, IPv6 source rules or policy-group bindings. Devices & Nodes provides searchable device and node lists with modal editors for rename, rebind, IP changes and removal. Removal retains DHCP leases and releases panel protection for that device. Move devices before removing/renaming nodes.

UDP enabled is configuration state, not a successful UDP transport test. Listener readiness is not a leak audit. Client Private DNS/application DoH bypass port-53 interception. MAC-based forwarding guards can block external IPv6. File snapshots do not guarantee crash-safe or complete runtime rollback. Review the [User Guide](docs/USER_GUIDE.en.md) before deployment.

## Development

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

CI validates syntax, planning, asynchronous UI state, isolated filesystem backup/restore and publication contents, not a real router or proxy provider. Do not blindly deploy to production.

## Privacy and license

No real proxy configuration, credentials, leases, device inventory, logs, screenshots or backups are included. All example network/device values are synthetic. Never submit unsanitized runtime YAML or logs. See [SECURITY.md](SECURITY.md).

MIT License. Not affiliated with OpenClash or ImmortalWrt.

### Landing-node creation

The Devices & Nodes page supports SOCKS5 creation, editing and reference-checked deletion with credentials, explicit UDP preference, an optional concrete dialer proxy, redacted preview, confirmed loading and rollback. See [node management](docs/NODE_MANAGEMENT.md). This update also fixes device IP migration, DHCP hostname synchronization, node selectors and interval-set merging.

### Unified operations and node lifecycle

Persistent background tasks, shared apply/recovery verification, device selection, fixed/leased/egress IP distinction, reference-aware SOCKS5 editing/deletion, a private node registry and measured UDP datagram tests are now available. See [operations and verification boundaries](docs/OPERATIONS.md). Destructive live recovery and cross-subscription migration remain unverified.

### Durable device bindings (1.2.0)

Existing installations must preview and confirm migration under Maintenance → Device-binding persistence. A versioned independent registry restores exact owned rules during subscription/configuration changes, with conflict rejection, an early independent forwarding guard and complete verified snapshots. Missing/corrupt policy data never silently becomes an empty installation. See [persistence and recovery](docs/PERSISTENCE.md). Physical power-loss and device/network acceptance remain deployment checks.
