(module asl-cli/native
  :x [main]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/command :a cmd) (tools/nativeTest :a nt) (asl-parser/indentParser :a ip) (asl-harness/launch :a launch) (asl/packages/asl-cli/src/sweep :a sw) (tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-gates/src/suiteRunner :a runner)])

fn rest args: (List String) -> (List String)
  (optionOr (listTail args) (list))

fn first args: (List String) -> String
  (optionOr (listHead args) "")

fn ! atRoot? ctx: sys/Context -> Bool
  (= (resultOr (realPath ".") ".") (resultOr (realPath ctx.root) ctx.root))

fn rooted ctx: sys/Context file: String -> String
  (let [(prefix (str ctx.root "/"))]
    (if (stringStartsWith? file prefix) (optionOr (stringSlice file (stringLength prefix) (stringLength file)) file) file))

fn ! nativeTest! args: (List String) -> Int64
  (mt (nt/main (cons "--self-fp" (cons (nt/fingerprint) args)))
    ((ok code) code)
    ((err e) (do (sys/sayErr! (str "asl: nativeTest: " e)) 1)))

fn ! run! ctx: sys/Context args: (List String) -> Int64
  (let [(file (first args))]
    (if (or (or (listEmpty? args) (or (= file "--help") (= file "-h"))) (or (not (atRoot? ctx)) (and (stringStartsWith? file "/") (not (stringStartsWith? file (str ctx.root "/"))))))
      (cmd/dispatch! ctx "run" args)
      (nativeTest! (cons "run" (cons (rooted ctx file) (rest args))))))

fn ! eprintText text: String -> Unit
  (if (stringEmpty? text) () (do (eprintln (if (stringEndsWith? text "\n") (optionOr (stringSlice text 0 (- (stringLength text) 1)) text) text)) ()))

fn ! preludeOverride ctx: sys/Context -> String
  (str "ASL_PRELUDE=" ctx.root "/asl/host/out/prelude.asl")

fn ! hostJob ctx: sys/Context cwd: String path: String errFile: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$NATIVE_HOST_ERR\"" ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/command.asl") "test" path) cwd
           (run/childEnv (list (str "NATIVE_HOST_ERR=" errFile))))

fn oneLine text: String -> String
  (stringReplace (stringTrim text) "\n" " ")

fn ! gapNote path: String reason: String -> Unit
  (do (eprintln (str "asl: " path " runs on asl-host: ERR_NATIVE_UNSUPPORTED: " (oneLine reason))) ())

fn ! hostSuite! ctx: sys/Context path: String reason: String -> Int64
  (if (not (sys/executable? ctx.hostBin))
    (do (eprintln (str "FAIL " path ": ERR_NATIVE_UNSUPPORTED: " reason " (after 0 asserts)")) 1)
    (let [(_ (gapNote path reason))
          (errFile (str "/tmp/aslNativeHost" (stringFromInt64 (procSelf)) ".err"))
          (timeoutS (resultOr (sw/timeoutWanted!) 1800))
          (d (run/runOneLimited (hostJob ctx "." path errFile) (run/limits timeoutS 64)))
          (errText (resultOr (fileRead errFile) ""))
          (_ (pathRemove errFile))]
      (do (print d.out)
          (eprintText errText)
          (if (= d.verdict "exit") d.exit (do (eprintln (str "FAIL " path ": asl-host " d.verdict " after " (stringFromInt64 timeoutS) "s (after 0 asserts)")) 124)))))

fn ! suite! ctx: sys/Context fp: String path: String -> Int64
  (let [(built (nt/prepare (rooted ctx path) fp))]
    (mt built.binary
      ((some bin)
        (let [(out (nt/runProc (list "nice" "-n" "15" bin) (some (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx))))))
              (v (nt/verdictOf path out.exitCode out.stderr))]
          (do (print out.stdout)
              (eprintText v.stderr)
              (if (= v.exit 0) (println v.line) (eprintln v.line))
              v.exit)))
      ((none) (hostSuite! ctx path built.reason))))

fn ! suites! ctx: sys/Context paths: (List String) -> Int64
  (if (not (sys/isFile? (str ctx.root "/asl/host/out/libaslrt.a")))
    (do (eprintln (str "asl test: " ctx.root "/asl/host/out/libaslrt.a not found; run sh asl/host/build.sh")) 2)
    (let [(fp (nt/fingerprint))
          (codes (map (fn [(p String)] -> Int64 (if (sys/isFile? p) (suite! ctx fp p) (do (eprintln (str p ":0:0: ERR_IO cannot open file\nFAIL " p ": 1 load error(s) (after 0 asserts)")) 1))) paths))]
      (optionOr (listHead (filter (fn [(c Int64)] -> Bool (!= c 0)) codes)) 0)))

