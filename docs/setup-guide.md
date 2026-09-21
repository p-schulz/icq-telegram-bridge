# Lab setup guide

Status: M0 lab verified on macOS (server) with XP and Windows 10 clients. The Ubuntu one-script
install below is **written but not yet run on a real Ubuntu server** (see "Verifying the Ubuntu install").

## Quick start on Ubuntu (server and gateway on one machine)

```bash
git clone <your-repo-url> nostalgia-sim && cd nostalgia-sim
./scripts/install.sh
```

It installs the packages, writes `infra/lab.env` from the detected LAN IP, downloads and
verifies Open OSCAR Server, installs systemd services (`nostalgia-oscar`, and dnsmasq if not
`--no-dns`), opens the firewall ports if `ufw` is active, builds TDLib from source (15-40 min),
builds the bridge, and prints the next steps. Re-running is safe. Useful options:
`--no-dns`, `--skip-tdlib`, `--server-ip IP`, `--iface NAME`, `--jobs N`.

Afterwards:

```bash
sudo systemctl status nostalgia-oscar          # logs: journalctl -u nostalgia-oscar -f
infra/server/create-account.sh 100001 labpass1
```

Keep the server's IP fixed (DHCP reservation or netplan). A changed address silently breaks
DNS and the ICQ Setup host (this happened once in the lab).

### Verifying the Ubuntu install

After `./scripts/install.sh` finishes, check (and record results in `docs/findings.md`):

1. `systemctl is-active nostalgia-oscar dnsmasq` prints `active` twice; `sudo ss -ltnp | grep -E ':(5190|9898|8080)'`
   shows the server (8080 on 127.0.0.1 only).
2. From another machine: `nc -z <server-ip> 5190` succeeds and `nslookup example.com <server-ip>` answers.
3. `infra/server/smoke-test.sh` passes.
4. ICQ 5.1 on the XP box logs in (Setup host = server IP) and the query appears in `/var/log/nostalgia-dnsmasq.log`.
5. Reboot the server; both services come back without manual steps (this is the M6 goal, checked early).
6. Re-run `./scripts/install.sh --skip-tdlib`; it must finish without errors and change nothing important.
7. `ls build/tg-probe` exists after the TDLib build (typically 30+ min on a small VPS; needs about 3 GB RAM per compile job, so pass `--jobs 1` or `2` on small machines).

## Telegram (M2)

1. Create API credentials at https://my.telegram.org (API development tools) with a
   **secondary** Telegram account.
2. Put them in `~/.config/nostalgia-sim/secrets.env` (the installer creates a 600-mode template):
   ```
   TG_API_ID=123456
   TG_API_HASH=<32 hex characters from my.telegram.org>
   ```
   The TDLib session lives in `~/.local/share/nostalgia-sim/tdlib` (override with `TG_DATA_DIR`).
   Both stay outside the repo.
3. Build and run:
   ```bash
   scripts/build-tdlib.sh      # once (macOS: brew install gperf first)
   scripts/build-bridge.sh
   scripts/tg-probe.sh         # first run asks for phone number, code, and 2FA password
   ```
   Probe commands: `me`, `contacts`, `chats [N]`, `send <chat_id> <text>`, `typing <chat_id> [off]`,
   `stats`, `quit`, `logout`. Incoming messages, presence and typing print as they arrive.
4. Soak test: `scripts/tg-probe.sh --run-for-minutes 60`. During the run, drop the network
   for a minute (e.g. disable Wi-Fi) and check the log shows `CONNECTION` going to
   waiting/connecting and back to ready.

## Manual lab setup (macOS, or step by step)

Reproduces the ICQ 5.1 lab from scratch. Steps marked *(untested)* have not been run.

## Topology

```
XP/Vista box(es)  --DNS-->  gateway host (dnsmasq)
        |                          
        +--- OSCAR :5190 --->  server host (Open OSCAR Server)
```

The gateway and server can be the same machine (a Mac or a small Linux box). Both need a
static LAN IP. Examples below use `192.168.0.248`; put yours in `infra/lab.env`.

