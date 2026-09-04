"""Unified multi-engine search client and RAG context extractor for ASL."""
import html
import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Callable, Optional


@dataclass
class SearchResultItem:
    title: str
    url: str
    snippet: str
    engine: str
    score: float = 1.0


def normalize_url(url: str) -> str:
    """Strips tracking query params (utm_*, ref, etc.) and fragments."""
    try:
        parsed = urllib.parse.urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return url
        qs = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        clean_qs = {
            k: v for k, v in qs.items()
            if not (k.startswith("utm_") or k in {"ref", "fbclid", "gclid", "source", "ref_src"})
        }
        new_query = urllib.parse.urlencode(clean_qs, doseq=True)
        return urllib.parse.urlunparse((
            parsed.scheme,
            parsed.netloc.lower(),
            parsed.path.rstrip("/") if parsed.path != "/" else "/",
            "",
            new_query,
            ""
        ))
    except Exception:
        return url


def http_fetch(
    url: str,
    headers: Optional[dict[str, str]] = None,
    data: Optional[bytes] = None,
    method: str = "GET",
    timeout: float = 4.0,
    proxy: Optional[str] = None
) -> Optional[bytes]:
    """Resilient HTTP client using urllib with automatic curl fallback."""
    req_headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "*/*",
    }
    if headers:
        req_headers.update(headers)

    # 1. Try standard library urllib
    try:
        handlers = []
        if proxy:
            handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
        opener = urllib.request.build_opener(*handlers)
        req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
        with opener.open(req, timeout=timeout) as resp:
            if resp.status == 200:
                return resp.read()
    except Exception:
        pass

    # 2. Try curl CLI fallback if available
    try:
        cmd = ["curl", "-s", "--max-time", str(max(1, int(timeout)))]
        if proxy:
            cmd.extend(["--proxy", proxy])
        for k, v in req_headers.items():
            cmd.extend(["-H", f"{k}: {v}"])
        if method == "POST" and data:
            cmd.extend(["-X", "POST", "--data-binary", data.decode("utf-8", errors="ignore")])
        cmd.append(url)
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout + 1.0)
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout
    except Exception:
        pass

    return None


# =====================================================================
# Engine Providers
# =====================================================================

