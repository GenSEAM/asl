(module aslWebApiSearch/ecosystems :x [PackageInfo PackageEcosystem DeepLinkTarget buildEcosystemUrl buildPackageCurlCmd formatPackageMarkdown formatEcosystemRag createDeepTargets] :i [(engine :a eng)])

(schema PackageInfo (:f name Str) (:f ecosystem Str) (:f version Str) (:f description Str) (:f repoUrl Str) (:f popularity I64))

(enum PackageEcosystem (:c npm [] "Node/npm ecosystem") (:c pypi [] "Python/PyPI ecosystem") (:c crates [] "Rust/crates.io ecosystem") (:c go [] "Go packages ecosystem") (:c github [] "GitHub repositories") (:c clib [] "C/C++ systems libraries"))

(schema DeepLinkTarget (:f url Str) (:f parentQuery Str) (:f depth I64))

fn buildEcosystemUrl eco: Str query: Str limit: I64 -> Str
  (let [(q1 (stringReplace query "%" "%25")) (q2 (stringReplace q1 " " "+")) (q3 (stringReplace q2 "&" "%26")) (q4 (stringReplace q3 "?" "%3F")) (q5 (stringReplace q4 "#" "%23")) (q6 (stringReplace q5 "/" "%2F")) (cleanQ q6) (limStr (stringFromInt64 limit))] (cond ((= eco "npm") (str "https://registry.npmjs.org/-/v1/search?text=" cleanQ "&size=" limStr)) ((= eco "crates") (str "https://crates.io/api/v1/crates?q=" cleanQ "&per_page=" limStr)) ((= eco "pypi") (str "https://pypi.org/search/?q=" cleanQ)) ((= eco "go") (str "https://pkg.go.dev/search?q=" cleanQ)) ((= eco "c") (str "https://api.github.com/search/repositories?q=" cleanQ "+language:C&per_page=" limStr)) (else (str "https://api.github.com/search/repositories?q=" cleanQ "&per_page=" limStr))))

fn buildPackageCurlCmd eco: Str query: Str limit: I64 -> eng/CurlCommand
  (let [(url (buildEcosystemUrl eco query limit)) (ua (cond ((= eco "crates") "ASL-AgentSearch/1.0 (https://aslang.dev)") ((= eco "github") "ASL-AgentSearch/1.0") (else "Mozilla/5.0 (ASL-Agent/1.0)"))) (headers (cond ((= eco "npm") (list "-H" "Accept: application/json" "-H" (str "User-Agent: " ua))) ((= eco "github") (list "-H" "Accept: application/vnd.github.v3+json" "-H" (str "User-Agent: " ua))) (else (list "-H" (str "User-Agent: " ua)))))] (eng/CurlCommand :bin "curl" :args (listAppend (list "-s" "--max-time" "5") (listAppend headers (list "--" url))) :url url))

fn formatPackageMarkdown pkg: PackageInfo -> Str
  (str "**[" pkg.name "](" pkg.repoUrl ")**  `[" pkg.ecosystem " - v" pkg.version "]` (stars/dl: " (stringFromInt64 pkg.popularity) ")\n   " pkg.description "\n")

fn formatEcosystemRag query: Str packages: (List PackageInfo) -> Str
  (let [(header (str "## Ecosystem Packages for: '" query "' (" (stringFromInt64 (listLength packages)) " packages)\n\n")) (rows (map formatPackageMarkdown packages))] (str header (stringJoin rows "\n")))

fn createDeepTargets results: (List eng/SearchResult) maxDepth: I64 -> (List DeepLinkTarget)
  (map (fn [(r eng/SearchResult)] -> DeepLinkTarget (DeepLinkTarget :url r.url :parentQuery r.title :depth maxDepth)) results)
