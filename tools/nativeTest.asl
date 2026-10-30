(module asl-tools/nativeTest
  :x [runTests main failLine initPhaseOff initPhaseOn initVerdict judgeInit! selfSlotOf linkArchives exportsOf entryOf mainTakesArgs importPathOf wrapperSource reportCounts verdictOf hostVerdictLine toolchainRoots slotKey relativeTo manifestText manifestHolds? manifestFileHolds? interfaceDigest moduleCacheKey fullPreludeKey preludeDigestIn prepare prepareIn prepareTestSource ephemeralSlotIn! linkedWorktree? defaultCacheDirFor sweepStore! sweepStoreNow! sweepStoreWith! leaseSlot! moduleEntries! slotEntries! prepareRun prepareRunIn fingerprint compile compileIn Built Verdict Outcome ProcOut runProc runProcIn withEnvOverrides! withEnvStripped! fileDigest readVerifiedMeta WorkerProc WorkerWatch spawnWorker! awaitWorkersWithin! workersVerdict]
  :i [(asl-tools/corpusNative :a cn)
      (asl-parser/ast :a ast)
      (asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm/ssa :a llvm)
      (asl-target-llvm :a nat)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a route)
      (asl-syntax/asl/paren :a paren)
      (asl-tools/fleet/run :a fr)
      (asl-cli/nativeCli :a ncli)
      (asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeBuild :a nb)
      (asl/packages/asl-cli/src/rcConfig :a rcc)
      (asl-cli/verify :a verify)
      (asl-compiler/checkCache :a ccache)
      (asl-checker/check :a chk)
      (asl-checker/checkCached :a ccd)])

(schema Verdict
  (:f exit Int64)
  (:f line String)
  (:f stderr String))

(schema ProcOut
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! pumpCollect outFd: Int64 errFd: Int64 outAcc: String errAcc: String outOpen: Bool errOpen: Bool pid: Int64 -> ProcOut
  (if (and (not outOpen) (not errOpen))
    (let [(w (procWaitPid pid false))]
      (match w
        ((ok opt) (ProcOut :exitCode (optionOr opt 0) :stdout outAcc :stderr errAcc))
        ((err _) (ProcOut :exitCode 1 :stdout outAcc :stderr errAcc))))
    (let [(rOut (if outOpen (fdRead outFd 65536) (err "closed")))
          (hadOut (match rOut
                    ((ok c) (if (> (stringLength c) 0) true (let [(_ (fdClose outFd))] false)))
                    ((err _) false)))
          (nextOutAcc (match rOut ((ok c) (if (> (stringLength c) 0) (str outAcc c) outAcc)) ((err _) outAcc)))
          (nextOutOpen (if outOpen (match rOut ((ok c) (> (stringLength c) 0)) ((err _) true)) false))
          (rErr (if errOpen (fdRead errFd 65536) (err "closed")))
          (hadErr (match rErr
                    ((ok c) (if (> (stringLength c) 0) true (let [(_ (fdClose errFd))] false)))
                    ((err _) false)))
          (nextErrAcc (match rErr ((ok c) (if (> (stringLength c) 0) (str errAcc c) errAcc)) ((err _) errAcc)))
          (nextErrOpen (if errOpen (match rErr ((ok c) (> (stringLength c) 0)) ((err _) true)) false))]
      (if (and (not hadOut) (not hadErr) (or nextOutOpen nextErrOpen))
        (let [(fds (cond
                     ((and nextOutOpen nextErrOpen) (list (pair outFd 1) (pair errFd 1)))
                     (nextOutOpen (list (pair outFd 1)))
                     (else (list (pair errFd 1)))))]
          (do (fdPoll fds 50)
              (pumpCollect outFd errFd nextOutAcc nextErrAcc nextOutOpen nextErrOpen pid)))
        (pumpCollect outFd errFd nextOutAcc nextErrAcc nextOutOpen nextErrOpen pid))))

fn ! runProc argv: (List String) envOpt: (Option (List String)) -> ProcOut
  (runProcIn argv (none) envOpt)

; (:m :ref ORPHAN-EVAL-ESCAPE :do "fr/ProcOut and this file's own ProcOut have the same fields but are nominally different schemas; runOne/evalExpression! now call fr/runGuarded, so their result needs converting back to this file's ProcOut for emit/judgeInit!/verdictOf")
fn ! fromFr p: fr/ProcOut -> ProcOut
  (ProcOut :exitCode p.exitCode :stdout p.stdout :stderr p.stderr)

fn ! runProcIn argv: (List String) cwd: (Option String) envOpt: (Option (List String)) -> ProcOut
  (let [(spawnRes (procSpawnv argv cwd envOpt))]
    (match spawnRes
      ((err e) (ProcOut :exitCode 127 :stdout "" :stderr (str "spawn failed: " e)))
      ((ok sp)
        (let [(_ (fdClose sp.stdin))
              (outFd sp.stdout)
              (errFd sp.stderr)
              (_ (fdNonBlocking outFd true))
              (_ (fdNonBlocking errFd true))]
          (pumpCollect outFd errFd "" "" true true sp.pid)))))

fn withEnvOverrides! overrides: (List String) -> (List String)
  (let [(names (map (fn [(s String)] -> String (optionOr (listHead (stringSplit s "=")) s)) overrides))]
    (listAppend overrides
                (filter (fn [(row String)] -> Bool
                          (let [(k (optionOr (listHead (stringSplit row "=")) row))]
                            (not (listContains? names k))))
                        (envList))))

fn withEnvStripped! names: (List String) -> (List String)
  (filter (fn [(row String)] -> Bool
            (let [(k (optionOr (listHead (stringSplit row "=")) row))]
              (not (listContains? names k))))
          (envList))

fn format -> String
  "nativeTest/7;compile=-O2,-Wno-override-module,-c;link=-O2,-lm"

; (:m :ref NATIVE-CHDIR :do "the root is explicit: the CLI process bin/asl started (ASL_CLI_ENTRY_PID is this pid) uses ASL_CLI_ROOT, the tree that bin/asl belongs to, whatever its cwd; any other process keeps a toolchain cwd, then ASL_CLI_ROOT, then ASL_ROOT; the native CLI no longer chdirs to the root before calling in")
fn ! toolchainRoot? dir: String -> Bool
  (and (not (stringEmpty? dir)) (and (fileExists? (str dir "/asl/tools/nativeTest.asl")) (fileExists? (str dir "/asl/prelude/prelude.asl"))))

fn ! toolRoot -> String
  (let [(cli (optionOr (envGet "ASL_CLI_ROOT") ""))]
    (cond
      ((and (= (optionOr (envGet "ASL_CLI_ENTRY_PID") "") (stringFromInt64 (procSelf))) (toolchainRoot? cli)) cli)
      ((toolchainRoot? ".") ".")
      ((toolchainRoot? cli) cli)
      (else (optionOr (envGet "ASL_ROOT") "."))))

fn ! toolPath rel: String -> String
  (let [(root (toolRoot))]
    (if (= root ".") rel (str root "/" rel)))

fn ! absPath rel: String -> String
  (let [(root (toolRoot))]
    (if (= root ".") (str (resultOr (realPath ".") ".") "/" rel) (str root "/" rel)))

; (:m :ref GATE-SPEED :do "a linked git worktree (its .git is a file) shares the compile cache ~/.asl/run/nativeTest with every other one, as audit gates already does: entries are keyed by content, so a unit worktree compiles only what it changed (conductorTest 49 s CPU cold, 1.4 s on a shared hit); the main checkout and an explicit ASL_NATIVE_TEST_CACHE keep their choice")
fn ! linkedWorktree? root: String -> Bool
  (match (fileStat (str root "/.git"))
    ((ok st) (not st.isDir))
    ((err _) false))

fn ! defaultCacheDirFor root: String home: String -> String
  (if (and (not (stringEmpty? home)) (linkedWorktree? root)) (str home "/.asl/run/nativeTest") ".asl/cache/nativeTest")

fn ! cacheDir! -> String
  (let [(c (optionOr (envGet "ASL_NATIVE_TEST_CACHE") (defaultCacheDirFor (toolRoot) (optionOr (envGet "HOME") ""))))]
    (if (stringStartsWith? c "/") c (toolPath c)))

fn modulesDirIn cDir: String -> String
  (str cDir "/modules")

fn ! wrapperDirIn cDir: String -> String
  (let [(full (resultOr (realPath cDir) cDir))]
    (if (stringStartsWith? (relativeTo (selfRoot) full) "/")
      (toolPath (str ".asl/cache/nativeTest/entries/" (slotKey "entries" full)))
      (str cDir "/entries")))

fn modulesDir! -> String
  (modulesDirIn (cacheDir!))

fn wrapperDir! -> String
  (wrapperDirIn (cacheDir!))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn headerOf src: String -> String
  (match (stringIndexOf src "\n\n")
    ((none) src)
    ((some i) (optionOr (stringSlice src 0 i) src)))

; (:m :ref SCRIPT-ENTRY :do "fn header lines with their tailrec marker dropped, so fn tailrec main and fn ! tailrec runTests read like fn main and fn ! runTests, as the parser reads them")
fn fnLine l: String -> String
  (let [(words (stringSplit l " ")) (rest (optionOr (listTail words) (list)))]
    (if (= (listHead words) (some "fn"))
      (stringJoin (cons "fn" (listAppend (filter (fn [(w String)] -> Bool (and (!= w "tailrec") (!= w ":tailrec"))) (listTake rest 2)) (listDrop rest 2))) " ")
      l))

fn fnLines src: String -> (List String)
  (map fnLine (stringLines src))

fn definesFn? lines: (List String) name: String -> Bool
  (listAny? (fn [l] (or (or (= l (str "fn " name)) (stringStartsWith? l (str "fn " name " ")))
                        (or (= l (str "fn ! " name)) (stringStartsWith? l (str "fn ! " name " ")))))
            lines)

fn moduleHeaded? lines: (List String) -> Bool
  (listAny? (fn [l] (or (= l "(module") (stringStartsWith? l "(module "))) lines)

; (:m :ref IMPLICIT-MODULE :do "a headerless source exports the entries it defines (main, runTests), as the parser's synthesised script header does")
; (:m :ref TOP-LEVEL-CODE :do "a column-0 paren form that is no declaration, data form or use line is top-level code, which the parser turns into main")
fn codeLine? l: String -> Bool
  (and (stringStartsWith? l "(")
       (not (listAny? (fn [p] (stringStartsWith? l p)) (list "(:" "(use " "(fn " "(defun " "(df " "(schema " "(defschema " "(dfs " "(enum " "(defenum " "(dfe "))))

; (:m :ref SCRIPT-ENTRY :do "a headerless file's entries are what the parser exports from its synthesised script header; the line heuristic is the fallback for a file that does not parse")
fn scriptExportsOf src: String -> (List String)
  (match (ast/parse src)
    ((ok forms) (listFlatMap (fn [(t ast/TopForm)] -> (List String) (match t ((ast/topModule m) (if (stringEmpty? m.path) m.exported (list))) (_ (list)))) forms))
    ((err _) (scriptExportsByLine src)))

fn scriptExportsByLine src: String -> (List String)
  (let [(lines (fnLines src))]
    (cond ((moduleHeaded? lines) (list))
          ((listAny? codeLine? lines) (cons "main" (filter (fn [n] (definesFn? lines n)) (list "runTests"))))
          (else (filter (fn [n] (definesFn? lines n)) (list "main" "runTests")))))

fn exportsOf src: String -> (List String)
  (let [(header (headerOf src))]
    (match (stringIndexOf header ":x [")
      ((none) (scriptExportsOf src))
      ((some i) (let [(rest (optionOr (stringSlice header (+ i 4) (stringLength header)) ""))
                      (body (optionOr (listHead (stringSplit rest "]")) ""))
                      (flat (stringReplace (stringReplace (stringReplace body "\n" " ") "\t" " ") "\r" " "))]
                  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit flat " "))))))

fn entryOf src: String -> (Option String)
  (let [(xs (exportsOf src))]
    (cond
      ((listContains? xs "runTests") (some "runTests"))
      ((listContains? xs "main") (some "main"))
      (else (none))))

; (:m :ref MAIN-SUGAR :do "a bare fn main header line, the parser's sugared main, binds args, so it takes the argument list")
fn mainLine line: String -> Bool
  (or (or (stringStartsWith? line "fn main ") (stringStartsWith? line "fn ! main ")) (or (= line "fn main") (= line "fn ! main")))

fn mainReturnsBareInt64 src: String -> Bool
  (match (listHead (filter mainLine (fnLines src)))
    ((none) false)
    ((some l) (match (stringIndexOf l "->")
                ((none) false)
                ((some i) (= (stringTrim (optionOr (stringSlice l (+ i 2) (stringLength l)) "")) "Int64")))))

fn wrapperSourceRunInt64 importPath: String takesArgs: Bool -> String
  (str "(module nativeTestEntry\n"
       "  :x [main]\n"
       "  :i [(" importPath " :a suite)])\n\n"
       (dropEphemeralSource)
       "fn ! main args: (List String) -> (Result Int64 String)\n"
       "  (do (dropEphemeral!) (ok (suite/main" (if takesArgs " args" "") ")))\n")

; (:m :ref BIN-NO-PERSIST-20261026 :do "a run binary built into an ephemeral slot removes its own file and slot first thing in main unless ASL_NATIVE_KEEP_LL is set (the kept IR lives in the slot), so a script, -e or - leaves no binary behind once it is running; a binary anywhere else (prepare, tests) is left alone")
fn dropEphemeralSource -> String
  (str "fn ! dropEphemeral! -> Bool\n"
       "  (match (procExePath)\n"
       "    ((ok p) (if (and (not (some? (envGet \"ASL_NATIVE_KEEP_LL\"))) (and (stringContains? p \"/ephemeral/run.\") (stringEndsWith? p \"/run\"))) (ok? (pathRemove (optionOr (stringSlice p 0 (- (stringLength p) 4)) p))) false))\n"
       "    ((err _) false))\n\n")

fn mainTakesArgs src: String -> Bool
  (match (listHead (filter mainLine (fnLines src)))
    ((none) (let [(lines (stringLines src))] (and (not (moduleHeaded? lines)) (listAny? codeLine? lines))))
    ((some l) (let [(after (stringTrim (optionOr (listGet (stringSplit l " main ") 1) "")))]
                (not (stringStartsWith? after "->")))))

fn importPathOf path: String -> String
  (let [(p (if (stringStartsWith? path "./") (optionOr (stringSlice path 2 (stringLength path)) path) path))]
    (if (stringEndsWith? p ".asl") (optionOr (stringSlice p 0 (- (stringLength p) 4)) p) p))

fn entryBody entry: String takesArgs: Bool -> String
  (if (= entry "runTests")
    "  (if (suite/runTests) (ok 0) (do (eprintln \"ERR_TEST_FAILED: runTests returned false, not true\") (ok 1)))\n"
    (str "  (match (suite/main" (if (= entry "run") (if takesArgs " args" "") (if takesArgs " (list)" "")) ")\n"
         (if (= entry "run") "    ((ok code) (ok code))\n" "    ((ok _) (ok 0))\n")
         "    ((err e) (do (eprintln (str \"ERR_TEST_FAILED: main returned (err \" e \"), not (ok ...)\")) (ok 1))))\n"))

fn argvGuardMessage -> String
  "nativeTest: native test binary takes no arguments (spawned as a host via procExePath?)"

fn initPhaseEnv -> String
  "ASL_NATIVE_TEST_PHASE"

fn guardedBody entry: String takesArgs: Bool -> String
  (if (= entry "run")
    (entryBody entry takesArgs)
    (str "  (cond\n"
         "    ((= (envGet \"" (initPhaseEnv) "\") (some \"init\")) (ok 0))\n"
         "    ((not (listEmpty? args)) (do (eprintln \"" (argvGuardMessage) "\") (ok 97)))\n"
         "    (else " (entryBody entry takesArgs) "  ))\n"))

fn wrapperSource importPath: String entry: String takesArgs: Bool -> String
  (str "(module nativeTestEntry\n"
       "  :x [main]\n"
       "  :i [(" importPath " :a suite)])\n\n"
       (if (= entry "run") (dropEphemeralSource) "")
       "fn ! main args: (List String) -> (Result Int64 String)\n"
       (if (= entry "run") (str "  (do (dropEphemeral!)\n" (guardedBody entry takesArgs) "  )\n") (guardedBody entry takesArgs)))

fn reportLine? line: String -> Bool
  (let [(words (stringSplit line " "))]
    (and (= (listLength words) 6)
         (and (stringEndsWith? line " refutation(s) executed")
              (and (some? (stringToInt64 (optionOr (listGet words 0) "")))
                   (and (= (listGet words 1) (some "assertion(s)"))
                        (and (= (listGet words 2) (some "executed,"))
                             (some? (stringToInt64 (optionOr (listGet words 3) "")))))))))

fn reportCounts stderr: String -> (Option (Pair Int64 Int64))
  (match (listLast (filter reportLine? (stringLines stderr)))
    ((none) (none))
    ((some l) (let [(words (stringSplit l " "))]
                (some (pair (optionOr (stringToInt64 (optionOr (listGet words 0) "")) 0)
                            (optionOr (stringToInt64 (optionOr (listGet words 3) "")) 0))))))

fn dropLastMatch lines: (List String) keep: (fn [String] -> Bool) -> (List String)
  (let [(rev (listReverse lines))
        (split (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                       (if (and (not (pairFirst acc)) (not (keep l)))
                         (pair true (pairSecond acc))
                         (pair (pairFirst acc) (cons l (pairSecond acc)))))
                     (pair false (list)) rev))]
    (pairSecond split))

fn textLines text: String -> (List String)
  (let [(lines (stringLines text))]
    (if (stringEndsWith? text "\n") (listTake lines (- (listLength lines) 1)) lines))

fn errorLine? line: String -> Bool
  (and (stringStartsWith? line "ERR_") (stringContains? line ": "))

fn verdictOf path: String exitCode: Int64 stderr: String -> Verdict
  (let [(counts (reportCounts stderr))
        (withoutReport (dropLastMatch (textLines stderr) (fn [(l String)] -> Bool (not (reportLine? l)))))
        (errLine (listLast (filter errorLine? withoutReport)))
        (rest (if (and (!= exitCode 0) (some? errLine)) (dropLastMatch withoutReport (fn [(l String)] -> Bool (not (errorLine? l)))) withoutReport))
        (restText (stringJoin rest "\n"))]
    (match counts
      ((none) (Verdict :exit 1 :line (str "FAIL " path ": " (optionOr errLine (str "native binary exited " exitCode " without an assertion report"))) :stderr restText))
      ((some c) (let [(a (pairFirst c)) (r (pairSecond c))]
                  (cond
                    ((!= exitCode 0) (Verdict :exit 1 :line (str "FAIL " path ": " (optionOr errLine (str "native binary exited " exitCode)) " (after " a " asserts)") :stderr restText))
                    ((<= (+ a r) 0) (Verdict :exit 1 :line (str "FAIL " path ": ERR_TEST_FAILED: zero assertions executed (after 0 asserts)") :stderr restText))
                    (else (Verdict :exit 0 :line (str path ": " (cn/summary a r)) :stderr restText)))))))

fn initAssertLine path: String asserts: Int64 refutes: Int64 -> String
  (str "FAIL " path ": ERR_ASSERT_AT_INIT: "
       (cond
         ((and (> asserts 0) (> refutes 0)) "assertion and refutation")
         ((> refutes 0) "refutation")
         (else "assertion"))
       " executed during module initialization of " (importPathOf path)
       " (" asserts " assertion(s), " refutes " refutation(s)); asserts and refutes run only from the test entry (D152) (after " asserts " asserts)")

