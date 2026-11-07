(module aslGateway/chat
  :x [ChatRequest upstreamTools
      sseToChat
      streamBody
      gatewayOriginHeader
      ChatWorld
      ChatEffect
      effortDialectFor
      applyEffort
      effRealpath
      effIsDir
      effClock
      effBreakerDown
      effBreakerDownAll
      effBreakerEvent
      effUsageNote
      effLimit
      effUsageFallback
      effSpreadOrder
      effSpreadNote429
      effAffinity
      effAffinityNote
      effTelemetry
      effNoteIntent
      effLog
      effBucket
      effSleepMs
      effHttp
      effPoolHttp
      effCli
      cliCallerKey
      promptEstimate contextOverflowError? maxBudgetOf byBudget
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
      outStrings
      HeadItem
      headStatus
      headField
      ChatResponse
      ChatStep
      stepEffect
      stepDone
      stepRaised
      modelCascade
      chatStart!
      effectJson
      headJson
      Ctx
      Loop
      Attempt
      httpAttempt
      httpFailed
      raised
      anthropicBody
      cacheHints
      credentialKey
      missingKeyWhy
      missingKey
      anthropicCacheHints
      anthropicToChat
      anthropicMessagesOf
      anthropicStopReasonToFinish
      geminiBody
      geminiToChat
      geminiMessagesOf
      geminiFinishReasonToFinish]
  :i [(asl-json/json :a j)
      (upstream :a u)
      (config :a c)
      (wire :a w)
      (pyText :a pt)
      (usage :a g)
      (breaker :a b)
      (localTime :a lt)
      (limits :a lim)
      (aslGateway/dispatch :a dp)
      (secrets :a sc)])

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
  ; (:m :ref GW-PARK-TYPED :do "parkSec is the seconds a markDown event parks the pool for, 0 meaning the breaker's fixed cooldown; control data rides on the event, never inside the pool name")
  (:c effBreakerEvent [(event String) (pool String) (parkSec Int64)])
  (:c effUsageNote [(provider String) (alias String) (outcome String) (usage j/Json)])
  (:c effUsageFallback [(provider String) (alias String)])
  ; (:m :ref GW-LIMIT-WINDOWS :do "asks the reactor whether a provider limit window is spent for this member; the answer is empty to go ahead, else (outcome reason)")
  (:c effLimit [(provider String) (alias String)])
  ; (:m :ref GW-SPREAD-LIVE-20261018 :do "asks the server for this call's spread-member order: real per-profile+intent SWRR state (GatewayLoop.spreadState) and real breaker/429-cooldown availability live server-side, never in chat.asl; pools carries one (alias, providerPool:alias) pair per spread member so the server can check the real BreakerState without re-resolving the config table")
  (:c effSpreadOrder [(profile String) (intent String) (spread (List (Pair String Int64))) (cooldownSec Int64) (pools (List (Pair String String)))])
  ; (:m :ref GW-SPREAD-LIVE-20261018 :do "records this alias's 429 at the server's own wall clock (GatewayLoop.spreadLast429), independent of and in addition to the existing per-model breaker trip -- :cooldownSec is configurable per route and almost never equals BreakerState's own fixed cooldown")
  (:c effSpreadNote429 [(alias String)])
  ; (:m :ref GW-SESSION-AFFINITY :do "asks the server for a session's last answering member: empty, or (alias stick drop) with stick and drop 1 or 0; a driver that answers done means none")
  (:c effAffinity [(session String)])
  (:c effAffinityNote [(session String) (alias String)])
  (:c effTelemetry [(rec (Option String))])
  (:c effNoteIntent [(intent String)])
  (:c effLog [(text String)])
  (:c effBucket [(model String) (rpm Float64) (timeout Float64)])
  (:c effSleepMs [(ms Int64)])
  (:c effHttp [(provider String) (model String) (intent String) (role String) (request u/UpstreamRequest) (timeout Float64) (profile String) (firstByteSec Float64)])
  (:c effPoolHttp [(provider String) (model String) (base String) (pool c/GatewayPool) (request u/UpstreamRequest) (timeout Float64)])
  (:c effCli [(client String) (args (List (Pair String j/Json)))]))

(schema CliReply
  (:f text String)
  (:f usage j/Json)
  (:f dedup Bool)
  (:f queueWaitSec Float64)
  (:f execSec Float64)
  (:f pool String)
  (:f binding j/Json))

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
  (:c outHttp [(reply HttpReply)])
  (:c outStrings [(items (List String))]))

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
  (:f cascadeLen Int64)
  ; (:m :ref GW-SPREAD-LIVE-20261018 :do "the matched route's :spread/:cooldownSec, carried from config.asl's RouteEntries through withProfile so cascadeChosen can order Loop.models by spreadOrder before construction; empty spread (the default for any route without one) means startLoop skips the effect entirely, unchanged behaviour")
  (:f spread (List (Pair String Int64)))
  (:f cooldownSec Int64)
  ; (:m :ref GW-SESSION-AFFINITY :do "the caller session key (cliCallerKey), the member that last answered it (empty when none) and whether another member gets the transcript without its reasoning")
  (:f session String)
  (:f stuck String)
  (:f dropOnSwitch Bool)
  ; (:m :ref GW-AFFINITY-SPREAD :do "seconds the sticking member (stuck) waits for its rpm token, 0 when the session does not stick")
  (:f stickWaitSec Float64)
  ; (:m :ref GW-AFFINITY-SPREAD :do "true while the session sticks to stuck (inside :affinityStickSec)")
  (:f sticking Bool)
  ; (:m :ref GW-MODES :do "the selected profile's mode (pin, route or judge) and judge rules, set by withProfile; route and the default rules before")
  (:f mode String)
  (:f judge c/JudgeRules)
  (:f excludeModel String))

(schema Loop
  (:f body j/Json)
  (:f models (List c/GatewayResolvedEntry))
  (:f idx Int64)
  (:f lastErr (Option String))
  (:f skipped (List String))
  (:f emptyRetries Int64)
  (:f telBound Bool)
  (:f head (List HeadItem))
  ; (:m :ref HUB-QUEUE-PACED :do "seconds to the next bucket token when the last failure was a refused rpm bucket, else 0; afterLoop answers 429 with this Retry-After")
  (:f retryAfterSec Int64)
  ; (:m :ref CTX-ROUTE :do "context routing state: ctxNeed is the contextBudget a later member must exceed after a member overflowed its window (0 none), ctxFails the members skipped or failed for context, ctxEst the largest prompt estimate seen")
  (:f ctxNeed Int64)
  (:f ctxFails Int64)
  (:f ctxEst Int64))

(schema Attempt
  (:f entry c/GatewayResolvedEntry)
  (:f v2 (Option c/GatewayEntry))
  (:f model String)
  (:f target String)
  (:f upstream u/UpstreamEndpoint)
  (:f alias String)
  (:f pool String)
  (:f providerPool String)
  (:f sentEffort (Option (Option String)))
  (:f poolConfig (Option c/GatewayPool))
  (:f data String)
  (:f api String)
  (:f path String)
  (:f retryUsed Int64)
  (:f retryDeadline (Option Float64)))


; (:m :do "role/intent cascades and their calibrated default temperatures come from the gateway config's profile routes, never from a built-in list in source; a role or intent string is resolved the same way an intent is for the profile-routed path (c/gatewayRouteEntries!), so a config-only change to a route's :chain or :temperature changes the chosen model with no rebuild")
fn configuredRoute! world: ChatWorld headers: (List (Pair String String)) key: String -> (Option c/RouteEntries)
  (if (stringEmpty? key) none
    (match world.table
      ((err _) none)
      ((ok tbl)
       (match (c/gatewayRouteEntriesExact! tbl headers (mapGet world.env "ASL_GATEWAY_PROFILE") key)
         ((err _) none)
         ((ok re) (if (listEmpty? re.entries) none (some re)))))))

fn cxConfiguredRoute! cx: Ctx key: String -> (Option c/RouteEntries)
  (configuredRoute! cx.world cx.req.headers key)

fn cxRouteTemperature! cx: Ctx key: String -> (Option Float64)
  (match (cxConfiguredRoute! cx key) ((some re) re.temperature) ((none) none))

; (:m :do "if the caller's literal model string is itself a member of some configured route's :chain, treat it as a request for that whole cascade (try it, then its configured siblings) instead of a single dead end; a reverse lookup against config, never a built-in model list")
fn modelCascade cx: Ctx model: String -> (Option (List String))
  (if (stringEmpty? model) none
    (match cx.world.table
      ((err _) none)
      ((ok tbl) (c/gatewayChainContainingModel! tbl cx.req.headers (mapGet cx.world.env "ASL_GATEWAY_PROFILE") model))))


fn raise e: pt/PyErr -> ChatStep
  (stepRaised e.kind e.msg)

fn splitErr s: String -> pt/PyErr
  (match (stringIndexOf s ": ")
    ((some i) (pt/pyErr (u/slice s 0 i) (u/slice s (+ i 2) (stringLength s))))
    ((none) (pt/pyErr "Exception" s)))

fn attrErr v: j/Json attr: String -> pt/PyErr
  (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName v) "' object has no attribute '" attr "'"))

fn itemErr v: j/Json -> pt/PyErr
  (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object does not support item assignment"))

fn isObj? v: j/Json -> Bool
  (match v ((j/jobj _) true) (_ false))

fn isNull? v: j/Json -> Bool
  (match v ((j/jnull) true) (_ false))

fn has? v: j/Json k: String -> Bool
  (some? (pt/jget v k))

fn getOr v: j/Json k: String d: j/Json -> j/Json
  (optionOr (pt/jget v k) d)

fn jdel v: j/Json k: String -> j/Json
  (match v
    ((j/jobj kvs) (j/jobj (filter (fn [(p (Pair String j/Json))] -> Bool (!= (pairFirst p) k)) kvs)))
    (_ v))

fn keysOf v: j/Json -> (List String)
  (match v ((j/jobj kvs) (map (fn [(p (Pair String j/Json))] -> String (pairFirst p)) kvs)) (_ (list)))

fn strOr v: j/Json d: String -> String
  (match v ((j/jstr s) s) (_ d))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (u/slice s 1 (stringLength s))) s)

fn norm s: String -> String
  (u/pyLower (lstripColons s))

fn truncInt f: Float64 -> Int64
  (optionOr (float64ToInt64 f) 0)

fn present v: (Option String) -> (Option String)
  (match v ((some s) (if (stringEmpty? s) none (some s))) ((none) none))

fn fieldIfBody body: j/Json key: String -> (Result j/Json pt/PyErr)
  (if (pt/pyTruthy body)
    (if (isObj? body) (ok (getOr body key (j/jnull))) (err (attrErr body "get")))
    (ok (j/jstr "")))

fn normField hdr: (Option String) body: j/Json key: String -> (Result String pt/PyErr)
  (match (present hdr)
    ((some h) (ok (norm h)))
    ((none)
     (match (fieldIfBody body key)
       ((err e) (err e))
       ((ok v)
        (if (pt/pyTruthy v)
          (match v ((j/jstr s) (ok (norm s))) (_ (err (attrErr v "lstrip"))))
          (ok ""))))))

fn roleField world: ChatWorld headers: (List (Pair String String)) body: j/Json -> (Result String pt/PyErr)
  (match (present (u/headerGet headers "X-ASL-Role"))
    ((some h) (ok (norm h)))
    ((none)
     (match (fieldIfBody body "role")
       ((err e) (err e))
       ((ok v)
        (if (pt/pyTruthy v)
          (match v ((j/jstr s) (ok (norm s))) (_ (err (attrErr v "lstrip"))))
          (if (pt/pyTruthy body)
            (let [(model (getOr body "model" (j/jnull)))]
              (match model
                ((j/jstr s) (ok (if (some? (configuredRoute! world headers (norm s))) (norm s) "")))
                ((j/jarr _) (err (pt/pyErr "TypeError" "unhashable type: 'list'")))
                ((j/jobj _) (err (pt/pyErr "TypeError" "unhashable type: 'dict'")))
                (_ (ok ""))))
            (ok "")))))))

fn floatOf v: j/Json -> (Result Float64 pt/PyErr)
  (match v
    ((j/jint i) (ok (int64ToFloat64 i)))
    ((j/jfloat f) (ok f))
    ((j/jnum f) (ok f))
    ((j/jbool b) (ok (if b 1.0 0.0)))
    ((j/jstr s) (match (u/pyFloat s) ((ok f) (ok f)) ((err _) (err (pt/pyErr "ValueError" (str "could not convert string to float: " (pt/pyRepr v)))))))
    (_ (err (pt/pyErr "TypeError" (str "float() argument must be a string or a real number, not '" (pt/pyTypeName v) "'")))))

fn numberOf v: j/Json -> (Option Float64)
  (match v
    ((j/jint i) (some (int64ToFloat64 i)))
    ((j/jfloat f) (some f))
    ((j/jnum f) (some f))
    ((j/jbool b) (some (if b 1.0 0.0)))
    (_ none))

fn escapeAsnStr v: j/Json -> String
  (u/replaceAll (u/replaceAll (u/replaceAll (u/replaceAll (u/replaceAll (pt/pyStr v) "\\" "\\\\") "\"" "\\\"") "\n" " ") "\r" " ") "\t" " ")

fn messageText content: j/Json -> (Result String pt/PyErr)
  (match content
    ((j/jnull) (ok ""))
    ((j/jarr parts)
     (match (fold (fn [(acc (Result (List String) pt/PyErr)) (p j/Json)] -> (Result (List String) pt/PyErr)
                 (match acc
                   ((err e) (err e))
                   ((ok xs)
                    (if (and (isObj? p) (pt/pyTruthy (getOr p "text" (j/jnull))))
                      (match (getOr p "text" (j/jnull))
                        ((j/jstr t) (ok (cons t xs)))
                        (_ (err (pt/pyErr "TypeError" "sequence item: expected str instance"))))
                      (ok xs)))))
               (ok (list)) parts)
       ((err e) (err e))
       ((ok xs) (ok (stringJoin (listReverse xs) "\n")))))
    (_ (ok (pt/pyStr content))))

fn messageList v: j/Json -> (Result (List j/Json) pt/PyErr)
  (match v
    ((j/jarr xs) (ok xs))
    ((j/jstr _) (err (attrErr (j/jstr "") "get")))
    ((j/jobj _) (err (attrErr (j/jstr "") "get")))
    (_ (err (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object is not iterable")))))

fn msgGet msg: j/Json key: String d: j/Json -> (Result j/Json pt/PyErr)
  (if (isObj? msg) (ok (getOr msg key d)) (err (attrErr msg "get")))

fn promptOf msgs: (List j/Json) keep: (fn [j/Json] -> (Result Bool pt/PyErr)) -> (Result String pt/PyErr)
  (match (fold (fn [(acc (Result (List String) pt/PyErr)) (msg j/Json)] -> (Result (List String) pt/PyErr)
              (match acc
                ((err e) (err e))
                ((ok parts)
                 (match (keep msg)
                   ((err e) (err e))
                   ((ok kept)
                    (if (not kept)
                      (ok parts)
                      (match (msgGet msg "role" (j/jstr "user"))
                        ((err e) (err e))
                        ((ok role)
                         (match (msgGet msg "content" (j/jstr ""))
                           ((err e) (err e))
                           ((ok content) (ok (cons (str "[" (pt/pyStr role) "]:\n" (pt/pyStr content)) parts))))))))))))
            (ok (list)) msgs)
    ((err e) (err e))
    ((ok parts) (ok (stringJoin (listReverse parts) "\n\n"))))

fn contentKept msg: j/Json -> (Result Bool pt/PyErr)
  (match (msgGet msg "content" (j/jnull)) ((err e) (err e)) ((ok c) (ok (pt/pyTruthy c))))

fn fallbackPrompt body: j/Json -> (Result String pt/PyErr)
  (if (and (pt/pyTruthy body) (pt/pyTruthy (getOr body "messages" (j/jnull))))
    (match (messageList (getOr body "messages" (j/jnull)))
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
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outDone) (k)) (_ (mismatch "done")))))

fn tellAll effs: (List ChatEffect) k: (fn [] -> ChatStep) -> ChatStep
  (match (listHead effs)
    ((none) (k))
    ((some e) (tell e (fn [] -> ChatStep (tellAll (optionOr (listTail effs) (list)) k)))))

fn askPath eff: ChatEffect k: (fn [String] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outPath p) (k p)) (_ (mismatch "path")))))

fn askBool eff: ChatEffect k: (fn [Bool] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outBool b) (k b)) (_ (mismatch "bool")))))

fn askFloat eff: ChatEffect k: (fn [Float64] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outFloat f) (k f)) (_ (mismatch "float")))))

fn askFloats eff: ChatEffect k: (fn [(List Float64)] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outFloats fs) (k fs)) (_ (mismatch "floats")))))

fn askStrings eff: ChatEffect k: (fn [(List String)] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outStrings xs) (k xs)) (_ (mismatch "strings")))))

fn askCli eff: ChatEffect k: (fn [(Option CliReply)] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outCli r) (k r)) (_ (mismatch "cli")))))

fn askHttp eff: ChatEffect k: (fn [HttpReply] -> ChatStep) -> ChatStep
  (stepEffect eff (fn [(o ChatOutcome)] -> ChatStep (match o ((outHttp r) (k r)) (_ (mismatch "http")))))

fn usageNote provider: String alias: String outcome: String -> ChatEffect
  (effUsageNote provider alias outcome (j/jnull))

fn telemetry cx: Ctx content: j/Json model: String k: (fn [(Option String)] -> ChatStep) -> ChatStep
  (let [(blank (match content ((j/jstr s) (stringEmpty? (u/pyStrip s))) (_ true)))]
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

; (:m :ref ROTATE :do "the pool agy:bin answers nonzero when no agy binary is configured or on PATH; the call then skips the CLI without a spawn and notes skipped-noBinary")
fn agyFallback cx: Ctx prompt: String k: (fn [(Option CliReply)] -> ChatStep) -> ChatStep
  (if (stringEmpty? prompt)
    (k none)
    (askFloat (effBreakerDown "agy:bin")
      (fn [(missing Float64)] -> ChatStep
        (if (!= missing 0.0)
          (tell (usageNote "agy-cli" "agyFallback" "skipped-noBinary") (fn [] -> ChatStep (k none)))
          (agyFallbackLive cx prompt k)))))

fn agyFallbackLive cx: Ctx prompt: String k: (fn [(Option CliReply)] -> ChatStep) -> ChatStep
  (askFloat (effBreakerDown "agy")
      (fn [(left Float64)] -> ChatStep
        (if (!= left 0.0)
          (tell (usageNote "agy-cli" "agyFallback" "skipped-breaker") (fn [] -> ChatStep (k none)))
          (askCli (effCli "agy" (list (pair "prompt" (j/jstr prompt)) (pair "model" (j/jstr "gemini-3.8-flash")) (pair "effort" (j/jstr "low"))
                                      (pair "timeout" (j/jint 300)) (pair "queue_timeout" (j/jint 1200)) (pair "agent" (j/jnull))
                                      (pair "add_dirs" (j/jnull)) (pair "workspace" (j/jstr cx.workspace)) (pair "system_prompt" (j/jnull))
                                      (pair "no_tools" (j/jbool false))))
            (fn [(r (Option CliReply))] -> ChatStep
              (let [(text (match r ((some x) (if (stringEmpty? x.text) none (some x))) ((none) none)))]
                (tell (usageNote "agy-cli" "agyFallback" (if (some? text) "ok" "failed")) (fn [] -> ChatStep (k text)))))))))

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
  (match table
    ((none) none)
    ((some tbl)
     (match (mapGet tbl.models e.alias)
       ((none) none)
       ((some m)
        (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) key)) m.shown))
          ((none) none)
          ((some p) (match (pt/jsonLoads (pairSecond p)) ((ok v) (some v)) ((err _) none))))))))

