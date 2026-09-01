(module asl-search/engine
  :doc "SearXNG metasearch engine and proxy pool rotator in ASL Nano"
  :export [ProxyState ProxyNode SearchQuery SearchResult is-proxy-healthy])

(dfe ProxyState
  (:case active [] "active proxy")
  (:case cooldown [] "cooldown proxy")
  (:case dead [] "dead proxy"))

(dfs ProxyNode
  (:field endpoint Str "endpoint url")
  (:field state ProxyState "state")
  (:field latency-ms F64 "latency in ms")
  (:field success-rate F64 "success rate"))

(dfs SearchQuery
  (:field text Str "query string")
  (:field max-results I64 "max results count"))

(dfs SearchResult
  (:field title Str "title")
  (:field url Str "url")
  (:field snippet Str "snippet")
  (:field score F64 "relevance score"))

(df is-proxy-healthy [(proxy ProxyNode)] -> Bool
  :doc "Checks if proxy is healthy"
  (and (< (.-latency-ms proxy) 500.0) (> (.-success-rate proxy) 0.9)))
