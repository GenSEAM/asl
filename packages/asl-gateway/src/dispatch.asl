(module aslGateway/dispatch
  :x [Slot Serverless Wiring RouteHint DecisionRow Plan planSend planReject planReserving planWait
      LifecycleSpec LifecycleFamily StartOutcome startOk startRefused SlotReady readyNow readyLater readyGone
      rowsFromTable pluginsFromRows emptyWiring wiringFromConfig parseWiring httpFamily builtinFamilies
      plan started settle carrySpend sendTimeout usageTokens decisionText retarget startSlot! waiting pollSlots! slotReady anyWarming?
      slotNamed priceFor servedModel callUsageTokens settledConsumed observeReply]
  :i [(aslGateway/router :a rt) (aslGateway/fleet :a fl) (aslGateway/budget :a bgt) (aslGateway/plugin :a p)
      (aslGateway/upstream :a u) (aslGateway/config :a c) (aslGateway/pyText :a pt)
      (aslGateway/poolDispatch :a pd) (aslGateway/balancer :a bl) (asl-parser/reader :a rd) (asl-json/json :a j) (aslGateway/usage :a g) (aslGateway/secrets :a sc)])

(schema Serverless
  (:f coldStartMs Int64)
  (:f startCost Int64)
  (:f unit String))

(schema Slot
  (:f id String)
  (:f provider String)
  (:f model String)
  (:f pricePerMillion Int64)
  (:f state fl/State)
  (:f serverless (Option Serverless))
  (:f polledMs Int64)
  (:f deadlineMs Int64))

(schema Wiring
  (:f rows (List u/UpstreamProvider))
  (:f plugins (List p/Plugin))
  (:f profile (Option rt/Profile))
  (:f slots (List Slot))
  (:f ledger (Option bgt/Ledger))
  (:f settings u/UpstreamSettings)
  ; (:m :ref GW-BALANCER-WIRE :do "some when the gateway form carries a balancer section: plan routes every request through bl/pick and settle charges its windows, none keeps the router and passthrough paths byte for byte")
  (:f pool (Option bl/Pool))
  ; (:m :ref GW-BALANCER-ALIAS :do "the pool alias the last settle charged, none after a non-pool settle; the server writes it as the usage row alias so the ledger names the picked model, not the chat alias")
  (:f settledAlias (Option String))
  ; (:m :ref GW-UNKNOWN-MODEL-FALLTHROUGH :do "with a gateway table: every model id and model :name (effort suffix dropped) it declares; none without a table, so a config-less gateway keeps dispatching raw upstream names")
  (:f known (Option (List String))))

(schema RouteHint
  (:f provider String)
  (:f model String)
  (:f intent String)
  (:f role String)
  (:f promptTokens Int64))

(schema DecisionRow
  (:f rule String)
  (:f candidates (List String))
  (:f refused (List String))
  (:f pick String)
  (:f admission String)
  (:f budget String)
  (:f model String)
  (:f why String))

(enum Plan
  (:c planSend [(slot String) (plugin String) (request u/UpstreamRequest) (row DecisionRow)])
  (:c planReject [(status Int64) (reason String) (row DecisionRow)])
  (:c planWait [(slot String) (plugin String) (request u/UpstreamRequest) (row DecisionRow) (cold Bool) (deadlineMs Int64)]))

(schema LifecycleSpec
  (:f lifecycle p/Lifecycle)
  (:f scale p/ScaleModel)
  (:f startCost Int64)
  (:f unit String))

(schema LifecycleFamily
  (:f name String)
  (:f make (fn [(Map String rd/SExpr) u/UpstreamProvider u/UpstreamSettings (Map String String)] -> (Result LifecycleSpec String))))

(enum StartOutcome
  (:c startOk [(wiring Wiring) (row String)])
  (:c startRefused [(status Int64) (reason String) (row String)]))

(enum SlotReady
  (:c readyNow [])
  (:c readyLater [])
  (:c readyGone [(reason String)]))


fn defaultRowNamed id: String -> (Option u/UpstreamProvider)
  (u/upstreamProviderNamed (listAppend (u/upstreamProviders) (list (u/upstreamFallback))) id)

fn configuredRow pv: c/GatewayProvider -> u/UpstreamProvider
  (let [(base pv.base)
        (keyEnv pv.keyEnv)
        (timeout (if (> pv.timeoutSec 0.0) pv.timeoutSec 45.0))
        (firstByte pv.firstByteSec)
]
    (u/UpstreamProvider :id pv.id :prefixes (list (str pv.id "/")) :names (list)
      :url (fn [(st u/UpstreamSettings) (env (Map String String))] -> String base)
      :key (fn [(st u/UpstreamSettings) (env (Map String String))] -> String (if (stringEmpty? keyEnv) "" (u/envGetOr env keyEnv "")))
      :timeoutSec (fn [(st u/UpstreamSettings)] -> Float64 timeout)
      :firstByteSec (fn [(st u/UpstreamSettings)] -> Float64 firstByte)))

fn rowsFromTable table: (Option c/GatewayTable) -> (List u/UpstreamProvider)
  (match table
    ((none) (u/upstreamProviders))
    ((some tbl)
      (let [(configured (fold (fn [(acc (List u/UpstreamProvider)) (pid String)] -> (List u/UpstreamProvider)
                                (match (mapGet tbl.providers pid)
                                  ((some pv) (if (and (or (= pv.kind "openai") (or (= pv.kind "anthropic") (or (= pv.kind "gemini") (= pv.kind "gateway")))) (none? (defaultRowNamed pid))) (listAppend acc (list (configuredRow pv))) acc))
                                  ((none) acc)))
                          (list) (mapKeys tbl.providers)))
]
        (listAppend configured (listAppend (u/upstreamProviders) (list (u/upstreamFallback)))))))

