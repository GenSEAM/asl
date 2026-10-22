(module asl-cli/native
  :x [main]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/command :a cmd) (asl-tools/nativeTest :a nt) (asl-parser/indentParser :a ip) (asl-harness/launch :a launch) (asl/packages/asl-cli/src/sweep :a sw) (asl/packages/asl-proc/src/jobPool :a run) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-gates/src/suiteRunner :a runner) (asl-forms/main :a forms) (asl-intel :a intel) (asl/packages/asl-cli/src/verify :a verify) (asl-checker/checkCached :a cc) (asl-checker/types :a ty)])

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
  (match (nt/main (cons "--self-fp" (cons (nt/fingerprint) args)))
    ((ok code) code)
    ((err e) (do (sys/sayErr! (str "asl: nativeTest: " e)) 1)))

; (:m :ref NATIVETEST-HOSTLESS :do "bin/asl run asl/tools/nativeTest.asl runs the nativeTest this CLI is built from in place (bin/asl rebuilds the CLI when that source moves): no per-process compile of its ~60-module closure, and nothing of it in the suite cache")
fn ! nativeTool! args: (List String) -> Int64
  (match (nt/main args)
    ((ok code) code)
    ((err e) (do (sys/sayErr! (str "asl: nativeTest: " e)) 1)))

fn ! outsideStageDir ctx: sys/Context -> String
  (str ctx.root "/.asl/cache/nativeTest/outside")

fn ! outsideRelPath digest: String -> String
  (str ".asl/cache/nativeTest/outside/" digest ".asl")

fn ! ensureDir! dir: String -> (Result Unit String)
  (if (sys/isDir? dir) (ok ()) (dirCreate dir))

fn ! stageOutside! ctx: sys/Context absFile: String -> (Result String String)
  (match (fileReadString absFile)
    ((err e) (err (str "cannot read " absFile ": " e)))
    ((ok src)
      (let [(digest (bytesSha256 (stringToBytes src)))
            (rel (outsideRelPath digest))
            (dest (str ctx.root "/" rel))]
        (match (ensureDir! (outsideStageDir ctx))
          ((err e2) (err (str "cannot create " (outsideStageDir ctx) ": " e2)))
          ((ok _)
            (if (sys/isFile? dest)
              (ok rel)
              (match (fileWrite dest src)
                ((err e3) (err (str "cannot write " dest ": " e3)))
                ((ok _) (ok rel)))))))))

fn ! runOutside! ctx: sys/Context file: String absFile: String args: (List String) -> Int64
  (if (not (sys/isFile? absFile))
    (do (sys/sayErr! (str "(:run :status :failed :error ERR_NO_FILE :message \"file not found: " file "\")")) 1)
    (match (stageOutside! ctx absFile)
      ((err e) (do (sys/sayErr! (str "(:run :status :failed :error ERR_BUILD :message \"cannot stage " file ": " e "\")")) 1))
      ((ok rel)
        (do (eprintln (str "NATIVE-BYPASS " file " :reason absolute-path-outside-workspace :staged " rel))
            (nativeTest! (cons "run" (cons rel (rest args))))))))

; (:m :ref R1-NATIVE-RECERT :do "nt/main prints its own 'FAIL path: ERR_NATIVE_UNSUPPORTED: path exports neither runTests nor main' when run! delegates straight to it, same generic wrap as the test-side gap but with no Built.reason string this layer could intercept; a cheap static nt/entryOf read of the file's own header, done here before delegating, catches the same no-entry case and reports it with the canonical ERR_NO_ENTRY CONTRACT.asn names, while any file that does declare an entry still goes to nativeTest! exactly as before")
; (:m :ref POSTFIX :do "the early-intercept FAIL line reinvented nt/main's own construction and got it wrong on 3 points: it rooted (relative) both path mentions where nt/main's runFile uses the raw absFile for the FAIL prefix and only the relative logical path for the message body, it dropped the colon after ERR_NO_ENTRY, and it appended a bogus (after 0 asserts) suffix nt/main's run leg never prints (that suffix is test/eval-only, from failLine, not runFile's bare failReason); matched verbatim to nt/main's own text so nativeCliTest's native-equals-asl-host comparison holds")
fn ! runEntryChecked! ctx: sys/Context absFile: String args: (List String) -> Int64
  (match (fileReadString absFile)
    ((err _) (nativeTest! (cons "run" (cons absFile (rest args)))))
    ((ok src)
      (if (listContains? (nt/exportsOf src) "main")
        (nativeTest! (cons "run" (cons absFile (rest args))))
        (do (eprintln (str "FAIL " absFile ": ERR_NO_ENTRY: " (rooted ctx absFile) " exports neither runTests nor main")) 1))))

