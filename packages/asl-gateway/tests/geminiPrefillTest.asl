(module aslGateway/tests/geminiPrefillTest
  :x [runTests]
  :i [(chat :a ch)
      (config :a c)
      (upstream :a u)
      (pyText :a pt)
      (asl-json/json :a j)])

; (:m :ref GW-GEMINI-400 :do "scripted chat path: a model on the generativelanguage host answers HTTP 400 to a body ending with the assistant prefill, so such a model defaults to :prefill false and sends system and user only, an explicit :prefill true keeps it, and a model on another host is untouched")

(schema Seen
  (:f sent String)
  (:f body String))

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn text v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

fn items v: j/Json -> (List j/Json)
  (match v ((j/jarr xs) xs) (_ (list)))

fn configText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://generativelanguage.googleapis.com/v1beta/openai\" :keyEnv \"TEST_KEY\") (:provider :id plain :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id flash :provider test :name \"flash\") (:model :id flashOn :provider test :name \"flashOn\" :prefill true) (:model :id nim :provider plain :name \"nim\")) :profiles ((:profile :id default :routes ((:intent any :chain (flash))))) :uses ((:use :for default :profile default)))"

fn ! world! -> (Option ch/ChatWorld)
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))
        (table (c/gatewayProfilesLoadText! "/test" true (ok (configText)) ""))]
    (match (u/upstreamSettings env)
      ((err _) none)
      ((ok settings) (some (ch/ChatWorld :env env :rootDir "/" :settings settings :agyPromptMaxBytes 10000 :table table)))))

fn ! drive! step: ch/ChatStep reply: String sent: String fuel: Int64 -> Seen
  (if (<= fuel 0)
    (Seen :sent sent :body "out of fuel")
    (match step
      ((ch/stepDone resp) (Seen :sent sent :body resp.body))
      ((ch/stepRaised kind msg) (Seen :sent sent :body (str "raised " kind ": " msg)))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ _ _ _ req _ _ _) (drive! (k (ch/outHttp (ch/httpOk 200 (list) reply))) reply req.data (- fuel 1)))
         ((ch/effRealpath _) (drive! (k (ch/outPath "/")) reply sent (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) reply sent (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) reply sent (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) reply sent (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) reply sent (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) reply sent (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) reply sent (- fuel 1)))
         (_ (drive! (k ch/outDone) reply sent (- fuel 1)))))))

fn ! post! model: String reply: String -> Seen
  (let [(body (str "{\"model\":\"" model "\",\"messages\":[{\"role\":\"system\",\"content\":\"reply in ASN\"},{\"role\":\"user\",\"content\":\"read a.asl\"},{\"role\":\"assistant\",\"content\":\"(:step\"}]}"))]
    (match (world!)
      ((none) (Seen :sent "" :body "no world"))
      ((some w) (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body body) w) reply "" 80))))

fn okReply -> String
  "{\"id\":\"r1\",\"model\":\"m\",\"choices\":[{\"index\":0,\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\" :op \\\"gate\\\")\"}}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":7}}"

fn sentJson s: Seen -> j/Json
  (match (pt/jsonLoads s.sent) ((ok v) v) ((err _) (j/jnull)))

fn lastRole v: j/Json -> String
  (text (get (optionOr (listLast (items (get v "messages"))) (j/jnull)) "role"))
fn ! testGeminiHostDropsPrefill -> Bool
  (let [(v (sentJson (post! "flash" (okReply))))]
    (do
      (assert (= (listLength (items (get v "messages"))) 2) (str "a model on the generativelanguage host sends system and user only, got " (pt/jsonDumps v -1)))
      (assert (= (lastRole v) "user") "the request to the Gemini host ends with a user turn, which the host requires")
      true))

fn ! testExplicitPrefillWins -> Bool
  (let [(v (sentJson (post! "flashOn" (okReply))))]
    (do
      (assert (= (lastRole v) "assistant") "an explicit :prefill true on a Gemini-host model keeps the assistant prefill")
      true))

fn ! testOtherHostKeeps -> Bool
  (let [(v (sentJson (post! "nim" (okReply))))]
    (do
      (assert (= (lastRole v) "assistant") "a model on another host keeps the assistant prefill")
      true))

fn ! runTests -> Bool
  (do
    (assert (testGeminiHostDropsPrefill) "testGeminiHostDropsPrefill passed")
    (assert (testExplicitPrefillWins) "testExplicitPrefillWins passed")
    (assert (testOtherHostKeeps) "testOtherHostKeeps passed")
    true)
