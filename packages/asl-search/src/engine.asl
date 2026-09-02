(module asl-search/engine
  :d "SearXNG metasearch engine and proxy pool rotator in ASL Nano"
  :x [ProxyState ProxyNode SearchQuery SearchResult is-proxy-healthy])

(dfe ProxyState
  (:c active [] "active proxy")
  (:c cooldown [] "cooldown proxy")
  (:c dead [] "dead proxy"))

(dfs ProxyNode
  (:f endpoint Str "endpoint url")
  (:f state ProxyState "state")
  (:f latency-ms F64 "latency in ms")
  (:f success-rate F64 "success rate"))

(dfs SearchQuery
  (:f text Str "query string")
  (:f max-results I64 "max results count"))

(dfs SearchResult
  (:f title Str "title")
  (:f url Str "url")
  (:f snippet Str "snippet")
  (:f score F64 "relevance score"))

(df is-proxy-healthy [(proxy ProxyNode)] -> Bool
  :d "Checks if proxy is healthy"
  (and (< (.-latency-ms proxy) 500.0) (> (.-success-rate proxy) 0.9)))
