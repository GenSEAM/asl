(module asl-registry/tests/publish-test
  :d "Unit tests for package publishing, distribution tarball metadata, and registry indexing."
  :x [test-create-spec test-create-artifact test-format-manifest test-index-release run-tests]
  :i [(publish :a pub)])

(df test-create-spec [] -> Bool
  :d "Verifies construction of package publication specification."
  (let [(spec (pub/create-publish-spec "@genseam/asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn" "src/circuit.asl")))]
    (and (= (.-package-name spec) "@genseam/asl-quantum")
         (and (= (.-target-version spec) "0.1.0")
              (= (list-length (.-files spec)) 2)))))

(df test-create-artifact [] -> Bool
  :d "Verifies release artifact tarball naming and checksum assignment."
  (let [(spec (pub/create-publish-spec "@genseam/asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/create-release-artifact spec "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))]
    (and (= (.-tarball-name artifact) "genseam-asl-quantum-0.1.0.tar.gz")
         (= (.-file-count artifact) 1))))

(df test-format-manifest [] -> Bool
  :d "Verifies release manifest generation in canonical ASN format."
  (let [(spec (pub/create-publish-spec "@genseam/asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (artifact (pub/create-release-artifact spec "sha256-mock"))
        (manifest (pub/format-release-manifest spec artifact))]
    (and (string-contains? manifest "(:release")
         (and (string-contains? manifest "@genseam/asl-quantum")
              (string-contains? manifest "0.1.0")))))

(df test-index-release [] -> Bool
  :d "Verifies registry index update on package publication."
  (let [(spec (pub/create-publish-spec "@genseam/asl-quantum" "0.1.0" "src/circuit.asl" (list "manifest.asn")))
        (idx (pub/PackageIndex :total-packages 0 :release-entries (list)))
        (updated (pub/index-package-release spec idx))]
    (and (= (.-total-packages updated) 1)
         (= (list-length (.-release-entries updated)) 1))))

(df run-tests [] -> Bool
  :d "Executes full publishing test suite."
  (and (test-create-spec)
       (and (test-create-artifact)
            (and (test-format-manifest)
                 (test-index-release)))))
