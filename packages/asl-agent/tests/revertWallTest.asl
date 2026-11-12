(module aslAgent/tests/revertWallTest
  :x [runTests]
  :i [(aslAgent/gateIntegrity :a gi) (aslAgent/gates :a g) (aslAgent/main :a m)])

; (:m :ref LEON-FINISH-HANG :do "the revert check of a finish ends inside the wall the run has left: a gate that sleeps 40 s on the reverted tree, a 300 s gate timeout with its 900 s revert floor and 14 s of wall end the check unfinished near 14 s, its sleeping child is gone, the implementation is restored; the floor and the grader wall are cut to the wall left")

fn ! run command: String -> ProcessOutput
  (processRun command)

fn ! write root: String name: String contents: String -> Bool
  (ok? (fileWrite (str root "/" name) contents))

fn ! initRepo root: String -> Bool
  (and (= (run (str "git -C " root " init -q")).exitCode 0)
    (and (= (run (str "git -C " root " add -A")).exitCode 0)
      (= (run (str "git -C " root " -c user.email=t@t -c user.name=t commit -qm base")).exitCode 0)))

fn ! alive? pid: Int64 -> Bool
  (let [row (stringTrim (run (str "ps -p " (stringFromInt64 pid) " -o stat=")).stdout)]
    (and (> pid 1) (and (not (stringEmpty? row)) (not (stringStartsWith? row "Z")))))

fn ! testPure -> Bool
  (do
    (assert (= (gi/revertTimeoutWithin 300 (some 40)) 40) "the 900 s revert floor is cut to the 40 s of wall left")
    (assert (= (gi/revertTimeoutWithin 300 (some 5000)) 900) "with wall to spare the floor holds")
    (assert (= (gi/revertTimeoutWithin 300 (none)) 900) "an unbounded run keeps the floor")
    (assert (= (gi/revertTimeoutWithin 300 (some 0)) 1) "no wall left still gives a positive timeout")
    (assert (= (m/graderWall (some 100) 50.0) (some 35)) "the grader gets the wall left less the 15 s grace")
    (assert (= (m/graderWall (some 100) 99.0) (some 1)) "a spent wall gives the grader one second, never zero")
    (assert (= (m/graderWall (none) 50.0) (none)) "an unbounded run leaves the grader uncapped")
    true)

fn ! testWallBound -> Bool
  (let [root (stringTrim (run "mktemp -d /tmp/asl_revert_wall_test.XXXXXX").stdout)
        script "if grep -qx old impl.txt; then sleep 40 & echo $! > sleeper; wait; fi; echo '(:gate :asserts 1 :failed 0)'\n"
        setup (and (write root "impl.txt" "old\n") (and (write root "gate.sh" script) (initRepo root)))
        changed (write root "impl.txt" "new\n")
        started (monotonicNs)
        result (gi/gateIntegrityWithin! (list "sh gate.sh") (list "impl.txt" "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 300 (none) (list) (none) "" (some 14))
        ms (/ (- (monotonicNs) started) 1000000)
        sleeper (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str root "/sleeper")) ""))) 0)
        sleeperAlive (alive? sleeper)
        _killed (if sleeperAlive (ok? (procKill sleeper "SIGKILL")) true)
        after (resultOr (fileReadString (str root "/impl.txt")) "")
        cleaned (= (run (str "rm -rf " root)).exitCode 0)]
    (do
      (assert (and setup changed) "the fixture repo is set up with the change on top of its base")
      (assert (> sleeper 1) "the reverted gate started its sleeper")
      (refute (pairFirst result) (str "a revert check cut by the wall does not pass: " (pairSecond result)))
      (assert (stringContains? (pairSecond result) "revertCheck unfinished :revertKind wall") (str "the check names the wall as why it is unfinished: " (pairSecond result)))
      (assert (< ms 30000) (str "the check ends near the 14 s wall, not on the 900 s floor or the 40 s gate: " (stringFromInt64 ms) " ms"))
      (refute sleeperAlive "the reverted gate's sleeping child is killed with the run cut by the wall")
      (assert (= after "new\n") (str "the implementation is restored after the check: " after))
      (assert cleaned "the fixture repo is removed")
      true))

fn ! runTests -> Bool
  (and (testPure) (testWallBound))