fn paramJson cx: Ctx e: c/GatewayEntry key: String typed: j/Json -> j/Json
  (optionOr (shownParam cx.table e key) typed)

fn floatJson v: (Option Float64) -> j/Json
  (match v ((some f) (j/jfloat f)) ((none) (j/jnull)))

; (:m :ref GW-EMPTY-SYSTEM :do "openai-kind providers answer 400 'system message must have content' to a system message whose content is empty or only whitespace (commandCode, Vercel free models); such a message is dropped before sending, a non-empty one and every other role are untouched")
fn emptySystemMessage? msg: j/Json -> Bool
  (and (= (getOr msg "role" (j/jnull)) (j/jstr "system"))
       (match (getOr msg "content" (j/jnull))
         ((j/jstr s) (stringEmpty? (pt/pyStrip s)))
         ((j/jnull) true)
         (_ false)))

fn dropEmptySystem body: j/Json -> j/Json
  (match (getOr body "messages" (j/jnull))
    ((j/jarr xs) (pt/jset body "messages" (j/jarr (filter (fn [(m j/Json)] -> Bool (not (emptySystemMessage? m))) xs))))
    (_ body))

; (:m :ref GW-IFM-EMPTY-TOOLS :do "true when the body carries tools as an empty array, which a provider with :dropEmptyTools true must not receive")
; (:m :ref NATIVE-TOOLS-DEFAULT :do "the tools a provider receives: a row with :nativeTools false gets none (tools and tool_choice dropped), a :dropEmptyTools provider gets no empty array, everything else is sent as the caller built it")
; (:m :ref IFM-4XX-20261031 :do "a provider with :assistantReasoning true gets reasoning_content \"\" on every assistant message that carries neither reasoning_content nor reasoning: ifm answers 400 'Add a supported thinking field to each assistant message in the multi-turn conversation history' to any history or prefill without one; other providers and other roles are untouched")
fn thinkingMissing? msg: j/Json -> Bool
  (and (= (getOr msg "role" (j/jnull)) (j/jstr "assistant"))
       (and (= (getOr msg "reasoning_content" (j/jnull)) (j/jnull))
            (= (getOr msg "reasoning" (j/jnull)) (j/jnull))))

fn withThinking msg: j/Json -> j/Json
  (if (thinkingMissing? msg) (pt/jset msg "reasoning_content" (j/jstr "")) msg)

fn fillReasoning fill: Bool body: j/Json -> j/Json
  (if (not fill)
    body
    (match (getOr body "messages" (j/jnull))
      ((j/jarr xs) (pt/jset body "messages" (j/jarr (map withThinking xs))))
      (_ body)))

fn reasoningBlock? part: j/Json -> Bool
  (match (getOr part "type" (j/jnull))
    ((j/jstr t) (listContains? (list "thinking" "redacted_thinking" "reasoning") t))
    (_ false))

fn withoutReasoning msg: j/Json -> j/Json
  (if (!= (getOr msg "role" (j/jnull)) (j/jstr "assistant"))
    msg
    (let [(bare (fold jdel msg (list "reasoning_content" "reasoning" "reasoning_details" "thinking")))]
      (match (getOr bare "content" (j/jnull))
        ((j/jarr parts) (pt/jset bare "content" (j/jarr (filter (fn [(p j/Json)] -> Bool (not (reasoningBlock? p))) parts))))
        (_ bare))))

; (:m :ref GW-SESSION-AFFINITY :do "a session moved to another member forwards its transcript without the reasoning the previous member wrote: the reasoning_content, reasoning, reasoning_details and thinking fields and thinking or reasoning content blocks leave every assistant message; runs before fillReasoning, so an :assistantReasoning provider still gets its empty field")
fn dropReasoning body: j/Json -> j/Json
  (match (getOr body "messages" (j/jnull))
    ((j/jarr xs) (pt/jset body "messages" (j/jarr (map withoutReasoning xs))))
    (_ body))

fn upstreamTools params: c/GatewayParams dropEmpty: Bool body: j/Json -> j/Json
  (cond
    ((match params.nativeTools ((some b) (not b)) ((none) false)) (jdel (jdel body "tools") "tool_choice"))
    ((and dropEmpty (emptyTools? body)) (jdel body "tools"))
    (else body))

fn emptyTools? body: j/Json -> Bool
  (match (getOr body "tools" (j/jnull))
    ((j/jarr xs) (listEmpty? xs))
    (_ false))

; (:m :ref GW-REASONING-FLOOR :do "an entry with :reasoning true never sends a max_tokens under 4096 whichever path chose it: an absent, zero, null or smaller client value is raised, because a reasoning model spends its first tokens thinking and returns empty content under a small cap")
fn reasoningTokenFloor -> Int64
  4096

fn belowReasoningFloor? body: j/Json -> Bool
  (match (getOr body "max_tokens" (j/jnull))
    ((j/jint n) (< n (reasoningTokenFloor)))
    ((j/jfloat f) (< f (int64ToFloat64 (reasoningTokenFloor))))
    ((j/jnum f) (< f (int64ToFloat64 (reasoningTokenFloor))))
    (_ true))

fn entryBody cx: Ctx e: c/GatewayEntry -> j/Json
  (let [(ep e.params)
        (b0 cx.baseBody)
        (b1 (match ep.temperatureFixed
              ((some _) (pt/jset b0 "temperature" (floatJson ep.temperatureFixed)))
              ((none) (if (and (some? ep.temperature) (not cx.tempExplicit)) (pt/jset b0 "temperature" (paramJson cx e "temperature" (floatJson ep.temperature))) b0))))
        (b2 (match ep.effort ((some s) (pt/jset b1 "effort" (j/jstr s))) ((none) b1)))
        (b3 (match ep.maxTokens
              ((some n) (if (listContains? cx.reqKeys "max_tokens") b2 (pt/jset b2 "max_tokens" (paramJson cx e "maxTokens" (j/jint n)))))
              ((none) b2)))
        (b4 (if (and (optionOr ep.reasoning false) (belowReasoningFloor? b3)) (pt/jset b3 "max_tokens" (j/jint (reasoningTokenFloor))) b3))
        (b5 (if (and (some? ep.timeoutSec) (not cx.timeoutExplicit)) (pt/jset b4 "timeout" (paramJson cx e "timeoutSec" (floatJson ep.timeoutSec))) b4))]
    (if (optionOr ep.prefill true) b5 (dropPrefill b5)))

; (:m :ref PREFILL-OFF :do "a body whose last message is the assistant's loses it; any other body is unchanged")
fn dropPrefill body: j/Json -> j/Json
  (match (getOr body "messages" (j/jnull))
    ((j/jarr xs)
     (match (listLast xs)
       ((some m) (if (= (strOr (getOr m "role" (j/jnull)) "") "assistant") (pt/jset body "messages" (j/jarr (listTake xs (- (listLength xs) 1)))) body))
       ((none) body)))
    (_ body))

; (:m :ref GW-WIRE-UP :do "the provider's :secret wins over :keyEnv, as resolveProviderCredential! decides: the host puts each resolved secret into ChatWorld.env under secret:<id> before the chat runs, so this stays pure and never reads or prints the secrets file; a provider naming a secret the host did not resolve gets an empty key, never its keyEnv value")
fn credentialKey kind: String env: (Map String String) keyEnv: String secretId: String -> String
  (cond
    ((= kind "cli") "")
    ((not (stringEmpty? secretId)) (optionOr (mapGet env (sc/secretEnvName secretId)) ""))
    (else (optionOr (mapGet env keyEnv) "")))

fn entryUpstream cx: Ctx e: c/GatewayEntry -> u/UpstreamEndpoint
  (let [(up e.upstream)
        (pv (match cx.table ((some tbl) (mapGet tbl.providers e.provider)) ((none) none)))
        (keyEnv (match pv ((some p) p.keyEnv) ((none) "")))
        (sessionHeader (match pv ((some p) p.sessionHeader) ((none) "")))
        (secretId (match pv ((some p) p.secret) ((none) "")))
        (key (credentialKey e.kind cx.world.env keyEnv secretId))]
    (u/UpstreamEndpoint :provider up.provider :url up.url :key key :sessionHeader sessionHeader))

fn upstreamFor cx: Ctx m: String -> u/UpstreamEndpoint
  (u/getUpstreamForModelIn (dp/rowsFromTable cx.table) (u/upstreamFallback) cx.world.settings cx.world.env (some m))

fn cliProvider? p: String -> Bool
  (or (= p "agy-cli") (or (= p "codex-cli") (= p "claude-cli")))

fn validEffort? v: (Option String) -> Bool
  (match v ((some s) (or (= s "low") (or (= s "medium") (= s "high")))) ((none) false))


fn chatStart! req: ChatRequest world: ChatWorld -> ChatStep
  (let [(path (if (stringStartsWith? req.path "/v1/chat/completions") "/chat/completions" req.path))
        (body (match (pt/jsonLoads req.body) ((ok v) v) ((err _) (j/jnull))))
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
    (match (normField (u/headerGet hs "X-ASL-Intent") body "intent")
      ((err e) (raise e))
      ((ok intent)
       (match (roleField world hs body)
         ((err e) (raise e))
         ((ok explicitRole)
          (let [(role (if (stringEmpty? explicitRole) (if (stringEmpty? intent) "coder" "") explicitRole))
                (roleOpt (if (stringEmpty? explicitRole) none (some explicitRole)))
                (reqKeys (keysOf body))
                ; (:m :do "GW-UPSTREAM-TABLES: the pre-resolution max-tokens floor used to guess reasoning-ness from hardcoded free-model lists; now, when the caller already named a registered model id, its own config :reasoning answers the question instead -- aliasRoute!/profileRoute! still resolve the real cascade entry afterward and apply the same param via entryBody, this is only for the literal-model case prepareRequestPayload sees before that resolution happens")
                (explicitModelRaw (if (isObj? body) (strOr (getOr body "model" (j/jstr "")) "") ""))
                (configReasoning (match world.table ((err _) none) ((ok tbl) (match (mapGet tbl.models explicitModelRaw) ((none) none) ((some m) m.params.reasoning)))))]
            (match (if (pt/pyTruthy body) (match (u/prepareRequestPayload body roleOpt configReasoning) ((ok b) (ok b)) ((err s) (err (splitErr s)))) (ok body))
              ((err e) (raise e))
              ((ok prepared)
               (match (normField (u/headerGet hs "X-ASL-Lens") prepared "lens")
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
                                 :profileName "" :table (match world.table ((ok t) (some t)) ((err _) none)) :reqKeys reqKeys
                                 :headerEff (u/headerGet hs "X-ASL-Effort") :envEff (mapGet world.env "ASL_EFFORT")
                                 :tempExplicit false :timeoutExplicit false :baseBody prepared :cascadeLen 0 :spread (list) :cooldownSec 60
                                 :session (cliCallerKey hs body) :stuck "" :dropOnSwitch false :stickWaitSec 0.0 :sticking false :mode "route" :judge (c/judgeDefault)
                                 :excludeModel (u/pyStrip (optionOr (u/headerGet hs "X-ASL-Exclude-Model") ""))))]
                    (match world.table
                      ((err e) (if (stringStartsWith? e "ERR_GATEWAY_NO_CONFIG")
                                  (sendError cx (list) 503 e true)
                                  (if routed
                                    (profileRoute! cx prepared explicitRole composite)
                                    (aliasRoute! cx prepared explicitRole composite))))
                      ((ok _)
                        (if routed
                          (profileRoute! cx prepared explicitRole composite)
                          (aliasRoute! cx prepared explicitRole composite)))))))))))))))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "threads the matched route's :spread/:cooldownSec alongside its name, the only place a RouteEntries' routing metadata enters Ctx")
fn withProfile cx: Ctx re: c/RouteEntries -> Ctx
  (with cx :profileName re.name :spread re.spread :cooldownSec re.cooldownSec
           :mode (c/gatewayProfileMode re.table re.name) :judge (c/gatewayProfileJudge re.table re.name))

fn profileRoute! cx: Ctx body: j/Json explicitRole: String composite: String -> ChatStep
  (match cx.world.table
    ((err e) (sendError cx (list) (if (stringStartsWith? e "ERR_GATEWAY_NO_CONFIG") 503 500) e true))
    ((ok tbl)
     (match (c/gatewayRouteEntries! tbl cx.req.headers (mapGet cx.world.env "ASL_GATEWAY_PROFILE") cx.intent)
       ((err e) (sendError cx (list) 400 e true))
       ((ok re)
        (let [(i cx.intent)
              (noted (and (= tbl.version 2) (and (not (stringEmpty? i)) (not (mapHas? tbl.intents i)))))
              (next (fn [] -> ChatStep
                      (if (listEmpty? re.entries)
                        (sendError cx (list) 400 (str "profile " re.name " has no route for intent " (if (stringEmpty? i) "any" i)) true)
                        (cascadeChosen (withProfile cx re) body explicitRole composite re.entries (optionOr re.temperature (selectTemp cx composite))))))]
          (if noted (tell (effNoteIntent i) next) (next)))))))

fn selectTemp cx: Ctx composite: String -> Float64
  (let [(i cx.intent)]
    (match (cxRouteTemperature! cx i)
      ((some t) t)
      ((none)
       (match (cxRouteTemperature! cx composite)
         ((some t) t)
         ((none) (optionOr (cxRouteTemperature! cx cx.role) 0.2))))))

fn unresolved ms: (List String) -> (List c/GatewayResolvedEntry)
  (map (fn [(m String)] -> c/GatewayResolvedEntry (c/entryUnresolved m)) ms)

fn fromRoute cx: Ctx body: j/Json explicitRole: String composite: String re: c/RouteEntries -> ChatStep
  (cascadeChosen (withProfile cx re) body explicitRole composite re.entries (optionOr re.temperature 0.2))

; (:m :do "role/intent cascades are read from the gateway config's profile routes (c/gatewayRouteEntries!), never a built-in list: intent first, then the role:lens composite, then the bare role, then -- if the caller's literal model string is itself a member of some configured chain -- that chain; absent any match, an explicit error names what was missing instead of a hardcoded default cascade")
; (:m :ref GW-CHAT-UNKNOWN-LOCAL :do "with a loaded config table, a model no alias, route or provider row claims is answered 400 ERR_UNKNOWN_MODEL here, instead of a raw dispatch to the fallback provider that ends in a 502 ERR_NO_UPSTREAM; a vendor/model slug is refused too unless a row claims it by :prefixes or :names (an openrouter row claiming \"vendor/\" passes it), the rule dispatch applies; the claim test resolves the model against the table's provider rows with a fallback no real row can have")
fn unclaimedModel? cx: Ctx model: String -> Bool
  (unclaimedBare? cx model)

fn unclaimedBare? cx: Ctx model: String -> Bool
  (match cx.world.table
    ((err _) false)
    ((ok _) (= (u/getUpstreamForModelIn (dp/rowsFromTable cx.table) (with (u/upstreamFallback) :id "unclaimed") cx.world.settings cx.world.env (some model)).provider "unclaimed")))

fn asnQuoteModel m: String -> String
  (str "\"" (u/replaceAll (u/replaceAll m "\\" "\\\\") "\"" "\\\"") "\"")

fn aliasRoute! cx: Ctx body: j/Json explicitRole: String composite: String -> ChatStep
  (let [(model cx.explicitModel)
        (world cx.world)
        (choose (fn [(alias (Option c/GatewayResolvedEntry))] -> ChatStep
                  (let [(prov (if (stringEmpty? model) "" (upstreamFor cx model).provider))
                        (i cx.intent)
                        (role cx.role)
                        (roleOk (or (stringEmpty? model) (some? (cxConfiguredRoute! cx model))))
                        (iRoute (cxConfiguredRoute! cx i))
                        (compositeRoute (if roleOk (cxConfiguredRoute! cx composite) none))
                        (roleRoute (if roleOk (cxConfiguredRoute! cx role) none))]
                    (if (or (some? alias) (cliProvider? prov))
                      (cascadeChosen cx body explicitRole composite (list (optionOr alias (c/entryUnresolved model))) (selectTemp cx composite))
                      (match iRoute
                        ((some re) (fromRoute cx body explicitRole composite re))
                        ((none)
                         (match compositeRoute
                           ((some re) (fromRoute cx body explicitRole composite re))
                           ((none)
                            (match roleRoute
                              ((some re) (fromRoute cx body explicitRole composite re))
                              ((none)
                               (match (modelCascade cx model)
                                 ((some chain)
                                  (cascadeChosen cx body explicitRole composite
                                                 (unresolved (cons model (filter (fn [(x String)] -> Bool (!= x model)) chain))) 0.2))
                                 ((none)
                                  (if (not (stringEmpty? model))
                                    (if (unclaimedModel? cx model)
                                      (sendError cx (list) 400 (str "(:err :code ERR_UNKNOWN_MODEL :model " (asnQuoteModel model) ")") true)
                                      (cascadeChosen cx body explicitRole composite (unresolved (list model)) 0.2))
                                    (sendError cx (list) 400
                                      (str "no route configured for intent " (if (stringEmpty? i) "(none)" i)
                                           ", role " (if (stringEmpty? role) "(none)" role)
                                           " or lens " (if (stringEmpty? composite) "(none)" composite))
                                      true))))))))))))))]
    (if (stringEmpty? model)
      (choose none)
      (match world.table
        ((err e) (tell (effLog (str "[Gateway Config] " model " dispatched raw: " e "\n")) (fn [] -> ChatStep (choose none))))
        ((ok tbl) (choose (c/gatewayV2AliasEntry! tbl model))))))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "the pool key a spread member's breaker availability is checked under, identical to prepareAttempt's own providerPool:alias for a v2-resolved entry (spread members are only ever v2-resolved, drawn from the same route's :chain); an unresolved entry has no provider to key on and is simply never breaker-checked, available by default like every other field this reorder leaves alone")
fn poolKeyForEntry e: c/GatewayResolvedEntry -> String
  (match e
    ((c/entryResolved g) (if (stringEmpty? g.provider) "" (str g.provider ":" g.alias)))
    ((c/entryUnresolved _) ""))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "one (alias, poolKey) pair per spread member actually present in this cascade's resolved models, so the server can check real BreakerState without re-resolving the config table itself")
