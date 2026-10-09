(module asl-registry/registry :x [parsePackageSpecifier formatPackageSummary formatOutdatedReport formatAslRegistryTable resolveGitCloneCmd checkPackageOutdated makePackageInfo] :i [(regtypes :a ty) (endpoints :a ep) (version :a ver)])

fn parsePackageSpecifier spec: Str -> ty/PackageSpec
  (let [(parts (stringSplit spec ":"))] (if (> (listLength parts) 1) (let [(ecoStr (optionOr (listGet parts 0) "github")) (eco (ty/stringToEco ecoStr)) (rem (optionOr (listGet parts 1) "")) (nameParts (stringSplit rem "@")) (name (optionOr (listGet nameParts 0) rem)) (verReq (if (> (listLength nameParts) 1) (optionOr (listGet nameParts 1) "*") "*"))] (ty/PackageSpec :name name :eco eco :versionReq verReq)) (let [(nameParts (stringSplit spec "@")) (name (optionOr (listGet nameParts 0) spec)) (verReq (if (> (listLength nameParts) 1) (optionOr (listGet nameParts 1) "*") "*"))] (ty/PackageSpec :name name :eco (ty/makeEcoAsl) :versionReq verReq))))

fn makePackageInfo name: Str eco: ty/EcosystemKind latest: Str desc: Str lic: Str -> ty/PackageMeta
  (ty/PackageMeta :name name :eco eco :latestVersion latest :description desc :license lic :homepage (str "https://github.com/" name) :recentReleases (list) :downloadCount 0)

fn checkPackageOutdated meta: ty/PackageMeta currentV: Str -> ty/OutdatedReport
  (ver/evaluateOutdated meta.name currentV meta.latestVersion)

fn formatPackageSummary m: ty/PackageMeta -> Str
  (str "[PKG] " m.name " [" (ty/ecoToString m.eco) "]\n" "   Latest:  v" m.latestVersion "\n" "   License: " m.license "\n" "   Summary: " m.description "\n" "   URL:     " m.homepage)

fn formatOutdatedReport r: ty/OutdatedReport -> Str
  (if r.outdated (str "[WARN] " r.packageName ": " r.currentVersion " -> " r.latestVersion " (" r.severity " update available)") (str "[OK] " r.packageName ": " r.currentVersion " is up-to-date"))

fn resolveGitCloneCmd entry: ty/AslRegistryEntry -> Str
  (str "git clone --depth 1 --branch " entry.latestTag " " entry.gitRepo " packages/" entry.name)

fn formatAslRegistryTable entries: (List ty/AslRegistryEntry) -> Str
  (let [(header "=== AgentScript Git-Native Package Registry ===\nNAME                     VERSION   REPOSITORY\n------------------------------------------------------------------\n") (lines (map (fn [(e ty/AslRegistryEntry)] -> Str (str e.name "  v" e.latestTag "  " e.gitRepo)) entries))] (str header (stringJoin lines "\n")))
