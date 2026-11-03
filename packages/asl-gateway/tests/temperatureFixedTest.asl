(module aslGateway/tests/temperatureFixedTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref KIMI-TEMP-FIXED :do "a model row with :temperatureFixed F always sends temperature F, even when the request carries its own; a cascade fallback model keeps the request temperature; config check rejects :temperatureFixed together with :temperature on one row")
fn tempOf data: String -> String
  (match (stringIndexOf data "\"temperature\": ")
    ((none) "none")
    ((some at)
      (let [(rest (optionOr (stringSlice data (+ at 15) (stringLength data)) ""))
            (cut (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ",")) "") "}")) ""))]
        (stringTrim cut))))

fn ! drive! step: ch/ChatStep labels: String failFirst: Bool fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone r) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels failFirst (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels failFirst (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels failFirst (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels failFirst (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels failFirst (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels failFirst (- fuel 1)))
         ((ch/effHttp _ m _ _ request _ _ _)
          (let [(seen (str labels "|http:" m ":" (tempOf request.data)))]
            (if (and failFirst (= (listLength (stringSplit labels "|http:")) 1))
              (drive! (k (ch/outHttp (ch/httpError 500 "boom" (list) "{}"))) seen failFirst (- fuel 1))
              (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))) seen failFirst (- fuel 1)))))
         (_ (drive! (k ch/outDone) labels failFirst (- fuel 1)))))))

fn cfg m1extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\"" m1extra ") (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))\n")

fn ! run! m1extra: String body: String failFirst: Bool -> String
  (match (c/gatewayConfigParse! (cfg m1extra) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body body)
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-TEMP-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" failFirst 200)))))

fn explicitBody -> String
  "{\"model\":\"default\",\"temperature\":0.2,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn plainBody -> String
  "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn ! runTests -> Bool
  (let [(fixedExplicit (run! " :temperatureFixed 1.0" (explicitBody) false))
        (fixedPlain (run! " :temperatureFixed 1" (plainBody) false))
        (fallback (run! " :temperatureFixed 1.0" (explicitBody) true))
        (unfixed (run! "" (explicitBody) false))
        (both (c/gatewayConfigCheckText! (cfg " :temperatureFixed 1.0 :temperature 0.5") "src" ".asl/mem/calibration/index.asn"))
        (alone (c/gatewayConfigCheckText! (cfg " :temperatureFixed 1.0") "src" ".asl/mem/calibration/index.asn"))
        (junk (c/gatewayConfigCheckText! (cfg " :temperatureFixed \"hot\"") "src" ".asl/mem/calibration/index.asn"))]
    (do (assert (stringContains? fixedExplicit "|http:n1:1.0") (str "an explicit request temperature 0.2 is replaced by the fixed 1.0: " fixedExplicit))
        (assert (stringContains? fixedPlain "|http:n1:1.0") (str "a request without temperature gets the fixed value too: " fixedPlain))
        (assert (stringContains? fallback "|http:n1:1.0|http:n2:0.2") (str "the cascade fallback model keeps the request's 0.2: " fallback))
        (assert (stringContains? unfixed "|http:n1:0.2") (str "a model without the row keeps the explicit temperature: " unfixed))
        (assert (and (= (pairSecond both) 1) (stringContains? (pairFirst both) "temperatureFixed")) (str "config check rejects :temperatureFixed with :temperature on one row: " (pairFirst both)))
        (assert (= (pairSecond alone) 0) (str "config check accepts :temperatureFixed alone: " (pairFirst alone)))
        (assert (and (= (pairSecond junk) 1) (stringContains? (pairFirst junk) "temperatureFixed")) (str "config check rejects a non-number: " (pairFirst junk)))
        true))
