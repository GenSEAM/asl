(module asl-gates/tests/suiteTimesTest
  :x [runTests]
  :i [(asl-gates/suiteRunner :a sr) (asl-gates/suiteTimes :a st)])

fn sh! command: String -> String
  (let [(res (processRun command))]
    (do
      (assert (= res.exitCode 0) (str "fixture command exits 0: " command " -> " res.stderr))
      (stringTrim res.stdout)))

fn readText! path: String -> String
  (mt (fileReadString path) ((ok text) text) ((err e) (str "unreadable: " e)))

fn errText r: (Result (Map String Int64) String) -> String
  (mt r ((ok _) "") ((err e) e))

fn msOf r: (Result (Map String Int64) String) suite: String -> Int64
  (mt r ((ok m) (optionOr (mapGet m suite) -1)) ((err _) -1))

fn ! testLedgerRoundTrip! dir: String -> Bool
  (let [(path (str dir "/nested/run/gateTimes.asn"))
        (weird "tests/we\"ird\\Test.sh")
        (first (st/writeTimes! path (list (st/SuiteTime :suite "tests/aTest.asl" :ms 1200) (st/SuiteTime :suite weird :ms 5))))
        (firstRead (st/readTimes! path))
        (second (st/writeTimes! path (list (st/SuiteTime :suite "tests/aTest.asl" :ms 900) (st/SuiteTime :suite "tests/bTest.asl" :ms 7))))
        (secondRead (st/readTimes! path))
        (text (readText! path))
        (absent (st/readTimes! (str dir "/absent/gateTimes.asn")))]
    (do
      (assert (ok? first) (str "first ledger write succeeds, creating the parent directories: " (mt first ((ok _) "") ((err e) e))))
      (assert (= (msOf firstRead "tests/aTest.asl") 1200) "written row reads back")
      (assert (= (msOf firstRead weird) 5) "a suite with a quote and a backslash round-trips")
      (assert (ok? second) "second ledger write succeeds")
      (assert (= (msOf secondRead "tests/aTest.asl") 900) "the newest run wins for a suite")
      (assert (= (msOf secondRead "tests/bTest.asl") 7) "a new suite is added")
      (assert (= (msOf secondRead weird) 5) "a suite absent from the newer run keeps its row")
      (assert (= text (str "(:suiteTime :suite \"tests/aTest.asl\" :ms 900)\n"
                           "(:suiteTime :suite \"tests/bTest.asl\" :ms 7)\n"
                           "(:suiteTime :suite \"tests/we\\\"ird\\\\Test.sh\" :ms 5)\n"))
              (str "ledger text is one row per suite sorted by suite: " text))
      (assert (not (fileExists? (str path ".tmp." (stringFromInt64 (procSelf))))) "no temporary ledger is left behind")
      (assert (and (ok? absent) (= (msOf absent "tests/aTest.asl") -1)) "a missing ledger reads as empty")
      true))

fn ! corruptCase! dir: String name: String text: String want: String -> Bool
  (let [(path (str dir "/" name ".asn"))
        (seeded (fileWrite path text))
        (read (st/readTimes! path))
        (write (st/writeTimes! path (list (st/SuiteTime :suite "tests/aTest.asl" :ms 1))))
        (after (readText! path))]
    (do
      (assert (ok? seeded) (str name ": corrupt ledger seeded"))
      (assert (stringContains? (errText read) want) (str name ": read reports " want ", got: " (errText read)))
      (assert (err? write) (str name ": a write over a corrupt ledger is an error"))
      (assert (= after text) (str name ": the corrupt ledger is left as found"))
      true))

fn ! testCorruptLedger! dir: String -> Bool
  (do
    (assert (corruptCase! dir "badMs" "(:suiteTime :suite \"tests/aTest.asl\" :ms 3)\n(:suiteTime :suite \"tests/bTest.asl\" :ms 4x)\n" "line 2: expected :ms") "non-digit :ms")
    (assert (corruptCase! dir "truncated" "(:suiteTime :suite \"tests/aTest.asl\" :ms 3)\n(:suiteTime :suite \"tests/b\n" "line 2: unterminated") "truncated row")
    (assert (corruptCase! dir "foreign" "(:other :x 1)\n" "line 1: not a (:suiteTime") "foreign row")
    (assert (corruptCase! dir "duplicate" "(:suiteTime :suite \"tests/aTest.asl\" :ms 3)\n(:suiteTime :suite \"tests/aTest.asl\" :ms 4)\n" "line 2: duplicate :suite") "duplicate suite")
    true)

