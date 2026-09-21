#!/usr/bin/env bash
# Configure and build the bridge into build/. Needs TDLib: run scripts/build-tdlib.sh first.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ -f "$REPO_ROOT/third_party/td-install/.built-commit" ]] || die "TDLib not built: run scripts/build-tdlib.sh"
cmake -S "$REPO_ROOT/bridge" -B "$REPO_ROOT/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$REPO_ROOT/build" --parallel "$(default_jobs)" "$@"
