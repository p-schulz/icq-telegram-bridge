#!/usr/bin/env bash
# Server-side smoke test: API up, two lab accounts exist, OSCAR port reachable on the LAN IP.
# Run on the server machine after run-server.sh is up.
. "$(dirname "$0")/../common.sh"
here="$(dirname "$0")"
echo "== API version"; curl -fsS "$API_URL/version"; echo
"$here/create-account.sh" 100001 labpass1
"$here/create-account.sh" 100002 labpass2
echo "== Users"; curl -fsS "$API_URL/user"; echo
echo "== OSCAR port $SERVER_IP:5190"
if nc -z -w2 "$SERVER_IP" 5190; then echo "open"; else echo "NOT reachable" >&2; exit 1; fi
echo "== Active sessions"; curl -fsS "$API_URL/session"; echo
