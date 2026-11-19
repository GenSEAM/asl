(module asl-tools/coord/tests/trainTimeoutProgressTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-TRAIN-PIN-WEAK :do "a train its limit killed keeps what it finished: the unit stays merging with its lease and fail count while each attempt finishes a suite green and leaves fewer unfinished than the one before, and is parked only by an attempt that brought nothing; the verdict and the journal row name the unfinished suites, or the phase and the reds when every suite was done; the retry waits its turn behind a fresh unit; the kept attempts are files in a scratch store under this worktree's .asl/cache and no train runs")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "ttpTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 100000 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn n i: Int64 -> String
  (stringFromInt64 i)

fn ! cuNow root: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! (str root "/store"))) (pf/cuIn id "absent" "" ""))

fn resOf sig: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict "fail" :tiers "")

fn ! waiting! root: String id: String -> cd/CUnit
  (let [(store (str root "/store"))
        (c0 (cuNow root id))
        (epoch (if (> c0.epoch 0) c0.epoch (match (st/claim! store id "ttpTest" 3600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0))))
        (c (with c0 :st "merging" :epoch epoch :launched 0))
        (_ (cd/writeCUnit! store c))]
    c)

fn ! seeded! root: String id: String -> st/Task
  (let [(u (with (pf/unitIn id "true") :base "main" :owns (list (str id ".txt"))))
        (_ (pf/seedUnit! root (pf/unitIn id "true") "merging" (str id ".txt")))
        (_ (st/put! (str root "/store") u))]
    u)

fn running items: (List String) -> String
  (str "(:trainRunning :items (" (stringJoin (map st/q items) " ") "))")

fn done p: String exit: Int64 -> String
  (str "(:itemDone " (st/q p) " " (n exit) ")")

fn killRow sec: Int64 -> String
  (str "(:fleetRun :verdict :timeout :pid 1 :desc 3 :timeoutMs " (n (* sec 1000)) " :maxDesc 200 :left 0)")

; (:m :do "one train of the unit ended by its limit: the attempt is kept as the merge stage keeps it, under the next number with the signature gateSig reads from the output, and the stage result is applied")
fn ! killed! root: String u: st/Task attempt: Int64 rows: (List String) sec: Int64 -> cd/CUnit
  (let [(store (str root "/store"))
        (out (str (stringJoin (listAppend rows (list (killRow sec))) "\n") "\n"))
        (sig (cd/gateSig out))
        (dir (cd/trainsDir store u.id))
        (_ (dirCreate (str store "/trains")))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/00000" (n attempt) ".out") (str "(:trainAttempt :unit " (st/q u.id) " :n " (n attempt) " :branch \"sh/" u.id "\" :at 1 :exit 124 :ms 1 :verdict \"timeout\" :sig " (st/q sig) ")\n" out)))
        (c (with (waiting! root u.id) :launched 1))
        (_ (cd/writeCUnit! store c))
        (_ (cd/finish! (ctxFor root) u c (resOf sig)))]
    (cuNow root u.id))

fn ! tRows root: String id: String part: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringStartsWith? l (str "(:t :unit " (st/q id) " ")) (stringContains? l part))) (pf/journalLines (str root "/store")))

fn ! ttRows root: String id: String part: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringStartsWith? l (str "(:trainTimeout :action ")) (and (stringContains? l (str " :unit " (st/q id) " ")) (stringContains? l part)))) (pf/journalLines (str root "/store")))

fn ! escRows root: String id: String part: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringStartsWith? l (str "(:escalate :unit " (st/q id) " ")) (stringContains? l part)))
          (stringLines (resultOr (fileReadString (cd/escalationsPath (str root "/store"))) "")))

fn ! leaseOf root: String id: String -> String
  (resultOr (fileReadString (st/leasePath (str root "/store") id)) "")

fn receipt slow: String -> String
  (str "(:train :head \"abc\" :merged \"def\" :branches (\"sh/X\") :changed 1 :selected 2 :red () :preexisting () :assertLoss () :phasesMs (:suites 9000 :blame 4000) :slowestMs " slow " :carried (:forced () :added ()) :seconds 13)")

