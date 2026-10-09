(module aslGateway/tests/upstreamParityTest
  :x [runTests]
  :i [(upstream :a u)
      (usage :a g)
      (wire :a w)
      (asl-json/json :a j)])

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/upstreamParityFixtures.asn"

fn fixtureKeys -> (List String)
  (list "fixture-openrouter-key-7Q2" "fixture-openai-key-4M8" "fixture-gemini-key-9Z1" "fixture-groq-key-3K5" "fixture-ollama-key-6P0" "fixture-llmgw-key-2W4")

fn unescapeLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (u/joinAll (listReverse (cons (u/slice s start n) acc))))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n))
     (unescapeLoop s bs n (+ i 2) (+ i 2) (cons (u/slice s (+ i 1) (+ i 2)) (cons (u/slice s start i) acc))))
    (else (unescapeLoop s bs n (+ i 1) start acc)))

fn unescape s: String -> String
  (let [(bs (stringToBytes s))]
    (unescapeLoop s bs (bytesLength bs) 0 0 (list)))

fn quotedAfter line: String key: String -> String
  (mt (stringIndexOf line (str key " \""))
    ((none) "")
    ((some i)
     (let [(start (+ i (stringLength key) 2))
           (rest (u/slice line start (stringLength line)))]
       (mt (stringIndexOf rest "\"")
         ((some k) (u/slice rest 0 k))
         ((none) "")))))

fn ioText line: String -> String
  (mt (stringIndexOf line ":io \"")
    ((none) "")
    ((some i) (unescape (u/slice line (+ i 5) (- (stringLength line) 2)))))

(schema Case
  (:f id String)
  (:f fn String)
  (:f args j/Json)
  (:f want j/Json))

fn parseCase line: String -> (Result Case String)
  (mt (j/jsonParse (ioText line))
    ((err e) (err (str "fixture line does not parse: " e)))
    ((ok io) (ok (Case :id (quotedAfter line ":id") :fn (quotedAfter line ":fn")
                       :args (optionOr (j/jsonGet io "args") (j/jnull)) :want (optionOr (j/jsonGet io "want") (j/jnull))))))

fn jget v: j/Json k: String -> j/Json
  (optionOr (j/jsonGet v k) (j/jnull))

fn has? v: j/Json k: String -> Bool
  (some? (j/jsonGet v k))

fn jstrOf v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn optStr v: j/Json -> (Option String)
  (mt v ((j/jstr s) (some s)) (_ none))

fn numF v: j/Json -> Float64
  (mt v
    ((j/jint i) (int64ToFloat64 i))
    ((j/jfloat f) f)
    ((j/jnum f) f)
    (_ 0.0))

fn numI v: j/Json -> Int64
  (mt v
    ((j/jint i) i)
    ((j/jfloat f) (optionOr (float64ToInt64 f) 0))
    ((j/jnum f) (optionOr (float64ToInt64 f) 0))
    (_ 0))

fn jlist v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn jpairs v: j/Json -> (List (Pair String j/Json))
  (mt v ((j/jobj kvs) kvs) (_ (list)))

fn envOf v: j/Json -> (Map String String)
  (fold (fn [(m (Map String String)) (p (Pair String j/Json))] -> (Map String String) (mapSet m (pairFirst p) (jstrOf (pairSecond p))))
        (mapEmpty) (jpairs v))

fn headerPairs v: j/Json -> (List (Pair String String))
  (map (fn [(h j/Json)] -> (Pair String String) (pair (jstrOf (optionOr (listGet (jlist h) 0) (j/jnull))) (jstrOf (optionOr (listGet (jlist h) 1) (j/jnull)))))
       (jlist v))

fn floatEq? x: Float64 b: j/Json -> Bool
  (mt b
    ((j/jfloat y) (or (= x y) (and (isNan? x) (isNan? y))))
    ((j/jnum y) (or (= x y) (and (isNan? x) (isNan? y))))
    (_ false))

fn listEq? xs: (List j/Json) ys: (List j/Json) -> Bool
  (mt (listHead xs)
    ((none) (listEmpty? ys))
    ((some x)
     (mt (listHead ys)
       ((none) false)
       ((some y) (and (jsonEq? x y) (listEq? (optionOr (listTail xs) (list)) (optionOr (listTail ys) (list))))))))

fn pairsEq? xs: (List (Pair String j/Json)) ys: (List (Pair String j/Json)) -> Bool
  (mt (listHead xs)
    ((none) (listEmpty? ys))
    ((some x)
     (mt (listHead ys)
       ((none) false)
       ((some y) (and (= (pairFirst x) (pairFirst y))
                      (and (jsonEq? (pairSecond x) (pairSecond y)) (pairsEq? (optionOr (listTail xs) (list)) (optionOr (listTail ys) (list)))))))))

fn jsonEq? a: j/Json b: j/Json -> Bool
  (mt a
    ((j/jint x) (mt b ((j/jint y) (= x y)) (_ false)))
    ((j/jfloat x) (floatEq? x b))
    ((j/jnum x) (floatEq? x b))
    ((j/jarr xs) (mt b ((j/jarr ys) (listEq? xs ys)) (_ false)))
    ((j/jobj xs) (mt b ((j/jobj ys) (pairsEq? xs ys)) (_ false)))
    (_ (= a b)))

fn errName e: String -> String
  (mt (stringIndexOf e ":") ((some i) (u/slice e 0 i)) ((none) e))

fn okJ v: j/Json -> j/Json
  (j/jobj (list (pair "ok" v)))

fn raisesJ e: String -> j/Json
  (j/jobj (list (pair "raises" (j/jstr (errName e)))))

fn strJ s: String -> j/Json
  (j/jstr s)

