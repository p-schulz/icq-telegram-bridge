#!/usr/bin/env bash
# Usage: create-account.sh <UIN-or-screenname> <password>
# Creates an account through the Management API (POST /user).
. "$(dirname "$0")/../common.sh"
[[ $# -eq 2 ]] || { echo "Usage: $0 <uin> <password>" >&2; exit 2; }
code="$(curl -s -o /dev/stderr -w '%{http_code}' -X POST "$API_URL/user" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"screen_name":"%s","password":"%s"}' "$1" "$2")")"
case "$code" in
  201) echo "Created $1" ;;
  409) echo "Already exists: $1" ;;
  *)   echo "Failed: HTTP $code" >&2; exit 1 ;;
esac
