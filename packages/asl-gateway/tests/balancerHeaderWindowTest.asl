(module aslGateway/tests/balancerHeaderWindowTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl) (asl-parser/reader :a rd)])

; (:m :ref GW-BALANCER-HEADER-WINDOW :do "one model on a header-sourced daily request budget of 100; the budget declares no header window, a daily one or a per-minute one, and the OpenAI-shaped headers report a reset 30 seconds or 6 hours away")

fn dayMs -> Int64 86400000

fn noon -> Int64 43200000

fn budget headerWindowMs: Int64 -> bl/Budget
  (bl/Budget :id "aDay" :windowMs (dayMs) :anchorMs 0 :headerWindowMs headerWindowMs :unit "req" :size 100 :softPct 100 :hardPct 100 :useOrLose true :source "header")

fn pool headerWindowMs: Int64 -> bl/Pool
  (bl/poolFromParts
    (bl/makeBalancer (list (bl/PoolModel :id "mA" :provider "pa" :tier (bl/tierFree) :why "fixture" :budgets (list "aDay") :costMicros 0 :declaredQuality (none)))
                     (list (budget headerWindowMs))
                     (list)
                     (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))
    (bl/emptyUse)
    (mapFromPairs (list (pair "mA" (pair "pa" "model-a")))))

fn headers remaining: Int64 reset: String -> (List (Pair String String))
  (list (pair "x-ratelimit-remaining-requests" (stringFromInt64 remaining)) (pair "x-ratelimit-reset-requests" reset))

fn usedAfter headerWindowMs: Int64 remaining: Int64 reset: String atMs: Int64 -> Int64
  (let [(seen (bl/poolObserve (pool headerWindowMs) "mA" 200 (headers remaining reset) (noon)))]
    (bl/budgetUsed (bl/effectiveUse seen atMs) (budget headerWindowMs) atMs))

fn testUndeclared -> Bool
  (do
    (assert (= (usedAfter 0 40 "30s" (noon)) 60) "with no header window a header remaining of 40 reads as 60 of 100 used, as before")
    (assert (= (usedAfter 0 40 "6h" (noon)) 60) "whatever its reset")
    true)

fn testSameWindow -> Bool
  (do
    (assert (= (usedAfter (dayMs) 40 "6h" (noon)) 60) "a daily header window on a daily budget applies a reset 6 hours away")
    (assert (= (usedAfter (dayMs) 40 "30s" (noon)) 60) "and one 30 seconds away")
    true)

fn testShorterWindow -> Bool
  (do
    (assert (= (usedAfter 60000 40 "30s" (noon)) 0) "a per-minute header with room says nothing about the daily budget")
    (assert (= (usedAfter 60000 0 "30s" (noon)) 100) "a per-minute header at zero holds the daily budget at its hard cap")
    (assert (= (usedAfter 60000 0 "30s" (+ (noon) 31000)) 0) "until that minute resets")
    (assert (= (usedAfter 60000 0 "6h" (noon)) 0) "a reset 6 hours away is beyond a minute window, so that header counts another window and is ignored")
    (assert (= (usedAfter 60000 5 "6h" (noon)) 0) "with room as well")
    true)

fn parsed headerWindow: String -> (Result bl/Balancer String)
  (bl/parseBalancer
    (rd/parseSexpr (str "(:gateway :v 2 :models () :balancer (:balancer :budgets ((:budget :id aDay :window day :unit req :size 100 :source header" headerWindow "))))"))
    (list))

fn testParse -> Bool
  (do
    (assert (match (parsed " :headerWindow minute") ((ok b) (match (mapGet b.budgets "aDay") ((some x) (= x.headerWindowMs 60000)) ((none) false))) ((err _) false)) "a :headerWindow minute row is 60000 ms")
    (assert (match (parsed "") ((ok b) (match (mapGet b.budgets "aDay") ((some x) (= x.headerWindowMs 0)) ((none) false))) ((err _) false)) "a row without one is 0")
    (assert (match (parsed " :headerWindow fortnight") ((err e) (stringContains? e "unknown window fortnight in budget aDay :headerWindow")) ((ok _) false)) "an unknown header window is an error naming the budget")
    true)

fn runTests -> Bool
  (do
    (assert (testUndeclared) "undeclared")
    (assert (testSameWindow) "same window")
    (assert (testShorterWindow) "shorter window")
    (assert (testParse) "parse")
    true)
