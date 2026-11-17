(module asl-cli/tests/testVerdictChannelTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/nativeTest :a nt)])

; (:m :ref TEST-RUNNER-SELECT :do "the asl test verdict rests on what the test program cannot forge: the exit status the runtime forces non-zero after a failure it kept going past and the failed count of the report record it writes last, on a fresh line. Covers the grader's fixture (fail, unterminated stderr write, true) under --keep-going and under an inherited ASL_ASSERT_KEEP_GOING, forged records, a binary that closed its fds under --wall, stale selection copies, and the default output of a passing, a failing and a signal-killed fixture")
fn dir -> String
  "asl/packages/asl-cli/tests/fixtures/testSelect/"

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslTestEnv! args: (List String) env: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str (repoRoot!) "/bin/asl") "test") args) (repoRoot!) (fr/childEnv env)) (fr/limits 900 64))

fn ! aslTest! args: (List String) -> fr/Done
  (aslTestEnv! args (list))

fn passLine? out: String -> Bool
  (stringContains? out " assertion(s) executed (")

fn ! testUnterminatedKeepGoing! -> Bool
  (let [(run (aslTest! (list (str (dir) "partial.asl") "--keep-going" "--stats")))]
    (do (assert (!= run.exit 0) (str "a failed assertion followed by an unterminated stderr write fails under --keep-going: " run.out))
        (refute (passLine? run.out) (str "no suite pass line: " run.out))
        (assert (stringContains? run.out (str "FAIL " (dir) "partial.asl: ERR_ASSERT: 1 assertion(s) or refutation(s) failed, execution kept going (--keep-going) (after 1 asserts)")) (str "the FAIL line counts the kept failure: " run.out))
        (assert (stringContains? run.out ":binaryExit 1 ") (str "the binary itself exits non-zero after the failure it kept going past: " run.out))
        true))

fn ! testInheritedSwitchStripped! -> Bool
  (let [(run (aslTestEnv! (list (str (dir) "partial.asl")) (list "ASL_ASSERT_KEEP_GOING=1")))]
    (do (assert (= run.exit 1) (str "an inherited ASL_ASSERT_KEEP_GOING without --keep-going does not make the run green: " run.out))
        (refute (passLine? run.out) (str "no suite pass line: " run.out))
        (refute (stringContains? run.out "kept going") (str "the runner strips the inherited switch, so the binary stops at its first failure: " run.out))
        (assert (stringContains? run.out (str "FAIL " (dir) "partial.asl: ERR_ASSERT: assertion failed: partial breaks on purpose (after 1 asserts)")) (str "the plain FAIL line: " run.out))
        true))

fn ! testForgedRecords! -> Bool
  (let [(run (aslTest! (list (str (dir) "forged.asl") "--keep-going")))]
    (do (assert (!= run.exit 0) (str "forged report records and a forged pass line do not make a failed run green: " run.out))
        (assert (stringContains? run.out (str "FAIL " (dir) "forged.asl: ERR_ASSERT: 1 assertion(s) or refutation(s) failed, execution kept going (--keep-going) (after 1 asserts)")) (str "the runtime's own record, written last on a fresh line, is the one read: " run.out))
        true))

fn ! testClosedFdsWall! -> Bool
  (let [(run (aslTest! (list (str (dir) "closedFds.asl") "--wall" "3")))]
    (do (assert (= run.exit 1) (str "a binary that closed fd 1 and 2 and runs past --wall 3 fails: " run.out))
        (assert (stringContains? run.out (str "FAIL " (dir) "closedFds.asl: ERR_LIMIT: the runner killed the native binary at its wall limit of 3 s (--wall) after ")) (str "the wall limit fires on the process, not on its pipes, and is named: " run.out))
        true))

fn staleDir -> String
  (str (dir) "staleCopies")

fn suiteText -> String
  "(module testSelect/staleOne :x [runTests] :i [])\n\nfn testOne -> Bool\n  (do (assert (= (stringLength \"one\") 3) \"one holds\")\n      true)\n\nfn runTests -> Bool\n  (testOne)\n"

fn ! cleanStale! d: String names: (List String) -> Bool
  (let [(_ (map (fn [(n String)] -> Bool (do (pathRemove (str d "/" n)) true)) names))
        (_ (pathRemove (str d "/tests")))
        (_ (pathRemove d))]
    true)

