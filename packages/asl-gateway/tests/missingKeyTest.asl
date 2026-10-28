(module aslGateway/tests/missingKeyTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-MISSINGKEY-UNAUTH :do "a provider that declares keyEnv but resolves to an empty key is never sent: the chat finishes with ERR_KEY_MISSING naming the provider and the keyEnv, and no http effect is emitted; with the key present the same request does emit the http effect")
fn configText -> String
  "(:gateway :v 2 :providers ((:provider :id keyed :kind openai :base \"http://127.0.0.1:1\" :keyEnv \"MISSINGKEY_TEST_KEY\")) :models ((:model :id m :provider keyed :name \"upstreamName\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))"

(schema Seen
  (:f body String)
  (:f sent Int64))

fn twoText -> String
  "(:gateway :v 2 :providers ((:provider :id nokey :kind openai :base \"http://127.0.0.1:1\" :keyEnv \"MISSINGKEY_TEST_KEY\") (:provider :id haskey :kind openai :base \"http://127.0.0.1:2\" :keyEnv \"HASKEY_TEST_KEY\")) :models ((:model :id m1 :provider nokey :name \"first\") (:model :id m2 :provider haskey :name \"second\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))"

fn ! world! env: (Map String String) -> (Option ch/ChatWorld)
  (worldOf! (configText) env)

fn ! worldOf! text: String env: (Map String String) -> (Option ch/ChatWorld)
  (match (c/gateway_config_parse! text "missingKey" ".asl/mem/calibration/index.asn")
    ((err _) none)
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) none)
        ((ok st) (some (ch/ChatWorld :env env :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))))))

fn ! drive! step: ch/ChatStep n: Int64 fuel: Int64 -> Seen
  (if (<= fuel 0)
    (Seen :body "out of fuel" :sent n)
    (match step
      ((ch/stepDone resp) (Seen :body resp.body :sent n))
      ((ch/stepRaised kind msg) (Seen :body (str "raised " kind ": " msg) :sent n))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) n (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) n (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) n (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) n (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) n (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) n (- fuel 1)))
         ((ch/effHttp provider _ _ _ _ _ _) (Seen :body provider :sent (+ n 1)))
         ((ch/effPoolHttp _ _ _ _ _ _) (Seen :body "http" :sent (+ n 1)))
         (_ (drive! (k ch/outDone) n (- fuel 1)))))))

fn ! post! env: (Map String String) -> Seen
  (match (world! env)
    ((none) (Seen :body "no world" :sent 0))
    ((some w)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}") w) 0 80)))

fn ! postTwo! env: (Map String String) -> Seen
  (match (worldOf! (twoText) env)
    ((none) (Seen :body "no world" :sent 0))
    ((some w)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}") w) 0 120)))

fn ! runTests -> Bool
  (let [(missing (post! (mapEmpty)))
        (failover (postTwo! (mapFromPairs (list (pair "HASKEY_TEST_KEY" "k-BBBB2222")))))
        (present (post! (mapFromPairs (list (pair "MISSINGKEY_TEST_KEY" "k-AAAA1111")))))]
    (do
      (assert (= missing.sent 0) "an empty resolved key emits no http effect")
      (assert (and (stringContains? missing.body "ERR_KEY_MISSING") (stringContains? missing.body "keyed") (stringContains? missing.body "MISSINGKEY_TEST_KEY")) (str "the reply names the provider and keyEnv: " missing.body))
      (assert (= present.sent 1) "with the key set the same request emits the http effect")
      (assert (and (= failover.sent 1) (= failover.body "haskey")) (str "a keyless first candidate fails over to the second: " failover.body))
      (assert (not (stringContains? (str missing.body present.body) "AAAA1111")) "no key value appears in a reply")
      true))
