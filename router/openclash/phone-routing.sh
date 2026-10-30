#!/bin/sh
# Reference integration for the tested fw4 REDIRECT + TPROXY topology.
set -eu
BR=$(uci -q get phone_panel.main.bridge || echo br-lan)
MARK=$(uci -q get phone_panel.main.fwmark || echo 0x162)
case "$BR" in *[!a-zA-Z0-9_.:-]*|'') exit 1;; esac
case "$MARK" in 0x*) ;; *) exit 1;; esac
HEX=${MARK#0x}; case "$HEX" in *[!0-9a-fA-F]*|'') exit 1;; esac
nft list chain inet fw4 openclash >/dev/null
nft list chain inet fw4 openclash_mangle >/dev/null
P=$(uci -q get openclash.config.proxy_port)
T=$(uci -q get openclash.config.tproxy_port)
case "$P:$T" in *[!0-9:]*|:*|*:) exit 1;; esac
for C in openclash openclash_mangle input; do
 nft -a list chain inet fw4 "$C" | sed -n '/comment "codex-phone-/s/.*# handle \([0-9]*\).*/\1/p' | while read -r H; do nft delete rule inet fw4 "$C" handle "$H"; done
done
nft list chain inet fw4 codex_phone_tcp >/dev/null 2>&1 || nft add chain inet fw4 codex_phone_tcp
nft list chain inet fw4 codex_phone_udp >/dev/null 2>&1 || nft add chain inet fw4 codex_phone_udp
nft flush chain inet fw4 codex_phone_tcp
nft flush chain inet fw4 codex_phone_udp
nft add rule inet fw4 codex_phone_tcp ip daddr @localnetwork return
nft add rule inet fw4 codex_phone_tcp ct direction reply return
nft add rule inet fw4 codex_phone_tcp ip protocol tcp counter redirect to :"$P"
nft add rule inet fw4 codex_phone_udp ip daddr @localnetwork return
nft add rule inet fw4 codex_phone_udp ct direction reply return
nft add rule inet fw4 codex_phone_udp meta l4proto udp meta mark set "$MARK" tproxy ip to 127.0.0.1:"$T" counter accept
nft insert rule inet fw4 openclash ip saddr @codex_phone4 jump codex_phone_tcp comment '"codex-phone-tcp"'
nft insert rule inet fw4 openclash_mangle ip saddr @codex_phone4 jump codex_phone_udp comment '"codex-phone-udp"'
nft insert rule inet fw4 input iifname "\"$BR\"" ip saddr @codex_phone4 meta mark "$MARK" meta l4proto udp counter accept comment '"codex-phone-udp-input"'
