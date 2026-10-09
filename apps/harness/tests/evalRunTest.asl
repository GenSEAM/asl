(module aslHarness/tests/evalRunTest
  :x [runTests stubAgent workspace! driverEnv scenario! mask quote]
  :i [(asl-forms/gate :a gate)])

fn stubAgent -> String
  (str "#!/bin/sh\n"
       "if [ \"$1\" = engine ]; then\n"
       "  case \"$2\" in\n"
       "    start) sleep 300 </dev/null >/dev/null 2>&1 & echo $! > \"$ASL_ENGINE_PID_FILE\"; echo $! >> \"$STUB_PID_LOG\" ;;\n"
       "    ping) echo '(:pong :status :ok :stub true)' ;;\n"
       "  esac\n"
       "  exit 0\n"
       "fi\n"
       "tc=$(cd \"$(dirname \"$0\")/..\" && pwd)\n"
       "clean=$(git status --porcelain | wc -l | tr -d ' ')\n"
       "mkdir -p .asl/run/agentLoop\n"
       "{\n"
       "  printf 'invocation %s\\n' \"$1\"\n"
       "  printf 'truthInRepo %s\\n' \"$([ -e truth.asn ] && echo yes || echo no)\"\n"
       "  printf 'hiddenInRepo %s\\n' \"$([ -e hidden ] && echo yes || echo no)\"\n"
       "  printf 'hiddenVar %s\\n' \"$([ -n \"$ASL_EVAL_HIDDEN\" ] && ls \"$ASL_EVAL_HIDDEN\" | tr '\\n' ' ')\"\n"
       "  printf 'hiddenVars %s\\n' \"$ASL_EVAL_HIDDEN_VARS\"\n"
       "  printf 'commits %s %s\\n' \"$(git rev-list --count HEAD)\" \"$(git log -1 --format='%an <%ae> %s')\"\n"
       "  printf 'untracked %s\\n' \"$clean\"\n"
       "  printf 'engine %s %s %s\\n' \"${ASL_ENGINE_SOCKET##*/}\" \"${ASL_ENGINE_PID_FILE##*/}\" \"$ASL_ENGINE_UPDATE_SEC\"\n"
       "  printf 'live %s %s\\n' \"$ASL_SANDBOX_KEEP_HOME\" \"$ASL_ALLOW_AGY\"\n"
       "  for p in asl/packages/asl-engine asl/packages/asl-json asl/packages/asl-other asl/host scripts .asl.config.asn bin/asl-core; do\n"
       "    if [ -L \"$tc/$p\" ]; then echo \"$p linked\"; elif [ -e \"$tc/$p\" ]; then echo \"$p copied\"; else echo \"$p absent\"; fi\n"
       "  done\n"
       "} > .asl/run/agentLoop/stub.journal\n"
       "echo 'not a journal' > .asl/run/agentLoop/notes.txt\n"
       "cat reply.asn\n"
       "echo 'stub stderr after the receipt' >&2\n")

fn ! step r: (Result Unit String) what: String -> (Result Unit String)
  (mt r ((ok _) (ok ())) ((err e) (err (str what ": " e))))

fn ! writeAll! files: (List (Pair String String)) -> (Result Unit String)
  (fold (fn [(acc (Result Unit String)) (f (Pair String String))] -> (Result Unit String)
          (mt acc ((err e) (err e)) ((ok _) (step (fileWrite (pairFirst f) (pairSecond f)) (pairFirst f)))))
        (ok ()) files)

fn ! workspace! top: String -> (Result String String)
  (let [(ws (str top "/ws"))
        (dirs (list (str ws "/bin") (str ws "/scripts") (str ws "/asl/host") (str ws "/asl/packages/asl-engine/src")
                    (str ws "/asl/packages/asl-json") (str ws "/asl/packages/asl-other") (str ws "/tests/agentEval") (str top "/tmp") (str top "/eng")))
        (made (fold (fn [(acc (Result Unit String)) (d String)] -> (Result Unit String)
                      (mt acc ((err e) (err e)) ((ok _) (step (dirCreate d) d))))
                    (ok ()) dirs))
        (copied (mt made
                  ((err e) (err e))
                  ((ok _)
                    (let [(r (gate/runArgv! (list "cp" "-R" "harness/tests/fixtures/evalRun/cases" (str ws "/tests/agentEval/cases")) (none) (none) 60000 0))]
                      (if (= r.code 0) (ok ()) (err (str "cp cases: " r.errText)))))))]
    (mt copied
      ((err e) (err e))
      ((ok _)
        (mt (writeAll! (list (pair (str ws "/bin/asl") (stubAgent))
                             (pair (str ws "/scripts/keep.txt") "frozen with the toolchain\n")
                             (pair (str ws "/.asl.config.asn") "(:config :stub true)\n")
                             (pair (str ws "/asl/host/README") "linked\n")
                             (pair (str ws "/asl/packages/asl-engine/src/engine.txt") "copied\n")
                             (pair (str ws "/asl/packages/asl-json/README") "copied\n")
                             (pair (str ws "/asl/packages/asl-other/README") "linked\n")))
          ((err e) (err e))
          ((ok _) (mt (fileChmod (str ws "/bin/asl") 493) ((err e) (err (str "chmod stub: " e))) ((ok _) (ok ws))))))))

