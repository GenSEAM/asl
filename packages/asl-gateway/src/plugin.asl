(module aslGateway/plugin
  :x [PluginApi Batching ScaleModel PriceModel PluginCapabilities
      PluginRequest PluginReply PluginFailure
      LifecycleRequest EndpointState LifecycleStatus Lifecycle Plugin
      openaiChat anthropicMessages cliAgent custom
      continuous batchEndpoint unbatched
      alwaysOn serverless rentedVm perToken perGpuSecond
      httpSend cliSend httpStarted cliDone
      upstreamFailed cliFailed unsupported spendGate lifecycleFailed
      cold warming warm draining down
      capabilitiesError makePlugin
      pluginSend! pluginSendBatch! pluginHealth! pluginDeploy! pluginStart! pluginStop! pluginStatus!
      openaiCompatCapabilities cliAgentCapabilities followingRedirects maxRedirects
      openaiCompat cliPlugin ollama codex claude agy
      defaultPlugins! pluginNamed pluginWithLifecycle sendHttp! failureText]
  :i [(aslGateway/budget :a budget) (aslGateway/upstream :a up) (aslGateway/cliDispatch :a cli)])

(enum PluginApi
  (:c openaiChat [])
  (:c anthropicMessages [])
  (:c cliAgent [])
  (:c custom []))

(enum Batching
  (:c continuous [])
  (:c batchEndpoint [])
  (:c unbatched []))

(enum ScaleModel
  (:c alwaysOn [])
  (:c serverless [(idleTimeoutSec Int64) (coldStartMs Int64)])
  (:c rentedVm []))

(enum PriceModel
  (:c perToken [(inPerM Float64) (outPerM Float64)])
  (:c perGpuSecond [(rates (List (Pair String Float64)))]))

(schema PluginCapabilities
  (:f api PluginApi)
  (:f batching Batching)
  (:f maxConcurrency Int64)
  (:f streaming Bool)
  (:f tools Bool)
  (:f json Bool)
  (:f scaleModel ScaleModel)
  (:f priceModel PriceModel)
  (:f regions (List String))
  (:f redirectAfterSec Int64))

(enum PluginRequest
  (:c httpSend [(request up/UpstreamRequest) (env (Map String String)) (timeoutSec Float64)])
  (:c cliSend [(prompt String) (options cli/DispatchOptions)]))

(enum PluginReply
  (:c httpStarted [(call up/UpstreamCall)])
  (:c cliDone [(result cli/CliParseResult)]))

(enum PluginFailure
  (:c upstreamFailed [(failure up/UpstreamFailure)])
  (:c cliFailed [(reason String)])
  (:c unsupported [(plugin String) (operation String)])
  (:c spendGate [(reason String)])
  (:c lifecycleFailed [(reason String)]))

(schema LifecycleRequest
  (:f endpoint String)
  (:f model String)
  (:f gpu String)
  (:f region String)
  (:f version String)
  (:f unit String)
  (:f expectedCost Int64))

(enum EndpointState
  (:c cold [])
  (:c warming [])
  (:c warm [])
  (:c draining [])
  (:c down []))

(schema LifecycleStatus
  (:f endpoint String)
  (:f state EndpointState)
  (:f detail String))

(schema Lifecycle
  (:f deploy (fn [LifecycleRequest] -> (Result LifecycleStatus String)))
  (:f start (fn [LifecycleRequest] -> (Result LifecycleStatus String)))
  (:f stop (fn [LifecycleRequest] -> (Result LifecycleStatus String)))
  (:f status (fn [LifecycleRequest] -> (Result LifecycleStatus String))))

(schema Plugin
  (:f id String)
  (:f capabilities PluginCapabilities)
  (:f send (fn [PluginRequest] -> (Result PluginReply PluginFailure)))
  (:f sendBatch (Option (fn [(List PluginRequest)] -> (Result (List PluginReply) PluginFailure))))
  (:f health (fn [(Map String String)] -> (Result String String)))
  (:f lifecycle (Option Lifecycle)))

