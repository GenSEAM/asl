(module asl-cli/tests/nativeCliTest
  :x [runTests normalize telemetry? caseJob cliEnv Case caseLine readCases prepareSweep!]
  :i [(asl-tools/fleet/run :a run) (asl-tools/nativeTest :a nt) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/asl1Cache :a ac)])

(schema Case
  (:f id String)
  (:f argv (List String))
  (:f env (List String))
  (:f stdout String)
  (:f stderr String)
  (:f exit Int64))

fn asnQuote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\r" "\\r") "\"")

fn caseLine c: Case -> String
  (str "(:case :id " (asnQuote c.id) " :argv [" (stringJoin (map asnQuote c.argv) " ") "]" (if (listEmpty? c.env) "" (str " :env [" (stringJoin (map asnQuote c.env) " ") "]")) " :stdout " (asnQuote c.stdout) " :stderr " (asnQuote c.stderr) " :exit " (stringFromInt64 c.exit) ")")

fn unescape c: Int64 -> String
  (cond ((= c 110) "\n") ((= c 116) "\t") ((= c 114) "\r") ((= c 34) "\"") (else "\\"))

fn readText line: String b: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (cond
    ((>= i n) (err "unterminated string"))
    ((= (bytesGet b i) 34) (ok (pair (stringJoin (listReverse (cons (optionOr (stringSlice line start i) "") acc)) "") (+ i 1))))
    ((and (= (bytesGet b i) 92) (< (+ i 1) n)) (readText line b (+ i 2) n (+ i 2) (cons (unescape (bytesGet b (+ i 1))) (cons (optionOr (stringSlice line start i) "") acc))))
    (else (readText line b (+ i 1) n start acc)))

fn atomEnd? c: Int64 -> Bool
  (or (or (= c 32) (= c 9)) (or (or (= c 41) (= c 93)) (= c 40)))

fn atomStop b: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (atomEnd? (bytesGet b i)))) (atomStop b (+ i 1) n) i)

fn tokens line: String b: Bytes i: Int64 n: Int64 acc: (List String) -> (Result (List String) String)
  (cond
    ((>= i n) (ok (listReverse acc)))
    ((or (or (= (bytesGet b i) 32) (= (bytesGet b i) 9)) (or (= (bytesGet b i) 40) (= (bytesGet b i) 41))) (tokens line b (+ i 1) n acc))
    ((= (bytesGet b i) 91) (tokens line b (+ i 1) n (cons "[" acc)))
    ((= (bytesGet b i) 93) (tokens line b (+ i 1) n (cons "]" acc)))
    ((= (bytesGet b i) 34) (match (readText line b (+ i 1) n (+ i 1) (list)) ((err e) (err e)) ((ok p) (tokens line b (pairSecond p) n (cons (str "s:" (pairFirst p)) acc)))))
    (else (let [(j (atomStop b i n))] (tokens line b j n (cons (optionOr (stringSlice line i j) "") acc)))))

fn textOf tok: String -> (Option String)
  (if (stringStartsWith? tok "s:") (stringSlice tok 2 (stringLength tok)) (none))

fn after toks: (List String) key: String -> (List String)
  (match (listIndexOf toks key) ((some i) (listDrop toks (+ i 1))) ((none) (list)))

fn untilClose toks: (List String) acc: (List String) -> (List String)
  (match (listHead toks)
    ((none) (listReverse acc))
    ((some t) (if (= t "]") (listReverse acc) (untilClose (listDrop toks 1) (cons (optionOr (textOf t) t) acc)))))

fn vectorOf toks: (List String) -> (List String)
  (if (= (optionOr (listHead toks) "") "[") (untilClose (listDrop toks 1) (list)) (list))

