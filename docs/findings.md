# Findings

Every protocol finding: date, evidence, source. Unverified items are **VERIFY**.

## Source-reading findings (2026-09-20, no hardware yet)

| Finding | Evidence | Status |
|---|---|---|
| Latest Open OSCAR Server release is v0.24.0 with prebuilt macOS/Linux/Windows assets and a checksum file | GitHub API, `releases/latest` | Confirmed (docs only) |
| Upstream ICQ guide names ICQ 5.1 explicitly under "ICQ 2003, 4 & 5" | `docs/CLIENT_ICQ.md` | Documented upstream; **VERIFY** on real hardware |
| ICQ 5.1 has a Setup dialog for server host/port, so login DNS redirection may be unnecessary | `docs/CLIENT_ICQ.md` | **VERIFY** |
| Contact lists of ICQ 2003/4/5 live on the server | `docs/CLIENT_ICQ.md` | Relevant to M1 buddy-list seeding |
| Management API offers `POST /user`, `GET /session`, `POST /instant-message` (sender need not exist) | `api.yml` | Confirmed (docs only). The IM endpoint may be a shortcut for M1 tests |
| Server config keys: `OSCAR_LISTENERS`, `OSCAR_ADVERTISED_LISTENERS_PLAIN`, `TOC_LISTENERS` (9898), `API_LISTENER` (127.0.0.1:8080), `DB_PATH`, `DISABLE_AUTH` | `config/settings.env` | Confirmed (docs only) |
| Server also has TOC on :9898, which matches the M1 plan for a TOC2 spike client | `config/settings.env` | Confirmed (docs only) |

## M0 VERIFY items

| # | Item | Result | Evidence |
|---|---|---|---|
| V1 | ICQ 5.1 (not just "ICQ 5") logs in and messages | PASS (2026-09-20, reported by author; OS/build details to add) | author report |
| V2 | Presence flows between two clients | PASS (2026-09-20, reported by author) | author report |
| V3 | Offline messages flow | PASS (2026-09-20, author report) | author report |
| V4 | Typing indicators flow | PASS (2026-09-20, author report; direction(s) not recorded) | author report |
| V5 | Which dead endpoints slow startup or blank panes | PARTIAL: cold start is fast; only ad panes and Xtraz are blank. Hostname to pane mapping not yet established | author report |
| V6 | `run-server.sh` env-var config is honored by the binary | FAIL/fixed 2026-09-20: binary warns "settings.env not found" (default `-config settings.env` in CWD); DB_PATH from env was honored, but the shipped settings.env advertises 127.0.0.1. `run-server.sh` now passes `-config infra/server/run/settings.env`, as upstream `run_dev.sh` does | author report; `-help`, upstream scripts/run_dev.sh |

## Hostnames contacted by ICQ 5.1 at startup

_Source: dnsmasq query log, client 192.168.0.11, 2026-09-20. Partial: log only, no pcap yet. These names resolve to live, public servers (Mail.ru-operated ICQ), so with no stub the client is talking to the real internet._

| Hostname | Port/proto | Purpose | Action (redirect/stub/leave) | Effect |
|---|---|---|---|---|
| xtraz.icq.com | A (likely 80/443) | Xtraz / status panes; CNAME to www.ovip.icq.com = 95.163.61.100 | undecided | **VERIFY** |
| welcome.icq.com | A | likely start/welcome web pane | undecided | **VERIFY** |
| icq.com, c.icq.com | A | unknown, maybe web pane/content | undecided | **VERIFY** |
| ar.atwola.com | A | AOL ad network (Atwola): probably the ad pane | undecided | **VERIFY** |
| ars.oscar.aol.com | A | AOL "ARS" service, likely ad/pane redirector | undecided | **VERIFY** |
| cb.icq.com | A, AAAA | unknown; CNAME chain srp.icq.com -> srpvip.evip.icq.com -> srp.ovip.icq.com = 178.237.20.30 | undecided | **VERIFY** |