fn testStartOrder -> Bool
  (let [(known (mapFromPairs (list (pair "c" 10) (pair "d" 500) (pair "e" 500))))]
    (do
      (assert (= (st/startOrder (list "e" "b" "a" "c" "d") known) (list 2 1 4 0 3)) "unknown suites first by name, then known by descending ms, ties by name")
      (assert (= (st/startOrder (list "x" "y") (mapEmpty)) (list 0 1)) "with no ledger the order is by name")
      true))

fn sleepJob name: String seconds: Int64 -> sr/Job
  (sr/Job :input "" :argv (list "/bin/sh" "-c" (str "sleep " (stringFromInt64 seconds) "; echo " name)) :cwd (none) :env (none) :timeoutMs 30000)

fn names -> (List String)
  (list "s1" "s2" "s3" "s4" "long")

fn seconds -> (List Int64)
  (list 1 1 1 1 4)

fn jobs -> (List sr/Job)
  (map (fn [(p (Pair String Int64))] -> sr/Job (sleepJob (pairFirst p) (pairSecond p))) (zip (names) (seconds)))

fn ! timedRun! order: (List Int64) -> (Pair Int64 (List sr/Done))
  (let [(t0 (monotonicNs))
        (res (sr/runJobsBy! (jobs) order 2 (none) (none)))
        (wall (/ (- (monotonicNs) t0) 1000000))]
    (pair wall (mt res ((ok ds) ds) ((err e) (list)))))

fn withinHalfSecond d: sr/Done s: Int64 -> Bool
  (let [(ms (sr/doneMs d))]
    (and (>= ms (- (* s 1000) 500)) (<= ms (+ (* s 1000) 500))))

fn ! testLongestFirst! dir: String -> Bool
  (let [(path (str dir "/pool/gateTimes.asn"))
        (seeded (st/writeTimes! path (list (st/SuiteTime :suite "long" :ms 4000) (st/SuiteTime :suite "s1" :ms 1000) (st/SuiteTime :suite "s2" :ms 1000)
                                           (st/SuiteTime :suite "s3" :ms 1000) (st/SuiteTime :suite "s4" :ms 1000))))
        (known (mt (st/readTimes! path) ((ok m) m) ((err _) (mapEmpty))))
        (order (st/startOrder (names) known))
        (ordered (timedRun! order))
        (dones (pairSecond ordered))
        (fifo (timedRun! (list 0 1 2 3 4)))]
    (do
      (assert (ok? seeded) "times ledger seeded")
      (assert (= order (list 4 0 1 2 3)) "the ledger puts the 4 s job first")
      (assert (= (listLength dones) 5) "every job returns a Done")
      (assert (< (pairFirst ordered) 5500) (str "longest-first makespan under 5.5 s with k=2: " (stringFromInt64 (pairFirst ordered)) " ms"))
      (assert (>= (pairFirst fifo) 6000) (str "input-order start keeps the 6 s tail this unit removes: " (stringFromInt64 (pairFirst fifo)) " ms"))
      (assert (= (map (fn [(d sr/Done)] -> String (stringTrim d.out)) dones) (names)) "results come back in input order")
      (assert (listAll? (fn [(p (Pair sr/Done Int64))] -> Bool (withinHalfSecond (pairFirst p) (pairSecond p))) (zip dones (seconds)))
              (str "every Done carries its wall time within 0.5 s: " (stringJoin (map (fn [(d sr/Done)] -> String (stringFromInt64 (sr/doneMs d))) dones) " ")))
      (assert (err? (sr/runJobsBy! (jobs) (list 0 0 1 2 3) 2 (none) (none))) "a start order that is not a permutation is refused")
      true))