fn initVerdict path: String exitCode: Int64 stderr: String -> (Option Verdict)
  (match (reportCounts stderr)
    ((none) (some (Verdict :exit 1 :line (str "FAIL " path ": ERR_TEST_FAILED: the module-initialization probe exited " exitCode " without an assertion report (after 0 asserts)") :stderr stderr)))
    ((some c) (cond
                ((> (+ (pairFirst c) (pairSecond c)) 0) (some (Verdict :exit 1 :line (initAssertLine path (pairFirst c) (pairSecond c)) :stderr "")))
                ((!= exitCode 0) (some (Verdict :exit 1 :line (str "FAIL " path ": ERR_TEST_FAILED: the module-initialization probe exited " exitCode " (after 0 asserts)") :stderr stderr)))
                (else (none)))))

fn initPhaseOff -> String
  (str (initPhaseEnv) "=")

fn initPhaseOn -> String
  (str (initPhaseEnv) "=init")

fn ! judgeInit! bin: String path: String prelude: String ran: Verdict -> Verdict
  (if (!= ran.exit 0)
    ran
    (let [(probe (runProc (list "nice" "-n" "15" bin) (some (withEnvOverrides! (list "ASL_ASSERT_REPORT=1" prelude (initPhaseOn))))))]
      (optionOr (initVerdict path probe.exitCode probe.stderr) ran)))

fn hostVerdictLine text: String -> String
  (let [(lines (stringLines text))
        (failLines (filter (fn [(l String)] -> Bool (stringStartsWith? l "FAIL ")) lines))]
    (match (listLast failLines)
      ((some f) f)
      ((none) (optionOr (listLast (filter (fn [(l String)] -> Bool (stringContains? l " assertion(s) executed")) lines)) ""))))

; (:m :ref HL-FIXWAVE :do "toolchainRoots fed its fingerprint hash two paths HL-DELETE can never produce again -- asl/host/out/asl-host and asl/host/out/libaslhost.a; both are dropped, leaving the native runtime archive, the prelude and the compiler sources that actually change the fingerprint")
fn ! toolchainRoots -> (List String)
  (map toolPath (list "asl/packages/asl-compiler/src" "asl/packages/asl-checker/src" "asl/packages/asl-codegen/src" "asl/packages/asl-ir/src"
        "asl/packages/asl-parser/src" "asl/packages/asl-syntax/src/core" "asl/packages/asl-target-llvm/src"
        "asl/host/out/libaslrt.a" "asl/host/out/prelude.asl" "asl/prelude/prelude.asl" "asl/prelude/native" "asl/tools/nativeTest.asl"))

fn ! fileDigest path: String -> String
  (match (fileReadBytes path)
    ((ok b) (bytesSha256 b))
    ((err e) (str "unreadable " e)))

fn ! digestLogPath -> (Option String)
  (envGet "ASL_NATIVE_DIGEST_LOG")

fn ! jobEventLog! line: String -> Unit
  (match (envGet "ASL_NATIVE_JOB_LOG")
    ((none) ())
    ((some _) (eprintln line)))

fn ! loggedDigest tag: String path: String -> String
  (let [(d (fileDigest path))
        (_ (match (digestLogPath)
             ((none) ())
             ((some logPath) (match (fileAppend logPath (str tag " " path "\n")) ((ok _) ()) ((err _) ())))))]
    d)

fn ! treeLines path: String -> (List String)
  (match (fileStat path)
    ((err e) (list (str path " missing " e)))
    ((ok st) (if st.isDir
               (match (dirList path)
                 ((err e) (list (str path " unlistable " e)))
                 ((ok names) (fold (fn [(acc (List String)) (n String)] -> (List String) (listAppend acc (treeLines (str path "/" n)))) (list) (listSort names))))
               (list (str path " " (fileDigest path))))))

; (:m :ref CLI-CLANG-PROBE :do "the shared resolver, from the toolchain root: :native :clang row, CLANG, then clang and clang-19 .. clang-15 on PATH")
fn ! clangCommand -> String
  (resultOr (ncli/clangFor! (toolRoot)) "clang")

fn ! jobSlots! -> Int64
  (let [(envJ (match (envGet "ASL_NATIVE_JOBS") ((none) 4) ((some s) (optionOr (stringToInt64 s) 4))))
        (cpus (resultOr (cpuCount) envJ))]
    (max 1 (min envJ cpus)))

fn ! optLevelFor mode: String -> String
  (optionOr (envGet "ASL_NATIVE_OPT") (if (= mode "test") "-O1" "-O2"))

fn ! fingerprintOf clangVersion: String targetTriple: String -> String
  (bytesSha256 (stringToBytes (stringJoin (cons (format) (cons clangVersion (cons targetTriple (fold (fn [(acc (List String)) (r String)] -> (List String) (listAppend acc (map (fn [(l String)] -> String (relativeTo (toolRoot) l)) (treeLines r)))) (list) (toolchainRoots))))) "\n")))

; (:m :ref RUN-ENTRY-REBUILD-COST :do "a stat walk of the toolchain roots: one path size mtime line per file and the newest mtime seen")
fn ! treeStamps path: String -> (Pair Int64 (List String))
  (match (fileStat path)
    ((err e) (pair 0 (list (str path " missing " e))))
    ((ok st) (if st.isDir
               (fold (fn [(acc (Pair Int64 (List String))) (n String)] -> (Pair Int64 (List String))
                       (let [(sub (treeStamps (str path "/" n)))]
                         (pair (max (pairFirst acc) (pairFirst sub)) (listAppend (pairSecond acc) (pairSecond sub)))))
                     (pair 0 (list)) (listSort (resultOr (dirList path) (list))))
               (pair st.mtimeNs (list (str path " " (stringFromInt64 st.size) " " (stringFromInt64 st.mtimeNs)))))))

fn ! fingerprintMemoDir -> String
  (str (cacheDir!) "/fingerprints")

; (:m :ref RUN-ENTRY-REBUILD-COST :do "every asl run fingerprints the toolchain (3.6 MB of compiler sources, 122 files, hashed per call: 280-420 ms of a warm run under fleet load, 2026-10-27); the digest is kept under the stat lines of those files, so an unchanged tree costs 122 stats. A tree with a file touched in the last 2 s is hashed and not kept, since an edit within the mtime grain could keep its stamp")
fn ! fingerprint -> String
  (let [(facts (ncli/clangFacts!))
        (clangVersion (optionOr (listGet facts 0) "clang absent"))
        (targetTriple (optionOr (listGet facts 1) "unknown-target"))
        (stamps (fold (fn [(acc (Pair Int64 (List String))) (r String)] -> (Pair Int64 (List String))
                        (let [(t (treeStamps r))] (pair (max (pairFirst acc) (pairFirst t)) (listAppend (pairSecond acc) (pairSecond t)))))
                      (pair 0 (list)) (toolchainRoots)))
        (memo (str (fingerprintMemoDir) "/" (bytesSha256 (stringToBytes (stringJoin (cons (format) (cons clangVersion (cons targetTriple (pairSecond stamps)))) "\n")))))
        (kept (stringTrim (resultOr (fileReadString memo) "")))]
    (if (= (stringLength kept) 64)
      kept
      (let [(fp (fingerprintOf clangVersion targetTriple))
            (settled (< (pairFirst stamps) (- (nowNs) 2000000000)))
            (_ (if settled
                 (do (dirCreate (fingerprintMemoDir)) (writeAtomic memo fp) (prune (fingerprintMemoDir) (sys/baseName memo)))
                 ()))]
        fp)))

fn wrapperVersion -> String
  "wrapper/3;argvGuard;initPhase"

fn slotKey path: String suiteDigest: String -> String
  (bytesSha256 (stringToBytes (str (format) "\n" (wrapperVersion) "\n" path "\n" suiteDigest)))

fn relativeTo root: String path: String -> String
  (if (stringStartsWith? path (str root "/")) (optionOr (stringSlice path (+ (stringLength root) 1) (stringLength path)) path) path)

fn ms ns: Int64 -> Int64
  (/ ns 1000000)

fn ! manifestTextWith prev: (Map String (List String)) kind: String deps: (List String) -> String
  (str (format) " " kind "\n" (stringJoin (map (fn [(p String)] -> String (str (manifestStamp prev p) " " p)) deps) "\n") "\n")

fn ! manifestText kind: String deps: (List String) -> String
  (manifestTextWith (mapEmpty) kind deps)

fn ! manifestStamp prev: (Map String (List String)) p: String -> String
  (let [(st (fileStat (resolveIn (toolRoot) p)))
        (curSize (match st ((ok s) (stringFromInt64 s.size)) ((err _) "-1")))
        (curMtime (match st ((ok s) (stringFromInt64 s.mtimeNs)) ((err _) "-1")))
        (prevFs (mapGet prev p))
        (sha (match prevFs
               ((some fs) (if (and (= (optionOr (listGet fs 1) "") curSize) (= (optionOr (listGet fs 2) "") curMtime))
                            (optionOr (listGet fs 0) "")
                            (loggedDigest "manifestStamp" (resolveIn (toolRoot) p))))
               ((none) (loggedDigest "manifestStamp" (resolveIn (toolRoot) p)))))]
    (str sha " " curSize " " curMtime))

fn ! manifestPrevStamps slot: String -> (Map String (List String))
  (match (fileReadString (str slot "/manifest"))
    ((err _) (mapEmpty))
    ((ok text) (fold (fn [(m (Map String (List String))) (e (Option (List String)))] -> (Map String (List String))
                       (match e
                         ((none) m)
                         ((some fs) (if (= (listLength fs) 4) (mapSet m (optionOr (listGet fs 3) "") fs) m))))
                     (mapEmpty) (manifestEntries text))))

fn manifestKind text: String -> String
  (optionOr (listGet (stringSplit (optionOr (listHead (stringLines text)) "") " ") 1) "")

fn manifestEntry stamped: Bool line: String -> (Option (List String))
  (let [(parts (stringSplit line " "))]
    (cond
      ((and (not stamped) (>= (listLength parts) 2))
       (some (list (optionOr (listGet parts 0) "") "-" "-" (stringJoin (listDrop parts 1) " "))))
      ((< (listLength parts) 4) (none))
      (else (some (list (optionOr (listGet parts 0) "") (optionOr (listGet parts 1) "") (optionOr (listGet parts 2) "")
                        (stringJoin (listDrop parts 3) " "))))))

fn manifestEntries text: String -> (List (Option (List String)))
  (let [(header (optionOr (listHead (stringLines text)) ""))
        (stamped (or (stringStartsWith? header "nativeTest/5") (or (stringStartsWith? header "nativeTest/6") (stringStartsWith? header "nativeTest/7"))))]
    (map (fn [(l String)] -> (Option (List String)) (manifestEntry stamped l))
         (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (optionOr (listTail (stringLines text)) (list)))))

fn manifestFiles text: String -> (List String)
  (map (fn [(e (Option (List String)))] -> String (match e ((some fs) (optionOr (listGet fs 3) "")) ((none) ""))) (manifestEntries text))

fn resolveIn root: String p: String -> String
  (if (or (= root ".") (stringStartsWith? p "/")) p (str root "/" p))

fn ! entryHolds? root: String manifestMtime: Int64 fields: (List String) -> Bool
  (let [(p (resolveIn root (optionOr (listGet fields 3) "")))
        (sha (optionOr (listGet fields 0) ""))
        (size (optionOr (listGet fields 1) ""))
        (mtime (optionOr (listGet fields 2) ""))]
    (match (fileStat p)
      ((err _) false)
      ((ok st) (or (and (= (stringFromInt64 st.size) size)
                        (and (= (stringFromInt64 st.mtimeNs) mtime) (< st.mtimeNs manifestMtime)))
                   (= (loggedDigest "entryHolds" p) sha)))))

fn ! manifestHoldsAt root: String manifestMtime: Int64 text: String -> Bool
  (let [(entries (manifestEntries text))]
    (and (not (listEmpty? entries))
         (fold (fn [(acc Bool) (e (Option (List String)))] -> Bool
                 (and acc (match e ((none) false) ((some fs) (entryHolds? root manifestMtime fs)))))
               true entries)))

fn ! manifestHolds? text: String -> Bool
  (manifestHoldsAt "." -1 text)

fn ! writeAtomic path: String text: String -> (Result Unit String)
  (let [(tmp (str path ".tmp." (monotonicNs)))]
    (match (fileWrite tmp text)
      ((err e) (err e))
      ((ok _) (pathRename tmp path))))

fn ! entryHoldsLine root: String manifestMtime: Int64 fields: (List String) -> (Pair Bool String)
  (let [(path (optionOr (listGet fields 3) ""))
        (p (resolveIn root path))
        (sha (optionOr (listGet fields 0) ""))
        (size (optionOr (listGet fields 1) ""))
        (mtime (optionOr (listGet fields 2) ""))
        (staleLine (str sha " " size " " mtime " " path))]
    (match (fileStat p)
      ((err _) (pair false staleLine))
      ((ok st)
       (if (and (= (stringFromInt64 st.size) size) (and (= (stringFromInt64 st.mtimeNs) mtime) (< st.mtimeNs manifestMtime)))
         (pair true staleLine)
         (if (= (loggedDigest "entryHolds" p) sha)
           (pair true (str sha " " (stringFromInt64 st.size) " " (stringFromInt64 st.mtimeNs) " " path))
           (pair false staleLine))))))

fn manifestHeader text: String -> String
  (optionOr (listHead (stringLines text)) "")

fn fieldsLine fields: (List String) -> String
  (str (optionOr (listGet fields 0) "") " " (optionOr (listGet fields 1) "") " " (optionOr (listGet fields 2) "") " " (optionOr (listGet fields 3) ""))

fn ! manifestHoldsRestampAt root: String manifestMtime: Int64 text: String -> (Pair Bool String)
  (let [(entries (manifestEntries text))
        (folded (fold (fn [(acc (Pair Bool (List String))) (e (Option (List String)))] -> (Pair Bool (List String))
                        (match e
                          ((none) (pair false (pairSecond acc)))
                          ((some fs)
                           (if (not (pairFirst acc))
                             (pair false (listAppend (pairSecond acc) (list (fieldsLine fs))))
                             (let [(r (entryHoldsLine root manifestMtime fs))]
                               (pair (pairFirst r) (listAppend (pairSecond acc) (list (pairSecond r)))))))))
                      (pair true (list)) entries))]
    (pair (and (not (listEmpty? entries)) (pairFirst folded))
          (str (manifestHeader text) "\n" (stringJoin (pairSecond folded) "\n") "\n")))

fn ! manifestFileHolds? root: String path: String text: String -> Bool
  (let [(manifestMtime (match (fileStat path) ((ok st) st.mtimeNs) ((err _) -1)))
        (result (manifestHoldsRestampAt root manifestMtime text))
        (holds (pairFirst result))
        (freshText (pairSecond result))
        (stillSame (= (match (fileStat path) ((ok st) st.mtimeNs) ((err _) -1)) manifestMtime))]
    (do (if (and holds (and (!= freshText text) stillSame)) (writeAtomic path freshText) (ok ()))
        holds))

fn interfaceDigest forms: (List ast/TopForm) -> String
  (let [(modHead (fold (fn [(acc (Option ast/ModuleNode)) (t ast/TopForm)] -> (Option ast/ModuleNode)
                         (match acc ((some _) acc) ((none) (match t ((ast/topModule m) (some m)) (_ (none))))))
                       (none) forms))
        (modName (match modHead ((some m) m.path) ((none) "")))
        (exports (match modHead ((some m) m.exported) ((none) (list))))
        (items (fold (fn [(acc (List String)) (t ast/TopForm)] -> (List String)
                       (match t
                         ((ast/topDefun d)
                          (if (listContains? exports d.name)
                            (cons (str "fn " d.name (if d.effect " !" "") " [" (stringJoin (map (fn [(p ast/Param)] -> String (str p.name ": " p.type)) d.params) " ") "] -> " d.retType) acc)
                            acc))
                         ((ast/topSchema s)
                          (if (listContains? exports s.name)
                            (cons (str "schema " s.name " " (stringJoin (map (fn [(f ast/AstField)] -> String (str "(:f " f.name " " f.type ")")) s.fields) " ")) acc)
                            acc))
                         ((ast/topEnum e)
                          (if (listContains? exports e.name)
                            (cons (str "enum " e.name " " (stringJoin (map (fn [(c ast/EnumCase)] -> String (str "(" c.name " " (stringJoin (map (fn [(p ast/Param)] -> String (str p.name ": " p.type)) c.fields) " ") ")")) e.cases) " ")) acc)
                            acc))
                         ((ast/topModule _) acc)
                         ((ast/topExpr _) acc)))
                     (list) forms))
        (sorted (listSort items))
        (canonical (str "(interface " modName "\n  " (stringJoin sorted "\n  ") "\n)"))]
    (bytesSha256 (stringToBytes canonical)))

fn moduleCacheKey compVer: String path: String srcHash: String importHashes: (List String) -> String
  (let [(body (str "mod/1\n" compVer "\n" path "\n" srcHash "\n" (stringJoin (listSort importHashes) "\n")))]
    (bytesSha256 (stringToBytes body)))

(schema Built
  (:f binary (Option String))
  (:f reason String)
  (:f cache String)
  (:f recompiled (List String))
  (:f reused (List String))
  (:f depsMs Int64)
  (:f asl1Ms Int64)
  (:f clangMs Int64))

fn firstLines text: String n: Int64 -> String
  (stringJoin (listTake (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines text)) n) " | ")

fn ! storeFallback slot: String deps: (List String) reason: String t: (List Int64) -> Built
  (let [(prevStamps (manifestPrevStamps slot))
        (stored (match (writeAtomic (str slot "/reason") reason)
                  ((err e) (err e))
                  ((ok _) (writeAtomic (str slot "/manifest") (manifestTextWith prevStamps "fallback" deps)))))]
    (do (match stored
          ((err e) (eprintln (str "nativeTest: cannot cache the fallback in " slot ": " e)))
          ((ok _) ()))
        (Built :binary (none) :reason reason :cache "miss" :recompiled (list) :reused (list)
               :depsMs (optionOr (listGet t 0) 0) :asl1Ms (optionOr (listGet t 1) 0) :clangMs (optionOr (listGet t 2) 0))))

; (:m :ref NATIVETEST-CACHE-KEY-IMPORTS-20261022 :do "a closure-load failure names a module the manifest never lists (only the suite file is recorded), so a cached verdict could not notice an edit to an imported module and kept serving the failure; loading is a parse-only step, so the failure is reported without being stored")
fn uncachedFailure reason: String t: (List Int64) -> Built
  (Built :binary (none) :reason reason :cache "miss" :recompiled (list) :reused (list)
         :depsMs (optionOr (listGet t 0) 0) :asl1Ms (optionOr (listGet t 1) 0) :clangMs (optionOr (listGet t 2) 0))

(schema ModCompileResult
  (:f path String)
  (:f ok Bool)
  (:f obj String)
  (:f recompiled Bool)
  (:f preludeRefs (List String))
  (:f initName String)
  (:f err String))

fn ! readVerifiedMeta metaPath: String objPath: String -> (Option (List String))
  (if (not (and (fileExists? objPath) (fileExists? metaPath)))
    (none)
    (match (fileReadString metaPath)
      ((err _) (none))
      ((ok metaText)
       (let [(lines (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringLines metaText)))]
         (if (< (listLength lines) 3)
           (none)
           (let [(storedSha (optionOr (listGet lines 0) ""))
                 (storedSize (optionOr (listGet lines 1) ""))
                 (storedMtime (optionOr (listGet lines 2) ""))
                 (refs (listDrop lines 3))
                 (st (fileStat objPath))
                 (curSize (match st ((ok s) (stringFromInt64 s.size)) ((err _) "-1")))
                 (curMtime (match st ((ok s) (stringFromInt64 s.mtimeNs)) ((err _) "-1")))]
             (if (not (= storedSize curSize))
               (none)
               (if (or (= storedMtime curMtime) (= storedSha (loggedDigest "readVerifiedMeta" objPath)))
                 (do (fileUtime metaPath (nowNs)) (some refs))
                 (none)))))))))

