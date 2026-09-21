#!/usr/bin/env bash
# One-shot setup of the Nostalgia Simulator on Ubuntu 22.04/24.04 (also works on Debian 12).
#
#   git clone <repo-url> nostalgia-sim && cd nostalgia-sim && ./scripts/install.sh
#
# Run as a normal user with sudo rights (not as root). Idempotent: safe to re-run.
# Installs packages, downloads Open OSCAR Server (checksum verified), builds TDLib from source
# and the bridge, writes infra/lab.env, installs systemd services and (optionally) dnsmasq.
#
# Options:
#   --server-ip IP    LAN IP that clients use to reach this machine (default: auto-detected)
#   --iface NAME      LAN interface (default: auto-detected)
#   --no-dns          do not set up dnsmasq (ICQ 5.1 works without it; DNS only stubs dead endpoints)
#   --skip-tdlib      skip the long TDLib build (M2 and later need it)
#   --skip-bridge     skip building the bridge
#   --jobs N          parallel compile jobs for TDLib
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

server_ip=""; iface=""; want_dns=1; want_tdlib=1; want_bridge=1; jobs_arg=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-ip) server_ip="$2"; shift 2 ;;
    --iface) iface="$2"; shift 2 ;;
    --no-dns) want_dns=0; shift ;;
    --skip-tdlib) want_tdlib=0; shift ;;
    --skip-bridge) want_bridge=0; shift ;;
    --jobs) jobs_arg=(--jobs "$2"); shift 2 ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done

[[ "$OS" == "Linux" ]] || die "install.sh targets Ubuntu/Debian. On macOS see docs/setup-guide.md."
[[ $EUID -ne 0 ]] || die "run as a normal user with sudo, not as root (services run as your user)"
have apt-get || die "apt-get not found: Ubuntu/Debian only"
have sudo || die "sudo is required"
sudo -v

SERVICE_USER="$(id -un)"

# ---------------------------------------------------------------- packages
log "Installing packages"
pkgs=(build-essential cmake git gperf zlib1g-dev libssl-dev libreadline-dev
      libasio-dev libspdlog-dev libyaml-cpp-dev libsqlite3-dev sqlite3
      curl unzip ca-certificates netcat-openbsd tcpdump python3 iproute2)
(( want_dns )) && pkgs+=(dnsmasq)
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"

# ---------------------------------------------------------------- network detection
route="$(ip -4 route get 1.1.1.1 2>/dev/null | head -1 || true)"
detected_iface="$(sed -n 's/.* dev \([^ ]*\).*/\1/p' <<<"$route")"
detected_ip="$(sed -n 's/.* src \([^ ]*\).*/\1/p' <<<"$route")"
server_ip="${server_ip:-$detected_ip}"; iface="${iface:-$detected_iface}"
[[ -n "$server_ip" && -n "$iface" ]] || die "could not detect LAN IP/interface; pass --server-ip and --iface"

lab_env="$REPO_ROOT/infra/lab.env"
if [[ -f "$lab_env" ]]; then
  log "Keeping existing infra/lab.env"
  # shellcheck disable=SC1090
  old_ip="$(. "$lab_env"; echo "${SERVER_IP:-}")"
  [[ "$old_ip" == "$server_ip" ]] || warn "lab.env SERVER_IP=$old_ip but this machine now has $server_ip. Edit lab.env if the address changed."
else
  log "Writing infra/lab.env (SERVER_IP=$server_ip, interface $iface)"
  sed -e "s|^SERVER_IP=.*|SERVER_IP=$server_ip|" \
      -e "s|^GATEWAY_IP=.*|GATEWAY_IP=$server_ip|" \
      -e "s|^LAN_IFACE=.*|LAN_IFACE=$iface|" \
      "$REPO_ROOT/infra/lab.env.example" > "$lab_env"
fi
warn "This IP must stay fixed: set a DHCP reservation on the router or a static address (netplan). ICQ clients and the server config depend on it."

# ---------------------------------------------------------------- Open OSCAR Server
log "Fetching Open OSCAR Server"
"$REPO_ROOT/infra/server/fetch-server.sh"

unit_dir=/etc/systemd/system
log "Installing systemd service nostalgia-oscar"
sudo tee "$unit_dir/nostalgia-oscar.service" >/dev/null <<UNIT
[Unit]
Description=Open OSCAR Server (Nostalgia Simulator)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$REPO_ROOT/infra/server
ExecStart=$REPO_ROOT/infra/server/run-server.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

