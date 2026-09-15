(module asl-gates/tests/gateRunnerTest
  :d "Falsifiable verification and test suite for pure ASL gate runner and extensionless audit."
  :x [testAllGatesPass
      testGateFailFast
      testExtensionlessAudit
      testDeadCodeAudit
      testSummaryFormatting
      testVerifyBalance
      testVerifyManifests
      testRunAll
      testFaultInjectionGate4
      testZeroCommentAudit
      runTests]
  :i [(gateRunner :a gr)
      (shebangAudit :a sa)
      (gates :a g)])

(df testAllGatesPass [] -> Bool
  :d "Asserts all 7 gates passing verdict aggregation and clean report."
  (let [(summary (gr/runAllGates 34 673 12 0 212 3223 29))]
    (assert (.-allClean summary) "All 7 gates clean must report all-clean true")
    (assert (= (.-totalGates summary) 7) "Total gates count must equal 7")
    (assert (= (.-passedGates summary) 7) "Passed gates count must equal 7")
    (assert (= (list-length (.-verdicts summary)) 7) "Verdicts list length must equal 7")
    (let [(s7 (gr/runAllSevenGates 10 100 15 0 50 1500 20))]
      (assert (.-allClean s7) "run-all-seven-gates must pass when all criteria met")
      (assert (= (.-passedGates s7) 7) "run-all-seven-gates passed gates must be 7"))
    true))

(df testGateFailFast [] -> Bool
  :d "Asserts fail-fast rejection for each individual gate failure mode."
  (let [(sNoManifests (gr/runAllGates 0 673 12 0 212 3223 29))
        (sNoAsl (gr/runAllGates 34 0 12 0 212 3223 29))
        (sFewClaims (gr/runAllGates 34 673 5 0 212 3223 29))
        (sForeignFiles (gr/runAllGates 34 673 12 3 212 3223 29))
        (sNoTests (gr/runAllGates 34 673 12 0 0 3223 29))
        (sFewGrammar (gr/runAllGates 34 673 12 0 212 500 29))
        (sFewSkills (gr/runAllGates 34 673 12 0 212 3223 4))]
    (assert (not (.-allClean sNoManifests)) "0 manifests must fail gate 1")
    (assert (= (.-passedGates sNoManifests) 6) "0 manifests must leave 6 passed gates")
    (assert (not (.-allClean sNoAsl)) "0 ASL files must fail gate 2")
    (assert (= (.-passedGates sNoAsl) 6) "0 ASL files must leave 6 passed gates")
    (assert (not (.-allClean sFewClaims)) "<12 claims must fail gate 3")
    (assert (not (.-allClean sForeignFiles)) "Foreign files > 0 must fail gate 4")
    (assert (not (.-allClean sNoTests)) "0 tests must fail gate 5")
    (assert (not (.-allClean sFewGrammar)) "<= 1000 grammar symbols must fail gate 6")
    (assert (not (.-allClean sFewSkills)) "<10 skills must fail gate 7")
    true))

(df testExtensionlessAudit [] -> Bool
  :d "Asserts extensionless binary blob detection and approved forwarder filtering."
  (let [(approved (list "asl" "agent" "gsa" "lens"))
        (elfHeader "\u007fELF\u0002\u0001\u0001\u0000")
        (peHeader "MZ\u0090\u0000\u0003\u0000")
        (shHeader "#!/usr/bin/env bash\nexec asl \"$@\"")
        (aslShHeader "#!/usr/bin/env asl\n(println 1)")
        (badShHeader "#!/usr/bin/python3\nimport os")]
    (assert (sa/isBinaryBlob elfHeader) "ELF header must be detected as binary blob")
    (assert (sa/isBinaryBlob peHeader) "PE MZ header must be detected as binary blob")
    (assert (not (sa/isBinaryBlob shHeader)) "Bash script must not be detected as binary blob")
    (assert (sa/auditShebang shHeader) "Approved bash shebang must pass audit")
    (assert (sa/auditShebang aslShHeader) "Approved asl shebang must pass audit")
    (assert (not (sa/auditShebang badShHeader)) "Python shebang must fail audit")
    (assert (sa/isApprovedForwarder "asl" approved) "asl must be approved forwarder")
    (assert (sa/isApprovedForwarder "agent" approved) "agent must be approved forwarder")
    (assert (not (sa/isApprovedForwarder "claude-standalone" approved)) "claude-standalone must be rejected")
    (assert (not (sa/isApprovedForwarder "eddie" approved)) "eddie must be rejected")
    (let [(unapproved (gr/auditExtensionlessBinaries (list "asl" "rogue" "bin/eddie") approved))]
      (assert (= (list-length unapproved) 2) "Two unapproved binaries must be flagged")
      (assert (list-contains? unapproved "rogue") "rogue binary must be in unapproved list")
      (assert (list-contains? unapproved "bin/eddie") "eddie must be in unapproved list"))
    true))