; (:m :ref RUN-ENTRY-REBUILD-COST :do "the fingerprint holds clang's version and target triple, so the host's uname -s -m is the same for every build under one fingerprint: it is spawned once per fingerprint and kept beside its slots as fp/uname (a few bytes), and a warm build forks no uname")
fn ! unameIn! cDir: String fp: String -> (Result String String)
  (let [(dir (str cDir "/" fp))
        (memo (str dir "/uname"))
        (kept (resultOr (fileReadString memo) ""))]
    (if (not (stringEmpty? (stringTrim kept)))
      (ok kept)
      (let [(out (runProc (list "uname" "-s" "-m") (none)))]
        (if (!= out.exitCode 0)
          (err (str "uname -s -m exited " out.exitCode ": " out.stderr))
          (do (dirCreate dir) (writeAtomic memo out.stdout)
              (ok out.stdout))))))

fn ! nativeFacts! cDir: String fp: String -> (Option libc/TripleFacts)
  (match (unameIn! cDir fp)
    ((err e) (do (eprintln (str "nativeTest: " e "; building unrouted")) (none)))
    ((ok text)
      (match (route/hostFactsOf text)
        ((err e) (do (eprintln (str "nativeTest: " e "; building unrouted")) (none)))
        ((ok f) f))))

fn emitModuleFor facts: (Option libc/TripleFacts) m: irTy/SsaModule -> (Result String (List irTy/IrDiag))
  (match facts ((some f) (nat/emitLlvmModuleFor f m)) ((none) (llvm/emitLlvmModule m)))

fn emitProgramFor facts: (Option libc/TripleFacts) m: irTy/SsaModule entry: String -> (Result String (List irTy/IrDiag))
  (match facts ((some f) (nat/emitLlvmProgramFor f m entry)) ((none) (llvm/emitLlvmProgram m entry)))

; (:m :ref HL-FIXWAVE :do "the unrouted (facts none) branch used to add asl/host/out/libaslhost.a to the link, the same dead-archive fallback build.asl's linkLibs! carried (HL-DELETE: no host archive exists, routed or not); both branches now link libaslrt.a alone, matching build.asl's own fix")
fn ! linkArchives facts: (Option libc/TripleFacts) -> (List String)
  (match facts ((some _) (list (toolPath "asl/host/out/libaslrt.a"))) ((none) (list (toolPath "asl/host/out/libaslrt.a"))))

fn overlayNamesOf o: lk/LinkUnit -> (List String)
  (lk/definedNames o)

fn overlayFormName t: ast/TopForm -> (Option String)
  (match t ((ast/topDefun d) (some d.name)) (_ (none)))

; (:m :ref KNOWCARDS-OVERLAY-DUP-20261018 :do "lk/overlayUnitAt! scans every *.asl file directly under nativeOverlayDir and concatenates their forms; a leaked printHostValidLib.asl temp fixture (.asl_chk_print_*.asl, gitignored but orphaned when its owning process is killed mid-test) landing in that directory duplicated every overlay function's defun form, so overlayRewrite's :only lowering produced two SsaFunctions named prelude.parquetOpen and verify's functions+externs duplicate check correctly flagged it; dedupe the overlay's own defun forms by name (first occurrence wins) before appending to prelude, so a stray extra file in that directory can never double-define a claimed builtin again")
fn dedupeOverlayFold acc: (Pair (Map String Bool) (List ast/TopForm)) t: ast/TopForm -> (Pair (Map String Bool) (List ast/TopForm))
  (let [(seen (pairFirst acc))
        (out (pairSecond acc))
        (name (overlayFormName t))
        (dup (match name ((none) false) ((some n) (mapHas? seen n))))]
    (if dup
      acc
      (pair (match name ((none) seen) ((some n) (mapSet seen n true))) (listAppend out (list t)))))

fn dedupeOverlayForms forms: (List ast/TopForm) -> (List ast/TopForm)
  (pairSecond (fold dedupeOverlayFold (pair (mapEmpty) (list)) forms))

fn withOverlay prelude: lk/LinkUnit o: lk/LinkUnit -> lk/LinkUnit
  (lk/LinkUnit :path prelude.path :name prelude.name :forms (listAppend prelude.forms (dedupeOverlayForms (optionOr (listTail o.forms) (list)))) :positions prelude.positions :imports prelude.imports)

fn moduleBuiltinNames functions: (List irTy/SsaFunction) -> (List String)
  (dedupeStr (fold (fn [(a (List String)) (f irTy/SsaFunction)] -> (List String) (listAppend a (lk/functionBuiltinRefs f))) (list) functions))

fn overlayResolved names: (List String) -> (Map String String)
  (fold (fn [(m (Map String String)) (n String)] -> (Map String String) (mapSet m n (str "prelude." n))) (mapEmpty) names)

fn overlayRewrite m: irTy/SsaModule px: lk/LinkUnit names: (List String) -> (Result irTy/SsaModule (List irTy/IrDiag))
  (let [(claimed (filter (fn [(n String)] -> Bool (listContains? names n)) (moduleBuiltinNames m.functions)))]
    (if (listEmpty? claimed)
      (ok m)
      (match (low/lowerLinked px.forms px.positions (low/LinkScope :path px.path :imports (mapEmpty) :prelude (list) :strings (list) :only (some claimed)))
        ((err ds) (err ds))
        ((ok sm)
          (let [(callees (filter (fn [(f irTy/SsaFunction)] -> Bool (listContains? claimed (optionOr (stringSlice f.name 8 (stringLength f.name)) ""))) sm.functions))
                (rewritten (lk/rewriteModuleBuiltinsAgainst (overlayResolved claimed) callees m))
                (externs (map (fn [(f irTy/SsaFunction)] -> irTy/SsaExtern (irTy/ssaExternTyped f.name (map (fn [(p irTy/SsaParam)] -> irTy/SsaTy p.ty) f.params) f.retTy)) callees))]
            (ok (irTy/ssaModule m.name m.strings m.types m.records (listAppend m.externs externs) m.globals rewritten.functions)))))))

fn overlayRounds px: lk/LinkUnit names: (List String) acc: lk/LinkAcc -> lk/LinkAcc
  (let [(functions (lk/allFunctions acc.modules))
        (defined (map (fn [(f irTy/SsaFunction)] -> String f.name) functions))
        (seeds (filter (fn [(n String)] -> Bool (and (listContains? names n) (not (listContains? defined (str "prelude." n))))) (moduleBuiltinNames functions)))]
    (if (or (listEmpty? seeds) (not (listEmpty? acc.diags)))
      acc
      (match (low/lowerLinked px.forms px.positions (low/LinkScope :path px.path :imports (mapEmpty) :prelude (list) :strings acc.strings :only (some seeds)))
        ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds)))
        ((ok m) (overlayRounds px names (lk/lowerPrelude px (lk/LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested (listAppend acc.requested seeds) :diags acc.diags)))))))

(schema PendingObj
  (:f path String)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f tmpLl String)
  (:f tmpO String)
  (:f objPath String)
  (:f metaPath String)
  (:f pExts (List String))
  (:f initName String)
  (:f lowerMs Int64)
  (:f emitMs Int64)
  (:f llcStart Int64)
  (:f opt String))

(schema UnitStep
  (:f done (Option ModCompileResult))
  (:f pending (Option PendingObj)))

fn unitFailed path: String e: String -> UnitStep
  (UnitStep :done (some (ModCompileResult :path path :ok false :obj "" :recompiled true :preludeRefs (list) :initName "" :err e)) :pending (none))

; (:m :ref BIN-NO-PERSIST-20261026 :do "the key holds the unit name: an implicit script module is named by its path as seen from the cwd (greet from its own dir, asl/packages/.../greet from the root), and an object compiled under one name linked under the other left greet.main undefined once run binaries stopped being reused")
; (:m :ref RUN-ENTRY-REBUILD-COST :do "the entry wrapper is keyed by its text, imports and inits, not its path: an ephemeral run writes it under a per-run name, and the same text lowers to the same object wherever it sits, so a warm run reuses the wrapper object instead of compiling it again")
fn ! unitKey fp: String u: lk/LinkUnit ifaceMap: (Map String String) isEntry: Bool inits: (List String) -> String
  (moduleCacheKey fp (if isEntry "@entry" u.path) (fileDigest u.path)
                  (listAppend (map (fn [(imp (Pair String String))] -> String (str (pairSecond imp) " " (optionOr (mapGet ifaceMap (pairSecond imp)) ""))) u.imports)
                              (cons (str "@name " u.name) (if isEntry (list (str "@inits " (stringJoin inits ","))) (list)))))

; (:m :ref RUN-ENTRY-REBUILD-COST :do "an ephemeral slot keeps only the objects of transient text (-e, -, eval) and of an entry whose closure holds such text; a script's entry object goes to the shared module cache, content-addressed and swept like any other")
fn ! slotObject? slot: String u: lk/LinkUnit units: (List lk/LinkUnit) isEntry: Bool -> Bool
  (and (ephemeralSlot? slot)
       (or (transientSource? u.path)
           (and isEntry (not (listEmpty? (filter (fn [(x lk/LinkUnit)] -> Bool (transientSource? x.path)) units))))))

fn hitResult path: String objPath: String refs: (List String) -> ModCompileResult
  (ModCompileResult :path path :ok true :obj objPath :recompiled false
                    :preludeRefs (filter (fn [(r String)] -> Bool (not (stringStartsWith? r "@init:"))) refs)
                    :initName (optionOr (listHead (map (fn [(r String)] -> String (optionOr (stringSlice r 6 (stringLength r)) "")) (filter (fn [(r String)] -> Bool (stringStartsWith? r "@init:")) refs))) "")
                    :err "")

fn ! unitObjPath cDir: String fp: String slot: String u: lk/LinkUnit units: (List lk/LinkUnit) ifaceMap: (Map String String) isEntry: Bool inits: (List String) -> String
  (str (if (slotObject? slot u units isEntry) slot (modulesDirIn cDir)) "/" (unitKey fp u ifaceMap isEntry inits))

; (:m :ref RUN-ENTRY-REBUILD-COST :do "every unit of the closure, the entry last with the inits of the units before it, as compileUnitsStep keys them; none at the first unit whose object is not cached")
fn ! cachedUnits cDir: String fp: String slot: String units: (List lk/LinkUnit) ifaceMap: (Map String String) entry: lk/LinkUnit -> (Option (List ModCompileResult))
  (fold (fn [(acc (Option (List ModCompileResult))) (u lk/LinkUnit)] -> (Option (List ModCompileResult))
          (match acc
            ((none) (none))
            ((some rs)
             (let [(isEntry (= u.name entry.name))
                   (stem (unitObjPath cDir fp slot u units ifaceMap isEntry (filter (fn [(n String)] -> Bool (not (stringEmpty? n))) (map (fn [(r ModCompileResult)] -> String r.initName) rs))))]
               (match (readVerifiedMeta (str stem ".meta") (str stem ".o"))
                 ((none) (none))
                 ((some refs) (some (listAppend rs (list (hitResult u.path (str stem ".o") refs))))))))))
        (some (list)) units)

; (:m :ref RUN-ENTRY-REBUILD-COST :do "a build whose every unit object and the full prelude object are cached links them at once: the prelude and the native overlay are not parsed and nothing is lowered, so a warm run spawns one clang, the link")
fn ! cachedLink! cDir: String fp: String slot: String bin: String key: String uRes: (Result (List lk/LinkUnit) (List irTy/IrDiag)) t0: Int64 -> (Option Built)
  (match uRes
    ((err _) (none))
    ((ok units)
     (if (or (listEmpty? units) (not (fullPreludeWanted?)))
       (none)
       (let [(darwin (hostDarwin? cDir fp))
             (pStem (str (modulesDirIn cDir) "/prelude-full-" (fullPreludeKey fp (preludeDigestIn (toolRoot)) (optLevelFor "run") (preludeSectionFlags darwin))))]
         (match (readVerifiedMeta (str pStem ".meta") (str pStem ".o"))
           ((none) (none))
           ((some _)
            (match (cachedUnits cDir fp slot units (ifaceMapOf units) (optionOr (listGet units (- (listLength units) 1)) (lk/emptyUnit "")))
              ((none) (none))
              ((some results)
               (let [(t1 (monotonicNs))
                     (_ (telemetry "NATIVE-PRELUDE-CACHE :hit :full"))]
                 (some (linkUnits! slot bin (closureDeps units key) (str pStem ".o") results darwin (nativeFacts! cDir fp) t0 t1 t1)))))))))))

fn ! compileUnitPrepare facts: (Option libc/TripleFacts) cDir: String fp: String u: lk/LinkUnit units: (List lk/LinkUnit) ifaceMap: (Map String String) prelude: lk/LinkUnit px: lk/LinkUnit ovlNames: (List String) entry: lk/LinkUnit slot: String counter: Int64 inits: (List String) opt: String -> UnitStep
  (let [(isEntry (= u.name entry.name))
        (uKey (unitKey fp u ifaceMap isEntry inits))
        (objDir (if (slotObject? slot u units isEntry) slot (modulesDirIn cDir)))
        (objPath (str objDir "/" uKey ".o"))
        (metaPath (str objDir "/" uKey ".meta"))]
    (match (readVerifiedMeta metaPath objPath)
      ((some refs)
       (UnitStep :done (some (hitResult u.path objPath refs)) :pending (none)))
      ((none)
       (let [(_ (if (fileExists? objPath) (pathRemove objPath) (ok ())))
             (_ (if (fileExists? metaPath) (pathRemove metaPath) (ok ())))
             (scope (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings (list) :only (none)))
             (lowerStart (monotonicNs))
             (mRes (match (low/lowerLinked u.forms u.positions scope) ((err ds0) (err ds0)) ((ok m0) (overlayRewrite m0 px ovlNames))))
             (lowerEnd (monotonicNs))
             (_ (telemetry (str "NATIVE-MODULE-PHASE " u.path " :lowerMs " (ms (- lowerEnd lowerStart)))))]
        (match mRes
          ((err ds) (unitFailed u.path (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")))
          ((ok m)
           (let [(emitStart (monotonicNs))
                 (llRes (if isEntry
                          (match (emitProgramFor facts m (str m.name ".main"))
                            ((err ds) (err ds))
                            ((ok text) (match (llvm/linkInits text (cons "prelude" inits))
                                         ((ok linked) (ok linked))
                                         ((err e) (err (list (irTy/makeIrDiag "ERR_LLVM_ENTRY" e u.path)))))))
                          (emitModuleFor facts m)))
                 (emitEnd (monotonicNs))
                 (_ (telemetry (str "NATIVE-MODULE-PHASE " u.path " :emitMs " (ms (- emitEnd emitStart)))))]
             (match llRes
               ((err ds2) (unitFailed u.path (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds2) "; ")))
               ((ok ll)
                (let [(tmpLl (str slot "/" uKey "." (stringFromInt64 (procSelf)) "." (stringFromInt64 counter) ".ll"))
                      (tmpO (str slot "/" uKey "." (stringFromInt64 (procSelf)) "." (stringFromInt64 counter) ".part.o"))]
                  (match (writeAtomic tmpLl ll)
                    ((err we) (unitFailed u.path (str "cannot write " tmpLl ": " we)))
                    ((ok _)
                     (UnitStep :done (none)
                               :pending (some (PendingObj :path u.path :pid 0 :outFd -1 :errFd -1 :tmpLl tmpLl :tmpO tmpO :objPath objPath :metaPath metaPath
                                                          :pExts (filter (fn [(n String)] -> Bool (stringStartsWith? n "prelude.")) (map (fn [(e irTy/SsaExtern)] -> String e.name) m.externs))
                                                          :initName (if (llvm/definesInit? ll m.name) m.name "")
                                                          :lowerMs (ms (- lowerEnd lowerStart)) :emitMs (ms (- emitEnd emitStart)) :llcStart 0 :opt opt)))))))))))))))

fn ! compileUnitSpawn p: PendingObj -> UnitStep
  (match (procSpawnv (list (clangCommand) p.opt "-Wno-override-module" "-c" p.tmpLl "-o" p.tmpO) (none) (none))
    ((err e) (unitFailed p.path (str "spawn failed: " e)))
    ((ok sp)
     (let [(_ (fdClose sp.stdin))
           (_ (fdNonBlocking sp.stdout true))
           (_ (fdNonBlocking sp.stderr true))
           (startNs (monotonicNs))
           (_ (jobEventLog! (str "NATIVE-JOB-SPAWN :pid " sp.pid " :tNs " startNs " :path " p.path)))]
       (UnitStep :done (none)
                 :pending (some (PendingObj :path p.path :pid sp.pid :outFd sp.stdout :errFd sp.stderr :tmpLl p.tmpLl :tmpO p.tmpO
                                            :objPath p.objPath :metaPath p.metaPath :pExts p.pExts :initName p.initName
                                            :lowerMs p.lowerMs :emitMs p.emitMs :llcStart startNs :opt p.opt))))))

fn ! compileUnitFinish p: PendingObj -> ModCompileResult
  (let [(cRes (pumpCollect p.outFd p.errFd "" "" true true p.pid))
        (finishNs (monotonicNs))
        (llcMs (ms (- finishNs p.llcStart)))
        (_ (telemetry (str "NATIVE-MODULE-PHASE " p.path " :llcMs " llcMs)))
        (_ (jobEventLog! (str "NATIVE-JOB-FINISH :pid " p.pid " :tNs " finishNs " :path " p.path)))
        (rmLl (if (some? (envGet "ASL_NATIVE_KEEP_LL")) (ok ()) (pathRemove p.tmpLl)))
        (fail (fn [(e String)] -> ModCompileResult (ModCompileResult :path p.path :ok false :obj "" :recompiled true :preludeRefs (list) :initName "" :err e)))]
    (if (!= cRes.exitCode 0)
      (fail (firstLines cRes.stderr 3))
      (match (pathRename p.tmpO p.objPath)
        ((err me) (fail (str "cannot move to " p.objPath ": " me)))
        ((ok _)
         (let [(objSha (fileDigest p.objPath))
               (objStat (fileStat p.objPath))
               (objSize (match objStat ((ok st) (stringFromInt64 st.size)) ((err _) "-1")))
               (objMtime (match objStat ((ok st) (stringFromInt64 st.mtimeNs)) ((err _) "-1")))
               (metaContent (stringJoin (cons objSha (cons objSize (cons objMtime (listAppend p.pExts (if (stringEmpty? p.initName) (list) (list (str "@init:" p.initName))))))) "\n"))]
           (match (writeAtomic p.metaPath metaContent)
             ((err me) (fail (str "cannot write metadata " p.metaPath ": " me)))
             ((ok _) (do (telemetry (str "NATIVE-MODULE-PHASES :lowerMs " p.lowerMs " :emitMs " p.emitMs " :llcMs " llcMs))
                         (ModCompileResult :path p.path :ok true :obj p.objPath :recompiled true :preludeRefs p.pExts :initName p.initName :err "")))))))))

(schema PreludeCompileResult
  (:f ok Bool)
  (:f obj String)
  (:f err String))

(schema PendingPrelude
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f tmpPLl String)
  (:f tmpPO String)
  (:f preludeObj String)
  (:f preludeMeta String))

(schema PreludeStep
  (:f done (Option PreludeCompileResult))
  (:f pending (Option PendingPrelude)))

fn dedupeStr xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (s String)] -> (List String) (if (listContains? acc s) acc (cons s acc))) (list) xs)

fn preludeFailed err: String -> PreludeStep
  (PreludeStep :done (some (PreludeCompileResult :ok false :obj "" :err err)) :pending (none))

