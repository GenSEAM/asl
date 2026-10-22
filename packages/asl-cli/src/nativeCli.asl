(module asl-cli/nativeCli
  :x [cacheDir! headPath underRoot clangFacts! fresh? probe? alive? verbKind nativeGate! hostEntry!]
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
      ((or (listContains? (list "run" "test" "parse" "eval" "launch" "check") verb) (stringEndsWith? verb ".asl")) "native")
      ((or (stringStartsWith? verb "(")
           (or (stringStartsWith? verb ":")
               (listContains? (list "rpc" "intel" "coupling" "graph" "complexity" "vitality" "full" "stubs" "trace"
                                     "crawler" "crawl" "engine" "mesh" "train" "version" "-v" "--version"
                                     "build" "audit" "pack" "target" "help" "-h" "--help"
                                     "note" "doc" "heal" "lens" "consilium" "browser" "web" "search" "research"
                                     "gateway" "relay" "rla" "mem" "tool" "lint" "gate" "-" "-f") verb)))
        "forms")
      (else "host")))

fn ! direct? -> Bool
  (= (optionOr (envGet "ASL_CLI_ENTRY_PID") "") (stringFromInt64 (procSelf)))

fn underRoot root: String path: String -> String
  (if (stringStartsWith? path "/") path (str root "/" path))

fn ! sameBytes? a: String b: String -> Bool
  (match (fileReadBytes a)
    ((err _) false)
    ((ok x) (match (fileReadBytes b) ((err _) false) ((ok y) (= x y)))))

fn ! allSame? root: String dir: String paths: (List String) -> Bool
  (match (listHead paths)
    ((none) true)
    ((some p) (if (sameBytes? (underRoot root p) (str dir "/src/" p)) (allSame? root dir (optionOr (listTail paths) (list))) false)))

fn ! shQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! boundedCapture! cmd: String timeoutMs: Int64 -> sys/Captured
  (match (processSpawn cmd)
    ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))
    ((ok h) (match (processWait h timeoutMs)
              ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))
              ((ok o) (sys/Captured :exitCode o.exitCode :stdout o.stdout :stderr o.stderr)))))

; (:m :ref BIN-ASL-FORKS :do "the warm path needs clang's version and target triple on every call (the CLI freshness gate, the nativeTest fingerprint); spawning clang for them forks, so where no child can start (ulimit -u, a full process table) a warm call failed. The facts are recorded once per clang identity, the stat of the clang command and of the Xcode toolchain it dispatches to plus CLANG, DEVELOPER_DIR and the xcode-select link, and read back without a spawn; an unreadable record spawns clang as before and a failed spawn records nothing")
fn ! clangCommand! -> String
  (optionOr (envGet "CLANG") "clang")

fn ! statStamp path: String -> String
  (match (fileStat path)
    ((ok st) (str path " " (stringFromInt64 st.size) " " (stringFromInt64 st.mtimeNs)))
    ((err _) (str path " absent")))

fn ! clangIdentity! -> String
  (let [(cmd (clangCommand!))
        (found (if (stringContains? cmd "/") cmd (optionOr (sys/onPath! cmd) cmd)))
        (developer (optionOr (envGet "DEVELOPER_DIR") (resultOr (realPath "/var/db/xcode_select_link") "")))]
    (stringJoin (list (str "CLANG=" cmd) (str "DEVELOPER_DIR=" developer)
                      (statStamp found) (statStamp (resultOr (realPath found) found))
                      (statStamp (str developer "/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"))
                      (statStamp (str developer "/usr/bin/clang")))
                "\n"))

fn ! firstLine! cmd: String -> (Option String)
  (let [(o (boundedCapture! cmd 10000))
        (line (stringTrim (optionOr (listHead (stringLines o.stdout)) "")))]
    (if (and (= o.exitCode 0) (not (stringEmpty? line))) (some line) (none)))

fn ! recordClang! path: String version: String triple: String -> Bool
  (let [(made (dirCreate (str (cacheDir!) "/clang")))
        (part (str path ".part." (stringFromInt64 (procSelf))))]
    (match (fileWrite part (str version "\n" triple "\n"))
      ((err e) (sys/sayErr! (str "asl: cannot record clang facts at " part ": " e (match made ((err m) (str " (" m ")")) ((ok _) "")))))
      ((ok _) (match (pathRename part path)
                ((err e) (let [(gone (pathRemove part))]
                           (sys/sayErr! (str "asl: cannot record clang facts at " path ": " e (if (err? gone) (str "; " part " stays") "")))))
                ((ok _) true)))))

fn ! clangFacts! -> (List String)
  (let [(path (str (cacheDir!) "/clang/" (bytesSha256 (stringToBytes (clangIdentity!)))))
        (recorded (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString path) ""))))]
    (if (= (listLength recorded) 2)
      recorded
      (let [(q (shQuote (clangCommand!)))]
        (match (firstLine! (str q " --version"))
          ((none) (list))
          ((some version) (match (firstLine! (str q " -dumpmachine"))
                            ((none) (list))
                            ((some triple) (do (recordClang! path version triple) (list version triple)))))))))

