# shellcheck shell=bash
# Shared helpers. Source from other scripts: . "$(dirname "$0")/../common.sh"
set -euo pipefail
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$INFRA_DIR/.." && pwd)"
if [[ ! -f "$INFRA_DIR/lab.env" ]]; then
  echo "Missing $INFRA_DIR/lab.env. Copy lab.env.example and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$INFRA_DIR/lab.env"