fn optJ v: (Option String) -> j/Json
  (mt v ((some s) (j/jstr s)) ((none) (j/jnull)))

fn strList xs: (List String) -> j/Json
  (j/jarr (map strJ xs))

fn intList xs: (List Int64) -> j/Json
  (j/jarr (map (fn [(i Int64)] -> j/Json (j/jint i)) xs))

fn settingsJ st: u/UpstreamSettings -> j/Json
  (j/jobj (list (pair "GEMINI_URL" (strJ st.geminiUrl)) (pair "GEMINI_KEY" (strJ st.geminiKey)) (pair "GROQ_URL" (strJ st.groqUrl))
                (pair "OLLAMA_URL" (strJ st.ollamaUrl)) (pair "GROQ_KEY" (strJ st.groqKey)) (pair "URL" (strJ st.url))
                (pair "KEY" (strJ st.key)) (pair "ollamaTimeoutSec" (j/jfloat st.ollamaTimeoutSec))))

fn endpointJ e: u/UpstreamEndpoint -> j/Json
  (j/jobj (list (pair "provider" (strJ e.provider)) (pair "url" (strJ e.url)) (pair "key" (strJ e.key))))

fn policyJ p: u/RoleTokenPolicy -> j/Json
  (j/jobj (list (pair "mode" (strJ p.mode)) (pair "floorIfReasoning" (j/jint p.floorIfReasoning)) (pair "hardCap" (j/jint p.hardCap))))

fn fullUrl r: u/UpstreamRequest -> String
  (if (stringEmpty? r.fragment) r.url (str r.url "#" r.fragment))

fn requestJ r: u/UpstreamRequest -> j/Json
  (j/jobj (list (pair "fullUrl" (strJ (fullUrl r))) (pair "method" (strJ r.method))
                (pair "headers" (j/jarr (map (fn [(h (Pair String String))] -> j/Json (strList (list (pairFirst h) (pairSecond h)))) r.headers)))
                (pair "data" (strJ r.data))))

fn resultJ r: (Result j/Json String) -> j/Json
  (mt r ((ok v) (okJ v)) ((err e) (raisesJ e)))

fn settingsOf env: (Map String String) -> (Result u/UpstreamSettings String)
  (u/upstreamSettings env)

fn routeCase a: j/Json -> j/Json
  (let [(env (envOf (jget a "env")))]
    (mt (settingsOf env)
      ((err e) (raisesJ e))
      ((ok st) (okJ (endpointJ (u/getUpstreamForModel st env (optStr (jget a "model"))))))))

fn timeoutCase a: j/Json -> j/Json
  (mt (settingsOf (envOf (jget a "env")))
    ((err e) (raisesJ e))
    ((ok st) (okJ (j/jfloat (u/upstreamTimeoutSec st (jstrOf (jget a "provider")))))))

fn bucketJ b: u/TokenBucket acquired: Bool slept: j/Json -> j/Json
  (j/jobj (list (pair "acquired" (j/jbool acquired)) (pair "slept" slept) (pair "tokens" (j/jfloat b.tokens)) (pair "lastUpdate" (j/jfloat b.lastUpdate))))

fn bucketRaiseJ b: u/TokenBucket e: String -> j/Json
  (j/jobj (list (pair "raises" (strJ (errName e))) (pair "tokens" (j/jfloat b.tokens)) (pair "lastUpdate" (j/jfloat b.lastUpdate))))

fn bucketOp b: u/TokenBucket now: Float64 timeout: Float64 extra: Float64 -> (Pair u/TokenBucket (Result (Pair Bool j/Json) String))
  (let [(step (u/tokenBucketBegin b timeout now))
        (b1 (pairFirst step))]
    (mt (pairSecond step)
      ((err e) (pair b1 (err e)))
      ((ok s)
       (mt s
         ((u/bucketAcquired) (pair b1 (ok (pair true (j/jnull)))))
         ((u/bucketRefused) (pair b1 (ok (pair false (j/jnull)))))
         ((u/bucketWait secs)
          (let [(done (u/tokenBucketFinish b1 (+ now (+ secs extra))))]
            (pair (pairFirst done) (ok (pair (pairSecond done) (j/jfloat secs))))))))))

fn bucketLoop b: u/TokenBucket ops: (List j/Json) acc: (List j/Json) -> (List j/Json)
  (mt (listHead ops)
    ((none) (listReverse acc))
    ((some op)
     (let [(r (bucketOp b (numF (jget op "now")) (numF (jget op "timeout")) (numF (jget op "extra"))))
           (b2 (pairFirst r))
           (row (mt (pairSecond r)
                  ((err e) (bucketRaiseJ b2 e))
                  ((ok p) (bucketJ b2 (pairFirst p) (pairSecond p)))))]
       (bucketLoop b2 (optionOr (listTail ops) (list)) (cons row acc)))))

fn bucketCase a: j/Json -> j/Json
  (j/jarr (bucketLoop (u/makeTokenBucket (numF (jget a "rate")) (numF (jget a "capacity")) (numF (jget a "t0"))) (jlist (jget a "ops")) (list)))

