(module aslGateway/router
  :x [Candidate Rule Profile Request ModelCalibration EndpointState ScoreParts Decision RouteDecision RouterError route parseRules score replay mergeSampling matches]
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
  (mt (listHead rs)
    ((some r) (if (matches r q) (some r) (findRule (optionOr (listTail rs) (list)) q)))
    ((none) (none)))

fn findState ss: (List EndpointState) endpoint: String -> (Option EndpointState)
  (mt (listHead ss)
    ((some s) (if (= s.endpoint endpoint) (some s) (findState (optionOr (listTail ss) (list)) endpoint)))
    ((none) (none)))

fn findCalibration cs: (List ModelCalibration) model: String role: String -> (Option ModelCalibration)
  (mt (listHead cs)
    ((some c) (if (and (= c.model model) (= c.role role)) (some c) (findCalibration (optionOr (listTail cs) (list)) model role)))
    ((none) (none)))

fn validateCalibrationScores cs: (List ModelCalibration) -> (Result (List ModelCalibration) RouterError)
  (mt (listHead cs)
    ((none) (ok cs))
    ((some c)
      (if (or (< c.score 0) (> c.score 10000))
        (err (invalidCalibrationScore c.model c.score))
        (mt (validateCalibrationScores (optionOr (listTail cs) (list)))
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
  (mt (asn/kwArg a key)
    ((some value) (mt value ((asn/aSym s) (= s "true")) ((asn/aKw s) (= s "true")) (else false)))
    ((none) false))

fn kwOptionalInt a: asn/Asn key: String -> (Option Int64)
  (mt (asn/kwArg a key)
    ((some value) (mt value ((asn/aInt n) (some n)) (else (none))))
    ((none) (none)))

fn kwOptionalString a: asn/Asn key: String -> (Option String)
  (mt (asn/kwArg a key)
    ((some value) (mt value ((asn/aStr s) (some s)) ((asn/aSym s) (some s)) (else (none))))
    ((none) (none)))

fn parseStopItems xs: (List asn/Asn) acc: (List String) -> (Result (List String) String)
  (mt (listHead xs)
    ((none) (ok acc))
    ((some value)
      (mt value
        ((asn/aStr stop) (parseStopItems (optionOr (listTail xs) (list)) (listAppend acc (list stop))))
        (else (err "stop entries must be strings")))))

fn kwStops a: asn/Asn -> (Result (List String) String)
  (mt (asn/kwArg a "stop")
    ((none) (ok (list)))
    ((some _) (mt (asn/kwItems a "stop") ((err e) (err e)) ((ok xs) (parseStopItems xs (list))))))

fn kwHasStop a: asn/Asn -> Bool
  (some? (asn/kwArg a "stop"))

fn score c: Candidate r: Rule q: Request s: EndpointState calibration: (Option ModelCalibration) -> (Result ScoreParts String)
  (mt calibration
    ((some m) (if (or (< m.score 0) (> m.score 10000)) (err "invalid calibration score") (rawScore c r q s calibration)))
    ((none) (rawScore c r q s calibration)))

fn rawScore c: Candidate r: Rule q: Request s: EndpointState calibration: (Option ModelCalibration) -> (Result ScoreParts String)
  (mt (multiplyChecked s.pricePerMillion q.expectedTokens)
    ((err e) (err e))
    ((ok gross)
      (mt (multiplyChecked (/ gross 1000000) r.costWeight)
        ((err e) (err e))
        ((ok cost)
          (let [(qualityRaw (mt calibration ((some m) (- 10000 m.score)) ((none) 10000)))
                (waitRaw (expectedWait s r))]
            (mt (multiplyChecked waitRaw r.waitWeight)
              ((err e) (err e))
              ((ok wait)
                (mt (multiplyChecked qualityRaw r.qualityWeight)
                  ((err e) (err e))
                  ((ok quality)
                    (mt (addChecked cost wait)
                      ((err e) (err e))
                      ((ok first)
                        (mt (addChecked first quality)
                          ((err e) (err e))
                          ((ok total) (ok (ScoreParts :cost cost :wait wait :quality quality :total total)))))))))))))))

fn mergeSampling c: Candidate cal: (Option ModelCalibration) -> Candidate
  (mt cal
    ((some m) (Candidate :endpoint c.endpoint :model c.model :weight c.weight
       :temperature (optionOr c.temperature (some m.temperature))
       :topP (optionOr c.topP (some m.topP)) :maxTokens (optionOr c.maxTokens (some m.maxTokens))
       :effort (optionOr c.effort (some m.effort))
       :stopSet true :stop (if c.stopSet c.stop m.stop)))
    ((none) c))

fn buildDecisions cs: (List Candidate) r: Rule q: Request states: (List EndpointState) calibrations: (List ModelCalibration) -> (Result (List Decision) String)
  (mt (listHead cs)
    ((none) (ok (list)))
    ((some c)
      (let [(cal (findCalibration calibrations c.model q.role))
            (state (findState states c.endpoint))]
        (mt state
          ((none) (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations))
          ((some s)
            (if s.down
              (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
              (if (and (none? cal) (not c.explicit))
                (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
                (mt (score c r q s cal)
                  ((err e) (err e))
                  ((ok sc)
                    (mt (buildDecisions (optionOr (listTail cs) (list)) r q states calibrations)
                      ((err e) (err e))
                      ((ok rest) (ok (listAppend (list (Decision :endpoint c.endpoint :model c.model :ruleWeight c.weight :sampling (mergeSampling c cal) :score sc :total sc.total :waitMs (expectedWait s r))) rest)))))))))))))

fn better a: Decision b: Decision -> Bool
  (or (< a.total b.total)
    (and (= a.total b.total) (>= a.ruleWeight b.ruleWeight)))

fn insertSorted d: Decision ds: (List Decision) -> (List Decision)
  (mt (listHead ds)
    ((none) (list d))
    ((some h) (if (better d h) (listAppend (list d) ds) (listAppend (list h) (insertSorted d (optionOr (listTail ds) (list)))))))

fn sortDecisions ds: (List Decision) -> (List Decision)
  (mt (listHead ds)
    ((none) (list))
    ((some h) (insertSorted h (sortDecisions (optionOr (listTail ds) (list))))))

fn route profile: Profile q: Request states: (List EndpointState) calibrations: (List ModelCalibration) -> (Result RouteDecision RouterError)
  (mt (validateCalibrationScores calibrations)
    ((err e) (err e))
    ((ok _) (mt (findRule profile.rules q)
      ((none) (err (routeFailure (noRoute q ""))))
      ((some r)
        (mt (buildDecisions r.candidates r q states calibrations)
          ((err e) (err (routeFailure e)))
          ((ok unsorted)
            (let [(ordered (sortDecisions unsorted))]
              (mt (listHead ordered)
                ((none) (err (routeFailure (noRoute q "candidatesUnavailable"))))
                ((some winner)
                  (let [(wait winner.waitMs)
                        (spill (if (> wait r.maxWaitMs) (optionOr (listTail ordered) (list)) (list)))]
                    (ok (RouteDecision :ruleId r.id :request q :candidates ordered :choice winner :spillover spill))))))))))))

fn parseCandidate a: asn/Asn -> (Result Candidate String)
  (mt (asn/kwStr a "endpoint")
    ((err e) (err e))
    ((ok endpoint)
      (mt (asn/kwStr a "model")
        ((err e) (err e))
        ((ok model) (mt (kwStops a)
          ((err e) (err e))
          ((ok stops) (ok (Candidate :endpoint endpoint :model model :weight (resultOr (asn/kwInt a "weight") 1) :explicit true :temperature (kwOptionalInt a "temperature") :topP (kwOptionalInt a "topP") :maxTokens (kwOptionalInt a "maxTokens") :effort (kwOptionalString a "effort") :stopSet (kwHasStop a) :stop stops))))))))

fn parseCandidateList xs: (List asn/Asn) acc: (List Candidate) -> (Result (List Candidate) String)
  (mt (listHead xs)
    ((none) (ok acc))
    ((some x) (mt (parseCandidate x)
      ((err e) (err e))
      ((ok c) (parseCandidateList (optionOr (listTail xs) (list)) (listAppend acc (list c)))))))

fn parseRule a: asn/Asn -> (Result Rule String)
  (mt (asn/kwStr a "id") ((err e) (err e)) ((ok id)
    (mt (asn/kwStr a "intent") ((err e) (err e)) ((ok intent)
      (mt (asn/kwStr a "role") ((err e) (err e)) ((ok role)
        (mt (asn/kwItems a "candidates") ((err e) (err e)) ((ok xs)
          (mt (parseCandidateList xs (list)) ((err e) (err e)) ((ok candidates)
            (ok (Rule :id id :intent intent :role role
              :minTokens (resultOr (asn/kwInt a "minTokens") 0) :maxTokens (resultOr (asn/kwInt a "maxTokens") 9223372036854775807)
              :tools (kwFlag a "tools") :json (kwFlag a "json") :streaming (kwFlag a "streaming")
              :latency (resultOr (asn/kwStr a "latency") "interactive") :budget (resultOr (asn/kwStr a "budget") "standard")
              :maxWaitMs (resultOr (asn/kwInt a "maxWaitMs") 0) :costWeight (resultOr (asn/kwInt a "costWeight") 1) :waitWeight (resultOr (asn/kwInt a "waitWeight") 1) :qualityWeight (resultOr (asn/kwInt a "qualityWeight") 1) :coldPenaltyMs (resultOr (asn/kwInt a "coldPenaltyMs") 0) :candidates candidates))))))))))))

fn parseRules text: String -> (Result Profile String)
  (mt (asn/readAsn text)
    ((err e) (err e))
    ((ok forms)
      (mt (listHead forms)
        ((none) (err "empty profile ASN"))
        ((some root)
          (mt (asn/kwItems root "rules")
            ((err e) (err e))
            ((ok rules) (parseRuleList rules (list))))))))

fn parseRuleList xs: (List asn/Asn) acc: (List Rule) -> (Result Profile String)
  (mt (listHead xs)
    ((none) (ok (Profile :rules acc)))
    ((some x) (mt (parseRule x)
      ((err e) (err e))
      ((ok r) (parseRuleList (optionOr (listTail xs) (list)) (listAppend acc (list r)))))))

fn replay records: (List (Pair Request (List EndpointState))) profile: Profile calibrations: (List ModelCalibration) -> (List (Result RouteDecision RouterError))
  (mt (listHead records)
    ((none) (list))
    ((some item) (listAppend (list (route profile (pairFirst item) (pairSecond item) calibrations)) (replay (optionOr (listTail records) (list)) profile calibrations))))