fn ! pluginsFromRows rows: (List u/UpstreamProvider) st: u/UpstreamSettings redirects: (Map String Int64) -> (Result (List p/Plugin) String)
  (fold (fn [(acc (Result (List p/Plugin) String)) (row u/UpstreamProvider)] -> (Result (List p/Plugin) String)
          (match acc
            ((err e) (err e))
            ((ok plugins)
              (if (stringStartsWith? (row.url st (mapEmpty)) "cli://")
                (ok plugins)
                (match (p/openaiCompat row st (p/followingRedirects (p/openaiCompatCapabilities 64 (p/alwaysOn) (p/perToken 0.0 0.0) (list)) (optionOr (mapGet redirects row.id) 0)) none)
                  ((ok plugin) (ok (listAppend plugins (list plugin))))
                  ((err e) (err e)))))))
    (ok (list)) rows)


fn scalarText props: (Map String rd/SExpr) key: String fallback: String -> String
  (match (mapGet props key) ((some e) (c/scalarToString (c/asnScalar e))) ((none) fallback))

fn scalarInt props: (Map String rd/SExpr) key: String fallback: Int64 -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (ok fallback))
    ((some e) (match (c/asnScalar e) ((c/scalarInt n) (if (>= n 0) (ok n) (err (str ":" key " must be nonnegative")))) (_ (err (str ":" key " must be an integer"))))))

fn admissionMode text: String -> (Result fl/AdmissionMode String)
  (cond
    ((= text "direct") (ok (fl/direct)))
    ((= text "concurrencyCap") (ok (fl/concurrencyCap)))
    ((= text "ourBatch") (ok (fl/ourBatch)))
    (else (err (str "endpoint :admission must be direct, concurrencyCap or ourBatch, got " text))))

fn warmState endpoint: fl/Endpoint -> fl/State
  (let [(cold (fl/emptyState endpoint))]
    (match (fl/transition cold (fl/demand))
      ((err _) cold)
      ((ok warming) (match (fl/transition warming (fl/warmed)) ((ok warm) warm) ((err _) cold)))))

fn fleetEndpoint provider: String model: String mode: fl/AdmissionMode maxConcurrency: Int64 -> fl/Endpoint
  (fl/Endpoint :provider provider :model model :gpuTier "" :region "" :engine "" :admissionMode mode
    :maxConcurrency maxConcurrency :idleStopMs 0 :warmupMs 0 :upgradeQueueThreshold 1000000 :upgradeHoldMs 0
    :downgradeQueueThreshold 0 :downgradeHoldMs 0 :rewarmHourlyPrice 0 :idleHourlyPrice 0 :expectedDemandMs 0 :nextGpuTier "")

fn parseSlot form: rd/SExpr -> (Result Slot String)
  (match (c/asnProps form (some ":endpoint"))
    ((err e) (err e))
    ((ok props)
      (let [(id (scalarText props "id" ""))
            (provider (scalarText props "provider" ""))
            (model (scalarText props "model" ""))]
        (cond
          ((or (stringEmpty? id) (or (stringEmpty? provider) (stringEmpty? model))) (err "endpoint needs :id, :provider and :model"))
          (else
            (match (admissionMode (scalarText props "admission" "direct"))
              ((err e) (err (str "endpoint " id ": " e)))
              ((ok mode)
                (match (scalarInt props "maxConcurrency" 8)
                  ((err e) (err (str "endpoint " id ": " e)))
                  ((ok cap)
                    (match (scalarInt props "pricePerMillion" 0)
                      ((err e) (err (str "endpoint " id ": " e)))
                      ((ok price)
                        (if (< cap 1) (err (str "endpoint " id ": :maxConcurrency must be at least 1"))
                          (ok (Slot :id id :provider provider :model model :pricePerMillion price
                                :state (warmState (fleetEndpoint provider model mode cap)) :serverless none :polledMs 0 :deadlineMs 0))))))))))))))

fn parseSlots items: (List rd/SExpr) -> (Result (List Slot) String)
  (fold (fn [(acc (Result (List Slot) String)) (form rd/SExpr)] -> (Result (List Slot) String)
          (match acc ((err e) (err e)) ((ok slots) (match (parseSlot form) ((ok s) (ok (listAppend slots (list s)))) ((err e) (err e))))))
    (ok (list)) items)

fn formItems expr: rd/SExpr -> (List rd/SExpr)
  (match expr ((rd/sexprVect items) items) ((rd/sexprList items) items) (_ (list)))

(schema WiringConfig
  (:f profile (Option rt/Profile))
  (:f slots (List Slot))
  (:f ledger (Option bgt/Ledger))
  (:f lifecycles (List rd/SExpr))
  (:f redirects (Map String Int64)))

fn providerRedirects items: (List rd/SExpr) -> (Result (Map String Int64) String)
  (fold (fn [(acc (Result (Map String Int64) String)) (form rd/SExpr)] -> (Result (Map String Int64) String)
          (match acc
            ((err e) (err e))
            ((ok m)
              (match (c/asnProps form (some ":provider"))
                ((err _) (ok m))
                ((ok props)
                  (match (scalarInt props "redirectAfterSec" 0)
                    ((err e) (err (str "provider " (scalarText props "id" "") ": " e)))
                    ((ok n) (if (> n 0) (ok (mapSet m (scalarText props "id" "") n)) (ok m)))))))))
    (ok (mapEmpty)) items)

