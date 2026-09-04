(module asl-search/test
  :d "Unit tests for multi-engine metasearch aggregator and ecosystem intelligence in ASL"
  :x [run-tests]
  :i [(engine :a eng)
      (ecosystems :a eco)])

(df test-url-builders [] -> Bool
  :d "Verifies query endpoint generation for search providers."
  (and (= (eng/build-search-url "github" "agent script" 5)
          "https://api.github.com/search/repositories?q=agent+script&per_page=5")
       (= (eng/build-search-url "ddg" "agent script" 5)
          "https://html.duckduckgo.com/html/?q=agent+script")))

(df test-url-cleaning [] -> Bool
  :d "Verifies tracking parameter removal from URLs."
  (and (= (eng/clean-url "https://example.com/item?utm_source=twitter&id=42")
          "https://example.com/item?id=42")
       (= (eng/clean-url "https://example.com/docs")
          "https://example.com/docs")))

(df test-proxy-health [] -> Bool
  :d "Verifies proxy health check logic."
  (let [(good-proxy (eng/ProxyNode :endpoint "http://proxy1:8080" :state (eng/active) :latency-ms 120.0 :success-rate 0.98))
        (slow-proxy (eng/ProxyNode :endpoint "http://proxy2:8080" :state (eng/active) :latency-ms 800.0 :success-rate 0.95))
        (pool (list good-proxy slow-proxy))
        (healthy (eng/select-healthy-proxies pool))]
    (and (eng/is-proxy-healthy good-proxy)
         (and (not (eng/is-proxy-healthy slow-proxy))
              (= (list-length healthy) 1)))))

(df test-result-merge [] -> Bool
  :d "Verifies cross-engine result deduplication and score boosting."
  (let [(r1 (eng/SearchResult :title "ASL" :url "https://aslang.dev" :snippet "Lang" :engine "ddg" :score 1.0))
        (r2 (eng/SearchResult :title "ASL" :url "https://aslang.dev" :snippet "The Missing Seam" :engine "github" :score 1.05))
        (merged (eng/merge-search-results (list r1) (list r2)))]
    (and (= (list-length merged) 1)
         (mt (list-head merged)
           ((none) false)
           ((some top)
            (and (> (.-score top) 2.0)
                 (= (.-engine top) "ddg+github")))))))

(df test-rag-formatting [] -> Bool
  :d "Verifies markdown formatting for LLM context injection."
  (let [(r (eng/SearchResult :title "ASL" :url "https://aslang.dev" :snippet "Infrastructure Seam" :engine "github" :score 1.0))
        (md (eng/format-rag-context "asl" (list r)))]
    (string-contains? md "## Search Results for: 'asl' (1 items)")))

(df test-ecosystems [] -> Bool
  :d "Verifies ecosystem package search URL generation and formatting."
  (let [(npm-url (eco/build-ecosystem-url "npm" "agentscript" 5))
        (crates-url (eco/build-ecosystem-url "crates" "serde" 3))
        (pkg (eco/PackageInfo :name "serde" :ecosystem "crates" :version "1.0.210" :description "Serialization" :repo-url "https://crates.io/crates/serde" :popularity 100000))
        (pkg-md (eco/format-package-markdown pkg))
        (deep (eco/create-deep-targets (list (eng/SearchResult :title "Docs" :url "https://aslang.dev" :snippet "S" :engine "ddg" :score 1.0)) 2))]
    (and (string-contains? npm-url "registry.npmjs.org")
         (and (string-contains? crates-url "crates.io/api")
              (and (string-contains? pkg-md "serde")
                   (= (list-length deep) 1))))))

(df run-tests [] -> Bool
  :d "Runs all asl-search unit tests."
  (and (test-url-builders)
       (and (test-url-cleaning)
            (and (test-proxy-health)
                 (and (test-result-merge)
                      (and (test-rag-formatting)
                           (test-ecosystems)))))))