fn readCase line: String -> (Result Case String)
  (match (let [(b (stringToBytes line))] (tokens line b 0 (bytesLength b) (list)))
    ((err e) (err e))
    ((ok toks)
      (let [(id (optionOr (textOf (optionOr (listHead (after toks ":id")) "")) ""))
            (exit (stringToInt64 (optionOr (listHead (after toks ":exit")) "")))]
        (if (or (stringEmpty? id) (none? exit))
          (err (str "case without :id or :exit: " line))
          (ok (Case :id id :argv (vectorOf (after toks ":argv")) :env (vectorOf (after toks ":env"))
                    :stdout (optionOr (textOf (optionOr (listHead (after toks ":stdout")) "")) "")
                    :stderr (optionOr (textOf (optionOr (listHead (after toks ":stderr")) "")) "")
                    :exit (optionOr exit 0)))))))

fn readCases text: String -> (Result (List Case) String)
  (fold (fn [(acc (Result (List Case) String)) (line String)] -> (Result (List Case) String)
          (match acc
            ((err e) (err e))
            ((ok cs) (if (stringStartsWith? (stringTrim line) "(:case ")
                       (match (readCase (stringTrim line)) ((err e) (err e)) ((ok c) (ok (listAppend cs (list c)))))
                       (ok cs)))))
        (ok (list)) (stringLines text))

fn telemetry? line: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? line p))
            (list "NATIVE-SELF " "NATIVE-PRELUDE-" "NATIVE-MODULE-PHASE" "NATIVE-CACHE " "NATIVE-WORKERS " "NATIVE-EVAL"))

; (:m :ref INBOX-RELEASE-PIN :do "the version banner carries the release tag and commit of the tree under test, which change with every commit; the line keeps its banner and the word release, the tag and commit are masked to $RELEASE (releaseTest pins their values)")
fn releaseMask line: String -> String
  (if (stringStartsWith? line "asl 0.1.0 (bin/asl) release ") "asl 0.1.0 (bin/asl) release $RELEASE" line)

fn normalize text: String root: String sweep: String -> String
  (let [(lines (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace text sweep "$SWEEP") root "$ROOT") ":runner \"native\"" ":runner \"asl-host\"") " (cached)" "") "\n"))]
    (stringJoin (map releaseMask (filter (fn [(l String)] -> Bool (not (telemetry? l))) lines)) "\n"))

fn envName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

; (:m :ref HL-FIXWAVE :do "HOSTBIN: host used to be the literal string /nonexistent/asl-host -- a path that merely happens not to exist, so replay! could not tell 'the build correctly never touched hostBin' apart from 'something else masked a touch that would otherwise have failed the same way'. host is now a real, executable witness stub (hostWitness!) that logs every invocation to ASL_HOST_WITNESS before exiting nonzero; runTests asserts that log stays empty across every replayed case, buildHostAbsent included, so a build that quietly execs ctx.hostBin is caught even if its exit code and output would otherwise have matched")
; (:m :ref TRAIN-SHARED-NATIVE-20261022 :do "HOME=$ROOT made warmCli! and the one case that re-enters bin/asl build the whole native CLI into $ROOT/.asl/run/nativeCli, a per-tree cache; the caller's own cache dir is forwarded instead so both are cache hits, while an overriding case env still wins")
fn sharedCli -> String
  (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))

; (:m :ref NATIVECLI-RUNTIME :do "HOME=$ROOT also sent asl build (buildHostAbsent) to a per-tree asl1 cache, a cold asl1 build of about 430 s in every fresh worktree (measured 2026-11-11, load 15) while the caller's cache already held the same keyed entry; the caller's asl1 cache is forwarded like the CLI cache")
fn sharedAsl1 -> String
  (optionOr (envGet "ASL_NATIVE_ASL1_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/asl1"))

