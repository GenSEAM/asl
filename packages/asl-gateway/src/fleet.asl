(module aslGateway/fleet
  :x [AdmissionMode Lifecycle Endpoint State FleetError Event Admission ScaleDecision RejectReason
      Sample Ring makeRing emptyState transition admit decide spillover expectedWarmCost expectedIdleCost stateThroughputTps]
  :i [])

(enum AdmissionMode (:c direct []) (:c concurrencyCap []) (:c ourBatch []))
(enum Lifecycle (:c cold []) (:c warming []) (:c warm []) (:c draining []) (:c down []))
(schema Endpoint
  (:f provider String) (:f model String) (:f gpuTier String) (:f region String) (:f engine String)
  (:f admissionMode AdmissionMode) (:f maxConcurrency Int64) (:f idleStopMs Int64) (:f warmupMs Int64)
  (:f upgradeQueueThreshold Int64) (:f upgradeHoldMs Int64)
  (:f downgradeQueueThreshold Int64) (:f downgradeHoldMs Int64)
  (:f rewarmHourlyPrice Int64) (:f idleHourlyPrice Int64) (:f expectedDemandMs Int64) (:f nextGpuTier String))
(schema Sample (:f latencyMs Int64) (:f tokens Int64) (:f ok Bool))
(schema Ring (:f a Sample) (:f b Sample) (:f c Sample) (:f d Sample) (:f e Sample) (:f count Int64) (:f next Int64))
(schema State
  (:f endpoint Endpoint) (:f lifecycle Lifecycle) (:f inFlight Int64) (:f queueLength Int64)
  (:f lastUsedMs Int64) (:f ring Ring) (:f rollingTokens Int64) (:f rollingElapsedMs Int64)
  (:f p50LatencyMs Int64) (:f p95LatencyMs Int64) (:f errorRatePpm Int64) (:f costSoFar Int64)
  (:f highQueueSinceMs Int64) (:f quietSinceMs Int64) (:f releasedOnWarm Int64))
(enum FleetError (:c invalidTransition [(reason String)]) (:c invalidSample []) (:c costOverflow []))
(enum Event (:c demand []) (:c warmed []) (:c failed []) (:c requestStart [])
  (:c requestEnd [(tokens Int64) (latencyMs Int64) (ok Bool)]) (:c tick [(nowMs Int64)])
  (:c drainRequested []) (:c stopped []))
(enum RejectReason (:c endpointUnavailable []) (:c atCapacity []))
(enum Admission (:c admitNow []) (:c queue []) (:c reject [(reason RejectReason)]))
(enum ScaleDecision (:c keep []) (:c warmUp []) (:c drain []) (:c stop []) (:c upgradeTier []) (:c downgradeTier []))

fn makeRing -> Ring
  (let [(z (Sample :latencyMs 0 :tokens 0 :ok true))] (Ring :a z :b z :c z :d z :e z :count 0 :next 0))

fn emptyState endpoint: Endpoint -> State
  (State :endpoint endpoint :lifecycle cold :inFlight 0 :queueLength 0 :lastUsedMs 0 :ring (makeRing)
    :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0 :costSoFar 0
    :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0)

fn ringGet ring: Ring index: Int64 -> Sample
  (if (= index 0) ring.a (if (= index 1) ring.b (if (= index 2) ring.c (if (= index 3) ring.d ring.e))))

fn ringPut ring: Ring sample: Sample -> Ring
  (Ring :a (if (= ring.next 0) sample ring.a) :b (if (= ring.next 1) sample ring.b)
    :c (if (= ring.next 2) sample ring.c) :d (if (= ring.next 3) sample ring.d)
    :e (if (= ring.next 4) sample ring.e) :count (if (< ring.count 5) (+ ring.count 1) 5)
    :next (mod (+ ring.next 1) 5))

fn ringLatency ring: Ring index: Int64 -> Int64
  (ringGet ring (mod (+ (- ring.next ring.count) index 5) 5)).latencyMs

fn ringTokens ring: Ring index: Int64 -> Int64
  (if (>= index ring.count) 0
    (+ (ringGet ring (mod (+ (- ring.next ring.count) index 5) 5)).tokens (ringTokens ring (+ index 1))))
fn ringLatencyTotal ring: Ring index: Int64 -> Int64
  (if (>= index ring.count) 0 (+ (ringLatency ring index) (ringLatencyTotal ring (+ index 1))))
fn ringFailures ring: Ring index: Int64 -> Int64
  (if (>= index ring.count) 0
    (+ (if (ringGet ring (mod (+ (- ring.next ring.count) index 5) 5)).ok 0 1)
      (ringFailures ring (+ index 1))))
fn stateThroughputTps state: State -> Int64
  (if (= (ringLatencyTotal state.ring 0) 0) 0
    (/ (* (ringTokens state.ring 0) 1000) (ringLatencyTotal state.ring 0)))

