(module aslGateway/router
  :x [Candidate Rule Profile Request ModelCalibration EndpointState ScoreParts Decision RouteDecision RouterError route parseRules score replay mergeSampling matches
      spreadOrder spreadAvailable?]
  :i [(asl-intel/fixture :a asn)])

(schema Candidate
  (:f endpoint String) (:f model String) (:f weight Int64)
  (:f explicit Bool)
  (:f temperature (Option Int64)) (:f topP (Option Int64))
  (:f maxTokens (Option Int64)) (:f effort (Option String))
  (:f stopSet Bool) (:f stop (List String)))
(schema Rule
  (:f id String) (:f intent String) (:f role String)
  (:f minTokens Int64) (:f maxTokens Int64)
  (:f tools Bool) (:f json Bool) (:f streaming Bool)
  (:f latency String) (:f budget String) (:f maxWaitMs Int64)
  (:f costWeight Int64) (:f waitWeight Int64) (:f qualityWeight Int64)
  (:f coldPenaltyMs Int64) (:f candidates (List Candidate)))
(schema Profile (:f rules (List Rule)))
(schema Request
  (:f intent String) (:f role String) (:f promptTokens Int64)
  (:f tools Bool) (:f json Bool) (:f streaming Bool)
  (:f latency String) (:f budget String) (:f expectedTokens Int64))
(schema ModelCalibration
  (:f model String) (:f role String) (:f score Int64)
  (:f temperature Int64) (:f topP Int64) (:f maxTokens Int64) (:f effort String)
  (:f stop (List String)))
(schema EndpointState
  (:f endpoint String) (:f queue Int64) (:f throughput Int64)
  (:f cold Bool) (:f down Bool) (:f pricePerMillion Int64))
(schema ScoreParts
  (:f cost Int64) (:f wait Int64) (:f quality Int64) (:f total Int64))
(schema Decision
  (:f endpoint String) (:f model String) (:f ruleWeight Int64)
  (:f sampling Candidate) (:f score ScoreParts) (:f total Int64) (:f waitMs Int64))
(schema RouteDecision
  (:f ruleId String) (:f request Request) (:f candidates (List Decision))
  (:f choice Decision) (:f spillover (List Decision)))

(enum RouterError
  (:c invalidCalibrationScore [(model String) (score Int64)])
  (:c routeFailure [(message String)]))

fn matches r: Rule q: Request -> Bool
  (and (= r.intent q.intent)
    (and (= r.role q.role)
      (and (>= q.promptTokens r.minTokens)
        (and (<= q.promptTokens r.maxTokens)
          (and (or (not r.tools) q.tools)
            (and (or (not r.json) q.json)
              (and (or (not r.streaming) q.streaming)
                (and (= r.latency q.latency) (= r.budget q.budget)))))))))

fn findRule rs: (List Rule) q: Request -> (Option Rule)
  (match (listHead rs)
    ((some r) (if (matches r q) (some r) (findRule (optionOr (listTail rs) (list)) q)))
    ((none) (none)))

fn findState ss: (List EndpointState) endpoint: String -> (Option EndpointState)
  (match (listHead ss)
    ((some s) (if (= s.endpoint endpoint) (some s) (findState (optionOr (listTail ss) (list)) endpoint)))
    ((none) (none)))

fn findCalibration cs: (List ModelCalibration) model: String role: String -> (Option ModelCalibration)
  (match (listHead cs)
    ((some c) (if (and (= c.model model) (= c.role role)) (some c) (findCalibration (optionOr (listTail cs) (list)) model role)))
    ((none) (none)))

fn validateCalibrationScores cs: (List ModelCalibration) -> (Result (List ModelCalibration) RouterError)
  (match (listHead cs)
    ((none) (ok cs))
    ((some c)
      (if (or (< c.score 0) (> c.score 10000))
        (err (invalidCalibrationScore c.model c.score))
        (match (validateCalibrationScores (optionOr (listTail cs) (list)))
          ((err e) (err e))
          ((ok _) (ok cs))))))

fn addChecked a: Int64 b: Int64 -> (Result Int64 String)
  (if (> b 0)
    (if (> a (- 9223372036854775807 b)) (err "score overflow") (ok (+ a b)))
    (ok (+ a b)))

fn expectedWait s: EndpointState r: Rule -> Int64
  (let [(waitBase (if (> s.throughput 0)
        (if (> s.queue (/ 9223372036854775807 1000)) 9223372036854775807
          (/ (* s.queue 1000) s.throughput))
        9223372036854775807))
        (cold (if s.cold r.coldPenaltyMs 0))]
    (if (> waitBase (- 9223372036854775807 cold)) 9223372036854775807 (+ waitBase cold)))

