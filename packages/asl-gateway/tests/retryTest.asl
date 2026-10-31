(module aslGateway/tests/retryTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (pyText :a pt)
      (asl-json/json :a j)])

; (:m :tags (retry) :do "hand-written (not pinned to any python corpus) coverage for GW-FREE-RETRY: upstream.asl's transient classification and backoff math, config.asl's :retry parsing and precedence, and chat.asl's httpFailed/raised retry-before-breaker decision")

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn text v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

; (:m :tags (retry) :do "upstream.asl coverage")

fn testTransientTextClassification -> Bool
  (do
    (assert (u/looksTransientText? "Upstream model provider is temporarily unavailable") "temporarily unavailable is transient text")
    (assert (u/looksTransientText? "The model is currently OVERLOADED, please retry") "overloaded (any case) is transient text")
    (assert (u/looksTransientText? "429: rate limit exceeded, slow down") "rate limit is transient text")
    (refute (u/looksTransientText? "insufficient_quota: you have run out of credits") "quota text is not the transient wording")
    (refute (u/looksTransientText? "") "empty body is not transient text")
    true)

fn testProviderWideQuotaClassification -> Bool
  (do
    (assert (u/looksProviderWideQuota? "You exceeded your current quota, insufficient_quota") "insufficient_quota marks provider-wide")
    (assert (u/looksProviderWideQuota? "Billing hard limit reached") "billing marks provider-wide")
    (assert (u/looksProviderWideQuota? "Your ACCOUNT is out of QUOTA this month") "account+quota marks provider-wide")
    (refute (u/looksProviderWideQuota? "rate limit exceeded, please slow down") "an ordinary rate-limit body is not provider-wide")
    (refute (u/looksProviderWideQuota? "") "empty body is not provider-wide")
    true)

fn testRetryableHttpStatus -> Bool
  (do
    (assert (u/retryableHttpStatus? 429 "Upstream model provider is temporarily unavailable") "laguna-style 429 retries")
    (refute (u/retryableHttpStatus? 429 "You exceeded your quota: insufficient_quota") "provider-wide 429 does not retry")
    (assert (u/retryableHttpStatus? 429 "some unrelated upstream message") "an unrecognised 429 body retries: only quota and daily-cap bodies are final")
    (assert (u/retryableHttpStatus? 502 "Bad Gateway") "502 always retries")
    (assert (u/retryableHttpStatus? 503 "Service Unavailable") "503 always retries")
    (assert (u/retryableHttpStatus? 504 "Gateway Timeout") "504 is a gateway timeout and retries like the transport timeouts")
    (refute (u/retryableHttpStatus? 404 "Not Found") "404 is never retried")
    (refute (u/retryableHttpStatus? 500 "Internal Server Error") "500 is not in the retry set")
    (refute (u/retryableHttpStatus? 400 "Bad Request") "400 is not in the retry set")
    (refute (u/retryableHttpStatus? 401 "Unauthorized") "401 is not in the retry set")
    true)

fn testParseCurlExitCode -> Bool
  (do
    (match (u/parseCurlExitCode "curl exit 7: Failed to connect")
      ((some c) (assert (= c 7) "parses the connect-failure exit code"))
      ((none) (assert false "expected some code")))
    (match (u/parseCurlExitCode "curl exit 28: Operation timed out")
      ((some c) (assert (= c 28) "parses the timeout exit code"))
      ((none) (assert false "expected some code")))
    (refute (some? (u/parseCurlExitCode "curl: command not found")) "a toolAbsent-style message has no curl exit prefix")
    (refute (some? (u/parseCurlExitCode "AttributeError: 'NoneType' object has no attribute 'x'")) "a pure parse-error message has no curl exit prefix")
    true)

