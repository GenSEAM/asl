(module asl-registry/endpoints
  :d "URL and HTTP request header builders for multi-ecosystem package registries."
  :x [build-package-url build-search-url build-headers default-asl-catalog-url]
  :i [(regtypes :a ty)])

(df default-asl-catalog-url [] -> Str
  :d "Returns canonical URI for the Git-native AgentScript package catalog index."
  "https://raw.githubusercontent.com/GenSEAM/asl/main/registry.asn")

(df build-package-url [(eco ty/EcosystemKind) (pkg-name Str)] -> Str
  :d "Constructs exact metadata API endpoint for a package in target registry."
  (mt eco
    ((ty/eco-asl)
     (str "https://api.github.com/repos/" pkg-name "/releases?per_page=5"))
    ((ty/eco-npm)
     (str "https://registry.npmjs.org/" pkg-name))
    ((ty/eco-pypi)
     (str "https://pypi.org/pypi/" pkg-name "/json"))
    ((ty/eco-crates)
     (str "https://crates.io/api/v1/crates/" pkg-name))
    ((ty/eco-go)
     (str "https://proxy.golang.org/" pkg-name "/@latest"))
    ((ty/eco-github)
     (str "https://api.github.com/repos/" pkg-name "/releases?per_page=5"))))

(df build-search-url [(eco ty/EcosystemKind) (query Str) (limit I64)] -> Str
  :d "Constructs search endpoint for finding packages matching a text query."
  (let [(clean-q (string-replace query " " "+"))
        (lim-str (string-from-int64 limit))]
    (mt eco
      ((ty/eco-asl)
       (str "https://api.github.com/search/repositories?q=" clean-q "+topic:asl-package&per_page=" lim-str))
      ((ty/eco-npm)
       (str "https://registry.npmjs.org/-/v1/search?text=" clean-q "&size=" lim-str))
      ((ty/eco-pypi)
       (str "https://pypi.org/search/?q=" clean-q))
      ((ty/eco-crates)
       (str "https://crates.io/api/v1/crates?q=" clean-q "&per_page=" lim-str))
      ((ty/eco-go)
       (str "https://pkg.go.dev/search?q=" clean-q))
      ((ty/eco-github)
       (str "https://api.github.com/search/repositories?q=" clean-q "&per_page=" lim-str)))))

(df build-headers [(eco ty/EcosystemKind)] -> (List (Pair Str Str))
  :d "Constructs HTTP header list with user agents and registry-appropriate content negotiation."
  (let [(std-ua (pair "User-Agent" "ASL-Registry/0.3.0 (+https://aslang.dev)"))]
    (mt eco
      ((ty/eco-npm)
       (list std-ua (pair "Accept" "application/vnd.npm.install-v1+json")))
      ((ty/eco-github)
       (list std-ua (pair "Accept" "application/vnd.github.v3+json")))
      ((ty/eco-asl)
       (list std-ua (pair "Accept" "application/vnd.github.v3+json")))
      (_
       (list std-ua (pair "Accept" "application/json"))))))