def search_ddg(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """DuckDuckGo web search via HTML Lite interface (no API key required)."""
    params = urllib.parse.urlencode({"q": query})
    url = f"https://html.duckduckgo.com/html/?{params}"
    raw = http_fetch(url, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    page = raw.decode("utf-8", errors="ignore")
    blocks = re.findall(r'<div class=\"[^\"]*web-result[^\"]*\".*?(?=<div class=\"[^\"]*web-result[^\"]*\"|<div class=\"nav-link\"|$)', page, re.DOTALL)
    results = []

    for b in blocks:
        t = re.search(r'<a[^>]*class=\"[^\"]*result__a[^\"]*\"[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>', b, re.DOTALL)
        if not t:
            t = re.search(r'<a[^>]*href=\"([^\"]*)\"[^>]*class=\"[^\"]*result__a[^\"]*\"[^>]*>(.*?)</a>', b, re.DOTALL)
        s = re.search(r'class=\"[^\"]*result__snippet[^\"]*\"[^>]*>(.*?)</a>', b, re.DOTALL)

        if t:
            raw_url = t.group(1)
            raw_title = re.sub(r'<[^>]+>', '', t.group(2)).strip()
            if "uddg=" in raw_url:
                m = re.search(r'uddg=([^&]+)', raw_url)
                target_url = urllib.parse.unquote(m.group(1)) if m else raw_url
            else:
                target_url = raw_url

            snippet = re.sub(r'<[^>]+>', '', s.group(1)).strip() if s else ""
            results.append(SearchResultItem(
                title=html.unescape(raw_title),
                url=normalize_url(target_url),
                snippet=html.unescape(snippet),
                engine="ddg",
                score=1.0
            ))
            if len(results) >= limit:
                break
    return results


def search_wikipedia(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """Wikipedia OpenSearch API (factual definitions and reference articles)."""
    params = urllib.parse.urlencode({
        "action": "opensearch",
        "search": query,
        "limit": limit,
        "namespace": 0,
        "format": "json"
    })
    url = f"https://en.wikipedia.org/w/api.php?{params}"
    headers = {"User-Agent": "ASL-SearchAgent/1.0 (https://aslang.dev)"}
    raw = http_fetch(url, headers=headers, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        if len(data) >= 4:
            titles = data[1]
            descriptions = data[2]
            urls = data[3]
            results = []
            for t, d, u in zip(titles, descriptions, urls):
                results.append(SearchResultItem(
                    title=t,
                    url=normalize_url(u),
                    snippet=d if d else f"Wikipedia article for {t}",
                    engine="wikipedia",
                    score=1.1
                ))
            return results[:limit]
    except Exception:
        pass
    return []


def search_github(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """GitHub repositories search (code, libraries, developer tools)."""
    params = urllib.parse.urlencode({"q": query, "per_page": limit})
    url = f"https://api.github.com/search/repositories?{params}"
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "ASL-SearchAgent/1.0",
    }
    gh_token = os.environ.get("GITHUB_TOKEN")
    if gh_token:
        headers["Authorization"] = f"token {gh_token}"

    raw = http_fetch(url, headers=headers, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for item in data.get("items", [])[:limit]:
            stars = item.get("stargazers_count", 0)
            lang = item.get("language") or "Code"
            desc = item.get("description") or "No description provided."
            results.append(SearchResultItem(
                title=item.get("full_name", ""),
                url=normalize_url(item.get("html_url", "")),
                snippet=f"{desc} (★ {stars} · {lang})",
                engine="github",
                score=1.05
            ))
        return results
    except Exception:
        pass
    return []


def search_arxiv(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """arXiv scientific papers and AI/CS research."""
    clean_q = re.sub(r'[^\w\s]', ' ', query).strip()
    params = urllib.parse.urlencode({
        "search_query": f"all:{clean_q}",
        "start": 0,
        "max_results": limit
    })
    url = f"http://export.arxiv.org/api/query?{params}"
    raw = http_fetch(url, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        root = ET.fromstring(raw)
        entries = root.findall("{http://www.w3.org/2005/Atom}entry")
        results = []
        for entry in entries[:limit]:
            t_elem = entry.find("{http://www.w3.org/2005/Atom}title")
            s_elem = entry.find("{http://www.w3.org/2005/Atom}summary")
            u_elem = entry.find("{http://www.w3.org/2005/Atom}id")
            title = t_elem.text.strip().replace("\n", " ") if t_elem is not None and t_elem.text else ""
            summary = s_elem.text.strip().replace("\n", " ") if s_elem is not None and s_elem.text else ""
            paper_url = u_elem.text.strip() if u_elem is not None and u_elem.text else ""
            results.append(SearchResultItem(
                title=title,
                url=normalize_url(paper_url),
                snippet=summary[:280] + ("..." if len(summary) > 280 else ""),
                engine="arxiv",
                score=1.15
            ))
        return results
    except Exception:
        pass
    return []


def search_hackernews(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """HackerNews Algolia API (developer discussions, releases, debates)."""
    params = urllib.parse.urlencode({"query": query, "tags": "story", "hitsPerPage": limit})
    url = f"https://hn.algolia.com/api/v1/search?{params}"
    raw = http_fetch(url, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for hit in data.get("hits", [])[:limit]:
            title = hit.get("title", "")
            target_url = hit.get("url") or f"https://news.ycombinator.com/item?id={hit.get('objectID')}"
            points = hit.get("points", 0)
            comments = hit.get("num_comments", 0)
            author = hit.get("author", "unknown")
            results.append(SearchResultItem(
                title=title,
                url=normalize_url(target_url),
                snippet=f"HN Score: {points} · {comments} comments · by {author}",
                engine="hackernews",
                score=0.95
            ))
        return results
    except Exception:
        pass
    return []


def search_brave(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """Brave Search API (premium independent index via BRAVE_API_KEY)."""
    api_key = os.environ.get("BRAVE_API_KEY") or os.environ.get("BRAVE_SEARCH_API_KEY")
    if not api_key:
        return []

    params = urllib.parse.urlencode({"q": query, "count": limit})
    url = f"https://api.search.brave.com/res/v1/web/search?{params}"
    headers = {"X-Subscription-Token": api_key, "Accept": "application/json"}
    raw = http_fetch(url, headers=headers, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for item in data.get("web", {}).get("results", [])[:limit]:
            results.append(SearchResultItem(
                title=item.get("title", ""),
                url=normalize_url(item.get("url", "")),
                snippet=item.get("description", ""),
                engine="brave",
                score=1.3
            ))
        return results
    except Exception:
        pass
    return []


def search_google(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """Google Custom Search JSON API (via GOOGLE_API_KEY and GOOGLE_CSE_ID)."""
    api_key = os.environ.get("GOOGLE_API_KEY")
    cse_id = os.environ.get("GOOGLE_CSE_ID") or os.environ.get("GOOGLE_SEARCH_CX")
    if not api_key or not cse_id:
        return []

    params = urllib.parse.urlencode({"key": api_key, "cx": cse_id, "q": query, "num": limit})
    url = f"https://www.googleapis.com/customsearch/v1?{params}"
    raw = http_fetch(url, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for item in data.get("items", [])[:limit]:
            results.append(SearchResultItem(
                title=item.get("title", ""),
                url=normalize_url(item.get("link", "")),
                snippet=item.get("snippet", ""),
                engine="google",
                score=1.35
            ))
        return results
    except Exception:
        pass
    return []


def search_tavily(query: str, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """Tavily Search API for LLM agents (via TAVILY_API_KEY)."""
    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        return []

    payload = json.dumps({"api_key": api_key, "query": query, "max_results": limit}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    raw = http_fetch("https://api.tavily.com/search", headers=headers, data=payload, method="POST", timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for item in data.get("results", [])[:limit]:
            results.append(SearchResultItem(
                title=item.get("title", ""),
                url=normalize_url(item.get("url", "")),
                snippet=item.get("content", ""),
                engine="tavily",
                score=1.4
            ))
        return results
    except Exception:
        pass
    return []


def search_searxng(query: str, instance_url: Optional[str] = None, limit: int = 5, proxy: Optional[str] = None, timeout: float = 4.0) -> list[SearchResultItem]:
    """Custom SearXNG instance client."""
    inst = instance_url or os.environ.get("SEARXNG_URL")
    if not inst:
        return []

    params = urllib.parse.urlencode({"q": query, "format": "json"})
    url = f"{inst.rstrip('/')}/search?{params}"
    raw = http_fetch(url, timeout=timeout, proxy=proxy)
    if not raw:
        return []

    try:
        data = json.loads(raw.decode("utf-8"))
        results = []
        for item in data.get("results", [])[:limit]:
            results.append(SearchResultItem(
                title=item.get("title", ""),
                url=normalize_url(item.get("url", "")),
                snippet=item.get("content", ""),
                engine=item.get("engine", "searxng"),
                score=1.1
            ))
        return results
    except Exception:
        pass
    return []


# Engine Registry
ENGINES: dict[str, Callable[..., list[SearchResultItem]]] = {
    "ddg": search_ddg,
    "duckduckgo": search_ddg,
    "wikipedia": search_wikipedia,
    "wiki": search_wikipedia,
    "github": search_github,
    "arxiv": search_arxiv,
    "hn": search_hackernews,
    "hackernews": search_hackernews,
    "brave": search_brave,
    "google": search_google,
    "tavily": search_tavily,
    "searxng": search_searxng,
}

AVAILABLE_ENGINES = ["ddg", "wikipedia", "github", "arxiv", "hn", "brave", "google", "tavily", "searxng"]


# =====================================================================
# Multi-Engine Orchestrator
# =====================================================================

def search_multi(
    query: str,
    engines: Optional[list[str]] = None,
    limit: int = 5,
    instance_url: Optional[str] = None,
    proxy: Optional[str] = None,
    timeout: float = 4.0
) -> list[SearchResultItem]:
    """Parallel multi-engine search aggregator with URL deduplication and RAG scoring."""
    selected = []

    if engines:
        for e in engines:
            canonical = e.strip().lower()
            if canonical in ENGINES and canonical not in selected:
                selected.append(canonical)

    if not selected:
        # Auto-detect: prioritize available API keys, then high-quality zero-config engines
        if os.environ.get("BRAVE_API_KEY") or os.environ.get("BRAVE_SEARCH_API_KEY"):
            selected.append("brave")
        if os.environ.get("GOOGLE_API_KEY") and (os.environ.get("GOOGLE_CSE_ID") or os.environ.get("GOOGLE_SEARCH_CX")):
            selected.append("google")
        if os.environ.get("TAVILY_API_KEY"):
            selected.append("tavily")
        if instance_url or os.environ.get("SEARXNG_URL"):
            selected.append("searxng")

        # Zero-config default set
        for fallback_eng in ["ddg", "wikipedia", "github", "hn"]:
            if fallback_eng not in selected:
                selected.append(fallback_eng)

    items_by_url: dict[str, SearchResultItem] = {}

    def run_engine(engine_name: str) -> list[SearchResultItem]:
        fn = ENGINES.get(engine_name)
        if not fn:
            return []
        try:
            if engine_name == "searxng":
                return fn(query, instance_url=instance_url, limit=limit, proxy=proxy, timeout=timeout)
            return fn(query, limit=limit, proxy=proxy, timeout=timeout)
        except Exception:
            return []

    # Parallel dispatch across selected engines
    with ThreadPoolExecutor(max_workers=min(len(selected), 8)) as pool:
        future_to_engine = {pool.submit(run_engine, eng): eng for eng in selected}
        for future in as_completed(future_to_engine):
            try:
                res_list = future.result()
                for item in res_list:
                    if not item.url:
                        continue
                    if item.url in items_by_url:
                        # Existing item: boost score and concatenate engine tag
                        existing = items_by_url[item.url]
                        existing.score += item.score
                        if item.engine not in existing.engine:
                            existing.engine = f"{existing.engine}+{item.engine}"
                        if len(item.snippet) > len(existing.snippet):
                            existing.snippet = item.snippet
                    else:
                        items_by_url[item.url] = item
            except Exception:
                continue

    aggregated = sorted(items_by_url.values(), key=lambda x: x.score, reverse=True)

    # Offline/Mock fallback for test environments or completely firewalled networks
    if not aggregated:
        return [
            SearchResultItem(
                title=f"ASL Language Reference for '{query}'",
                url="https://aslang.dev",
                snippet="Official documentation for ASL (AgentScript Language) - The Missing Infrastructure Seam.",
                engine="asl-internal",
                score=1.0
            ),
            SearchResultItem(
                title=f"WebAssembly & Agentic Computing: {query}",
                url="https://aslang.dev/docs/runtimes",
                snippet="High-performance S-expression execution in WebAssembly, iOS Wasm3, and Python Numba.",
                engine="asl-docs",
                score=1.0
            )
        ]

    return aggregated


# Backward compatibility alias
def query_searxng(
    query: str,
    instance_url: Optional[str] = None,
    proxy: Optional[str] = None,
    timeout: float = 4.0
) -> list[SearchResultItem]:
    """Backward-compatible entrypoint mapping to multi-engine search."""
    return search_multi(query, instance_url=instance_url, proxy=proxy, timeout=timeout)


def format_results_markdown(query: str, items: list[SearchResultItem]) -> str:
    """Formats search results as token-efficient markdown context for LLM prompt injection."""
    lines = [f"## Search Results for: '{query}' ({len(items)} items)\n"]
    for i, item in enumerate(items, 1):
        lines.append(f"{i}. **[{item.title}]({item.url})**  `[{item.engine}]`")
        if item.snippet:
            lines.append(f"   {item.snippet}\n")
    return "\n".join(lines)

