(module aslGateway/tests/fleetTest
  :x [runTests]
  :i [(fleet :a f)])

fn endpoint mode: f/AdmissionMode -> f/Endpoint
  (f/Endpoint :provider "p" :model "m" :gpuTier "small" :region "r" :engine "e" :admissionMode mode
    :maxConcurrency 1 :idleStopMs 10 :warmupMs 3600000 :upgradeQueueThreshold 0 :upgradeHoldMs 10
    :downgradeQueueThreshold 0 :downgradeHoldMs 10 :rewarmHourlyPrice 100 :idleHourlyPrice 200
    :expectedDemandMs 3600000 :nextGpuTier "large")

fn warmedState mode: f/AdmissionMode -> f/State
  (warmStateFor (endpoint mode))

fn warmStateFor ep: f/Endpoint -> f/State
  (f/State :endpoint ep :lifecycle f/warm :inFlight 0 :queueLength 0 :lastUsedMs 0
    :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0
    :errorRatePpm 0 :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0)

fn value result: (Result f/State f/FleetError) -> f/State
  (optionOr (resultToOption result) (f/State :endpoint (endpoint f/direct) :lifecycle f/down :inFlight 0 :queueLength 0 :lastUsedMs 0 :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0 :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0))

fn invalid result: (Result f/State f/FleetError) -> Bool
  (mt result ((err e) (mt e ((invalidTransition _) true) ((invalidSample) true) ((costOverflow) true))) (_ false))

fn testLifecycleTransitions -> Bool
  (let [(cold (f/emptyState (endpoint f/direct)))
        (demand (value (f/transition cold f/demand)))
        (warm (value (f/transition demand f/warmed)))
        (started (value (f/transition warm f/requestStart)))
        (ended (value (f/transition started (f/requestEnd 20 30 true))))
        (tick (value (f/transition ended (f/tick 50))))
        (draining (value (f/transition tick f/drainRequested)))
        (down (value (f/transition draining f/stopped)))
        (failed (value (f/transition demand f/failed)))]
    (assert (= demand.lifecycle f/warming) "demand warms cold endpoint")
    (assert (= warm.lifecycle f/warm) "warmed completes lifecycle transition")
    (assert (= started.inFlight 1) "requestStart increments in-flight")
    (assert (= ended.inFlight 0) "requestEnd decrements in-flight")
    (assert (= tick.p95LatencyMs 30) "tick snapshots latency percentile")
    (assert (= draining.lifecycle f/draining) "drainRequested enters draining")
    (assert (= down.lifecycle f/down) "stopped enters down")
    (assert (= failed.lifecycle f/down) "failed enters down")
    true)

fn testWarmupRelease -> Bool
  (let [(one (value (f/transition (f/emptyState (endpoint f/direct)) f/demand)))
        (two (value (f/transition one f/demand)))
        (observed (value (f/transition two (f/tick 1))))
        (ready (value (f/transition observed f/warmed)))]
    (assert (= ready.queueLength 0) "warmed clears queued requests")
    (assert (= ready.releasedOnWarm 2) "warmed releases all queued requests together")
    (assert (= ready.highQueueSinceMs -1) "warming completion resets queue-upgrade hold")
    true)

fn testInvalidTransitions -> Bool
  (let [(cold (f/emptyState (endpoint f/direct)))
        (warm (warmedState f/direct))
        (busy (f/State :endpoint (endpoint f/direct) :lifecycle f/draining :inFlight 1 :queueLength 1 :lastUsedMs 0
          :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0
          :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0))]
    (assert (invalid (f/transition cold f/warmed)) "warmed rejects cold")
    (assert (invalid (f/transition cold f/failed)) "failed rejects cold")
    (assert (invalid (f/transition cold f/requestStart)) "requestStart rejects cold")
    (let [(atCapacity (value (f/transition warm f/requestStart)))]
      (assert (= atCapacity.inFlight 1) "requestStart reaches configured capacity")
      (assert (invalid (f/transition atCapacity f/requestStart)) "requestStart rejects at capacity"))
    (assert (invalid (f/transition warm (f/requestEnd 1 0 true))) "requestEnd rejects zero latency")
    (assert (invalid (f/transition warm (f/requestEnd 1 1 true))) "requestEnd rejects without in-flight request")
    (assert (invalid (f/transition (value (f/transition warm f/requestStart)) (f/requestEnd -1 1 true)))
      "requestEnd rejects negative tokens")
    (assert (invalid (f/transition cold (f/tick -1))) "tick rejects time before last use")
    (assert (invalid (f/transition cold f/drainRequested)) "drainRequested rejects cold")
    (assert (invalid (f/transition busy f/stopped)) "stopped rejects active drain")
    (assert (invalid (f/transition (value (f/transition cold f/failed)) f/demand)) "demand rejects down")
    true)

