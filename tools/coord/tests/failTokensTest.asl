(module asl-tools/coord/tests/failTokensTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref ACCT-FAIL-TOKENS :do "a failed write journals the receipt's tokens and cost on its :t row, not 0 0, and leonTokens counts input plus output whatever the cached part is")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "failTokensTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! runTests -> Bool
  (let [(root (pf/scratch "failTokens" "t"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (store (str root "/store"))
        (u (pf/unitIn "T1" "g"))
        (wt (pf/seedUnit! root u "writing" "impl.txt"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (cd/worktreesPath store) (str root "/wts")))
        (ctx (ctxOf store))
        (epoch (match (st/claim! store "T1" "failTokensTest" 600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0)))
        (cw (with (pf/cuIn "T1" "writing" wt "sh/T1") :epoch epoch :launched 1))
        (_ (cd/writeCUnit! store cw))
        (out "(:agentReceipt :usage (:input 1000 :cached 600 :output 50))")
        (res (cd/Res :tiers "" :ok 0 :wt wt :branch "sh/T1" :model "m" :tokens (cd/leonTokens out) :costMicro 7 :claimedGreen 0 :sig "provider said no" :ms 5 :exit 1 :asserts 0 :verdict ""))
        (_ (cd/finish! ctx u cw res))
        (journal (resultOr (fileReadString (cd/journalPath store)) ""))
        (row (optionOr (listLast (filter (fn [(l String)] -> Bool (and (stringContains? l ":unit \"T1\"") (stringContains? l ":stage write"))) (stringLines journal))) ""))
        (_ (pf/cleanup root))
        (_ (fr/stubRemove!))]
    (do (assert (= (cd/leonTokens out) 1050) "leonTokens is input plus output")
        (assert (stringContains? row ":tokens 1050") (str "the failed write row carries the receipt tokens: " row))
        (assert (and (stringContains? row (str ":costUsd " (cd/costText 7))) (!= (cd/costText 7) (cd/costText 0))) (str "the row carries the receipt cost, not the zero cost: " row))
        true))
