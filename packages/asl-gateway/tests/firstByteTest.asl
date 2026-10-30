(module aslGateway/tests/firstByteTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-SLOW-STREAM :do "drives the chat steps with scripted effects: m1 (n1) answers a silent-connection failure, m2 (n2) answers ok; every http effect is labelled with its model and its first-byte limit, every usage note with its outcome")
fn ! drive! step: ch/ChatStep labels: String n1Reply: ch/HttpReply fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels n1Reply (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels n1Reply (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels n1Reply (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels n1Reply (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels n1Reply (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels n1Reply (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels n1Reply (- fuel 1)))
         ((ch/effUsageNote _ _ outcome _) (drive! (k ch/outDone) (str labels "|note:" outcome) n1Reply (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ fb)
          (drive! (k (ch/outHttp (if (= m "n1") n1Reply (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))))
                  (str labels "|http:" m ":" (stringFromFloat64 fb)) n1Reply (- fuel 1)))
         (_ (drive! (k ch/outDone) labels n1Reply (- fuel 1)))))))

fn cfg fb: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5" fb ") (:model :id m2 :provider fp :name \"n2\" :rpm 5)) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))")

fn ! run! fb: String n1Reply: ch/HttpReply -> String
  (match (c/gateway_config_parse! (cfg fb) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-FB-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" n1Reply 200)))))

fn silent -> ch/HttpReply
  (ch/httpRaised true (str "curl exit 28: " (u/firstByteDeadlineText)))

fn ! runTests -> Bool
  (let [(keyed (run! " :firstByteSec 20" (silent)))
        (plain (run! "" (ch/httpRaised true "curl exit 28: Operation timed out")))
        (dl (u/firstByteDeadlineAt 1000 20.0))]
    (do (assert (stringContains? keyed "|http:n1:20") (str "the attempt carries the model's :firstByteSec: " keyed))
        (assert (stringContains? keyed "|http:n2:0") (str "a member without the key carries no limit: " keyed))
        (assert (stringContains? keyed "|note:firstByteTimeout") (str "a silent attempt is noted firstByteTimeout: " keyed))
        (assert (stringContains? keyed "|http:n2") (str "the silent attempt cascades to the next member: " keyed))
        (assert (and (stringContains? plain "|note:timeout") (not (stringContains? plain "firstByteTimeout"))) (str "an ordinary timeout keeps its outcome: " plain))
        (assert (stringContains? plain "|http:n1:0") (str "without the key the effect carries 0.0: " plain))
        (assert (= dl 21000) (str "the deadline is start plus the limit: " (stringFromInt64 dl)))
        (assert (= (u/firstByteDeadlineAt 1000 0.0) 0) "no key sets no deadline")
        (assert (not (u/firstByteExpired? dl false 20999)) "before the deadline the call is live")
        (assert (u/firstByteExpired? dl false 21000) "a silent call expires at the deadline")
        (assert (not (u/firstByteExpired? dl true 99999)) "once a byte arrived the guard is off")
        (assert (not (u/firstByteExpired? 0 false 99999)) "no deadline never expires")
        (assert (= (u/firstByteWaitMs dl false 20500) (some 500)) "the reactor is woken at the deadline")
        (assert (= (u/firstByteWaitMs 0 false 20500) none) "no deadline asks for no wakeup")
        true))
