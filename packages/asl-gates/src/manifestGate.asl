(module asl-gates/manifestGate
  :d "Pure AgentScript package manifest structure and metadata verification gate."
  :x [ManifestRecord makeManifestRecord parsePackageId verifyManifestRecord isValidPkgName?]
  :i [])

(dfs ManifestRecord
  (:f path Str "Manifest file path")
  (:f packageName Str "Package identifier e.g. asl-codec")
  (:f version Str "Semver version string")
  (:f entry Str "Entrypoint source file")
  (:f isValid Bool "True if all required metadata is present"))

(df isValidPkgName? [(name Str)] -> Bool
  :d "Validates that package name follows native ASL naming convention without sigils."
  (and (not (string-contains? name "@"))
       (> (string-length name) 2)))

(df makeManifestRecord [(path Str) (pkgName Str) (version Str) (entry Str)] -> ManifestRecord
  (let [(valid (and (isValidPkgName? pkgName)
                    (and (> (string-length version) 0)
                         (> (string-length entry) 0))))]
    (ManifestRecord
      :path path
      :packageName pkgName
      :version version
      :entry entry
      :isValid valid)))

(df parsePackageId [(content Str)] -> Str
  :d "Extracts package identifier from manifest S-expression (:package <id> ...)."
  (let [(trimmed (string-trim content))]
    (if (string-starts-with? trimmed "(:package")
        (let [(after (string-trim (option-or (string-slice trimmed 9 (string-length trimmed)) "")))
              (words (string-split after " "))]
          (string-trim (option-or (list-head words) "")))
        "")))

(df verifyManifestRecord [(record ManifestRecord)] -> Bool
  :d "Verifies manifest record compliance."
  (.-isValid record))
