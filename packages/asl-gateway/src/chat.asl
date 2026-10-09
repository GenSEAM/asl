(module aslGateway/chat
  :x [ChatRequest
      gatewayOriginHeader
      ChatWorld
      ChatEffect
      effRealpath
      effIsDir
      effClock
      effBreakerDown
      effBreakerDownAll
      effBreakerEvent
      effUsageNote
      effUsageFallback
      effTelemetry
      effNoteIntent
      effLog
      effBucket
      effHttp
      effPoolHttp
      effCli
      CliReply
      HttpReply
      httpOk
      httpError
      httpRaised
      ChatOutcome
      outDone
      outPath
      outBool
      outFloat
      outFloats
      outCli
      outHttp
      HeadItem
      headStatus
      headField
      ChatResponse
      ChatStep
      stepEffect
      stepDone
      stepRaised
      roleCascades
      roleTemperatures
      intentCascades
      intentTemperatures
      modelCascade
      chatStart!
      effectJson
      headJson]
  :i [(asl-json/json :a j)
      (upstream :a u)
      (config :a c)
      (wire :a w)
      (pyText :a pt)
      (usage :a g)
      (breaker :a b)
      (aslGateway/dispatch :a dp)])

(schema ChatRequest
  (:f path String)
  (:f headers (List (Pair String String)))
  (:f body String))

(schema ChatWorld
  (:f env (Map String String))
  (:f rootDir String)
  (:f settings u/UpstreamSettings)
  (:f agyPromptMaxBytes Int64)
  (:f table (Result c/GatewayTable String)))

(enum ChatEffect
  (:c effRealpath [(path String)])
  (:c effIsDir [(path String)])
  (:c effClock [])
  (:c effBreakerDown [(pool String)])
  (:c effBreakerDownAll [(pools (List String))])
  (:c effBreakerEvent [(event String) (pool String)])
  (:c effUsageNote [(provider String) (alias String) (outcome String) (usage j/Json)])
  (:c effUsageFallback [(provider String) (alias String)])
  (:c effTelemetry [(rec (Option String))])
  (:c effNoteIntent [(intent String)])
  (:c effLog [(text String)])
  (:c effBucket [(model String) (rpm Float64) (timeout Float64)])
  (:c effHttp [(provider String) (model String) (intent String) (role String) (request u/UpstreamRequest) (timeout Float64)])
  (:c effPoolHttp [(provider String) (model String) (base String) (pool c/GatewayPool) (request u/UpstreamRequest) (timeout Float64)])
  (:c effCli [(client String) (args (List (Pair String j/Json)))]))

(schema CliReply
  (:f text String)
  (:f usage j/Json)
  (:f dedup Bool)
  (:f queueWaitSec Float64)
  (:f execSec Float64)
  (:f pool String))

(enum HttpReply
  (:c httpOk [(status Int64) (headers (List (Pair String String))) (body String)])
  (:c httpError [(status Int64) (reason String) (headers (List (Pair String String))) (body String)])
  (:c httpRaised [(timeout Bool) (text String)]))

(enum ChatOutcome
  (:c outDone [])
  (:c outPath [(path String)])
  (:c outBool [(b Bool)])
  (:c outFloat [(f Float64)])
  (:c outFloats [(fs (List Float64))])
  (:c outCli [(reply (Option CliReply))])
  (:c outHttp [(reply HttpReply)]))

(enum HeadItem
  (:c headStatus [(code Int64)])
  (:c headField [(name String) (value String)]))

(schema ChatResponse
  (:f head (List HeadItem))
  (:f body String))

(enum ChatStep
  (:c stepEffect [(effect ChatEffect) (k (fn [ChatOutcome] -> ChatStep))])
  (:c stepDone [(response ChatResponse)])
  (:c stepRaised [(kind String) (message String)]))

(schema Ctx
  (:f req ChatRequest)
  (:f world ChatWorld)
  (:f path String)
  (:f asn Bool)
  (:f sanitize Bool)
  (:f intent String)
  (:f role String)
  (:f workspace String)
  (:f explicitModel String)
  (:f profileRouted Bool)
  (:f profileName String)
  (:f table (Option c/GatewayTable))
  (:f reqKeys (List String))
  (:f headerEff (Option String))
  (:f envEff (Option String))
  (:f tempExplicit Bool)
  (:f timeoutExplicit Bool)
  (:f baseBody j/Json)
  (:f cascadeLen Int64))

(schema Loop
  (:f body j/Json)
  (:f models (List c/GatewayResolvedEntry))
  (:f idx Int64)
  (:f lastErr (Option String))
  (:f skipped (List String))
  (:f emptyRetries Int64)
  (:f telBound Bool)
  (:f head (List HeadItem)))

(schema Attempt
  (:f entry c/GatewayResolvedEntry)
  (:f v2 (Option c/GatewayEntry))
  (:f model String)
  (:f target String)
  (:f upstream u/UpstreamEndpoint)
  (:f alias String)
  (:f pool String)
  (:f sentEffort (Option (Option String)))
  (:f poolConfig (Option c/GatewayPool))
  (:f data String))