(df testDeadCodeAudit [] -> Bool
  :d "Asserts detection of dead code and orphan symbol exports."
  (let [(exports (list "live-fn" "orphan-fn" "unused-helper"))
        (callers (list "live-fn" "other-fn"))
        (orphans (gr/auditDeadCode exports callers))]
    (assert (= (list-length orphans) 2) "Two orphan functions must be detected")
    (assert (list-contains? orphans "orphan-fn") "orphan-fn must be detected")
    (assert (list-contains? orphans "unused-helper") "unused-helper must be detected")
    (assert (not (list-contains? orphans "live-fn")) "live-fn must not be in orphan list")
    true))

(df testSummaryFormatting [] -> Bool
  :d "Asserts formatting of clean and failed gate summaries."
  (let [(sClean (gr/runAllGates 34 673 12 0 212 3223 29))
        (sFail (gr/runAllGates 0 0 0 1 0 0 0))
        (repClean (gr/formatGateSummary sClean))
        (repFail (gr/formatGateSummary sFail))]
    (assert (string-contains? repClean "ALL VERIFICATION GATES PASSED CLEANLY") "Clean report must contain success header")
    (assert (string-contains? repFail "GATES FAILED") "Failed report must contain failure header")
    (assert (> (string-length repClean) 100) "Report length must be substantial")
    true))

(df testVerifyBalance [] -> Bool
  :d "Asserts verification of S-expression delimiter balance and sigil prohibition."
  (let [(validSrc "(df test-fn [] -> I64 42)")
        (unclosedSrc "(df test-fn [] -> I64 (+ 1 2)")
        (sigilSrc "(df test-fn [] -> Str @bad)")]
    (assert (g/verifyBalance validSrc) "Valid balanced ASL source must pass")
    (assert (not (g/verifyBalance unclosedSrc)) "Unclosed delimiter must fail")
    (assert (not (g/verifyBalance sigilSrc)) "Forbidden sigil @ must fail")
    true))

(df ! testVerifyManifests [] -> Bool
  :d "Asserts verification of package manifest structure and sigil hygiene."
  (let [(validMf "(:package asl-codec :version \"0.1.0\" :entry \"src/main.asl\")")
        (sigilMf "(:package @asl-codec :version \"0.1.0\" :entry \"src/main.asl\")")
        (invalidMf "(:not-a-package 123)")
        (realPaths (list "asl/packages/asl-gates/manifest.asn"))]
    (assert (g/verifyManifestString validMf) "Valid manifest string must pass")
    (assert (not (g/verifyManifestString sigilMf)) "Manifest with sigil must fail")
    (assert (not (g/verifyManifestString invalidMf)) "Malformed manifest must fail")
    (assert (g/verifyManifests realPaths) "Real package manifests must pass verification")
    true))

