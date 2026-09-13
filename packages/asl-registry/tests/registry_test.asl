(module asl-registry/tests/registryTest
  :d "Unit test suite for universal package registry and version inspector."
  :x [testParseSpecifier testSemverComparison testOutdatedEvaluation
      testFormatting runTests main]
  :i [(regtypes :a ty) (version :a ver) (registry :a reg)])

(df testParseSpecifier [] -> Bool
  :d "Tests specifier parsing across npm, pypi, crates, and asl."
  (let [(s1 (reg/parsePackageSpecifier "npm:kysely@^0.27.0"))
        (s2 (reg/parsePackageSpecifier "pypi:requests"))
        (s3 (reg/parsePackageSpecifier "crates:serde@1.0.197"))]
    (assert (= (.-name s1) "kysely") "s1 name")
    (assert (= (ty/ecoToString (.-eco s1)) "npm") "s1 eco")
    (assert (= (.-versionReq s1) "^0.27.0") "s1 version-req")
    (assert (= (.-name s2) "requests") "s2 name")
    (assert (= (ty/ecoToString (.-eco s2)) "pypi") "s2 eco")
    (assert (= (.-name s3) "serde") "s3 name")
    (assert (= (ty/ecoToString (.-eco s3)) "crates") "s3 eco")
    (assert (= (.-versionReq s3) "1.0.197") "s3 version-req")
    true))

(df testSemverComparison [] -> Bool
  :d "Tests semantic version ordering and comparison."
  (do
    (assert (= (ver/compareSemver "0.1.0" "0.2.0") -1) "0.1.0 < 0.2.0")
    (assert (= (ver/compareSemver "1.2.3" "1.2.3") 0) "1.2.3 == 1.2.3")
    (assert (= (ver/compareSemver "1.0.0" "2.0.0") -1) "1.0.0 < 2.0.0")
    (assert (= (ver/compareSemver "v1.5.0" "1.4.9") 1) "1.5.0 > 1.4.9")
    (assert (= (ver/compareSemver "0.3.1" "0.3.2") -1) "0.3.1 < 0.3.2")
    true))

(df testOutdatedEvaluation [] -> Bool
  :d "Tests upgrade severity classification."
  (let [(r1 (ver/evaluateOutdated "requests" "2.28.0" "2.31.0"))
        (r2 (ver/evaluateOutdated "next" "14.0.0" "15.0.0"))
        (r3 (ver/evaluateOutdated "tokio" "1.35.0" "1.35.1"))
        (r4 (ver/evaluateOutdated "asl" "0.1.0" "0.1.0"))]
    (assert (.-outdated r1) "r1 outdated")
    (assert (= (.-severity r1) "minor") "r1 minor")
    (assert (.-outdated r2) "r2 outdated")
    (assert (= (.-severity r2) "major") "r2 major")
    (assert (.-outdated r3) "r3 outdated")
    (assert (= (.-severity r3) "patch") "r3 patch")
    (refute (.-outdated r4) "r4 not outdated")
    (assert (= (.-severity r4) "current") "r4 current")
    true))

(df testFormatting [] -> Bool
  :d "Tests summary and table markdown formatters."
  (let [(info (reg/makePackageInfo "requests" (ty/makeEcoPypi) "2.31.0" "Python HTTP library" "Apache-2.0"))
        (summary (reg/formatPackageSummary info))
        (outdated (ver/evaluateOutdated "requests" "2.28.0" "2.31.0"))
        (rep (reg/formatOutdatedReport outdated))
        (entry (ty/AslRegistryEntry
                 :name "asl-mem"
                 :gitRepo "https://github.com/GenSEAM/asl-mem.git"
                 :branch "main"
                 :latestTag "v0.1.0"
                 :description "AgentScript Memory Matrix"
                 :capabilities (list "vector" "graph")))
        (tbl (reg/formatAslRegistryTable (list entry)))]
    (assert (string-contains? summary "requests") "summary requests")
    (assert (string-contains? summary "v2.31.0") "summary v2.31.0")
    (assert (string-contains? rep "minor update available") "rep minor")
    (assert (string-contains? tbl "asl-mem") "tbl asl-mem")
    (assert (string-contains? tbl "v0.1.0") "tbl v0.1.0")
    true))

(df runTests [] -> Bool
  :d "Runs all registry tests."
  (do
    (assert (testParseSpecifier) "test-parse-specifier must pass")
    (assert (testSemverComparison) "test-semver-comparison must pass")
    (assert (testOutdatedEvaluation) "test-outdated-evaluation must pass")
    (assert (testFormatting) "test-formatting must pass")
    true))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Main test runner entrypoint."
  (if (runTests)
      (let [(unusedU (println ":ok ALL ASL REGISTRY TESTS PASSED"))]
        (ok ()))
      (let [(unusedE (eprintln "FAILED ASL REGISTRY TESTS"))]
        (err (other)))))
