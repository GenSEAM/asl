(module asl-registry/publish
  :d "Package Distribution & Registry Publishing Engine for AgentScript packages."
  :x [PublishSpec ReleaseArtifact PackageIndex
      createPublishSpec createReleaseArtifact indexPackageRelease formatReleaseManifest]
  :i [(regtypes :a ty) (version :a ver)])

(dfs PublishSpec
  (:f packageName Str "Package identifier e.g. asl-quantum")
  (:f targetVersion Str "Semver release version string")
  (:f entryPoint Str "Path to primary entry source file")
  (:f files (List Str) "List of distribution files included in release")
  (:f license Str "SPDX license tag"))

(dfs ReleaseArtifact
  (:f tarballName Str "Generated archive file name")
  (:f checksumSha256 Str "Hex digest of archive content")
  (:f fileCount I64 "Number of files packed")
  (:f publishedAtEpoch I64 "Timestamp of packaging"))

(dfs PackageIndex
  (:f totalPackages I64 "Total published packages in index")
  (:f releaseEntries (List Str) "Index entries in ASN format"))

(df createPublishSpec [(name Str) (v Str) (entry Str) (files (List Str))] -> PublishSpec
  :d "Constructs validated package publication specification."
  (PublishSpec
    :packageName name
    :targetVersion v
    :entryPoint entry
    :files files
    :license "MIT OR Apache-2.0"))

(df createReleaseArtifact [(spec PublishSpec) (sha Str)] -> ReleaseArtifact
  :d "Generates ReleaseArtifact metadata for published distribution tarball."
  (let [(cleanName (string-replace (.-packageName spec) "@" ""))
        (tarName (str (string-replace cleanName "/" "-") "-" (.-targetVersion spec) ".tar.gz"))]
    (ReleaseArtifact
      :tarballName tarName
      :checksumSha256 sha
      :fileCount (list-length (.-files spec))
      :publishedAtEpoch 1788700000)))

(df formatReleaseManifest [(spec PublishSpec) (artifact ReleaseArtifact)] -> Str
  :d "Generates canonical distribution release manifest in pure ASN notation."
  (str "(:release\n"
       "  :package \"" (.-packageName spec) "\"\n"
       "  :version \"" (.-targetVersion spec) "\"\n"
       "  :artifact \"" (.-tarballName artifact) "\"\n"
       "  :checksum \"" (.-checksumSha256 artifact) "\"\n"
       "  :files " (string-from-int64 (.-fileCount artifact)) "\n"
       "  :license \"" (.-license spec) "\")"))

(df indexPackageRelease [(spec PublishSpec) (idx PackageIndex)] -> PackageIndex
  :d "Appends new release entry to global registry index."
  (let [(entry (str (.-packageName spec) "@" (.-targetVersion spec)))]
    (PackageIndex
      :totalPackages (+ (.-totalPackages idx) 1)
      :releaseEntries (list-append (.-releaseEntries idx) (list entry)))))
