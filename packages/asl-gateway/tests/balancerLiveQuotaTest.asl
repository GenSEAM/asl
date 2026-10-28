(module aslGateway/tests/balancerLiveQuotaTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl)])

fn dayMs -> Int64 86400000

fn noon -> Int64 43200000

fn budget id: String unit: String size: Int64 source: String -> bl/Budget
  (bl/Budget :id id :windowMs (dayMs) :anchorMs 0 :headerWindowMs 0 :unit unit :size size :softPct 100 :hardPct 100 :useOrLose true :source source)

fn model id: String budgets: (List String) -> bl/PoolModel
  (bl/PoolModel :id id :provider id :tier (bl/tierFree) :why "fixture" :budgets budgets :costMicros 0 :declaredQuality (none))

fn cal id: String pass: Int64 -> bl/CalScore
  (bl/CalScore :model id :intent "any" :pass pass :total 10 :source "cal:fixture")

; (:m :do "mA is stronger and draws on a header-sourced daily request quota, mB on a ledger-sourced one, orPaid on an endpoint-sourced usd budget that the status poll fills")
fn pool -> bl/Pool
  (bl/poolFromParts
    (bl/makeBalancer (list (model "mA" (list "aDay")) (model "mB" (list "bDay")))
                     (list (budget "aDay" "req" 100 "header") (budget "bDay" "req" 100 "ledger") (budget "orUsd" "usd" 1000000 "endpoint"))
                     (list (cal "mA" 9) (cal "mB" 6))
                     (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))
    (bl/emptyUse)
    (mapFromPairs (list (pair "mA" (pair "pa" "model-a")) (pair "mB" (pair "pb" "model-b")))))

fn req atMs: Int64 -> bl/Request
  (bl/Request :seq 1 :atMs atMs :intent "code" :tokens 10)

fn pickAt p: bl/Pool atMs: Int64 -> String
  (match (bl/poolPick p (req atMs)) ((bl/picked m _ _ _) m) ((bl/refused _) ""))

fn usedOf p: bl/Pool id: String unit: String size: Int64 source: String atMs: Int64 -> Int64
  (bl/budgetUsed (bl/effectiveUse p atMs) (budget id unit size source) atMs)

fn obsOf obs: (List bl/RateObs) unit: String -> (Option bl/RateObs)
  (listFind (fn [(o bl/RateObs)] -> Bool (= o.unit unit)) obs)

fn openaiHeaders -> (List (Pair String String))
  (list (pair "X-RateLimit-Limit-Requests" "60") (pair "X-RateLimit-Remaining-Requests" "59") (pair "X-RateLimit-Reset-Requests" "6m0s")
        (pair "x-ratelimit-limit-tokens" "150000") (pair "x-ratelimit-remaining-tokens" "149984") (pair "x-ratelimit-reset-tokens" "6ms"))

fn groqHeaders -> (List (Pair String String))
  (list (pair "x-ratelimit-limit-requests" "14400") (pair "x-ratelimit-remaining-requests" "14370") (pair "x-ratelimit-reset-requests" "2m59.56s")
        (pair "x-ratelimit-limit-tokens" "6000") (pair "x-ratelimit-remaining-tokens" "5900") (pair "x-ratelimit-reset-tokens" "7.66s"))

fn anthropicHeaders -> (List (Pair String String))
  (list (pair "anthropic-ratelimit-requests-limit" "50") (pair "anthropic-ratelimit-requests-remaining" "49") (pair "anthropic-ratelimit-requests-reset" "2026-10-27T12:00:30Z")
        (pair "anthropic-ratelimit-tokens-remaining" "39000") (pair "anthropic-ratelimit-tokens-reset" "2026-10-27T12:00:30.500Z"))

fn testDurationsAndTimes -> Bool
  (do
    (assert (= (bl/parseDurationMs "1s") (some 1000)) "1s")
    (assert (= (bl/parseDurationMs "6m0s") (some 360000)) "6m0s")
    (assert (= (bl/parseDurationMs "2m59.56s") (some 179560)) "2m59.56s")
    (assert (= (bl/parseDurationMs "120ms") (some 120)) "120ms")
    (assert (= (bl/parseDurationMs "1h2m3s") (some 3723000)) "1h2m3s")
    (assert (= (bl/parseDurationMs "20") (some 20000)) "a bare number is seconds")
    (assert (none? (bl/parseDurationMs "soon")) "an unreadable duration is none")
    (assert (= (bl/parseRfc3339Ms "2026-10-27T12:00:30Z") (some 1793102430000)) "an RFC 3339 UTC time is epoch ms (2026-10-27T12:00:30Z = 1793102430 s)")
    (assert (= (bl/parseRfc3339Ms "2026-10-27T12:00:30.500Z") (some 1793102430500)) "fractional seconds count")
    (assert (= (bl/parseRfc3339Ms "1970-01-01T00:00:00Z") (some 0)) "the epoch is 0")
    (assert (none? (bl/parseRfc3339Ms "2026-10-27T12:00:30+02:00")) "a non-UTC offset is none, never a wrong instant")
    true)

