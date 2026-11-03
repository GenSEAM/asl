(module aslGateway/tests/chatParityTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (pyText :a pt)
      (asl-json/json :a j)])

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/chatParityFixture.asn"

fn unescapeLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (u/joinAll (listReverse (cons (u/slice s start n) acc))))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n))
     (unescapeLoop s bs n (+ i 2) (+ i 2) (cons (u/slice s (+ i 1) (+ i 2)) (cons (u/slice s start i) acc))))
    (else (unescapeLoop s bs n (+ i 1) start acc)))

fn unescape s: String -> String
  (let [(bs (stringToBytes s))]
    (unescapeLoop s bs (bytesLength bs) 0 0 (list)))

fn idOf line: String -> String
  (match (stringIndexOf line ":id \"")
    ((none) "")
    ((some i)
     (let [(rest (u/slice line (+ i 5) (stringLength line)))]
       (match (stringIndexOf rest "\"") ((some k) (u/slice rest 0 k)) ((none) "")))))

fn ioText line: String -> String
  (match (stringIndexOf line ":io \"")
    ((none) "")
    ((some i) (unescape (u/slice line (+ i 5) (- (stringLength line) 2)))))

(schema Case
  (:f id String)
  (:f io j/Json))

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn text v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

fn items v: j/Json -> (List j/Json)
  (match v ((j/jarr xs) xs) (_ (list)))

fn num v: j/Json -> Float64
  (match v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) ((j/jnum f) f) (_ 0.0))

fn int v: j/Json -> Int64
  (match v ((j/jint i) i) (_ 0))

fn flag v: j/Json -> Bool
  (match v ((j/jbool b) b) (_ false))

fn pairs v: j/Json -> (List (Pair String String))
  (map (fn [(p j/Json)] -> (Pair String String) (pair (text (optionOr (listGet (items p) 0) (j/jnull))) (text (optionOr (listGet (items p) 1) (j/jnull)))))
       (items v))

fn envOf v: j/Json -> (Map String String)
  (match v
    ((j/jobj kvs) (fold (fn [(m (Map String String)) (p (Pair String j/Json))] -> (Map String String) (mapSet m (pairFirst p) (text (pairSecond p)))) (mapEmpty) kvs))
    (_ (mapEmpty)))

fn parseLine line: String -> (Option Case)
  (match (pt/jsonLoads (ioText line))
    ((ok io) (some (Case :id (idOf line) :io io)))
    ((err _) none))

