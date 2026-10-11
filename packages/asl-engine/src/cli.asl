(module asl-engine/cli
  :x [main CliArgs parseArgs helpText versionText]
  :i [(asl-engine/engine :a eng)
      (asl-engine/server :a srv)
      (asl-engine/build :a bld)
      (asl-engine/breaker :a brk)
      (asl-engine/transport :a tp)
      (asl-engine/wire :a w)])

(schema CliArgs
  (:f root String)
  (:f scope String)
  (:f foreground Bool)
  (:f force Bool)
  (:f rest (List String)))

fn versionText -> String
  "asl-engine 0.1.0 (Resident Engine & Context Isolation Supervisor, ADR0081/D120)"

fn helpText -> String
  (stringJoin (list "asl-engine: Sovereign Resident Engine & Context Isolation Supervisor"
                    "Authority: ADR0081 / D102 / D120"
                    ""
                    "Usage: asl engine [command|option] [args...]"
                    ""
                    "Commands:"
                    "  status                      Print current engine status, scope, memory RSS, and channels"
                    "  start                       Start the resident engine supervisor"
                    "  stop                        Stop active engine and clean socket/PID files"
                    "  restart                     Bounce active engine gracefully and restart"
                    "  ping                        Test engine connectivity and responsiveness over UNIX socket"
                    "  run                         Run engine in foreground"
                    "  eval <expr>                 Evaluate pure ASL expression in engine context"
                    ""
                    "Options:"
                    "  --root <dir>                Workspace root (default: the toolchain root)"
                    "  --scope <workspace|system|task-<id>>  Target engine scope (default: workspace if inside repo)"
                    "  -f, --foreground            Run in foreground mode"
                    "  --force                     Force termination on restart/stop and bypass circuit breaker"
                    "  -v, --version               Print version information"
                    "  -h, --help                  Show this help message"
                    ""
                    "Environment Variables:"
                    "  ASL_ENGINE_SCOPE            Default scope (workspace, system, task-<id>)"
                    "  ASL_ENGINE_SOCKET           Path to UNIX domain socket"
                    "  ASL_ENGINE_PID_FILE         Path to PID file"
                    "  ASL_ENGINE_IDLE_SEC         Daemon idle exit timeout in seconds (default: 900)"
                    "  ASL_ENGINE_UPDATE_SEC       Source version check period in seconds (default: 30, 0 disables)"
                    "  ASL_ENGINE_MAX_RSS_MB       Hard memory RSS limit in MB (default: 512)"
                    "  ASL_ENGINE_SOFT_RSS_MB      Soft memory RSS limit in MB (default: 384)"
                    "  ASL_ENGINE_ENTRY            This entry, set by asl engine; the daemon and self-update run it"
                    "  ASL_HOST                    runner binary (native CLI or built stage-0) that runs the entry")
              "\n")

fn afterEq s: String -> String
  (mt (stringIndexOf s "=") ((some i) (optionOr (stringSlice s (+ i 1) (stringLength s)) "")) ((none) ""))

fn parseArgs args: (List String) acc: CliArgs -> CliArgs
  (mt (listHead args)
    ((none) (with acc :rest (listReverse acc.rest)))
    ((some a)
      (let [(more (optionOr (listTail args) (list)))
            (next (optionOr (listHead more) ""))
            (afterNext (optionOr (listTail more) (list)))]
        (cond
          ((and (= a "--root") (not (listEmpty? more)))
            (parseArgs afterNext (with acc :root next)))
          ((stringStartsWith? a "--root=")
            (parseArgs more (with acc :root (afterEq a))))
          ((and (= a "--scope") (not (listEmpty? more)))
            (parseArgs afterNext (with acc :scope next)))
          ((stringStartsWith? a "--scope=")
            (parseArgs more (with acc :scope (afterEq a))))
          ((or (= a "-f") (= a "--foreground"))
            (parseArgs more (with acc :foreground true)))
          ((= a "--force")
            (parseArgs more (with acc :force true)))
          (else
            (parseArgs more (with acc :rest (cons a acc.rest))))))))

fn say! text: String -> Int64
  (do (println text) 0)

fn sayErr! text: String code: Int64 -> Int64
  (do (eprintln text) code)

fn ! pidOf! cfg: eng/EngineConfig -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString cfg.pidFile) ""))) 0)

fn ! alive! pid: Int64 -> Bool
  (and (> pid 1) (resultOr (procAlive? pid) false))

fn ! exists! path: String -> Bool
  (ok? (fileStat path))

fn ! waitGone! pid: Int64 tries: Int64 -> Bool
  (cond
    ((not (alive! pid)) true)
    ((<= tries 0) false)
    (else (do (sleepMs 100) (waitGone! pid (- tries 1)))))

