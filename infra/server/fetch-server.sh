#!/usr/bin/env bash
# Download Open OSCAR Server from the official GitHub release and verify its checksum.
# Installs to infra/server/bin/. Safe to re-run.
. "$(dirname "$0")/../common.sh"

os="$(uname -s)"; arch="$(uname -m)"
case "$os/$arch" in
  Darwin/arm64)  asset="open_oscar_server.${OSCAR_VERSION}.macos.apple_silicon.zip" ;;
  Darwin/x86_64) asset="open_oscar_server.${OSCAR_VERSION}.macos.intel_x86_64.zip" ;;
  Linux/x86_64)  asset="open_oscar_server.${OSCAR_VERSION}.linux.x86_64.tar.gz" ;;
  Linux/aarch64|Linux/armv7l) asset="open_oscar_server.${OSCAR_VERSION}.linux.arm64_arm7_raspberry_pi.tar.gz" ;;
  *) echo "No release asset known for $os/$arch (see PLAN.md M0; build from source instead)." >&2; exit 1 ;;
esac

base="https://github.com/mk6i/open-oscar-server/releases/download/v${OSCAR_VERSION}"
dest="$INFRA_DIR/server/bin"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$dest"

echo "Fetching $asset"
curl -fsSL -o "$tmp/$asset" "$base/$asset"
curl -fsSL -o "$tmp/checksums.txt" "$base/open-oscar-server_${OSCAR_VERSION}_checksums.txt"

expected="$(grep -F "$asset" "$tmp/checksums.txt" | awk '{print $1}')"
[[ -n "$expected" ]] || { echo "Asset not listed in checksums.txt" >&2; exit 1; }
if command -v sha256sum >/dev/null; then actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
else actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"; fi
[[ "$expected" == "$actual" ]] || { echo "Checksum mismatch: expected $expected, got $actual" >&2; exit 1; }
echo "Checksum OK"

case "$asset" in
  *.zip)    unzip -qo "$tmp/$asset" -d "$dest" ;;
  *.tar.gz) tar -xzf "$tmp/$asset" -C "$dest" ;;
esac
echo "Installed to $dest:"; ls -la "$dest"
echo "Note: on macOS you may need: xattr -dr com.apple.quarantine $dest"