fn testRetryableRaised -> Bool
  (do
    (assert (u/retryableRaised? true "curl exit 28: Operation timed out") "a real timeout always retries")
    (assert (u/retryableRaised? false "curl exit 7: Failed to connect") "connect failure (7) retries")
    (assert (u/retryableRaised? false "curl exit 52: Empty reply from server") "empty reply (52) retries")
    (assert (u/retryableRaised? false "curl exit 56: Recv failure: Connection reset by peer") "connection reset (56) retries")
    (refute (u/retryableRaised? false "curl exit 3: URL malformed") "an unrelated curl exit code does not retry")
    (refute (u/retryableRaised? false "curl: command not found") "a missing tool does not retry")
    (refute (u/retryableRaised? false "AttributeError: 'NoneType' object has no attribute 'x'") "a body-parse error does not retry")
    true)

fn testRetryDelayMs -> Bool
  (do
    (assert (= (u/retryDelayMs 1000 20000 1 (some 5.0) 123.0) 5000) "Retry-After of 5s becomes 5000ms")
    (assert (= (u/retryDelayMs 1000 20000 1 (some 999.0) 123.0) 20000) "Retry-After is still bounded by capMs")
    (assert (= (u/retryDelayMs 1000 20000 1 (none) 100.0) 1) "zero jitter fraction floors to the 1ms minimum, never zero")
    (assert (= (u/retryDelayMs 1000 20000 1 (none) 100.73) 730) "attempt 1: baseMs(1000) * jitter fraction (0.73)")
    (assert (= (u/retryDelayMs 1000 20000 2 (none) 100.5) 1000) "attempt 2: exponential window doubles to 2000ms, half of it is 1000ms")
    (assert (= (u/retryDelayMs 1000 20000 6 (none) 100.5) 10000) "attempt 6 would be 32000ms uncapped; capMs 20000 halved by jitter is 10000ms")
    true)

; (:m :tags (retry) :do "config.asl coverage")

fn retryConfigText -> String
  (str
    "(:gateway :v 2 :profile p1\n"
    "  :providers ((:provider :id openrouter :kind openai :base \"https://example.test/v1\" :timeoutSec 45\n"
    "                :retry (:max 2 :baseMs 1000 :capMs 20000)))\n"
    "  :models ((:model :id m1 :provider openrouter :name \"m1\")\n"
    "           (:model :id m2 :provider openrouter :name \"m2\" :retry (:max 5 :baseMs 500 :capMs 4000))\n"
    "           (:model :id m3 :provider agy :name \"m3\"))\n"
    "  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1))))))")

fn retryMax policy: c/RetryPolicy -> Int64
  policy.maxAttempts

fn testRetryParseAndPrecedence -> Bool
  (let [(tblRes (c/gatewayConfigParse! (retryConfigText) "retryTest" ""))]
    (match tblRes
      ((err e) (assert false (str "retryConfigText must parse: " e)))
      ((ok tbl)
       (do
         (assert (= tbl.version 2) "a :v 2 config parses to version 2")
         (match (mapGet tbl.providers "openrouter")
           ((none) (assert false "provider openrouter must be present"))
           ((some pv)
            (match pv.retry
              ((none) (assert false "provider openrouter must carry its own :retry"))
              ((some pr) (assert (= pr.maxAttempts 2) "provider-level :max parses to 2")))))
         (match (c/gatewayV2Entry! tbl "m1")
           ((c/entryUnresolved _) (assert false "m1 must resolve"))
           ((c/entryResolved e1)
            (match e1.retry
              ((none) (assert false "m1 has no own :retry, so it must inherit the provider's"))
              ((some r1) (assert (= r1.maxAttempts 2) "m1 inherits provider :max 2 when it names none of its own")))))
         (match (c/gatewayV2Entry! tbl "m2")
           ((c/entryUnresolved _) (assert false "m2 must resolve"))
           ((c/entryResolved e2)
            (match e2.retry
              ((none) (assert false "m2 must carry its own :retry"))
              ((some r2) (do
                           (assert (= r2.maxAttempts 5) "m2's own :max 5 wins over the provider's :max 2")
                           (assert (= r2.baseMs 500) "m2's own :baseMs wins too")
                           (assert (= r2.capMs 4000) "m2's own :capMs wins too"))))))
         (match (c/gatewayV2Entry! tbl "m3")
           ((c/entryUnresolved _) (assert false "m3 must resolve"))
           ((c/entryResolved e3) (assert (none? e3.retry) "m3's provider (agy) names no :retry, so m3 has none")))
         (match (c/gatewayV2Entry! tbl "m1")
           ((c/entryUnresolved _) (assert false "m1 must resolve"))
           ((c/entryResolved e1)
            (let [(viaEntry (c/mergedRetryPolicy (some tbl) "openrouter" (some e1)))
                  (viaProviderOnly (c/mergedRetryPolicy (some tbl) "openrouter" (none)))
                  (viaUnknownProvider (c/mergedRetryPolicy (some tbl) "unknownProvider" (none)))
                  (viaNoTable (c/mergedRetryPolicy (none) "openrouter" (none)))]
              (do
                (assert (= (retryMax viaEntry) 2) "mergedRetryPolicy with an entry carrying :retry returns that entry's policy")
                (assert (= (retryMax viaProviderOnly) 2) "mergedRetryPolicy with no entry falls back to the provider's policy")
                (assert (= (retryMax viaUnknownProvider) 0) "mergedRetryPolicy for a provider absent from the table is noRetryPolicy")
                (assert (= (retryMax viaNoTable) 0) "mergedRetryPolicy with no table at all is noRetryPolicy")))))
         (assert (= (retryMax (c/noRetryPolicy)) 0) "noRetryPolicy.maxAttempts is 0 (today's behaviour, absent config)")
         true))))

