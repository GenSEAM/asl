(module asl-tools/coord/tests/mergeRedFixTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-RED-TO-WRITER :do "a merge train red the unit's own branch caused goes back to its writer as a bounded fix round under (:mergeRed :fixRounds N): the attribution rules on train outputs, the addendum bounds, the finish! transitions (fix round, unchanged, exhausted, default, stale attempt, base red, batch passengers), the writer's brief and the status row; stores are scratch dirs under this worktree's .asl/cache")

fn receipt red: String pre: String loss: String -> String
  (str "(:train :head \"abc\" :merged \"def\" :branches (\"sh/M1\") :changed 1 :selected 1 :cached 0 :ran 1 :green 0 :invariants 0 :red (" red ") :preexisting (" pre ") :assertLoss (" loss ") :baseKnown 0 :knownRed () :blocked (:fresh 1 :preexisting 0) :seconds 9)")

fn entry path: String branch: String why: String err: String -> String
  (str "(\"" path "\" \"" branch "\" 1 7 :kind suite :why " why " :err (\"ERR_ASSERT: " err "\"))")

fn live path: String err: String -> String
  (str "(:redLive \"" path "\" 1 7 :kind suite :err (\"ERR_ASSERT: " err "\" \"second line\"))")

fn redOut path: String branch: String err: String -> String
  (str (live path err) "\n" (receipt (entry path branch "only" err) "" "") "\n")

fn got? o: (Option cd/MergeRed) -> Bool
  (match o ((some _) true) ((none) false))

fn suitesOf o: (Option cd/MergeRed) -> String
  (match o ((some r) (stringJoin r.suites " ")) ((none) ""))

fn keyOf o: (Option cd/MergeRed) -> String
  (match o ((some r) r.key) ((none) ""))

fn moreOf o: (Option cd/MergeRed) -> Int64
  (match o ((some r) r.more) ((none) -1))

