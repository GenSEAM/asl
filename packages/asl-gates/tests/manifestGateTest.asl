(module asl-gates/tests/manifestGateTest :x [testIsValidPkgName testMakeRecord testParsePackageId testVerifyRecord runTests] :i [(manifestGate :a mg)])

fn testIsValidPkgName -> Bool
  (do (assert (mg/isValidPkgName? "asl-transpile") "asl-transpile valid") (assert (mg/isValidPkgName? "my-package") "my-package valid") (assert (not (mg/isValidPkgName? "@scoped")) "@ sigil rejected") (assert (not (mg/isValidPkgName? "ab")) "2-char name rejected") (assert (mg/isValidPkgName? "abc") "3-char name accepted") true)

fn testMakeRecord -> Bool
  (let [(valid (mg/makeManifestRecord "manifest.asn" "asl-transpile" "0.1.0" "src/main.asl")) (noVersion (mg/makeManifestRecord "manifest.asn" "asl-transpile" "" "src/main.asl")) (noEntry (mg/makeManifestRecord "manifest.asn" "asl-transpile" "0.1.0" "")) (sigil (mg/makeManifestRecord "manifest.asn" "@bad" "0.1.0" "src/main.asl")) (short (mg/makeManifestRecord "manifest.asn" "ab" "0.1.0" "src/main.asl"))] (do (assert valid.isValid "valid record") (assert (not noVersion.isValid) "no version invalid") (assert (not noEntry.isValid) "no entry invalid") (assert (not sigil.isValid) "sigil invalid") (assert (not short.isValid) "short name invalid") true))

fn testParsePackageId -> Bool
  (do (assert (= (mg/parsePackageId "(:package asl-transpile :version \"0.1.0\")") "asl-transpile") "extracts asl-transpile") (assert (= (mg/parsePackageId "  (:package   my-pkg :entry \"src/main.asl\")") "my-pkg") "extracts my-pkg with whitespace") (assert (= (mg/parsePackageId "(:not-package foo)") "") "non-package returns empty") (assert (= (mg/parsePackageId "") "") "empty string returns empty") true)

fn testVerifyRecord -> Bool
  (let [(valid (mg/makeManifestRecord "p" "asl-transpile" "1.0.0" "src/main.asl")) (invalid (mg/makeManifestRecord "p" "@bad" "1.0.0" "src/main.asl"))] (do (assert (mg/verifyManifestRecord valid) "valid record passes verify") (assert (not (mg/verifyManifestRecord invalid)) "invalid record fails verify") true))

fn runTests -> Bool
  (do (assert (testIsValidPkgName) "testIsValidPkgName") (assert (testMakeRecord) "testMakeRecord") (assert (testParsePackageId) "testParsePackageId") (assert (testVerifyRecord) "testVerifyRecord") true)