; (:m :tags (retry) :ref FREEPOOL-GATEWAY-FIRSTBYTE-20261017 :do "GW-RETRY-OCGO-HANG follow-up: firstByteCapSec's 60s floor was a bare literal; :firstByteSec is now a real gateway config knob at both provider and model level, same precedence as :timeoutSec/:retry (model wins, else provider, else the 60s default applied by firstByteCapSec itself -- never a second literal resolved here)")
fn firstByteSecConfigText -> String
  (str
    "(:gateway :v 2 :profile p1\n"
    "  :providers ((:provider :id openrouter :kind openai :base \"https://example.test/v1\" :timeoutSec 120\n"
    "                :firstByteSec 20))\n"
    "  :models ((:model :id m1 :provider openrouter :name \"m1\")\n"
    "           (:model :id m2 :provider openrouter :name \"m2\" :firstByteSec 5)\n"
    "           (:model :id m3 :provider agy :name \"m3\"))\n"
    "  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1))))))")

fn testFirstByteSecParseAndPrecedence -> Bool
  (let [(tblRes (c/gatewayConfigParse! (firstByteSecConfigText) "retryTest" ""))]
    (match tblRes
      ((err e) (assert false (str "firstByteSecConfigText must parse: " e)))
      ((ok tbl)
       (do
         (match (mapGet tbl.providers "openrouter")
           ((none) (assert false "provider openrouter must be present"))
           ((some pv) (assert (= pv.firstByteSec 20.0) "provider-level :firstByteSec parses to 20.0")))
         (match (c/gatewayV2Entry! tbl "m1")
           ((c/entryUnresolved _) (assert false "m1 must resolve"))
           ((c/entryResolved e1) (assert (= e1.firstByteSec 20.0) "m1 names no :firstByteSec of its own, so it inherits the provider's 20.0")))
         (match (c/gatewayV2Entry! tbl "m2")
           ((c/entryUnresolved _) (assert false "m2 must resolve"))
           ((c/entryResolved e2) (assert (= e2.firstByteSec 5.0) "m2's own :firstByteSec 5.0 wins over the provider's 20.0")))
         (match (c/gatewayV2Entry! tbl "m3")
           ((c/entryUnresolved _) (assert false "m3 must resolve"))
           ((c/entryResolved e3) (assert (= e3.firstByteSec 0.0) "m3's provider (agy) names no :firstByteSec, so m3 gets the 0.0 unconfigured sentinel, never a baked-in 60.0 here")))
         (assert (= (u/firstByteCapSec 120.0 20.0) 20.0) "firstByteCapSec honours a configured value under the attempt's own timeout")
         (assert (= (u/firstByteCapSec 10.0 20.0) 10.0) "firstByteCapSec still never exceeds the attempt's own timeout, even when the configured value is larger")
         (assert (= (u/firstByteCapSec 120.0 0.0) 60.0) "firstByteCapSec falls back to the 60s default only when nothing configured a value (0.0 sentinel)")
         true))))