fn ! absolute path: String -> String
  (if (stringStartsWith? path "/") path (str (resultOr (realPath ".") ".") "/" path))

fn ! sweepJob ctx: sys/Context ws: String tmp: String i: Int64 bin: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" 2>\"$NATIVE_SWEEP_ERR\"" bin) ws
           (run/childEnv (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (str "NATIVE_SWEEP_ERR=" tmp "/" (stringFromInt64 i) ".err"))))

fn ! sweepVerdict tmp: String timeoutS: Int64 i: Int64 path: String d: run/Done -> sw/Done
  (if (!= d.verdict "exit")
    (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
    (let [(v (nt/verdictOf path d.exit (resultOr (fileRead (str tmp "/" (stringFromInt64 i) ".err")) "")))
          (out (if (= v.exit 0) (str d.out v.line "\n") d.out))
          (errText (if (= v.exit 0) v.stderr (str v.stderr "\n" v.line)))]
      (sw/Done :index i :path path :code v.exit :last (sw/lastLine (str out "\n" errText)) :out out)))

fn ! sweepDone! ctx: sys/Context ws: String timeoutS: Int64 k: Int64 files: (List String) -> (List sw/Done)
  (let [(fp (nt/fingerprint))
        (rootReal (resultOr (realPath ctx.root) ctx.root))
        (tmp (str "/tmp/aslNativeSweep" (stringFromInt64 (procSelf))))
        (made (dirCreate tmp))
        (built (map (fn [(ip (Pair Int64 String))] -> (Pair (Pair Int64 String) nt/Built) (pair ip (nt/prepare (nt/relativeTo rootReal (str ws "/" (pairSecond ip))) fp))) (enumerate files)))
        (runnable (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (some? (pairSecond b).binary)) built))
        (unbuilt (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (none? (pairSecond b).binary)) built))
        (jobs (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (sweepJob ctx ws tmp (pairFirst (pairFirst b)) (absolute (optionOr (pairSecond b).binary "")))) runnable))
        (ran (if (ok? made) (run/runPoolLimited jobs k (run/limits timeoutS 64)) (list)))
        (fromRuns (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> sw/Done
                         (sweepVerdict tmp timeoutS (pairFirst (pairFirst (pairFirst p))) (pairSecond (pairFirst (pairFirst p))) (pairSecond p)))
                       (zip runnable ran)))
        (fromBuilds (hostSweep! ctx ws tmp timeoutS k unbuilt))
        (lost (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
                     (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 127 :last (str "cannot create " tmp) :out ""))
                   (if (ok? made) (list) runnable)))
        (removed (pathRemove tmp))]
    (listAppend fromRuns (listAppend fromBuilds lost)))

fn ! hostSweep! ctx: sys/Context ws: String tmp: String timeoutS: Int64 k: Int64 unbuilt: (List (Pair (Pair Int64 String) nt/Built)) -> (List sw/Done)
  (let [(errOf (fn [(i Int64)] -> String (str tmp "/" (stringFromInt64 i) ".host.err")))
        (hosted (sys/executable? ctx.hostBin))
        (notes (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (do (if hosted (gapNote (pairSecond (pairFirst b)) (pairSecond b).reason) ()) true)) unbuilt))
        (ran (if hosted (run/runPoolLimited (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (hostJob ctx ws (pairSecond (pairFirst b)) (errOf (pairFirst (pairFirst b))))) unbuilt) k (run/limits timeoutS 64)) (list)))]
    (if (not hosted)
      (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
             (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 1
                      :last (str "FAIL " (pairSecond (pairFirst b)) ": ERR_NATIVE_UNSUPPORTED: " (pairSecond b).reason " (after 0 asserts)") :out ""))
           unbuilt)
      (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> sw/Done
             (let [(i (pairFirst (pairFirst (pairFirst p))))
                   (path (pairSecond (pairFirst (pairFirst p))))
                   (d (pairSecond p))]
               (if (!= d.verdict "exit")
                 (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
                 (sw/Done :index i :path path :code d.exit :last (sw/lastLine (str d.out "\n" (resultOr (fileRead (errOf i)) ""))) :out d.out))))
           (zip unbuilt ran))))