fn testAdmission -> Bool
  (let [(warm (warmedState f/concurrencyCap))
        (atCap (f/State :endpoint (endpoint f/concurrencyCap) :lifecycle f/warm :inFlight 1 :queueLength 0 :lastUsedMs 0
          :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0
          :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0))
        (directCap (f/State :endpoint (endpoint f/direct) :lifecycle f/warm :inFlight 1 :queueLength 0 :lastUsedMs 0
          :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0
          :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0))]
    (assert (= (f/admit warm 0) f/admitNow) "warm endpoint under cap admits immediately")
    (assert (= (f/admit atCap 0) f/queue) "concurrencyCap queues at cap")
    (assert (= (f/admit (warmedState f/ourBatch) 0) f/queue) "ourBatch delegates by queueing")
    (assert (= (f/admit (warmedState f/direct) 0) f/admitNow) "direct admits below cap")
    (assert (mt (f/admit directCap 0) ((reject reason) (= reason f/atCapacity)) (_ false)) "direct rejects at cap")
    (assert (= (f/admit (f/emptyState (endpoint f/direct)) 0) f/queue) "cold arrival queues during warmup")
    (assert (mt (f/admit (value (f/transition (warmedState f/direct) f/drainRequested)) 0)
      ((reject reason) (= reason f/endpointUnavailable)) (_ false)) "draining endpoint rejects")
    true)

fn testScaleHysteresis -> Bool
  (let [(queued (value (f/transition (f/emptyState (endpoint f/direct)) f/demand)))
        (spike (value (f/transition queued (f/tick 100))))
        (late (value (f/transition spike (f/tick 109))))
        (held (value (f/transition late (f/tick 110))))
        (quiet (value (f/transition (warmedState f/direct) (f/tick 100))))]
    (assert (not (= (f/decide spike 109) f/upgradeTier)) "short queue spike does not upgrade before hold time")
    (assert (= (f/decide held 110) f/upgradeTier) "sustained queue upgrades after hold time")
    (assert (not (= (f/decide quiet 109) f/downgradeTier)) "brief quiet period does not downgrade before hold time")
    (assert (= (f/decide quiet 110) f/downgradeTier) "quiet period allows tier downgrade")
    (assert (= (f/decide (f/emptyState (endpoint f/direct)) 0) f/keep) "cold idle endpoint remains cold")
    (assert (= (f/decide queued 0) f/warmUp) "demanded cold endpoint warms")
    true)

fn testStopCostDecision -> Bool
  (let [(stopEndpoint (f/Endpoint :provider "p" :model "m" :gpuTier "" :region "r" :engine "e" :admissionMode f/direct
          :maxConcurrency 1 :idleStopMs 10 :warmupMs 3600000 :upgradeQueueThreshold 10 :upgradeHoldMs 10
          :downgradeQueueThreshold 0 :downgradeHoldMs 100 :rewarmHourlyPrice 100 :idleHourlyPrice 200
          :expectedDemandMs 3600000 :nextGpuTier ""))
        (quiet (value (f/transition (warmStateFor stopEndpoint) (f/tick 0))))
        (active (value (f/transition quiet f/requestStart)))
        (cheapWarm (f/Endpoint :provider "p" :model "m" :gpuTier "" :region "r" :engine "e" :admissionMode f/direct
          :maxConcurrency 1 :idleStopMs 10 :warmupMs 3600000 :upgradeQueueThreshold 10 :upgradeHoldMs 10
          :downgradeQueueThreshold 0 :downgradeHoldMs 100 :rewarmHourlyPrice 300 :idleHourlyPrice 100
          :expectedDemandMs 3600000 :nextGpuTier ""))
        (keepState (f/State :endpoint cheapWarm :lifecycle f/warm :inFlight 0 :queueLength 0 :lastUsedMs 0 :ring (f/makeRing)
          :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0 :costSoFar 0
          :highQueueSinceMs -1 :quietSinceMs 0 :releasedOnWarm 0))]
    (assert (= (f/decide quiet 10) f/stop) "idle cost above expected rewarm cost stops endpoint")
    (assert (= active.inFlight 1) "requestStart succeeds from quiet warm state")
    (assert (= active.quietSinceMs -1) "requestStart resets the quiet timer")
    (assert (= (f/decide active 100) f/keep) "request activity resets the idle stop hold")
    (assert (= (f/decide keepState 10) f/keep) "expected rewarm cost above idle cost keeps endpoint")
    (assert (mt (f/expectedWarmCost (f/Endpoint :provider "p" :model "m" :gpuTier "" :region "r" :engine "e"
      :admissionMode f/direct :maxConcurrency 1 :idleStopMs 0 :warmupMs 9223372036854775807
      :upgradeQueueThreshold 0 :upgradeHoldMs 0 :downgradeQueueThreshold 0 :downgradeHoldMs 0
      :rewarmHourlyPrice 2 :idleHourlyPrice 0 :expectedDemandMs 0 :nextGpuTier "")) ((err e) (= e f/costOverflow)) (_ false))
      "warm cost guards Int64 multiplication overflow")
    true)

