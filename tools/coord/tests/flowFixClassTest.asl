(module asl-tools/coord/tests/flowFixClassTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref FLOW-FIX-CLASS-NARROW :do "with (:flow ... :fixClass owed) the fix class is the units owed a fix round in their current life (a review fail or a mergeRed round, until their write passes to gating or an operator requeue), not every ready unit with a branch, and a class holds new units only for work that can use a slot now (a fix unit the writer admission refuses holds nothing); without the key both rules are today's; stores are scratch dirs under this worktree's .asl/cache")

fn ctxFor dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "flowFixClassTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuNow dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" ""))

fn ! unit! dir: String id: String c: cd/CUnit -> st/Task
  (let [(u (pf/unitIn id "true"))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir c))]
    u)

fn flowRow -> String
  "(:flow :order (merge gate review fix new) :newWhen idle :fixClass owed)"

fn ! runTests -> Bool
  (let [(root (pf/scratch "flowFixClass" "w"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (_ (dirCreate (str dir "/tasks")))
        (ctx (ctxFor dir))
        (meminfo (str root "/meminfo"))
        (_ (fileWrite meminfo "MemTotal: 16000000 kB\nMemAvailable: 1000 kB\n"))
        (held (str "(:writers :minFreeMb 500000 :warmFirst false :meminfo \"" meminfo "\")"))
        (f1 (with (pf/cuIn "F1" "ready" "" "sh/F1") :sig "gates: exit 1"))
        (f2 (with (pf/cuIn "F2" "ready" "" "sh/F2") :owed 1))
        (m3 (with (pf/cuIn "M3" "ready" "" "sh/M3") :sig "mergeRedFix 1/2: train red: a.asl"))
        (n1 (pf/cuIn "N1" "ready" "" ""))
        (u1 (unit! dir "F1" f1))
        (u2 (unit! dir "F2" f2))
        (u3 (unit! dir "N1" n1))
        (units (list u1 u2 u3))
        (cus (cd/readCUnits! dir))
        (_ (fileWrite (str dir "/ladder.asn") (str "(:flow :order (merge gate review fix new) :newWhen idle)\n" held "\n")))
        (oldHeld (cd/flowHeldIn ctx cus cus "fix"))
        (_ (cd/flowStep! ctx units (cd/flowRowOf dir)))
        (oldNote (fileExists? (cd/flowHeldPath dir)))
        (_ (pathRemove (cd/flowHeldPath dir)))
        (_ (fileWrite (str dir "/ladder.asn") (str (flowRow) "\n" held "\n")))
        (problems (cd/ladderProblems dir))
        (narrowHeld (cd/flowHeldBy ctx cus cus "fix" true))
        (_ (cd/flowStep! ctx units (cd/flowRowOf dir)))
        (newNote (fileExists? (cd/flowHeldPath dir)))
        (_ (fileWrite (str dir "/ladder.asn") (str (flowRow) "\n")))
        (freeHeld (cd/flowHeldBy ctx cus cus "fix" true))
        (_ (fileWrite (str dir "/ladder.asn") ""))
        (r5 (cd/fail! ctx (with (pf/cuIn "R5" "reviewing" "" "sh/R5") :epoch 0) "review" "" "review: fail: missing test" 0))
        (q5 (cd/cleaned r5 "free"))
        (repo (pf/repoIn root))
        (_ (fileWrite (cd/repoPath dir) repo))
        (u6 (pf/unitIn "W6" "true"))
        (wt6 (pf/seedUnit! root u6 "writing" "w6.txt"))
        (_ (cd/writeCUnit! dir (with (cuNow dir "W6") :owed 1 :launched 1)))
        (_ (cd/finish! ctx u6 (cuNow dir "W6") (cd/Res :ok 1 :wt wt6 :branch "sh/W6" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "" :ms 0 :exit 0 :asserts 0 :verdict "" :tiers "")))
        (g6 (cuNow dir "W6"))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (listEmpty? problems) (str "the key is a valid flow row: " (stringJoin problems "; ")))
        (assert (not (listEmpty? (cd/flowErrors "(:flow :fixClass some)"))) "another fixClass value is an error")
        (assert (= (cd/flowClass f1) "fix") "without the key a ready unit with a branch is a fix unit, as today")
        (assert (= (cd/flowClassOf true f1) "new") "with it a branch alone is not an owed fix round")
        (assert (= (cd/flowClassOf true f2) "fix") "a unit owed a fix round is one")
        (assert (= (cd/flowClassOf true m3) "fix") "so is a unit in a mergeRed round")
        (assert (= (cd/flowClassOf true n1) "new") "a unit with no branch stays new")
        (assert (and (listContains? oldHeld "F1") (listContains? oldHeld "F2")) (str "without the key every ready unit with a branch holds new units: " (stringJoin oldHeld ",")))
        (assert oldNote "and the idle flow writes the hold")
        (assert (listEmpty? narrowHeld) (str "with it a fix unit the writer admission refuses holds nothing: " (stringJoin narrowHeld ",")))
        (refute newNote "so no hold is written while no class can use a slot")
        (assert (= freeHeld (list "F2")) (str "with admission open only the owed unit holds: " (stringJoin freeHeld ",")))
        (assert (and (= r5.st "ready") (= r5.owed 1)) (str "a review fail owes the unit its fix round: " r5.st " " (stringFromInt64 r5.owed)))
        (assert (= q5.owed 0) "an operator requeue clears it")
        (assert (and (not (stringEmpty? wt6)) (and (= g6.st "gating") (= g6.owed 0))) (str "a write that reaches gating has paid it: " g6.st " " (stringFromInt64 g6.owed)))
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