fn spreadPools models: (List c/GatewayResolvedEntry) spread: (List (Pair String Int64)) -> (List (Pair String String))
  (let [(names (map pairFirst spread))]
    (map (fn [(e c/GatewayResolvedEntry)] -> (Pair String String) (pair (c/gatewayEntryLabel e) (poolKeyForEntry e)))
      (filter (fn [(e c/GatewayResolvedEntry)] -> Bool (listContains? names (c/gatewayEntryLabel e))) models)))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "order is the server's available-spread-member sequence; every entry it names is moved to the front in that sequence, every other entry (not in spread, or in spread but currently unavailable) keeps its original relative order after -- same multiset of aliases as models, never a duplicate or a drop, so the plain-chain fallback still reaches an unavailable spread member later instead of losing it")
fn reorderBySpread models: (List c/GatewayResolvedEntry) order: (List String) -> (List c/GatewayResolvedEntry)
  (let [(picked (fold (fn [(acc (List c/GatewayResolvedEntry)) (alias String)] -> (List c/GatewayResolvedEntry)
                        (match (listHead (filter (fn [(e c/GatewayResolvedEntry)] -> Bool (= (c/gatewayEntryLabel e) alias)) models))
                          ((some e) (listAppend acc (list e)))
                          ((none) acc)))
                 (list) order))
        (pickedAliases (map c/gatewayEntryLabel picked))
        (rest (filter (fn [(e c/GatewayResolvedEntry)] -> Bool (not (listContains? pickedAliases (c/gatewayEntryLabel e)))) models))]
    (listAppend picked rest))


; (:m :ref GW-SPREAD-LIVE-20261018 :do "cascadeChosen's own last step: an empty :spread (the default) skips the effect entirely, zero behaviour change for any route without one; otherwise asks the server for this call's spread order and reorders models by it before Loop is built -- the literal 'orders Loop.models by spreadOrder before construction'")
; (:m :ref CTX-ROUTE :do "a large prompt under a profile with :budgetFirstAbove orders the members by budget after the spread order, so the window preference wins over the spread for that call")
fn startLoop cx: Ctx body: j/Json models: (List c/GatewayResolvedEntry) -> ChatStep
  (if (listEmpty? cx.spread)
    (stickLoop cx body (budgetOrder cx body models))
    (askStrings (effSpreadOrder cx.profileName cx.intent cx.spread cx.cooldownSec (spreadPools models cx.spread))
      (fn [(order (List String))] -> ChatStep (stickLoop cx body (budgetOrder cx body (reorderBySpread models order))))))

; (:m :ref GW-SESSION-AFFINITY :do "a session's last answering member goes first while it sticks, after the spread order and before the loop, so breakers and limits still skip it when it is down; no session key asks nothing")
fn stickLoop cx: Ctx body: j/Json models: (List c/GatewayResolvedEntry) -> ChatStep
  (let [(run (fn [(cx2 Ctx) (ms (List c/GatewayResolvedEntry))] -> ChatStep
               (loopStep cx2 (Loop :body body :models ms :idx 0 :lastErr none :skipped (list) :emptyRetries 0 :telBound false :head (list) :retryAfterSec 0 :ctxNeed 0 :ctxFails 0 :ctxEst 0))))]
    (if (stringEmpty? cx.session)
      (run cx models)
      (stepEffect (effAffinity cx.session)
        (fn [(o ChatOutcome)] -> ChatStep
          (match o
            ((outStrings xs)
             (match (listHead xs)
               ((none) (run cx models))
               ((some alias)
                (let [(sticks (= (listGet xs 1) (some "1")))
                      (wait (if sticks (match (listGet xs 3) ((some s) (match (u/pyFloat s) ((ok f) (max 0.0 f)) ((err _) 0.0))) ((none) 0.0)) 0.0))]
                  (run (with cx :stuck alias :dropOnSwitch (= (listGet xs 2) (some "1")) :stickWaitSec wait :sticking sticks)
                       (if sticks (reorderBySpread models (list alias)) models))))))
            ((outDone) (run cx models))
            (_ (mismatch "strings")))))))

; (:m :ref GW-SESSION-AFFINITY :do "records the member that answered a session; no session key records nothing")
fn noteAffinity cx: Ctx alias: String k: (fn [] -> ChatStep) -> ChatStep
  (if (stringEmpty? cx.session) (k) (tell (effAffinityNote cx.session alias) k))

fn switchedBody cx: Ctx alias: String body: j/Json -> j/Json
  (if (and cx.dropOnSwitch (and (not (stringEmpty? cx.stuck)) (!= alias cx.stuck))) (dropReasoning body) body)

; (:m :ref GW-MODES :do "a pin profile tries the first member of its route and nothing after it, so no reroute, spread or fallback profile ever replaces the named model")
fn entryMatchesExclude? entry: c/GatewayResolvedEntry ex: String -> Bool
  (if (stringEmpty? ex)
    false
    (match entry
      ((c/entryResolved e) (or (= e.alias ex) (or (= e.name ex) (= e.dispatch ex))))
      ((c/entryUnresolved a) (= a ex))))

fn filterExcluded cx: Ctx models: (List c/GatewayResolvedEntry) -> (List c/GatewayResolvedEntry)
  (if (stringEmpty? cx.excludeModel)
    models
    (let [(kept (filter (fn [(m c/GatewayResolvedEntry)] -> Bool (not (entryMatchesExclude? m cx.excludeModel))) models))]
      kept))

fn pinModels cx: Ctx models: (List c/GatewayResolvedEntry) -> (List c/GatewayResolvedEntry)
  (let [(filtered (filterExcluded cx models))]
    (if (= cx.mode "pin") (listTake filtered 1) filtered))

fn finishReason resp: j/Json -> String
  (match (getOr resp "choices" (j/jnull))
    ((j/jarr xs) (match (listHead xs)
                   ((some c) (match (getOr c "finish_reason" (j/jnull)) ((j/jstr s) s) (_ "")))
                   ((none) "")))
    (_ ""))

; (:m :ref GW-MODES :do "the first judge check a judge-mode reply fails, empty when it passes or the profile is not judge: empty (message content of the raw upstream reply blank, before project copies reasoning into it, and no tool calls), truncated (finish_reason length), noStepForm (an intent of :stepIntents whose answer holds none of :stepHeads)")
fn judgeFailure cx: Ctx p: Projection raw: String -> String
  (if (!= cx.mode "judge")
    ""
    (let [(r cx.judge)
          (msg (match (pt/jsonLoads raw) ((ok parsed) (firstMessage parsed)) ((err _) (firstMessage p.resp))))
          (text (match p.content ((j/jstr s) s) (_ "")))]
      (cond
        ((and r.empty (and (emptyContent? (getOr msg "content" (j/jnull))) (not (toolCalls? msg)))) "empty")
        ((and r.truncated (= (finishReason p.resp) "length")) "truncated")
        ((and (listContains? r.stepIntents (stringLower cx.intent))
              (not (listAny? (fn [(h String)] -> Bool (stringContains? text h)) r.stepHeads))) "noStepForm")
        (else ""))))


fn cascadeChosen cx: Ctx body: j/Json explicitRole: String composite: String models: (List c/GatewayResolvedEntry) calibrated: Float64 -> ChatStep
  (let [(world cx.world)
        (hs cx.req.headers)
        (mode (u/harnessMode hs world.env))
        (roleOpt (if (stringEmpty? explicitRole) none (some explicitRole)))]
    (match (if (and (pt/pyTruthy body) (or (= mode "override") (= mode "minimal")))
          (match (u/applyHarnessPolicy body mode roleOpt) ((ok b) (ok b)) ((err s) (err (splitErr s))))
          (ok body))
      ((err e) (raise e))
      ((ok harnessed)
       (let [(hTemp (u/headerGet hs "X-ASL-Temperature"))
             (envTemp (mapGet world.env "ASL_TEMPERATURE"))
             (envTempSet (match envTemp ((some s) (not (stringEmpty? (u/pyStrip s)))) ((none) false)))
             (assign (fn [(text String)] -> j/Json
                       (match (u/pyFloat text)
                         ((ok f) (if (isObj? harnessed) (pt/jset harnessed "temperature" (j/jfloat f)) harnessed))
                         ((err _) harnessed))))
             (tempered (cond
                         ((some? hTemp) (assign (optionOr hTemp "")))
                         (envTempSet (assign (u/pyStrip (optionOr envTemp ""))))
                         ((and (pt/pyTruthy harnessed) (not (has? harnessed "temperature"))) (pt/jset harnessed "temperature" (j/jfloat calibrated)))
                         (else harnessed)))
             (hEff cx.headerEff)
             (eEff cx.envEff)]
         (match (cond
               ((validEffort? hEff) (if (isObj? tempered) (ok (pt/jset tempered "effort" (j/jstr (optionOr hEff "")))) (err (itemErr tempered))))
               ((validEffort? eEff) (if (isObj? tempered) (ok (pt/jset tempered "effort" (j/jstr (optionOr eEff "")))) (err (itemErr tempered))))
               ((and (pt/pyTruthy tempered) (not (has? tempered "effort")))
                (match (numberOf (getOr tempered "temperature" (j/jfloat 0.2)))
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
                  (cx2 (with cx :world world :reqKeys keys :headerEff hEff :envEff eEff :tempExplicit tempExplicit :timeoutExplicit timeoutExplicit :baseBody final :cascadeLen (listLength (pinModels cx models))))]
              (if (and (not (listEmpty? models)) (listEmpty? (pinModels cx models)))
                (sendError cx (list) 400 (str "(:err :code excludedAll :model " (asnQuoteModel cx.excludeModel) ")") true)
                (startLoop cx2 final (pinModels cx models))))))))))


fn advance l: Loop body: j/Json -> Loop
  (with l :body body :idx (+ l.idx 1))

fn failed l: Loop err: String -> Loop
  (with l :lastErr (some err) :retryAfterSec 0)

fn loopStep cx: Ctx l: Loop -> ChatStep
  (match (listGet l.models l.idx)
    ((none) (afterLoop cx l))
    ((some entry) (attempt cx l entry)))

fn respSystemJoin msgs: (List j/Json) acc: (List String) -> String
  (match (listHead msgs)
    ((none) (stringJoin (listReverse acc) "\n\n"))
    ((some msg)
     (let [(rest (optionOr (listTail msgs) (list)))
           (role (getOr msg "role" (j/jnull)))]
       (if (and (= role (j/jstr "system")) (pt/pyTruthy (getOr msg "content" (j/jnull))))
         (match (getOr msg "content" (j/jnull))
           ((j/jstr s) (respSystemJoin rest (cons s acc)))
           (_ (respSystemJoin rest acc)))
         (respSystemJoin rest acc)))))

fn respInputItems msgs: (List j/Json) acc: (List j/Json) -> (List j/Json)
  (match (listHead msgs)
    ((none) (listReverse acc))
    ((some msg)
     (let [(rest (optionOr (listTail msgs) (list)))
           (role (getOr msg "role" (j/jnull)))]
       (if (= role (j/jstr "system"))
         (respInputItems rest acc)
         (respInputItems rest (cons (j/jobj (list (pair "role" role) (pair "content" (getOr msg "content" (j/jstr ""))))) acc))))))

fn responsesBody body: j/Json target: String -> j/Json
  (let [(msgs (match (getOr body "messages" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
        (sys (respSystemJoin msgs (list)))
        (b0 (j/jobj (list (pair "model" (j/jstr target)) (pair "input" (j/jarr (respInputItems msgs (list)))))))
        (b1 (if (not (stringEmpty? sys)) (pt/jset b0 "instructions" (j/jstr sys)) b0))]
    (match (getOr body "max_tokens" (j/jnull))
      ((j/jint n) (pt/jset b1 "max_output_tokens" (j/jint n)))
      ((j/jfloat f) (pt/jset b1 "max_output_tokens" (j/jint (optionOr (float64ToInt64 f) 0))))
      (_ b1)))

fn anthropicToolOf t: j/Json -> j/Json
  (let [(fn_ (getOr t "function" (j/jobj (list))))]
    (j/jobj (list (pair "name" (getOr fn_ "name" (j/jstr "")))
                  (pair "description" (getOr fn_ "description" (j/jstr "")))
                  (pair "input_schema" (getOr fn_ "parameters" (j/jobj (list)))))))

fn jsonStopSequencesOf v: j/Json -> j/Json
  (match v
    ((j/jstr s) (j/jarr (list (j/jstr s))))
    ((j/jarr xs) (j/jarr xs))
    (_ (j/jarr (list))))

fn anthropicToolCallBlock tc: j/Json -> j/Json
  (let [(id (strOr (getOr tc "id" (j/jstr "")) ""))
        (fn_ (getOr tc "function" (j/jobj (list))))
        (name (strOr (getOr fn_ "name" (j/jstr "")) ""))
        (argsText (strOr (getOr fn_ "arguments" (j/jstr "{}")) "{}"))
        (input (match (pt/jsonLoads argsText) ((ok v) v) ((err _) (j/jobj (list)))))]
    (j/jobj (list (pair "type" (j/jstr "tool_use")) (pair "id" (j/jstr id)) (pair "name" (j/jstr name)) (pair "input" input))))

; (:m :tags (anthropic) :do "an OpenAI assistant message carries plain text content plus a sibling tool_calls array; Anthropic wants both folded into one content block list on the same message")
fn anthropicAssistantContent msg: j/Json -> j/Json
  (let [(content (getOr msg "content" (j/jnull)))
        (textBlocks (match content
                      ((j/jstr s) (if (stringEmpty? s) (list) (list (j/jobj (list (pair "type" (j/jstr "text")) (pair "text" (j/jstr s)))))))
                      (_ (list))))
        (calls (match (getOr msg "tool_calls" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
        (callBlocks (map anthropicToolCallBlock calls))]
    (j/jarr (listAppend textBlocks callBlocks)))

fn anthropicToolResultBlock msg: j/Json -> j/Json
  (j/jobj (list (pair "type" (j/jstr "tool_result"))
                (pair "tool_use_id" (j/jstr (strOr (getOr msg "tool_call_id" (j/jstr "")) "")))
                (pair "content" (j/jstr (strOr (getOr msg "content" (j/jstr "")) "")))))

; (:m :tags (anthropic) :do "OpenAI history puts each tool result in its own {role:tool} message; Anthropic requires every tool_result answering one assistant turn's tool_use blocks to live in ONE user message, so consecutive tool-role messages are grouped into a single user message with one tool_result block per message")
fn anthropicFlushToolResults out: (List j/Json) pending: (List j/Json) -> (List j/Json)
  (if (listEmpty? pending) out
    (listAppend out (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jarr (listReverse pending))))))))

fn anthropicMessagesFold acc: (Pair (List j/Json) (List j/Json)) msg: j/Json -> (Pair (List j/Json) (List j/Json))
  (let [(out (pairFirst acc))
        (pending (pairSecond acc))
        (role (strOr (getOr msg "role" (j/jnull)) ""))]
    (cond
      ((= role "system") acc)
      ((= role "tool") (pair out (cons (anthropicToolResultBlock msg) pending)))
      ((= role "assistant")
       (pair (listAppend (anthropicFlushToolResults out pending)
                          (list (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (anthropicAssistantContent msg))))))
             (list)))
      (else
       (pair (listAppend (anthropicFlushToolResults out pending)
                          (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (getOr msg "content" (j/jstr "")))))))
             (list)))))

fn anthropicMessagesOf msgs: (List j/Json) -> (List j/Json)
  (let [(folded (fold anthropicMessagesFold (pair (list) (list)) msgs))]
    (anthropicFlushToolResults (pairFirst folded) (pairSecond folded)))

fn anthropicBody body: j/Json target: String -> j/Json
  (let [(msgs (match (getOr body "messages" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
        (sys (respSystemJoin msgs (list)))
        (b0 (j/jobj (list (pair "model" (j/jstr target)) (pair "messages" (j/jarr (anthropicMessagesOf msgs))))))
        (b1 (if (not (stringEmpty? sys)) (pt/jset b0 "system" (j/jstr sys)) b0))
        (b2 (match (getOr body "max_tokens" (j/jnull))
              ((j/jint n) (pt/jset b1 "max_tokens" (j/jint n)))
              ((j/jfloat f) (pt/jset b1 "max_tokens" (j/jint (optionOr (float64ToInt64 f) 0))))
              (_ (pt/jset b1 "max_tokens" (j/jint (u/minTokenFloor))))))
        (tempV (getOr body "temperature" (j/jnull)))
        (b3 (match tempV ((j/jnull) b2) (_ (pt/jset b2 "temperature" tempV))))
        (stopV (getOr body "stop" (j/jnull)))
        (b4 (match stopV ((j/jnull) b3) (_ (pt/jset b3 "stop_sequences" (jsonStopSequencesOf stopV)))))
        (toolsV (getOr body "tools" (j/jnull)))
        (b5 (match toolsV ((j/jarr xs) (pt/jset b4 "tools" (j/jarr (map anthropicToolOf xs)))) (_ b4)))]
    b5)

fn geminiFunctionDeclarationOf t: j/Json -> j/Json
  (let [(fn_ (getOr t "function" (j/jobj (list))))]
    (j/jobj (list (pair "name" (getOr fn_ "name" (j/jstr "")))
                  (pair "description" (getOr fn_ "description" (j/jstr "")))
                  (pair "parameters" (getOr fn_ "parameters" (j/jobj (list)))))))

fn geminiFunctionCallPart tc: j/Json -> j/Json
  (let [(fn_ (getOr tc "function" (j/jobj (list))))
        (name (strOr (getOr fn_ "name" (j/jstr "")) ""))
        (argsText (strOr (getOr fn_ "arguments" (j/jstr "{}")) "{}"))
        (args (match (pt/jsonLoads argsText) ((ok v) v) ((err _) (j/jobj (list)))))]
    (j/jobj (list (pair "functionCall" (j/jobj (list (pair "name" (j/jstr name)) (pair "args" args)))))))

fn geminiAssistantParts msg: j/Json -> (List j/Json)
  (let [(content (getOr msg "content" (j/jnull)))
        (textParts (match content
                     ((j/jstr s) (if (stringEmpty? s) (list) (list (j/jobj (list (pair "text" (j/jstr s)))))))
                     (_ (list))))
        (calls (match (getOr msg "tool_calls" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
        (callParts (map geminiFunctionCallPart calls))]
    (listAppend textParts callParts))

; (:m :tags (gemini) :do "Gemini's functionResponse part needs the ORIGINAL function name, not just the call id OpenAI's tool-role message carries; this pre-pass recovers name-by-id from the assistant tool_calls that preceded each tool result, before the main fold ever runs")
fn geminiToolNamesFold acc: (List (Pair String String)) msg: j/Json -> (List (Pair String String))
  (let [(role (strOr (getOr msg "role" (j/jnull)) ""))]
    (if (!= role "assistant") acc
      (let [(calls (match (getOr msg "tool_calls" (j/jnull)) ((j/jarr xs) xs) (_ (list))))]
        (fold (fn [(acc2 (List (Pair String String))) (tc j/Json)] -> (List (Pair String String))
                (let [(id (strOr (getOr tc "id" (j/jstr "")) ""))
                      (fn_ (getOr tc "function" (j/jobj (list))))
                      (name (strOr (getOr fn_ "name" (j/jstr "")) ""))]
                  (listAppend acc2 (list (pair id name)))))
              acc calls))))

fn geminiToolNamesOf msgs: (List j/Json) -> (List (Pair String String))
  (fold geminiToolNamesFold (list) msgs)

fn geminiNameForCallId names: (List (Pair String String)) id: String -> String
  (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) id)) names))
    ((some p) (pairSecond p))
    ((none) ""))

fn geminiFunctionResponsePart msg: j/Json names: (List (Pair String String)) -> j/Json
  (let [(id (strOr (getOr msg "tool_call_id" (j/jstr "")) ""))
        (name (geminiNameForCallId names id))
        (contentText (strOr (getOr msg "content" (j/jstr "")) ""))
        (contentValue (match (pt/jsonLoads contentText) ((ok v) v) ((err _) (j/jstr contentText))))]
    (j/jobj (list (pair "functionResponse" (j/jobj (list (pair "name" (j/jstr name))
                                                           (pair "response" (j/jobj (list (pair "content" contentValue))))))))))

; (:m :tags (gemini) :do "same grouping as anthropicMessagesFold (consecutive tool-role messages collapse into one user turn's parts), but Gemini's roles are user/model (not user/assistant) and its wrapper key is :parts, not :content")
fn geminiFlushToolResults out: (List j/Json) pending: (List j/Json) -> (List j/Json)
  (if (listEmpty? pending) out
    (listAppend out (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "parts" (j/jarr (listReverse pending))))))))