fn parseWiring text: String -> (Result WiringConfig String)
  (let [(form (rd/parseSexpr text))]
    (match (c/asnProps form (some ":gateway"))
      ((err e) (err e))
      ((ok props)
        (match (match (mapGet props "router")
              ((none) (ok none))
              ((some expr) (match (rt/parseRules (rd/renderSexpr expr)) ((ok profile) (ok (some profile))) ((err e) (err (str ":router: " e))))))
          ((err e) (err e))
          ((ok profile)
            (match (match (mapGet props "endpoints") ((none) (ok (list))) ((some expr) (parseSlots (formItems expr))))
              ((err e) (err (str ":endpoints: " e)))
              ((ok slots)
                (match (match (mapGet props "budget")
                      ((none) (ok none))
                      ((some expr) (match (bgt/parseBudgetConfig expr 256) ((ok l) (ok (some l))) ((err e) (err (str ":budget: " e))))))
                  ((err e) (err e))
                  ((ok ledger)
                    (match (providerRedirects (match (mapGet props "providers") ((some expr) (formItems expr)) ((none) (list))))
                      ((err e) (err (str ":providers: " e)))
                      ((ok redirects)
                        (ok (WiringConfig :profile profile :slots slots :ledger ledger
                              :lifecycles (match (mapGet props "lifecycles") ((some expr) (formItems expr)) ((none) (list))) :redirects redirects)))))))))))))

fn ! emptyWiring st: u/UpstreamSettings -> Wiring
  (Wiring :rows (u/upstreamProviders) :plugins (resultOr (pluginsFromRows (u/upstreamProviders) st (mapEmpty)) (list))
    :profile none :slots (list) :ledger none :settings st :pool none :settledAlias none :known none)


fn endpointStateNamed name: String -> (Option p/EndpointState)
  (cond
    ((= name "cold") (some (p/cold)))
    ((= name "warming") (some (p/warming)))
    ((= name "warm") (some (p/warm)))
    ((= name "draining") (some (p/draining)))
    ((= name "down") (some (p/down)))
    (else none))

fn lifecycleStatus endpoint: String body: String -> (Result p/LifecycleStatus String)
  (match (j/jsonParse body)
    ((err e) (err (str "lifecycle reply is not JSON: " e)))
    ((ok v)
      (match (j/jsonGet v "state")
        ((none) (err "lifecycle reply has no state"))
        ((some field)
          (match field
            ((j/jstr name) (match (endpointStateNamed name)
                             ((some state) (ok (p/LifecycleStatus :endpoint endpoint :state state :detail body)))
                             ((none) (err (str "lifecycle reply names unknown state " name)))))
            (_ (err "lifecycle reply state is not a string")))))))

fn ! lifecycleCall! row: u/UpstreamProvider st: u/UpstreamSettings env: (Map String String) path: String request: p/LifecycleRequest timeoutSec: Float64 -> (Result p/LifecycleStatus String)
  (let [(body (j/jsonEmit (j/jobj (list (pair "endpoint" (j/jstr request.endpoint)) (pair "model" (j/jstr request.model))))))]
    (match (u/upstreamRequest (row.url st env) path (row.key st env) body (list (pair "Content-Type" "application/json")))
      ((err e) (err e))
      ((ok req)
        (match (u/callUpstream! req env timeoutSec (row.firstByteSec st))
          ((err f) (err (str "lifecycle " path ": " (pd/failureText f))))
          ((ok resp) (lifecycleStatus request.endpoint resp.body))))))

fn ! httpLifecycle! props: (Map String rd/SExpr) row: u/UpstreamProvider st: u/UpstreamSettings env: (Map String String) -> (Result LifecycleSpec String)
  (let [(start (scalarText props "start" ""))
        (status (scalarText props "status" ""))
        (stop (scalarText props "stop" ""))]
    (if (or (stringEmpty? start) (stringEmpty? status)) (err "http lifecycle needs :start and :status paths")
      (match (scalarInt props "coldStartMs" 30000)
        ((err e) (err e))
        ((ok cold)
          (match (scalarInt props "idleTimeoutSec" 0)
            ((err e) (err e))
            ((ok idle)
              (match (scalarInt props "startCost" 0)
                ((err e) (err e))
                ((ok cost)
                  (ok (LifecycleSpec
                        :lifecycle (p/Lifecycle
                                     :deploy (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (err "http lifecycle does not deploy"))
                                     :start (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (lifecycleCall! row st env start r 10.0))
                                     :stop (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String)
                                             (if (stringEmpty? stop) (err "http lifecycle has no :stop path") (lifecycleCall! row st env stop r 10.0)))
                                     :status (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (lifecycleCall! row st env status r 2.0)))
                        :scale (p/serverless idle cold) :startCost cost :unit (scalarText props "unit" "start")))))))))))

fn ! httpFamily -> LifecycleFamily
  (LifecycleFamily :name "http"
    :make (fn [(props (Map String rd/SExpr)) (row u/UpstreamProvider) (st u/UpstreamSettings) (env (Map String String))] -> (Result LifecycleSpec String)
            (httpLifecycle! props row st env)))

fn ! builtinFamilies -> (List LifecycleFamily)
  (list (httpFamily))

fn familyNamed families: (List LifecycleFamily) name: String -> (Option LifecycleFamily)
  (listHead (filter (fn [(f LifecycleFamily)] -> Bool (= f.name name)) families))

fn replacePlugin plugins: (List p/Plugin) plugin: p/Plugin -> (List p/Plugin)
  (map (fn [(x p/Plugin)] -> p/Plugin (if (= x.id plugin.id) plugin x)) plugins)

