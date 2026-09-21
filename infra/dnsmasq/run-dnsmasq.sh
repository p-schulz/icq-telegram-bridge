#!/usr/bin/env bash
# Render the dnsmasq config from lab.env and run dnsmasq in the foreground (needs root for port 53).
# Usage: sudo infra/dnsmasq/run-dnsmasq.sh
. "$(dirname "$0")/../common.sh"
command -v dnsmasq >/dev/null || { echo "dnsmasq not installed (macOS: brew install dnsmasq; Debian: apt install dnsmasq)." >&2; exit 1; }

gen="$INFRA_DIR/dnsmasq/generated"; mkdir -p "$gen"
sed -e "s|@SERVER_IP@|$SERVER_IP|g" "$INFRA_DIR/dnsmasq/redirects.conf" > "$gen/redirects.conf"
sed -e "s|@LAN_IFACE@|$LAN_IFACE|g" \
    -e "s|@UPSTREAM_DNS@|$UPSTREAM_DNS|g" \
    -e "s|@LOG_FILE@|$gen/queries.log|g" \
    -e "s|@REDIRECTS_FILE@|$gen/redirects.conf|g" \
    "$INFRA_DIR/dnsmasq/dnsmasq.conf.template" > "$gen/dnsmasq.conf"

dnsmasq --test -C "$gen/dnsmasq.conf"
echo "Query log: $gen/queries.log"
exec dnsmasq --keep-in-foreground -C "$gen/dnsmasq.conf"