fn worldOf! io: j/Json -> (Result ch/ChatWorld String)
  (let [(env (envOf (get io "env")))
        (config (get io "config"))
        (path (str (text (get io "home")) "/.asl/gateway.asn"))
        (exists (match config ((j/jstr _) true) (_ false)))
        (builtin (match config ((j/jstr _) "") (_ (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/chatBuiltinConfig/gateway.asn") ""))))
        (table (if exists
                 (c/gatewayProfilesLoadText! path true (ok (text config)) (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))
                 (c/gatewayProfilesLoadText! "builtin" true (ok builtin) (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))))
        (maxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000))]
    (match (u/upstreamSettings env)
      ((err e) (err e))
      ((ok st) (ok (ch/ChatWorld :env env :rootDir (optionOr (mapGet env "ROOT_DIR") "") :settings st :agyPromptMaxBytes maxBytes :table table)))))

fn requestOf io: j/Json -> ch/ChatRequest
  (let [(r (get io "request"))]
    (ch/ChatRequest :path (text (get r "path")) :headers (pairs (get r "headers")) :body (text (get r "body"))))

fn cliOf v: j/Json -> (Option ch/CliReply)
  (match v
    ((j/jobj _)
     (some (ch/CliReply :text (text (get v "text")) :usage (get v "usage") :dedup (flag (get v "dedup"))
                        :queueWaitSec (num (get v "queueWaitSec")) :execSec (num (get v "execSec")) :pool (text (get v "pool")) :binding (j/jnull))))
    (_ none))

fn httpOf v: j/Json -> ch/HttpReply
  (let [(kind (text (get v "kind")))]
    (cond
      ((= kind "ok") (ch/httpOk (int (get v "status")) (pairs (get v "headers")) (text (get v "body"))))
      ((= kind "httpError") (ch/httpError (int (get v "status")) (text (get v "reason")) (pairs (get v "headers")) (text (get v "body"))))
      (else (ch/httpRaised (flag (get v "timeout")) (text (get v "text"))))))

fn outcomeOf op: String v: j/Json -> ch/ChatOutcome
  (cond
    ((= op "realpath") (ch/outPath (text (get v "path"))))
    ((or (= op "isDir") (= op "bucket")) (ch/outBool (flag (get v "bool"))))
    ((or (= op "clock") (= op "breakerDown")) (ch/outFloat (num (get v "float"))))
    ((= op "breakerDownAll") (ch/outFloats (map num (items (get v "floats")))))
    ((= op "cli") (ch/outCli (cliOf v)))
    ((= op "http") (ch/outHttp (httpOf v)))
    (else (ch/outDone)))

fn dump v: j/Json -> String
  (pt/jsonDumps v -1)

(schema Verdict
  (:f id String)
  (:f traceOk Bool)
  (:f responseOk Bool)
  (:f effects Int64)
  (:f detail String))

fn replay id: String step: ch/ChatStep trace: (List j/Json) n: Int64 want: j/Json -> Verdict
  (match step
    ((ch/stepEffect eff k)
     (match (listHead trace)
       ((none) (Verdict :id id :traceOk false :responseOk false :effects n :detail (str "extra effect " (dump (ch/effectJson eff)))))
       ((some rec)
        (let [(got (dump (ch/effectJson eff)))
              (exp (dump (get rec "effect")))]
          (if (= got exp)
            (replay id (k (outcomeOf (text (get (get rec "effect") "op")) (get rec "outcome"))) (optionOr (listTail trace) (list)) (+ n 1) want)
            (Verdict :id id :traceOk false :responseOk false :effects n :detail (str "effect " (stringFromInt64 n) " got " got " want " exp)))))))
    ((ch/stepDone resp)
     (let [(got (dump (j/jobj (list (pair "head" (ch/headJson resp.head)) (pair "body" (j/jstr resp.body))))))
           (exp (dump want))]
       (Verdict :id id :traceOk (listEmpty? trace) :responseOk (= got exp) :effects n
                :detail (if (= got exp) (if (listEmpty? trace) "" (str (stringFromInt64 (listLength trace)) " recorded effects never asked")) (str "response got " got " want " exp)))))
    ((ch/stepRaised kind msg)
     (let [(got (dump (j/jobj (list (pair "raises" (j/jstr kind))))))
           (exp (dump want))]
       (Verdict :id id :traceOk (listEmpty? trace) :responseOk (= got exp) :effects n
                :detail (if (= got exp) (if (listEmpty? trace) "" "recorded effects never asked") (str "raised " kind ": " msg " want " exp))))))

fn judge! c: Case -> Verdict
  (match (worldOf! c.io)
    ((err e) (Verdict :id c.id :traceOk false :responseOk false :effects 0 :detail (str "world: " e)))
    ((ok world)
     (replay c.id (ch/chatStart! (requestOf c.io) world) (items (get c.io "trace")) 0 (get c.io "response"))))

fn transportEffect step: ch/ChatStep remaining: Int64 -> (Option j/Json)
  (if (<= remaining 0) none
    (match step
      ((ch/stepEffect eff k)
       (let [(effectJson (ch/effectJson eff))
             (op (text (get effectJson "op")))]
         (if (or (= op "http") (= op "poolHttp")) (some effectJson)
           (match eff
             ((ch/effRealpath _) (transportEffect (k (ch/outPath "/")) (- remaining 1)))
             ((ch/effIsDir _) (transportEffect (k (ch/outBool true)) (- remaining 1)))
             ((ch/effClock) (transportEffect (k (ch/outFloat 1.0)) (- remaining 1)))
             ((ch/effBreakerDown _) (transportEffect (k (ch/outFloat 0.0)) (- remaining 1)))
             ((ch/effBreakerDownAll _) (transportEffect (k (ch/outFloats (list 0.0))) (- remaining 1)))
             ((ch/effBucket _ _ _) (transportEffect (k (ch/outBool true)) (- remaining 1)))
             ((ch/effCli _ _) (transportEffect (k (ch/outCli none)) (- remaining 1)))
             (_ (transportEffect (k ch/outDone) (- remaining 1)))))))
      ((ch/stepDone resp) none)
      ((ch/stepRaised kind msg) none)))

fn ! testChatWorld configText: String env: (Map String String) -> (Option ch/ChatWorld)
  (let [(table (c/gatewayProfilesLoadText! "/test" true (ok configText) ""))]
    (match (u/upstreamSettings env)
      ((err _) none)
      ((ok settings) (some (ch/ChatWorld :env env :rootDir "/" :settings settings :agyPromptMaxBytes 10000 :table table)))))

fn ! transportEffectJson world: ch/ChatWorld -> (Option j/Json)
  (let [(request (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                  :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"))]
    (transportEffect (ch/chatStart! request world) 40))

fn ! transportOp world: ch/ChatWorld -> String
  (match (transportEffectJson world)
    ((none) "no-transport")
    ((some effect) (text (get effect "op"))))

fn ! configuredPoolEffect -> j/Json
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\" :pool (:windowMs 50 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 200))) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld configText env)
      ((none) (j/jnull))
      ((some world) (optionOr (transportEffectJson world) (j/jnull)))))

fn ! configuredPoolTransportOp -> String
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\" :pool (:windowMs 50 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 200))) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld configText env)
      ((none) "world-error")
      ((some world) (transportOp world))))

fn ! directTransportOp -> String
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld configText env)
      ((none) "world-error")
      ((some world) (transportOp world))))

