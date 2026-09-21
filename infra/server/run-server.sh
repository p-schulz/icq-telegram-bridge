#!/usr/bin/env bash
# Generate settings.env for the lab and run Open OSCAR Server in the foreground.
# State (SQLite DB) lives in infra/server/run/.
. "$(dirname "$0")/../common.sh"

bin="$(find "$INFRA_DIR/server/bin" -type f -name 'open_oscar_server*' ! -name '*.zip' ! -name '*.tar.gz' | head -1)"
[[ -x "$bin" ]] || { echo "Server binary not found or not executable. Run fetch-server.sh first." >&2; exit 1; }

run_dir="$INFRA_DIR/server/run"; mkdir -p "$run_dir"
cat > "$run_dir/settings.env" <<CFG
export OSCAR_LISTENERS=LAN://0.0.0.0:5190
export OSCAR_ADVERTISED_LISTENERS_PLAIN=LAN://${SERVER_IP}:5190
export TOC_LISTENERS=0.0.0.0:9898
export API_LISTENER=127.0.0.1:8080
export DB_PATH=${run_dir}/oscar.sqlite
export DISABLE_AUTH=${DISABLE_AUTH}
export LOG_LEVEL=debug
export ICQ_LEGACY_ENABLED=false
CFG
# The binary loads its config via -config (default: ./settings.env in the CWD).
# Upstream's run_dev.sh does the same.
echo "Advertised: LAN://${SERVER_IP}:5190  DB: $run_dir/oscar.sqlite  DISABLE_AUTH=$DISABLE_AUTH"
exec "$bin" -config "$run_dir/settings.env"
