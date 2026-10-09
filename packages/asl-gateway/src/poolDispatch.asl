(module aslGateway/poolDispatch
  :x [PoolMember PoolFailure poolTimedOut poolRejected poolUpstream PoolReply PoolRegistry PoolOutput
      emptyPoolRegistry poolWithPlugins poolLaneKey poolSubmit! poolAdvance! poolWatch poolActive? poolScaleDowns poolCallCount failureText]
  :i [(aslGateway/batchPool :a bp) (upstream :a u) (config :a c) (asl-json/json :a j) (pyText :a pt)
      (aslGateway/plugin :a p)])

(schema PoolMember
  (:f requestId Int64)
  (:f request u/UpstreamRequest)
  (:f timeoutSec Float64))

(enum PoolFailure
  (:c poolTimedOut [(requestId Int64) (timeoutMs Int64)])
  (:c poolRejected [(reason String)])
  (:c poolUpstream [(failure u/UpstreamFailure)]))

(schema PoolReply
  (:f requestId Int64)
  (:f result (Result u/UpstreamResponse PoolFailure)))

(schema PoolLane
  (:f provider String)
  (:f model String)
  (:f base String)
  (:f settings c/GatewayPool)
  (:f state bp/PoolState))

(enum PoolCallRole
  (:c roleBatch [(lane String) (batchId Int64) (requestIds (List Int64)) (batched Bool)])
  (:c roleHook [(lane String)]))

(schema PoolCall
  (:f role PoolCallRole)
  (:f call u/UpstreamCall))

(schema PoolRegistry
  (:f lanes (Map String PoolLane))
  (:f members (Map Int64 PoolMember))
  (:f results (Map Int64 (Result u/UpstreamResponse PoolFailure)))
  (:f calls (List PoolCall))
  (:f nextRequestId Int64)
  (:f scaleDowns Int64)
  (:f plugins (List p/Plugin)))

(schema PoolOutput
  (:f registry PoolRegistry)
  (:f replies (List PoolReply)))

(schema Finished
  (:f role PoolCallRole)
  (:f result (Result u/UpstreamResponse u/UpstreamFailure)))

fn emptyPoolRegistry -> PoolRegistry
  (PoolRegistry :lanes (mapEmpty) :members (mapEmpty) :results (mapEmpty) :calls (list) :nextRequestId 1 :scaleDowns 0 :plugins (list))

fn poolWithPlugins reg: PoolRegistry plugins: (List p/Plugin) -> PoolRegistry
  (with reg :plugins plugins)

fn poolLaneKey provider: String model: String -> String
  (str (stringFromInt64 (stringLength provider)) ":" provider model)

fn poolScaleDowns reg: PoolRegistry -> Int64
  reg.scaleDowns

fn poolCallCount reg: PoolRegistry -> Int64
  (listLength reg.calls)

fn withLanes reg: PoolRegistry lanes: (Map String PoolLane) -> PoolRegistry
  (with reg :lanes lanes)

fn withCalls reg: PoolRegistry calls: (List PoolCall) -> PoolRegistry
  (with reg :calls calls)

fn withResult reg: PoolRegistry id: Int64 result: (Result u/UpstreamResponse PoolFailure) -> PoolRegistry
  (if (mapHas? reg.members id)
    (with reg :results (mapSet reg.results id result))
    reg)

fn forget reg: PoolRegistry id: Int64 -> PoolRegistry
  (with reg :members (mapRemove reg.members id) :results (mapRemove reg.results id))

fn poolActive? reg: PoolRegistry -> Bool
  (or (not (listEmpty? reg.calls))
    (listAny? (fn [(lane PoolLane)] -> Bool
                (or (> (bp/poolStateQueued lane.state) 0) (> (bp/poolStateInFlightCount lane.state) 0)))
      (mapValues reg.lanes)))

fn poolWatch reg: PoolRegistry -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (pc PoolCall)] -> (List (Pair Int64 Int64)) (listAppend acc (u/upstreamCallWatch pc.call)))
    (list) reg.calls)

fn failureText f: u/UpstreamFailure -> String
  (mt f
    ((u/toolAbsent tool detail) (str tool ": " detail))
    ((u/transportFailure code text) (str "curl exit " (stringFromInt64 code) ": " (stringTrim text)))
    ((u/httpFailure status reason _) (u/httpErrorText status reason))
    ((u/protocolFailure detail) detail))