fn priceError price: PriceModel -> (Option String)
  (mt price
    ((perToken inPerM outPerM) (if (or (< inPerM 0.0) (< outPerM 0.0)) (some "perToken price is negative") none))
    ((perGpuSecond rates)
      (cond
        ((listEmpty? rates) (some "perGpuSecond has no gpu rate"))
        ((listAny? (fn [(rate (Pair String Float64))] -> Bool (or (stringEmpty? (pairFirst rate)) (< (pairSecond rate) 0.0))) rates)
          (some "perGpuSecond rate is negative or names no gpu"))
        (else none))))

fn scaleError scale: ScaleModel -> (Option String)
  (mt scale
    ((serverless idleTimeoutSec coldStartMs)
      (if (or (< idleTimeoutSec 0) (< coldStartMs 0)) (some "serverless timings are negative") none))
    (_ none))

fn capabilitiesError caps: PluginCapabilities -> (Option String)
  (if (< caps.maxConcurrency 1)
    (some "maxConcurrency is below 1")
    (if (< caps.redirectAfterSec 0) (some "redirectAfterSec is negative")
    (mt (priceError caps.priceModel)
      ((some e) (some e))
      ((none) (scaleError caps.scaleModel)))))

fn batchEndpoint? caps: PluginCapabilities -> Bool
  (mt caps.batching ((batchEndpoint) true) (_ false))

fn makePlugin id: String caps: PluginCapabilities send: (fn [PluginRequest] -> (Result PluginReply PluginFailure)) sendBatch: (Option (fn [(List PluginRequest)] -> (Result (List PluginReply) PluginFailure))) health: (fn [(Map String String)] -> (Result String String)) lifecycle: (Option Lifecycle) -> (Result Plugin String)
  (cond
    ((stringEmpty? id) (err "plugin id is empty"))
    ((some? (capabilitiesError caps)) (err (str id ": " (optionOr (capabilitiesError caps) ""))))
    ((and (batchEndpoint? caps) (not (some? sendBatch))) (err (str id ": batchEndpoint without sendBatch")))
    ((and (not (batchEndpoint? caps)) (some? sendBatch)) (err (str id ": sendBatch without batchEndpoint")))
    (else (ok (Plugin :id id :capabilities caps :send send :sendBatch sendBatch :health health :lifecycle lifecycle))))

fn ! pluginSend! plugin: Plugin request: PluginRequest -> (Result PluginReply PluginFailure)
  (plugin.send request)

fn ! pluginSendBatch! plugin: Plugin requests: (List PluginRequest) -> (Result (List PluginReply) PluginFailure)
  (mt plugin.sendBatch
    ((some batch) (batch requests))
    ((none) (err (unsupported plugin.id "sendBatch"))))

fn ! pluginHealth! plugin: Plugin env: (Map String String) -> (Result String String)
  (plugin.health env)

fn lifecycleResult result: (Result LifecycleStatus String) -> (Result LifecycleStatus PluginFailure)
  (mt result
    ((ok status) (ok status))
    ((err reason) (err (lifecycleFailed reason))))

fn ! gatedLifecycle! plugin: Plugin operation: String pick: (fn [Lifecycle] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String))) action: budget/Action ledger: (Option budget/Ledger) request: LifecycleRequest nowMs: Int64 -> (Result LifecycleStatus PluginFailure)
  (mt plugin.lifecycle
    ((none) (err (unsupported plugin.id operation)))
    ((some ops)
      (mt ledger
        ((none) (err (spendGate (str operation " needs a budget ledger"))))
        ((some l)
          (mt (budget/gate l action nowMs)
            ((budget/deny reason) (err (spendGate reason)))
            ((budget/allow) (lifecycleResult ((pick ops) request))))))))

fn ! pluginDeploy! plugin: Plugin ledger: (Option budget/Ledger) request: LifecycleRequest nowMs: Int64 -> (Result LifecycleStatus PluginFailure)
  (gatedLifecycle! plugin "deploy" (fn [(ops Lifecycle)] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String)) ops.deploy)
    (budget/actionDeploy request.endpoint) ledger request nowMs)

