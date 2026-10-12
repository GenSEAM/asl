(module asl-cli/nativeCli
  :x [cacheDir! headPath underRoot fresh? verbKind nativeGate! hostEntry!]
  :i [(asl/packages/asl-cli/src/system :a sys)])

fn ! cacheDir! -> String
  (let [(configured (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (home (optionOr (envGet "HOME") ""))]
    (cond
      ((not (stringEmpty? configured)) configured)
      ((stringEmpty? home) "/tmp/.asl/run/nativeCli")
      (else (str home "/.asl/run/nativeCli"))))

fn headPath cache: String root: String -> String
  (str cache "/head" (stringReplace root "/" "_"))

fn verbKind args: (List String) -> String
  (let [(verb (optionOr (listHead args) "help"))]
    (cond
      ((or (listContains? (list "run" "test" "parse" "eval" "launch") verb) (stringEndsWith? verb ".asl")) "native")
      ((or (stringStartsWith? verb "(")
           (or (stringStartsWith? verb ":")
               (listContains? (list "rpc" "intel" "coupling" "graph" "complexity" "vitality" "full" "stubs" "trace"
                                     "crawler" "crawl" "engine" "mesh" "version" "-v" "--version") verb)))
        "forms")
      (else "host")))

fn ! direct? -> Bool
  (= (optionOr (envGet "ASL_CLI_ENTRY_PID") "") (stringFromInt64 (procSelf)))

fn underRoot root: String path: String -> String
  (if (stringStartsWith? path "/") path (str root "/" path))

fn ! sameBytes? a: String b: String -> Bool
  (mt (fileReadBytes a)
    ((err _) false)
    ((ok x) (mt (fileReadBytes b) ((err _) false) ((ok y) (= x y)))))

fn ! allSame? root: String dir: String paths: (List String) -> Bool
  (mt (listHead paths)
    ((none) true)
    ((some p) (if (sameBytes? (underRoot root p) (str dir "/src/" p)) (allSame? root dir (optionOr (listTail paths) (list))) false)))

fn ! fresh? root: String dir: String -> Bool
  (if (or (stringEmpty? dir) (not (sys/executable? (str dir "/bin"))))
    false
    (mt (fileRead (str dir "/deps"))
      ((err _) false)
      ((ok text) (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
                   (if (listEmpty? paths) false (allSame? root dir paths))))))

fn envName row: String -> String
  (mt (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn ! execWith! argv: (List String) drop: (List String) extra: (List String) -> Int64
  (let [(names (listAppend drop (map envName extra)))
        (kept (filter (fn [(row String)] -> Bool (not (listContains? names (envName row)))) (envList)))]
    (mt (procExecv argv (some (listAppend kept extra)))
      ((ok _) 0)
      ((err e) (do (sys/sayErr! (str "asl: cannot exec " (optionOr (listHead argv) "") ": " e)) (if (= e "notFound") 127 126)))))

fn ! hostExec! ctx: sys/Context args: (List String) extra: (List String) -> Int64
  (if (sys/executable? ctx.hostBin)
    (execWith! (listAppend (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/command.asl")) args) (list "ASL_NATIVE_CLI_DIR" "ASL_NATIVE_QUIET_PID") extra)
    (do (sys/say! "(:asl :status :failed :error ERR_HOST_ABSENT :message \"asl runs on the stage-0 host at asl/host/out/asl-host; build it with sh asl/host/build.sh or set ASL_HOST\")") 2))

fn ! nativeGate! ctx: sys/Context args: (List String) -> (Option Int64)
  (let [(dir (optionOr (envGet "ASL_NATIVE_CLI_DIR") ""))]
    (cond
      ((not (direct?)) (none))
      ((= (verbKind args) "host") (some (hostExec! ctx args (list))))
      ((or (stringEmpty? dir) (fresh? ctx.root dir)) (none))
      (else (some (hostExec! ctx args (list (str "ASL_NATIVE_CLI_STALE=" dir)))))))

fn ! heldPid lock: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileRead (str lock "/pid")) ""))) 0)

fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (resultOr (procAlive? pid) false))

fn detachScript -> String
  "perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' \"$@\" < /dev/null >> \"$NATIVE_CLI_LOG\" 2>&1 & echo $!"

fn ! spawnBuilder! ctx: sys/Context cache: String lock: String -> String
  (let [(log (str cache "/build.log"))
        (native (str ctx.root "/asl/host/out/aslNativeBuild"))
        (builder (if (sys/executable? native) (list native) (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/nativeBuild.asl"))))
        (argv (listAppend (list "/bin/sh" "-c" (detachScript) "sh" "nice" "-n" "15") (listAppend builder (list ctx.root cache "--lock-owner" (stringFromInt64 (procSelf))))))
        (d (mt (sys/captureWith! argv (some ctx.root) (list (str "NATIVE_CLI_LOG=" log)))
             ((ok c) c)
             ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))))
        (pid (optionOr (stringToInt64 (stringTrim d.stdout)) 0))
        (part (str lock "/pid.part"))]
    (if (or (!= d.exitCode 0) (<= pid 1))
      (do (pathRemove lock) (str "its build did not start: " (stringReplace (stringTrim (str d.stdout " " d.stderr)) "\n" " ")))
      (do (mt (fileWrite part (str (stringFromInt64 pid) "\n")) ((ok _) (pathRename part (str lock "/pid"))) ((err e) (err e)))
          (str "its build started in the background (log " log ")"))))

fn ! startBuild! ctx: sys/Context cache: String tries: Int64 last: String -> String
  (let [(lock (str cache "/lock"))]
    (if (<= tries 0)
      last
      (mt (dirCreate lock)
        ((err e) (str "cannot create " lock ": " e))
        ((ok _) (mt (fileCreateExclusive (str lock "/pid") (str (stringFromInt64 (procSelf)) "\n"))
          ((ok _) (spawnBuilder! ctx cache lock))
          ((err e) (let [(held (heldPid lock))]
                     (if (alive? held)
                       (str "pid " (stringFromInt64 held) " is building it")
                       (do (pathRemove lock) (startBuild! ctx cache (- tries 1) "a stale build lock was cleared"))))))))))

fn ! waitBuild! lock: String deadlineNs: Int64 -> Bool
  (if (and (alive? (heldPid lock)) (< (monotonicNs) deadlineNs))
    (do (sleepMs 1000) (waitBuild! lock deadlineNs))
    true)

fn ! execNative! ctx: sys/Context dir: String args: (List String) -> String
  (let [(code (execWith! (cons (str dir "/bin") args) (list) (list (str "ASL_NATIVE_CLI_DIR=" dir) (str "ASL_NATIVE_QUIET_PID=" (stringFromInt64 (procSelf))))))]
    (str "exec of " dir "/bin failed with " (stringFromInt64 code)))

fn ! timeoutS! -> Int64
  (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_CLI_TIMEOUT") "")) 1800)

fn ! headDir! cache: String root: String -> String
  (stringTrim (resultOr (fileRead (headPath cache root)) ""))

fn ! awaitNative! ctx: sys/Context cache: String stale: String args: (List String) rounds: Int64 -> String
  (let [(_ (waitBuild! (str cache "/lock") (+ (monotonicNs) (* (+ (timeoutS!) 60) 1000000000))))
        (built (headDir! cache ctx.root))]
    (cond
      ((and (!= built stale) (fresh? ctx.root built)) (execNative! ctx built args))
      ((<= rounds 1) (str "its build did not finish (see " cache "/build.log)"))
      (else (do (startBuild! ctx cache 2 "") (awaitNative! ctx cache stale args (- rounds 1))))))

fn ! nativeWhy! ctx: sys/Context args: (List String) -> String
  (let [(cache (cacheDir!))
        (stale (optionOr (envGet "ASL_NATIVE_CLI_STALE") ""))
        (dir (headDir! cache ctx.root))]
    (cond
      ((not (sys/isFile? (str ctx.root "/asl/host/out/libaslrt.a"))) "asl/host/out/libaslrt.a is absent (sh asl/host/build.sh)")
      ((and (!= dir stale) (fresh? ctx.root dir)) (execNative! ctx dir args))
      (else
        (let [(why (startBuild! ctx cache 2 ""))]
          (cond
            ((not (stringEmpty? (optionOr (envGet "ASL_NATIVE_CLI_WAIT") ""))) (awaitNative! ctx cache stale args 3))
            ((stringEmpty? stale) why)
            (else (str "the cached binary predates its sources and " why)))))))

fn ! hostEntry! ctx: sys/Context args: (List String) -> Unit
  (let [(verb (optionOr (listHead args) "help"))
        (kind (verbKind args))]
    (cond
      ((or (not (direct?)) (!= (optionOr (envGet "ASL_CLI_HOST_UNSET") "") "1")) ())
      ((= kind "host") (do (eprintln (str "asl: " verb " is not native yet, so it runs on asl-host")) ()))
      ((= kind "native") (do (eprintln (str "asl: " verb " runs on asl-host: no native toolchain, " (nativeWhy! ctx args))) ()))
      (else ())))