fn ! waitSocket! path: String pid: Int64 tries: Int64 -> Bool
  (cond
    ((exists! path) true)
    ((<= tries 0) false)
    (else
      (mt (procWaitPid pid true)
        ((ok got) (if (some? got) false (do (sleepMs 100) (waitSocket! path pid (- tries 1)))))
        ((err _) (do (sleepMs 100) (waitSocket! path pid (- tries 1)))))))

fn statusField answer: String key: String -> String
  (mt (stringIndexOf answer (str ":" key " "))
    ((none) "")
    ((some i)
      (let [(tail (optionOr (stringSlice answer (+ i (+ (stringLength key) 2)) (stringLength answer)) ""))]
        (mt (stringIndexOf tail " ")
          ((some k) (optionOr (stringSlice tail 0 k) ""))
          ((none) (stringReplace tail ")" ""))))))

fn ! daemonRssMb! cfg: eng/EngineConfig -> Int64
  (mt (tp/socketExchange! cfg.socketPath "(:engine :action status)" 2000)
    ((err _) 0)
    ((ok answer)
      (let [(raw (statusField answer "rssMb"))
            (whole (mt (stringIndexOf raw ".") ((some i) (optionOr (stringSlice raw 0 i) "")) ((none) raw)))]
        (optionOr (stringToInt64 whole) 0))))

fn ! status! cfg: eng/EngineConfig -> Int64
  (let [(pid (pidOf! cfg))]
    (if (alive! pid)
      (say! (w/formatCliStatusActive pid cfg.scope cfg.socketPath (daemonRssMb! cfg) cfg.maxRssMb cfg.pidFile))
      (say! (w/formatCliStatusStopped cfg.scope cfg.socketPath cfg.pidFile))))

fn ! ping! cfg: eng/EngineConfig -> Int64
  (if (and (exists! cfg.socketPath) (alive! (pidOf! cfg)))
    (mt (tp/socketExchange! cfg.socketPath "(:ping)" 10000)
      ((ok answer) (say! (stringTrim answer)))
      ((err e) (do (say! (w/formatPongUnresponsive e)) 1)))
    (say! (w/formatPongOffline cfg.scope)))

fn setEnvRow rows: (List String) key: String val: String -> (List String)
  (cons (str key "=" val) (filter (fn [(r String)] -> Bool (not (stringStartsWith? r (str key "=")))) rows))

fn isDarwin! -> Bool
  (mt (platformInfo) ((ok p) (= p.os "Darwin")) ((err _) true))

fn ! spawnDaemon! cfg: eng/EngineConfig build: bld/EngineBuild root: String -> (Result Int64 String)
  (let [(env (setEnvRow (setEnvRow (envList) "ASL_ENGINE_ENTRY" build.entry) "ASL_HOST" build.host))
        (argv (list build.host "run" build.entry "run" "--root" root "--scope" cfg.scope))]
    (mt (procSpawnv argv (some root) (some env))
      ((err e) (err (str "ERR_ENGINE_START: cannot run " build.host ": " (tp/socketErrorText! e))))
      ((ok child)
        (let [(_ (fdClose child.stdin))
              (_ (fdClose child.stdout))
              (_ (fdClose child.stderr))
              (pid child.pid)]
          (if (waitSocket! cfg.socketPath pid 50)
            (ok pid)
            (err (str "ERR_ENGINE_START: the engine (PID " (stringFromInt64 pid) ") did not bind " cfg.socketPath "; see " cfg.logFile)))))))

fn ! foreground! cfg: eng/EngineConfig build: bld/EngineBuild root: String -> Int64
  (do (println (str "Starting ASL Engine (foreground) on " cfg.socketPath " (Scope: " cfg.scope ")..."))
      (mt (srv/serve! root cfg.scope build)
        ((ok reason) (do (println (str "ASL Engine exited: " reason)) 0))
        ((err e) (sayErr! e 1))))

fn ! preflight! cfg: eng/EngineConfig build: bld/EngineBuild -> (Result Unit String)
  (cond
    ((err? (eng/checkSocketPath cfg.socketPath (isDarwin!)))
      (mt (eng/checkSocketPath cfg.socketPath (isDarwin!)) ((err e) (err e)) ((ok _) (ok ()))))
    ((stringEmpty? build.entry) (err "ERR_ENGINE_ENTRY: set ASL_ENGINE_ENTRY to asl/packages/asl-engine/src/cli.asl or run from the toolchain root"))
    ((stringEmpty? build.host) (err "ERR_ENGINE_HOST: no runner; set ASL_HOST or build asl/host"))
    (else (ok ())))

