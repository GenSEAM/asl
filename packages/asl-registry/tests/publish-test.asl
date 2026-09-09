(module asl-registry/tests/publish-test
  :d "Unit tests for package publishing, distribution tarball metadata, and registry indexing."
  :x [test-create-spec test-create-artifact test-format-manifest test-index-release run-tests]
  :i [(publish :a pub)])

(df test-create-spec [] -> Bool
  :d "Verifies construction of package publication specification."
  (let [(spec (pub/create-publish-spec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn" "src/circuit.asl")))]
    (assert (= (.-package-name spec) "asl-quantum") "package-name")
    (assert (= (.-target-version spec) "0.1.0") "target-version")
    (assert (= (list-length (.-files spec)) 2) "files count")
    true))

(df test-create-artifact [] -> Bool
  :d "Verifies release artifact tarball naming and checksum assignment."
  (let [(spec (pub/create-publish-spec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/create-release-artifact spec "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))]
    (assert (= (.-tarball-name artifact) "asl-quantum-0.1.0.tar.gz") "tarball name")
    (assert (= (.-file-count artifact) 1) "file count")
    true))

(df test-format-manifest [] -> Bool
  :d "Verifies release manifest generation in canonical ASN format."
  (let [(spec (pub/create-publish-spec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/create-release-artifact spec "sha256-mock"))
        (manifest (pub/format-release-manifest spec artifact))]
    (assert (string-contains? manifest "(:release") "release header")
    (assert (string-contains? manifest "asl-quantum") "package name")
    (assert (string-contains? manifest "0.1.0") "version")
    true))

(df test-index-release [] -> Bool
  :d "Verifies registry index update on package publication."
  (let [(spec (pub/create-publish-spec "asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (idx (pub/PackageIndex :total-packages 0 :release-entries (list)))
        (updated (pub/index-package-release spec idx))]
    (assert (= (.-total-packages updated) 1) "total packages 1")
    (assert (= (list-length (.-release-entries updated)) 1) "release entries 1")
    true))

(df run-tests [] -> Bool
  :d "Executes full publishing test suite."
  (do
    (assert (test-create-spec) "test-create-spec must pass")
    (assert (test-create-artifact) "test-create-artifact must pass")
    (assert (test-format-manifest) "test-format-manifest must pass")
    (assert (test-index-release) "test-index-release must pass")
    true))
