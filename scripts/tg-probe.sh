#!/usr/bin/env bash
# Run tg-probe with credentials from ~/.config/nostalgia-sim/secrets.env (outside the repo).
#   scripts/tg-probe.sh [--run-for-minutes N] [--heartbeat-seconds N]
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
secrets="${TG_SECRETS_FILE:-$HOME/.config/nostalgia-sim/secrets.env}"
[[ -f "$secrets" ]] || die "missing $secrets (copy the template from scripts/install.sh or see docs/setup-guide.md)"
set -a; . "$secrets"; set +a
[[ -x "$REPO_ROOT/build/tg-probe" ]] || die "build/tg-probe not found: run scripts/build-bridge.sh"
exec "$REPO_ROOT/build/tg-probe" "$@"