fn roleCascades -> (List (Pair String (List String)))
  (list (pair "coder" (list "groq/qwen/qwen3.8-27b" "gemini-3.8-flash" "poolside/laguna-s-2.1:free" "cohere/north-mini-code:free" "poolside/laguna-xs-2.1:free" "google/gemma-4-31b-it:free" "google/gemma-4-26b-a4b-it:free" "qwen/qwen3.8-27b:free"))
        (pair "planner" (list "gemini-3.8-flash" "groq/qwen/qwen3.8-27b" "nvidia/nemotron-3-ultra-550b-a55b:free" "nvidia/nemotron-3-super-120b-a12b:free" "z-ai/glm-5.2:free" "nex-agi/nex-n2.5-pro:free"))
        (pair "scout" (list "groq/qwen/qwen3.8-27b" "gemini-3.5-flash-lite" "cohere/north-mini-code:free" "nex-agi/nex-n2.5-pro:free" "google/gemma-4-26b-a4b-it:free"))
        (pair "distillator" (list "gemini-3.5-flash-lite" "groq/qwen/qwen3.8-27b" "cohere/north-mini-code:free" "nex-agi/nex-n2.5-pro:free" "google/gemma-4-31b-it:free"))
        (pair "auditor" (list "gemini-3.8-flash" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free"))
        (pair "auditor:concurrency" (list "gemini-3.8-flash" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free" "nvidia/nemotron-3-super-120b-a12b:free"))
        (pair "auditor:logic" (list "gemini-3.8-flash" "google/gemma-4-31b-it:free" "qwen/qwen3.8-27b:free" "nvidia/nemotron-3-super-120b-a12b:free"))
        (pair "auditor:invariants" (list "gemini-3.8-flash" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" "google/gemma-4-31b-it:free"))
        (pair "auditor:architecture" (list "gemini-3.8-flash" "nvidia/nemotron-3-super-120b-a12b:free" "nex-agi/nex-n2.5-pro:free" "google/gemma-4-31b-it:free"))
        (pair "auditor:nonvacuity" (list "gemini-3.8-flash" "cohere/north-mini-code:free" "google/gemma-4-31b-it:free" "qwen/qwen3.8-27b:free"))
        (pair "knowledgecurator" (list "gemini-3.8-flash" "nvidia/nemotron-3-super-120b-a12b:free" "nex-agi/nex-n2.5-pro:free" "google/gemma-4-31b-it:free"))
        (pair "corroborator" (list "gemini-3.8-flash" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free" "nex-agi/nex-n2.5-pro:free"))
        (pair "consilium" (list "gemini-3.8-flash" "nvidia/nemotron-3-super-120b-a12b:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free"))
        (pair "chiefJustice" (list "gpt-6-astra" "nvidia/nemotron-3-ultra-550b-a55b:free" "z-ai/glm-5.2:free"))
        (pair "chiefjustice" (list "gpt-6-astra" "nvidia/nemotron-3-ultra-550b-a55b:free"))
        (pair "falsifier" (list "gemini-3.8-flash" "deepseek/deepseek-chat:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free" "nex-agi/nex-n2.5-pro:free"))
        (pair "shadowCritic" (list "gemini-3.8-flash" "deepseek/deepseek-chat:free" "nvidia/nemotron-3-super-120b-a12b:free" "google/gemma-4-31b-it:free"))
        (pair "notebook" (list "dots-studio/dots-3-note-preview:free" "thinkingmachines/inkling:free" "thinkingmachines/inkling-small:free"))
        (pair "router" (list "gemini-3.5-flash-lite" "liquid/lfm-2.5-2.6b:free" "inclusionai/ling-3.0-flash-fin:free" "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"))
        (pair "vision" (list "inclusionai/ling-3.0-flash-vl:free")))

fn roleTemperatures -> (List (Pair String Float64))
  (list (pair "coder" 0.0) (pair "scout" 0.2) (pair "distillator" 0.45) (pair "auditor" 0.25) (pair "auditor:concurrency" 0.6)
        (pair "auditor:logic" 0.55) (pair "auditor:invariants" 0.25) (pair "auditor:architecture" 0.2) (pair "auditor:nonvacuity" 0.45)
        (pair "knowledgecurator" 0.2) (pair "corroborator" 0.5) (pair "consilium" 0.35) (pair "chiefJustice" 0.0) (pair "chiefjustice" 0.0)
        (pair "falsifier" 0.55) (pair "shadowCritic" 0.3) (pair "planner" 0.2) (pair "router" 0.0))

fn intentCascades -> (List (Pair String (List String)))
  (list (pair "falsify" (list "gemini-3.8-flash" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" "cohere/north-mini-code:free"))
        (pair "discover" (list "gemini-3.5-flash-lite" "nex-agi/nex-n2.5-pro:free" "liquid/lfm-2.5-2.6b:free" "cohere/north-mini-code:free" "nvidia/nemotron-3-super-120b-a12b:free"))
        (pair "construct" (list "gemini-3.8-flash" "google/gemma-4-31b-it:free" "poolside/laguna-s-2.1:free" "cohere/north-mini-code:free" "poolside/laguna-xs-2.1:free"))
        (pair "formulate" (list "gemini-3.8-flash" "nvidia/nemotron-3-ultra-550b-a55b:free" "nvidia/nemotron-3-super-120b-a12b:free" "google/gemma-4-31b-it:free"))
        (pair "reconcile" (list "gemini-3.8-flash" "nvidia/nemotron-3-super-120b-a12b:free" "nex-agi/nex-n2.5-pro:free" "google/gemma-4-31b-it:free"))
        (pair "deliberate" (list "gemini-3.8-flash" "gpt-6-astra" "nvidia/nemotron-3-ultra-550b-a55b:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free"))
        (pair "puredeterministic" (list "liquid/lfm-2.5-2.6b:free"))
        (pair "strictast" (list "nex-agi/nex-n2.5-pro:free")))

fn intentTemperatures -> (List (Pair String Float64))
  (list (pair "falsify" 0.55) (pair "discover" 0.25) (pair "construct" 0.15) (pair "formulate" 0.2) (pair "reconcile" 0.35)
        (pair "deliberate" 0.6) (pair "puredeterministic" 0.0) (pair "strictast" 0.035))

fn lookup xs: (List (Pair String (List String))) k: String -> (Option (List String))
  (mt (listHead (filter (fn [(p (Pair String (List String)))] -> Bool (= (pairFirst p) k)) xs))
    ((some p) (some (pairSecond p)))
    ((none) none))

fn lookupTemp xs: (List (Pair String Float64)) k: String -> (Option Float64)
  (mt (listHead (filter (fn [(p (Pair String Float64))] -> Bool (= (pairFirst p) k)) xs))
    ((some p) (some (pairSecond p)))
    ((none) none))

fn modelCascade model: String -> (Option (List String))
  (mt (listHead (filter (fn [(p (Pair String (List String)))] -> Bool (listContains? (pairSecond p) model)) (roleCascades)))
    ((some p) (some (pairSecond p)))
    ((none) none))


fn raise e: pt/PyErr -> ChatStep
  (stepRaised e.kind e.msg)

fn splitErr s: String -> pt/PyErr
  (mt (stringIndexOf s ": ")
    ((some i) (pt/pyErr (u/slice s 0 i) (u/slice s (+ i 2) (stringLength s))))
    ((none) (pt/pyErr "Exception" s)))

fn attrErr v: j/Json attr: String -> pt/PyErr
  (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName v) "' object has no attribute '" attr "'"))

fn itemErr v: j/Json -> pt/PyErr
  (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object does not support item assignment"))

fn isObj? v: j/Json -> Bool
  (mt v ((j/jobj _) true) (_ false))

fn isNull? v: j/Json -> Bool
  (mt v ((j/jnull) true) (_ false))

fn has? v: j/Json k: String -> Bool
  (some? (pt/jget v k))

fn getOr v: j/Json k: String d: j/Json -> j/Json
  (optionOr (pt/jget v k) d)

fn jdel v: j/Json k: String -> j/Json
  (mt v
    ((j/jobj kvs) (j/jobj (filter (fn [(p (Pair String j/Json))] -> Bool (!= (pairFirst p) k)) kvs)))
    (_ v))

fn keysOf v: j/Json -> (List String)
  (mt v ((j/jobj kvs) (map (fn [(p (Pair String j/Json))] -> String (pairFirst p)) kvs)) (_ (list)))

fn strOr v: j/Json d: String -> String
  (mt v ((j/jstr s) s) (_ d))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (u/slice s 1 (stringLength s))) s)

fn norm s: String -> String
  (u/pyLower (lstripColons s))

fn truncInt f: Float64 -> Int64
  (optionOr (float64ToInt64 f) 0)

fn present v: (Option String) -> (Option String)
  (mt v ((some s) (if (stringEmpty? s) none (some s))) ((none) none))

fn fieldIfBody body: j/Json key: String -> (Result j/Json pt/PyErr)
  (if (pt/pyTruthy body)
    (if (isObj? body) (ok (getOr body key (j/jnull))) (err (attrErr body "get")))
    (ok (j/jstr "")))

fn normField hdr: (Option String) body: j/Json key: String -> (Result String pt/PyErr)
  (mt (present hdr)
    ((some h) (ok (norm h)))
    ((none)
     (mt (fieldIfBody body key)
       ((err e) (err e))
       ((ok v)
        (if (pt/pyTruthy v)
          (mt v ((j/jstr s) (ok (norm s))) (_ (err (attrErr v "lstrip"))))
          (ok ""))))))

fn roleField hdr: (Option String) body: j/Json -> (Result String pt/PyErr)
  (mt (present hdr)
    ((some h) (ok (norm h)))
    ((none)
     (mt (fieldIfBody body "role")
       ((err e) (err e))
       ((ok v)
        (if (pt/pyTruthy v)
          (mt v ((j/jstr s) (ok (norm s))) (_ (err (attrErr v "lstrip"))))
          (if (pt/pyTruthy body)
            (let [(model (getOr body "model" (j/jnull)))]
              (mt model
                ((j/jstr s) (ok (if (some? (lookup (roleCascades) s)) (norm s) "")))
                ((j/jarr _) (err (pt/pyErr "TypeError" "unhashable type: 'list'")))
                ((j/jobj _) (err (pt/pyErr "TypeError" "unhashable type: 'dict'")))
                (_ (ok ""))))
            (ok "")))))))

fn floatOf v: j/Json -> (Result Float64 pt/PyErr)
  (mt v
    ((j/jint i) (ok (int64ToFloat64 i)))
    ((j/jfloat f) (ok f))
    ((j/jnum f) (ok f))
    ((j/jbool b) (ok (if b 1.0 0.0)))
    ((j/jstr s) (mt (u/pyFloat s) ((ok f) (ok f)) ((err _) (err (pt/pyErr "ValueError" (str "could not convert string to float: " (pt/pyRepr v)))))))
    (_ (err (pt/pyErr "TypeError" (str "float() argument must be a string or a real number, not '" (pt/pyTypeName v) "'")))))

fn numberOf v: j/Json -> (Option Float64)
  (mt v
    ((j/jint i) (some (int64ToFloat64 i)))
    ((j/jfloat f) (some f))
    ((j/jnum f) (some f))
    ((j/jbool b) (some (if b 1.0 0.0)))
    (_ none))

fn escapeAsnStr v: j/Json -> String
  (u/replaceAll (u/replaceAll (u/replaceAll (u/replaceAll (u/replaceAll (pt/pyStr v) "\\" "\\\\") "\"" "\\\"") "\n" " ") "\r" " ") "\t" " ")

fn messageText content: j/Json -> (Result String pt/PyErr)
  (mt content
    ((j/jnull) (ok ""))
    ((j/jarr parts)
     (mt (fold (fn [(acc (Result (List String) pt/PyErr)) (p j/Json)] -> (Result (List String) pt/PyErr)
                 (mt acc
                   ((err e) (err e))
                   ((ok xs)
                    (if (and (isObj? p) (pt/pyTruthy (getOr p "text" (j/jnull))))
                      (mt (getOr p "text" (j/jnull))
                        ((j/jstr t) (ok (cons t xs)))
                        (_ (err (pt/pyErr "TypeError" "sequence item: expected str instance"))))
                      (ok xs)))))
               (ok (list)) parts)
       ((err e) (err e))
       ((ok xs) (ok (stringJoin (listReverse xs) "\n")))))
    (_ (ok (pt/pyStr content))))

fn messageList v: j/Json -> (Result (List j/Json) pt/PyErr)
  (mt v
    ((j/jarr xs) (ok xs))
    ((j/jstr _) (err (attrErr (j/jstr "") "get")))
    ((j/jobj _) (err (attrErr (j/jstr "") "get")))
    (_ (err (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object is not iterable")))))

fn msgGet msg: j/Json key: String d: j/Json -> (Result j/Json pt/PyErr)
  (if (isObj? msg) (ok (getOr msg key d)) (err (attrErr msg "get")))

fn promptOf msgs: (List j/Json) keep: (fn [j/Json] -> (Result Bool pt/PyErr)) -> (Result String pt/PyErr)
  (mt (fold (fn [(acc (Result (List String) pt/PyErr)) (msg j/Json)] -> (Result (List String) pt/PyErr)
              (mt acc
                ((err e) (err e))
                ((ok parts)
                 (mt (keep msg)
                   ((err e) (err e))
                   ((ok kept)
                    (if (not kept)
                      (ok parts)
                      (mt (msgGet msg "role" (j/jstr "user"))
                        ((err e) (err e))
                        ((ok role)
                         (mt (msgGet msg "content" (j/jstr ""))
                           ((err e) (err e))
                           ((ok content) (ok (cons (str "[" (pt/pyStr role) "]:\n" (pt/pyStr content)) parts))))))))))))
            (ok (list)) msgs)
    ((err e) (err e))
    ((ok parts) (ok (stringJoin (listReverse parts) "\n\n"))))

fn contentKept msg: j/Json -> (Result Bool pt/PyErr)
  (mt (msgGet msg "content" (j/jnull)) ((err e) (err e)) ((ok c) (ok (pt/pyTruthy c))))

fn fallbackPrompt body: j/Json -> (Result String pt/PyErr)
  (if (and (pt/pyTruthy body) (pt/pyTruthy (getOr body "messages" (j/jnull))))
    (mt (messageList (getOr body "messages" (j/jnull)))
      ((err e) (err e))
      ((ok msgs) (promptOf msgs contentKept)))
    (ok ""))


fn wantsAsn? headers: (List (Pair String String)) -> Bool
  (or (stringContains? (optionOr (u/headerGet headers "Accept") "") "application/asn+sexpr")
      (= (u/pyLower (u/pyStrip (optionOr (u/headerGet headers "X-ASL-Wire") ""))) "asn"))

fn done head: (List HeadItem) body: String -> ChatStep
  (stepDone (ChatResponse :head head :body body))

fn fields xs: (List (Pair String String)) -> (List HeadItem)
  (map (fn [(p (Pair String String))] -> HeadItem (headField (pairFirst p) (pairSecond p))) xs)

fn asnHead -> (List HeadItem)
  (list (headField "Content-Type" "application/asn+sexpr") (headField "X-ASL-Wire-Protocol" "asn/1.0"))

fn sendError cx: Ctx head: (List HeadItem) status: Int64 reason: String jsonType: Bool -> ChatStep
  (if cx.asn
    (done (listAppend head (cons (headStatus status) (listAppend (asnHead) (list (headField "X-ASL-Wire" "asn,json")))))
          (str "(:error :status " (stringFromInt64 status) " :reason \"" (w/asnEscape reason) "\")\n"))
    (done (listAppend head (cons (headStatus status) (listAppend (if jsonType (list (headField "Content-Type" "application/json")) (list))
                                                               (list (headField "X-ASL-Wire" "asn,json")))))
          (pt/jsonDumps (j/jobj (list (pair "error" (j/jstr reason)))) -1)))

fn sendReply cx: Ctx head: (List HeadItem) status: Int64 resp: j/Json extra: (List (Pair String String)) -> ChatStep
  (done (listAppend head (cons (headStatus status)
                               (listAppend (if cx.asn (asnHead) (list (headField "Content-Type" "application/json")))
                                           (listAppend (fields extra) (list (headField "X-ASL-Wire" "asn,json"))))))
        (if cx.asn (w/chatReplyAsn resp) (pt/jsonDumps resp -1)))

fn workspaceError msg: String -> ChatStep
  (done (cons (headStatus 400) (asnHead))
        (str "(:error ERR_WORKSPACE :message \"" msg "\" :hint \"pass an absolute existing directory\")\n"))

fn telemetryHeader rec: (Option String) -> (List (Pair String String))
  (if (some? rec) (list (pair "X-ASL-Telemetry" "logged")) (list))


fn mismatch want: String -> ChatStep
  (stepRaised "ProtocolError" (str "effect answered without the " want " outcome it needs"))

fn tell eff: ChatEffect k: (fn [] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outDone) (k)) (_ (mismatch "done")))))

fn tellAll effs: (List ChatEffect) k: (fn [] -> ChatStep) -> ChatStep
  (mt (listHead effs)
    ((none) (k))
    ((some e) (tell e (fn [] -> ChatStep (tellAll (optionOr (listTail effs) (list)) k)))))

fn askPath eff: ChatEffect k: (fn [String] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outPath p) (k p)) (_ (mismatch "path")))))

fn askBool eff: ChatEffect k: (fn [Bool] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outBool b) (k b)) (_ (mismatch "bool")))))

