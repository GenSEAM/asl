(module asl-registry/endpoints :x [buildPackageUrl buildSearchUrl buildHeaders defaultAslCatalogUrl] :i [(regtypes :a ty)])

fn defaultAslCatalogUrl -> Str
  "https://raw.githubusercontent.com/GenSEAM/asl/main/registry.asn"

fn buildPackageUrl eco: ty/EcosystemKind pkgName: Str -> Str
  (mt eco ((ty/ecoAsl) (str "https://api.github.com/repos/" pkgName "/releases?per_page=5")) ((ty/ecoNpm) (str "https://registry.npmjs.org/" pkgName)) ((ty/ecoPypi) (str "https://pypi.org/pypi/" pkgName "/json")) ((ty/ecoCrates) (str "https://crates.io/api/v1/crates/" pkgName)) ((ty/ecoGo) (str "https://proxy.golang.org/" pkgName "/@latest")) ((ty/ecoGithub) (str "https://api.github.com/repos/" pkgName "/releases?per_page=5")))

fn buildSearchUrl eco: ty/EcosystemKind query: Str limit: I64 -> Str
  (let [(cleanQ (stringReplace query " " "+")) (limStr (stringFromInt64 limit))] (mt eco ((ty/ecoAsl) (str "https://api.github.com/search/repositories?q=" cleanQ "+topic:asl-package&per_page=" limStr)) ((ty/ecoNpm) (str "https://registry.npmjs.org/-/v1/search?text=" cleanQ "&size=" limStr)) ((ty/ecoPypi) (str "https://pypi.org/search/?q=" cleanQ)) ((ty/ecoCrates) (str "https://crates.io/api/v1/crates?q=" cleanQ "&per_page=" limStr)) ((ty/ecoGo) (str "https://pkg.go.dev/search?q=" cleanQ)) ((ty/ecoGithub) (str "https://api.github.com/search/repositories?q=" cleanQ "&per_page=" limStr))))

fn buildHeaders eco: ty/EcosystemKind -> (List (Pair Str Str))
  (let [(stdUa (pair "User-Agent" "ASL-Registry/0.1.0 (+https://aslang.dev)"))] (mt eco ((ty/ecoNpm) (list stdUa (pair "Accept" "application/vnd.npm.install-v1+json"))) ((ty/ecoGithub) (list stdUa (pair "Accept" "application/vnd.github.v3+json"))) ((ty/ecoAsl) (list stdUa (pair "Accept" "application/vnd.github.v3+json"))) (_ (list stdUa (pair "Accept" "application/json")))))
