(module aslGateway/tests/topPRowTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-TOPP-ROW :do "a model row with :topP P sends top_p P when the request does not set top_p; an explicit request top_p wins; a row without :topP sends no top_p; config check rejects a :topP outside 0..1")
fn topPOf data: String -> String
  (match (stringIndexOf data "\"top_p\": ")
    ((none) "none")
    ((some at)
      (let [(rest (optionOr (stringSlice data (+ at 9) (stringLength data)) ""))
            (cut (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ",")) "") "}")) ""))]
        (stringTrim cut))))

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
          (let [(seen (str labels "|http:" m ":" (tempOf request.data) ":" (topPOf request.data)))]
            (if (and failFirst (= (listLength (stringSplit labels "|http:")) 1))
              (drive! (k (ch/outHttp (ch/httpError 500 "boom" (list) "{}"))) seen failFirst (- fuel 1))
              (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))) seen failFirst (- fuel 1)))))
         (_ (drive! (k ch/outDone) labels failFirst (- fuel 1)))))))

fn cfg m1extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\"" m1extra ") (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))\n")

fn ! run! m1extra: String body: String -> String
  (match (c/gatewayConfigParse! (cfg m1extra) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body body)
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-TOPP-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" false 200)))))

fn plainBody -> String
  "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn topPBody -> String
  "{\"model\":\"default\",\"top_p\":0.5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn ! runTests -> Bool
  (let [(row (run! " :topP 0.95" (plainBody)))
        (explicit (run! " :topP 0.95" (topPBody)))
        (absent (run! "" (plainBody)))
        (bad (c/gatewayConfigCheckText! (cfg " :topP 2") "src" ".asl/mem/calibration/index.asn"))
        (junk (c/gatewayConfigCheckText! (cfg " :topP \"warm\"") "src" ".asl/mem/calibration/index.asn"))]
    (do (assert (stringEndsWith? row ":0.95") (str "a row :topP 0.95 sends top_p 0.95: " row))
        (assert (stringEndsWith? explicit ":0.5") (str "a request top_p 0.5 is kept: " explicit))
        (assert (not (stringContains? absent "top_p")) (str "a row without :topP sends no top_p: " absent))
        (assert (and (= (pairSecond bad) 1) (stringContains? (pairFirst bad) "topP")) (str "config check rejects :topP 2: " (pairFirst bad)))
        (assert (and (= (pairSecond junk) 1) (stringContains? (pairFirst junk) "topP")) (str "config check rejects a non-number :topP: " (pairFirst junk)))
        true))
