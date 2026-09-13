(module asl-registry/regtypes
  :d "Data structures and algebraic types for universal package registry inspection."
  :x [EcosystemKind
      makeEcoAsl makeEcoNpm makeEcoPypi makeEcoCrates makeEcoGo makeEcoGithub
      ecoToString stringToEco
      PackageSpec ReleaseItem PackageMeta OutdatedReport AslRegistryEntry]
  :i [])

(dfe EcosystemKind
  (:c ecoAsl [] "AgentScript native and Git-hosted packages")
  (:c ecoNpm [] "Node.js and npm package registry")
  (:c ecoPypi [] "Python Package Index (PyPI)")
  (:c ecoCrates [] "Rust crates.io package registry")
  (:c ecoGo [] "Go package ecosystem and proxy.golang.org")
  (:c ecoGithub [] "GitHub repositories and release assets"))

(df makeEcoAsl [] -> EcosystemKind
  :d "Constructs eco-asl case."
  (ecoAsl))

(df makeEcoNpm [] -> EcosystemKind
  :d "Constructs eco-npm case."
  (ecoNpm))

(df makeEcoPypi [] -> EcosystemKind
  :d "Constructs eco-pypi case."
  (ecoPypi))

(df makeEcoCrates [] -> EcosystemKind
  :d "Constructs eco-crates case."
  (ecoCrates))

(df makeEcoGo [] -> EcosystemKind
  :d "Constructs eco-go case."
  (ecoGo))

(df makeEcoGithub [] -> EcosystemKind
  :d "Constructs eco-github case."
  (ecoGithub))

(df ecoToString [(k EcosystemKind)] -> Str
  :d "Maps ecosystem enum case to canonical string identifier."
  (mt k
    ((ecoAsl) "asl")
    ((ecoNpm) "npm")
    ((ecoPypi) "pypi")
    ((ecoCrates) "crates")
    ((ecoGo) "go")
    ((ecoGithub) "github")))

(df stringToEco [(s Str)] -> EcosystemKind
  :d "Parses string identifier into EcosystemKind case."
  (cond
    ((or (= s "asl") (= s "agentscript")) (ecoAsl))
    ((= s "npm") (ecoNpm))
    ((= s "pypi") (ecoPypi))
    ((= s "crates") (ecoCrates))
    ((= s "go") (ecoGo))
    (:else (ecoGithub))))

(dfs PackageSpec
  (:f name Str "Target package identifier")
  (:f eco EcosystemKind "Target ecosystem registry")
  (:f versionReq Str "Requested semantic version constraint"))

(dfs ReleaseItem
  (:f version Str "Semantic version string")
  (:f releasedAt Str "ISO release timestamp or date string")
  (:f yanked Bool "Whether version was revoked or yanked"))

(dfs PackageMeta
  (:f name Str "Canonical package identifier")
  (:f eco EcosystemKind "Source ecosystem")
  (:f latestVersion Str "Current stable release version")
  (:f description Str "One-line package summary")
  (:f license Str "SPDX license expression or proprietary")
  (:f homepage Str "Homepage or documentation URI")
  (:f recentReleases (List ReleaseItem) "Recent versions history")
  (:f downloadCount I64 "Downloads or popularity score"))

(dfs OutdatedReport
  (:f packageName Str "Inspected package name")
  (:f currentVersion Str "Currently installed or declared version")
  (:f latestVersion Str "Latest upstream version")
  (:f outdated Bool "True if upstream version is newer")
  (:f severity Str "Bump degree: major, minor, patch, or current"))

(dfs AslRegistryEntry
  (:f name Str "AgentScript package name (e.g. asl-mem)")
  (:f gitRepo Str "Git repository HTTPS or SSH URI")
  (:f branch Str "Default branch (typically main)")
  (:f latestTag Str "Latest tagged release (e.g. v0.1.0)")
  (:f description Str "Package description")
  (:f capabilities (List Str) "Declared capabilities or tags"))