fn registryLoop reg: u/BucketRegistry ops: (List j/Json) acc: (List j/Json) -> (List j/Json)
  (mt (listHead ops)
    ((none) (listReverse acc))
    ((some op)
     (let [(model (jstrOf (jget op "model")))
           (rpm (numF (jget op "rpm")))
           (now (numF (jget op "now")))
           (got (u/geminiBucket reg model rpm now))
           (r (bucketOp (pairSecond got) now (numF (jget op "timeout")) 0.0))
           (reg2 (u/bucketRegistryPut (pairFirst got) model rpm (pairFirst r)))
           (size (j/jint (u/bucketRegistrySize reg2)))
           (b (pairFirst r))
           (row (mt (pairSecond r)
                  ((err e) (j/jobj (list (pair "raises" (strJ (errName e))) (pair "size" size))))
                  ((ok p) (j/jobj (list (pair "acquired" (j/jbool (pairFirst p))) (pair "slept" (pairSecond p)) (pair "rate" (j/jfloat b.rate))
                                        (pair "tokens" (j/jfloat b.tokens)) (pair "lastUpdate" (j/jfloat b.lastUpdate)) (pair "size" size))))))]
       (registryLoop reg2 (optionOr (listTail ops) (list)) (cons row acc)))))

fn policyCase a: j/Json -> j/Json
  (okJ (mt (u/roleTokenPolicy (optStr (jget a "role"))) ((some p) (policyJ p)) ((none) (j/jnull))))

fn requestCase a: j/Json -> j/Json
  (mt (u/upstreamRequest (jstrOf (jget a "url")) (jstrOf (jget a "path")) (jstrOf (jget a "key")) (jstrOf (jget a "data")) (headerPairs (jget a "clientHeaders")))
    ((err e) (raisesJ e))
    ((ok r) (okJ (requestJ r))))

fn tablesCase -> j/Json
  (let [(modes (list "scout" "plan" "implement" "grade" "orchestrate"))]
    (j/jobj (list (pair "reasoningModels" (strList (listSort (u/reasoningModels)))) (pair "coderCascade" (strList (u/coderCascade)))
                  (pair "plannerCascade" (strList (u/plannerCascade))) (pair "tokenFloorRoles" (strList (listSort (u/tokenFloorRoles))))
                  (pair "minTokenFloor" (j/jint (u/minTokenFloor)))
                  (pair "modelTokenFloors" (j/jarr (map (fn [(p (Pair String Int64))] -> j/Json (j/jarr (list (strJ (pairFirst p)) (j/jint (pairSecond p))))) (u/modelTokenFloors))))
                  (pair "replyCeilings" (j/jobj (map (fn [(m String)] -> (Pair String j/Json) (pair m (j/jint (optionOr (u/replyCeiling m) -1)))) modes)))
                  (pair "roleTokenPolicy" (j/jobj (map (fn [(p (Pair String u/RoleTokenPolicy))] -> (Pair String j/Json) (pair (pairFirst p) (policyJ (pairSecond p)))) (u/roleTokenPolicyTable))))
                  (pair "emptyContentRetries" (j/jint (u/emptyContentRetries))) (pair "harness" (strJ (u/aslMinimalHarness)))
                  (pair "wordRanges" (intList (g/wordRanges))) (pair "digitRanges" (intList (u/unicodeDigitRanges)))
                  (pair "spaceRanges" (intList (u/unicodeSpaceRanges))) (pair "nfkcBadNetloc" (intList (g/nfkcBadNetloc))))))

fn telemetryCase a: j/Json -> j/Json
  (optJ (g/analyzeTelemetry (jget a "content") (optStr (jget a "intent")) (optStr (jget a "role")) (optStr (jget a "model")) (optStr (jget a "workspace"))
                            (jstrOf (jget a "rootDir")) (numI (jget a "nowMs"))))

fn gatewayUpdateCase a: j/Json want: j/Json -> j/Json
  (let [(disk (jstrOf (jget a "disk")))
        (flag (= (jget a "diskValid") (j/jbool true)))
        (expectCall (not (listEmpty? (jlist (jget want "diskValidCalls")))))
        (st (g/gatewayUpdateStatus (numI (jget a "pid")) (jstrOf (jget a "version")) disk (numI (jget a "inFlight")) (= (jget a "draining") (j/jbool true))
                                   (numI (jget a "updates")) (jstrOf (jget a "updatedFrom"))
                                   (fn [(d String)] -> Bool (if (and expectCall (= d disk)) flag (not flag)))))]
    (j/jobj (list (pair "status" (g/gatewayStatusJson st)) (pair "asn" (strJ (g/gatewayUpdateAsn st))) (pair "diskValidCalls" (jget want "diskValidCalls")))))

fn pureGot c: Case -> (Option j/Json)
  (let [(a c.args)
        (f c.fn)]
    (cond
      ((= f "upstreamSettings") (some (mt (settingsOf (envOf (jget a "env"))) ((ok st) (okJ (settingsJ st))) ((err e) (raisesJ e)))))
      ((= f "getUpstreamForModel") (some (routeCase a)))
      ((= f "upstreamTimeoutSec") (some (timeoutCase a)))
      ((= f "tokenBucket") (some (bucketCase a)))
      ((= f "geminiRegistry") (some (j/jarr (registryLoop (u/emptyBucketRegistry) (jlist (jget a "ops")) (list)))))
      ((= f "roleTokenPolicy") (some (policyCase a)))
      ((= f "emptyContentAction") (some (strJ (u/emptyContentAction (numI (jget a "cascadeLen")) (numI (jget a "retriesDone"))))))
      ((= f "isEmptyContent") (some (j/jbool (u/isEmptyContent? (jget a "content")))))
      ((= f "prepareRequestPayload") (some (resultJ (u/prepareRequestPayload (jget a "payload") (optStr (jget a "role"))))))
      ((= f "applyHarnessPolicy") (some (resultJ (u/applyHarnessPolicy (jget a "payload") (jstrOf (jget a "mode")) (optStr (jget a "role"))))))
      ((= f "harnessMode") (some (okJ (strJ (u/harnessMode (headerPairs (jget a "headers")) (envOf (jget a "env")))))))
      ((= f "upstreamRequest") (some (requestCase a)))
      ((= f "usageTokens") (some (intList (g/usageTokens (jget a "usage")))))
      ((= f "usageHttpError") (some (strJ (g/usageHttpError (numI (jget a "code"))))))
      ((= f "usageException") (some (strJ (g/usageException (u/transportFailure (numI (jget a "curlExit")) "")))))
      ((= f "analyzeTelemetry") (some (telemetryCase a)))
      ((= f "telemetryLogPath") (some (strJ (g/telemetryLogPath (envOf (jget a "env")) (jstrOf (jget a "cwd")) (jstrOf (jget a "script"))))))
      ((= f "cleanUrl") (some (strJ (g/cleanUrl (jstrOf (jget a "url"))))))
      ((= f "gatewayUpdate") (some (gatewayUpdateCase a c.want)))
      ((= f "tables") (some (tablesCase)))
      (else none)))

