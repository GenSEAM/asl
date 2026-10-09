(module asl-gates/test :x [testSyntaxValid testSyntaxInvalid testForeignExt testGrammarGate testSkillsGate testManifestGate testRunner runTests] :i [(gates :a g) (grammarGate :a gg) (skillsGate :a sg) (manifestGate :a mg) (gateRunner :a rn)])

fn testSyntaxValid -> Bool
  (do (assert (g/verifySourceSyntax "(module test/m :export [f]) (fn f [(x Int64)] -> Int64 (+ x 1))") "valid syntax") (assert (not (g/verifySourceSyntax "(module broken (:export unclosed")) "unclosed form syntax rejected") (assert (not (g/verifySourceSyntax "(fn incomplete [(x Int64)] ->")) "incomplete function signature rejected") (assert (not (g/verifyForeignExt ".py")) "rejected gate condition for foreign python file") true)

fn testSyntaxInvalid -> Bool
  (do (assert (g/verifySourceSyntax "(module valid/m :export [])") "valid minimal syntax accepted") (assert (g/verifyForeignExt ".asl") "accepted gate condition for valid asl extension") (assert (not (g/verifySourceSyntax "(module broken (:export unclosed")) "invalid syntax") (assert (not (g/verifySourceSyntax "((( unbalanced ((((")) "unbalanced delimiters rejected") (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "asl-test" "" "src/main.asl"))) "missing manifest version field rejected") (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "asl-test" "0.1.0" ""))) "missing manifest entry field rejected") (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "@sigil-pkg" "0.1.0" "src/main.asl"))) "prohibited @ sigil package name rejected") true)

fn testForeignExt -> Bool
  (let [(foreign (g/findForeignFilesInPaths (list "foo.asl" "bar.asn" "doc.md" "script.rb" "binary.bin")))] (assert (not (g/verifyForeignExt ".py")) "reject .py") (assert (not (g/verifyForeignExt ".ts")) "reject .ts") (assert (not (g/verifyForeignExt ".js")) "reject .js") (assert (not (g/verifyForeignExt ".json")) "reject .json") (assert (g/verifyForeignExt ".asl") "allow .asl") (assert (= (listLength foreign) 2) "findForeignFilesInPaths returns 2 foreign files") (assert (listContains? foreign "script.rb") "script.rb detected") (assert (listContains? foreign "binary.bin") "binary.bin detected") true)

fn testGrammarGate -> Bool
  (let [(e1 (gg/makeSymbolEntry "run" (gg/symFn) 1 false "")) (e2 (gg/makeSymbolEntry "make-circuit" (gg/symFn) 2 true "Creates circuit")) (e3 (gg/makeSymbolEntry "make-circuit-bad" (gg/symFn) 3 false ""))] (assert (gg/auditSymbolDensity e1 1) "e1 density") (assert (gg/auditSymbolDensity e2 1) "e2 density") (assert (not (gg/auditSymbolDensity e3 1)) "e3 bad density") true)

fn testSkillsGate -> Bool
  (let [(validRec (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "A test skill" true)) (validFolded (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" ">-" true)) (validQuoted (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "\"Triggers: test\"" true)) (invalidUnquotedColon (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "Triggers: unquoted colon fails" true)) (invalidRec (sg/makeSkillRecord "skills/test/SKILL.md" "" "No name" true))] (assert (sg/verifySkillRecord validRec) "valid-rec") (assert (sg/verifySkillRecord validFolded) "valid-folded") (assert (sg/verifySkillRecord validQuoted) "valid-quoted") (assert (not (sg/verifySkillRecord invalidUnquotedColon)) "invalid-unquoted-colon") (assert (not (sg/verifySkillRecord invalidRec)) "invalid-rec") true)

fn testManifestGate -> Bool
  (let [(validM (mg/makeManifestRecord "manifest.asn" "asl-transpile" "0.1.0" "src/codec.asl")) (invalidM (mg/makeManifestRecord "manifest.asn" "@bad-sigil" "0.1.0" "src/codec.asl"))] (assert (mg/verifyManifestRecord validM) "valid-m") (assert (not (mg/verifyManifestRecord invalidM)) "invalid-m") true)

