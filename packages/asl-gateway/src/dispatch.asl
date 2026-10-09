(module aslGateway/dispatch
  :x [Slot Serverless Wiring RouteHint DecisionRow Plan planSend planReject planWait
      LifecycleSpec LifecycleFamily StartOutcome startOk startRefused SlotReady readyNow readyLater readyGone
      rowsFromTable pluginsFromRows emptyWiring wiringFromConfig parseWiring httpFamily builtinFamilies
      plan started settle carrySpend sendTimeout usageTokens decisionText retarget startSlot! waiting pollSlots! slotReady anyWarming?]
  :i [(aslGateway/router :a rt) (aslGateway/fleet :a fl) (aslGateway/budget :a bgt) (aslGateway/plugin :a p)
      (aslGateway/upstream :a u) (aslGateway/config :a c) (aslGateway/pyText :a pt)
      (aslGateway/poolDispatch :a pd) (asl-parser/reader :a rd) (asl-json/json :a j)])

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
  (:f settings u/UpstreamSettings))

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
  (:f model String))

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
]
    (u/UpstreamProvider :id pv.id :prefixes (list (str pv.id "/")) :names (list)
      :url (fn [(st u/UpstreamSettings) (env (Map String String))] -> String base)
      :key (fn [(st u/UpstreamSettings) (env (Map String String))] -> String (if (stringEmpty? keyEnv) "" (u/envGetOr env keyEnv "")))
      :timeoutSec (fn [(st u/UpstreamSettings)] -> Float64 timeout)))

fn rowsFromTable table: (Option c/GatewayTable) -> (List u/UpstreamProvider)
  (mt table
    ((none) (u/upstreamProviders))
    ((some tbl)
      (let [(configured (fold (fn [(acc (List u/UpstreamProvider)) (pid String)] -> (List u/UpstreamProvider)
                                (mt (mapGet tbl.providers pid)
                                  ((some pv) (if (and (= pv.kind "openai") (none? (defaultRowNamed pid))) (listAppend acc (list (configuredRow pv))) acc))
                                  ((none) acc)))
                          (list) (mapKeys tbl.providers)))
]
        (listAppend configured (u/upstreamProviders)))))

fn ! pluginsFromRows rows: (List u/UpstreamProvider) st: u/UpstreamSettings redirects: (Map String Int64) -> (Result (List p/Plugin) String)
  (fold (fn [(acc (Result (List p/Plugin) String)) (row u/UpstreamProvider)] -> (Result (List p/Plugin) String)
          (mt acc
            ((err e) (err e))
            ((ok plugins)
              (if (stringStartsWith? (row.url st (mapEmpty)) "cli://")
                (ok plugins)
                (mt (p/openaiCompat row st (p/followingRedirects (p/openaiCompatCapabilities 64 (p/alwaysOn) (p/perToken 0.0 0.0) (list)) (optionOr (mapGet redirects row.id) 0)) none)
                  ((ok plugin) (ok (listAppend plugins (list plugin))))
                  ((err e) (err e)))))))
    (ok (list)) rows)


fn scalarText props: (Map String rd/SExpr) key: String fallback: String -> String
  (mt (mapGet props key) ((some e) (c/scalarToString (c/asnScalar e))) ((none) fallback))

fn scalarInt props: (Map String rd/SExpr) key: String fallback: Int64 -> (Result Int64 String)
  (mt (mapGet props key)
    ((none) (ok fallback))
    ((some e) (mt (c/asnScalar e) ((c/scalarInt n) (if (>= n 0) (ok n) (err (str ":" key " must be nonnegative")))) (_ (err (str ":" key " must be an integer"))))))

fn admissionMode text: String -> (Result fl/AdmissionMode String)
  (cond
    ((= text "direct") (ok (fl/direct)))
    ((= text "concurrencyCap") (ok (fl/concurrencyCap)))
    ((= text "ourBatch") (ok (fl/ourBatch)))
    (else (err (str "endpoint :admission must be direct, concurrencyCap or ourBatch, got " text))))