fn testMalformedRetryIsRejected -> Bool
  (let [(badText (str
                   "(:gateway :v 2 :profile p1\n"
                   "  :providers ((:provider :id openrouter :kind openai :base \"https://example.test/v1\"\n"
                   "                :retry (:max 1 :baseMs 500 :capMs 100)))\n"
                   "  :models ((:model :id m1 :provider openrouter :name \"m1\"))\n"
                   "  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1))))))"))]
    (match (c/gatewayConfigParse! badText "retryTest" "")
      ((err e) (do (assert (stringContains? e "capMs") "a capMs below baseMs is rejected with a message naming capMs") true))
      ((ok _) (do (assert false "capMs < baseMs must not parse ok") true))))

; (:m :tags (retry) :do "chat.asl coverage")

fn emptySettings -> u/UpstreamSettings
  (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 300.0)

fn testWorld tbl: (Option c/GatewayTable) -> ch/ChatWorld
  (ch/ChatWorld :env (mapEmpty) :rootDir "/tmp" :settings (emptySettings) :agyPromptMaxBytes 188000
    :table (match tbl ((some t) (ok t)) ((none) (err "ERR_GATEWAY_NO_CONFIG: no config loaded"))))

fn testCtx tbl: (Option c/GatewayTable) -> ch/Ctx
  (ch/Ctx :req (ch/ChatRequest :path "/chat/completions" :headers (list) :body "{}")
    :world (testWorld tbl) :path "/chat/completions" :asn true :sanitize false
    :intent "" :role "coder" :workspace "/tmp" :explicitModel "" :profileRouted false :profileName ""
    :table tbl :reqKeys (list) :headerEff (none) :envEff (none) :tempExplicit false :timeoutExplicit false
    :baseBody (j/jnull) :cascadeLen 1 :spread (list) :cooldownSec 60 :session "" :stuck "" :dropOnSwitch false)

fn testLoop -> ch/Loop
  (ch/Loop :body (j/jnull) :models (list) :idx 0 :lastErr (none) :skipped (list) :emptyRetries 0 :telBound false :head (list) :retryAfterSec 0)

fn testAttempt providerId: String data: String -> ch/Attempt
  (ch/Attempt :entry (c/entryUnresolved "m1") :v2 (none) :model "m1" :target "m1"
    :upstream (u/UpstreamEndpoint :provider providerId :url "https://example.test/v1" :key "" :sessionHeader "")
    :alias "m1" :pool (str providerId ":m1") :providerPool providerId
    :sentEffort (none) :poolConfig (none) :data data :api "chat" :path "/chat/completions"
    :retryUsed 0 :retryDeadline (none))

fn opOf step: ch/ChatStep -> String
  (match step
    ((ch/stepEffect eff _) (text (get (ch/effectJson eff) "op")))
    ((ch/stepDone _) "done")
    ((ch/stepRaised kind _) (str "raised:" kind)))

fn fieldOf step: ch/ChatStep key: String -> j/Json
  (match step
    ((ch/stepEffect eff _) (get (ch/effectJson eff) key))
    (_ (j/jnull)))

fn feedDone step: ch/ChatStep -> ch/ChatStep
  (match step
    ((ch/stepEffect _ k) (k (ch/outDone)))
    (_ step))

fn feedFloat step: ch/ChatStep f: Float64 -> ch/ChatStep
  (match step
    ((ch/stepEffect _ k) (k (ch/outFloat f)))
    (_ step))

fn feedHttp step: ch/ChatStep reply: ch/HttpReply -> ch/ChatStep
  (match step
    ((ch/stepEffect _ k) (k (ch/outHttp reply)))
    (_ step))