; (:m :tags (retry) :do "GW-RETRY-OCGO-HANG event proof: a provider configured with both :pool and :retry must route its RETRIED attempt through effHttp, never effPoolHttp again, replacing a timing proxy with a direct assertion on which transport effect the second attempt actually asks for")
fn poolRetryConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\" :retry (:max 2 :baseMs 1 :capMs 2) :pool (:windowMs 50 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 200))) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))"

; (:m like transportEffect, but skips past `skip` transport effects first, answering each with a retryable 503 so the Loop's own retry path drives it to the next attempt, and returns the transport effect actually reached after that)
fn nthTransportEffect step: ch/ChatStep remaining: Int64 skip: Int64 -> (Option j/Json)
  (if (<= remaining 0) none
    (match step
      ((ch/stepEffect eff k)
       (let [(effectJson (ch/effectJson eff))
             (op (text (get effectJson "op")))]
         (if (or (= op "http") (= op "poolHttp"))
           (if (> skip 0)
             (nthTransportEffect (k (ch/outHttp (ch/httpError 503 "Service Unavailable" (list) "{}"))) (- remaining 1) (- skip 1))
             (some effectJson))
           (match eff
             ((ch/effRealpath _) (nthTransportEffect (k (ch/outPath "/")) (- remaining 1) skip))
             ((ch/effIsDir _) (nthTransportEffect (k (ch/outBool true)) (- remaining 1) skip))
             ((ch/effClock) (nthTransportEffect (k (ch/outFloat 1.0)) (- remaining 1) skip))
             ((ch/effBreakerDown _) (nthTransportEffect (k (ch/outFloat 0.0)) (- remaining 1) skip))
             ((ch/effBreakerDownAll _) (nthTransportEffect (k (ch/outFloats (list 0.0))) (- remaining 1) skip))
             ((ch/effBucket _ _ _) (nthTransportEffect (k (ch/outBool true)) (- remaining 1) skip))
             ((ch/effCli _ _) (nthTransportEffect (k (ch/outCli none)) (- remaining 1) skip))
             (_ (nthTransportEffect (k ch/outDone) (- remaining 1) skip))))))
      ((ch/stepDone resp) none)
      ((ch/stepRaised kind msg) none)))

fn ! retriedTransportOp -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (poolRetryConfigText) env)
      ((none) "world-error")
      ((some world)
       (let [(request (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                       :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"))]
         (match (nthTransportEffect (ch/chatStart! request world) 60 1)
           ((none) "no-second-transport")
           ((some effect) (text (get effect "op"))))))))

fn ! firstTransportOpOfRetryConfig -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (poolRetryConfigText) env)
      ((none) "world-error")
      ((some world)
       (let [(request (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                       :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"))]
         (match (nthTransportEffect (ch/chatStart! request world) 60 0)
           ((none) "no-transport")
           ((some effect) (text (get effect "op"))))))))

; (:m OCSESSION-2: queue_timeout is a Leon-internal field, stripped before an openai v2 upstream body)
fn ! queueTimeoutEffect -> j/Json
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))
        (request (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                  :body "{\"model\":\"m\",\"queue_timeout\":1200,\"timeout\":300,\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"))]
    (match (testChatWorld configText env)
      ((none) (j/jnull))
      ((some world) (optionOr (transportEffect (ch/chatStart! request world) 40) (j/jnull)))))