fn ! compilePreludeSpawn slot: String preludeKey: String preludeObj: String preludeMeta: String rawLl: String counter: Int64 opt: String extra: (List String) -> PreludeStep
  (let [(pLl (llvm/ensureInit rawLl "prelude"))
        (tmpPLl (str slot "/prelude-" preludeKey "." (stringFromInt64 (procSelf)) "." (stringFromInt64 counter) ".ll"))
        (tmpPO (str slot "/prelude-" preludeKey "." (stringFromInt64 (procSelf)) "." (stringFromInt64 counter) ".part.o"))
        (wRes (writeAtomic tmpPLl pLl))]
    (match wRes
      ((err we) (preludeFailed (str "cannot write " tmpPLl ": " we)))
      ((ok _)
       (match (procSpawnv (cons (clangCommand) (cons opt (listAppend extra (list "-Wno-override-module" "-c" tmpPLl "-o" tmpPO)))) (none) (none))
         ((err e) (preludeFailed (str "spawn failed: " e)))
         ((ok sp)
          (let [(_ (fdClose sp.stdin))
                (_ (fdNonBlocking sp.stdout true))
                (_ (fdNonBlocking sp.stderr true))]
            (PreludeStep :done (none)
                         :pending (some (PendingPrelude :pid sp.pid :outFd sp.stdout :errFd sp.stderr :tmpPLl tmpPLl :tmpPO tmpPO :preludeObj preludeObj :preludeMeta preludeMeta)))))))))

fn ! compilePreludeAwait pp: PendingPrelude -> PreludeCompileResult
  (let [(cRes (pumpCollect pp.outFd pp.errFd "" "" true true pp.pid))
        (rmLl (if (some? (envGet "ASL_NATIVE_KEEP_LL")) (ok ()) (pathRemove pp.tmpPLl)))]
    (if (!= cRes.exitCode 0)
      (do (if (fileExists? pp.tmpPO) (match (pathRemove pp.tmpPO) ((ok _) ()) ((err _) ())) ())
          (PreludeCompileResult :ok false :obj "" :err (firstLines cRes.stderr 3)))
      (match (pathRename pp.tmpPO pp.preludeObj)
        ((err me) (PreludeCompileResult :ok false :obj "" :err (str "cannot move to " pp.preludeObj ": " me)))
        ((ok _)
         (let [(objSha (fileDigest pp.preludeObj))
               (objStat (fileStat pp.preludeObj))
               (objSize (match objStat ((ok st) (stringFromInt64 st.size)) ((err _) "-1")))
               (objMtime (match objStat ((ok st) (stringFromInt64 st.mtimeNs)) ((err _) "-1")))
               (metaContent (stringJoin (list objSha objSize objMtime) "
"))
               (metaRes (writeAtomic pp.preludeMeta metaContent))]
           (match metaRes
             ((err me) (PreludeCompileResult :ok false :obj "" :err (str "cannot write metadata " pp.preludeMeta ": " me)))
             ((ok _) (PreludeCompileResult :ok true :obj pp.preludeObj :err ""))))))))

fn ! compilePreludeAwaitStep step: PreludeStep -> PreludeCompileResult
  (match step.pending
    ((some pp) (compilePreludeAwait pp))
    ((none) (optionOr step.done (PreludeCompileResult :ok false :obj "" :err "no prelude build was started"))))

fn ! hostDarwin? cDir: String fp: String -> Bool
  (match (unameIn! cDir fp)
    ((ok text) (= (optionOr (listHead (stringSplit (stringTrim text) " ")) "") "Darwin"))
    ((err _) false))

fn ! preludeSectionFlags darwin: Bool -> (List String)
  (if darwin (list) (list "-ffunction-sections" "-fdata-sections"))

fn ! deadStripFlags darwin: Bool -> (List String)
  (if darwin (list "-Wl,-dead_strip") (list "-Wl,--gc-sections"))

; (:m :ref NATIVE-LOWER-GAPS :do "a closure that does not load is the program's own error (an unresolved import), not a native gap: its reason leads with the first diagnostic's code, which failLine keeps as the FAIL code; a parse error carries its path:line:col")
fn loadFailure ds: (List irTy/IrDiag) -> String
  (str (match (listHead ds) ((some d) d.code) ((none) "ERR_NATIVE_UNSUPPORTED")) ": closure load failed: " (stringJoin (map (fn [(d irTy/IrDiag)] -> String (if (and (= d.code "ERR_LOWER_PARSE") (not (stringEmpty? d.locus))) (str d.locus ": " d.message) d.message)) ds) "; "))

; (:m :ref U4-MARKER-PARITY :do "a checker-rejected reason (cache :checker-reject) already names its own path:line:col CODE, cosmetically rewritten back to the logical path the caller knows (checkerRejection!'s stringReplace); failReason must not re-wrap that behind ERR_NATIVE_UNSUPPORTED just because it does not start with ERR_")
fn failReason reason: String path: String -> String
  (str (if (or (stringStartsWith? reason "ERR_") (stringStartsWith? reason path)) "" "ERR_NATIVE_UNSUPPORTED: ") reason)

fn failLine path: String reason: String -> String
  (str "FAIL " path ": " (failReason reason path) " (after 0 asserts)")

fn diagText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn preludeLl facts: (Option libc/TripleFacts) prelude: lk/LinkUnit ovlNames: (List String) preludeFns: (List String) -> (Result String String)
  (if (listEmpty? preludeFns)
    (match (llvm/emitLlvmModule (irTy/ssaModule "prelude" (list) (list) (list) (list) (list) (list)))
      ((err ds) (err (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) ds) "; ")))
      ((ok pLl) (ok pLl)))
    (match (low/lowerLinked prelude.forms prelude.positions
                         (low/LinkScope :path prelude.path :imports (mapEmpty) :prelude (list) :strings (list) :only (some preludeFns)))
      ((err ds) (err (diagText ds)))
      ((ok m0)
       (let [(initAcc (lk/LinkAcc :strings m0.strings :modules (list m0) :requested preludeFns :diags (list)))
             (withPrelude (overlayRounds prelude ovlNames (lk/lowerPrelude prelude initAcc)))]
         (if (not (listEmpty? withPrelude.diags))
           (err (diagText withPrelude.diags))
           (let [(preludeMods withPrelude.modules)
                 (allPDecls (fold (fn [(a (List irTy/SsaTypeDecl)) (m irTy/SsaModule)] -> (List irTy/SsaTypeDecl) (listAppend a m.types)) (list) preludeMods))
                 (allPRecs (fold (fn [(a (List irTy/SsaRecordDecl)) (m irTy/SsaModule)] -> (List irTy/SsaRecordDecl) (listAppend a m.records)) (list) preludeMods))
                 (preludeMod (lk/rewriteModuleBuiltins (overlayResolved (filter (fn [(n String)] -> Bool (listContains? ovlNames n)) (moduleBuiltinNames (lk/allFunctions preludeMods))))
                               (irTy/ssaModule "prelude" withPrelude.strings (lk/firstByName allPDecls) (lk/firstRecordByName allPRecs) (list) (list) (lk/allFunctions preludeMods))))]
             (match (emitModuleFor facts preludeMod)
               ((err ds2) (err (diagText ds2)))
               ((ok pLl) (ok pLl)))))))))

fn ! dropStale objPath: String metaPath: String -> Unit
  (do (if (fileExists? objPath) (match (pathRemove objPath) ((ok _) ()) ((err _) ())) ())
      (if (fileExists? metaPath) (match (pathRemove metaPath) ((ok _) ()) ((err _) ())) ()))

fn ! compileSubsetPrelude facts: (Option libc/TripleFacts) cDir: String fp: String allPreludeRefs: (List String) prelude: lk/LinkUnit ovlNames: (List String) slot: String counter: Int64 opt: String extra: (List String) -> PreludeStep
  (let [(preludeFns (map (fn [(n String)] -> String (optionOr (stringSlice n 8 (stringLength n)) n)) allPreludeRefs))
        (preludeKey (bytesSha256 (stringToBytes (str "prelude/2
" fp "
" (preludeDigestIn (toolRoot)) "
" (stringJoin (listSort preludeFns) ",")))))
        (preludeObj (str (modulesDirIn cDir) "/prelude-" preludeKey ".o"))
        (preludeMeta (str (modulesDirIn cDir) "/prelude-" preludeKey ".meta"))]
    (match (readVerifiedMeta preludeMeta preludeObj)
      ((some _)
       (do (telemetry "NATIVE-PRELUDE-CACHE :hit :subset")
           (PreludeStep :done (some (PreludeCompileResult :ok true :obj preludeObj :err "")) :pending (none))))
      ((none)
       (let [(_ (dropStale preludeObj preludeMeta))]
         (match (preludeLl facts prelude ovlNames preludeFns)
           ((err e) (preludeFailed e))
           ((ok pLl) (compilePreludeSpawn slot preludeKey preludeObj preludeMeta pLl counter opt extra)))))))

; (:m :ref PRELUDEKEY :do "fp alone is the caller's claim and some callers pass a label (nativeOracle selfBuild), so a prelude object keyed by fp outlived its prelude: a 2026-10-18 object without HashMap was linked into units calling prelude.hashMapEmpty. Prelude keys now also cover the digests of the prelude source and native overlay files actually compiled")
fn ! preludeDigestIn root: String -> String
  (let [(at (fn [(rel String)] -> String (if (= root ".") rel (str root "/" rel))))
        (overlay (lk/nativeOverlayDir))
        (overlayDir (if (stringEndsWith? overlay "/") (optionOr (stringSlice overlay 0 (- (stringLength overlay) 1)) overlay) overlay))]
    (bytesSha256 (stringToBytes (stringJoin (map (fn [(l String)] -> String (relativeTo root l)) (listAppend (treeLines (at (lk/preludePath))) (treeLines (at overlayDir)))) "\n"))))

fn fullPreludeKey fp: String preludeDigest: String opt: String extra: (List String) -> String
  (bytesSha256 (stringToBytes (str "preludeFull/2\n" fp "\n" preludeDigest "\n" opt "\n" (stringJoin extra " "))))

fn ! compileFullPrelude facts: (Option libc/TripleFacts) cDir: String fp: String prelude: lk/LinkUnit ovlNames: (List String) slot: String counter: Int64 opt: String extra: (List String) -> (Option PreludeStep)
  (let [(key (fullPreludeKey fp (preludeDigestIn (toolRoot)) opt extra))
        (preludeObj (str (modulesDirIn cDir) "/prelude-full-" key ".o"))
        (preludeMeta (str (modulesDirIn cDir) "/prelude-full-" key ".meta"))
        (marker (str (modulesDirIn cDir) "/prelude-full-" key ".unsupported"))]
    (cond
      ((some? (readVerifiedMeta preludeMeta preludeObj))
       (do (telemetry "NATIVE-PRELUDE-CACHE :hit :full")
           (some (PreludeStep :done (some (PreludeCompileResult :ok true :obj preludeObj :err "")) :pending (none)))))
      ((fileExists? marker)
       (do (telemetry "NATIVE-PRELUDE-FULL :unsupported (cached); compiling the referenced subset")
           (none)))
      (else
       (let [(_ (dropStale preludeObj preludeMeta))
             (names (listSort (dedupeStr (lk/definedNames prelude))))]
         (match (preludeLl facts prelude ovlNames names)
           ((err e)
            (do (telemetry (str "NATIVE-PRELUDE-FULL :unsupported " (firstLines e 1) "; compiling the referenced subset"))
                (match (writeAtomic marker e) ((ok _) ()) ((err we) (eprintln (str "nativeTest: cannot write " marker ": " we))))
                (none)))
           ((ok pLl)
            (do (telemetry (str "NATIVE-PRELUDE-CACHE :miss :full :fns " (listLength names)))
                (some (compilePreludeSpawn slot (str "full-" key) preludeObj preludeMeta pLl counter opt extra)))))))))

fn ! fullPreludeWanted? -> Bool
  (match (envGet "ASL_NATIVE_PRELUDE") ((some v) (!= v "subset")) ((none) true))

fn ! finishOldest acc: (List ModCompileResult) inFlight: (List PendingObj) -> (Pair (List ModCompileResult) (List PendingObj))
  (match (listHead inFlight)
    ((none) (pair acc inFlight))
    ((some p) (pair (listAppend acc (list (compileUnitFinish p))) (optionOr (listTail inFlight) (list)))))

fn ! drainAllPending acc: (List ModCompileResult) inFlight: (List PendingObj) -> (List ModCompileResult)
  (if (listEmpty? inFlight)
    acc
    (let [(r (finishOldest acc inFlight))]
      (drainAllPending (pairFirst r) (pairSecond r))))

fn ! compileUnitsStep facts: (Option libc/TripleFacts) cDir: String fp: String units: (List lk/LinkUnit) allUnits: (List lk/LinkUnit) ifaceMap: (Map String String) prelude: lk/LinkUnit px: lk/LinkUnit ovlNames: (List String) entry: lk/LinkUnit slot: String idx: Int64 acc: (List ModCompileResult) inFlight: (List PendingObj) jobs: Int64 opt: String -> (Pair (List ModCompileResult) (List PendingObj))
  (match (listHead units)
    ((none) (pair acc inFlight))
    ((some u)
     (let [(_ (leaveIfOrphaned!))
           (preTrim (if (>= (listLength inFlight) jobs) (finishOldest acc inFlight) (pair acc inFlight)))
           (acc0 (pairFirst preTrim))
           (inFlight0 (pairSecond preTrim))
           (inits (filter (fn [(n String)] -> Bool (not (stringEmpty? n)))
                          (listAppend (map (fn [(r ModCompileResult)] -> String r.initName) acc0)
                                      (map (fn [(p PendingObj)] -> String p.initName) inFlight0))))
           (prepared (compileUnitPrepare facts cDir fp u allUnits ifaceMap prelude px ovlNames entry slot idx inits opt))
           (step (match prepared.pending ((some p) (compileUnitSpawn p)) ((none) prepared)))
           (acc1 (match step.done ((some r) (listAppend acc0 (list r))) ((none) acc0)))
           (inFlight1 (match step.pending ((some p) (listAppend inFlight0 (list p))) ((none) inFlight0)))
           (rest (optionOr (listTail units) (list)))]
       (compileUnitsStep facts cDir fp rest allUnits ifaceMap prelude px ovlNames entry slot (+ idx 1) acc1 inFlight1 jobs opt))))

fn ! closureDeps units: (List lk/LinkUnit) key: String -> (List String)
  (let [(root (selfRoot))]
    (filter (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (not (stringEndsWith? p (str key ".asl")))))
            (map (fn [(u lk/LinkUnit)] -> String (relativeTo root u.path)) units)))

fn ! leaveIfOrphaned! -> Unit
  (match (envGet "ASL_NATIVE_SELF_PARENT")
    ((none) ())
    ((some text)
     (match (stringToInt64 text)
       ((none) ())
       ((some pid) (if (pidAlive? pid)
                     ()
                     (do (eprintln (str "nativeTest: the self builder " pid " is gone, so this stage stops"))
                         (match (procKill (procSelf) "SIGTERM") ((ok _) ()) ((err _) ()))))))))

fn ifaceMapOf units: (List lk/LinkUnit) -> (Map String String)
  (fold (fn [(acc (Map String String)) (u lk/LinkUnit)] -> (Map String String) (mapSet acc u.path (interfaceDigest u.forms))) (mapEmpty) units)

fn ! workerCount! jobs: Int64 -> Int64
  (let [(envK (match (envGet "ASL_NATIVE_WORKERS") ((none) 4) ((some s) (optionOr (stringToInt64 s) 4))))
        (cpus (resultOr (cpuCount) envK))]
    (max 1 (min (min envK cpus) jobs)))

; (:m :ref NATIVETEST-HOSTLESS :do "workers run one self binary: asl/tools/nativeTest.asl compiled once per fingerprint into the self cache (never the suite cache, so a suite's module and prelude counts never include nativeTest's own closure), only when ASL_NATIVE_WORKERS asks for two or more, and never the running executable; the self build itself and a worker get none")
fn ! workersAsked? -> Bool
  (> (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_WORKERS") "")) 0) 1)

fn ! runningExe? bin: String -> Bool
  (= (resultOr (realPath bin) bin) (resultOr (realPath (resultOr (procExePath) "")) ""))

fn ! buildSelfWorker! root: String fp: String cDir: String -> (Option String)
  (if (and (ok? (dirCreate cDir)) (takeLock! (str cDir "/lock") 3))
    (let [(_ (prune (selfDirIn root) fp))
          (_ (telemetry (str "NATIVE-SELF :build :fp " fp " :cache " cDir)))
          (t0 (monotonicNs))
          (built (prepareRunIn cDir (selfSource) fp))
          (_ (pathRemove (str cDir "/lock")))
          (_ (telemetry (str "NATIVE-SELF :" (if (some? built.binary) "built" "failed") " :fp " fp " :ms " (ms (- (monotonicNs) t0)) (if (some? built.binary) "" (str " " built.reason)))))]
      built.binary)
    (do (telemetry (str "NATIVE-SELF :busy :fp " fp " (another process holds " cDir "/lock, so this compile runs without workers)")) (none)))

fn ! selfWorker! fp: String -> (Option String)
  (let [(root (selfRoot))
        (cDir (selfCacheIn root fp))]
    (match (selfBinaryOf cDir root fp)
      ((some b) (some b))
      ((none) (buildSelfWorker! root fp cDir))))

fn ! workerArgv cDir: String fp: String -> (Option (List String))
  (cond
    ((some? (envGet "ASL_NATIVE_WORKER")) (none))
    ((not (workersAsked?)) (none))
    ((stringStartsWith? cDir (selfDirIn (selfRoot))) (none))
    (else (match (selfWorker! fp)
            ((some b) (if (runningExe? b) (none) (some (list b))))
            ((none) (none)))))

fn ! uncachedUnits cDir: String fp: String units: (List lk/LinkUnit) entry: lk/LinkUnit ifaceMap: (Map String String) -> (List lk/LinkUnit)
  (filter (fn [(u lk/LinkUnit)] -> Bool
            (and (!= u.name entry.name)
                 (let [(k (unitKey fp u ifaceMap false (list)))]
                   (none? (readVerifiedMeta (str (modulesDirIn cDir) "/" k ".meta") (str (modulesDirIn cDir) "/" k ".o"))))))
          units)

fn ! sourceSize u: lk/LinkUnit -> Int64
  (match (fileStat u.path) ((ok st) st.size) ((err _) 0))

fn leastLoaded groups: (List (Pair Int64 (List String))) -> Int64
  (pairFirst (fold (fn [(best (Pair Int64 Int64)) (i Int64)] -> (Pair Int64 Int64)
                     (let [(load (pairFirst (optionOr (listGet groups i) (pair 0 (list)))))]
                       (if (< load (pairSecond best)) (pair i load) best)))
                   (pair 0 (pairFirst (optionOr (listGet groups 0) (pair 0 (list)))))
                   (range 0 (listLength groups))))

fn ! balancedGroups todo: (List lk/LinkUnit) n: Int64 startupCost: Int64 -> (List (List String))
  (let [(sized (listSortBy (fn [(p (Pair Int64 String))] -> Int64 (- 0 (pairFirst p))) (map (fn [(u lk/LinkUnit)] -> (Pair Int64 String) (pair (sourceSize u) u.path)) todo)))
        (empty (map (fn [(i Int64)] -> (Pair Int64 (List String)) (pair (if (= i 0) 0 startupCost) (list))) (range 0 n)))
        (filled (fold (fn [(gs (List (Pair Int64 (List String)))) (p (Pair Int64 String))] -> (List (Pair Int64 (List String)))
                        (let [(target (leastLoaded gs))]
                          (map (fn [(i Int64)] -> (Pair Int64 (List String))
                                 (let [(g (optionOr (listGet gs i) (pair 0 (list))))]
                                   (if (= i target) (pair (+ (pairFirst g) (+ 1 (pairFirst p))) (listAppend (pairSecond g) (list (pairSecond p)))) g)))
                               (range 0 (listLength gs)))))
                      empty sized))]
    (map pairSecond filled))

(schema WorkerProc
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f units Int64))

(schema WorkerPlan
  (:f procs (List WorkerProc))
  (:f own (List String))
  (:f planned (List String))
  (:f jobs Int64))

fn ! spawnWorker! t0: Int64 base: (List String) env: (Option (List String)) acc: (List WorkerProc) g: (List String) -> (List WorkerProc)
  (match (procSpawnv (listAppend base g) (none) env)
    ((err e) (do (telemetry (str "NATIVE-WORKERS :spawn-failed " e " (the parent compiles these units after its workers)")) acc))
    ((ok sp) (do (fdClose sp.stdin) (fdNonBlocking sp.stdout true) (fdNonBlocking sp.stderr true)
                 (telemetry (str "NATIVE-WORKERS :worker-start :pid " sp.pid " :ms " (ms (- (monotonicNs) t0))))
                 (listAppend acc (list (WorkerProc :pid sp.pid :outFd sp.stdout :errFd sp.stderr :units (listLength g)))))))

fn ! fullPreludePending? cDir: String fp: String opt: String extra: (List String) -> Bool
  (let [(key (fullPreludeKey fp (preludeDigestIn (toolRoot)) opt extra))
        (stem (str (modulesDirIn cDir) "/prelude-full-" key))]
    (and (fullPreludeWanted?)
         (none? (readVerifiedMeta (str stem ".meta") (str stem ".o")))
         (not (fileExists? (str stem ".unsupported")))))

fn ! spawnUnitWorkers! t0: Int64 cDir: String fp: String mode: String slot: String wrapper: String units: (List lk/LinkUnit) entry: lk/LinkUnit ifaceMap: (Map String String) jobs: Int64 parentBusy: Bool -> WorkerPlan
  (let [(_ (leaveIfOrphaned!))
        (k (workerCount! jobs))
        (todo0 (if (>= k 2) (uncachedUnits cDir fp units entry ifaceMap) (list)))
        (argv (if (>= (min k (listLength todo0)) 2) (workerArgv cDir fp) (none)))
        (todo (if (some? argv) todo0 (list)))
        (n (min k (listLength todo)))]
    (if (< n 2)
      (WorkerPlan :procs (list) :own (list) :planned (list) :jobs jobs)
      (let [(perWorker (max 1 (/ jobs n)))
            (env (some (withEnvOverrides! (list (str "ASL_NATIVE_JOBS=" perWorker) "ASL_NATIVE_WORKERS=1" "ASL_NATIVE_WORKER=1"))))
            (base (listAppend (optionOr argv (list)) (list "--compile-units" cDir fp mode slot wrapper)))
            (meanSize (/ (fold (fn [(a Int64) (u lk/LinkUnit)] -> Int64 (+ a (sourceSize u))) 0 todo) (max 1 (listLength todo))))
            (groups (balancedGroups todo n (if parentBusy 0 (/ (* 3 meanSize) 2))))
            (spawned (if parentBusy groups (listDrop groups 1)))
            (_ (telemetry (str "NATIVE-WORKERS :k " n " :units " (listLength todo) " :workers " (listLength spawned) " :jobsPerWorker " perWorker (if parentBusy " :parent prelude" ""))))]
        (WorkerPlan :procs (fold (fn [(acc (List WorkerProc)) (g (List String))] -> (List WorkerProc) (spawnWorker! t0 base env acc g)) (list) spawned)
                    :own (if parentBusy (list) (optionOr (listHead groups) (list)))
                    :planned (map (fn [(u lk/LinkUnit)] -> String u.path) todo)
                    :jobs perWorker))))

fn ! compileOwnGroup! facts: (Option libc/TripleFacts) cDir: String fp: String plan: WorkerPlan units: (List lk/LinkUnit) ifaceMap: (Map String String) prelude: lk/LinkUnit px: lk/LinkUnit ovlNames: (List String) entry: lk/LinkUnit slot: String opt: String -> Unit
  (if (listEmpty? plan.own)
    ()
    (let [(mine (filter (fn [(u lk/LinkUnit)] -> Bool (listContains? plan.own u.path)) units))
          (raw (compileUnitsStep facts cDir fp mine units ifaceMap prelude px ovlNames entry slot 0 (list) (list) plan.jobs opt))
          (_ (drainAllPending (pairFirst raw) (pairSecond raw)))]
      ()))

(schema WorkerWatch
  (:f proc WorkerProc)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f errText String)
  (:f groups (List Int64))
  (:f known (List Int64))
  (:f verdict String)
  (:f exit Int64)
  (:f done Bool))

fn ! workerLimits! -> fr/Limits
  (let [(secs (match (envGet "ASL_NATIVE_WORKER_TIMEOUT") ((none) 1800) ((some s) (optionOr (stringToInt64 s) 1800))))
        (maxDesc (match (envGet "ASL_NATIVE_WORKER_MAXDESC") ((none) 64) ((some s) (optionOr (stringToInt64 s) 64))))]
    (fr/limits (max 1 secs) (max 1 maxDesc)))

fn ! readSome fd: Int64 isOpen: Bool -> (Pair Bool String)
  (if (not isOpen) (pair false "")
    (match (fdRead fd 65536)
      ((ok c) (if (> (stringLength c) 0) (pair true c) (do (fdClose fd) (pair false ""))))
      ((err _) (pair true ""))))

fn ! pumpWatch w: WorkerWatch -> (Pair Bool WorkerWatch)
  (if w.done (pair false w)
    (let [(o (readSome w.proc.outFd w.outOpen))
          (e (readSome w.proc.errFd w.errOpen))]
      (pair (not (stringEmpty? (str (pairSecond o) (pairSecond e))))
            (WorkerWatch :proc w.proc :outOpen (pairFirst o) :errOpen (pairFirst e) :errText (str w.errText (pairSecond e))
                         :groups w.groups :known w.known :verdict w.verdict :exit w.exit :done w.done))))

fn ! reapWorker pid: Int64 -> Int64
  (match (procWaitPid pid false) ((ok status) (optionOr status 1)) ((err _) 1))

fn ! settleWatch t0: Int64 w: WorkerWatch -> WorkerWatch
  (if (or w.done (or w.outOpen w.errOpen)) w
    (let [(exit (reapWorker w.proc.pid))
          (_ (telemetry (str "NATIVE-WORKERS :worker-done :pid " w.proc.pid " :ms " (ms (- (monotonicNs) t0)))))]
      (WorkerWatch :proc w.proc :outOpen false :errOpen false :errText w.errText :groups w.groups :known w.known
                   :verdict w.verdict :exit exit :done true)))

fn groupOf procs: (List fr/Proc) pid: Int64 -> Int64
  (match (listHead (filter (fn [(p fr/Proc)] -> Bool (= p.pid pid)) procs)) ((some p) p.pgid) ((none) -1))

fn ! judgeWatch lim: fr/Limits now: Int64 t0: Int64 snap: (List fr/Proc) own: Int64 checked: Bool w: WorkerWatch -> WorkerWatch
  (if w.done w
    (let [(overTime (> (/ (- now t0) 1000000) lim.timeoutMs))
          (tree (if checked (fr/treeOf snap w.proc.pid w.groups w.known own) (pair w.known w.groups)))
          (descN (if checked (listLength (pairFirst tree)) 0))
          (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (else "")))]
      (if (stringEmpty? verdict)
        (WorkerWatch :proc w.proc :outOpen w.outOpen :errOpen w.errOpen :errText w.errText :groups (pairSecond tree) :known (pairFirst tree)
                     :verdict "" :exit w.exit :done false)
        (let [(left (fr/killTree! w.proc.pid))
              (_ (if w.outOpen (do (fdClose w.proc.outFd) ()) ()))
              (_ (if w.errOpen (do (fdClose w.proc.errFd) ()) ()))
              (_ (reapWorker w.proc.pid))]
          (WorkerWatch :proc w.proc :outOpen false :errOpen false
                       :errText (str w.errText "\nNATIVE-WORKERS :killed :verdict :" verdict " :pid " w.proc.pid " :desc " descN " :timeoutMs " lim.timeoutMs " :maxDesc " lim.maxDesc " :left " left "\n")
                       :groups (pairSecond tree) :known (pairFirst tree) :verdict verdict :exit (if (= verdict "timeout") 124 125) :done true)))))

fn watchFds ws: (List WorkerWatch) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (w WorkerWatch)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if w.outOpen (list (pair w.proc.outFd 1)) (list)) (if w.errOpen (list (pair w.proc.errFd 1)) (list)))))
        (list) ws)

