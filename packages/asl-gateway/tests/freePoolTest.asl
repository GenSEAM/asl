(module aslGateway/tests/freePoolTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (breaker :a b)])

; (:m :ref GW-FREEPOOL-CODE :do "free-pool behaviour proved on the pure chat state machine with scripted effects: a depleted bucket moves on to the next loop model and never to the agy CLI, retry classes, daily-cap parking, provider-shared buckets, the reasoning token floor, empty tools and the context budget")
(schema Seen
  (:f labels String)
  (:f body String)
  (:f status Int64))

fn okBody -> String
  "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"

fn ok200 -> ch/HttpReply
  (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody))

fn effLabel eff: ch/ChatEffect -> String
  (match eff
    ((ch/effBucket m _ _) (str "bucket:" m))
    ((ch/effHttp _ m _ _ req _ _) (str "http:" m "=" req.data))
    ((ch/effPoolHttp _ m _ _ _ _) (str "pool:" m))
    ((ch/effCli client _) (str "cli:" client))
    ((ch/effBreakerEvent e p park) (str "bk:" e ":" p ":" (stringFromInt64 park)))
    ((ch/effSleepMs ms) (str "sleep:" (stringFromInt64 ms)))
    (_ ""))

fn push labels: String l: String -> String
  (if (stringEmpty? l) labels (if (stringEmpty? labels) l (str labels "|" l)))

; (:m :do "bucketOk answers every effBucket; replies feed effHttp in order and the last repeats; a CLI call answers empty")
fn ! drive! step: ch/ChatStep labels: String bucketOk: Bool replies: (List ch/HttpReply) fuel: Int64 -> Seen
  (if (<= fuel 0)
    (Seen :labels labels :body "out of fuel" :status 0)
    (match step
      ((ch/stepDone resp) (Seen :labels labels :body resp.body :status (statusOf resp)))
      ((ch/stepRaised kind msg) (Seen :labels labels :body (str "raised " kind ": " msg) :status 0))
      ((ch/stepEffect eff k)
       (let [(labels2 (push labels (effLabel eff)))]
         (match eff
           ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels2 bucketOk replies (- fuel 1)))
           ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels2 bucketOk replies (- fuel 1)))
           ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels2 bucketOk replies (- fuel 1)))
           ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels2 bucketOk replies (- fuel 1)))
           ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels2 bucketOk replies (- fuel 1)))
           ((ch/effBucket _ _ _) (drive! (k (ch/outBool bucketOk)) labels2 bucketOk replies (- fuel 1)))
           ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels2 bucketOk replies (- fuel 1)))
           ((ch/effHttp _ _ _ _ _ _ _) (drive! (k (ch/outHttp (optionOr (listHead replies) (ok200)))) labels2 bucketOk (optionOr (listTail replies) (list)) (- fuel 1)))
           ((ch/effPoolHttp _ _ _ _ _ _) (drive! (k (ch/outHttp (optionOr (listHead replies) (ok200)))) labels2 bucketOk (optionOr (listTail replies) (list)) (- fuel 1)))
           (_ (drive! (k ch/outDone) labels2 bucketOk replies (- fuel 1))))))))

fn statusOf resp: ch/ChatResponse -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus c) c) (_ acc))) 0 resp.head)

fn ! worldOf! text: String -> (Option ch/ChatWorld)
  (match (c/gateway_config_parse! text "freePool" ".asl/mem/calibration/index.asn")
    ((err _) none)
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) none)
        ((ok st) (some (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-FREEPOOL-1") (pair "FQ_KEY" "k-FREEPOOL-2"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))))))

fn ! run! text: String body: String bucketOk: Bool replies: (List ch/HttpReply) -> Seen
  (match (worldOf! text)
    ((none) (Seen :labels "" :body "no world" :status 0))
    ((some w)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body body) w) "" bucketOk replies 200)))

fn chatBody -> String
  "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn twoModels -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5) (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))"