fn ! poolLog! text: String -> Bool
  (do (eprintln text) true)

fn laneState lane: PoolLane state: bp/PoolState -> PoolLane
  (with lane :state state)

fn ! laneEvent! reg: PoolRegistry key: String event: bp/PoolEvent env: (Map String String) nowMs: Int64 replies: (List PoolReply) -> PoolOutput
  (mt (mapGet reg.lanes key)
    ((none) (PoolOutput :registry reg :replies replies))
    ((some lane)
      (let [(step (bp/poolStep lane.state event nowMs))
            (reg1 (withLanes reg (mapSet reg.lanes key (laneState lane step.state))))]
        (runActions! reg1 key step.actions env nowMs replies))))

fn ! runActions! reg: PoolRegistry key: String actions: (List bp/PoolAction) env: (Map String String) nowMs: Int64 replies: (List PoolReply) -> PoolOutput
  (mt (listHead actions)
    ((none) (PoolOutput :registry reg :replies replies))
    ((some action)
      (let [(out (runAction! reg key action env nowMs replies))]
        (runActions! out.registry key (optionOr (listTail actions) (list)) env nowMs out.replies))))

fn laneTimeoutMs reg: PoolRegistry key: String -> Int64
  (mt (mapGet reg.lanes key)
    ((some lane) lane.settings.config.requestTimeoutMs)
    ((none) 0))

fn replyResult reg: PoolRegistry key: String id: Int64 result: (Result String bp/PoolError) -> (Result u/UpstreamResponse PoolFailure)
  (mt result
    ((ok _) (optionOr (mapGet reg.results id) (err (poolRejected "pool batch finished without a result for this request"))))
    ((err e)
      (mt e
        ((bp/requestTimedOut rid) (err (poolTimedOut rid (laneTimeoutMs reg key))))
        ((bp/batchRejected reason) (err (poolRejected reason))))))

fn ! runAction! reg: PoolRegistry key: String action: bp/PoolAction env: (Map String String) nowMs: Int64 replies: (List PoolReply) -> PoolOutput
  (mt action
    ((bp/dispatch batch) (startBatch! reg key batch env nowMs replies))
    ((bp/reply id result)
      (PoolOutput :registry (forget reg id)
        :replies (listAppend replies (list (PoolReply :requestId id :result (replyResult reg key id result))))))
    ((bp/scaleDown) (scaleDown! reg key env replies)))

fn membersOf reg: PoolRegistry requests: (List bp/PoolRequest) -> (List PoolMember)
  (fold (fn [(acc (List PoolMember)) (r bp/PoolRequest)] -> (List PoolMember)
          (mt (mapGet reg.members r.requestId) ((some m) (listAppend acc (list m))) ((none) acc)))
    (list) requests)

fn maxTimeout members: (List PoolMember) -> Float64
  (fold (fn [(acc Float64) (m PoolMember)] -> Float64 (if (> m.timeoutSec acc) m.timeoutSec acc)) 0.0 members)

fn batchRequest members: (List PoolMember) -> u/UpstreamRequest
  (let [(first (optionOr (listHead members) (PoolMember :requestId 0 :request (u/UpstreamRequest :url "" :fragment "" :method "POST" :headers (list) :data "") :timeoutSec 0.0)).request)
        (bodies (map (fn [(m PoolMember)] -> String m.request.data) members))]
    (u/UpstreamRequest :url first.url :fragment first.fragment :method "POST"
      :headers (listAppend first.headers (list (pair "X-ASL-Batch" (stringFromInt64 (listLength members)))))
      :data (str "{\"batch\":[" (stringJoin bodies ",") "]}")))

(schema PlannedCall
  (:f ids (List Int64))
  (:f request u/UpstreamRequest)
  (:f timeoutSec Float64)
  (:f batched Bool))

