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
      (assert (= (mc/normEv "a.c :lines 359 > baseline 258 (+101)") "a.c") "only the trailing count fields are dropped")
      (assert (= (mc/normEv "total foreign lines 12369 > baseline 12265 (+104)") "total foreign") "the total row drops its counts")
      (assert (= (mc/rowKey "g" "x.c :lines 12 (+2)") (mc/rowKey "g" "x.c :lines 9 (+1)")) "a drifting count keeps one identity")
      (assert (not (= (mc/rowKey "g" "a1.c :lines 12") (mc/rowKey "g" "a2.c :lines 12"))) "digits in a path stay part of the identity")
      (assert (not (= (mc/rowKey "g" "x1 broke") (mc/rowKey "g" "x2 broke"))) "an ev with no count field is kept whole")
      (assert (= (mc/evDelta "b.sh :lines 359 > baseline 258 (+101)") 101) "the +K delta")
      (assert (= (mc/evDelta "no delta here") -1) "no delta reads -1")
      (let [(base (list (red "foreignGrowth" "build.sh :lines 300 > baseline 258 (+42)")))
            (head (list (red "foreignGrowth" "build.sh :lines 359 > baseline 258 (+101)") (red "foreignGrowth" "new.c :lines 5 > baseline 4 (+1)") (red "gate2" "")))
            (c (mc/classify head base))]
        (do
          (assert (= (listLength (pairSecond (mc/classify (list (red "foreignGrowth" "build.sh :lines 300 > baseline 258 (+42)")) base))) 1) "a same or smaller delta is pre-existing")
          (assert (= (listLength (pairFirst (mc/classify (list (red "foreignGrowth" "build.sh :lines 359 > baseline 258 (+101)")) base))) 1) "a larger delta is a regression, the red got worse")
          (assert (= (listLength (pairFirst c)) 3) "a worse delta, a new ev and a new id are regressions")
          (assert (= (listLength (pairSecond c)) 0) "the shared red got worse so it is not pre-existing")
          true))
      (assert (= (listLength (pairFirst (mc/classify (list (red "a" "e") (red "a" "e")) (list)))) 1) "duplicate head rows count once")
      (let [(h (mc/SuiteRun :path "t/aTest.asl" :exit 0 :asserts 5 :verdict "exit"))
            (hf (mc/SuiteRun :path "t/aTest.asl" :exit 1 :asserts 5 :verdict "exit"))
            (ht (mc/SuiteRun :path "t/aTest.asl" :exit 124 :asserts 0 :verdict "timeout"))]
        (do
          (assert (= (mc/judgeSuite h 0 5) "pass") "equal asserts pass")
          (assert (= (mc/judgeSuite h 0 4) "pass") "more asserts pass")
          (assert (= (mc/judgeSuite (with h :asserts 3) 0 5) "regression") "fewer asserts than a green base block")
          (assert (= (mc/judgeSuite hf 0 5) "regression") "a failure against a green base blocks")
          (assert (= (mc/judgeSuite hf 1 5) "preExisting") "a failure also red at base with asserts executed is pre-existing")
          (assert (= (mc/judgeSuite hf 1 0) "unverified") "a base red that executed no asserts is not pre-existing")
          (assert (= (mc/judgeSuite hf 127 3) "unverified") "a base that exited 127 is not pre-existing")
          (assert (= (mc/judgeSuite (with hf :asserts 0) 1 5) "unverified") "a head load failure against a red base is unverified")
          (assert (= (mc/judgeSuite (with hf :asserts 0) 1 0) "unverified") "a load failure on both sides is unverified")
          (assert (= (mc/judgeSuite (with hf :exit 126) 0 5) "regression") "a head that cannot start against a green base blocks")
          (assert (= (mc/judgeSuite (with hf :asserts 0) -2 0) "regression") "a new suite that does not load blocks")
          (assert (= (mc/judgeSuite (with h :retried true) 0 5) "flaky") "a pass that needed the retry is flaky")
          (assert (= (mc/judgeSuite (with (with h :retried true) :asserts 3) 0 5) "regression") "a retried pass with fewer asserts is still a drop")
          (assert (stringContains? (mc/suiteReceipt (with (with h :retried true) :firstWhy "boom") 0 5) ":retried true :firstWhy \"boom\"") "the row records the retry and the first failure")
          (assert (= (mc/judgeSuite hf -2 0) "regression") "a failing suite absent at base blocks")
          (assert (= (mc/judgeSuite hf -1 0) "regression") "a failure that ran asserts with no base run blocks")
          (assert (= (mc/judgeSuite ht 0 5) "unverified") "a timeout at head is unverified, not pass")
          (assert (= (mc/judgeSuite (with h :asserts 3) -1 0) "pass") "no base run, green head: head only")))
      (assert (mc/oneAsnLine? "(:c :a x :do \"y\" :ev (Z))\n") "an ASN line with a trailing newline")
      (assert (not (mc/oneAsnLine? "fix the thing")) "prose is not an ASN line")
      (assert (not (mc/oneAsnLine? "(:c :a x)\n\nbody text")) "a body makes it more than one line")
      (assert (not (mc/oneAsnLine? "")) "empty is not an ASN line")
      (assert (= (mc/cachePath "/c" "abc" "gates") "/c/abc-gates.asn") "the cache is keyed by base sha and sub")
      (assert (not (stringContains? (str (mc/cleanEnv)) "ASL_ROOT")) "the child env carries no ASL_ROOT")
      (assert (and (not (mc/keepEnv? "ASL_ROOT")) (not (mc/keepEnv? "ASL_PRELUDE"))) "the launcher's root and prelude are dropped so bin/asl derives its own")
      (assert (and (mc/keepEnv? "HOME") (mc/keepEnv? "ASL_NATIVE_TEST_CACHE") (not (mc/keepEnv? "FOO_API_KEY"))) "ordinary and cache variables stay, secrets go")
      (assert (mc/conflictMarkers? "+a\n+<<<<<<< HEAD\n+b") "an added conflict opener")
      (assert (not (mc/conflictMarkers? " <<<<<<< HEAD\n-=======\n+ok")) "context and removed lines do not count")
      (let [(r (list (red "foreignGrowth" "x 1")))
            (row (mc/planRow "foreignGrowth" "x 1"))]
        (do
          (assert (stringStartsWith? row (str "(:u " (mc/planId "foreignGrowth" "x 1") " :p p1 :do ")) "the plan row shape")
          (assert (stringEndsWith? row " :src mergeCheck)") "the row names its source")
          (assert (= (mc/planId "foreignGrowth" "x.c :lines 1 (+1)") (mc/planId "foreignGrowth" "x.c :lines 77 (+2)")) "the id is stable under number drift")
          (assert (= (listLength (mc/missingRows "" r)) 1) "an empty ledger misses the row")
          (assert (= (listLength (mc/missingRows (str row "\n") r)) 0) "a ledger carrying the id misses nothing")))
      true))