# ---------------------------------------------------------------- dnsmasq (optional)
if (( want_dns )); then
  log "Configuring dnsmasq"
  sudo mkdir -p /etc/nostalgia
  DNSMASQ_LOG=/var/log/nostalgia-dnsmasq.log "$REPO_ROOT/infra/dnsmasq/run-dnsmasq.sh" --render
  gen="$REPO_ROOT/infra/dnsmasq/generated"
  sudo install -m 644 "$gen/redirects.conf" /etc/nostalgia/redirects.conf
  # dnsmasq reloads as an unprivileged user, so keep everything it reads outside the home directory.
  sed "s|^conf-file=.*|conf-file=/etc/nostalgia/redirects.conf|" "$gen/dnsmasq.conf" | sudo tee /etc/dnsmasq.d/nostalgia.conf >/dev/null
  sudo dnsmasq --test -C /etc/dnsmasq.d/nostalgia.conf
  sudo systemctl enable dnsmasq >/dev/null 2>&1
  sudo systemctl restart dnsmasq
else
  warn "Skipping dnsmasq (--no-dns). Point ICQ's Setup dialog at $server_ip:5190."
fi

# ---------------------------------------------------------------- firewall
if have ufw && sudo ufw status | grep -q "Status: active"; then
  log "Opening firewall ports (ufw): 5190/tcp$( (( want_dns )) && echo ', 53/udp+tcp')"
  sudo ufw allow 5190/tcp >/dev/null
  (( want_dns )) && { sudo ufw allow 53/udp >/dev/null; sudo ufw allow 53/tcp >/dev/null; }
fi

log "Starting nostalgia-oscar"
sudo systemctl daemon-reload
sudo systemctl enable nostalgia-oscar >/dev/null 2>&1
sudo systemctl restart nostalgia-oscar

# ---------------------------------------------------------------- Telegram secrets template
secrets_dir="$HOME/.config/nostalgia-sim"
if [[ ! -f "$secrets_dir/secrets.env" ]]; then
  mkdir -p "$secrets_dir"; chmod 700 "$secrets_dir"
  cat > "$secrets_dir/secrets.env" <<'ENVF'
# Telegram API credentials from https://my.telegram.org (use a secondary account until M4 passes).
# Keep this file outside the repo. Never commit it.
TG_API_ID=
TG_API_HASH=
# Optional TDLib database encryption key:
# TG_DB_KEY=
ENVF
  chmod 600 "$secrets_dir/secrets.env"
  log "Created $secrets_dir/secrets.env (fill in TG_API_ID and TG_API_HASH)"
fi

# ---------------------------------------------------------------- TDLib and bridge
if (( want_tdlib )); then
  "$REPO_ROOT/scripts/build-tdlib.sh" "${jobs_arg[@]}"
else
  warn "Skipped TDLib build (--skip-tdlib). Run scripts/build-tdlib.sh before M2."
fi
if (( want_bridge )) && [[ -f "$REPO_ROOT/third_party/td-install/.built-commit" ]]; then
  log "Building the bridge"
  cmake -S "$REPO_ROOT/bridge" -B "$REPO_ROOT/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$REPO_ROOT/build" --parallel "$(default_jobs)"
fi

# ---------------------------------------------------------------- checks
log "Checking"
sleep 3
ok=1
systemctl is-active --quiet nostalgia-oscar && echo "  nostalgia-oscar: active" || { echo "  nostalgia-oscar: NOT active (journalctl -u nostalgia-oscar)"; ok=0; }
(( want_dns )) && { systemctl is-active --quiet dnsmasq && echo "  dnsmasq: active" || { echo "  dnsmasq: NOT active (journalctl -u dnsmasq)"; ok=0; }; }
nc -z -w2 "$server_ip" 5190 && echo "  OSCAR $server_ip:5190: reachable" || { echo "  OSCAR $server_ip:5190: NOT reachable"; ok=0; }
"$REPO_ROOT/infra/server/create-account.sh" 100001 labpass1 >/dev/null 2>&1 && echo "  lab account 100001: ok" || true

cat <<DONE

Setup finished$( ((ok)) || echo ' WITH PROBLEMS (see above)').
Next:
  1. Create lab accounts:   infra/server/create-account.sh <uin> <password>
  2. ICQ 5.1 on the XP/Vista box: Setup -> host $server_ip, port 5190. If dnsmasq is on, set the box's DNS server to $server_ip.
  3. Telegram (M2): put TG_API_ID/TG_API_HASH in $secrets_dir/secrets.env, then run scripts/tg-probe.sh
Service control:  sudo systemctl status|restart nostalgia-oscar     Logs: journalctl -u nostalgia-oscar -f
DONE