fn testConfigAbsentKeepsOldBehaviour -> Bool
  (let [(cx (testCtx (none)))
        (a (testAttempt "openrouter" "{}"))
        (step (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list) "Upstream model provider is temporarily unavailable"))]
    (do
      (assert (= (opOf step) "breaker") "with no :retry anywhere, a transient 429 still goes straight to the old finish path (breaker trip first, same as before this unit)")
      (assert (= (opOf (feedDone step)) "usageNote") "...then records the outcome on the usage ledger, unchanged")
      true))

fn emptyTable -> c/GatewayTable
  (c/GatewayTable :version 0 :defaultProfile "" :profiles (mapEmpty) :profileOrder (list) :models (mapEmpty) :modelOrder (list)
    :providers (mapEmpty) :intents (mapEmpty) :uses (mapEmpty) :useOrder (list) :source "" :registry "" :registryError (none)
    :warnings (list) :undeclaredIntents (mapEmpty) :keyFiles (list) :limits (list) :bucketWaitSec 5.0 :queueBudgetSec 30.0)

fn tableWithRetry maxAttempts: Int64 -> c/GatewayTable
  (let [(text (str
                "(:gateway :v 2 :profile p1\n"
                "  :providers ((:provider :id openrouter :kind openai :base \"https://example.test/v1\" :timeoutSec 45\n"
                "                :retry (:max " (stringFromInt64 maxAttempts) " :baseMs 1000 :capMs 20000)))\n"
                "  :models ((:model :id m1 :provider openrouter :name \"m1\"))\n"
                "  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1))))))"))]
    (match (c/gatewayConfigParse! text "retryTest" "")
      ((ok tbl) tbl)
      ((err e) (do (assert false (str "tableWithRetry text must parse: " e)) (emptyTable)))))

fn testProviderWideQuotaSkipsRetry -> Bool
  (let [(cx (testCtx (some (tableWithRetry 2))))
        (a (testAttempt "openrouter" "{}"))
        (step (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list) "You exceeded your quota: insufficient_quota"))]
    (do
      (assert (= (opOf step) "breaker") "a provider-wide quota 429 never asks the clock: it goes straight to the breaker-trip finish path")
      (assert (= (opOf (feedDone step)) "usageNote") "...then records the outcome on the usage ledger, unchanged")
      true))

fn testUnrecognisedStatusSkipsRetry -> Bool
  (let [(cx (testCtx (some (tableWithRetry 2))))
        (a (testAttempt "openrouter" "{}"))
        (step (ch/httpFailed cx (testLoop) a 500 "Internal Server Error" (list) "boom"))]
    (do
      (assert (= (opOf step) "breaker") "a 500 is outside the retry set even when :retry is configured: straight to the old finish path")
      (assert (= (opOf (feedDone step)) "usageNote") "...then records the outcome on the usage ledger, unchanged")
      true))

fn testTransientRetriggersSameRequest -> Bool
  (let [(tbl (tableWithRetry 1))
        (cx (testCtx (some tbl)))
        (a (testAttempt "openrouter" "{\"model\":\"m1\"}"))
        (step0 (ch/httpAttempt cx (testLoop) a))]
    (do
      (assert (= (opOf step0) "http") "httpAttempt's first effect is the outgoing http call")
      (let [(firstUrl (text (fieldOf step0 "url")))
            (firstData (text (fieldOf step0 "data")))
            (step1 (feedHttp step0 (ch/httpError 429 "Too Many Requests" (list) "Upstream model provider is temporarily unavailable")))]
        (do
          (assert (= (opOf step1) "clock") "a transient 429 asks the clock before doing anything else (no breaker event yet)")
          (let [(step2 (feedFloat step1 100.0))]
            (do
              (assert (= (opOf step2) "log") "within the deadline, it logs the retry attempt next")
              (let [(step3 (feedDone step2))]
                (do
                  (assert (= (opOf step3) "usageNote") "then records the retry attempt on the usage ledger")
                  (assert (stringContains? (text (fieldOf step3 "outcome")) "retry") "the retry's usage outcome is tagged distinctly from a plain failure")
                  (let [(step4 (feedDone step3))]
                    (do
                      (assert (= (opOf step4) "sleepMs") "then it sleeps for the computed backoff before the next attempt")
                      (let [(step5 (feedDone step4))]
                        (do
                          (assert (= (opOf step5) "http") "after sleeping it calls httpAttempt again: same model, same payload")
                          (assert (= (text (fieldOf step5 "url")) firstUrl) "the retried call targets the exact same url")
                          (assert (= (text (fieldOf step5 "data")) firstData) "the retried call carries the exact same request body")
                          (let [(step6 (feedHttp step5 (ch/httpOk 200 (list) "{\"choices\": [{\"message\": {\"role\": \"assistant\", \"content\": \"(:ok)\"}}]}")))]
                            (do
                              (assert (not (= (opOf step6) "sleepMs")) "a second failure would not be scripted here; success on retry stops asking for more sleeps")
                              true))))))))))))))