fn testRunner -> Bool
  (let [(summary (rn/runAllSevenGates 15 87 12 0 31 1638 13))] (assert summary.allClean "all-clean") (assert (= summary.passedGates 7) "7 gates passed") true)

fn ! testCollectDirectoryFiles -> Bool
  (mt (g/collectDirectoryFiles "asl/packages/asl-gates")
    ((err e) (do (assert false (str "listing asl-gates must succeed: " e)) false))
    ((ok files) (do (assert (> (listLength files) 0) "should find files in asl-gates") (let [(badFound (fold (fn [(acc Bool) (f Str)] -> Bool (or acc (or (stringContains? f "node_modules") (or (stringContains? f "dist") (or (stringContains? f "asl-quantum") (stringContains? f "asl-arduino")))))) false files))] (assert (not badFound) "no excluded directories found in output") true))))

fn ! testAuditPackageTreeZeroForeign -> Bool
  (mt (g/auditPackageTreeZeroForeign (list "asl/packages/asl-gates/src")) ((ok cleanCount) (do (assert (> cleanCount 0) "should find clean files in src") true)) ((err violations) (do (assert false (str "should not find foreign files in src: " (stringJoin violations ", "))) false)))

fn ! testAllowlistedPathsMissingFileIsError -> Bool
  (let [(missing (str "/tmp/aslGatesHardening." (stringFromInt64 (nowNs)) "/noSuchAllowlist.asn"))]
    (mt (g/allowlistedPaths missing)
      ((ok paths) (do (assert false (str "a missing allowlist must not resolve to an ok list: got " (stringFromInt64 (listLength paths)) " paths")) false))
      ((err msg) (do (assert (stringContains? msg missing) (str "the allowlist read error names the path: " msg)) true))))

fn ! testAuditPackageTreeZeroForeignMissingAllowlistIsRed -> Bool
  (let [(missing (str "/tmp/aslGatesHardening." (stringFromInt64 (nowNs)) "/noSuchAllowlist.asn"))]
    (mt (g/auditPackageTreeZeroForeignAt (list "asl/packages/asl-gates/src") missing)
      ((ok cleanCount) (do (assert false (str "a missing allowlist must not report clean (" (stringFromInt64 cleanCount) " files)")) false))
      ((err violations) (do (assert (= (listLength violations) 1) (str "a missing allowlist reports exactly one violation line: " (stringJoin violations ", "))) (assert (listAny? (fn [(v Str)] -> Bool (stringContains? v missing)) violations) (str "the violation names the missing allowlist path: " (stringJoin violations ", "))) true))))

fn ! testIsForeignFileUnreadableIsError -> Bool
  (let [(dir (str "/tmp/aslGatesHardening." (stringFromInt64 (nowNs))))
        (made (ok? (dirCreate dir)))
        (target (str dir "/probe"))
        (written (ok? (fileWrite target "#!/bin/sh\necho hi\n")))
        (locked (processRun (str "chmod 000 " target)))
        (result (g/isForeignFile? target))
        (restored (processRun (str "chmod 644 " target)))
        (cleaned (pathRemove dir))]
    (do (assert made "fixture dir created")
        (assert written "shebang fixture written")
        (assert (= locked.exitCode 0) "fixture made unreadable")
        (assert (= restored.exitCode 0) "fixture made readable again for cleanup")
        (mt result
          ((ok isForeign) (do (assert false (str "an unreadable file must not resolve to ok " (if isForeign "true" "false"))) false))
          ((err msg) (do (assert (stringContains? msg target) (str "the read error names the file: " msg)) true)))))

fn ! testAuditPackageTreeZeroForeignUnreadableFileIsRed -> Bool
  (let [(dir (str "/tmp/aslGatesHardening." (stringFromInt64 (nowNs))))
        (made (ok? (dirCreate dir)))
        (target (str dir "/probe"))
        (written (ok? (fileWrite target "#!/bin/sh\necho hi\n")))
        (emptyAllow (ok? (fileWrite (str dir "/allow.asn") (validAllowlistText))))
        (locked (processRun (str "chmod 000 " target)))
        (result (g/auditPackageTreeZeroForeignAt (list dir) (str dir "/allow.asn")))
        (restored (processRun (str "chmod 644 " target)))
        (cleaned (pathRemove dir))]
    (do (assert made "fixture dir created")
        (assert written "shebang fixture written")
        (assert emptyAllow "allowlist fixture written")
        (assert (= locked.exitCode 0) "fixture made unreadable")
        (assert (= restored.exitCode 0) "fixture made readable again for cleanup")
        (mt result
          ((ok cleanCount) (do (assert false (str "an unreadable candidate file must not report clean (" (stringFromInt64 cleanCount) " files)")) false))
          ((err violations) (do (assert (listAny? (fn [(v Str)] -> Bool (stringContains? v target)) violations) (str "the violation names the unreadable file: " (stringJoin violations ", "))) true)))))