fn testRingWindow -> Bool
  (let [(s1 (value (f/transition (warmedState f/direct) f/requestStart)))
        (s2 (value (f/transition s1 (f/requestEnd 1 10 true))))
        (s3 (value (f/transition (value (f/transition s2 f/requestStart)) (f/requestEnd 1 20 true))))
        (s4 (value (f/transition (value (f/transition s3 f/requestStart)) (f/requestEnd 1 30 true))))
        (s5 (value (f/transition (value (f/transition s4 f/requestStart)) (f/requestEnd 1 40 true))))
        (s6 (value (f/transition (value (f/transition s5 f/requestStart)) (f/requestEnd 1 50 true))))
        (s7 (value (f/transition (value (f/transition s6 f/requestStart)) (f/requestEnd 1 70 true))))]
    (assert (= s7.ring.count 5) "telemetry ring remains bounded at five samples")
    (assert (= s7.p95LatencyMs 70) "p95 uses latest bounded-window samples")
    (assert (= s7.p50LatencyMs 40) "p50 sorts bounded-window samples")
    (assert (= s7.rollingTokens 5) "rolling token count discards evicted samples")
    (assert (= (f/stateThroughputTps s7) 23) "rolling throughput is tokens per second over ring samples")
    true)

fn testRollingErrorRate -> Bool
  (let [(one (value (f/transition (warmedState f/direct) f/requestStart)))
        (good (value (f/transition one (f/requestEnd 1 10 true))))
        (two (value (f/transition good f/requestStart)))
        (bad (value (f/transition two (f/requestEnd 1 10 false))))]
    (assert (= bad.errorRatePpm 500000) "rolling error rate is failed samples per million")
    true)

fn testSpillover -> Bool
  (let [(busy (f/State :endpoint (endpoint f/direct) :lifecycle f/warm :inFlight 1 :queueLength 0 :lastUsedMs 0
          :ring (f/makeRing) :rollingTokens 0 :rollingElapsedMs 0 :p50LatencyMs 0 :p95LatencyMs 0 :errorRatePpm 0
          :costSoFar 0 :highQueueSinceMs -1 :quietSinceMs -1 :releasedOnWarm 0))
        (free (warmedState f/direct))
        (warming (value (f/transition (f/emptyState (endpoint f/direct)) f/demand)))
        (down (value (f/transition (warmedState f/direct) f/failed)))
        (tie (f/spillover (list free free)))]
    (assert (= (f/spillover (list busy free)) (ok 1)) "spillover prefers warm endpoint under its cap")
    (assert (= (f/spillover (list busy warming)) (ok 0)) "spillover chooses shortest expected wait")
    (assert (= tie (ok 0)) "spillover breaks equal-score ties by declaration order")
    (assert (mt (f/spillover (list down)) ((err e) true) (_ false)) "spillover refuses unavailable endpoints")
    true)

fn runTests -> Bool
  (do (testLifecycleTransitions) (testWarmupRelease) (testInvalidTransitions) (testAdmission)
    (testScaleHysteresis) (testStopCostDecision) (testRingWindow) (testRollingErrorRate) (testSpillover) true)