; (:m :ref OUT-OF-ROOT-USERPATH :do "an in-root file is run as absFile, not (rooted ctx absFile): nativeTest.asl's runFile now reads the path it is given against the caller's actual cwd (OUT-OF-ROOT-USERPATH), so a root-stripped name only resolves when cwd already equals root; absFile is cwd-independent and runFile derives its own logical/import name by stripping toolRoot internally")
fn ! run! ctx: sys/Context args: (List String) -> Int64
  (let [(file (first args))
        (absFile (resultOr (realPath file) file))
        (inRoot (stringStartsWith? absFile (str ctx.root "/")))]
    (cond
      ((or (listEmpty? args) (or (= file "--help") (= file "-h"))) (cmd/dispatch! ctx "run" args))
      ((not inRoot) (runOutside! ctx file absFile args))
      ((= (rooted ctx absFile) "asl/tools/nativeTest.asl") (nativeTool! (rest args)))
      (else (runEntryChecked! ctx absFile args))))

fn ! eprintText text: String -> Unit
  (if (stringEmpty? text) () (do (eprintln (if (stringEndsWith? text "\n") (optionOr (stringSlice text 0 (- (stringLength text) 1)) text) text)) ()))

fn ! preludeOverride ctx: sys/Context -> String
  (str "ASL_PRELUDE=" ctx.root "/asl/host/out/prelude.asl")

fn ! hostJob ctx: sys/Context cwd: String path: String errFile: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$NATIVE_HOST_ERR\"" ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/command.asl") "test" path) cwd
           (run/childEnv (list (str "NATIVE_HOST_ERR=" errFile))))

fn oneLine text: String -> String
  (stringReplace (stringTrim text) "\n" " ")

; (:m :ref R1-NATIVE-RECERT :do "the lowering pass rejects an unbuilt file with its own ERR_LOWER_* vocabulary, wrapped generically as ERR_NATIVE_UNSUPPORTED by every caller below; CONTRACT.asn names the canonical code verbatim, so recognize the well-known lowering shapes and surface that code; an unrecognized shape keeps the generic tag")
fn unsupportedCode reason: String -> String
  (cond
    ((stringContains? reason "exports neither runTests nor main") "ERR_NO_ENTRY")
    ((and (stringContains? reason "imports ") (or (stringContains? reason "not declared") (stringContains? reason "has an empty, . or .. segment"))) "ERR_UNRESOLVED_IMPORT")
    ((stringContains? reason "[ERR_LOWER_ARITY]") "ERR_ARITY")
    ((stringContains? reason "is neither a module function nor a builtin") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "unknown symbol '") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "declares no '") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "nested deeper than") "ERR_DEPTH")
    (else ""))

fn unsupportedTag reason: String -> String
  (let [(code (unsupportedCode reason))] (if (stringEmpty? code) "ERR_NATIVE_UNSUPPORTED" code))

fn ! gapNote path: String reason: String -> Unit
  (do (eprintln (str "asl: " path " runs on asl-host: " (unsupportedTag reason) ": " (oneLine reason))) ())