fn cfgWith provExtra: String m1Extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY" provExtra ")) :models ((:model :id m1 :provider fp :name \"n1\"" m1Extra ") (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))")

fn bodyWith extra: String -> String
  (str "{\"model\":\"default\"," extra "\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn ! runTests -> Bool
  (let [(throttled (run! (twoModels) (chatBody) false (list)))
        (daily (run! (twoModels) (chatBody) true (list (ch/httpError 429 "Too Many Requests" (list) (groqDaily)) (ok200))))
        (shared (run! (cfgWith " :rpm 20 :rpmShared true" "") (chatBody) false (list)))
        (perModel (run! (cfgWith " :rpm 20" " :rpm 5") (chatBody) false (list)))
        (lowFloor (run! (cfgWith "" " :reasoning true") (bodyWith "\"max_tokens\":1000,") true (list)))
        (highKeep (run! (cfgWith "" " :reasoning true") (bodyWith "\"max_tokens\":8000,") true (list)))
        (plainKeep (run! (cfgWith "" "") (bodyWith "\"max_tokens\":1000,") true (list)))
        (dropped (run! (cfgWith " :dropEmptyTools true" "") (bodyWith "\"tools\":[],") true (list)))
        (keptEmpty (run! (cfgWith "" "") (bodyWith "\"tools\":[],") true (list)))
        (droppedFull (run! (cfgWith " :dropEmptyTools true" "") (bodyWith "\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"t\"}}],") true (list)))
        (budget (run! (cfgWith "" " :contextBudget 10") (longBody) true (list)))
        (budgetFits (run! (cfgWith "" " :contextBudget 100000") (longBody) true (list)))
        (emptySys (run! (twoModels) (sysBody "") true (list)))
        (blankSys (run! (twoModels) (sysBody "  \\n ") true (list)))
        (fullSys (run! (twoModels) (sysBody "be terse") true (list)))
        (explicit (run! (twoModels) "{\"model\":\"m1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" false (list)))]
    (do
      (assert (stringContains? throttled.labels "bucket:") (str "the rate bucket is consulted: " throttled.labels))
      (assert (not (stringContains? throttled.labels "cli:agy")) (str "a depleted bucket never goes to the agy CLI: " throttled.labels))
      (assert (and (stringContains? throttled.labels "http:") (= throttled.status 200)) (str "a depleted bucket moves on to the next loop model: " throttled.labels " " throttled.body))
      (assert (and (stringContains? explicit.labels "bucket:") (not (stringContains? explicit.labels "cli:"))) (str "a configured entry named outright is never rescued by the agy CLI when throttled: " explicit.labels))
      (assert (and (stringContains? daily.labels ":433") (not (stringContains? daily.labels "#park")) (= daily.status 200)) (str "a daily-cap 429 parks the model with a duration and the next model answers: " daily.labels))
      (assert (not (stringContains? daily.labels "sleep:")) (str "a daily-cap 429 is not retried: " daily.labels))
      (assert (and (not (u/retryableHttpStatus? 400 "x")) (not (u/retryableHttpStatus? 401 "x")) (not (u/retryableHttpStatus? 402 "x")) (not (u/retryableHttpStatus? 403 "x")) (not (u/retryableHttpStatus? 413 "x"))) "400 401 402 403 413 are never retried")
      (assert (and (u/retryableHttpStatus? 502 "x") (u/retryableHttpStatus? 503 "x") (u/retryableHttpStatus? 429 "plain rate limit")) "502 503 and an ordinary 429 are retried")
      (assert (not (or (u/retryableHttpStatus? 500 "x") (u/retryableHttpStatus? 404 "x"))) "500 and 404 are not retried")
      (assert (u/retryableHttpStatus? 504 "x") "504 is a gateway timeout and retries")
      (assert (not (u/retryableHttpStatus? 429 (groqDaily))) "a daily-cap 429 is not retried")
      (assert (not (u/retryableHttpStatus? 429 "insufficient_quota")) "an account-wide quota 429 is not retried")
      (assert (= (u/dailyCapKind 429 (orDaily)) "openrouter") "openrouter free_model_daily_requests is a daily cap")
      (assert (= (u/dailyCapKind 429 (geminiDaily)) "gemini") "a google quotaId naming PerDay is a daily cap")
      (assert (= (u/dailyCapKind 429 (groqDaily)) "groq") "groq tokens per day is a daily cap")
      (assert (= (u/dailyCapKind 429 "rate limit exceeded, retry in 2s") "") "a per-minute 429 is no daily cap")
      (assert (= (u/dailyCapKind 500 (groqDaily)) "") "only a 429 is a daily cap")
      (assert (= (u/dailyCapParkSec "groq" (list) (groqDaily) 1000.0) 433) "groq parks for the 7m12.96s its body names, rounded up")
      (assert (= (u/dailyCapParkSec "gemini" (list) (geminiDaily) 1000.0) 3001) (str "google parks for its retryDelay 3000s: " (stringFromInt64 (u/dailyCapParkSec "gemini" (list) (geminiDaily) 1000.0))))
      (assert (= (u/dailyCapParkSec "openrouter" (list (pair "X-RateLimit-Reset" "1700007200000")) (orDaily) 1700000000.0) 7200) "openrouter parks until X-RateLimit-Reset given in milliseconds")
      (assert (= (u/dailyCapParkSec "openrouter" (list (pair "X-RateLimit-Reset" "1700007200")) (orDaily) 1700000000.0) 7200) "openrouter parks until X-RateLimit-Reset given in seconds")
      (assert (= (u/dailyCapParkSec "openrouter" (list) (orDaily) 259200.0) 86400) "openrouter with no hint parks to the next UTC midnight")
      (assert (= (u/dailyCapParkSec "openrouter" (list) (orDaily) 342000.0) 3600) "an hour before midnight UTC parks for an hour")
      (assert (= (pairSecond (b/breakerDownFor (b/breakerMarkDownFor (b/defaultBreakerState) "fp:m1" 1000 7200) "fp:m1" 1000)) 7200) "the breaker parks a model for the carried duration")
      (assert (= (pairSecond (b/breakerDownFor (b/breakerMarkDown (b/defaultBreakerState) "fp:m1" 1000) "fp:m1" 1000)) 600) "a plain trip keeps the fixed cooldown")
      (assert (and (stringContains? shared.labels "bucket:provider:fp") (not (stringContains? shared.labels "bucket:n1"))) (str "a provider :rpmShared keys the bucket on the provider: " shared.labels))
      (assert (= (listLength (stringSplit shared.labels "bucket:provider:fp")) 3) (str "both models of the provider draw from the one bucket: " shared.labels))
      (assert (and (stringContains? perModel.labels "bucket:n1") (not (stringContains? perModel.labels "provider:fp"))) (str "without :rpmShared the bucket stays per model: " perModel.labels))
      (assert (stringContains? lowFloor.labels "\"max_tokens\": 4096") (str "a reasoning entry raises a small client max_tokens to 4096 on the profile path: " lowFloor.labels))
      (assert (stringContains? highKeep.labels "\"max_tokens\": 8000") (str "a reasoning entry keeps a client max_tokens above the floor: " highKeep.labels))
      (assert (stringContains? plainKeep.labels "\"max_tokens\": 1000") (str "an entry without :reasoning keeps a small max_tokens: " plainKeep.labels))
      (assert (not (stringContains? dropped.labels "\"tools\"")) (str "dropEmptyTools removes tools:[] from the body: " dropped.labels))
      (assert (stringContains? keptEmpty.labels "\"tools\"") (str "without the option tools:[] is sent as before: " keptEmpty.labels))
      (assert (stringContains? droppedFull.labels "\"tools\"") (str "dropEmptyTools leaves a non-empty tools array alone: " droppedFull.labels))
      (assert (and (not (stringContains? budget.labels "http:n1")) (stringContains? budget.labels "http:n2") (= budget.status 200)) (str "a member whose contextBudget the prompt exceeds is skipped for the next: " budget.labels))
      (assert (stringContains? budgetFits.labels "http:n1") (str "a prompt inside the budget is sent to that member: " budgetFits.labels))
      (assert (and (stringContains? emptySys.labels "http:n1") (not (stringContains? emptySys.labels "\"system\"")) (stringContains? emptySys.labels "\"user\"")) (str "an empty system message is dropped before sending and the user message stays: " emptySys.labels))
      (assert (and (stringContains? blankSys.labels "http:n1") (not (stringContains? blankSys.labels "\"system\""))) (str "a whitespace-only system message is dropped: " blankSys.labels))
      (assert (and (stringContains? fullSys.labels "\"system\"") (stringContains? fullSys.labels "be terse")) (str "a non-empty system message is sent unchanged: " fullSys.labels))
      true))

fn groqDaily -> String
  "{\"error\":{\"message\":\"Rate limit reached for model x in organization y on tokens per day (TPD): Limit 100000, Used 99990, Requested 50. Please try again in 7m12.96s.\",\"type\":\"tokens\"}}"

fn geminiDaily -> String
  "{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\",\"details\":[{\"violations\":[{\"quotaId\":\"GenerateRequestsPerDayPerProjectPerModel-FreeTier\"}]},{\"retryDelay\":\"3000s\"}]}}"

fn orDaily -> String
  "{\"error\":{\"message\":\"Rate limit exceeded: free-models-per-day\",\"metadata\":{\"headers\":{\"X-RateLimit-Limit\":\"50\"},\"quota\":\"free_model_daily_requests\"}}}"

fn longBody -> String
  (str "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"" (rep "lorem ipsum dolor " 40) "\"}]}")

fn rep s: String n: Int64 -> String
  (if (<= n 0) "" (str s (rep s (- n 1))))

fn sysBody content: String -> String
  (str "{\"model\":\"default\",\"messages\":[{\"role\":\"system\",\"content\":\"" content "\"},{\"role\":\"user\",\"content\":\"hi\"}]}")