fn warmState endpoint: fl/Endpoint -> fl/State
  (let [(cold (fl/emptyState endpoint))]
    (mt (fl/transition cold (fl/demand))
      ((err _) cold)
      ((ok warming) (mt (fl/transition warming (fl/warmed)) ((ok warm) warm) ((err _) cold)))))

fn fleetEndpoint provider: String model: String mode: fl/AdmissionMode maxConcurrency: Int64 -> fl/Endpoint
  (fl/Endpoint :provider provider :model model :gpuTier "" :region "" :engine "" :admissionMode mode
    :maxConcurrency maxConcurrency :idleStopMs 0 :warmupMs 0 :upgradeQueueThreshold 1000000 :upgradeHoldMs 0
    :downgradeQueueThreshold 0 :downgradeHoldMs 0 :rewarmHourlyPrice 0 :idleHourlyPrice 0 :expectedDemandMs 0 :nextGpuTier "")

fn parseSlot form: rd/SExpr -> (Result Slot String)
  (mt (c/asnProps form (some ":endpoint"))
    ((err e) (err e))
    ((ok props)
      (let [(id (scalarText props "id" ""))
            (provider (scalarText props "provider" ""))
            (model (scalarText props "model" ""))]
        (cond
          ((or (stringEmpty? id) (or (stringEmpty? provider) (stringEmpty? model))) (err "endpoint needs :id, :provider and :model"))
          (else
            (mt (admissionMode (scalarText props "admission" "direct"))
              ((err e) (err (str "endpoint " id ": " e)))
              ((ok mode)
                (mt (scalarInt props "maxConcurrency" 8)
                  ((err e) (err (str "endpoint " id ": " e)))
                  ((ok cap)
                    (mt (scalarInt props "pricePerMillion" 0)
                      ((err e) (err (str "endpoint " id ": " e)))
                      ((ok price)
                        (if (< cap 1) (err (str "endpoint " id ": :maxConcurrency must be at least 1"))
                          (ok (Slot :id id :provider provider :model model :pricePerMillion price
                                :state (warmState (fleetEndpoint provider model mode cap)) :serverless none :polledMs 0 :deadlineMs 0))))))))))))))

fn parseSlots items: (List rd/SExpr) -> (Result (List Slot) String)
  (fold (fn [(acc (Result (List Slot) String)) (form rd/SExpr)] -> (Result (List Slot) String)
          (mt acc ((err e) (err e)) ((ok slots) (mt (parseSlot form) ((ok s) (ok (listAppend slots (list s)))) ((err e) (err e))))))
    (ok (list)) items)

fn formItems expr: rd/SExpr -> (List rd/SExpr)
  (mt expr ((rd/sexprVect items) items) ((rd/sexprList items) items) (_ (list)))

(schema WiringConfig
  (:f profile (Option rt/Profile))
  (:f slots (List Slot))
  (:f ledger (Option bgt/Ledger))
  (:f lifecycles (List rd/SExpr))
  (:f redirects (Map String Int64)))

fn providerRedirects items: (List rd/SExpr) -> (Result (Map String Int64) String)
  (fold (fn [(acc (Result (Map String Int64) String)) (form rd/SExpr)] -> (Result (Map String Int64) String)
          (mt acc
            ((err e) (err e))
            ((ok m)
              (mt (c/asnProps form (some ":provider"))
                ((err _) (ok m))
                ((ok props)
                  (mt (scalarInt props "redirectAfterSec" 0)
                    ((err e) (err (str "provider " (scalarText props "id" "") ": " e)))
                    ((ok n) (if (> n 0) (ok (mapSet m (scalarText props "id" "") n)) (ok m)))))))))
    (ok (mapEmpty)) items)

