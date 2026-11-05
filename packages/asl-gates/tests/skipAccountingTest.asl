(module asl-gates/tests/skipAccountingTest
  :x [runTests]
  :i [(asl-gates/suiteRunner :a sr) (asl-gates/runnerLedger :a rl) (asl-gates/auditGates :a ag) (asl-gates/runnerMain :a rm)])

; (:m :ref SKIP-AND-CONSTANT :do "only a suite listed in .asl/mem/skipAllowed.asn is SKIPPED (zero asserts, not a pass, no red check); an unlisted skip row is ERR_SKIP_NOT_ALLOWED; a skip row never hides a failing cause; a run of only skips fails ERR_ALL_SKIPPED in the runner receipt and in audit gates; knownRed capture never records a skip; a fullGreen record carries :skipped N; a suite whose every executed assert is the literal true is ERR_CONSTANT_ASSERT")
fn ! fixture! dir: String name: String body: String -> Bool
  (ok? (fileWrite (str dir "/" name) (str "(module fx\n  :x [runTests]\n  :i [])\n\nfn ! runTests -> Bool\n  (do " body "\n      true))\n")))

fn okOut name: String n: Int64 -> String
  (str name ": " (stringFromInt64 n) " assertion(s) executed (" (stringFromInt64 n) " passed)\n")

fn skipLine -> String
  "(:skip :suite x :why \"off\")\n"

fn ! testRunner! dir: String -> Bool
  (let [(rows (str "(:skipAllowedRule :do \"x\")\n"
                   "(:skip :suite \"markSkip.sh\" :unless (:fileHas \"" dir "/flagNo\" \"go\") :why \"flag says no\")\n"
                   "(:skip :suite \"markRun.sh\" :unless (:fileHas \"" dir "/flagYes\" \"go\") :why \"flag says yes\")\n"
                   "(:skip :suite \"echoTest.asl\" :unless (:fileHas \"" dir "/flagYes\" \"go\") :why \"flag says yes\")\n"
                   "(:skip :suite \"envTest.asl\" :unless (:env \"ASL_SKIP_FIXTURE_NEVER_SET\" \"1\") :why \"env unset\")\n"))
        (_ (dirCreate (str dir "/.asl")))
        (_ (dirCreate (str dir "/.asl/mem")))
        (_ (fileWrite (str dir "/.asl/mem/skipAllowed.asn") rows))
        (_ (fileWrite (str dir "/flagNo") "no\n"))
        (_ (fileWrite (str dir "/flagYes") "go\n"))
        (_ (fileWrite (str dir "/markSkip.sh") (str "#!/bin/sh\necho ran > " dir "/markSkip.marker\n")))
        (_ (fileWrite (str dir "/markRun.sh") (str "#!/bin/sh\necho ran > " dir "/markRun.marker\n")))
        (_ (fixture! dir "echoTest.asl" "(println \"x\")"))
        (_ (fixture! dir "envTest.asl" "(println \"x\")"))
        (_ (fixture! dir "plainTest.asl" "(assert (= 1 1) \"real\")"))
        (_ (fixture! dir "constTest.asl" "(assert true \"always\")"))
        (skipDec (sr/skipDecision! dir "markSkip.sh"))
        (runDec (sr/skipDecision! dir "markRun.sh"))
        (envDec (sr/skipDecision! dir "envTest.asl"))
        (plainDec (sr/skipDecision! dir "plainTest.asl"))
        (skipJob (sr/suiteJob! dir "markSkip.sh" 30))
        (runJob (sr/suiteJob! dir "markRun.sh" 30))
        (skipDone (sr/runOne! skipJob))
        (runDone (sr/runOne! runJob))
        (skipRes (sr/toResult! dir dir "markSkip.sh" (match skipDone ((ok d) d) ((err _) (sr/Done :code 1 :out "" :errText "" :merged "" :startNs 0 :endNs 0))) skipDec))
        (echoOut (str "(:skip :suite child :why \"echo\")\n"))
        (echoZero (sr/aslResult! dir "echoTest.asl" 1 (str echoOut "FAIL echoTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n")))
        (echoQuiet (sr/aslResult! dir "echoTest.asl" 0 echoOut))
        (echoFail (sr/aslResult! dir "plainTest.asl" 1 (str echoOut "FAIL plainTest.asl: ERR_ASSERT: boom (after 2 asserts)\n")))
        (echoOk (sr/aslResult! dir "plainTest.asl" 0 (str echoOut (okOut "plainTest.asl" 1))))
        (const (sr/aslResult! dir "constTest.asl" 0 (okOut "constTest.asl" 1)))]
    (do (assert (some? skipDec) "a false precondition (file lacks the text) says skip")
        (assert (none? runDec) "a true precondition says run")
        (assert (some? envDec) "an unset env precondition says skip")
        (assert (none? plainDec) "a suite with no row always runs")
        (assert (not (fileExists? (str dir "/markSkip.marker"))) "a suite with a false precondition is not executed: its marker file is never written")
        (assert (fileExists? (str dir "/markRun.marker")) "a suite with a true precondition is executed: its marker file is written")
        (assert (and (ok? skipDone) (ok? runDone)) "both fixture jobs ran to completion")
        (assert (= skipRes.cause "SKIPPED") (str "the runner reports SKIPPED: " skipRes.cause))
        (assert (and (= skipRes.asserts 0) (= skipRes.failed 0)) "a skipped suite has 0 asserts and is not failed")
        (assert (= echoZero.cause "ERR_VACUOUS_SUITE") (str "a run suite whose last line echoes a child skip row with 0 asserts is vacuous: " echoZero.cause))
        (assert (= echoZero.failed 1) "and it is failed")
        (assert (= echoQuiet.cause "ERR_VACUOUS_SUITE") (str "a skip row alone, exit 0, no assertion line is vacuous: " echoQuiet.cause))
        (assert (= echoFail.cause "ASSERTION_FAILURE") (str "a skip row never hides a failure: " echoFail.cause))
        (assert (and (= echoOk.cause "OK") (= echoOk.asserts 1)) "a skip row in the output of a passing suite has no effect")
        (assert (= (sr/gateCounts "SKIPPED" 0 0 0 0) (pair 0 0)) "gate counts of a skip are 0 asserts 0 failed")
        (assert (= const.cause "ERR_CONSTANT_ASSERT") (str "a suite of one constant assert is flagged: " const.cause))
        true))

