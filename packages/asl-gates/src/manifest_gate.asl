(module asl-gates/manifest-gate
  :d "Pure AgentScript package manifest structure and metadata verification gate."
  :x [ManifestRecord make-manifest-record parse-package-id verify-manifest-record is-valid-pkg-name?]
  :i [])

(dfs ManifestRecord
  (:f path Str "Manifest file path")
  (:f package-name Str "Package identifier e.g. asl-codec")
  (:f version Str "Semver version string")
  (:f entry Str "Entrypoint source file")
  (:f is-valid Bool "True if all required metadata is present"))

(df is-valid-pkg-name? [(name Str)] -> Bool
  :d "Validates that package name follows native ASL naming convention without sigils."
  (and (not (string-contains? name "@"))
       (> (string-length name) 2)))

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
  (let [(trimmed (string-trim content))]
    (if (string-starts-with? trimmed "(:package")
        (let [(after (string-trim (option-or (string-slice trimmed 9 (string-length trimmed)) "")))
              (words (string-split after " "))]
          (string-trim (option-or (list-head words) "")))
        "")))

(df verify-manifest-record [(record ManifestRecord)] -> Bool
  :d "Verifies manifest record compliance."
  (.-is-valid record))