fn boolText value: Bool -> String
  (if value "true" "false")

fn noRoute q: Request detail: String -> String
  (str "noRoute intent=" q.intent " role=" q.role
    " tokens=" (stringFromInt64 q.promptTokens)
    " tools=" (boolText q.tools) " json=" (boolText q.json)
    " streaming=" (boolText q.streaming)
    " latency=" q.latency " budget=" q.budget
    " expectedTokens=" (stringFromInt64 q.expectedTokens) " " detail)

fn multiplyChecked a: Int64 b: Int64 -> (Result Int64 String)
  (if (or (< a 0) (< b 0)) (err "negative score input")
    (if (and (> a 0) (> b (/ 9223372036854775807 a))) (err "cost overflow") (ok (* a b))))

fn kwFlag a: asn/Asn key: String -> Bool
  (match (asn/kwArg a key)
    ((some value) (match value ((asn/aSym s) (= s "true")) ((asn/aKw s) (= s "true")) (else false)))
    ((none) false))

fn kwOptionalInt a: asn/Asn key: String -> (Option Int64)
  (match (asn/kwArg a key)
    ((some value) (match value ((asn/aInt n) (some n)) (else (none))))
    ((none) (none)))

fn kwOptionalString a: asn/Asn key: String -> (Option String)
  (match (asn/kwArg a key)
    ((some value) (match value ((asn/aStr s) (some s)) ((asn/aSym s) (some s)) (else (none))))
    ((none) (none)))

fn parseStopItems xs: (List asn/Asn) acc: (List String) -> (Result (List String) String)
  (match (listHead xs)
    ((none) (ok acc))
    ((some value)
      (match value
        ((asn/aStr stop) (parseStopItems (optionOr (listTail xs) (list)) (listAppend acc (list stop))))
        (else (err "stop entries must be strings")))))

fn kwStops a: asn/Asn -> (Result (List String) String)
  (match (asn/kwArg a "stop")
    ((none) (ok (list)))
    ((some _) (match (asn/kwItems a "stop") ((err e) (err e)) ((ok xs) (parseStopItems xs (list))))))

fn kwHasStop a: asn/Asn -> Bool
  (some? (asn/kwArg a "stop"))

fn score c: Candidate r: Rule q: Request s: EndpointState calibration: (Option ModelCalibration) -> (Result ScoreParts String)
  (match calibration
    ((some m) (if (or (< m.score 0) (> m.score 10000)) (err "invalid calibration score") (rawScore c r q s calibration)))
    ((none) (rawScore c r q s calibration)))

fn rawScore c: Candidate r: Rule q: Request s: EndpointState calibration: (Option ModelCalibration) -> (Result ScoreParts String)
  (match (multiplyChecked s.pricePerMillion q.expectedTokens)
    ((err e) (err e))
    ((ok gross)
      (match (multiplyChecked (/ gross 1000000) r.costWeight)
        ((err e) (err e))
        ((ok cost)
          (let [(qualityRaw (match calibration ((some m) (- 10000 m.score)) ((none) 10000)))
                (waitRaw (expectedWait s r))]
            (match (multiplyChecked waitRaw r.waitWeight)
              ((err e) (err e))
              ((ok wait)
                (match (multiplyChecked qualityRaw r.qualityWeight)
                  ((err e) (err e))
                  ((ok quality)
                    (match (addChecked cost wait)
                      ((err e) (err e))
                      ((ok first)
                        (match (addChecked first quality)
                          ((err e) (err e))
                          ((ok total) (ok (ScoreParts :cost cost :wait wait :quality quality :total total)))))))))))))))

fn mergeSampling c: Candidate cal: (Option ModelCalibration) -> Candidate
  (match cal
    ((some m) (Candidate :endpoint c.endpoint :model c.model :weight c.weight :explicit c.explicit
       :temperature (if (some? c.temperature) c.temperature (some m.temperature))
       :topP (if (some? c.topP) c.topP (some m.topP)) :maxTokens (if (some? c.maxTokens) c.maxTokens (some m.maxTokens))
       :effort (if (some? c.effort) c.effort (some m.effort))
       :stopSet true :stop (if c.stopSet c.stop m.stop)))
    ((none) c))