fn validAllowlistText -> Str
  "(:foreignAllowlist :v 1\n  (:path \"fixture/neverListed.py\" :kind :testGenerator :rationale \"fixture entry naming no listed file\" :until :none))\n"

fn ! freshDir! tag: Str -> Str
  (let [(dir (str "/tmp/aslGatesTest." tag "." (stringFromInt64 (nowNs))))] (do (assert (ok? (dirCreate dir)) (str "fixture dir created: " dir)) dir))

fn ! testAllowlistedPathsUnparseableIsError -> Bool
  (let [(dir (freshDir! "unparseable")) (allow (str dir "/allow.asn")) (written (ok? (fileWrite allow "(:foreignAllowlist :v 1\n  (:path \"a/b.py\" :kind :testGenerator :rationale \"r\" :until :none\n"))) (result (g/allowlistedPaths allow)) (cleaned (pathRemove dir))]
    (do (assert written "unparseable allowlist fixture written")
        (mt result
          ((ok paths) (do (assert false (str "an unparseable allowlist must not resolve to ok: got " (stringFromInt64 (listLength paths)) " paths")) false))
          ((err msg) (do (assert (stringContains? msg allow) (str "the parse error names the allowlist: " msg)) (assert (stringContains? msg "does not parse") (str "the error says the allowlist does not parse: " msg)) true)))))

fn ! testAllowlistedPathsZeroEntriesIsError -> Bool
  (let [(dir (freshDir! "zeroEntries")) (allow (str dir "/allow.asn")) (written (ok? (fileWrite allow "(:foreignAllowlist :v 1 :doc \"no entries\")\n"))) (result (g/allowlistedPaths allow)) (cleaned (pathRemove dir))]
    (do (assert written "entry-less allowlist fixture written")
        (mt result
          ((ok paths) (do (assert false (str "an entry-less allowlist must not resolve to ok: got " (stringFromInt64 (listLength paths)) " paths")) false))
          ((err msg) (do (assert (stringContains? msg allow) (str "the error names the allowlist: " msg)) (assert (stringContains? msg "zero (:path") (str "the error says the allowlist has zero entries: " msg)) true)))))

fn ! testAllowlistedPathsMalformedEntryIsError -> Bool
  (let [(dir (freshDir! "malformed")) (allow (str dir "/allow.asn")) (written (ok? (fileWrite allow "(:foreignAllowlist :v 1\n  (:path \"a/b.py\"))\n"))) (result (g/allowlistedPaths allow)) (cleaned (pathRemove dir))]
    (do (assert written "malformed allowlist fixture written")
        (mt result
          ((ok paths) (do (assert false (str "a malformed allowlist entry must not resolve to ok: got " (stringFromInt64 (listLength paths)) " paths")) false))
          ((err msg) (do (assert (stringContains? msg allow) (str "the error names the allowlist: " msg)) (assert (stringContains? msg "malformed") (str "the error says an entry is malformed: " msg)) true)))))

fn ! testAllowlistedPathsLiveFileHasEntries -> Bool
  (mt (g/allowlistedPaths "scripts/audit/foreignAllowlist.asn")
    ((err msg) (do (assert false (str "the live allowlist must parse: " msg)) false))
    ((ok paths) (do (assert (> (listLength paths) 0) "the live allowlist has entries") (assert (listContains? paths "scripts/install.sh") "the live allowlist contains its bootstrap installer") true)))