fn askFloat eff: ChatEffect k: (fn [Float64] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outFloat f) (k f)) (_ (mismatch "float")))))

fn askFloats eff: ChatEffect k: (fn [(List Float64)] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outFloats fs) (k fs)) (_ (mismatch "floats")))))

fn askCli eff: ChatEffect k: (fn [(Option CliReply)] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outCli r) (k r)) (_ (mismatch "cli")))))

fn askHttp eff: ChatEffect k: (fn [HttpReply] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (mt o ((outHttp r) (k r)) (_ (mismatch "http")))))

fn usageNote provider: String alias: String outcome: String -> ChatEffect
  (effUsageNote provider alias outcome (j/jnull))

fn telemetry cx: Ctx content: j/Json model: String k: (fn [(Option String)] -> ChatStep) -> ChatStep
  (let [(blank (mt content ((j/jstr s) (stringEmpty? (u/pyStrip s))) (_ true)))]
    (if blank
      (tell (effTelemetry none) (fn [] -> ChatStep (k none)))
      (askFloat (effClock)
        (fn [(t Float64)] -> ChatStep
          (let [(rec (g/analyzeTelemetry content (some cx.intent) (some cx.role) (some model) (some cx.workspace)
                                         cx.world.rootDir (truncInt (* t 1000.0))))]
            (tell (effTelemetry rec) (fn [] -> ChatStep (k rec))))))))

fn cliArgs agent: j/Json addDirs: j/Json prompt: String model: String effort: j/Json timeout: Float64 queue: Float64 ws: String system: String noTools: Bool -> (List (Pair String j/Json))
  (list (pair "prompt" (j/jstr prompt)) (pair "model" (j/jstr model)) (pair "effort" effort) (pair "timeout" (j/jfloat timeout))
        (pair "queue_timeout" (j/jfloat queue)) (pair "agent" agent) (pair "add_dirs" addDirs) (pair "workspace" (j/jstr ws))
        (pair "system_prompt" (if (stringEmpty? system) (j/jnull) (j/jstr system))) (pair "no_tools" (j/jbool noTools)))

fn agyFallback cx: Ctx prompt: String k: (fn [(Option CliReply)] -> ChatStep) -> ChatStep
  (if (stringEmpty? prompt)
    (k none)
    (askFloat (effBreakerDown "agy")
      (fn [(left Float64)] -> ChatStep
        (if (!= left 0.0)
          (tell (usageNote "agy-cli" "agyFallback" "skipped-breaker") (fn [] -> ChatStep (k none)))
          (askCli (effCli "agy" (list (pair "prompt" (j/jstr prompt)) (pair "model" (j/jstr "gemini-3.8-flash")) (pair "effort" (j/jstr "low"))
                                      (pair "timeout" (j/jint 300)) (pair "queue_timeout" (j/jint 1200)) (pair "agent" (j/jnull))
                                      (pair "add_dirs" (j/jnull)) (pair "workspace" (j/jstr cx.workspace)) (pair "system_prompt" (j/jnull))
                                      (pair "no_tools" (j/jbool false))))
            (fn [(r (Option CliReply))] -> ChatStep
              (let [(text (mt r ((some x) (if (stringEmpty? x.text) none (some x))) ((none) none)))]
                (tell (usageNote "agy-cli" "agyFallback" (if (some? text) "ok" "failed")) (fn [] -> ChatStep (k text))))))))))

fn round3 f: Float64 -> j/Json
  (j/jfloat (g/pyRound3 f))

fn completionJson id: String ts: Int64 model: String text: String asl: (List (Pair String j/Json)) -> j/Json
  (j/jobj (list (pair "id" (j/jstr id)) (pair "object" (j/jstr "chat.completion")) (pair "created" (j/jint ts)) (pair "model" (j/jstr model))
                (pair "choices" (j/jarr (list (j/jobj (list (pair "index" (j/jint 0))
                                                             (pair "message" (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr text)))))
                                                             (pair "finish_reason" (j/jstr "stop")))))))
                (pair "asl" (j/jobj asl))))

fn maybeSanitize cx: Ctx text: String -> String
  (if cx.sanitize (w/sanitizeAsnContent text) text)

fn agyReply cx: Ctx l: Loop r: CliReply -> ChatStep
  (let [(text (maybeSanitize cx r.text))]
    (telemetry cx (j/jstr text) "agy:gemini-3.8-flash-high"
      (fn [(rec (Option String))] -> ChatStep
        (askFloat (effClock)
          (fn [(t Float64)] -> ChatStep
            (let [(ts (truncInt t))]
              (sendReply cx l.head 200
                (completionJson (str "chatcmpl-agy-" (stringFromInt64 ts)) ts "agy:gemini-3.8-flash" text
                                (list (pair "queueWaitSec" (round3 r.queueWaitSec)) (pair "execSec" (round3 r.execSec)) (pair "pool" (j/jstr "agy"))))
                (cons (pair "X-ASL-Fallback" "agy-cli") (telemetryHeader rec)))))))))


fn shownParam table: (Option c/GatewayTable) e: c/GatewayEntry key: String -> (Option j/Json)
  (mt table
    ((none) none)
    ((some tbl)
     (mt (mapGet tbl.models e.alias)
       ((none) none)
       ((some m)
        (mt (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) key)) m.shown))
          ((none) none)
          ((some p) (mt (pt/jsonLoads (pairSecond p)) ((ok v) (some v)) ((err _) none))))))))