fn ringLatencies ring: Ring index: Int64 -> (List Int64)
  (if (>= index ring.count) (list)
    (listAppend (list (ringLatency ring index)) (ringLatencies ring (+ index 1))))

fn latencyAt ring: Ring percentile: Int64 -> Int64
  (let [(n ring.count)
        (sorted (listSort (ringLatencies ring 0)))
        (rank (if (<= percentile 50) (if (= n 0) 0 (- (/ (+ n 1) 2) 1)) (- n 1)))]
    (if (= n 0) 0 (optionOr (listGet sorted rank) 0)))

fn copyState state: State lifecycle: Lifecycle flight: Int64 queued: Int64 used: Int64 ring: Ring tokens: Int64
    elapsed: Int64 p50: Int64 p95: Int64 errors: Int64 cost: Int64 high: Int64 quiet: Int64 released: Int64 -> State
  (with state :lifecycle lifecycle :inFlight flight :queueLength queued :lastUsedMs used :ring ring :rollingTokens tokens :rollingElapsedMs elapsed :p50LatencyMs p50 :p95LatencyMs p95 :errorRatePpm errors :costSoFar cost :highQueueSinceMs high :quietSinceMs quiet :releasedOnWarm released)

fn transition state: State event: Event -> (Result State FleetError)
  (mt event
    ((demand)
      (if (or (= state.lifecycle cold) (= state.lifecycle warming))
        (ok (copyState state warming state.inFlight (+ state.queueLength 1) state.lastUsedMs state.ring
          state.rollingTokens state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs
          state.errorRatePpm state.costSoFar state.highQueueSinceMs -1 0))
        (err (invalidTransition "demand requires cold or warming"))))
    ((warmed)
      (if (= state.lifecycle warming)
        (ok (copyState state warm state.inFlight 0 state.lastUsedMs state.ring state.rollingTokens
          state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs state.errorRatePpm
          state.costSoFar -1 -1 state.queueLength))
        (err (invalidTransition "warmed requires warming"))))
    ((failed)
      (if (or (= state.lifecycle warming) (= state.lifecycle warm))
        (ok (copyState state down 0 state.queueLength state.lastUsedMs state.ring state.rollingTokens
          state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs state.errorRatePpm
          state.costSoFar -1 -1 0))
        (err (invalidTransition "failed requires warming or warm"))))
    ((requestStart)
      (if (and (= state.lifecycle warm) (< state.inFlight state.endpoint.maxConcurrency))
        (ok (copyState state warm (+ state.inFlight 1) state.queueLength state.lastUsedMs state.ring
          state.rollingTokens state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs
          state.errorRatePpm state.costSoFar state.highQueueSinceMs -1 0))
        (err (invalidTransition "requestStart requires warm capacity"))))
    ((requestEnd tokens latencyMs success)
      (if (and (> state.inFlight 0) (>= tokens 0) (> latencyMs 0))
        (let [(ring (ringPut state.ring (Sample :latencyMs latencyMs :tokens tokens :ok success)))
              (n ring.count)
              (errors (ringFailures ring 0))]
          (ok (copyState state state.lifecycle (- state.inFlight 1) state.queueLength state.lastUsedMs
            ring (ringTokens ring 0) (ringLatencyTotal ring 0) (latencyAt ring 50) (latencyAt ring 95)
            (/ (* errors 1000000) n) state.costSoFar state.highQueueSinceMs -1 0)))
        (err invalidSample)))
    ((tick nowMs)
      (if (< nowMs state.lastUsedMs) (err (invalidTransition "tick cannot precede last use"))
        (ok (copyState state state.lifecycle state.inFlight state.queueLength
          (if (or (> state.inFlight 0) (> state.queueLength 0)) nowMs state.lastUsedMs)
          state.ring state.rollingTokens state.rollingElapsedMs (latencyAt state.ring 50)
          (latencyAt state.ring 95) state.errorRatePpm state.costSoFar
          (if (> state.queueLength state.endpoint.upgradeQueueThreshold)
            (if (< state.highQueueSinceMs 0) nowMs state.highQueueSinceMs) -1)
          (if (and (<= state.queueLength state.endpoint.downgradeQueueThreshold) (= state.inFlight 0))
            (if (< state.quietSinceMs 0) nowMs state.quietSinceMs) -1) 0))))
    ((drainRequested)
      (if (or (= state.lifecycle warming) (= state.lifecycle warm))
        (ok (copyState state draining state.inFlight state.queueLength state.lastUsedMs state.ring
          state.rollingTokens state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs
          state.errorRatePpm state.costSoFar -1 -1 0))
        (err (invalidTransition "drainRequested requires warming or warm"))))
    ((stopped)
      (if (and (= state.lifecycle draining) (= state.inFlight 0) (= state.queueLength 0))
        (ok (copyState state down 0 0 state.lastUsedMs state.ring state.rollingTokens
          state.rollingElapsedMs state.p50LatencyMs state.p95LatencyMs state.errorRatePpm
          state.costSoFar state.highQueueSinceMs state.quietSinceMs 0))
        (err (invalidTransition "stopped requires drained endpoint")))))

