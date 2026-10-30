#!/bin/sh
# Install only missing runtime packages from the router's configured opkg feeds.
set -eu
MODE=${1:---check}
case "$MODE" in --check|--install-deps) ;; *) echo 'Usage: install-deps.sh --check|--install-deps'; exit 2;; esac
command -v opkg >/dev/null || { echo 'Unsupported package manager: opkg required; nothing changed'; exit 1; }
MISSING=''
need() { command -v "$1" >/dev/null 2>&1 || MISSING="$MISSING $2"; }
need ruby ruby
need lua lua
need curl curl
need nft nftables
need fw4 firewall4
need netstat net-tools-netstat
need ip ip-full
need sha256sum coreutils-sha256sum
need sing-box sing-box
need dnsmasq dnsmasq
need uci uci
if command -v ruby >/dev/null 2>&1; then
 ruby -ryaml -e 'exit 0' >/dev/null 2>&1 || MISSING="$MISSING ruby-yaml"
else
 MISSING="$MISSING ruby-yaml"
fi
MISSING=$(printf '%s\n' "$MISSING" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')
[ -n "$MISSING" ] || { echo 'Runtime command/module dependency checks passed'; exit 0; }
echo "Missing packages: $MISSING"
[ "$MODE" = --install-deps ] || exit 1
[ "$(id -u)" = 0 ] || { echo 'Root required'; exit 1; }
FREE=$(df -Pk /overlay 2>/dev/null | awk 'END {print $4}')
case "$FREE" in ''|*[!0-9]*) echo 'Cannot determine overlay free space'; exit 1;; esac
[ "$FREE" -ge 32768 ] || { echo 'At least 32 MiB free overlay space required; package sizes may require more'; exit 1; }
echo 'Using configured opkg feeds. No system upgrade, custom feeds, or remote install scripts.'
opkg update
# Resolve every package before installing any package. Do not bypass feed signatures.
for P in $MISSING; do
 opkg info "$P" | grep -q '^Package:' || { echo "Package unavailable: $P; check firmware feed compatibility"; exit 1; }
done
for P in $MISSING; do
 opkg install "$P" || { echo "Installation failed: $P. Previously installed dependencies retained; no automatic removal."; exit 1; }
done
sh "$0" --check
echo 'Dependencies installed; run maintenance.sh doctor for version/topology checks.'