fn paramJson cx: Ctx e: c/GatewayEntry key: String typed: j/Json -> j/Json
  (optionOr (shownParam cx.table e key) typed)

fn floatJson v: (Option Float64) -> j/Json
  (mt v ((some f) (j/jfloat f)) ((none) (j/jnull)))

fn entryBody cx: Ctx e: c/GatewayEntry -> j/Json
  (let [(ep e.params)
        (b0 cx.baseBody)
        (b1 (if (and (some? ep.temperature) (not cx.tempExplicit)) (pt/jset b0 "temperature" (paramJson cx e "temperature" (floatJson ep.temperature))) b0))
        (b2 (mt ep.effort ((some s) (pt/jset b1 "effort" (j/jstr s))) ((none) b1)))
        (b3 (mt ep.maxTokens
              ((some n) (if (listContains? cx.reqKeys "max_tokens") b2 (pt/jset b2 "max_tokens" (paramJson cx e "maxTokens" (j/jint n)))))
              ((none) b2)))
        (b4 (if (and (optionOr ep.reasoning false) (not (pt/pyTruthy (getOr b3 "max_tokens" (j/jnull))))) (pt/jset b3 "max_tokens" (j/jint (u/minTokenFloor))) b3))
        (b5 (if (and (some? ep.timeoutSec) (not cx.timeoutExplicit)) (pt/jset b4 "timeout" (paramJson cx e "timeoutSec" (floatJson ep.timeoutSec))) b4))]
    b5)

fn entryUpstream cx: Ctx e: c/GatewayEntry -> u/UpstreamEndpoint
  (let [(up e.upstream)
        (keyEnv (mt cx.table
                  ((some tbl) (mt (mapGet tbl.providers e.provider) ((some pv) pv.keyEnv) ((none) "")))
                  ((none) "")))
        (key (if (= e.kind "cli") "" (optionOr (mapGet cx.world.env keyEnv) "")))]
    (u/UpstreamEndpoint :provider up.provider :url up.url :key key))

fn upstreamFor cx: Ctx m: String -> u/UpstreamEndpoint
  (u/getUpstreamForModelIn (dp/rowsFromTable cx.table) (u/upstreamFallback) cx.world.settings cx.world.env (some m))

fn cliProvider? p: String -> Bool
  (or (= p "agy-cli") (or (= p "codex-cli") (= p "claude-cli")))

fn validEffort? v: (Option String) -> Bool
  (mt v ((some s) (or (= s "low") (or (= s "medium") (= s "high")))) ((none) false))


fn chatStart! req: ChatRequest world: ChatWorld -> ChatStep
  (let [(path (if (stringStartsWith? req.path "/v1/chat/completions") "/chat/completions" req.path))
        (body (mt (pt/jsonLoads req.body) ((ok v) v) ((err _) (j/jnull))))
        (wsRaw (if (isObj? body) (getOr body "workspace" (j/jnull)) (j/jnull)))]
    (if (isNull? wsRaw)
      (askPath (effRealpath world.rootDir) (fn [(ws String)] -> ChatStep (identify! req world path body ws)))
      (if (stringStartsWith? (strOr wsRaw "") "/")
        (askPath (effRealpath (strOr wsRaw ""))
          (fn [(resolved String)] -> ChatStep
            (askBool (effIsDir resolved)
              (fn [(isDir Bool)] -> ChatStep
                (if isDir
                  (identify! req world path body resolved)
                  (workspaceError (str "Workspace directory does not exist: " (escapeAsnStr wsRaw))))))))
        (workspaceError (str "Workspace must be an absolute path: " (escapeAsnStr wsRaw))))))

fn identify! req: ChatRequest world: ChatWorld path: String body: j/Json ws: String -> ChatStep
  (let [(hs req.headers)]
    (mt (normField (u/headerGet hs "X-ASL-Intent") body "intent")
      ((err e) (raise e))
      ((ok intent)
       (mt (roleField (u/headerGet hs "X-ASL-Role") body)
         ((err e) (raise e))
         ((ok explicitRole)
          (let [(role (if (stringEmpty? explicitRole) (if (stringEmpty? intent) "coder" "") explicitRole))
                (roleOpt (if (stringEmpty? explicitRole) none (some explicitRole)))
                (reqKeys (keysOf body))]
            (mt (if (pt/pyTruthy body) (mt (u/prepareRequestPayload body roleOpt) ((ok b) (ok b)) ((err s) (err (splitErr s)))) (ok body))
              ((err e) (raise e))
              ((ok prepared)
               (mt (normField (u/headerGet hs "X-ASL-Lens") prepared "lens")
                 ((err e) (raise e))
                 ((ok lens)
                  (let [(composite (if (stringEmpty? lens)
                                     (cond ((not (stringEmpty? role)) role) ((not (stringEmpty? intent)) intent) (else "coder"))
                                     (cond ((not (stringEmpty? role)) (str role ":" lens)) ((not (stringEmpty? intent)) (str intent ":" lens)) (else lens))))
                        (explicitModel (if (pt/pyTruthy prepared) (strOr (getOr prepared "model" (j/jstr "")) "") ""))
                        (routed (and (= path "/chat/completions") (or (stringEmpty? explicitModel) (or (= explicitModel "default") (= explicitModel "profile")))))
                        (cx (Ctx :req req :world world :path path :asn (wantsAsn? hs)
                                 :sanitize (listContains? (list "true" "1") (u/pyLower (optionOr (u/headerGet hs "X-Sanitize-ASN") "")))
                                 :intent intent :role role :workspace ws :explicitModel explicitModel :profileRouted routed
                                 :profileName "" :table (mt world.table ((ok t) (some t)) ((err _) none)) :reqKeys reqKeys
                                 :headerEff (u/headerGet hs "X-ASL-Effort") :envEff (mapGet world.env "ASL_EFFORT")
                                 :tempExplicit false :timeoutExplicit false :baseBody prepared :cascadeLen 0))]
                    (mt world.table
                      ((err e) (if (stringStartsWith? e "ERR_GATEWAY_NO_CONFIG")
                                  (sendError cx (list) 503 e true)
                                  (if routed
                                    (profileRoute! cx prepared explicitRole composite)
                                    (aliasRoute! cx prepared explicitRole composite))))
                      ((ok _)
                        (if routed
                          (profileRoute! cx prepared explicitRole composite)
                          (aliasRoute! cx prepared explicitRole composite)))))))))))))))

fn withProfile cx: Ctx name: String -> Ctx
  (with cx :profileName name)

fn profileRoute! cx: Ctx body: j/Json explicitRole: String composite: String -> ChatStep
  (mt cx.world.table
    ((err e) (sendError cx (list) (if (stringStartsWith? e "ERR_GATEWAY_NO_CONFIG") 503 500) e true))
    ((ok tbl)
     (mt (c/gatewayRouteEntries! tbl cx.req.headers (mapGet cx.world.env "ASL_GATEWAY_PROFILE") cx.intent)
       ((err e) (sendError cx (list) 400 e true))
       ((ok re)
        (let [(i cx.intent)
              (noted (and (= tbl.version 2) (and (not (stringEmpty? i)) (not (mapHas? tbl.intents i)))))
              (next (fn [] -> ChatStep
                      (if (listEmpty? re.entries)
                        (sendError cx (list) 400 (str "profile " re.name " has no route for intent " (if (stringEmpty? i) "any" i)) true)
                        (cascadeChosen (withProfile cx re.name) body explicitRole composite re.entries (selectTemp cx composite)))))]
          (if noted (tell (effNoteIntent i) next) (next)))))))

fn selectTemp cx: Ctx composite: String -> Float64
  (let [(i cx.intent)]
    (mt (if (stringEmpty? i) none (lookupTemp (intentTemperatures) i))
      ((some t) t)
      ((none)
       (mt (lookupTemp (roleTemperatures) composite)
         ((some t) t)
         ((none) (optionOr (lookupTemp (roleTemperatures) cx.role) 0.2))))))

fn unresolved ms: (List String) -> (List c/GatewayResolvedEntry)
  (map (fn [(m String)] -> c/GatewayResolvedEntry (c/entryUnresolved m)) ms)