(df ! testRunAll [] -> Bool
  :d "Asserts run-all convenience function forwards to all 7 gates."
  (let [(sClean (gr/runAll 34 673 12 0 212 3223 29))
        (sFail (gr/runAll 0 673 12 0 212 3223 29))
        (sLive (gr/runLiveGateAudit))]
    (assert (.-allClean sClean) "gr/run-all clean must pass all 7 gates")
    (assert (= (.-passedGates sClean) 7) "gr/run-all clean passed count must be 7")
    (assert (not (.-allClean sFail)) "gr/run-all with 0 manifests must fail")
    (assert (= (.-totalGates sLive) 7) "gr/run-live-gate-audit total gates must be 7")
    (do (if (not (.-allClean sLive)) (file-write "tmp/gate_runner_fail.txt" (gr/formatGateSummary sLive))) (assert (.-allClean sLive) "gr/run-live-gate-audit must pass all 7 gates on live disk"))
    (assert (= (.-passedGates sLive) 7) "gr/run-live-gate-audit passed count must be 7")
    true))

(df ! testFaultInjectionGate4 [] -> Bool
  :d "Asserts fault injection: foreign file detection in path list causes Gate 4 rejection."
  (let [(mixed (list "asl/packages/asl-gates/src/gates.asl" "asl/packages/asl-gates/src/bad.py"))
        (detected (g/findForeignFilesInPaths mixed))]
    (assert (= (list-length detected) 1) "Foreign detector must detect simulated injected foreign file")
    (assert (list-contains? detected "asl/packages/asl-gates/src/bad.py") "bad.py must be detected")
    (refute (list-contains? detected "asl/packages/asl-gates/src/gates.asl") "gates.asl must not be flagged")
    true))

(df ! testZeroCommentAudit [] -> Bool
  :d "Asserts C3 Zero-Comment invariant audit detects Lisp comments (; and ;;) and ignores // or /*."
  (let [(cleanSrc "(df test-fn [] -> I64 42)")
        (semiSrc "(df test-fn [] -> I64 ; inline comment\n 42)")
        (doubleSemiSrc ";; Module comment\n(df test-fn [] -> I64 42)")
        (stringWithSemi "(df test-fn [] -> Str \"http://localhost:8080;foo\")")
        (slashSrc "(df test-fn [] -> Str \"// not a lisp comment\")")
        (violating (gr/auditZeroComments (list cleanSrc semiSrc doubleSemiSrc stringWithSemi slashSrc)))]
    (assert (gr/verifyZeroComments cleanSrc) "Clean ASL source must pass zero-comment check")
    (assert (gr/verifyZeroComments stringWithSemi) "Semicolon inside string literal must pass zero-comment check")
    (assert (gr/verifyZeroComments slashSrc) "String with // must pass zero-comment check")
    (assert (not (gr/verifyZeroComments semiSrc)) "Single semicolon comment must fail zero-comment check")
    (assert (not (gr/verifyZeroComments doubleSemiSrc)) "Double semicolon comment must fail zero-comment check")
    (assert (gr/hasComment? semiSrc) "Single semicolon must be identified as comment")
    (assert (gr/hasComment? doubleSemiSrc) "Double semicolon must be identified as comment")
    (refute (gr/hasComment? cleanSrc) "Clean code must refute having comment")
    (refute (gr/hasComment? stringWithSemi) "Code with semicolon in string must refute having comment")
    (assert (= (list-length violating) 2) "auditZeroComments must detect exactly 2 violating sources with Lisp comments")
    (assert (list-contains? violating semiSrc) "semiSrc must be in violating list")
    (assert (list-contains? violating doubleSemiSrc) "doubleSemiSrc must be in violating list")
    (refute (list-contains? violating cleanSrc) "cleanSrc must not be in violating list")
    (refute (list-contains? violating stringWithSemi) "stringWithSemi must not be in violating list")
    true))

(df ! runTests [] -> Bool
  :d "Master test runner executing all gate runner assertion suites."
  (let [(r1 (testAllGatesPass))
        (r2 (testGateFailFast))
        (r3 (testExtensionlessAudit))
        (r4 (testDeadCodeAudit))
        (r5 (testSummaryFormatting))
        (r6 (testVerifyBalance))
        (r7 (testVerifyManifests))
        (r8 (testRunAll))
        (r9 (testFaultInjectionGate4))
        (r10 (testZeroCommentAudit))]
    (and r1 (and r2 (and r3 (and r4 (and r5 (and r6 (and r7 (and r8 (and r9 r10)))))))))))
