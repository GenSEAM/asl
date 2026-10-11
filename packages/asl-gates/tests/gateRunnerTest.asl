(module asl-gates/tests/gateRunnerTest :x [testAllGatesPass testGateFailFast testExtensionlessAudit testDeadCodeAudit testSummaryFormatting testVerifyBalance testVerifyManifests testRunAll testFaultInjectionGate4 runTests] :i [(gateRunner :a gr) (shebangAudit :a sa) (gates :a g) (tools/fleet/run :a fr)])

fn testAllGatesPass -> Bool
  (let [(summary (gr/runAllGates 34 673 12 0 212 3223 29))] (assert summary.allClean "All 7 gates clean must report all-clean true") (assert (= summary.totalGates 7) "Total gates count must equal 7") (assert (= summary.passedGates 7) "Passed gates count must equal 7") (assert (= (listLength summary.verdicts) 7) "Verdicts list length must equal 7") (let [(s7 (gr/runAllSevenGates 10 100 15 0 50 1500 20))] (assert s7.allClean "run-all-seven-gates must pass when all criteria met") (assert (= s7.passedGates 7) "run-all-seven-gates passed gates must be 7")) true)

fn testGateFailFast -> Bool
  (let [(sNoManifests (gr/runAllGates 0 673 12 0 212 3223 29)) (sNoAsl (gr/runAllGates 34 0 12 0 212 3223 29)) (sFewClaims (gr/runAllGates 34 673 5 0 212 3223 29)) (sForeignFiles (gr/runAllGates 34 673 12 3 212 3223 29)) (sNoTests (gr/runAllGates 34 673 12 0 0 3223 29)) (sFewGrammar (gr/runAllGates 34 673 12 0 212 500 29)) (sFewSkills (gr/runAllGates 34 673 12 0 212 3223 4))] (assert (not sNoManifests.allClean) "0 manifests must fail gate 1") (assert (= sNoManifests.passedGates 6) "0 manifests must leave 6 passed gates") (assert (not sNoAsl.allClean) "0 ASL files must fail gate 2") (assert (= sNoAsl.passedGates 6) "0 ASL files must leave 6 passed gates") (assert (not sFewClaims.allClean) "<12 claims must fail gate 3") (assert (not sForeignFiles.allClean) "Foreign files > 0 must fail gate 4") (assert (not sNoTests.allClean) "0 tests must fail gate 5") (assert (not sFewGrammar.allClean) "<= 1000 grammar symbols must fail gate 6") (assert (not sFewSkills.allClean) "<10 skills must fail gate 7") true)

fn testExtensionlessAudit -> Bool
  (let [(approved (list "asl" "agent" "gsa" "lens")) (elfHeader "\u007fELF\u0002\u0001\u0000") (peHeader "MZ\u0090\u0000\u0003\u0000") (shHeader "#!/usr/bin/env bash\nexec asl \"$@\"") (aslShHeader "#!/usr/bin/env asl\n(println 1)") (badShHeader "#!/usr/bin/python\nimport os")] (assert (sa/isBinaryBlob elfHeader) "ELF header must be detected as binary blob") (assert (sa/isBinaryBlob peHeader) "PE MZ header must be detected as binary blob") (assert (not (sa/isBinaryBlob shHeader)) "Bash script must not be detected as binary blob") (assert (sa/auditShebang shHeader) "Approved bash shebang must pass audit") (assert (sa/auditShebang aslShHeader) "Approved asl shebang must pass audit") (assert (not (sa/auditShebang badShHeader)) "Python shebang must fail audit") (assert (sa/isApprovedForwarder "asl" approved) "asl must be approved forwarder") (assert (sa/isApprovedForwarder "agent" approved) "agent must be approved forwarder") (assert (not (sa/isApprovedForwarder "claude-standalone" approved)) "claude-standalone must be rejected") (assert (not (sa/isApprovedForwarder "eddie" approved)) "eddie must be rejected") (let [(unapproved (gr/auditExtensionlessBinaries (list "asl" "rogue" "bin/eddie") approved))] (assert (= (listLength unapproved) 2) "Two unapproved binaries must be flagged") (assert (listContains? unapproved "rogue") "rogue binary must be in unapproved list") (assert (listContains? unapproved "bin/eddie") "eddie must be in unapproved list")) true)

fn testDeadCodeAudit -> Bool
  (let [(exports (list "live-fn" "orphan-fn" "unused-helper")) (callers (list "live-fn" "other-fn")) (orphans (gr/auditDeadCode exports callers))] (assert (= (listLength orphans) 2) "Two orphan functions must be detected") (assert (listContains? orphans "orphan-fn") "orphan-fn must be detected") (assert (listContains? orphans "unused-helper") "unused-helper must be detected") (assert (not (listContains? orphans "live-fn")) "live-fn must not be in orphan list") true)

fn testSummaryFormatting -> Bool
  (let [(sClean (gr/runAllGates 34 673 12 0 212 3223 29)) (sFail (gr/runAllGates 0 0 0 1 0 0 0)) (repClean (gr/formatGateSummary sClean)) (repFail (gr/formatGateSummary sFail))] (assert (stringContains? repClean "ALL VERIFICATION GATES PASSED CLEANLY") "Clean report must contain success header") (assert (stringContains? repFail "GATES FAILED") "Failed report must contain failure header") (assert (> (stringLength repClean) 100) "Report length must be substantial") true)

