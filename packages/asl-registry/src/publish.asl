(module asl-registry/publish
  :d "Package Distribution & Registry Publishing Engine for AgentScript packages."
  :x [PublishSpec ReleaseArtifact PackageIndex
      create-publish-spec create-release-artifact index-package-release format-release-manifest]
  :i [(regtypes :a ty) (version :a ver)])

(dfs PublishSpec
  (:f package-name Str "Package identifier e.g. asl-quantum")
  (:f target-version Str "Semver release version string")
  (:f entry-point Str "Path to primary entry source file")
  (:f files (List Str) "List of distribution files included in release")
  (:f license Str "SPDX license tag"))

(dfs ReleaseArtifact
  (:f tarball-name Str "Generated archive file name")
  (:f checksum-sha256 Str "Hex digest of archive content")
  (:f file-count I64 "Number of files packed")
  (:f published-at-epoch I64 "Timestamp of packaging"))

(dfs PackageIndex
  (:f total-packages I64 "Total published packages in index")
  (:f release-entries (List Str) "Index entries in ASN format"))

(df create-publish-spec [(name Str) (v Str) (entry Str) (files (List Str))] -> PublishSpec
  :d "Constructs validated package publication specification."
  (PublishSpec
    :package-name name
    :target-version v
    :entry-point entry
    :files files
    :license "MIT OR Apache-2.0"))

(df create-release-artifact [(spec PublishSpec) (sha Str)] -> ReleaseArtifact
  :d "Generates ReleaseArtifact metadata for published distribution tarball."
  (let [(clean-name (string-replace (.-package-name spec) "@" ""))
        (tar-name (str (string-replace clean-name "/" "-") "-" (.-target-version spec) ".tar.gz"))]
    (ReleaseArtifact
      :tarball-name tar-name
      :checksum-sha256 sha
      :file-count (list-length (.-files spec))
      :published-at-epoch 1788700000)))

(df format-release-manifest [(spec PublishSpec) (artifact ReleaseArtifact)] -> Str
  :d "Generates canonical distribution release manifest in pure ASN notation."
  (str "(:release\n"
       "  :package \"" (.-package-name spec) "\"\n"
       "  :version \"" (.-target-version spec) "\"\n"
       "  :artifact \"" (.-tarball-name artifact) "\"\n"
       "  :checksum \"" (.-checksum-sha256 artifact) "\"\n"
       "  :files " (string-from-int64 (.-file-count artifact)) "\n"
       "  :license \"" (.-license spec) "\")"))

(df index-package-release [(spec PublishSpec) (idx PackageIndex)] -> PackageIndex
  :d "Appends new release entry to global registry index."
  (let [(entry (str (.-package-name spec) "@" (.-target-version spec)))]
    (PackageIndex
      :total-packages (+ (.-total-packages idx) 1)
      :release-entries (list-append (.-release-entries idx) (list entry)))))