fn geminiMessagesFold names: (List (Pair String String)) acc: (Pair (List j/Json) (List j/Json)) msg: j/Json -> (Pair (List j/Json) (List j/Json))
  (let [(out (pairFirst acc))
        (pending (pairSecond acc))
        (role (strOr (getOr msg "role" (j/jnull)) ""))]
    (cond
      ((= role "system") acc)
      ((= role "tool") (pair out (cons (geminiFunctionResponsePart msg names) pending)))
      ((= role "assistant")
       (pair (listAppend (geminiFlushToolResults out pending)
                          (list (j/jobj (list (pair "role" (j/jstr "model")) (pair "parts" (j/jarr (geminiAssistantParts msg)))))))
             (list)))
      (else
       (pair (listAppend (geminiFlushToolResults out pending)
                          (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "parts" (j/jarr (list (j/jobj (list (pair "text" (getOr msg "content" (j/jstr ""))))))))))))
             (list)))))

fn geminiMessagesOf msgs: (List j/Json) -> (List j/Json)
  (let [(names (geminiToolNamesOf msgs))
        (folded (fold (fn [(acc (Pair (List j/Json) (List j/Json))) (msg j/Json)] -> (Pair (List j/Json) (List j/Json)) (geminiMessagesFold names acc msg))
                       (pair (list) (list)) msgs))]
    (geminiFlushToolResults (pairFirst folded) (pairSecond folded)))

fn geminiGenerationConfig body: j/Json -> j/Json
  (let [(c0 (j/jobj (list)))
        (c1 (match (getOr body "max_tokens" (j/jnull))
              ((j/jint n) (pt/jset c0 "maxOutputTokens" (j/jint n)))
              ((j/jfloat f) (pt/jset c0 "maxOutputTokens" (j/jint (optionOr (float64ToInt64 f) 0))))
              (_ c0)))
        (tempV (getOr body "temperature" (j/jnull)))
        (c2 (match tempV ((j/jnull) c1) (_ (pt/jset c1 "temperature" tempV))))
        (stopV (getOr body "stop" (j/jnull)))
        (c3 (match stopV ((j/jnull) c2) (_ (pt/jset c2 "stopSequences" (jsonStopSequencesOf stopV)))))]
    c3)