fn ! fakeCli! path: String ctr: String -> Bool
  (and (put path (str "#!/bin/sh\ncase \"$1\" in\n  audit) cat \"./audit.$2.txt\"; if grep -q ':status :failed' \"./audit.$2.txt\"; then exit 1; fi; exit 0;;\n  test) if [ -f ./flaky ]; then n=$(cat " ctr " 2>/dev/null || echo 0); echo $((n+1)) > " ctr "; if [ $n -eq 0 ]; then echo \"FAIL $2: ERR_ASSERT boom (after 1 asserts)\"; exit 1; fi; fi; cat ./suite.out; if grep -q '^FAIL' ./suite.out; then exit 1; fi; exit 0;;\nesac\nexit 2\n"))
       (= (sh "." (list "chmod" "+x" path)).exit 0))

fn greenAudit sub: String -> String
  (str "(:audit :sub " sub " :status :passed (:check :id syntax :status :passed :n 5))\n")

fn redGates ev: String -> String
  (str "(:audit :sub gates :status :failed (:check :id foreignGrowth :status :failed :err E :ev \"" ev "\"))\n")

fn suiteOut n: Int64 -> String
  (str "pkg/tests/aTest.asl: " (stringFromInt64 n) " assertion(s) executed (" (stringFromInt64 n) " passed)\n")

fn aSrc k: Int64 -> String
  (str "(module pkg/a\n  :x [f]\n  :i [])\nfn f -> Int64 " (stringFromInt64 k) "\n")

fn ! headOf! repo: String -> String
  (stringTrim (git repo (list "rev-parse" "HEAD")).out)

fn opts repo: String base: String head: String mode: String maxS: Int64 gate: String ledger: String totalS: Int64 cli: String cache: String headDir: String -> mc/Opts
  (mc/Opts :repo repo :base base :head head :ledger ledger :cli cli :totalS totalS :stepS 60 :maxSuites maxS :only (list) :mode mode :gate gate :headDir headDir :baseDir "" :cache cache)

