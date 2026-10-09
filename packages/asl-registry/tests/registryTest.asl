(module asl-registry/tests/registryTest :x [testParseSpecifier testSemverComparison testOutdatedEvaluation testFormatting runTests main] :i [(regtypes :a ty) (version :a ver) (registry :a reg)])

fn testParseSpecifier -> Bool
  (let [(s1 (reg/parsePackageSpecifier "npm:kysely@^0.27.0")) (s2 (reg/parsePackageSpecifier "pypi:requests")) (s3 (reg/parsePackageSpecifier "crates:serde@1.0.197"))] (assert (= s1.name "kysely") "s1 name") (assert (= (ty/ecoToString s1.eco) "npm") "s1 eco") (assert (= s1.versionReq "^0.27.0") "s1 version-req") (assert (= s2.name "requests") "s2 name") (assert (= (ty/ecoToString s2.eco) "pypi") "s2 eco") (assert (= s3.name "serde") "s3 name") (assert (= (ty/ecoToString s3.eco) "crates") "s3 eco") (assert (= s3.versionReq "1.0.197") "s3 version-req") true)

fn testSemverComparison -> Bool
  (do (assert (= (ver/compareSemver "0.1.0" "0.2.0") -1) "0.1.0 < 0.2.0") (assert (= (ver/compareSemver "1.2.3" "1.2.3") 0) "1.2.3 == 1.2.3") (assert (= (ver/compareSemver "1.0.0" "2.0.0") -1) "1.0.0 < 2.0.0") (assert (= (ver/compareSemver "v1.5.0" "1.4.9") 1) "1.5.0 > 1.4.9") (assert (= (ver/compareSemver "0.3.1" "0.3.2") -1) "0.3.1 < 0.3.2") true)

fn testOutdatedEvaluation -> Bool
  (let [(r1 (ver/evaluateOutdated "requests" "2.28.0" "2.31.0")) (r2 (ver/evaluateOutdated "next" "14.0.0" "15.0.0")) (r3 (ver/evaluateOutdated "tokio" "1.35.0" "1.35.1")) (r4 (ver/evaluateOutdated "asl" "0.1.0" "0.1.0"))] (assert r1.outdated "r1 outdated") (assert (= r1.severity "minor") "r1 minor") (assert r2.outdated "r2 outdated") (assert (= r2.severity "major") "r2 major") (assert r3.outdated "r3 outdated") (assert (= r3.severity "patch") "r3 patch") (refute r4.outdated "r4 not outdated") (assert (= r4.severity "current") "r4 current") true)

fn testFormatting -> Bool
  (let [(info (reg/makePackageInfo "requests" (ty/makeEcoPypi) "2.31.0" "Python HTTP library" "Apache-2.0")) (summary (reg/formatPackageSummary info)) (outdated (ver/evaluateOutdated "requests" "2.28.0" "2.31.0")) (rep (reg/formatOutdatedReport outdated)) (entry (ty/AslRegistryEntry :name "asl-mem" :gitRepo "https://github.com/GenSEAM/asl-mem.git" :branch "main" :latestTag "v0.1.0" :description "AgentScript Memory Matrix" :capabilities (list "vector" "graph"))) (tbl (reg/formatAslRegistryTable (list entry)))] (assert (stringContains? summary "requests") "summary requests") (assert (stringContains? summary "v2.31.0") "summary v2.31.0") (assert (stringContains? rep "minor update available") "rep minor") (assert (stringContains? tbl "asl-mem") "tbl asl-mem") (assert (stringContains? tbl "v0.1.0") "tbl v0.1.0") true)

fn runTests -> Bool
  (do (assert (testParseSpecifier) "test-parse-specifier must pass") (assert (testSemverComparison) "test-semver-comparison must pass") (assert (testOutdatedEvaluation) "test-outdated-evaluation must pass") (assert (testFormatting) "test-formatting must pass") true)

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runTests) (let [(unusedU (println ":ok ALL ASL REGISTRY TESTS PASSED"))] (ok ())) (let [(unusedE (eprintln "FAILED ASL REGISTRY TESTS"))] (err (other))))