fn envName entry: String -> String
  (mt (stringIndexOf entry "=") ((some i) (optionOr (stringSlice entry 0 i) entry)) ((none) entry))

fn ! driverEnv top: String ws: String cases: String -> (List String)
  (let [(dropped (list "ASL_PROFILE" "ASL_EVAL_CASES" "ASL_EVAL_LEDGER" "ASL_SANDBOX_ACTIVE" "ASL_ENGINE_SOCKET" "ASL_ENGINE_PID_FILE"
                       "ASL_EVAL_HIDDEN" "ASL_EVAL_HIDDEN_VARS" "ASL_SANDBOX_KEEP_HOME" "ASL_ALLOW_AGY" "ASL_ROOT" "ASL_MODEL" "ASL_EVAL_TIMEOUT_SEC"))
        (kept (filter (fn [(e String)] -> Bool (not (listContains? dropped (envName e)))) (envList)))
        (base (filter (fn [(e String)] -> Bool (not (listContains? (list "TMPDIR" "ASL_LLM_GATES" "ASL_EVAL_ROOT" "ASL_EVAL_ENGINE_TMP" "STUB_PID_LOG") (envName e)))) kept))]
    (listAppend base (listAppend (list (str "TMPDIR=" top "/tmp") (str "ASL_EVAL_ENGINE_TMP=" top "/eng") "ASL_LLM_GATES=1" "ASL_MODEL=stub-model"
                                       (str "ASL_EVAL_ROOT=" ws) (str "STUB_PID_LOG=" top "/pids"))
                                 (if (stringEmpty? cases) (list) (list (str "ASL_EVAL_CASES=" cases))))))

fn quote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn tokenEnd s: String i: Int64 n: Int64 -> Int64
  (if (>= i n) i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (or (= c " ") (or (= c ")") (= c "\n"))) i (tokenEnd s (+ i 1) n))))

fn digitStart? t: String -> Bool
  (stringContains? "0123456789" (optionOr (stringSlice t 0 1) "x"))

fn maskFrom s: String key: String from: Int64 hideHead: Int64 hideTail: Int64 -> String
  (mt (stringIndexOf (optionOr (stringSlice s from (stringLength s)) "") key)
    ((none) s)
    ((some rel)
      (let [(start (+ from rel (stringLength key)))
            (end (tokenEnd s start (stringLength s)))
            (token (optionOr (stringSlice s start end) ""))
            (masked (cond
                      ((not (digitStart? token)) token)
                      ((= (+ hideHead hideTail) 0) "#")
                      ((> (stringLength token) (+ hideHead hideTail))
                        (str "#" (optionOr (stringSlice token hideHead (- (stringLength token) hideTail)) "") "#"))
                      (else "#")))
            (next (str (optionOr (stringSlice s 0 start) "") masked (optionOr (stringSlice s end (stringLength s)) "")))]
        (maskFrom next key (+ start (stringLength masked)) hideHead hideTail))))

fn mask s: String -> String
  (maskFrom (maskFrom (maskFrom (maskFrom s ":date \"" 0 0 0) ":wallSec " 0 0 0) ":avgWallSec " 0 0 0) "journals: .asl/run/agentEval/" 0 15 6)

fn ! readOr path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err e) (str "<unreadable " e ">")))

fn ! listOr path: String -> (List String)
  (mt (dirList path) ((ok xs) (listSort xs)) ((err _) (list)))

fn ! journalRows! runDir: String -> String
  (fold (fn [(acc String) (id String)] -> String
          (fold (fn [(a String) (f String)] -> String
                  (str a "\n    (:file " (quote (str id "/" f)) " :text " (quote (mask (readOr (str runDir "/" id "/" f)))) ")"))
                acc (listOr (str runDir "/" id))))
        "" (listOr runDir))