fn ! pluginStart! plugin: Plugin ledger: (Option budget/Ledger) request: LifecycleRequest nowMs: Int64 -> (Result LifecycleStatus PluginFailure)
  (gatedLifecycle! plugin "start" (fn [(ops Lifecycle)] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String)) ops.start)
    (budget/actionScaleUp request.endpoint plugin.id request.unit request.expectedCost) ledger request nowMs)

fn ! ungatedLifecycle! plugin: Plugin operation: String pick: (fn [Lifecycle] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String))) request: LifecycleRequest -> (Result LifecycleStatus PluginFailure)
  (mt plugin.lifecycle
    ((none) (err (unsupported plugin.id operation)))
    ((some ops) (lifecycleResult ((pick ops) request))))

fn ! pluginStop! plugin: Plugin request: LifecycleRequest -> (Result LifecycleStatus PluginFailure)
  (ungatedLifecycle! plugin "stop" (fn [(ops Lifecycle)] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String)) ops.stop) request)

fn ! pluginStatus! plugin: Plugin request: LifecycleRequest -> (Result LifecycleStatus PluginFailure)
  (ungatedLifecycle! plugin "status" (fn [(ops Lifecycle)] -> (fn [LifecycleRequest] -> (Result LifecycleStatus String)) ops.status) request)

fn openaiCompatCapabilities maxConcurrency: Int64 scale: ScaleModel price: PriceModel regions: (List String) -> PluginCapabilities
  (PluginCapabilities :api (openaiChat) :batching (continuous) :maxConcurrency maxConcurrency
    :streaming true :tools true :json true :scaleModel scale :priceModel price :regions regions :redirectAfterSec 0)

fn followingRedirects caps: PluginCapabilities redirectAfterSec: Int64 -> PluginCapabilities
  (with caps :redirectAfterSec redirectAfterSec)

fn maxRedirects caps: PluginCapabilities timeoutSec: Float64 -> Int64
  (if (<= caps.redirectAfterSec 0) 0
    (let [(secs (optionOr (float64ToInt64 (ceil timeoutSec)) 0))]
      (max 1 (/ (+ secs (- caps.redirectAfterSec 1)) caps.redirectAfterSec))))

fn cliAgentCapabilities -> PluginCapabilities
  (PluginCapabilities :api (cliAgent) :batching (unbatched) :maxConcurrency 1
    :streaming false :tools true :json false :scaleModel (alwaysOn) :priceModel (perToken 0.0 0.0) :regions (list) :redirectAfterSec 0)

fn ! openaiCompat provider: up/UpstreamProvider st: up/UpstreamSettings caps: PluginCapabilities lifecycle: (Option Lifecycle) -> (Result Plugin String)
  (makePlugin provider.id caps
    (fn [(request PluginRequest)] -> (Result PluginReply PluginFailure)
      (mt request
        ((httpSend req env timeoutSec)
          (mt (up/upstreamCallStartFollowing! req env timeoutSec (maxRedirects caps timeoutSec))
            ((ok call) (ok (httpStarted call)))
            ((err failure) (err (upstreamFailed failure)))))
        ((cliSend _ _) (err (unsupported provider.id "cliSend")))))
    none
    (fn [(env (Map String String))] -> (Result String String)
      (let [(url (provider.url st env))]
        (if (stringEmpty? url) (err (str provider.id ": no base URL")) (ok url))))
    lifecycle)

fn ! cliPlugin row: cli/CliProvider dispatch: (fn [String cli/DispatchOptions] -> (Result cli/CliParseResult String)) caps: PluginCapabilities -> (Result Plugin String)
  (makePlugin row.id caps
    (fn [(request PluginRequest)] -> (Result PluginReply PluginFailure)
      (mt request
        ((cliSend prompt options)
          (mt (dispatch prompt options)
            ((ok parsed) (ok (cliDone parsed)))
            ((err reason) (err (cliFailed reason)))))
        ((httpSend _ _ _) (err (unsupported row.id "httpSend")))))
    none
    (fn [(env (Map String String))] -> (Result String String) (cli/cliProviderHealth! row))
    none)

