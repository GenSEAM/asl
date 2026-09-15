(module asl-sh/sessionTest
  :d "Verification test suite for interactive process sessions and streaming stdin."
  :x [runTests]
  :i [(asl-sh/coreProcess :a proc)])

(df testSessionSpawn [] -> Bool
  :d "Verifies initial session state after spawning."
  (let [(c (proc/cmd "bash" (list "-i")))
        (s (proc/sessionSpawn! "sess-1" c))]
    (assert (= (.-id s) "sess-1") "Session ID must match")
    (assert (= (.-state s) "active") "Initial session state must be active")
    (assert (= (.-pid s) 1001) "Mock PID must be assigned")
    (assert (list-empty? (.-stdinBuffer s)) "Initial stdin buffer must be empty")
    (assert (list-empty? (.-stdoutBuffer s)) "Initial stdout buffer must be empty")
    (refute (.-deadlockDetected s) "Deadlock must not be detected initially")
    true))

(df testSessionInputAndAlias [] -> Bool
  :d "Verifies stdin buffer accumulation and alias."
  (let [(c (proc/cmd "cat" (list)))
        (s0 (proc/sessionSpawn! "sess-2" c))
        (s1 (proc/sessionSendInput! s0 "line 1"))
        (s2 (proc/sessionInput! s1 "line 2"))]
    (assert (= (list-length (.-stdinBuffer s2)) 2) "Two lines must be buffered in stdin")
    (assert (= (option-or (list-get (.-stdinBuffer s2) 0) "") "line 1") "First stdin line must match")
    (assert (= (option-or (list-get (.-stdinBuffer s2) 1) "") "line 2") "Second stdin line must match")
    (assert (= (.-idleMs s2) 0) "Sending input must reset idle ms")
    true))

(df testSessionStdoutAndTail [] -> Bool
  :d "Verifies stdout emission and tail polling."
  (let [(c (proc/cmd "python3" (list "-i")))
        (s0 (proc/sessionSpawn! "sess-3" c))
        (s1 (proc/sessionEmitStdout! s0 "Python 3.13.0"))
        (s2 (proc/sessionEmitStdout! s1 ">>> "))
        (tailAll (proc/sessionPollTail! s2 2))
        (tailOne (proc/sessionTail! s2 1))]
    (assert (= (list-length (.-stdoutBuffer s2)) 2) "Stdout buffer must contain two lines")
    (assert (= (list-length tailAll) 2) "Polling 2 lines must return 2 lines")
    (assert (= (list-length tailOne) 1) "Polling 1 line must return 1 line")
    (assert (= (option-or (list-get tailOne 0) "") ">>> ") "Tail line must match prompt")
    true))

(df testSessionStderr [] -> Bool
  :d "Verifies stderr buffer accumulation."
  (let [(c (proc/cmd "test" (list)))
        (s0 (proc/sessionSpawn! "sess-4" c))
        (s1 (proc/sessionEmitStderr! s0 "warning: deprecation"))]
    (assert (= (list-length (.-stderrBuffer s1)) 1) "Stderr buffer must contain one line")
    (assert (= (option-or (list-get (.-stderrBuffer s1) 0) "") "warning: deprecation") "Stderr line must match")
    true))

(df testSessionDeadlockDetection [] -> Bool
  :d "Verifies idle deadlock auditing and flag transitions."
  (let [(c (proc/cmd "sudo" (list "ls")))
        (s0 (proc/sessionSpawn! "sess-5" c))
        (s1 (proc/sessionTickIdle s0 12000))
        (s2 (proc/sessionCheckDeadlock s1 10000))
        (s3 (proc/sessionSendInput! s2 "password\n"))
        (sIdle2 (proc/sessionCheckDeadlock (proc/sessionTickIdle s0 2000) 1000))
        (sRecoveredStdout (proc/sessionEmitStdout! sIdle2 "output line"))
        (sRecoveredCap (proc/sessionCheckDeadlock sIdle2 5000))]
    (assert (= (.-idleMs s1) 12000) "Idle time must advance by 12000ms")
    (assert (.-deadlockDetected s2) "Deadlock must be detected when idle exceeds ceiling")
    (assert (= (.-state s2) "idle") "Session state must transition to idle on deadlock")
    (refute (.-deadlockDetected s3) "Sending input must clear deadlock flag")
    (assert (= (.-state s3) "active") "Sending input must restore active state")
    (assert (= (.-state sRecoveredStdout) "active") "Stdout emission must restore active state")
    (assert (= (.-state sRecoveredCap) "active") "Higher deadlock ceiling must restore active state")
    true))

(df testSessionKillAndTermination [] -> Bool
  :d "Verifies process termination with signals and no-op input."
  (let [(c (proc/cmd "sleep" (list "100")))
        (s0 (proc/sessionSpawn! "sess-6" c))
        (sTerm (proc/sessionKill! s0 "SIGTERM"))
        (sDead (proc/sessionKill! s0 "SIGKILL"))
        (sInt (proc/sessionKill! s0 "SIGINT"))
        (sHup (proc/sessionKill! s0 "SIGHUP"))
        (sNoop (proc/sessionSendInput! sDead "ignored"))]
    (assert (= (.-state sTerm) "terminated") "State must be terminated after SIGTERM")
    (assert (= (mt (.-exitCode sTerm) ((some code) code) ((none) 0)) 143) "Exit code must be 143 for SIGTERM")
    (assert (= (.-state sDead) "terminated") "State must be terminated after SIGKILL")
    (assert (= (mt (.-exitCode sDead) ((some code) code) ((none) 0)) 137) "Exit code must be 137 for SIGKILL")
    (assert (= (mt (.-exitCode sInt) ((some code) code) ((none) 0)) 130) "Exit code must be 130 for SIGINT")
    (assert (= (mt (.-exitCode sHup) ((some code) code) ((none) 0)) 129) "Exit code must be 129 for SIGHUP")
    (assert (list-empty? (.-stdinBuffer sNoop)) "Input to terminated session must be ignored")
    true))

(df runTests [] -> Bool
  :d "Executes all session verification tests."
  (and (testSessionSpawn)
       (and (testSessionInputAndAlias)
            (and (testSessionStdoutAndTail)
                 (and (testSessionStderr)
                      (and (testSessionDeadlockDetection)
                           (testSessionKillAndTermination)))))))