fn serverlessSlots slots: (List Slot) provider: String spec: LifecycleSpec -> (List Slot)
  (match spec.scale
    ((p/serverless _ cold)
      (map (fn [(s Slot)] -> Slot
             (if (!= s.provider provider) s
               (let [(e s.state.endpoint)]
                 (Slot :id s.id :provider s.provider :model s.model :pricePerMillion s.pricePerMillion
                   :state (fl/emptyState (fl/Endpoint :provider e.provider :model e.model :gpuTier e.gpuTier :region e.region :engine e.engine
                                           :admissionMode e.admissionMode :maxConcurrency e.maxConcurrency :idleStopMs e.idleStopMs :warmupMs cold
                                           :upgradeQueueThreshold e.upgradeQueueThreshold :upgradeHoldMs e.upgradeHoldMs
                                           :downgradeQueueThreshold e.downgradeQueueThreshold :downgradeHoldMs e.downgradeHoldMs
                                           :rewarmHourlyPrice e.rewarmHourlyPrice :idleHourlyPrice e.idleHourlyPrice
                                           :expectedDemandMs e.expectedDemandMs :nextGpuTier e.nextGpuTier))
                   :serverless (some (Serverless :coldStartMs cold :startCost spec.startCost :unit spec.unit)) :polledMs 0 :deadlineMs 0))))
        slots))
    (_ slots))

(schema Attached
  (:f plugins (List p/Plugin))
  (:f slots (List Slot)))

fn ! attachLifecycle! families: (List LifecycleFamily) rows: (List u/UpstreamProvider) st: u/UpstreamSettings env: (Map String String) acc: Attached form: rd/SExpr -> (Result Attached String)
  (match (c/asnProps form (some ":lifecycle"))
    ((err e) (err e))
    ((ok props)
      (let [(provider (scalarText props "provider" ""))
            (family (scalarText props "family" ""))]
        (match (familyNamed families family)
          ((none) (err (str "lifecycle for " provider ": unknown family " family)))
          ((some fam)
            (match (u/upstreamProviderNamed rows provider)
              ((none) (err (str "lifecycle names provider " provider " with no row")))
              ((some row)
                (match (p/pluginNamed acc.plugins provider)
                  ((none) (err (str "lifecycle names provider " provider " with no plugin")))
                  ((some plugin)
                    (match (fam.make props row st env)
                      ((err e) (err (str "lifecycle for " provider ": " e)))
                      ((ok spec)
                        (match (p/pluginWithLifecycle plugin spec.scale spec.lifecycle)
                          ((err e) (err e))
                          ((ok next) (ok (Attached :plugins (replacePlugin acc.plugins next) :slots (serverlessSlots acc.slots provider spec))))))))))))))))

; (:m :ref GW-BALANCER-WIRE :do "dispatch can send a balancer pick only over an HTTP row: a provider configured with another kind (cli, agy) stays out of the pool")
fn routableProvider? table: (Option c/GatewayTable) rows: (List u/UpstreamProvider) pid: String -> Bool
  (and (some? (u/upstreamProviderNamed rows pid))
       (match table
         ((none) true)
         ((some tbl) (match (mapGet tbl.providers pid) ((some pv) (listContains? (list "openai" "anthropic" "gemini" "gateway") pv.kind)) ((none) true)))))

fn ! wiringFromConfig table: (Option c/GatewayTable) text: String st: u/UpstreamSettings env: (Map String String) families: (List LifecycleFamily) -> (Result Wiring String)
  (match (missingSecret table env)
    ((some receipt) (err receipt))
    ((none) (wiringFromRows table text st env families)))

fn missingSecret table: (Option c/GatewayTable) env: (Map String String) -> (Option String)
  (match table
    ((none) none)
    ((some tbl)
      (optionMap (fn [(pv c/GatewayProvider)] -> String (sc/secretsMissingReceipt pv.secret))
        (listFind (fn [(pv c/GatewayProvider)] -> Bool (and (not (stringEmpty? pv.secret)) (not (mapHas? env pv.keyEnv)))) (mapValues tbl.providers)))))

fn ! wiringFromRows table: (Option c/GatewayTable) text: String st: u/UpstreamSettings env: (Map String String) families: (List LifecycleFamily) -> (Result Wiring String)
  (let [(rows (rowsFromTable table))]
    (match (if (stringEmpty? text) (ok (WiringConfig :profile none :slots (list) :ledger none :lifecycles (list) :redirects (mapEmpty))) (parseWiring text))
      ((err e) (err e))
      ((ok cfg)
        (match (pluginsFromRows rows st cfg.redirects)
          ((err e) (err e))
          ((ok plugins)
            (match (fold (fn [(acc (Result Attached String)) (form rd/SExpr)] -> (Result Attached String)
                        (match acc ((err e) (err e)) ((ok a) (attachLifecycle! families rows st env a form))))
                  (ok (Attached :plugins plugins :slots cfg.slots)) cfg.lifecycles)
              ((err e) (err (str ":lifecycles: " e)))
              ((ok a)
                (match (bl/loadPool! text table (optionOr (mapGet env "HOME") "") (fn [(pid String)] -> Bool (routableProvider? table rows pid)))
                  ((err e) (err (str ":balancer: " e)))
                  ((ok pool) (ok (Wiring :rows rows :plugins a.plugins :profile cfg.profile :slots a.slots :ledger cfg.ledger :settings st :pool pool :settledAlias none :known (knownModels table))))))))))))

fn knownModels table: (Option c/GatewayTable) -> (Option (List String))
  (match table
    ((none) none)
    ((some tbl) (some (fold (fn [(acc (List String)) (m c/GatewayModel)] -> (List String) (listAppend acc (list m.id (bl/modelKey m.name)))) (list) (mapValues tbl.models)))))

fn rowClaims? rows: (List u/UpstreamProvider) model: String -> Bool
  (listAny? (fn [(r u/UpstreamProvider)] -> Bool
              (or (listAny? (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (stringStartsWith? model p))) r.prefixes) (listContains? r.names model)))
            rows)

; (:m :ref GW-UNKNOWN-MODEL-FALLTHROUGH :do "a hint naming a model the table does not declare and no provider row claims by prefix or name would fall through to the fallback upstream with whatever key it has; it is refused locally instead")
fn unknownModel? w: Wiring hint: RouteHint -> Bool
  (match w.known
    ((none) false)
    ((some ks) (and (not (stringEmpty? hint.model))
                    (not (listContains? ks hint.model))
                    (not (listContains? ks (bl/modelKey hint.model)))
                    (not (rowClaims? w.rows hint.model)))))

