(module aslGateway/tests/balancerStatusPollTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl) (aslGateway/config :a cfg)])

; (:m :ref GW-BALANCER-STATUS-POLL :do "two endpoint usd budgets polled from an OpenRouter-shaped and a Vercel-shaped provider row, plus a polled budget no model draws on; bodies are fixtures, nothing is sent")

fn scratchDir -> String
  "/tmp/balancerStatusPollTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn config budgets: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id orx :kind openai :base \"https://openrouter.ai/api/v1/\" :keyEnv ORX_KEY)"
       " (:provider :id vcl :kind openai :base \"https://ai-gateway.vercel.sh/v1\" :keyEnv VCL_KEY))"
       " :models ((:model :id mO :provider orx :name \"m-o\" :tier paid :budgets (orUsd) :costMicros 100)"
       " (:model :id mV :provider vcl :name \"m-v\" :tier paid :budgets (vUsd) :costMicros 100))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mO)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\""
       " :budgets (" budgets ")))\n")

fn goodBudgets -> String
  (str "(:budget :id orUsd :window month :unit usd :size 10000000 :source endpoint :poll (:poll :provider orx :path \"/key\" :everyMs 120000))"
       " (:budget :id vUsd :window month :unit usd :size 100000000 :source endpoint :poll (:poll :provider vcl :path \"/credits\" :everyMs 1000))"
       " (:budget :id xUsd :window month :unit usd :size 5 :source endpoint :poll (:poll :provider orx :path \"/credits\"))")

fn ! poolOf text: String -> (Result bl/Pool String)
  (match (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok text) "")
    ((err e) (err e))
    ((ok table)
      (match (bl/loadPool! text (some table) "" (fn [(pid String)] -> Bool (or (= pid "orx") (= pid "vcl"))))
        ((err e) (err e))
        ((ok (none)) (err "no pool"))
        ((ok (some p)) (ok p)))))

fn dueIds pool: bl/Pool nowMs: Int64 -> String
  (stringJoin (map (fn [(p bl/Poll)] -> String p.budget) (bl/pollsDue pool nowMs)) " ")

fn pollFor pool: bl/Pool id: String -> (Option bl/Poll)
  (listFind (fn [(p bl/Poll)] -> Bool (= p.budget id)) pool.polls)

fn usedOf pool: bl/Pool id: String nowMs: Int64 -> Int64
  (match (mapGet pool.bal.budgets id)
    ((some b) (bl/budgetUsed (bl/effectiveUse pool nowMs) b nowMs))
    ((none) -1))

fn ! testSchedule now: Int64 -> Bool
  (match (poolOf (config (goodBudgets)))
    ((err e) (do (assert false (str "polled pool loads: " e)) false))
    ((ok pool)
      (let [(sent (bl/poolPolled pool "orUsd" now))]
        (do
          (assert (match (pollFor pool "orUsd") ((some p) (and (= p.url "https://openrouter.ai/api/v1/key") (= p.provider "orx") (= p.everyMs 120000))) ((none) false))
                  "the OpenRouter poll url is the provider base without its trailing slash plus the path")
          (assert (match (pollFor pool "vUsd") ((some p) (and (= p.url "https://ai-gateway.vercel.sh/v1/credits") (= p.everyMs 60000))) ((none) false))
                  "an everyMs under a minute is raised to one poll a minute")
          (assert (= (dueIds pool now) "orUsd vUsd") (str "both budgets a model draws on are due before any poll, the orphan xUsd is not: " (dueIds pool now)))
          (assert (= (dueIds sent (+ now 1000)) "vUsd") (str "a poll just sent is not due again: " (dueIds sent (+ now 1000))))
          (assert (= (dueIds sent (+ now 120000)) "orUsd vUsd") "after everyMs the budget is due again")
          true))))

