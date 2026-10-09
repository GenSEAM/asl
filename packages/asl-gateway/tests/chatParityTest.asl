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
  (mt (stringIndexOf line ":id \"")
    ((none) "")
    ((some i)
     (let [(rest (u/slice line (+ i 5) (stringLength line)))]
       (mt (stringIndexOf rest "\"") ((some k) (u/slice rest 0 k)) ((none) "")))))

fn ioText line: String -> String
  (mt (stringIndexOf line ":io \"")
    ((none) "")
    ((some i) (unescape (u/slice line (+ i 5) (- (stringLength line) 2)))))

(schema Case
  (:f id String)
  (:f io j/Json))

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn text v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn items v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn num v: j/Json -> Float64
  (mt v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) ((j/jnum f) f) (_ 0.0))

fn int v: j/Json -> Int64
  (mt v ((j/jint i) i) (_ 0))

fn flag v: j/Json -> Bool
  (mt v ((j/jbool b) b) (_ false))

fn pairs v: j/Json -> (List (Pair String String))
  (map (fn [(p j/Json)] -> (Pair String String) (pair (text (optionOr (listGet (items p) 0) (j/jnull))) (text (optionOr (listGet (items p) 1) (j/jnull)))))
       (items v))

fn envOf v: j/Json -> (Map String String)
  (mt v
    ((j/jobj kvs) (fold (fn [(m (Map String String)) (p (Pair String j/Json))] -> (Map String String) (mapSet m (pairFirst p) (text (pairSecond p)))) (mapEmpty) kvs))
    (_ (mapEmpty)))

fn parseLine line: String -> (Option Case)
  (mt (pt/jsonLoads (ioText line))
    ((ok io) (some (Case :id (idOf line) :io io)))
    ((err _) none))

fn worldOf! io: j/Json -> (Result ch/ChatWorld String)
  (let [(env (envOf (get io "env")))
        (config (get io "config"))
        (path (str (text (get io "home")) "/.asl/gateway.asn"))
        (exists (mt config ((j/jstr _) true) (_ false)))
        (builtin (mt config ((j/jstr _) "") (_ (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/builtinConfig/gateway.asn") ""))))
        (table (if exists
                 (c/gatewayProfilesLoadText! path true (ok (text config)) (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))
                 (c/gatewayProfilesLoadText! "builtin" true (ok builtin) (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))))
        (maxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000))]
    (mt (u/upstreamSettings env)
      ((err e) (err e))
      ((ok st) (ok (ch/ChatWorld :env env :rootDir (optionOr (mapGet env "ROOT_DIR") "") :settings st :agyPromptMaxBytes maxBytes :table table)))))

fn requestOf io: j/Json -> ch/ChatRequest
  (let [(r (get io "request"))]
    (ch/ChatRequest :path (text (get r "path")) :headers (pairs (get r "headers")) :body (text (get r "body"))))

fn cliOf v: j/Json -> (Option ch/CliReply)
  (mt v
    ((j/jobj _)
     (some (ch/CliReply :text (text (get v "text")) :usage (get v "usage") :dedup (flag (get v "dedup"))
                        :queueWaitSec (num (get v "queueWaitSec")) :execSec (num (get v "execSec")) :pool (text (get v "pool")))))
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
  (mt step
    ((ch/stepEffect eff k)
     (mt (listHead trace)
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
  (mt (worldOf! c.io)
    ((err e) (Verdict :id c.id :traceOk false :responseOk false :effects 0 :detail (str "world: " e)))
    ((ok world)
     (replay c.id (ch/chatStart! (requestOf c.io) world) (items (get c.io "trace")) 0 (get c.io "response"))))

fn transportEffect step: ch/ChatStep remaining: Int64 -> (Option j/Json)
  (if (<= remaining 0) none
    (mt step
      ((ch/stepEffect eff k)
       (let [(effectJson (ch/effectJson eff))
             (op (text (get effectJson "op")))]
         (if (or (= op "http") (= op "poolHttp")) (some effectJson)
           (mt eff
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
    (mt (u/upstreamSettings env)
      ((err _) none)
      ((ok settings) (some (ch/ChatWorld :env env :rootDir "/" :settings settings :agyPromptMaxBytes 10000 :table table)))))

fn ! transportEffectJson world: ch/ChatWorld -> (Option j/Json)
  (let [(request (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                  :body "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"))]
    (transportEffect (ch/chatStart! request world) 40))

fn ! transportOp world: ch/ChatWorld -> String
  (mt (transportEffectJson world)
    ((none) "no-transport")
    ((some effect) (text (get effect "op"))))

fn ! configuredPoolEffect -> j/Json
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\" :pool (:windowMs 50 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 200))) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (mt (testChatWorld configText env)
      ((none) (j/jnull))
      ((some world) (optionOr (transportEffectJson world) (j/jnull)))))

fn ! configuredPoolTransportOp -> String
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\" :pool (:windowMs 50 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 200))) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (mt (testChatWorld configText env)
      ((none) "world-error")
      ((some world) (transportOp world))))

fn ! directTransportOp -> String
  (let [(configText "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")
        (env (mapSet (mapEmpty) "TEST_KEY" "test-key"))]
    (mt (testChatWorld configText env)
      ((none) "world-error")
      ((some world) (transportOp world))))

fn statusOf c: Case -> String
  (let [(r (get c.io "response"))
        (hs (filter (fn [(h j/Json)] -> Bool (= (text (optionOr (listGet (items h) 0) (j/jnull))) ":status")) (items (get r "head"))))]
    (mt (listHead hs)
      ((some h) (text (optionOr (listGet (items h) 1) (j/jnull))))
      ((none) (str "raises " (text (get r "raises"))))))

fn statusesOf cases: (List Case) -> (List String)
  (fold (fn [(acc (List String)) (c Case)] -> (List String) (if (listContains? acc (statusOf c)) acc (cons (statusOf c) acc)))
        (list) cases)

fn ! runTests -> Bool
  (let [(src (mt (fileReadString (fixturePath)) ((ok t) t) ((err _) "")))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit src "\n")))
        (cases (fold (fn [(acc (List Case)) (l String)] -> (List Case) (mt (parseLine l) ((some c) (listAppend acc (list c))) ((none) acc))) (list) lines))
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
      true))