fn testDeadlineExceededAbortsRetry -> Bool
  (let [(tbl (tableWithRetry 3))
        (cx (testCtx (some tbl)))
        (a (with (testAttempt "openrouter" "{}") :retryUsed 1 :retryDeadline (some 100.0)))
        (step0 (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list) "Upstream model provider is temporarily unavailable"))]
    (do
      (assert (= (opOf step0) "clock") "it still has to ask the clock to find out whether the deadline already passed")
      (let [(step1 (feedFloat step0 150.0))]
        (do
          (assert (= (opOf step1) "breaker") "now (150.0) is past the stored deadline (100.0): it aborts straight to the finish path, no sleep")
          true))))

fn testTransportRetryClassification -> Bool
  (let [(cx (testCtx (some (tableWithRetry 1))))
        (a (testAttempt "openrouter" "{}"))
        (stepRetry (ch/raised cx (testLoop) a false "curl exit 56: Recv failure: Connection reset by peer"))
        (stepFinal (ch/raised cx (testLoop) a false "curl exit 3: URL malformed"))]
    (do
      (assert (= (opOf stepRetry) "clock") "a connection-reset transport failure asks the clock to consider a retry")
      (assert (= (opOf stepFinal) "breaker") "an unrelated curl exit code goes straight to the finish path, not through the clock")
      true))

; (:m :tags (retry) :do "GW-FREE-RETRY-3: a real Retry-After header (carried in now via u/UpstreamResponse/u/httpFailure's :headers field, not dropped) overrides the jittered exponential window with the exact server-requested wait; this is the deterministic companion to retryConcurrencyTest.asl's live-process check, controlling now exactly instead of racing the wall clock")
fn testRetryAfterHeaderSetsExactWait -> Bool
  (let [(tbl (tableWithRetry 1))
        (cx (testCtx (some tbl)))
        (a (testAttempt "openrouter" "{}"))
        (step0 (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list (pair "Retry-After" "3")) "Upstream model provider is temporarily unavailable"))]
    (do
      (assert (= (opOf step0) "clock") "a transient 429 with a Retry-After header still asks the clock first, same shape as without one")
      (let [(step1 (feedFloat step0 100.0))
            (step2 (feedDone step1))
            (step3 (feedDone step2))]
        (do
          (assert (= (opOf step1) "log") "logs the retry attempt next")
          (assert (= (opOf step2) "usageNote") "then records the retry attempt on the usage ledger")
          (assert (= (opOf step3) "sleepMs") "then sleeps for the Retry-After-driven wait before the next attempt")
          (match (fieldOf step3 "ms")
            ((j/jint ms) (do
                           (assert (= ms 3000) (str "Retry-After: 3 becomes exactly a 3000 ms parked wait, got " ms))
                           (assert (< ms 20000) (str "the parked wait (" ms " ms) still stays under capMs (20000 ms)"))))
            (_ (assert false "effSleepMs must carry an integer ms field")))
          true))))