fn ! testE2e base: String -> Bool
  (let [(repo (str base "/repo"))
        (cli (str base "/fakeAsl"))
        (cache (str base "/cache"))
        (ledger (str base "/ledger.asn"))
        (_ (sh "." (list "mkdir" "-p" (str repo "/pkg/tests") (str repo "/pkg2/tests"))))
        (_ (git repo (list "init" "-q")))
        (_ (put (str repo "/audit.consistency.txt") (greenAudit "consistency")))
        (_ (put (str repo "/audit.gates.txt") (greenAudit "gates")))
        (_ (put (str repo "/pkg/a.asl") (aSrc 1)))
        (_ (put (str repo "/pkg/tests/aTest.asl") "(module pkg/tests/aTest\n  :x [runTests]\n  :i [(pkg/a :a a)])\n"))
        (_ (put (str repo "/pkg/tests/bTest.asl") "(module pkg/tests/bTest\n  :x [runTests]\n  :i [])\n"))
        (_ (put (str repo "/pkg2/tests/cTest.asl") "(module pkg2/tests/cTest\n  :x [runTests]\n  :i [(pkg/a :a a)])\n"))
        (_ (put (str repo "/suite.out") (suiteOut 5)))
        (c0 (commit! repo "(:c :a fx :do \"base\" :ev (T))"))
        (_ (put (str repo "/audit.gates.txt") (redGates "x.c :lines 9 > baseline 8 (+1)")))
        (c1 (commit! repo "(:c :a fx :do \"regress\" :ev (T))"))
        (_ (put (str repo "/audit.gates.txt") (redGates "x.c :lines 10 > baseline 9 (+1)")))
        (_ (put (str repo "/pkg/a.asl") (aSrc 2)))
        (c2 (commit! repo "(:c :a fx :do \"touch a, red drifts\" :ev (T))"))
        (_ (git repo (list "checkout" "-q" "-b" "flk")))
        (_ (put (str repo "/flaky") "x\n"))
        (_ (put (str repo "/pkg/a.asl") (aSrc 5)))
        (c5 (commit! repo "(:c :a fx :do \"flaky\" :ev (T))"))
        (_ (git repo (list "checkout" "-q" c2)))
        (_ (git repo (list "checkout" "-q" "-b" "side")))
        (_ (put (str repo "/side.txt") "s\n"))
        (c5s (commit! repo "(:c :a fx :do \"side\" :ev (T))"))
        (_ (git repo (list "checkout" "-q" "flk")))
        (_ (git repo (list "merge" "--no-ff" "-q" "-m" "Merge side" "side")))
        (c6 (headOf! repo))
        (_ (git repo (list "checkout" "-q" c2)))
        (_ (git repo (list "checkout" "-q" "-b" "line")))
        (_ (put (str repo "/suite.out") (suiteOut 3)))
        (_ (put (str repo "/pkg/a.asl") (aSrc 3)))
        (c3 (commit! repo "(:c :a fx :do \"fewer asserts\" :ev (T))"))
        (_ (put (str repo "/pkg/a.asl") (aSrc 4)))
        (c4 (commit! repo "fix stuff"))
        (_ (put (str repo "/audit.gates.txt") (redGates "x.c :lines 14 > baseline 9 (+5)")))
        (cw (commit! repo "(:c :a fx :do \"worse\" :ev (T))"))
        (ctr (str base "/flaky.n"))
        (_ (fakeCli! cli ctr))
        (r1 (mc/run! (opts repo c0 c1 "full" 12 "" "" 120 cli cache "")))
        (r2 (mc/run! (opts repo c1 c2 "full" 12 "" ledger 120 cli cache "")))
        (r2b (mc/run! (opts repo c1 c2 "full" 12 "" ledger 120 cli cache "")))
        (r3 (mc/run! (opts repo c2 c3 "full" 12 "" "" 120 cli cache "")))
        (r4 (mc/run! (opts repo c3 c4 "full" 12 "" "" 120 cli cache "")))
        (r5 (mc/run! (opts repo c1 c2 "full" 12 "" "" 0 cli cache "")))
        (r6 (mc/run! (opts repo c1 c2 "full" 1 "" "" 120 cli cache "")))
        (r6b (mc/run! (opts repo c1 c2 "full" 2 "" "" 120 cli cache "")))
        (r7 (mc/run! (opts repo c1 c2 "cheap" 12 "" "" 120 cli cache "")))
        (r8 (mc/run! (opts repo c1 c2 "cheap" 12 "exit 3" "" 120 cli cache "")))
        (r8b (mc/run! (opts repo c1 c2 "cheap" 12 "true" "" 120 cli cache "")))
        (_ (pathRemove ctr))
        (r9 (mc/run! (opts repo c2 c6 "full" 12 "" "" 120 cli cache "")))
        (r10 (mc/run! (opts repo c4 cw "cheap" 12 "" "" 120 cli cache "")))
        (hd (str base "/hd"))
        (_ (git repo (list "worktree" "add" "-q" "--detach" hd c2)))
        (r11 (mc/run! (opts repo c1 c2 "cheap" 12 "" "" 120 cli cache hd)))
        (_ (git repo (list "worktree" "remove" "--force" hd)))
        (rows (stringLines (resultOr (fileReadString ledger) "")))
        (out (fn [(r (Pair Int64 String))] -> String (pairSecond r)))]
    (do
      (assert (= (pairFirst r1) 1) (str "a regression added by head blocks: " (out r1)))
      (assert (stringContains? (out r1) ":verdict block") "the receipt says block")
      (assert (stringContains? (out r1) ":regressions ((:check :id foreignGrowth") "the regression names the check")
      (assert (= (pairFirst r2) 0) (str "a red on both sides passes: " (out r2)))
      (assert (stringContains? (out r2) ":preExisting ((:check :id foreignGrowth") "the shared red is listed pre-existing")
      (assert (stringContains? (out r2) ":planRows ((:u MC-foreignGrowth-") "a ready plan row is printed")
      (assert (stringContains? (out r2) ":ledgerAdded 1") "the first ledger run adds the row")
      (assert (stringContains? (out r2b) ":ledgerAdded 0") "the second ledger run adds nothing")
      (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:u MC-foreignGrowth-")) rows)) 1) "the ledger holds the row exactly once")
      (assert (and (stringContains? (out r2) "pkg/tests/aTest.asl") (and (stringContains? (out r2) "pkg/tests/bTest.asl") (stringContains? (out r2) "pkg2/tests/cTest.asl"))) "the package suites and the importer suite are all run")
      (assert (stringContains? (out r2) ":complete true") "nothing was cut with the default cap")
      (assert (stringContains? (out r2) ":judged :pass") "equal asserts pass")
      (assert (= (pairFirst r3) 1) (str "a drop in executed asserts blocks: " (out r3)))
      (assert (stringContains? (out r3) ":judged :regression") "the suite is the regression")
      (assert (= (pairFirst r4) 1) (str "a commit that is not an ASN line blocks: " (out r4)))
      (assert (stringContains? (out r4) "notOneAsnLine") "the structure problem is named")
      (assert (= (pairFirst r5) 3) (str "a spent deadline is unverified with exit 3: " (out r5)))
      (assert (stringContains? (out r5) ":verdict unverified") "the verdict is unverified, never pass")
      (assert (stringContains? (out r5) ":complete false") "a spent deadline reports incomplete")
      (assert (stringContains? (out r5) "consistencyHead:deadline") "the skipped step is listed unverified")
      (assert (not (stringContains? (out r5) ":suites ((:suite")) "a step that did not run has no suite result")
      (assert (= (pairFirst r6) 3) (str "suites cut by the cap make the run unverified: " (out r6)))
      (assert (and (stringContains? (out r6) "suite:pkg/tests/bTest.asl:cutByMaxSuites") (stringContains? (out r6) "suite:pkg2/tests/cTest.asl:cutByMaxSuites")) "the cut suites are listed")
      (assert (not (stringContains? (out r6) "suite:pkg/tests/aTest.asl:cutByMaxSuites")) "the touched package runs first")
      (assert (and (stringContains? (out r6b) "suite:pkg2/tests/cTest.asl:cutByMaxSuites") (not (stringContains? (out r6b) "suite:pkg/tests/bTest.asl:cutByMaxSuites"))) "the importer is cut before the touched package")
      (assert (and (= (pairFirst r7) 0) (stringContains? (out r7) ":mode cheap") (stringContains? (out r7) ":suites ()")) (str "cheap mode runs no suites: " (out r7)))
      (assert (and (stringContains? (out r7) ":baseCheckout false") (stringContains? (out r7) ":baseCached 2")) "a cached base needs no base checkout")
      (assert (and (> (listLength (resultOr (dirList cache) (list))) 3) (fileExists? (str cache "/" c1 "-gates.asn"))) "base audits are cached by sha")
      (assert (and (= (pairFirst r8) 1) (stringContains? (out r8) ":check :id gate")) (str "a failing --gate blocks: " (out r8)))
      (assert (= (pairFirst r8b) 0) (str "a passing --gate passes: " (out r8b)))
      (assert (= (pairFirst r9) 0) (str "a retried pass does not block and a merge commit is exempt: " (out r9)))
      (assert (stringContains? (out r9) ":flaky (\"pkg/tests/aTest.asl\")") "the flaky suite is listed")
      (assert (stringContains? (out r9) ":retried true :firstWhy") "the row records the retry")
      (assert (and (= (pairFirst r10) 1) (stringContains? (out r10) ":regressions ((:check :id foreignGrowth")) (str "a red that got worse blocks: " (out r10)))
      (assert (and (= (pairFirst r11) 0) (stringContains? (out r11) ":headCheckout false")) (str "an existing head checkout is used: " (out r11)))
      true))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/mergeCheckTest-" (stringFromInt64 (procSelf))))
        (_ (sh "." (list "mkdir" "-p" base)))
        (a (testPure))
        (b (testE2e base))
        (_ (pathRemove base))]
    (and a b))
