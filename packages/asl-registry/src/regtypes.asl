(module asl-registry/regtypes :x [EcosystemKind makeEcoAsl makeEcoNpm makeEcoPypi makeEcoCrates makeEcoGo makeEcoGithub ecoToString stringToEco PackageSpec ReleaseItem PackageMeta OutdatedReport AslRegistryEntry] :i [])

(enum EcosystemKind (:c ecoAsl [] "AgentScript native and Git-hosted packages") (:c ecoNpm [] "Node.js and npm package registry") (:c ecoPypi [] "Python Package Index (PyPI)") (:c ecoCrates [] "Rust crates.io package registry") (:c ecoGo [] "Go package ecosystem and proxy.golang.org") (:c ecoGithub [] "GitHub repositories and release assets"))

fn makeEcoAsl -> EcosystemKind
  (ecoAsl)

fn makeEcoNpm -> EcosystemKind
  (ecoNpm)

fn makeEcoPypi -> EcosystemKind
  (ecoPypi)

fn makeEcoCrates -> EcosystemKind
  (ecoCrates)

fn makeEcoGo -> EcosystemKind
  (ecoGo)

fn makeEcoGithub -> EcosystemKind
  (ecoGithub)

fn ecoToString k: EcosystemKind -> Str
  (mt k ((ecoAsl) "asl") ((ecoNpm) "npm") ((ecoPypi) "pypi") ((ecoCrates) "crates") ((ecoGo) "go") ((ecoGithub) "github"))

fn stringToEco s: Str -> EcosystemKind
  (cond ((or (= s "asl") (= s "agentscript")) (ecoAsl)) ((= s "npm") (ecoNpm)) ((= s "pypi") (ecoPypi)) ((= s "crates") (ecoCrates)) ((= s "go") (ecoGo)) (else (ecoGithub)))

(schema PackageSpec (:f name Str) (:f eco EcosystemKind) (:f versionReq Str))

(schema ReleaseItem (:f version Str) (:f releasedAt Str) (:f yanked Bool))

(schema PackageMeta (:f name Str) (:f eco EcosystemKind) (:f latestVersion Str) (:f description Str) (:f license Str) (:f homepage Str) (:f recentReleases (List ReleaseItem)) (:f downloadCount I64))

(schema OutdatedReport (:f packageName Str) (:f currentVersion Str) (:f latestVersion Str) (:f outdated Bool) (:f severity Str))

(schema AslRegistryEntry (:f name Str) (:f gitRepo Str) (:f branch Str) (:f latestTag Str) (:f description Str) (:f capabilities (List Str)))