fn ! hostSuite! ctx: sys/Context path: String reason: String -> Int64
  (if (not (sys/executable? ctx.hostBin))
    (do (eprintln (str "FAIL " path ": " (unsupportedTag reason) ": " reason " (after 0 asserts)")) 1)
    (let [(_ (gapNote path reason))
          (errFile (str "/tmp/aslNativeHost" (stringFromInt64 (procSelf)) ".err"))
          (timeoutS (resultOr (sw/timeoutWanted!) 1800))
          (d (run/runOneLimited (hostJob ctx "." path errFile) (run/limits timeoutS 64)))
          (errText (resultOr (fileReadString errFile) ""))
          (_ (pathRemove errFile))]
      (do (print d.out)
          (eprintText errText)
          (if (= d.verdict "exit") d.exit (do (eprintln (str "FAIL " path ": asl-host " d.verdict " after " (stringFromInt64 timeoutS) "s (after 0 asserts)")) 124)))))

fn ! suiteRelPath! ctx: sys/Context path: String -> (Result String String)
  (let [(absPath (resultOr (realPath path) path))]
    (if (stringStartsWith? absPath (str ctx.root "/"))
      (ok (rooted ctx absPath))
      (stageOutside! ctx absPath)))

fn ! suite! ctx: sys/Context fp: String path: String -> Int64
  (match (suiteRelPath! ctx path)
    ((err e) (do (eprintln (str "FAIL " path ": ERR_BUILD cannot stage " path ": " e " (after 0 asserts)")) 1))
    ((ok rel) (suiteBuilt! ctx fp path rel)))

; (:m :ref OUT-OF-ROOT-USERPATH :do "rel is always root-relative (rooted for an in-root file, stageOutside!'s rel for a staged one); nt/prepare would read it bare against the actual cwd (OUT-OF-ROOT-USERPATH), wrong whenever test! skipped reexecTestAtRoot! (anyOutOfRoot?) and cwd never became ctx.root, so prepareSourceIn reads the absolute ctx.root-anchored path while keeping rel as the logical/import name")
fn ! suiteBuilt! ctx: sys/Context fp: String path: String rel: String -> Int64
  (let [(built (nt/prepareTestSource (str ctx.root "/" rel) rel fp))]
    (match built.binary
      ((some bin)
        (let [(out (nt/runProc (list "nice" "-n" "15" bin) (some (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOff))))))
              (v (nt/judgeInit! bin path (preludeOverride ctx) (nt/verdictOf path out.exitCode out.stderr)))]
          (do (print out.stdout)
              (eprintText v.stderr)
              (if (= v.exit 0) (println v.line) (eprintln v.line))
              v.exit)))
      ((none) (if (= built.cache "checker-reject")
                (do (eprintln (nt/failLine rel built.reason)) 1)
                (hostSuite! ctx path built.reason)))))

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
           (run/childEnv (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOff) (str "NATIVE_SWEEP_ERR=" tmp "/" (stringFromInt64 i) ".err"))))

fn ! initProbeJob ctx: sys/Context ws: String tmp: String i: Int64 bin: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" 2>\"$NATIVE_SWEEP_ERR\"" bin) ws
           (run/childEnv (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOn) (str "NATIVE_SWEEP_ERR=" tmp "/" (stringFromInt64 i) ".init.err"))))

fn ! initProbed tmp: String timeoutS: Int64 done: sw/Done d: run/Done -> sw/Done
  (if (!= d.verdict "exit")
    (sw/Done :index done.index :path done.path :code 124 :last (str "module-initialization probe timed out after " (stringFromInt64 timeoutS) "s") :out done.out)
    (match (nt/initVerdict done.path d.exit (resultOr (fileReadString (str tmp "/" (stringFromInt64 done.index) ".init.err")) ""))
      ((none) done)
      ((some v) (sw/Done :index done.index :path done.path :code v.exit :last v.line :out ""))))

fn ! sweepInitProbes! ctx: sys/Context ws: String tmp: String timeoutS: Int64 k: Int64 pairs: (List (Pair sw/Done String)) -> (List sw/Done)
  (let [(passed (filter (fn [(p (Pair sw/Done String))] -> Bool (= (pairFirst p).code 0)) pairs))
        (failed (filter (fn [(p (Pair sw/Done String))] -> Bool (!= (pairFirst p).code 0)) pairs))
        (jobs (map (fn [(p (Pair sw/Done String))] -> run/Job (initProbeJob ctx ws tmp (pairFirst p).index (pairSecond p))) passed))
        (ran (run/runPoolLimited jobs k (run/limits timeoutS 64)))]
    (listAppend (map (fn [(p (Pair (Pair sw/Done String) run/Done))] -> sw/Done (initProbed tmp timeoutS (pairFirst (pairFirst p)) (pairSecond p))) (zip passed ran))
                (map (fn [(p (Pair sw/Done String))] -> sw/Done (pairFirst p)) failed)))