fn cliEnv root: String host: String errFile: String overrides: (List String) -> (List String)
  (listAppend (filter (fn [(row String)] -> Bool (not (listContains? (map envName overrides) (envName row))))
    (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp" (str "ASL_ROOT=" root) (str "ASL_CLI_ROOT=" root) (str "ASL_CLI_SCRIPT_DIR=" root "/bin")
        (str "ASL_CLI_ARGV0=" root "/bin/asl") (str "ASL_CLI_HOST_BIN=" host) (str "ASL_HOST=" host) (str "ASL_HOST_WITNESS=" host ".log") (str "NATIVE_CLI_ERR=" errFile) (str "ASL_NATIVE_CLI_CACHE=" (sharedCli)) (str "ASL_NATIVE_ASL1_CACHE=" (sharedAsl1))))
    overrides)

fn ! hostWitness! path: String -> (Result Unit String)
  (match (fileWrite path "#!/bin/sh\necho \"host-invoked $*\" >> \"$ASL_HOST_WITNESS\"\nexit 97\n")
    ((err e) (err e))
    ((ok _) (match (fileChmod path 493) ((err e) (err e)) ((ok _) (ok ())))))

fn expand s: String root: String sweep: String -> String
  (stringReplace (stringReplace s "$SWEEP" sweep) "$ROOT" root)

fn caseJob program: (List String) c: Case root: String host: String errFile: String sweep: String -> run/Job
  (run/job (listAppend (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$NATIVE_CLI_ERR\"") (listAppend program (map (fn [(a String)] -> String (expand a root sweep)) c.argv)))
           root (cliEnv root host errFile (map (fn [(e String)] -> String (expand e root sweep)) c.env)))

; (:m :ref NATIVECLI-RUNTIME :do "cases are judged apart from their run so the pool can run them side by side; each case has its own stderr capture file, and a case that names $SWEEP its own sweep workspace, so no two running cases share a file")
fn ! judge! c: Case d: run/Done errFile: String root: String sweep: String -> (List String)
  (let [(errText (resultOr (fileReadString errFile) ""))
        (out (normalize d.out root sweep))
        (errNorm (normalize errText root sweep))]
    (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
      (list (if (= d.verdict "exit") "" (str "verdict " d.verdict))
            (if (= out c.stdout) "" (str "stdout native " (asnQuote out) " host " (asnQuote c.stdout)))
            (if (= errNorm c.stderr) "" (str "stderr native " (asnQuote errNorm) " host " (asnQuote c.stderr)))
            (if (= d.exit c.exit) "" (str "exit native " (stringFromInt64 d.exit) " host " (stringFromInt64 c.exit))))))

fn sweepCase? c: Case -> Bool
  (listAny? (fn [(a String)] -> Bool (stringContains? a "$SWEEP")) (listAppend c.argv c.env))

fn caseErr errFile: String i: Int64 -> String
  (str errFile "." (stringFromInt64 i))

fn noSweep -> String
  "/nonexistent/sweep"

; (:m :do "a case that re-enters $ROOT/bin/asl (auditIntelTrace) reaches the native CLI cache under HOME=$ROOT; after any source change its first call prints the stale-CLI rebuild banner on stderr, a build event rather than CLI behaviour, so one call with the case environment builds it before the replay")
fn ! warmCli! root: String errFile: String host: String -> run/Done
  (run/runOneLimited (run/job (list (str root "/bin/asl") "version") root (cliEnv root host errFile (list))) (run/limits 1800 32))

fn ! git! dir: String args: (List String) -> (Result Unit String)
  (let [(d (run/runOneLimited (run/job (cons "git" args) dir (run/childEnv (list "GIT_CONFIG_NOSYSTEM=1"))) (run/limits 60 8)))]
    (if (and (= d.verdict "exit") (= d.exit 0)) (ok ()) (err (str "git " (stringJoin args " ") ": " d.out))))

fn ! copyFixture! root: String dir: String name: String -> (Result Unit String)
  (match (fileReadString (str root "/asl/packages/asl-cli/tests/fixtures/sweep/" name))
    ((err e) (err (str "cannot read fixture " name)))
    ((ok text) (match (fileWrite (str dir "/tests/" name) text) ((err e) (err (str "cannot write " name))) ((ok _) (ok ())))))

