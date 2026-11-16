(module asl-tools/coord/tests/trainLimitTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref TRAIN-LIMIT-ESTIMATE :do "the merge stage's train limit is a (:train ...) key: :limitS caps it (default 3600, today's), :limitFactorPct and :limitFloorS derive it from the (:trainEstimate :tier (:estimateS N ...)) line of the unit's newest kept attempt; no line, no factor or no row is the cap; the store is a scratch dir under this worktree's .asl/cache")

fn estimateLine s: Int64 -> String
  (str "(:trainEstimate :tier (:estimateS " (stringFromInt64 s) " :heavyS 120 :deadlineFactorPct 200 :deadlineFloorS 300 :unknownS 30 :split false :light (:n 3 :estimateS " (stringFromInt64 s) " :deadlineS 600) :heavy (:n 0 :estimateS 0 :deadlineS 0) :unrecorded 0))")

fn ! runTests -> Bool
  (let [(root (pf/scratch "trainLimit" "w"))
        (_ (pf/cleanup root))
        (store (str root "/store"))
        (_ (dirCreate root))
        (_ (dirCreate store))
        (_ (dirCreate (str store "/trains")))
        (tdir (cd/trainsDir store "T1"))
        (_ (dirCreate tdir))
        (_ (fileWrite (str tdir "/000001.out") (str "(:trainAttempt :unit \"T1\" :n 1 :at 1 :exit 1 :ms 5 :verdict \"exit\" :sig \"x\")\n" (estimateLine 9000) "\n")))
        (_ (fileWrite (str tdir "/000002.out") (str "(:trainAttempt :unit \"T1\" :n 2 :at 2 :exit 1 :ms 5 :verdict \"exit\" :sig \"x\")\n(:trainRunning :items (\"a.asl\"))\n  " (estimateLine 1500) "\n")))
        (none0 (cd/trainLimitFor! store "T1"))
        (_ (fileWrite (str store "/ladder.asn") "(:train :jobs 4 :limitS 5000 :limitFactorPct 200 :limitFloorS 900)\n"))
        (derived (cd/trainLimitFor! store "T1"))
        (noAttempt (cd/trainLimitFor! store "T9"))
        (_ (fileWrite (str store "/ladder.asn") "(:train :limitS 4000)\n"))
        (capOnly (cd/trainLimitFor! store "T1"))
        (problems (cd/ladderProblems store))
        (_ (pf/cleanup root))]
    (do (assert (= none0 3600) (str "no train row: the limit is today's 3600 s: " (stringFromInt64 none0)))
        (assert (= derived 3000) (str "factor 200 percent of the newest attempt's estimate 1500 s: " (stringFromInt64 derived)))
        (assert (= noAttempt 5000) (str "no estimate: the cap: " (stringFromInt64 noAttempt)))
        (assert (= capOnly 4000) (str "a cap alone sets the limit: " (stringFromInt64 capOnly)))
        (assert (listEmpty? problems) (str "a limit key alone is a valid train row: " (stringJoin problems "; ")))
        (assert (= (cd/trainLimitOf "(:train :limitS 5000 :limitFactorPct 150 :limitFloorS 900)" 100) 900) "a small estimate is raised to the floor")
        (assert (= (cd/trainLimitOf "(:train :limitS 5000 :limitFactorPct 150 :limitFloorS 900)" 9000) 5000) "a large one is held at the cap")
        (assert (= (cd/trainLimitOf "(:train :limitS 5000 :limitFactorPct 150)" -1) 5000) "an absent estimate is the cap")
        (assert (= (cd/trainLimitOf "(:train :limitS 50)" 1000) 3600) "a rejected row is today's limit")
        (assert (= (cd/estimateSOf (estimateLine 777)) 777) "the estimate is the first :estimateS of the line")
        (assert (= (cd/estimateSOf "(:train :head \"a\")") -1) "an output without the line has none")
        (assert (not (listEmpty? (cd/trainErrors "(:train :limitFactorPct 50)"))) "a factor under 100 percent is rejected")
        true))