fn unknownModelText hint: RouteHint -> String
  (str "(:err :code ERR_UNKNOWN_MODEL :status 400 :model \"" (stringReplace hint.model "\"" "'") "\" :why \"no gateway model id or :name declares it and no provider claims it, so it is not sent upstream\")")


fn slotNamed slots: (List Slot) id: String -> (Option Slot)
  (listHead (filter (fn [(s Slot)] -> Bool (= s.id id)) slots))

fn routerRequest hint: RouteHint -> rt/Request
  (rt/Request :intent (if (stringEmpty? hint.intent) "any" hint.intent) :role hint.role
    :promptTokens hint.promptTokens :tools false :json false :streaming false
    :latency "interactive" :budget "standard" :expectedTokens (* 2 hint.promptTokens))

fn endpointState s: Slot -> rt/EndpointState
  (let [(st s.state)]
    (rt/EndpointState :endpoint s.id :queue (+ st.inFlight st.queueLength)
      :throughput (max 1 (fl/stateThroughputTps st))
      :cold (match st.lifecycle ((fl/cold) true) (_ false))
      :down (match st.lifecycle ((fl/down) true) ((fl/draining) true) (_ false))
      :pricePerMillion s.pricePerMillion))

fn passthroughSlot hint: RouteHint -> Slot
  (Slot :id hint.provider :provider hint.provider :model hint.model :pricePerMillion 0
    :state (warmState (fleetEndpoint hint.provider hint.model (fl/direct) 1000000)) :serverless none :polledMs 0 :deadlineMs 0)

fn routeCandidates w: Wiring hint: RouteHint -> (Pair String (List Slot))
  (match w.profile
    ((none) (pair "passthrough" (list (passthroughSlot hint))))
    ((some profile)
      (match (rt/route profile (routerRequest hint) (map endpointState w.slots) (list))
        ((err _) (pair "passthrough" (list (passthroughSlot hint))))
        ((ok decision)
          (pair decision.ruleId
            (fold (fn [(acc (List Slot)) (d rt/Decision)] -> (List Slot)
                    (match (slotNamed w.slots d.endpoint)
                      ((some s) (listAppend acc (list (Slot :id s.id :provider s.provider :model d.model :pricePerMillion s.pricePerMillion :state s.state
                                                       :serverless s.serverless :polledMs s.polledMs :deadlineMs s.deadlineMs))))
                      ((none) acc)))
              (list) decision.candidates))))))

fn expectedCost s: Slot hint: RouteHint -> Int64
  (/ (* s.pricePerMillion (* 2 (max 1 hint.promptTokens))) 1000000)

fn admissionText a: fl/Admission -> String
  (match a ((fl/admitNow) "admitNow") ((fl/queue) "queue") ((fl/reject r) (match r ((fl/endpointUnavailable) "rejectUnavailable") ((fl/atCapacity) "rejectAtCapacity"))))

fn without slots: (List Slot) id: String -> (List Slot)
  (filter (fn [(s Slot)] -> Bool (!= s.id id)) slots)

fn requestDecision w: Wiring s: Slot hint: RouteHint nowMs: Int64 -> bgt/Decision
  (match w.ledger
    ((none) (bgt/allow))
    ((some l) (bgt/gate l (bgt/actionRequest s.id s.provider "request" (expectedCost s hint)) nowMs)))

fn startable? s: Slot -> Bool
  (and (some? s.serverless) (match s.state.lifecycle ((fl/cold) true) ((fl/warming) true) (_ false)))

fn coldStartMs s: Slot -> Int64
  (match s.serverless ((some sv) sv.coldStartMs) ((none) 0))

fn pickLoop w: Wiring hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 rule: String names: (List String) left: (List Slot) refused: (List String) budgetDenied: Bool held: (Option Slot) -> Plan
  (let [(row (fn [(pick String) (model String) (a String) (b String)] -> DecisionRow
               (DecisionRow :rule rule :candidates names :refused refused :pick pick :admission a :budget b :model model :why "")))]
    (if (listEmpty? left)
      (match held
        ((some s)
          (match (requestDecision w s hint nowMs)
            ((bgt/deny _) (planReject 429 (str "no endpoint admitted: " (stringJoin (listAppend refused (list (str s.id ":budget"))) " ")) (row "" hint.model "none" "deny")))
            ((bgt/allow)
              (match (retarget w s hint request env)
                ((err e) (planReject 502 e (row s.id s.model "wait" "allow")))
                ((ok sent) (planWait s.id s.provider sent (row s.id s.model "wait" "allow")
                             (match s.state.lifecycle ((fl/cold) true) (_ false)) (+ nowMs (coldStartMs s))))))))
        ((none) (planReject (if budgetDenied 429 503) (str "no endpoint admitted: " (stringJoin refused " ")) (row "" hint.model "none" (if budgetDenied "deny" "unchecked")))))
      (let [(index (resultOr (fl/spillover (map (fn [(s Slot)] -> fl/State s.state) left)) 0))
            (chosen (optionOr (listGet left index) (optionOr (listHead left) (passthroughSlot hint))))
            (admission (fl/admit chosen.state nowMs))
            (rest (without left chosen.id))]
        (match admission
          ((fl/admitNow)
            (match (requestDecision w chosen hint nowMs)
              ((bgt/deny _) (pickLoop w hint request env nowMs rule names rest (listAppend refused (list (str chosen.id ":budget"))) true held))
              ((bgt/allow)
                (match (retarget w chosen hint request env)
                  ((err e) (planReject 502 e (row chosen.id chosen.model "admitNow" "allow")))
                  ((ok sent) (planSend chosen.id chosen.provider sent (row chosen.id chosen.model "admitNow" "allow")))))))
          (_ (if (and (startable? chosen) (none? held))
               (pickLoop w hint request env nowMs rule names rest refused budgetDenied (some chosen))
               (pickLoop w hint request env nowMs rule names rest (listAppend refused (list (str chosen.id ":" (admissionText admission)))) budgetDenied held)))))))

