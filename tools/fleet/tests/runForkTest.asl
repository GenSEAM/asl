(module asl/tools/fleet/tests/runForkTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref LEON-POOL-SPAWNSAFETY :do "forkLimited! children: one returns its exit code, one spawns six sleeps past maxDesc 3 and is killed whole with a runaway verdict, one outlives timeoutMs and is killed with a timeout verdict, one is killed by its caller; no sleep 29 or sleep 28 survives")

fn ! logPath tag: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/runForkTest-" (stringFromInt64 (procSelf)) "-" tag ".log")

fn ! drive! f: fr/Forked -> fr/ForkEnd
  (let [(s (fr/forkAdvance! f))]
    (match s.end
      ((some e) e)
      ((none) (do (sleepMs 20) (drive! s.fork)))))

fn ! spawner! n: Int64 secs: String -> Int64
  (do (map (fn [(i Int64)] -> Bool (ok? (fr/spawnSep (list "sleep" secs) "/" (fr/childEnv (list))))) (range 0 n))
      (sleepMs 30000)
      0)

fn ! survivors! secs: String -> Bool
  (stringContains? (fr/runOneLimited (fr/job (list "ps" "-A" "-o" "command=") "/" (fr/childEnv (list))) (fr/limits 10 8)).out (str "sleep " secs))

fn ! endOf r: (Result fr/Forked String) -> fr/ForkEnd
  (match r
    ((ok f) (drive! f))
    ((err e) (fr/ForkEnd :exit -2 :verdict "forkFailed" :desc 0 :note e)))

fn ! runTests -> Bool
  (let [(plain (endOf (fr/forkLimited! (logPath "plain") (fr/limits 30 8) (fn [] -> Int64 7))))
        (t0 (monotonicNs))
        (runaway (endOf (fr/forkLimited! (logPath "desc") (fr/limits 60 3) (fn [] -> Int64 (spawner! 6 "29")))))
        (runawayMs (/ (- (monotonicNs) t0) 1000000))
        (descLeft (survivors! "29"))
        (late (endOf (fr/forkLimited! (logPath "time") (fr/limits 1 64) (fn [] -> Int64 (spawner! 1 "28")))))
        (timeLeft (survivors! "28"))
        (killed (match (fr/forkLimited! (logPath "kill") (fr/limits 60 64) (fn [] -> Int64 (spawner! 1 "27")))
                  ((ok f) (do (sleepMs 1500) (fr/forkKill! f "lane")))
                  ((err e) (fr/ForkEnd :exit -2 :verdict "forkFailed" :desc 0 :note e))))
        (killLeft (survivors! "27"))
        (badClass (fr/forkLimited! (logPath "class") (fr/heavy (fr/limits 30 8) "audit" "/nonexistent") (fn [] -> Int64 0)))
        (noTimeout (fr/forkLimited! (logPath "zero") (fr/limits 0 8) (fn [] -> Int64 0)))
        (noLog (endOf (fr/forkLimited! "/nonexistent-runForkTest-dir/child.log" (fr/limits 30 8) (fn [] -> Int64 7))))
        (cleaned (map (fn [(t String)] -> Bool (ok? (pathRemove (logPath t)))) (list "plain" "desc" "time" "kill")))]
    (do
      (assert (and (= plain.exit 7) (= plain.verdict "")) "a child that returns ends with its code and no verdict")
      (assert (= runaway.verdict "runaway") (str "a child spawning past maxDesc is killed with a runaway verdict: " runaway.note))
      (assert (> runaway.desc 3) "the verdict records the descendant count over maxDesc")
      (assert (stringContains? runaway.note ":maxDesc 3") "the note names the limit")
      (assert (< runawayMs 20000) "the runaway child is killed long before its 30 s body ends")
      (assert (not descLeft) "none of its six sleeps survives the kill")
      (assert (= late.verdict "timeout") (str "a child past timeoutMs is killed with a timeout verdict: " late.note))
      (assert (not timeLeft) "the timed-out child's sleep does not survive")
      (assert (and (= killed.verdict "lane") (= killed.exit -1)) "a caller verdict kills and reaps the child")
      (assert (not killLeft) "the caller-killed child's sleep does not survive")
      (assert (match badClass ((err e) (stringContains? e "lim.class must be empty")) ((ok _) false)) "a jobserver class is refused before any fork")
      (assert (match noTimeout ((err e) (stringContains? e "timeoutMs must be positive")) ((ok _) false)) "a zero timeout is refused before any fork")
      (assert (and (= noLog.exit 125) (= noLog.verdict "")) "a child that cannot open its log exits 125 without running its body")
      true))
