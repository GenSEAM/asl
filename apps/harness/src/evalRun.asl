(module aslHarness/evalRun
  :x [Driver main envSet selectedCase? ledgerHeader relativeTo stripTrailingNewlines]
  :i [(aslHarness/eval :a ev) (asl-forms/gate :a gate) (asl-gateway/localTime :a lt) (asl-cli/system :a sys)])

(schema Driver
  (:f root String)
  (:f tmp String)
  (:f ledger String)
  (:f model String)
  (:f profile String)
  (:f today String)
  (:f toolchain String)
  (:f engineDir String)
  (:f env (List String))
  (:f timeoutMs Int64))

fn envOr! name: String fallback: String -> String
  (let [(v (optionOr (envGet name) ""))]
    (if (stringEmpty? v) fallback v))

fn envName entry: String -> String
  (mt (stringIndexOf entry "=") ((some i) (optionOr (stringSlice entry 0 i) entry)) ((none) entry))

fn envSet env: (List String) name: String value: String -> (List String)
  (listAppend (filter (fn [(e String)] -> Bool (!= (envName e) name)) env) (list (str name "=" value)))

fn stripTrailingNewlines s: String -> String
  (if (stringEndsWith? s "\n") (stripTrailingNewlines (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

fn relativeTo root: String path: String -> String
  (if (stringStartsWith? path (str root "/")) (optionOr (stringSlice path (+ (stringLength root) 1) (stringLength path)) path) path)

fn selectedCase? wanted: String id: String -> Bool
  (or (stringEmpty? wanted) (listContains? (stringSplit (stringReplace wanted "\t" " ") " ") id))

fn ledgerHeader -> String
  ";; tests/agentEval/ledger.asn\n;; Agent evaluation run ledger\n;; Format: (:evalRun :date :model :case :recall :precision :turns :wallSec :queueWaitSec :status)\n"

fn ! run! d: Driver argv: (List String) cwd: (Option String) -> gate/RunOut
  (gate/runArgv! argv cwd (some d.env) 600000 5000)

fn failText r: gate/RunOut -> String
  (stringTrim (str r.failure " " r.errText " " r.out))

fn ! must! d: Driver argv: (List String) cwd: (Option String) -> (Result String String)
  (let [(r (run! d argv cwd))]
    (if (= r.code 0)
      (ok r.out)
      (err (str (stringJoin argv " ") " exited " (stringFromInt64 r.code) ": " (failText r)))))

fn ! mktempDir! d: Driver template: String -> (Result String String)
  (mt (must! d (list "mktemp" "-d" template) (none))
    ((err e) (err e))
    ((ok out) (ok (stripTrailingNewlines out))))

fn ! ioStep r: (Result Unit String) what: String -> (Result Unit String)
  (mt r ((ok _) (ok ())) ((err e) (err (str what ": " e))))

fn ! linkAll! from: String into: String names: (List String) -> (Result Unit String)
  (mt (listHead names)
    ((none) (ok ()))
    ((some n)
      (mt (ioStep (pathSymlink (str from "/" n) (str into "/" n)) (str "ln -s " from "/" n))
        ((err e) (err e))
        ((ok _) (linkAll! from into (optionOr (listTail names) (list)))))))

fn visible names: (List String) -> (List String)
  (filter (fn [(n String)] -> Bool (not (stringStartsWith? n "."))) names)

fn ! packages! d: Driver names: (List String) -> (Result Unit String)
  (mt (listHead names)
    ((none) (ok ()))
    ((some n)
      (let [(src (str d.root "/asl/packages/" n))
            (dst (str d.toolchain "/asl/packages/"))
            (step (if (or (= n "asl-engine") (= n "asl-json"))
                    (mt (must! d (list "cp" "-R" src dst) (none)) ((err e) (err e)) ((ok _) (ok ())))
                    (ioStep (pathSymlink src (str dst n)) (str "ln -s " src))))]
        (mt step ((err e) (err e)) ((ok _) (packages! d (optionOr (listTail names) (list))))))))

fn ! freeze! d: Driver -> (Result Unit String)
  (let [(root d.root)
        (tc d.toolchain)
        (aslTop (filter (fn [(n String)] -> Bool (!= n "packages")) (visible (resultOr (dirList (str root "/asl")) (list)))))
        (pkgs (visible (resultOr (dirList (str root "/asl/packages")) (list))))]
    (mt (ioStep (dirCreate (str tc "/bin")) "mkdir bin")
      ((err e) (err e))
      ((ok _)
        (mt (must! d (list "cp" "-R" (str root "/scripts") (str tc "/scripts")) (none))
          ((err e) (err e))
          ((ok _)
            (mt (must! d (list "cp" (str root "/bin/asl") (str tc "/bin/")) (none))
              ((err e) (err e))
              ((ok _)
                (mt (ioStep (pathSymlink (str root "/.asl.config.asn") (str tc "/.asl.config.asn")) "ln -s .asl.config.asn")
                  ((err e) (err e))
                  ((ok _)
                    (mt (ioStep (dirCreate (str tc "/asl/packages")) "mkdir asl/packages")
                      ((err e) (err e))
                      ((ok _)
                        (mt (linkAll! (str root "/asl") (str tc "/asl") aslTop)
                          ((err e) (err e))
                          ((ok _)
                            (mt (packages! d pkgs)
                              ((err e) (err e))
                              ((ok _)
                                (if (sys/isFile? (str root "/bin/asl-core"))
                                  (ioStep (pathSymlink (str root "/bin/asl-core") (str tc "/bin/asl-core")) "ln -s asl-core")
                                  (ok ())))))))))))))))))

fn ! engine! d: Driver action: (List String) -> gate/RunOut
  (run! d (cons (str d.toolchain "/bin/asl") (cons "engine" action)) (none))

fn ! stopEngine! d: Driver -> Unit
  (let [(stopped (engine! d (list "stop")))
        (pidFile (str d.engineDir "/e.pid"))]
    (do
      (if (!= stopped.code 0) (eprintln (str "evalRun: engine stop exited " (stringFromInt64 stopped.code) ": " (failText stopped))) ())
      (mt (fileReadString pidFile)
        ((err _) ())
        ((ok text)
          (mt (stringToInt64 (stringTrim text))
            ((none) (eprintln (str "evalRun: " pidFile " holds no pid")))
            ((some pid) (mt (procKill pid "SIGTERM") ((ok _) ()) ((err _) ()))))))))

fn ! cleanup! d: Driver -> Unit
  (do
    (stopEngine! d)
    (mt (pathRemove d.toolchain) ((ok _) ()) ((err e) (eprintln (str "evalRun: cannot remove " d.toolchain ": " e))))
    (mt (pathRemove d.engineDir) ((ok _) ()) ((err e) (eprintln (str "evalRun: cannot remove " d.engineDir ": " e)))))

fn ! ensureLedger! path: String -> (Result Unit String)
  (if (sys/isFile? path) (ok ()) (ioStep (fileWrite path (ledgerHeader)) (str "cannot create ledger " path)))

fn ! copyJournals! from: String into: String -> Unit
  (let [(names (filter (fn [(n String)] -> Bool (and (stringEndsWith? n ".journal") (sys/isFile? (str from "/" n))))
                       (resultOr (dirList from) (list))))]
    (fold (fn [(u Unit) (n String)] -> Unit
            (mt (fileReadString (str from "/" n))
              ((err e) (eprintln (str "evalRun: cannot read journal " from "/" n ": " e)))
              ((ok text) (mt (fileWrite (str into "/" n) text)
                         ((ok _) ())
                         ((err e) (eprintln (str "evalRun: cannot keep journal " n ": " e)))))))
          () names))

fn ! caseRepo! d: Driver caseDir: String id: String -> (Result (Pair String String) String)
  (mt (mktempDir! d (str d.tmp "/asl_eval_" id "_XXXXXX"))
    ((err e) (err e))
    ((ok repo)
      (let [(hiddenSrc (str caseDir "/hidden"))
            (laid (mt (must! d (list "cp" "-R" (str caseDir "/.") (str repo "/")) (none))
                    ((err e) (err e))
                    ((ok _)
                      (mt (if (sys/isFile? (str repo "/truth.asn")) (ioStep (pathRemove (str repo "/truth.asn")) "rm truth.asn") (ok ()))
                        ((err e) (err e))
                        ((ok _) (if (fileExists? (str repo "/hidden")) (ioStep (pathRemove (str repo "/hidden")) "rm hidden") (ok ())))))))
            (hidden (mt laid
                      ((err e) (err e))
                      ((ok _)
                        (if (sys/isDir? hiddenSrc)
                          (mt (mktempDir! d (str d.tmp "/asl_eval_hidden_XXXXXX"))
                            ((err e) (err e))
                            ((ok h) (mt (must! d (list "cp" "-R" (str hiddenSrc "/.") (str h "/")) (none))
                                      ((err e) (err e))
                                      ((ok _) (ok h)))))
                          (ok "")))))]
        (mt hidden
          ((err e) (do (pathRemove repo) (err e)))
          ((ok h) (ok (pair repo h)))))))

fn ! gitInit! d: Driver repo: String -> (Result Unit String)
  (let [(steps (list (list "init" "-q") (list "config" "user.email" "eval@asl.local") (list "config" "user.name" "Agent Eval")
                     (list "add" ".") (list "commit" "-q" "-m" "initial fixture state")))]
    (fold (fn [(acc (Result Unit String)) (args (List String))] -> (Result Unit String)
            (mt acc
              ((err e) (err e))
              ((ok _) (mt (must! d (cons "git" (cons "-C" (cons repo args))) (none)) ((err e) (err e)) ((ok _) (ok ()))))))
          (ok ()) steps))

fn ! runCase! d: Driver journals: String caseDir: String id: String -> (Result ev/EvalRun String)
  (mt (fileReadString (str caseDir "/task.asn"))
    ((err e) (err (str "cannot read " caseDir "/task.asn: " e)))
    ((ok task)
      (mt (fileReadString (str caseDir "/truth.asn"))
        ((err e) (err (str "cannot read " caseDir "/truth.asn: " e)))
        ((ok truth)
          (mt (caseRepo! d caseDir id)
            ((err e) (err e))
            ((ok laid)
              (let [(repo (pairFirst laid))
                    (hidden (pairSecond laid))
                    (dc (with d :env (envSet (envSet d.env "ASL_EVAL_HIDDEN" hidden) "ASL_EVAL_HIDDEN_VARS" "ASL_EVAL_HIDDEN")))
                    (result
                      (mt (gitInit! dc repo)
                        ((err e) (err e))
                        ((ok _)
                          (let [(invocation (ev/buildInvocation task d.model d.profile))
                                (t0 (monotonicNs))
                                (agent (gate/runArgv! (list (str d.toolchain "/bin/asl") invocation) (some repo) (some dc.env) d.timeoutMs 10000))
                                (t1 (monotonicNs))
                                (wall (ev/round2 (/ (int64ToFloat64 (- t1 t0)) 1000000000.0)))
                                (receipt (stripTrailingNewlines (str agent.out agent.errText)))
                                (keep (str journals "/" id))]
                            (mt (ev/scoreCase receipt truth id d.model wall d.today)
                             ((err e) (err e))
                             ((ok scored)
                            (do
                              (if agent.timedOut (eprintln (str "evalRun: case " id " passed ASL_EVAL_TIMEOUT_SEC and was stopped")) ())
                              (if (stringEmpty? agent.failure) () (eprintln (str "evalRun: case " id " agent: " agent.failure)))
                              (mt (fileAppend d.ledger (str scored.form "\n"))
                                ((err e) (err (str "cannot append to " d.ledger ": " e)))
                                ((ok _)
                                  (do
                                    (println scored.form)
                                    (mt (dirCreate keep)
                                      ((err e) (eprintln (str "evalRun: cannot keep journals in " keep ": " e)))
                                      ((ok _)
                                        (do (copyJournals! (str repo "/.asl/run/agentLoop") keep)
                                            (mt (fileWrite (str keep "/receipt.asn") (str receipt "\n"))
                                              ((ok _) ())
                                              ((err e) (eprintln (str "evalRun: cannot keep receipt of " id ": " e)))))))
                                    (ok scored)))))))))))]
                (do
                  (mt (pathRemove repo) ((ok _) ()) ((err e) (eprintln (str "evalRun: cannot remove " repo ": " e))))
                  (if (stringEmpty? hidden) () (mt (pathRemove hidden) ((ok _) ()) ((err e) (eprintln (str "evalRun: cannot remove " hidden ": " e)))))
                  result))))))))

fn ! runCases! d: Driver journals: String ids: (List String) acc: (List ev/EvalRun) -> (Result (List ev/EvalRun) String)
  (mt (listHead ids)
    ((none) (ok acc))
    ((some id)
      (let [(caseDir (str d.root "/tests/agentEval/cases/" id))
            (rest (optionOr (listTail ids) (list)))]
        (if (and (sys/isFile? (str caseDir "/task.asn")) (sys/isFile? (str caseDir "/truth.asn")))
          (mt (runCase! d journals caseDir id)
            ((err e) (err e))
            ((ok r) (runCases! d journals rest (listAppend acc (list r)))))
          (runCases! d journals rest acc)))))

fn ! caseIds! root: String -> (Result (List String) String)
  (let [(dir (str root "/tests/agentEval/cases"))]
    (mt (dirList dir)
      ((err e) (err (str "cannot list " dir ": " e)))
      ((ok names)
        (ok (listSort (filter (fn [(n String)] -> Bool (sys/isDir? (str dir "/" n))) names))))))

fn stamp local: String -> String
  (stringReplace (stringReplace (stringReplace local "-" "") " " "-") ":" "")

fn ! localNow! -> String
  (mt (lt/zoneLoad! (envGet "TZ"))
    ((ok z) (lt/formatLocal z (/ (nowNs) 1000000000) true))
    ((err _) (lt/formatLocal (lt/utcZone) (/ (nowNs) 1000000000) true)))

fn ! evaluate! d: Driver -> (Result Int64 String)
  (let [(start (engine! d (list "start" "--scope" "workspace")))]
    (if (!= start.code 0)
      (do (if (stringEmpty? start.errText) () (eprintln (stripTrailingNewlines start.errText)))
          (eprintln (str "ERR_ENGINE_START: the frozen engine did not start at " d.engineDir "/e.sock"))
          (ok 1))
      (let [(ping (engine! d (list "ping")))]
        (if (not (stringStartsWith? ping.out "(:pong :status :ok"))
          (do (eprintln (str "ERR_ENGINE_PING: the frozen engine at " d.engineDir "/e.sock does not answer :ping; a run would fork bin/asl per form"))
              (ok 1))
          (let [(runDir (str d.root "/.asl/run/agentEval"))]
            (mt (ioStep (dirCreate runDir) (str "mkdir " runDir))
              ((err e) (err e))
              ((ok _)
                (mt (mktempDir! d (str runDir "/" (stamp (localNow!)) "-" d.model "-XXXXXX"))
                  ((err e) (err e))
                  ((ok journals)
                    (do
                      (println (str "--- Starting AG3 agentEval (model: " d.model ") journals: " (relativeTo d.root journals) " ---"))
                      (mt (caseIds! d.root)
                        ((err e) (err e))
                        ((ok all)
                          (mt (runCases! d journals (filter (fn [(id String)] -> Bool (selectedCase? (envOr! "ASL_EVAL_CASES" "") id)) all) (list))
                            ((err e) (err e))
                            ((ok runs)
                              (if (listEmpty? runs)
                                (ok 0)
                                (let [(summary (ev/summarizeEvalRuns runs))]
                                  (do (println (ev/formatEvalSummary summary))
                                      (ok (if (ev/evalSummaryPassed? summary runs) 0 1)))))))))))))))))))

fn ! drive! root: String -> (Result Int64 String)
  (let [(tmp (envOr! "TMPDIR" "/tmp"))
        (profile (envOr! "ASL_PROFILE" ""))
        (model (if (stringEmpty? profile) (envOr! "ASL_MODEL" "gemini-3.8-flash") (str "profile-" profile)))
        (ledger (envOr! "ASL_EVAL_LEDGER" (str root "/tests/agentEval/ledger.asn")))
        (timeoutSec (optionOr (stringToInt64 (envOr! "ASL_EVAL_TIMEOUT_SEC" "3600")) 3600))
        (base (Driver :root root :tmp tmp :ledger ledger :model model :profile profile
                      :today (optionOr (stringSlice (localNow!) 0 10) "") :toolchain "" :engineDir ""
                      :env (envSet (envSet (envList) "ASL_SANDBOX_KEEP_HOME" "1") "ASL_ALLOW_AGY" "1") :timeoutMs (* timeoutSec 1000)))]
    (mt (ensureLedger! ledger)
      ((err e) (err e))
      ((ok _)
        (mt (mktempDir! base (str tmp "/asl_eval_toolchain_XXXXXX"))
          ((err e) (err e))
          ((ok toolchain)
            (mt (mktempDir! base (str (envOr! "ASL_EVAL_ENGINE_TMP" "/tmp") "/aslE.XXXXXX"))
              ((err e) (do (pathRemove toolchain) (err e)))
              ((ok engineDir)
                (let [(d (Driver :root root :tmp tmp :ledger ledger :model model :profile profile :today base.today
                                 :toolchain toolchain :engineDir engineDir :timeoutMs base.timeoutMs
                                 :env (envSet (envSet (envSet base.env "ASL_ENGINE_SOCKET" (str engineDir "/e.sock"))
                                                      "ASL_ENGINE_PID_FILE" (str engineDir "/e.pid"))
                                              "ASL_ENGINE_UPDATE_SEC" "0")))
                      (result (mt (freeze! d) ((err e) (err (str "cannot freeze the toolchain: " e))) ((ok _) (evaluate! d))))]
                  (do (cleanup! d) result)))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (if (!= (optionOr (envGet "ASL_LLM_GATES") "0") "1")
    (do (println "skip: agentEval requires ASL_LLM_GATES=1") (ok 0))
    (let [(root (envOr! "ASL_EVAL_ROOT" (resultOr (realPath ".") ".")))
          (sandbox (str root "/tests/acceptance/agentLoop/sandbox.sh"))]
      (if (and (!= (optionOr (envGet "ASL_SANDBOX_ACTIVE") "0") "1") (sys/isFile? sandbox))
        (ok (sys/execv! (listAppend (list sandbox (envOr! "ASL_HOST" (str root "/asl/host/out/asl-host")) "run" (str root "/harness/src/evalRun.asl")) args)
                                  (list "ASL_SANDBOX_KEEP_HOME=1" "ASL_ALLOW_AGY=1")))
        (drive! root))))