fn geminiBody body: j/Json target: String -> j/Json
  (let [(msgs (match (getOr body "messages" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
        (sys (respSystemJoin msgs (list)))
        (b0 (j/jobj (list (pair "contents" (j/jarr (geminiMessagesOf msgs))))))
        (b1 (if (not (stringEmpty? sys))
              (pt/jset b0 "systemInstruction" (j/jobj (list (pair "parts" (j/jarr (list (j/jobj (list (pair "text" (j/jstr sys))))))))))
              b0))
        (b2 (pt/jset b1 "generationConfig" (geminiGenerationConfig body)))
        (toolsV (getOr body "tools" (j/jnull)))
        (b3 (match toolsV
              ((j/jarr xs) (pt/jset b2 "tools" (j/jarr (list (j/jobj (list (pair "functionDeclarations" (j/jarr (map geminiFunctionDeclarationOf xs)))))))))
              (_ b2)))]
    b3)

; (:m :ref LEON-PREFIX-CACHE-20261026 :tags (cache) :do "provider cache hints are added on the wire only, after the body is converted: Anthropic gets cache_control breakpoints on the last tool, the system prompt and the message just before the final one (so everything up to the last user message is one cached prefix, 3 of the 4 allowed breakpoints); Gemini gets cachedContent when the caller names one in cached_content; OpenAI-compatible providers whose config declares :promptCacheKey true get prompt_cache_key (the caller's, else a digest of the system text). Any other provider's body is untouched except that cached_content is dropped")
fn cacheMark -> j/Json
  (j/jobj (list (pair "type" (j/jstr "ephemeral"))))

fn markBlock block: j/Json -> j/Json
  (pt/jset block "cache_control" (cacheMark))

fn cacheEligible? block: j/Json -> Bool
  (let [(t (strOr (getOr block "type" (j/jnull)) ""))]
    (or (= t "text") (or (= t "tool_result") (= t "image"))))

fn lastEligibleIndex xs: (List j/Json) i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((cacheEligible? (optionOr (listGet xs i) (j/jnull))) i)
    (else (lastEligibleIndex xs (- i 1))))

fn replaceAt xs: (List j/Json) i: Int64 v: j/Json -> (List j/Json)
  (listAppend (listTake xs i) (cons v (optionOr (listSlice xs (+ i 1) (listLength xs)) (list))))

; (:m :ref LEON-PREFIX-CACHE-20261026 :do "Anthropic allows 4 cache_control marks per request and the client may already have placed some, so marks are counted over the whole body first and the gateway adds only up to the remainder; only text, tool_result and image blocks are marked")
fn countMarks v: j/Json -> Int64
  (match v
    ((j/jobj kvs) (fold (fn [acc kv] (+ acc (+ (if (= (pairFirst kv) "cache_control") 1 0) (countMarks (pairSecond kv))))) 0 kvs))
    ((j/jarr xs) (fold (fn [acc x] (+ acc (countMarks x))) 0 xs))
    (_ 0))

fn markContent content: j/Json -> j/Json
  (match content
    ((j/jstr s) (if (stringEmpty? s) content
                  (j/jarr (list (markBlock (j/jobj (list (pair "type" (j/jstr "text")) (pair "text" content))))))))
    ((j/jarr xs)
      (let [(i (lastEligibleIndex xs (- (listLength xs) 1)))]
        (if (< i 0) content
          (j/jarr (replaceAt xs i (markBlock (optionOr (listGet xs i) (j/jnull))))))))
    (_ content))

fn markMessageAt msgs: (List j/Json) i: Int64 -> (List j/Json)
  (if (or (< i 0) (>= i (listLength msgs))) msgs
    (let [(m (optionOr (listGet msgs i) (j/jnull)))]
      (replaceAt msgs i (pt/jset m "content" (markContent (getOr m "content" (j/jnull)))))))

fn markLast xs: (List j/Json) -> (List j/Json)
  (let [(n (listLength xs))]
    (if (= n 0) xs
      (replaceAt xs (- n 1) (markBlock (optionOr (listGet xs (- n 1)) (j/jnull))))))

fn anthropicCacheHints up: j/Json -> j/Json
  (let [(room0 (- 4 (countMarks up)))
        (c1 (match (getOr up "tools" (j/jnull))
              ((j/jarr xs) (if (> room0 0) (pt/jset up "tools" (j/jarr (markLast xs))) up))
              (_ up)))
        (room1 (- 4 (countMarks c1)))
        (c2 (match (getOr c1 "system" (j/jnull))
              ((j/jstr s) (if (> room1 0) (pt/jset c1 "system" (markContent (j/jstr s))) c1))
              (_ c1)))
        (room2 (- 4 (countMarks c2)))
        (msgs (match (getOr c2 "messages" (j/jnull)) ((j/jarr xs) xs) (_ (list))))]
    (if (or (< (listLength msgs) 2) (<= room2 0)) c2
      (pt/jset c2 "messages" (j/jarr (markMessageAt msgs (- (listLength msgs) 2))))))

fn geminiCacheHints src: j/Json up: j/Json -> j/Json
  (match (getOr src "cached_content" (j/jnull))
    ((j/jstr s) (if (stringEmpty? s) up (pt/jset up "cachedContent" (j/jstr s))))
    (_ up))

fn promptCacheKeyHint prov: String table: (Option c/GatewayTable) src: j/Json up: j/Json -> j/Json
  (let [(base (jdel up "cached_content"))]
    (if (not (match table ((some t) (c/providerPromptCacheKey? t prov)) ((none) false))) base
      (let [(msgs (match (getOr src "messages" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
            (given (strOr (getOr src "prompt_cache_key" (j/jnull)) ""))
            (key (if (stringEmpty? given)
                   (str "asl-" (u/slice (bytesSha256 (stringToBytes (respSystemJoin msgs (list)))) 0 16))
                   given))]
        (pt/jset base "prompt_cache_key" (j/jstr key)))))

fn cacheHints api: String prov: String table: (Option c/GatewayTable) src: j/Json up: j/Json -> j/Json
  (cond
    ((= api "anthropic") (anthropicCacheHints up))
    ((= api "gemini") (geminiCacheHints src up))
    (else (promptCacheKeyHint prov table src up)))

; (:m :ref GWREASON :do "the provider's dialect for a model's :effort: a row :effortDialect wins, else a built-in per provider id (openrouter, nim), else reasoningEffort for any other openai-kind provider; off sends nothing")
fn effortDialectFor providerId: String kind: String override: (Option String) -> String
  (match override
    ((some d) d)
    ((none) (cond
              ((= providerId "openrouter") "openrouter")
              ((= providerId "nim") "chatTemplateThinking")
              ((= kind "openai") "reasoningEffort")
              (else "off"))))

fn effortObj kvs: (List (Pair String j/Json)) -> j/Json
  (j/jobj kvs)

; (:m :ref GWREASON :do "writes the effort into the upstream body in the dialect and returns the effort actually forwarded, none when nothing was written; none means thinking off where the dialect has an off switch")
fn applyEffort dialect: String eff: (Option String) body: j/Json -> (Pair j/Json (Option String))
  (match eff
    ((none) (pair body none))
    ((some e)
      (let [(off (= e "none"))
            (known (listContains? (list "low" "medium" "high" "xhigh" "none") e))]
        (cond
          ((not known) (pair body none))
          ((or (= dialect "reasoningEffort") (= dialect "gemini"))
            (pair (pt/jset body "reasoning_effort" (j/jstr (if (and (= dialect "gemini") (= e "xhigh")) "high" e))) (some e)))
          ((= dialect "openrouter")
            (pair (pt/jset body "reasoning" (effortObj (list (pair "effort" (j/jstr e))))) (some e)))
          ((= dialect "chatTemplateThinking")
            (pair (pt/jset body "chat_template_kwargs"
                    (effortObj (listAppend (list (pair "enable_thinking" (j/jbool (not off))) (pair "thinking" (j/jbool (not off))))
                                           (if (= e "low") (list (pair "low_effort" (j/jbool true))) (list)))))
                  (some e)))
          ((= dialect "glmThinking")
            (pair (pt/jset body "thinking" (effortObj (list (pair "type" (j/jstr (if off "disabled" "enabled")))))) (some e)))
          (else (pair body none))))))

fn prepareAttempt cx: Ctx l: Loop entry: c/GatewayResolvedEntry -> (Pair j/Json Attempt)
  (let [(v2 (match entry ((c/entryResolved e) (some e)) ((c/entryUnresolved _) none)))
        (m (match entry ((c/entryResolved e) e.dispatch) ((c/entryUnresolved a) a)))
        (body0 (match v2 ((some e) (if (isObj? cx.baseBody) (entryBody cx e) l.body)) ((none) l.body)))
        (target (cond
                  ((some? v2) m)
                  ((stringStartsWith? m "groq/") (u/slice m 5 (stringLength m)))
                  ((stringStartsWith? m "ollama/") (u/slice m 7 (stringLength m)))
                  ((= m "qwen") "qwen/qwen3.8-27b")
                  (else m)))
        (world cx.world)
        (upstream (match v2 ((some e) (entryUpstream cx e)) ((none) (upstreamFor cx m))))
        (prov upstream.provider)
        (alias (match v2 ((some e) e.alias) ((none) m)))
        (providerPool (cond
                ((and (some? v2) (not (stringEmpty? (match v2 ((some e) e.provider) ((none) ""))))) (match v2 ((some e) e.provider) ((none) "")))
                ((= prov "agy-cli") "agy")
                ((= prov "codex-cli") "codex")
                ((= prov "claude-cli") "claude")
                (else prov)))
        ; (:m :tags (breaker pool) :do "the breaker's default key is per model (providerPool:alias) so one free model rate-limited at 429 does not block its siblings on the same provider; providerPool alone is still used for account-wide failures (see httpFailed)")
        (pool (if (stringEmpty? providerPool) "" (str providerPool ":" alias)))
        (truthy (pt/pyTruthy body0))
        (body1 (if truthy (pt/jset body0 "model" (j/jstr target)) body0))
        (ollama (or (= prov "ollama") (match v2 ((some e) (= e.provider "ollama")) ((none) false))))
        (entryEff (match v2 ((some e) e.params.effort) ((none) none)))
        (reqHasEff (or (listContains? cx.reqKeys "effort") (or (some? cx.headerEff) (some? cx.envEff))))
        (chosen (match entryEff ((some s) (j/jstr s)) ((none) (if reqHasEff (getOr body1 "effort" (j/jnull)) (j/jnull)))))
        (chosenValid (match chosen ((j/jstr s) (validEffort? (some s))) (_ false)))
        (out0 (jdel body1 "effort"))
        (chosenStr (match chosen ((j/jstr s) (some s)) (_ none)))
        (effGate (if ollama (if chosenValid chosenStr none) (if (or (some? entryEff) chosenValid) chosenStr none)))
        (provId (match v2 ((some e) e.provider) ((none) prov)))
        (provKind (match v2 ((some e) e.kind) ((none) "")))
        (rowDialect (match v2 ((some e) e.params.effortDialect) ((none) none)))
        (dialect (if (and ollama (none? rowDialect)) "reasoningEffort" (effortDialectFor provId provKind rowDialect)))
        (effApplied (applyEffort dialect effGate out0))
        (out1 (pairFirst effApplied))
        (out2 (jdel (jdel (jdel (jdel out1 "role") "intent") "lens") "workspace"))
        (out3a (switchedBody cx alias (if (some? v2) (jdel (jdel out2 "timeout") "queue_timeout") out2)))
        (out3b (match v2 ((some e) (fillReasoning e.assistantReasoning (upstreamTools e.params e.dropEmptyTools out3a))) ((none) out3a)))
        (out3 (match v2 ((some e) (if (= e.kind "openai") (dropEmptySystem out3b) out3b)) ((none) out3b)))
        (sent (if truthy (if ollama (some (pairSecond effApplied)) (match (pairSecond effApplied) ((some s) (some (some s))) ((none) none))) none))
        (respApi (match v2 ((some e) (cond ((= e.kind "anthropic") "anthropic") ((= e.kind "gemini") "gemini") (else (optionOr e.params.api "chat")))) ((none) "chat")))
        (upBody0 (cond ((= respApi "anthropic") (anthropicBody out3 target)) ((= respApi "gemini") (geminiBody out3 target)) ((= respApi "responses") (responsesBody out3 target)) (else out3)))
        (upBody (streamBody (rowStream v2) respApi (cacheHints respApi prov cx.table out3 upBody0)))
        (data (if truthy (pt/jsonDumps upBody -1) cx.req.body))]
    (pair body1 (Attempt :entry entry :v2 v2 :model m :target target :upstream upstream :alias alias :pool pool :providerPool providerPool :sentEffort sent
      :poolConfig (match v2 ((some e) e.pool) ((none) none)) :data data :api respApi
      :path (cond ((= respApi "anthropic") "/messages") ((= respApi "gemini") (str "/models/" target ":generateContent")) ((= respApi "responses") "/responses") (else cx.path)) :retryUsed 0 :retryDeadline none)))

; (:m :tags (breaker pool) :do "checks each candidate pool key in order and stops at the first one that is down, so a provider-wide trip (401/402/provider marker) and a per-model trip are both honored")
fn withBreakerPools pools: (List String) k: (fn [Float64 String] -> ChatStep) -> ChatStep
  (match (listHead pools)
    ((none) (k 0.0 ""))
    ((some p)
     (let [(rest (optionOr (listTail pools) (list)))]
       (if (stringEmpty? p)
         (withBreakerPools rest k)
         (askFloat (effBreakerDown p)
           (fn [(left Float64)] -> ChatStep
             (if (!= left 0.0) (k left p) (withBreakerPools rest k))))))))

; (:m :ref GW-MISSINGKEY-UNAUTH :do "a non-cli provider that declares a keyEnv or a secret but resolved to an empty key is never sent: the request would reach the provider with no Authorization and burn a 401; the attempt is skipped before any network effect, the next candidate is tried, and the reason names the provider id and the keyEnv or secret id, never a value")
fn missingKeyWhy providerId: String keyEnv: String secretId: String kind: String key: String -> (Option String)
  (cond
    ((= kind "cli") none)
    ((not (stringEmpty? key)) none)
    ((and (stringEmpty? keyEnv) (stringEmpty? secretId)) none)
    (else (some (str "(:err :code ERR_KEY_MISSING :provider " providerId
                     (if (stringEmpty? secretId) "" (str " :secret " secretId))
                     (if (stringEmpty? keyEnv) "" (str " :keyEnv " keyEnv)) ")"))))

fn missingKey cx: Ctx a: Attempt -> (Option String)
  (match a.v2
    ((none) none)
    ((some e)
      (match (match cx.table ((some tbl) (mapGet tbl.providers e.provider)) ((none) none))
        ((none) none)
        ((some p) (missingKeyWhy e.provider p.keyEnv p.secret e.kind a.upstream.key)))))

fn attempt cx: Ctx l: Loop entry: c/GatewayResolvedEntry -> ChatStep
  (let [(prepared (prepareAttempt cx l entry))
        (body (pairFirst prepared))
        (a (pairSecond prepared))
        (l1 (with l :body body))
        (prov a.upstream.provider)
        (overBudget (overContextBudget a body l.ctxNeed))]
    (if (some? overBudget)
      (let [(why (optionOr overBudget ""))]
        ; (:m :ref CTX-ROUTE :do "a context skip is not a breaker skip: it counts in ctxFails, never in skipped, so a chain no member of which fits ends in contextTooLarge rather than a circuit-breaker cooldown reply")
        (tellAll (list (effLog (str "[Gateway Context] skip " a.alias ": " why "\n")) (usageNote prov a.alias "context budget"))
          (fn [] -> ChatStep
            (loopStep cx (with l1 :idx (+ l1.idx 1) :lastErr (some why) :retryAfterSec 0
                               :ctxFails (+ l1.ctxFails 1) :ctxEst (max l1.ctxEst (promptEstimate body)))))))
    (withBreakerPools (list a.providerPool a.pool)
      (fn [(left Float64) (downPool String)] -> ChatStep
        (if (!= left 0.0)
          (let [(secs (stringFromInt64 (truncInt left)))]
            (tellAll (list (effLog (str "[Gateway Breaker] skip " downPool " for " secs "s\n")) (usageNote prov a.alias (str "breaker " secs "s")))
              (fn [] -> ChatStep
                (loopStep cx (Loop :body body :models l1.models :idx (+ l1.idx 1)
                                   :lastErr (some (str "circuit breaker open for " downPool " (" secs "s left)"))
                                   :skipped (listAppend l1.skipped (list downPool)) :emptyRetries l1.emptyRetries
                                   :telBound l1.telBound :head l1.head :retryAfterSec 0 :ctxNeed l1.ctxNeed :ctxFails l1.ctxFails :ctxEst l1.ctxEst)))))
          (match (missingKey cx a)
            ((some why)
              (tellAll (list (effLog (str "[Gateway Key] skip " a.alias ": " why "\n")) (usageNote prov a.alias "keyMissing"))
                (fn [] -> ChatStep
                  (loopStep cx (Loop :body body :models l1.models :idx (+ l1.idx 1)
                                     :lastErr (some why)
                                     :skipped l1.skipped :emptyRetries l1.emptyRetries
                                     :telBound l1.telBound :head l1.head :retryAfterSec 0 :ctxNeed l1.ctxNeed :ctxFails l1.ctxFails :ctxEst l1.ctxEst)))))
            ((none) (if (cliProvider? prov) (cliAttempt cx l1 a) (rateAttempt cx l1 a)))))))))

; (:m :ref GW-CONTEXT-BUDGET :do "an entry whose :contextBudget (tokens) is below the prompt estimate (a quarter of the serialized messages, the gateway's usual chars-per-token guess) is skipped for the next loop member instead of being sent a request its window cannot hold; some carries the reason text")
; (:m :ref CTX-ROUTE :do "the gateway's prompt token estimate: a quarter of the serialized messages")
fn promptEstimate body: j/Json -> Int64
  (/ (stringLength (pt/jsonDumps (getOr body "messages" (j/jnull)) -1)) 4)

; (:m :ref CTX-ROUTE :do "need is the budget an earlier member overflowed with; a member whose declared budget is not above it is skipped too, so the loop hops only to a member with a larger window; a member with no declared budget is still tried")
fn overContextBudget a: Attempt body: j/Json need: Int64 -> (Option String)
  (match a.v2
    ((none) none)
    ((some e)
      (match e.params.contextBudget
        ((none) none)
        ((some budget)
          (let [(est (promptEstimate body))]
            (cond
              ((> est budget)
               (some (str "prompt about " (stringFromInt64 est) " tokens exceeds " e.alias " contextBudget " (stringFromInt64 budget))))
              ((and (> need 0) (<= budget need))
               (some (str e.alias " contextBudget " (stringFromInt64 budget) " is not above the overflowed window " (stringFromInt64 need))))
              (else none)))))))

; (:m :ref CTX-ROUTE :do "a provider reply that says the prompt overflowed the model's window: a 400, 413 or 422 whose body names a context length, context window or a too long prompt; such a reply is never retried on the same member")
fn contextOverflowError? status: Int64 body: String -> Bool
  (and (listContains? (list 400 413 422) status)
       (let [(low (stringLower body))]
         (listAny? (fn [(m String)] -> Bool (stringContains? low m))
                   (list "context_length_exceeded" "context length" "context window" "maximum context" "context_window_exceeded"
                         "prompt is too long" "input is too long" "too many input tokens" "prompt too long" "exceeds the model's maximum"
                         "input token count" "reduce the length of the messages"))))

; (:m :ref CTX-ROUTE :do "the largest declared contextBudget among the loop's members, 0 when none declares one")
fn maxBudgetOf models: (List c/GatewayResolvedEntry) -> Int64
  (fold (fn [(acc Int64) (m c/GatewayResolvedEntry)] -> Int64
          (match m
            ((c/entryResolved e) (match e.params.contextBudget ((some n) (max acc n)) ((none) acc)))
            ((c/entryUnresolved _) acc)))
        0 models)

fn entryBudget m: c/GatewayResolvedEntry -> Int64
  (match m
    ((c/entryResolved e) (optionOr e.params.contextBudget 0))
    ((c/entryUnresolved _) 0))

fn insertByBudget m: c/GatewayResolvedEntry sorted: (List c/GatewayResolvedEntry) -> (List c/GatewayResolvedEntry)
  (match (listHead sorted)
    ((none) (list m))
    ((some h) (if (> (entryBudget m) (entryBudget h)) (cons m sorted) (cons h (insertByBudget m (optionOr (listTail sorted) (list)))))))

; (:m :ref CTX-ROUTE :do "members ordered by declared contextBudget, largest first; equal budgets keep their chain order and members without a budget go last")
fn byBudget models: (List c/GatewayResolvedEntry) -> (List c/GatewayResolvedEntry)
  (fold (fn [(acc (List c/GatewayResolvedEntry)) (m c/GatewayResolvedEntry)] -> (List c/GatewayResolvedEntry) (insertByBudget m acc)) (list) models)

; (:m :ref CTX-ROUTE :do "a profile's :budgetFirstAbove N: when the prompt estimate is above N tokens the members are tried largest budget first; 0 (absent) keeps the chain order")
fn budgetOrder cx: Ctx body: j/Json models: (List c/GatewayResolvedEntry) -> (List c/GatewayResolvedEntry)
  (let [(above (match cx.world.table ((ok t) (c/gatewayProfileBudgetFirst t cx.profileName)) ((err _) 0)))]
    (if (and (> above 0) (> (promptEstimate body) above)) (byBudget models) models))

; (:m :ref CTX-ROUTE :do "the typed reply when no member's window holds the prompt: 413 with (:err :code contextTooLarge :need N :maxBudget M) and an X-ASL-Max-Context header, so a client compacts to M and retries; maxBudget is left out when no member declares a budget")
fn contextTooLarge cx: Ctx l: Loop -> ChatStep
  (let [(m (maxBudgetOf l.models))
        (need (max l.ctxEst (promptEstimate l.body)))]
    (sendError cx (listAppend l.head (if (> m 0) (list (headField "X-ASL-Max-Context" (stringFromInt64 m))) (list)))
               413 (str "(:err :code contextTooLarge :need " (stringFromInt64 need) (if (> m 0) (str " :maxBudget " (stringFromInt64 m)) "") ")") true))

; (:m :ref CTX-PIN-RELAY :do "a route-mode member that overflowed its window: its declared budget (else the estimate) becomes the need a later member must exceed and the loop moves on; the breaker gets the same event the plain HTTP failure path sends (reset503 for a 4xx), so a config with no budget rows keeps its breaker state as before; a pin profile never comes here, httpFailed relays its reply unchanged")
fn contextOverflowed cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) body: String -> ChatStep
  (let [(est (promptEstimate l.body))
        (declared (match a.v2 ((some e) (optionOr e.params.contextBudget 0)) ((none) 0)))
        (l1 (with l :ctxFails (+ l.ctxFails 1) :ctxEst (max l.ctxEst est) :ctxNeed (max l.ctxNeed (if (> declared 0) declared est))
                    :lastErr (some (str a.alias " HTTP " (stringFromInt64 status) ": prompt about " (stringFromInt64 est) " tokens overflowed its context window")) :retryAfterSec 0))]
    (tellAll (listAppend (overflowBreakerEffects a status headers body)
                         (list (usageNote a.upstream.provider a.alias "contextOverflow")
                               (effLog (str "[Gateway Context] " a.alias " overflowed its context window (HTTP " (stringFromInt64 status) "). Trying a larger member...\n"))))
      (fn [] -> ChatStep (loopStep cx (advance l1 l1.body)))))

; (:m :ref CTX-PIN-RELAY :do "the breaker event httpFailedParked would send for this failure, none for an empty pool or a reply the gateway made itself")
fn overflowBreakerEffects a: Attempt status: Int64 headers: (List (Pair String String)) body: String -> (List ChatEffect)
  (let [(pool (b/breakerScope status body a.providerPool a.pool))
        (event (cond
                 ((or (= status 401) (or (= status 402) (b/breakerIsProviderWideQuota body))) "markDown")
                 ((or (= status 429) (b/breakerIsQuotaError body)) "note429")
                 ((= status 503) "note503")
                 (else "reset503")))]
    (if (or (stringEmpty? pool) (gatewayOrigin? headers)) (list) (list (effBreakerEvent event pool 0))))


fn systemPrompt msgs: (List j/Json) -> (Result String pt/PyErr)
  (match (fold (fn [(acc (Result (List String) pt/PyErr)) (msg j/Json)] -> (Result (List String) pt/PyErr)
              (match acc
                ((err e) (err e))
                ((ok xs)
                 (match (msgGet msg "role" (j/jnull))
                   ((err e) (err e))
                   ((ok role)
                    (if (and (= role (j/jstr "system")) (pt/pyTruthy (getOr msg "content" (j/jnull))))
                      (match (messageText (getOr msg "content" (j/jnull)))
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
    (match (messageList msgsVal)
      ((err e) (raise e))
      ((ok msgs)
       (match (if agentOn (ok "") (systemPrompt msgs))
         ((err e) (raise e))
         ((ok system)
          (match (promptOf msgs (fn [(msg j/Json)] -> (Result Bool pt/PyErr)
                               (match (msgGet msg "content" (j/jnull))
                                 ((err e) (err e))
                                 ((ok c) (ok (and (pt/pyTruthy c) (or agentOn (!= (getOr msg "role" (j/jnull)) (j/jstr "system")))))))))
            ((err e) (raise e))
            ((ok prompt)
             (let [(tools (getOr bodyObj "tools" (j/jnull)))
                   (noTools (or (match tools ((j/jarr xs) (listEmpty? xs)) (_ false))
                                (= (u/pyLower (u/pyStrip (optionOr (u/headerGet hs "X-ASL-Tools") ""))) "none")))
                   (truthy (pt/pyTruthy body))
                   (effort (if truthy (getOr body "effort" (j/jstr "low")) (j/jstr "low")))
                   (temp (if truthy (getOr body "temperature" (j/jfloat 0.2)) (j/jfloat 0.2)))
                   (execRaw (match (u/headerGet hs "X-ASL-Timeout")
                              ((some h) (j/jstr h))
                              ((none) (match (u/headerGet hs "X-ASL-Execution-Timeout")
                                        ((some h) (j/jstr h))
                                        ((none) (if truthy (getOr body "timeout" (getOr body "execution_timeout" (j/jint 300))) (j/jint 300)))))))
                   (queueRaw (match (u/headerGet hs "X-ASL-Queue-Timeout")
                               ((some h) (j/jstr h))
                               ((none) (if truthy (getOr body "queue_timeout" (j/jint 1200)) (j/jint 1200)))))]
               (match (floatOf execRaw)
                 ((err e) (raise e))
                 ((ok execT)
                  (match (floatOf queueRaw)
                    ((err e) (raise e))
                    ((ok queueT)
                     (let [(promptBytes (bytesLength (stringToBytes prompt)))]
                       (if (and (= prov "agy-cli") (and agentOn (> promptBytes cx.world.agyPromptMaxBytes)))
                         (sendError cx l.head 413 (str "agy prompt is " (stringFromInt64 promptBytes) " bytes, over the "
                                                          (stringFromInt64 cx.world.agyPromptMaxBytes) " bytes agy keeps; shorten the message") true)
                         (cliDispatch cx l a prompt system noTools effort temp execT queueT agent bodyObj)))))))))))))))

; (:m :ref GW-SESSION-BIND :do "the caller session key of a request: the X-ASL-Session header unless it is the server fallback asl-run-*, else the body field session; empty when none, and an empty key leaves the CLI dispatch exactly as before; the body field user is not a key")
fn cliCallerKey hs: (List (Pair String String)) body: j/Json -> String
  (let [(h (optionOr (u/headerGet hs "X-ASL-Session") ""))
        (s (if (isObj? body) (strOr (getOr body "session" (j/jstr "")) "") ""))]
    (cond
      ((and (not (stringEmpty? h)) (not (stringStartsWith? h "asl-run-"))) h)
      (else s)))

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
                         (list (pair "prompt" (j/jstr prompt)) (pair "model" (match sub ((some s) (j/jstr s)) ((none) (j/jnull)))) (pair "temp" temp)
                               (pair "effort" effort) (pair "timeout" (j/jfloat execT)) (pair "queue_timeout" (j/jfloat queueT))
                               (pair "workspace" (j/jstr ws)) (pair "system_prompt" sysJ) (pair "no_tools" (j/jbool noTools))))))
                (else
                 (let [(sub (if (stringStartsWith? m "claude/") (some (u/slice m 7 (stringLength m))) none))]
                   (pair (pair "claude" (str "claude:" (optionOr sub "default")))
                         (list (pair "prompt" (j/jstr prompt)) (pair "model" (match sub ((some s) (j/jstr s)) ((none) (j/jnull))))
                               (pair "timeout" (j/jfloat execT)) (pair "queue_timeout" (j/jfloat queueT)) (pair "workspace" (j/jstr ws))
                               (pair "system_prompt" sysJ) (pair "no_tools" (j/jbool noTools)) (pair "effort" effort)))))))
        (client (pairFirst (pairFirst plan)))
        (telModel (pairSecond (pairFirst plan)))
        (sentEffort (match effort ((j/jstr s) (if (listContains? (list "low" "medium" "high" "xhigh" "max") s) (some s) none)) (_ none)))
        (onReply (fn [(r (Option CliReply))] -> ChatStep
                   (match r
                     ((some reply) (cliReplied cx l a reply client telModel sentEffort))
                     ((none)
                      (tell (usageNote prov a.alias "failed")
                        (fn [] -> ChatStep
                          (if (> (listLength l.models) 1)
                            (tell (effUsageFallback prov a.alias) (fn [] -> ChatStep (loopStep cx (advance l l.body))))
                            (sendError cx l.head 502 (str "CLI worker " prov " failed or returned empty response") true))))))))]
    (if (stringEmpty? prompt)
      (onReply none)
      (askCli (effCli client (let [(key (cliCallerKey cx.req.headers bodyObj))] (if (stringEmpty? key) (pairSecond plan) (listAppend (pairSecond plan) (list (pair "session" (j/jstr key)) (pair "messages" (getOr bodyObj "messages" (j/jnull))) (pair "sanitize" (j/jbool cx.sanitize))))))) onReply)))

fn usageInt u: j/Json k: String -> Int64
  (match (getOr u k (j/jnull)) ((j/jint n) n) (_ 0))

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
                  (asl2b (match reply.binding ((j/jnull) asl2) (b (listAppend asl2 (list (pair "binding" b))))))
                  (asl3 (u/objSet asl2b "alias" (j/jstr a.alias)))
                  (asl4 (match sentEffort ((some s) (u/objSet asl3 "effort" (j/jstr s))) ((none) asl3)))
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
                  (noteAffinity cx a.alias (fn [] -> ChatStep
                    (sendReply cx l.head 200 ordered (cons (pair "X-ASL-Fallback" tag) (telemetryHeader rec)))))))))))))


; (:m :ref GW-THROTTLE-NO-AGY :do "a throttled member (bucket depleted) goes straight to the next loop model whenever its entry comes from the config table; the agy CLI rescue stays only for the legacy gemini-only path where no config entry exists")
; (:m :ref GW-THROTTLE-WAIT :do "the last member of a chain waits up to 30 s for its own bucket instead of failing the request, so a chain skipped only by local rpm buckets ends in a call, not an error; earlier members keep the 0.5 s fall-through")
; (:m :ref GW-BUCKET-SHORTWAIT :do "a member before the last waits for its bucket up to the config's :bucketWaitSec (default 5 s) instead of 0.5 s, so a bucket refilling within a few seconds is used rather than skipped; the last member still waits 30 s")
; (:m :ref GW-AFFINITY-SPREAD :do "a session's sticking member waits up to :affinityWaitSec (never past the queue budget) for its own rpm token, so a provider bucket shared with other sessions does not push the session onto another model after a few seconds")
fn bucketWaitSec cx: Ctx l: Loop alias: String -> Float64
  (let [(plain (if (>= l.idx (- (listLength l.models) 1))
                 (queueBudgetSec cx)
                 (match cx.world.table ((ok t) t.bucketWaitSec) ((err _) (c/defaultBucketWaitSec)))))]
    (if (and (> cx.stickWaitSec 0.0) (= alias cx.stuck))
      (max plain (min cx.stickWaitSec (queueBudgetSec cx)))
      plain))

; (:m :ref HUB-QUEUE-PACED :do "the request's own queue budget in seconds: X-ASL-Queue-Ms, else X-ASL-Queue-Timeout, else the body's queue_timeout (Leon always sends one); 30 s when the caller gave none, the wait the last member always had")
fn positiveSec v: j/Json scale: Float64 -> (Option Float64)
  (match (floatOf v)
    ((ok f) (if (> f 0.0) (some (/ f scale)) none))
    ((err _) none))

fn tableQueueBudgetSec cx: Ctx -> Float64
  (match cx.world.table ((ok t) t.queueBudgetSec) ((err _) (c/defaultQueueBudgetSec)))

; (:m :ref GW-ALL-DOWN-RETRY-AFTER :do "the 503 for a chain whose every member is in breaker cooldown carries Retry-After = the shortest cooldown left, rounded up to whole seconds (at least 1), so a caller waits for the first member to come back rather than guessing")
fn minLeftSec lefts: (List Float64) -> Int64
  (let [(least (fold (fn [(acc Float64) (f Float64)] -> Float64 (if (and (> f 0.0) (< f acc)) f acc)) 1000000.0 lefts))]
    (if (>= least 1000000.0) 1 (max 1 (truncInt (+ least 0.999)))))

fn queueBudgetSec cx: Ctx -> Float64
  (let [(hs cx.req.headers)
        (fromMs (match (u/headerGet hs "X-ASL-Queue-Ms") ((some h) (positiveSec (j/jstr h) 1000.0)) ((none) none)))
        (fromHeader (match (u/headerGet hs "X-ASL-Queue-Timeout") ((some h) (positiveSec (j/jstr h) 1.0)) ((none) none)))
        (fromBody (if (isObj? cx.baseBody) (positiveSec (getOr cx.baseBody "queue_timeout" (j/jnull)) 1.0) none))]
    (optionOr fromMs (optionOr fromHeader (optionOr fromBody (tableQueueBudgetSec cx)))))

