(module asl-registry/publish :x [PublishSpec ReleaseArtifact PackageIndex createPublishSpec createReleaseArtifact indexPackageRelease formatReleaseManifest] :i [(regtypes :a ty) (version :a ver)])

(schema PublishSpec (:f packageName Str) (:f targetVersion Str) (:f entryPoint Str) (:f files (List Str)) (:f license Str))

(schema ReleaseArtifact (:f tarballName Str) (:f checksumSha256 Str) (:f fileCount I64) (:f publishedAtEpoch I64))

(schema PackageIndex (:f totalPackages I64) (:f releaseEntries (List Str)))

fn createPublishSpec name: Str v: Str entry: Str files: (List Str) -> PublishSpec
  (PublishSpec :packageName name :targetVersion v :entryPoint entry :files files :license "MIT OR Apache-2.0")

fn createReleaseArtifact spec: PublishSpec sha: Str -> ReleaseArtifact
  (let [(cleanName (stringReplace spec.packageName "@" "")) (tarName (str (stringReplace cleanName "/" "-") "-" spec.targetVersion ".tar.gz"))] (ReleaseArtifact :tarballName tarName :checksumSha256 sha :fileCount (listLength spec.files) :publishedAtEpoch 1788700000))

fn formatReleaseManifest spec: PublishSpec artifact: ReleaseArtifact -> Str
  (str "(:release\n" "  :package \"" spec.packageName "\"\n" "  :version \"" spec.targetVersion "\"\n" "  :artifact \"" artifact.tarballName "\"\n" "  :checksum \"" artifact.checksumSha256 "\"\n" "  :files " (stringFromInt64 artifact.fileCount) "\n" "  :license \"" spec.license "\")")

fn indexPackageRelease spec: PublishSpec idx: PackageIndex -> PackageIndex
  (let [(entry (str spec.packageName "@" spec.targetVersion))] (PackageIndex :totalPackages (+ idx.totalPackages 1) :releaseEntries (listAppend idx.releaseEntries (list entry))))