; (:m :ref SKIP-DECIDED-ONCE :do "through snapRun on a temp git repo: a suite that fails and then rewrites its own precondition file stays a failed run, a suite whose precondition is false is not executed and is SKIPPED")
fn ! testSnap! dir: String -> Bool
  (let [(repo (str dir "/snaprepo"))
        (flag (str dir "/snapFlag"))
        (flag2 (str dir "/snapFlagNever"))
        (_ (dirCreate repo))
        (_ (dirCreate (str repo "/.asl")))
        (_ (dirCreate (str repo "/.asl/mem")))
        (_ (fileWrite flag "go\n"))
        (_ (fileWrite (str repo "/.asl/mem/skipAllowed.asn") (str "(:skip :suite \"flipTest.sh\" :unless (:fileHas \"" flag "\" \"go\") :why \"w\")\n(:skip :suite \"neverTest.sh\" :unless (:fileHas \"" flag2 "\" \"go\") :why \"w\")\n")))
        (_ (fileWrite (str repo "/flipTest.sh") (str "#!/bin/sh\necho no > " flag "\necho \"(:gate :name \\\"flipTest.sh\\\" :asserts 1 :failed 1)\"\nexit 1\n")))
        (_ (fileWrite (str repo "/neverTest.sh") (str "#!/bin/sh\necho ran > " dir "/neverMarker\nexit 0\n")))
        (g1 (sh! repo (list "init" "-q")))
        (g2 (sh! repo (list "add" "-A")))
        (g3 (sh! repo (list "-c" "user.name=t" "-c" "user.email=t" "commit" "-q" "-m" "seed")))
        (run (sr/snapRun repo (list "flipTest.sh" "neverTest.sh") 1 0))
        (flipped (resultOr (fileReadString flag) ""))
        (results (match run ((ok r) r.results) ((err _) (list))))
        (find (fn [(s String)] -> String (match (listHead (filter (fn [(r sr/SuiteResult)] -> Bool (= r.suite s)) results)) ((some r) r.cause) ((none) "MISSING"))))]
    (do (assert (and g1 g2 g3) "snap fixture repo")
        (assert (ok? run) "snapRun ran the fixture")
        (assert (stringContains? flipped "no") "the failing suite really rewrote its own precondition file")
        (assert (!= (find "flipTest.sh") "SKIPPED") (str "a run that rewrites its precondition file is not reported SKIPPED: " (find "flipTest.sh")))
        (assert (!= (find "flipTest.sh") "OK") (str "and the failing suite is red: " (find "flipTest.sh")))
        (assert (= (find "neverTest.sh") "SKIPPED") (str "a false precondition through snapRun is SKIPPED: " (find "neverTest.sh")))
        (assert (not (fileExists? (str dir "/neverMarker"))) "and its suite was never executed")
        true))

