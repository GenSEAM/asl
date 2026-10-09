(module asl-engine/engine
  :x [EngineConfig EngineRuntime resolveScope! checkSocketPath
      makeEngineRuntime withBuild withSupervisor dispatchRequest! formatRssMb
      cmdStatus! cmdPing! cmdStart! cmdStop! cmdRestart! cmdRun! cmdEval!]
  :i [(asl-engine/wire :a w)
      (asl-engine/breaker :a brk)
      (asl-engine/lease :a lse)
      (asl-engine/guard :a grd)
      (asl-engine/watchdog :a wd)
      (asl-engine/supervisor :a sp)
      (asl-engine/transport :a tp)
      (asl-engine/build :a bld)])

(schema EngineConfig
  (:f scope String)
  (:f rootDir String)
  (:f socketPath String)
  (:f pidFile String)
  (:f logFile String)
  (:f idleSec Int64)
  (:f maxRssMb Int64)
  (:f softRssMb Int64))

(schema EngineRuntime
  (:f config EngineConfig)
  (:f supervisor sp/SupervisorState)
  (:f activity wd/EngineActivity)
  (:f lease lse/LeaseLock)
  (:f startTimeSec Int64)
  (:f build bld/EngineBuild))

fn resolveScope! rootDir: String scopeOpt: String -> EngineConfig
  (let [(effectiveScope (cond
                          ((!= scopeOpt "") scopeOpt)
                          ((ok? (fileStat (str rootDir "/.asl"))) "workspace")
                          ((ok? (fileStat (str rootDir "/asl"))) "workspace")
                          ((ok? (fileStat (str rootDir "/.git"))) "workspace")
                          (else "system")))
        (defaultPaths (cond
                        ((= effectiveScope "system")
                          (pair "/tmp/asl-engine.sock"
                                (pair (str "/tmp/asl-engine-" (optionOr (envGet "USER") "user") ".pid")
                                      "/tmp/asl-engine.log")))
                        ((or (stringStartsWith? effectiveScope "task-") (stringStartsWith? effectiveScope "task/"))
                          (let [(taskName (if (stringStartsWith? effectiveScope "task-")
                                            (optionOr (stringSlice effectiveScope 5 (stringLength effectiveScope)) "task")
                                            (optionOr (stringSlice effectiveScope 5 (stringLength effectiveScope)) "task")))
                                (taskDir (str rootDir "/.asl/tasks/" taskName))
                                (_ (dirCreate taskDir))]
                            (pair (str taskDir "/engine.sock")
                                  (pair (str taskDir "/engine.pid")
                                        (str taskDir "/engine.log")))))
                        (else
                          (pair (str rootDir "/.asl/engine.sock")
                                (pair (str rootDir "/.asl/engine.pid")
                                      (str rootDir "/.asl/engine.log"))))))
        (defSock (pairFirst defaultPaths))
        (defPid (pairFirst (pairSecond defaultPaths)))
        (defLog (pairSecond (pairSecond defaultPaths)))
        (envSock (optionOr (envGet "ASL_ENGINE_SOCKET") ""))
        (finalSock (if (!= envSock "") envSock defSock))
        (envPid (optionOr (envGet "ASL_ENGINE_PID_FILE") ""))
        (finalPid (if (!= envPid "") envPid defPid))
        (envIdle (optionOr (envGet "ASL_ENGINE_IDLE_SEC") "900"))
        (idleSec (optionOr (stringToInt64 envIdle) 900))
        (maxRss (optionOr (stringToInt64 (optionOr (envGet "ASL_ENGINE_MAX_RSS_MB") "512")) 512))
        (softRss (optionOr (stringToInt64 (optionOr (envGet "ASL_ENGINE_SOFT_RSS_MB") "384")) 384))]
    (EngineConfig :scope effectiveScope
                  :rootDir rootDir
                  :socketPath finalSock
                  :pidFile finalPid
                  :logFile defLog
                  :idleSec idleSec
                  :maxRssMb maxRss
                  :softRssMb softRss))
fn checkSocketPath socketPath: String isDarwin: Bool -> (Result Unit String)
  (let [(limit (if isDarwin 104 108))
        (len (stringLength socketPath))]
    (if (>= len limit)
      (err (w/formatSocketPathTooLong socketPath len limit))
      (ok ())))
fn makeEngineRuntime config: EngineConfig nowSec: Int64 -> EngineRuntime
  (let [(act (wd/makeEngineActivity config.idleSec nowSec))
        (sup (sp/makeSupervisorState))
        (lease (lse/LeaseLock :acquired false :fd -1 :lockPath "" :error ""))]
    (EngineRuntime :config config
                   :supervisor sup
                   :activity act
                   :lease lease
                   :startTimeSec nowSec
                   :build (bld/EngineBuild :entry "" :toolRoot "" :host "" :version "" :updates 0 :updatedFrom "")))

fn withBuild rt: EngineRuntime build: bld/EngineBuild -> EngineRuntime
  (with rt :build build)

