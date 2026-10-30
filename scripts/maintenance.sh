#!/bin/sh
# Explicit maintenance only; no automatic network changes on installation.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ACTION=${1:-doctor}
[ "$(id -u)" = 0 ] || { echo 'Run on router as root'; exit 1; }
source_config() {
 CFG=$(uci -q get openclash.config.config_path)
 case "$CFG" in /etc/openclash/config/*.yaml) ;; *) echo 'Invalid OpenClash source path' >&2; exit 1;; esac
 case "$CFG" in *'/../'*|*'/./'*|*'//'*) echo 'Non-canonical source path' >&2; exit 1;; esac
 [ -f "$CFG" ] || { echo 'Active source file missing' >&2; exit 1; }
}
backup() (
 source_config
 B=/root/phone-panel-maintenance/$(date +%Y%m%d%H%M%S)-$$
 umask 077; mkdir -p "$B"
 for P in "${CFG#/}" etc/openclash/custom/phone-routing.sh etc/openclash/custom/openclash_custom_overwrite.sh etc/openclash/custom/openclash_custom_firewall_rules.sh etc/phone-dns etc/config/phone_panel etc/config/dhcp etc/nftables.d/90-phone-fixed-egress.nft etc/init.d/phone-dns usr/lib/lua/luci/controller/phone_panel.lua usr/lib/lua/luci/view/phone_panel.htm usr/lib/lua/luci/model/cbi/phone_panel_settings.lua; do
  if [ -e "/$P" ]; then mkdir -p "$B/$(dirname "$P")"; cp -a "/$P" "$B/$P"; fi
 done
 printf '%s\n' "$CFG" > "$B/source-path"
 echo "$B"
)
case "$ACTION" in
 doctor)
  sh "$ROOT/scripts/install.sh" --check
  ruby -I "$ROOT/router/phone-dns" -rsettings -e 'PhoneSettings.values; puts "Settings validation PASS"'
  ;;
 backup) backup ;;
 initialize)
  [ "${2:-}" = --apply ] || { echo 'Use initialize --apply in a maintenance window; configure hooks per INSTALL.md first'; exit 2; }
  sh "$0" doctor
  B=$(backup); echo "Recovery snapshot: $B"
  CFG=$(uci -q get openclash.config.config_path)
  ruby /etc/phone-dns/align-dns.rb "$CFG"
  fw4 check
  sing-box check -c /etc/phone-dns/config.json
  /etc/init.d/phone-dns enable
  /etc/init.d/openclash stop
  /etc/init.d/firewall reload
  /etc/init.d/openclash start
  ;;
 upgrade)
  sh "$0" doctor
  B=$(backup); echo "Recovery snapshot: $B"
  [ -d /etc/phone-dns ] || exit 1
  cp "$ROOT"/router/phone-dns/*.rb /etc/phone-dns/
  cp "$ROOT/router/phone-dns/status.rb" /etc/phone-dns/panel-status.rb
  cp "$ROOT/router/phone-dns/phone-dns.init" /etc/init.d/phone-dns
  chmod 755 /etc/init.d/phone-dns
  cp "$ROOT/router/openclash/phone-routing.sh" /etc/openclash/custom/phone-routing.sh
  chmod 755 /etc/openclash/custom/phone-routing.sh
  cp "$ROOT/router/luci/controller/phone_panel.lua" /usr/lib/lua/luci/controller/
  cp "$ROOT/router/luci/view/phone_panel.htm" /usr/lib/lua/luci/view/
  mkdir -p /usr/lib/lua/luci/model/cbi
  cp "$ROOT/router/luci/model/cbi/phone_panel_settings.lua" /usr/lib/lua/luci/model/cbi/
  [ -f /etc/config/phone_panel ] || cp "$ROOT/router/config/phone_panel" /etc/config/
  echo 'Upgrade staged, configuration preserved. Run doctor, review hooks, then initialize --apply.'
  ;;
 restore)
  B=${2:-}
  [ -n "$B" ] && [ -d "$B" ] || { echo 'Snapshot directory missing'; exit 2; }
  B=$(CDPATH='' cd -P -- "$B" && pwd -P)
  case "$B" in /root/phone-panel-maintenance/*) ;; *) echo 'Only local maintenance snapshots accepted'; exit 2;; esac
  NAME=${B#/root/phone-panel-maintenance/}
  case "$NAME" in ''|*/*) echo 'Select a single snapshot directory'; exit 2;; esac
  [ -d "$B/etc/phone-dns" ] || exit 1
  [ "${3:-}" = --apply ] || { echo 'Use restore SNAPSHOT --apply; services will be stopped; reactivate manually after checking'; exit 2; }
  backup
  /etc/init.d/phone-dns stop
  /etc/init.d/openclash stop
  cp -a "$B/etc/." /etc/
  [ ! -d "$B/usr" ] || cp -a "$B/usr/." /usr/
  echo 'Files restored. Inspect hooks and fw4 check before restarting services; runtime rollback is not guaranteed.'
  ;;
 uninstall)
  [ "${2:-}" = --disable ] || { echo 'Use uninstall --disable; first remove project hooks as documented'; exit 2; }
  backup
  /etc/init.d/phone-dns stop; /etc/init.d/phone-dns disable
  echo 'Service disabled, private state retained. Remove project hooks and restore preinstallation firewall/DHCP backups per INSTALL.md. No files or protection rules silently deleted.'
  ;;
 *) echo 'doctor | backup | initialize --apply | upgrade | restore SNAPSHOT --apply | uninstall --disable'; exit 2;;
esac
