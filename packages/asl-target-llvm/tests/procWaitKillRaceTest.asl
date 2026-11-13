(module asl/packages/asl-target-llvm/tests/procWaitKillRaceTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref KILLEDLAUNCHER-HANG :do "a blocking procWaitPid right after a SIGKILL returns: own sleepers (per-run unique seconds) are killed and waited for, up to 1500 times or 45 s; on Darwin the one-shot NOTE_EXIT can come before waitpid can reap the child, and the old wait then blocked in kevent forever (seen within 800 to 2800 rounds at load 20); a watchdog sh SIGKILLs this test at 150 s, so a hang ends red, never stuck")

fn ! sleeper! secs: String -> Int64
  (match (fr/spawnSep (list "sleep" secs) "." (fr/childEnv (list)))
    ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) r.pid))
    ((err _) -1))

fn ! rounds! secs: String i: Int64 n: Int64 deadlineNs: Int64 reaped: Int64 -> (Pair Int64 Int64)
  (if (or (>= i n) (> (monotonicNs) deadlineNs)) (pair i reaped)
    (let [(pid (sleeper! secs))]
      (if (<= pid 1) (pair i reaped)
        (let [(_ (procKill pid "SIGKILL"))
              (got (match (procWaitPid pid false) ((ok (some _)) 1) ((ok (none)) 0) ((err _) 0)))]
          (rounds! secs (+ i 1) n deadlineNs (+ reaped got))))))

fn ! runTests -> Bool
  (let [(m (mod (procSelf) 90))
        (secs (stringFromInt64 (+ 900 m)))
        (dog (match (fr/spawnSep (list "sh" "-c" (str "sleep 150; kill -KILL " (stringFromInt64 (procSelf)))) "." (fr/childEnv (list)))
               ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) r.pid))
               ((err _) -1)))
        (done (rounds! secs 0 1500 (+ (monotonicNs) 45000000000) 0))
        (_ (if (> dog 1) (do (fr/killTree! dog) (procWaitPid dog true) true) true))
        (leftover (resultOr (fr/shellOut (str "pgrep -f '^sleep " secs "$' | wc -l") 10000) "?"))]
    (do (assert (> dog 1) (str "the watchdog started: " (stringFromInt64 dog)))
        (assert (> (pairFirst done) 100) (str "more than 100 kill-and-wait rounds ran: " (stringFromInt64 (pairFirst done))))
        (assert (= (pairSecond done) (pairFirst done)) (str "every blocking wait after a SIGKILL returned the exit: " (stringFromInt64 (pairSecond done)) " of " (stringFromInt64 (pairFirst done))))
        (assert (= (stringTrim leftover) "0") (str "no sleeper is left: " leftover))
        true))
