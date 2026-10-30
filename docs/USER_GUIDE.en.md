# English User Guide

## 1. Dashboard

Sign in to existing LuCI and open **Services → 手机出口与 DNS**. No additional public port or account is required. Keep LuCI authentication and POST CSRF checks; do not expose the panel or control API publicly.

- **DNS listener ready** means a port is listening, not that the upstream is reachable.
- **Guard loaded** means a protection chain was detected, not a complete leak audit.
- **Lease present** does not mean the phone is currently online.
- **UDP enabled** reflects the proxy configuration, not a successful UDP ASSOCIATE test.
- **Connections / UDP** are kernel records, not a delivery success rate.
- **Test DNS / egress** queries example.com and requests api.ipify.org through the fixed SOCKS listener. This contacts external services, and does not emulate every phone application.

The 15-second timer refreshes status only. It does not continuously apply network configuration.

## 2. Automatic import

1. Add a real proxy to the active source configuration with a name starting with the literal `手机-` prefix.
2. Add exactly one top-of-list source rule:

   ```yaml
   - SRC-IP-CIDR,192.168.1.101/32,手机-01-示例
   ```

3. Create a unique static DHCP lease for that phone. An unambiguous unexpired current lease can also be converted to a static lease by the importer.
4. Save and apply OpenClash. This can interrupt proxy traffic briefly.
5. Refresh the panel and inspect the imported device/group, or resolve the reason listed under pending imports.

Phones sharing a proxy share that node's DNS cache and egress. Isolation is per proxy node, not per process. Google DoH uses `8.8.8.8`/`8.8.4.4` with TLS SNI `dns.google`, detoured through a fixed node-specific SOCKS listener without ISP fallback.

Automatic UDP enabling affects only `手机-` SOCKS5 business proxies. The provider still needs working UDP support. The TCP-only DNS SOCKS listener does not disable UDP on the business proxy.

## 3. Add a device manually

Enter a label, stable Wi-Fi MAC, unused fixed IPv4 and node. Click **检查并预览** (check/preview), verify the plan, then **确认应用** (confirm/apply). The job checks conflicts, snapshots files, updates static DHCP/rules/DNS/protection and restarts affected services after validation. Reconnect Wi-Fi and run the group's tests.

Use the MAC actually used on this Wi-Fi, not another network's MAC. Disable periodically rotating addresses or select a stable mode. An offline device may still own an address: absence from current leases is not proof that it is free.

A matching existing source rule can be adopted to complete a pending import after you supply the missing MAC. Conflicting rules/leases must be corrected manually.

## 4. Rebinding and deletion

Edit the existing `/32` rule target in the active source configuration, save and apply. DNS follows the business egress target, not the other way around.

Old devices are not automatically deleted. There is no general-purpose delete action. Migrate devices and inspect mapping/leases/listeners/firewall sets before deleting a source rule or renaming/removing its node. Ambiguous/missing managed rules cause alignment to fail rather than guess.

Single-device IPv4 /32 rules are supported within one configurable LAN (CIDR parameters /8 through /30, default /24). Wider subnet integration still needs router testing. Policy-group targets, arbitrary CIDRs, IPv6 source addresses and multiple LANs require adaptation. No proxy subscriptions or provider accounts are included.

## 5. Troubleshooting

| Symptom | Check |
|---|---|
| Missing node | Active source file, direct proxy definition, literal `手机-` name prefix |
| Missing MAC | Connect phone or create a unique static lease; apply again |
| Lease conflict | Duplicate IP/MAC assignments, current leases and pending UCI changes |
| Import rejected | Unique `/32` source rule before other rule types |
| Stale UI | Reload LuCI completely and verify template cache refresh |
| Listener ready but test fails | Upstream credentials, SOCKS reachability, dialer chain and DoH endpoint |
| UDP enabled but application fails | Provider UDP ASSOCIATE/relay reachability, TPROXY, policy routes and return path |
| context deadline exceeded | Inspect node/target and test the actual path; timeout alone is not a root cause |
| rejected username/password | Verify upstream proxy authentication without posting credentials |
| Connectivity lost after apply | Use local recovery access and the recovery procedure in INSTALL.md |

## 6. Security and recovery

Write actions require authenticated LuCI and a POST CSRF token. This is privileged router software: do not grant untrusted users access or remove those controls.

Snapshots contain private proxy/DHCP data and stay on the router. Never upload them. Rollback is not a transaction engine; concurrent edits, process crashes, failed service startups or power loss can leave runtime state inconsistent even when files are restored. Keep wired/local recovery access.

MAC guards may block external IPv6. Reference routing retains private/local destinations rather than proxying every packet. Client Private DNS and application DoH bypass port-53 interception. Test these separately: ready listeners and a successful egress test do not establish absence of DNS/IPv6 leaks.

## 7. Status and job recovery

Form edits or catalog changes invalidate previews. Binding changes clear old probe results. An unavailable controller is shown as unavailable, not zero connections. Status reads have a 15-second timeout.

The current tab stores the pending job ID in session storage and resumes polling after reload. If polling reaches its retry limit, use the resume button; new submissions remain blocked until the job ends. If session storage is disabled, retain the displayed job ID. Warning summaries include only time, managed IP and error category; inspect detailed logs locally on the router.
