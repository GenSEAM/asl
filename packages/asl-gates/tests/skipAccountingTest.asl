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
  (let [(_ (dirCreate (str dir "/.asl")))
        (_ (dirCreate (str dir "/.asl/mem")))
        (_ (fileWrite (str dir "/.asl/mem/skipAllowed.asn") "(:skipAllowedRule :do \"x\")\n(:skipAllowed :suite \"skipOneTest.asl\" :why \"w\" :precondition \"p\")\n(:skipAllowed :suite \"skipZeroTest.asl\" :why \"w\" :precondition \"p\")\n"))
        (_ (fixture! dir "skipOneTest.asl" "(assert (= 1 1) \"cause still holds\")"))
        (_ (fixture! dir "skipZeroTest.asl" "(println \"skip\")"))
        (_ (fixture! dir "rogueTest.asl" "(assert (= 1 1) \"cause still holds\")"))
        (_ (fixture! dir "constTest.asl" "(assert true \"always\")"))
        (_ (fixture! dir "realTest.asl" "(assert (= 1 1) \"real\")"))
        (skipOne (sr/aslResult! dir "skipOneTest.asl" 0 (str (skipLine) (okOut "skipOneTest.asl" 1))))
        (skipZero (sr/aslResult! dir "skipZeroTest.asl" 1 (str (skipLine) "FAIL skipZeroTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n")))
        (rogue (sr/aslResult! dir "rogueTest.asl" 0 (str (skipLine) (okOut "rogueTest.asl" 1))))
        (rogueZero (sr/aslResult! dir "rogueTest.asl" 1 (str (skipLine) "FAIL rogueTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n")))
        (skipFail (sr/aslResult! dir "skipOneTest.asl" 1 (str (skipLine) "FAIL skipOneTest.asl: ERR_ASSERT: boom (after 2 asserts)\n")))
        (const (sr/aslResult! dir "constTest.asl" 0 (okOut "constTest.asl" 1)))
        (real (sr/aslResult! dir "realTest.asl" 0 (okOut "realTest.asl" 1)))
        (echoMid (sr/aslResult! dir "skipOneTest.asl" 0 (str "child: (:skip :suite x :why \"c\")\n(:skip :suite child :why \"echo\")\nmore output\n" (okOut "skipOneTest.asl" 1))))
        (echoFail (sr/aslResult! dir "skipOneTest.asl" 1 (str "(:skip :suite child :why \"echo\")\nlater\nFAIL skipOneTest.asl: ERR_ASSERT: boom (after 2 asserts)\n")))
        (echoRogue (sr/aslResult! dir "rogueTest.asl" 0 (str "(:skip :suite child :why \"echo\")\nmore\n" (okOut "rogueTest.asl" 1))))
        (zero (sr/aslResult! dir "skipZeroTest.asl" 1 "FAIL skipZeroTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n"))]
    (do (assert (= skipOne.cause "SKIPPED") (str "a listed suite with a skip row is SKIPPED: " skipOne.cause))
        (assert (= skipOne.asserts 1) "a skipped suite still reports the asserts that ran")
        (assert (= skipZero.cause "SKIPPED") (str "a listed skip with zero asserts is SKIPPED, not vacuous: " skipZero.cause))
        (assert (= rogue.cause "ERR_SKIP_NOT_ALLOWED") (str "a skip row from an unlisted suite is red: " rogue.cause))
        (assert (= rogue.failed 1) "an unlisted skip is failed")
        (assert (= rogueZero.cause "ERR_SKIP_NOT_ALLOWED") (str "an unlisted zero-assert skip is red too: " rogueZero.cause))
        (assert (= skipFail.cause "ASSERTION_FAILURE") (str "a skip row never turns a failing suite into SKIPPED: " skipFail.cause))
        (assert (= (sr/gateCounts "SKIPPED" 0 2 0 0) (pair 2 0)) "gate counts of a skip are the asserts that ran, 0 failed")
        (assert (= echoMid.cause "OK") (str "a skip row echoed mid-output does not skip the suite: " echoMid.cause))
        (assert (= echoMid.asserts 1) "an echoing suite keeps its asserts")
        (assert (= echoFail.cause "ASSERTION_FAILURE") (str "an echoed skip row does not hide a failure: " echoFail.cause))
        (assert (= echoRogue.cause "OK") (str "an unlisted suite echoing a skip row mid-output is just a pass, not ERR_SKIP_NOT_ALLOWED: " echoRogue.cause))
        (assert (= const.cause "ERR_CONSTANT_ASSERT") (str "a suite of one constant assert is flagged: " const.cause))
        (assert (= const.failed 1) "a constant-assert suite is failed")
        (assert (= real.cause "OK") (str "a real assert passes: " real.cause))
        (assert (= real.asserts 1) "a real suite executes its assert")
        (assert (= zero.cause "ERR_VACUOUS_SUITE") (str "zero asserts without a skip row stays vacuous: " zero.cause))
        true))

fn ! testLedger! -> Bool
  (let [(skip (sr/makeSuiteResult "a/skipTest.asl" "SKIPPED" "" "(:skip :suite x)" 0 0 0 0))
        (pass (sr/makeSuiteResult "a/okTest.asl" "OK" "" "" 3 0 3 0))
        (mixed (rl/reconcile! (list skip pass) (list) ""))
        (onlySkip (rl/reconcile! (list skip) (list) ""))
        (mixedText (pairFirst (rl/receipt (list skip pass) mixed.checks 0 0 "" "" "scope" 0)))
        (skipText (pairFirst (rl/receipt (list skip) onlySkip.checks 0 0 "" "" "scope" 0)))
        (auditSkip (ag/suiteGateChecks! "gate5Suites" (list skip) (list) ""))
        (auditMixed (ag/suiteGateChecks! "gate5Suites" (list skip pass) (list) ""))]
    (do (assert (listEmpty? mixed.checks) "a skipped suite raises no red check")
        (assert (stringContains? mixedText ":skippedSuites 1") (str "skips are counted apart from passes: " mixedText))
        (assert (stringContains? mixedText ":executedAsserts 3") "a skip adds no executed asserts")
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

fn ! runTests -> Bool
  (match (sr/makeTempDir! "skipFx")
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (let [(a (testRunner! dir))
            (b (testLedger!))
            (c (testCapture!))
            (d (testRecord! dir))
            (_ (pathRemove dir))]
        (do (assert a "runner results")
            (assert b "ledger accounting")
            (assert c "knownRed capture")
            (assert d "fullGreen record")
            true))))