fn testVerifyBalance -> Bool
  (let [(validSrc "(fn test-fn [] -> I64 42)") (unclosedSrc "(fn test-fn [] -> I64 (+ 1 2)") (sigilSrc "(fn test-fn [] -> Str @bad)")] (assert (g/verifyBalance validSrc) "Valid balanced ASL source must pass") (assert (not (g/verifyBalance unclosedSrc)) "Unclosed delimiter must fail") (assert (not (g/verifyBalance sigilSrc)) "Forbidden sigil @ must fail") (assert (g/verifyBalance "([{}] \")]\")") "nested kinds and a quoted closer must pass") (refute (g/verifyBalance "(]") "mismatched closer kind must fail") (refute (g/verifyBalance "([)]") "crossed bracket kinds must fail") (refute (g/verifyBalance ")(") "closer before opener must fail") true)

fn ! testVerifyManifests -> Bool
  (let [(validMf "(:package asl-transpile :version \"0.1.0\" :entry \"src/main.asl\")") (sigilMf "(:package @asl-transpile :version \"0.1.0\" :entry \"src/main.asl\")") (invalidMf "(:not-a-package 123)") (realPaths (list "asl/packages/asl-gates/manifest.asn"))] (assert (g/verifyManifestString validMf) "Valid manifest string must pass") (assert (not (g/verifyManifestString sigilMf)) "Manifest with sigil must fail") (assert (not (g/verifyManifestString invalidMf)) "Malformed manifest must fail") (assert (ok? (g/verifyManifests realPaths)) "Real package manifests must pass verification") true)

fn ! testRunAll -> Bool
  (let [(scratch "asl/packages/asl-gates/tests/gateRunnerFixture")
        (passPath (str scratch "/gateRunnerPassTest.asl"))
        (failPath (str scratch "/gateRunnerFailTest.asl"))
        (marker (str scratch "/passingSuiteRan"))
        (cleaned (pathRemove scratch))
        (made (dirCreate scratch))
        (passWritten (fileWrite passPath "(module asl-gates/tests/gateRunnerFixture/gateRunnerPassTest :x [runTests])\nfn runTests -> Bool\n  (assert (= (stringLength \"fixture\") 7) \"fixture passes\")\n  true\n"))
        (failWritten (fileWrite failPath "(module asl-gates/tests/gateRunnerFixture/gateRunnerFailTest :x [runTests])\nfn runTests -> Bool\n  (assert false \"deliberate fixture failure\")\n  true\n"))
        (buildCommand (fn [(p Str)] -> fr/Job (fr/job (list "/bin/sh" "-c" (str "bin/asl test " p (if (= p passPath) (str " && printf passed > " marker) ""))) "." (fr/childEnv (list)))))
        (verdict (gr/auditSuitePaths (list failPath passPath) buildCommand))
        (markerStat (fileStat marker))
        (markerText (fileRead marker))
        (passVerdict (gr/auditSuitePaths (list passPath) buildCommand))
        (emptyVerdict (gr/auditSuitePaths (list) buildCommand))
        (removed (pathRemove scratch))
        (sClean (gr/runAll 34 673 12 0 212 3223 29))
        (sFail (gr/runAll 0 673 12 0 212 3223 29))]
    (assert sClean.allClean "gr/run-all clean must pass all 7 gates")
    (assert (= sClean.passedGates 7) "gr/run-all clean passed count must be 7")
    (assert (not sFail.allClean) "gr/run-all with 0 manifests must fail")
    (assert (ok? made) "scratch suite fixture directory must be created")
    (assert (ok? passWritten) "passing scratch suite must be written")
    (assert (ok? failWritten) "failing scratch suite must be written")
    (assert (not verdict.passed) "a failing scratch suite must fail gate 5")
    (assert (stringContains? verdict.message "1 of 2 gate test suites failed") "gate 5 must count exactly one failed suite")
    (assert (mt markerStat ((ok stat) stat.isFile) ((err _) false)) "gate 5 must run every suite after encountering a failure")
    (assert (= (resultOr markerText "") "passed") "the passing suite after the failure must finish")
    (assert (and (= verdict.gateNum 5) (= verdict.gateName "Pure ASL Gate Test Suite")) "failure verdict must identify gate 5")
    (assert (stringContains? verdict.message "bin/asl test exited 1:") "gate 5 must report the command's failing exit line")
    (refute (stringContains? verdict.message passPath) "gate 5 must not include the passing suite in failures")
    (assert passVerdict.passed "the same builder must pass the passing scratch suite")
    (assert (= passVerdict.gateNum 5) "passing verdict must identify gate 5")
    (assert (stringContains? passVerdict.message "1 test suites executed") "passing verdict must report the number of executed suites")
    (refute (stringContains? passVerdict.message failPath) "passing verdict must not mention the failing fixture")
    (assert (not emptyVerdict.passed) "an empty suite list must fail gate 5")
    (assert (= emptyVerdict.gateNum 5) "empty-suite verdict must identify gate 5")
    (assert (stringContains? emptyVerdict.message "No gate test suites found") "empty-suite failure must be explained")
    true)

fn ! testFaultInjectionGate4 -> Bool
  (let [(mixed (list "asl/packages/asl-gates/src/gates.asl" "asl/packages/asl-gates/src/bad.py")) (detected (g/findForeignFilesInPaths mixed))] (assert (= (listLength detected) 1) "Foreign detector must detect simulated injected foreign file") (assert (listContains? detected "asl/packages/asl-gates/src/bad.py") "bad.py must be detected") (refute (listContains? detected "asl/packages/asl-gates/src/gates.asl") "gates.asl must not be flagged") true)

fn ! runTests -> Bool
  (let [(r1 (testAllGatesPass)) (r2 (testGateFailFast)) (r3 (testExtensionlessAudit)) (r4 (testDeadCodeAudit)) (r5 (testSummaryFormatting)) (r6 (testVerifyBalance)) (r7 (testVerifyManifests)) (r8 (testRunAll)) (r9 (testFaultInjectionGate4))] (and r1 (and r2 (and r3 (and r4 (and r5 (and r6 (and r7 (and r8 r9)))))))))
