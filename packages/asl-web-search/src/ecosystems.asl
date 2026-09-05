(module asl-web-search/ecosystems
  :d "Package ecosystem search, code library intelligence, and deep link traversal in ASL Nano."
  :x [PackageInfo PackageEcosystem DeepLinkTarget build-ecosystem-url build-package-curl-cmd format-package-markdown format-ecosystem-rag create-deep-targets]
  :i [(engine :a eng)])

(dfs PackageInfo
  (:f name Str "Package or library name")
  (:f ecosystem Str "Ecosystem identifier (npm, pypi, crates, go, github, c)")
  (:f version Str "Latest or specified version string")
  (:f description Str "Package summary description")
  (:f repo-url Str "Repository or package URL")
  (:f popularity I64 "Stars, downloads, or score metric"))

(dfe PackageEcosystem
  (:c npm [] "Node/npm ecosystem")
  (:c pypi [] "Python/PyPI ecosystem")
  (:c crates [] "Rust/crates.io ecosystem")
  (:c go [] "Go packages ecosystem")
  (:c github [] "GitHub repositories")
  (:c clib [] "C/C++ systems libraries"))

(dfs DeepLinkTarget
  (:f url Str "Target web page URL")
  (:f parent-query Str "Source search query")
  (:f depth I64 "Crawl depth level"))

(df build-ecosystem-url [(eco Str) (query Str) (limit I64)] -> Str
  :d "Constructs search API endpoint for the target package registry."
  (let [(clean-q (string-replace query " " "+"))
        (lim-str (string-from-int64 limit))]
    (cond
      ((= eco "npm")
       (str "https://registry.npmjs.org/-/v1/search?text=" clean-q "&size=" lim-str))
      ((= eco "crates")
       (str "https://crates.io/api/v1/crates?q=" clean-q "&per_page=" lim-str))
      ((= eco "pypi")
       (str "https://pypi.org/search/?q=" clean-q))
      ((= eco "go")
       (str "https://pkg.go.dev/search?q=" clean-q))
      ((= eco "c")
       (str "https://api.github.com/search/repositories?q=" clean-q "+language:C&per_page=" lim-str))
      (:else
       (str "https://api.github.com/search/repositories?q=" clean-q "&per_page=" lim-str)))))

(df build-package-curl-cmd [(eco Str) (query Str) (limit I64)] -> eng/CurlCommand
  :d "Constructs typed curl command vector with registry-specific headers."
  (let [(url (build-ecosystem-url eco query limit))
        (ua (cond
              ((= eco "crates") "ASL-AgentSearch/1.0 (https://aslang.dev)")
              ((= eco "github") "ASL-AgentSearch/1.0")
              (:else "Mozilla/5.0 (ASL-Agent/1.0)")))
        (headers (cond
                   ((= eco "npm") (list "-H" "Accept: application/json" "-H" (str "User-Agent: " ua)))
                   ((= eco "github") (list "-H" "Accept: application/vnd.github.v3+json" "-H" (str "User-Agent: " ua)))
                   (:else (list "-H" (str "User-Agent: " ua)))))]
    (eng/CurlCommand
      :bin "curl"
      :args (list-append (list "-s" "--max-time" "5")
                         (list-append headers (list url)))
      :url url)))

(df format-package-markdown [(pkg PackageInfo)] -> Str
  :d "Formats single package record as markdown citation."
  (str "**[" (.-name pkg) "](" (.-repo-url pkg) ")**  `[" (.-ecosystem pkg) " · v" (.-version pkg) "]` (★/dl: " (string-from-int64 (.-popularity pkg)) ")\n   "
       (.-description pkg) "\n"))

(df format-ecosystem-rag [(query Str) (packages (List PackageInfo))] -> Str
  :d "Formats list of ecosystem packages into RAG prompt context."
  (let [(header (str "## Ecosystem Packages for: '" query "' (" (string-from-int64 (list-length packages)) " packages)\n\n"))
        (rows (map format-package-markdown packages))]
    (str header (string-join rows "\n"))))

(df create-deep-targets [(results (List eng/SearchResult)) (max-depth I64)] -> (List DeepLinkTarget)
  :d "Extracts target URLs from top search results for deep crawling."
  (map (fn [(r eng/SearchResult)] -> DeepLinkTarget
         (DeepLinkTarget
           :url (.-url r)
           :parent-query (.-title r)
           :depth max-depth))
       results))