; (:m :tags (retry) :do "the RFC 7231 HTTP-date form of Retry-After (vs. the delta-seconds form above): 2026-01-01T00:00:10Z is 1767225610.0 epoch seconds (checked against python's datetime for this exact value); now is fed as exactly 3 seconds before that, so the header resolves to the same 3000 ms wait as a literal Retry-After: 3 would")
fn testRetryAfterHttpDateFormResolvesAgainstNow -> Bool
  (let [(tbl (tableWithRetry 1))
        (cx (testCtx (some tbl)))
        (a (testAttempt "openrouter" "{}"))
        (step0 (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list (pair "Retry-After" "Thu, 01 Jan 2026 00:00:10 GMT")) "Upstream model provider is temporarily unavailable"))]
    (do
      (assert (= (opOf step0) "clock") "an HTTP-date Retry-After still asks the clock first, same shape as delta-seconds")
      (let [(step1 (feedFloat step0 1767225607.0))
            (step2 (feedDone step1))
            (step3 (feedDone step2))]
        (do
          (assert (= (opOf step3) "sleepMs") "resolves to a sleep, same as the delta-seconds form")
          (match (fieldOf step3 "ms")
            ((j/jint ms) (assert (= ms 3000) (str "the HTTP-date form 3 seconds ahead of now becomes a 3000 ms wait, got " ms)))
            (_ (assert false "effSleepMs must carry an integer ms field")))
          true))))

; (:m :tags (retry) :do "RFC 9110 IMF-fixdate is GMT only: a Retry-After date in another zone (PST) is no hint, so it does not become the 3000 ms wait the same instant gives in GMT")
fn testRetryAfterNonGmtDateIsNoHint -> Bool
  (let [(tbl (tableWithRetry 1))
        (cx (testCtx (some tbl)))
        (a (testAttempt "openrouter" "{}"))
        (step0 (ch/httpFailed cx (testLoop) a 429 "Too Many Requests" (list (pair "Retry-After" "Thu, 01 Jan 2026 00:00:10 PST")) "Upstream model provider is temporarily unavailable"))]
    (do
      (assert (= (opOf step0) "clock") "a non-GMT Retry-After still asks the clock first")
      (let [(step1 (feedFloat step0 1767225607.0))
            (step2 (feedDone step1))
            (step3 (feedDone step2))]
        (do
          (match (fieldOf step3 "ms")
            ((j/jint ms) (assert (not (= ms 3000)) (str "a PST date is no Retry-After hint, so it is not the 3000 ms wait: got " ms)))
            (_ (assert false "effSleepMs must carry an integer ms field")))
          true))))

fn ! runTests -> Bool
  (do
    (assert (testTransientTextClassification) "testTransientTextClassification passed")
    (assert (testProviderWideQuotaClassification) "testProviderWideQuotaClassification passed")
    (assert (testRetryableHttpStatus) "testRetryableHttpStatus passed")
    (assert (testParseCurlExitCode) "testParseCurlExitCode passed")
    (assert (testRetryableRaised) "testRetryableRaised passed")
    (assert (testRetryDelayMs) "testRetryDelayMs passed")
    (assert (testRetryParseAndPrecedence) "testRetryParseAndPrecedence passed")
    (assert (testFirstByteSecParseAndPrecedence) "testFirstByteSecParseAndPrecedence passed")
    (assert (testMalformedRetryIsRejected) "testMalformedRetryIsRejected passed")
    (assert (testConfigAbsentKeepsOldBehaviour) "testConfigAbsentKeepsOldBehaviour passed")
    (assert (testProviderWideQuotaSkipsRetry) "testProviderWideQuotaSkipsRetry passed")
    (assert (testUnrecognisedStatusSkipsRetry) "testUnrecognisedStatusSkipsRetry passed")
    (assert (testTransientRetriggersSameRequest) "testTransientRetriggersSameRequest passed")
    (assert (testDeadlineExceededAbortsRetry) "testDeadlineExceededAbortsRetry passed")
    (assert (testTransportRetryClassification) "testTransportRetryClassification passed")
    (assert (testRetryAfterHeaderSetsExactWait) "testRetryAfterHeaderSetsExactWait passed")
    (assert (testRetryAfterHttpDateFormResolvesAgainstNow) "testRetryAfterHttpDateFormResolvesAgainstNow passed")
    (assert (testRetryAfterNonGmtDateIsNoHint) "testRetryAfterNonGmtDateIsNoHint passed")
    true)
