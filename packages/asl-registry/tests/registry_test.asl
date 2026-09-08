(module asl-registry/tests/registry-test
  :d "Unit test suite for universal package registry and version inspector."
  :x [test-parse-specifier test-semver-comparison test-outdated-evaluation
      test-formatting run-tests main]
  :i [(regtypes :a ty) (version :a ver) (registry :a reg)])

(df test-parse-specifier [] -> Bool
  :d "Tests specifier parsing across npm, pypi, crates, and asl."
  (let [(s1 (reg/parse-package-specifier "npm:kysely@^0.27.0"))
        (s2 (reg/parse-package-specifier "pypi:requests"))
        (s3 (reg/parse-package-specifier "crates:serde@1.0.197"))]
    (assert (= (.-name s1) "kysely") "s1 name")
    (assert (= (ty/eco-to-string (.-eco s1)) "npm") "s1 eco")
    (assert (= (.-version-req s1) "^0.27.0") "s1 version-req")
    (assert (= (.-name s2) "requests") "s2 name")
    (assert (= (ty/eco-to-string (.-eco s2)) "pypi") "s2 eco")
    (assert (= (.-name s3) "serde") "s3 name")
    (assert (= (ty/eco-to-string (.-eco s3)) "crates") "s3 eco")
    (assert (= (.-version-req s3) "1.0.197") "s3 version-req")
    true))

(df test-semver-comparison [] -> Bool
  :d "Tests semantic version ordering and comparison."
  (do
    (assert (= (ver/compare-semver "0.1.0" "0.2.0") -1) "0.1.0 < 0.2.0")
    (assert (= (ver/compare-semver "1.2.3" "1.2.3") 0) "1.2.3 == 1.2.3")
    (assert (= (ver/compare-semver "1.0.0" "2.0.0") -1) "1.0.0 < 2.0.0")
    (assert (= (ver/compare-semver "v1.5.0" "1.4.9") 1) "1.5.0 > 1.4.9")
    (assert (= (ver/compare-semver "0.3.1" "0.3.2") -1) "0.3.1 < 0.3.2")
    true))

(df test-outdated-evaluation [] -> Bool
  :d "Tests upgrade severity classification."
  (let [(r1 (ver/evaluate-outdated "requests" "2.28.0" "2.31.0"))
        (r2 (ver/evaluate-outdated "next" "14.0.0" "15.0.0"))
        (r3 (ver/evaluate-outdated "tokio" "1.35.0" "1.35.1"))
        (r4 (ver/evaluate-outdated "asl" "0.1.0" "0.1.0"))]
    (assert (.-outdated r1) "r1 outdated")
    (assert (= (.-severity r1) "minor") "r1 minor")
    (assert (.-outdated r2) "r2 outdated")
    (assert (= (.-severity r2) "major") "r2 major")
    (assert (.-outdated r3) "r3 outdated")
    (assert (= (.-severity r3) "patch") "r3 patch")
    (assert (not (.-outdated r4)) "r4 not outdated")
    (assert (= (.-severity r4) "current") "r4 current")
    true))

(df test-formatting [] -> Bool
  :d "Tests summary and table markdown formatters."
  (let [(info (reg/make-package-info "requests" (ty/make-eco-pypi) "2.31.0" "Python HTTP library" "Apache-2.0"))
        (summary (reg/format-package-summary info))
        (outdated (ver/evaluate-outdated "requests" "2.28.0" "2.31.0"))
        (rep (reg/format-outdated-report outdated))
        (entry (ty/AslRegistryEntry
                 :name "@genseam/asl-mem"
                 :git-repo "https://github.com/GenSEAM/asl-mem.git"
                 :branch "main"
                 :latest-tag "v0.1.0"
                 :description "AgentScript Memory Matrix"
                 :capabilities (list "vector" "graph")))
        (tbl (reg/format-asl-registry-table (list entry)))]
    (assert (string-contains? summary "requests") "summary requests")
    (assert (string-contains? summary "v2.31.0") "summary v2.31.0")
    (assert (string-contains? rep "minor update available") "rep minor")
    (assert (string-contains? tbl "@genseam/asl-mem") "tbl asl-mem")
    (assert (string-contains? tbl "v0.1.0") "tbl v0.1.0")
    true))

(df run-tests [] -> Bool
  :d "Runs all registry tests."
  (do
    (assert (test-parse-specifier) "test-parse-specifier must pass")
    (assert (test-semver-comparison) "test-semver-comparison must pass")
    (assert (test-outdated-evaluation) "test-outdated-evaluation must pass")
    (assert (test-formatting) "test-formatting must pass")
    true))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Main test runner entrypoint."
  (if (run-tests)
      (let [(unused-u (println "✓ ALL ASL REGISTRY TESTS PASSED"))]
        (ok ()))
      (let [(unused-e (eprintln "FAILED ASL REGISTRY TESTS"))]
        (err (other)))))
