#!/usr/bin/env python3
"""Reads URLs (one per line) and prints the distinct host names, sorted. IPv6 literals are left out.

IPv6 is left out on purpose: the allowlists of checks 01/05/08 hold IPv4 and name hosts only. A document that also
lists an IPv6 redirect (goose lists http://[::1]/...) is then refused for that host; check 09 measures exactly that,
and check 10 adds "[::1]" explicitly. A sed-based extraction parsed "[::1]" as the host "[" and broke the allowlist.
"""
import sys
import urllib.parse

hosts = set()
for raw in sys.stdin:
    url = raw.strip()
    if not url:
        continue
    try:
        host = urllib.parse.urlsplit(url).hostname
    except ValueError:
        continue
    if host and ":" not in host:
        hosts.add(host)
for h in sorted(hosts):
    print(h)