fn testHeaderFixtures -> Bool
  (let [(now 1000)
        (oa (bl/parseRateHeaders (openaiHeaders) now))
        (gq (bl/parseRateHeaders (groqHeaders) now))
        (an (bl/parseRateHeaders (anthropicHeaders) now))]
    (do
      (assert (= (listLength oa) 2) "openai headers give a request and a token row")
      (assert (match (obsOf oa "req") ((some o) (and (= o.remaining 59) (= o.resetAtMs (+ now 360000)))) ((none) false)) "openai requests: 59 left, reset in 6m0s, header names matched case-insensitively")
      (assert (match (obsOf oa "tok") ((some o) (and (= o.remaining 149984) (= o.resetAtMs (+ now 6)))) ((none) false)) "openai tokens: 149984 left, reset in 6ms")
      (assert (match (obsOf gq "req") ((some o) (and (= o.remaining 14370) (= o.resetAtMs (+ now 179560)))) ((none) false)) "groq requests per day: 14370 left, reset in 2m59.56s")
      (assert (match (obsOf gq "tok") ((some o) (and (= o.remaining 5900) (= o.resetAtMs (+ now 7660)))) ((none) false)) "groq tokens: 5900 left, reset in 7.66s")
      (assert (match (obsOf an "req") ((some o) (and (= o.remaining 49) (= o.resetAtMs 1793102430000))) ((none) false)) "anthropic requests: 49 left, reset at its RFC 3339 time")
      (assert (match (obsOf an "tok") ((some o) (and (= o.remaining 39000) (= o.resetAtMs 1793102430500))) ((none) false)) "anthropic tokens: 39000 left")
      (assert (listEmpty? (bl/parseRateHeaders (list (pair "content-type" "application/json")) now)) "a reply without rate-limit headers gives no rows")
      (assert (= (bl/retryAfterMs (list (pair "Retry-After" "7")) (noon)) (some 7000)) "retry-after seconds")
      true))

fn testObservedShiftsPick -> Bool
  (let [(p0 (pool))
        (low (bl/poolObserve p0 "mA" 200 (list (pair "x-ratelimit-remaining-requests" "2")) (noon)))
        (charged (fold (fn [(p bl/Pool) (i Int64)] -> bl/Pool (bl/poolCharge p "mA" (noon) 10)) p0 (range 0 30)))
        (high (bl/poolObserve charged "mA" 200 (list (pair "x-ratelimit-remaining-requests" "90")) (noon)))
        (ledgerOnly (bl/poolObserve p0 "mB" 200 (list (pair "x-ratelimit-remaining-requests" "0")) (noon)))]
    (do
      (assert (= (pickAt p0 (noon)) "mA") "with an empty ledger the stronger mA wins")
      (assert (= (usedOf low "aDay" "req" 100 "header" (noon)) 98) "a header saying 2 left raises aDay's usage to 98 although the ledger has 0")
      (assert (= (pickAt low (noon)) "mB") "the observed shortfall moves the pick to mB")
      (assert (= (usedOf high "aDay" "req" 100 "header" (noon)) 30) "a header reporting more room than the ledger leaves the ledger's 30: pacing uses the smaller remaining")
      (assert (= (usedOf ledgerOnly "bDay" "req" 100 "ledger" (noon)) 0) "a ledger-sourced budget ignores rate-limit headers")
      (assert (= (usedOf low "aDay" "req" 100 "header" (+ (dayMs) 10)) 0) "an observation from yesterday's window does not count today")
      (assert (= (usedOf (bl/poolObserve p0 "mA" 200 (list (pair "x-ratelimit-remaining-requests" "2") (pair "x-ratelimit-reset-requests" "10s")) (noon)) "aDay" "req" 100 "header" (+ (noon) 10001)) 0) "an observation past its own reset is ignored")
      true))

fn testUpstream429Rests -> Bool
  (let [(p0 (pool))
        (retry (bl/poolObserve p0 "mA" 429 (list (pair "retry-after" "30")) (noon)))
        (noHint (bl/poolObserve p0 "mA" 429 (list) (noon)))
        (onLedger (bl/poolObserve p0 "mB" 429 (list) (noon)))]
    (do
      (assert (= (usedOf retry "aDay" "req" 100 "header" (noon)) 100) "a 429 holds aDay at its hard cap")
      (assert (= (pickAt retry (+ (noon) 1)) "mB") "while mA's budget rests the pick goes to mB")
      (assert (= (pickAt retry (+ (noon) 30001)) "mA") "after retry-after the budget is usable again")
      (assert (= (pickAt noHint (+ (noon) 3600000)) "mB") "without retry-after or a reset header the budget rests to the end of its window")
      (assert (= (pickAt noHint (+ (dayMs) 1000)) "mA") "and is back in the next window")
      (assert (= (usedOf onLedger "bDay" "req" 100 "ledger" (noon)) 100) "a 429 exhausts a ledger-sourced budget as well")
      true))

