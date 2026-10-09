(module aslGateway/tests/batchPoolTest
  :x [runTests]
  :i [(batchPool :a bp)])

fn stepState step: bp/PoolStep -> bp/PoolState
  step.state

fn stepActions step: bp/PoolStep -> (List bp/PoolAction)
  step.actions

fn firstBatchId state: bp/PoolState -> Int64
  (let [(batch (optionOr (listHead state.inFlight) (bp/PoolBatch :batchId 0 :requests (list))))]
    batch.batchId)

fn firstDispatchSize actions: (List bp/PoolAction) -> Int64
  (mt (optionOr (listHead actions) (bp/reply 0 (ok "missing")))
    ((dispatch batch) (listLength batch.requests))
    (_ 0))

fn testWindowFlush -> Bool
  (let [(config (bp/makePoolConfig 10 8 true 100))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (arrived (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 1 :payload "a" :arrivedAt 0)) 0))
        (waiting (bp/poolStep (stepState arrived) bp/tick 9))
        (flushed (bp/poolStep (stepState waiting) bp/tick 10))]
    (assert (= (bp/poolActionDispatchCount (stepActions arrived)) 0) "window trace queues before deadline")
    (assert (= (bp/poolActionDispatchCount (stepActions waiting)) 0) "window trace does not flush early")
    (assert (= (bp/poolActionDispatchCount (stepActions flushed)) 1) "oldest request flushes at windowMs")
    (assert (= (bp/poolStateInFlightCount (stepState flushed)) 1) "window flush creates one in-flight batch")
    true)

fn testCountFlush -> Bool
  (let [(config (bp/makePoolConfig 100 2 true 1000))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (one (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 1 :payload "a" :arrivedAt 0)) 0))
        (two (bp/poolStep (stepState one) (bp/arrive (bp/PoolRequest :requestId 2 :payload "b" :arrivedAt 1)) 1))]
    (assert (= (bp/poolActionDispatchCount (stepActions one)) 0) "count trace holds first request")
    (assert (= (bp/poolActionDispatchCount (stepActions two)) 1) "pool flushes immediately at peakCount")
    (assert (= (firstDispatchSize (stepActions two)) 2) "count-triggered batch contains both requests")
    (assert (= (bp/poolStateQueued (stepState two)) 0) "count flush empties queue")
    true)

fn testBusyBypass -> Bool
  (let [(config (bp/makePoolConfig 100 8 true 1000))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (one (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 1 :payload "a" :arrivedAt 0)) 0))
        (flush (bp/poolStep (stepState one) bp/tick 100))
        (bypass (bp/poolStep (stepState flush) (bp/arrive (bp/PoolRequest :requestId 2 :payload "b" :arrivedAt 101)) 101))]
    (assert (= (bp/poolStateInFlightCount (stepState flush)) 1) "first batch is in flight")
    (assert (= (bp/poolActionDispatchCount (stepActions bypass)) 1) "busy bypass immediately dispatches a small batch")
    (assert (= (bp/poolStateInFlightCount (stepState bypass)) 2) "bypass batch proceeds alongside original")
    (assert (= (bp/poolStateQueued (stepState bypass)) 0) "bypass request does not wait in queue")
    true)

fn testBusyQueueWhenBypassOff -> Bool
  (let [(config (bp/makePoolConfig 100 8 false 1000))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (one (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 1 :payload "a" :arrivedAt 0)) 0))
        (flush (bp/poolStep (stepState one) bp/tick 100))
        (queued (bp/poolStep (stepState flush) (bp/arrive (bp/PoolRequest :requestId 2 :payload "b" :arrivedAt 101)) 101))
        (done (bp/poolStep (stepState queued) (bp/batchDone 1 "ok") 102))]
    (assert (= (bp/poolActionDispatchCount (stepActions queued)) 0) "disabled bypass queues behind active batch")
    (assert (= (bp/poolStateQueued (stepState queued)) 1) "disabled bypass preserves waiting request")
    (assert (= (bp/poolActionDispatchCount (stepActions done)) 0) "batch completion does not flush before windowMs or peakCount")
    (assert (= (bp/poolStateQueued (stepState done)) 1) "queued work remains pending after active batch drains")
    (let [(flushed (bp/poolStep (stepState done) bp/tick 201))]
      (assert (= (bp/poolActionDispatchCount (stepActions flushed)) 1) "queued work flushes at its window deadline")
      (assert (= (bp/poolStateInFlightCount (stepState flushed)) 1) "window flush dispatches queued work"))
    true)