## Stub list

_Empty. Mirrors `infra/dnsmasq/redirects.conf`._

## Resolved (2026-09-20): ICQ 5.1 stuck at "connecting..." on XP (192.168.0.11)

Author reports it now works. **Root cause (author report): Windows XP kept resetting the DNS server setting on the adapter** (not seen on Windows 10). Symptom: DNS looked right at times but the client did not reliably use the gateway. Lesson: re-check `ipconfig /all` right before each test, and look for every place XP stores DNS (adapter properties, any alternate/DHCP config, third-party network tools). Author also reports ICQ 5.1 connects from Windows 10 to the macOS server instance (user-reported, not independently verified).


- Server up, listening on *:5190, advertised 192.168.0.31:5190, reachable from the Mac itself. macOS app firewall off.
- XP resolves via dnsmasq (queries logged). No connection from 192.168.0.11 appears in server debug output.
- Only DNS names seen so far: xtraz.icq.com, cb.icq.com. No login hostname was queried, consistent with the Setup dialog host being used.
- Stubbing xtraz.icq.com and cb.icq.com changed nothing (server was not running at that time, so inconclusive).
- Next evidence needed: `sudo tcpdump -ni en0 host 192.168.0.11 and not port 53` on the Mac during a login attempt, plus telnet from XP to 192.168.0.31:5190.

## M0 closure (2026-09-20)

Author decision: the full startup capture is **deferred to the end of the plan** (PLAN.md, M9). M0 closes with these known gaps:
- Hostname-to-pane mapping is unknown. Observed names are listed above, none are stubbed yet.
- Cold start is fast without stubs. Ad panes and Xtraz panes are blank (the client cannot show them, or the real servers no longer serve them).
- Presence states beyond online/offline (Away, Occupied, DND, Invisible) were not explicitly recorded.

# M1: Identity and attachment spike

Status: server-side results done (2026-09-20). ICQ 5.1 client-side results pending (see "M1 pending").
Tools: `tools/toc2_spike.py` (TOC2 client), `tools/seed_buddy.py` (feedbag seeding).

## Protocol facts (server source + spike runs)

| Finding | Evidence |
|---|---|
| TOC2 works against the unmodified server on port 9898: login (`toc2_signon`, roasted password), `toc2_send_im`, `toc2_client_event`, `toc_add_buddy`, `toc_set_away` are all supported | `server/toc/cmd_client.go`; spike run: `SIGN_ON:TOC2.0`, `NICK`, `CONFIG2` |
| IM delivered from TOC account `vbuddy1` (AIM-style) to UIN account `100003` as `IM_IN2:vbuddy1:F:F:<text>` | spike, both directions of session tested on one side |
| Typing events pass through: `CLIENT_EVENT2:vbuddy1:2` (typing) and `:0` (none) | spike |
| The server marks accounts `users.isICQ` (1 for numeric UINs, 0 for `vbuddy1`); AIM-style names are valid server accounts | `select identScreenName,isICQ from users` |
| TOC2 IM errors are opaque: `ERROR:903` = rate limited, `ERROR:983` = login rate limited. There is no "user offline" error | spike, `cmd_client.go` comment |

## Rate limits (task 4), measured

| Limit | Value | Evidence |
|---|---|---|
| IM send, per account (OSCAR rate class 3) | window 20, limited below 4000 ms, disconnect below 3000 ms, max 6000. Formula: `level' = (level*19 + dt_ms)/20`, starting at 6000 | `wire/rate_limit.go` |
| Observed | at 20/250/500/1000 ms spacing the first throttle came after 8/8/9/10 messages; `ERROR:903` follows and the server **closes the connection** after about 5 errors | spike burst runs, matches the model (7/8/8/9) |
| Sustained safe rate | one message per **4 s or slower**. Faster only works for a budget of about 8-21 messages (2 s: 13, 3 s: 21), then throttle, then disconnect. Recovery needs idle time | model + runs |
| Login, per source IP | token bucket: burst 10, refill 1 per minute. Applies to OSCAR :5190 and TOC :9898 | `cmd/server/factory.go`; spike: 4 of 10 rapid logins got `ERROR:983` |

