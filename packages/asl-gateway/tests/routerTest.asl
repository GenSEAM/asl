(module aslGateway/tests/routerTest
  :x [runTests]
  :i [(aslGateway/router :a rt)])

fn candidate endpoint: String model: String weight: Int64 -> rt/Candidate
  (rt/Candidate :endpoint endpoint :model model :weight weight :explicit false :temperature (none) :topP (none) :maxTokens (none) :effort (none) :stopSet false :stop (list))

fn rule id: String latency: String maxWait: Int64 candidates: (List rt/Candidate) -> rt/Rule
  (rt/Rule :id id :intent "chat" :role "assistant" :minTokens 0 :maxTokens 10000 :tools false :json false :streaming false :latency latency :budget "standard" :maxWaitMs maxWait :costWeight 1 :waitWeight 1 :qualityWeight 1 :coldPenaltyMs 0 :candidates candidates)

fn request latency: String -> rt/Request
  (rt/Request :intent "chat" :role "assistant" :promptTokens 100 :tools false :json false :streaming false :latency latency :budget "standard" :expectedTokens 1000)

fn endpoint id: String queue: Int64 throughput: Int64 cold: Bool down: Bool price: Int64 -> rt/EndpointState
  (rt/EndpointState :endpoint id :queue queue :throughput throughput :cold cold :down down :pricePerMillion price)

fn calibration model: String role: String score: Int64 -> rt/ModelCalibration
  (rt/ModelCalibration :model model :role role :score score :temperature 1 :topP 9 :maxTokens 4096 :effort "medium" :stop (list "CAL_STOP"))

