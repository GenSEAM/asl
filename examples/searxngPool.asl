(module search/engine :x [Proxy ProxyStatus SearchItem SearchResult selectProxy deduplicateResults formatForLlm] :i [(asl-text/string :as s)])

(enum ProxyStatus (:c active [] "Healthy and active proxy") (:c degraded [(fails I64)] "Degraded with failure count") (:c dead [] "Dead proxy"))

(schema Proxy (:f endpoint Str) (:f latency F64) (:f status ProxyStatus))

(schema SearchItem (:f title Str) (:f url Str) (:f snippet Str) (:f engine Str) (:f score F64))

(schema SearchResult (:f query Str) (:f total I64) (:f items (List SearchItem)))

fn selectProxy pool: (List Proxy) -> (Option Proxy)
  (match (listHead pool) ((none) (none)) ((some head) (let [(tail (optionOr (listTail pool) (list)))] (match head.status ((active) (some head)) ((degraded f) (if (< f 3) (some head) (selectProxy tail))) ((dead) (selectProxy tail))))))

fn deduplicateResults items: (List SearchItem) -> (List SearchItem)
  (match (listHead items) ((none) (list)) ((some first) (cons first (deduplicateResults (optionOr (listTail items) (list))))))

fn formatItemMarkdown item: SearchItem -> Str
  (s/concat "### " item.title)

fn formatForLlm res: SearchResult -> Str
  (s/concat "## Search Results for: " res.query)