Consequences for the bridge (feeds gate G1/G2):
- Each virtual contact is its own account, so the IM limit is **per contact**. A chatty Telegram contact or an offline backlog delivered as fast as possible would get throttled and disconnected. The bridge needs a per-contact send queue paced to >= 4 s once past a small burst budget.
- Approach (a) logs in once per contact from one IP: 10 contacts at startup fine, then 1 login/minute. A restart of the bridge with N > 10 contacts takes N-10 minutes. Mitigations to test: staggered logins, keep-alive/reconnect discipline, or several source IPs (on Linux the whole 127.0.0.0/8 is bindable; macOS needs `ifconfig lo0 alias`). Note that limits are enforced per remote IP as the server sees it.
- Approach (b) (in-process provider) would avoid both limits, at the cost of maintaining a fork.

## Buddy-list seeding (task 3), server side

- The ICQ user's contact list is the `feedbag` table in `oscar.sqlite`. Decoded format is documented in `tools/seed_buddy.py`: `attributes` = uint16 length + big-endian TLVs; group order TLV `0xC8`, buddy alias TLV `0x131`.
- ICQ 5.1's own rows also carry TLVs `0x137`, `0x144`, `0x145` (buddy added by client). `seed_buddy.py` writes only the alias.
- Encoder round-trips every existing row byte-for-byte; applied only to a copy of the DB so far.
- `contactPreauth(ownerScreenName, authorizedScreenName)` is filled by the server when authorization is granted. `users.icq_permissions_authRequired` defaults to true. Presence of a virtual buddy may need one of these. **VERIFY**

## M1 client-side results (ICQ 5.1 on real hardware)

| # | Question | Result |
|---|---|---|
| I1 | Does ICQ 5.1 show and let you reply to an IM from non-numeric `vbuddy1`? | PASS (2026-09-21, author report) |
| I2 | Can ICQ 5.1 add `vbuddy1` (non-numeric) through its Add Contact dialog? | PASS (2026-09-21, author report) |
| I3 | Does a feedbag row seeded with `seed_buddy.py` appear in ICQ 5.1 after login, and does it show presence? | PASS (2026-09-21, author report): seeded contact appears in ICQ 5.1 and shows presence |
| I4 | Does the virtual buddy need `--preauth` (or authRequired=false) to show presence, or does ICQ ask for authorization? | PASS (2026-09-21, author report): no `--preauth` needed, authorization did not matter |
| I5 | Does ICQ 5.1 show typing from a virtual buddy, and does the spike see typing from ICQ (`CLIENT_EVENT2`)? | PASS (2026-09-21, author report): typing indicators work |
| I6 | Does away status (`toc_set_away`) show in ICQ 5.1? | PASS (2026-09-21, author report): away status works |

Notes on I1-I6: `--preauth` was not needed, so `contactPreauth` is not part of the seeding recipe (server-side writes needed: one `feedbag` buddy row plus the group's `0xC8` order TLV). Details of I1-I6 (which OS, which exact account names) were not recorded.

## Gate G1 (2026-09-21)

Status: **awaiting author confirmation.** Recommendation: (a) external sessions, unmodified server. Rationale and open risks are in the chat transcript; the essentials:
- Pace limit (one message per 4 s sustained, budget of about 8 messages faster) is acceptable for the expected traffic pattern (occasional bursts of 3-4). Needs a per-contact paced send queue in the bridge.
- Login limit (burst 10, then 1 per minute per source IP) only bites on bridge restarts with more than 10 contacts. Stagger logins.
- Seeding works through direct SQLite writes to `feedbag`, so it couples the bridge to the server's schema. Pin the server version.