fn ! testRows root: String -> Bool
  (let [(store (str root "/rows"))
        (_ (dirCreate root))
        (_ (dirCreate store))
        (_ (fileWrite (str store "/ladder.asn") "(:mergeRed :fixRounds 11)\n"))
        (bad (cd/ladderProblems store))
        (_ (fileWrite (str store "/ladder.asn") "(:train :jobs 2)\n(:mergeRed :fixRounds 3)\n"))
        (good (cd/ladderProblems store))
        (row (cd/mergeRedRowOf store))]
    (do (assert (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds 2)")) "a fixRounds row in range is valid")
        (assert (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds 0)")) "0 rounds is valid, today's behaviour")
        (assert (not (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds 11)"))) "more than 10 rounds is rejected")
        (assert (not (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds -1)"))) "a negative count is rejected")
        (assert (not (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds two)"))) "a count that is no number is rejected")
        (assert (not (listEmpty? (cd/mergeRedErrors "(:mergeRed :fixRounds 2 :retries 1)"))) "an unknown key is rejected")
        (assert (not (listEmpty? (cd/mergeRedErrors "(:mergeRed)"))) "a row without fixRounds is rejected")
        (assert (= (cd/mergeRedRounds "") 0) "no row: no fix round")
        (assert (= (cd/mergeRedRounds "(:mergeRed :fixRounds 11)") 0) "a rejected row: no fix round")
        (assert (= (cd/mergeRedRounds "(:mergeRed :fixRounds 3)") 3) "a valid row sets the rounds")
        (assert (listAny? (fn [(p String)] -> Bool (stringStartsWith? p "ladder mergeRed: ")) bad) (str "ladderProblems names a rejected mergeRed row: " (stringJoin bad "; ")))
        (assert (listEmpty? good) (str "a valid mergeRed row beside a train row is no problem: " (stringJoin good "; ")))
        (assert (= row "(:mergeRed :fixRounds 3)") (str "the row is read from the store's ladder.asn: " row))
        true))

fn ! testAttribution -> Bool
  (let [(only (cd/mergeRedOf (redOut "s.asl" "sh/M1" "expected (1) got (2)") "sh/M1"))
        (again (cd/mergeRedOf (redOut "s.asl" "sh/M1" "expected (1) got (2)") "sh/M1"))
        (other (cd/mergeRedOf (redOut "s.asl" "sh/M1" "expected (1) got (3)") "sh/M1"))
        (noLive (cd/mergeRedOf (str (receipt (entry "s.asl" "sh/M1" "only" "from the receipt") "" "") "\n") "sh/M1"))
        (pre (cd/mergeRedOf (str (live "s.asl" "e") "\n" (receipt (entry "s.asl" "sh/M1" "only" "e") (entry "b.asl" "base" "preexisting" "e") "") "\n") "sh/M1"))
        (loss (cd/mergeRedOf (str (live "s.asl" "e") "\n" (receipt (entry "s.asl" "sh/M1" "only" "e") "" "\"l.asl\"") "\n") "sh/M1"))
        (killed (cd/mergeRedOf (str "(:fleetRun :verdict :timeout :timeoutMs 3600000)\n" (redOut "s.asl" "sh/M1" "e")) "sh/M1"))
        (noReceipt (cd/mergeRedOf (str (live "s.asl" "e") "\n") "sh/M1"))
        (failed (cd/mergeRedOf (str "(:train :status :failed :error (:err :silentSuites :ran 1))\n" (redOut "s.asl" "sh/M1" "e")) "sh/M1"))
        (commitErr (cd/mergeRedOf (str (live "s.asl" "e") "\n" (stringReplace (receipt (entry "s.asl" "sh/M1" "only" "e") "" "") " :seconds 9)" " :commitError \"x\" :seconds 9)") "\n") "sh/M1"))
        (inter (cd/mergeRedOf (str (live "s.asl" "e") "\n" (receipt (entry "s.asl" "sh/M1+sh/M2" "interaction" "e") "" "") "\n") "sh/M1"))
        (bisect (cd/mergeRedOf (str (live "s.asl" "e") "\n" (receipt (str (entry "s.asl" "sh/M1" "alone" "e") " " (entry "c.asl" "sh/M3" "bisect" "e")) "" "") "\n") "sh/M1"))
        (elsewhere (cd/mergeRedOf (str (live "s.asl" "e") "\n" (receipt (entry "s.asl" "sh/M2" "alone" "e") "" "") "\n") "sh/M1"))
        (batch (cd/mergeRedOf (str (live "s.asl" "mine") "\n" (live "t.asl" "theirs") "\n" (receipt (str (entry "s.asl" "sh/M1" "alone" "mine") " " (entry "t.asl" "sh/M2" "alone" "theirs")) "" "") "\n") "sh/M1"))
        (noFresh (cd/mergeRedOf (str (receipt "" "" "") "\n") "sh/M1"))]
    (do (assert (got? only) "a red the train attributes to this branch only is the writer's")
        (assert (stringContains? (suitesOf only) "(:suite \"s.asl\" :exit 1 :asserts 7 :err ") (str "the suite carries path, exit and assert count: " (suitesOf only)))
        (assert (stringContains? (suitesOf only) "ERR_ASSERT: expected (1) got (2)") (str "and the error text of its redLive row, parentheses kept: " (suitesOf only)))
        (assert (stringContains? (suitesOf only) "second line") (str "the redLive row's error lines are preferred over the receipt's: " (suitesOf only)))
        (assert (stringContains? (suitesOf noLive) "ERR_ASSERT: from the receipt") (str "with no redLive row the receipt entry's errors are used: " (suitesOf noLive)))
        (assert (and (= (keyOf only) (keyOf again)) (!= (keyOf only) (keyOf other))) (str "the key is the same for the same red and differs with the error: " (keyOf only) " " (keyOf other)))
        (refute (got? pre) "a red on the base too keeps the merge failure path")
        (refute (got? loss) "an assert loss keeps the merge failure path")
        (refute (got? killed) "a killed train keeps the merge failure path")
        (refute (got? noReceipt) "a train with no receipt keeps the merge failure path")
        (refute (got? failed) "a failed train (infra) keeps the merge failure path")
        (refute (got? commitErr) "a commit error keeps the merge failure path")
        (refute (got? inter) "a red of a branch combination keeps the merge failure path")
        (refute (got? bisect) "a red a bisection placed keeps the merge failure path for every member")
        (refute (got? elsewhere) "a red of another branch alone is not this writer's")
        (refute (got? noFresh) "a receipt with no fresh red is no fix round")
        (assert (and (stringContains? (suitesOf batch) "s.asl") (not (stringContains? (suitesOf batch) "t.asl"))) (str "a batch red is split: this branch gets its own suite only: " (suitesOf batch)))
        true))

fn ! testBounds -> Bool
  (let [(paths (list "a.asl" "b.asl" "c.asl" "d.asl" "e.asl" "f.asl"))
        (long (stringJoin (map (fn [(i Int64)] -> String "0123456789") (range 0 100)) ""))
        (out (str (stringJoin (map (fn [(p String)] -> String (live p (str p " " long))) paths) "\n") "\n"
                  (receipt (stringJoin (map (fn [(p String)] -> String (entry p "sh/M1" "only" p)) paths) " ") "" "") "\n"))
        (r (cd/mergeRedOf out "sh/M1"))
        (s (suitesOf r))
        (note (match r ((some x) (cd/mergeRedNote x 1 2 "sh/M1")) ((none) "")))]
    (do (assert (got? r) "six red suites of this branch are a fix round")
        (assert (= (listLength (stringSplit s "(:suite ")) (+ 1 (cd/mergeRedSuitesMax))) (str "at most mergeRedSuitesMax suites are carried: " (stringFromInt64 (- (listLength (stringSplit s "(:suite ")) 1))))
        (assert (= (moreOf r) 2) (str "the suites past the bound are counted: " (stringFromInt64 (moreOf r))))
        (assert (stringContains? s " :errCut ") "a suite whose error text passes the bound says how many bytes were cut")
        (refute (stringContains? s (str long long)) "no error text passes the bound")
        (assert (stringStartsWith? note "(:mergeRed :round 1 :of 2 :branch \"sh/M1\" :red ((:suite ") (str "the addendum shape: " (cd/utf8Clip note 160)))
        (assert (stringContains? note ":more 2 :must ") "the addendum carries the count of suites left out and the instruction")
        (assert (stringContains? note "every listed suite passes") "the instruction asks every listed suite to pass")
        (assert (stringContains? note "no assert may be removed, skipped or weakened") "the instruction forbids weakening asserts")
        true))

fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "mergeRedFixTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "gone" "" ""))

; (:m :do "the unit back in merging with a fresh lease, its signature and count kept, as after its gating and review passed again")
fn ! merging! dir: String id: String -> cd/CUnit
  (let [(epoch (match (st/claim! dir id "mergeRedFixTest" 600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0)))
        (c (with (cuOf dir id) :st "merging" :epoch epoch :launched 1))
        (_ (cd/writeCUnit! dir c))]
    c)

; (:m :do "one kept train attempt of the unit as keepTrain! writes it: the attempt row with the signature, then the train output")
fn ! attempt! dir: String id: String k: Int64 sig: String out: String -> Bool
  (let [(tdir (cd/trainsDir dir id))
        (_ (dirCreate (str dir "/trains")))
        (_ (dirCreate tdir))]
    (ok? (fileWrite (str tdir "/00000" (stringFromInt64 k) ".out")
                    (str "(:trainAttempt :unit " (st/q id) " :n " (stringFromInt64 k) " :branch " (st/q (str "sh/" id)) " :at 1 :exit 1 :ms 5 :verdict \"exit\" :sig " (st/q sig) ")\n" out))))

fn ! rowsOf dir: String head: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l head)) (pf/journalLines dir))

fn ! newestT dir: String id: String -> String
  (optionOr (listLast (rowsOf dir (str "(:t :unit " (st/q id) " "))) "")

fn red -> String
  "train red: s.asl"

; (:m :do "a red finish! of the unit's merge stage over the given train output, kept as attempt k")
fn ! redFinish! dir: String u: st/Task k: Int64 out: String -> cd/CUnit
  (let [(c (merging! dir u.id))
        (_ (attempt! dir u.id k (red) out))
        (_ (cd/finish! (ctxOf dir) u c (cd/batchRes "fail" (red) 0)))]
    (cuOf dir u.id))

fn ! testFlow root: String -> Bool
  (let [(repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (str store "/ladder.asn") "(:mergeRed :fixRounds 2)\n"))
        (u1 (pf/unitIn "M1" "true"))
        (w1 (pf/seedUnit! root u1 "merging" "impl.txt"))
        (m1a (redFinish! store u1 1 (redOut "s.asl" "sh/M1" "expected (1) got (2)")))
        (t1a (newestT store "M1"))
        (fix1 (rowsOf store "(:mergeRed :unit \"M1\" :action fixRound "))
        (note1 (cd/mergeRedNote! store "M1"))
        (lease1 (match (st/readLeases! store) ((ok ls) (listAny? (fn [(l st/Lease)] -> Bool (= l.id "M1")) ls)) ((err _) true)))
        (status1 (cd/status! (ctxOf store)))
        (redoWriter (cd/reviewFailedSinceWriter? store "M1"))
        (m1b (redFinish! store u1 2 (redOut "s.asl" "sh/M1" "expected (1) got (2)")))
        (t1b (newestT store "M1"))
        (esc1 (rowsOf store "(:mergeRed :unit \"M1\" :action escalate "))
        (note1Gone (not (fileExists? (cd/mergeRedPath store "M1"))))
        (u2 (pf/unitIn "M2" "true"))
        (w2 (pf/seedUnit! root u2 "merging" "impl2.txt"))
        (m2a (redFinish! store u2 1 (redOut "s.asl" "sh/M2" "first")))
        (m2b (redFinish! store u2 2 (redOut "s.asl" "sh/M2" "second")))
        (m2c (redFinish! store u2 3 (redOut "s.asl" "sh/M2" "third")))
        (t2c (newestT store "M2"))
        (esc2 (rowsOf store "(:mergeRed :unit \"M2\" :action escalate "))
        (before (cd/mergeRedHistory store "M2"))
        (_ (fileAppend (cd/journalPath store) "(:t :unit \"M2\" :from blocked :to queued :stage requeue :model \"\" :tokens 0 :costUsd 0 :verdict \"requeued\" :ms 0 :at 1)\n"))
        (after (cd/mergeRedHistory store "M2"))
        (u4 (pf/unitIn "M4" "true"))
        (w4 (pf/seedUnit! root u4 "merging" "impl4.txt"))
        (c4 (merging! store "M4"))
        (_ (attempt! store "M4" 1 "train red: old.asl" (redOut "s.asl" "sh/M4" "old")))
        (_ (cd/finish! (ctxOf store) u4 c4 (cd/batchRes "fail" (red) 0)))
        (m4 (cuOf store "M4"))
        (u5 (pf/unitIn "M5" "true"))
        (w5 (pf/seedUnit! root u5 "merging" "impl5.txt"))
        (m5 (redFinish! store u5 1 (str (live "s.asl" "e") "\n" (receipt (entry "s.asl" "sh/M5" "only" "e") (entry "b.asl" "base" "preexisting" "e") "") "\n")))
        (_ (fileWrite (str store "/ladder.asn") ""))
        (u3 (pf/unitIn "M3" "true"))
        (w3 (pf/seedUnit! root u3 "merging" "impl3.txt"))
        (m3 (redFinish! store u3 1 (redOut "s.asl" "sh/M3" "e")))
        (mr3 (rowsOf store "(:mergeRed :unit \"M3\" "))]
    (do (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? w1)) (and (not (stringEmpty? w2)) (and (not (stringEmpty? w3)) (and (not (stringEmpty? w4)) (not (stringEmpty? w5))))))) "fixture: repo and five unit branches")
        (assert (= m1a.st "ready") (str "a red of its own branch sends the unit back to the writing path: " m1a.st " " m1a.sig))
        (assert (and (= m1a.fails 0) (stringStartsWith? m1a.sig "mergeRedFix 1/2: train red: s.asl")) (str "with a clean count and the fix round in its signature: " (stringFromInt64 m1a.fails) " " m1a.sig))
        (assert (= m1a.branch "sh/M1") "on the same branch")
        (assert (and (stringContains? t1a ":from merging :to ready :stage mergeRed ") (stringContains? t1a ":verdict \"mergeRedFix 1/2: ")) (str "one transition row names the fix round: " t1a))
        (assert (and (= (listLength fix1) 1) (stringContains? (optionOr (listHead fix1) "") ":round 1 :of 2 ")) (str "one fixRound journal row: " (stringJoin fix1 " | ")))
        (assert (and (stringStartsWith? note1 "(:mergeRed :round 1 :of 2 :branch \"sh/M1\" ") (stringContains? note1 "expected (1) got (2)")) (str "the addendum carries the train's error text: " (cd/utf8Clip note1 200)))
        (refute lease1 "the lease is released for the writer's claim")
        (assert (stringContains? status1 "(:mergeRedFix (\"M1 1/2\"))") (str "status shows the unit in its fix round: " status1))
        (assert redoWriter "the ahead shortcut is closed: the writer runs on the addendum")
        (assert (= m1b.st "blocked") (str "the same red after a fix round escalates at once: " m1b.st))
        (assert (stringContains? t1b ":verdict \"escalated: mergeRed unchanged 1/2: train red: s.asl\"") (str "the verdict names the reason and the count: " t1b))
        (assert (and (= (listLength esc1) 1) (stringContains? (optionOr (listHead esc1) "") ":why unchanged ")) (str "one escalate row: " (stringJoin esc1 " | ")))
        (assert (= m1b.sig (red)) (str "the blocked unit carries the train signature: " m1b.sig))
        (assert note1Gone "a finished merge stage removes the addendum")
        (assert (and (= m2a.st "ready") (and (= m2b.st "ready") (stringStartsWith? m2b.sig "mergeRedFix 2/2: "))) (str "a changed red takes the next round: " m2a.st " " m2b.st " " m2b.sig))
        (assert (= m2c.st "blocked") (str "past the bound the unit escalates: " m2c.st " " m2c.sig))
        (assert (stringContains? t2c ":verdict \"escalated: mergeRed exhausted 2/2: ") (str "naming the exhausted count: " t2c))
        (assert (and (= (listLength esc2) 1) (stringContains? (optionOr (listHead esc2) "") ":why exhausted ")) (str "one escalate row: " (stringJoin esc2 " | ")))
        (assert (and (= (pairFirst before) 2) (and (= (pairFirst after) 0) (= (pairSecond after) ""))) (str "an operator requeue resets the rounds: " (stringFromInt64 (pairFirst before)) " " (stringFromInt64 (pairFirst after))))
        (assert (and (= m4.st "merging") (= m4.fails 1)) (str "a newest attempt with another signature is not read: the merge is retried as before: " m4.st " " (stringFromInt64 m4.fails)))
        (assert (and (= m5.st "merging") (= m5.fails 1)) (str "a red with the base red too is retried as before: " m5.st " " (stringFromInt64 m5.fails)))
        (assert (and (= m3.st "merging") (and (= m3.fails 1) (= m3.sig (red)))) (str "no mergeRed row: today's retry with a count: " m3.st " " (stringFromInt64 m3.fails) " " m3.sig))
        (assert (listEmpty? mr3) "and no mergeRed row in the journal")
        true))