## 1. Configure

```bash
cp infra/lab.env.example infra/lab.env   # then edit SERVER_IP, GATEWAY_IP, LAN_IFACE
```

## 2. Server (server host)

```bash
infra/server/fetch-server.sh      # downloads v0.24.0, verifies SHA-256 (untested)
infra/server/run-server.sh        # foreground; state in infra/server/run/
```

In a second shell:

```bash
infra/server/smoke-test.sh        # API up, creates 100001 / 100002, checks port 5190
```

Facts taken from the upstream docs (`docs/CLIENT_ICQ.md`, `api.yml`):
- ICQ 5.1 is listed by name for "ICQ 2003, 4 & 5" and the install link points at 5.1.
- Clients store their contact list **on the server** (relevant to M1 buddy-list seeding).
- These clients "do not run reliably under WINE": use native Windows.
- The client's **Setup** button on the login screen takes host and port. Use the values from
  `OSCAR_ADVERTISED_LISTENERS_PLAIN` (`run-server.sh` writes `SERVER_IP:5190`).
- Management API: `POST /user {screen_name,password}`, `GET /session`,
  `POST /instant-message {from,to,text}` (sender need not exist).

**VERIFY (script assumption):** `run-server.sh` sources `settings.env` and starts the binary with those
variables exported, instead of passing `-config`. If the server ignores them, run the binary
with `-config infra/server/run/settings.env` and record it in findings.

Firewall: allow inbound TCP 5190 on the server host (macOS asks on first run).

## 3. Gateway (gateway host)

```bash
brew install dnsmasq        # or: apt install dnsmasq
sudo infra/dnsmasq/run-dnsmasq.sh   # renders config, runs in foreground, logs every query
```

On macOS with a running system resolver, port 53 may be busy; check with
`sudo lsof -i :53` and record the outcome.

The query log is `infra/dnsmasq/generated/queries.log`. Stubs and redirects go in
`infra/dnsmasq/redirects.conf`.

## 4. Client (XP/Vista box)

1. Set the network adapter's DNS server to `GATEWAY_IP` (manual, no DHCP change needed).
2. Check: `nslookup example.com` returns an answer, and a line appears in `queries.log`.
3. Install ICQ 5.1 (own copy/license). Launch, click **Setup** on the login screen, enter
   `SERVER_IP` and port `5190`.
4. Log in as `100001` / `labpass1`.
5. On a second machine (or Pidgin with ICQ protocol pointed at the server), log in as `100002`.

## 5. Capture the startup (M0 task 4)

On the gateway, before launching ICQ on the client:

```bash
sudo infra/capture/capture-startup.sh <client-ip> icq51-startup
```

Launch ICQ 5.1, log in, wait until the UI settles, Ctrl-C. Then:

```bash
tools/pcap_hosts.py docs/captures/icq51-startup-*.pcap <client-ip>   # needs tshark
```

Copy the hostnames and observations into `docs/findings.md`. Uncomment/add stub lines in
`redirects.conf`, re-run, and repeat the capture to confirm start-up got faster or panes stopped blanking.

## Troubleshooting

- tcpdump ends with "0 packets captured, N received by filter" (macOS): the capture buffer was
  never drained. `capture-startup.sh` uses `--immediate-mode` for this. The final line must show
  a non-zero "packets captured".
- ICQ shows "connecting..." on XP although DNS looked right: Windows XP may reset the adapter's
  DNS server. Re-check `ipconfig /all` right before each test (see findings.md).
- The server warns "settings.env not found": run it through `infra/server/run-server.sh`,
  which passes `-config`.
- The Mac's IP changes (DHCP): reserve a fixed address in the router, update `infra/lab.env`,
  restart the server and dnsmasq, and change the host in ICQ's Setup dialog.
- Login times out: host/port in Setup dialog; server port reachable from the client
  (`telnet SERVER_IP 5190` on Vista, or PuTTY raw on XP).
- `409` from the API: account already exists, harmless.
- No DNS lines in the log: client is not using the gateway; check adapter settings and any
  router that forces DNS.
