(module asl-gates/tests/manifestGateTest
  :d "Comprehensive unit tests for manifest_gate functionality."
  :x [testIsValidPkgName testMakeRecord testParsePackageId testVerifyRecord runTests]
  :i [(manifestGate :a mg)])

(df testIsValidPkgName [] -> Bool
  :d "Verifies isValidPkgName? for valid and invalid names"
  (do
    (assert (mg/isValidPkgName? "asl-codec") "asl-codec valid")
    (assert (mg/isValidPkgName? "my-package") "my-package valid")
    (assert (not (mg/isValidPkgName? "@scoped")) "@ sigil rejected")
    (assert (not (mg/isValidPkgName? "ab")) "2-char name rejected")
    (assert (mg/isValidPkgName? "abc") "3-char name accepted")
    true))

(df testMakeRecord [] -> Bool
  :d "Verifies makeManifestRecord construction for valid and invalid inputs"
  (let [(valid (mg/makeManifestRecord "manifest.asn" "asl-codec" "0.1.0" "src/main.asl"))
        (noVersion (mg/makeManifestRecord "manifest.asn" "asl-codec" "" "src/main.asl"))
        (noEntry (mg/makeManifestRecord "manifest.asn" "asl-codec" "0.1.0" ""))
        (sigil (mg/makeManifestRecord "manifest.asn" "@bad" "0.1.0" "src/main.asl"))
        (short (mg/makeManifestRecord "manifest.asn" "ab" "0.1.0" "src/main.asl"))]
    (do
      (assert (.-isValid valid) "valid record")
      (assert (not (.-isValid noVersion)) "no version invalid")
      (assert (not (.-isValid noEntry)) "no entry invalid")
      (assert (not (.-isValid sigil)) "sigil invalid")
      (assert (not (.-isValid short)) "short name invalid")
      true)))

(df testParsePackageId [] -> Bool
  :d "Verifies parsePackageId extraction from manifest content"
  (do
    (assert (= (mg/parsePackageId "(:package asl-codec :version \"0.1.0\")") "asl-codec") "extracts asl-codec")
    (assert (= (mg/parsePackageId "  (:package   my-pkg :entry \"src/main.asl\")") "my-pkg") "extracts my-pkg with whitespace")
    (assert (= (mg/parsePackageId "(:not-package foo)") "") "non-package returns empty")
    (assert (= (mg/parsePackageId "") "") "empty string returns empty")
    true))

(df testVerifyRecord [] -> Bool
  :d "Verifies verifyManifestRecord delegates to isValid"
  (let [(valid (mg/makeManifestRecord "p" "asl-codec" "1.0.0" "src/main.asl"))
        (invalid (mg/makeManifestRecord "p" "@bad" "1.0.0" "src/main.asl"))]
    (do
      (assert (mg/verifyManifestRecord valid) "valid record passes verify")
      (assert (not (mg/verifyManifestRecord invalid)) "invalid record fails verify")
      true)))

(df runTests [] -> Bool
  :d "Master test runner for manifest gate."
  (do
    (assert (testIsValidPkgName) "testIsValidPkgName")
    (assert (testMakeRecord) "testMakeRecord")
    (assert (testParsePackageId) "testParsePackageId")
    (assert (testVerifyRecord) "testVerifyRecord")
    true))