fn withSupervisor rt: EngineRuntime sup: sp/SupervisorState -> EngineRuntime
  (with rt :supervisor sup)

fn withActivity rt: EngineRuntime act: wd/EngineActivity -> EngineRuntime
  (with rt :activity act)

fn formatRssMb kb: Int64 -> String
  (str (stringFromInt64 (/ kb 1024)) "." (stringFromInt64 (/ (* (mod kb 1024) 10) 1024)))

fn rssKb! -> Int64
  (mt (procRusage) ((ok u) u.selfMaxRssKb) ((err _) 0))

fn sleepSeconds! raw: String -> (Result String String)
  (mt (stringToFloat64 raw)
    ((none) (err (str "sleep needs a number of seconds, got " raw)))
    ((some sec)
      (if (or (< sec 0.0) (> sec 3600.0))
        (err (str "sleep seconds must lie in [0, 3600], got " raw))
        (do (sleepMs (optionOr (float64ToInt64 (* sec 1000.0)) 0)) (ok raw)))))

fn dispatchRequest! rt: EngineRuntime line: String nowSec: Int64 -> (Pair EngineRuntime String)
  (let [(parsed (w/parseSimpleSExpr line))
        (op (pairFirst parsed))
        (args (pairSecond parsed))]
    (cond
      ((= op "ping")
        (let [(slept (mt (w/getArg args "sleep") ((some raw) (sleepSeconds! raw)) ((none) (ok ""))))
              (uptime (- nowSec rt.startTimeSec))
              (newRt (withActivity rt (wd/activityOnRequestStart rt.activity nowSec)))]
          (mt slept
            ((err e) (pair newRt (w/formatReceiptError e)))
            ((ok _) (pair newRt (w/formatPongOk (procSelf) uptime rt.config.scope))))))
      ((or (= op "sleep") (= op "wait"))
        (let [(secStr (w/getArgOr args "sec" (w/getArgOr args "seconds" "3")))]
          (mt (sleepSeconds! secStr)
            ((err e) (pair rt (w/formatReceiptError e)))
            ((ok _) (pair rt (w/formatSleepReceipt secStr))))))
      ((= op "engine")
        (let [(action (w/getArgOr args "action" "status"))
              (uptime (- nowSec rt.startTimeSec))]
          (cond
                        ((= action "stop")
              (pair rt (w/formatEngineStoppingReceipt (procSelf) rt.config.scope)))
            ((= action "ping")
              (pair rt (w/formatEnginePongReceipt (procSelf) uptime rt.config.scope)))
            (else
              (let [(b rt.build)
                    (disk (if (stringEmpty? b.entry) b.version (bld/sourceVersion! b.entry)))
                    (activeCount (sp/runningCount rt.supervisor))
                    (receipt (w/formatEngineStatusReceipt (procSelf) uptime (formatRssMb (rssKb!)) activeCount rt.config.socketPath rt.config.scope
                                                          b.version disk (and (!= disk b.version) (!= disk "absent")) b.updates b.updatedFrom))]
                (pair rt receipt))))))
      ((or (= op "manage") (or (= op "spawn") (or (= op "poll") (or (= op "tail") (or (= op "kill") (or (= op "send") (= op "list")))))))
        (let [(action (w/getArgOr args "action" op))]
          (cond
            ((or (= action "spawn") (= action "start"))
              (let [(id (w/getArgOr args "id" (w/getArgOr args "name" "")))
                    (cmd (w/getArgOr args "cmd" ""))
                    (cwd (w/getArgOr args "cwd" rt.config.rootDir))
                    (stdin (= (w/getArgOr args "stdin" "false") "true"))
                    (spawnRes (sp/spawnSessionWith! rt.supervisor id cmd cwd stdin (w/getArgOr args "unset" "") (w/getArgOr args "setenv" "") nowSec))
                    (newSup (pairFirst spawnRes))
                    (resp (pairSecond spawnRes))
                    (newRt (withActivity (withSupervisor rt newSup) (wd/activityOnSessionActive rt.activity nowSec)))]
                (pair newRt resp)))
            ((or (= action "poll") (= action "status"))
              (let [(id (w/getArgOr args "id" ""))
                    (pollRes (sp/pollSession! rt.supervisor id nowSec))
                    (newSup (pairFirst pollRes))
                    (resp (pairSecond pollRes))
                    (newRt (withSupervisor rt newSup))]
                (pair newRt resp)))
            ((or (= action "tail") (= action "logs"))
              (let [(id (w/getArgOr args "id" ""))
                    (linesStr (w/getArgOr args "lines" "20"))
                    (linesN (optionOr (stringToInt64 linesStr) 20))
                    (resp (sp/tailSession! rt.supervisor id linesN))]
                (pair rt resp)))
            ((or (= action "kill") (or (= action "terminate") (= action "stop")))
              (let [(id (w/getArgOr args "id" ""))
                    (killRes (sp/killSession! rt.supervisor id))
                    (newSup (pairFirst killRes))
                    (resp (pairSecond killRes))
                    (newRt (withSupervisor rt newSup))]
                (pair newRt resp)))
            ((= action "send")
              (let [(id (w/getArgOr args "id" ""))
                    (text (w/getArgOr args "text" ""))
                    (closeStdin (= (w/getArgOr args "close" "false") "true"))
                    (resp (sp/sendSession! rt.supervisor id text closeStdin))]
                (pair rt resp)))
            ((or (= action "list") (= action "sessions"))
              (let [(resp (sp/listSessionsReceipt rt.supervisor))]
                (pair rt resp)))
                        (else
              (pair rt (w/formatReceiptError (str "Unknown engine op: " op)))))))
      (else
        (pair rt (w/formatReceiptError (str "Unknown engine op: " op))))))
