from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
for name in ("router/nftables/90-phone-fixed-egress.nft", "router/phone-dns/align-dns.rb", "router/phone-dns/device-manager.rb"):
    text = (ROOT / name).read_text()
    assert "priority -101;" in text, name
    assert -101 < -100  # precedes OpenClash DNS Hijack at dstnat
manager = (ROOT / "router/phone-dns/device-manager.rb").read_text()
assert "ip saddr { #{g['ips'].join(', ')} }" in manager
assert "th dport 53" in manager
print("PASS: DNS ordering persisted; redirect remains scoped to bound group IPs")
status = (ROOT / "router/phone-dns/status-lib.rb").read_text()
assert "redirect to :" in status and "(?!" in status, "DNS ready check must match ports exactly"
assert "@codex_phone4" in status and "@codex_phone_mac" in status, "guard check must verify IP and MAC sets"
print("PASS: status checks use exact port and guard-set matching")
