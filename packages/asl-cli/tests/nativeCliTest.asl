(module asl-cli/tests/nativeCliTest
  :x [runTests normalize telemetry? caseJob cliEnv Case caseLine readCases prepareSweep!]
  :i [(asl-tools/fleet/run :a run) (asl-tools/nativeTest :a nt) (asl/packages/asl-cli/src/nativeCli :a nc)])

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

fn normalize text: String root: String sweep: String -> String
  (let [(lines (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace text sweep "$SWEEP") root "$ROOT") ":runner \"native\"" ":runner \"asl-host\"") " (cached)" "") "\n"))]
    (stringJoin (filter (fn [(l String)] -> Bool (not (telemetry? l))) lines) "\n"))

fn envName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

; (:m :ref HL-FIXWAVE :do "HOSTBIN: host used to be the literal string /nonexistent/asl-host -- a path that merely happens not to exist, so replay! could not tell 'the build correctly never touched hostBin' apart from 'something else masked a touch that would otherwise have failed the same way'. host is now a real, executable witness stub (hostWitness!) that logs every invocation to ASL_HOST_WITNESS before exiting nonzero; runTests asserts that log stays empty across every replayed case, buildHostAbsent included, so a build that quietly execs ctx.hostBin is caught even if its exit code and output would otherwise have matched")
; (:m :ref TRAIN-SHARED-NATIVE-20261022 :do "HOME=$ROOT made warmCli! and the one case that re-enters bin/asl build the whole native CLI into $ROOT/.asl/run/nativeCli, a per-tree cache; the caller's own cache dir is forwarded instead so both are cache hits, while an overriding case env still wins")
fn sharedCli -> String
  (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))