fn ! startBatch! reg: PoolRegistry key: String batch: bp/PoolBatch env: (Map String String) nowMs: Int64 replies: (List PoolReply) -> PoolOutput
  (mt (mapGet reg.lanes key)
    ((none) (PoolOutput :registry reg :replies replies))
    ((some lane)
      (let [(members (membersOf reg batch.requests))
            (plans (if lane.settings.batch
                     (list (PlannedCall :ids (map (fn [(m PoolMember)] -> Int64 m.requestId) members)
                             :request (batchRequest members) :timeoutSec (maxTimeout members) :batched true))
                     (map (fn [(m PoolMember)] -> PlannedCall
                            (PlannedCall :ids (list m.requestId) :request m.request :timeoutSec m.timeoutSec :batched false))
                       members)))
            (started (fold (fn [(acc PoolRegistry) (plan PlannedCall)] -> PoolRegistry
                             (mt (p/sendHttp! acc.plugins lane.provider plan.request env plan.timeoutSec)
                               ((ok call)
                                 (withCalls acc (listAppend acc.calls
                                   (list (PoolCall :role (roleBatch key batch.batchId plan.ids plan.batched) :call call)))))
                               ((err f) (fold (fn [(r PoolRegistry) (id Int64)] -> PoolRegistry (withResult r id (err (poolUpstream f)))) acc plan.ids))))
                       reg plans))]
        (if (batchOpen? started key batch.batchId)
          (PoolOutput :registry started :replies replies)
          (laneEvent! started key (bp/batchDone batch.batchId "") env nowMs replies)))))

fn batchOpen? reg: PoolRegistry key: String batchId: Int64 -> Bool
  (listAny? (fn [(pc PoolCall)] -> Bool
              (mt pc.role
                ((roleBatch lane id _ _) (and (= lane key) (= id batchId)))
                ((roleHook _) false)))
    reg.calls)

fn ! scaleDown! reg: PoolRegistry key: String env: (Map String String) replies: (List PoolReply) -> PoolOutput
  (mt (mapGet reg.lanes key)
    ((none) (PoolOutput :registry reg :replies replies))
    ((some lane)
      (let [(counted (with reg :scaleDowns (+ reg.scaleDowns 1)))
            (path lane.settings.scaleDownPath)
            (base (if (stringEndsWith? lane.base "/") (optionOr (stringSlice lane.base 0 (- (stringLength lane.base) 1)) "") lane.base))
            (note (str "(:gateway :pool :scaleDown :provider \"" lane.provider "\" :model \"" lane.model "\")"))]
        (if (stringEmpty? path)
          (do (poolLog! note) (PoolOutput :registry counted :replies replies))
          (let [(body (pt/jsonDumps (j/jobj (list (pair "event" (j/jstr "scaleDown")) (pair "provider" (j/jstr lane.provider))
                                                 (pair "model" (j/jstr lane.model)))) -1))
                (request (u/UpstreamRequest :url (str base path) :fragment "" :method "POST"
                           :headers (list (pair "Content-Type" "application/json")) :data body))]
            (mt (p/sendHttp! reg.plugins lane.provider request env 10.0)
              ((err f) (do (poolLog! (str "(:gateway :pool :scaleDownFailed :provider \"" lane.provider "\" :reason \"" (failureText f) "\")"))
                         (PoolOutput :registry counted :replies replies)))
              ((ok call) (PoolOutput :registry (withCalls counted (listAppend counted.calls (list (PoolCall :role (roleHook key) :call call))))
                           :replies replies))))))))

fn ! poolSubmit! reg: PoolRegistry provider: String model: String base: String settings: c/GatewayPool request: u/UpstreamRequest timeoutSec: Float64 env: (Map String String) nowMs: Int64 -> (Pair Int64 PoolOutput)
  (let [(id reg.nextRequestId)
        (key (poolLaneKey provider model))
        (state (mt (mapGet reg.lanes key)
                 ((some lane)
                   (let [(s lane.state)]
                     (bp/PoolState :config settings.config :queued s.queued :inFlight s.inFlight
                       :nextBatchId s.nextBatchId :scaleDownEmitted s.scaleDownEmitted)))
                 ((none) (bp/PoolState :config settings.config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))))
        (lane (PoolLane :provider provider :model model :base base :settings settings :state state))
        (reg1 (with reg :lanes (mapSet reg.lanes key lane) :members (mapSet reg.members id (PoolMember :requestId id :request request :timeoutSec timeoutSec)) :nextRequestId (+ id 1)))]
    (pair id (laneEvent! reg1 key (bp/arrive (bp/PoolRequest :requestId id :payload request.data :arrivedAt nowMs)) env nowMs (list))))