fn ! responsesConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\" :api \"responses\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))"

fn ! responsesRequest -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                  :body "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"be brief\"},{\"role\":\"user\",\"content\":\"hello\"}],\"max_tokens\":256}")

fn ! responsesTransportEffect -> j/Json
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (responsesConfigText) env)
      ((none) (j/jnull))
      ((some world) (optionOr (transportEffect (ch/chatStart! (responsesRequest) world) 40) (j/jnull)))))

fn ! drive! step: ch/ChatStep reply: String remaining: Int64 -> (Option ch/ChatResponse)
  (if (<= remaining 0) none
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ _ _ _ _ _ _ _) (drive! (k (ch/outHttp (ch/httpOk 200 (list) reply))) reply (- remaining 1)))
         ((ch/effPoolHttp _ _ _ _ _ _) (drive! (k (ch/outHttp (ch/httpOk 200 (list) reply))) reply (- remaining 1)))
         ((ch/effRealpath _) (drive! (k (ch/outPath "/")) reply (- remaining 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) reply (- remaining 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) reply (- remaining 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) reply (- remaining 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) reply (- remaining 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) reply (- remaining 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) reply (- remaining 1)))
         (_ (drive! (k ch/outDone) reply (- remaining 1)))))
      ((ch/stepDone resp) (some resp))
      ((ch/stepRaised _ _) none)))

fn ! responsesReplyCheck -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))
        (reply "{\"id\":\"r1\",\"object\":\"response\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"hi there\"}]}],\"usage\":{\"input_tokens\":5,\"output_tokens\":7,\"output_tokens_details\":{\"reasoning_tokens\":2}}}")]
    (match (testChatWorld (responsesConfigText) env)
      ((none) "world-error")
      ((some world)
       (match (drive! (ch/chatStart! (responsesRequest) world) reply 60)
         ((none) "no-response")
         ((some resp) resp.body)))))

; (:m :tags (chat parser reasoning) :do "EMPTYCONTENTFALLBACK: a reasoning-tuned model that answers only into message.reasoning, leaving content empty with finish_reason stop, must be served that text instead of ERR_EMPTY_CONTENT")
fn ! reasoningFallbackConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))"

fn ! reasoningFallbackRequest -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                  :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn ! reasoningOnlyReplyBody -> String
  "{\"id\":\"gen_1\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning\":\"the answer is 42\",\"reasoning_details\":[{\"type\":\"reasoning.text\",\"text\":\"the answer is 42\",\"format\":\"unknown\",\"index\":0}]},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"

fn ! reasoningFallbackCheck -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (reasoningFallbackConfigText) env)
      ((none) "world-error")
      ((some world)
       (match (drive! (ch/chatStart! (reasoningFallbackRequest) world) (reasoningOnlyReplyBody) 60)
         ((none) "no-response")
         ((some resp) resp.body)))))

; (:m :tags (chat parser reasoning) :do "opencodeGo's cat-jam-free: content is JSON null (not an empty string) and the text sits in reasoning_content, a third field spelling beside commandCode's reasoning/reasoning_details")
fn ! reasoningContentOnlyReplyBody -> String
  "{\"id\":\"gen_2\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":null,\"reasoning_content\":\"the answer is 42\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"

fn ! reasoningContentFallbackCheck -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (reasoningFallbackConfigText) env)
      ((none) "world-error")
      ((some world)
       (match (drive! (ch/chatStart! (reasoningFallbackRequest) world) (reasoningContentOnlyReplyBody) 60)
         ((none) "no-response")
         ((some resp) resp.body)))))

; (:m :ref PROTO-STUDY :do "TOOLCALLREPLY: a native tool call answers with content null, tool_calls and, on reasoning models, reasoning_content; the call is the answer, not an empty reply to retry or to replace with the reasoning text")
fn ! toolCallReplyBody -> String
  "{\"id\":\"gen_3\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"finish_reason\":\"tool_calls\",\"message\":{\"role\":\"assistant\",\"content\":null,\"reasoning_content\":\"I will read it\",\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"

fn ! toolCallPlainBody -> String
  (stringReplace (toolCallReplyBody) "\"reasoning_content\":\"I will read it\"," "")

fn ! toolCallReplyCheck body: String -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (reasoningFallbackConfigText) env)
      ((none) "world-error")
      ((some world)
       (match (drive! (ch/chatStart! (reasoningFallbackRequest) world) body 60)
         ((none) "no-response")
         ((some resp) resp.body)))))

