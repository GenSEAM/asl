(module asl-tools/coord/tests/writerNiceTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref TRAIN-PRIORITY-CPU :do "(:train :writerNice K) starts every write stage child under nice -n K, so a writer's whole tree yields the CPU to the merge train, whose stage child is not niced; no key starts it as today; the argv is read from stageArgv!, the one launchNow! spawns, because this test already runs at the highest niceness the host allows, so a child's measured niceness could not differ; the store is a scratch dir under this worktree's .asl/cache")

fn ctxFor dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "writerNiceTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/bin/echo" stage u.id))
          :pace (cd/fixedPace 8 8))

fn ! runTests -> Bool
  (let [(root (pf/scratch "writerNice" "w"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (ctx (ctxFor dir))
        (u (pf/unitIn "W1" "true"))
        (c (pf/cuIn "W1" "writing" "" ""))
        (plain (cd/stageArgv! ctx "write" u c))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :jobs 2 :writerNice 7)\n"))
        (niced (cd/stageArgv! ctx "write" u c))
        (merge (cd/stageArgv! ctx "merge" u c))
        (gates (cd/stageArgv! ctx "gates" u c))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :writerNice 20)\n"))
        (rejected (cd/stageArgv! ctx "write" u c))
        (_ (pf/cleanup root))]
    (do (assert (= plain (list "/bin/echo" "write" "W1")) (str "no key: the write child argv is the launcher's: " (stringJoin plain " ")))
        (assert (= niced (list "nice" "-n" "7" "/bin/echo" "write" "W1")) (str "writerNice 7: the write child starts under nice -n 7: " (stringJoin niced " ")))
        (assert (= merge (list "/bin/echo" "merge" "W1")) (str "the merge stage is never niced: " (stringJoin merge " ")))
        (assert (= gates (list "/bin/echo" "gates" "W1")) "nor the gates stage")
        (assert (= rejected (list "/bin/echo" "write" "W1")) "a rejected row nices nothing")
        (assert (listEmpty? (cd/trainErrors "(:train :writerNice 7)")) "a writerNice key alone is a valid train row")
        (assert (not (listEmpty? (cd/trainErrors "(:train :writerNice 20)"))) "a niceness past 19 is rejected")
        true))
