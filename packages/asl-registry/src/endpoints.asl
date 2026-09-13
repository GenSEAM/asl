(module asl-registry/endpoints
  :d "URL and HTTP request header builders for multi-ecosystem package registries."
  :x [buildPackageUrl buildSearchUrl buildHeaders defaultAslCatalogUrl]
  :i [(regtypes :a ty)])

(df defaultAslCatalogUrl [] -> Str
  :d "Returns canonical URI for the Git-native AgentScript package catalog index."
  "https://raw.githubusercontent.com/GenSEAM/asl/main/registry.asn")

(df buildPackageUrl [(eco ty/EcosystemKind) (pkgName Str)] -> Str
  :d "Constructs exact metadata API endpoint for a package in target registry."
  (mt eco
    ((ty/ecoAsl)
     (str "https://api.github.com/repos/" pkgName "/releases?per_page=5"))
    ((ty/ecoNpm)
     (str "https://registry.npmjs.org/" pkgName))
    ((ty/ecoPypi)
     (str "https://pypi.org/pypi/" pkgName "/json"))
    ((ty/ecoCrates)
     (str "https://crates.io/api/v1/crates/" pkgName))
    ((ty/ecoGo)
     (str "https://proxy.golang.org/" pkgName "/@latest"))
    ((ty/ecoGithub)
     (str "https://api.github.com/repos/" pkgName "/releases?per_page=5"))))

(df buildSearchUrl [(eco ty/EcosystemKind) (query Str) (limit I64)] -> Str
  :d "Constructs search endpoint for finding packages matching a text query."
  (let [(cleanQ (string-replace query " " "+"))
        (limStr (string-from-int64 limit))]
    (mt eco
      ((ty/ecoAsl)
       (str "https://api.github.com/search/repositories?q=" cleanQ "+topic:asl-package&per_page=" limStr))
      ((ty/ecoNpm)
       (str "https://registry.npmjs.org/-/v1/search?text=" cleanQ "&size=" limStr))
      ((ty/ecoPypi)
       (str "https://pypi.org/search/?q=" cleanQ))
      ((ty/ecoCrates)
       (str "https://crates.io/api/v1/crates?q=" cleanQ "&per_page=" limStr))
      ((ty/ecoGo)
       (str "https://pkg.go.dev/search?q=" cleanQ))
      ((ty/ecoGithub)
       (str "https://api.github.com/search/repositories?q=" cleanQ "&per_page=" limStr)))))

(df buildHeaders [(eco ty/EcosystemKind)] -> (List (Pair Str Str))
  :d "Constructs HTTP header list with user agents and registry-appropriate content negotiation."
  (let [(stdUa (pair "User-Agent" "ASL-Registry/0.1.0 (+https://aslang.dev)"))]
    (mt eco
      ((ty/ecoNpm)
       (list stdUa (pair "Accept" "application/vnd.npm.install-v1+json")))
      ((ty/ecoGithub)
       (list stdUa (pair "Accept" "application/vnd.github.v3+json")))
      ((ty/ecoAsl)
       (list stdUa (pair "Accept" "application/vnd.github.v3+json")))
      (_
       (list stdUa (pair "Accept" "application/json"))))))