fn ! scenario! top: String name: String argv: (List String) cases: String -> (Pair gate/RunOut String)
  (mt (workspace! top)
    ((err e) (pair (gate/RunOut :code -1 :out "" :errText e :timedOut false :failure e) ""))
    ((ok ws)
      (let [(r (gate/runArgv! argv (none) (some (driverEnv top ws cases)) 300000 2000))
            (runs (listOr (str ws "/.asl/run/agentEval")))
            (runDir (str ws "/.asl/run/agentEval/" (optionOr (listHead runs) "none")))
            (text (str "(:record :scenario " (quote name) " :exit " (stringFromInt64 r.code)
                       "\n  :stdout " (quote (mask r.out))
                       "\n  :ledger " (quote (mask (readOr (str ws "/tests/agentEval/ledger.asn"))))
                       "\n  :runDirs " (stringFromInt64 (listLength runs))
                       "\n  :journals (" (journalRows! runDir) "))\n"))]
        (pair r text))))

fn ! host -> String
  (let [(h (optionOr (envGet "ASL_HOST") ""))]
    (if (stringEmpty? h) (resultOr (realPath "asl/host/out/asl-host") "asl/host/out/asl-host") h))

fn ! evalRunArgv -> (List String)
  (list (host) "run" (resultOr (realPath "harness/src/evalRun.asl") "harness/src/evalRun.asl"))

fn ! freshTop! tag: String -> String
  (let [(r (gate/runArgv! (list "mktemp" "-d" (str "/tmp/aslEvalRun" tag ".XXXXXX")) (none) (none) 10000 0))]
    (stringTrim r.out))

fn ! alive? pidText: String -> Bool
  (mt (stringToInt64 (stringTrim pidText))
    ((none) false)
    ((some pid) (resultOr (procAlive? pid) true)))

fn ! fixtureBody -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringStartsWith? l ";;"))) (stringSplit (readOr "harness/tests/fixtures/evalRun/runShRecord.asn") "\n")) "\n")

fn ! runTests -> Bool
  (let [(topAll (freshTop! "All"))
        (all (scenario! topAll "all" (evalRunArgv) ""))
        (topPass (freshTop! "Pass"))
        (passOnly (scenario! topPass "passOnly" (evalRunArgv) "passCase"))
        (expected (fixtureBody))
        (got (str (pairSecond all) (pairSecond passOnly)))
        (failJournal (readOr (str topAll "/ws/.asl/run/agentEval/" (optionOr (listHead (listOr (str topAll "/ws/.asl/run/agentEval"))) "none") "/failCase/stub.journal")))
        (leftTmp (listLength (listOr (str topAll "/tmp"))))
        (leftEng (listLength (listOr (str topAll "/eng"))))
        (enginePids (stringSplit (stringTrim (readOr (str topAll "/pids"))) "\n"))
        (skip (gate/runArgv! (evalRunArgv) (none) (some (filter (fn [(e String)] -> Bool (!= (envName e) "ASL_LLM_GATES")) (driverEnv topPass (str topPass "/ws") ""))) 60000 0))
        (skipLedger (readOr (str topPass "/ws/tests/agentEval/ledger.asn")))]
    (do
      (if (= got expected) () (do (println "--- evalRun record") (print got) (println "--- run.sh record") (println expected)))
      (pathRemove topAll)
      (pathRemove topPass)
      (assert (stringContains? expected "(:record :scenario \"all\" :exit 1") "the run.sh fixture is present and records a failing run")
      (assert (= (pairFirst all).code 1) "a run with a failed case exits 1 as run.sh did")
      (assert (= (pairFirst passOnly).code 0) "ASL_EVAL_CASES=passCase runs only the passing case and exits 0")
      (assert (= got expected) "stdout, ledger and kept journals equal the run.sh record, timestamps masked")
      (assert (and (stringContains? failJournal "truthInRepo no") (and (stringContains? failJournal "hiddenInRepo no") (stringContains? failJournal "hiddenVar check.txt"))) "truth.asn and hidden/ stay out of the case repo; hidden/ is reachable as ASL_EVAL_HIDDEN")
      (assert (and (= leftTmp 0) (= leftEng 0)) "the frozen toolchain, case repos, hidden dirs and engine dir are removed")
      (assert (and (not (listEmpty? enginePids)) (not (listAny? alive? enginePids))) "the private engine started for the run is stopped")
      (assert (and (= skip.code 0) (and (= skip.out "skip: agentEval requires ASL_LLM_GATES=1\n") (stringContains? got (quote (mask skipLedger))))) "without ASL_LLM_GATES=1 the driver skips and exits 0")
      true))