fn ! testReplies now: Int64 -> Bool
  (match (poolOf (config (goodBudgets)))
    ((err e) (do (assert false (str "polled pool loads: " e)) false))
    ((ok pool)
      (let [(or1 (bl/poolPollReply (bl/poolPolled pool "orUsd" now) "orUsd" 200 "{\"data\":{\"label\":\"k\",\"limit\":10,\"limit_remaining\":2.5}}" now))
            (vc1 (bl/poolPollReply (pairFirst or1) "vUsd" 200 "{\"balance\":\"95.50\",\"total_used\":\"4.50\"}" now))
            (limited (bl/poolPollReply (pairFirst vc1) "orUsd" 429 "" (+ now 10)))
            (broken (bl/poolPollReply (pairFirst vc1) "vUsd" 500 "oops" (+ now 10)))
            (empty (bl/poolPollReply pool "vUsd" 200 "{}" now))]
        (do
          (assert (= (pairSecond or1) "") (str "an OpenRouter /key reply refreshes the budget: " (pairSecond or1)))
          (assert (= (usedOf (pairFirst or1) "orUsd" now) 7500000) "limit_remaining 2.5 USD of a 10 USD budget reads as 7.5 USD used")
          (assert (= (pairSecond vc1) "") (str "a Vercel /credits reply refreshes the budget: " (pairSecond vc1)))
          (assert (= (usedOf (pairFirst vc1) "vUsd" now) 4500000) "a balance of \"95.50\" USD of a 100 USD budget reads as 4.5 USD used")
          (assert (stringContains? (pairSecond limited) "rate limited") (str "a 429 says the poll was rate limited: " (pairSecond limited)))
          (assert (not (stringContains? (dueIds (pairFirst limited) (+ now 10 360000)) "orUsd")) "after a 429 the budget is not polled at three intervals")
          (assert (stringContains? (dueIds (pairFirst limited) (+ now 10 480000)) "orUsd") "it is polled again after four intervals")
          (assert (stringContains? (pairSecond broken) "answered 500") (str "another status keeps the last observation and says why: " (pairSecond broken)))
          (assert (= (usedOf (pairFirst broken) "vUsd" now) 4500000) "the last observation still holds after a 500")
          (assert (not (stringEmpty? (pairSecond empty))) "a body of neither shape is an error, not a zero")
          (assert (= (usedOf (pairFirst empty) "vUsd" now) 0) "and it observes nothing")
          (assert (not (stringContains? (dueIds (pairFirst empty) (+ now 1)) "vUsd")) "a failed reply still counts as a poll, so a bad endpoint is not hammered")
          true))))

fn ! testBadPolls -> Bool
  (let [(reqBudget (poolOf (config "(:budget :id orUsd :window month :unit req :size 10 :poll (:poll :provider orx :path \"/key\")) (:budget :id vUsd :window month :unit usd :size 1 :source endpoint)")))
        (noProvider (poolOf (config "(:budget :id orUsd :window month :unit usd :size 10 :source endpoint :poll (:poll :provider nobody :path \"/key\")) (:budget :id vUsd :window month :unit usd :size 1 :source endpoint)")))
        (noSlash (poolOf (config "(:budget :id orUsd :window month :unit usd :size 10 :source endpoint :poll (:poll :provider orx :path \"key\")) (:budget :id vUsd :window month :unit usd :size 1 :source endpoint)")))]
    (do
      (assert (match reqBudget ((err e) (stringContains? e "needs :source endpoint :unit usd")) ((ok _) false)) "a poll on a request budget is refused")
      (assert (match noProvider ((err e) (stringContains? e "polls provider nobody, which is no gateway provider")) ((ok _) false)) "a poll through an unknown provider is refused")
      (assert (match noSlash ((err e) (stringContains? e ":path must start with /")) ((ok _) false)) "a poll path without a leading slash is refused")
      true))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))
        (wrote (fileWrite (ledgerPath) ""))
        (now 1000000)]
    (do
      (assert (and (ok? made) (ok? wrote)) "the scratch ledger exists and is empty")
      (assert (testSchedule now) "schedule")
      (assert (testReplies now) "replies")
      (assert (testBadPolls) "bad polls")
      (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
      true))
