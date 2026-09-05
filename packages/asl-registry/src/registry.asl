(module asl-registry/registry
  :d "Universal Multi-Ecosystem Package Registry & Git-Native Dependency Inspector."
  :x [parse-package-specifier format-package-summary format-outdated-report
      format-asl-registry-table resolve-git-clone-cmd check-package-outdated
      make-package-info]
  :i [(regtypes :a ty) (endpoints :a ep) (version :a ver)])

(df parse-package-specifier [(spec Str)] -> ty/PackageSpec
  :d "Parses specifiers like 'npm:kysely@^0.27.0', 'pypi:requests', or 'serde@1.0'."
  (let [(parts (string-split spec ":"))]
    (if (> (list-length parts) 1)
        (let [(eco-str (option-or (list-get parts 0) "github"))
              (eco (ty/string-to-eco eco-str))
              (rem (option-or (list-get parts 1) ""))
              (name-parts (string-split rem "@"))
              (name (option-or (list-get name-parts 0) rem))
              (ver-req (if (> (list-length name-parts) 1)
                           (option-or (list-get name-parts 1) "*")
                           "*"))]
          (ty/PackageSpec :name name :eco eco :version-req ver-req))
        (let [(name-parts (string-split spec "@"))
              (name (option-or (list-get name-parts 0) spec))
              (ver-req (if (> (list-length name-parts) 1)
                           (option-or (list-get name-parts 1) "*")
                           "*"))]
          (ty/PackageSpec :name name :eco (ty/make-eco-asl) :version-req ver-req)))))

(df make-package-info [(name Str) (eco ty/EcosystemKind) (latest Str) (desc Str) (lic Str)] -> ty/PackageMeta
  :d "Constructs a PackageMeta instance with empty recent releases list."
  (ty/PackageMeta
    :name name
    :eco eco
    :latest-version latest
    :description desc
    :license lic
    :homepage (str "https://github.com/" name)
    :recent-releases (list)
    :download-count 0))

(df check-package-outdated [(meta ty/PackageMeta) (current-v Str)] -> ty/OutdatedReport
  :d "Checks if declared version is behind registry latest version."
  (ver/evaluate-outdated (.-name meta) current-v (.-latest-version meta)))

(df format-package-summary [(m ty/PackageMeta)] -> Str
  :d "Formats concise package summary for terminal and LLM agent consumption."
  (str "📦 " (.-name m) " [" (ty/eco-to-string (.-eco m)) "]\n"
       "   Latest:  v" (.-latest-version m) "\n"
       "   License: " (.-license m) "\n"
       "   Summary: " (.-description m) "\n"
       "   URL:     " (.-homepage m)))

(df format-outdated-report [(r ty/OutdatedReport)] -> Str
  :d "Formats outdated status with severity emoji."
  (if (.-outdated r)
      (str "⚠️  " (.-package-name r) ": " (.-current-version r) " -> "
           (.-latest-version r) " (" (.-severity r) " update available)")
      (str "✓  " (.-package-name r) ": " (.-current-version r) " is up-to-date")))

(df resolve-git-clone-cmd [(entry ty/AslRegistryEntry)] -> Str
  :d "Constructs shallow Git clone command for targeted ASL package version."
  (str "git clone --depth 1 --branch " (.-latest-tag entry) " "
       (.-git-repo entry) " packages/" (.-name entry)))

(df format-asl-registry-table [(entries (List ty/AslRegistryEntry))] -> Str
  :d "Renders tabular catalog of Git-native AgentScript packages."
  (let [(header "=== AgentScript Git-Native Package Registry ===\nNAME                     VERSION   REPOSITORY\n------------------------------------------------------------------\n")
        (lines (map (fn [(e ty/AslRegistryEntry)] -> Str
                      (str (.-name e) "  v" (.-latest-tag e) "  " (.-git-repo e)))
                    entries))]
    (str header (string-join lines "\n"))))