fn ! watchLoop lim: fr/Limits t0: Int64 ws: (List WorkerWatch) lastCheck: Int64 -> (List WorkerWatch)
  (if (listEmpty? (filter (fn [(w WorkerWatch)] -> Bool (not w.done)) ws)) ws
    (let [(pumped (map pumpWatch ws))
          (progress (fold (fn [(acc Bool) (p (Pair Bool WorkerWatch))] -> Bool (or acc (pairFirst p))) false pumped))
          (now (monotonicNs))
          (checked (>= (- now lastCheck) 250000000))
          (snap (if checked (fr/procSnapshot) (list)))
          (own (if checked (groupOf snap (procSelf)) -1))
          (states (map (fn [(w WorkerWatch)] -> WorkerWatch (judgeWatch lim now t0 snap own checked (settleWatch t0 w))) (map pairSecond pumped)))
          (finished (- (listLength (filter (fn [(w WorkerWatch)] -> Bool w.done) states)) (listLength (filter (fn [(w WorkerWatch)] -> Bool w.done) ws))))]
      (do (if (and (not progress) (= finished 0)) (do (fdPoll (watchFds states) 50) ()) ())
          (watchLoop lim t0 states (if checked now lastCheck)))))

fn ! awaitWorkersWithin! procs: (List WorkerProc) t0: Int64 lim: fr/Limits -> (List WorkerWatch)
  (watchLoop lim t0 (map (fn [(p WorkerProc)] -> WorkerWatch
                           (WorkerWatch :proc p :outOpen true :errOpen true :errText "" :groups (list p.pid) :known (list) :verdict "" :exit 0 :done false))
                         procs)
             0)

fn workersVerdict ws: (List WorkerWatch) -> String
  (let [(killed (filter (fn [(w WorkerWatch)] -> Bool (not (stringEmpty? w.verdict))) ws))]
    (if (listEmpty? killed) ""
      (str "unit workers killed: " (stringJoin (map (fn [(w WorkerWatch)] -> String (str "pid " w.proc.pid " " w.verdict " (" w.proc.units " units)")) killed) "; "))))

fn ! awaitUnitWorkers! procs: (List WorkerProc) t0: Int64 -> String
  (if (listEmpty? procs)
    ""
    (let [(ws (awaitWorkersWithin! procs t0 (workerLimits!)))
          (_ (map (fn [(w WorkerWatch)] -> Unit (eprintText w.errText)) ws))
          (failed (listLength (filter (fn [(w WorkerWatch)] -> Bool (!= w.exit 0)) ws)))
          (verdict (workersVerdict ws))]
      (do (telemetry (str "NATIVE-WORKERS :done :ms " (ms (- (monotonicNs) t0)) " :failed " failed (if (stringEmpty? verdict) "" (str " :error " verdict))))
          verdict)))

fn workerWrapperSource imports: (List String) -> String
  (str "(module nativeTestWorker\n  :x [main]\n  :i ["
       (stringJoin (map (fn [(i Int64)] -> String (str "(" (optionOr (listGet imports i) "") " :a w" (stringFromInt64 i) ")")) (range 0 (listLength imports))) "\n      ")
       "])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (ok 0)\n")

fn ! workerClosure! wrapper: String slot: String paths: (List String) -> (Result (List lk/LinkUnit) (List irTy/IrDiag))
  (let [(root (selfRoot))
        (imports (map (fn [(p String)] -> String (let [(rel (relativeTo root p))] (if (stringStartsWith? rel "/") "" (importPathOf rel)))) paths))
        (narrow (str slot "/worker-" (stringFromInt64 (procSelf)) ".asl"))]
    (if (listAny? stringEmpty? imports)
      (lk/loadClosure! wrapper)
      (match (fileWrite narrow (workerWrapperSource imports))
        ((err _) (lk/loadClosure! wrapper))
        ((ok _)
         (let [(res (lk/loadClosure! narrow))
               (_ (pathRemove narrow))
               (covered (match res ((ok us) (listAll? (fn [(p String)] -> Bool (listAny? (fn [(u lk/LinkUnit)] -> Bool (= u.path p)) us)) paths)) ((err _) false)))]
           (if covered res (lk/loadClosure! wrapper)))))))

fn ! compileUnitsWorker! args: (List String) -> (Result Int64 String)
  (let [(cDir (optionOr (listGet args 0) ""))
        (fp (optionOr (listGet args 1) ""))
        (mode (optionOr (listGet args 2) ""))
        (slot (optionOr (listGet args 3) ""))
        (wrapper (optionOr (listGet args 4) ""))
        (paths (listDrop args 5))
        (failWith (fn [(what String) (ds (List irTy/IrDiag))] -> (Result Int64 String) (do (eprintln (str "nativeTest --compile-units: " what ": " (diagText ds))) (ok 1))))]
    (if (or (stringEmpty? wrapper) (listEmpty? paths))
      (do (eprintln "usage: nativeTest --compile-units CACHEDIR FINGERPRINT MODE SLOT WRAPPER UNIT...") (ok 2))
      (match (workerClosure! wrapper slot paths)
        ((err ds) (failWith "closure load failed" ds))
        ((ok units)
         (match (lk/loadClosure! (toolPath (lk/preludePath)))
           ((err pds) (failWith "prelude load failed" pds))
           ((ok pUnits)
            (match (lk/overlayUnitAt! (toolPath (lk/nativeOverlayDir)))
              ((err ods) (failWith "native overlay load failed" ods))
              ((ok o)
               (let [(prelude (optionOr (listHead pUnits) (lk/LinkUnit :path "" :name "prelude" :forms (list) :positions (mapEmpty) :imports (list))))
                     (entryUnit (optionOr (listGet units (- (listLength units) 1)) prelude))
                     (mine (filter (fn [(u lk/LinkUnit)] -> Bool (and (listContains? paths u.path) (!= u.name entryUnit.name))) units))
                     (raw (compileUnitsStep (nativeFacts! cDir fp) cDir fp mine units (ifaceMapOf units) prelude (withOverlay prelude o) (overlayNamesOf o) entryUnit slot 0 (list) (list) (jobSlots!) (optLevelFor mode)))
                     (results (drainAllPending (pairFirst raw) (pairSecond raw)))
                     (bad (filter (fn [(r ModCompileResult)] -> Bool (not r.ok)) results))]
                 (do (map (fn [(r ModCompileResult)] -> Unit (eprintln (str "nativeTest --compile-units: " r.path ": " r.err))) bad)
                     (ok (if (and (listEmpty? bad) (= (listLength mine) (listLength paths))) 0 1))))))))))))

; (:m :ref NATIVETEST-RC :do "the RC pass needs the whole program (its user set and the routed helpers), so a suite under a .asl.config.asn :native :rc other than :tracing is linked and emitted as one module and linked with that mode's runtime; :tracing keeps the per-module cached pipeline")
fn ! rcModeFor! path: String -> (Result String String)
  (rcc/rcModeIn! (sys/parentOf (resultOr (realPath path) (absPath path))) "0")

fn rcTag rc: (Result String String) -> String
  (match rc ((ok m) (if (= m "0") "" (str ":rc=" m))) ((err _) ":rc=invalid"))

fn ! unbuilt reason: String -> Built
  (Built :binary (none) :reason reason :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0)

fn entryFor mode: String src: String -> (Option String)
  (if (= mode "run") (if (listContains? (exportsOf src) "main") (some "run") (none)) (entryOf src))

fn ! checkRootsForNative -> (List String)
  (list "." "asl/packages" "asl")

; (:m :ref U4-MARKER-PARITY :do "test and run used to compile straight from AST to IR/SSA/LLVM with no static check at all (compileSeparate! and compileWhole! both lower unconditionally), so a type error only ever surfaced if the VM or the native runtime happened to trap it, in a different format with no line:col, or (when the fixture has no main/runTests, like the sem/invalid corpus) not at all before ERR_NO_ENTRY. checkerRejection! runs asl-checker's own checkFile! once per entry, through the same digest-keyed on-disk Verdict cache asl1's own check subcommand already uses (asl-compiler/checkCache), so a repeat test/run of an unchanged entry (and unchanged checker) replays the cached verdict instead of rechecking; a hit with diagnostics renders them through asl-cli/verify's formatDiags, the exact formatter asl check's own printDiag! uses, so the three subcommands name the same site. actualPath is read (checkFile! does its own fileReadString); logicalPath is only substituted into the rendered text, so a staged or root-relative name still shows the form check would print")
fn ! checkerRejection! actualPath: String logicalPath: String fp: String -> (Option String)
  (let [(inline (inlineStaged? logicalPath))
        (shown (if inline (inlineName logicalPath) logicalPath))]
    (match (ccache/verdictKeyWith! actualPath (if inline (str "inline " shown) "") (str "nativeTest " fp))
      ((none) (freshRejection! actualPath shown (none)))
      ((some key)
       (match (ccache/lookup! key)
         ((some v) (if (= v.exitCode 0) (none) (some v.body)))
         ((none) (freshRejection! actualPath shown (some key)))))))

; (:m :ref SCRIPT-RUN-UNCHECKED :do "a file the checker cannot key or read is checked uncached or rejected, never let through unchecked")
fn ! freshRejection! actualPath: String logicalPath: String key: (Option String) -> (Option String)
  (match (pairFirst (ccd/checkFileCached! actualPath (checkRootsForNative) (ccd/stampedCache!)))
    ((err e) (some (str logicalPath ":0:0: ERR_IO " e)))
    ((ok verdict)
     (let [(diags verdict.diags)
           (body (if (listEmpty? diags) "" (stringReplace (verify/formatDiags diags) actualPath logicalPath)))
           (_ (match key
                ((some k) (match (ccache/store! k (ccache/Verdict :exitCode (if (listEmpty? diags) 0 1) :body body)) ((ok _) ()) ((err _) ())))
                ((none) ())))]
       (if (listEmpty? diags) (none) (some body)))))

fn ! rcRuntime! rc: String -> (Result (Pair String (List String)) String)
  (let [(root (toolRoot))
        (plain (toolPath "asl/host/out/libaslrt.a"))
        (clang (clangCommand))
        (cacheDir (str root "/.asl/cache/rcRuntime"))
        (ctx (sys/Context :root root :scriptDir "" :argv0 "" :hostBin ""))
        (b (nb/Build :root root :cache cacheDir :tmp cacheDir :lib plain :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 900000000000) :maxDesc 16))]
    (if (= rc "1")
      (ok (pair plain (list (optLevelFor "test"))))
      (match (dirCreate cacheDir)
        ((err e) (err (str "cannot create " cacheDir ": " e)))
        ((ok _) (match (cache/nativeAsl1! ctx plain clang)
          ((err e) (err (str "native asl1: " e)))
          ((ok asl1) (if (= rc "asan")
                       (match (nb/asanRuntime! b asl1 (toolPath "asl/packages")) ((err e) (err e)) ((ok lib) (ok (pair lib (nb/sanitizeFlags)))))
                       (match (nb/notraceRuntime! b asl1 (toolPath "asl/packages")) ((err e) (err e)) ((ok lib) (ok (pair lib (list (optLevelFor "test")))))))))))))

