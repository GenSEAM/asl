(module asl-registry/tests/publishTest
  :d "Unit tests for package publishing, distribution tarball metadata, and registry indexing."
  :x [testCreateSpec testCreateArtifact testFormatManifest testIndexRelease runTests]
  :i [(publish :a pub)])

(df testCreateSpec [] -> Bool
  :d "Verifies construction of package publication specification."
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn" "src/circuit.asl")))]
    (assert (= (.-packageName spec) "asl-quantum") "package-name")
    (assert (= (.-targetVersion spec) "0.1.0") "target-version")
    (assert (= (list-length (.-files spec)) 2) "files count")
    true))

(df testCreateArtifact [] -> Bool
  :d "Verifies release artifact tarball naming and checksum assignment."
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/createReleaseArtifact spec "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))]
    (assert (= (.-tarballName artifact) "asl-quantum-0.1.0.tar.gz") "tarball name")
    (assert (= (.-fileCount artifact) 1) "file count")
    true))

(df testFormatManifest [] -> Bool
  :d "Verifies release manifest generation in canonical ASN format."
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/createReleaseArtifact spec "sha256-mock"))
        (manifest (pub/formatReleaseManifest spec artifact))]
    (assert (string-contains? manifest "(:release") "release header")
    (assert (string-contains? manifest "asl-quantum") "package name")
    (assert (string-contains? manifest "0.1.0") "version")
    true))

(df testIndexRelease [] -> Bool
  :d "Verifies registry index update on package publication."
  (let [(spec (pub/createPublishSpec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (idx (pub/PackageIndex :totalPackages 0 :releaseEntries (list)))
        (updated (pub/indexPackageRelease spec idx))]
    (assert (= (.-totalPackages updated) 1) "total packages 1")
    (assert (= (list-length (.-releaseEntries updated)) 1) "release entries 1")
    true))

(df runTests [] -> Bool
  :d "Executes full publishing test suite."
  (do
    (assert (testCreateSpec) "test-create-spec must pass")
    (assert (testCreateArtifact) "test-create-artifact must pass")
    (assert (testFormatManifest) "test-format-manifest must pass")
    (assert (testIndexRelease) "test-index-release must pass")
    true))
