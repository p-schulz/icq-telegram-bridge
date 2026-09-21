# Manual test checklist

Run on real XP/Vista. Record date, OS, ICQ build, and result per line.

## M0 lab baseline

| # | Step | Expected | Result (date/OS) |
|---|---|---|---|
| 1 | Set DNS to gateway; `nslookup example.com` | answer, query appears in dnsmasq log | |
| 2 | ICQ 5.1 Setup: host/port, log in as 100001 | signed in, no error dialog | |
| 3 | Second client logs in as 100002; add each other | each sees the other online | |
| 4 | Send message 100001 → 100002 and back | delivered both ways, text intact | |
| 5 | Typing in one client | typing indicator on the other (note if absent) | |
| 6 | Set status Away / Occupied / DND / Invisible on 100002 | 100001 sees the change | |
| 7 | Log out 100002; from 100001 (or `send-test-im.sh`) send message; log 100002 in | message delivered at login | |
| 8 | Cold-start ICQ 5.1 with gateway stubs | note time to usable UI; blank panes? | |
| 9 | Reboot client; relogin | contact list restored from server | |