fn ! prepareSweep! root: String tag: String -> (Result String String)
  (let [(dir (str root "/.asl/cache/nativeCliSweep/" (stringFromInt64 (procSelf)) "-" tag))]
    (match (dirCreate (str dir "/tests"))
      ((err e) (err (str "cannot create " dir)))
      ((ok _)
        (let [(steps (list (copyFixture! root dir "passTest.asl") (copyFixture! root dir "failTest.asl") (copyFixture! root dir "zeroTest.asl")
                           (git! dir (list "init" "-q")) (git! dir (list "add" "-A"))
                           (git! dir (list "-c" "user.name=nativeCliTest" "-c" "user.email=nativeCliTest@localhost" "commit" "-q" "-m" "sweep fixture"))))]
          (match (listHead (filter err? steps))
            ((some bad) (match bad ((err e) (err e)) ((ok _) (err "unreachable"))))
            ((none) (ok dir)))))))

fn knownGapIds -> (List String)
  (list)

fn replayable cs: (List Case) -> (List Case)
  (filter (fn [(c Case)] -> Bool (not (listContains? (knownGapIds) c.id))) cs)

; (:m GWSTATS-HOSTGAP: "gateway"/"relay"/"rla" are dispatched by command.asl's dispatch! (tool! ctx "asl-gateway" args), never by the retired stage-0 host; verbKind must classify them as "forms" so nativeGate! never routes them through hostExec!'s ERR_HOST_ABSENT, which asl/host/build.sh's own header says no host is built to answer)
fn testGatewayVerbsAreForms! -> Bool
  (do
    (assert (!= (nc/verbKind (list "gateway" "stats")) "host") "gateway must not be classified as needing the retired stage-0 host")
    (assert (!= (nc/verbKind (list "relay" "stats")) "host") "relay (gateway alias) must not be classified as needing the retired stage-0 host")
    (assert (!= (nc/verbKind (list "rla" "stats")) "host") "rla (gateway alias) must not be classified as needing the retired stage-0 host")
    (assert (= (nc/verbKind (list "gateway" "stats")) "forms") "gateway classifies as forms, same lane as audit/build/pack")
    true)

; (:m :ref TOOLNT :do "the installed native CLI and the asl1 stage that built it carry the untraced RC runtime: ASL_RC_STATS=1 makes only an RC build print :rcStats on exit, a tracing build never does; the CLI is the head recorded for this workspace after warmCli!, the asl1 stage is any cache dir whose rc marker nativeBuild install! wrote")
fn ! rcStatsOf! bin: String errFile: String -> String
  (let [(_ (fileWrite errFile ""))
        (d (run/runOneLimited (run/job (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$1\"" bin errFile "version") "/tmp" (list "PATH=/usr/bin:/bin" "ASL_RC_STATS=1")) (run/limits 120 8)))]
    (resultOr (fileReadString errFile) ""))

fn ! installedCli! root: String -> String
  (stringTrim (resultOr (fileReadString (nc/headPath (sharedCli) root)) ""))

fn ! notraceAsl1! -> String
  (let [(cache (sharedCli))
        (dirs (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "asl1-") (fileExists? (str cache "/" n "/rc")))) (resultOr (dirList cache) (list))))]
    (match (listHead dirs) ((none) "") ((some n) (str cache "/" n "/bin"))))