fn ! sweepVerdict tmp: String timeoutS: Int64 i: Int64 path: String d: run/Done -> sw/Done
  (if (!= d.verdict "exit")
    (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
    (let [(v (nt/verdictOf path d.exit (resultOr (fileReadString (str tmp "/" (stringFromInt64 i) ".err")) "")))
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
        (rejected (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (and (none? (pairSecond b).binary) (= (pairSecond b).cache "checker-reject"))) built))
        (unbuilt (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (and (none? (pairSecond b).binary) (!= (pairSecond b).cache "checker-reject"))) built))
        (jobs (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (sweepJob ctx ws tmp (pairFirst (pairFirst b)) (absolute (optionOr (pairSecond b).binary "")))) runnable))
        (ran (if (ok? made) (run/runPoolLimited jobs k (run/limits timeoutS 64)) (list)))
        (judged (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> (Pair sw/Done String)
                       (pair (sweepVerdict tmp timeoutS (pairFirst (pairFirst (pairFirst p))) (pairSecond (pairFirst (pairFirst p))) (pairSecond p))
                             (absolute (optionOr (pairSecond (pairFirst p)).binary ""))))
                     (zip runnable ran)))
        (fromRuns (sweepInitProbes! ctx ws tmp timeoutS k judged))
        (fromChecker (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
                             (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 1
                                      :last (nt/failLine (pairSecond (pairFirst b)) (pairSecond b).reason) :out ""))
                           rejected))
        (fromBuilds (hostSweep! ctx ws tmp timeoutS k unbuilt))
        (lost (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
                     (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 127 :last (str "cannot create " tmp) :out ""))
                   (if (ok? made) (list) runnable)))
        (removed (pathRemove tmp))]
    (listAppend fromRuns (listAppend fromChecker (listAppend fromBuilds lost))))

fn ! hostSweep! ctx: sys/Context ws: String tmp: String timeoutS: Int64 k: Int64 unbuilt: (List (Pair (Pair Int64 String) nt/Built)) -> (List sw/Done)
  (let [(errOf (fn [(i Int64)] -> String (str tmp "/" (stringFromInt64 i) ".host.err")))
        (hosted (sys/executable? ctx.hostBin))
        (notes (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (do (if hosted (gapNote (pairSecond (pairFirst b)) (pairSecond b).reason) ()) true)) unbuilt))
        (ran (if hosted (run/runPoolLimited (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (hostJob ctx ws (pairSecond (pairFirst b)) (errOf (pairFirst (pairFirst b))))) unbuilt) k (run/limits timeoutS 64)) (list)))]
    (if (not hosted)
      (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
             (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 1
                      :last (str "FAIL " (pairSecond (pairFirst b)) ": " (unsupportedTag (pairSecond b).reason) ": " (pairSecond b).reason " (after 0 asserts)") :out ""))
           unbuilt)
      (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> sw/Done
             (let [(i (pairFirst (pairFirst (pairFirst p))))
                   (path (pairSecond (pairFirst (pairFirst p))))
                   (d (pairSecond p))]
               (if (!= d.verdict "exit")
                 (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
                 (sw/Done :index i :path path :code d.exit :last (sw/lastLine (str d.out "\n" (resultOr (fileReadString (errOf i)) ""))) :out d.out))))
           (zip unbuilt ran))))

fn ! sweepFailed! verb: String e: String -> Int64
  (do (eprintln (str "(:" verb " :status :failed :error ERR_NOT_A_WORKSPACE :message \"" e "\")")) 1)

