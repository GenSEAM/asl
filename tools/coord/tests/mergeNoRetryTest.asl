(module asl-tools/coord/tests/mergeNoRetryTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-RED-NO-RETRY :do "under (:conductor :redNoRetry true) a train is not started again for a unit whose branch head, train base and red signature are those of its last red train: the unit parks blocked await redSame with the red text, or goes to its writer when a mergeRed round is left; a base that moved during the train or after it allows one more train per base head, a new branch head goes back to ready, a kill keeps its retry, and without the key the retry is today's; stores are scratch dirs under this worktree's .asl/cache")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "noRetryTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuNow root: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! (str root "/store"))) (pf/cuIn id "absent" "" ""))

fn resOf sig: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict "fail" :tiers "")

; (:m :do "the unit merging with a live lease, as after its review passed, then one merge result")
fn ! fin! root: String u: st/Task sig: String -> cd/CUnit
  (let [(store (str root "/store"))
        (c0 (cuNow root u.id))
        (epoch (if (> c0.epoch 0) c0.epoch (match (st/claim! store u.id "noRetryTest" 3600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0))))
        (c (with c0 :st "merging" :epoch epoch :launched 1))
        (_ (cd/writeCUnit! store c))
        (_ (cd/finish! (ctxFor root) u c (resOf sig)))]
    (cuNow root u.id))

fn ! rev root: String ref: String -> String
  (stringTrim (pf/sh (str "git -C " root "/repo rev-parse --short=9 " ref)))

fn ! rows root: String head: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l head)) (pf/journalLines (str root "/store")))

fn ! newestT root: String id: String -> String
  (optionOr (listLast (rows root (str "(:t :unit " (st/q id) " "))) "")

fn ! seeded! root: String id: String -> st/Task
  (let [(u (with (pf/unitIn id "true") :base "bx"))
        (_ (pf/seedUnit! root (pf/unitIn id "true") "merging" (str id ".txt")))
        (_ (st/put! (str root "/store") u))]
    u)

fn red -> String
  "train red: asl/a/aTest.asl"

fn receipt red: String -> String
  (str "(:train :head \"abc\" :merged \"def\" :branches (\"sh/F1\") :changed 1 :selected 1 :cached 0 :ran 1 :green 0 :invariants 0 :red (" red ") :preexisting () :assertLoss () :baseKnown 0 :knownRed () :blocked (:fresh 1 :preexisting 0) :seconds 9)")

fn redOut branch: String err: String -> String
  (str "(:redLive \"asl/a/aTest.asl\" 1 7 :kind suite :err (\"ERR_ASSERT: " err "\"))\n"
       (receipt (str "(\"asl/a/aTest.asl\" \"" branch "\" 1 7 :kind suite :why only :err (\"ERR_ASSERT: " err "\"))")) "\n")

fn ! attempt! root: String id: String sig: String out: String -> Bool
  (let [(store (str root "/store"))
        (tdir (cd/trainsDir store id))
        (_ (dirCreate (str store "/trains")))
        (_ (dirCreate tdir))]
    (ok? (fileWrite (str tdir "/000001.out")
                    (str "(:trainAttempt :unit " (st/q id) " :n 1 :branch " (st/q (str "sh/" id)) " :at 1 :exit 1 :ms 5 :verdict \"exit\" :sig " (st/q sig) ")\n" out))))

