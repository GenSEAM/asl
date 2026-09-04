#!/usr/bin/env python3
"""Ping IndexNow and search engines with updated blog articles and sitemap URLs."""

import json
import sys
import urllib.request
import urllib.error

KEY = "6f7c9e1b2a4d3e8f5c0a1b2c3d4e5f6a"
HOST = "aslang.dev"
KEY_LOCATION = f"https://{HOST}/{KEY}.txt"

URLS = [
    f"https://{HOST}/",
    f"https://{HOST}/blog",
    f"https://{HOST}/blog/why-llms-struggle-with-python-and-rust",
    f"https://{HOST}/blog/the-token-tax-and-interface-compression",
    f"https://{HOST}/blog/from-vibe-code-to-wasm-in-0-04ms",
    f"https://{HOST}/blog/agent-script-the-optimal-agent-language",
    f"https://{HOST}/blog/token-economy-and-structural-compression",
    f"https://{HOST}/blog/inter-agent-protocols-and-wire-frames",
    f"https://{HOST}/blog/the-agent-native-developer-cockpit",
    f"https://{HOST}/blog/multi-dimensional-observability-for-autonomous-systems",
    f"https://{HOST}/blog/universal-cross-platform-glue-without-drift",
    f"https://{HOST}/blog/epistemic-grounding-and-anti-hallucination-firewalls",
    f"https://{HOST}/blog/zero-server-in-browser-agent-runtimes",
    f"https://{HOST}/sitemap.xml",
    f"https://{HOST}/llms.txt",
    f"https://{HOST}/llms-full.txt",
]

ENDPOINTS = [
    "https://api.indexnow.org/indexnow",
    "https://www.bing.com/indexnow",
]


def ping_indexnow():
    payload = {
        "host": HOST,
        "key": KEY,
        "keyLocation": KEY_LOCATION,
        "urlList": URLS,
    }
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "AgentScript-Ping/1.0",
    }

    print(f"Submitting {len(URLS)} URLs to IndexNow endpoints for {HOST}...")
    success_count = 0

    ctx = None
    try:
        import ssl
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            ctx = ssl.create_default_context()
    except Exception:
        ctx = None

    for ep in ENDPOINTS:
        req = urllib.request.Request(ep, data=data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
                status = resp.status
                print(f"  ✓ {ep}: HTTP {status} (OK)")
                success_count += 1
        except urllib.error.HTTPError as e:
            # 200 or 202 accepted
            if e.code in (200, 202):
                print(f"  ✓ {ep}: HTTP {e.code} (Accepted)")
                success_count += 1
            else:
                print(f"  ✗ {ep}: HTTP {e.code} ({e.reason})")
        except Exception as e:
            # Retry with unverified context if macOS local trust store is missing root certs
            try:
                import ssl
                insecure_ctx = ssl._create_unverified_context()
                with urllib.request.urlopen(req, timeout=10, context=insecure_ctx) as resp:
                    print(f"  ✓ {ep}: HTTP {resp.status} (Accepted via fallback)")
                    success_count += 1
            except Exception as e2:
                print(f"  ✗ {ep}: Error ({e2})")

    return success_count > 0


if __name__ == "__main__":
    ping_indexnow()
