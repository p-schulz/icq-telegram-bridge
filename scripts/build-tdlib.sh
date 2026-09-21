#!/usr/bin/env bash
# Build TDLib (official Telegram library) from source at the commit pinned in scripts/tdlib.commit.
# Result: third_party/td-install (headers, libs, CMake config). Safe to re-run; skips if up to date.
#   scripts/build-tdlib.sh [--jobs N] [--force]
# Prerequisites: git, cmake, a C++17 compiler, gperf, zlib and OpenSSL dev files.
#   macOS:  brew install gperf         Ubuntu: done by scripts/install.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

jobs="$(default_jobs)"; force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) jobs="$2"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "unknown argument $1" ;;
  esac
done

commit="$(tr -d '[:space:]' < "$REPO_ROOT/scripts/tdlib.commit")"
src="$REPO_ROOT/third_party/td-src"
build="$REPO_ROOT/third_party/td-build"
prefix="$REPO_ROOT/third_party/td-install"
stamp="$prefix/.built-commit"

for tool in git cmake gperf; do have "$tool" || die "$tool not found (macOS: brew install $tool; Ubuntu: apt install $tool)"; done

if [[ $force -eq 0 && -f "$stamp" && "$(cat "$stamp")" == "$commit" ]]; then
  log "TDLib $commit already built in $prefix"; exit 0
fi

mkdir -p "$REPO_ROOT/third_party"
if [[ ! -d "$src/.git" ]]; then
  log "Cloning tdlib/td"
  git clone --quiet https://github.com/tdlib/td.git "$src"
fi
log "Checking out $commit"
git -C "$src" fetch --quiet origin
git -C "$src" checkout --quiet "$commit"

cmake_args=(-DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$prefix")
if [[ "$OS" == "Darwin" ]]; then
  have brew || die "Homebrew not found"
  cmake_args+=("-DOPENSSL_ROOT_DIR=$(brew --prefix openssl@3)")
fi

log "Configuring (build dir $build)"
cmake -S "$src" -B "$build" "${cmake_args[@]}"
log "Building with $jobs jobs. This takes a while (15-40 min)."
cmake --build "$build" --target install --parallel "$jobs"
echo "$commit" > "$stamp"
log "TDLib installed to $prefix"
