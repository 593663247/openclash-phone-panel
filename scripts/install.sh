#!/bin/sh
# Stage files only. Never edit existing OpenClash hooks or restart networking.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MODE=${1:---check}
if [ "$MODE" = --install-deps ]; then
 exec sh "$ROOT/scripts/install-deps.sh" --install-deps
fi
case "$MODE" in --check|--install) ;; *) echo 'Usage: install.sh --check|--install|--install-deps'; exit 2;; esac
[ "$(id -u)" = 0 ] || { echo 'Run on router as root'; exit 1; }
for C in ruby lua uci nft fw4 curl netstat ip sha256sum sing-box dnsmasq; do command -v "$C" >/dev/null || { echo "Missing dependency: $C"; exit 1; }; done
[ -x /etc/openclash/clash ] && [ -d /usr/lib/lua/luci/controller ] || { echo 'OpenClash/LuCI missing'; exit 1; }
ruby -ryaml -e 'abort "Ruby >= 3.1 required" if (RUBY_VERSION.split(".").first(2).map(&:to_i) <=> [3,1]) < 0'
CFG=$(uci -q get openclash.config.config_path)
[ -f "$CFG" ] || { echo 'No active OpenClash source configuration'; exit 1; }
[ "$MODE" = --install ] || { echo 'Dependencies present. Read docs/INSTALL.md before installing; topology and ports are not automatically validated.'; exit 0; }
for P in /etc/phone-dns /etc/config/phone_panel /etc/init.d/phone-dns /etc/init.d/phone-panel-monitor /etc/init.d/phone-panel-guard /usr/lib/lua/luci/controller/phone_panel.lua /usr/lib/lua/luci/view/phone_panel.htm /usr/lib/lua/luci/model/cbi/phone_panel_settings.lua /etc/nftables.d/90-phone-fixed-egress.nft /etc/openclash/custom/phone-routing.sh; do
 [ ! -e "$P" ] || { echo "Refusing to overwrite existing path: $P"; exit 1; }
done
umask 077
mkdir -p /etc/phone-dns/jobs /etc/phone-dns/panel-requests
cp "$ROOT"/router/phone-dns/*.rb "$ROOT"/router/phone-dns/*.lua /etc/phone-dns/
printf '%s\n' '--- []' > /etc/phone-dns/mapping.yaml
printf '%s\n' '--- []' > /etc/phone-dns/devices.yaml
printf '%s\n' '--- []' > /etc/phone-dns/listeners.yaml
printf '%s\n' '{}' > /etc/phone-dns/config.json
cp "$ROOT/router/phone-dns/phone-dns.init" /etc/init.d/phone-dns
chmod 755 /etc/init.d/phone-dns
cp "$ROOT/router/phone-dns/phone-panel-monitor.init" /etc/init.d/phone-panel-monitor
chmod 755 /etc/init.d/phone-panel-monitor
cp "$ROOT/router/phone-dns/phone-panel-guard.init" /etc/init.d/phone-panel-guard
chmod 755 /etc/init.d/phone-panel-guard
/etc/init.d/phone-panel-guard enable
cp "$ROOT/router/phone-dns/status.rb" /etc/phone-dns/panel-status.rb
cp "$ROOT/router/luci/controller/phone_panel.lua" /usr/lib/lua/luci/controller/
mkdir -p /usr/lib/lua/luci/model/cbi
cp "$ROOT/router/config/phone_panel" /etc/config/
cp "$ROOT/router/luci/model/cbi/phone_panel_settings.lua" /usr/lib/lua/luci/model/cbi/
cp "$ROOT/router/luci/view/phone_panel.htm" /usr/lib/lua/luci/view/
ruby /etc/phone-dns/luci-cache.rb
cp "$ROOT/router/nftables/90-phone-fixed-egress.nft" /etc/nftables.d/
cp "$ROOT/router/openclash/phone-routing.sh" /etc/openclash/custom/
chmod 755 /etc/openclash/custom/phone-routing.sh
if [ "$ROOT" != /usr/share/phone-panel ]; then
 mkdir -p /usr/share/phone-panel
 cp -R "$ROOT/router" "$ROOT/scripts" /usr/share/phone-panel/
fi
echo 'Files staged. Do NOT start phone-dns yet. Complete docs/INSTALL.md, including backups, subnet edits, hook integration and validation.'