fn retryAfterOf rpm: Float64 -> Int64
  (max 1 (truncInt (+ (/ 60.0 rpm) 0.999)))

fn withRetryAfter l: Loop secs: Int64 -> Loop
  (with l :retryAfterSec secs)

fn rateAttempt cx: Ctx l: Loop a: Attempt -> ChatStep
  (let [(prov a.upstream.provider)
        (rpm (match a.v2 ((some e) e.rpm) ((none) (if (= prov "gemini") (some 15.0) none))))]
    (match rpm
      ((some r)
       (if (!= r 0.0)
         (askBool (effBucket (match a.v2 ((some e) (if (stringEmpty? e.rpmKey) a.target e.rpmKey)) ((none) a.target)) r (bucketWaitSec cx l a.alias))
           (fn [(acquired Bool)] -> ChatStep
             (if acquired
               (httpAttempt cx l a)
               (tellAll (list (usageNote prov a.alias "throttled") (effUsageFallback prov a.alias))
                 (fn [] -> ChatStep
                   (if (or cx.profileRouted (some? a.v2))
                     (tell (effLog (str "[Gateway RateLimit] Gemini token bucket depleted for " a.alias ". Trying the next profile model...\n"))
                       (fn [] -> ChatStep (loopStep cx (withRetryAfter (failed (advance l l.body) (str "token bucket empty for " a.alias)) (if (>= l.idx (- (listLength l.models) 1)) (retryAfterOf r) 0)))))
                     (tell (effLog (str "[Gateway RateLimit] Gemini token bucket depleted for " a.model ". Cascading to agy fallback...\n"))
                       (fn [] -> ChatStep
                         (match (fallbackPrompt l.body)
                           ((err e) (raise e))
                           ((ok prompt)
                            (agyFallback cx prompt
                              (fn [(r (Option CliReply))] -> ChatStep
                                (match r
                                  ((some reply) (agyReply cx l reply))
                                  ((none) (loopStep cx (advance l l.body))))))))))))))))
         (httpAttempt cx l a)))
      ((none) (httpAttempt cx l a))))

; (:m :ref GW-SLOW-STREAM :do "the attempt's resolved :firstByteSec (model over provider); 0.0 means none was set and the reactor applies no first-byte deadline, so only a configured row changes behaviour")
fn httpFirstByteSec a: Attempt -> Float64
  (match a.v2
    ((some e) e.firstByteSec)
    ((none) 0.0))

fn upTimeout cx: Ctx l: Loop a: Attempt -> (Result Float64 pt/PyErr)
  (let [(body l.body)
        (fallback (fn [] -> Float64
                    (match a.v2
                      ((some e) (if (!= e.timeoutSec 0.0) e.timeoutSec (u/upstreamTimeoutSec cx.world.settings a.upstream.provider)))
                      ((none) (u/upstreamTimeoutSec cx.world.settings a.upstream.provider)))))]
    (if (and (some? a.v2) (and (isObj? body) (pt/pyTruthy (getOr body "timeout" (j/jnull)))))
      (floatOf (getOr body "timeout" (j/jnull)))
      (ok (fallback))))

; (:m :tags (retry) :do "GW-RETRY-OCGO-HANG: a provider's :pool batch window exists to amortize a serverless cold start across concurrent arrivals (modal), so the first request into an idle lane deliberately waits up to :windowMs before dispatch, hoping siblings join the batch. A retried attempt is not a sibling: retryOrFinish already slept once, so by the time it resubmits the lane has gone idle again (the prior batch settled and scaled down), and it would simply pay the full :windowMs a second time -- parked in the pool's own queue, not any connTimer/connBucketWait, with nothing logged while it waits. Across :max retries this compounds past any attempt timeout with zero gateway output, exactly the reported hang; a retry is a single urgent resend, never a batch candidate, so it always skips pooling and goes straight to effHttp")
fn poolConfigFor a: Attempt -> (Option c/GatewayPool)
  (if (> a.retryUsed 0) none a.poolConfig)

; (:m :ref GW-LIMIT-WINDOWS :do "a member whose provider has a limit row asks once per attempt; a spent window skips it with the outcome limit:<window> (pace:<window> when it only runs ahead of an even spread) and the cascade goes on. A config with no limit rows never asks")
fn limitedAttempt? cx: Ctx a: Attempt -> Bool
  (match cx.world.table
    ((ok t) (lim/hasLimitFor? t.limits a.upstream.provider a.alias))
    ((err _) false))

fn limitSkipped cx: Ctx l: Loop a: Attempt outcome: String reason: String -> ChatStep
  (let [(prov a.upstream.provider)
        (l1 (failed l reason))]
    (tell (usageNote prov a.alias outcome)
      (fn [] -> ChatStep
        (if (> cx.cascadeLen 1)
          (tellAll (list (effUsageFallback prov a.alias) (effLog (str "[Gateway Limit] Model " a.model " skipped: " reason " (" outcome "). Cascading to next...\n")))
            (fn [] -> ChatStep (loopStep cx (advance l1 l1.body))))
          (loopStep cx (advance l1 l1.body))))))

; (:m :ref GW-LIMIT-SCOPES :do "a member under a concurrency limit that is full parks: the server answers park with the poll interval, the call sleeps that long and asks again until its queue budget (X-ASL-Queue-Ms, the config's :queueBudgetSec) is used up, then the member is skipped with limit:concurrency and the cascade goes on")
fn httpAttempt cx: Ctx l: Loop a: Attempt -> ChatStep
  (if (limitedAttempt? cx a)
    (askLimit cx l a 0)
    (httpAttemptSend cx l a))

; (:m :ref GW-PARK-LAST-ONLY :do "true when no chain member follows the current one: only that member parks on a full concurrency limit, an earlier one is skipped at once so a later member can answer")
fn lastMember? l: Loop -> Bool
  (>= (+ l.idx 1) (listLength l.models))

fn askLimit cx: Ctx l: Loop a: Attempt waitedMs: Int64 -> ChatStep
  (askStrings (effLimit a.upstream.provider a.alias)
    (fn [(v (List String))] -> ChatStep
      (match (listHead v)
        ((none) (httpAttemptSend cx l a))
        ((some outcome)
          (if (!= outcome "park")
            (limitSkipped cx l a outcome (optionOr (listGet v 1) outcome))
            (if (not (lastMember? l))
              (limitSkipped cx l a "limit:concurrency" "provider concurrency limit full, a later chain member answers")
              (let [(poll (optionOr (stringToInt64 (optionOr (listGet v 2) "250")) 250))
                    (budgetMs (truncInt (* 1000.0 (queueBudgetSec cx))))]
                (if (>= (+ waitedMs poll) budgetMs)
                  (limitSkipped cx l a "limit:concurrency" "provider concurrency limit full for the whole queue budget")
                  (tell (effSleepMs poll) (fn [] -> ChatStep (askLimit cx l a (+ waitedMs poll))))))))))))

fn httpAttemptSend cx: Ctx l: Loop a: Attempt -> ChatStep
  (let [(up a.upstream)
        (reqHeaders (u/withSessionHeader cx.req.headers up.sessionHeader))
        (reqResult (if (= a.api "anthropic")
                     (u/anthropicUpstreamRequest up.url a.path up.key a.data reqHeaders)
                     (u/upstreamRequest up.url a.path up.key a.data reqHeaders)))]
    (match reqResult
      ((err s) (raise (splitErr s)))
      ((ok request)
       (match (upTimeout cx l a)
         ((err e) (raised cx l a false e.msg))
         ((ok timeout)
          (askHttp (match (poolConfigFor a)
            ((some poolConfig) (effPoolHttp up.provider a.model up.url poolConfig request timeout))
            ((none) (effHttp up.provider a.target cx.intent cx.role request timeout cx.profileName (httpFirstByteSec a))))
            (fn [(r HttpReply)] -> ChatStep
              (match r
                ((httpOk status headers body) (httpAnswered cx l a status headers body))
                ((httpError status reason headers body) (httpFailed cx l a status reason headers body))
                ((httpRaised timeout text) (raised cx l a timeout text))))))))))

fn retryPolicyFor cx: Ctx a: Attempt -> c/RetryPolicy
  (c/mergedRetryPolicy cx.table a.upstream.provider a.v2)

; (:m :tags (retry) :do "the shared backoff decision for both httpFailed and raised: read the clock once, anchor the retry deadline to the first failure's clock + the attempt's own timeout budget, abort (fall through to finish) once now or the wanted delay would cross that deadline, else sleep and recurse into httpAttempt on the SAME attempt (model, payload, alias unchanged) with retryUsed incremented")
fn retryOrFinish cx: Ctx l: Loop a: Attempt policy: c/RetryPolicy retryAfterHeader: (Option String) logLine: String usageOutcome: String finish: (fn [] -> ChatStep) -> ChatStep
  (let [(timeoutBudget (resultOr (upTimeout cx l a) 45.0))]
    (askFloat (effClock)
      (fn [(now Float64)] -> ChatStep
        (let [(deadline (optionOr a.retryDeadline (+ now timeoutBudget)))
              (attemptN (+ a.retryUsed 1))
              (retryAfterSec (retryAfterSecondsFromNow retryAfterHeader now))
              (wantMs (u/retryDelayMs policy.baseMs policy.capMs attemptN retryAfterSec now))
              (remainMs (optionOr (float64ToInt64 (* (- deadline now) 1000.0)) 0))]
          (if (or (<= (- deadline now) 0.0) (> wantMs remainMs))
            (finish)
            (tellAll (list (effLog logLine) (usageNote a.upstream.provider a.alias usageOutcome))
              (fn [] -> ChatStep
                (tell (effSleepMs wantMs)
                  (fn [] -> ChatStep (httpAttempt cx l (with a :retryUsed attemptN :retryDeadline (some deadline))))))))))))

fn retryTransport cx: Ctx l: Loop a: Attempt timeout: Bool text: String policy: c/RetryPolicy -> ChatStep
  (retryOrFinish cx l a policy none
    (str "[Gateway Retry] " a.model " transport error: " text ". Retrying attempt " (stringFromInt64 (+ a.retryUsed 1)) " of " (stringFromInt64 policy.maxAttempts) "...\n")
    (str "retry " (if (stringContains? text (u/firstByteDeadlineText)) "firstByteTimeout" (if timeout "timeout" "transport")))
    (fn [] -> ChatStep (raisedFinal cx l a timeout text)))

fn raised cx: Ctx l: Loop a: Attempt timeout: Bool text: String -> ChatStep
  (let [(policy (retryPolicyFor cx a))]
    (if (and (> policy.maxAttempts 0) (< a.retryUsed policy.maxAttempts) (u/retryableRaised? timeout text))
      (retryTransport cx l a timeout text policy)
      (raisedFinal cx l a timeout text)))

; (:m :ref GW-SLOW-STREAM :do "an attempt the reactor failed for a silent connection keeps the timeout flag (so :retry and the cascade treat it as a timeout) but is noted firstByteTimeout in the usage ledger")
fn raisedOutcome timeout: Bool text: String -> String
  (cond
    ((not timeout) "other")
    ((stringContains? text (u/firstByteDeadlineText)) "firstByteTimeout")
    (else "timeout"))

fn raisedFinal cx: Ctx l: Loop a: Attempt timeout: Bool text: String -> ChatStep
  (let [(prov a.upstream.provider)
        (pool a.pool)
        (l1 (failed l text))
        (rest (fn [] -> ChatStep
                (tell (usageNote prov a.alias (raisedOutcome timeout text))
                  (fn [] -> ChatStep
                    (if (> cx.cascadeLen 1)
                      (tellAll (list (effUsageFallback prov a.alias) (effLog (str "[Gateway Cascade] Model " a.model " error: " text ". Cascading to next...\n")))
                        (fn [] -> ChatStep (loopStep cx (advance l1 l1.body))))
                      (loopStep cx (advance l1 l1.body)))))))]
    (if (stringEmpty? pool) (rest) (tell (effBreakerEvent "reset503" pool 0) rest)))

(schema Projection
  (:f resp j/Json)
  (:f content j/Json))

; (:m :tags (chat parser) :do "a reasoning-tuned model may answer only into message.reasoning or message.reasoning_details, leaving message.content empty with finish_reason stop (not length): ERR_EMPTY_CONTENT fired on a real answer the parser never looked at. reasoningFallbackText below is that fallback, used only when content is empty")
fn reasoningDetailsTexts items: (List j/Json) acc: (List String) -> (List String)
  (match (listHead items)
    ((none) (listReverse acc))
    ((some o)
     (let [(rest (optionOr (listTail items) (list)))
           (tx (getOr o "text" (j/jnull)))]
       (match tx
         ((j/jstr s) (reasoningDetailsTexts rest (if (stringEmpty? (pt/pyStrip s)) acc (cons s acc))))
         (_ (reasoningDetailsTexts rest acc))))))

fn reasoningDetailsFallback msg: j/Json -> (Option String)
  (match (getOr msg "reasoning_details" (j/jnull))
    ((j/jarr xs)
     (let [(texts (reasoningDetailsTexts xs (list)))]
       (if (listEmpty? texts) none (some (stringJoin texts "\n")))))
    (_ none))

; (:m :tags (chat parser reasoning) :do "opencodeGo's cat-jam-free names the same field reasoning_content (vLLM/DeepSeek-style), a third spelling beside commandCode's reasoning/reasoning_details; tried after reasoning, before reasoning_details")
fn reasoningContentFallback msg: j/Json -> (Option String)
  (match (getOr msg "reasoning_content" (j/jnull))
    ((j/jstr s) (if (stringEmpty? (pt/pyStrip s)) (reasoningDetailsFallback msg) (some s)))
    (_ (reasoningDetailsFallback msg)))

fn reasoningFallbackText msg: j/Json -> (Option String)
  (match (getOr msg "reasoning" (j/jnull))
    ((j/jstr s) (if (stringEmpty? (pt/pyStrip s)) (reasoningContentFallback msg) (some s)))
    (_ (reasoningContentFallback msg)))

fn projectChoiceList choices: j/Json -> (List j/Json)
  (match choices ((j/jarr xs) xs) (_ (list)))

fn project body: String -> (Option Projection)
  (match (pt/jsonLoads body)
    ((err _) none)
    ((ok resp)
     (if (not (isObj? resp))
       none
       (let [(choices (getOr resp "choices" (j/jarr (list (j/jobj (list))))))
             (first (match choices ((j/jarr xs) (listHead xs)) (_ none)))]
         (match first
           ((some c)
            (if (isObj? c)
              (let [(msg (getOr c "message" (j/jobj (list))))]
                (if (isObj? msg)
                  (let [(raw (getOr msg "content" (j/jnull)))]
                    (if (and (emptyContent? raw) (and (not (toolCalls? msg)) (!= (finishReason resp) "length")))
                      (match (reasoningFallbackText msg)
                        ((none) (some (Projection :resp resp :content raw)))
                        ((some fb)
                         (let [(newMsg (pt/jset msg "content" (j/jstr fb)))
                               (newChoice (pt/jset c "message" newMsg))
                               (restChoices (optionOr (listTail (projectChoiceList choices)) (list)))
                               (newResp (pt/jset resp "choices" (j/jarr (cons newChoice restChoices))))]
                           (some (Projection :resp newResp :content (j/jstr fb))))))
                      (some (Projection :resp resp :content raw))))
                  none))
              none))
           ((none) none))))))

; (:m :ref PROTO-STUDY :do "a message whose content is null but which carries tool_calls answered; it is neither empty nor replaced by its reasoning text, else a native tool call was retried and ended as ERR_EMPTY_CONTENT 502 (nim, 2026-10-29)")
fn toolCalls? msg: j/Json -> Bool
  (match (getOr msg "tool_calls" (j/jnull)) ((j/jarr xs) (not (listEmpty? xs))) (_ false))

fn firstMessage resp: j/Json -> j/Json
  (match (getOr resp "choices" (j/jnull))
    ((j/jarr xs) (match (listHead xs) ((some c) (if (isObj? c) (getOr c "message" (j/jnull)) (j/jnull))) ((none) (j/jnull))))
    (_ (j/jnull)))

fn emptyContent? v: j/Json -> Bool
  (match v ((j/jnull) true) ((j/jstr s) (stringEmpty? (u/pyStrip s))) (_ false))

fn sanitizeFirst resp: j/Json f: (fn [String] -> String) -> j/Json
  (match (getOr resp "choices" (j/jnull))
    ((j/jarr xs)
     (match (listHead xs)
       ((some c)
        (match (getOr c "message" (j/jnull))
          ((j/jobj _)
           (let [(msg (getOr c "message" (j/jnull)))
                 (content (getOr msg "content" (j/jnull)))
                 (newMsg (match content ((j/jstr s) (pt/jset msg "content" (j/jstr (f s)))) (_ msg)))]
             (pt/jset resp "choices" (j/jarr (cons (pt/jset c "message" newMsg) (optionOr (listTail xs) (list)))))))
          (_ resp)))
       ((none) resp)))
    (_ resp))

; (:m :ref CTX-ROUTE :do "maxContext is the largest contextBudget in the loop's chain, sent as maxContextTokens when any member declares one: the largest window this route can serve, so a client knows how far it may grow before compacting harder")
; (:m :ref GW-AFFINITY-SPREAD :do "prev is the session's last answering member (empty when none); when another member answers, the reply names it as switchedFrom, so the caller rebuilds its context for the new member's contextTokens")
fn servedBy a: Attempt body: j/Json maxContext: Int64 prev: String -> (List (Pair String j/Json))
  (let [(base (if (or (stringEmpty? prev) (= prev a.alias))
                (list (pair "alias" (j/jstr a.alias)))
                (list (pair "alias" (j/jstr a.alias)) (pair "switchedFrom" (j/jstr prev)))))
        (withEffort (match a.sentEffort
                      ((some e) (match e ((some s) (listAppend base (list (pair "effort" (j/jstr s))))) ((none) base)))
                      ((none) base)))
        (temp (if (isObj? body) (getOr body "temperature" (j/jnull)) (j/jnull)))
        (withTemp (if (isNull? temp) withEffort (listAppend withEffort (list (pair "temperature" temp)))))]
    (listAppend
      (match a.v2
        ((some e) (match e.params.contextBudget
                    ((some n) (listAppend withTemp (list (pair "contextTokens" (j/jint n)))))
                    ((none) withTemp)))
        ((none) withTemp))
      (if (> maxContext 0) (list (pair "maxContextTokens" (j/jint maxContext))) (list))))

fn mergeAsl resp: j/Json served: (List (Pair String j/Json)) -> j/Json
  (let [(existing (match (getOr resp "asl" (j/jnull)) ((j/jobj kvs) kvs) (_ (list))))]
    (pt/jset resp "asl" (j/jobj (fold (fn [(acc (List (Pair String j/Json))) (p (Pair String j/Json))] -> (List (Pair String j/Json))
                                        (u/objSet acc (pairFirst p) (pairSecond p)))
                                      existing served))))

