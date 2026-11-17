(module asl-cli/tests/testSelectTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref TEST-RUNNER-SELECT :do "asl test FILE --only NAME runs one test function of the file: the fixture threeFns has testFirst (1 assertion), testSecond (fails at its second assertion) and testThird (2 assertions), so each count and message names the function that ran; an unknown name is refused with the names it could have been, and a selected pass never reads as N assertion(s) executed, the suite-pass evidence audit gates and sweeps count")
fn fixture -> String
  "asl/packages/asl-cli/tests/fixtures/testSelect/threeFns.asl"

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslTest! args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str (repoRoot!) "/bin/asl") "test") args) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testOnlySelects! -> Bool
  (let [(thirdRun (aslTest! (list (fixture) "--only" "testThird")))
        (firstRun (aslTest! (list (fixture) "--only" "testFirst")))
        (secondRun (aslTest! (list (fixture) "--only" "testSecond")))]
    (do (assert (= thirdRun.exit 0) (str "--only testThird passes although testSecond fails: " thirdRun.out))
        (assert (stringContains? thirdRun.out (str (fixture) " --only testThird: 2 assertion(s) ran in testThird, 0 refutation(s) ran (selected function, not a suite pass)")) (str "the summary names the function and counts its 2 assertions: " thirdRun.out))
        (assert (= (fr/executedOf thirdRun.out) (none)) (str "a selected pass carries no N assertion(s) executed line, so a gate reading it finds no suite pass: " thirdRun.out))
        (assert (stringContains? firstRun.out "1 assertion(s) ran in testFirst") (str "testFirst counts only its own assertion: " firstRun.out))
        (assert (!= secondRun.exit 0) (str "--only testSecond fails: " secondRun.out))
        (assert (stringContains? secondRun.out (str "FAIL " (fixture) " --only testSecond: ERR_ASSERT: assertion failed: second breaks on purpose (after 2 asserts)")) (str "the failure names the function and counts its asserts: " secondRun.out))
        true))

fn ! testUnknownNameRefused! -> Bool
  (let [(nope (aslTest! (list (fixture) "--only" "nope")))
        (bare (aslTest! (list (fixture) "--only")))
        (two (aslTest! (list (fixture) "asl/packages/asl-cli/tests/fixtures/testOk.asl" "--only" "testThird")))]
    (do (assert (= nope.exit 2) (str "an unknown name exits 2: " nope.out))
        (assert (stringContains? nope.out "ERR_UNKNOWN_TEST") (str "an unknown name is ERR_UNKNOWN_TEST: " nope.out))
        (assert (stringContains? nope.out ":available (testFirst testSecond testThird)") (str "the refusal lists the test functions, without runTests or a helper taking parameters: " nope.out))
        (assert (and (= bare.exit 2) (stringContains? bare.out "--only needs a test function name")) (str "--only without a name is a usage error: " bare.out))
        (assert (and (= two.exit 2) (stringContains? two.out "--only selects a function of one file")) (str "--only with two files is a usage error: " two.out))
        true))

fn ! testWholeSuiteUnchanged! -> Bool
  (let [(whole (aslTest! (list (fixture))))]
    (do (assert (= whole.exit 1) (str "the whole file still fails: " whole.out))
        (assert (stringContains? whole.out (str "FAIL " (fixture) ": ERR_ASSERT: assertion failed: second breaks on purpose (after 3 asserts)")) (str "the whole-file FAIL line is the one asl test printed before --only existed: " whole.out))
        (refute (stringContains? whole.out "--only") (str "a run without --only says nothing of it: " whole.out))
        true))

fn ! runTests -> Bool
  (and (testOnlySelects!) (and (testUnknownNameRefused!) (testWholeSuiteUnchanged!)))