fn ! sweepFailed! verb: String e: String -> Int64
  (do (eprintln (str "(:" verb " :status :failed :error ERR_NOT_A_WORKSPACE :message \"" e "\")")) 1)

fn ! sweepTest! ctx: sys/Context -> Int64
  (mt (sw/workspace!)
    ((err e) (sweepFailed! "sweep" e))
    ((ok ws)
      (mt (sw/timeoutWanted!)
        ((err e) (sweepFailed! "sweep" e))
        ((ok timeoutS)
          (mt (sw/jobsWanted!)
            ((err e) (sweepFailed! "sweep" e))
            ((ok jobs)
              (mt (sw/plan! "test" ws)
                ((err e) (sweepFailed! "sweep" e))
                ((ok plan) (sw/report! "test" "native" (pairFirst plan) (pairSecond plan) (sweepDone! ctx ws timeoutS (max 1 jobs) (pairFirst plan)) (sw/frozenCountFor! "test" ws))))))))))

fn ! changedFailed! e: String -> Int64
  (do (eprintln (str "(:changed :status :failed :error ERR_SELECTION :message \"" e "\")")) 2)

fn ! changedTest! ctx: sys/Context args: (List String) -> Int64
  (let [(restArgs (filter (fn [(a String)] -> Bool (and (!= a "--changed") (!= a "--dry-run"))) (rest args)))
        (dryRun (listContains? args "--dry-run"))]
    (if (> (listLength restArgs) 1)
      (do (sys/say! "(:changed :status :failed :error ERR_USAGE :message \"asl test --changed [BASE] [--dry-run]\")") 2)
      (let [(base (optionOr (listHead restArgs) "main"))]
        (mt (sw/changedPlan! base)
          ((err e) (changedFailed! e))
          ((ok plan)
           (let [(changed (pairFirst plan))
                 (selected (pairFirst (pairSecond plan)))
                 (frozen (pairSecond (pairSecond plan)))]
            (if dryRun
              (sw/changedDry! base changed selected frozen)
              (mt (sw/workspace!)
                ((err e) (changedFailed! e))
                ((ok ws)
                  (mt (sw/timeoutWanted!)
                    ((err e) (changedFailed! (str "ERR_TIMEOUT: " e)))
                    ((ok timeoutS) (sw/changedReport! base changed selected (sweepDone! ctx ws timeoutS 2 selected) frozen))))))))))))

fn ! check! ctx: sys/Context args: (List String) -> Int64
  (if (or (not (listEmpty? args)) (not (sys/executable? ctx.hostBin)))
    (cmd/dispatch! ctx "check" args)
    (mt (sw/main (list "check" ctx.hostBin)) ((ok code) code) ((err e) (do (sys/sayErr! e) 1))))

fn ! test! ctx: sys/Context args: (List String) -> Int64
  (let [(tracing (or (listContains? args "--trace") (= (optionOr (envGet "ASL_TRACE") "0") "1")))
        (hosted (or (listContains? args "--compare") (or tracing (not (atRoot? ctx)))))]
    (cond
      (hosted (cmd/dispatch! ctx "test" args))
      ((listContains? args "--changed") (changedTest! ctx args))
      ((listEmpty? args) (sweepTest! ctx))
      ((= (first args) "--native") (if (listEmpty? (rest args)) (cmd/dispatch! ctx "test" args) (suites! ctx (rest args))))
      (else (mt (cmd/testFiles! args (list))
              ((err code) code)
              ((ok paths)
                (let [(dirs (filter (fn [(a String)] -> Bool (sys/isDir? a)) args))
                      (selection (runner/selectDirectorySuites! ctx.root paths dirs))
                      (selected (pairFirst selection))
                      (frozen (pairSecond selection))
                      (note (if (listEmpty? dirs) true (sys/say! (str "(:test :frozen " (stringFromInt64 (listLength frozen)) ")"))))]
                  (suites! ctx selected)))))))

fn readCode msg: String -> String
  (if (or (or (stringStartsWith? msg "unmatched") (stringStartsWith? msg "unclosed")) (or (stringContains? msg "' closes '") (stringContains? msg "unterminated")))
    "ERR_READ_UNBALANCED"
    "ERR_READ")