fn ! testProfileParseAndFirstMatch -> Bool
  (let [(text (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/router/profile.asn") ""))
        (parsed (rt/parseRules text))]
    (assert (ok? parsed) "ASN profile fixture parses")
    (mt parsed
      ((err _) false)
      ((ok profile)
        (mt (rt/route profile (rt/Request :intent "chat" :role "assistant" :promptTokens 100 :tools true :json true :streaming true :latency "interactive" :budget "standard" :expectedTokens 1000) (list (endpoint "fast" 0 100 false false 1) (endpoint "quality" 0 100 false false 1)) (list (calibration "m-fast" "assistant" 9000)))
          ((err _) false)
          ((ok decision) (do
            (assert (= decision.ruleId "interactive") "first matching rule wins")
            (assert (= decision.choice.sampling.temperature 3) "candidate sampling override replaces role default")
            (assert (= decision.choice.sampling.stop (list "HALT")) "stop override is parsed and retained")
            true))))))

fn ! testCalibrationSamplingDefaults -> Bool
  (let [(r (rule "defaults" "interactive" 100 (list (candidate "e" "m" 1))))
        (result (rt/route (rt/Profile :rules (list r)) (request "interactive") (list (endpoint "e" 0 10 false false 1)) (list (calibration "m" "assistant" 9000))))]
    (mt result ((err _) false) ((ok d) (do
      (assert (= d.choice.sampling.stop (list "CAL_STOP")) "calibration stop is the role default")
      true))))

fn testDimensionAndNoRoute -> Bool
  (let [(profile (rt/Profile :rules (list (rule "only" "interactive" 100 (list (candidate "a" "m" 1))))))
        (bad (rt/Request :intent "other" :role "assistant" :promptTokens 100 :tools true :json true :streaming true :latency "interactive" :budget "standard" :expectedTokens 321))
        (result (rt/route profile bad (list) (list)))]
    (assert (err? result) "unmatched request returns noRoute")
    (mt result
      ((err error) (mt error
        ((rt/routeFailure message) (do
        (assert (stringContains? message "noRoute") "noRoute error identifies the failure")
        (assert (stringContains? message "intent=other") "noRoute error reports intent")
        (assert (stringContains? message "role=assistant") "noRoute error reports role")
        (assert (stringContains? message "tokens=100") "noRoute error reports prompt token count")
        (assert (stringContains? message "tools=true") "noRoute error reports tools")
        (assert (stringContains? message "json=true") "noRoute error reports JSON mode")
        (assert (stringContains? message "streaming=true") "noRoute error reports streaming mode")
        (assert (stringContains? message "latency=interactive") "noRoute error reports latency class")
        (assert (stringContains? message "budget=standard") "noRoute error reports budget class")
        (assert (stringContains? message "expectedTokens=321") "noRoute error reports expected tokens") true))
        (_ false)))
      ((ok _) false))
    true)

fn testRouteScoreDownAndSpillover -> Bool
  (let [(r (rule "score" "interactive" 1 (list (candidate "cheap" "cheap-model" 1) (candidate "good" "good-model" 1) (candidate "slow" "slow-model" 1) (candidate "down" "down-model" 99))))
        (p (rt/Profile :rules (list r)))
        (q (request "interactive"))
        (states (list (endpoint "cheap" 1 1 false false 1) (endpoint "good" 1 1 false false 1) (endpoint "slow" 1 1 false false 1) (endpoint "down" 1 1 false true 1)))
        (cal (list (calibration "cheap-model" "assistant" 9000) (calibration "good-model" "assistant" 10000) (calibration "slow-model" "assistant" 5000) (calibration "down-model" "assistant" 10000)))
        (result (rt/route p q states cal))]
    (assert (ok? result) "healthy candidates route")
    (mt result ((err _) false) ((ok d)
      (assert (= d.choice.endpoint "good") "quality term changes winning candidate")
      (assert (= (listLength d.spillover) 2) "wait over rule maximum spills ordered remainder")
      (mt (listHead d.spillover) ((none) false) ((some first) (do
        (assert (= first.endpoint "cheap") "spillover begins with next score-ranked candidate")
        (mt (listTail d.spillover) ((none) false) ((some rest) (mt (listHead rest) ((none) false) ((some second) (do (assert (= second.endpoint "slow") "spillover preserves complete score order") true))))))))
      (assert (= (listLength d.candidates) 3) "down endpoint excluded") true)))

fn testExpectedWaitThresholdIndependentOfWeight -> Bool
  (let [(base (rule "zero-wait-weight" "interactive" 50 (list (candidate "slow" "slow" 1) (candidate "fast" "fast" 1))))
        (r (rt/Rule :id base.id :intent base.intent :role base.role :minTokens base.minTokens :maxTokens base.maxTokens :tools false :json false :streaming false :latency "interactive" :budget "standard" :maxWaitMs 50 :costWeight 0 :waitWeight 0 :qualityWeight 0 :coldPenaltyMs 0 :candidates base.candidates))
        (p (rt/Profile :rules (list r)))
        (got (rt/route p (request "interactive") (list (endpoint "slow" 1 10 false false 1) (endpoint "fast" 1 100 false false 1)) (list (calibration "slow" "assistant" 10000) (calibration "fast" "assistant" 10000))))]
    (mt got ((err _) false) ((ok d) (do
      (assert (= d.choice.waitMs 100) "decision reports expected wait rather than weighted wait score")
      (assert (= (listLength d.spillover) 1) "expected wait above threshold spills even at zero wait weight") true))))

fn testUncalibratedEligibility -> Bool
  (let [(r (rule "explicit" "interactive" 100 (list (rt/Candidate :endpoint "e" :model "m" :weight 1 :explicit true :temperature (none) :topP (none) :maxTokens (none) :effort (none) :stopSet false :stop (list)))))
        (p (rt/Profile :rules (list r)))]
    (assert (ok? (rt/route p (request "interactive") (list (endpoint "e" 0 10 false false 1)) (list))) "explicit uncalibrated model remains eligible")
    (assert (err? (rt/route (rt/Profile :rules (list (rule "not-explicit" "interactive" 100 (list (candidate "e" "m" 1))))) (request "interactive") (list (endpoint "e" 0 10 false false 1)) (list))) "uncalibrated model without explicit rule inclusion is ineligible")
    true)

fn testReplayDeterminism -> Bool
  (let [(p (rt/Profile :rules (list (rule "r" "interactive" 100 (list (candidate "e" "m" 1))))))
        (q (request "interactive"))
        (s (list (endpoint "e" 0 10 false false 1)))
        (records (list (pair q s)))
        (one (rt/replay records p (list (calibration "m" "assistant" 9000))))
        (two (rt/replay records p (list (calibration "m" "assistant" 9000))))]
    (assert (= one two) "replay produces deterministic decisions")
    true)

fn choiceEndpoint result: (Result rt/RouteDecision rt/RouterError) -> String
  (mt result ((err _) "error") ((ok decision) decision.choice.endpoint))

fn testReplayOrder -> Bool
  (let [(p (rt/Profile :rules (list (rule "replay" "interactive" 100 (list (candidate "first" "m1" 1) (candidate "second" "m2" 1))))))
        (q (request "interactive"))
        (records (list (pair q (list (endpoint "first" 0 10 false false 1))) (pair q (list (endpoint "second" 0 10 false false 1)))))
        (results (rt/replay records p (list (calibration "m1" "assistant" 10000) (calibration "m2" "assistant" 10000))))
        (first (optionOr (listGet results 0) (err (rt/routeFailure "missing first result"))))
        (second (optionOr (listGet results 1) (err (rt/routeFailure "missing second result"))))]
    (assert (= (listLength results) 2) "replay preserves one result per record")
    (assert (= (choiceEndpoint first) "first") "replay keeps first record first")
    (assert (= (choiceEndpoint second) "second") "replay keeps second record second")
    true)

fn testAllMatcherDimensions -> Bool
  (let [(r0 (rule "match" "interactive" 100 (list (candidate "e" "m" 1))))
        (rTool (rt/Rule :id "x" :intent "chat" :role "assistant" :minTokens 0 :maxTokens 10000 :tools true :json false :streaming false :latency "interactive" :budget "standard" :maxWaitMs 1 :costWeight 1 :waitWeight 1 :qualityWeight 1 :coldPenaltyMs 0 :candidates (list)))
        (q (request "interactive"))]
    (assert (rt/matches r0 q) "all default matcher dimensions match")
    (assert (not (rt/matches rTool q)) "required tools capability mismatch rejects")
    (assert (not (rt/matches (rt/Rule :id "json" :intent "chat" :role "assistant" :minTokens 0 :maxTokens 10000 :tools false :json true :streaming false :latency "interactive" :budget "standard" :maxWaitMs 1 :costWeight 1 :waitWeight 1 :qualityWeight 1 :coldPenaltyMs 0 :candidates (list)) q)) "required json capability mismatch rejects")
    (assert (not (rt/matches (rt/Rule :id "stream" :intent "chat" :role "assistant" :minTokens 0 :maxTokens 10000 :tools false :json false :streaming true :latency "interactive" :budget "standard" :maxWaitMs 1 :costWeight 1 :waitWeight 1 :qualityWeight 1 :coldPenaltyMs 0 :candidates (list)) q)) "required streaming capability mismatch rejects")
    (assert (not (rt/matches r0 (rt/Request :intent "chat" :role "user" :promptTokens 100 :tools false :json false :streaming false :latency "interactive" :budget "standard" :expectedTokens 1))) "role mismatch rejects")
    (assert (not (rt/matches r0 (rt/Request :intent "chat" :role "assistant" :promptTokens 10001 :tools false :json false :streaming false :latency "interactive" :budget "standard" :expectedTokens 1))) "token maximum mismatch rejects")
    (assert (not (rt/matches (rt/Rule :id "minimum" :intent "chat" :role "assistant" :minTokens 101 :maxTokens 10000 :tools false :json false :streaming false :latency "interactive" :budget "standard" :maxWaitMs 1 :costWeight 1 :waitWeight 1 :qualityWeight 1 :coldPenaltyMs 0 :candidates (list)) q)) "token minimum mismatch rejects")
    (assert (not (rt/matches r0 (rt/Request :intent "chat" :role "assistant" :promptTokens 100 :tools false :json false :streaming false :latency "batch" :budget "standard" :expectedTokens 1))) "latency class mismatch rejects")
    (assert (not (rt/matches r0 (rt/Request :intent "chat" :role "assistant" :promptTokens 100 :tools false :json false :streaming false :latency "interactive" :budget "economy" :expectedTokens 1))) "budget class mismatch rejects")
    true)

fn testTieBreaks -> Bool
  (let [(cs (list (candidate "first" "m1" 4) (candidate "heavy" "m2" 8)))
        (p (rt/Profile :rules (list (rule "ties" "interactive" 100 (list (candidate "first" "m1" 4) (candidate "heavy" "m2" 8))))))
        (ss (list (endpoint "first" 0 10 false false 1) (endpoint "heavy" 0 10 false false 1)))
        (cc (list (calibration "m1" "assistant" 10000) (calibration "m2" "assistant" 10000)))
        (got (rt/route p (request "interactive") ss cc))]
    (assert (ok? got) "equal scores route")
    (mt got ((err _) false) ((ok d) (do (assert (= d.choice.endpoint "heavy") "equal score prefers higher candidate weight") true)))
    (let [(firstRule (rule "declaration" "interactive" 100 (list (candidate "first" "m1" 1) (candidate "heavy" "m2" 1))))
          (same (rt/route (rt/Profile :rules (list firstRule)) (request "interactive") ss cc))]
      (mt same ((err _) false) ((ok d) (do (assert (= d.choice.endpoint "first") "equal score and weight preserve declaration order") true)))))

fn testCostAndWaitChangeWinner -> Bool
  (let [(p (rt/Profile :rules (list (rule "cost-wait" "interactive" 10000 (list (candidate "a" "a" 1) (candidate "b" "b" 1))))))
        (q (rt/Request :intent "chat" :role "assistant" :promptTokens 100 :tools false :json false :streaming false :latency "interactive" :budget "standard" :expectedTokens 1000000))
        (cal (list (calibration "a" "assistant" 10000) (calibration "b" "assistant" 10000)))
        (costWinner (rt/route p q (list (endpoint "a" 0 10 false false 9) (endpoint "b" 0 10 false false 1)) cal))
        (waitWinner (rt/route p q (list (endpoint "a" 100 1 false false 1) (endpoint "b" 0 1 false false 1)) cal))]
    (mt costWinner ((err _) false) ((ok d) (assert (= d.choice.endpoint "b") "lower token cost changes winner") true))
    (mt waitWinner ((err _) false) ((ok d) (assert (= d.choice.endpoint "b") "shorter expected queue wait changes winner") true))
    true)

fn testColdStartPenalty -> Bool
  (let [(base (rule "cold" "interactive" 10000 (list (candidate "cold" "cold" 1) (candidate "warm" "warm" 1))))
        (r (rt/Rule :id base.id :intent base.intent :role base.role :minTokens base.minTokens :maxTokens base.maxTokens :tools false :json false :streaming false :latency "interactive" :budget "standard" :maxWaitMs 10000 :costWeight 1 :waitWeight 1 :qualityWeight 0 :coldPenaltyMs 2000 :candidates base.candidates))
        (p (rt/Profile :rules (list r)))
        (ss (list (endpoint "cold" 0 1 true false 1) (endpoint "warm" 0 1 false false 1)))
        (cc (list (calibration "cold" "assistant" 10000) (calibration "warm" "assistant" 10000)))
        (got (rt/route p (request "interactive") ss cc))]
    (mt got ((err _) false) ((ok d) (do (assert (= d.choice.endpoint "warm") "cold-start penalty changes winner") true))))

fn testCalibrationScoreRange -> Bool
  (let [(p (rt/Profile :rules (list (rule "calibration-range" "interactive" 100 (list (candidate "e" "m" 1))))))
        (s (list (endpoint "e" 0 10 false false 1)))
        (q (request "interactive"))
        (c (candidate "e" "m" 1))
        (r (rule "calibration-range" "interactive" 100 (list c)))
        (state (endpoint "e" 0 10 false false 1))]
    (assert (ok? (rt/route p q s (list (calibration "m" "assistant" 0)))) "calibration score zero is accepted")
    (assert (ok? (rt/route p q s (list (calibration "m" "assistant" 10000)))) "calibration score 10000 is accepted")
    (assert (mt (rt/route p q s (list (calibration "m" "assistant" -1)))
      ((err error) (mt error ((rt/invalidCalibrationScore model score) (and (= model "m") (= score -1))) (_ false)))
      ((ok _) false)) "negative calibration score returns typed error")
    (assert (mt (rt/route p q s (list (calibration "m" "assistant" 10001)))
      ((err error) (mt error ((rt/invalidCalibrationScore model score) (and (= model "m") (= score 10001))) (_ false)))
      ((ok _) false)) "calibration score above 10000 returns typed error")
    (assert (err? (rt/score c r q state (some (calibration "m" "assistant" -1)))) "score helper rejects invalid calibration values")
    true)

fn testCostOverflowGuard -> Bool
  (let [(p (rt/Profile :rules (list (rule "overflow" "interactive" 100 (list (candidate "e" "m" 1))))))
        (q (rt/Request :intent "chat" :role "assistant" :promptTokens 1 :tools false :json false :streaming false :latency "interactive" :budget "standard" :expectedTokens 2))
        (s (list (endpoint "e" 0 1 false false 9223372036854775807)))
        (c (list (calibration "m" "assistant" 10000)))]
    (assert (err? (rt/route p q s c)) "cost multiplication overflow is returned as error")
    true)

fn testExpectedWaitOverflowGuard -> Bool
  (let [(p (rt/Profile :rules (list (rule "wait-overflow" "interactive" 9223372036854775807 (list (candidate "e" "m" 1))))))
        (q (request "interactive"))
        (s (list (endpoint "e" 9223372036854775807 1 false false 0)))
        (c (list (calibration "m" "assistant" 10000)))
        (result (rt/route p q s c))]
    (assert (ok? result) "expected-wait multiplication overflow saturates instead of trapping")
    (mt result ((err _) false) ((ok decision)
      (assert (= decision.choice.waitMs 9223372036854775807) "overflowed expected wait saturates at Int64 maximum") true)))

fn ! runTests -> Bool
  (do
    (testProfileParseAndFirstMatch)
    (testCalibrationSamplingDefaults)
    (testDimensionAndNoRoute)
    (testRouteScoreDownAndSpillover)
    (testExpectedWaitThresholdIndependentOfWeight)
    (testUncalibratedEligibility)
    (testReplayDeterminism)
    (testReplayOrder)
    (testAllMatcherDimensions)
    (testTieBreaks)
    (testCostOverflowGuard)
    (testExpectedWaitOverflowGuard)
    (testCostAndWaitChangeWinner)
    (testColdStartPenalty)
    (testCalibrationScoreRange)
    true)