fn cmdStatus! rootDir: String scopeOpt: String -> String
  (let [(cfg (resolveScope! rootDir scopeOpt))
        (pidContent (resultOr (fileReadString cfg.pidFile) ""))
        (pid (optionOr (stringToInt64 (stringTrim pidContent)) 0))
        (alive (if (> pid 0) (resultOr (procAlive? pid) false) false))]
    (if alive
      (let [(rss (grd/sampleCurrentRssMb!))]
        (w/formatCliStatusActive pid cfg.scope cfg.socketPath rss cfg.maxRssMb cfg.pidFile))
      (w/formatCliStatusStopped cfg.scope cfg.socketPath cfg.pidFile)))
fn cmdPing! rootDir: String scopeOpt: String -> String
  (let [(cfg (resolveScope! rootDir scopeOpt))
        (pidContent (resultOr (fileReadString cfg.pidFile) ""))
        (pid (optionOr (stringToInt64 (stringTrim pidContent)) 0))
        (alive (if (> pid 0) (resultOr (procAlive? pid) false) false))
        (sockStat (fileStat cfg.socketPath))]
    (if (and alive (ok? sockStat))
      (w/formatPongOk pid 0 cfg.scope)
      (w/formatPongOffline cfg.scope)))
fn cmdStart! rootDir: String scopeOpt: String foreground: Bool force: Bool -> (Result EngineRuntime String)
  (let [(cfg (resolveScope! rootDir scopeOpt))
        (isDarwin (mt (platformInfo) ((ok p) (= p.os "Darwin")) ((err _) true)))
        (pathCheck (checkSocketPath cfg.socketPath isDarwin))]
    (mt pathCheck
      ((err e)
        (err e))
      ((ok _)
        (let [(leaseRes (lse/acquireLease! cfg.socketPath))]
          (mt leaseRes
            ((err e)
              (err e))
            ((ok lease)
              (let [(nowSec (/ (nowNs) 1000000000))
                    (_ (fileWrite cfg.pidFile (stringFromInt64 (procSelf))))
                    (rt (makeEngineRuntime cfg nowSec))]
                (ok (EngineRuntime :config cfg
                                   :supervisor rt.supervisor
                                   :activity rt.activity
                                   :lease lease
                                   :startTimeSec nowSec
                                   :build rt.build)))))))))
fn cmdStop! rootDir: String scopeOpt: String -> String
  (let [(cfg (resolveScope! rootDir scopeOpt))
        (pidContent (resultOr (fileReadString cfg.pidFile) ""))
        (pid (optionOr (stringToInt64 (stringTrim pidContent)) 0))]
    (if (> pid 0)
      (let [(_ (procKill pid "SIGTERM"))
            (_ (sleepMs 100))
            (_ (procKill pid "SIGKILL"))
            (_ (pathRemove cfg.pidFile))
            (_ (pathRemove cfg.socketPath))]
        (str "✓ ASL Engine stopped (Scope: " cfg.scope ")."))
      (let [(_ (pathRemove cfg.socketPath))]
        (str "ASL Engine is not running (Scope: " cfg.scope ")."))))
fn cmdRestart! rootDir: String scopeOpt: String force: Bool -> (Result String String)
  (let [(cfg (resolveScope! rootDir scopeOpt))
        (brkRes (brk/checkBreakerFile! cfg.socketPath force cfg.logFile))]
    (mt brkRes
      ((err e)
        (err e))
      ((ok _)
        (let [(_ (cmdStop! rootDir scopeOpt))
              (startRes (cmdStart! rootDir scopeOpt false force))]
          (mt startRes
            ((err e)
              (err e))
            ((ok rt)
              (ok (str "✓ ASL Engine restarted cleanly on " cfg.socketPath " (PID " (stringFromInt64 (procSelf)) ", Scope: " cfg.scope ")."))))))))
fn cmdRun! rootDir: String scopeOpt: String -> (Result EngineRuntime String)
  (cmdStart! rootDir scopeOpt true false)
fn cmdEval! aslBin: String expr: String -> ProcessOutput
  (tp/runEngineEval! aslBin expr)