fn ! testLedger! -> Bool
  (let [(skip (sr/makeSuiteResult "a/skipTest.asl" "SKIPPED" "" "(:skip :suite x)" 2 0 2 0))
        (pass (sr/makeSuiteResult "a/okTest.asl" "OK" "" "" 3 0 3 0))
        (mixed (rl/reconcile! (list skip pass) (list) ""))
        (onlySkip (rl/reconcile! (list skip) (list) ""))
        (mixedText (pairFirst (rl/receipt (list skip pass) mixed.checks 0 0 "" "" "scope" 0)))
        (skipText (pairFirst (rl/receipt (list skip) onlySkip.checks 0 0 "" "" "scope" 0)))
        (auditSkip (ag/suiteGateChecks! "gate5Suites" (list skip) (list) ""))
        (auditMixed (ag/suiteGateChecks! "gate5Suites" (list skip pass) (list) ""))]
    (do (assert (listEmpty? mixed.checks) "a skipped suite raises no red check")
        (assert (stringContains? mixedText ":skippedSuites 1") (str "skips are counted apart from passes: " mixedText))
        (assert (stringContains? mixedText ":executedAsserts 3") "a skip adds no executed asserts even when it ran some")
        (assert (stringContains? mixedText ":skippedAsserts 2") (str "the asserts that ran in a skip are reported apart: " mixedText))
        (assert (stringContains? mixedText "(:runner :status :passed") "skips plus a pass is green")
        (assert (stringContains? skipText "(:runner :status :failed") "only skips is not green")
        (assert (stringContains? skipText "ERR_ALL_SKIPPED") (str "only skips names ERR_ALL_SKIPPED: " skipText))
        (assert (= (listLength auditSkip) 1) "audit gates: one check for an all-skipped scope")
        (assert (let [(c (optionOr (listHead auditSkip) (ag/passCheck "x" (none) (none))))] (and (= c.status ":failed") (stringContains? (ag/fmtCheck c) "ERR_ALL_SKIPPED"))) "audit gates: an all-skipped scope fails ERR_ALL_SKIPPED")
        (assert (let [(c (optionOr (listHead auditMixed) (ag/failCheck "x" "E" "e" (none) (none))))] (= c.status ":passed")) "audit gates: skips plus a pass is green")
        true))

fn ! testCapture! -> Bool
  (let [(skip (sr/makeSuiteResult "a/skipTest.asl" "SKIPPED" "" "" 0 0 0 0))
        (red (sr/makeSuiteResult "a/redTest.asl" "ASSERTION_FAILURE" "d" "f" 1 0 1 1))
        (ok (sr/makeSuiteResult "a/okTest.asl" "OK" "" "" 1 0 1 0))]
    (do (assert (not (rm/redForCapture? skip)) "knownRed capture never records a skipped suite")
        (assert (rm/redForCapture? red) "knownRed capture still records a failure")
        (assert (not (rm/redForCapture? ok)) "knownRed capture skips a pass")
        true))

fn ! sh! dir: String args: (List String) -> Bool
  (match (sr/gitRun! dir args) ((ok d) (= d.code 0)) ((err _) false))

fn ! testRecord! dir: String -> Bool
  (let [(repo (str dir "/rec"))
        (_ (dirCreate repo))
        (a (sh! repo (list "init" "-q")))
        (_ (fileWrite (str repo "/aTest.asl") "x\n"))
        (_ (fileWrite (str repo "/bTest.asl") "y\n"))
        (b (sh! repo (list "add" "-A")))
        (c (sh! repo (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "-q" "-m" "seed")))
        (ok (sr/makeSuiteResult "aTest.asl" "OK" "" "" 3 0 3 0))
        (skip (sr/makeSuiteResult "bTest.asl" "SKIPPED" "" "" 0 0 0 0))
        (wrote (ag/writeRecord! repo (list ok skip)))
        (text (match wrote ((ok rel) (resultOr (fileReadString (str repo "/" rel)) "")) ((err e) e)))]
    (do (assert (and a b c) "record fixture repo")
        (assert (stringContains? text ":suites 2 :skipped 1 ") (str "a fullGreen record with a skipped suite says :skipped 1: " text))
        true))

; (:m :ref SKIP-ALLOWLIST-PIN :do "the tracked allowlist is exactly the two e2e suites, growth means editing this test in plain view")
fn ! testPin! -> Bool
  (let [(text (resultOr (fileReadString ".asl/mem/skipAllowed.asn") "MISSING"))
        (paths (listSort (sr/skipAllowedPaths text)))]
    (do (assert (= paths (list "asl/tools/coord/tests/e2eSmokeTest.asl" "tools/remote/tests/vpsE2eTest.asl")) (str "skipAllowed.asn lists exactly e2eSmokeTest and vpsE2eTest: " (stringJoin paths " ")))
        true))

fn ! runTests -> Bool
  (match (sr/makeTempDir! "skipFx")
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (let [(a (testRunner! dir))
            (b (testLedger!))
            (c (testCapture!))
            (d (testRecord! dir))
            (h (testSnap! dir))
            (e (testPin!))
            (_ (pathRemove dir))]
        (do (assert a "runner results")
            (assert b "ledger accounting")
            (assert c "knownRed capture")
            (assert d "fullGreen record")
            (assert h "decided once through snapRun")
            (assert e "allowlist pinned")
            true))))
