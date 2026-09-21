#!/usr/bin/env python3
"""M1 throwaway: minimal TOC2 client for probing Open OSCAR Server. Not part of the bridge.

Protocol details come from the server source (server/toc/*.go, 2026-09-20):
  - client sends "FLAPON\\r\\n\\r\\n"; server replies with a FLAP signon frame (type 1)
  - client replies with a signon frame (version 1 + TLV 0x01 screen name)
  - client sends data frame "toc2_signon <host> <port> <sn> <roasted pw> ..."
  - roasting: XOR with "Tic/Toc", hex, prefixed "0x"

Usage:
  tools/toc2_spike.py --user vbuddy1 --password pw [--host 127.0.0.1] [--port 9898] [--script FILE]
Commands (stdin, or --script file; lines starting with # are ignored):
  im <to> <text...>            send an IM
  typing <to> <0|1|2>          typing event (0 none, 1 paused, 2 typing)
  add <name> [<name>...]       toc_add_buddy (does not persist)
  newbuddy <group> <name>      toc2_new_buddies (persists to the server-side buddy list)
  away [text...]               toc_set_away (no text = back)
  raw <toc command...>         send a raw command
  burst <to> <n> <ms>          send n IMs, ms apart, and report the first error/limit
  sleep <seconds>
  quit
"""
import argparse
import select
import socket
import struct
import sys
import time

ROAST = b"Tic/Toc"


def roast(pw: str) -> str:
    return "0x" + "".join(f"{b ^ ROAST[i % len(ROAST)]:02x}" for i, b in enumerate(pw.encode()))


def toc_quote(s: str) -> str:
    out = []
    for ch in s:
        if ch in '\\"$[]{}()':
            out.append("\\")
        out.append(ch)
    return '"' + "".join(out) + '"'


def normalize(s: str) -> str:
    return s.replace(" ", "").lower()


class Toc2:
    def __init__(self, host, port, user, password, quiet=False):
        self.user = user
        self.seq = 0
        self.buf = b""
        self.t0 = time.time()
        self.quiet = quiet
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.sendall(b"FLAPON\r\n\r\n")
        ftype, payload = self.read_frame()
        assert ftype == 1, f"expected signon frame, got type {ftype}"
        sn = user.encode()
        self.send_frame(1, struct.pack(">IHH", 1, 1, len(sn)) + sn)
        code = self.login_code(user, password)
        self.send(f"toc2_signon login.oscar.aol.com 29999 {normalize(user)} {roast(password)} "
                  f'english-US "TIC:TOC2:REVISION" 160 {code}')

    @staticmethod
    def login_code(sn: str, pw: str) -> int:
        a = (ord(sn[0].lower()) - 96) * 7696 + 738816
        b = (ord(sn[0].lower()) - 96) * 746512
        c = (ord(pw[0].lower()) - 96) * a
        return c - a + b + 71665152

    def log(self, direction, text):
        if not self.quiet:
            print(f"[{time.time() - self.t0:7.3f}] {self.user} {direction} {text}", flush=True)

    def send_frame(self, ftype, payload):
        self.seq = (self.seq + 1) & 0xFFFF
        self.sock.sendall(b"*" + struct.pack(">BHH", ftype, self.seq, len(payload)) + payload)

    def send(self, cmd):
        self.log(">>", cmd if "toc2_signon" not in cmd else cmd.split(" ")[0] + " ...")
        self.send_frame(2, cmd.encode() + b"\x00")

    def read_frame(self, timeout=10):
        self.sock.settimeout(timeout)
        while True:
            if len(self.buf) >= 6:
                assert self.buf[0:1] == b"*", f"bad FLAP start {self.buf[:6]!r}"
                ftype, _seq, length = struct.unpack(">BHH", self.buf[1:6])
                if len(self.buf) >= 6 + length:
                    payload = self.buf[6:6 + length]
                    self.buf = self.buf[6 + length:]
                    return ftype, payload
            chunk = self.sock.recv(4096)
            if not chunk:
                raise EOFError("server closed the connection")
            self.buf += chunk

    def pump(self, seconds):
        """Read and print server frames for up to `seconds`."""
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.sock], [], [], max(0.0, end - time.time()))
            if not r and not self.buf:
                break
            try:
                ftype, payload = self.read_frame(timeout=0.5)
            except (socket.timeout, TimeoutError):
                continue
            if ftype == 2:
                self.log("<<", payload.rstrip(b"\x00").decode("utf-8", "replace"))
            else:
                self.log("<<", f"frame type {ftype} {payload!r}")


def run_cmd(t: Toc2, line: str):
    line = line.strip()
    if not line or line.startswith("#"):
        return True
    parts = line.split(" ")
    cmd, args = parts[0], parts[1:]
    if cmd == "im":
        t.send(f"toc2_send_im {normalize(args[0])} {toc_quote(' '.join(args[1:]))}")
    elif cmd == "typing":
        t.send(f"toc2_client_event {normalize(args[0])} {args[1]}")
    elif cmd == "add":
        t.send("toc_add_buddy " + " ".join(normalize(a) for a in args))
    elif cmd == "newbuddy":
        t.send(f"toc2_new_buddies {{g:{args[0]}\nb:{args[1]}\n}}")
    elif cmd == "away":
        t.send("toc_set_away" + (" " + toc_quote(" ".join(args)) if args else ""))
    elif cmd == "raw":
        t.send(" ".join(args))
    elif cmd == "burst":
        to, n, ms = args[0], int(args[1]), float(args[2])
        started = time.time()
        for i in range(n):
            t.send(f"toc2_send_im {normalize(to)} {toc_quote(f'burst {i + 1}/{n}')}")
            t.pump(ms / 1000.0)
        print(f"burst of {n} took {time.time() - started:.2f}s", flush=True)
    elif cmd == "sleep":
        t.pump(float(args[0]))
    elif cmd == "quit":
        return False
    else:
        print(f"unknown command {cmd}")
    t.pump(0.3)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=9898)
    ap.add_argument("--script", help="file with commands instead of stdin")
    a = ap.parse_args()

    t = Toc2(a.host, a.port, a.user, a.password)
    t.pump(1.5)
    t.send("toc_init_done")
    t.pump(0.5)

    src = open(a.script) if a.script else sys.stdin
    for line in src:
        if not run_cmd(t, line):
            break
    t.pump(1.0)


if __name__ == "__main__":
    main()
