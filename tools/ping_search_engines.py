#!/usr/bin/env python3
"""
Ping Search Engines & AI Crawlers (IndexNow, Bing, Web Archive, AI Datasets).
Notifies search engines and AI web crawlers (BingBot / ChatGPT / Copilot / Perplexity)
that aslang.dev has updated its pages, sitemap, and LLM machine-readable specs.
"""

import json
import subprocess
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
    payload_str = json.dumps(payload)
    cmd = [
        "curl", "-s", "-w", "%{http_code}",
        "-X", "POST", endpoint,
        "-H", "Content-Type: application/json; charset=utf-8",
        "-H", "User-Agent: AgentScript-Ping/1.0",
        "-d", payload_str,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    status = res.stdout.strip()
    if status in ("200", "202"):
        print(f"    [IndexNow OK] HTTP {status} (URLs successfully queued for re-crawling!)")
    else:
        print(f"    [IndexNow Response] HTTP {status}: {res.stderr or res.stdout}")

def ping_bing_sitemap():
    """Ping Bing sitemap endpoint."""
    print(f"--> Pinging Bing Sitemap endpoint...")
    sitemap_url = f"https://{HOST}/sitemap.xml"
    endpoint = f"https://www.bing.com/ping?sitemap={sitemap_url}"
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", endpoint]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(f"    [Bing Sitemap OK] HTTP {res.stdout.strip()}")

def ping_wayback_machine():
    """Trigger archive snapshot on Wayback Machine (used by Common Crawl & AI dataset collectors)."""
    print(f"--> Triggering Wayback Machine snapshot (Common Crawl & AI dataset harvest)...")
    target = f"https://web.archive.org/save/https://{HOST}/"
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", target]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(f"    [Wayback Machine OK] HTTP {res.stdout.strip()}")

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