fn ! testAuditPackageTreeZeroForeignUnparseableAllowlistIsRed -> Bool
  (let [(dir (freshDir! "auditUnparseable")) (allow (str dir "/allow.asn")) (pyFile (str dir "/y.py")) (wroteAllow (ok? (fileWrite allow "(:foreignAllowlist (:path \"y.py\" :kind :testGenerator"))) (wrotePy (ok? (fileWrite pyFile "print(1)\n"))) (result (g/auditPackageTreeZeroForeignAt (list dir) allow)) (cleaned (pathRemove dir))]
    (do (assert wroteAllow "unparseable allowlist fixture written")
        (assert wrotePy "foreign fixture written")
        (mt result
          ((ok cleanCount) (do (assert false (str "an unparseable allowlist must not report clean (" (stringFromInt64 cleanCount) " files)")) false))
          ((err violations) (do (assert (= (listLength violations) 1) (str "an unparseable allowlist reports exactly one violation: " (stringJoin violations ", "))) (assert (listAny? (fn [(v Str)] -> Bool (and (stringContains? v allow) (stringContains? v "does not parse"))) violations) (str "the violation names the allowlist parse failure: " (stringJoin violations ", "))) true)))))

fn ! testAuditPackageTreeZeroForeignEmptyAllowlistIsRed -> Bool
  (let [(dir (freshDir! "auditEmpty")) (allow (str dir "/allow.asn")) (wroteAllow (ok? (fileWrite allow ""))) (result (g/auditPackageTreeZeroForeignAt (list (str dir "/none")) allow)) (cleaned (pathRemove dir))]
    (do (assert wroteAllow "empty allowlist fixture written")
        (mt result
          ((ok cleanCount) (do (assert false (str "an empty allowlist must not report clean (" (stringFromInt64 cleanCount) " files)")) false))
          ((err violations) (do (assert (listAny? (fn [(v Str)] -> Bool (and (stringContains? v allow) (stringContains? v "zero (:path"))) violations) (str "the violation names the entry-less allowlist: " (stringJoin violations ", "))) true)))))

fn ! testCollectDirectoryFilesMissingRootIsError -> Bool
  (let [(missing (str "/tmp/aslGatesTest.missing." (stringFromInt64 (nowNs))))]
    (mt (g/collectDirectoryFiles missing)
      ((ok files) (do (assert false (str "a missing root must not list as ok: got " (stringFromInt64 (listLength files)) " files")) false))
      ((err msg) (do (assert (stringContains? msg missing) (str "the listing error names the root: " msg)) true))))

fn ! testCollectDirectoryFilesUnreadableSubdirIsError -> Bool
  (let [(dir (freshDir! "unreadableSubdir")) (sub (str dir "/locked")) (madeSub (ok? (dirCreate sub))) (wrotePy (ok? (fileWrite (str sub "/y.py") "print(1)\n"))) (locked (processRun (str "chmod 000 " sub))) (result (g/collectDirectoryFiles dir)) (restored (processRun (str "chmod 755 " sub))) (cleaned (pathRemove dir))]
    (do (assert madeSub "locked subdirectory created")
        (assert wrotePy "foreign fixture written")
        (assert (= locked.exitCode 0) "subdirectory made unreadable")
        (assert (= restored.exitCode 0) "subdirectory made readable again for cleanup")
        (mt result
          ((ok files) (do (assert false (str "an unreadable subdirectory must not list as ok: got " (stringFromInt64 (listLength files)) " files")) false))
          ((err msg) (do (assert (stringContains? msg dir) (str "the listing error names the directory: " msg)) (assert (stringContains? msg "Permission denied") (str "the listing error carries find's stderr: " msg)) true)))))

fn ! testAuditPackageTreeZeroForeignUnreadableSubdirIsRed -> Bool
  (let [(dir (freshDir! "auditUnreadableSubdir")) (allow (str dir "/allow.asn")) (root (str dir "/packages")) (sub (str root "/locked")) (wroteAllow (ok? (fileWrite allow (validAllowlistText)))) (madeRoot (ok? (dirCreate root))) (madeSub (ok? (dirCreate sub))) (wrotePy (ok? (fileWrite (str sub "/y.py") "print(1)\n"))) (locked (processRun (str "chmod 000 " sub))) (result (g/auditPackageTreeZeroForeignAt (list root) allow)) (restored (processRun (str "chmod 755 " sub))) (cleaned (pathRemove dir))]
    (do (assert wroteAllow "allowlist fixture written")
        (assert (and madeRoot madeSub) "fixture tree created")
        (assert wrotePy "foreign fixture written")
        (assert (= locked.exitCode 0) "subdirectory made unreadable")
        (assert (= restored.exitCode 0) "subdirectory made readable again for cleanup")
        (mt result
          ((ok cleanCount) (do (assert false (str "an unreadable subdirectory must not report clean (" (stringFromInt64 cleanCount) " files)")) false))
          ((err violations) (do (assert (listAny? (fn [(v Str)] -> Bool (and (stringContains? v root) (stringContains? v "Permission denied"))) violations) (str "the violation names the unlistable directory: " (stringJoin violations ", "))) true)))))

