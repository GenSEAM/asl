; (:m :do "GW-UPSTREAM-TABLES dropped the old modelTokenFloors hardcoded ollama/glm-prefix token-floor table (rule LEON-ROLE/gateway-config-in-home: no model-name knowledge in code); this suite still proves provider/URL/auth/timeout routing for an explicit ollama/glm model, which is a separate, still-live string-prefix provider lookup (getUpstreamForModelIn), not a reasoning-floor guess")
(module aslGateway/tests/ollamaProviderAcceptanceTest
  :x [runTests]
  :i [(upstream :a u)])

fn hasAuth headers: (List (Pair String String)) -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool
               (and (= (pairFirst p) "Authorization") (= (pairSecond p) "Bearer testKey123")))
            headers)

fn runTests -> Bool
  (let [(env (mapSet (mapSet (mapSet (mapEmpty) "OLLAMA_BASE_URL" "http://127.0.0.1:9000/")
                       "OLLAMA_API_KEY" "testKey123")
                     "OLLAMA_TIMEOUT_SEC" "1"))
        (settingsRes (u/upstreamSettings env))]
    (mt settingsRes
      ((err _) false)
      ((ok settings)
        (let [(endpoint (u/getUpstreamForModel settings env (some "ollama/glm-5.3")))
              (requestRes (u/upstreamRequest (u/getUpstreamForModel settings env (some "ollama/glm-5.3")).url
                                             "/chat/completions"
                                             (u/getUpstreamForModel settings env (some "ollama/glm-5.3")).key
                                             "{\"model\":\"glm-5.3\"}"
                                             (list)))
              (timeout settings.ollamaTimeoutSec)]
          (mt requestRes
            ((err _) false)
            ((ok request)
              (do
                (assert (= endpoint.provider "ollama") "explicit ollama model selects the Ollama provider")
                (assert (= endpoint.url "http://127.0.0.1:9000/v1") "Ollama base URL is normalized to the v1 API")
                (assert (= endpoint.key "testKey123") "Ollama API key is selected from its environment variable")
                (assert (= request.url "http://127.0.0.1:9000/v1/chat/completions") "Ollama request targets chat completions")
                (assert (= request.method "POST") "provider request uses POST")
                (assert (hasAuth request.headers) "provider request carries bearer authorization")
                (assert (= timeout 1.0) "Ollama timeout uses its environment setting")
                true)))))))