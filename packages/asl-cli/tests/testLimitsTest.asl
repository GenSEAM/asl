(module asl-cli/tests/testLimitsTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref TEST-RUNNER-SELECT :do "asl test names why a native test binary died: the runner's own wall limit (--wall, a declared suiteWallS or the 1800 s default) and memory cap (--max-rss, sampled) each kill the group and say so, a signal from elsewhere is named as one when the run gave an option (a plain run keeps the line it printed before, testVerdictChannelTest); --stats adds a (:testRun ...) receipt with wall time and peak resident size. The fixtures end on their own (a 60 s spin, a 512 MB string, a self-sent SIGTERM), so a limit that does not fire turns these assertions red instead of hanging")
fn dir -> String
  "asl/packages/asl-cli/tests/fixtures/testSelect/"

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslTest! args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str (repoRoot!) "/bin/asl") "test") args) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testWallLimitNamed! -> Bool
  (let [(spun (aslTest! (list (str (dir) "spinner.asl") "--wall" "2")))]
    (do (assert (= spun.exit 1) (str "a spin past --wall 2 fails: " spun.out))
        (assert (stringContains? spun.out (str "FAIL " (dir) "spinner.asl: ERR_LIMIT: the runner killed the native binary at its wall limit of 2 s (--wall) after ")) (str "the FAIL line names the wall limit and its source: " spun.out))
        (refute (stringContains? spun.out "without an assertion report") (str "the kill is not left unexplained: " spun.out))
        true))

fn ! testMemoryCapNamed! -> Bool
  (let [(hog (aslTest! (list (str (dir) "memHog.asl") "--max-rss" "64" "--stats")))]
    (do (assert (= hog.exit 1) (str "a binary growing past --max-rss 64 fails: " hog.out))
        (assert (stringContains? hog.out (str "FAIL " (dir) "memHog.asl: ERR_LIMIT: the runner killed the native binary at its memory cap of 64 MB (--max-rss) with ")) (str "the FAIL line names the memory cap: " hog.out))
        (assert (stringContains? hog.out ":maxRssMb 64 :killedBy memory)") (str "the receipt records the cap and what fired: " hog.out))
        true))

fn ! testOutsideSignalNamed! -> Bool
  (let [(termed (aslTest! (list (str (dir) "selfTerm.asl") "--stats")))]
    (do (assert (= termed.exit 1) (str "a binary ended by a signal fails: " termed.out))
        (assert (stringContains? termed.out (str "FAIL " (dir) "selfTerm.asl: native binary killed by SIGTERM (signal 15) after ")) (str "the signal is named: " termed.out))
        (assert (stringContains? termed.out "no runner limit fired (wall limit 1800 s from the default, no memory cap), so the signal came from outside the runner") (str "the line says no runner limit sent it and which limits were set: " termed.out))
        true))

fn ! testStatsReceipt! -> Bool
  (let [(ran (aslTest! (list (str (dir) "threeFns.asl") "--only" "testThird" "--stats")))
        (plain (aslTest! (list (str (dir) "threeFns.asl") "--only" "testThird")))]
    (do (assert (= ran.exit 0) (str "--stats does not change the verdict: " ran.out))
        (assert (stringContains? ran.out (str "(:testRun :file \"" (dir) "threeFns.asl --only testThird\" :exit 0 :binaryExit 0 :wallMs ")) (str "the receipt names the run and its exit: " ran.out))
        (assert (stringContains? ran.out ":peakFrom rusage :wallLimitS 1800 :wallFrom \"the default\")") (str "the peak comes from the binary's own rusage and the wall limit from the default: " ran.out))
        (refute (stringContains? ran.out ":peakRssKb 0 ") (str "the peak resident size is a measured number: " ran.out))
        (refute (stringContains? ran.out "ASL_TEST_PEAK_RSS_KB") (str "the wrapper's peak line is folded into the receipt: " ran.out))
        (refute (stringContains? plain.out "(:testRun") (str "without --stats there is no receipt line: " plain.out))
        true))

fn ! testBadLimitsRefused! -> Bool
  (let [(zero (aslTest! (list (str (dir) "threeFns.asl") "--wall" "0")))
        (word (aslTest! (list (str (dir) "threeFns.asl") "--max-rss" "lots")))]
    (do (assert (and (= zero.exit 2) (stringContains? zero.out "--wall needs a whole number of seconds from 1 to 7200, got 0")) (str "--wall 0 is a usage error: " zero.out))
        (assert (and (= word.exit 2) (stringContains? word.out "--max-rss needs a whole number of megabytes above 0, got lots")) (str "--max-rss lots is a usage error: " word.out))
        true))

fn ! runTests -> Bool
  (and (testWallLimitNamed!) (and (testMemoryCapNamed!) (and (testOutsideSignalNamed!) (and (testStatsReceipt!) (testBadLimitsRefused!)))))