fn ! sweepTest! ctx: sys/Context -> Int64
  (match (sw/workspace!)
    ((err e) (sweepFailed! "sweep" e))
    ((ok ws)
      (match (sw/timeoutWanted!)
        ((err e) (sweepFailed! "sweep" e))
        ((ok timeoutS)
          (match (sw/jobsWanted!)
            ((err e) (sweepFailed! "sweep" e))
            ((ok jobs)
              (match (sw/plan! "test" ws)
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
        (match (sw/changedPlan! base)
          ((err e) (changedFailed! e))
          ((ok plan)
           (let [(changed (pairFirst plan))
                 (selected (pairFirst (pairSecond plan)))
                 (frozen (pairSecond (pairSecond plan)))]
            (if dryRun
              (sw/changedDry! base changed selected frozen)
              (match (sw/workspace!)
                ((err e) (changedFailed! e))
                ((ok ws)
                  (match (sw/timeoutWanted!)
                    ((err e) (changedFailed! (str "ERR_TIMEOUT: " e)))
                    ((ok timeoutS) (sw/changedReport! base changed selected (sweepDone! ctx ws timeoutS 2 selected) frozen))))))))))))

fn ! check! ctx: sys/Context args: (List String) -> Int64
  (if (not (listEmpty? args))
    (cmd/dispatch! ctx "check" args)
    (match (sw/nativeCheckSweep!) ((ok code) code) ((err e) (do (sys/sayErr! e) 1))))

fn ! rootRelativeArg ctx: sys/Context a: String -> String
  (rooted ctx (resultOr (realPath a) a))

fn ! reexecTestAtRoot! ctx: sys/Context args: (List String) -> Int64
  (sys/execv! (listAppend (list "/bin/sh" "-c" "cd -- \"$0\" && exec \"$@\"" ctx.root (str ctx.root "/bin/asl") "test")
                          (map (fn [(a String)] -> String (rootRelativeArg ctx a)) args))
              (list))

fn ! outOfRoot? ctx: sys/Context a: String -> Bool
  (not (stringStartsWith? (resultOr (realPath a) a) (str ctx.root "/")))

; (:m :ref OUT-OF-ROOT-USERPATH :do "reexecTestAtRoot! exists so a plain-file arg given relative to a toolchain SUBdirectory still resolves (cd to root, then make the arg root-relative); an already-absolute, genuinely out-of-root arg (a /tmp fixture repo, fleetCompareTest's base/head) gains nothing from that cd and loses everything from it, since the fixture's own relative data-file reads (at runtime, inside the compiled suite) stay anchored to whatever cwd the reexec left behind, not the fixture's own root; skip the reexec for those and let the normal else-branch pipeline (suites!, whose suiteRelPath! already stages a genuinely out-of-root path) run with cwd untouched")
fn ! anyOutOfRoot? ctx: sys/Context args: (List String) -> Bool
  (listAny? (fn [(a String)] -> Bool (outOfRoot? ctx a)) (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) args))

fn ! test! ctx: sys/Context args: (List String) -> Int64
  (let [(tracing (or (listContains? args "--trace") (= (optionOr (envGet "ASL_TRACE") "0") "1")))
        (plainFiles (and (not (listEmpty? args)) (and (not (listContains? args "--changed")) (not (= (first args) "--native")))))
        (hosted (or (listContains? args "--compare") (or tracing (and (not plainFiles) (not (atRoot? ctx))))))]
    (cond
      (hosted (cmd/dispatch! ctx "test" args))
      ((and plainFiles (not (atRoot? ctx)) (not (anyOutOfRoot? ctx args))) (reexecTestAtRoot! ctx args))
      ((listContains? args "--changed") (changedTest! ctx args))
      ((listEmpty? args) (sweepTest! ctx))
      ((= (first args) "--native") (if (listEmpty? (rest args)) (cmd/dispatch! ctx "test" args) (suites! ctx (rest args))))
      (else (match (cmd/testFiles! args (list))
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
      (match (fileReadString path)
        ((err _) (do (sys/sayErr! (str path ": ERR_IO cannot read file")) 1))
        ((ok src) (match (ip/parseIndentedFormsPos src)
                    ((err e) (do (sys/sayErr! (str path ":" (stringFromInt64 e.line) ":" (stringFromInt64 e.col) ": " (readCode e.msg) " " e.msg)) 1))
                    ((ok forms) (do (sys/say! (str (stringFromInt64 (listLength forms)) " top-level form(s)")) 0)))))))

fn evalSource expr: String -> String
  (str "(module nativeEval :x [main] :i [])\n\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(shown (str (list (do " expr "\n  ))))]\n"
       "    (do (println (optionOr (stringSlice shown 1 (- (stringLength shown) 1)) shown)) (ok 0)))\n")

fn ! printDiag! d: ty/Diagnostic -> Bool
  (sys/sayErr! (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message))

fn ! evalRejected! path: String reason: String -> Int64
  (let [(verdict (pairFirst (cc/checkFileCached! path (verify/checkRoots) (cc/emptyCache))))
        (diags (match verdict ((err _) (list)) ((ok v) v.diags)))]
    (if (listEmpty? diags)
      (do (sys/sayErr! (str "asl eval: " reason)) 1)
      (do (map printDiag! diags) 1)))

fn ! evalValue! ctx: sys/Context expr: String -> Int64
  (let [(src (evalSource expr))
        (digest (nt/slotKey "eval" src))
        (dir (str ctx.root "/.asl/cache/nativeTest/evals"))
        (path (str dir "/" digest ".asl"))
        (fp (nt/fingerprint))
        (cDir (let [(configured (optionOr (envGet "ASL_NATIVE_TEST_CACHE") ""))]
                (if (stringEmpty? configured) (str ctx.root "/.asl/cache/nativeTest") configured)))
        (key (nt/slotKey (str "eval:" (nt/importPathOf path)) digest))
        (slot (str cDir "/" fp "/" key))
        (made (match (dirCreate dir) ((err e) (str e)) ((ok _) (match (fileWrite path src) ((err e) (str e)) ((ok _) (match (dirCreate slot) ((err e) (str e)) ((ok _) "")))))))]
    (if (not (stringEmpty? made))
      (do (sys/sayErr! (str "asl eval: cannot prepare " path ": " made)) 1)
      (let [(built (nt/compileIn cDir path path src slot key fp "eval"))]
                (match built.binary
                  ((none) (evalRejected! path built.reason))
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
      (else (evalValue! ctx expr))))

fn ! launch! ctx: sys/Context args: (List String) -> Int64
  (match (launch/mainIn! ctx.root args) ((ok code) code) ((err e) (do (sys/sayErr! (str "asl launch: " e)) 1)))

fn ! forms! args: (List String) -> Int64
  (let [(result (forms/mainText! args))]
    (do (sys/say! (sys/stripTrailingNewlines (pairFirst result))) (pairSecond result)))

fn ! intel! ctx: sys/Context args: (List String) -> Int64
  (let [(oc (intel/runIntel! (intel/makeCtxFor! ctx.root) args))]
    (do (print oc.out)
        (if (stringEmpty? oc.err) () (eprintln (optionOr (stringSlice oc.err 0 (- (stringLength oc.err) 1)) "")))
        oc.code))

fn intelAlias verb: String -> String
  (cond
    ((listContains? (list "coupling" "graph" "complexity" "stubs" "trace") verb) verb)
    ((or (= verb "vitality") (= verb "full")) "vitality")
    (else ""))

fn ! dispatch! ctx: sys/Context verb: String args: (List String) -> Int64
  (cond
    ((or (stringStartsWith? verb "(") (stringStartsWith? verb ":")) (forms! (cons verb args)))
    ((= verb "rpc") (forms! args))
    ((= verb "intel") (intel! ctx args))
    ((not (stringEmpty? (intelAlias verb))) (intel! ctx (cons (intelAlias verb) args)))
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
      (match (cmd/main args) ((ok code) code) ((err _) 2))
      (let [(r (cmd/route! ctx args))]
        (dispatch! ctx (pairFirst r) (pairSecond r)))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (sys/context!)
    ((err e) (do (sys/sayErr! (str "(:asl :status :failed :error ERR_NO_WORKSPACE :message \"" e "\")")) (ok 2)))
    ((ok ctx) (match (nc/nativeGate! ctx args) ((some code) (ok code)) ((none) (ok (entry! ctx args))))))