fn ! runArgv! argv: (List String) env: (Option (List String)) -> (Result (Pair Int64 String) String)
  (mt (procSpawnv argv none env)
    ((err e) (err (str (optionOr (listHead argv) "?") ": " e)))
    ((ok sp)
     (let [(c (fdClose sp.stdin))
           (out (readAll! sp.stdout (list)))
           (errText (readAll! sp.stderr (list)))
           (c2 (fdClose sp.stdout))
           (c3 (fdClose sp.stderr))]
       (mt (procWaitPid sp.pid false)
         ((err e) (err (str "wait: " e)))
         ((ok st) (ok (pair (optionOr st -1) out)))))))

fn ! readAll! fd: Int64 acc: (List String) -> String
  (mt (fdRead fd 1048576)
    ((err _) (u/joinAll (listReverse acc)))
    ((ok chunk) (if (stringEmpty? chunk) (u/joinAll (listReverse acc)) (readAll! fd (cons chunk acc)))))

fn trimSlash s: String -> String
  (if (and (stringEndsWith? s "/") (> (stringLength s) 1)) (trimSlash (u/slice s 0 (- (stringLength s) 1))) s)

fn ! makeTmp! -> String
  (let [(root (trimSlash (optionOr (envGet "TMPDIR") "/tmp")))
        (dir (str root "/aslU8test-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate dir))]
    dir)

fn ! writeB64! path: String b64: String -> Bool
  (mt (bytesFromBase64 b64)
    ((ok bs) (ok? (fileWrite path bs)))
    ((err _) false))

fn ! readOr! path: String -> String
  (resultOr (fileReadString path) "")

fn stateAppend r: j/Json extra: (List (Pair String j/Json)) -> j/Json
  (j/jobj (listAppend (jpairs r) extra))

fn noteResult res: (Pair j/Json (Option String)) -> j/Json
  (mt (pairSecond res) ((some e) (raisesJ e)) ((none) (okJ (j/jnull))))

fn callsHave? calls: (List j/Json) head: String -> Bool
  (listAny? (fn [(c j/Json)] -> Bool (= (optionOr (listGet (jlist c) 0) (j/jnull)) (j/jstr head))) calls)

fn dispatchCall calls: (List j/Json) -> (List j/Json)
  (jlist (optionOr (listHead (filter (fn [(c j/Json)] -> Bool (= (optionOr (listGet (jlist c) 0) (j/jnull)) (j/jstr "dispatch"))) calls)) (j/jarr (list))))

fn agyOp state: j/Json op: j/Json calls: (List j/Json) -> (Pair j/Json j/Json)
  (let [(breakerExpected (callsHave? calls "breaker"))
        (dcall (dispatchCall calls))
        (dispatchExpected (callsHave? calls "dispatch"))
        (down (numI (jget op "breakerDown")))
        (res (g/usageAgyFallback state (jstrOf (jget op "prompt")) (optStr (jget op "workspace"))
                                 (fn [(p String)] -> Int64 (if (and breakerExpected (= p "agy")) down 777))
                                 (fn [(p String) (ws (Option String))] -> j/Json
                                   (if (and dispatchExpected (and (= (j/jstr p) (optionOr (listGet dcall 1) (j/jnull))) (= (optJ ws) (optionOr (listGet dcall 2) (j/jnull)))))
                                     (jget op "dispatch")
                                     (j/jobj (list (pair "text" (j/jstr "UNEXPECTED-CALL"))))))
                                 (numF (jget op "now"))))]
    (pair (pairFirst res) (resultJ (pairSecond res))))

fn ! seqOp! state: j/Json op: j/Json path: String want: j/Json -> (Pair j/Json j/Json)
  (let [(kind (jstrOf (jget op "op")))
        (now (numF (jget op "now")))]
    (cond
      ((= kind "note")
       (let [(r (g/usageNote state (optStr (jget op "provider")) (optStr (jget op "alias")) (jstrOf (jget op "outcome")) (jget op "usage") now))]
         (pair (pairFirst r) (stateAppend (noteResult r) (list (pair "state" (pairFirst r)))))))
      ((= kind "fallback")
       (let [(r (g/usageFallback state (optStr (jget op "provider")) (optStr (jget op "alias"))))]
         (pair (pairFirst r) (stateAppend (noteResult r) (list (pair "state" (pairFirst r)))))))
      ((= kind "asn")
       (pair state (stateAppend (mt (g/usageAsn state) ((ok s) (okJ (strJ s))) ((err e) (raisesJ e))) (list (pair "state" state)))))
      ((= kind "restore")
       (let [(prep (mt (jget op "file")
                     ((j/jstr b) (writeB64! path b))
                     (_ (do (pathRemove path) true))))
             (r (g/usageRestore! path state))
             (left (fileExists? path))]
         (pair (pairFirst r) (stateAppend (okJ (j/jnull)) (list (pair "fileLeft" (j/jbool left)) (pair "state" (pairFirst r)))))))
      ((= kind "agy")
       (let [(r (agyOp state op (jlist (jget want "calls"))))]
         (pair (pairFirst r) (stateAppend (pairSecond r) (list (pair "state" (pairFirst r)))))))
      (else (pair state (j/jobj (list (pair "unknownOp" (strJ kind))))))))

fn dropCalls v: j/Json -> j/Json
  (j/jobj (filter (fn [(p (Pair String j/Json))] -> Bool (not (= (pairFirst p) "calls"))) (jpairs v)))

fn ! seqLoop! state: j/Json ops: (List j/Json) wants: (List j/Json) path: String acc: (List j/Json) -> (List j/Json)
  (mt (listHead ops)
    ((none) (listReverse acc))
    ((some op)
     (let [(want (optionOr (listHead wants) (j/jnull)))
           (r (seqOp! state op path want))]
       (seqLoop! (pairFirst r) (optionOr (listTail ops) (list)) (optionOr (listTail wants) (list)) path (cons (pairSecond r) acc)))))

fn ! usageSequenceCase! c: Case tmp: String -> (Pair j/Json j/Json)
  (let [(a c.args)
        (got (seqLoop! (g/usageInit (numF (jget a "since"))) (jlist (jget a "ops")) (jlist c.want) (str tmp "/usage-" c.id ".usage") (list)))]
    (pair (j/jarr got) (j/jarr (map dropCalls (jlist c.want)))))

fn ! logCase! c: Case tmp: String -> (Pair j/Json j/Json)
  (let [(a c.args)
        (base (str tmp "/tel-" c.id))
        (made (dirCreate base))
        (blocked (= (jget a "parentIsFile") (j/jbool true)))
        (occupy (if blocked (ok? (fileWrite (str base "/log") "occupied")) true))
        (path (str base "/log/deep/mesh.asnl"))
        (results (map (fn [(r j/Json)] -> (Pair Bool (Result Bool String)) (pair (not (stringEmpty? (jstrOf r))) (g/logTelemetryEvent! path (optStr r))))
                      (jlist (jget a "records"))))
        (errorsSurface (listAll? (fn [(p (Pair Bool (Result Bool String)))] -> Bool (if (and blocked (pairFirst p)) (err? (pairSecond p)) (ok? (pairSecond p)))) results))
        (file (mt (fileReadString path) ((ok t) (strJ t)) ((err _) (j/jnull))))]
    (pair (j/jobj (list (pair "file" file) (pair "errorsSurface" (j/jbool errorsSurface))))
          (j/jobj (list (pair "file" (jget c.want "file")) (pair "errorsSurface" (j/jbool true))))))

fn sortedPairs m: (Map String String) -> j/Json
  (j/jobj (map (fn [(p (Pair String String))] -> (Pair String j/Json) (pair (pairFirst p) (strJ (pairSecond p)))) (mapPairs m)))

fn ! placeRc! home: String name: String spec: j/Json -> Bool
  (let [(path (str home "/" name))]
    (mt spec
      ((j/jstr s) (if (= s "dir") (ok? (dirCreate path)) (writeB64! path s)))
      (_ true)))

fn ! zshCase! c: Case tmp: String -> (Pair j/Json j/Json)
  (let [(a c.args)
        (home (str tmp "/home-" c.id))
        (made (dirCreate home))
        (p1 (placeRc! home ".zshenv" (jget a "zshenv")))
        (p2 (placeRc! home ".zshrc" (jget a "zshrc")))
        (unreadable (map jstrOf (jlist (jget a "unreadable"))))
        (locked (map (fn [(n String)] -> Bool (ok? (runArgv! (list "/bin/chmod" "000" (str home "/" n)) none))) unreadable))
        (env (mapSet (envOf (jget a "env")) "HOME" home))
        (r (g/loadZshEnv! env))
        (errorsSurface (= (listEmpty? unreadable) (listEmpty? (pairSecond r))))
        (restored (map (fn [(n String)] -> Bool (ok? (runArgv! (list "/bin/chmod" "600" (str home "/" n)) none))) unreadable))]
    (pair (j/jobj (list (pair "env" (sortedPairs (mapRemove (pairFirst r) "HOME"))) (pair "errorsSurface" (j/jbool errorsSurface))))
          (j/jobj (list (pair "env" (sortedPairs (envOf c.want))) (pair "errorsSurface" (j/jbool true))))))

fn ! fileVersionCase! c: Case tmp: String -> (Pair j/Json j/Json)
  (let [(a c.args)
        (kind (jstrOf (jget a "kind")))
        (path (str tmp "/gwfile-" c.id))
        (prep (cond
                ((= kind "file") (writeB64! path (jstrOf (jget a "content"))))
                ((= kind "dir") (ok? (dirCreate path)))
                (else true)))
        (got (g/gatewayFileVersion! (if (= kind "empty") "" path)))]
    (pair (strJ got) c.want))

fn keyFree? text: String -> Bool
  (not (listAny? (fn [(k String)] -> Bool (stringContains? text k)) (fixtureKeys)))

fn stubScript dir: String -> String
  (str "#!/bin/sh\nd='" dir "'\nprintf '%s\\n' \"$@\" > \"$d/argv\"\nenv > \"$d/env\"\ncat > \"$d/stdin\"\ncat \"$d/out\"\ncat \"$d/err\" 1>&2\nexit \"$(cat \"$d/code\")\"\n")

fn ! installStub! dir: String -> Bool
  (and (ok? (dirCreate dir))
       (and (ok? (fileWrite (str dir "/curl") (stubScript dir)))
            (mt (runArgv! (list "/bin/chmod" "755" (str dir "/curl")) none) ((ok p) (= (pairFirst p) 0)) ((err _) false))))

fn stubEnv dir: String tmp: String -> (Map String String)
  (mapFromPairs (list (pair "PATH" (str dir ":/usr/bin:/bin")) (pair "TMPDIR" tmp) (pair "HOME" tmp)
                      (pair "OPENROUTER_API_KEY" "fixture-openrouter-key-7Q2") (pair "OPENAI_API_KEY" "fixture-openai-key-4M8")
                      (pair "GEMINI_API_KEY" "fixture-gemini-key-9Z1") (pair "GROQ_API_KEY" "fixture-groq-key-3K5")
                      (pair "OLLAMA_API_KEY" "fixture-ollama-key-6P0") (pair "LLM_GATEWAY_API_KEY" "fixture-llmgw-key-2W4")))

fn outcomeJ r: (Result u/UpstreamResponse u/UpstreamFailure) -> j/Json
  (mt r
    ((ok resp) (j/jobj (list (pair "body" (strJ resp.body)))))
    ((err f)
     (mt f
       ((u/httpFailure status reason body)
        (j/jobj (list (pair "status" (j/jint status)) (pair "usage" (strJ (g/usageHttpError status)))
                      (pair "reason" (strJ (w/upstreamErrorReason body (u/httpErrorText status reason)))))))
       ((u/transportFailure code errText) (j/jobj (list (pair "usage" (strJ (g/usageException f))))))
       ((u/toolAbsent tool detail) (j/jobj (list (pair "toolAbsent" (strJ detail)))))
       ((u/protocolFailure detail) (j/jobj (list (pair "protocolFailure" (strJ detail))))))))

fn testQuote s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t")

fn configHas? cfg: String name: String value: String -> Bool
  (stringContains? cfg (str name " = \"" (testQuote value) "\"\n"))

fn firstWord line: String -> String
  (let [(t (stringTrim line))
        (sp (fold (fn [(best Int64) (c String)] -> Int64 (mt (stringIndexOf t c) ((some i) (if (< i best) i best)) ((none) best))) (stringLength t) (list " " "=" "\t")))]
    (u/slice t 0 sp))

fn forbiddenFree? cfg: String -> Bool
  (not (listAny? (fn [(l String)] -> Bool (listContains? (list "insecure" "--insecure" "-k" "proxy-insecure" "--proxy-insecure" "location" "--location" "-L" "location-trusted" "--location-trusted") (firstWord l)))
                 (stringLines cfg)))

fn transportOk? req: u/UpstreamRequest key: String argv: String env: String cfg: String -> Bool
  (and (= argv "-q\n--config\n-\n")
       (and (keyFree? argv)
            (and (keyFree? env)
                 (and (if (stringEmpty? key) (not (stringContains? cfg "Authorization")) (configHas? cfg "header" (str "Authorization: Bearer " key)))
                      (and (configHas? cfg "url" req.url)
                           (and (configHas? cfg "data-raw" req.data)
                                (and (stringContains? cfg "header = \"Connection: close\"\n")
                                     (and (stringContains? cfg "proto = \"=http,https\"\n")
                                          (and (forbiddenFree? cfg)
                                               (listAll? (fn [(h (Pair String String))] -> Bool
                                                           (or (= (pairFirst h) "Connection") (configHas? cfg "header" (str (pairFirst h) ": " (pairSecond h)))))
                                                         req.headers))))))))))

fn ! resetStub! dir: String code: String out: String -> Bool
  (do
    (pathRemove (str dir "/stdin"))
    (pathRemove (str dir "/argv"))
    (pathRemove (str dir "/env"))
    (and (ok? (fileWrite (str dir "/out") out)) (and (ok? (fileWrite (str dir "/err") "")) (ok? (fileWrite (str dir "/code") code)))))

fn ! literalConfig! dir: String tmp: String -> Bool
  (let [(reset (resetStub! dir "0" "HTTP/1.1 200 OK\r\n\r\nok"))
        (key "k\"q\\z\\")
        (res (mt (u/upstreamRequest "https://h.example/v1" "/chat" key "l1\nl2 \"q\" \\ end\\" (list (pair "X-Q" "a\"b\\c\\")))
               ((ok req) (u/callUpstream! req (stubEnv dir tmp) 45.0))
               ((err e) (err (u/protocolFailure e)))))
        (cfg (readOr! (str dir "/stdin")))
        (argv (readOr! (str dir "/argv")))
        (env (readOr! (str dir "/env")))]
    (and reset
         (and (ok? res)
              (and (stringContains? cfg "url = \"https://h.example/v1/chat\"\n")
                   (and (stringContains? cfg "proto = \"=http,https\"\n")
                        (and (stringContains? cfg "header = \"X-q: a\\\"b\\\\c\\\\\"\n")
                             (and (stringContains? cfg "header = \"Authorization: Bearer k\\\"q\\\\z\\\\\"\n")
                                  (and (stringContains? cfg "data-raw = \"l1\\nl2 \\\"q\\\" \\\\ end\\\\\"\n")
                                       (and (forbiddenFree? cfg) (and (not (stringContains? argv "k\"q")) (not (stringContains? env "k\"q"))))))))))))

fn ! rejected! dir: String tmp: String url: String key: String headers: (List (Pair String String)) secret: String -> Bool
  (let [(reset (resetStub! dir "0" "HTTP/1.1 200 OK\r\n\r\nok"))
        (res (mt (u/upstreamRequest url "/chat" key "{}" headers)
               ((ok req) (u/callUpstream! req (stubEnv dir tmp) 45.0))
               ((err e) (err (u/protocolFailure e)))))]
    (and reset
         (and (mt res
                ((err f) (mt f ((u/protocolFailure d) (and (stringStartsWith? d "ValueError") (not (stringContains? d secret)))) (_ false)))
                ((ok _) false))
              (not (fileExists? (str dir "/stdin"))))))

fn ! badNamesRejected! dir: String tmp: String -> Bool
  (let [(secretFile (str tmp "/secretHeaders"))
        (w (fileWrite secretFile "X-Leak: SECRET-FILE-CONTENT\n"))]
    (listAll? (fn [(n String)] -> Bool (rejected! dir tmp "https://h.example/v1" "" (list (pair n "v")) "SECRET"))
              (list (str "@" secretFile) "@/etc/hosts" "X Y" "A:B" "" "X\u{e9}")))

fn ! lineBreaksRejected! dir: String tmp: String -> Bool
  (and (rejected! dir tmp "https://h.example/v1" "abc\nKEY-SECRET-1" (list) "KEY-SECRET-1")
       (and (rejected! dir tmp "https://h.example/v1" "abc\rKEY-SECRET-2" (list) "KEY-SECRET-2")
            (and (rejected! dir tmp "https://h.example/v1" "" (list (pair "X-A" "v\r\nInjected: VAL-SECRET")) "VAL-SECRET")
                 (and (rejected! dir tmp "https://h.example/v1" "" (list (pair "X-A\nInjected" "v")) "Injected")
                      (rejected! dir tmp "https://h.example/v1 x" "" (list) "SECRET")))))

fn ! redirectIsError! dir: String tmp: String -> Bool
  (let [(reset (resetStub! dir "0" "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:9/elsewhere\r\n\r\nmoved"))
        (res (mt (u/upstreamRequest "https://h.example/v1" "/chat" "" "{}" (list))
               ((ok req) (u/callUpstream! req (stubEnv dir tmp) 45.0))
               ((err e) (err (u/protocolFailure e)))))]
    (and reset (mt res ((err f) (mt f ((u/httpFailure status _ body) (and (= status 302) (= body "moved"))) (_ false))) ((ok _) false))))

fn ! stubCase! c: Case dir: String tmp: String -> (Pair j/Json j/Json)
  (let [(a c.args)
        (curl (jget a "curl"))
        (key (jstrOf (jget a "key")))
        (w1 (fileWrite (str dir "/out") (jstrOf (jget curl "stdout"))))
        (w2 (fileWrite (str dir "/err") (jstrOf (jget curl "stderr"))))
        (w3 (fileWrite (str dir "/code") (stringFromInt64 (numI (jget curl "exit")))))
        (reqRes (u/upstreamRequest (jstrOf (jget a "url")) (jstrOf (jget a "path")) key (jstrOf (jget a "data")) (headerPairs (jget a "clientHeaders"))))]
    (mt reqRes
      ((err e) (pair (raisesJ e) c.want))
      ((ok req)
       (let [(out (u/callUpstream! req (stubEnv dir tmp) 45.0))
             (transport (transportOk? req key (readOr! (str dir "/argv")) (readOr! (str dir "/env")) (readOr! (str dir "/stdin"))))]
         (pair (j/jobj (list (pair "request" (requestJ req)) (pair "outcome" (outcomeJ out)) (pair "transport" (j/jbool transport))))
               (j/jobj (list (pair "request" (jget c.want "request")) (pair "outcome" (jget c.want "outcome")) (pair "transport" (j/jbool true)))))))))

(schema Ctx
  (:f tmp String)
  (:f stub String))

fn ! effectGot! c: Case ctx: Ctx -> (Option (Pair j/Json j/Json))
  (let [(f c.fn)]
    (cond
      ((= f "usageSequence") (some (usageSequenceCase! c ctx.tmp)))
      ((= f "logTelemetryEvent") (some (logCase! c ctx.tmp)))
      ((= f "loadZshEnv") (some (zshCase! c ctx.tmp)))
      ((= f "gatewayFileVersion") (some (fileVersionCase! c ctx.tmp)))
      ((= f "callUpstream") (some (stubCase! c ctx.stub ctx.tmp)))
      (else none)))

fn ! judge! c: Case ctx: Ctx -> Bool
  (let [(gw (mt (pureGot c)
              ((some got) (some (pair got c.want)))
              ((none) (effectGot! c ctx))))]
    (mt gw
      ((none) (do (eprintln (str "(:case " c.id " :unknownFn " c.fn ")")) false))
      ((some p)
       (if (jsonEq? (pairFirst p) (pairSecond p))
         true
         (do (eprintln (str "(:case " c.id " :fn " c.fn "\n  :got " (j/jsonEmit (pairFirst p)) "\n  :want " (j/jsonEmit (pairSecond p)) ")")) false)))))

fn caseLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringLines text))

fn ! judgeAll! cases: (List Case) ctx: Ctx acc: (List (Pair String Bool)) -> (List (Pair String Bool))
  (mt (listHead cases)
    ((none) (listReverse acc))
    ((some c) (judgeAll! (optionOr (listTail cases) (list)) ctx (cons (pair c.id (judge! c ctx)) acc))))

fn ! assertAll! rs: (List (Pair String Bool)) -> Bool
  (mt (listHead rs)
    ((none) true)
    ((some r) (do (assert (pairSecond r) (str "fixture case " (pairFirst r) " matches the Python original")) (assertAll! (optionOr (listTail rs) (list))))))

fn parsedCases lines: (List String) -> (List (Result Case String))
  (map parseCase lines)

fn okCases rs: (List (Result Case String)) -> (List Case)
  (fold (fn [(acc (List Case)) (r (Result Case String))] -> (List Case) (mt r ((ok c) (cons c acc)) ((err _) acc))) (list) (listReverse rs))

fn doubled s: String k: Int64 -> String
  (if (<= k 0) s (doubled (stringConcat s s) (- k 1)))

fn ! stubFirst? dir: String -> Bool
  (mt (runArgv! (list "/bin/sh" "-c" "command -v curl") (some (list (str "PATH=" dir ":/usr/bin:/bin"))))
    ((ok p) (= (pairSecond p) (str dir "/curl\n")))
    ((err _) false))

fn ! missingCurl! tmp: String -> Bool
  (let [(empty (str tmp "/emptyPath"))
        (made (dirCreate empty))]
    (mt (u/upstreamRequest "https://h.example/v1" "/chat" "" "{}" (list))
      ((err _) false)
      ((ok req)
       (mt (u/callUpstream! req (mapFromPairs (list (pair "PATH" empty))) 5.0)
         ((err f) (mt f ((u/toolAbsent tool _) (= tool "curl")) (_ false)))
         ((ok _) false)))))

fn ! largeTransfer! dir: String tmp: String -> (Pair Bool Int64)
  (let [(body (doubled "0123456789abcdef" 17))
        (reply (doubled "(:ok 0123456789)" 16))
        (w1 (fileWrite (str dir "/out") (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" reply)))
        (w2 (fileWrite (str dir "/err") ""))
        (w3 (fileWrite (str dir "/code") "0"))
        (t0 (monotonicNs))
        (res (mt (u/upstreamRequest "https://h.example/v1" "/chat" "fixture-openrouter-key-7Q2" body (list))
               ((ok req) (u/callUpstream! req (stubEnv dir tmp) 45.0))
               ((err e) (err (u/protocolFailure e)))))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (sent (resultOr (fileSize (str dir "/stdin")) 0))]
    (pair (and (mt res ((ok r) (= r.body reply)) ((err _) false)) (> sent (stringLength body))) ms))

fn ! largeTelemetry! -> (Pair Bool Int64)
  (let [(content (str "(:reply " (doubled "(:x \"a\\\"b\" (:y 1)) " 13) ")"))
        (t0 (monotonicNs))
        (rec (g/analyzeTelemetry (j/jstr content) (some "implement") (some "coder") (some "m") (some "/w") "/r" 1))
        (url (g/cleanUrl (str "https://example.com/a?" (doubled "utm_x=1&q=%C3%A9+x&" 11) "end=1")))
        (ms (/ (- (monotonicNs) t0) 1000000))]
    (pair (and (mt rec ((some r) (stringContains? r ":pureDyck1 true :markdownWrapped false")) ((none) false))
               (and (stringStartsWith? url "https://example.com/a?q=%C3%A9+x&q=") (stringEndsWith? url "&end=1")))
          ms))

fn ! runTests -> Bool
  (let [(text (resultOr (fileReadString (fixturePath)) ""))
        (lines (caseLines text))
        (parsed (parsedCases lines))
        (cases (okCases parsed))
        (tmp (makeTmp!))
        (stub (str tmp "/stub"))
        (installed (installStub! stub))
        (ctx (Ctx :tmp tmp :stub stub))
        (results (judgeAll! cases ctx (list)))
        (failed (filter (fn [(r (Pair String Bool))] -> Bool (not (pairSecond r))) results))
        (fns (listSort (fold (fn [(acc (List String)) (c Case)] -> (List String) (if (listContains? acc c.fn) acc (cons c.fn acc))) (list) cases)))
        (first (stubFirst? stub))
        (missing (missingCurl! tmp))
        (literal (literalConfig! stub tmp))
        (badNames (badNamesRejected! stub tmp))
        (breaks (lineBreaksRejected! stub tmp))
        (redirect (redirectIsError! stub tmp))
        (big (largeTransfer! stub tmp))
        (tel (largeTelemetry!))
        (report (eprintln (str "(:upstreamParity :cases " (stringFromInt64 (listLength cases)) " :failed " (stringFromInt64 (listLength failed))
                               " :fns " (stringFromInt64 (listLength fns)) " :largeTransferMs " (stringFromInt64 (pairSecond big))
                               " :largeTelemetryMs " (stringFromInt64 (pairSecond tel)) ")")))
        (cleaned (pathRemove tmp))]
    (do
      (assert (not (stringEmpty? text)) "fixture file is readable")
      (assert (= (listLength parsed) (listLength cases)) "every fixture line parses as JSON")
      (assert (= (listLength cases) 521) "fixture holds the 521 recorded cases")
      (assert (= (listLength fns) 25) "cases cover the 25 recorded function families")
      (assert installed "stub curl installed in a unique temp dir")
      (assert first "command -v curl resolves to the stub before /usr/bin")
      (assertAll! results)
      (assert missing "curl absent from PATH is toolAbsent, not a simulated reply")
      (assert literal "config carries literal escaped url, proto, header, key and body lines")
      (assert badNames "header names outside RFC 7230 tokens are refused before curl runs")
      (assert breaks "CR or LF in key, header name or value is refused without echoing it")
      (assert redirect "a 302 reply is an httpFailure, not followed")
      (assert (pairFirst big) "2 MiB request and 1 MiB reply cross the stub intact")
      (assert (< (pairSecond big) 20000) "large transfer finishes within 20 s")
      (assert (pairFirst tel) "large telemetry record and long clean_url query are correct")
      (assert (< (pairSecond tel) 20000) "large telemetry and clean_url finish within 20 s")
      (assert (ok? cleaned) "temp dir removed")
      true))