; (:m :ref GW-BALANCER-WIRE :do "the balancer replaces router and passthrough choice: the pick is retargeted to its provider row and upstream model name, a refusal is a 429 whose reason is one ASN form naming the budgets at their hard cap, and the receipt row carries the score parts")
fn estimateTokens hint: RouteHint -> Int64
  (* 2 (max 1 hint.promptTokens))

; (:m :ref GW-MODEL-SUBSTITUTION :do "a request whose provider and model already name pool aliases is honoured: the balancer picks among those only, and chooses freely only when the hint names no pool model or every asked alias is refused, then the receipt names the substitution as (:substituted :asked :served :reason)")
fn balancerPlan w: Wiring pool: bl/Pool hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 -> Plan
  (let [(req (bl/poolRequest pool hint.intent nowMs (estimateTokens hint)))
        (askedIds (bl/poolAliasesFor pool hint.provider hint.model))
        (honoured (if (listEmpty? askedIds) none (some (bl/poolHonour pool req askedIds))))
        (picked (match honoured ((some (bl/picked id score q explore)) (bl/picked id score q explore)) (_ (bl/poolPick pool req))))
        (substitution (match (pair honoured picked)
                        ((pair (some (bl/refused reason)) (bl/picked id _ _ _))
                          (str " (:substituted :asked \"" hint.provider "/" hint.model "\" :served " id " :reason \"" reason "\")"))
                        (_ "")))
        (names (map (fn [(m bl/PoolModel)] -> String m.id) pool.bal.models))
        (why (str (bl/pickWhy pool req picked) (match honoured ((some (bl/picked _ _ _ _)) " (:honoured true)") ((some (bl/refused reason)) (if (stringEmpty? substitution) (str " (:asked \"" hint.provider "/" hint.model "\" :refused \"" reason "\")") substitution)) ((none) (match picked ((bl/picked id _ _ _) (if (stringEmpty? hint.model) "" (str " (:asked \"" hint.provider "/" hint.model "\" :inPool false :served " id ")"))) (_ ""))))))
        (row (fn [(pick String) (model String) (a String) (b String)] -> DecisionRow
               (DecisionRow :rule "balancer" :candidates names :refused (list) :pick pick :admission a :budget b :model model :why why)))]
    (match picked
      ((bl/refused reason) (planReject 429 (bl/refusalText pool req reason) (row "" hint.model "none" "deny")))
      ((bl/picked id _ _ _)
        (match (bl/poolTarget pool id)
          ((none) (planReject 502 (str "balancer pick " id " has no provider row") (row id "" "none" "allow")))
          ((some target)
            (let [(s (Slot :id id :provider (pairFirst target) :model (pairSecond target) :pricePerMillion 0
                       :state (warmState (fleetEndpoint (pairFirst target) (pairSecond target) (fl/direct) 1000000)) :serverless none :polledMs 0 :deadlineMs 0))]
              (match (retarget w s hint request env)
                ((err e) (planReject 502 e (row id s.model "balancer" "allow")))
                ((ok sent) (planSend id s.provider sent (row id s.model "balancer" "allow"))))))))))

fn ! plan w: Wiring hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 -> Plan
  (if (unknownModel? w hint)
    (planReject 400 (unknownModelText hint) (DecisionRow :rule "unknownModel" :candidates (list) :refused (list hint.model) :pick "" :admission "none" :budget "unchecked" :model hint.model :why ""))
  (match w.pool
    ((some pool) (balancerPlan w pool hint request env nowMs))
    ((none)
      (let [(routed (routeCandidates w hint))
            (names (map (fn [(s Slot)] -> String s.id) (pairSecond routed)))]
        (pickLoop w hint request env nowMs (pairFirst routed) names (pairSecond routed) (list) false none)))))

; (:m :ref AUDIT11-A3 :do "plan plus the wiring to keep: a balancer send holds its estimated charge in the pool from plan time, so concurrent requests planned before any settle cannot overrun a hard budget; settle releases the hold and charges the actual")
fn ! planReserving w: Wiring hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 -> (Pair Plan Wiring)
  (let [(planned (plan w hint request env nowMs))]
    (match w.pool
      ((none) (pair planned w))
      ((some pool)
        (match planned
          ((planSend slot _ _ _) (pair planned (with w :pool (some (bl/poolReserve pool slot nowMs (estimateTokens hint))))))
          (_ (pair planned w))))))

fn sendTimeout w: Wiring hint: RouteHint provider: String timeoutSec: Float64 -> Float64
  (if (= provider hint.provider) timeoutSec
    (match (u/upstreamProviderNamed w.rows provider)
      ((some row) (row.timeoutSec w.settings))
      ((none) timeoutSec)))

fn retarget w: Wiring s: Slot hint: RouteHint request: u/UpstreamRequest env: (Map String String) -> (Result u/UpstreamRequest String)
  (if (and (= s.provider hint.provider) (= s.model hint.model))
    (ok request)
    (match (u/upstreamProviderNamed w.rows s.provider)
      ((none) (err (str "endpoint " s.id ": no provider row " s.provider)))
      ((some row)
        (match (j/jsonParse request.data)
          ((err e) (err (str "request body is not JSON: " e)))
          ((ok body)
            (u/upstreamRequest (row.url w.settings env) "/chat/completions" (row.key w.settings env)
              (j/jsonEmit (pt/jset body "model" (j/jstr s.model))) request.headers))))))


fn withState s: Slot st: fl/State polledMs: Int64 -> Slot
  (with s :state st :polledMs polledMs)