fn ! testRunnerRecords! dir: String -> Bool
  (let [(cwd (sh! "pwd -P"))
        (repo (str dir "/repo"))
        (ledger (str dir "/runner/gateTimes.asn"))
        (orderPath (str dir "/runner/startOrder.txt"))
        (envPath (str dir "/runner/suiteTimesEnv.txt"))
        (gate "echo '(:gate :name t :asserts 1 :failed 0)'\n")
        (made (dirCreate (str repo "/tests")))
        (fastWrote (fileWrite (str repo "/tests/fastTest.sh") (str "#!/bin/sh\nprintf 'fast\\n' >> " orderPath "\nprintf '%s\\n' \"$ASL_GATE_TIMES\" > " envPath "\n" gate)))
        (slowWrote (fileWrite (str repo "/tests/slowTest.sh") (str "#!/bin/sh\nprintf 'slow\\n' >> " orderPath "\nsleep 1\n" gate)))
        (seeded (st/writeTimes! ledger (list (st/SuiteTime :suite "tests/fastTest.sh" :ms 10) (st/SuiteTime :suite "tests/slowTest.sh" :ms 2000))))
        (setup (sh! (str "cd " repo " && git init -q && git config user.name fixture && git config user.email fixture@example.invalid"
                         " && chmod +x tests/*.sh && git add -A && git commit -q -m fixture")))
        (run (str "cd " repo " && ASL_JOBS=1 ASL_GATE_TIMES=" ledger " " cwd "/asl/host/out/asl-host run " cwd "/asl/packages/asl-gates/src/runnerMain.asl run --suite tests/fastTest.sh --suite tests/slowTest.sh"))
        (first (processRun run))
        (observedOrder (readText! orderPath))
        (suiteEnv (readText! envPath))
        (rows (st/readTimes! ledger))
        (slow (msOf rows "tests/slowTest.sh"))
        (fast (msOf rows "tests/fastTest.sh"))
        (corrupted (fileWrite ledger "(:suiteTime :suite \"tests/slowTest.sh\" :ms slow)\n"))
        (second (processRun run))
        (orderAfterCorrupt (readText! orderPath))]
    (do
      (assert (and (ok? made) (ok? fastWrote) (ok? slowWrote)) "fixture suites written")
      (assert (ok? seeded) "known runtime ledger seeded before the runner starts")
      (assert (stringStartsWith? first.stdout "(:runner :status") (str "runner printed a receipt: " first.stdout first.stderr))
      (assert (= observedOrder "slow\nfast\n") (str "runner starts the ledger-longest suite before the input-first, name-first suite: " observedOrder))
      (assert (and (stringContains? suiteEnv "/aslRunnerSnap.") (stringEndsWith? suiteEnv "/.git/aslGateTimes.asn\n")) (str "a suite under the runner gets a snapshot-local ledger, not the runner's: " suiteEnv))
      (assert (and (>= slow 900) (< slow 3000)) (str "the runner recorded the 1 s suite: " (stringFromInt64 slow)))
      (assert (and (>= fast 0) (< fast slow)) (str "the runner recorded the fast suite below the slow one: " (stringFromInt64 fast)))
      (assert (ok? corrupted) "ledger corrupted")
      (assert (= second.exitCode 2) "a corrupt ledger fails the runner")
      (assert (stringContains? second.stdout "ERR_RUNNER :ev \"gateTimes ") (str "the runner names the corrupt ledger: " second.stdout))
      (assert (= orderAfterCorrupt observedOrder) (str "a corrupt ledger stops the runner before any suite starts: " orderAfterCorrupt))
      true))

fn ! runTests -> Bool
  (let [(dir (optionOr (mt (sr/makeTempDir! "aslSuiteTimesTest") ((ok d) (some d)) ((err _) (none))) ""))]
    (do
      (assert (not (stringEmpty? dir)) "scratch directory created")
      (assert (testLedgerRoundTrip! dir) "ledger write and read round-trip")
      (assert (testCorruptLedger! dir) "a corrupt ledger row is an error")
      (assert (testStartOrder) "start order from the ledger")
      (assert (testLongestFirst! dir) "longest known job starts first")
      (assert (testRunnerRecords! dir) "runner records per-suite times")
      (assert (ok? (pathRemove dir)) "scratch directory removed")
      true))
