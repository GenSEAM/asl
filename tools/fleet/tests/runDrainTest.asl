(module asl-tools/fleet/tests/runDrainTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref FR-KILL-DRAIN :do "a child writes 200 lines, touches a marker and sleeps; once the marker exists the lines are in its pipe and nothing has read them. The judge then kills it for its timeout at once and the 200 lines must be in the text of the pooled run (judge) and of the guarded run (judgeSep): before the drain they were lost. The sleeper is killed by the judge itself, its fds closed and its pid reaped; no sleep stands in for a race, only a bounded wait for the marker")

fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/runDrainTest-" (stringFromInt64 (procSelf)))

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn scriptFor marker: String life: String -> String
  (str "i=1; while [ $i -le 200 ]; do echo line$i; echo err$i >&2; i=$((i+1)); done; touch " marker "; exec sleep " life)

fn script marker: String -> String
  (scriptFor marker "60")

fn ! waitFor! path: String tries: Int64 -> Bool
  (cond ((fileExists? path) true) ((<= tries 0) false) (else (do (sleepMs 50) (waitFor! path (- tries 1)))))

fn countPrefix text: String prefix: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l prefix)) (stringLines text)))

fn lineCount text: String -> Int64
  (countPrefix text "line")

fn ! tidy! pid: Int64 -> Unit
  (let [(_ (fr/killTree! pid))
        (_ (procWaitPid pid false))]
    ())

fn ! testPooled -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (marker (str dir "/m1"))
        (sp (fr/spawn 0 (fr/job (list "sh" "-c" (script marker)) "." (fr/childEnv (list)))))]
    (match sp
      ((err d) (do (assert false (str "spawn failed: " d.out)) false))
      ((ok r)
        (let [(ready (waitFor! marker 200))
              (j (fr/judge (fr/limits 1 16) (+ r.startNs 5000000000) (list) -1 false r))
              (_ (if j.outOpen (ok? (fdClose j.outFd)) false))
              (_ (if j.errOpen (ok? (fdClose j.errFd)) false))
              (_ (tidy! r.pid))
              (_ (cleanup dir))]
          (do (assert ready "the child printed its lines and touched the marker")
              (assert (= j.killed "timeout") (str "the judge killed it for its timeout: " j.killed))
              (assert (= (lineCount j.text) 200) (str "all 200 stdout lines are in the text after the kill: " (stringFromInt64 (lineCount j.text))))
              (assert (= (countPrefix j.text "err") 200) (str "and all 200 stderr lines: " (stringFromInt64 (countPrefix j.text "err"))))
              (assert (stringContains? j.text "(:fleetRun :verdict :timeout") "and the verdict note follows them")
              true)))))

fn ! testGuarded -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (marker (str dir "/m2"))
        (sp (fr/spawnSep (list "sh" "-c" (script marker)) "." (fr/childEnv (list))))]
    (match sp
      ((err d) (do (assert false (str "spawn failed: " d.stderr)) false))
      ((ok r)
        (let [(ready (waitFor! marker 200))
              (old (fr/RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText r.errText :outOpen r.outOpen :errOpen r.errOpen :startNs (- r.startNs 5000000000) :killed r.killed :groups r.groups :known r.known))
              (j (fr/judgeSep (fr/limits 1 16) r.startNs (list) -1 false old))
              (_ (if j.outOpen (ok? (fdClose j.outFd)) false))
              (_ (if j.errOpen (ok? (fdClose j.errFd)) false))
              (_ (tidy! r.pid))
              (_ (cleanup dir))]
          (do (assert ready "the child printed its lines and touched the marker")
              (assert (= j.killed "timeout") (str "the judge killed it for its timeout: " j.killed))
              (assert (= (lineCount j.outText) 200) (str "all 200 lines are in stdout after the kill: " (stringFromInt64 (lineCount j.outText))))
              (assert (= (countPrefix j.errText "err") 200) (str "all 200 stderr lines are in errText after the kill: " (stringFromInt64 (countPrefix j.errText "err"))))
              (assert (stringContains? j.errText "(:fleetRun :verdict :timeout") "and the verdict note is in stderr")
              true)))))

