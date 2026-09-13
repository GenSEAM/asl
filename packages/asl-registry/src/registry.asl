(module asl-registry/registry
  :d "Universal Multi-Ecosystem Package Registry & Git-Native Dependency Inspector."
  :x [parsePackageSpecifier formatPackageSummary formatOutdatedReport
      formatAslRegistryTable resolveGitCloneCmd checkPackageOutdated
      makePackageInfo]
  :i [(regtypes :a ty) (endpoints :a ep) (version :a ver)])

(df parsePackageSpecifier [(spec Str)] -> ty/PackageSpec
  :d "Parses specifiers like 'npm:kysely@^0.27.0', 'pypi:requests', or 'serde@1.0'."
  (let [(parts (string-split spec ":"))]
    (if (> (list-length parts) 1)
        (let [(ecoStr (option-or (list-get parts 0) "github"))
              (eco (ty/stringToEco ecoStr))
              (rem (option-or (list-get parts 1) ""))
              (nameParts (string-split rem "@"))
              (name (option-or (list-get nameParts 0) rem))
              (verReq (if (> (list-length nameParts) 1)
                           (option-or (list-get nameParts 1) "*")
                           "*"))]
          (ty/PackageSpec :name name :eco eco :versionReq verReq))
        (let [(nameParts (string-split spec "@"))
              (name (option-or (list-get nameParts 0) spec))
              (verReq (if (> (list-length nameParts) 1)
                           (option-or (list-get nameParts 1) "*")
                           "*"))]
          (ty/PackageSpec :name name :eco (ty/makeEcoAsl) :versionReq verReq)))))

(df makePackageInfo [(name Str) (eco ty/EcosystemKind) (latest Str) (desc Str) (lic Str)] -> ty/PackageMeta
  :d "Constructs a PackageMeta instance with empty recent releases list."
  (ty/PackageMeta
    :name name
    :eco eco
    :latestVersion latest
    :description desc
    :license lic
    :homepage (str "https://github.com/" name)
    :recentReleases (list)
    :downloadCount 0))

(df checkPackageOutdated [(meta ty/PackageMeta) (currentV Str)] -> ty/OutdatedReport
  :d "Checks if declared version is behind registry latest version."
  (ver/evaluateOutdated (.-name meta) currentV (.-latestVersion meta)))

(df formatPackageSummary [(m ty/PackageMeta)] -> Str
  :d "Formats concise package summary for terminal and LLM agent consumption."
  (str "[PKG] " (.-name m) " [" (ty/ecoToString (.-eco m)) "]\n"
       "   Latest:  v" (.-latestVersion m) "\n"
       "   License: " (.-license m) "\n"
       "   Summary: " (.-description m) "\n"
       "   URL:     " (.-homepage m)))

(df formatOutdatedReport [(r ty/OutdatedReport)] -> Str
  :d "Formats outdated status with severity emoji."
  (if (.-outdated r)
      (str "[WARN] " (.-packageName r) ": " (.-currentVersion r) " -> "
           (.-latestVersion r) " (" (.-severity r) " update available)")
      (str "[OK] " (.-packageName r) ": " (.-currentVersion r) " is up-to-date")))

(df resolveGitCloneCmd [(entry ty/AslRegistryEntry)] -> Str
  :d "Constructs shallow Git clone command for targeted ASL package version."
  (str "git clone --depth 1 --branch " (.-latestTag entry) " "
       (.-gitRepo entry) " packages/" (.-name entry)))

(df formatAslRegistryTable [(entries (List ty/AslRegistryEntry))] -> Str
  :d "Renders tabular catalog of Git-native AgentScript packages."
  (let [(header "=== AgentScript Git-Native Package Registry ===\nNAME                     VERSION   REPOSITORY\n------------------------------------------------------------------\n")
        (lines (map (fn [(e ty/AslRegistryEntry)] -> Str
                      (str (.-name e) "  v" (.-latestTag e) "  " (.-gitRepo e)))
                    entries))]
    (str header (string-join lines "\n"))))
