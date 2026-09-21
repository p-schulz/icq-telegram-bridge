#!/usr/bin/env bash
# Render the dnsmasq config from lab.env and run dnsmasq in the foreground (needs root for port 53).
# Usage: sudo infra/dnsmasq/run-dnsmasq.sh [--render]
#   --render  only write infra/dnsmasq/generated/dnsmasq.conf and exit (used by scripts/install.sh)
# Env: DNSMASQ_LOG overrides the query log path (default: generated/queries.log).
. "$(dirname "$0")/../common.sh"
render_only=0; [[ "${1:-}" == "--render" ]] && render_only=1
command -v dnsmasq >/dev/null || { echo "dnsmasq not installed (macOS: brew install dnsmasq; Debian: apt install dnsmasq)." >&2; exit 1; }

gen="$INFRA_DIR/dnsmasq/generated"; mkdir -p "$gen"
sed -e "s|@SERVER_IP@|$SERVER_IP|g" "$INFRA_DIR/dnsmasq/redirects.conf" > "$gen/redirects.conf"
sed -e "s|@LAN_IFACE@|$LAN_IFACE|g" \
    -e "s|@UPSTREAM_DNS@|$UPSTREAM_DNS|g" \
    -e "s|@LOG_FILE@|${DNSMASQ_LOG:-$gen/queries.log}|g" \
    -e "s|@REDIRECTS_FILE@|$gen/redirects.conf|g" \
    "$INFRA_DIR/dnsmasq/dnsmasq.conf.template" > "$gen/dnsmasq.conf"

dnsmasq --test -C "$gen/dnsmasq.conf"
[[ $render_only -eq 1 ]] && { echo "Rendered $gen/dnsmasq.conf"; exit 0; }
echo "Query log: ${DNSMASQ_LOG:-$gen/queries.log}"
exec dnsmasq --keep-in-foreground -C "$gen/dnsmasq.conf"
