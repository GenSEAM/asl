(module asl-search/engine
  :d "Decentralized multi-engine metasearch aggregator, URL deduplicator, and RAG context compressor in ASL."
  :x [ProxyState ProxyNode SearchEngine SearchQuery SearchResult CurlCommand is-proxy-healthy select-healthy-proxies build-search-url make-curl-command clean-url merge-search-results format-result-markdown format-rag-context])

(dfe ProxyState
  (:c active [] "active proxy")
  (:c cooldown [] "cooldown proxy")
  (:c dead [] "dead proxy"))

(dfs ProxyNode
  (:f endpoint Str "endpoint url")
  (:f state ProxyState "state")
  (:f latency-ms F64 "latency in ms")
  (:f success-rate F64 "success rate"))

(dfe SearchEngine
  (:c ddg [] "DuckDuckGo web search")
  (:c wikipedia [] "Wikipedia OpenSearch")
  (:c github [] "GitHub code & repositories")
  (:c arxiv [] "arXiv scientific papers")
  (:c hackernews [] "HackerNews Algolia")
  (:c brave [] "Brave Search API")
  (:c google [] "Google Custom Search")
  (:c tavily [] "Tavily AI Search"))

(dfs SearchQuery
  (:f text Str "query string")
  (:f max-results I64 "max results count")
  (:f engines (List Str) "selected search engines"))

(dfs SearchResult
  (:f title Str "title")
  (:f url Str "url")
  (:f snippet Str "snippet")
  (:f engine Str "engine name")
  (:f score F64 "relevance score"))

(dfs CurlCommand
  (:f bin Str "curl executable path")
  (:f args (List Str) "command argument vector")
  (:f url Str "target URL"))

(df is-proxy-healthy [(proxy ProxyNode)] -> Bool
  :d "Checks if proxy is healthy based on latency and success rate."
  (and (< (.-latency-ms proxy) 500.0) (> (.-success-rate proxy) 0.9)))

(df select-healthy-proxies [(proxies (List ProxyNode))] -> (List ProxyNode)
  :d "Filters proxy pool for active healthy nodes."
  (filter is-proxy-healthy proxies))

(df build-search-url [(engine Str) (query Str) (limit I64)] -> Str
  :d "Generates target query endpoint for the selected search provider."
  (let [(clean-q (string-replace query " " "+"))
        (lim-str (string-from-int64 limit))]
    (cond
      ((= engine "wikipedia")
       (str "https://en.wikipedia.org/w/api.php?action=opensearch&search=" clean-q "&limit=" lim-str "&namespace=0&format=json"))
      ((= engine "github")
       (str "https://api.github.com/search/repositories?q=" clean-q "&per_page=" lim-str))
      ((= engine "arxiv")
       (str "http://export.arxiv.org/api/query?search_query=all:" clean-q "&start=0&max_results=" lim-str))
      ((= engine "hackernews")
       (str "https://hn.algolia.com/api/v1/search?query=" clean-q "&tags=story&hitsPerPage=" lim-str))
      ((= engine "hn")
       (str "https://hn.algolia.com/api/v1/search?query=" clean-q "&tags=story&hitsPerPage=" lim-str))
      (:else
       (str "https://html.duckduckgo.com/html/?q=" clean-q)))))

(df make-curl-command [(url Str) (timeout-sec I64) (user-agent Str)] -> CurlCommand
  :d "Builds a safe, typed curl execution vector."
  (CurlCommand
    :bin "curl"
    :args (list "-s" "--max-time" (string-from-int64 timeout-sec) "-H" (str "User-Agent: " user-agent) url)
    :url url))

(df is-tracking-param? [(param Str)] -> Bool
  :d "Checks if query parameter is a tracking tag."
  (or (string-starts-with? param "utm_")
      (or (string-starts-with? param "fbclid=")
          (or (string-starts-with? param "gclid=")
              (string-starts-with? param "ref=")))))

(df filter-query-params [(query-str Str)] -> Str
  :d "Filters tracking parameters from query string."
  (let [(parts (string-split query-str "&"))
        (clean-parts (filter (fn [(p Str)] -> Bool (not (is-tracking-param? p))) parts))]
    (string-join clean-parts "&")))

(df clean-url [(url Str)] -> Str
  :d "Strips tracking parameters (utm_*, ref, fbclid) from a URL."
  (let [(url-parts (string-split url "?"))]
    (mt (list-head url-parts)
      ((none) url)
      ((some base)
       (mt (list-tail url-parts)
         ((none) base)
         ((some tail)
          (mt (list-head tail)
            ((none) base)
            ((some raw-qs)
             (let [(clean-qs (filter-query-params raw-qs))]
               (if (string-empty? clean-qs)
                   base
                   (str base "?" clean-qs)))))))))))

(df update-item-or-add [(acc (List SearchResult)) (item SearchResult)] -> (List SearchResult)
  :d "Appends item or boosts score and combines engine tags if URL already exists."
  (let [(url (.-url item))
        (found (filter (fn [(r SearchResult)] -> Bool (= (.-url r) url)) acc))]
    (if (list-empty? found)
        (list-append acc (list item))
        (map (fn [(r SearchResult)] -> SearchResult
               (if (= (.-url r) url)
                   (SearchResult
                     :title (.-title r)
                     :url (.-url r)
                     :snippet (if (> (string-length (.-snippet item)) (string-length (.-snippet r)))
                                  (.-snippet item)
                                  (.-snippet r))
                     :engine (str (.-engine r) "+" (.-engine item))
                     :score (+ (.-score r) (.-score item)))
                   r))
             acc))))

(df merge-search-results [(primary (List SearchResult)) (secondary (List SearchResult))] -> (List SearchResult)
  :d "Merges two result sets with cross-engine deduplication and score boosting."
  (fold (fn [(acc (List SearchResult)) (item SearchResult)] -> (List SearchResult)
          (update-item-or-add acc item))
        primary
        secondary))

(df format-result-markdown [(index I64) (res SearchResult)] -> Str
  :d "Formats a single search result as markdown for LLM injection."
  (str (string-from-int64 index) ". **[" (.-title res) "](" (.-url res) ")**  `[" (.-engine res) "]`\n   " (.-snippet res) "\n"))

(df format-rag-context [(query Str) (items (List SearchResult))] -> Str
  :d "Formats full search results as token-efficient markdown context for LLM prompt injection."
  (let [(header (str "## Search Results for: '" query "' (" (string-from-int64 (list-length items)) " items)\n\n"))
        (indexed (zip (range 1 (+ (list-length items) 1)) items))
        (formatted-items (map (fn [(p (Pair I64 SearchResult))] -> Str
                                (format-result-markdown (.-first p) (.-second p)))
                              indexed))]
    (str header (string-join formatted-items "\n"))))