fn ! linkWhole! slot: String bin: String ll: String deps: (List String) libFlags: (Pair String (List String)) t0: Int64 t1: Int64 -> Built
  (let [(part (str bin ".part" (monotonicNs)))
        (args (listAppend (cons (clangCommand) (pairSecond libFlags)) (list "-Wno-override-module" "-x" "ir" ll "-x" "none" (pairFirst libFlags) "-lm" "-o" part)))
        (t2 (monotonicNs))
        (linked (runProc args (none)))
        (t3 (monotonicNs))
        (_ (pathRemove ll))]
    (cond
      ((!= linked.exitCode 0)
       (do (pathRemove part)
           (storeFallback slot deps (str "clang link failed (exit " linked.exitCode "): " (firstLines linked.stderr 3)) (list (ms (- t1 t0)) (ms (- t2 t1)) (ms (- t3 t2))))))
      ((err? (pathRename part bin)) (unbuilt (str "cannot move " part " to " bin)))
      (else
       (do (match (writeAtomic (str slot "/manifest") (manifestTextWith (manifestPrevStamps slot) "binary" deps))
             ((err e) (eprintln (str "nativeTest: cannot write the manifest in " slot ": " e)))
             ((ok _) ()))
           (Built :binary (some bin) :reason "" :cache "miss" :recompiled deps :reused (list)
                  :depsMs (ms (- t1 t0)) :asl1Ms (ms (- t2 t1)) :clangMs (ms (- t3 t2)))))))

fn ! compileWhole! cDir: String path: String src: String slot: String key: String mode: String rc: String -> Built
  (let [(wrapper (str (wrapperDirIn cDir) "/" key ".asl"))
        (bin (str slot "/" mode))
        (ll (str slot "/" mode ".ll"))
        (t0 (monotonicNs))]
    (match (entryFor mode src)
      ((none) (storeFallback slot (list path) (str "ERR_NO_ENTRY: " path " exports neither runTests nor main") (list)))
      ((some e)
       (match (dirCreate (wrapperDirIn cDir))
         ((err e1) (unbuilt (str "cannot create " (wrapperDirIn cDir) ": " e1)))
         ((ok _)
          (match (fileWrite wrapper (if (and (= e "run") (mainReturnsBareInt64 src))
                                   (wrapperSourceRunInt64 (importPathOf path) (mainTakesArgs src))
                                   (wrapperSource (importPathOf path) e (mainTakesArgs src))))
            ((err e2) (unbuilt (str "cannot write " wrapper ": " e2)))
            ((ok _)
             (match (lk/loadClosure! wrapper)
               ((err ds) (uncachedFailure (loadFailure ds) (list)))
               ((ok units)
                (let [(deps (closureDeps units key))]
                  (match (lk/linkEntry! wrapper)
                    ((err ds) (storeFallback slot deps (loadFailure ds) (list)))
                    ((ok m)
                     (match (nat/emitLlvmProgramNativeWith! m (str m.name ".main") rc)
                       ((err ds) (storeFallback slot deps (str "ERR_NATIVE_UNSUPPORTED: RC mode " rc " emission failed: " (diagText ds)) (list)))
                       ((ok code)
                        (let [(t1 (monotonicNs))]
                          (match (fileWrite ll code)
                            ((err we) (unbuilt (str "cannot write " ll ": " we)))
                            ((ok _)
                             (match (rcRuntime! rc)
                               ((err re) (unbuilt (str "ERR_NATIVE_UNSUPPORTED: the " rc " runtime: " re)))
                               ((ok libFlags) (linkWhole! slot bin ll deps libFlags t0 t1))))))))))))))))))))

