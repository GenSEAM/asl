(module asl-cli/tests/testKeepGoingTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref TEST-RUNNER-SELECT :do "asl test FILE --keep-going executes every assertion: the fixture twoFails fails an assertion in testEarly and in testLate and a refutation in testRefuted, and the run lists all three with file:line:col and message, exits non-zero and counts them in its FAIL line; without the flag the output is the two lines asl test printed before the flag existed")
fn fixture -> String
  "asl/packages/asl-cli/tests/fixtures/testSelect/twoFails.asl"

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslTest! args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str (repoRoot!) "/bin/asl") "test") args) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testKeepGoingListsAll! -> Bool
  (let [(kept (aslTest! (list (fixture) "--keep-going")))]
    (do (assert (!= kept.exit 0) (str "--keep-going with failures exits non-zero: " kept.out))
        (assert (stringContains? kept.out (str (fixture) ":4:7: ERR_ASSERT: assertion failed: early breaks on purpose")) (str "the first failure is listed with its site: " kept.out))
        (assert (stringContains? kept.out (str (fixture) ":10:7: ERR_ASSERT: assertion failed: late breaks on purpose")) (str "the failure after it is listed too: " kept.out))
        (assert (stringContains? kept.out (str (fixture) ":14:7: ERR_REFUTE: refutation failed: the refutation breaks on purpose")) (str "a failed refutation is listed too: " kept.out))
        (assert (stringContains? kept.out (str "FAIL " (fixture) ": ERR_ASSERT: 3 assertion(s) or refutation(s) failed, execution kept going (--keep-going) (after 4 asserts)")) (str "the FAIL line counts the three failures and all four assertions: " kept.out))
        true))

fn ! testKeepGoingWithOnly! -> Bool
  (let [(late (aslTest! (list (fixture) "--only" "testLate" "--keep-going")))]
    (do (assert (!= late.exit 0) (str "--only testLate --keep-going fails: " late.out))
        (assert (stringContains? late.out (str "FAIL " (fixture) " --only testLate: ERR_ASSERT: 1 assertion(s) or refutation(s) failed, execution kept going (--keep-going) (after 2 asserts)")) (str "the selected run counts its one failure: " late.out))
        (refute (stringContains? late.out "early breaks on purpose") (str "the selected run does not run testEarly: " late.out))
        true))

fn ! testDefaultUnchanged! -> Bool
  (let [(plain (aslTest! (list (fixture))))]
    (do (assert (= plain.exit 1) (str "the plain run fails: " plain.out))
        (assert (= (stringTrim plain.out) (str (fixture) ":4:7: ERR_ASSERT: assertion failed: early breaks on purpose\nFAIL " (fixture) ": ERR_ASSERT: assertion failed: early breaks on purpose (after 1 asserts)")) (str "without --keep-going the run stops at the first failure with exactly the output asl test gave before: " plain.out))
        true))

fn ! runTests -> Bool
  (and (testKeepGoingListsAll!) (and (testKeepGoingWithOnly!) (testDefaultUnchanged!)))
