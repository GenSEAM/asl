(module asl-proc/sessionTest :x [runTests] :i [(asl-proc/coreProcess :a proc)])

fn testSessionSpawn! -> Bool
  (let [(c (proc/cmd "bash" (list "-i"))) (s (proc/sessionSpawn! "sess-1" c))] (assert (= s.id "sess-1") "Session ID must match") (assert (= s.state "active") "Initial session state must be active") (assert (= s.pid 1001) "Mock PID must be assigned") (assert (listEmpty? s.stdinBuffer) "Initial stdin buffer must be empty") (assert (listEmpty? s.stdoutBuffer) "Initial stdout buffer must be empty") (refute s.deadlockDetected "Deadlock must not be detected initially") true)

fn testSessionInputAndAlias! -> Bool
  (let [(c (proc/cmd "cat" (list))) (s0 (proc/sessionSpawn! "sess-2" c)) (s1 (proc/sessionSendInput! s0 "line 1")) (s2 (proc/sessionInput! s1 "line 2"))] (assert (= (listLength s2.stdinBuffer) 2) "Two lines must be buffered in stdin") (assert (= (optionOr (listGet s2.stdinBuffer 0) "") "line 1") "First stdin line must match") (assert (= (optionOr (listGet s2.stdinBuffer 1) "") "line 2") "Second stdin line must match") (assert (= s2.idleMs 0) "Sending input must reset idle ms") true)

fn testSessionStdoutAndTail! -> Bool
  (let [(c (proc/cmd "python3" (list "-i"))) (s0 (proc/sessionSpawn! "sess-3" c)) (s1 (proc/sessionEmitStdout! s0 "Python 3.13.0")) (s2 (proc/sessionEmitStdout! s1 ">>> ")) (tailAll (proc/sessionPollTail! s2 2)) (tailOne (proc/sessionTail! s2 1))] (assert (= (listLength s2.stdoutBuffer) 2) "Stdout buffer must contain two lines") (assert (= (listLength tailAll) 2) "Polling 2 lines must return 2 lines") (assert (= (listLength tailOne) 1) "Polling 1 line must return 1 line") (assert (= (optionOr (listGet tailOne 0) "") ">>> ") "Tail line must match prompt") true)

fn testSessionStderr! -> Bool
  (let [(c (proc/cmd "test" (list))) (s0 (proc/sessionSpawn! "sess-4" c)) (s1 (proc/sessionEmitStderr! s0 "warning: deprecation"))] (assert (= (listLength s1.stderrBuffer) 1) "Stderr buffer must contain one line") (assert (= (optionOr (listGet s1.stderrBuffer 0) "") "warning: deprecation") "Stderr line must match") true)

fn testSessionDeadlockDetection! -> Bool
  (let [(c (proc/cmd "sudo" (list "ls"))) (s0 (proc/sessionSpawn! "sess-5" c)) (s1 (proc/sessionTickIdle s0 12000)) (s2 (proc/sessionCheckDeadlock s1 10000)) (s3 (proc/sessionSendInput! s2 "password\n")) (sIdle2 (proc/sessionCheckDeadlock (proc/sessionTickIdle s0 2000) 1000)) (sRecoveredStdout (proc/sessionEmitStdout! sIdle2 "output line")) (sRecoveredCap (proc/sessionCheckDeadlock sIdle2 5000))] (assert (= s1.idleMs 12000) "Idle time must advance by 12000ms") (assert s2.deadlockDetected "Deadlock must be detected when idle exceeds ceiling") (assert (= s2.state "idle") "Session state must transition to idle on deadlock") (refute s3.deadlockDetected "Sending input must clear deadlock flag") (assert (= s3.state "active") "Sending input must restore active state") (assert (= sRecoveredStdout.state "active") "Stdout emission must restore active state") (assert (= sRecoveredCap.state "active") "Higher deadlock ceiling must restore active state") true)

fn testSessionKillAndTermination! -> Bool
  (let [(c (proc/cmd "sleep" (list "100"))) (s0 (proc/sessionSpawn! "sess-6" c)) (sTerm (proc/sessionKill! s0 "SIGTERM")) (sDead (proc/sessionKill! s0 "SIGKILL")) (sInt (proc/sessionKill! s0 "SIGINT")) (sHup (proc/sessionKill! s0 "SIGHUP")) (sNoop (proc/sessionSendInput! sDead "ignored"))] (assert (= sTerm.state "terminated") "State must be terminated after SIGTERM") (assert (= (mt sTerm.exitCode ((some code) code) ((none) 0)) -15) "Exit code must be -15 for SIGTERM") (assert (= sDead.state "terminated") "State must be terminated after SIGKILL") (assert (= (mt sDead.exitCode ((some code) code) ((none) 0)) -9) "Exit code must be -9 for SIGKILL") (assert (= (mt sInt.exitCode ((some code) code) ((none) 0)) -2) "Exit code must be -2 for SIGINT") (assert (= (mt sHup.exitCode ((some code) code) ((none) 0)) -1) "Exit code must be -1 for SIGHUP") (assert (listEmpty? sNoop.stdinBuffer) "Input to terminated session must be ignored") true)

fn ! runTests -> Bool
  (and (testSessionSpawn!) (and (testSessionInputAndAlias!) (and (testSessionStdoutAndTail!) (and (testSessionStderr!) (and (testSessionDeadlockDetection!) (testSessionKillAndTermination!))))))
