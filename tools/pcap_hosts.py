#!/usr/bin/env python3
"""Throwaway: list hostnames and TCP/UDP endpoints a client contacted, from a pcap.

Needs tshark (brew install wireshark / apt install tshark).
Usage: tools/pcap_hosts.py capture.pcap <client-ip>
"""
import collections
import subprocess
import sys


def tshark(pcap, display_filter, fields):
    cmd = ["tshark", "-r", pcap, "-Y", display_filter, "-T", "fields"]
    for f in fields:
        cmd += ["-e", f]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.splitlines()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    pcap, client = sys.argv[1:]

    total = len(tshark(pcap, "frame", ["frame.number"]))
    from_client = len(tshark(pcap, f"ip.src=={client}", ["frame.number"]))
    print(f"{total} packets in file, {from_client} from {client}")
    if from_client == 0:
        sys.exit("No IP packets from the client: the capture is empty or was cut short. Re-capture (see docs/setup-guide.md).")

    names = collections.Counter(
        line.strip() for line in tshark(pcap, f"dns.flags.response==0 && ip.src=={client}", ["dns.qry.name"]) if line.strip()
    )
    print("== DNS names queried ==")
    for n, c in sorted(names.items()):
        print(f"{c:5d}  {n}")

    eps = collections.Counter()
    for line in tshark(pcap, f"ip.src=={client} && (tcp.flags.syn==1 && tcp.flags.ack==0 || udp)",
                       ["ip.dst", "tcp.dstport", "udp.dstport"]):
        dst, tp, up = (line.split("\t") + ["", "", ""])[:3]
        eps[(dst, "tcp" if tp else "udp", tp or up)] += 1
    print("\n== Destinations (first SYN / UDP) ==")
    for (dst, proto, port), c in sorted(eps.items()):
        print(f"{c:5d}  {dst}:{port}/{proto}")

    http = tshark(pcap, f"ip.src=={client} && http.request", ["http.host", "http.request.uri"])
    if http:
        print("\n== Plain HTTP requests ==")
        for h in sorted(set(http)):
            print("  ", h.replace("\t", ""))


if __name__ == "__main__":
    main()
