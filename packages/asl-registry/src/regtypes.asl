(module asl-registry/regtypes
  :d "Data structures and algebraic types for universal package registry inspection."
  :x [EcosystemKind
      make-eco-asl make-eco-npm make-eco-pypi make-eco-crates make-eco-go make-eco-github
      eco-to-string string-to-eco
      PackageSpec ReleaseItem PackageMeta OutdatedReport AslRegistryEntry]
  :i [])

(dfe EcosystemKind
  (:c eco-asl [] "AgentScript native and Git-hosted packages")
  (:c eco-npm [] "Node.js and npm package registry")
  (:c eco-pypi [] "Python Package Index (PyPI)")
  (:c eco-crates [] "Rust crates.io package registry")
  (:c eco-go [] "Go package ecosystem and proxy.golang.org")
  (:c eco-github [] "GitHub repositories and release assets"))

(df make-eco-asl [] -> EcosystemKind
  :d "Constructs eco-asl case."
  (eco-asl))

(df make-eco-npm [] -> EcosystemKind
  :d "Constructs eco-npm case."
  (eco-npm))

(df make-eco-pypi [] -> EcosystemKind
  :d "Constructs eco-pypi case."
  (eco-pypi))

(df make-eco-crates [] -> EcosystemKind
  :d "Constructs eco-crates case."
  (eco-crates))

(df make-eco-go [] -> EcosystemKind
  :d "Constructs eco-go case."
  (eco-go))

(df make-eco-github [] -> EcosystemKind
  :d "Constructs eco-github case."
  (eco-github))

(df eco-to-string [(k EcosystemKind)] -> Str
  :d "Maps ecosystem enum case to canonical string identifier."
  (mt k
    ((eco-asl) "asl")
    ((eco-npm) "npm")
    ((eco-pypi) "pypi")
    ((eco-crates) "crates")
    ((eco-go) "go")
    ((eco-github) "github")))

(df string-to-eco [(s Str)] -> EcosystemKind
  :d "Parses string identifier into EcosystemKind case."
  (cond
    ((or (= s "asl") (= s "agentscript")) (eco-asl))
    ((= s "npm") (eco-npm))
    ((= s "pypi") (eco-pypi))
    ((= s "crates") (eco-crates))
    ((= s "go") (eco-go))
    (:else (eco-github))))

(dfs PackageSpec
  (:f name Str "Target package identifier")
  (:f eco EcosystemKind "Target ecosystem registry")
  (:f version-req Str "Requested semantic version constraint"))

(dfs ReleaseItem
  (:f version Str "Semantic version string")
  (:f released-at Str "ISO release timestamp or date string")
  (:f yanked Bool "Whether version was revoked or yanked"))

(dfs PackageMeta
  (:f name Str "Canonical package identifier")
  (:f eco EcosystemKind "Source ecosystem")
  (:f latest-version Str "Current stable release version")
  (:f description Str "One-line package summary")
  (:f license Str "SPDX license expression or proprietary")
  (:f homepage Str "Homepage or documentation URI")
  (:f recent-releases (List ReleaseItem) "Recent versions history")
  (:f download-count I64 "Downloads or popularity score"))

(dfs OutdatedReport
  (:f package-name Str "Inspected package name")
  (:f current-version Str "Currently installed or declared version")
  (:f latest-version Str "Latest upstream version")
  (:f outdated Bool "True if upstream version is newer")
  (:f severity Str "Bump degree: major, minor, patch, or current"))

(dfs AslRegistryEntry
  (:f name Str "AgentScript package name (e.g. @genseam/asl-mem)")
  (:f git-repo Str "Git repository HTTPS or SSH URI")
  (:f branch Str "Default branch (typically main)")
  (:f latest-tag Str "Latest tagged release (e.g. v0.3.0)")
  (:f description Str "Package description")
  (:f capabilities (List Str) "Declared capabilities or tags"))
