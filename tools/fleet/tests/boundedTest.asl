(module asl/tools/fleet/tests/boundedTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl/tools/fleet/bounded :a bd)])

; (:m :ref WATCHDOG-GROUP-KILL :do "bounded.asl through its real command line, each case one child of this test run through fleet/run.asl with a 90 s limit: a command past SECS is killed with its whole tree (a sleeper child, a sleeper grandchild in a nested sh, and a nested bin/asl run with its own sleeper) with exit 124 and a timeout note, a command that ends keeps its exit code and output whole, a bad line is refused with exit 2 before any run")
; (:m :ref BOUNDED-RED-SLEEPER :do "the commands write the pids of their sleepers and wrappers into pid files of this run; survivors are judged and cleaned by those pids, never by command text: after the judgement every recorded pid still alive is killed, but only when its command still holds what the recorded process ran (a pid that was reused is left alone), so a red run leaves none and a foreign process, even a sleep with the same number, is never touched; a decoy sleep with the same number, started by this test outside every bounded run, must survive")

fn ! psRow! pid: Int64 -> String
  (stringTrim (fr/runOneLimited (fr/job (list "ps" "-p" (stringFromInt64 pid) "-o" "stat=,command=") "/" (fr/childEnv (list))) (fr/limits 10 8)).out)

fn ! aliveOwn? pid: Int64 -> Bool
  (let [(row (psRow! pid))]
    (and (> pid 1) (and (not (stringEmpty? row)) (not (stringStartsWith? row "Z")))))

; (:m :do "SIGKILL pid only while it is alive and its command holds expect; the count of pids killed")
fn ! killOwn! pid: Int64 expect: String -> Int64
  (if (and (aliveOwn? pid) (stringContains? (psRow! pid) expect))
    (match (procKill pid "SIGKILL") ((ok _) 1) ((err _) 0))
    0)

fn ! pidIn! path: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString path) ""))) 0)

fn ! startDecoy! secs: String -> Int64
  (match (fr/spawnSep (list "sleep" secs) "." (fr/childEnv (list)))
    ((ok r) r.pid)
    ((err _) -1))

fn ! child! root: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "./bin/asl" "run" "asl/tools/fleet/bounded.asl") argv) root (fr/childEnv (list))) (fr/limits 90 64))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (m (mod (procSelf) 90))
        (sa (stringFromInt64 (+ 100 m)))
        (sb (stringFromInt64 (+ 200 m)))
        (sc (stringFromInt64 (+ 300 m)))
        (dir (str (optionOr (envGet "TMPDIR") "/tmp") "/boundedTest-" (stringFromInt64 (procSelf))))
        (_ (dirCreate dir))
        (decoy (startDecoy! sa))
        (tree (child! root (list "3" "--" "sh" "-c" (str "echo $$ > " dir "/w1; sleep " sa " & echo $! > " dir "/a; sh -c 'echo $$ > " dir "/w2; sleep " sb " & echo $! > " dir "/b; wait' & wait"))))
        (pa (pidIn! (str dir "/a")))
        (pb (pidIn! (str dir "/b")))
        (w1 (pidIn! (str dir "/w1")))
        (w2 (pidIn! (str dir "/w2")))
        (aliveA (aliveOwn? pa))
        (aliveB (aliveOwn? pb))
        (nested (child! root (list "3" "--" "sh" "-c" (str "echo $$ > " dir "/w3; exec ./bin/asl run asl/tools/fleet/bounded.asl 120 -- sh -c 'sleep " sc " & echo $! > " dir "/c; wait'"))))
        (pc (pidIn! (str dir "/c")))
        (w3 (pidIn! (str dir "/w3")))
        (aliveC (aliveOwn? pc))
        (okRun (child! root (list "20" "--" "sh" "-c" "echo whole; echo err >&2; exit 7")))
        (noCmd (child! root (list "3" "--")))
        (noSep (child! root (list "3" "sleep" "1")))
        (zero (child! root (list "0" "--" "true")))
        (killedOwn (fold (fn [(n Int64) (x (Pair Int64 String))] (+ n (killOwn! (pairFirst x) (pairSecond x)))) 0
                    (list (pair pa (str "sleep " sa)) (pair pb (str "sleep " sb)) (pair pc (str "sleep " sc)) (pair w1 dir) (pair w2 dir) (pair w3 dir))))
        (decoyAlive (aliveOwn? decoy))
        (decoyKilled (killOwn! decoy (str "sleep " sa)))
        (_ (map (fn [(f String)] (pathRemove (str dir "/" f))) (list "a" "b" "c" "w1" "w2" "w3")))
        (_ (pathRemove dir))]
    (do (assert (and (> pa 1) (and (> pb 1) (and (> pc 1) (and (> w1 1) (and (> w2 1) (> w3 1)))))) "the commands recorded the pids of their sleepers and wrappers")
        (assert (> decoy 1) "the decoy sleep with the same number as a test sleeper started outside every bounded run")
        (assert (= tree.exit 124) (str "a tree past SECS ends with exit 124: " (stringFromInt64 tree.exit)))
        (assert (stringContains? tree.out ":verdict :timeout") (str "the timeout note is printed: " tree.out))
        (assert (< tree.ms 60000) (str "the 120 s body is killed at SECS 3, long before its end: " (stringFromInt64 tree.ms)))
        (assert (not aliveA) "the direct child's sleeper does not survive")
        (assert (not aliveB) "the sleeper of the nested sh (a grandchild) does not survive")
        (assert (= nested.exit 124) (str "a nested bin/asl run past SECS ends with exit 124: " (stringFromInt64 nested.exit)))
        (assert (not aliveC) "the nested bin/asl run's own sleeper does not survive")
        (assert (and (= okRun.exit 7) (and (stringContains? okRun.out "whole") (stringContains? okRun.out "err"))) (str "a command that ends keeps its exit code and output: " okRun.out))
        (assert (not (stringContains? okRun.out ":verdict")) "an ended command carries no kill note")
        (assert (and (= noCmd.exit 2) (stringContains? noCmd.out "the command is empty")) (str "an empty command is refused: " noCmd.out))
        (assert (and (= noSep.exit 2) (stringContains? noSep.out "the command must follow --")) (str "a missing separator is refused: " noSep.out))
        (assert (and (= zero.exit 2) (stringContains? zero.out "SECS must be a positive integer")) (str "SECS 0 is refused: " zero.out))
        (assert (= (bd/parseArgs (list "5" "--max-desc" "9" "--" "a" "b")).maxDesc 9) "parseArgs reads --max-desc")
        (assert (= (bd/parseArgs (list "5" "--" "a" "b")).maxDesc 64) "parseArgs defaults maxDesc to 64")
        (assert (= killedOwn 0) (str "a green run leaves none of its recorded pids to kill: " (stringFromInt64 killedOwn)))
        (assert decoyAlive "a foreign sleep with a matching number survives the whole run")
        (assert (= decoyKilled 1) "the decoy is the test's own and is killed at the end")
        true))
