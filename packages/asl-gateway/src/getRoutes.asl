(module aslGateway/getRoutes
  :x [PoolRow CliRow BreakerRow SessionRow TargetRow ActionQueue HealthInputs GetState SearchRequest GetOutcome
      getRespond getCockpit getSearch getFail
      roleCascades cockpitPath? pyIntParse pathRstrip pathStrip requestPath
      profileHealthJson configHealthJson healthAsn healthJson modelsJson
      searchResponse gatewayGet gatewayGetRequest]
  :i [(config :a cfg)
      (usage :a us)
      (search :a se)
      (pyText :a pt)
      (wire :a w)
      (asl-json/json :a j)
      (asl-http/http11 :a h)])

(schema PoolRow
  (:f name String)
  (:f size Int64)
  (:f busy Int64)
  (:f queued Int64))

(schema CliRow
  (:f name String)
  (:f bin String)
  (:f version String))

(schema BreakerRow
  (:f name String)
  (:f down Bool)
  (:f secondsLeft Int64))

(schema SessionRow
  (:f id String)
  (:f status String)
  (:f url String))

(schema TargetRow
  (:f id String)
  (:f kind String)
  (:f family String)
  (:f authenticated Bool)
  (:f tabsCount Int64)
  (:f lastHeartbeat Int64))

(schema ActionQueue
  (:f id String)
  (:f items (List String)))

(schema HealthInputs
  (:f pools (List PoolRow))
  (:f clis (List CliRow))
  (:f breaker (List BreakerRow))
  (:f undeclared (List (Pair String Int64)))
  (:f update us/GatewayStatus)
  (:f usage j/Json)
  (:f profiles (Result cfg/GatewayTable String))
  (:f envProfile (Option String))
  (:f profilePath String)
  (:f profileExists Bool))

(schema GetState
  (:f projects (List (Pair String String)))
  (:f channels (List (Pair String String)))
  (:f sessions (List SessionRow))
  (:f targets (List TargetRow))
  (:f targetQueues (List ActionQueue))
  (:f extensionQueues (List ActionQueue))
  (:f health HealthInputs))

(schema SearchRequest
  (:f query String)
  (:f engine String)
  (:f limit Int64)
  (:f json Bool))

(enum GetOutcome
  (:c getRespond [(state GetState) (response h/HttpResponse)])
  (:c getCockpit [(path String)])
  (:c getSearch [(request SearchRequest)])
  (:c getFail [(error pt/PyErr)]))