fn ! runTests -> Bool
  (let [(root (pf/scratch "trainTimeoutProgress" "a"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (str store "/ladder.asn") "(:conductor :redNoRetry true)\n(:train :limitS 600)\n"))
        (ctx (ctxFor root))
        ; (:m :do "P: 4 suites, the first attempt finishes 2, the second one more, the third none")
        (up (seeded! root "P"))
        (p0 (waiting! root "P"))
        (p1 (killed! root up 1 (list (running (list "a/aTest.asl" "b/bTest.asl" "c/cTest.asl" "d/dTest.asl")) (done "a/aTest.asl" 0) (done "b/bTest.asl" 0)) 600))
        (lease1 (leaseOf root "P"))
        (left1 (stringTrim (resultOr (fileReadString (cd/deadlineLeftPath store "P")) "")))
        (note1 (fileExists? (cd/trainTimeoutPath store "P")))
        ; (:m :do "F never had a train: the stage goes to it, not back to P at once")
        (uf (seeded! root "F"))
        (_ (waiting! root "F"))
        (_ (cd/tick! ctx))
        (pTick (cuNow root "P"))
        (fTick (cuNow root "F"))
        (p2 (killed! root up 2 (list (running (list "c/cTest.asl" "d/dTest.asl")) (done "c/cTest.asl" 0)) 600))
        (left2 (stringTrim (resultOr (fileReadString (cd/deadlineLeftPath store "P")) "")))
        (p3 (killed! root up 3 (list (running (list "d/dTest.asl"))) 600))
        (lease3 (leaseOf root "P"))
        (retryP (tRows root "P" " :from merging :to merging :stage merge "))
        (blockP (tRows root "P" " :from merging :to blocked :stage merge "))
        (rowsP (ttRows root "P" ""))
        (escP (escRows root "P" "trainTimeout"))
        ; (:m :do "Q: the second attempt finishes a suite and leaves as many unfinished as the first")
        (uq (seeded! root "Q"))
        (_ (waiting! root "Q"))
        (q1 (killed! root uq 1 (list (running (list "a/aTest.asl" "b/bTest.asl" "c/cTest.asl")) (done "a/aTest.asl" 0)) 600))
        (q2 (killed! root uq 2 (list (running (list "b/bTest.asl" "c/cTest.asl" "x/xTest.asl")) (done "x/xTest.asl" 0)) 600))
        (rowQ (stringJoin (ttRows root "Q" " :action blocked ") "|"))
        ; (:m :do "R: only a red suite finished, nothing green to keep")
        (ur (seeded! root "R"))
        (_ (waiting! root "R"))
        (r1 (killed! root ur 1 (list (running (list "a/aTest.asl" "b/bTest.asl")) "(:redLive \"a/aTest.asl\" 1 2 :kind suite)" (done "a/aTest.asl" 1)) 600))
        ; (:m :do "S: the AUD-FINDING shape, every suite done and the kill in the recheck of the reds")
        (us (seeded! root "S"))
        (_ (waiting! root "S"))
        (sRows (list (running (list "a/aTest.asl" "b/bTest.asl")) (done "a/aTest.asl" 0) "(:redLive \"b/bTest.asl\" 1 2 :kind suite)" (done "b/bTest.asl" 1) "(:trainPhase :name \"suites\" :ms 2679447)"))
        (s1 (killed! root us 1 sRows 5400))
        (s2 (killed! root us 2 sRows 5400))
        (retryS (stringJoin (tRows root "S" " :from merging :to merging :stage merge ") "|"))
        (blockS (stringJoin (tRows root "S" " :from merging :to blocked :stage merge ") "|"))
        (rowS (stringJoin (ttRows root "S" " :action retry ") "|"))
        ; (:m :do "W: 12 suites unfinished, the verdict names ten and counts the rest")
        (uw (seeded! root "W"))
        (_ (waiting! root "W"))
        (twelve (map (fn [(i Int64)] -> String (str "s/s" (n i) "Test.asl")) (range 1 13)))
        (w1 (killed! root uw 1 (list (running (cons "g/gTest.asl" twelve)) (done "g/gTest.asl" 0)) 600))
        (retryW (stringJoin (tRows root "W" " :from merging :to merging :stage merge ") "|"))
        (rowW (stringJoin (ttRows root "W" "") "|"))
        ; (:m :do "a requeue forgets the counter")
        (_ (cd/requeueOne! ctx (list up) "P"))
        (leftReq (fileExists? (cd/deadlineLeftPath store "P")))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))
        ; (:m :do "the time row of an attempt")
        (full (cd/trainTimesRow "U" 3 1 13000 (stringJoin (list "(:trainPhase :name \"prepare\" :ms 200)" (running (list "a/aTest.asl" "b/bTest.asl")) (done "a/aTest.asl" 0) (done "b/bTest.asl" 1)
                                                                  "(:trainPhase :name \"suites\" :ms 9000)" "(:trainPhase :name \"blame\" :ms 4000)" (receipt "((\"b/bTest.asl\" 8000) (\"a/aTest.asl\" 1000))")) "\n")))
        (cut (cd/trainTimesRow "U" 4 124 600000 (stringJoin (list "(:trainPhase :name \"prepare\" :ms 200)" (running (list "a/aTest.asl" "b/bTest.asl")) (done "a/aTest.asl" 0) (killRow 600)) "\n")))
        (none (cd/trainTimesRow "U" 5 1 10 (receipt "()")))]
    (do (assert (and stubGone (listEmpty? (fr/stubDirsOwnedBy (procSelf)))) "the stand-in host dir of this run is removed")
        (assert (and (not (stringEmpty? repo)) (and (= p0.st "merging") (> p0.epoch 0))) "fixture: a scratch repo and P merging under its lease")
        (assert (and (= p1.st "merging") (stringEmpty? p1.await)) (str "a kill that finished two suites green keeps the unit merging: " p1.st " " p1.await))
        (assert (and (= p1.epoch p0.epoch) (not (stringEmpty? lease1))) (str "its lease stays: " (n p1.epoch) " " lease1))
        (assert (and (= p1.fails p0.fails) (= p1.launched 0)) (str "no fail is charged and no train is started by the kill itself: " (n p1.fails) " " (n p1.launched)))
        (assert (and (= left1 "2") (not note1)) (str "the counter holds the two unfinished suites and no park note is written: " left1))
        (assert (and (= fTick.launched 1) (= pTick.launched 0)) (str "the next tick gives the stage to the unit with no outcome, the retry waits: F " (n fTick.launched) " P " (n pTick.launched)))
        (assert (and (= p2.st "merging") (= left2 "1")) (str "one suite fewer left keeps it merging again: " p2.st " " left2))
        (assert (and (= p3.st "blocked") (= p3.await "trainTimeout")) (str "an attempt that finished no suite parks it: " p3.st " " p3.await))
        (assert (and (= p3.epoch 0) (stringEmpty? lease3)) (str "the park drops the lease: " lease3))
        (assert (= p3.fails p0.fails) "still no fail charged")
        (assert (= (listLength retryP) 2) (str "two retries journalled: " (stringJoin retryP "|")))
        (assert (stringContains? (optionOr (listHead retryP) "") " :verdict \"trainTimeout: retry, 600 s, 2 suites still running: c/cTest.asl d/dTest.asl\"") (str "the retry verdict names the two unfinished suites: " (optionOr (listHead retryP) "")))
        (assert (and (= (listLength blockP) 1) (stringContains? (optionOr (listHead blockP) "") " :verdict \"trainTimeout: 600 s, 1 suites still running: d/dTest.asl\"")) (str "the park verdict names the suite that never finished: " (stringJoin blockP "|")))
        (assert (= (listLength rowsP) 3) (str "one trainTimeout journal row per kill: " (n (listLength rowsP))))
        (assert (stringContains? (optionOr (listGet rowsP 0) "") " :action retry :unit \"P\" :why progress :left 2 :prior -1 :doneGreen 2 :limitS 600 :afterPhase \"\" :unfinished (\"c/cTest.asl\" \"d/dTest.asl\") ") (str "the first row: " (optionOr (listGet rowsP 0) "")))
        (assert (stringContains? (optionOr (listGet rowsP 1) "") " :action retry :unit \"P\" :why progress :left 1 :prior 2 :doneGreen 1 ") (str "the second row compares with the attempt before: " (optionOr (listGet rowsP 1) "")))
        (assert (stringContains? (optionOr (listGet rowsP 2) "") " :action blocked :unit \"P\" :why noProgress :left 1 :prior 1 :doneGreen 0 ") (str "the third row says why it parked: " (optionOr (listGet rowsP 2) "")))
        (assert (and (= (listLength escP) 1) (stringContains? (optionOr (listHead escP) "") "0 suites finished green in it, 1 left unfinished, 1 left by the attempt before")) (str "one escalation, with the counts: " (stringJoin escP "|")))
        (assert (and (= q1.st "merging") (and (= q2.st "blocked") (= q2.await "trainTimeout"))) (str "as many suites left as before parks the unit though one finished: " q1.st " " q2.st))
        (assert (stringContains? rowQ " :why noProgress :left 2 :prior 2 :doneGreen 1 ") (str "its row: " rowQ))
        (assert (and (= r1.st "blocked") (= r1.await "trainTimeout")) (str "a first attempt whose only finished suite is red parks: " r1.st))
        (assert (and (= s1.st "merging") (and (= s2.st "blocked") (= s2.await "trainTimeout"))) (str "killed after its suites: once more, then parked: " s1.st " " s2.st))
        (assert (stringContains? retryS " :verdict \"trainTimeout: retry, 5400 s, 0 suites still running, killed after phase suites while rechecking reds: b/bTest.asl\"") (str "the verdict names the phase and the red, not unknown suites: " retryS))
        (assert (and (stringContains? blockS " :verdict \"trainTimeout: 5400 s, 0 suites still running, killed after phase suites while rechecking reds: b/bTest.asl\"") (not (stringContains? (str retryS blockS) "unknown"))) (str "so does the park: " blockS))
        (assert (stringContains? rowS " :left 0 :prior -1 :doneGreen 1 :limitS 600 :afterPhase \"suites\" :unfinished () ") (str "its row has the phase and no unfinished suite: " rowS))
        (assert (= w1.st "merging") (str "fixture: W retried: " w1.st))
        (assert (stringContains? retryW " 12 suites still running: s/s1Test.asl s/s2Test.asl s/s3Test.asl s/s4Test.asl s/s5Test.asl s/s6Test.asl s/s7Test.asl s/s8Test.asl s/s9Test.asl s/s10Test.asl +2\"") (str "ten names and the rest counted: " retryW))
        (assert (stringContains? rowW "\"s/s11Test.asl\" \"s/s12Test.asl\") ") (str "the journal row names every one: " rowW))
        (assert (not leftReq) "a requeue removes the counter")
        (assert (= full "(:trainTimes :unit \"U\" :n 3 :exit 1 :ms 13000 :receipt true :phases ((\"prepare\" 200) (\"suites\" 9000) (\"blame\" 4000)) :slowest ((\"b/bTest.asl\" 8000) (\"a/aTest.asl\" 1000)) :unfinished ())") (str "a finished train: phases in order and the receipt's longest items: " full))
        (assert (= cut "(:trainTimes :unit \"U\" :n 4 :exit 124 :ms 600000 :receipt false :phases ((\"prepare\" 200)) :slowest () :unfinished (\"b/bTest.asl\"))") (str "a killed train: no receipt, the unfinished suite by name: " cut))
        (assert (stringContains? none " :receipt true :phases () :slowest () :unfinished ())") (str "an empty slowest list stays empty: " none))
        true))