fn ! start! cfg: eng/EngineConfig build: bld/EngineBuild root: String fg: Bool -> Int64
  (let [(pid (pidOf! cfg))
        (sock cfg.socketPath)]
    (if (and (> pid 0) (alive! pid) (exists! sock))
      (say! (str "Starting ASL Engine on " sock "...\n"
                "ASL Engine is already active (PID " (stringFromInt64 pid) ", Scope: " cfg.scope ", Socket: " sock ").\n"
                "Use 'asl engine restart' to bounce or 'asl engine status' to inspect."))
      (let [(_ (if (and (exists! cfg.pidFile) (not (alive! pid)))
                 (do (println (str "[Notice] Cleaning stale PID file (" cfg.pidFile ") and socket (" sock ")..."))
                     (pathRemove cfg.pidFile)
                     (pathRemove sock))
                 (ok ())))]
        (mt (preflight! cfg build)
          ((err e) (sayErr! e 2))
          ((ok _)
            (if fg
              (foreground! cfg build root)
              (mt (spawnDaemon! cfg build root)
                ((err e) (sayErr! e 1))
                ((ok child)
                  (say! (str "Starting ASL Engine on " sock " (PID " (stringFromInt64 child) ")...\n"
                            "ASL Engine active in " cfg.scope " scope (PID " (stringFromInt64 child) ", socket: " sock ")."))))))))))

fn ! halt! cfg: eng/EngineConfig pid: Int64 -> Bool
  (let [(_ (tp/socketExchange! cfg.socketPath "(:engine :action stop)" 1000))]
    (cond
      ((waitGone! pid 25) true)
      (else
        (let [(_ (procKill pid "SIGTERM"))]
          (if (waitGone! pid 25)
            true
            (do (procKill pid "SIGKILL") (waitGone! pid 10)))))))

fn ! stop! cfg: eng/EngineConfig -> Int64
  (let [(pid (pidOf! cfg))]
    (if (exists! cfg.pidFile)
      (let [(_ (if (alive! pid) (halt! cfg pid) true))
            (_ (pathRemove cfg.pidFile))
            (_ (pathRemove cfg.socketPath))]
        (say! (str "✓ ASL Engine stopped (Scope: " cfg.scope ").")))
      (let [(_ (pathRemove cfg.socketPath))]
        (say! (str "ASL Engine is not running (Scope: " cfg.scope ").")))))

fn ! restart! cfg: eng/EngineConfig build: bld/EngineBuild root: String force: Bool -> Int64
  (mt (brk/checkBreakerFile! cfg.socketPath force cfg.logFile)
    ((err e) (sayErr! e 1))
    ((ok _)
      (let [(_ (println (str "Restarting ASL Engine (Scope: " cfg.scope ")...")))
            (pid (pidOf! cfg))
            (_ (if (alive! pid) (halt! cfg pid) true))
            (_ (pathRemove cfg.pidFile))
            (_ (pathRemove cfg.socketPath))]
        (mt (preflight! cfg build)
          ((err e) (sayErr! e 2))
          ((ok _)
            (mt (spawnDaemon! cfg build root)
              ((err e) (sayErr! e 1))
              ((ok child)
                (say! (str "✓ ASL Engine restarted cleanly on " cfg.socketPath " (PID " (stringFromInt64 child) ", Scope: " cfg.scope ").")))))))))

fn ! eval! build: bld/EngineBuild exprs: (List String) -> Int64
  (if (stringEmpty? build.host)
    (sayErr! "ERR_ENGINE_HOST: no runner; set ASL_HOST or build asl/host" 2)
    (mt (procExecv (list build.host "eval" (stringJoin exprs " ")) (none))
      ((ok _) 0)
      ((err e) (sayErr! (str "asl engine eval: cannot exec " build.host ": " e) 126))))

fn ! resolveRoot! given: String toolRoot: String -> String
  (let [(raw (cond ((not (stringEmpty? given)) given) ((not (stringEmpty? toolRoot)) toolRoot) (else ".")))]
    (resultOr (realPath raw) raw))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(a (parseArgs args (CliArgs :root "" :scope "" :foreground false :force false :rest (list))))
        (cmd (optionOr (listHead a.rest) "status"))
        (build (bld/makeBuild! (bld/entryPath!)))
        (root (resolveRoot! a.root build.toolRoot))
        (scope (if (stringEmpty? a.scope) (optionOr (envGet "ASL_ENGINE_SCOPE") "") a.scope))
        (cfg (eng/resolveScope! root scope))]
    (ok (cond
          ((listContains? (list "-v" "--version" "version") cmd) (say! (versionText)))
          ((listContains? (list "-h" "--help" "help") cmd) (say! (helpText)))
          ((= cmd "status") (status! cfg))
          ((= cmd "ping") (ping! cfg))
          ((= cmd "start") (start! cfg build root (or a.foreground (listContains? (list "--foreground" "-f") (optionOr (listGet a.rest 1) "")))))
          ((= cmd "run") (start! cfg build root true))
          ((= cmd "stop") (stop! cfg))
          ((= cmd "restart") (restart! cfg build root a.force))
          ((= cmd "eval") (eval! build (optionOr (listTail a.rest) (list))))
          (else (sayErr! "Usage: asl engine {status|start|stop|restart|ping|run|eval|--version|--help}" 1)))))