fn ! cliRowPlugin id: String dispatch: (fn [String cli/DispatchOptions] -> (Result cli/CliParseResult String)) -> (Result Plugin String)
  (mt (cli/cliProviderNamed id)
    ((some row) (cliPlugin row dispatch (cliAgentCapabilities)))
    ((none) (err (str "no CLI provider row " id))))

fn ! codex -> (Result Plugin String)
  (cliRowPlugin "codex" cli/dispatchCodexFallback!)

fn ! claude -> (Result Plugin String)
  (cliRowPlugin "claude" cli/dispatchClaudeFallback!)

fn ! agy -> (Result Plugin String)
  (cliRowPlugin "agy" cli/dispatchAgyFallback!)

fn ! ollama st: up/UpstreamSettings -> (Result Plugin String)
  (mt (up/upstreamProviderNamed (up/upstreamProviders) "ollama")
    ((some row) (openaiCompat row st (openaiCompatCapabilities 1 (alwaysOn) (perToken 0.0 0.0) (list)) none))
    ((none) (err "no upstream provider row ollama")))

fn ! defaultPlugins! st: up/UpstreamSettings -> (Result (List Plugin) String)
  (let [(httpRows (filter (fn [(row up/UpstreamProvider)] -> Bool (not (stringStartsWith? (row.url st (mapEmpty)) "cli://")))
                    (listAppend (up/upstreamProviders) (list (up/upstreamFallback)))))
        (http (map (fn [(row up/UpstreamProvider)] -> (Result Plugin String)
                     (openaiCompat row st (openaiCompatCapabilities 1 (alwaysOn) (perToken 0.0 0.0) (list)) none))
                httpRows))
        (all (listAppend (list (claude) (codex) (agy)) http))]
    (fold (fn [(acc (Result (List Plugin) String)) (one (Result Plugin String))] -> (Result (List Plugin) String)
            (mt acc
              ((err e) (err e))
              ((ok plugins) (mt one ((ok p) (ok (listAppend plugins (list p)))) ((err e) (err e))))))
      (ok (list)) all))

fn pluginWithLifecycle plugin: Plugin scale: ScaleModel lifecycle: Lifecycle -> (Result Plugin String)
  (let [(c plugin.capabilities)]
    (makePlugin plugin.id
      (PluginCapabilities :api c.api :batching c.batching :maxConcurrency c.maxConcurrency :streaming c.streaming
        :tools c.tools :json c.json :scaleModel scale :priceModel c.priceModel :regions c.regions :redirectAfterSec c.redirectAfterSec)
      plugin.send plugin.sendBatch plugin.health (some lifecycle)))

fn pluginNamed plugins: (List Plugin) id: String -> (Option Plugin)
  (if (listEmpty? plugins) none
    (if (= (preludeHead plugins).id id) (some (preludeHead plugins)) (pluginNamed (preludeTail plugins) id)))

fn failureText failure: PluginFailure -> String
  (mt failure
    ((upstreamFailed _) "upstream failure")
    ((cliFailed reason) reason)
    ((unsupported plugin operation) (str plugin " does not support " operation))
    ((spendGate reason) (str "spendGate: " reason))
    ((lifecycleFailed reason) reason))

fn ! sendHttp! plugins: (List Plugin) provider: String request: up/UpstreamRequest env: (Map String String) timeoutSec: Float64 -> (Result up/UpstreamCall up/UpstreamFailure)
  (mt (pluginNamed plugins provider)
    ((none) (err (up/protocolFailure (str "no plugin for provider " provider))))
    ((some plugin)
      (mt (pluginSend! plugin (httpSend request env timeoutSec))
        ((ok reply) (mt reply ((httpStarted call) (ok call)) ((cliDone _) (err (up/protocolFailure (str provider " answered an HTTP send without a call"))))))
        ((err failure) (mt failure ((upstreamFailed f) (err f)) (_ (err (up/protocolFailure (failureText failure)))))))))
