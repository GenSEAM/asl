(module asl-engine/watchdog
  :x [LifetimeStatus EngineActivity checkLifetimeStatus!
      isIdle makeEngineActivity activityOnRequestStart activityOnRequestEnd activityOnSessionActive]
  :i [])

(schema LifetimeStatus
  (:f alive Bool)
  (:f socketExists Bool)
  (:f rootExists Bool)
  (:f reason String))

(schema EngineActivity
  (:f inFlight Int64)
  (:f lastActiveSec Int64)
  (:f idleSec Int64))

fn checkLifetimeStatus! socketPath: String rootDir: String -> LifetimeStatus
  (let [(sockStat (fileStat socketPath))
        (rootStat (fileStat rootDir))
        (sockOk (ok? sockStat))
        (rootOk (ok? rootStat))]
    (cond
      ((not sockOk)
        (LifetimeStatus :alive false :socketExists false :rootExists rootOk :reason "socket unlinked"))
      ((not rootOk)
        (LifetimeStatus :alive false :socketExists true :rootExists false :reason "root directory missing"))
      (else
        (LifetimeStatus :alive true :socketExists true :rootExists true :reason ""))))

fn isIdle nowSec: Int64 lastActiveSec: Int64 inFlight: Int64 activeSessionCount: Int64 idleSec: Int64 -> Bool
  (if (<= idleSec 0)
    false
    (if (> inFlight 0)
      false
      (if (> activeSessionCount 0)
        false
        (>= (- nowSec lastActiveSec) idleSec))))

fn makeEngineActivity idleSec: Int64 nowSec: Int64 -> EngineActivity
  (EngineActivity :inFlight 0 :lastActiveSec nowSec :idleSec idleSec)

fn activityOnRequestStart act: EngineActivity nowSec: Int64 -> EngineActivity
  (with act :inFlight (+ act.inFlight 1) :lastActiveSec nowSec)

fn activityOnRequestEnd act: EngineActivity nowSec: Int64 -> EngineActivity
  (let [(newFlight (if (> act.inFlight 0) (- act.inFlight 1) 0))]
    (with act :inFlight newFlight :lastActiveSec nowSec))

fn activityOnSessionActive act: EngineActivity nowSec: Int64 -> EngineActivity
  (with act :lastActiveSec nowSec)
