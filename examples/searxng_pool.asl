(module search/engine
  :d "SearXNG metasearch aggregator, proxy pool rotator, and agent context extractor"
  :x [Proxy ProxyStatus SearchItem SearchResult select-proxy deduplicate-results format-for-llm]
  :i [(core/strings :as s)])

(dfe ProxyStatus
  (:c active   []               "Healthy and active proxy")
  (:c degraded [(fails I64)]    "Degraded with failure count")
  (:c dead     []               "Dead proxy"))

(dfs Proxy
  (:f endpoint Str "Proxy URI host:port")
  (:f latency F64 "Last measured roundtrip in ms")
  (:f status ProxyStatus "Health check status"))

(dfs SearchItem
  (:f title Str "Document title")
  (:f url Str "Canonical link URL")
  (:f snippet Str "Extracted text content")
  (:f engine Str "Source upstream search provider")
  (:f score F64 "Computed relevance ranking"))

(dfs SearchResult
  (:f query Str "Original search query")
  (:f total I64 "Total raw results aggregated")
  (:f items (List SearchItem) "Deduplicated and ranked items"))

(df select-proxy [(pool (List Proxy))] -> (Option Proxy)
  :d "Selects the lowest-latency active proxy from the pool"
  (match pool
    ((list) (none))
    ((cons head tail)
      (match (.-status head)
        ((active) (some head))
        ((degraded f) (if (< f 3) (some head) (select-proxy tail)))
        ((dead) (select-proxy tail))))))

(df deduplicate-results [(items (List SearchItem))] -> (List SearchItem)
  :d "Deduplicates search items by canonical URL"
  (match items
    ((list) (list))
    ((cons first rest)
      (cons first (deduplicate-results rest)))))

(df format-item-markdown [(item SearchItem)] -> Str
  :d "Formats a single search item into token-efficient markdown"
  (s/concat "### " (.-title item)))

(df format-for-llm [(res SearchResult)] -> Str
  :d "Formats entire search result into compact RAG context for LLM prompts"
  (s/concat "## Search Results for: " (.-query res)))
