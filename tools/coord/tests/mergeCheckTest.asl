(module asl-tools/coord/tests/mergeCheckTest
  :x [runTests]
  :i [(asl-tools/coord/mergeCheck :a mc) (asl-tools/fleet/run :a fr)])

; (:m :ref MERGE-CHECK :do "pure coverage of the comparison, the suite judgement, the ledger idempotence, and an end to end run over a fixture repo whose fake cli reads canned audit and suite output from the checked out tree, so base and head differ only by commits; each assert goes red when its check is removed")
fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false") args))

fn ! commit! dir: String msg: String -> String
  (let [(_ (git dir (list "add" "-A")))
        (c (git dir (list "commit" "-q" "-m" msg)))]
    (stringTrim (git dir (list "rev-parse" "HEAD")).out))

fn red id: String ev: String -> (Pair String String)
  (pair id ev)

fn testPure -> Bool
  (let [(rcpt "audit gates: failed\n(:audit :sub gates :status :failed (:check :id gate1 :status :passed :n 3) (:check :id foreignGrowth :status :failed :n 270 :err E :ev \"build.sh :lines 359 > baseline 258 (+101)\") (:check :id gate2 :status :failed :err E2) (:check :id gate3 :status :passed))")
        (rows (mc/failedRows rcpt))]
    (do
      (assert (= (listLength rows) 2) (str "two failed checks, passes ignored: " (str (listLength rows))))
      (assert (= (pairFirst (optionOr (listHead rows) (pair "" ""))) "foreignGrowth") "the id of the first red")
      (assert (stringContains? (pairSecond (optionOr (listHead rows) (pair "" ""))) "+101") "its :ev text")
      (assert (= (pairSecond (optionOr (listGet rows 1) (pair "" "x"))) "") "a red without :ev has an empty ev")
      (assert (= (listLength (mc/failedRows "(:audit :status :passed (:check :id a :status :passed))")) 0) "a green receipt has no reds")
      (assert (= (mc/normEv "a.c :lines 359 > baseline 258 (+101)") "a.c :lines # > baseline # (+#)") "digit runs collapse")
      (assert (= (mc/rowKey "g" "x 12") (mc/rowKey "g" "x 9")) "a drifting number keeps one identity")
      (assert (not (= (mc/rowKey "g" "x.c 12") (mc/rowKey "g" "y.c 12"))) "a new path is a new identity")
      (let [(base (list (red "foreignGrowth" "build.sh :lines 300 > baseline 258 (+42)")))
            (head (list (red "foreignGrowth" "build.sh :lines 359 > baseline 258 (+101)") (red "foreignGrowth" "new.c :lines 5 > baseline 4 (+1)") (red "gate2" "")))
            (c (mc/classify head base))]
        (do
          (assert (= (listLength (pairSecond c)) 1) "the same check and ev on both sides is pre-existing")
          (assert (= (listLength (pairFirst c)) 2) "a new ev and a new id are regressions")
          (assert (= (pairFirst (optionOr (listHead (pairSecond c)) (pair "" ""))) "foreignGrowth") "the pre-existing row is the shared one")))
      (assert (= (listLength (pairFirst (mc/classify (list (red "a" "e") (red "a" "e")) (list)))) 1) "duplicate head rows count once")
      (let [(h (mc/SuiteRun :path "t/aTest.asl" :exit 0 :asserts 5 :verdict "exit"))
            (hf (mc/SuiteRun :path "t/aTest.asl" :exit 1 :asserts 5 :verdict "exit"))
            (ht (mc/SuiteRun :path "t/aTest.asl" :exit 124 :asserts 0 :verdict "timeout"))]
        (do
          (assert (= (mc/judgeSuite h 0 5) "pass") "equal asserts pass")
          (assert (= (mc/judgeSuite h 0 4) "pass") "more asserts pass")
          (assert (= (mc/judgeSuite (with h :asserts 3) 0 5) "regression") "fewer asserts than a green base block")
          (assert (= (mc/judgeSuite hf 0 5) "regression") "a failure against a green base blocks")
          (assert (= (mc/judgeSuite hf 1 5) "preExisting") "a failure also red at base is pre-existing")
          (assert (= (mc/judgeSuite hf -2 0) "regression") "a failing suite absent at base blocks")
          (assert (= (mc/judgeSuite hf -1 0) "regression") "a failure with no base run blocks")
          (assert (= (mc/judgeSuite ht 0 5) "unverified") "a timeout at head is unverified, not pass")
          (assert (= (mc/judgeSuite (with h :asserts 3) -1 0) "pass") "no base run, green head: head only")))
      (assert (mc/oneAsnLine? "(:c :a x :do \"y\" :ev (Z))\n") "an ASN line with a trailing newline")
      (assert (not (mc/oneAsnLine? "fix the thing")) "prose is not an ASN line")
      (assert (not (mc/oneAsnLine? "(:c :a x)\n\nbody text")) "a body makes it more than one line")
      (assert (not (mc/oneAsnLine? "")) "empty is not an ASN line")
      (assert (mc/conflictMarkers? "+a\n+<<<<<<< HEAD\n+b") "an added conflict opener")
      (assert (not (mc/conflictMarkers? " <<<<<<< HEAD\n-=======\n+ok")) "context and removed lines do not count")
      (let [(r (list (red "foreignGrowth" "x 1")))
            (row (mc/planRow "foreignGrowth" "x 1"))]
        (do
          (assert (stringStartsWith? row (str "(:u " (mc/planId "foreignGrowth" "x 1") " :p p1 :do ")) "the plan row shape")
          (assert (stringEndsWith? row " :src mergeCheck)") "the row names its source")
          (assert (= (mc/planId "foreignGrowth" "x 1") (mc/planId "foreignGrowth" "x 77")) "the id is stable under number drift")
          (assert (= (listLength (mc/missingRows "" r)) 1) "an empty ledger misses the row")
          (assert (= (listLength (mc/missingRows (str row "\n") r)) 0) "a ledger carrying the id misses nothing")))
      true))

