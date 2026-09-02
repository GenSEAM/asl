#!/usr/bin/env python3
"""
Ping Search Engines & AI Crawlers (IndexNow, Bing, Web Archive, AI Datasets).
Notifies search engines and AI web crawlers (BingBot / ChatGPT / Copilot / Perplexity)
that aslang.dev has updated its pages, sitemap, and LLM machine-readable specs.
"""

import json
import urllib.request
import urllib.error
import sys

HOST = "aslang.dev"
INDEXNOW_KEY = "6f7c9e1b2a4d3e8f5c0a1b2c3d4e5f6a"
KEY_LOCATION = f"https://{HOST}/{INDEXNOW_KEY}.txt"

URLS = [
    f"https://{HOST}/",
    f"https://{HOST}/ecosystem",
    f"https://{HOST}/roadmap",
    f"https://{HOST}/playground",
    f"https://{HOST}/docs",
    f"https://{HOST}/llms.txt",
    f"https://{HOST}/llms-full.txt",
    f"https://{HOST}/sitemap.xml",
]

def ping_indexnow():
    """Submit URLs to IndexNow (powers Bing, ChatGPT Search, Copilot, Yandex, Seznam)."""
    print(f"--> Pinging IndexNow API (Bing / ChatGPT / Copilot)...")
    endpoint = "https://api.indexnow.org/indexnow"
    payload = {
        "host": HOST,
        "key": INDEXNOW_KEY,
        "keyLocation": KEY_LOCATION,
        "urlList": URLS,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=data,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "AgentScript-Ping/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.status
            print(f"    [IndexNow OK] Status: {status} (URLs successfully submitted to index queue)")
    except urllib.error.HTTPError as e:
        print(f"    [IndexNow Response] HTTP {e.code}: {e.read().decode('utf-8', errors='ignore')}")
    except Exception as e:
        print(f"    [IndexNow Error] {e}")

def ping_bing_sitemap():
    """Ping Bing sitemap endpoint."""
    print(f"--> Pinging Bing Sitemap endpoint...")
    sitemap_url = f"https://{HOST}/sitemap.xml"
    endpoint = f"https://www.bing.com/ping?sitemap={urllib.parse.quote(sitemap_url)}"
    req = urllib.request.Request(endpoint, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"    [Bing Sitemap OK] Status: {resp.status}")
    except Exception as e:
        print(f"    [Bing Sitemap Note] {e}")

def ping_wayback_machine():
    """Trigger archive snapshot on Wayback Machine (used by Common Crawl & AI dataset collectors)."""
    print(f"--> Triggering Wayback Machine snapshot (Common Crawl & AI dataset harvest)...")
    target = f"https://web.archive.org/save/https://{HOST}/"
    req = urllib.request.Request(target, headers={"User-Agent": "AgentScript-Bot/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"    [Wayback Machine OK] Status: {resp.status}")
    except Exception as e:
        print(f"    [Wayback Machine Note] Snapshot requested ({e})")

def main():
    print(f"================================================================")
    print(f"  Pinging Search Engines & AI Crawlers for {HOST}")
    print(f"================================================================")
    ping_indexnow()
    ping_bing_sitemap()
    ping_wayback_machine()
    print(f"================================================================")
    print(f"  All search engine & AI ping requests dispatched.")
    print(f"================================================================")

if __name__ == "__main__":
    main()