; (:m :ref FR-KILL-DRAIN :do "the drain is bounded: on a killed child a zero byte cap reads nothing and leaves the pipe open and an ample cap reads every line and sees the end of the pipe; on a second child that lives 2 s a deadline already passed reads nothing and leaves the pipe open, where an unbounded drain would read its 200 lines and wait for its end (the child's own short life keeps the fixture bounded)")
fn ! testBounds -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (m3 (str dir "/m3"))
        (m4 (str dir "/m4"))
        (sp (fr/spawnSep (list "sh" "-c" (script m3)) "." (fr/childEnv (list))))
        (sq (fr/spawnSep (list "sh" "-c" (scriptFor m4 "2")) "." (fr/childEnv (list))))]
    (match sp
      ((err d) (do (assert false (str "spawn failed: " d.stderr)) false))
      ((ok r)
        (match sq
          ((err d) (do (assert false (str "spawn failed: " d.stderr)) (fr/killTree! r.pid) false))
          ((ok q)
            (let [(ready (waitFor! m3 200))
                  (readyQ (waitFor! m4 200))
                  (_ (fr/killTree! r.pid))
                  (off (fr/drainFd r.outFd true 0 (+ (monotonicNs) 2000000000) ""))
                  (all (fr/drainFd r.outFd true 1000000 (+ (monotonicNs) 2000000000) ""))
                  (late (fr/drainFd q.outFd true 1000000 (monotonicNs) ""))
                  (_ (if (pairFirst all) (ok? (fdClose r.outFd)) false))
                  (_ (ok? (fdClose r.errFd)))
                  (_ (ok? (fdClose q.outFd)))
                  (_ (ok? (fdClose q.errFd)))
                  (_ (tidy! r.pid))
                  (_ (tidy! q.pid))
                  (_ (cleanup dir))]
              (do (assert (and ready readyQ) "both children printed their lines and touched their marker")
                  (assert (and (pairFirst off) (stringEmpty? (pairSecond off))) "a zero byte cap reads nothing and leaves the pipe open")
                  (assert (and (not (pairFirst all)) (= (lineCount (pairSecond all)) 200)) "an ample cap reads all 200 lines and reaches the end of the pipe")
                  (assert (and (pairFirst late) (stringEmpty? (pairSecond late))) "a passed deadline reads nothing and leaves the pipe open")
                  true)))))))

; (:m :ref FR-KILL-DRAIN :do "the two :fleet rows: an absent file, group or key, a non-number and an out-of-range value give the default; a good value is read from inside the group only")
fn testConfig -> Bool
  (let [(good "(:aslConfig :fleet (:drainBytes 4096 :drainMs 50) :other (:drainBytes 9))")
        (other "(:aslConfig :other (:drainBytes 9))")
        (high "(:aslConfig :fleet (:drainBytes 99999999999 :drainMs 6000))")
        (word "(:aslConfig :fleet (:drainBytes many :drainMs))")
        (zero "(:aslConfig :fleet (:drainBytes 0 :drainMs 0))")
        (prefix "(:aslConfig :fleetRun (:drainBytes 5) :fleet (:drainBytes 7))")
        (onlyPrefix "(:aslConfig :fleetRun (:drainBytes 5))")
        (tight "(:aslConfig :fleet(:drainBytes 9))")]
    (do (assert (and (= (fr/fleetInt good "drainBytes" 1048576 0 67108864) 4096) (= (fr/fleetInt good "drainMs" 300 0 5000) 50)) "good values are read")
        (assert (= (fr/fleetInt "" "drainMs" 300 0 5000) 300) "an absent file gives the default")
        (assert (= (fr/fleetInt other "drainBytes" 1048576 0 67108864) 1048576) "a key of another group is not the fleet key")
        (assert (and (= (fr/fleetInt high "drainBytes" 1048576 0 67108864) 1048576) (= (fr/fleetInt high "drainMs" 300 0 5000) 300)) "out of range gives the default")
        (assert (and (= (fr/fleetInt word "drainBytes" 1048576 0 67108864) 1048576) (= (fr/fleetInt word "drainMs" 300 0 5000) 300)) "a non-number gives the default")
        (assert (and (= (fr/fleetInt prefix "drainBytes" 1048576 0 67108864) 7) (and (= (fr/fleetInt onlyPrefix "drainBytes" 1048576 0 67108864) 1048576) (= (fr/fleetInt tight "drainBytes" 1048576 0 67108864) 9))) "a key that begins with fleet is not the group, a group with no space is")
        (assert (and (= (fr/fleetInt zero "drainBytes" 1048576 0 67108864) 0) (= (fr/fleetInt zero "drainMs" 300 0 5000) 0)) "zero is a value, not an absent key")
        true))

fn ! runTests -> Bool
  (do (assert (testPooled) "a pooled run killed by the judge keeps the output written just before")
      (assert (testGuarded) "a guarded run killed by the judge keeps the output written just before")
      (assert (testBounds) "the drain is bounded by bytes and by time")
      (assert (testConfig) "the fleet rows parse with defaults")
      true)