; (:m :tags (chat breaker pool) :do "429BREAKERSCOPE: captures effBreakerDown/effBreakerEvent pool keys seen while driving a real cascade, so the markDown/checkDown key choice (per model vs provider-wide) is observed through the public effect API rather than an unexported helper")
fn ! captureBreaker! step: ch/ChatStep downAcc: (List String) eventAcc: (List String) status: Int64 reason: String httpBody: String remaining: Int64 -> (Pair (List String) (List String))
  (if (<= remaining 0)
    (pair (listReverse downAcc) (listReverse eventAcc))
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effBreakerDown p) (captureBreaker! (k (ch/outFloat 0.0)) (cons p downAcc) eventAcc status reason httpBody (- remaining 1)))
         ((ch/effBreakerEvent e p _) (captureBreaker! (k ch/outDone) downAcc (cons (str e ":" p) eventAcc) status reason httpBody (- remaining 1)))
         ((ch/effHttp _ _ _ _ _ _ _ _) (captureBreaker! (k (ch/outHttp (ch/httpError status reason (list) httpBody))) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effPoolHttp _ _ _ _ _ _) (captureBreaker! (k (ch/outHttp (ch/httpError status reason (list) httpBody))) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effRealpath _) (captureBreaker! (k (ch/outPath "/")) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effIsDir _) (captureBreaker! (k (ch/outBool true)) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effClock) (captureBreaker! (k (ch/outFloat 1.0)) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effBreakerDownAll _) (captureBreaker! (k (ch/outFloats (list 0.0))) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effBucket _ _ _) (captureBreaker! (k (ch/outBool true)) downAcc eventAcc status reason httpBody (- remaining 1)))
         ((ch/effCli _ _) (captureBreaker! (k (ch/outCli none)) downAcc eventAcc status reason httpBody (- remaining 1)))
         (_ (captureBreaker! (k ch/outDone) downAcc eventAcc status reason httpBody (- remaining 1)))))
      ((ch/stepDone _) (pair (listReverse downAcc) (listReverse eventAcc)))
      ((ch/stepRaised _ _) (pair (listReverse downAcc) (listReverse eventAcc)))))

fn ! twoModelCascadeConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m1 :provider test :name \"model-1\") (:model :id m2 :provider test :name \"model-2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))"

fn ! oneModelConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m1 :provider test :name \"model-1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))"

fn ! profileRoutedRequest -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Intent" "any"))
                  :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")

fn ! breakerCapture! configText: String status: Int64 reason: String httpBody: String -> (Pair (List String) (List String))
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld configText env)
      ((none) (pair (list) (list)))
      ((some world) (captureBreaker! (ch/chatStart! (profileRoutedRequest) world) (list) (list) status reason httpBody 120))))

fn ! plainRateLimitEvents -> (List String)
  (pairSecond (breakerCapture! (twoModelCascadeConfigText) 429 "Too Many Requests" "{\"error\":{\"message\":\"rate limited, slow down\"}}"))

fn ! unauthorizedEvents -> (List String)
  (pairSecond (breakerCapture! (oneModelConfigText) 401 "Unauthorized" "{\"error\":{\"message\":\"invalid api key\"}}"))

fn ! providerWideQuotaEvents -> (List String)
  (pairSecond (breakerCapture! (oneModelConfigText) 429 "Too Many Requests" "{\"error\":{\"message\":\"insufficient_quota: account is out of credit\"}}"))

; (:m :ref GW-BREAKER-STALE-20261018 :tags (chat breaker pool) :do "the real incident's shape: a non-429 status (503, matching Gemini's own transport) whose body carries RESOURCE_EXHAUSTED, which breakerIsQuotaError already recognises regardless of status code -- this must mark down only the failing model's own pool, never the bare provider pool, so a quota-exhausted model never blocks a healthy sibling on the same provider")
fn ! resourceExhaustedEvents -> (List String)
  (pairSecond (breakerCapture! (twoModelCascadeConfigText) 503 "Service Unavailable" "{\"error\":{\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"quota exceeded\"}}"))

fn statusOf c: Case -> String
  (let [(r (get c.io "response"))
        (hs (filter (fn [(h j/Json)] -> Bool (= (text (optionOr (listGet (items h) 0) (j/jnull))) ":status")) (items (get r "head"))))]
    (match (listHead hs)
      ((some h) (text (optionOr (listGet (items h) 1) (j/jnull))))
      ((none) (str "raises " (text (get r "raises"))))))

