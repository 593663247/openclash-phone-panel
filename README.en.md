# OpenClash Phone Panel

[简体中文](README.md) · [Installation](docs/INSTALL.md) · [User Guide](docs/USER_GUIDE.en.md)

A LuCI dashboard for device-specific proxy egress, per-node encrypted DNS and OpenClash configuration synchronization.

> **Experimental reference implementation, not an official OpenClash plugin or a universal one-click installer.**
> Extracted from a specific fw4 + REDIRECT/TPROXY deployment. Deployment data is excluded. The public reference defaults to `192.168.1.0/24` and `br-lan`; adapt it before using a different network. The staging script does not activate networking.

## Features

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

The reference supports one IPv4 `/24`, literal proxy names beginning `手机-`, direct proxy targets and at most 100 node groups. It is not validated for TUN, iptables, multiple VLANs, arbitrary firewall marks, IPv6 source rules or policy-group bindings. Existing devices are not automatically deleted. Move devices before removing/renaming their nodes.

UDP enabled is configuration state, not a successful UDP transport test. Listener readiness is not a leak audit. Client Private DNS/application DoH bypass port-53 interception. MAC-based forwarding guards can block external IPv6. File snapshots do not guarantee crash-safe or complete runtime rollback. Review the [User Guide](docs/USER_GUIDE.en.md) before deployment.

## Development

```sh
ruby tests/test-auto-import.rb
python3 scripts/privacy_check.py
find router tests -name '*.rb' -exec ruby -c {} \;
sh -n scripts/install.sh
```

CI validates syntax, pure planning behavior and publication contents, not a real router or proxy provider. Do not blindly deploy to production.

## Privacy and license

No real proxy configuration, credentials, leases, device inventory, logs, screenshots or backups are included. All example network/device values are synthetic. Never submit unsanitized runtime YAML or logs. See [SECURITY.md](SECURITY.md).

MIT License. Not affiliated with OpenClash or ImmortalWrt.