; (:m :ref ASL1-NOTRACE-COLD :do "asl build in this tree runs once against the caller's asl1 cache: a warm hit when the keyed entry exists, a cold build into that cache only when it is missing (it was a cold build into a fresh cache on every run, 377 s). The entry checked is the one the head for this tree's compiler, runtime and clang names (asl1Cache headName!), not the newest head. A stage that fell back to the tracing runtime is installed under <key>-tracing and never under the key (installStage!, asserted by asl1BootstrapTest), so the keyed entry is a notrace build; its rc marker and :rcStats on exit confirm it")
fn ! asl1EntryFor! root: String work: String -> String
  (let [(cache (sharedAsl1))
        (clang (resultOr (nc/clangFor! root) "clang"))
        (src (str work ".asl"))
        (_ (fileWrite src "(module hello\n  :x [main]\n  :i [])\n\nfn ! main -> (Result Int64 String)\n  (ok 0)\n"))
        (d (run/runOneLimited (run/job (list (str root "/bin/asl") "build" src "-o" work) root (list "PATH=/usr/bin:/bin" (str "HOME=" (optionOr (envGet "HOME") "/tmp")) (str "CLANG=" clang) (str "ASL_NATIVE_ASL1_CACHE=" cache))) (run/limits 1800 32)))
        (head (ac/headName! (str root "/asl/packages/asl-compiler/src/asl1.asl") (str root "/asl/host/out/libaslrt.a") clang))
        (key (match head ((err _) "") ((ok h) (stringTrim (resultOr (fileReadString (str cache "/" h)) "")))))
        (_ (map (fn [(f String)] -> Bool (or (not (fileExists? f)) (ok? (pathRemove f)))) (list work src)))]
    (if (and (= d.verdict "exit") (and (= d.exit 0) (not (stringEmpty? key)))) (str cache "/" key) ""))