; (:m :do "a batch leader's pass file: a red the batch gives to P2 alone sends P2 to its fix round, P1's rebatch stays a retry in merging with its count untouched")
fn ! testBatch root: String -> Bool
  (let [(repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (str store "/ladder.asn") "(:train :batch 2)\n(:mergeRed :fixRounds 1)\n"))
        (u1 (pf/unitIn "P1" "true")) (u2 (pf/unitIn "P2" "true"))
        (w1 (pf/seedUnit! root u1 "merging" "p1.txt"))
        (w2 (pf/seedUnit! root u2 "merging" "p2.txt"))
        (p1 (with (merging! store "P1") :launched 0))
        (p2 (with (merging! store "P2") :launched 0))
        (_ (cd/writeCUnit! store p1))
        (_ (cd/writeCUnit! store p2))
        (out (str (live "b.asl" "p2 broke it") "\n" (stringReplace (receipt (entry "b.asl" "sh/P2" "alone" "p2 broke it") "" "") "(\"sh/M1\")" "(\"sh/P1\" \"sh/P2\")") "\n"))
        (_ (attempt! store "P1" 1 (red) out))
        (_ (attempt! store "P2" 1 (red) out))
        (_ (dirCreate (cd/runsDir store)))
        (_ (fileWrite (cd/passPath store "L0") (str (cd/passRow "P1" p1.epoch (cd/batchRes "rebatch" (red) 1)) "\n" (cd/passRow "P2" p2.epoch (cd/batchRes "red" (red) 1)) "\n")))
        (applied (cd/applyPassengers! (ctxOf store) (pf/cuIn "L0" "merging" "" "")))
        (a1 (cuOf store "P1"))
        (a2 (cuOf store "P2"))]
    (do (assert (and (not (stringEmpty? w1)) (not (stringEmpty? w2))) "fixture: two unit branches")
        (assert (= applied 2) (str "both pass rows are applied: " (stringFromInt64 applied)))
        (assert (and (= a2.st "ready") (stringStartsWith? a2.sig "mergeRedFix 1/1: ")) (str "the branch the batch blamed alone goes to its writer: " a2.st " " a2.sig))
        (assert (stringContains? (cd/mergeRedNote! store "P2") "p2 broke it") "with its own suite's error text")
        (assert (and (= a1.st "merging") (= a1.fails 0)) (str "the rebatched member is retried untouched: " a1.st " " (stringFromInt64 a1.fails)))
        (refute (fileExists? (cd/mergeRedPath store "P1")) "and gets no addendum")
        true))