fn ! parse! ctx: sys/Context args: (List String) -> Int64
  (if (listEmpty? args)
    (cmd/dispatch! ctx "parse" args)
    (let [(path (first args))]
      (mt (fileRead path)
        ((err _) (do (sys/sayErr! (str path ": ERR_IO cannot read file")) 1))
        ((ok src) (mt (ip/parseIndentedFormsPos src)
                    ((err e) (do (sys/sayErr! (str path ":" (stringFromInt64 e.line) ":" (stringFromInt64 e.col) ": " (readCode e.msg) " " e.msg)) 1))
                    ((ok forms) (do (sys/say! (str (stringFromInt64 (listLength forms)) " top-level form(s)")) 0)))))))

fn evalSource expr: String -> String
  (str "(module nativeEval :x [main] :i [])\n\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(shown (str (list (do " expr "\n  ))))]\n"
       "    (do (println (optionOr (stringSlice shown 1 (- (stringLength shown) 1)) shown)) (ok 0)))\n")

fn ! evalValue! ctx: sys/Context expr: String -> Int64
  (let [(src (evalSource expr))
        (digest (nt/slotKey "eval" src))
        (dir ".asl/cache/nativeTest/evals")
        (path (str dir "/" digest ".asl"))
        (fp (nt/fingerprint))
        (cDir (optionOr (envGet "ASL_NATIVE_TEST_CACHE") ".asl/cache/nativeTest"))
        (key (nt/slotKey (str "eval:" (nt/importPathOf path)) digest))
        (slot (str cDir "/" fp "/" key))
        (made (mt (dirCreate dir) ((err e) (str e)) ((ok _) (mt (fileWrite path src) ((err e) (str e)) ((ok _) (mt (dirCreate slot) ((err e) (str e)) ((ok _) "")))))))]
    (if (not (stringEmpty? made))
      (do (sys/sayErr! (str "asl eval: cannot prepare " path ": " made)) 1)
      (let [(built (nt/compileIn cDir path src slot key fp "eval"))]
                (mt built.binary
                  ((none) (cmd/dispatch! ctx "eval" (list expr)))
                  ((some bin) (let [(out (nt/runProc (list bin) (some (nt/withEnvOverrides! (list (preludeOverride ctx))))))]
                                (do (print out.stdout)
                                    (eprintText out.stderr)
                                    out.exitCode)))))))

fn ! eval! ctx: sys/Context args: (List String) -> Int64
  (let [(expr (stringJoin args " "))
        (trimmed (sys/trimLeft expr))]
    (cond
      ((= (first args) "--native")
        (if (or (listEmpty? (rest args)) (not (atRoot? ctx))) (cmd/dispatch! ctx "eval" args) (nativeTest! (list "eval" (stringJoin (rest args) " ")))))
      ((stringStartsWith? trimmed "(:") (let [(r (cmd/asnEcho trimmed))] (do (sys/say! (pairFirst r)) (pairSecond r))))
      ((stringEmpty? (stringTrim expr)) (do (sys/say! "()") 0))
      ((not (atRoot? ctx)) (cmd/dispatch! ctx "eval" args))
      (else (evalValue! ctx expr))))

fn ! launch! ctx: sys/Context args: (List String) -> Int64
  (mt (launch/mainIn! ctx.root args) ((ok code) code) ((err e) (do (sys/sayErr! (str "asl launch: " e)) 1)))

fn ! dispatch! ctx: sys/Context verb: String args: (List String) -> Int64
  (cond
    ((= verb "run") (run! ctx args))
    ((= verb "test") (test! ctx args))
    ((= verb "parse") (parse! ctx args))
    ((= verb "eval") (eval! ctx args))
    ((= verb "launch") (launch! ctx args))
    ((= verb "check") (check! ctx args))
    (else (cmd/dispatch! ctx verb args)))

fn ! entry! ctx: sys/Context args: (List String) -> Int64
  (let [(head (first args))]
    (if (or (= head "-f") (= head "-"))
      (mt (cmd/main args) ((ok code) code) ((err _) 2))
      (let [(r (cmd/route! ctx args))]
        (dispatch! ctx (pairFirst r) (pairSecond r)))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (sys/context!)
    ((err e) (do (sys/sayErr! (str "(:asl :status :failed :error ERR_NO_WORKSPACE :message \"" e "\")")) (ok 2)))
    ((ok ctx) (mt (nc/nativeGate! ctx args) ((some code) (ok code)) ((none) (ok (entry! ctx args))))))