fn parseWiring text: String -> (Result WiringConfig String)
  (let [(form (rd/parseSexpr text))]
    (mt (c/asnProps form (some ":gateway"))
      ((err e) (err e))
      ((ok props)
        (mt (mt (mapGet props "router")
              ((none) (ok none))
              ((some expr) (mt (rt/parseRules (rd/renderSexpr expr)) ((ok profile) (ok (some profile))) ((err e) (err (str ":router: " e))))))
          ((err e) (err e))
          ((ok profile)
            (mt (mt (mapGet props "endpoints") ((none) (ok (list))) ((some expr) (parseSlots (formItems expr))))
              ((err e) (err (str ":endpoints: " e)))
              ((ok slots)
                (mt (mt (mapGet props "budget")
                      ((none) (ok none))
                      ((some expr) (mt (bgt/parseBudgetConfig expr 256) ((ok l) (ok (some l))) ((err e) (err (str ":budget: " e))))))
                  ((err e) (err e))
                  ((ok ledger)
                    (mt (providerRedirects (mt (mapGet props "providers") ((some expr) (formItems expr)) ((none) (list))))
                      ((err e) (err (str ":providers: " e)))
                      ((ok redirects)
                        (ok (WiringConfig :profile profile :slots slots :ledger ledger
                              :lifecycles (mt (mapGet props "lifecycles") ((some expr) (formItems expr)) ((none) (list))) :redirects redirects)))))))))))))

fn ! emptyWiring st: u/UpstreamSettings -> Wiring
  (Wiring :rows (u/upstreamProviders) :plugins (resultOr (pluginsFromRows (u/upstreamProviders) st (mapEmpty)) (list))
    :profile none :slots (list) :ledger none :settings st)


fn endpointStateNamed name: String -> (Option p/EndpointState)
  (cond
    ((= name "cold") (some (p/cold)))
    ((= name "warming") (some (p/warming)))
    ((= name "warm") (some (p/warm)))
    ((= name "draining") (some (p/draining)))
    ((= name "down") (some (p/down)))
    (else none))

fn lifecycleStatus endpoint: String body: String -> (Result p/LifecycleStatus String)
  (mt (j/jsonParse body)
    ((err e) (err (str "lifecycle reply is not JSON: " e)))
    ((ok v)
      (mt (j/jsonGet v "state")
        ((none) (err "lifecycle reply has no state"))
        ((some field)
          (mt field
            ((j/jstr name) (mt (endpointStateNamed name)
                             ((some state) (ok (p/LifecycleStatus :endpoint endpoint :state state :detail body)))
                             ((none) (err (str "lifecycle reply names unknown state " name)))))
            (_ (err "lifecycle reply state is not a string")))))))

fn ! lifecycleCall! row: u/UpstreamProvider st: u/UpstreamSettings env: (Map String String) path: String request: p/LifecycleRequest timeoutSec: Float64 -> (Result p/LifecycleStatus String)
  (let [(body (j/jsonEmit (j/jobj (list (pair "endpoint" (j/jstr request.endpoint)) (pair "model" (j/jstr request.model))))))]
    (mt (u/upstreamRequest (row.url st env) path (row.key st env) body (list (pair "Content-Type" "application/json")))
      ((err e) (err e))
      ((ok req)
        (mt (u/callUpstream! req env timeoutSec)
          ((err f) (err (str "lifecycle " path ": " (pd/failureText f))))
          ((ok resp) (lifecycleStatus request.endpoint resp.body))))))