; (:m :do "the writer of a fix round is handed the addendum: the write stage with a fake Leon run records the task text; the unit's branch is ahead and its gate green, so only the fix-round row keeps the ahead shortcut from skipping the writer")
fn ! testBrief root: String -> Bool
  (let [(repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (str store "/ladder.asn") "(:mergeRed :fixRounds 1)\n"))
        (_ (fileWrite (str store "/tasks/B1.txt") "Build b1."))
        (u (with (pf/unitIn "B1" "true") :owns (list "b1.txt")))
        (w (pf/seedUnit! root u "merging" "b1.txt"))
        (c (redFinish! store u 1 (redOut "s.asl" "sh/B1" "expected (1) got (2)")))
        (rc (cd/realCfg (list "--repo" repo "--home" (str root "/home") "--worktrees" (str root "/wts")) store))
        (seen (str root "/seenTask"))
        (run (fn [(rcx cd/RealCfg) (lane String) (id String) (prof String) (p String) (task String) (owns (List String)) (gates (List String)) (extra String)] -> fr/Done
               (let [(_ (fileWrite seen task))] (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "exit"))))
        (res (cd/writeResWith run rc store u c))
        (task (resultOr (fileReadString seen) "NOTASK"))]
    (do (assert (and (not (stringEmpty? w)) (= c.st "ready")) (str "fixture: a unit sent to its fix round: " c.st))
        (assert (stringContains? task "Build b1.") (str "the writer runs on the stored task: " (cd/utf8Clip task 300) " / " res.sig))
        (assert (stringContains? task "(:mergeRed :round 1 :of 1 :branch \"sh/B1\" :red ((:suite \"s.asl\" :exit 1 :asserts 7 ") (str "followed by the addendum: " (cd/utf8Clip task 600)))
        (assert (stringContains? task "ERR_ASSERT: expected (1) got (2)") "with the train's error text")
        (assert (stringContains? task "no assert may be removed, skipped or weakened") "and the instruction")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "mergeRedFix" "w"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (rows (testRows (str root "/rows")))
        (flow (testFlow (str root "/flow")))
        (batch (testBatch (str root "/batch")))
        (brief (testBrief (str root "/brief")))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert rows "the mergeRed ladder row")
        (assert (testAttribution) "which train reds are the writer's")
        (assert (testBounds) "the addendum bounds and shape")
        (assert flow "the finish! transitions")
        (assert batch "batch passengers")
        (assert brief "the writer's brief")
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