fn dropHeaders hs: (List (Pair String String)) names: (List String) -> (List (Pair String String))
  (filter (fn [(p (Pair String String))] -> Bool (not (listContains? names (u/pyLower (pairFirst p))))) hs)

fn respTexts items: (List j/Json) acc: (List String) -> (List String)
  (match (listHead items)
    ((none) (listReverse acc))
    ((some o)
     (let [(rest (optionOr (listTail items) (list)))
           (isMsg (= (getOr o "type" (j/jnull)) (j/jstr "message")))
           (cItems (match (getOr o "content" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
           (texts (fold (fn [(acc2 (List String)) (c j/Json)] -> (List String)
                          (let [(ct (getOr c "type" (j/jnull)))
                                (tx (getOr c "text" (j/jnull)))]
                            (if (and (= ct (j/jstr "output_text")) (pt/pyTruthy tx))
                              (match tx ((j/jstr s) (cons s acc2)) (_ acc2))
                              acc2)))
                        acc cItems))]
       (if isMsg (respTexts rest texts) (respTexts rest acc)))))

fn responsesToChat body: String -> (Option String)
  (match (pt/jsonLoads body)
    ((err _) none)
    ((ok resp)
     (if (and (isObj? resp) (pt/pyTruthy (getOr resp "output" (j/jnull))))
       (let [(itemsL (match (getOr resp "output" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
             (content (stringJoin (respTexts itemsL (list)) ""))
             (usage (getOr resp "usage" (j/jnull)))
             (msg (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr content)))))
             (choice (j/jobj (list (pair "message" msg))))
             (use (j/jobj (list (pair "prompt_tokens" (j/jint (usageInt usage "input_tokens")))
                                (pair "completion_tokens" (j/jint (usageInt usage "output_tokens"))))))
             (chat (j/jobj (list (pair "choices" (j/jarr (list choice))) (pair "usage" use))))]
         (some (pt/jsonDumps chat -1)))
       none)))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "true when the attempt's model row carries :stream true; a row without it, or a legacy attempt with no row, is not a stream route")
fn rowStream v2: (Option c/GatewayEntry) -> Bool
  (match v2 ((some e) (optionOr e.params.stream false)) ((none) false))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "the chat body a stream row sends: stream true and stream_options include_usage so the final chunk carries usage; other APIs and non-stream rows go unchanged")
fn streamBody on: Bool api: String body: j/Json -> j/Json
  (if (and on (and (= api "chat") (isObj? body)))
    (pt/jset (pt/jset body "stream" (j/jbool true)) "stream_options" (j/jobj (list (pair "include_usage" (j/jbool true)))))
    body)

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "a reply is SSE when its first non-blank line is a data:, event: or : comment line")
fn sseBody? body: String -> Bool
  (match (listFind (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit (stringReplace body "\r\n" "\n") "\n"))
    ((some l) (let [(t (stringTrim l))] (or (stringStartsWith? t "data:") (or (stringStartsWith? t "event:") (stringStartsWith? t ":")))))
    ((none) false))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "the data payload of each SSE event in order: data: lines of one event joined by newlines, events split on blank lines, the [DONE] sentinel and data-less events dropped")
fn sseData body: String -> (List String)
  (let [(events (stringSplit (stringReplace body "\r\n" "\n") "\n\n"))
        (payload (fn [(ev String)] -> String
                   (stringJoin (map (fn [(l String)] -> String (stringTrim (optionOr (stringSlice l 5 (stringLength l)) "")))
                                    (filter (fn [(l String)] -> Bool (stringStartsWith? l "data:")) (stringSplit ev "\n")))
                               "\n")))]
    (filter (fn [(d String)] -> Bool (and (not (stringEmpty? d)) (!= d "[DONE]"))) (map payload events)))

(schema SseFold
  (:f ok Bool)
  (:f id String)
  (:f model String)
  (:f content (List String))
  (:f reasoning (List String))
  (:f finish String)
  (:f usage j/Json)
  (:f calls (List (Pair Int64 (List String)))))

fn jText v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "a tool call delta at index i: the first delta brings id and function name, later ones append argument text; kept as (i (id name args))")
fn sseCall calls: (List (Pair Int64 (List String))) tc: j/Json -> (List (Pair Int64 (List String)))
  (let [(i (match (getOr tc "index" (j/jnull)) ((j/jint n) n) (_ 0)))
        (fnv (getOr tc "function" (j/jnull)))
        (id (jText (getOr tc "id" (j/jnull))))
        (name (jText (getOr fnv "name" (j/jnull))))
        (args (jText (getOr fnv "arguments" (j/jnull))))]
    (match (listFind (fn [(p (Pair Int64 (List String)))] -> Bool (= (pairFirst p) i)) calls)
      ((none) (listAppend calls (list (pair i (list id name args)))))
      ((some p)
       (map (fn [(q (Pair Int64 (List String)))] -> (Pair Int64 (List String))
              (if (= (pairFirst q) i)
                (let [(cur (pairSecond q))]
                  (pair i (list (let [(c0 (optionOr (listGet cur 0) ""))] (if (stringEmpty? c0) id c0))
                                (let [(c1 (optionOr (listGet cur 1) ""))] (if (stringEmpty? c1) name c1))
                                (str (optionOr (listGet cur 2) "") args))))
                q))
            calls))))

fn sseStep acc: SseFold d: String -> SseFold
  (if (not acc.ok)
    acc
    (match (pt/jsonLoads d)
      ((err _) (with acc :ok false))
      ((ok chunk)
       (if (or (not (isObj? chunk)) (has? chunk "error"))
         (with acc :ok false)
         (let [(choice (match (getOr chunk "choices" (j/jnull)) ((j/jarr xs) (optionOr (listHead xs) (j/jnull))) (_ (j/jnull))))
               (delta (getOr choice "delta" (j/jnull)))
               (c (jText (getOr delta "content" (j/jnull))))
               (r (let [(rc (jText (getOr delta "reasoning_content" (j/jnull))))] (if (stringEmpty? rc) (jText (getOr delta "reasoning" (j/jnull))) rc)))
               (fin (jText (getOr choice "finish_reason" (j/jnull))))
               (use (getOr chunk "usage" (j/jnull)))
               (tcs (match (getOr delta "tool_calls" (j/jnull)) ((j/jarr xs) xs) (_ (list))))]
           (with acc
             :id (if (stringEmpty? acc.id) (jText (getOr chunk "id" (j/jnull))) acc.id)
             :model (if (stringEmpty? acc.model) (jText (getOr chunk "model" (j/jnull))) acc.model)
             :content (if (stringEmpty? c) acc.content (cons c acc.content))
             :reasoning (if (stringEmpty? r) acc.reasoning (cons r acc.reasoning))
             :finish (if (stringEmpty? fin) acc.finish fin)
             :usage (if (isObj? use) use acc.usage)
             :calls (fold sseCall acc.calls tcs)))))))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "an SSE reply that carries an event: error line, whatever its data")
fn sseErrorEvent? body: String -> Bool
  (some? (listFind (fn [(l String)] -> Bool (= (stringReplace (stringTrim l) " " "") "event:error")) (stringSplit (stringReplace body "\r\n" "\n") "\n")))

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "folds an OpenAI SSE reply into one chat.completion: content and reasoning deltas concatenated in order, tool call deltas joined per index, the last finish_reason, usage from the chunk that carries it; none when no event parses, any data payload is not a JSON object or carries an error key, an event: error arrives, or no chunk gave a finish_reason (a truncated stream), so a broken stream is never a partial answer")
fn sseToChat body: String -> (Option String)
  (let [(ds (sseData body))
        (f (fold sseStep (SseFold :ok true :id "" :model "" :content (list) :reasoning (list) :finish "" :usage (j/jnull) :calls (list)) ds))]
    (if (or (not f.ok) (or (listEmpty? ds) (or (sseErrorEvent? body) (stringEmpty? f.finish))))
      none
      (let [(reasoning (stringJoin (listReverse f.reasoning) ""))
            (calls (map (fn [(p (Pair Int64 (List String)))] -> j/Json
                          (let [(v (pairSecond p))]
                            (j/jobj (list (pair "id" (j/jstr (optionOr (listGet v 0) ""))) (pair "type" (j/jstr "function"))
                                          (pair "function" (j/jobj (list (pair "name" (j/jstr (optionOr (listGet v 1) ""))) (pair "arguments" (j/jstr (optionOr (listGet v 2) ""))))))))))
                        f.calls))
            (msg (j/jobj (listAppend (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr (stringJoin (listReverse f.content) ""))))
                                     (listAppend (if (stringEmpty? reasoning) (list) (list (pair "reasoning_content" (j/jstr reasoning))))
                                                 (if (listEmpty? calls) (list) (list (pair "tool_calls" (j/jarr calls))))))))
            (choice (j/jobj (list (pair "index" (j/jint 0)) (pair "message" msg) (pair "finish_reason" (j/jstr (if (stringEmpty? f.finish) "stop" f.finish))))))
            (chat (j/jobj (listAppend (list (pair "id" (j/jstr f.id)) (pair "object" (j/jstr "chat.completion")) (pair "model" (j/jstr f.model)) (pair "choices" (j/jarr (list choice))))
                                      (if (isObj? f.usage) (list (pair "usage" f.usage)) (list)))))]
        (some (pt/jsonDumps chat -1)))))

(schema AnthropicFold
  (:f texts (List String))
  (:f calls (List j/Json))
  (:f thinking (List String)))

fn anthropicContentBlocksFold acc: AnthropicFold block: j/Json -> AnthropicFold
  (let [(t (strOr (getOr block "type" (j/jnull)) ""))]
    (cond
      ((= t "text") (with acc :texts (listAppend acc.texts (list (strOr (getOr block "text" (j/jstr "")) "")))))
      ((= t "thinking") (with acc :thinking (listAppend acc.thinking (list (strOr (getOr block "thinking" (j/jstr "")) "")))))
      ((= t "tool_use")
       (let [(id (strOr (getOr block "id" (j/jstr "")) ""))
             (name (strOr (getOr block "name" (j/jstr "")) ""))
             (input (getOr block "input" (j/jobj (list))))
             (call (j/jobj (list (pair "id" (j/jstr id)) (pair "type" (j/jstr "function"))
                                  (pair "function" (j/jobj (list (pair "name" (j/jstr name)) (pair "arguments" (j/jstr (pt/jsonDumps input -1)))))))))]
         (with acc :calls (listAppend acc.calls (list call)))))
      (else acc)))

; (:m :tags (anthropic) :do "stop_reason -> finish_reason mirrors OpenAI's vocabulary so the rest of the pipeline (which only ever reads finish_reason) is unaware the call went to Anthropic")
fn anthropicStopReasonToFinish v: j/Json -> String
  (let [(s (strOr v ""))]
    (cond
      ((= s "max_tokens") "length")
      ((= s "tool_use") "tool_calls")
      ((or (= s "end_turn") (= s "stop_sequence")) "stop")
      (else "stop")))

fn anthropicToChat body: String -> (Option String)
  (match (pt/jsonLoads body)
    ((err _) none)
    ((ok resp)
     (if (not (isObj? resp)) none
       (let [(blocks (match (getOr resp "content" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
             (folded (fold anthropicContentBlocksFold (AnthropicFold :texts (list) :calls (list) :thinking (list)) blocks))
             (contentText (stringJoin folded.texts ""))
             (msg0 (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr contentText)))))
             (msg1 (if (listEmpty? folded.thinking) msg0 (pt/jset msg0 "reasoning_content" (j/jstr (stringJoin folded.thinking "\n\n")))))
             (msg2 (if (listEmpty? folded.calls) msg1 (pt/jset msg1 "tool_calls" (j/jarr folded.calls))))
             (finish (anthropicStopReasonToFinish (getOr resp "stop_reason" (j/jnull))))
             (choice (j/jobj (list (pair "message" msg2) (pair "finish_reason" (j/jstr finish)))))
             (usage (getOr resp "usage" (j/jnull)))
             (inputTokens (usageInt usage "input_tokens"))
             (cacheRead (usageInt usage "cache_read_input_tokens"))
             (cacheCreate (usageInt usage "cache_creation_input_tokens"))
             (use (j/jobj (list (pair "prompt_tokens" (j/jint (+ inputTokens (+ cacheRead cacheCreate))))
                                (pair "completion_tokens" (j/jint (usageInt usage "output_tokens")))
                                (pair "cached_tokens" (j/jint cacheRead))
                                (pair "cache_creation_tokens" (j/jint cacheCreate)))))
             (chat (j/jobj (list (pair "choices" (j/jarr (list choice))) (pair "usage" use))))]
         (some (pt/jsonDumps chat -1))))))

(schema GeminiFold
  (:f texts (List String))
  (:f calls (List j/Json))
  (:f thinking (List String)))

; (:m :tags (gemini) :do "a part is text (the normal case), text with :thought true (Gemini's reasoning trace, becomes reasoning_content like Anthropic's thinking blocks), or a functionCall (becomes an OpenAI tool_calls entry; Gemini never sends a call id, so one is synthesized from the position in acc.calls)")
fn geminiPartsFold acc: GeminiFold part: j/Json -> GeminiFold
  (let [(isThought (match (getOr part "thought" (j/jnull)) ((j/jbool b) b) (_ false)))
        (textV (getOr part "text" (j/jnull)))
        (fc (getOr part "functionCall" (j/jnull)))]
    (cond
      ((pt/pyTruthy fc)
       (let [(name (strOr (getOr fc "name" (j/jstr "")) ""))
             (args (getOr fc "args" (j/jobj (list))))
             (callId (str "call_" (stringFromInt64 (listLength acc.calls))))
             (call (j/jobj (list (pair "id" (j/jstr callId)) (pair "type" (j/jstr "function"))
                                  (pair "function" (j/jobj (list (pair "name" (j/jstr name)) (pair "arguments" (j/jstr (pt/jsonDumps args -1)))))))))]
         (with acc :calls (listAppend acc.calls (list call)))))
      ((and isThought (pt/pyTruthy textV)) (with acc :thinking (listAppend acc.thinking (list (strOr textV "")))))
      ((pt/pyTruthy textV) (with acc :texts (listAppend acc.texts (list (strOr textV "")))))
      (else acc)))

; (:m :tags (gemini) :do "Gemini reports STOP even when the turn is really a tool call, so finish_reason has to come from whether any functionCall part was seen, not from finishReason alone")
fn geminiFinishReasonToFinish fr: String hasCalls: Bool -> String
  (if hasCalls "tool_calls"
    (cond
      ((= fr "MAX_TOKENS") "length")
      ((= fr "STOP") "stop")
      (else "stop")))

fn geminiToChat body: String -> (Option String)
  (match (pt/jsonLoads body)
    ((err _) none)
    ((ok resp)
     (if (not (isObj? resp)) none
       (let [(cands (match (getOr resp "candidates" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
             (cand0 (optionOr (listGet cands 0) (j/jnull)))
             (parts (match (getOr (getOr cand0 "content" (j/jnull)) "parts" (j/jnull)) ((j/jarr xs) xs) (_ (list))))
             (folded (fold geminiPartsFold (GeminiFold :texts (list) :calls (list) :thinking (list)) parts))
             (contentText (stringJoin folded.texts ""))
             (msg0 (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr contentText)))))
             (msg1 (if (listEmpty? folded.thinking) msg0 (pt/jset msg0 "reasoning_content" (j/jstr (stringJoin folded.thinking "\n\n")))))
             (msg2 (if (listEmpty? folded.calls) msg1 (pt/jset msg1 "tool_calls" (j/jarr folded.calls))))
             (finish (geminiFinishReasonToFinish (strOr (getOr cand0 "finishReason" (j/jstr "")) "") (not (listEmpty? folded.calls))))
             (choice (j/jobj (list (pair "message" msg2) (pair "finish_reason" (j/jstr finish)))))
             (usage (getOr resp "usageMetadata" (j/jnull)))
             (promptTokens (usageInt usage "promptTokenCount"))
             (candidatesTokens (usageInt usage "candidatesTokenCount"))
             (thoughtsTokens (usageInt usage "thoughtsTokenCount"))
             (cachedTokens (usageInt usage "cachedContentTokenCount"))
             (use (j/jobj (list (pair "prompt_tokens" (j/jint promptTokens))
                                (pair "completion_tokens" (j/jint (+ candidatesTokens thoughtsTokens)))
                                (pair "cached_tokens" (j/jint cachedTokens)))))
             (chat (j/jobj (list (pair "choices" (j/jarr (list choice))) (pair "usage" use))))]
         (some (pt/jsonDumps chat -1))))))

fn httpAnswered cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) body: String -> ChatStep
  (let [(prov a.upstream.provider)
        (alias a.alias)
        (m a.model)
        (chatBody (cond ((= a.api "responses") (optionOr (responsesToChat body) body))
                         ((= a.api "anthropic") (optionOr (anthropicToChat body) body))
                         ((= a.api "gemini") (optionOr (geminiToChat body) body))
                         ((and (rowStream a.v2) (sseBody? body)) (optionOr (sseToChat body) body))
                         (else body)))
        (proj (project chatBody))]
    (match proj
      ((some p)
       (if (and (emptyContent? p.content) (not (toolCalls? (firstMessage p.resp))))
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
         (if (not (stringEmpty? (judgeFailure cx p chatBody)))
           (judged cx l a p (judgeFailure cx p chatBody))
         (let [(content p.content)
               (sanitized (if cx.sanitize (sanitizeFirst p.resp w/sanitizeAsnContent) p.resp))]
           (telemetry cx content m
             (fn [(rec (Option String))] -> ChatStep
               (let [(withModel (if (has? sanitized "model") sanitized (pt/jset sanitized "model" (j/jstr a.target))))
                     (resp (mergeAsl withModel (servedBy a l.body (maxBudgetOf l.models) cx.stuck)))
                     (lb (with l :telBound true))]
                 (answered cx lb a status headers (pt/jsonDumps resp -1) (some resp) rec))))))))
      ((none) (answered cx l a status headers body none none))))

; (:m :ref GW-MODES :do "a reply that fails a judge check is charged to its member with the outcome judge:CHECK and the next member is tried; past the last member the profile's no-model-answered error names the check")
fn judged cx: Ctx l: Loop a: Attempt p: Projection why: String -> ChatStep
  (tellAll (list (effUsageNote a.upstream.provider a.alias (str "judge:" why) (getOr p.resp "usage" (j/jnull)))
                 (effLog (str "[Gateway Judge] Model " a.model " failed the " why " check. Trying the next member...\n")))
    (fn [] -> ChatStep (loopStep cx (advance (failed l (str "judge " why ": " a.alias)) l.body))))

; (:m :tags (breaker pool) :do "a success clears both the model pool and the provider pool: it proves the account and this model both work, so any stale account-wide trip (from a sibling model's 401/402) is cleared too")
fn clearBreakerPools pools: (List String) k: (fn [] -> ChatStep) -> ChatStep
  (match (listHead pools)
    ((none) (k))
    ((some p)
     (let [(rest (optionOr (listTail pools) (list)))]
       (if (stringEmpty? p)
         (clearBreakerPools rest k)
         (tell (effBreakerEvent "clear" p 0) (fn [] -> ChatStep (clearBreakerPools rest k)))))))