fn aliasRoute! cx: Ctx body: j/Json explicitRole: String composite: String -> ChatStep
  (let [(model cx.explicitModel)
        (world cx.world)
        (choose (fn [(alias (Option c/GatewayResolvedEntry))] -> ChatStep
                  (let [(prov (if (stringEmpty? model) "" (upstreamFor cx model).provider))
                        (i cx.intent)
                        (role cx.role)
                        (roleOk (or (stringEmpty? model) (some? (lookup (roleCascades) model))))]
                    (cond
                      ((or (some? alias) (cliProvider? prov))
                       (cascadeChosen cx body explicitRole composite (list (optionOr alias (c/entryUnresolved model))) (selectTemp cx composite)))
                      ((and (not (stringEmpty? i)) (some? (lookup (intentCascades) i)))
                       (cascadeChosen cx body explicitRole composite (unresolved (optionOr (lookup (intentCascades) i) (list)))
                                      (optionOr (lookupTemp (intentTemperatures) i) 0.2)))
                      ((and (some? (lookup (roleCascades) composite)) roleOk)
                       (cascadeChosen cx body explicitRole composite (unresolved (optionOr (lookup (roleCascades) composite) (list)))
                                      (optionOr (lookupTemp (roleTemperatures) composite) 0.2)))
                      ((and (some? (lookup (roleCascades) role)) roleOk)
                       (cascadeChosen cx body explicitRole composite (unresolved (optionOr (lookup (roleCascades) role) (list)))
                                      (optionOr (lookupTemp (roleTemperatures) role) 0.2)))
                      ((some? (modelCascade model))
                       (cascadeChosen cx body explicitRole composite
                                      (unresolved (cons model (filter (fn [(x String)] -> Bool (!= x model)) (optionOr (modelCascade model) (list))))) 0.2))
                      ((not (stringEmpty? model)) (cascadeChosen cx body explicitRole composite (unresolved (list model)) 0.2))
                      (else (cascadeChosen cx body explicitRole composite (unresolved (optionOr (lookup (roleCascades) "coder") (list))) 0.0))))))]
    (if (stringEmpty? model)
      (choose none)
      (mt world.table
        ((err e) (tell (effLog (str "[Gateway Config] " model " dispatched raw: " e "\n")) (fn [] -> ChatStep (choose none))))
        ((ok tbl) (choose (c/gatewayV2AliasEntry! tbl model))))))

fn cascadeChosen cx: Ctx body: j/Json explicitRole: String composite: String models: (List c/GatewayResolvedEntry) calibrated: Float64 -> ChatStep
  (let [(world cx.world)
        (hs cx.req.headers)
        (mode (u/harnessMode hs world.env))
        (roleOpt (if (stringEmpty? explicitRole) none (some explicitRole)))]
    (mt (if (and (pt/pyTruthy body) (or (= mode "override") (= mode "minimal")))
          (mt (u/applyHarnessPolicy body mode roleOpt) ((ok b) (ok b)) ((err s) (err (splitErr s))))
          (ok body))
      ((err e) (raise e))
      ((ok harnessed)
       (let [(hTemp (u/headerGet hs "X-ASL-Temperature"))
             (envTemp (mapGet world.env "ASL_TEMPERATURE"))
             (envTempSet (mt envTemp ((some s) (not (stringEmpty? (u/pyStrip s)))) ((none) false)))
             (assign (fn [(text String)] -> j/Json
                       (mt (u/pyFloat text)
                         ((ok f) (if (isObj? harnessed) (pt/jset harnessed "temperature" (j/jfloat f)) harnessed))
                         ((err _) harnessed))))
             (tempered (cond
                         ((some? hTemp) (assign (optionOr hTemp "")))
                         (envTempSet (assign (u/pyStrip (optionOr envTemp ""))))
                         ((and (pt/pyTruthy harnessed) (not (has? harnessed "temperature"))) (pt/jset harnessed "temperature" (j/jfloat calibrated)))
                         (else harnessed)))
             (hEff cx.headerEff)
             (eEff cx.envEff)]
         (mt (cond
               ((validEffort? hEff) (if (isObj? tempered) (ok (pt/jset tempered "effort" (j/jstr (optionOr hEff "")))) (err (itemErr tempered))))
               ((validEffort? eEff) (if (isObj? tempered) (ok (pt/jset tempered "effort" (j/jstr (optionOr eEff "")))) (err (itemErr tempered))))
               ((and (pt/pyTruthy tempered) (not (has? tempered "effort")))
                (mt (numberOf (getOr tempered "temperature" (j/jfloat 0.2)))
                  ((some t) (ok (pt/jset tempered "effort" (j/jstr (cond ((<= t 0.15) "low") ((<= t 0.35) "medium") (else "high"))))))
                  ((none) (err (pt/pyErr "TypeError" (str "'<=' not supported between instances of '" (pt/pyTypeName (getOr tempered "temperature" (j/jnull))) "' and 'float'"))))))
               (else (ok tempered)))
           ((err e) (raise e))
           ((ok final)
            (let [(keys cx.reqKeys)
                  (tempExplicit (or (some? hTemp) (or envTempSet (listContains? keys "temperature"))))
                  (timeoutExplicit (or (some? (present (u/headerGet hs "X-ASL-Timeout")))
                                       (or (some? (present (u/headerGet hs "X-ASL-Execution-Timeout")))
                                           (or (listContains? keys "timeout") (listContains? keys "execution_timeout")))))
                  (cx2 (with cx :world world :reqKeys keys :headerEff hEff :envEff eEff :tempExplicit tempExplicit :timeoutExplicit timeoutExplicit :baseBody final :cascadeLen (listLength models)))]
              (loopStep cx2 (Loop :body final :models models :idx 0 :lastErr none :skipped (list) :emptyRetries 0 :telBound false :head (list))))))))))


fn advance l: Loop body: j/Json -> Loop
  (with l :body body :idx (+ l.idx 1))

fn failed l: Loop err: String -> Loop
  (with l :lastErr (some err))

fn loopStep cx: Ctx l: Loop -> ChatStep
  (mt (listGet l.models l.idx)
    ((none) (afterLoop cx l))
    ((some entry) (attempt cx l entry)))

fn prepareAttempt cx: Ctx l: Loop entry: c/GatewayResolvedEntry -> (Pair j/Json Attempt)
  (let [(v2 (mt entry ((c/entryResolved e) (some e)) ((c/entryUnresolved _) none)))
        (m (mt entry ((c/entryResolved e) e.dispatch) ((c/entryUnresolved a) a)))
        (body0 (mt v2 ((some e) (if (isObj? cx.baseBody) (entryBody cx e) l.body)) ((none) l.body)))
        (target (cond
                  ((some? v2) m)
                  ((stringStartsWith? m "groq/") (u/slice m 5 (stringLength m)))
                  ((stringStartsWith? m "ollama/") (u/slice m 7 (stringLength m)))
                  ((= m "qwen") "qwen/qwen3.8-27b")
                  (else m)))
        (world cx.world)
        (upstream (mt v2 ((some e) (entryUpstream cx e)) ((none) (upstreamFor cx m))))
        (prov upstream.provider)
        (alias (mt v2 ((some e) e.alias) ((none) m)))
        (pool (cond
                ((and (some? v2) (not (stringEmpty? (mt v2 ((some e) e.provider) ((none) ""))))) (mt v2 ((some e) e.provider) ((none) "")))
                ((= prov "agy-cli") "agy")
                ((= prov "codex-cli") "codex")
                ((= prov "claude-cli") "claude")
                (else prov)))
        (truthy (pt/pyTruthy body0))
        (body1 (if truthy (pt/jset body0 "model" (j/jstr target)) body0))
        (ollama (or (= prov "ollama") (mt v2 ((some e) (= e.provider "ollama")) ((none) false))))
        (entryEff (mt v2 ((some e) e.params.effort) ((none) none)))
        (reqHasEff (or (listContains? cx.reqKeys "effort") (or (some? cx.headerEff) (some? cx.envEff))))
        (chosen (mt entryEff ((some s) (j/jstr s)) ((none) (if reqHasEff (getOr body1 "effort" (j/jnull)) (j/jnull)))))
        (chosenValid (mt chosen ((j/jstr s) (validEffort? (some s))) (_ false)))
        (out0 (jdel body1 "effort"))
        (out1 (if (and ollama chosenValid) (pt/jset out0 "reasoning_effort" chosen) out0))
        (out2 (jdel (jdel (jdel (jdel out1 "role") "intent") "lens") "workspace"))
        (out3 (if (some? v2) (jdel out2 "timeout") out2))
        (sent (if (and truthy ollama) (if chosenValid (some (some (strOr chosen ""))) (some none)) none))
        (data (if truthy (pt/jsonDumps out3 -1) cx.req.body))]
    (pair body1 (Attempt :entry entry :v2 v2 :model m :target target :upstream upstream :alias alias :pool pool :sentEffort sent
      :poolConfig (mt v2 ((some e) e.pool) ((none) none)) :data data)))

fn withBreaker pool: String k: (fn [Float64] -> ChatStep) -> ChatStep
  (if (stringEmpty? pool) (k 0.0) (askFloat (effBreakerDown pool) k))

fn attempt cx: Ctx l: Loop entry: c/GatewayResolvedEntry -> ChatStep
  (let [(prepared (prepareAttempt cx l entry))
        (body (pairFirst prepared))
        (a (pairSecond prepared))
        (l1 (with l :body body))
        (prov a.upstream.provider)
        (pool a.pool)]
    (withBreaker pool
      (fn [(left Float64)] -> ChatStep
        (if (!= left 0.0)
          (let [(secs (stringFromInt64 (truncInt left)))]
            (tellAll (list (effLog (str "[Gateway Breaker] skip " pool " for " secs "s\n")) (usageNote prov a.alias (str "breaker " secs "s")))
              (fn [] -> ChatStep
                (loopStep cx (Loop :body body :models l1.models :idx (+ l1.idx 1)
                                   :lastErr (some (str "circuit breaker open for " pool " (" secs "s left)"))
                                   :skipped (listAppend l1.skipped (list pool)) :emptyRetries l1.emptyRetries
                                   :telBound l1.telBound :head l1.head)))))
          (if (cliProvider? prov) (cliAttempt cx l1 a) (rateAttempt cx l1 a))))))