fn statusesOf cases: (List Case) -> (List String)
  (fold (fn [(acc (List String)) (c Case)] -> (List String) (if (listContains? acc (statusOf c)) acc (cons (statusOf c) acc)))
        (list) cases)

; (:m :tags (chat) :do "hand-written (not pinned to any python corpus) coverage for GW-SPREAD-LIVE-20261018: no corpus profile has a :spread, so cascadeChosen's effSpreadOrder ask is otherwise never exercised against a real cascade -- this drives chatStart! directly against the real public effect API, matching captureBreaker!'s own precedent in this file")
fn ! spreadConfigText -> String
  "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m1 :provider test :name \"model-1\") (:model :id m2 :provider test :name \"model-2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2) :spread ((m1 1) (m2 1)))))) :uses ((:use :for default :profile default)))"

; (:m :do "answers the one effSpreadOrder a spread-configured cascade asks with answerOrder, every other effect with the same defaults transportEffect uses, and returns the model actually dispatched (from the real effHttp effect's own model field, never JSON) or a diagnostic string if the step ends another way")
fn ! spreadDrive! step: ch/ChatStep answerOrder: (List String) remaining: Int64 -> String
  (if (<= remaining 0) "timeout"
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effSpreadOrder _ _ _ _ _) (spreadDrive! (k (ch/outStrings answerOrder)) answerOrder (- remaining 1)))
         ((ch/effHttp _ model _ _ _ _ _ _) model)
         ((ch/effRealpath _) (spreadDrive! (k (ch/outPath "/")) answerOrder (- remaining 1)))
         ((ch/effIsDir _) (spreadDrive! (k (ch/outBool true)) answerOrder (- remaining 1)))
         ((ch/effClock) (spreadDrive! (k (ch/outFloat 1.0)) answerOrder (- remaining 1)))
         ((ch/effBreakerDown _) (spreadDrive! (k (ch/outFloat 0.0)) answerOrder (- remaining 1)))
         ((ch/effBreakerDownAll _) (spreadDrive! (k (ch/outFloats (list 0.0))) answerOrder (- remaining 1)))
         ((ch/effBucket _ _ _) (spreadDrive! (k (ch/outBool true)) answerOrder (- remaining 1)))
         ((ch/effCli _ _) (spreadDrive! (k (ch/outCli none)) answerOrder (- remaining 1)))
         (_ (spreadDrive! (k ch/outDone) answerOrder (- remaining 1)))))
      ((ch/stepDone _) "done-no-transport")
      ((ch/stepRaised kind msg) (str "raised " kind ": " msg))))

