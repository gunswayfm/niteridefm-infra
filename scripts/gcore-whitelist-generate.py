#!/usr/bin/env python3
"""
gcore-whitelist-generate.py

Generates /etc/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml
from GCore's published edge IP list.

Source: https://api.gcore.com/cdn/public-ip-list (no auth required)

Why this exists:
  GCore CDN proxies bot scans (`.env`, `setup.cgi`, etc.) to origin.
  Origin nginx sees the request as coming from the GCore shield POP IP,
  not the bot. After 5 such scans, CrowdSec's `http-sensitive-files`
  scenario bans the shield IP, killing all legitimate stream traffic.
  The whitelist below tells CrowdSec to never ban GCore IPs.

Output structure:
  - 972 (current count) IPv4 /32 entries — primary precision layer
  - 55 (current count) "dense" /24 CIDRs (each contains 5+ GCore IPs)
    as defense-in-depth for moments between cron syncs

GCore does NOT rotate IPs in the AWS-style "ephemeral pool" sense.
The list is stable; new IPs appear only when GCore adds POPs.
A daily cron is sufficient.

Usage:
  python3 gcore-whitelist-generate.py > niteride-gcore-whitelist.yaml

References:
  - engineering/platforms/gcore-cdn.md
  - engineering/runbooks/failure-modes.md (CORS preflight blocked symptom)
  - engineering/backlog.md P0 "Make GCore CrowdSec whitelist durable"
"""

import collections
import datetime
import ipaddress
import json
import sys
import urllib.request

GCORE_PUBLIC_IP_LIST_URL = "https://api.gcore.com/cdn/public-ip-list"
DENSE_BUCKET_THRESHOLD = 5  # /24s with ≥ this many GCore IPs become CIDR fallbacks


def fetch_ip_list():
    with urllib.request.urlopen(GCORE_PUBLIC_IP_LIST_URL, timeout=15) as resp:
        return json.load(resp)


def bucket_into_dense_24s(addresses):
    """Group /32 entries into /24 buckets, return only those with ≥ THRESHOLD entries."""
    buckets = collections.Counter()
    for addr in addresses:
        ip = addr.split("/")[0]
        try:
            net = ipaddress.ip_network(ip + "/24", strict=False)
            buckets[str(net)] += 1
        except (ValueError, ipaddress.AddressValueError):
            continue
    return sorted(b for b, n in buckets.items() if n >= DENSE_BUCKET_THRESHOLD)


def render_yaml(v4_addresses, v6_addresses, dense_v4_24s, snapshot):
    lines = [
        'name: niteride/gcore-cdn-whitelist',
        'description: "Whitelist GCore CDN edge + shield POPs (AS 199524 G-Core Labs S.A.). See engineering/platforms/gcore-cdn.md."',
        f"# Source: {GCORE_PUBLIC_IP_LIST_URL} (no auth)",
        f"# Snapshot: {snapshot}",
        f"# Counts: {len(v4_addresses)} IPv4 /32 entries, {len(v6_addresses)} IPv6 /48 entries, {len(dense_v4_24s)} dense /24 buckets",
        "# Refresh: regenerate via gcore-whitelist-generate.py (daily cron in CI).",
        "whitelist:",
        '  reason: "GCore CDN origin-pull (AS 199524). Bot scans flowing through GCore would otherwise trigger crowdsecurity/http-sensitive-files bans on shield POP IPs and nuke streaming."',
        "  ip:",
    ]
    for addr in sorted(v4_addresses):
        lines.append(f'    - "{addr.split("/")[0]}"')
    lines.append("  cidr:")
    lines.append("    # Defense-in-depth: GCore-owned /24 buckets that hold 5+ active IPs.")
    lines.append("    # Covers the gap between IP changes upstream and our daily sync.")
    for cidr in dense_v4_24s:
        lines.append(f'    - "{cidr}"')
    lines.append("")
    return "\n".join(lines)


def main():
    data = fetch_ip_list()
    v4 = data.get("addresses", [])
    v6 = data.get("addresses_v6", [])
    dense_v4_24s = bucket_into_dense_24s(v4)
    snapshot = datetime.datetime.now(datetime.UTC).isoformat().replace("+00:00", "Z")
    sys.stdout.write(render_yaml(v4, v6, dense_v4_24s, snapshot))


if __name__ == "__main__":
    main()
