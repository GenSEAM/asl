(module aslGateway/batchPool
  :x [PoolConfig PoolRequest PoolBatch PoolState PoolError PoolEvent PoolAction PoolStep defaultPoolConfig makePoolConfig defaultPoolState poolStep poolStateQueued poolStateInFlightCount poolActionReplyCount poolActionDispatchCount poolActionScaleDownCount]
  :i [])

(schema PoolConfig
  (:f windowMs Int64)
  (:f peakCount Int64)
  (:f bypassWhileBusy Bool)
  (:f requestTimeoutMs Int64))

(schema PoolRequest
  (:f requestId Int64)
  (:f payload String)
  (:f arrivedAt Int64))

(schema PoolBatch
  (:f batchId Int64)
  (:f requests (List PoolRequest)))

(schema PoolState
  (:f config PoolConfig)
  (:f queued (List PoolRequest))
  (:f inFlight (List PoolBatch))
  (:f nextBatchId Int64)
  (:f scaleDownEmitted Bool))

(enum PoolError
  (:c requestTimedOut [(requestId Int64)])
  (:c batchRejected [(reason String)]))

(enum PoolEvent
  (:c arrive [(request PoolRequest)])
  (:c tick [])
  (:c batchDone [(batchId Int64) (response String)])
  (:c batchFailed [(batchId Int64) (reason String)]))

(enum PoolAction
  (:c dispatch [(batch PoolBatch)])
  (:c reply [(requestId Int64) (result (Result String PoolError))])
  (:c scaleDown []))

(schema PoolStep
  (:f state PoolState)
  (:f actions (List PoolAction)))

fn defaultPoolConfig -> PoolConfig
  (PoolConfig :windowMs 7000 :peakCount 16 :bypassWhileBusy true :requestTimeoutMs 30000)

fn makePoolConfig windowMs: Int64 peakCount: Int64 bypassWhileBusy: Bool requestTimeoutMs: Int64 -> PoolConfig
  (PoolConfig :windowMs (if (> windowMs 0) windowMs 7000)
    :peakCount (if (> peakCount 0) peakCount 16) :bypassWhileBusy bypassWhileBusy
    :requestTimeoutMs (if (> requestTimeoutMs 0) requestTimeoutMs 30000))

fn defaultPoolState -> PoolState
  (PoolState :config (defaultPoolConfig) :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false)

fn poolStateQueued state: PoolState -> Int64
  (listLength state.queued)

fn poolStateInFlightCount state: PoolState -> Int64
  (listLength state.inFlight)

fn poolActionReplyCount actions: (List PoolAction) -> Int64
  (if (listEmpty? actions) 0
    (let [(head (optionOr (listHead actions) (reply 0 (err (batchRejected "invalid")))))
          (tail (optionOr (listTail actions) (list)))]
      (+ (mt head ((reply _ _) 1) (_ 0)) (poolActionReplyCount tail))))

fn poolActionDispatchCount actions: (List PoolAction) -> Int64
  (if (listEmpty? actions) 0
    (let [(head (optionOr (listHead actions) (reply 0 (err (batchRejected "invalid")))))
          (tail (optionOr (listTail actions) (list)))]
      (+ (mt head ((dispatch _) 1) (_ 0)) (poolActionDispatchCount tail))))

fn poolActionScaleDownCount actions: (List PoolAction) -> Int64
  (if (listEmpty? actions) 0
    (let [(head (optionOr (listHead actions) (reply 0 (err (batchRejected "invalid")))))
          (tail (optionOr (listTail actions) (list)))]
      (+ (mt head ((scaleDown) 1) (_ 0)) (poolActionScaleDownCount tail))))

fn isTimedOut request: PoolRequest nowMs: Int64 timeoutMs: Int64 -> Bool
  (>= (- nowMs request.arrivedAt) timeoutMs)

fn timeoutQueue requests: (List PoolRequest) nowMs: Int64 timeoutMs: Int64 -> (Pair (List PoolRequest) (List PoolAction))
  (if (listEmpty? requests) (pair (list) (list))
    (let [(head (optionOr (listHead requests) (PoolRequest :requestId 0 :payload "" :arrivedAt nowMs)))
          (tail (optionOr (listTail requests) (list)))
          (rest (timeoutQueue tail nowMs timeoutMs))]
      (if (isTimedOut head nowMs timeoutMs)
        (pair (pairFirst rest) (listAppend (list (reply head.requestId (err (requestTimedOut head.requestId)))) (pairSecond rest)))
        (pair (listAppend (list head) (pairFirst rest)) (pairSecond rest)))))