fn ! runTests -> Bool
  (let [(root (pf/scratch "mergeNoRetry" "w"))
        (_ (pf/cleanup root))
        (store (str root "/store"))
        (repo (pf/repoIn root))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (pf/sh (str "cd " repo " && git branch -f bx main && echo ok")))
        (ctx (ctxFor root))
        ; (:m :do "no key: today's retry, and the red is recorded with its head and base")
        (u0 (seeded! root "N0"))
        (a0 (fin! root u0 (red)))
        (headN0 (rev root "sh/N0"))
        (bx0 (rev root "bx"))
        (rec0 (resultOr (fileReadString (cd/redTrainPath store "N0")) ""))
        (_ (cd/writeCUnit! store (with a0 :st "merged" :launched 0 :epoch 0)))
        (_ (st/release! store "N0" a0.epoch))
        (_ (fileWrite (str store "/ladder.asn") "(:conductor :redNoRetry true)\n"))
        (problems (cd/ladderProblems store))
        ; (:m :do "unchanged head and base: no second train")
        (u1 (seeded! root "N1"))
        (b1 (fin! root u1 (red)))
        (t1 (newestT root "N1"))
        (same1 (resultOr (fileReadString (cd/redSamePath store "N1")) ""))
        (esc1 (resultOr (fileReadString (cd/escalationsPath store)) ""))
        (units (list u0 u1))
        (_ (cd/retryBlocked! ctx units))
        (still1 (cuNow root "N1"))
        ; (:m :do "a base that moved during the train allows one more train, which records its own base")
        (u2 (seeded! root "N2"))
        (_ (dirCreate (cd/runsDir store)))
        (_ (fileWrite (cd/mergeBasePath store "N2") "000000001\n"))
        (r2 (fin! root u2 (red)))
        (base2 (resultOr (fileReadString (cd/mergeBasePath store "N2")) ""))
        (r2b (fin! root u2 (red)))
        ; (:m :do "a kill keeps its retry")
        (u3 (seeded! root "N3"))
        (k3 (fin! root u3 "killed: timeout after 3600 s :running 2 a.asl b.asl"))
        (_ (cd/writeCUnit! store (with k3 :st "merged" :launched 0 :epoch 0)))
        (_ (st/release! store "N3" k3.epoch))
        ; (:m :do "the base moves after the block: one train at the new base, then blocked again on its red")
        (bxOld (rev root "bx"))
        (_ (pf/sh (str "cd " repo " && git branch -f bx sh/N0 && echo ok")))
        (bxNew (rev root "bx"))
        (_ (cd/retryBlocked! ctx (list u1)))
        (w1 (cuNow root "N1"))
        (l1 (cd/launch! ctx u1 w1))
        (again1 (fin! root u1 (red)))
        (baseRec1 (cd/redTrainField! store "N1" "base"))
        (_ (cd/retryBlocked! ctx (list u1)))
        (stay1 (cuNow root "N1"))
        ; (:m :do "a new branch head goes back to ready through gating and review")
        (_ (pf/sh (str "cd " repo " && git branch sh/H1 sh/N1 && echo ok")))
        (uh (with (pf/unitIn "H1" "true") :base "bx"))
        (_ (st/put! store uh))
        (_ (cd/writeCUnit! store (pf/cuIn "H1" "merging" "" "sh/H1")))
        (h1 (fin! root uh (red)))
        (_ (pf/sh (str "cd " repo " && git branch -f sh/H1 main && echo ok")))
        (_ (cd/retryBlocked! ctx (list uh)))
        (hw (cuNow root "H1"))
        (th (newestT root "H1"))
        ; (:m :do "a mergeRed round left: the would-be repeat goes to the writer instead")
        (_ (fileWrite (str store "/ladder.asn") "(:conductor :redNoRetry true)\n(:mergeRed :fixRounds 2)\n"))
        (uf (seeded! root "F1"))
        (cf0 (with (cuNow root "F1") :sig (red) :launched 0))
        (_ (cd/writeCUnit! store cf0))
        (_ (attempt! root "F1" (red) (redOut "sh/F1" "expected (1) got (2)")))
        (_ (cd/redTrainRow! ctx uf cf0 (red)))
        (f1 (cd/launch! ctx uf cf0))
        (note1 (cd/mergeRedNote! store "F1"))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (and (not (stringEmpty? repo)) (not (stringEmpty? bxOld))) "fixture: a repo and its base head")
        (assert (and stubGone (listEmpty? (fr/stubDirsOwnedBy (procSelf)))) "the stand-in host dir of this run is removed")
        (assert (and (= a0.st "merging") (and (= a0.fails 1) (= a0.launched 1))) (str "without the key a red is retried as today: " a0.st " " (stringFromInt64 a0.fails) " " (stringFromInt64 a0.launched)))
        (assert (stringContains? rec0 (str ":head " (st/q headN0) " :base " (st/q bx0) " :sig " (st/q (red)))) (str "every red train is recorded with the branch head and the base it ran on: " rec0))
        (assert (listEmpty? problems) (str "the key is a valid conductor row: " (stringJoin problems "; ")))
        (assert (not (listEmpty? (cd/cdErrors "(:conductor :redNoRetry true :bogus 1)"))) "an unknown key beside it is still an error")
        (assert (and (= b1.st "blocked") (= b1.await "redSame")) (str "the same head and base start no second train: " b1.st " " b1.await " " b1.sig))
        (assert (and (= b1.sig (red)) (= b1.epoch 0)) (str "the blocked unit keeps the red signature and drops its lease: " b1.sig))
        (assert (stringContains? t1 ":verdict \"redUnchanged: train red: asl/a/aTest.asl\"") (str "the transition names the reason: " t1))
        (assert (stringContains? same1 ":sig \"train red: asl/a/aTest.asl\"") (str "the red is stored beside the unit: " same1))
        (assert (stringContains? esc1 "merge red unchanged: head ") (str "one escalation tells why: " esc1))
        (assert (and (= still1.st "blocked") (= still1.await "redSame")) (str "nothing changed: the blocked retry leaves it: " still1.st))
        (assert (and (= r2.st "merging") (= r2.launched 1)) (str "a base that moved while the train ran allows one more train: " r2.st " " (stringFromInt64 r2.launched)))
        (assert (= (stringTrim base2) bxOld) (str "that train records the base it runs onto: " base2))
        (assert (and (= r2b.st "blocked") (= r2b.await "redSame")) (str "its red at the same base is not run a third time: " r2b.st " " r2b.await))
        (assert (and (= k3.st "merging") (and (= k3.launched 1) (!= k3.await "redSame"))) (str "a killed train keeps its retry: " k3.st " " k3.await))
        (assert (!= bxOld bxNew) "fixture: the base moved")
        (assert (and (= w1.st "merging") (and (> w1.epoch 0) (stringEmpty? w1.await))) (str "a moved base claims the lease and goes back to merging: " w1.st " " (stringFromInt64 w1.epoch) " " w1.await))
        (assert (= l1.launched 1) (str "and its train starts: " (stringFromInt64 l1.launched) " " l1.st))
        (assert (and (= again1.st "blocked") (= baseRec1 bxNew)) (str "a red at the new base blocks again, recorded at that base: " again1.st " " baseRec1))
        (assert (and (= stay1.st "blocked") (= stay1.await "redSame")) (str "one train per base head: the unchanged new base wakes nothing: " stay1.st))
        (assert (and (= h1.st "blocked") (= h1.await "redSame")) (str "fixture: a unit blocked on its red: " h1.st))
        (assert (and (= hw.st "ready") (and (stringEmpty? hw.await) (= hw.epoch 0))) (str "a new branch head sends it to ready: " hw.st " " hw.await))
        (assert (stringContains? th ":stage redWake ") (str "journalled as a redWake: " th))
        (assert (and (= f1.st "ready") (stringStartsWith? f1.sig "mergeRedFix 1/2: ")) (str "with a mergeRed round left the repeat goes to the writer: " f1.st " " f1.sig))
        (assert (stringContains? note1 "expected (1) got (2)") (str "with the red text: " (cd/utf8Clip note1 200)))
        true))
