(module asl-registry/tests/registry-test
  :d "Unit test suite for universal package registry and version inspector."
  :x [test-parse-specifier test-semver-comparison test-outdated-evaluation
      test-formatting main]
  :i [(regtypes :a ty) (version :a ver) (registry :a reg)])

(df test-parse-specifier [] -> Bool
  :d "Tests specifier parsing across npm, pypi, crates, and asl."
  (let [(s1 (reg/parse-package-specifier "npm:kysely@^0.27.0"))
        (s2 (reg/parse-package-specifier "pypi:requests"))
        (s3 (reg/parse-package-specifier "crates:serde@1.0.197"))]
    (and (= (.-name s1) "kysely")
    (and (= (ty/eco-to-string (.-eco s1)) "npm")
    (and (= (.-version-req s1) "^0.27.0")
    (and (= (.-name s2) "requests")
    (and (= (ty/eco-to-string (.-eco s2)) "pypi")
    (and (= (.-name s3) "serde")
    (and (= (ty/eco-to-string (.-eco s3)) "crates")
         (= (.-version-req s3) "1.0.197"))))))))))

(df test-semver-comparison [] -> Bool
  :d "Tests semantic version ordering and comparison."
  (and (= (ver/compare-semver "0.3.0" "0.2.0") 1)
  (and (= (ver/compare-semver "1.2.3" "1.2.3") 0)
  (and (= (ver/compare-semver "1.0.0" "2.0.0") -1)
  (and (= (ver/compare-semver "v1.5.0" "1.4.9") 1)
       (= (ver/compare-semver "0.3.1" "0.3.2") -1))))))

(df test-outdated-evaluation [] -> Bool
  :d "Tests upgrade severity classification."
  (let [(r1 (ver/evaluate-outdated "requests" "2.28.0" "2.31.0"))
        (r2 (ver/evaluate-outdated "next" "14.0.0" "15.0.0"))
        (r3 (ver/evaluate-outdated "tokio" "1.35.0" "1.35.1"))
        (r4 (ver/evaluate-outdated "asl" "0.3.0" "0.3.0"))]
    (and (.-outdated r1)
    (and (= (.-severity r1) "minor")
    (and (.-outdated r2)
    (and (= (.-severity r2) "major")
    (and (.-outdated r3)
    (and (= (.-severity r3) "patch")
    (and (not (.-outdated r4))
         (= (.-severity r4) "current"))))))))))

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
                 :latest-tag "v0.3.0"
                 :description "AgentScript Memory Matrix"
                 :capabilities (list "vector" "graph")))
        (tbl (reg/format-asl-registry-table (list entry)))]
    (and (string-contains? summary "requests")
    (and (string-contains? summary "v2.31.0")
    (and (string-contains? rep "minor update available")
    (and (string-contains? tbl "@genseam/asl-mem")
         (string-contains? tbl "v0.3.0")))))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Main test runner entrypoint."
  (let [(p1 (test-parse-specifier))
        (p2 (test-semver-comparison))
        (p3 (test-outdated-evaluation))
        (p4 (test-formatting))]
    (if (and p1 (and p2 (and p3 p4)))
        (let [(unused-u (println "✓ ALL ASL REGISTRY TESTS PASSED"))]
          (ok ()))
        (let [(unused-e (eprintln "FAILED ASL REGISTRY TESTS"))]
          (err (other))))))
