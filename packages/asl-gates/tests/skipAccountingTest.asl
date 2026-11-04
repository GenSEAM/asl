(module asl-gates/tests/skipAccountingTest
  :x [runTests]
  :i [(asl-gates/suiteRunner :a sr) (asl-gates/runnerLedger :a rl)])

; (:m :ref SKIP-AND-CONSTANT :do "a suite that skips is SKIPPED, not passed, with zero executed asserts and no red check; a run of only skips fails ERR_ALL_SKIPPED; a suite whose every executed assert is the literal true is ERR_CONSTANT_ASSERT")
fn ! fixture! dir: String name: String body: String -> Bool
  (ok? (fileWrite (str dir "/" name) (str "(module fx\n  :x [runTests]\n  :i [])\n\nfn ! runTests -> Bool\n  (do " body "\n      true))\n")))

fn okOut name: String n: Int64 -> String
  (str name ": " (stringFromInt64 n) " assertion(s) executed (" (stringFromInt64 n) " passed)\n")

fn ! testRunner! dir: String -> Bool
  (let [(_ (fixture! dir "skipOneTest.asl" "(assert (= 1 1) \"cause still holds\")"))
        (_ (fixture! dir "skipZeroTest.asl" "(println \"skip\")"))
        (_ (fixture! dir "constTest.asl" "(assert true \"always\")"))
        (_ (fixture! dir "realTest.asl" "(assert (= 1 1) \"real\")"))
        (skipOne (sr/aslResult! dir "skipOneTest.asl" 0 (str "(:skip :suite x :why \"noConfig\")\n" (okOut "skipOneTest.asl" 1))))
        (skipZero (sr/aslResult! dir "skipZeroTest.asl" 1 "(:skip :suite x :why \"off\")\nFAIL skipZeroTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n"))
        (const (sr/aslResult! dir "constTest.asl" 0 (okOut "constTest.asl" 1)))
        (real (sr/aslResult! dir "realTest.asl" 0 (okOut "realTest.asl" 1)))
        (zero (sr/aslResult! dir "skipZeroTest.asl" 1 "FAIL skipZeroTest.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)\n"))]
    (do (assert (= skipOne.cause "SKIPPED") (str "a skip row with one passing assert is SKIPPED: " skipOne.cause))
        (assert (= skipOne.asserts 0) "a skipped suite executes zero asserts")
        (assert (= skipZero.cause "SKIPPED") (str "a skip row with zero asserts is SKIPPED, not vacuous: " skipZero.cause))
        (assert (= (sr/gateCounts "SKIPPED" 0 0 0 0) (pair 0 0)) "gate counts of a skip are 0 asserts 0 failed")
        (assert (= const.cause "ERR_CONSTANT_ASSERT") (str "a suite of one constant assert is flagged: " const.cause))
        (assert (= const.failed 1) "a constant-assert suite is failed")
        (assert (= real.cause "OK") (str "a real assert passes: " real.cause))
        (assert (= real.asserts 1) "a real suite executes its assert")
        (assert (= zero.cause "ERR_VACUOUS_SUITE") (str "zero asserts without a skip row stays vacuous: " zero.cause))
        true))

fn ! testLedger! -> Bool
  (let [(skip (sr/makeSuiteResult "a/skipTest.asl" "SKIPPED" "" "(:skip :why x)" 0 0 0 0))
        (pass (sr/makeSuiteResult "a/okTest.asl" "OK" "" "" 3 0 3 0))
        (mixed (rl/reconcile! (list skip pass) (list) ""))
        (onlySkip (rl/reconcile! (list skip) (list) ""))
        (mixedText (pairFirst (rl/receipt (list skip pass) mixed.checks 0 0 "" "" "scope" 0)))
        (skipText (pairFirst (rl/receipt (list skip) onlySkip.checks 0 0 "" "" "scope" 0)))]
    (do (assert (listEmpty? mixed.checks) "a skipped suite raises no red check")
        (assert (stringContains? mixedText ":skippedSuites 1") (str "skips are counted apart from passes: " mixedText))
        (assert (stringContains? mixedText ":executedAsserts 3") "a skip adds no executed asserts")
        (assert (stringContains? mixedText "(:runner :status :passed") "skips plus a pass is green")
        (assert (stringContains? skipText "(:runner :status :failed") "only skips is not green")
        (assert (stringContains? skipText "ERR_ALL_SKIPPED") (str "only skips names ERR_ALL_SKIPPED: " skipText))
        (assert (stringContains? skipText ":skippedSuites 1") "only skips executes and passes nothing")
        true))

fn ! runTests -> Bool
  (match (sr/makeTempDir! "skipFx")
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (let [(a (testRunner! dir))
            (b (testLedger!))
            (_ (pathRemove dir))]
        (do (assert a "runner results")
            (assert b "ledger accounting")
            true))))
