#!/usr/bin/env bash
# Usage: send-test-im.sh <from> <to> <text>
# Sends an IM through the Management API (POST /instant-message). Useful to test delivery
# to an ICQ client, including offline queueing, without a second client.
. "$(dirname "$0")/../common.sh"
[[ $# -eq 3 ]] || { echo "Usage: $0 <from> <to> <text>" >&2; exit 2; }
curl -fsS -X POST "$API_URL/instant-message" -H 'Content-Type: application/json' \
  -d "$(printf '{"from":"%s","to":"%s","text":"%s"}' "$1" "$2" "$3")" && echo "sent"
