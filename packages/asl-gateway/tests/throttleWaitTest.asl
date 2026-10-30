(module aslGateway/tests/throttleWaitTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-THROTTLE-WAIT :do "the bucket timeout each chain member asks for: earlier members fall through after 0.5 s, the last member waits up to 30 s, so a chain refused only by local rpm buckets still ends in a call")
fn ! drive! step: ch/ChatStep labels: String granted: (List String) fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels granted (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels granted (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels granted (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels granted (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels granted (- fuel 1)))
         ((ch/effBucket m _ t)
          (drive! (k (ch/outBool (listContains? granted m))) (str labels "|bucket:" m ":" (stringFromFloat64 t)) granted (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) (str labels "|cli") granted (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ _)
          (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))) (str labels "|http:" m) granted (- fuel 1)))
         (_ (drive! (k ch/outDone) labels granted (- fuel 1)))))))

fn cfg chain: String extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5) (:model :id m2 :provider fp :name \"n2\" :rpm 5)) :profiles ((:profile :id default :routes ((:intent any :chain (" chain "))))) :uses ((:use :for default :profile default))" extra ")")

fn ! run! chain: String extra: String granted: (List String) -> String
  (match (c/gateway_config_parse! (cfg chain extra) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-THROTTLE-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" granted 200)))))

fn ! runTests -> Bool
  (let [(two (run! "m1 m2" "" (list "n2")))
        (one (run! "m1" "" (list "n1")))
        (none_ (run! "m1 m2" "" (list)))
        (tuned (run! "m1 m2" " :bucketWaitSec 2" (list "n2")))
        (bad (c/gateway_config_parse! (cfg "m1" " :bucketWaitSec 0") "default" ".asl/mem/calibration/index.asn"))]
    (do (assert (stringContains? tuned "|bucket:n1:2") (str "the configured :bucketWaitSec sets the wait of a member before the last: " tuned))
        (assert (stringContains? tuned "|bucket:n2:30") (str "the last member keeps 30 s whatever :bucketWaitSec says: " tuned))
        (assert (match bad ((ok t) (and (= t.bucketWaitSec 5.0) (listAny? (fn [(w String)] -> Bool (stringContains? w "bucketWaitSec")) t.warnings))) ((err _) false)) "a non-positive :bucketWaitSec warns and keeps the default")
        (assert (stringContains? two "|bucket:n1:5") (str "a member before the last waits the default 5 s for its bucket: " two))
        (assert (stringContains? two "|bucket:n2:30") (str "the last member waits up to 30 s: " two))
        (assert (stringContains? two "|http:n2") (str "the waited member is called: " two))
        (assert (stringContains? one "|bucket:n1:30") (str "a single-member chain waits: " one))
        (assert (not (stringContains? none_ "|http:")) (str "a bucket refused after the wait sends nothing: " none_))
        true))