fn ! httpLifecycle! props: (Map String rd/SExpr) row: u/UpstreamProvider st: u/UpstreamSettings env: (Map String String) -> (Result LifecycleSpec String)
  (let [(start (scalarText props "start" ""))
        (status (scalarText props "status" ""))
        (stop (scalarText props "stop" ""))]
    (if (or (stringEmpty? start) (stringEmpty? status)) (err "http lifecycle needs :start and :status paths")
      (mt (scalarInt props "coldStartMs" 30000)
        ((err e) (err e))
        ((ok cold)
          (mt (scalarInt props "idleTimeoutSec" 0)
            ((err e) (err e))
            ((ok idle)
              (mt (scalarInt props "startCost" 0)
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
  (mt spec.scale
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
  (mt (c/asnProps form (some ":lifecycle"))
    ((err e) (err e))
    ((ok props)
      (let [(provider (scalarText props "provider" ""))
            (family (scalarText props "family" ""))]
        (mt (familyNamed families family)
          ((none) (err (str "lifecycle for " provider ": unknown family " family)))
          ((some fam)
            (mt (u/upstreamProviderNamed rows provider)
              ((none) (err (str "lifecycle names provider " provider " with no row")))
              ((some row)
                (mt (p/pluginNamed acc.plugins provider)
                  ((none) (err (str "lifecycle names provider " provider " with no plugin")))
                  ((some plugin)
                    (mt (fam.make props row st env)
                      ((err e) (err (str "lifecycle for " provider ": " e)))
                      ((ok spec)
                        (mt (p/pluginWithLifecycle plugin spec.scale spec.lifecycle)
                          ((err e) (err e))
                          ((ok next) (ok (Attached :plugins (replacePlugin acc.plugins next) :slots (serverlessSlots acc.slots provider spec))))))))))))))))

fn ! wiringFromConfig table: (Option c/GatewayTable) text: String st: u/UpstreamSettings env: (Map String String) families: (List LifecycleFamily) -> (Result Wiring String)
  (let [(rows (rowsFromTable table))]
    (mt (if (stringEmpty? text) (ok (WiringConfig :profile none :slots (list) :ledger none :lifecycles (list) :redirects (mapEmpty))) (parseWiring text))
      ((err e) (err e))
      ((ok cfg)
        (mt (pluginsFromRows rows st cfg.redirects)
          ((err e) (err e))
          ((ok plugins)
            (mt (fold (fn [(acc (Result Attached String)) (form rd/SExpr)] -> (Result Attached String)
                        (mt acc ((err e) (err e)) ((ok a) (attachLifecycle! families rows st env a form))))
                  (ok (Attached :plugins plugins :slots cfg.slots)) cfg.lifecycles)
              ((err e) (err (str ":lifecycles: " e)))
              ((ok a) (ok (Wiring :rows rows :plugins a.plugins :profile cfg.profile :slots a.slots :ledger cfg.ledger :settings st)))))))))


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
      :cold (mt st.lifecycle ((fl/cold) true) (_ false))
      :down (mt st.lifecycle ((fl/down) true) ((fl/draining) true) (_ false))
      :pricePerMillion s.pricePerMillion))

fn passthroughSlot hint: RouteHint -> Slot
  (Slot :id hint.provider :provider hint.provider :model hint.model :pricePerMillion 0
    :state (warmState (fleetEndpoint hint.provider hint.model (fl/direct) 1000000)) :serverless none :polledMs 0 :deadlineMs 0)

fn routeCandidates w: Wiring hint: RouteHint -> (Pair String (List Slot))
  (mt w.profile
    ((none) (pair "passthrough" (list (passthroughSlot hint))))
    ((some profile)
      (mt (rt/route profile (routerRequest hint) (map endpointState w.slots) (list))
        ((err _) (pair "passthrough" (list (passthroughSlot hint))))
        ((ok decision)
          (pair decision.ruleId
            (fold (fn [(acc (List Slot)) (d rt/Decision)] -> (List Slot)
                    (mt (slotNamed w.slots d.endpoint)
                      ((some s) (listAppend acc (list (Slot :id s.id :provider s.provider :model d.model :pricePerMillion s.pricePerMillion :state s.state
                                                       :serverless s.serverless :polledMs s.polledMs :deadlineMs s.deadlineMs))))
                      ((none) acc)))
              (list) decision.candidates))))))

fn expectedCost s: Slot hint: RouteHint -> Int64
  (/ (* s.pricePerMillion (* 2 (max 1 hint.promptTokens))) 1000000)

fn admissionText a: fl/Admission -> String
  (mt a ((fl/admitNow) "admitNow") ((fl/queue) "queue") ((fl/reject r) (mt r ((fl/endpointUnavailable) "rejectUnavailable") ((fl/atCapacity) "rejectAtCapacity"))))

fn without slots: (List Slot) id: String -> (List Slot)
  (filter (fn [(s Slot)] -> Bool (!= s.id id)) slots)

fn requestDecision w: Wiring s: Slot hint: RouteHint nowMs: Int64 -> bgt/Decision
  (mt w.ledger
    ((none) (bgt/allow))
    ((some l) (bgt/gate l (bgt/actionRequest s.id s.provider "request" (expectedCost s hint)) nowMs)))

fn startable? s: Slot -> Bool
  (and (some? s.serverless) (mt s.state.lifecycle ((fl/cold) true) ((fl/warming) true) (_ false)))

fn coldStartMs s: Slot -> Int64
  (mt s.serverless ((some sv) sv.coldStartMs) ((none) 0))

fn pickLoop w: Wiring hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 rule: String names: (List String) left: (List Slot) refused: (List String) budgetDenied: Bool held: (Option Slot) -> Plan
  (let [(row (fn [(pick String) (model String) (a String) (b String)] -> DecisionRow
               (DecisionRow :rule rule :candidates names :refused refused :pick pick :admission a :budget b :model model)))]
    (if (listEmpty? left)
      (mt held
        ((some s)
          (mt (requestDecision w s hint nowMs)
            ((bgt/deny _) (planReject 429 (str "no endpoint admitted: " (stringJoin (listAppend refused (list (str s.id ":budget"))) " ")) (row "" hint.model "none" "deny")))
            ((bgt/allow)
              (mt (retarget w s hint request env)
                ((err e) (planReject 502 e (row s.id s.model "wait" "allow")))
                ((ok sent) (planWait s.id s.provider sent (row s.id s.model "wait" "allow")
                             (mt s.state.lifecycle ((fl/cold) true) (_ false)) (+ nowMs (coldStartMs s))))))))
        ((none) (planReject (if budgetDenied 429 503) (str "no endpoint admitted: " (stringJoin refused " ")) (row "" hint.model "none" (if budgetDenied "deny" "unchecked")))))
      (let [(index (resultOr (fl/spillover (map (fn [(s Slot)] -> fl/State s.state) left)) 0))
            (chosen (optionOr (listGet left index) (optionOr (listHead left) (passthroughSlot hint))))
            (admission (fl/admit chosen.state nowMs))
            (rest (without left chosen.id))]
        (mt admission
          ((fl/admitNow)
            (mt (requestDecision w chosen hint nowMs)
              ((bgt/deny _) (pickLoop w hint request env nowMs rule names rest (listAppend refused (list (str chosen.id ":budget"))) true held))
              ((bgt/allow)
                (mt (retarget w chosen hint request env)
                  ((err e) (planReject 502 e (row chosen.id chosen.model "admitNow" "allow")))
                  ((ok sent) (planSend chosen.id chosen.provider sent (row chosen.id chosen.model "admitNow" "allow")))))))
          (_ (if (and (startable? chosen) (none? held))
               (pickLoop w hint request env nowMs rule names rest refused budgetDenied (some chosen))
               (pickLoop w hint request env nowMs rule names rest (listAppend refused (list (str chosen.id ":" (admissionText admission)))) budgetDenied held)))))))

fn ! plan w: Wiring hint: RouteHint request: u/UpstreamRequest env: (Map String String) nowMs: Int64 -> Plan
  (let [(routed (routeCandidates w hint))
        (names (map (fn [(s Slot)] -> String s.id) (pairSecond routed)))]
    (pickLoop w hint request env nowMs (pairFirst routed) names (pairSecond routed) (list) false none))

fn sendTimeout w: Wiring hint: RouteHint provider: String timeoutSec: Float64 -> Float64
  (if (= provider hint.provider) timeoutSec
    (mt (u/upstreamProviderNamed w.rows provider)
      ((some row) (row.timeoutSec w.settings))
      ((none) timeoutSec)))

fn retarget w: Wiring s: Slot hint: RouteHint request: u/UpstreamRequest env: (Map String String) -> (Result u/UpstreamRequest String)
  (if (and (= s.provider hint.provider) (= s.model hint.model))
    (ok request)
    (mt (u/upstreamProviderNamed w.rows s.provider)
      ((none) (err (str "endpoint " s.id ": no provider row " s.provider)))
      ((some row)
        (mt (j/jsonParse request.data)
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
  (mt (slotNamed w.slots slotId)
    ((none) w)
    ((some s) (mt (fl/transition s.state (fl/requestStart))
      ((ok st) (withSlots w (replaceSlot w.slots (withState s st s.polledMs)) w.ledger))
      ((err _) w))))


fn lifecycleRequest s: Slot -> p/LifecycleRequest
  (let [(sv s.serverless)]
    (p/LifecycleRequest :endpoint s.id :model s.model :gpu s.state.endpoint.gpuTier :region s.state.endpoint.region
      :version "" :unit (mt sv ((some x) x.unit) ((none) "start")) :expectedCost (mt sv ((some x) x.startCost) ((none) 0))))

fn lifecycleRow op: String slotId: String detail: String -> String
  (str "(:gateway :lifecycle :op " op " :endpoint \"" slotId "\" " detail ")")

fn stateName state: p/EndpointState -> String
  (mt state ((p/cold) "cold") ((p/warming) "warming") ((p/warm) "warm") ((p/draining) "draining") ((p/down) "down"))

fn transitioned s: Slot event: fl/Event polledMs: Int64 -> Slot
  (mt (fl/transition s.state event) ((ok st) (withState s st polledMs)) ((err _) (withState s s.state polledMs)))

fn chargeStart w: Wiring s: Slot req: p/LifecycleRequest nowMs: Int64 -> (Pair (Option bgt/Ledger) String)
  (mt w.ledger
    ((none) (pair none "noLedger"))
    ((some l) (mt (bgt/charge l (bgt/Charge :endpoint s.id :provider s.provider :unit req.unit :atMs nowMs :cost req.expectedCost))
      ((ok next) (pair (some next) "charged"))
      ((err _) (pair (some l) "overCap")))))

fn ! startSlot! w: Wiring slotId: String nowMs: Int64 deadlineMs: Int64 -> StartOutcome
  (mt (slotNamed w.slots slotId)
    ((none) (startRefused 503 (str "endpoint " slotId " is not configured") (lifecycleRow "start" slotId ":result failed :reason \"not configured\"")))
    ((some s)
      (mt (p/pluginNamed w.plugins s.provider)
        ((none) (startRefused 503 (str "no plugin for provider " s.provider) (lifecycleRow "start" slotId ":result failed :reason \"no plugin\"")))
        ((some plugin)
          (let [(req (lifecycleRequest s))]
            (mt (p/pluginStart! plugin w.ledger req nowMs)
              ((err f)
                (let [(reason (p/failureText f))
                      (denied (mt f ((p/spendGate _) true) (_ false)))]
                  (startRefused (if denied 429 502) reason
                    (lifecycleRow "start" slotId (str ":result " (if denied "denied" "failed") " :reason \"" reason "\"")))))
              ((ok status)
                (let [(warming (withDeadline (transitioned s (fl/demand) nowMs) deadlineMs))
                      (ready (mt status.state ((p/warm) (transitioned warming (fl/warmed) nowMs)) (_ warming)))
                      (charged (chargeStart w s req nowMs))]
                  (startOk (withSlots w (replaceSlot w.slots ready) (pairFirst charged))
                    (lifecycleRow "start" slotId (str ":result started :state " (stateName status.state) " :cost " (stringFromInt64 req.expectedCost) " :charge " (pairSecond charged))))))))))))

fn waiting w: Wiring slotId: String -> Wiring
  (mt (slotNamed w.slots slotId)
    ((none) w)
    ((some s) (withSlots w (replaceSlot w.slots (transitioned s (fl/demand) s.polledMs)) w.ledger)))

fn warming? s: Slot -> Bool
  (and (some? s.serverless) (mt s.state.lifecycle ((fl/warming) true) (_ false)))

fn anyWarming? w: Wiring -> Bool
  (listAny? warming? w.slots)

fn ! pollSlot! w: Wiring s: Slot nowMs: Int64 -> (Pair Slot (List String))
  (if (not (warming? s)) (pair s (list))
  (if (> nowMs s.deadlineMs)
    (pair (withState s (fl/emptyState s.state.endpoint) nowMs) (list (lifecycleRow "status" s.id ":state cold :reason \"coldStartMs exceeded\"")))
  (if (< (- nowMs s.polledMs) 100) (pair s (list))
    (mt (p/pluginNamed w.plugins s.provider)
      ((none) (pair (transitioned s (fl/failed) nowMs) (list (lifecycleRow "status" s.id ":state down :reason \"no plugin\""))))
      ((some plugin)
        (mt (p/pluginStatus! plugin (lifecycleRequest s))
          ((err f) (pair (withState s s.state nowMs) (list (lifecycleRow "status" s.id (str ":error \"" (p/failureText f) "\"")))))
          ((ok status)
            (mt status.state
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
  (mt (slotNamed w.slots slotId)
    ((none) (readyGone (str "endpoint " slotId " is no longer configured")))
    ((some s)
      (mt (fl/admit s.state nowMs)
        ((fl/admitNow) (readyNow))
        ((fl/queue) (readyLater))
        ((fl/reject r) (mt r ((fl/atCapacity) (readyLater)) ((fl/endpointUnavailable) (readyGone (str "endpoint " slotId " failed to start"))))))))

fn carrySpend old: Wiring next: Wiring -> Wiring
  (mt old.ledger
    ((none) next)
    ((some spent)
      (mt next.ledger
        ((none) next)
        ((some l)
          (let [(kept (filter (fn [(b bgt/Bucket)] -> Bool (listAny? (fn [(line bgt/BudgetLine)] -> Bool (= line.id b.lineId)) l.lines)) spent.buckets))]
            (withSlots next next.slots
              (some (bgt/Ledger :lines l.lines :approvals l.approvals :buckets kept :maxBuckets l.maxBuckets))))))))

fn usageTokens body: String -> Int64
  (mt (j/jsonParse body)
    ((err _) 0)
    ((ok v) (mt (j/jsonGet v "usage")
      ((none) 0)
      ((some usage) (mt (j/jsonGet usage "total_tokens") ((some t) (mt t ((j/jint n) n) (_ 0))) ((none) 0))))))

fn settle w: Wiring slotId: String provider: String tokens: Int64 latencyMs: Int64 success: Bool nowMs: Int64 -> (Pair Wiring String)
  (let [(slot (slotNamed w.slots slotId))
        (price (mt slot ((some s) s.pricePerMillion) ((none) 0)))
        (cost (/ (* (max 0 tokens) price) 1000000))
        (slots (mt slot
                 ((none) w.slots)
                 ((some s) (mt (fl/transition s.state (fl/requestEnd (max 0 tokens) (max 1 latencyMs) success))
                   ((ok st) (replaceSlot w.slots (withState s st s.polledMs)))
                   ((err _) w.slots)))))
        (charged (mt w.ledger
                   ((none) (pair none "noLedger"))
                   ((some l) (mt (bgt/charge l (bgt/Charge :endpoint slotId :provider provider :unit "request" :atMs nowMs :cost cost))
                     ((ok next) (pair (some next) "charged"))
                     ((err _) (pair (some l) "overCap"))))))]
    (pair (withSlots w slots (pairFirst charged))
      (str "(:gateway :charge :endpoint \"" slotId "\" :tokens " (stringFromInt64 tokens) " :cost " (stringFromInt64 cost) " :status " (pairSecond charged) ")")))

fn quoted xs: (List String) -> String
  (stringJoin (map (fn [(x String)] -> String (str "\"" x "\"")) xs) " ")

fn decisionText row: DecisionRow -> String
  (str "(:gateway :route :rule \"" row.rule "\" :candidates (" (quoted row.candidates) ") :pick \"" row.pick
       "\" :refused (" (quoted row.refused) ") :model \"" row.model "\" :admission " row.admission " :budget " row.budget ")")
