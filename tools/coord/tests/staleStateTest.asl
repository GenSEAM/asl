(module asl-tools/coord/tests/staleStateTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf) (asl-tools/vcs/vcs :a v)])

; (:m :ref COND-STALE-STATE :do "a done row goes to merged when its branch is on main or, with no branch, its commit is on main by id, to ready when the branch exists and is not on main, and stays done with :await lead when neither exists; a dead stage run file no in-flight stage owns is removed and the unit keeps its state, a launched-0 merging unit included; an in-flight stage keeps its run file for poll")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "staleStateTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! stateOf store: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! store)) ((some c) c.st) ((none) "none"))

fn ! awaitOf store: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! store)) ((some c) c.await) ((none) "none"))

fn ! deadRun store: String id: String stage: String -> Bool
  (ok? (fileWrite (cd/runPath store id stage "run") "(:run :pid 2147483000 :deadlineMs 1)\n"))

fn ! bare store: String id: String stateName: String -> Bool
  (ok? (cd/writeCUnit! store (pf/cuIn id stateName "" (str "sh/" id))))

fn ! runTests -> Bool
  (let [(root (pf/scratch "staleState" "s"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (cd/worktreesPath store) (str root "/wts")))
        (ctx (ctxOf store))
        (_ (dirCreate (cd/runsDir store)))
        (wD1 (pf/seedUnit! root (pf/unitIn "D1" "g") "done" ""))
        (wD2 (pf/seedUnit! root (pf/unitIn "D2" "g") "done" "impl.txt"))
        (_ (fileWrite (str repo "/d3.txt") "d3\n"))
        (cm (v/commit! repo repo (list "d3.txt") "(:c :a t :do \"unit work\" :g none :ev (D3))" "warn"))
        (_ (fileWrite (str repo "/d5.txt") "d5\n"))
        (cm5 (v/commit! repo repo (list "d5.txt") "(:c :a t :do \"other\" :g none :ev (D5-LONGER))" "warn"))
        (okD (and (bare store "D3" "done") (and (bare store "D4" "done") (bare store "D5" "done"))))
        (wS1 (pf/seedUnit! root (pf/unitIn "S1" "g") "gating" ""))
        (wS2 (pf/seedUnit! root (pf/unitIn "S2" "g") "ready" ""))
        (wM1 (pf/seedUnit! root (pf/unitIn "M1" "g") "merging" ""))
        (flying (with (pf/cuIn "F1" "gating" wS1 "sh/F1") :launched 1))
        (_ (st/put! store (pf/unitIn "F1" "g")))
        (_ (cd/writeCUnit! store flying))
        (r1 (deadRun store "S1" "gates"))
        (r2 (deadRun store "S2" "write"))
        (r3 (deadRun store "F1" "gates"))
        (r4 (deadRun store "M1" "review"))
        (n (cd/staleStateSweep! ctx))
        (d1 (stateOf store "D1"))
        (d2 (stateOf store "D2"))
        (d3 (stateOf store "D3"))
        (d4 (stateOf store "D4"))
        (d5 (stateOf store "D5"))
        (a4 (awaitOf store "D4"))
        (s1 (stateOf store "S1"))
        (s2 (stateOf store "S2"))
        (m1 (stateOf store "M1"))
        (f1 (stateOf store "F1"))
        (goneS1 (not (fileExists? (cd/runPath store "S1" "gates" "run"))))
        (goneS2 (not (fileExists? (cd/runPath store "S2" "write" "run"))))
        (goneM1 (not (fileExists? (cd/runPath store "M1" "review" "run"))))
        (keptF1 (fileExists? (cd/runPath store "F1" "gates" "run")))
        (n2 (cd/staleStateSweep! ctx))
        (_ (pf/cleanup root))]
    (do (assert (and r1 r2 r3 r4 okD (= cm.code 0) (= cm5.code 0) (not (stringEmpty? wD1)) (not (stringEmpty? wD2)) (not (stringEmpty? wM1)) (not (stringEmpty? wS2))) "fixture")
        (assert (= d1 "merged") (str "done with its branch on main goes to merged: " d1))
        (assert (= d2 "ready") (str "done with a branch not on main goes to ready: " d2))
        (assert (= d3 "merged") (str "done with no branch and its commit on main goes to merged: " d3))
        (assert (and (= d4 "done") (= a4 "lead")) (str "done with no branch and no commit stays done, await lead, never ready: " d4 " " a4))
        (assert (= d5 "done") (str "a commit naming a longer id does not count as the unit's commit: " d5))
        (assert (and (= m1 "merging") goneM1) (str "a launched-0 merging unit keeps its state and loses the dead review run file: " m1))
        (assert (and (= s1 "gating") goneS1) (str "a launched-0 gating unit keeps its state, the dead file goes: " s1))
        (assert (and (= s2 "ready") goneS2) "a ready unit loses its dead run file")
        (assert (and (= f1 "gating") keptF1) "an in-flight stage keeps its run file for poll")
        (assert (= n 8) (str "eight changes: " (stringFromInt64 n)))
        (assert (= n2 0) (str "a second sweep changes nothing: " (stringFromInt64 n2)))
        true))
