#!/usr/bin/env python3
"""Ping WebSub / PubSubHubbub hubs and search engines to notify them of new RSS posts."""

import sys
import urllib.request
import urllib.parse
import urllib.error

RSS_URL = "https://aslang.dev/rss.xml"
SITEMAP_URL = "https://aslang.dev/sitemap.xml"

HUBS = [
    "https://pubsubhubbub.appspot.com/",
    "https://pubsubhubbub.superfeedr.com/",
]

SEARCH_ENGINES = [
    f"https://www.bing.com/ping?sitemap={urllib.parse.quote(SITEMAP_URL)}",
]

def ping_hubs():
    print(f"Pinging WebSub hubs for RSS feed: {RSS_URL}")
    data = urllib.parse.urlencode({
        "hub.mode": "publish",
        "hub.url": RSS_URL,
    }).encode("utf-8")

    ctx = None
    try:
        import ssl
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass

    for hub in HUBS:
        req = urllib.request.Request(
            hub,
            data=data,
            headers={
                "User-Agent": "AgentScript-Rss-Notifier/1.0",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
                print(f"  ✓ {hub}: HTTP {resp.status} (OK)")
        except urllib.error.HTTPError as e:
            if e.code in (200, 204):
                print(f"  ✓ {hub}: HTTP {e.code} (Published)")
            else:
                print(f"  ✗ {hub}: HTTP {e.code} ({e.reason})")
        except Exception as e:
            print(f"  ✗ {hub}: Error: {e}")

    print("\nPinging search engines for sitemap & feed update...")
    for se in SEARCH_ENGINES:
        req = urllib.request.Request(
            se,
            headers={"User-Agent": "AgentScript-Rss-Notifier/1.0"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
                print(f"  ✓ {se}: HTTP {resp.status} (OK)")
        except Exception as e:
            print(f"  ~ {se}: {e}")

if __name__ == "__main__":
    ping_hubs()