fn splitBatch resp: u/UpstreamResponse count: Int64 -> (Result (List u/UpstreamResponse) String)
  (mt (pt/jsonLoads resp.body)
    ((err _) (err "batch reply is not JSON"))
    ((ok v)
      (mt v
        ((j/jobj kvs)
          (mt (u/objGet kvs "batch")
            ((some items)
              (mt items
                ((j/jarr xs)
                  (if (= (listLength xs) count)
                    (ok (map (fn [(x j/Json)] -> u/UpstreamResponse
                               (u/UpstreamResponse :status resp.status :reason resp.reason :body (pt/jsonDumps x -1))) xs))
                    (err (str "batch reply carries " (stringFromInt64 (listLength xs)) " items for " (stringFromInt64 count) " requests"))))
                (_ (err "batch reply :batch is not an array"))))
            ((none) (err "batch reply has no batch array"))))
        (_ (err "batch reply is not an object")))))

fn storeResults reg: PoolRegistry ids: (List Int64) batched: Bool result: (Result u/UpstreamResponse u/UpstreamFailure) -> PoolRegistry
  (mt result
    ((err f) (fold (fn [(r PoolRegistry) (id Int64)] -> PoolRegistry (withResult r id (err (poolUpstream f)))) reg ids))
    ((ok resp)
      (if (not batched)
        (fold (fn [(r PoolRegistry) (id Int64)] -> PoolRegistry (withResult r id (ok resp))) reg ids)
        (mt (splitBatch resp (listLength ids))
          ((err why) (fold (fn [(r PoolRegistry) (id Int64)] -> PoolRegistry (withResult r id (err (poolUpstream (u/protocolFailure why))))) reg ids))
          ((ok parts)
            (fold (fn [(r PoolRegistry) (p (Pair Int64 u/UpstreamResponse))] -> PoolRegistry (withResult r (pairFirst p) (ok (pairSecond p))))
              reg (zip ids parts)))))))

fn ! completeCall! reg: PoolRegistry done: Finished env: (Map String String) nowMs: Int64 replies: (List PoolReply) -> PoolOutput
  (mt done.role
    ((roleHook key)
      (do
        (mt done.result
          ((ok _) true)
          ((err f) (poolLog! (str "(:gateway :pool :scaleDownFailed :lane \"" key "\" :reason \"" (failureText f) "\")"))))
        (PoolOutput :registry reg :replies replies)))
    ((roleBatch key batchId ids batched)
      (let [(stored (storeResults reg ids batched done.result))]
        (if (batchOpen? stored key batchId)
          (PoolOutput :registry stored :replies replies)
          (laneEvent! stored key (bp/batchDone batchId "") env nowMs replies)))))

fn ! pumpCall! pc: PoolCall ready: (List (Pair Int64 Int64)) -> (Pair (Option PoolCall) (Option Finished))
  (mt (u/upstreamCallPump! pc.call ready)
    ((err f) (pair none (some (Finished :role pc.role :result (err f)))))
    ((ok next)
      (if (u/upstreamCallOpen? next)
        (pair (some (with pc :call next)) none)
        (pair none (some (Finished :role pc.role :result (u/upstreamCallFinish! next)))))))

fn ! poolAdvance! reg: PoolRegistry ready: (List (Pair Int64 Int64)) env: (Map String String) nowMs: Int64 -> PoolOutput
  (let [(pumped (map (fn [(pc PoolCall)] -> (Pair (Option PoolCall) (Option Finished)) (pumpCall! pc ready)) reg.calls))
        (open (fold (fn [(acc (List PoolCall)) (p (Pair (Option PoolCall) (Option Finished)))] -> (List PoolCall)
                      (mt (pairFirst p) ((some pc) (listAppend acc (list pc))) ((none) acc))) (list) pumped))
        (finished (fold (fn [(acc (List Finished)) (p (Pair (Option PoolCall) (Option Finished)))] -> (List Finished)
                          (mt (pairSecond p) ((some f) (listAppend acc (list f))) ((none) acc))) (list) pumped))
        (settled (fold (fn [(out PoolOutput) (f Finished)] -> PoolOutput (completeCall! out.registry f env nowMs out.replies))
                   (PoolOutput :registry (withCalls reg open) :replies (list)) finished))]
    (fold (fn [(out PoolOutput) (key String)] -> PoolOutput
            (laneEvent! out.registry key (bp/tick) env nowMs out.replies))
      settled (mapKeys settled.registry.lanes)))
