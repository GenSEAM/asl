(module asl-registry/tests/publishTest :x [testCreateSpec testCreateArtifact testFormatManifest testIndexRelease runTests] :i [(publish :a pub)])

fn testCreateSpec -> Bool
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn" "src/circuit.asl")))] (assert (= spec.packageName "asl-quantum") "package-name") (assert (= spec.targetVersion "0.1.0") "target-version") (assert (= (listLength spec.files) 2) "files count") true)

fn testCreateArtifact -> Bool
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn"))) (artifact (pub/createReleaseArtifact spec "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))] (assert (= artifact.tarballName "asl-quantum-0.1.0.tar.gz") "tarball name") (assert (= artifact.fileCount 1) "file count") true)

fn testFormatManifest -> Bool
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn"))) (artifact (pub/createReleaseArtifact spec "sha256-mock")) (manifest (pub/formatReleaseManifest spec artifact))] (assert (stringContains? manifest "(:release") "release header") (assert (stringContains? manifest "asl-quantum") "package name") (assert (stringContains? manifest "0.1.0") "version") true)

fn testIndexRelease -> Bool
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn"))) (idx (pub/PackageIndex :totalPackages 0 :releaseEntries (list))) (updated (pub/indexPackageRelease spec idx))] (assert (= updated.totalPackages 1) "total packages 1") (assert (= (listLength updated.releaseEntries) 1) "release entries 1") true)

fn runTests -> Bool
  (do (assert (testCreateSpec) "test-create-spec must pass") (assert (testCreateArtifact) "test-create-artifact must pass") (assert (testFormatManifest) "test-format-manifest must pass") (assert (testIndexRelease) "test-index-release must pass") true)