fn answered cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) respBody: String resp: (Option j/Json) rec: (Option String) -> ChatStep
  (let [(prov a.upstream.provider)
        (usage (match resp ((some r) (getOr r "usage" (j/jnull))) ((none) (j/jnull))))
        (finish (fn [] -> ChatStep
                  (match resp
                    ((some r)
                     (if cx.asn
                       (sendReply cx l.head status r (telemetryHeader rec))
                       (passthrough cx l a status headers respBody rec)))
                    ((none) (passthrough cx l a status headers respBody rec)))))]
    (tell (effUsageNote prov a.alias "ok" usage)
      (fn [] -> ChatStep (noteSwitch cx l a.alias (fn [] -> ChatStep (noteAffinity cx a.alias (fn [] -> ChatStep (clearBreakerPools (list a.pool a.providerPool) finish))))))))

; (:m :ref GW-AFFINITY-SPREAD :do "a sticking session answered by another member than its own records the switch: a skippedSwitch usage note on the member it left (not a sent call) and a log line naming session, from and to")
fn noteSwitch cx: Ctx l: Loop alias: String k: (fn [] -> ChatStep) -> ChatStep
  (if (or (stringEmpty? cx.session) (or (not cx.sticking) (or (stringEmpty? cx.stuck) (= cx.stuck alias))))
    (k)
    (let [(prov (fold (fn [(acc String) (m c/GatewayResolvedEntry)] -> String
                        (match m ((c/entryResolved e) (if (= e.alias cx.stuck) e.provider acc)) ((c/entryUnresolved _) acc)))
                      "" l.models))]
      (tellAll (list (usageNote prov cx.stuck (str "skippedSwitch:" alias))
                     (effLog (str "[Gateway Affinity] session " cx.session " switched " cx.stuck " -> " alias "\n")))
        k)))

fn passthrough cx: Ctx l: Loop a: Attempt status: Int64 headers: (List (Pair String String)) respBody: String rec: (Option String) -> ChatStep
  (let [(head (listAppend l.head
                          (cons (headStatus status)
                                (listAppend (fields (dropHeaders headers (list "transfer-encoding" "content-encoding" "content-length" "connection")))
                                            (list (headField "Content-Length" (stringFromInt64 (bytesLength (stringToBytes respBody)))))))))]
    (if l.telBound
      (done (listAppend head (listAppend (fields (telemetryHeader rec)) (list (headField "X-ASL-Wire" "asn,json")))) respBody)
      (raised cx (with (with l :head head) :telBound false) a false "cannot access local variable 'tel_rec' where it is not associated with a value")))

fn gatewayOriginHeader -> String
  "X-ASL-Origin"

fn gatewayOrigin? headers: (List (Pair String String)) -> Bool
  (listAny? (fn [(h (Pair String String))] -> Bool (and (= (stringLower (pairFirst h)) (stringLower (gatewayOriginHeader))) (= (pairSecond h) "gateway"))) headers)

fn retryAfterHeaderOf headers: (List (Pair String String)) -> (Option String)
  (u/headerGet headers "Retry-After")

; (:m :tags (retry) :do "Retry-After is either delta-seconds (\"120\") or the RFC 7231 preferred HTTP-date (\"Wed, 21 Oct 2026 07:28:00 GMT\"); delta-seconds is tried first since it is overwhelmingly the common form and is unambiguous, falling back to the date form resolved against now; a header present but unparseable by either form is none, same as absent, so retryDelayMs falls back to the jittered exponential window instead of guessing")
fn retryAfterSecondsFromNow headerText: (Option String) now: Float64 -> (Option Float64)
  (match headerText
    ((none) none)
    ((some raw)
     (let [(s (u/pyStrip raw))]
       (match (u/pyFloat s)
         ((ok f) (if (>= f 0.0) (some f) none))
         ((err _) (match (if (stringEndsWith? s " GMT") (lt/parseHttpDateEpochSeconds s) none)
                    ((some epoch) (some (- epoch now)))
                    ((none) none)))))))

; (:m :ref GW-BREAKER-STALE-20261018 :tags (breaker pool) :do "401/402 and an explicit provider-wide quota marker trip the whole provider; a 429 or any body matching breakerIsQuotaError trips only this model's pool, so a rate-limited free model does not block its siblings; a plain 503/502/504 with no quota marker is deliberately provider-wide after 3 strikes (parity-pinned in chatParityFixture.asn), treated as generic infra trouble rather than a per-model limit -- checked against the real incident: Gemini's RESOURCE_EXHAUSTED body already matches breakerIsQuotaError and was already per-model, so the staleness there was the fixed 600s cooldown outlasting the sweep, not pool scope")
fn retryHttp cx: Ctx l: Loop a: Attempt status: Int64 reason: String headers: (List (Pair String String)) body: String policy: c/RetryPolicy -> ChatStep
  (retryOrFinish cx l a policy (retryAfterHeaderOf headers)
    (str "[Gateway Retry] " a.model " HTTP " (stringFromInt64 status) ". Retrying attempt " (stringFromInt64 (+ a.retryUsed 1)) " of " (stringFromInt64 policy.maxAttempts) "...\n")
    (str "retry " (stringFromInt64 status))
    (fn [] -> ChatStep (httpFailedFinal cx l a status reason headers body)))

fn httpFailed cx: Ctx l: Loop a: Attempt status: Int64 reason: String headers: (List (Pair String String)) body: String -> ChatStep
  (let [(policy (retryPolicyFor cx a))]
    ; (:m :ref CTX-PIN-RELAY :do "a pin profile relays an overflow like any other failure (GW-MODES); only route and judge hop to a larger window")
    (if (and (!= cx.mode "pin") (contextOverflowError? status body))
      (contextOverflowed cx l a status headers body)
    (if (and (> policy.maxAttempts 0) (< a.retryUsed policy.maxAttempts) (u/retryableHttpStatus? status body))
      (retryHttp cx l a status reason headers body policy)
      (httpFailedFinal cx l a status reason headers body))))

; (:m :ref GW-DAILY-PARK :do "a daily-cap 429 asks the clock once so the model is parked until the provider's reset instead of the fixed cooldown; every other failure goes straight on")
fn httpFailedFinal cx: Ctx l: Loop a: Attempt status: Int64 reason: String headers: (List (Pair String String)) body: String -> ChatStep
  (let [(kind (u/dailyCapKind status body))
        (retryAfter (u/headerGet headers "retry-after"))]
    (if (and (stringEmpty? kind) (match retryAfter ((some _) false) ((none) true)))
      (httpFailedParked cx l a status reason headers body 0 0.0)
      (askFloat (effClock)
        (fn [(now Float64)] -> ChatStep
          (if (stringEmpty? kind)
            (httpFailedParked cx l a status reason headers body 0 now)
            (httpFailedParked cx l a status reason headers body (u/dailyCapParkSec kind headers body now) now))))))

fn limitWindowSec w: String -> Int64
  (cond ((= w "minute") 60) ((= w "hour") 3600) ((= w "day") 86400) (else 0))

; (:m :ref GW-429-WINDOW-WAIT :do "the aligned window a member's limit resets on: 60 s when the alias is paced by :rpm, else the shortest minute, hour or day of the (:gateway :limits ...) rows for its provider (scope account) or for the alias itself (scope model); 0 when none, so the breaker uses its growing base; fiveHour, week and month are rolling and give no boundary")
fn memberWindowSec cx: Ctx a: Attempt -> Int64
  (match a.v2
    ((none) 0)
    ((some e)
      (let [(fromRpm (match e.rpm ((some r) (if (> r 0.0) 60 0)) ((none) 0)))
            (rows (match cx.world.table ((ok t) t.limits) ((err _) (list))))
            (own (filter (fn [(l c/GatewayLimit)] -> Bool (and (= l.provider e.provider) (or (= l.scope "account") (= l.model e.alias)))) rows))
            (secs (filter (fn [(n Int64)] -> Bool (> n 0)) (cons fromRpm (map (fn [(l c/GatewayLimit)] -> Int64 (limitWindowSec l.window)) own))))]
        (fold (fn [(m Int64) (n Int64)] -> Int64 (if (or (= m 0) (< n m)) n m)) 0 secs))))

fn httpFailedParked cx: Ctx l: Loop a: Attempt status: Int64 reason: String headers: (List (Pair String String)) body: String parkSec: Int64 now: Float64 -> ChatStep
  (let [(prov a.upstream.provider)
        (alias a.alias)
        (providerWide (or (= status 401) (or (= status 402) (b/breakerIsProviderWideQuota body))))
        (quota (or (= status 429) (b/breakerIsQuotaError body)))
        (pool (b/breakerScope status body a.providerPool a.pool))
        (park (if (and (> parkSec 0) (and quota (not providerWide))) parkSec 0))
        ; (:m :ref GW-429-WINDOW-WAIT :do "a 429 that is not a daily cap sends note429 (note429window:SECONDS for a member with an aligned window, see memberWindowSec) with the wait its headers name; the breaker turns that into the hint, the minute window end or the growing base")
        (windowSec (memberWindowSec cx a))
        (errText (u/httpErrorText status reason))
        (l1 (failed l errText))
        (event (cond
                 (providerWide "markDown")
                 (quota (cond ((> park 0) "markDown") ((> windowSec 0) (str "note429window:" windowSec)) (else "note429")))
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
                       ; (:m :ref GW-MODES :do "a pin profile relays its member's HTTP error with its own status and headers (Retry-After included) instead of trying anything else")
                       ((= cx.mode "pin") (relay))
                       (cx.profileRouted
                        (tellAll (list (effLog (str "[Gateway Profile] Model " alias " returned HTTP " (stringFromInt64 status) ". Trying the next profile model...\n"))
                                       (effUsageFallback prov alias))
                          (fn [] -> ChatStep (loopStep cx (advance l1 l1.body)))))
                       ((listContains? (list 429 502 503 504) status)
                        (tellAll (list (effUsageFallback prov alias)
                                       (effLog (str "[Gateway Cascade] Model " a.model " returned HTTP " (stringFromInt64 status) ". Checking agy fallback...\n")))
                          (fn [] -> ChatStep
                            (match (fallbackPrompt l1.body)
                              ((err e) (raise e))
                              ((ok prompt)
                               (agyFallback cx prompt
                                 (fn [(r (Option CliReply))] -> ChatStep
                                   (match r
                                     ((some reply) (agyReply cx l1 reply))
                                     ((none) (if (> cx.cascadeLen 1) (loopStep cx (advance l1 l1.body)) (relay)))))))))))
                       (else (relay)))))))
        ; (:m :ref GW-SPREAD-LIVE-20261018 :do "records this alias's 429 for the spread cooldown, in addition to (never instead of) the existing per-model breaker trip above -- the breaker's own cooldown is fixed and provider/account-scoped, :cooldownSec is per-route and configurable, the two must stay independent")
        (effs (listAppend (if (or (stringEmpty? pool) (gatewayOrigin? headers)) (list) (list (effBreakerEvent event pool (if (stringStartsWith? event "note429") (b/quotaHintSec headers now) park))))
                (if (and (= status 429) (not (listEmpty? cx.spread))) (list (effSpreadNote429 alias)) (list))))]
    (if (listEmpty? effs) (after) (tellAll effs after)))


fn labels models: (List c/GatewayResolvedEntry) -> String
  (stringJoin (map c/gatewayEntryLabel models) ", ")

fn lastErrSuffix l: Loop -> String
  (match l.lastErr ((some e) (str "; last error: " e)) ((none) ""))

fn uniqueSorted xs: (List String) -> (List String)
  (listSort (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn maxFloat fs: (List Float64) -> Float64
  (fold (fn [(acc Float64) (f Float64)] -> Float64 (if (> f acc) f acc)) (optionOr (listHead fs) 0.0) fs)

fn afterLoop cx: Ctx l: Loop -> ChatStep
  (let [(skipped l.skipped)
        (model cx.explicitModel)]
    (cond
      ((> l.retryAfterSec 0)
       (sendError cx (listAppend l.head (list (headField "Retry-After" (stringFromInt64 l.retryAfterSec))))
                  429 (str "ERR_RATE_LIMITED: no rate-limit token within the queue budget" (lastErrSuffix l) "; retry in " (stringFromInt64 l.retryAfterSec) "s") true))
      ((and (> l.ctxFails 0) (>= l.ctxFails cx.cascadeLen)) (contextTooLarge cx l))
      ((and (not (listEmpty? skipped)) (>= (listLength skipped) cx.cascadeLen))
       (let [(pools (uniqueSorted skipped))]
         (askFloats (effBreakerDownAll pools)
           (fn [(lefts (List Float64))] -> ChatStep
             (sendError cx (listAppend l.head (list (headField "Retry-After" (stringFromInt64 (minLeftSec lefts))))) 503 (str "providers " (stringJoin pools ", ") " are in circuit-breaker cooldown after quota or timeout failures; retry in "
                                               (stringFromInt64 (truncInt (maxFloat lefts))) "s") true)))))
      (cx.profileRouted
       (sendError cx l.head 502 (str "profile " cx.profileName ": no model answered (" (labels l.models) ")" (lastErrSuffix l)) true))
      ((and (not (stringEmpty? model)) (not (or (= model "agy") (stringStartsWith? model "agy/"))))
       (sendError cx l.head 502 (str "ERR_NO_UPSTREAM: model " model " failed" (lastErrSuffix l)) true))
      (else
       (match (fallbackPrompt l.body)
         ((err e) (raise e))
         ((ok prompt)
          (agyFallback cx prompt
            (fn [(r (Option CliReply))] -> ChatStep
              (match r
                ((some reply) (agyReply cx l reply))
                ((none)
                 (match l.lastErr
                   ((some e) (sendError cx l.head 500 e false))
                   ((none) (done l.head ""))))))))))))


fn optJson v: (Option String) -> j/Json
  (match v ((some s) (j/jstr s)) ((none) (j/jnull)))

fn pairsJson hs: (List (Pair String String)) -> j/Json
  (j/jarr (map (fn [(p (Pair String String))] -> j/Json (j/jarr (list (j/jstr (pairFirst p)) (j/jstr (pairSecond p))))) hs))

fn effectJson eff: ChatEffect -> j/Json
  (let [(op (fn [(name String) (rest (List (Pair String j/Json)))] -> j/Json (j/jobj (cons (pair "op" (j/jstr name)) rest))))]
    (match eff
      ((effRealpath p) (op "realpath" (list (pair "path" (j/jstr p)))))
      ((effIsDir p) (op "isDir" (list (pair "path" (j/jstr p)))))
      ((effClock) (op "clock" (list)))
      ((effBreakerDown p) (op "breakerDown" (list (pair "pool" (j/jstr p)))))
      ((effBreakerDownAll ps) (op "breakerDownAll" (list (pair "pools" (j/jarr (map (fn [(p String)] -> j/Json (j/jstr p)) ps))))))
      ((effBreakerEvent e p park) (op "breaker" (listAppend (list (pair "event" (j/jstr e)) (pair "pool" (j/jstr p))) (if (> park 0) (list (pair "parkSec" (j/jint park))) (list)))))
      ((effUsageNote p a o u) (op "usageNote" (list (pair "provider" (j/jstr p)) (pair "alias" (j/jstr a)) (pair "outcome" (j/jstr o)) (pair "usage" u))))
      ((effLimit p a) (op "limit" (list (pair "provider" (j/jstr p)) (pair "alias" (j/jstr a)))))
      ((effUsageFallback p a) (op "usageFallback" (list (pair "provider" (j/jstr p)) (pair "alias" (j/jstr a)))))
      ((effSpreadOrder prof i spr cd pools)
       (op "spreadOrder" (list (pair "profile" (j/jstr prof)) (pair "intent" (j/jstr i))
                               (pair "spread" (j/jarr (map (fn [(m (Pair String Int64))] -> j/Json (j/jarr (list (j/jstr (pairFirst m)) (j/jint (pairSecond m))))) spr)))
                               (pair "cooldownSec" (j/jint cd))
                               (pair "pools" (j/jarr (map (fn [(p (Pair String String))] -> j/Json (j/jarr (list (j/jstr (pairFirst p)) (j/jstr (pairSecond p))))) pools))))))
      ((effSpreadNote429 alias) (op "spreadNote429" (list (pair "alias" (j/jstr alias)))))
      ((effAffinity s) (op "affinity" (list (pair "session" (j/jstr s)))))
      ((effAffinityNote s alias) (op "affinityNote" (list (pair "session" (j/jstr s)) (pair "alias" (j/jstr alias)))))
      ((effTelemetry r) (op "telemetry" (list (pair "rec" (optJson r)))))
      ((effNoteIntent i) (op "noteIntent" (list (pair "intent" (j/jstr i)))))
      ((effLog t) (op "log" (list (pair "text" (j/jstr t)))))
      ((effBucket m r t) (op "bucket" (list (pair "model" (j/jstr m)) (pair "rpm" (j/jfloat r)) (pair "timeout" (j/jfloat t)))))
      ((effSleepMs ms) (op "sleepMs" (list (pair "ms" (j/jint ms)))))
      ((effPoolHttp p m base pool req t)
       (op "poolHttp" (list (pair "provider" (j/jstr p)) (pair "model" (j/jstr m)) (pair "base" (j/jstr base))
                            (pair "windowMs" (j/jint pool.config.windowMs)) (pair "peakCount" (j/jint pool.config.peakCount))
                            (pair "bypassWhileBusy" (j/jbool pool.config.bypassWhileBusy))
                            (pair "requestTimeoutMs" (j/jint pool.config.requestTimeoutMs))
                            (pair "batch" (j/jbool pool.batch)) (pair "scaleDownPath" (j/jstr pool.scaleDownPath))
                            (pair "url" (j/jstr (if (stringEmpty? req.fragment) req.url (str req.url "#" req.fragment))))
                            (pair "method" (j/jstr req.method)) (pair "headers" (pairsJson req.headers))
                            (pair "data" (j/jstr req.data)) (pair "timeout" (j/jfloat t)))))
      ((effHttp _ _ _ _ req t _ _)
       (op "http" (list (pair "url" (j/jstr (if (stringEmpty? req.fragment) req.url (str req.url "#" req.fragment))))
                        (pair "method" (j/jstr req.method)) (pair "headers" (pairsJson req.headers))
                        (pair "data" (j/jstr req.data)) (pair "timeout" (j/jfloat t)))))
      ((effCli c args) (op "cli" (list (pair "client" (j/jstr c)) (pair "args" (j/jobj args)))))))

fn headJson head: (List HeadItem) -> j/Json
  (j/jarr (map (fn [(h HeadItem)] -> j/Json
                 (match h
                   ((headStatus c) (j/jarr (list (j/jstr ":status") (j/jstr (stringFromInt64 c)))))
                   ((headField n v) (j/jarr (list (j/jstr n) (j/jstr v))))))
               head))