fn withDeadline s: Slot deadlineMs: Int64 -> Slot
  (with s :deadlineMs deadlineMs)

fn replaceSlot slots: (List Slot) s: Slot -> (List Slot)
  (map (fn [(x Slot)] -> Slot (if (= x.id s.id) s x)) slots)

fn withSlots w: Wiring slots: (List Slot) ledger: (Option bgt/Ledger) -> Wiring
  (with w :slots slots :ledger ledger)

fn started w: Wiring slotId: String -> Wiring
  (match (slotNamed w.slots slotId)
    ((none) w)
    ((some s) (match (fl/transition s.state (fl/requestStart))
      ((ok st) (withSlots w (replaceSlot w.slots (withState s st s.polledMs)) w.ledger))
      ((err _) w))))


fn lifecycleRequest s: Slot -> p/LifecycleRequest
  (let [(sv s.serverless)]
    (p/LifecycleRequest :endpoint s.id :model s.model :gpu s.state.endpoint.gpuTier :region s.state.endpoint.region
      :version "" :unit (match sv ((some x) x.unit) ((none) "start")) :expectedCost (match sv ((some x) x.startCost) ((none) 0))))

fn lifecycleRow op: String slotId: String detail: String -> String
  (str "(:gateway :lifecycle :op " op " :endpoint \"" slotId "\" " detail ")")

fn stateName state: p/EndpointState -> String
  (match state ((p/cold) "cold") ((p/warming) "warming") ((p/warm) "warm") ((p/draining) "draining") ((p/down) "down"))

fn transitioned s: Slot event: fl/Event polledMs: Int64 -> Slot
  (match (fl/transition s.state event) ((ok st) (withState s st polledMs)) ((err _) (withState s s.state polledMs)))

fn chargeStart w: Wiring s: Slot req: p/LifecycleRequest nowMs: Int64 -> (Pair (Option bgt/Ledger) String)
  (match w.ledger
    ((none) (pair none "noLedger"))
    ((some l) (match (bgt/charge l (bgt/Charge :endpoint s.id :provider s.provider :unit req.unit :atMs nowMs :cost req.expectedCost))
      ((ok next) (pair (some next) "charged"))
      ((err _) (pair (some l) "overCap")))))

fn ! startSlot! w: Wiring slotId: String nowMs: Int64 deadlineMs: Int64 -> StartOutcome
  (match (slotNamed w.slots slotId)
    ((none) (startRefused 503 (str "endpoint " slotId " is not configured") (lifecycleRow "start" slotId ":result failed :reason \"not configured\"")))
    ((some s)
      (match (p/pluginNamed w.plugins s.provider)
        ((none) (startRefused 503 (str "no plugin for provider " s.provider) (lifecycleRow "start" slotId ":result failed :reason \"no plugin\"")))
        ((some plugin)
          (let [(req (lifecycleRequest s))]
            (match (p/pluginStart! plugin w.ledger req nowMs)
              ((err f)
                (let [(reason (p/failureText f))
                      (denied (match f ((p/spendGate _) true) (_ false)))]
                  (startRefused (if denied 429 502) reason
                    (lifecycleRow "start" slotId (str ":result " (if denied "denied" "failed") " :reason \"" reason "\"")))))
              ((ok status)
                (let [(warming (withDeadline (transitioned s (fl/demand) nowMs) deadlineMs))
                      (ready (match status.state ((p/warm) (transitioned warming (fl/warmed) nowMs)) (_ warming)))
                      (charged (chargeStart w s req nowMs))]
                  (startOk (withSlots w (replaceSlot w.slots ready) (pairFirst charged))
                    (lifecycleRow "start" slotId (str ":result started :state " (stateName status.state) " :cost " (stringFromInt64 req.expectedCost) " :charge " (pairSecond charged))))))))))))

fn waiting w: Wiring slotId: String -> Wiring
  (match (slotNamed w.slots slotId)
    ((none) w)
    ((some s) (withSlots w (replaceSlot w.slots (transitioned s (fl/demand) s.polledMs)) w.ledger)))

fn warming? s: Slot -> Bool
  (and (some? s.serverless) (match s.state.lifecycle ((fl/warming) true) (_ false)))

fn anyWarming? w: Wiring -> Bool
  (listAny? warming? w.slots)

fn ! pollSlot! w: Wiring s: Slot nowMs: Int64 -> (Pair Slot (List String))
  (if (not (warming? s)) (pair s (list))
  (if (> nowMs s.deadlineMs)
    (pair (withState s (fl/emptyState s.state.endpoint) nowMs) (list (lifecycleRow "status" s.id ":state cold :reason \"coldStartMs exceeded\"")))
  (if (< (- nowMs s.polledMs) 100) (pair s (list))
    (match (p/pluginNamed w.plugins s.provider)
      ((none) (pair (transitioned s (fl/failed) nowMs) (list (lifecycleRow "status" s.id ":state down :reason \"no plugin\""))))
      ((some plugin)
        (match (p/pluginStatus! plugin (lifecycleRequest s))
          ((err f) (pair (withState s s.state nowMs) (list (lifecycleRow "status" s.id (str ":error \"" (p/failureText f) "\"")))))
          ((ok status)
            (match status.state
              ((p/warm) (pair (transitioned s (fl/warmed) nowMs) (list (lifecycleRow "status" s.id ":state warm"))))
              ((p/down) (pair (transitioned s (fl/failed) nowMs) (list (lifecycleRow "status" s.id ":state down"))))
              (_ (pair (withState s s.state nowMs) (list)))))))))))