fn ! testStaleCopies! -> Bool
  (let [(root (repoRoot!))
        (d (str root "/" (staleDir) (procSelf)))
        (dead ".one.only.999999999.asl")
        (live (str ".other.only." (procSelf) ".asl"))
        (hidden (str "tests/.hiddenTest.only." (procSelf) ".asl"))
        (_ (dirCreate d))
        (_ (dirCreate (str d "/tests")))
        (_ (fileWrite (str d "/one.asl") (suiteText)))
        (_ (fileWrite (str d "/" dead) (suiteText)))
        (_ (fileWrite (str d "/" live) (suiteText)))
        (_ (fileWrite (str d "/" hidden) (stringReplace (suiteText) "(= (stringLength \"one\") 3)" "(= (stringLength \"one\") 4)")))
        (rel (str (staleDir) (procSelf)))
        (selected (aslTest! (list (str rel "/one.asl") "--only" "testOne")))
        (deadLeft (fileExists? (str d "/" dead)))
        (liveLeft (fileExists? (str d "/" live)))
        (found (aslTest! (list rel)))
        (_ (cleanStale! d (list "one.asl" dead live hidden)))]
    (do (assert (= selected.exit 0) (str "the selected run passes: " selected.out))
        (refute deadLeft (str "a selection copy whose pid is dead is removed by the next selected run in its directory: " selected.out))
        (assert liveLeft "a copy whose pid is alive stays")
        (assert (stringContains? found.out "ERR_NO_TESTS") (str "a hidden copy is never discovered as a suite: " found.out))
        (refute (stringContains? found.out "FAIL ") (str "nothing hidden ran: " found.out))
        true))

fn ! testDefaultBytes! -> Bool
  (let [(ok1 (aslTest! (list "asl/packages/asl-cli/tests/fixtures/testOk.asl")))
        (bad (aslTest! (list (str (dir) "twoFails.asl"))))
        (termed (aslTest! (list (str (dir) "selfTerm.asl"))))]
    (do (assert (and (= ok1.exit 0) (= (stringTrim ok1.out) "asl/packages/asl-cli/tests/fixtures/testOk.asl: 1 assertion(s) executed (1 passed)")) (str "a passing run prints the line it printed before: " ok1.out))
        (assert (and (= bad.exit 1) (= (stringTrim bad.out) (str (dir) "twoFails.asl:4:7: ERR_ASSERT: assertion failed: early breaks on purpose\nFAIL " (dir) "twoFails.asl: ERR_ASSERT: assertion failed: early breaks on purpose (after 1 asserts)"))) (str "a failing run prints the lines it printed before: " bad.out))
        (assert (and (= termed.exit 1) (= (stringTrim termed.out) (str "FAIL " (dir) "selfTerm.asl: native binary exited -15 without an assertion report"))) (str "a signal-killed run without options prints the line it printed before: " termed.out))
        true))

fn testVerdictRecord -> Bool
  (let [(keptExit0 (nt/verdictOf "x.asl" 0 "1 assertion(s) executed, 0 refutation(s) executed, 1 failed\n"))
        (siteKept (nt/verdictOf "x.asl" 0 "x.asl:3:4: ERR_ASSERT: assertion failed: m\n2 assertion(s) executed, 0 refutation(s) executed, 0 failed\n"))
        (sitePlain (nt/verdictOf "x.asl" 0 "x.asl:3:4: ERR_ASSERT: assertion failed: m\n2 assertion(s) executed, 0 refutation(s) executed\n"))
        (garbled (nt/verdictOf "x.asl" 0 "progress1 assertion(s) executed, 0 refutation(s) executed\n"))
        (clean (nt/verdictOf "x.asl" 0 "2 assertion(s) executed, 0 refutation(s) executed, 0 failed\n"))]
    (do (assert (= keptExit0.exit 1) (str "a record with a failure is red even when the exit status says 0: " keptExit0.line))
        (assert (= siteKept.exit 1) (str "in a keep-going run a site line of a failed assertion is red even with exit 0 and a clean record: " siteKept.line))
        (assert (= sitePlain.exit 0) (str "in a plain run an echoed site line leaves the verdict main gives: " sitePlain.line))
        (assert (= (nt/withoutRunnerSwitches (list "A=1" "ASL_ASSERT_KEEP_GOING=1" "ASL_NATIVE_TEST_STATS=1" "B=2")) (list "A=1" "B=2")) "the helper asl test FILE and the --all/--changed sweep share strips both runner switches")
        (assert (= garbled.exit 1) (str "a report glued to other text is no report: " garbled.line))
        (assert (and (= clean.exit 0) (= clean.line "x.asl: 2 assertion(s) executed (2 passed)")) (str "exit 0, a record with 0 failed and no site line is green: " clean.line))
        true))

fn ! testEchoedSiteLine! -> Bool
  (let [(plain (aslTest! (list (str (dir) "echoSite.asl"))))
        (broken (aslTest! (list (str (dir) "echoSite.asl") "--only" "testBroken" "--keep-going")))]
    (do (assert (and (= plain.exit 0) (stringContains? plain.out (str (dir) "echoSite.asl: 1 assertion(s) executed (1 passed)"))) (str "a passing suite echoing a site line to stderr stays green with no flags: " plain.out))
        (assert (and (!= broken.exit 0) (stringContains? broken.out "FAIL ")) (str "a real failure under --keep-going is still a FAIL: " broken.out))
        true))

fn ! runTests -> Bool
  (and (testVerdictRecord) (and (testEchoedSiteLine!) (and (testUnterminatedKeepGoing!) (and (testInheritedSwitchStripped!) (and (testForgedRecords!) (and (testClosedFdsWall!) (and (testStaleCopies!) (testDefaultBytes!))))))))