fn ! fakeCli! path: String -> Bool
  (and (put path "#!/bin/sh\ncase \"$1\" in\n  audit) cat \"./audit.$2.txt\"; if grep -q ':status :failed' \"./audit.$2.txt\"; then exit 1; fi; exit 0;;\n  test) cat ./suite.out; if grep -q '^FAIL' ./suite.out; then exit 1; fi; exit 0;;\nesac\nexit 2\n")
       (= (sh "." (list "chmod" "+x" path)).exit 0))

fn greenAudit sub: String -> String
  (str "(:audit :sub " sub " :status :passed (:check :id syntax :status :passed :n 5))\n")

fn redGates ev: String -> String
  (str "(:audit :sub gates :status :failed (:check :id foreignGrowth :status :failed :err E :ev \"" ev "\"))\n")

fn suiteOut n: Int64 -> String
  (str "pkg/tests/aTest.asl: " (stringFromInt64 n) " assertion(s) executed (" (stringFromInt64 n) " passed)\n")

fn ! testE2e base: String -> Bool
  (let [(repo (str base "/repo"))
        (cli (str base "/fakeAsl"))
        (ledger (str base "/ledger.asn"))
        (_ (sh "." (list "mkdir" "-p" (str repo "/pkg/tests"))))
        (_ (git repo (list "init" "-q")))
        (_ (put (str repo "/audit.consistency.txt") (greenAudit "consistency")))
        (_ (put (str repo "/audit.gates.txt") (greenAudit "gates")))
        (_ (put (str repo "/pkg/a.asl") "(module pkg/a\n  :x [f]\n  :i [])\nfn f -> Int64 1\n"))
        (_ (put (str repo "/pkg/tests/aTest.asl") "(module pkg/tests/aTest\n  :x [runTests]\n  :i [(pkg/a :a a)])\n"))
        (_ (put (str repo "/suite.out") (suiteOut 5)))
        (c0 (commit! repo "(:c :a fx :do \"base\" :ev (T))"))
        (_ (put (str repo "/audit.gates.txt") (redGates "x.c :lines 9 > baseline 8 (+1)")))
        (c1 (commit! repo "(:c :a fx :do \"regress\" :ev (T))"))
        (_ (put (str repo "/audit.gates.txt") (redGates "x.c :lines 11 > baseline 8 (+3)")))
        (_ (put (str repo "/pkg/a.asl") "(module pkg/a\n  :x [f]\n  :i [])\nfn f -> Int64 2\n"))
        (c2 (commit! repo "(:c :a fx :do \"touch a, red drifts\" :ev (T))"))
        (_ (put (str repo "/suite.out") (suiteOut 3)))
        (_ (put (str repo "/pkg/a.asl") "(module pkg/a\n  :x [f]\n  :i [])\nfn f -> Int64 3\n"))
        (c3 (commit! repo "(:c :a fx :do \"fewer asserts\" :ev (T))"))
        (_ (put (str repo "/pkg/a.asl") "(module pkg/a\n  :x [f]\n  :i [])\nfn f -> Int64 4\n"))
        (c4 (commit! repo "fix stuff"))
        (_ (fakeCli! cli))
        (r1 (mc/run! repo c0 c1 "" cli 120 60 12 (list)))
        (r2 (mc/run! repo c1 c2 ledger cli 120 60 12 (list)))
        (r2b (mc/run! repo c1 c2 ledger cli 120 60 12 (list)))
        (r3 (mc/run! repo c2 c3 "" cli 120 60 12 (list)))
        (r4 (mc/run! repo c3 c4 "" cli 120 60 12 (list)))
        (r5 (mc/run! repo c1 c2 "" cli 0 60 12 (list)))
        (rows (stringLines (resultOr (fileReadString ledger) "")))]
    (do
      (assert (= (pairFirst r1) 1) (str "a regression added by head blocks: " (pairSecond r1)))
      (assert (stringContains? (pairSecond r1) ":verdict block") "the receipt says block")
      (assert (stringContains? (pairSecond r1) ":regressions ((:check :id foreignGrowth") "the regression names the check")
      (assert (= (pairFirst r2) 0) (str "a red on both sides passes: " (pairSecond r2)))
      (assert (stringContains? (pairSecond r2) ":preExisting ((:check :id foreignGrowth") "the shared red is listed pre-existing")
      (assert (stringContains? (pairSecond r2) ":planRows ((:u MC-foreignGrowth-") "a ready plan row is printed")
      (assert (stringContains? (pairSecond r2) ":ledgerAdded 1") "the first ledger run adds the row")
      (assert (stringContains? (pairSecond r2b) ":ledgerAdded 0") "the second ledger run adds nothing")
      (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:u MC-foreignGrowth-")) rows)) 1) "the ledger holds the row exactly once")
      (assert (stringContains? (pairSecond r2) "pkg/tests/aTest.asl") "touching pkg/a.asl finds the package suite")
      (assert (stringContains? (pairSecond r2) ":judged :pass") "equal asserts pass")
      (assert (= (pairFirst r3) 1) (str "a drop in executed asserts blocks: " (pairSecond r3)))
      (assert (stringContains? (pairSecond r3) ":judged :regression") "the suite is the regression")
      (assert (= (pairFirst r4) 1) (str "a commit that is not an ASN line blocks: " (pairSecond r4)))
      (assert (stringContains? (pairSecond r4) "notOneAsnLine") "the structure problem is named")
      (assert (stringContains? (pairSecond r5) ":complete false") "a spent deadline reports incomplete")
      (assert (stringContains? (pairSecond r5) "consistencyHead:deadline") "the skipped step is listed unverified")
      (assert (not (stringContains? (pairSecond r5) ":suites ((:suite")) "a step that did not run has no suite result")
      true))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/mergeCheckTest-" (stringFromInt64 (procSelf))))
        (_ (sh "." (list "mkdir" "-p" base)))
        (a (testPure))
        (b (testE2e base))
        (_ (pathRemove base))]
    (and a b))