fn buildDecisions cs: (List Candidate) r: Rule q: Request states: (List EndpointState) calibrations: (List ModelCalibration) -> (Result (List Decision) String)
  (match (listHead cs)
    ((none) (ok (list)))
    ((some c)
      (let [(cal (findCalibration calibrations c.model q.role))
            (state (findState states c.endpoint))]
        (match state
          ((none) (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations))
          ((some s)
            (if s.down
              (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
              (if (and (none? cal) (not c.explicit))
                (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
                (match (score c r q s cal)
                  ((err e) (err e))
                  ((ok sc)
                    (match (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
                      ((err e) (err e))
                      ((ok rest) (ok (listAppend (list (Decision :endpoint c.endpoint :model c.model :ruleWeight c.weight :sampling (mergeSampling c cal) :score sc :total sc.total :waitMs (expectedWait s r))) rest)))))))))))))

fn better a: Decision b: Decision -> Bool
  (or (< a.total b.total)
    (and (= a.total b.total) (>= a.ruleWeight b.ruleWeight)))

fn insertSorted d: Decision ds: (List Decision) -> (List Decision)
  (match (listHead ds)
    ((none) (list d))
    ((some h) (if (better d h) (listAppend (list d) ds) (listAppend (list h) (insertSorted d (optionOr (listTail ds) (list)))))))

fn sortDecisions ds: (List Decision) -> (List Decision)
  (match (listHead ds)
    ((none) (list))
    ((some h) (insertSorted h (sortDecisions (optionOr (listTail ds) (list))))))

fn route profile: Profile q: Request states: (List EndpointState) calibrations: (List ModelCalibration) -> (Result RouteDecision RouterError)
  (match (validateCalibrationScores calibrations)
    ((err e) (err e))
    ((ok _) (match (findRule profile.rules q)
      ((none) (err (routeFailure (noRoute q ""))))
      ((some r)
        (match (buildDecisions r.candidates r q states calibrations)
          ((err e) (err (routeFailure e)))
          ((ok unsorted)
            (let [(ordered (sortDecisions unsorted))]
              (match (listHead ordered)
                ((none) (err (routeFailure (noRoute q "candidatesUnavailable"))))
                ((some winner)
                  (let [(wait winner.waitMs)
                        (spill (if (> wait r.maxWaitMs) (optionOr (listTail ordered) (list)) (list)))]
                    (ok (RouteDecision :ruleId r.id :request q :candidates ordered :choice winner :spillover spill))))))))))))

fn parseCandidate a: asn/Asn -> (Result Candidate String)
  (match (asn/kwStr a "endpoint")
    ((err e) (err e))
    ((ok endpoint)
      (match (asn/kwStr a "model")
        ((err e) (err e))
        ((ok model) (match (kwStops a)
          ((err e) (err e))
          ((ok stops) (ok (Candidate :endpoint endpoint :model model :weight (resultOr (asn/kwInt a "weight") 1) :explicit true :temperature (kwOptionalInt a "temperature") :topP (kwOptionalInt a "topP") :maxTokens (kwOptionalInt a "maxTokens") :effort (kwOptionalString a "effort") :stopSet (kwHasStop a) :stop stops))))))))

fn parseCandidateList xs: (List asn/Asn) acc: (List Candidate) -> (Result (List Candidate) String)
  (match (listHead xs)
    ((none) (ok acc))
    ((some x) (match (parseCandidate x)
      ((err e) (err e))
      ((ok c) (parseCandidateList (optionOr (listTail xs) (list)) (listAppend acc (list c)))))))

fn parseRule a: asn/Asn -> (Result Rule String)
  (match (asn/kwStr a "id") ((err e) (err e)) ((ok id)
    (match (asn/kwStr a "intent") ((err e) (err e)) ((ok intent)
      (match (asn/kwStr a "role") ((err e) (err e)) ((ok role)
        (match (asn/kwItems a "candidates") ((err e) (err e)) ((ok xs)
          (match (parseCandidateList xs (list)) ((err e) (err e)) ((ok candidates)
            (ok (Rule :id id :intent intent :role role
              :minTokens (resultOr (asn/kwInt a "minTokens") 0) :maxTokens (resultOr (asn/kwInt a "maxTokens") 9223372036854775807)
              :tools (kwFlag a "tools") :json (kwFlag a "json") :streaming (kwFlag a "streaming")
              :latency (resultOr (asn/kwStr a "latency") "interactive") :budget (resultOr (asn/kwStr a "budget") "standard")
              :maxWaitMs (resultOr (asn/kwInt a "maxWaitMs") 0) :costWeight (resultOr (asn/kwInt a "costWeight") 1) :waitWeight (resultOr (asn/kwInt a "waitWeight") 1) :qualityWeight (resultOr (asn/kwInt a "qualityWeight") 1) :coldPenaltyMs (resultOr (asn/kwInt a "coldPenaltyMs") 0) :candidates candidates))))))))))))

fn parseRules text: String -> (Result Profile String)
  (match (asn/readAsn text)
    ((err e) (err e))
    ((ok forms)
      (match (listHead forms)
        ((none) (err "empty profile ASN"))
        ((some root)
          (match (asn/kwItems root "rules")
            ((err e) (err e))
            ((ok rules) (parseRuleList rules (list))))))))

fn parseRuleList xs: (List asn/Asn) acc: (List Rule) -> (Result Profile String)
  (match (listHead xs)
    ((none) (ok (Profile :rules acc)))
    ((some x) (match (parseRule x)
      ((err e) (err e))
      ((ok r) (parseRuleList (optionOr (listTail xs) (list)) (listAppend acc (list r)))))))

fn replay records: (List (Pair Request (List EndpointState))) profile: Profile calibrations: (List ModelCalibration) -> (List (Result RouteDecision RouterError))
  (match (listHead records)
    ((none) (list))
    ((some item) (listAppend (list (route profile (pairFirst item) (pairSecond item) calibrations)) (replay (optionOr (listTail records) (list)) profile calibrations))))

; (:m :ref GW-SPREAD-20261017 :do "nginx's smooth weighted round-robin: every live member's current weight gains its own static weight each round, the max is picked, and only the picked member's current is reduced by the round's total live weight; a member excluded this round (breaker open or in cooldown) keeps its stored current untouched, so it resumes mid-rotation rather than resetting once it returns")
fn spreadCurrentOf state: (Map String Int64) alias: String -> Int64
  (optionOr (mapGet state alias) 0)

fn spreadBumped members: (List (Pair String Int64)) state: (Map String Int64) -> (List (Pair String Int64))
  (map (fn [(m (Pair String Int64))] -> (Pair String Int64)
         (pair (pairFirst m) (+ (spreadCurrentOf state (pairFirst m)) (pairSecond m))))
    members)

fn spreadBest bumped: (List (Pair String Int64)) -> (Option (Pair String Int64))
  (fold (fn [(acc (Option (Pair String Int64))) (b (Pair String Int64))] -> (Option (Pair String Int64))
          (match acc
            ((none) (some b))
            ((some cur) (if (> (pairSecond b) (pairSecond cur)) (some b) acc))))
    none bumped)

; (:m :ref GW-SPREAD-20261017 :do "available = still configured in :spread, breaker not open, and no 429 within :cooldownSec of now; a member outside this list is skipped for the pick entirely, not merely deprioritized")
fn spreadAvailable? now: Int64 cooldownSec: Int64 last429: (Map String Int64) breakerOpen?: (fn [String] -> Bool) alias: String -> Bool
  (and (not (breakerOpen? alias))
    (match (mapGet last429 alias)
      ((none) true)
      ((some at) (>= (- now at) (* cooldownSec 1000)))))

; (:m :ref GW-SPREAD-20261017 :do "the full attempt order for one call: the SWRR-picked member first, then every other available member by descending bumped current weight (the order they would have won in, had this round continued), skipped/unavailable members absent entirely; cascadeChosen prepends this ahead of the plain :chain and must never attempt a model twice, so the chain walk needs to skip whatever already appears here")
fn spreadOrder now: Int64 cooldownSec: Int64 members: (List (Pair String Int64)) last429: (Map String Int64) breakerOpen?: (fn [String] -> Bool) state: (Map String Int64) -> (Pair (List String) (Map String Int64))
  (let [(avail (filter (fn [(m (Pair String Int64))] -> Bool (spreadAvailable? now cooldownSec last429 breakerOpen? (pairFirst m))) members))]
    (if (listEmpty? avail) (pair (list) state)
      (let [(total (listSum (map pairSecond avail)))
            (bumped (spreadBumped avail state))
            (best (spreadBest bumped))]
        (match best
          ((none) (pair (list) state))
          ((some b)
            (let [(bestAlias (pairFirst b))
                  (rest (listSortBy (fn [(x (Pair String Int64))] -> Int64 (- 0 (pairSecond x)))
                          (filter (fn [(x (Pair String Int64))] -> Bool (!= (pairFirst x) bestAlias)) bumped)))
                  (order (cons bestAlias (map pairFirst rest)))
                  (withBumped (fold (fn [(m (Map String Int64)) (x (Pair String Int64))] -> (Map String Int64) (mapSet m (pairFirst x) (pairSecond x))) state bumped))
                  (finalState (mapSet withBumped bestAlias (- (pairSecond b) total)))]
              (pair order finalState)))))))