fn systemPrompt msgs: (List j/Json) -> (Result String pt/PyErr)
  (mt (fold (fn [(acc (Result (List String) pt/PyErr)) (msg j/Json)] -> (Result (List String) pt/PyErr)
              (mt acc
                ((err e) (err e))
                ((ok xs)
                 (mt (msgGet msg "role" (j/jnull))
                   ((err e) (err e))
                   ((ok role)
                    (if (and (= role (j/jstr "system")) (pt/pyTruthy (getOr msg "content" (j/jnull))))
                      (mt (messageText (getOr msg "content" (j/jnull)))
                        ((err e) (err e))
                        ((ok t) (ok (cons t xs))))
                      (ok xs)))))))
            (ok (list)) msgs)
    ((err e) (err e))
    ((ok xs) (ok (stringJoin (listReverse xs) "\n\n"))))

fn cliAttempt cx: Ctx l: Loop a: Attempt -> ChatStep
  (let [(body l.body)
        (prov a.upstream.provider)
        (m a.model)
        (hs cx.req.headers)
        (bodyObj (if (pt/pyTruthy body) body (j/jobj (list))))
        (agent (if (= prov "agy-cli") (getOr bodyObj "agent" (j/jnull)) (j/jnull)))
        (agentOn (pt/pyTruthy agent))
        (msgsVal (let [(v (getOr bodyObj "messages" (j/jnull)))] (if (pt/pyTruthy v) v (j/jarr (list)))))]
    (mt (messageList msgsVal)
      ((err e) (raise e))
      ((ok msgs)
       (mt (if agentOn (ok "") (systemPrompt msgs))
         ((err e) (raise e))
         ((ok system)
          (mt (promptOf msgs (fn [(msg j/Json)] -> (Result Bool pt/PyErr)
                               (mt (msgGet msg "content" (j/jnull))
                                 ((err e) (err e))
                                 ((ok c) (ok (and (pt/pyTruthy c) (or agentOn (!= (getOr msg "role" (j/jnull)) (j/jstr "system")))))))))
            ((err e) (raise e))
            ((ok prompt)
             (let [(tools (getOr bodyObj "tools" (j/jnull)))
                   (noTools (or (mt tools ((j/jarr xs) (listEmpty? xs)) (_ false))
                                (= (u/pyLower (u/pyStrip (optionOr (u/headerGet hs "X-ASL-Tools") ""))) "none")))
                   (truthy (pt/pyTruthy body))
                   (effort (if truthy (getOr body "effort" (j/jstr "low")) (j/jstr "low")))
                   (temp (if truthy (getOr body "temperature" (j/jfloat 0.2)) (j/jfloat 0.2)))
                   (execRaw (mt (u/headerGet hs "X-ASL-Timeout")
                              ((some h) (j/jstr h))
                              ((none) (mt (u/headerGet hs "X-ASL-Execution-Timeout")
                                        ((some h) (j/jstr h))
                                        ((none) (if truthy (getOr body "timeout" (getOr body "execution_timeout" (j/jint 300))) (j/jint 300)))))))
                   (queueRaw (mt (u/headerGet hs "X-ASL-Queue-Timeout")
                               ((some h) (j/jstr h))
                               ((none) (if truthy (getOr body "queue_timeout" (j/jint 1200)) (j/jint 1200)))))]
               (mt (floatOf execRaw)
                 ((err e) (raise e))
                 ((ok execT)
                  (mt (floatOf queueRaw)
                    ((err e) (raise e))
                    ((ok queueT)
                     (let [(promptBytes (bytesLength (stringToBytes prompt)))]
                       (if (and (= prov "agy-cli") (and agentOn (> promptBytes cx.world.agyPromptMaxBytes)))
                         (sendError cx l.head 413 (str "agy prompt is " (stringFromInt64 promptBytes) " bytes, over the "
                                                          (stringFromInt64 cx.world.agyPromptMaxBytes) " bytes agy keeps; shorten the message") true)
                         (cliDispatch cx l a prompt system noTools effort temp execT queueT agent bodyObj)))))))))))))))

fn cliDispatch cx: Ctx l: Loop a: Attempt prompt: String system: String noTools: Bool effort: j/Json temp: j/Json execT: Float64 queueT: Float64 agent: j/Json bodyObj: j/Json -> ChatStep
  (let [(prov a.upstream.provider)
        (m a.model)
        (ws cx.workspace)
        (sysJ (if (stringEmpty? system) (j/jnull) (j/jstr system)))
        (plan (cond
                ((= prov "agy-cli")
                 (let [(sub (cond ((stringStartsWith? m "agy/") (u/slice m 4 (stringLength m))) ((or (= m "agy") (= m "antigravity")) "gemini-3.8-flash") (else m)))]
                   (pair (pair "agy" (str "agy:" sub))
                         (cliArgs agent (getOr bodyObj "addDirs" (j/jnull)) prompt sub effort execT queueT ws system noTools))))
                ((= prov "codex-cli")
                 (let [(sub (cond ((stringStartsWith? m "codex/") (some (u/slice m 6 (stringLength m)))) ((= m "codex") none) (else (some m))))]
                   (pair (pair "codex" (str "codex:" (optionOr sub "default")))
                         (list (pair "prompt" (j/jstr prompt)) (pair "model" (mt sub ((some s) (j/jstr s)) ((none) (j/jnull)))) (pair "temp" temp)
                               (pair "effort" effort) (pair "timeout" (j/jfloat execT)) (pair "queue_timeout" (j/jfloat queueT))
                               (pair "workspace" (j/jstr ws)) (pair "system_prompt" sysJ) (pair "no_tools" (j/jbool noTools))))))
                (else
                 (let [(sub (if (stringStartsWith? m "claude/") (some (u/slice m 7 (stringLength m))) none))]
                   (pair (pair "claude" (str "claude:" (optionOr sub "default")))
                         (list (pair "prompt" (j/jstr prompt)) (pair "model" (mt sub ((some s) (j/jstr s)) ((none) (j/jnull))))
                               (pair "timeout" (j/jfloat execT)) (pair "queue_timeout" (j/jfloat queueT)) (pair "workspace" (j/jstr ws))
                               (pair "system_prompt" sysJ) (pair "no_tools" (j/jbool noTools)) (pair "effort" effort)))))))
        (client (pairFirst (pairFirst plan)))
        (telModel (pairSecond (pairFirst plan)))
        (sentEffort (mt effort ((j/jstr s) (if (listContains? (list "low" "medium" "high" "xhigh" "max") s) (some s) none)) (_ none)))
        (onReply (fn [(r (Option CliReply))] -> ChatStep
                   (mt r
                     ((some reply) (cliReplied cx l a reply client telModel sentEffort))
                     ((none)
                      (tell (usageNote prov a.alias "failed")
                        (fn [] -> ChatStep
                          (if (> (listLength l.models) 1)
                            (tell (effUsageFallback prov a.alias) (fn [] -> ChatStep (loopStep cx (advance l l.body))))
                            (sendError cx l.head 502 (str "CLI worker " prov " failed or returned empty response") true))))))))]
    (if (stringEmpty? prompt)
      (onReply none)
      (askCli (effCli client (pairSecond plan)) onReply)))

fn usageInt u: j/Json k: String -> Int64
  (mt (getOr u k (j/jnull)) ((j/jint n) n) (_ 0))

fn cliReplied cx: Ctx l: Loop a: Attempt reply: CliReply client: String telModel: String sentEffort: (Option String) -> ChatStep
  (let [(prov a.upstream.provider)
        (tag (str client "-cli"))
        (text (maybeSanitize cx reply.text))]
    (telemetry cx (j/jstr text) telModel
      (fn [(rec (Option String))] -> ChatStep
        (askFloat (effClock)
          (fn [(t Float64)] -> ChatStep
            (let [(ts (truncInt t))
                  (usage reply.usage)
                  (hasUsage (pt/pyTruthy usage))
                  (pool (if (stringEmpty? reply.pool) client reply.pool))
                  (asl0 (list (pair "queueWaitSec" (round3 reply.queueWaitSec)) (pair "execSec" (round3 reply.execSec)) (pair "pool" (j/jstr pool))))
                  (asl1 (if hasUsage (listAppend asl0 (list (pair "usage" usage))) asl0))
                  (asl2 (if reply.dedup (listAppend asl1 (list (pair "dedup" (j/jbool true)))) asl1))
                  (asl3 (u/objSet asl2 "alias" (j/jstr a.alias)))
                  (asl4 (mt sentEffort ((some s) (u/objSet asl3 "effort" (j/jstr s))) ((none) asl3)))
                  (resp0 (completionJson (str "chatcmpl-" tag "-" (stringFromInt64 ts)) ts telModel text asl4))
                  (resp (if hasUsage
                          (pt/jset resp0 "usage" (j/jobj (list (pair "prompt_tokens" (getOr usage "inputTokens" (j/jnull)))
                                                              (pair "completion_tokens" (getOr usage "outputTokens" (j/jnull)))
                                                              (pair "total_tokens" (j/jint (+ (usageInt usage "inputTokens") (usageInt usage "outputTokens"))))
                                                              (pair "cached_tokens" (getOr usage "cachedTokens" (j/jnull))))))
                          resp0))
                  (ordered resp)]
              (tell (effUsageNote prov a.alias "ok" usage)
                (fn [] -> ChatStep
                  (sendReply cx l.head 200 ordered (cons (pair "X-ASL-Fallback" tag) (telemetryHeader rec)))))))))))