fn testEndpointPoll -> Bool
  (let [(p0 (pool))
        (key (bl/poolObserveEndpoint p0 "orUsd" "{\"data\":{\"label\":\"k\",\"limit\":10,\"usage\":9.5,\"limit_remaining\":0.5}}" (noon)))
        (credits (bl/poolObserveEndpoint p0 "orUsd" "{\"data\":{\"total_credits\":5,\"total_usage\":4.75}}" (noon)))
        (bad (bl/poolObserveEndpoint p0 "orUsd" "{\"data\":{\"label\":\"k\"}}" (noon)))
        (wrongBudget (bl/poolObserveEndpoint p0 "aDay" "{\"data\":{\"limit_remaining\":1}}" (noon)))]
    (do
      (assert (match key ((ok p) (= (usedOf p "orUsd" "usd" 1000000 "endpoint" (noon)) 500000)) ((err _) false)) "/key limit_remaining 0.5 USD leaves 500000 of 1000000 microUSD")
      (assert (match credits ((ok p) (= (usedOf p "orUsd" "usd" 1000000 "endpoint" (noon)) 750000)) ((err _) false)) "/credits 5 - 4.75 USD leaves 250000 microUSD")
      (assert (match bad ((err e) (stringContains? e "none of data.limit_remaining")) ((ok _) false)) "a body without the fields is an error")
      (assert (match wrongBudget ((err e) (stringContains? e "not an endpoint usd budget")) ((ok _) false)) "a poll for a non-endpoint budget is an error")
      true))

; (:m :do "AUDIT10-A4: a free model at cost 0 drawing only on a usd budget charges 0 per request, so a used-plus-charge test alone would still let it through after a 429; it must stay out until the reset, well past the failure cooldown")
fn testZeroCostExhausted -> Bool
  (let [(lone (bl/poolFromParts
                (bl/makeBalancer (list (model "mZ" (list "zUsd"))) (list (budget "zUsd" "usd" 1000000 "ledger")) (list) (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))
                (bl/emptyUse)
                (mapFromPairs (list (pair "mZ" (pair "pz" "model-z"))))))
        (hit (bl/poolObserve lone "mZ" 429 (list (pair "retry-after" "3600")) (noon)))]
    (do
      (assert (= (pickAt lone (noon)) "mZ") "before the 429 the zero-cost model is picked")
      (assert (= (pickAt hit (+ (noon) 120000)) "") "two minutes after a 429 with retry-after 3600 it is still out, past any failure cooldown")
      (assert (match (bl/poolPick hit (req (+ (noon) 120000))) ((bl/refused why) (stringContains? why "zUsd")) (_ false)) "the refusal names the exhausted budget")
      (assert (= (pickAt hit (+ (noon) 3600001)) "mZ") "after the reset it is picked again")
      true))

; (:m :ref GW-BALANCER-RETRYAFTER-DATE :do "Retry-After as an IMF-fixdate: 12:01:30 GMT on the epoch day is 90 seconds after noon")
fn testRetryAfterDate -> Bool
  (let [(date "Thu, 01 Jan 1970 12:01:30 GMT")
        (rested (bl/poolObserve (pool) "mA" 429 (list (pair "Retry-After" date)) (noon)))]
    (do
      (assert (= (bl/parseHttpDateMs "Wed, 21 Oct 2015 07:28:00 GMT") (some 1445412480000)) "the RFC 9110 example date is its epoch milliseconds")
      (assert (= (bl/parseHttpDateMs "Wed, 21 Oct 2015 07:28:00 GMT") (bl/parseRfc3339Ms "2015-10-21T07:28:00Z")) "and the same instant as its RFC 3339 form")
      (assert (= (bl/retryAfterMs (list (pair "Retry-After" date)) (noon)) (some 90000)) "a Retry-After date 90 seconds ahead is a 90000 ms delay")
      (assert (= (bl/retryAfterMs (list (pair "Retry-After" date)) (+ (noon) 100000)) (some 0)) "a date already past is no delay")
      (assert (none? (bl/parseHttpDateMs "Wednesday, 21-Oct-15 07:28:00 GMT")) "the obsolete RFC 850 form is none")
      (assert (none? (bl/parseHttpDateMs "Wed Oct 21 07:28:00 2015")) "the asctime form is none")
      (assert (none? (bl/parseHttpDateMs "Wed, 21 Oct 2015 07:28:00 PST")) "a zone other than GMT is none")
      (assert (none? (bl/parseHttpDateMs "Wed, 21 Okt 2015 07:28:00 GMT")) "an unknown month is none")
      (assert (= (pickAt rested (+ (noon) 89000)) "mB") "a 429 with a Retry-After date rests mA until that date")
      (assert (= (pickAt rested (+ (noon) 91000)) "mA") "and mA is back after it")
      true))

fn runTests -> Bool
  (do
    (assert (testRetryAfterDate) "retry-after date")
    (assert (testZeroCostExhausted) "zero cost exhausted")
    (assert (testDurationsAndTimes) "durations and times")
    (assert (testHeaderFixtures) "header fixtures")
    (assert (testObservedShiftsPick) "observed shifts pick")
    (assert (testUpstream429Rests) "429 rests")
    (assert (testEndpointPoll) "endpoint poll")
    true)
