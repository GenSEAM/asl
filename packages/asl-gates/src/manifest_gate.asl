(module asl-gates/manifest-gate
  :d "Pure AgentScript package manifest structure and metadata verification gate."
  :x [ManifestRecord make-manifest-record parse-package-id verify-manifest-record is-valid-pkg-name?]
  :i [])

(dfs ManifestRecord
  (:f path Str "Manifest file path")
  (:f package-name Str "Package identifier e.g. @genseam/asl-codec")
  (:f version Str "Semver version string")
  (:f entry Str "Entrypoint source file")
  (:f is-valid Bool "True if all required metadata is present"))

(df is-valid-pkg-name? [(name Str)] -> Bool
  :d "Validates that package name follows @genseam/asl-* or standard naming convention."
  (and (string-starts-with? name "@genseam/")
       (> (string-length name) 9)))

(df make-manifest-record [(path Str) (pkg-name Str) (version Str) (entry Str)] -> ManifestRecord
  (let [(valid (and (is-valid-pkg-name? pkg-name)
                    (and (> (string-length version) 0)
                         (> (string-length entry) 0))))]
    (ManifestRecord
      :path path
      :package-name pkg-name
      :version version
      :entry entry
      :is-valid valid)))

(df parse-package-id [(content Str)] -> Str
  :d "Extracts package identifier from manifest S-expression (:package <id> ...)."
  (let [(words (string-split content " "))
        (candidates (filter (fn [(w Str)] -> Bool (string-starts-with? w "@genseam/")) words))]
    (mt (list-head candidates)
      ((none) "")
      ((some cand) (string-trim cand)))))

(df verify-manifest-record [(record ManifestRecord)] -> Bool
  :d "Verifies manifest record compliance."
  (.-is-valid record))