fn timeoutBatches batches: (List PoolBatch) nowMs: Int64 timeoutMs: Int64 -> (Pair (List PoolBatch) (List PoolAction))
  (if (listEmpty? batches) (pair (list) (list))
    (let [(head (optionOr (listHead batches) (PoolBatch :batchId 0 :requests (list))))
          (tail (optionOr (listTail batches) (list)))
          (reqResult (timeoutQueue head.requests nowMs timeoutMs))
          (rest (timeoutBatches tail nowMs timeoutMs))
          (filtered (PoolBatch :batchId head.batchId :requests (pairFirst reqResult)))]
      (pair (listAppend (list filtered) (pairFirst rest))
        (listAppend (pairSecond reqResult) (pairSecond rest)))))

fn oldestWaited requests: (List PoolRequest) nowMs: Int64 windowMs: Int64 -> Bool
  (if (listEmpty? requests) false
    (let [(head (optionOr (listHead requests) (PoolRequest :requestId 0 :payload "" :arrivedAt nowMs)))]
      (>= (- nowMs head.arrivedAt) windowMs)))

fn dispatchBatch state: PoolState requests: (List PoolRequest) -> PoolStep
  (let [(batch (PoolBatch :batchId state.nextBatchId :requests requests))
        (nextState (with state :queued (list) :inFlight (listAppend state.inFlight (list batch)) :nextBatchId (+ state.nextBatchId 1) :scaleDownEmitted false))]
    (PoolStep :state nextState :actions (list (dispatch batch))))

fn flushQueued state: PoolState -> PoolStep
  (dispatchBatch state state.queued)

fn poolStep state: PoolState event: PoolEvent nowMs: Int64 -> PoolStep
  (mt event
    ((arrive request)
      (let [(config state.config)
            (busy (not (listEmpty? state.inFlight)))
            (resetState (with state :config config :scaleDownEmitted false))]
        (if (and busy config.bypassWhileBusy)
          (dispatchBatch resetState (list request))
          (let [(queued (listAppend state.queued (list request)))
                (nextState (with state :config config :queued queued :scaleDownEmitted false))]
            (if (>= (listLength queued) config.peakCount) (flushQueued nextState)
              (PoolStep :state nextState :actions (list)))))))
    ((tick)
      (let [(config state.config)
            (queuedResult (timeoutQueue state.queued nowMs config.requestTimeoutMs))
            (flightResult (timeoutBatches state.inFlight nowMs config.requestTimeoutMs))
            (timedState (with state :config config :queued (pairFirst queuedResult) :inFlight (pairFirst flightResult)))
            (timeoutActions (listAppend (pairSecond queuedResult) (pairSecond flightResult)))]
        (if (and (not (listEmpty? timedState.queued))
              (oldestWaited timedState.queued nowMs config.windowMs))
          (let [(flushed (flushQueued timedState))]
            (PoolStep :state flushed.state :actions (listAppend timeoutActions flushed.actions)))
          (PoolStep :state timedState :actions timeoutActions))))
    ((batchDone batchId response) (completeBatch state batchId (ok response)))
    ((batchFailed batchId reason) (completeBatch state batchId (err (batchRejected reason)))))

fn completeBatch state: PoolState batchId: Int64 result: (Result String PoolError) -> PoolStep
  (let [(found (findBatch state.inFlight batchId))]
    (if (not (some? found)) (PoolStep :state state :actions (list))
      (let [(batch (optionOr found (PoolBatch :batchId 0 :requests (list))))
            (replyActions (replyBatchRequests batch.requests result))
            (remaining (removeBatch state.inFlight batchId))
            (nextState (with state :inFlight remaining))]
        (if (and (listEmpty? remaining) (listEmpty? state.queued) (not state.scaleDownEmitted))
            (PoolStep :state (with state :queued (list) :inFlight remaining :scaleDownEmitted true)
              :actions (listAppend replyActions (list (scaleDown))))
          (PoolStep :state nextState :actions replyActions)))))

fn findBatch batches: (List PoolBatch) batchId: Int64 -> (Option PoolBatch)
  (if (listEmpty? batches) (none)
    (let [(head (optionOr (listHead batches) (PoolBatch :batchId 0 :requests (list))))]
      (if (= head.batchId batchId) (some head)
        (findBatch (optionOr (listTail batches) (list)) batchId))))

fn removeBatch batches: (List PoolBatch) batchId: Int64 -> (List PoolBatch)
  (if (listEmpty? batches) (list)
    (let [(head (optionOr (listHead batches) (PoolBatch :batchId 0 :requests (list))))
          (tail (optionOr (listTail batches) (list)))]
      (if (= head.batchId batchId) tail
        (listAppend (list head) (removeBatch tail batchId)))))

fn replyBatchRequests requests: (List PoolRequest) result: (Result String PoolError) -> (List PoolAction)
  (if (listEmpty? requests) (list)
    (let [(head (optionOr (listHead requests) (PoolRequest :requestId 0 :payload "" :arrivedAt 0)))
          (tail (optionOr (listTail requests) (list)))]
      (listAppend (list (reply head.requestId result)) (replyBatchRequests tail result))))