fn admit state: State nowMs: Int64 -> Admission
  (if (or (= state.lifecycle cold) (= state.lifecycle warming)) queue
    (if (or (= state.lifecycle down) (= state.lifecycle draining)) (reject endpointUnavailable)
      (mt state.endpoint.admissionMode
        ((ourBatch) queue)
        ((direct) (if (< state.inFlight state.endpoint.maxConcurrency) admitNow (reject atCapacity)))
        ((concurrencyCap) (if (< state.inFlight state.endpoint.maxConcurrency) admitNow queue)))))

fn hourlyCost durationMs: Int64 price: Int64 -> (Result Int64 FleetError)
  (if (or (< durationMs 0) (< price 0) (and (> price 0) (> durationMs (/ 9223372036854775807 price))))
    (err costOverflow) (ok (/ (* durationMs price) 3600000)))
fn expectedWarmCost endpoint: Endpoint -> (Result Int64 FleetError)
  (hourlyCost endpoint.warmupMs endpoint.rewarmHourlyPrice)
fn expectedIdleCost endpoint: Endpoint -> (Result Int64 FleetError)
  (hourlyCost endpoint.expectedDemandMs endpoint.idleHourlyPrice)

fn decide state: State nowMs: Int64 -> ScaleDecision
  (let [(ep state.endpoint) (high (and (>= state.highQueueSinceMs 0)
      (>= (- nowMs state.highQueueSinceMs) ep.upgradeHoldMs)))
        (quiet (and (>= state.quietSinceMs 0) (>= (- nowMs state.quietSinceMs) ep.downgradeHoldMs)))]
    (if (and high (not (stringEmpty? ep.nextGpuTier))) upgradeTier
      (if (and quiet (not (stringEmpty? ep.gpuTier))) downgradeTier
        (if (= state.lifecycle warming) warmUp
          (if (or (= state.lifecycle cold) (= state.lifecycle down))
          (if (> state.queueLength 0) warmUp keep)
          (if (and (= state.lifecycle warm) (= state.inFlight 0) (= state.queueLength 0)
              (>= state.quietSinceMs 0) (>= (- nowMs state.quietSinceMs) ep.idleStopMs))
            (mt (expectedWarmCost ep) ((ok warmCost)
              (mt (expectedIdleCost ep) ((ok idleCost) (if (> idleCost warmCost) stop keep)) (_ keep))) (_ keep))
            keep))))))

fn waitScore state: State -> Int64
  (if (= state.lifecycle warm)
    (if (< state.inFlight state.endpoint.maxConcurrency) 0
      (* (+ state.inFlight state.queueLength) (max 1 state.p95LatencyMs)))
    (if (= state.lifecycle warming)
      (+ state.endpoint.warmupMs (* state.queueLength (max 1 state.p95LatencyMs)))
      state.endpoint.warmupMs))

fn spillover states: (List State) -> (Result Int64 FleetError)
  (if (listEmpty? states) (err (invalidTransition "spillover has no endpoints"))
    (spilloverLoop states 0 -1 false 9223372036854775807))
fn spilloverLoop states: (List State) index: Int64 bestIndex: Int64 bestAvailable: Bool bestScore: Int64 -> (Result Int64 FleetError)
  (if (listEmpty? states) (if (< bestIndex 0) (err (invalidTransition "no admissible endpoint")) (ok bestIndex))
    (let [(st (optionOr (listHead states) (emptyState (Endpoint :provider "" :model "" :gpuTier "" :region "" :engine ""
          :admissionMode direct :maxConcurrency 0 :idleStopMs 0 :warmupMs 0 :upgradeQueueThreshold 0 :upgradeHoldMs 0
          :downgradeQueueThreshold 0 :downgradeHoldMs 0 :rewarmHourlyPrice 0 :idleHourlyPrice 0 :expectedDemandMs 0 :nextGpuTier ""))))
          (tail (optionOr (listTail states) (list)))
          (available (and (= st.lifecycle warm) (< st.inFlight st.endpoint.maxConcurrency)))
          (score (waitScore st))
          (eligible (not (or (= st.lifecycle down) (= st.lifecycle draining))))
          (replace (and eligible (or (and available (not bestAvailable))
            (and (= available bestAvailable) (or (< score bestScore) (< bestIndex 0))))))
          (chosen (if replace index bestIndex))
          (nextAvailable (if replace available bestAvailable))
          (nextScore (if replace score bestScore))]
      (spilloverLoop tail (+ index 1) chosen nextAvailable nextScore)))