fn ! pollSlots! w: Wiring nowMs: Int64 -> (Pair Wiring (List String))
  (if (not (anyWarming? w)) (pair w (list))
    (let [(polled (fold (fn [(acc (Pair (List Slot) (List String))) (s Slot)] -> (Pair (List Slot) (List String))
                          (let [(one (pollSlot! w s nowMs))]
                            (pair (listAppend (pairFirst acc) (list (pairFirst one))) (listAppend (pairSecond acc) (pairSecond one)))))
                    (pair (list) (list)) w.slots))]
      (pair (withSlots w (pairFirst polled) w.ledger) (pairSecond polled))))

fn slotReady w: Wiring slotId: String nowMs: Int64 -> SlotReady
  (match (slotNamed w.slots slotId)
    ((none) (readyGone (str "endpoint " slotId " is no longer configured")))
    ((some s)
      (match (fl/admit s.state nowMs)
        ((fl/admitNow) (readyNow))
        ((fl/queue) (readyLater))
        ((fl/reject r) (match r ((fl/atCapacity) (readyLater)) ((fl/endpointUnavailable) (readyGone (str "endpoint " slotId " failed to start"))))))))

fn carrySpend old: Wiring next: Wiring -> Wiring
  (match old.ledger
    ((none) next)
    ((some spent)
      (match next.ledger
        ((none) next)
        ((some l)
          (let [(kept (filter (fn [(b bgt/Bucket)] -> Bool (listAny? (fn [(line bgt/BudgetLine)] -> Bool (= line.id b.lineId)) l.lines)) spent.buckets))]
            (withSlots next next.slots
              (some (bgt/Ledger :lines l.lines :approvals l.approvals :buckets kept :maxBuckets l.maxBuckets))))))))

fn usageTokens body: String -> Int64
  (match (j/jsonParse body)
    ((err _) 0)
    ((ok v) (match (j/jsonGet v "usage")
      ((none) 0)
      ((some usage) (match (j/jsonGet usage "total_tokens") ((some t) (match t ((j/jint n) n) (_ 0))) ((none) 0))))))

fn priceFor w: Wiring slotId: String -> Int64
  (match (slotNamed w.slots slotId) ((some s) s.pricePerMillion) ((none) 0))

fn servedModel body: String fallback: String -> String
  (match (j/jsonParse body)
    ((err _) fallback)
    ((ok v) (match (j/jsonGet v "model")
      ((none) fallback)
      ((some m) (match m ((j/jstr s) (if (stringEmpty? s) fallback s)) (_ fallback))))))

; (:m :ref CALL-USAGE-TOKENS-ARITY :do "always four values (in cached out reasoning), the shape usage.asl#usageTokens returns; a body with no usage or no JSON is four zeros, not three")
fn callUsageTokens body: String -> (List Int64)
  (match (j/jsonParse body)
    ((err _) (list 0 0 0 0))
    ((ok v) (match (j/jsonGet v "usage")
      ((none) (list 0 0 0 0))
      ((some usage) (g/usageTokens usage)))))

; (:m :ref GW-BALANCER-WIRE :do "a balancer pick is charged to its windows whether or not the upstream call succeeded: a provider counts the request either way, so charging only greens would overrun a daily request quota, and a failed pick sits out its cooldown so the chat cascade retry reaches another model (GW-BALANCER-CASCADE)")
fn settle w: Wiring slotId: String provider: String tokens: Int64 latencyMs: Int64 success: Bool nowMs: Int64 -> (Pair Wiring String)
  (let [(slot (slotNamed w.slots slotId))
        (price (match slot ((some s) s.pricePerMillion) ((none) 0)))
        (cost (/ (* (max 0 tokens) price) 1000000))
        (slots (match slot
                 ((none) w.slots)
                 ((some s) (match (fl/transition s.state (fl/requestEnd (max 0 tokens) (max 1 latencyMs) success))
                   ((ok st) (replaceSlot w.slots (withState s st s.polledMs)))
                   ((err _) w.slots)))))
        (charged (match w.ledger
                   ((none) (pair none "noLedger"))
                   ((some l) (match (bgt/charge l (bgt/Charge :endpoint slotId :provider provider :unit "request" :atMs nowMs :cost cost))
                     ((ok next) (pair (some next) "charged"))
                     ((err _) (pair (some l) "overCap"))))))]
    (pair (with (withSlots w slots (pairFirst charged))
            :pool (match w.pool ((some pool) (some (let [(charged (bl/poolCharge (bl/poolRelease pool slotId) slotId nowMs tokens))] (if success charged (bl/poolFailed charged slotId nowMs))))) ((none) none))
            :settledAlias (match w.pool ((some pool) (if (some? (bl/poolTarget pool slotId)) (some slotId) none)) ((none) none)))
      (str "(:gateway :charge :endpoint \"" slotId "\" :tokens " (stringFromInt64 tokens) " :cost " (stringFromInt64 cost) " :status " (pairSecond charged)
           (match w.pool ((some pool) (if (some? (bl/poolTarget pool slotId)) " :balancer charged" "")) ((none) "")) ")")))

; (:m :ref GW-BALANCER-LIVE-QUOTA :do "feeds an upstream reply status and its rate-limit headers to the pool when the slot is a pool alias, a no-op otherwise")
fn observeReply w: Wiring slotId: String status: Int64 headers: (List (Pair String String)) nowMs: Int64 -> Wiring
  (match w.pool
    ((some pool) (with w :pool (some (bl/poolObserve pool slotId status headers nowMs))))
    ((none) w))

fn settledConsumed w: Wiring -> Wiring
  (with w :settledAlias none)

fn quoted xs: (List String) -> String
  (stringJoin (map (fn [(x String)] -> String (str "\"" x "\"")) xs) " ")

fn decisionText row: DecisionRow -> String
  (str "(:gateway :route :rule \"" row.rule "\" :candidates (" (quoted row.candidates) ") :pick \"" row.pick
       "\" :refused (" (quoted row.refused) ") :model \"" row.model "\" :admission " row.admission " :budget " row.budget
       (if (stringEmpty? row.why) "" (str " :why " row.why)) ")")