fn ! notraceEntry? entry: String errFile: String -> Bool
  (and (not (stringEmpty? entry))
       (and (= (resultOr (fileReadString (str entry "/rc")) "") "notrace\n")
            (stringContains? (rcStatsOf! (str entry "/asl1-native") errFile) ":rcStats")))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cases (match (fileReadString (str root "/asl/packages/asl-cli/tests/fixtures/argv.asn")) ((err _) (err "argv.asn unreadable: run from the workspace root")) ((ok text) (readCases text))))
        (allCases (resultOr cases (list)))
        (liveCases (replayable allCases))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)).binary)
        (errFile (str "/tmp/aslNativeCli" (stringFromInt64 (procSelf)) ".err"))
        (host (str errFile ".hostWitness"))
        (hostLog (str host ".log"))
        (witnessWritten (hostWitness! host))
        (ids (range 0 (listLength liveCases)))
        (sweeps (map (fn [(i Int64)] -> (Result String String) (if (sweepCase? (optionOr (listGet liveCases i) (Case :id "" :argv (list) :env (list) :stdout "" :stderr "" :exit 0))) (prepareSweep! root (stringFromInt64 i)) (ok (noSweep)))) ids))
        (sweep (optionOr (listHead (filter err? sweeps)) (ok "every sweep workspace")))
        (sweepDirs (map (fn [(r (Result String String))] -> String (resultOr r (noSweep))) sweeps))
        (madeSweeps (filter (fn [(d String)] -> Bool (!= d (noSweep))) sweepDirs))
        (warm (warmCli! root errFile host))
        (asl1Entry (asl1EntryFor! root (str errFile ".hello")))
        (workers (nt/suiteWorkersFor (listLength liveCases) (resultOr (cpuCount) 1)))
        (found (match (if (ok? sweep) built (none))
                 ((none) (list))
                 ((some bin) (let [(_ (map (fn [(i Int64)] -> Bool (ok? (fileWrite (caseErr errFile i) ""))) ids))
                                   (jobs (map (fn [(i Int64)] -> run/Job (caseJob (list bin) (optionOr (listGet liveCases i) (Case :id "" :argv (list) :env (list) :stdout "" :stderr "" :exit 0)) root host (caseErr errFile i) (optionOr (listGet sweepDirs i) (noSweep)))) ids))
                                   (done (run/runPoolLimited jobs workers (run/limits 900 32)))]
                               (map (fn [(d run/Done)] -> (Pair String (List String))
                                      (match (listGet liveCases d.idx)
                                        ((none) (pair (str "#" (stringFromInt64 d.idx)) (list "result for no case")))
                                        ((some c) (pair c.id (judge! c d (caseErr errFile d.idx) root (optionOr (listGet sweepDirs d.idx) (noSweep)))))))
                                    done)))))
        (problems (fold (fn [(acc (List String)) (p (Pair String (List String)))] -> (List String) (if (listEmpty? (pairSecond p)) acc (listAppend acc (list (str "case " (pairFirst p) ": " (stringJoin (pairSecond p) "; ")))))) (list) found))
        (witnessText (resultOr (fileReadString hostLog) ""))
        (removed (fold (fn [(acc (Result Unit String)) (f String)] -> (Result Unit String) (match (if (fileExists? f) (pathRemove f) (ok ())) ((err e) (err e)) ((ok _) acc)))
                       (ok ()) (cons errFile (map (fn [(i Int64)] -> String (caseErr errFile i)) ids))))
        (hostGone (if (fileExists? host) (pathRemove host) (ok ())))
        (hostLogGone (if (fileExists? hostLog) (pathRemove hostLog) (ok ())))
        (sweepGone (fold (fn [(acc (Result Unit String)) (d String)] -> (Result Unit String) (match (pathRemove d) ((err e) (err e)) ((ok _) acc))) (ok ()) madeSweeps))]
    (do
      (assert (ok? cases) (match cases ((err e) e) ((ok _) "cases read")))
      (assert (listAny? (fn [(c Case)] -> Bool (= c.id "buildHostAbsent")) allCases) "the known BUILD-HOSTBIN gap case stays in the fixture")
      (assert (ok? witnessWritten) (match witnessWritten ((err e) (str "host witness stub: " e)) ((ok _) "host witness stub written")))
      (assert (some? built) "asl/packages/asl-cli/src/native.asl builds natively")
      (assert (ok? sweep) (match sweep ((err e) (str "sweep workspace: " e)) ((ok _) "sweep workspace")))
      (assert (and (= warm.verdict "exit") (= warm.exit 0)) (str "the workspace CLI that cases re-enter as $ROOT/bin/asl is built before replay: " warm.verdict " " (stringFromInt64 warm.exit) " " warm.out))
      (assert (stringContains? (rcStatsOf! (str (installedCli! root) "/bin") errFile) ":rcStats") "the installed native CLI links the untraced RC runtime (ASL_RC_STATS=1 prints :rcStats)")
      (assert (stringContains? (rcStatsOf! (notraceAsl1!) errFile) ":rcStats") "a notrace asl1 stage exists in the native CLI cache (rc marker) and prints :rcStats")
      (assert (not (stringEmpty? asl1Entry)) "asl build in this tree resolves through the caller's asl1 cache: the head for its compiler, runtime and clang (asl1Cache headName!) names a keyed entry")
      (assert (notraceEntry? asl1Entry errFile) "the cached asl1 that asl build uses is a notrace build: rc marker notrace and :rcStats on exit")
      (assert (listContains? (cliEnv root host errFile (list)) (str "ASL_NATIVE_ASL1_CACHE=" (sharedAsl1))) "cliEnv forwards the caller's asl1 cache, so asl build in a case hits the shared keyed entry instead of a cold per-tree build")
      (assert (> (listLength found) 0) "at least one case replayed")
      (assert (= (listLength found) (listLength liveCases)) "every live case replayed")
      (assert (stringEmpty? witnessText) (str "buildHostAbsent and every other replayed case never touch ctx.hostBin/ASL_HOST (HOSTBIN): " witnessText))
      (assert (listEmpty? problems) (str "native equals asl-host on every live case; " (stringJoin problems " | ")))
      (assert (and (ok? removed) (and (ok? hostGone) (and (ok? hostLogGone) (and (ok? sweepGone) (not (listAny? (fn [(d String)] -> Bool (fileExists? d)) madeSweeps)))))) "stderr capture file, host witness stub/log and sweep workspace removed")
      (testGatewayVerbsAreForms!)))