fn rateAttempt cx: Ctx l: Loop a: Attempt -> ChatStep
  (let [(prov a.upstream.provider)
        (rpm (mt a.v2 ((some e) e.rpm) ((none) (if (= prov "gemini") (some 15.0) none))))]
    (mt rpm
      ((some r)
       (if (!= r 0.0)
         (askBool (effBucket a.target r 0.5)
           (fn [(acquired Bool)] -> ChatStep
             (if acquired
               (httpAttempt cx l a)
               (tellAll (list (usageNote prov a.alias "throttled") (effUsageFallback prov a.alias))
                 (fn [] -> ChatStep
                   (if cx.profileRouted
                     (tell (effLog (str "[Gateway RateLimit] Gemini token bucket depleted for " a.alias ". Trying the next profile model...\n"))
                       (fn [] -> ChatStep (loopStep cx (failed (advance l l.body) (str "gemini rate limit for " a.alias)))))
                     (tell (effLog (str "[Gateway RateLimit] Gemini token bucket depleted for " a.model ". Cascading to agy fallback...\n"))
                       (fn [] -> ChatStep
                         (mt (fallbackPrompt l.body)
                           ((err e) (raise e))
                           ((ok prompt)
                            (agyFallback cx prompt
                              (fn [(r (Option CliReply))] -> ChatStep
                                (mt r
                                  ((some reply) (agyReply cx l reply))
                                  ((none) (loopStep cx (advance l l.body))))))))))))))))
         (httpAttempt cx l a)))
      ((none) (httpAttempt cx l a))))

fn upTimeout cx: Ctx l: Loop a: Attempt -> (Result Float64 pt/PyErr)
  (let [(body l.body)
        (fallback (fn [] -> Float64
                    (mt a.v2
                      ((some e) (if (!= e.timeoutSec 0.0) e.timeoutSec (u/upstreamTimeoutSec cx.world.settings a.upstream.provider)))
                      ((none) (u/upstreamTimeoutSec cx.world.settings a.upstream.provider)))))]
    (if (and (some? a.v2) (and (isObj? body) (pt/pyTruthy (getOr body "timeout" (j/jnull)))))
      (floatOf (getOr body "timeout" (j/jnull)))
      (ok (fallback))))

fn httpAttempt cx: Ctx l: Loop a: Attempt -> ChatStep
  (let [(up a.upstream)]
    (mt (u/upstreamRequest up.url cx.path up.key a.data cx.req.headers)
      ((err s) (raise (splitErr s)))
      ((ok request)
       (mt (upTimeout cx l a)
         ((err e) (raised cx l a false e.msg))
         ((ok timeout)
          (askHttp (mt a.poolConfig
            ((some poolConfig) (effPoolHttp up.provider a.model up.url poolConfig request timeout))
            ((none) (effHttp up.provider a.target cx.intent cx.role request timeout)))
            (fn [(r HttpReply)] -> ChatStep
              (mt r
                ((httpOk status headers body) (httpAnswered cx l a status headers body))
                ((httpError status reason headers body) (httpFailed cx l a status reason headers body))
                ((httpRaised timeout text) (raised cx l a timeout text))))))))))

fn raised cx: Ctx l: Loop a: Attempt timeout: Bool text: String -> ChatStep
  (let [(prov a.upstream.provider)
        (pool a.pool)
        (l1 (failed l text))
        (rest (fn [] -> ChatStep
                (tell (usageNote prov a.alias (if timeout "timeout" "other"))
                  (fn [] -> ChatStep
                    (if (> cx.cascadeLen 1)
                      (tellAll (list (effUsageFallback prov a.alias) (effLog (str "[Gateway Cascade] Model " a.model " error: " text ". Cascading to next...\n")))
                        (fn [] -> ChatStep (loopStep cx (advance l1 l1.body))))
                      (loopStep cx (advance l1 l1.body)))))))]
    (if (stringEmpty? pool) (rest) (tell (effBreakerEvent "reset503" pool) rest)))

(schema Projection
  (:f resp j/Json)
  (:f content j/Json))

fn project body: String -> (Option Projection)
  (mt (pt/jsonLoads body)
    ((err _) none)
    ((ok resp)
     (if (not (isObj? resp))
       none
       (let [(choices (getOr resp "choices" (j/jarr (list (j/jobj (list))))))
             (first (mt choices ((j/jarr xs) (listHead xs)) (_ none)))]
         (mt first
           ((some c)
            (if (isObj? c)
              (let [(msg (getOr c "message" (j/jobj (list))))]
                (if (isObj? msg) (some (Projection :resp resp :content (getOr msg "content" (j/jnull)))) none))
              none))
           ((none) none))))))

fn emptyContent? v: j/Json -> Bool
  (mt v ((j/jnull) true) ((j/jstr s) (stringEmpty? (u/pyStrip s))) (_ false))

fn sanitizeFirst resp: j/Json f: (fn [String] -> String) -> j/Json
  (mt (getOr resp "choices" (j/jnull))
    ((j/jarr xs)
     (mt (listHead xs)
       ((some c)
        (mt (getOr c "message" (j/jnull))
          ((j/jobj _)
           (let [(msg (getOr c "message" (j/jnull)))
                 (content (getOr msg "content" (j/jnull)))
                 (newMsg (mt content ((j/jstr s) (pt/jset msg "content" (j/jstr (f s)))) (_ msg)))]
             (pt/jset resp "choices" (j/jarr (cons (pt/jset c "message" newMsg) (optionOr (listTail xs) (list)))))))
          (_ resp)))
       ((none) resp)))
    (_ resp))

fn servedBy a: Attempt body: j/Json -> (List (Pair String j/Json))
  (let [(base (list (pair "alias" (j/jstr a.alias))))
        (withEffort (mt a.sentEffort
                      ((some e) (mt e ((some s) (listAppend base (list (pair "effort" (j/jstr s))))) ((none) base)))
                      ((none) base)))
        (temp (if (isObj? body) (getOr body "temperature" (j/jnull)) (j/jnull)))]
    (if (isNull? temp) withEffort (listAppend withEffort (list (pair "temperature" temp)))))

fn mergeAsl resp: j/Json served: (List (Pair String j/Json)) -> j/Json
  (let [(existing (mt (getOr resp "asl" (j/jnull)) ((j/jobj kvs) kvs) (_ (list))))]
    (pt/jset resp "asl" (j/jobj (fold (fn [(acc (List (Pair String j/Json))) (p (Pair String j/Json))] -> (List (Pair String j/Json))
                                        (u/objSet acc (pairFirst p) (pairSecond p)))
                                      existing served))))

fn dropHeaders hs: (List (Pair String String)) names: (List String) -> (List (Pair String String))
  (filter (fn [(p (Pair String String))] -> Bool (not (listContains? names (u/pyLower (pairFirst p))))) hs)

fn httpAnswered cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) body: String -> ChatStep
  (let [(prov a.upstream.provider)
        (alias a.alias)
        (m a.model)
        (proj (project body))]
    (mt proj
      ((some p)
       (if (emptyContent? p.content)
         (tell (usageNote prov alias "empty")
           (fn [] -> ChatStep
             (let [(action (u/emptyContentAction cx.cascadeLen l.emptyRetries))]
               (cond
                 ((= action "cascade")
                  (tellAll (list (effUsageFallback prov alias)
                                 (effLog (str "[Gateway Cascade] Model " m " returned empty content (reasoning exhausted tokens). Cascading to next...\n")))
                    (fn [] -> ChatStep (loopStep cx (advance l l.body)))))
                 ((= action "retry")
                  (tell (effLog (str "[Gateway Cascade] Model " m " returned empty content on a single-model cascade. Retrying once...\n"))
                    (fn [] -> ChatStep
                      (loopStep cx (with l :models (listAppend l.models (list a.entry)) :idx (+ l.idx 1) :emptyRetries (+ l.emptyRetries 1))))))
                 (else (sendError cx l.head 502 (str "ERR_EMPTY_CONTENT: model " m " returned empty content after "
                                                         (stringFromInt64 l.emptyRetries) " retry") true))))))
         (let [(content p.content)
               (sanitized (if cx.sanitize (sanitizeFirst p.resp w/sanitizeAsnContent) p.resp))]
           (telemetry cx content m
             (fn [(rec (Option String))] -> ChatStep
               (let [(withModel (if (has? sanitized "model") sanitized (pt/jset sanitized "model" (j/jstr a.target))))
                     (resp (mergeAsl withModel (servedBy a l.body)))
                     (lb (with l :telBound true))]
                 (answered cx lb a status headers (pt/jsonDumps resp -1) (some resp) rec)))))))
      ((none) (answered cx l a status headers body none none))))

fn answered cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) respBody: String resp: (Option j/Json) rec: (Option String) -> ChatStep
  (let [(prov a.upstream.provider)
        (pool a.pool)
        (usage (mt resp ((some r) (getOr r "usage" (j/jnull))) ((none) (j/jnull))))
        (finish (fn [] -> ChatStep
                  (mt resp
                    ((some r)
                     (if cx.asn
                       (sendReply cx l.head status r (telemetryHeader rec))
                       (passthrough cx l a status headers respBody rec)))
                    ((none) (passthrough cx l a status headers respBody rec)))))]
    (tell (effUsageNote prov a.alias "ok" usage)
      (fn [] -> ChatStep (if (stringEmpty? pool) (finish) (tell (effBreakerEvent "clear" pool) finish)))))