fn ! compileIn cDir: String path: String actualPath: String src: String slot: String key: String fp: String mode: String -> Built
  (match (if (or (= mode "test") (= mode "run")) (checkerRejection! actualPath path fp) (none))
    ((some body) (Built :binary (none) :reason body :cache "checker-reject" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
    ((none)
     (if (= mode "eval")
       (compileSeparate! cDir path src slot key fp mode)
       (match (rcModeFor! path)
         ((err e) (storeFallback slot (list path) e (list)))
         ((ok rc) (if (= rc "0") (compileSeparate! cDir path src slot key fp mode) (compileWhole! cDir path src slot key mode rc)))))))

; (:m :ref RUN-ENTRY-REBUILD-COST :do "the link of a separate build, shared by the compiling path and the all-cached path: the prelude object, the unit objects in closure order and the runtime archive")
fn ! linkUnits! slot: String bin: String deps: (List String) preludeObj: String unitResults: (List ModCompileResult) darwin: Bool facts: (Option libc/TripleFacts) t0: Int64 t1: Int64 t2: Int64 -> Built
  (let [(unitObjs (map (fn [(r ModCompileResult)] -> String r.obj) unitResults))
        (allObjs (cons preludeObj unitObjs))
        (part (str bin ".part" (monotonicNs)))
        (linkArgs (listAppend (list (clangCommand) "-O2") (listAppend (deadStripFlags darwin) (listAppend allObjs (listAppend (linkArchives facts) (list "-lm" "-o" part))))))
        (tClang0 (monotonicNs))
        (linked (runProc linkArgs (none)))
        (t3 (monotonicNs))]
    (cond
      ((!= linked.exitCode 0)
       (do (pathRemove part)
           (storeFallback slot deps (str "clang link failed (exit " linked.exitCode "): " (firstLines linked.stderr 3)) (list (ms (- t1 t0)) (ms (- t2 t1)) (ms (- t3 tClang0))))))
      ((err? (pathRename part bin))
       (Built :binary (none) :reason (str "cannot move " part " to " bin) :cache "miss" :recompiled (list) :reused (list) :depsMs (ms (- t1 t0)) :asl1Ms (ms (- t2 t1)) :clangMs (ms (- t3 tClang0))))
      (else
       (let [(root (selfRoot))
             (recompiled (map (fn [(r ModCompileResult)] -> String (relativeTo root r.path)) (filter (fn [(r ModCompileResult)] -> Bool r.recompiled) unitResults)))
             (reused (map (fn [(r ModCompileResult)] -> String (relativeTo root r.path)) (filter (fn [(r ModCompileResult)] -> Bool (not r.recompiled)) unitResults)))
             (prevStamps (manifestPrevStamps slot))
             (_ (match (writeAtomic (str slot "/manifest") (manifestTextWith prevStamps "binary" deps))
                  ((err e3) (eprintln (str "nativeTest: cannot write the manifest in " slot ": " e3)))
                  ((ok _) ())))]
         (Built :binary (some bin) :reason ""
                :cache (if (listEmpty? recompiled) "hit" "miss")
                :recompiled recompiled :reused reused
                :depsMs (ms (- t1 t0)) :asl1Ms (ms (- t2 t1)) :clangMs (ms (- t3 tClang0)))))))

fn ! compileSeparate! cDir: String path: String src: String slot: String key: String fp: String mode: String -> Built
  (let [(entry (if (or (= mode "run") (= mode "eval")) (if (listContains? (exportsOf src) "main") (some (if (= mode "eval") "main" "run")) (none)) (entryOf src)))
        (wrapper (if (= mode "eval") path (str (wrapperDirIn cDir) "/" key ".asl")))
        (bin (str slot "/" mode))]
    (match entry
      ((none) (storeFallback slot (list path) (str "ERR_NO_ENTRY: " path " exports neither runTests nor main") (list)))
      ((some e)
       (match (if (= mode "eval") (ok ()) (dirCreate (wrapperDirIn cDir)))
         ((err err1) (Built :binary (none) :reason (str "cannot create " (wrapperDirIn cDir) ": " err1) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
         ((ok _)
          (match (if (= mode "eval") (ok ())
                (fileWrite wrapper (if (and (= e "run") (mainReturnsBareInt64 src))
                                     (wrapperSourceRunInt64 (importPathOf path) (mainTakesArgs src))
                                     (wrapperSource (importPathOf path) e (mainTakesArgs src)))))
            ((err err2) (Built :binary (none) :reason (str "cannot write " wrapper ": " err2) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
            ((ok _)
             (match (dirCreate (modulesDirIn cDir))
               ((err err3) (Built :binary (none) :reason (str "cannot create " (modulesDirIn cDir) ": " err3) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
               ((ok _)
                (let [(tA (monotonicNs))
                      (uA (lk/loadClosure! wrapper))]
                 (match (cachedLink! cDir fp slot bin key uA tA)
                  ((some b) b)
                  ((none)
                (let [(t0 tA)
                      (uRes uA)
                      (units0 (match uRes ((ok us) us) ((err _) (list))))
                      (ifaceMap0 (ifaceMapOf units0))
                      (jobs (jobSlots!))
                      (darwin (hostDarwin? cDir fp))
                      (pExtra (preludeSectionFlags darwin))
                      (preludeOpt (optLevelFor "run"))
                      (plan (if (listEmpty? units0)
                              (WorkerPlan :procs (list) :own (list) :planned (list) :jobs jobs)
                              (spawnUnitWorkers! t0 cDir fp mode slot wrapper units0 (optionOr (listGet units0 (- (listLength units0) 1)) (lk/emptyUnit "")) ifaceMap0 jobs (fullPreludePending? cDir fp preludeOpt pExtra))))
                      (pRes (lk/loadClosure! (toolPath (lk/preludePath))))
                      (t1 (monotonicNs))]
                  (match uRes
                    ((err ds) (uncachedFailure (loadFailure ds) (list (ms (- t1 t0)) 0 0)))
                    ((ok units)
                     (match pRes
                       ((err pds) (do (awaitUnitWorkers! plan.procs t0) (storeFallback slot (list path) (str "prelude load failed: " (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) pds) "; ")) (list (ms (- t1 t0)) 0 0))))
                       ((ok pUnits)
                        (let [(prelude (optionOr (listHead pUnits) (lk/LinkUnit :path "" :name "prelude" :forms (list) :positions (mapEmpty) :imports (list))))
                              (ovl (lk/overlayUnitAt! (toolPath (lk/nativeOverlayDir))))
                              (ovlErr (match ovl ((ok _) "") ((err ods) (str "native overlay load failed: " (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ods) "; ")))))
                              (px (match ovl ((ok o) (withOverlay prelude o)) ((err _) prelude)))
                              (ovlNames (match ovl ((ok o) (overlayNamesOf o)) ((err _) (list))))
                              (entryUnit (optionOr (listGet units (- (listLength units) 1)) prelude))
                              (ifaceMap ifaceMap0)
                              (facts (nativeFacts! cDir fp))
                              (opt (optLevelFor mode))
                              (preludeStart (monotonicNs))
                              (earlyPrelude (if (and (stringEmpty? ovlErr) (fullPreludeWanted?)) (compileFullPrelude facts cDir fp px ovlNames slot (listLength units) preludeOpt pExtra) (none)))
                              (_ (if (stringEmpty? ovlErr) (compileOwnGroup! facts cDir fp plan units ifaceMap prelude px ovlNames entryUnit slot opt) ()))
                              (workerErr (awaitUnitWorkers! plan.procs t0))
                              (rawUnits (if (and (stringEmpty? ovlErr) (stringEmpty? workerErr)) (compileUnitsStep facts cDir fp units units ifaceMap prelude px ovlNames entryUnit slot 0 (list) (list) jobs opt) (pair (list) (list))))
                              (doneSoFar (pairFirst rawUnits))
                              (stillPending (pairSecond rawUnits))
                              (allPreludeRefs (dedupeStr (listAppend (fold (fn [(acc (List String)) (r ModCompileResult)] -> (List String) (listAppend acc r.preludeRefs)) (list) doneSoFar)
                                                                      (fold (fn [(acc (List String)) (p PendingObj)] -> (List String) (listAppend acc p.pExts)) (list) stillPending))))
                              (preludeStep (cond ((not (stringEmpty? ovlErr)) (preludeFailed ovlErr)) ((not (stringEmpty? workerErr)) (preludeFailed workerErr))
                                                 (else (match earlyPrelude ((some st) st) ((none) (compileSubsetPrelude facts cDir fp allPreludeRefs px ovlNames slot (listLength units) preludeOpt pExtra))))))
                              (unitResults (map (fn [(r ModCompileResult)] -> ModCompileResult (if (listContains? plan.planned r.path) (ModCompileResult :path r.path :ok r.ok :obj r.obj :recompiled true :preludeRefs r.preludeRefs :initName r.initName :err r.err) r))
                                                (drainAllPending doneSoFar stillPending)))
                              (failedUnits (filter (fn [(r ModCompileResult)] -> Bool (not r.ok)) unitResults))
                              (failedUnit (cond ((not (stringEmpty? ovlErr)) (some ovlErr)) ((not (stringEmpty? workerErr)) (some workerErr)) ((listEmpty? failedUnits) (none)) (else (some (str "compile unit failed: " (stringJoin (map (fn [(r ModCompileResult)] -> String r.err) failedUnits) "; ") (if (> (listLength failedUnits) 1) (str " (" (stringFromInt64 (listLength failedUnits)) " units)") ""))))))
                              (t2 (monotonicNs))
                              (deps (closureDeps units key))
                              (pCompRes (compilePreludeAwaitStep preludeStep))
                              (preludeEnd (monotonicNs))]
                          (match failedUnit
                            ((some bad) (if (stringEmpty? workerErr)
                                          (storeFallback slot deps bad (list (ms (- t1 t0)) (ms (- t2 t1)) 0))
                                          (Built :binary (none) :reason bad :cache "miss" :recompiled (list) :reused (list) :depsMs (ms (- t1 t0)) :asl1Ms (ms (- t2 t1)) :clangMs 0)))
                            ((none)
                             (if (not pCompRes.ok)
                                 (storeFallback slot deps (str "prelude compile failed: " pCompRes.err) (list (ms (- t1 t0)) (ms (- t2 t1)) 0))
                                 (let [(_ (telemetry (str "NATIVE-PRELUDE-PHASES :prepareMs " (ms (- preludeEnd preludeStart)))))]
                                   (linkUnits! slot bin deps pCompRes.obj unitResults darwin facts t0 t1 t2)))))))))))))))))))))))

fn ! lookup slot: String mode: String -> (Option Built)
  (match (fileReadString (str slot "/manifest"))
    ((err _) (none))
    ((ok text) (if (not (manifestFileHolds? (toolRoot) (str slot "/manifest") text))
                 (none)
                 (cond
                   ((and (= (manifestKind text) "binary")
                         (and (fileExists? (str slot "/" mode))
                              (match (fileStat (str slot "/" mode)) ((ok st) (> st.size 0)) ((err _) false))))
                    (do (fileUtime slot (nowNs)) (some (Built :binary (some (str slot "/" mode)) :reason "" :cache "hit" :recompiled (list) :reused (manifestFiles text) :depsMs 0 :asl1Ms 0 :clangMs 0))))
                   ((= (manifestKind text) "fallback")
                    (some (Built :binary (none) :reason (str (resultOr (fileReadString (str slot "/reason")) "reason unreadable") " (cached)") :cache "fallback-hit" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0)))
                   (else (none))))))

fn ! newestMtimeNs path: String -> Int64
  (match (fileStat path)
    ((err _) 0)
    ((ok st) (if st.isDir
               (fold (fn [(acc Int64) (n String)] -> Int64 (max acc (newestMtimeNs (str path "/" n)))) st.mtimeNs (resultOr (dirList path) (list)))
               st.mtimeNs)))

fn ! slotBusy? path: String -> Bool
  (or (lockLive? (str path "/lock"))
      (< (- (nowNs) (newestMtimeNs path)) 600000000000))

fn ! prune dir: String current: String -> Unit
  (match (dirList dir)
    ((err _) ())
    ((ok names)
     (let [(others (filter (fn [(n String)] -> Bool (and (= (stringLength n) 64) (and (!= n current) (not (slotBusy? (str dir "/" n)))))) names))
           (stamped (map (fn [(n String)] -> (Pair String Int64) (pair n (match (fileStat (str dir "/" n)) ((ok st) st.mtime) ((err _) 0)))) others))
           (stale (listDrop (listReverse (listSortBy (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) stamped)) 2))]
       (fold (fn [(acc Unit) (p (Pair String Int64))] -> Unit
               (match (pathRemove (str dir "/" (pairFirst p)))
                 ((ok _) acc)
                 ((err e) (eprintln (str "nativeTest: cannot prune " (pairFirst p) ": " e)))))
             () stale))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "scripts, -e, - and eval build into an ephemeral slot run.PID.NS under the store: the entry module and any inline or eval source keep their objects in the slot, the binary is exec'd and drops itself, and nothing of it stays in the store; library modules still reuse the shared object cache")
fn ephemeralDirIn cDir: String -> String
  (str cDir "/ephemeral")

fn ephemeralSlot? slot: String -> Bool
  (stringContains? slot "/ephemeral/run.")

fn transientSource? path: String -> Bool
  (or (stringContains? path ".asl/cache/nativeTest/outside/inline") (stringContains? path ".asl/cache/nativeTest/evals/"))

fn ! ephemeralSlotIn! cDir: String -> String
  (let [(dir (ephemeralDirIn cDir))
        (_ (dirCreate dir))
        (abs (resultOr (realPath dir) dir))]
    (str abs "/run." (stringFromInt64 (procSelf)) "." (stringFromInt64 (monotonicNs))))

fn ! keepOnly! slot: String keep: String -> Unit
  (fold (fn [(acc Unit) (n String)] -> Unit (if (= n keep) acc (match (pathRemove (str slot "/" n)) ((ok _) acc) ((err _) acc))))
        () (resultOr (dirList slot) (list)))

fn ! buildEphemeral! cDir: String actualPath: String logicalPath: String fp: String mode: String slot: String -> Built
  (match (fileReadString actualPath)
    ((err _) (unbuilt (str "cannot read " actualPath)))
    ((ok src) (let [(key (slotKey (str mode (rcTag (rcModeFor! logicalPath)) ":" (importPathOf logicalPath) ":" slot) (fileDigest actualPath)))]
                (match (dirCreate slot)
                  ((err e) (unbuilt (str "cannot create " slot ": " e)))
                  ((ok _) (let [(built (dropWrapperIn cDir key (compileIn cDir logicalPath actualPath src slot key fp mode)))
                                (_ (sweepStore! cDir))]
                            built))))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "the store holds slots of every fingerprint and the shared module objects, grouped by key stem; on each build the oldest of them go until the store fits the :native :storeCap bytes (2G), a slot with a live lock is pinned, nothing used within :native :storeMinAge (60m) goes (a build touches every object and slot it reuses as it starts), and an ephemeral slot whose process is dead is removed")
fn stemOfName n: String -> String
  (let [(parts (stringSplit n "."))]
    (if (< (listLength parts) 2) n (stringJoin (listTake parts (- (listLength parts) 1)) ".")))

fn ! moduleEntries! dir: String -> (List ncli/StoreEntry)
  (let [(groups (fold (fn [(m (Map String (List String))) (n String)] -> (Map String (List String))
                        (mapSet m (stemOfName n) (cons (str dir "/" n) (mapGetOr m (stemOfName n) (list)))))
                      (mapEmpty) (resultOr (dirList dir) (list))))]
    (map (fn [(k String)] -> ncli/StoreEntry (ncli/storeEntry! (mapGetOr groups k (list)) false)) (mapKeys groups)))

fn hexKey? n: String -> Bool
  (= (stringLength n) 64)

fn ! slotEntries! cDir: String -> (List ncli/StoreEntry)
  (fold (fn [(acc (List ncli/StoreEntry)) (f String)] -> (List ncli/StoreEntry)
          (listAppend acc (map (fn [(n String)] -> ncli/StoreEntry (ncli/storeEntry! (list (str cDir "/" f "/" n)) (lockLive? (str cDir "/" f "/" n "/lock"))))
                               (filter hexKey? (resultOr (dirList (str cDir "/" f)) (list))))))
        (list) (filter hexKey? (resultOr (dirList cDir) (list))))

fn ! deadEphemeral? name: String -> Bool
  (match (listGet (stringSplit name ".") 1)
    ((some pid) (not (pidAlive? (optionOr (stringToInt64 pid) 0))))
    ((none) false))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a sweep walks every file of the store (539 ms on 40000 files, 2026-10-27), so a build sweeps at most once a minute per store, marked by the swept file")
fn ! sweepStore! cDir: String -> Int64
  (let [(mark (str cDir "/swept"))]
    (if (< (- (nowNs) (ncli/entryStamp! mark)) 60000000000)
      0
      (do (fileWrite mark "") (sweepStoreNow! cDir))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "one sweep at a time per store, under sweep.lock; a build leases its slot with slot/lock while it fills it, and sweepEntries! re-stamps each entry right before deleting it")
fn ! sweepStoreNow! cDir: String -> Int64
  (sweepStoreWith! cDir (nb/storeCapFor! (toolRoot)) (nb/storeMinAgeNs! (toolRoot)))

fn ! sweepStoreWith! cDir: String capBytes: Int64 minAgeNs: Int64 -> Int64
  (let [(lock (str cDir "/sweep.lock"))]
    (if (not (takeLock! lock 1))
      0
      (let [(eDir (ephemeralDirIn cDir))
            (stale (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "run.") (and (deadEphemeral? n) (ok? (pathRemove (str eDir "/" n)))))) (resultOr (dirList eDir) (list))))
            (entries (listAppend (slotEntries! cDir) (moduleEntries! (modulesDirIn cDir))))
            (swept (ncli/sweepEntries! entries capBytes minAgeNs))
            (_ (pathRemove lock))]
        (+ (listLength stale) (pairSecond swept)))))

fn ! leaseSlot! slot: String -> Bool
  (ok? (fileWrite (str slot "/lock") (stringFromInt64 (procSelf))))

fn ! leasedBuild! slot: String b: Built -> Built
  (do (pathRemove (str slot "/lock")) b)

fn ! dropWrapperIn cDir: String key: String b: Built -> Built
  (let [(dir (wrapperDirIn cDir))
        (w (str dir "/" key ".asl"))]
    (do (if (fileExists? w)
          (match (pathRemove w)
            ((ok _) ())
            ((err e) (eprintln (str "nativeTest: cannot remove " w ": " e))))
          ())
        (if (and (stringStartsWith? dir ".asl/cache/nativeTest/entries/")
                 (match (dirList dir) ((ok names) (listEmpty? names)) ((err _) false)))
          (match (pathRemove dir) ((ok _) ()) ((err _) ()))
          ())
        b))

fn ! dropWrapper key: String b: Built -> Built
  (dropWrapperIn (cacheDir!) key b)

fn ! compile path: String src: String slot: String key: String fp: String -> Built
  (compileIn (cacheDir!) path path src slot key fp "test")

; (:m :ref OUT-OF-ROOT-USERPATH :do "a run/test FILE argument is the caller's own, resolved against the caller's cwd like any other CLI tool (NATIVE-CHDIR: the native CLI never chdirs to the toolchain root first); only the toolchain's own internal lookups (cache dirs, dep manifests) are root-relative, so prepareIn reads and digests path as given, never through resolveIn (toolRoot)")
fn ! prepareIn cDir: String path: String fp: String mode: String -> Built
  (match (fileReadString path)
    ((err _) (Built :binary (none) :reason (str "cannot read " path) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
    ((ok src) (let [(key (slotKey (str mode (rcTag (rcModeFor! path)) ":" (importPathOf path)) (fileDigest path)))
                    (slot (str cDir "/" fp "/" key))]
                (match (lookup slot mode)
                  ((some b) b)
                  ((none) (match (dirCreate slot)
                            ((err e) (Built :binary (none) :reason (str "cannot create " slot ": " e) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
                            ((ok _) (let [(built (leasedBuild! slot (do (leaseSlot! slot) (dropWrapperIn cDir key (compileIn cDir path path src slot key fp mode)))))
                                          (_ (sweepStore! cDir))]
                                      built))))))))

fn ! prepareSourceIn cDir: String actualPath: String logicalPath: String fp: String mode: String -> Built
  (match (fileReadString actualPath)
    ((err _) (Built :binary (none) :reason (str "cannot read " actualPath) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
    ((ok src) (let [(key (slotKey (str mode (rcTag (rcModeFor! logicalPath)) ":" (importPathOf logicalPath)) (fileDigest actualPath)))
                    (slot (str cDir "/" fp "/" key))]
                (match (lookup slot mode)
                  ((some b) b)
                  ((none) (match (dirCreate slot)
                            ((err e) (Built :binary (none) :reason (str "cannot create " slot ": " e) :cache "miss" :recompiled (list) :reused (list) :depsMs 0 :asl1Ms 0 :clangMs 0))
                            ((ok _) (let [(built (leasedBuild! slot (do (leaseSlot! slot) (dropWrapperIn cDir key (compileIn cDir logicalPath actualPath src slot key fp mode)))))
                                          (_ (sweepStore! cDir))]
                                      built))))))))

fn ! prepareTestSource actualPath: String logicalPath: String fp: String -> Built
  (prepareSourceIn (cacheDir!) actualPath logicalPath fp "test")

fn ! prepare path: String fp: String -> Built
  (prepareIn (cacheDir!) path fp "test")

fn ! prepareRunIn cDir: String path: String fp: String -> Built
  (prepareIn cDir path fp "run")

fn ! prepareRun path: String fp: String -> Built
  (prepareRunIn (cacheDir!) path fp)

fn ! prepareEval path: String src: String fp: String slot: String -> Built
  (let [(cDir (cacheDir!))
        (key (slotKey (str "eval:" (importPathOf path) ":" slot) (bytesSha256 (stringToBytes src))))]
    (match (fileWrite path src)
      ((err e) (unbuilt (str "cannot write " path ": " e)))
      ((ok _) (let [(built (match (dirCreate slot)
                              ((err e) (unbuilt (str "cannot create " slot ": " e)))
                              ((ok _) (compileIn cDir path path src slot key fp "eval"))))
                    (_ (pathRemove path))
                    (_ (sweepStore! cDir))]
                built))))

fn singleBalancedForm? expr: String -> Bool
  (let [(tree (paren/parseString expr))]
    (and (not (paren/hasErrors tree)) (= (paren/topLevelFormCount tree) 1)))

; (:m :ref NATIVECACHE-EVALNAME :do "the eval source is named by its text, pid and clock, not its text alone: two evals of the same text at once (parallel suites) wrote one file and the first to finish removed it under the other's compile")
fn ! evalExpression! expr: String fp: String -> Int64
  (if (not (singleBalancedForm? expr))
    (do (eprintln "usage: nativeTest eval EXPR (exactly one balanced ASL form required)") 2)
    (let [(digest (bytesSha256 (stringToBytes expr)))
        (path (toolPath (str ".asl/cache/nativeTest/evals/" digest "x" (stringFromInt64 (procSelf)) "x" (stringFromInt64 (monotonicNs)) ".asl")))
        (src (str "(module nativeEval :x [main] :i [])\n\n"
                  "fn ! main -> (Result Int64 String)\n"
                  "  (do (println (stringFromInt64 " expr "\n  )) (ok 0))\n"))
        (made (dirCreate (toolPath ".asl/cache/nativeTest/evals")))]
    (match made
      ((err e) (do (eprintln (str "native eval: cannot create cache: " e)) 1))
      ((ok _) (let [(slot (ephemeralSlotIn! (cacheDir!)))
                    (built (prepareEval path src fp slot))]
                (match built.binary
                  ((none) (do (pathRemove slot) (eprintln (str "native eval: " built.reason)) 1))
                  ((some bin) (let [(out (fromFr (fr/runGuarded (list bin) "." (withEnvOverrides! (list (str "ASL_PRELUDE=" (absPath "asl/host/out/prelude.asl")))) (fr/defaultLimits))))
                                    (_ (pathRemove slot))]
                                (do (if (not (stringEmpty? out.stdout)) (print out.stdout) ())
                                    (if (not (stringEmpty? out.stderr)) (eprintText out.stderr) ())
                                    (if (= out.exitCode 0)
                                      (do (telemetry (str "NATIVE-EVAL :cache :" built.cache " :recompiled " (listLength built.recompiled)
                                                         " :depsMs " built.depsMs " :asl1Ms " built.asl1Ms " :linkMs " built.clangMs)) 0)
                                      out.exitCode))))))))))

(schema Outcome
  (:f exit Int64)
  (:f line String)
  (:f native Bool)
  (:f built Built)
  (:f runMs Int64))

fn ! eprintText text: String -> Unit
  (if (stringEmpty? text) () (eprintln (if (stringEndsWith? text "\n") (optionOr (stringSlice text 0 (- (stringLength text) 1)) text) text)))

fn ! emit out: ProcOut v: Verdict -> Unit
  (do (print out.stdout)
      (eprintText v.stderr)
      (if (= v.exit 0) (println v.line) (eprintln v.line)))

fn ! runOne path: String fp: String -> Outcome
  (let [(built (prepare path fp))]
    (match built.binary
      ((some bin)
       (let [(t0 (monotonicNs))
             (prelude (str "ASL_PRELUDE=" (absPath "asl/host/out/prelude.asl")))
             (out (fromFr (fr/runGuarded (list "nice" "-n" "15" bin) "." (withEnvOverrides! (list "ASL_ASSERT_REPORT=1" prelude (initPhaseOff))) (fr/defaultLimits))))
             (took (ms (- (monotonicNs) t0)))
             (v (judgeInit! bin path prelude (verdictOf path out.exitCode out.stderr)))]
         (do (emit out v)
             (Outcome :exit v.exit :line v.line :native true :built built :runMs took))))
      ((none)
       (let [(line (failLine path built.reason))]
         (do (eprintln line)
             (Outcome :exit 1 :line line :native false :built built :runMs 0))))))

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

; (:m :ref NATIVETEST-HOSTLESS :do "--expect FILE replaces the retired --compare oracle (asl-host as a live interpreter): each suite's native verdict line is compared with the line recorded for it in FILE, rows (:verdict :suite PATH :line LINE)")
fn quotedField row: String key: String -> (Option String)
  (match (stringIndexOf row (str key " \""))
    ((none) (none))
    ((some i) (let [(rest (optionOr (stringSlice row (+ i (+ (stringLength key) 2)) (stringLength row)) ""))]
                (some (stringReplace (stringReplace (fieldBody rest 0) "\\\"" "\"") "\\\\" "\\")))))

fn fieldBody text: String i: Int64 -> String
  (cond
    ((>= i (stringLength text)) text)
    ((= (optionOr (stringSlice text i (+ i 1)) "") "\\") (fieldBody text (+ i 2)))
    ((= (optionOr (stringSlice text i (+ i 1)) "") "\"") (optionOr (stringSlice text 0 i) text))
    (else (fieldBody text (+ i 1))))

fn expectedLine text: String path: String -> (Option String)
  (optionOr (listHead (filter (fn [(o (Option String))] -> Bool (some? o)) (map (fn [(row String)] -> (Option String) (if (= (quotedField row ":suite") (some path)) (quotedField row ":line") (none))) (stringLines text)))) (none))

fn ! expectOne path: String o: Outcome expected: (Option String) -> Bool
  (let [(same (and o.native (= expected (some o.line))))
        (b o.built)]
    (do (println (str "(:nativeCompare :suite \"" (esc path) "\" :match " same " :native " o.native " :cache :" b.cache
                      " :recompiled " (listLength b.recompiled) " :reused " (listLength b.reused)
                      " :exit " o.exit " :runMs " o.runMs " :depsMs " b.depsMs " :asl1Ms " b.asl1Ms " :clangMs " b.clangMs
                      (if o.native "" (str " :reason \"" (esc b.reason) "\""))
                      (if same "" (str " :line \"" (esc o.line) "\" :expected \"" (esc (optionOr expected "none recorded")) "\""))
                      ")"))
        same))

fn ! testMain args: (List String) fpOpt: (Option String) -> (Result Int64 String)
  (let [(expectAt (listIndexOf args "--expect"))
        (expectFile (match expectAt ((some i) (listGet args (+ i 1))) ((none) (none))))
        (compare (some? expectAt))
        (operands (match expectAt ((some i) (listAppend (listTake args i) (listDrop args (+ i 2)))) ((none) args)))
        (expectText (match expectFile ((some f) (resultOr (fileReadString f) "")) ((none) "")))
        (paths (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) operands))
        (unknown (filter (fn [(a String)] -> Bool (stringStartsWith? a "--")) operands))]
    (cond
      ((not (listEmpty? unknown)) (do (eprintln (str "nativeTest: unknown option " (optionOr (listHead unknown) "") "; usage: nativeTest [--expect FILE] SUITE...")) (ok 2)))
      ((and compare (stringEmpty? expectText)) (do (eprintln (str "nativeTest: --expect needs a readable file of (:verdict :suite PATH :line LINE) rows: " (optionOr expectFile ""))) (ok 2)))
      ((listEmpty? paths) (do (eprintln "usage: nativeTest [--expect FILE] SUITE...") (ok 2)))
      ((not (fileExists? (toolPath "asl/host/out/libaslrt.a"))) (do (eprintln (str "nativeTest: " (toolPath "asl/host/out/libaslrt.a") " not found; set ASL_ROOT to the asl toolchain root or run sh asl/host/build.sh")) (ok 2)))
      (else
       (let [(fp (fingerprintOr fpOpt))
             (pruned (prune (cacheDir!) fp))
             (results (map (fn [(p String)] -> (Pair Int64 Bool)
                             (let [(o (runOne p fp))]
                               (pair o.exit (if compare (expectOne p o (expectedLine expectText p)) true))))
                           paths))
             (firstBad (listHead (filter (fn [(r (Pair Int64 Bool))] -> Bool (!= (pairFirst r) 0)) results)))
             (allSame (fold (fn [(acc Bool) (r (Pair Int64 Bool))] -> Bool (and acc (pairSecond r))) true results))]
         (ok (cond
               (compare (if allSame 0 1))
               (else (match firstBad ((none) 0) ((some r) (pairFirst r))))))))))

fn ! outsideRelPath digest: String -> String
  (str ".asl/cache/nativeTest/outside/" digest ".asl")

fn ! writeStaged! dest: String rel: String src: String -> (Result String String)
  (if (fileExists? dest)
    (ok rel)
    (match (fileWrite dest src)
      ((err e3) (err (str "cannot write " dest ": " e3)))
      ((ok _) (ok rel))))

; (:m :ref OUT-OF-ROOT-USERPATH :do "a copy outside toolRoot (no file of that name ever shares the real module's own declared path) cannot be given to the wrapper as a bare module name, the same class of gap stageOutside! already closed for asl-cli's run!; stageOutsideFile! mirrors it here so runFile works the same whether reached through bin/asl run or (as testDownstream and selfTestBinary! do) by calling asl/tools/nativeTest.asl's own compiled binary directly")
fn ! stageOutsideFile! root: String absFile: String -> (Result String String)
  (match (fileReadString absFile)
    ((err e) (err (str "cannot read " absFile ": " e)))
    ((ok src)
      (let [(digest (bytesSha256 (stringToBytes src)))
            (rel (outsideRelPath digest))
            (dest (str root "/" rel))
            (dir (str root "/.asl/cache/nativeTest/outside"))]
        (match (if (fileExists? dir) (ok ()) (dirCreate dir))
          ((err e2) (err (str "cannot create " dir ": " e2)))
          ((ok _) (writeStaged! dest rel src))))))

fn ! execStaged! bin: String args: (List String) -> Int64
  (match (procExecv (cons bin args) (some (withEnvOverrides! (list (str "ASL_PRELUDE=" (absPath "asl/host/out/prelude.asl"))))))
    ((ok _) 0)
    ((err e2) (do (eprintln (str "nativeTest: cannot execute " bin ": " e2)) 127)))

; (:m :ref SCRIPT-ENTRY :do "asl -e and asl - stage their text as outside/inline<pid>x<digest>.asl; the run execs its binary, so the staged text is removed once the binary is built, before the exec")
fn inlineStaged? rel: String -> Bool
  (stringStartsWith? rel ".asl/cache/nativeTest/outside/inline")

; (:m :ref SCRIPT-ENTRY :do "a failure of inline text names it as the user typed it (-e, -, or the shebang file's name) from the stage name's e, s or f mark, never the staged file")
fn inlineName rel: String -> String
  (let [(stem (optionOr (stringSlice rel 36 (- (stringLength rel) 4)) ""))]
    (cond ((stringStartsWith? stem "e") "-e")
          ((stringStartsWith? stem "f") (match (stringIndexOf stem "x-") ((some i) (optionOr (stringSlice stem (+ i 2) (stringLength stem)) stem)) ((none) stem)))
          (else "-")))

fn stemOf rel: String -> String
  (if (stringEndsWith? rel ".asl") (optionOr (stringSlice rel 0 (- (stringLength rel) 4)) rel) rel)

; (:m :ref SCRIPT-RUN-UNCHECKED :do "a staged copy of an outside file is named by the path the user gave (run --as), as asl check names it")
fn failText root: String rel: String path: String shown: String reason: String -> String
  (if (or (inlineStaged? rel) (not (stringEmpty? shown)))
    (let [(name (if (inlineStaged? rel) (inlineName rel) shown))]
      (str "FAIL " name ": " (fold (fn [(acc String) (p String)] -> String (stringReplace acc p name)) reason (list (str root "/" rel) (str root "/" (stemOf rel)) rel (stemOf rel)))))
    (str "FAIL " path ": " reason))

; (:m :ref INTEG9-F1 :do "a script that was prepared on purpose (nativeTest prepare FILE leaves a binary in the store) runs from that binary when its sources still match, so a tool that must start where fork is gone (fleet guard) needs no compile; a script nobody prepared still builds into an ephemeral slot and leaves nothing")
fn ! keptRun root: String rel: String fp: String -> (Option String)
  (if (inlineStaged? rel)
    (none)
    (match (fileReadString (str root "/" rel))
      ((err _) (none))
      ((ok _) (let [(key (slotKey (str "run" (rcTag (rcModeFor! rel)) ":" (importPathOf rel)) (fileDigest (str root "/" rel))))]
                (match (lookup (str (cacheDir!) "/" fp "/" key) "run")
                  ((some b) b.binary)
                  ((none) (none)))))))

; (:m :ref GUARD-FORKFREE-PREPARE :do "the fleet guard must start where fork is gone (a full process table is what it is there to clear), so its run keeps its binary: the first run builds it into the store as nativeTest prepare would, and every later run under the same fingerprint and sources execs it with no compile; every other script stays ephemeral")
fn keptScript? rel: String -> Bool
  (= rel "tools/fleet/guard.asl")

fn ! runStaged! root: String rel: String path: String shown: String args: (List String) fp: String -> Int64
  (match (keptRun root rel fp)
    ((some bin) (do (telemetry (str "NATIVE-CACHE " path " :cache :hit")) (execStaged! bin args)))
    ((none) (if (keptScript? rel) (runKept! root rel path shown args fp) (runBuilt! root rel path shown args fp))))

fn ! runKept! root: String rel: String path: String shown: String args: (List String) fp: String -> Int64
  (let [(built (prepareSourceIn (cacheDir!) (str root "/" rel) rel fp "run"))]
    (match built.binary
      ((some bin) (do (telemetry (str "NATIVE-CACHE " path " :cache :" built.cache " :kept")) (execStaged! bin args)))
      ((none) (do (eprintln (failText root rel path shown (failReason built.reason rel))) 1))))

fn ! runBuilt! root: String rel: String path: String shown: String args: (List String) fp: String -> Int64
  (let [(cDir (cacheDir!))
        (slot (ephemeralSlotIn! cDir))
        (built (buildEphemeral! cDir (str root "/" rel) rel fp "run" slot))
        (_ (if (inlineStaged? rel) (pathRemove (str root "/" rel)) (ok ())))
        (keepLl? (some? (envGet "ASL_NATIVE_KEEP_LL")))]
    (match built.binary
      ((some bin) (do (telemetry (str "NATIVE-CACHE " path " :cache :" built.cache))
                      (if keepLl? () (keepOnly! slot (sys/baseName bin)))
                      (let [(code (execStaged! bin args))
                            (_ (if keepLl? (ok ()) (pathRemove slot)))]
                        code)))
      ((none) (do (pathRemove slot) (eprintln (failText root rel path shown (failReason built.reason (if (inlineStaged? rel) (inlineName rel) rel)))) 1))))

; (:m :ref OUT-OF-ROOT-USERPATH :do "runFile's path is the caller's own (cwd-relative or absolute, per prepareIn's own note); an in-root file is read where it stands and named by stripping toolRoot (matching prepareCommand!'s prepareSourceIn split); an out-of-root file (testDownstream's downstream copy, a /tmp driver fixture) is staged into root first so its logical name is a real, resolvable one")
fn ! runFile path: String shown: String args: (List String) fp: String -> Int64
  (let [(root (resultOr (realPath (toolRoot)) (toolRoot)))
        (absFile (resultOr (realPath path) path))
        (inRoot (stringStartsWith? absFile (str root "/")))
        (staged (if inRoot (ok (relativeTo root absFile)) (stageOutsideFile! root absFile)))]
    (match staged
      ((err e) (do (eprintln (str "FAIL " path ": ERR_NATIVE_UNSUPPORTED: cannot stage " path ": " e)) 1))
      ((ok rel) (runStaged! root rel path shown args fp))))

fn ! fingerprintOr fpOpt: (Option String) -> String
  (match fpOpt ((some f) f) ((none) (fingerprint)))

fn selfSource -> String
  "asl/tools/nativeTest.asl"

fn ! selfRoot -> String
  (resultOr (realPath (toolRoot)) (toolRoot))

fn ! selfDirIn root: String -> String
  (optionOr (envGet "ASL_NATIVE_SELF_DIR") (str root "/.asl/cache/nativeSelf"))

fn ! selfCacheIn root: String fp: String -> String
  (str (selfDirIn root) "/" fp)

fn ! selfSlotOf cDir: String root: String fp: String -> String
  (str cDir "/" fp "/" (slotKey (str "run:" (importPathOf (selfSource))) (fileDigest (str root "/" (selfSource)))))

(schema SelfState
  (:f binary (Option String))
  (:f failure (Option String)))

fn ! selfStateOf cDir: String root: String fp: String -> SelfState
  (let [(slot (selfSlotOf cDir root fp))
        (bin (str slot "/run"))
        (unknown (SelfState :binary (none) :failure (none)))]
    (match (fileReadString (str slot "/manifest"))
      ((err _) unknown)
      ((ok text)
       (cond
         ((not (manifestFileHolds? root (str slot "/manifest") text)) unknown)
         ((and (= (manifestKind text) "binary") (match (fileStat bin) ((ok st) (> st.size 0)) ((err _) false)))
          (SelfState :binary (some bin) :failure (none)))
         ((= (manifestKind text) "fallback")
          (SelfState :binary (none) :failure (some (resultOr (fileReadString (str slot "/reason")) "reason unreadable"))))
         (else unknown)))))

fn ! selfBinaryOf cDir: String root: String fp: String -> (Option String)
  (selfStateOf cDir root fp).binary

fn ! telemetry line: String -> Unit
  (if (and (= (optionOr (envGet "ASL_NATIVE_QUIET_PID") "") (stringFromInt64 (procSelf))) (!= (optionOr (envGet "ASL_NATIVE_TRACE") "") "1"))
    ()
    (do (eprintln line) ()))

fn ! lockPid path: String -> (Option Int64)
  (match (fileReadString path)
    ((err _) (none))
    ((ok text) (stringToInt64 (stringTrim text))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "liveness asks procAlive?, as asl-cli/nativeCli does, instead of sending the pid a real SIGCONT")
fn ! pidAlive? pid: Int64 -> Bool
  (and (> pid 1) (resultOr (procAlive? pid) false))

fn ! lockLive? path: String -> Bool
  (and (fileExists? path)
       (match (lockPid path) ((none) true) ((some pid) (pidAlive? pid))))

fn ! breakLock! path: String deadPid: Int64 -> Unit
  (let [(stale (str path ".stale." (stringFromInt64 (procSelf))))]
    (match (pathRename path stale)
      ((err _) ())
      ((ok _)
       (let [(moved (resultOr (fileReadString stale) ""))]
         (do (if (= (stringToInt64 (stringTrim moved)) (some deadPid))
               ()
               (match (fileCreateExclusive path moved) ((ok _) ()) ((err _) ())))
             (match (pathRemove stale) ((ok _) ()) ((err _) ())))))))

fn ! takeLock! path: String tries: Int64 -> Bool
  (match (fileCreateExclusive path (stringFromInt64 (procSelf)))
    ((ok _) true)
    ((err _) (if (<= tries 0)
               false
               (match (lockPid path)
                 ((none) false)
                 ((some pid) (if (pidAlive? pid) false (do (breakLock! path pid) (takeLock! path (- tries 1)))))))))

fn ! prepareCommand! path: String fp: String -> Int64
  (let [(root (resultOr (realPath (toolRoot)) (toolRoot)))
        (logicalPath (relativeTo root path))
        (built (prepareSourceIn (cacheDir!) path logicalPath fp "run"))]
    (match built.binary
      ((some bin) (do (println bin) 0))
      ((none) (do (eprintln (str "nativeTest: " path " does not build natively: " built.reason)) 1))))

fn ! dispatch! args: (List String) fpOpt: (Option String) -> (Result Int64 String)
  (match (listHead args)
    ((some cmd)
     (cond
       ((= cmd "run")
        (match (listGet args 1)
          ((none) (do (eprintln "usage: nativeTest run [--as NAME] FILE [ARGS...]") (ok 2)))
          ((some path)
            (if (and (= path "--as") (>= (listLength args) 4))
              (ok (runFile (optionOr (listGet args 3) "") (optionOr (listGet args 2) "") (listDrop args 4) (fingerprintOr fpOpt)))
              (ok (runFile path "" (optionOr (listSlice args 2 (listLength args)) (list)) (fingerprintOr fpOpt)))))))
       ((= cmd "prepare")
        (match (listGet args 1)
          ((none) (do (eprintln "usage: nativeTest prepare FILE") (ok 2)))
          ((some path) (ok (prepareCommand! path (fingerprintOr fpOpt))))))
       ((= cmd "eval")
        (let [(expr (stringJoin (optionOr (listSlice args 1 (listLength args)) (list)) " "))]
          (if (stringEmpty? expr) (do (eprintln "usage: nativeTest eval EXPR") (ok 2)) (ok (evalExpression! expr (fingerprintOr fpOpt))))))
       (else (testMain args fpOpt))))
    ((none) (testMain args fpOpt)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(head (optionOr (listHead args) ""))]
    (cond
      ((= head "--self-fp") (dispatch! (listDrop args 2) (listGet args 1)))
      ((= head "--compile-units") (compileUnitsWorker! (listDrop args 1)))
      ((= head "--fingerprint") (do (println (fingerprint)) (ok 0)))
      (else (dispatch! args (none)))))

fn testHeaderParsing -> Bool
  (let [(src "(module a/b\n  :x [helper\n      runTests]\n  :i [])\n\nfn main -> Int64\n  1\n")
        (mainOnly "(module a/c :x [main other] :i [])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (ok 0)\n")
        (bare "(module a/d :i [])\n\nfn f -> Int64\n  (:x [runTests])\n")]
    (do (assert (= (exportsOf src) (list "helper" "runTests")) "exports read across lines of the :x vector")
        (assert (= (entryOf src) (some "runTests")) "runTests is the entry when exported")
        (assert (= (entryOf mainOnly) (some "main")) "main is the entry when runTests is not exported")
        (assert (none? (entryOf bare)) "an :x after the header is not an export")
        (assert (mainTakesArgs mainOnly) "fn ! main args takes the argument list")
        (refute (mainTakesArgs src) "fn main -> takes nothing")
        (assert (= (importPathOf "./asl/packages/p/tests/xTest.asl") "asl/packages/p/tests/xTest") "import path drops ./ and .asl")
        (assert (stringContains? (wrapperSource "tools/tests/xTest" "runTests" false) ":i [(tools/tests/xTest :a suite)]") "the entry imports the suite by its root path")
        (assert (stringContains? (wrapperSource "t/x" "main" true) "(suite/main (list))") "a main with a parameter gets the empty argument list")
        (refute (stringContains? (wrapperSource "t/x" "main" false) "(list)") "a main without a parameter gets no argument")
        (assert (stringContains? (wrapperSource "t/x" "runTests" false) "(ok 97)") "a runTests entry refuses arguments with exit 97")
        (assert (stringContains? (wrapperSource "t/x" "runTests" false) "(some \"init\")) (ok 0))") "a test entry stops after module initialization in the init phase")
        (refute (stringContains? (wrapperSource "t/x" "run" true) (initPhaseEnv)) "a run entry has no init phase")
        (assert (stringContains? (wrapperSource "t/x" "main" true) (argvGuardMessage)) "a main test entry refuses arguments")
        (refute (stringContains? (wrapperSource "t/x" "run" true) "(ok 97)") "a run entry passes its arguments through")
        true))

fn testVerdictParsing -> Bool
  (let [(pass (verdictOf "s.asl" 0 "note\n7 assertion(s) executed, 2 refutation(s) executed\n"))
        (noRefute (verdictOf "s.asl" 0 "5 assertion(s) executed, 0 refutation(s) executed\n"))
        (fail (verdictOf "s.asl" 1 "ERR_ASSERT: assertion failed: boom\n3 assertion(s) executed, 1 refutation(s) executed\n"))
        (zero (verdictOf "s.asl" 0 "0 assertion(s) executed, 0 refutation(s) executed\n"))
        (crash (verdictOf "s.asl" 139 "partial\n"))
        (crashWithErr (verdictOf "s.asl" 1 "ERR_STACK_DEPTH: native call stack exceeded the 1073741824-byte body thread stack\n"))]
    (do (assert (= (reportCounts "x\n1 assertion(s) executed, 0 refutation(s) executed\n9 assertion(s) executed, 4 refutation(s) executed\n") (some (pair 9 4))) "the last report line wins")
        (assert (none? (reportCounts "s.asl: 9 assertion(s) executed (9 passed)\n")) "an asl-host summary is not a native report")
        (assert (= pass.line "s.asl: 7 assertion(s) executed, 2 refutation(s) executed (9 passed)") "a pass reads as asl-host test prints it")
        (assert (= pass.exit 0) "a pass exits 0")
        (assert (= pass.stderr "note") "the suite's own stderr stays, the report line goes")
        (assert (= noRefute.line "s.asl: 5 assertion(s) executed (5 passed)") "no refutations: the short form")
        (assert (= fail.line "FAIL s.asl: ERR_ASSERT: assertion failed: boom (after 3 asserts)") "a failure names the error and the asserts executed")
        (assert (= fail.exit 1) "a failure exits 1")
        (assert (stringEmpty? fail.stderr) "the error line moves into the FAIL line")
        (assert (= zero.line "FAIL s.asl: ERR_TEST_FAILED: zero assertions executed (after 0 asserts)") "zero assertions fail as on the host")
        (assert (= crash.exit 1) "a run without a report fails")
        (assert (stringContains? crash.line "exited 139 without an assertion report") "and says so")
        (assert (= crashWithErr.exit 1) "a crash with a named error still fails")
        (assert (= crashWithErr.line "FAIL s.asl: ERR_STACK_DEPTH: native call stack exceeded the 1073741824-byte body thread stack") "a crash whose stderr names an ERR_ code (a hard trap, e.g. the stack guard page handler) shows that code instead of the generic exited-without-a-report message")
        (assert (= (hostVerdictLine "out\nFAIL a.asl: ERR_X: y (after 2 asserts)\n") "FAIL a.asl: ERR_X: y (after 2 asserts)") "the host verdict is its FAIL line")
        (assert (none? (initVerdict "s.asl" 0 "0 assertion(s) executed, 0 refutation(s) executed\n")) "a clean module initialization adds no verdict")
        (assert (= (optionMap (fn [(v Verdict)] -> String v.line) (initVerdict "t/s.asl" 0 "2 assertion(s) executed, 0 refutation(s) executed\n"))
                   (some "FAIL t/s.asl: ERR_ASSERT_AT_INIT: assertion executed during module initialization of t/s (2 assertion(s), 0 refutation(s)); asserts and refutes run only from the test entry (D152) (after 2 asserts)"))
                "an assertion during module initialization is ERR_ASSERT_AT_INIT naming the module")
        (assert (stringContains? (optionOr (optionMap (fn [(v Verdict)] -> String v.line) (initVerdict "s.asl" 0 "0 assertion(s) executed, 1 refutation(s) executed\n")) "") "ERR_ASSERT_AT_INIT: refutation executed during module initialization") "a refutation during module initialization says refutation")
        (assert (= (optionMap (fn [(v Verdict)] -> Int64 v.exit) (initVerdict "s.asl" 139 "boom\n")) (some 1)) "a probe without a report fails")
        true))

fn ! testManifestAndSlots dir: String -> Bool
  (let [(f1 (str dir "/dep1"))
        (f2 (str dir "/dep2"))
        (w1 (fileWrite f1 "alpha"))
        (w2 (fileWrite f2 "beta"))
        (t (manifestText "binary" (list f1 f2)))
        (h (manifestHolds? t))]
    (do (assert (ok? w1) "f1 is written")
        (assert (ok? w2) "f2 is written")
        (assert h "the manifest holds against untouched files")
        (assert (= (manifestKind t) "binary") "kind is extracted")
        (assert (= (manifestFiles t) (list f1 f2)) "manifest files are parsed")
        (refute (manifestHolds? "nativeTest/1 binary\n") "an empty manifest never holds")
        (assert (= (slotKey "t/x" "aa") (slotKey "t/x" "aa")) "slot key is deterministic")
        (refute (= (slotKey "t/x" "aa") (slotKey "t/x" "ab")) "the slot depends on the suite content")
        (assert (= (relativeTo "/w" "/w/a/b.asl") "a/b.asl") "a path under the root becomes relative")
        (assert (= (relativeTo "/w" "/wx/b.asl") "/wx/b.asl") "a sibling of the root stays absolute")
        true))

fn ! testManifestStamp dir: String -> Bool
  (let [(f (str dir "/stamped"))
        (m (str dir "/stamped.manifest"))
        (second (* (- (/ (nowNs) 1000000000) 5) 1000000000))
        (w1 (fileWrite f "one"))
        (u1 (fileUtime f (+ second 123456789)))
        (t (manifestText "binary" (list f)))
        (wm (fileWrite m t))
        (fresh (manifestFileHolds? "." m t))
        (w2 (fileWrite f "two"))
        (u2 (fileUtime f second))]
    (do (assert (and (ok? w1) (and (ok? u1) (and (ok? wm) (and (ok? w2) (ok? u2))))) "the stamped file and its manifest are written")
        (assert fresh "the manifest holds while the file is untouched")
        (refute (manifestFileHolds? "." m t) "a same-size edit whose mtime is reset to the recorded second does not hold")
        (assert (= (wrapperDirIn "rel/cache") "rel/cache/entries") "the entry wrapper lives under a cache root inside the workspace")
        (assert (stringStartsWith? (wrapperDirIn "/c") ".asl/cache/nativeTest/entries/") "a cache root outside the workspace keeps its wrappers inside it, where imports resolve")
        (refute (= (wrapperDirIn "/c") (wrapperDirIn "/d")) "one entries directory per outside cache root")
        true))

fn ! testLock dir: String -> Bool
  (let [(lock (str dir "/lock"))
        (held (fileCreateExclusive lock (stringFromInt64 (procSelf))))
        (_ (breakLock! lock 999999))
        (kept (lockPid lock))
        (cleared (pathRemove lock))
        (dead (fileCreateExclusive lock "999999"))
        (taken (takeLock! lock 3))
        (owner (lockPid lock))
        (released (pathRemove lock))]
    (do (assert (= kept (some (procSelf))) (str "breaking a lock for another pid leaves the live holder's lock: " kept))
        (assert (and (ok? held) (and (ok? cleared) (and (ok? dead) (ok? released)))) "the lock files are written and removed")
        (refute (pidAlive? 999999) "pid 999999 is not alive")
        (assert taken "a lock held by a dead pid is taken")
        (assert (= owner (some (procSelf))) "and then holds this process's pid")
        true))

fn ! testRoots -> Bool
  (let [(roots (toolchainRoots))]
    (do (refute (listContains? roots "asl/host/out/asl-host") "toolchainRoots no longer names the retired asl-host (HL-DELETE: it can never exist again)")
        (assert (listContains? roots "asl/host/out/libaslrt.a") "toolchainRoots includes libaslrt.a")
        (assert (listContains? roots "asl/tools/nativeTest.asl") "toolchainRoots includes nativeTest.asl")
        true))

fn testEvalInputValidation -> Bool
  (do (assert (singleBalancedForm? "(+ 1 (* 2 3))") "one nested expression is accepted")
      (refute (singleBalancedForm? "(+ 1 2) (+ 3 4)") "multiple top-level forms are rejected")
      (refute (singleBalancedForm? "x)) (fn ! injected -> Int64 0)") "unbalanced input cannot escape the expression form")
      true)

fn ! testNativeExecution cacheDir: String -> Bool
  (let [(fixturePath "tools/tests/fixtures/nativeTest/passingSuite.asl")
        (fp (fingerprint))
        (b1 (prepareIn cacheDir fixturePath fp "test"))
        (bin1 (optionOr b1.binary ""))
        (run1 (if (stringEmpty? bin1) (ProcOut :exitCode 1 :stdout "" :stderr "no bin") (runProc (list "nice" "-n" "15" bin1) (some (withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl"))))))
        (v (verdictOf fixturePath run1.exitCode run1.stderr))
        (b2 (prepareIn cacheDir fixturePath fp "test"))]
    (do (assert (some? b1.binary) (str "native compilation of passingSuite succeeds: " b1.reason))
        (refute (= b1.cache "fallback-hit") "passingSuite does not fall back")
        (assert (= b1.cache "miss") "first build is a cache miss")
        (assert (= run1.exitCode 0) "native binary exit code is 0")
        (assert (= v.exit 0) "verdict exit is 0")
        (assert (stringContains? run1.stdout "passing fixture ran") "stdout contains fixture output")
        (assert (stringContains? v.line "4 assertion(s) executed, 2 refutation(s) executed (6 passed)") "verdict reports 4 assertions and 2 refutations")
        (assert (some? b2.binary) (str "warm build succeeds: " b2.reason))
        (assert (= b2.cache "hit") "second build hits the cache")
        true))

fn ! runTests -> Bool
  (let [(dir (str ".asl/cache/nativeTest-self-" (monotonicNs)))
        (made (dirCreate dir))
        (result (and (ok? made)
                     (and (testHeaderParsing)
                          (and (testVerdictParsing)
                               (and (testManifestAndSlots dir)
                                    (and (testManifestStamp dir)
                                    (and (testLock dir)
                                    (and (testRoots)
                                         (and (testEvalInputValidation)
                                              (testNativeExecution (str dir "/cache")))))))))))
        (removed (pathRemove dir))]
    (do (assert (ok? made) "the scratch directory is created")
        (assert (ok? removed) "the scratch directory is removed")
        result))