fn testSingleScaleDownAfterDrain -> Bool
  (let [(config (bp/makePoolConfig 1 4 true 1000))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (arrived (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 1 :payload "a" :arrivedAt 0)) 0))
        (flushed (bp/poolStep (stepState arrived) bp/tick 1))
        (done (bp/poolStep (stepState flushed) (bp/batchDone 1 "ok") 2))
        (duplicate (bp/poolStep (stepState done) (bp/batchDone 1 "again") 3))]
    (assert (= (bp/poolActionReplyCount (stepActions done)) 1) "successful completion replies once")
    (assert (= (bp/poolActionScaleDownCount (stepActions done)) 1) "last drained batch emits scaleDown")
    (assert (= (bp/poolActionScaleDownCount (stepActions duplicate)) 0) "duplicate completion cannot re-emit scaleDown")
    (assert (= (bp/poolActionReplyCount (stepActions duplicate)) 0) "duplicate completion cannot duplicate reply")
    true)

fn testRequestTimeoutTypedError -> Bool
  (let [(config (bp/makePoolConfig 100 8 true 10))
        (state (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (arrived (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId 7 :payload "slow" :arrivedAt 0)) 0))
        (expired (bp/poolStep (stepState arrived) bp/tick 10))]
    (assert (= (bp/poolActionReplyCount (stepActions expired)) 1) "expired request receives exactly one reply action")
    (assert (= (bp/poolStateQueued (stepState expired)) 0) "timed out request leaves queue")
    (mt (optionOr (listHead (stepActions expired)) (bp/reply 0 (ok "missing")))
      ((reply requestId result)
       (do
         (assert (= requestId 7) "timeout reply identifies request")
         (assert (mt result ((err error) (mt error ((requestTimedOut id) (= id 7)) (_ false))) (_ false)) "timeout is a typed requestTimedOut error")
         true))
      (_ false)))

fn randomTrace state: bp/PoolState seed: Int64 index: Int64 replies: Int64 arrivals: Int64 -> (Pair bp/PoolState (Pair Int64 Int64))
  (if (>= index 1000) (pair state (pair replies arrivals))
    (let [(nextSeed (mod (+ (* seed 1103515245) 12345) 2147483647))
          (choice (mod nextSeed 4))
          (now (* index 3))]
      (if (< choice 2)
        (let [(step (bp/poolStep state (bp/arrive (bp/PoolRequest :requestId index :payload "trace" :arrivedAt now)) now))]
          (randomTrace (stepState step) nextSeed (+ index 1)
            (+ replies (bp/poolActionReplyCount (stepActions step))) (+ arrivals 1)))
        (if (and (= choice 2) (> (bp/poolStateInFlightCount state) 0))
          (let [(step (bp/poolStep state (bp/batchDone (firstBatchId state) "ok") now))]
            (randomTrace (stepState step) nextSeed (+ index 1)
              (+ replies (bp/poolActionReplyCount (stepActions step))) arrivals))
          (let [(step (bp/poolStep state bp/tick now))]
            (randomTrace (stepState step) nextSeed (+ index 1)
              (+ replies (bp/poolActionReplyCount (stepActions step))) arrivals))))))

fn drainBatches state: bp/PoolState replies: Int64 -> (Pair bp/PoolState Int64)
  (if (= (bp/poolStateInFlightCount state) 0) (pair state replies)
    (let [(step (bp/poolStep state (bp/batchDone (firstBatchId state) "drained") 1000000))]
      (drainBatches (stepState step) (+ replies (bp/poolActionReplyCount (stepActions step))))))

fn testSeededThousandEventTrace -> Bool
  (let [(config (bp/makePoolConfig 7 5 true 25))
        (initial (bp/PoolState :config config :queued (list) :inFlight (list) :nextBatchId 1 :scaleDownEmitted false))
        (trace (randomTrace initial 91357 0 0 0))
        (state (pairFirst trace))
        (counts (pairSecond trace))
        (timeout (bp/poolStep state bp/tick 1000000))
        (drained (drainBatches (stepState timeout) (+ (pairFirst counts) (bp/poolActionReplyCount (stepActions timeout)))))]
    (assert (> (pairSecond counts) 0) "seeded 1000-event trace includes arrivals")
    (assert (= (pairSecond drained) (pairSecond counts)) "seeded trace produces one reply per arrival")
    (assert (= (bp/poolStateQueued (pairFirst drained)) 0) "seeded trace drains pending queue")
    (assert (= (bp/poolStateInFlightCount (pairFirst drained)) 0) "seeded trace drains active batches")
    true)

fn runTests -> Bool
  (do
    (testWindowFlush)
    (testCountFlush)
    (testBusyBypass)
    (testBusyQueueWhenBypassOff)
    (testSingleScaleDownAfterDrain)
    (testRequestTimeoutTypedError)
    (testSeededThousandEventTrace)
    true)