fn ! fresh? root: String dir: String -> Bool
  (if (or (stringEmpty? dir) (not (sys/executable? (str dir "/bin"))))
    false
    (match (fileReadString (str dir "/clang-version"))
      ((err _) false)
      ((ok expected) (let [(actual (optionOr (listHead (clangFacts!)) ""))]
        (and (not (stringEmpty? actual))
          (and (= (stringTrim expected) actual)
            (match (fileReadString (str dir "/deps"))
              ((err _) false)
              ((ok text) (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
                           (if (listEmpty? paths) false (allSame? root dir paths)))))))))))

fn ! probe? root: String dir: String -> Bool
  (let [(cmd (str "cd " (shQuote root) " && ASL_CLI_ROOT=" (shQuote root) " ASL_CLI_SCRIPT_DIR=" (shQuote (str root "/bin")) " ASL_CLI_ARGV0=" (shQuote (str root "/bin/asl")) " ASL_CLI_ENTRY_PID=$$ ASL_NATIVE_CLI_DIR=" (shQuote dir) " ASL_NATIVE_QUIET_PID=$$ exec " (shQuote (str dir "/bin")) " test " (shQuote (str root "/asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl"))))
        (result (boundedCapture! cmd 30000))]
    (if (and (= result.exitCode 0)
          (and (stringContains? result.stdout "passTest.asl: 1 assertion(s) executed") (not (stringContains? result.stdout "asl-host"))))
      true
      (do (sys/sayErr! (str "native CLI self-probe: exit=" (stringFromInt64 result.exitCode) " stdout=" result.stdout " stderr=" result.stderr)) false)))

fn envName row: String -> String
  (match (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn ! execWith! argv: (List String) drop: (List String) extra: (List String) -> Int64
  (let [(names (listAppend drop (map envName extra)))
        (kept (filter (fn [(row String)] -> Bool (not (listContains? names (envName row)))) (envList)))]
    (match (procExecv argv (some (listAppend kept extra)))
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
      (else (some (awaitStaleRebuild! ctx dir args)))))

fn leadingDigitsAt s: String n: Int64 i: Int64 -> String
  (if (and (< i n) (stringContains? "0123456789" (optionOr (stringSlice s i (+ i 1)) "x")))
    (leadingDigitsAt s n (+ i 1))
    (optionOr (stringSlice s 0 i) ""))

fn leadingDigits s: String -> String
  (leadingDigitsAt s (stringLength s) 0)

fn configInt text: String key: String -> (Option Int64)
  (match (stringIndexOf text (str ":" key " "))
    ((none) (none))
    ((some i) (let [(after (+ i (+ (stringLength key) 2)))
                    (digits (leadingDigits (stringTrim (optionOr (stringSlice text after (stringLength text)) ""))))]
                (if (stringEmpty? digits) (none) (stringToInt64 digits)))))

; (:m :ref NATIVE-STALE-CONVERGE :do "ASL_NATIVE_BUILD_WAIT stays as the override an existing test (binAslStaleTest.asl, nativeStaleHeadTest.asl) injects to force a short, deterministic wait deadline without rewriting .asl.config.asn per case; when unset, the deadline comes from .asl.config.asn's :nativeCli :buildWaitS, falling back to 3600 only if the config file itself is absent or lacks the key (a stripped-down tree)")
fn ! buildWaitS! ctx: sys/Context -> Int64
  (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_BUILD_WAIT") ""))
    (optionOr (configInt (resultOr (fileReadString (str ctx.root "/.asl.config.asn")) "") "buildWaitS") 3600))

fn ! awaitStaleRebuild! ctx: sys/Context stale: String args: (List String) -> Int64
  (let [(cache (cacheDir!))
        (startMsg (startBuild! ctx cache 2 ""))
        (waitS (buildWaitS! ctx))
        (_ (eprintln (str "asl: native CLI predates its sources (" stale "); " startMsg "; waiting up to " (stringFromInt64 waitS) "s for the rebuild (.asl.config.asn :nativeCli :buildWaitS, or ASL_NATIVE_BUILD_WAIT)")))
        (deadline (+ (monotonicNs) (* waitS 1000000000)))
        (why (awaitNative! ctx cache stale args deadline))]
    (do (sys/say! (str "(:asl :status :failed :error ERR_NATIVE_STALE :message \"" why "; see " cache "/build.log\")")) 2))

fn ! heldPid lock: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str lock "/pid")) ""))) 0)

fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (resultOr (procAlive? pid) false))

fn detachScript -> String
  "perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' \"$@\" < /dev/null >> \"$NATIVE_CLI_LOG\" 2>&1 & echo $!"

fn ! nativeBuildReady? ctx: sys/Context native: String freshMark: String -> Bool
  (if (and (sys/executable? native) (fresh? ctx.root freshMark))
    true
    (do (boundedCapture! (str "sh " (shQuote (str ctx.root "/asl/host/build.sh"))) 600000)
        (and (sys/executable? native) (fresh? ctx.root freshMark))))