fn ! spreadDispatchedModel! answerOrder: (List String) -> String
  (let [(env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (match (testChatWorld (spreadConfigText) env)
      ((none) "world-error")
      ((some world) (spreadDrive! (ch/chatStart! (profileRoutedRequest) world) answerOrder 60))))

fn ! runTests -> Bool
  (let [(src (match (fileReadString (fixturePath)) ((ok t) t) ((err _) "")))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit src "\n")))
        (cases (fold (fn [(acc (List Case)) (l String)] -> (List Case) (match (parseLine l) ((some c) (listAppend acc (list c))) ((none) acc))) (list) lines))
        (verdicts (map judge! cases))
        (bad (filter (fn [(v Verdict)] -> Bool (not (and v.traceOk v.responseOk))) verdicts))
        (effects (fold (fn [(acc Int64) (v Verdict)] -> Int64 (+ acc v.effects)) 0 verdicts))
        (statuses (statusesOf cases))]
    (do
      (map (fn [(v Verdict)] -> Bool (do (eprintln (str "FAIL " v.id ": " v.detail)) true)) bad)
      (eprintln (str "(:chatParity :cases " (stringFromInt64 (listLength cases)) " :failed " (stringFromInt64 (listLength bad))
                     " :effects " (stringFromInt64 effects) " :outcomes " (stringFromInt64 (listLength statuses)) ")"))
      (assert (not (stringEmpty? src)) "fixture file is readable")
      (assert (= (listLength cases) (listLength lines)) "every fixture line parses as JSON")
      (assert (= (listLength cases) 65) "fixture holds the 65 recorded cases")
      (assert (>= (listLength statuses) 11) "cases end in at least 11 distinct statuses or raised exceptions")
      (map (fn [(v Verdict)] -> Bool (do (assert v.traceOk (str v.id ": effects equal the recorded trace")) true)) verdicts)
      (map (fn [(v Verdict)] -> Bool (do (assert v.responseOk (str v.id ": response head and body byte-equal")) true)) verdicts)
      (assert (> effects 400) "the replay crosses more than 400 recorded effects")
      (assert (= (configuredPoolTransportOp) "poolHttp") (str "configured pool effect: " (configuredPoolTransportOp)))
      (assert (= (text (get (configuredPoolEffect) "provider")) "test") "pool transport carries the configured provider identity")
      (assert (= (text (get (configuredPoolEffect) "model")) "model-m") "pool transport carries the resolved upstream model")
      (assert (= (text (get (configuredPoolEffect) "url")) "https://example.test/v1/chat/completions") "pool transport preserves the upstream HTTP URL")
      (assert (stringContains? (text (get (configuredPoolEffect) "data")) "hello") "pool transport carries the chat request body")
      (assert (= (directTransportOp) "http") (str "unpooled provider effect: " (directTransportOp)))
      (assert (= (firstTransportOpOfRetryConfig) "poolHttp") (str "GW-RETRY-OCGO-HANG: a provider with both :pool and :retry still pools its FIRST attempt: " (firstTransportOpOfRetryConfig)))
      (assert (= (retriedTransportOp) "http") (str "GW-RETRY-OCGO-HANG: a retried attempt on a :pool provider must ask for effHttp, never effPoolHttp again (a retry is not a batch sibling): " (retriedTransportOp)))
      (assert (= (text (get (queueTimeoutEffect) "op")) "http") (str "OCSESSION-2: queue_timeout body reaches an http transport: " (text (get (queueTimeoutEffect) "op"))))
      (assert (not (stringContains? (text (get (queueTimeoutEffect) "data")) "queue_timeout")) "OCSESSION-2: queue_timeout is stripped from the v2 openai upstream body")
      (assert (not (stringContains? (text (get (queueTimeoutEffect) "data")) "\"timeout\"")) "OCSESSION-2: timeout stays stripped from the v2 openai upstream body")
      (assert (stringContains? (text (get (queueTimeoutEffect) "data")) "\"messages\"") "OCSESSION-2: messages still reach the v2 openai upstream body")
      (assert (= (text (get (responsesTransportEffect) "op")) "http") (str "RESPAPI: responses entry reaches an http transport: " (text (get (responsesTransportEffect) "op"))))
      (assert (stringEndsWith? (text (get (responsesTransportEffect) "url")) "/responses") (str "RESPAPI: upstream path ends with /responses: " (text (get (responsesTransportEffect) "url"))))
      (assert (stringContains? (text (get (responsesTransportEffect) "data")) "\"input\"") "RESPAPI: upstream body carries input")
      (assert (stringContains? (text (get (responsesTransportEffect) "data")) "\"instructions\"") "RESPAPI: system message becomes instructions")
      (assert (not (stringContains? (text (get (responsesTransportEffect) "data")) "\"messages\"")) "RESPAPI: upstream body has no messages")
      (assert (stringContains? (text (get (responsesTransportEffect) "data")) "\"max_output_tokens\"") "RESPAPI: max_tokens becomes max_output_tokens")
      (let [(parsed (pt/jsonLoads (responsesReplyCheck)))]
        (match parsed
          ((err _) (assert false "RESPAPI: converted reply did not parse"))
          ((ok v)
            (let [(choices (get v "choices"))
                  (first (optionOr (listHead (items choices)) (j/jnull)))
                  (msg (get first "message"))]
              (assert (= (text (get msg "content")) "hi there") (str "RESPAPI: client sees output_text as chat content: " (text (get msg "content"))))
              (assert (= (int (get (get v "usage") "prompt_tokens")) 5) "RESPAPI: input_tokens maps to prompt_tokens")
              (assert (= (int (get (get v "usage") "completion_tokens")) 7) "RESPAPI: output_tokens maps to completion_tokens")))))
      (let [(raw (reasoningFallbackCheck))
            (parsed (pt/jsonLoads raw))]
        (match parsed
          ((err _) (assert false (str "EMPTYCONTENTFALLBACK: response did not parse as a chat completion: " raw)))
          ((ok v)
            (let [(choices (get v "choices"))
                  (first (optionOr (listHead (items choices)) (j/jnull)))
                  (msg (get first "message"))]
              (assert (= (text (get msg "content")) "the answer is 42")
                      (str "EMPTYCONTENTFALLBACK: empty content falls back to message.reasoning: " (text (get msg "content"))))))))
      (let [(raw2 (reasoningContentFallbackCheck))
            (parsed2 (pt/jsonLoads raw2))]
        (match parsed2
          ((err _) (assert false (str "EMPTYCONTENTFALLBACK2: response did not parse as a chat completion: " raw2)))
          ((ok v)
            (let [(choices (get v "choices"))
                  (first (optionOr (listHead (items choices)) (j/jnull)))
                  (msg (get first "message"))]
              (assert (= (text (get msg "content")) "the answer is 42")
                      (str "EMPTYCONTENTFALLBACK2: null content falls back to message.reasoning_content: " (text (get msg "content"))))))))
      (let [(raw3 (toolCallReplyCheck (toolCallPlainBody)))
            (raw4 (toolCallReplyCheck (toolCallReplyBody)))
            (content4 (match (pt/jsonLoads raw4)
                        ((ok v) (get (get (optionOr (listHead (items (get v "choices"))) (j/jnull)) "message") "content"))
                        ((err _) (j/jstr "unparsed"))))]
        (assert (stringContains? raw3 "tool_calls") (str "TOOLCALLREPLY: a tool call with null content reaches the client: " raw3))
        (refute (stringContains? raw3 "ERR_EMPTY_CONTENT") "TOOLCALLREPLY: a tool call is not an empty reply")
        (assert (stringContains? raw4 "tool_calls") (str "TOOLCALLREPLY: a reasoning model's tool call reaches the client: " raw4))
        (refute (= content4 (j/jstr "I will read it")) "TOOLCALLREPLY: the reasoning text does not become the content of a tool-call reply"))
      (let [(rl (plainRateLimitEvents))]
        (assert (= (listLength rl) 2) (str "BREAKERSCOPE: a two-model cascade on plain 429 marks down once per model: " (stringFromInt64 (listLength rl))))
        (assert (listContains? rl "note429:test:m1") "BREAKERSCOPE: model m1 429 cools its own pool test:m1 (GW-429-WINDOW-WAIT note429)")
        (assert (listContains? rl "note429:test:m2") "BREAKERSCOPE: model m2 429 cools its own pool test:m2")
        (refute (or (listContains? rl "markDown:test") (listContains? rl "note429:test")) "BREAKERSCOPE: a plain per-model 429 never trips the bare provider pool"))
      (let [(ue (unauthorizedEvents))]
        (assert (listContains? ue "markDown:test") "BREAKERSCOPE: 401 trips the whole provider pool, not a per-model one")
        (refute (listContains? ue "markDown:test:m1") "BREAKERSCOPE: 401 does not use the per-model pool key"))
      (let [(pe (providerWideQuotaEvents))]
        (assert (listContains? pe "markDown:test") "BREAKERSCOPE: an insufficient_quota/account marker trips the whole provider pool even on a 429")
        (refute (listContains? pe "markDown:test:m1") "BREAKERSCOPE: a provider-wide quota marker does not use the per-model pool key"))
      (let [(re (resourceExhaustedEvents))]
        (assert (= (listLength re) 2) (str "GW-BREAKER-STALE-20261018: a two-model cascade on a 503 RESOURCE_EXHAUSTED body marks down once per model: " (stringFromInt64 (listLength re))))
        (assert (listContains? re "note429:test:m1") "GW-BREAKER-STALE-20261018: model m1 RESOURCE_EXHAUSTED 503 cools its own pool test:m1 as a quota (GW-429-WINDOW-WAIT note429), matching the real Gemini incident shape")
        (assert (listContains? re "note429:test:m2") "GW-BREAKER-STALE-20261018: model m2 RESOURCE_EXHAUSTED 503 cools its own pool test:m2")
        (refute (listContains? re "markDown:test") "GW-BREAKER-STALE-20261018: a quota-marker 503 never trips the bare provider pool, regardless of status code"))
      (assert (= (spreadDispatchedModel! (list "m1" "m2")) "model-1") "SPREADLIVE: the server's natural-order answer dispatches model-1 first, same as the plain :chain")
      (assert (= (spreadDispatchedModel! (list "m2" "m1")) "model-2") "SPREADLIVE: cascadeChosen must dispatch whatever the server's effSpreadOrder answer names first, not the config's own :chain order -- this is the one assertion that would fail if startLoop forgot to reorder")
      true))