fn roleCascades -> (List (Pair String (List String)))
  (list
    (pair "coder" (list "groq/qwen/qwen3.8-27b" "gemini-3.8-flash" "poolside/laguna-s-2.1:free" "cohere/north-mini-code:free" "poolside/laguna-xs-2.1:free" "google/gemma-4-31b-it:free" "google/gemma-4-26b-a4b-it:free" "qwen/qwen3.8-27b:free"))
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

fn cockpitPath? path: String -> Bool
  (listContains? (list "/cockpit" "/cockpit/" "/cockpit/api/observatory" "/cockpit/api/intel" "/cockpit/api/coupling"
                       "/cockpit/api/vitality" "/cockpit/api/stubs" "/cockpit/api/daemons" "/cockpit/api/tasks"
                       "/cockpit/api/mem" "/cockpit/api/memory")
                 path)

fn dropPrefix s: String prefix: String -> String
  (optionOr (stringSlice s (stringLength prefix) (stringLength s)) "")

fn pathRstrip s: String -> String
  (if (stringEndsWith? s "/")
    (pathRstrip (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))
    s)

fn pathStrip s: String -> String
  (if (stringStartsWith? s "/")
    (pathStrip (dropPrefix s "/"))
    (pathRstrip s))

fn digit? c: Int64 -> Bool
  (and (>= c 48) (<= c 57))

fn digitsLoop bs: Bytes n: Int64 i: Int64 acc: Int64 prevDigit: Bool -> (Option Int64)
  (if (>= i n)
    (if prevDigit (some acc) (none))
    (let [(c (bytesGet bs i))]
      (cond
        ((digit? c)
          (if (> acc (/ (- 9223372036854775807 (- c 48)) 10))
            (none)
            (digitsLoop bs n (+ i 1) (+ (* acc 10) (- c 48)) true)))
        ((and (= c 95) prevDigit) (digitsLoop bs n (+ i 1) acc false))
        (else (none)))))

fn pyIntParse s: String -> (Option Int64)
  (let [(t (pt/pyStrip s))
        (neg (stringStartsWith? t "-"))
        (digits (if (or neg (stringStartsWith? t "+")) (optionOr (stringSlice t 1 (stringLength t)) "") t))
        (bs (stringToBytes digits))]
    (mt (digitsLoop bs (bytesLength bs) 0 0 false)
      ((none) (none))
      ((some v) (some (if neg (- 0 v) v)))))

fn lookupPair xs: (List (Pair String String)) key: String -> (Option String)
  (mt (listHead xs)
    ((none) (none))
    ((some p) (if (= (pairFirst p) key) (some (pairSecond p)) (lookupPair (optionOr (listTail xs) (list)) key))))

fn qsGet qs: (List (Pair String String)) key: String -> (Option String)
  (lookupPair (listReverse qs) key)

fn qsGetOr qs: (List (Pair String String)) key: String alt: String dflt: String -> String
  (mt (qsGet qs key)
    ((some v) v)
    ((none) (optionOr (qsGet qs alt) dflt)))

fn queryOf target: String -> (Result String pt/PyErr)
  (mt (pt/urlparse target)
    ((err e) (err e))
    ((ok parts) (ok (optionOr (listGet parts 4) ""))))

fn asnHeaders -> h/HttpHeaders
  (h/makeHeaders (list (pair "Content-Type" "application/asn+sexpr") (pair "X-ASL-Wire-Protocol" "asn/1.0")))

fn jsonHeaders -> h/HttpHeaders
  (h/makeHeaders (list (pair "Content-Type" "application/json")))

fn ok200 headers: h/HttpHeaders body: String -> h/HttpResponse
  (h/makeResponse 200 "OK" headers body)

fn dumps v: j/Json -> String
  (pt/jsonDumps v -1)

fn boolText b: Bool -> String
  (if b "true" "false")

fn quoted s: String -> String
  (str "\"" (w/asnEscape s) "\"")

fn poolsJson pools: (List PoolRow) -> j/Json
  (j/jobj (map (fn [(p PoolRow)] -> (Pair String j/Json)
                 (pair p.name (j/jobj (list (pair "size" (j/jint p.size)) (pair "busy" (j/jint p.busy)) (pair "queued" (j/jint p.queued))))))
               pools))

fn strList xs: (List String) -> j/Json
  (j/jarr (map (fn [(s String)] -> j/Json (j/jstr s)) xs))

fn optStr o: (Option String) -> j/Json
  (mt o ((some s) (j/jstr s)) ((none) (j/jnull)))

fn routesJson routes: (List cfg/GatewayRoute) key: String -> j/Json
  (j/jarr (map (fn [(r cfg/GatewayRoute)] -> j/Json
                 (j/jobj (list (pair "intent" (j/jstr r.intent))
                               (pair key (strList (if (= key "chain") r.chain r.models))))))
               routes))

fn profileHealthJson info: cfg/ProfileHealth -> j/Json
  (mt info
    ((cfg/healthError e source) (j/jobj (list (pair "error" (j/jstr e)) (pair "source" (j/jstr source)))))
    ((cfg/healthV1 name routes source)
      (j/jobj (list (pair "name" (j/jstr name)) (pair "routes" (routesJson routes "models")) (pair "source" (j/jstr source)))))
    ((cfg/healthV2 name routes fallback source)
      (j/jobj (list (pair "name" (j/jstr name)) (pair "v" (j/jint 2)) (pair "routes" (routesJson routes "chain"))
                    (pair "fallback" (optStr fallback)) (pair "source" (j/jstr source))))))

fn asnUnescapeLoop cs: (List String) acc: (List String) -> (Result String String)
  (mt (listHead cs)
    ((none) (ok (stringJoin (listReverse acc) "")))
    ((some c)
      (let [(rest (optionOr (listTail cs) (list)))]
        (if (= c "\\")
          (mt (listHead rest)
            ((none) (err "dangling backslash"))
            ((some e)
              (let [(ch (cond ((= e "n") (some "\n")) ((= e "r") (some "\r")) ((= e "t") (some "\t"))
                              ((= e "\\") (some "\\")) ((= e "\"") (some "\"")) (else (none))))]
                (mt ch
                  ((none) (err (str "unknown escape \\" e)))
                  ((some x) (asnUnescapeLoop (optionOr (listTail rest) (list)) (cons x acc)))))))
          (asnUnescapeLoop rest (cons c acc))))))

fn paramJson text: String -> (Result j/Json String)
  (cond
    ((= text "true") (ok (j/jbool true)))
    ((= text "false") (ok (j/jbool false)))
    ((= text "nil") (ok (j/jnull)))
    ((and (stringStartsWith? text "\"") (and (stringEndsWith? text "\"") (>= (stringLength text) 2)))
      (mt (asnUnescapeLoop (stringChars (optionOr (stringSlice text 1 (- (stringLength text) 1)) "")) (list))
        ((err e) (err e))
        ((ok s) (ok (j/jstr s)))))
    ((or (stringContains? text ".") (or (stringContains? text "e") (stringContains? text "E")))
      (mt (stringToFloat64 text)
        ((some f) (ok (j/jfloat f)))
        ((none) (err (str "parameter value " text " is no number")))))
    (else
      (mt (stringToInt64 text)
        ((some n) (ok (j/jint n)))
        ((none) (err (str "parameter value " text " is no number"))))))

fn paramsJson shown: (List (Pair String String)) acc: (List (Pair String j/Json)) -> (Result j/Json String)
  (mt (listHead shown)
    ((none) (ok (j/jobj (listReverse acc))))
    ((some p)
      (mt (paramJson (pairSecond p))
        ((err e) (err (str (pairFirst p) ": " e)))
        ((ok v) (paramsJson (optionOr (listTail shown) (list)) (cons (pair (pairFirst p) v) acc))))))

fn modelsCfgJson models: (List cfg/GatewayModel) acc: (List (Pair String j/Json)) -> (Result j/Json String)
  (mt (listHead models)
    ((none) (ok (j/jobj (listReverse acc))))
    ((some m)
      (mt (paramsJson m.shown (list))
        ((err e) (err (str "model " m.id " " e)))
        ((ok params)
          (modelsCfgJson (optionOr (listTail models) (list))
                         (cons (pair m.id (j/jobj (list (pair "provider" (j/jstr m.provider)) (pair "name" (j/jstr m.name))
                                                             (pair "calibration" (optStr m.calibration)) (pair "params" params))))
                               acc))))))

fn configHealthJson c: cfg/ConfigHealth -> (Result j/Json String)
  (mt (modelsCfgJson c.models (list))
    ((err e) (err e))
    ((ok models)
      (ok (j/jobj (list (pair "v" (j/jint 2))
                        (pair "source" (j/jstr c.source))
                        (pair "uses" (j/jobj (map (fn [(u (Pair String String))] -> (Pair String j/Json) (pair (pairFirst u) (j/jstr (pairSecond u)))) c.uses)))
                        (pair "profiles" (j/jobj (map (fn [(p cfg/GatewayProfile)] -> (Pair String j/Json)
                                                        (pair p.id (j/jobj (list (pair "routes" (routesJson p.routes "chain")) (pair "fallback" (optStr p.fallback))))))
                                                      c.profiles)))
                        (pair "models" models)
                        (pair "registry" (j/jstr c.registry))
                        (pair "registryError" (optStr c.registryError))
                        (pair "warnings" (strList c.warnings)))))))

fn requestProfileHealth hi: HealthInputs headers: (List (Pair String String)) -> cfg/ProfileHealth
  (cfg/gatewayProfileHealth hi.profiles headers hi.envProfile hi.profilePath hi.profileExists)

fn healthAsn st: GetState headers: (List (Pair String String)) api: Bool -> (Result String String)
  (let [(hi st.health)
        (pools (stringJoin (map (fn [(p PoolRow)] -> String
                                  (str ":" p.name " (:size " (stringFromInt64 p.size) " :busy " (stringFromInt64 p.busy) " :queued " (stringFromInt64 p.queued) ")"))
                                hi.pools) " "))
        (clis (stringJoin (map (fn [(c CliRow)] -> String (str ":" c.name " (:bin " (quoted c.bin) " :version " (quoted c.version) ")")) hi.clis) " "))
        (undeclared (stringJoin (map (fn [(u (Pair String Int64))] -> String (str "(:intent " (quoted (pairFirst u)) " :count " (stringFromInt64 (pairSecond u)) ")")) hi.undeclared) " "))
        (profile (str (cfg/gatewayProfileAsn (requestProfileHealth hi headers)) (cfg/gatewayConfigAsn (cfg/gatewayConfigHealth hi.profiles))
                      " :undeclaredIntents (" undeclared ")"))
        (breaker (str " :breaker (" (stringJoin (map (fn [(b BreakerRow)] -> String (str ":" b.name " (:down " (boolText b.down) " :secondsLeft " (stringFromInt64 b.secondsLeft) ")")) hi.breaker) " ") ")"))
        (tail (str ":pools (" pools ") :wire (asn json) :clis (" clis ") :profile " profile " " breaker " "))]
    (mt (us/usageAsn hi.usage)
      ((err e) (err e))
      ((ok usageText)
        (let [(update (str (us/gatewayUpdateAsn hi.update) " :usage " usageText))]
          (ok (if api
                (str "(:gatewayStatus :status :ok :service \"asl-gateway\" :omniProtocol true :projects " (stringFromInt64 (listLength st.projects))
                     " :channels " (stringFromInt64 (listLength st.channels)) " " tail update ")\n")
                (str "(:health :status :ok :service \"asl-gateway\" " tail update ")\n")))))))

fn objKvs v: j/Json -> (List (Pair String j/Json))
  (mt v ((j/jobj kvs) kvs) (_ (list)))

fn healthJson st: GetState headers: (List (Pair String String)) api: Bool -> (Result j/Json String)
  (let [(hi st.health)
        (gatewayCfg (cfg/gatewayConfigHealth hi.profiles))
        (head (list (pair "status" (j/jstr "ok")) (pair "service" (j/jstr "asl-gateway")) (pair "cascades" (j/jbool true))
                    (pair "pools" (poolsJson hi.pools))
                    (pair "wire" (strList (list "asn" "json")))
                    (pair "clis" (j/jobj (map (fn [(c CliRow)] -> (Pair String j/Json) (pair c.name (j/jobj (list (pair "bin" (j/jstr c.bin)) (pair "version" (j/jstr c.version)))))) hi.clis)))
                    (pair "profile" (profileHealthJson (requestProfileHealth hi headers)))
                    (pair "undeclaredIntents" (j/jobj (map (fn [(u (Pair String Int64))] -> (Pair String j/Json) (pair (pairFirst u) (j/jint (pairSecond u)))) hi.undeclared)))
                    (pair "breaker" (j/jobj (map (fn [(b BreakerRow)] -> (Pair String j/Json)
                                                   (pair b.name (j/jobj (list (pair "down" (j/jbool b.down)) (pair "secondsLeft" (j/jint b.secondsLeft))))))
                                                 hi.breaker)))))
        (withUsage (listAppend (listAppend head (objKvs (us/gatewayStatusJson hi.update))) (list (pair "usage" hi.usage))))
        (api3 (if api
                (list (pair "omniProtocol" (j/jbool true)) (pair "projects" (j/jint (listLength st.projects))) (pair "channels" (j/jint (listLength st.channels))))
                (list)))]
    (mt gatewayCfg
      ((none) (ok (j/jobj (listAppend withUsage api3))))
      ((some c)
        (mt (configHealthJson c)
          ((err e) (err e))
          ((ok g) (ok (j/jobj (listAppend (listAppend withUsage (list (pair "gateway" g))) api3))))))))

fn modelsJson -> j/Json
  (j/jobj (list (pair "object" (j/jstr "list"))
                (pair "data" (j/jarr (fold (fn [(acc (List j/Json)) (rc (Pair String (List String)))] -> (List j/Json)
                                             (listAppend acc (map (fn [(m String)] -> j/Json
                                                                    (j/jobj (list (pair "id" (j/jstr m)) (pair "object" (j/jstr "model"))
                                                                                  (pair "owned_by" (j/jstr "openrouter")) (pair "role" (j/jstr (pairFirst rc))))))
                                                                  (pairSecond rc))))
                                           (list) (roleCascades))))))

fn fallbackJson st: GetState -> j/Json
  (j/jobj (list (pair "status" (j/jstr "ok")) (pair "service" (j/jstr "asl-gateway")) (pair "cascades" (j/jbool true))
                (pair "pools" (poolsJson st.health.pools))))

fn voiceText -> String
  (str "(:voiceStatusReceipt\n  :status :ok\n  :mode :pushToTalk\n  :aecEnabled true\n  :duckingDb -12.0\n"
       "  :bargeInPurgeMs 20\n  :activeStream false\n  :assertCount 1)\n")

fn browserStatusJson -> j/Json
  (j/jobj (list (pair "status" (j/jstr "ok")) (pair "active" (j/jbool true)) (pair "tabs_count" (j/jint 1))
                (pair "engine" (j/jstr "extension-primary"))
                (pair "modes" (strList (list "extension" "patchright" "staticHttp" "cloudProxy" "auto")))))

fn sessionsText sessions: (List SessionRow) -> String
  (str "(:browserSessions ["
       (stringJoin (map (fn [(s SessionRow)] -> String (str "(:session :id \"" s.id "\" :status :" s.status " :url \"" s.url "\")")) sessions) " ")
       "])\n")

fn targetsText targets: (List TargetRow) -> String
  (str "(:browserTargets ["
       (stringJoin (map (fn [(t TargetRow)] -> String
                          (str "(:browserTarget :id \"" t.id "\" :kind :" t.kind " :family \"" t.family "\" :authenticated " (boolText t.authenticated)
                               " :tabsCount " (stringFromInt64 t.tabsCount) " :lastHeartbeat " (stringFromInt64 t.lastHeartbeat) ")"))
                        targets) " ")
       "])\n")

fn popAction queues: (List ActionQueue) id: String -> (Pair (Option String) (List ActionQueue))
  (fold (fn [(acc (Pair (Option String) (List ActionQueue))) (q ActionQueue)] -> (Pair (Option String) (List ActionQueue))
          (if (and (= q.id id) (none? (pairFirst acc)))
            (mt (listHead q.items)
              ((none) (pair (none) (listAppend (pairSecond acc) (list q))))
              ((some item) (pair (some item) (listAppend (pairSecond acc) (list (ActionQueue :id id :items (optionOr (listTail q.items) (list))))))))
            (pair (pairFirst acc) (listAppend (pairSecond acc) (list q)))))
        (pair (none) (list)) queues)

fn pollText head: String idKey: String id: String item: (Option String) -> String
  (mt item
    ((some a) (str "(" head "\n  :status :action\n  " idKey " \"" id "\"\n  :hasAction true\n  :action " a ")\n"))
    ((none) (str "(" head "\n  :status :idle\n  " idKey " \"" id "\"\n  :hasAction false)\n")))

fn withTargetQueues st: GetState qs: (List ActionQueue) -> GetState
  (with st :targetQueues qs)

fn withExtensionQueues st: GetState qs: (List ActionQueue) -> GetState
  (with st :extensionQueues qs)

fn pollRoute target: String st: GetState isTarget: Bool -> GetOutcome
  (mt (queryOf target)
    ((err e) (getFail e))
    ((ok q)
      (let [(qs (pt/parseQsl q))
            (id (if isTarget (qsGetOr qs "targetId" "target_id" "target-default") (qsGetOr qs "agentId" "agent_id" "ext-default")))
            (popped (popAction (if isTarget st.targetQueues st.extensionQueues) id))
            (next (if isTarget (withTargetQueues st (pairSecond popped)) (withExtensionQueues st (pairSecond popped))))
            (body (if isTarget
                    (pollText ":targetPollResponse" ":targetId" id (pairFirst popped))
                    (pollText ":extensionPollResponse" ":agentId" id (pairFirst popped))))]
        (getRespond next (ok200 (asnHeaders) body)))))

fn acceptOf headers: (List (Pair String String)) -> String
  (optionOr (h/getHeaderFromHeaders (h/makeHeaders headers) "Accept") "")

fn healthRoute st: GetState headers: (List (Pair String String)) parsedPath: String -> GetOutcome
  (let [(accept (acceptOf headers))
        (api (stringStartsWith? parsedPath "/api/asl/"))
        (asn (or (stringContains? accept "application/asn+sexpr") (and api (not (stringContains? accept "application/json")))))]
    (if asn
      (mt (healthAsn st headers api)
        ((err e) (getFail (pt/pyErr "ValueError" e)))
        ((ok body) (getRespond st (ok200 (asnHeaders) body))))
      (mt (healthJson st headers api)
        ((err e) (getFail (pt/pyErr "ValueError" e)))
        ((ok data) (getRespond st (ok200 (jsonHeaders) (dumps data)))))))

fn searchRoute target: String headers: (List (Pair String String)) -> GetOutcome
  (mt (queryOf target)
    ((err e) (getFail e))
    ((ok q)
      (let [(qs (pt/parseQsl q))]
        (getSearch (SearchRequest :query (qsGetOr qs "q" "query" "")
                                  :engine (optionOr (qsGet qs "engine") "auto")
                                  :limit (optionOr (pyIntParse (optionOr (qsGet qs "limit") "5")) 5)
                                  :json (stringContains? (acceptOf headers) "application/json"))))))

fn searchResponse req: SearchRequest res: j/Json -> (Result h/HttpResponse pt/PyErr)
  (if req.json
    (ok (ok200 (h/makeHeaders (list (pair "Content-Type" "application/json") (pair "X-ASL-Wire-Protocol" "asn/1.0"))) (dumps res)))
    (mt (se/formatSearchAsn res req.query)
      ((err e) (err e))
      ((ok body) (ok (ok200 (asnHeaders) body)))))

fn parsedRoute target: String headers: (List (Pair String String)) st: GetState -> GetOutcome
  (mt (pt/urlparse target)
    ((err e) (getFail e))
    ((ok parts)
      (let [(parsedPath (pathRstrip (optionOr (listGet parts 2) "")))]
        (if (listContains? (list "/health" "/api/asl/status" "/api/asl/health") parsedPath)
          (healthRoute st headers parsedPath)
          (restRoute target headers st)))))

fn restRoute target: String headers: (List (Pair String String)) st: GetState -> GetOutcome
  (cond
    ((or (= target "/api/asl/voice/status") (= target "/api/asl/voice/mode"))
      (getRespond st (ok200 (asnHeaders) (voiceText))))
    ((or (= target "/api/asl/browser/status") (= target "/api/asl/browser/status/"))
      (getRespond st (ok200 (jsonHeaders) (dumps (browserStatusJson)))))
    ((or (= target "/api/asl/browser/session/list") (= target "/api/asl/browser/session/list/"))
      (getRespond st (ok200 (asnHeaders) (sessionsText st.sessions))))
    ((or (= target "/api/asl/browser/target/list") (= target "/api/asl/browser/target/list/"))
      (getRespond st (ok200 (asnHeaders) (targetsText st.targets))))
    ((stringStartsWith? target "/api/asl/browser/target/poll") (pollRoute target st true))
    ((stringStartsWith? target "/api/asl/browser/extension/poll") (pollRoute target st false))
    ((or (= target "/v1/models") (= target "/models"))
      (getRespond st (ok200 (jsonHeaders) (dumps (modelsJson)))))
    ((stringStartsWith? target "/api/asl/search") (searchRoute target headers))
    (else (getRespond st (ok200 (jsonHeaders) (dumps (fallbackJson st))))))

fn lstripSlash s: String -> String
  (if (stringStartsWith? s "/") (lstripSlash (dropPrefix s "/")) s)

fn requestPath raw: String -> String
  (if (stringStartsWith? raw "//") (str "/" (lstripSlash raw)) raw)

fn gatewayGet raw: String headers: (List (Pair String String)) st: GetState -> GetOutcome
  (let [(target (requestPath raw))]
    (cond
      ((cockpitPath? target) (getCockpit target))
      ((stringStartsWith? target "/api/asl/project/")
        (let [(id (pathStrip (dropPrefix target "/api/asl/project/")))]
          (getRespond st (ok200 (asnHeaders) (optionOr (lookupPair st.projects id) (str "(:projectSync :id \"" id "\" :status :notFound)"))))))
      ((or (= target "/api/asl/channels") (= target "/api/asl/channels/"))
        (getRespond st (ok200 (asnHeaders) (str "(:channels (" (stringJoin (map (fn [(c (Pair String String))] -> String (pairSecond c)) st.channels) " ") "))"))))
      (else (parsedRoute target headers st))))

fn gatewayGetRequest req: h/HttpRequest st: GetState -> GetOutcome
  (gatewayGet (if (stringEmpty? req.query) req.path (str req.path "?" req.query))
              req.headers.entries st)