; (:m :ref NATIVE-STALE-CONVERGE :do "no longer passes --lock-owner: the shared ~/.asl/run/nativeCli/build.log showed a cascading 'owner-gone' retry storm (16 lines in 66) against the main checkout, traced to aslNativeBuild's own --lock-owner liveness check self-aborting a detached build the instant its SHORT-LIVED triggering CLI invocation (a bounded test/harness call, routinely shorter than a from-scratch asl1+CLI bootstrap) exited, which then made the next caller see a dead lock/pid and restart the whole build from zero, forever; the lock dir's own pid (the detached build process itself, tracked via heldPid/alive? in waitBuild!) is the trustworthy liveness signal and the build's own deadlineNs already bounds a truly orphaned run, so no separate owner-liveness coupling is needed for the common case of a build outliving its triggering caller")
fn ! spawnBuilder! ctx: sys/Context cache: String lock: String -> String
  (let [(log (str cache "/build.log"))
        (native (str ctx.root "/asl/host/out/aslNativeBuild"))
        (freshMark (str ctx.root "/asl/host/out/aslNativeBuild-fresh"))]
    (if (not (nativeBuildReady? ctx native freshMark))
      (do (pathRemove lock) "its build helper is stale and the hostless refresh (sh asl/host/build.sh) did not restore it")
      (let [(argv (listAppend (list "/bin/sh" "-c" (detachScript) "sh" "nice" "-n" "15") (list native ctx.root cache)))
            (d (match (sys/captureWith! argv (some ctx.root) (list (str "NATIVE_CLI_LOG=" log)))
                 ((ok c) c)
                 ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))))
            (pid (optionOr (stringToInt64 (stringTrim d.stdout)) 0))
            (part (str lock "/pid.part"))]
        (if (or (!= d.exitCode 0) (<= pid 1))
          (do (pathRemove lock) (str "its build did not start: " (stringReplace (stringTrim (str d.stdout " " d.stderr)) "\n" " ")))
          (do (match (fileWrite part (str (stringFromInt64 pid) "\n")) ((ok _) (pathRename part (str lock "/pid"))) ((err e) (err e)))
              (str "its build started in the background (log " log ")"))))))

fn ! startBuild! ctx: sys/Context cache: String tries: Int64 last: String -> String
  (let [(lock (str cache "/lock"))]
    (if (<= tries 0)
      last
      (match (dirCreate lock)
        ((err e) (str "cannot create " lock ": " e))
        ((ok _) (match (fileCreateExclusive (str lock "/pid") (str (stringFromInt64 (procSelf)) "\n"))
          ((ok _) (spawnBuilder! ctx cache lock))
          ((err e) (let [(held (heldPid lock))]
                     (if (alive? held)
                       (str "pid " (stringFromInt64 held) " is building it")
                       (do (pathRemove lock) (startBuild! ctx cache (- tries 1) "a stale build lock was cleared"))))))))))

fn ! waitBuild! lock: String deadlineNs: Int64 -> Bool
  (let [(owner (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str lock "/owner")) ""))) 0))]
  (if (and (alive? (heldPid lock)) (or (= owner 0) (alive? owner)) (< (monotonicNs) deadlineNs))
    (do (sleepMs 1000) (waitBuild! lock deadlineNs))
    true))

fn ! execNative! ctx: sys/Context dir: String args: (List String) -> String
  (let [(code (execWith! (cons (str dir "/bin") args) (list) (list (str "ASL_NATIVE_CLI_DIR=" dir) (str "ASL_NATIVE_QUIET_PID=" (stringFromInt64 (procSelf))))))]
    (str "exec of " dir "/bin failed with " (stringFromInt64 code)))

fn ! timeoutS! -> Int64
  (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_CLI_TIMEOUT") "")) 1800)

fn ! headDir! cache: String root: String -> String
  (stringTrim (resultOr (fileReadString (headPath cache root)) ""))

fn ! awaitNative! ctx: sys/Context cache: String stale: String args: (List String) deadline: Int64 -> String
  (let [(_ (waitBuild! (str cache "/lock") deadline))
        (built (headDir! cache ctx.root))]
    (cond
      ((and (!= built stale) (fresh? ctx.root built) (probe? ctx.root built)) (execNative! ctx built args))
      ((>= (monotonicNs) deadline) "its build exceeded its wait budget")
      (else (str "its build did not finish (see " cache "/build.log)"))))

fn ! nativeWhy! ctx: sys/Context args: (List String) -> String
  (let [(cache (cacheDir!))
        (stale (optionOr (envGet "ASL_NATIVE_CLI_STALE") ""))
        (dir (headDir! cache ctx.root))]
    (cond
      ((not (sys/isFile? (str ctx.root "/asl/host/out/libaslrt.a"))) "asl/host/out/libaslrt.a is absent (sh asl/host/build.sh)")
      ((and (!= dir stale) (fresh? ctx.root dir)) (if (probe? ctx.root dir) (execNative! ctx dir args) "the cached binary failed its self-probe"))
      (else
        (let [(why (startBuild! ctx cache 2 ""))]
          (cond
            ((not (stringEmpty? (optionOr (envGet "ASL_NATIVE_CLI_WAIT") ""))) (awaitNative! ctx cache stale args (+ (monotonicNs) (* (timeoutS!) 1000000000))))
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
