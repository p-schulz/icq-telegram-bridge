#!/usr/bin/env python3
"""M1 throwaway: add a buddy to an ICQ user's server-side contact list (feedbag) via SQLite.

Answers "can virtual contacts be pre-seeded instead of added by hand in ICQ 5.1?".
Format (decoded from rows written by ICQ 5.1, 2026-09-20):
  feedbag.attributes = uint16 total length + big-endian TLVs (tag u16, len u16, value)
  root group   : groupID 0, itemID 0, classID 1, TLV 0xC8 = list of group ids
  group        : groupID G, itemID 0, classID 1, TLV 0xC8 = list of buddy item ids (display order)
  buddy        : groupID G, itemID I, classID 0, name = buddy screen name, TLV 0x131 = alias

Default is a dry run. The user must be logged out in ICQ while applying.
Usage:
  tools/seed_buddy.py DB OWNER BUDDY [--alias NAME] [--apply] [--preauth]
  --preauth also inserts contactPreauth(owner=BUDDY, authorized=OWNER); VERIFY what this table means.
"""
import argparse
import random
import sqlite3
import struct
import sys
import time

CLASS_BUDDY, CLASS_GROUP = 0, 1
TAG_ORDER, TAG_ALIAS = 0x00C8, 0x0131


def parse_tlvs(blob):
    if not blob:
        return []
    (total,) = struct.unpack(">H", blob[:2])
    body, out, i = blob[2:2 + total], [], 0
    while i < len(body):
        tag, ln = struct.unpack(">HH", body[i:i + 4])
        out.append((tag, body[i + 4:i + 4 + ln]))
        i += 4 + ln
    return out


def build_tlvs(tlvs):
    body = b"".join(struct.pack(">HH", t, len(v)) + v for t, v in tlvs)
    return struct.pack(">H", len(body)) + body


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("db")
    ap.add_argument("owner")
    ap.add_argument("buddy")
    ap.add_argument("--alias")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--preauth", action="store_true")
    a = ap.parse_args()

    db = sqlite3.connect(a.db)
    owner, buddy = a.owner.lower(), a.buddy
    groups = db.execute("select groupID, attributes from feedbag where screenName=? and classID=? and groupID<>0",
                        (owner, CLASS_GROUP)).fetchall()
    if not groups:
        sys.exit(f"{owner} has no group yet: log in once with ICQ 5.1 so it creates 'General'.")
    gid, gattrs = groups[0]
    if db.execute("select 1 from feedbag where screenName=? and classID=? and name=?",
                  (owner, CLASS_BUDDY, buddy)).fetchone():
        sys.exit(f"{buddy} is already on {owner}'s list.")

    used = {r[0] for r in db.execute("select itemID from feedbag where screenName=?", (owner,))}
    item_id = next(i for i in iter(lambda: random.randint(1, 0x7FFF), None) if i not in used)

    tlvs = parse_tlvs(gattrs)
    new_tlvs = [(t, v + struct.pack(">H", item_id) if t == TAG_ORDER else v) for t, v in tlvs]
    if not any(t == TAG_ORDER for t, _ in tlvs):
        new_tlvs.append((TAG_ORDER, struct.pack(">H", item_id)))
    buddy_attrs = build_tlvs([(TAG_ALIAS, (a.alias or buddy).encode())])
    now = int(time.time())

    print(f"group {gid}: new buddy itemID {item_id} ({buddy}, alias {a.alias or buddy!r})")
    print(f"group attrs {gattrs.hex()} -> {build_tlvs(new_tlvs).hex()}")
    if not a.apply:
        print("dry run; add --apply to write")
        return
    with db:
        db.execute("insert into feedbag(screenName,groupID,itemID,classID,name,attributes,lastModified) values (?,?,?,?,?,?,?)",
                   (owner, gid, item_id, CLASS_BUDDY, buddy, buddy_attrs, now))
        db.execute("update feedbag set attributes=?, lastModified=? where screenName=? and groupID=? and itemID=0",
                   (build_tlvs(new_tlvs), now, owner, gid))
        if a.preauth:
            db.execute("insert or ignore into contactPreauth(ownerScreenName,authorizedScreenName,createdAt) values (?,?,?)",
                       (buddy, owner, now))
    print("applied")


if __name__ == "__main__":
    main()