fn passthrough cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) respBody: String rec: (Option String) -> ChatStep
  (let [(head (listAppend l.head
                          (cons (headStatus status)
                                (listAppend (fields (dropHeaders headers (list "transfer-encoding" "content-encoding" "content-length")))
                                            (list (headField "Content-Length" (stringFromInt64 (bytesLength (stringToBytes respBody)))))))))]
    (if l.telBound
      (done (listAppend head (listAppend (fields (telemetryHeader rec)) (list (headField "X-ASL-Wire" "asn,json")))) respBody)
      (let [(lh (with l :telBound false :head head))]
        (raised cx lh a false "cannot access local variable 'tel_rec' where it is not associated with a value"))))

fn gatewayOriginHeader -> String
  "X-ASL-Origin"

fn gatewayOrigin? headers: (List (Pair String String)) -> Bool
  (listAny? (fn [(h (Pair String String))] -> Bool (and (= (stringLower (pairFirst h)) (stringLower (gatewayOriginHeader))) (= (pairSecond h) "gateway"))) headers)

fn httpFailed cx: Ctx l: Loop a: Attempt status: Int64 reason: String headers: (List (Pair String String)) body: String -> ChatStep
  (let [(prov a.upstream.provider)
        (alias a.alias)
        (pool a.pool)
        (errText (u/httpErrorText status reason))
        (l1 (failed l errText))
        (event (cond
                 ((or (= status 429) (b/breakerIsQuotaError body)) "markDown")
                 ((= status 503) "note503")
                 (else "reset503")))
        (relay (fn [] -> ChatStep
                 (if cx.asn
                   (sendError cx l1.head status (w/upstreamErrorReason body errText) true)
                   (done (listAppend l1.head (cons (headStatus status)
                                                       (listAppend (fields (dropHeaders headers (list "transfer-encoding" "content-encoding")))
                                                                   (list (headField "X-ASL-Wire" "asn,json")))))
                         body))))
        (after (fn [] -> ChatStep
                 (tell (usageNote prov alias (g/usageHttpError status))
                   (fn [] -> ChatStep
                     (cond
                       (cx.profileRouted
                        (tellAll (list (effLog (str "[Gateway Profile] Model " alias " returned HTTP " (stringFromInt64 status) ". Trying the next profile model...\n"))
                                       (effUsageFallback prov alias))
                          (fn [] -> ChatStep (loopStep cx (advance l1 l1.body)))))
                       ((listContains? (list 429 502 503 504) status)
                        (tellAll (list (effUsageFallback prov alias)
                                       (effLog (str "[Gateway Cascade] Model " a.model " returned HTTP " (stringFromInt64 status) ". Checking agy fallback...\n")))
                          (fn [] -> ChatStep
                            (mt (fallbackPrompt l1.body)
                              ((err e) (raise e))
                              ((ok prompt)
                               (agyFallback cx prompt
                                 (fn [(r (Option CliReply))] -> ChatStep
                                   (mt r
                                     ((some reply) (agyReply cx l1 reply))
                                     ((none) (if (> cx.cascadeLen 1) (loopStep cx (advance l1 l1.body)) (relay)))))))))))
                       (else (relay)))))))]
    (if (or (stringEmpty? pool) (gatewayOrigin? headers)) (after) (tell (effBreakerEvent event pool) after)))


fn labels models: (List c/GatewayResolvedEntry) -> String
  (stringJoin (map c/gatewayEntryLabel models) ", ")

fn lastErrSuffix l: Loop -> String
  (mt l.lastErr ((some e) (str "; last error: " e)) ((none) ""))

fn uniqueSorted xs: (List String) -> (List String)
  (listSort (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn maxFloat fs: (List Float64) -> Float64
  (fold (fn [(acc Float64) (f Float64)] -> Float64 (if (> f acc) f acc)) (optionOr (listHead fs) 0.0) fs)

fn afterLoop cx: Ctx l: Loop -> ChatStep
  (let [(skipped l.skipped)
        (model cx.explicitModel)]
    (cond
      ((and (not (listEmpty? skipped)) (>= (listLength skipped) cx.cascadeLen))
       (let [(pools (uniqueSorted skipped))]
         (askFloats (effBreakerDownAll pools)
           (fn [(lefts (List Float64))] -> ChatStep
             (sendError cx l.head 503 (str "providers " (stringJoin pools ", ") " are in circuit-breaker cooldown after quota or timeout failures; retry in "
                                               (stringFromInt64 (truncInt (maxFloat lefts))) "s") true)))))
      (cx.profileRouted
       (sendError cx l.head 502 (str "profile " cx.profileName ": no model answered (" (labels l.models) ")" (lastErrSuffix l)) true))
      ((and (not (stringEmpty? model)) (not (or (= model "agy") (stringStartsWith? model "agy/"))))
       (sendError cx l.head 502 (str "ERR_NO_UPSTREAM: model " model " failed" (lastErrSuffix l)) true))
      (else
       (mt (fallbackPrompt l.body)
         ((err e) (raise e))
         ((ok prompt)
          (agyFallback cx prompt
            (fn [(r (Option CliReply))] -> ChatStep
              (mt r
                ((some reply) (agyReply cx l reply))
                ((none)
                 (mt l.lastErr
                   ((some e) (sendError cx l.head 500 e false))
                   ((none) (done l.head ""))))))))))))


fn optJson v: (Option String) -> j/Json
  (mt v ((some s) (j/jstr s)) ((none) (j/jnull)))

fn pairsJson hs: (List (Pair String String)) -> j/Json
  (j/jarr (map (fn [(p (Pair String String))] -> j/Json (j/jarr (list (j/jstr (pairFirst p)) (j/jstr (pairSecond p))))) hs))

fn effectJson eff: ChatEffect -> j/Json
  (let [(op (fn [(name String) (rest (List (Pair String j/Json)))] -> j/Json (j/jobj (cons (pair "op" (j/jstr name)) rest))))]
    (mt eff
      ((effRealpath p) (op "realpath" (list (pair "path" (j/jstr p)))))
      ((effIsDir p) (op "isDir" (list (pair "path" (j/jstr p)))))
      ((effClock) (op "clock" (list)))
      ((effBreakerDown p) (op "breakerDown" (list (pair "pool" (j/jstr p)))))
      ((effBreakerDownAll ps) (op "breakerDownAll" (list (pair "pools" (j/jarr (map (fn [(p String)] -> j/Json (j/jstr p)) ps))))))
      ((effBreakerEvent e p) (op "breaker" (list (pair "event" (j/jstr e)) (pair "pool" (j/jstr p)))))
      ((effUsageNote p a o u) (op "usageNote" (list (pair "provider" (j/jstr p)) (pair "alias" (j/jstr a)) (pair "outcome" (j/jstr o)) (pair "usage" u))))
      ((effUsageFallback p a) (op "usageFallback" (list (pair "provider" (j/jstr p)) (pair "alias" (j/jstr a)))))
      ((effTelemetry r) (op "telemetry" (list (pair "rec" (optJson r)))))
      ((effNoteIntent i) (op "noteIntent" (list (pair "intent" (j/jstr i)))))
      ((effLog t) (op "log" (list (pair "text" (j/jstr t)))))
      ((effBucket m r t) (op "bucket" (list (pair "model" (j/jstr m)) (pair "rpm" (j/jfloat r)) (pair "timeout" (j/jfloat t)))))
      ((effPoolHttp p m base pool req t)
       (op "poolHttp" (list (pair "provider" (j/jstr p)) (pair "model" (j/jstr m)) (pair "base" (j/jstr base))
                            (pair "windowMs" (j/jint pool.config.windowMs)) (pair "peakCount" (j/jint pool.config.peakCount))
                            (pair "bypassWhileBusy" (j/jbool pool.config.bypassWhileBusy))
                            (pair "requestTimeoutMs" (j/jint pool.config.requestTimeoutMs))
                            (pair "batch" (j/jbool pool.batch)) (pair "scaleDownPath" (j/jstr pool.scaleDownPath))
                            (pair "url" (j/jstr (if (stringEmpty? req.fragment) req.url (str req.url "#" req.fragment))))
                            (pair "method" (j/jstr req.method)) (pair "headers" (pairsJson req.headers))
                            (pair "data" (j/jstr req.data)) (pair "timeout" (j/jfloat t)))))
      ((effHttp _ _ _ _ req t)
       (op "http" (list (pair "url" (j/jstr (if (stringEmpty? req.fragment) req.url (str req.url "#" req.fragment))))
                        (pair "method" (j/jstr req.method)) (pair "headers" (pairsJson req.headers))
                        (pair "data" (j/jstr req.data)) (pair "timeout" (j/jfloat t)))))
      ((effCli c args) (op "cli" (list (pair "client" (j/jstr c)) (pair "args" (j/jobj args)))))))

fn headJson head: (List HeadItem) -> j/Json
  (j/jarr (map (fn [(h HeadItem)] -> j/Json
                 (mt h
                   ((headStatus c) (j/jarr (list (j/jstr ":status") (j/jstr (stringFromInt64 c)))))
                   ((headField n v) (j/jarr (list (j/jstr n) (j/jstr v))))))
               head))
