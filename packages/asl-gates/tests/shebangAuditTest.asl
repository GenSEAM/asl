(module asl-gates/tests/shebangAuditTest
  :d "Comprehensive unit tests for shebang_audit functionality."
  :x [testIsBinaryBlob testIsValidPackageFile testIsApprovedForwarder testAuditShebang testAuditScriptFile runTests]
  :i [(shebangAudit :a sa)])

(df testIsBinaryBlob [] -> Bool
  :d "Verifies isBinaryBlob for all magic headers and clean content"
  (do
    (assert (sa/isBinaryBlob "\u007fELF\u0002\u0001\u0001\u0000") "ELF detected")
    (assert (sa/isBinaryBlob "MZ\u0090\u0000") "PE MZ detected")
    (assert (sa/isBinaryBlob "\ucffa\u00ed\u00fe") "Mach-O detected")
    (assert (sa/isBinaryBlob "\ucafe\u00ba\u00be") "Java class detected")
    (assert (sa/isBinaryBlob "\u0000\u0001\u0002") "null byte detected")
    (assert (not (sa/isBinaryBlob "#!/usr/bin/env bash")) "bash not binary")
    (assert (not (sa/isBinaryBlob "(module m)")) "ASL not binary")
    (assert (not (sa/isBinaryBlob "")) "empty not binary")
    true))

(df testIsValidPackageFile [] -> Bool
  :d "Verifies isValidPackageFile for allowed and disallowed extensions"
  (do
    (assert (sa/isValidPackageFile ".asl") ".asl valid")
    (assert (sa/isValidPackageFile ".asn") ".asn valid")
    (assert (sa/isValidPackageFile ".md") ".md valid")
    (assert (not (sa/isValidPackageFile ".py")) ".py invalid")
    (assert (not (sa/isValidPackageFile ".ts")) ".ts invalid")
    (assert (not (sa/isValidPackageFile ".js")) ".js invalid")
    (assert (not (sa/isValidPackageFile ".json")) ".json invalid")
    (assert (not (sa/isValidPackageFile "")) "empty invalid")
    true))

(df testIsApprovedForwarder [] -> Bool
  :d "Verifies isApprovedForwarder for approved and unapproved names"
  (let [(approved (list "asl" "agent" "gsa" "lens"))]
    (do
      (assert (sa/isApprovedForwarder "asl" approved) "asl approved")
      (assert (sa/isApprovedForwarder "agent" approved) "agent approved")
      (assert (sa/isApprovedForwarder "gsa" approved) "gsa approved")
      (assert (sa/isApprovedForwarder "lens" approved) "lens approved")
      (assert (not (sa/isApprovedForwarder "rogue" approved)) "rogue not approved")
      (assert (not (sa/isApprovedForwarder "" approved)) "empty not approved")
      true)))

(df testAuditShebang [] -> Bool
  :d "Verifies auditShebang for different interpreter lines"
  (do
    (assert (sa/auditShebang "#!/usr/bin/env bash\nexec asl") "bash shebang ok")
    (assert (sa/auditShebang "#!/usr/bin/env asl\n(println 1)") "asl shebang ok")
    (assert (sa/auditShebang "#!/bin/sh\nexec something") "sh shebang ok")
    (assert (not (sa/auditShebang "#!/usr/bin/python3\nimport os")) "python shebang rejected")
    (assert (not (sa/auditShebang "#!/usr/bin/env node")) "node shebang rejected")
    (assert (not (sa/auditShebang "(module m)")) "no shebang rejected")
    (assert (not (sa/auditShebang "")) "empty rejected")
    true))

(df testAuditScriptFile [] -> Bool
  :d "Verifies auditScriptFile for all Gate 4 scenarios"
  (let [(approved (list "asl" "agent"))
        (binaryVerdict (sa/auditScriptFile "bin/bad" "\u007fELF" false "" approved))
        (pkgValidAsl (sa/auditScriptFile "src/m.asl" "(module m)" true ".asl" approved))
        (pkgBadExt (sa/auditScriptFile "src/m.py" "import x" true ".py" approved))
        (pkgBadShebang (sa/auditScriptFile "src/m.asl" "#!/usr/bin/python3\nimport" true ".asl" approved))
        (scriptOkBash (sa/auditScriptFile "bin/run" "#!/usr/bin/env bash\nexec asl" false "" approved))
        (scriptBadInterp (sa/auditScriptFile "bin/run" "#!/usr/bin/ruby\nfoo" false "" approved))
        (approvedFwd (sa/auditScriptFile "asl" "some content" false "" approved))
        (unapprovedFwd (sa/auditScriptFile "rogue" "some content" false "" approved))
        (docReadme (sa/auditScriptFile "README.md" "# ASL" false ".md" approved))
        (configYaml (sa/auditScriptFile "pnpm-workspace.yaml" "packages: []" false ".yaml" approved))
        (configJson (sa/auditScriptFile "package.json" "{}" false ".json" approved))]
    (do
      (assert (not (.-valid binaryVerdict)) "binary rejected")
      (assert (.-isBinary binaryVerdict) "binary flagged as binary")
      (assert (.-valid pkgValidAsl) "valid pkg .asl passes")
      (assert (not (.-valid pkgBadExt)) "bad pkg ext rejected")
      (assert (not (.-valid pkgBadShebang)) "bad pkg shebang rejected")
      (assert (.-valid scriptOkBash) "ok bash script passes")
      (assert (not (.-valid scriptBadInterp)) "bad interp rejected")
      (assert (.-valid approvedFwd) "approved forwarder passes")
      (assert (not (.-valid unapprovedFwd)) "unapproved forwarder rejected")
      (assert (.-valid docReadme) "README.md outside pkg tree passes")
      (assert (.-valid configYaml) "YAML config outside pkg tree passes")
      (assert (.-valid configJson) "JSON config outside pkg tree passes")
      (assert (sa/isApprovedDocOrConfigFile ".toml") ".toml is approved config ext")
      (assert (sa/isApprovedDocOrConfigFile ".lock") ".lock is approved config ext")
      (assert (not (sa/isApprovedDocOrConfigFile ".exe")) ".exe is not approved doc/config ext")
      true)))

(df runTests [] -> Bool
  :d "Master test runner for shebang audit."
  (do
    (assert (testIsBinaryBlob) "testIsBinaryBlob")
    (assert (testIsValidPackageFile) "testIsValidPackageFile")
    (assert (testIsApprovedForwarder) "testIsApprovedForwarder")
    (assert (testAuditShebang) "testAuditShebang")
    (assert (testAuditScriptFile) "testAuditScriptFile")
    true))
