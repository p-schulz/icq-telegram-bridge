#!/usr/bin/env bash
# Capture all traffic to/from one client during ICQ 5.1 startup and login (M0 task 4).
# Usage: sudo infra/capture/capture-startup.sh <client-ip> [label]
# Output: docs/captures/<label>-<timestamp>.pcap (gitignored; strip credentials before sharing).
. "$(dirname "$0")/../common.sh"
[[ $# -ge 1 ]] || { echo "Usage: $0 <client-ip> [label]" >&2; exit 2; }
out="$ROOT_DIR/docs/captures/${2:-icq51-startup}-$(date +%Y%m%d-%H%M%S).pcap"
echo "Capturing on $LAN_IFACE for host $1 -> $out (Ctrl-C to stop)"
# --immediate-mode: on macOS the BPF device batches packets, and Ctrl-C then exits without
# draining it ("0 packets captured, N received by filter"). Immediate mode avoids that.
# -U writes each packet to the file immediately, so a killed terminal does not lose the capture.
# Sanity check: run "nslookup example.com" on the client right after starting; you should
# see the packet counter ("Got N") rise. If it stays at 0, the capture is not seeing the client.
exec tcpdump -i "$LAN_IFACE" --immediate-mode -n -U -s 0 -w "$out" host "$1"