fn cliEnv root: String host: String errFile: String overrides: (List String) -> (List String)
  (listAppend (filter (fn [(row String)] -> Bool (not (listContains? (map envName overrides) (envName row))))
    (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp" (str "ASL_ROOT=" root) (str "ASL_CLI_ROOT=" root) (str "ASL_CLI_SCRIPT_DIR=" root "/bin")
        (str "ASL_CLI_ARGV0=" root "/bin/asl") (str "ASL_CLI_HOST_BIN=" host) (str "ASL_HOST=" host) (str "ASL_HOST_WITNESS=" host ".log") (str "NATIVE_CLI_ERR=" errFile) (str "ASL_NATIVE_CLI_CACHE=" (sharedCli))))
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

fn ! replay! c: Case binary: String root: String errFile: String sweep: String host: String -> (List String)
  (let [(_ (fileWrite errFile ""))
        (d (run/runOneLimited (caseJob (list binary) c root host errFile sweep) (run/limits 900 32)))
        (errText (resultOr (fileReadString errFile) ""))
        (out (normalize d.out root sweep))
        (errNorm (normalize errText root sweep))]
    (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
      (list (if (= d.verdict "exit") "" (str "verdict " d.verdict))
            (if (= out c.stdout) "" (str "stdout native " (asnQuote out) " host " (asnQuote c.stdout)))
            (if (= errNorm c.stderr) "" (str "stderr native " (asnQuote errNorm) " host " (asnQuote c.stderr)))
            (if (= d.exit c.exit) "" (str "exit native " (stringFromInt64 d.exit) " host " (stringFromInt64 c.exit))))))

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

fn ! prepareSweep! root: String -> (Result String String)
  (let [(dir (str root "/.asl/cache/nativeCliSweep/" (stringFromInt64 (procSelf))))]
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

; (:m :ref TOOLNT :do "asl build routes through the cached native asl1: after one build the newest head of the asl1 cache names an entry whose rc marker is notrace and whose binary prints :rcStats; a tracing fallback lives under <key>-tracing and is never a head's target")
fn ! cachedAsl1Entry! root: String work: String cache: String -> String
  (let [(src (str work ".asl"))
        (_ (fileWrite src "(module hello\n  :x [main]\n  :i [])\n\nfn ! main -> (Result Int64 String)\n  (ok 0)\n"))
        (d (run/runOneLimited (run/job (list (str root "/bin/asl") "build" src "-o" work) root (list "PATH=/usr/bin:/bin" (str "HOME=" (optionOr (envGet "HOME") "/tmp")) (str "ASL_NATIVE_ASL1_CACHE=" cache))) (run/limits 1800 32)))
        (hd (run/runOneLimited (run/job (list "/bin/sh" "-c" (str "ls -t \"" cache "\"/head-* 2>/dev/null | head -n 1")) root (list "PATH=/usr/bin:/bin")) (run/limits 60 8)))
        (heads (stringTrim hd.out))
        (key (stringTrim (resultOr (fileReadString heads) "")))]
    (if (and (= d.verdict "exit") (and (= d.exit 0) (not (stringEmpty? key)))) (str cache "/" key) ""))

fn ! asl1CacheNotrace! root: String errFile: String -> Bool
  (let [(cache (str errFile ".asl1"))
        (entry (cachedAsl1Entry! root (str errFile ".hello") cache))
        (good (and (not (stringEmpty? entry))
                   (and (= (resultOr (fileReadString (str entry "/rc")) "") "notrace\n")
                        (stringContains? (rcStatsOf! (str entry "/asl1-native") errFile) ":rcStats"))))
        (_ (run/runOneLimited (run/job (list "/bin/rm" "-rf" cache (str errFile ".hello") (str errFile ".hello.asl")) root (list)) (run/limits 60 8)))]
    good)

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
        (sweep (prepareSweep! root))
        (sweepDir (resultOr sweep "/nonexistent/sweep"))
        (warm (warmCli! root errFile host))
        (found (match (if (ok? sweep) built (none))
                 ((none) (list))
                 ((some bin) (map (fn [(c Case)] -> (Pair String (List String)) (pair c.id (replay! c bin root errFile sweepDir host))) liveCases))))
        (problems (fold (fn [(acc (List String)) (p (Pair String (List String)))] -> (List String) (if (listEmpty? (pairSecond p)) acc (listAppend acc (list (str "case " (pairFirst p) ": " (stringJoin (pairSecond p) "; ")))))) (list) found))
        (witnessText (resultOr (fileReadString hostLog) ""))
        (removed (if (fileExists? errFile) (pathRemove errFile) (ok ())))
        (hostGone (if (fileExists? host) (pathRemove host) (ok ())))
        (hostLogGone (if (fileExists? hostLog) (pathRemove hostLog) (ok ())))
        (sweepGone (if (ok? sweep) (pathRemove sweepDir) (ok ())))]
    (do
      (assert (ok? cases) (match cases ((err e) e) ((ok _) "cases read")))
      (assert (listAny? (fn [(c Case)] -> Bool (= c.id "buildHostAbsent")) allCases) "the known BUILD-HOSTBIN gap case stays in the fixture")
      (assert (ok? witnessWritten) (match witnessWritten ((err e) (str "host witness stub: " e)) ((ok _) "host witness stub written")))
      (assert (some? built) "asl/packages/asl-cli/src/native.asl builds natively")
      (assert (ok? sweep) (match sweep ((err e) (str "sweep workspace: " e)) ((ok _) "sweep workspace")))
      (assert (and (= warm.verdict "exit") (= warm.exit 0)) (str "the workspace CLI that cases re-enter as $ROOT/bin/asl is built before replay: " warm.verdict " " (stringFromInt64 warm.exit) " " warm.out))
      (assert (stringContains? (rcStatsOf! (str (installedCli! root) "/bin") errFile) ":rcStats") "the installed native CLI links the untraced RC runtime (ASL_RC_STATS=1 prints :rcStats)")
      (assert (stringContains? (rcStatsOf! (notraceAsl1!) errFile) ":rcStats") "a notrace asl1 stage exists in the native CLI cache (rc marker) and prints :rcStats")
      (assert (asl1CacheNotrace! root errFile) "the cached asl1 that asl build uses is a notrace build: rc marker notrace and :rcStats on exit")
      (assert (> (listLength found) 0) "at least one case replayed")
      (assert (= (listLength found) (listLength liveCases)) "every live case replayed")
      (assert (stringEmpty? witnessText) (str "buildHostAbsent and every other replayed case never touch ctx.hostBin/ASL_HOST (HOSTBIN): " witnessText))
      (assert (listEmpty? problems) (str "native equals asl-host on every live case; " (stringJoin problems " | ")))
      (assert (and (ok? removed) (and (ok? hostGone) (and (ok? hostLogGone) (and (ok? sweepGone) (not (fileExists? sweepDir)))))) "stderr capture file, host witness stub/log and sweep workspace removed")
      (testGatewayVerbsAreForms!)))
