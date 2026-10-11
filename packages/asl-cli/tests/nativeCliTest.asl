(module asl-cli/tests/nativeCliTest
  :x [runTests normalize telemetry? caseJob cliEnv Case caseLine readCases prepareSweep!]
  :i [(tools/fleet/run :a run) (tools/nativeTest :a nt)])

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
    ((= (bytesGet b i) 34) (mt (readText line b (+ i 1) n (+ i 1) (list)) ((err e) (err e)) ((ok p) (tokens line b (pairSecond p) n (cons (str "s:" (pairFirst p)) acc)))))
    (else (let [(j (atomStop b i n))] (tokens line b j n (cons (optionOr (stringSlice line i j) "") acc)))))

fn textOf tok: String -> (Option String)
  (if (stringStartsWith? tok "s:") (stringSlice tok 2 (stringLength tok)) (none))

fn after toks: (List String) key: String -> (List String)
  (mt (listIndexOf toks key) ((some i) (listDrop toks (+ i 1))) ((none) (list)))

fn untilClose toks: (List String) acc: (List String) -> (List String)
  (mt (listHead toks)
    ((none) (listReverse acc))
    ((some t) (if (= t "]") (listReverse acc) (untilClose (listDrop toks 1) (cons (optionOr (textOf t) t) acc)))))

fn vectorOf toks: (List String) -> (List String)
  (if (= (optionOr (listHead toks) "") "[") (untilClose (listDrop toks 1) (list)) (list))

fn readCase line: String -> (Result Case String)
  (mt (let [(b (stringToBytes line))] (tokens line b 0 (bytesLength b) (list)))
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
          (mt acc
            ((err e) (err e))
            ((ok cs) (if (stringStartsWith? (stringTrim line) "(:case ")
                       (mt (readCase (stringTrim line)) ((err e) (err e)) ((ok c) (ok (listAppend cs (list c)))))
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

fn cliEnv root: String host: String errFile: String overrides: (List String) -> (List String)
  (listAppend (filter (fn [(row String)] -> Bool (not (listContains? (map envName overrides) (envName row))))
    (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp" (str "ASL_ROOT=" root) (str "ASL_CLI_ROOT=" root) (str "ASL_CLI_SCRIPT_DIR=" root "/bin")
        (str "ASL_CLI_ARGV0=" root "/bin/asl") (str "ASL_CLI_HOST_BIN=" host) (str "ASL_HOST=" host) (str "NATIVE_CLI_ERR=" errFile)))
    overrides)

fn expand s: String root: String sweep: String -> String
  (stringReplace (stringReplace s "$SWEEP" sweep) "$ROOT" root)

fn caseJob program: (List String) c: Case root: String host: String errFile: String sweep: String -> run/Job
  (run/job (listAppend (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$NATIVE_CLI_ERR\"") (listAppend program (map (fn [(a String)] -> String (expand a root sweep)) c.argv)))
           root (cliEnv root host errFile (map (fn [(e String)] -> String (expand e root sweep)) c.env)))

fn ! replay! c: Case binary: String root: String errFile: String sweep: String -> (List String)
  (let [(_ (fileWrite errFile ""))
        (d (run/runOneLimited (caseJob (list binary) c root "/nonexistent/asl-host" errFile sweep) (run/limits 900 32)))
        (errText (resultOr (fileRead errFile) ""))
        (out (normalize d.out root sweep))
        (errNorm (normalize errText root sweep))]
    (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
      (list (if (= d.verdict "exit") "" (str "verdict " d.verdict))
            (if (= out c.stdout) "" (str "stdout native " (asnQuote out) " host " (asnQuote c.stdout)))
            (if (= errNorm c.stderr) "" (str "stderr native " (asnQuote errNorm) " host " (asnQuote c.stderr)))
            (if (= d.exit c.exit) "" (str "exit native " (stringFromInt64 d.exit) " host " (stringFromInt64 c.exit))))))

fn ! git! dir: String args: (List String) -> (Result Unit String)
  (let [(d (run/runOneLimited (run/job (cons "git" args) dir (run/childEnv (list "GIT_CONFIG_NOSYSTEM=1"))) (run/limits 60 8)))]
    (if (and (= d.verdict "exit") (= d.exit 0)) (ok ()) (err (str "git " (stringJoin args " ") ": " d.out))))

fn ! copyFixture! root: String dir: String name: String -> (Result Unit String)
  (mt (fileRead (str root "/asl/packages/asl-cli/tests/fixtures/sweep/" name))
    ((err e) (err (str "cannot read fixture " name)))
    ((ok text) (mt (fileWrite (str dir "/tests/" name) text) ((err e) (err (str "cannot write " name))) ((ok _) (ok ())))))

fn ! prepareSweep! root: String -> (Result String String)
  (let [(dir (str root "/.asl/cache/nativeCliSweep/" (stringFromInt64 (procSelf))))]
    (mt (dirCreate (str dir "/tests"))
      ((err e) (err (str "cannot create " dir)))
      ((ok _)
        (let [(steps (list (copyFixture! root dir "passTest.asl") (copyFixture! root dir "failTest.asl") (copyFixture! root dir "zeroTest.asl")
                           (git! dir (list "init" "-q")) (git! dir (list "add" "-A"))
                           (git! dir (list "-c" "user.name=nativeCliTest" "-c" "user.email=nativeCliTest@localhost" "commit" "-q" "-m" "sweep fixture"))))]
          (mt (listHead (filter err? steps))
            ((some bad) (mt bad ((err e) (err e)) ((ok _) (err "unreachable"))))
            ((none) (ok dir)))))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cases (mt (fileRead (str root "/asl/packages/asl-cli/tests/fixtures/argv.asn")) ((err _) (err "argv.asn unreadable: run from the workspace root")) ((ok text) (readCases text))))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)).binary)
        (errFile (str "/tmp/aslNativeCli" (stringFromInt64 (procSelf)) ".err"))
        (sweep (prepareSweep! root))
        (sweepDir (resultOr sweep "/nonexistent/sweep"))
        (found (mt (if (ok? sweep) built (none))
                 ((none) (list))
                 ((some bin) (map (fn [(c Case)] -> (Pair String (List String)) (pair c.id (replay! c bin root errFile sweepDir))) (resultOr cases (list))))))
        (problems (fold (fn [(acc (List String)) (p (Pair String (List String)))] -> (List String) (if (listEmpty? (pairSecond p)) acc (listAppend acc (list (str "case " (pairFirst p) ": " (stringJoin (pairSecond p) "; ")))))) (list) found))
        (removed (if (fileExists? errFile) (pathRemove errFile) (ok ())))
        (sweepGone (if (ok? sweep) (pathRemove sweepDir) (ok ())))]
    (do
      (assert (ok? cases) (mt cases ((err e) e) ((ok _) "cases read")))
      (assert (some? built) "asl/packages/asl-cli/src/native.asl builds natively")
      (assert (ok? sweep) (mt sweep ((err e) (str "sweep workspace: " e)) ((ok _) "sweep workspace")))
      (assert (> (listLength found) 0) "at least one case replayed")
      (assert (= (listLength found) (listLength (resultOr cases (list)))) "every case replayed")
      (assert (listEmpty? problems) (str "native equals asl-host on every case; " (stringJoin problems " | ")))
      (assert (and (ok? removed) (and (ok? sweepGone) (not (fileExists? sweepDir)))) "stderr capture file and sweep workspace removed")
      true))
