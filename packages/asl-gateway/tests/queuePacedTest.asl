(module aslGateway/tests/queuePacedTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref HUB-QUEUE-PACED :do "the last chain member waits for its rpm bucket up to the request's queue budget (X-ASL-Queue-Ms, X-ASL-Queue-Timeout seconds, or body queue_timeout seconds; 30 s when none) and, still refused, the request ends 429 with Retry-After seconds to the next token (ceil of 60 / rpm) instead of a 502; a refusal that is not a bucket stays a 502; the refusal text names the token bucket, not gemini")
fn statusOf head: (List ch/HeadItem) -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus c) c) ((ch/headField _ _) acc))) 0 head)

fn retryAfterOf head: (List ch/HeadItem) -> String
  (fold (fn [(acc String) (h ch/HeadItem)] -> String (match h ((ch/headStatus _) acc) ((ch/headField n v) (if (= n "Retry-After") v acc)))) "-" head)

fn ! drive! step: ch/ChatStep labels: String granted: (List String) fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone r) (str labels "|status:" (stringFromInt64 (statusOf r.head)) "|ra:" (retryAfterOf r.head) "|body:" r.body))
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels granted (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels granted (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels granted (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat (if (listContains? granted "breakerDown") 2.5 0.0))) labels granted (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 7.0 2.5))) labels granted (- fuel 1)))
         ((ch/effBucket m _ t)
          (drive! (k (ch/outBool (listContains? granted m))) (str labels "|bucket:" m ":" (stringFromFloat64 t)) granted (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ _)
          (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))) (str labels "|http:" m) granted (- fuel 1)))
         (_ (drive! (k ch/outDone) labels granted (- fuel 1)))))))

fn cfg chain: String extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5) (:model :id m2 :provider fp :name \"n2\" :rpm 5)) :profiles ((:profile :id default :routes ((:intent any :chain (" chain "))))) :uses ((:use :for default :profile default)))\n")

fn ! run! chain: String headers: (List (Pair String String)) extraBody: String granted: (List String) -> String
  (runWith! chain "" headers extraBody granted)

fn ! runWith! chain: String extra: String headers: (List (Pair String String)) extraBody: String granted: (List String) -> String
  (match (c/gateway_config_parse! (cfg chain extra) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers headers :body (str "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]" extraBody "}"))
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-QUEUE-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" granted 200)))))

fn ! runTests -> Bool
  (let [(plain (run! "m1" (list) "" (list)))
        (viaMs (run! "m1" (list (pair "X-ASL-Queue-Ms" "2500")) "" (list)))
        (viaBody (run! "m1" (list) ",\"queue_timeout\":7" (list)))
        (viaLeon (run! "m1" (list) ",\"queue_timeout\":1200" (list)))
        (two (run! "m1 m2" (list) ",\"queue_timeout\":9" (list)))
        (served (run! "m1" (list) ",\"queue_timeout\":9" (list "n1")))
        (down (run! "m1" (list) "" (list "breakerDown")))
        (tuned (runWith! "m1" " :queueBudgetSec 4" (list) "" (list)))
        (bad (c/gateway_config_parse! (cfg "m1" " :queueBudgetSec 0") "default" ".asl/mem/calibration/index.asn"))]
    (do (assert (stringContains? plain "|bucket:n1:30") (str "no budget keeps the 30 s wait: " plain))
        (assert (stringContains? plain "|status:429|ra:12|") (str "a refused last member ends 429 with Retry-After = ceil(60/rpm): " plain))
        (assert (not (stringContains? plain "gemini")) (str "the refusal names the token bucket, not gemini: " plain))
        (assert (stringContains? viaMs "|bucket:n1:2.5|") (str "X-ASL-Queue-Ms sets the last member's wait: " viaMs))
        (assert (stringContains? viaBody "|bucket:n1:7.0|") (str "body queue_timeout seconds sets the wait: " viaBody))
        (assert (stringContains? viaLeon "|bucket:n1:1200.0|") (str "Leon's queue_timeout 1200 is honoured whole: " viaLeon))
        (assert (stringContains? two "|bucket:n1:5.0|bucket:n2:9.0|") (str "a member before the last keeps the 5 s default, the last takes the budget: " two))
        (assert (stringContains? two "|status:429|ra:12|") (str "a two-member chain refused by buckets ends 429: " two))
        (assert (stringContains? served "|http:n1|status:200|ra:-|") (str "a granted bucket calls the member: " served))
        (assert (stringContains? down "|status:503|ra:3|") (str "every member in breaker cooldown ends 503 with Retry-After = the shortest cooldown left, rounded up: " down))
        (assert (stringContains? tuned "|bucket:n1:4.0|") (str "the gateway :queueBudgetSec is the wait when the caller gave no budget: " tuned))
        (assert (stringContains? viaMs "|bucket:n1:2.5|") (str "a caller budget still wins over :queueBudgetSec: " viaMs))
        (assert (match bad ((ok t) (and (= t.queueBudgetSec 30.0) (listAny? (fn [(w String)] -> Bool (stringContains? w "queueBudgetSec")) t.warnings))) ((err _) false)) "a non-positive :queueBudgetSec warns and keeps the 30 s default")
        true))
