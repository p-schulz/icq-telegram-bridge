# shellcheck shell=bash
# Shared helpers for scripts/. Source, do not execute.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Number of parallel compile jobs: TDLib needs roughly 3 GB per job.
default_jobs() {
  local cpu mem_gb jobs
  if [[ "$OS" == "Darwin" ]]; then
    cpu="$(sysctl -n hw.ncpu)"; mem_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  else
    cpu="$(nproc)"; mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1048576 ))
  fi
  jobs=$(( mem_gb / 3 )); (( jobs < 1 )) && jobs=1; (( jobs > cpu )) && jobs=$cpu
  echo "$jobs"
}