fn ! testVerifyManifestsNamesFailures -> Bool
  (let [(dir (freshDir! "manifests")) (good (str dir "/good.asn")) (bad (str dir "/bad.asn")) (missing (str dir "/missing.asn")) (wroteGood (ok? (fileWrite good "(:package asl-fixture :version \"0.1.0\" :entry \"src/main.asl\")"))) (wroteBad (ok? (fileWrite bad "(:not-a-package 1)"))) (okRes (g/verifyManifests (list good))) (badRes (g/verifyManifests (list good bad missing))) (cleaned (pathRemove dir))]
    (do (assert (and wroteGood wroteBad) "manifest fixtures written")
        (mt okRes ((ok n) (assert (= n 1) "one valid manifest verified")) ((err ps) (assert false (str "a valid manifest must verify: " (stringJoin ps "; ")))))
        (mt badRes
          ((ok n) (do (assert false (str "an invalid and a missing manifest must not verify: ok " (stringFromInt64 n))) false))
          ((err problems) (do (assert (= (listLength problems) 2) (str "two named problems: " (stringJoin problems "; "))) (assert (listAny? (fn [(v Str)] -> Bool (stringContains? v missing)) problems) "the unreadable manifest is named") (assert (listAny? (fn [(v Str)] -> Bool (stringContains? v bad)) problems) "the invalid manifest is named") true)))))

fn ! runTests -> Bool
  (do (assert (testSyntaxValid) "test-syntax-valid must pass") (assert (testSyntaxInvalid) "test-syntax-invalid must pass") (assert (testForeignExt) "test-foreign-ext must pass") (assert (testGrammarGate) "test-grammar-gate must pass") (assert (testSkillsGate) "test-skills-gate must pass") (assert (testManifestGate) "test-manifest-gate must pass") (assert (testRunner) "test-runner must pass") (assert (testCollectDirectoryFiles) "test-collect-directory-files must pass") (assert (testAuditPackageTreeZeroForeign) "test-audit-package-tree-zero-foreign must pass") (assert (testAllowlistedPathsMissingFileIsError) "test-allowlisted-paths-missing-file-is-error must pass") (assert (testAuditPackageTreeZeroForeignMissingAllowlistIsRed) "test-audit-package-tree-zero-foreign-missing-allowlist-is-red must pass") (assert (testIsForeignFileUnreadableIsError) "test-is-foreign-file-unreadable-is-error must pass") (assert (testAuditPackageTreeZeroForeignUnreadableFileIsRed) "test-audit-package-tree-zero-foreign-unreadable-file-is-red must pass") (assert (testAllowlistedPathsUnparseableIsError) "unparseable allowlist is an error") (assert (testAllowlistedPathsZeroEntriesIsError) "entry-less allowlist is an error") (assert (testAllowlistedPathsMalformedEntryIsError) "malformed allowlist entry is an error") (assert (testAllowlistedPathsLiveFileHasEntries) "live allowlist parses with entries") (assert (testAuditPackageTreeZeroForeignUnparseableAllowlistIsRed) "gate4 red on unparseable allowlist") (assert (testAuditPackageTreeZeroForeignEmptyAllowlistIsRed) "gate4 red on empty allowlist") (assert (testCollectDirectoryFilesMissingRootIsError) "missing root is a listing error") (assert (testCollectDirectoryFilesUnreadableSubdirIsError) "unreadable subdirectory is a listing error") (assert (testAuditPackageTreeZeroForeignUnreadableSubdirIsRed) "gate4 red on unreadable subdirectory") (assert (testVerifyManifestsNamesFailures) "verifyManifests names failures") true)
