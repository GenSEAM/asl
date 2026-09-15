(module asl-sh/rpcProcTest
  :d "Verification suite for interactive process Batch RPC operations and protocol lifecycle."
  :x [runTests]
  :i [(asl-sh/coreProcess :a proc)
      (reducer :a red)])

(df testProcSpawnOperation [] -> Bool
  :d "Verifies process session spawn operation semantics."
  (let [(c (proc/cmd "python3" (list "-i")))
        (s (proc/sessionSpawn! "proc-sess-100" c))]
    (assert (= (.-id s) "proc-sess-100") "Session ID matches")
    (assert (= (.-state s) "active") "Initial session state is active")
    (assert (> (.-pid s) 0) "Session PID is positive integer")
    (assert (list-empty? (.-stdinBuffer s)) "Initial stdin buffer is empty")
    (assert (list-empty? (.-stdoutBuffer s)) "Initial stdout buffer is empty")
    true))

(df testProcInputOperation [] -> Bool
  :d "Verifies streaming stdin injection and idle reset operation."
  (let [(c (proc/cmd "cat" (list)))
        (s0 (proc/sessionSpawn! "proc-sess-101" c))
        (s1 (proc/sessionTickIdle s0 5000))
        (s2 (proc/sessionSendInput! s1 "import math\nmath.sqrt(16)\n"))]
    (assert (= (.-idleMs s1) 5000) "Session idle ms updated")
    (assert (= (.-idleMs s2) 0) "Sending input resets idle ms to 0")
    (assert (= (list-length (.-stdinBuffer s2)) 1) "Stdin line stored in buffer")
    (assert (string-contains? (option-or (list-head (.-stdinBuffer s2)) "") "math.sqrt") "Stdin content matches")
    (assert (= (.-state s2) "active") "Session remains active")
    true))

(df testProcSkeletonOperation [] -> Bool
  :d "Verifies output skeleton extraction from process stdout stream."
  (let [(raw (str "--> [1/2] Compiling kernel\n"
                  "warning: unused variable `ctx`\n"
                  "--> [2/2] Running checks\n"
                  "src/main.rs:42:10 - error: unresolved import\n"))
        (skel (red/extractOutputSkeleton raw))]
    (assert (= (.-totalLines skel) 4) "Total lines count is 4")
    (assert (= (list-length (.-sections skel)) 2) "Identified 2 sections")
    (assert (= (list-length (.-diagnostics skel)) 1) "Extracted 1 compiler diagnostic")
    (assert (red/skeletonHasErrors? skel) "Skeleton flags error section")
    (assert (string-contains? (.-summary skel) "Errors: 1") "Summary reports 1 error")
    (let [(s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))]
      (assert (.-hasError s2) "Second section marked with error"))
    true))

(df testProcReadSliceOperation [] -> Bool
  :d "Verifies line slice reading from process output buffer."
  (let [(lines (list "line 1: header"
                     "line 2: compilation"
                     "line 3: diagnostic error"
                     "line 4: stack frame"
                     "line 5: footer"))
        (startIdx 2)
        (endIdx 4)
        (slice (option-or (list-slice lines startIdx endIdx) (list)))]
    (assert (= (list-length slice) 2) "Sliced 2 lines")
    (assert (= (option-or (list-get slice 0) "") "line 3: diagnostic error") "First sliced line matches")
    (assert (= (option-or (list-get slice 1) "") "line 4: stack frame") "Second sliced line matches")
    (refute (list-empty? slice) "Slice is not empty")
    true))

(df testProcSignalOperation [] -> Bool
  :d "Verifies process signal termination and exit state."
  (let [(c (proc/cmd "sleep" (list "60")))
        (s0 (proc/sessionSpawn! "proc-sess-102" c))
        (s1 (proc/sessionKill! s0))]
    (assert (= (.-state s0) "active") "Original session active")
    (assert (= (.-state s1) "terminated") "Killed session state is terminated")
    (assert (= (.-exitCode s1) 137) "Exit code reflects SIGKILL 137")
    (refute (.-deadlockDetected s1) "No deadlock flagged on manual kill")
    true))

(df testProcDeadlockTrapping [] -> Bool
  :d "Verifies deadlock detection when session exceeds idle ceiling."
  (let [(c (proc/cmd "bash" (list)))
        (s0 (proc/sessionSpawn! "proc-sess-103" c))
        (sNormal (proc/sessionTickIdle s0 8000))
        (sOver (proc/sessionTickIdle s0 12000))
        (vNormal (proc/sessionCheckDeadlock sNormal 10000))
        (vDeadlock (proc/sessionCheckDeadlock sOver 10000))]
    (refute (.-deadlockDetected sNormal) "8s idle is not deadlocked")
    (assert (.-deadlockDetected sOver) "12s idle trips deadlock")
    (refute (.-deadlockDetected vNormal) "Verdict normal reports not deadlocked")
    (assert (.-deadlockDetected vDeadlock) "Verdict deadlock reports deadlocked")
    true))

(df testProcDynamicTimeoutExtension [] -> Bool
  :d "Verifies dynamic timeout extension and set-timeout on active process session."
  (let [(c (proc/cmd "make" (list "-j8")))
        (s0 (proc/sessionSpawn! "proc-sess-104" c))
        (s1 (proc/sessionExtendTimeout s0 15000))
        (s2 (proc/sessionSetTimeout s1 45000))
        (sTick (proc/sessionTickIdle s2 20000))
        (vCheck (proc/sessionCheckDeadlock sTick 0))]
    (assert (= (.-timeoutMs s0) 5000) "Initial session timeout defaults to command timeout 5000ms")
    (assert (= (.-timeoutMs s1) 20000) "Extended session timeout reflects addition")
    (assert (= (.-termDeadlineMs s1) 25000) "Extended term deadline reflects addition")
    (assert (= (.-killDeadlineMs s1) 27000) "Extended kill deadline reflects addition")
    (assert (= (.-timeoutMs s2) 45000) "Updated session timeout reflects new ceiling")
    (assert (= (.-termDeadlineMs s2) 45000) "Updated term deadline reflects set-timeout")
    (assert (= (.-killDeadlineMs s2) 47000) "Updated kill deadline reflects set-timeout")
    (refute (.-deadlockDetected vCheck) "20s idle is safely within 45s extended timeout ceiling")
    true))

(df testProcWatchdogNoResurrection [] -> Bool
  :d "Verifies that sessionStepWatchdog! preserves terminated state and prevents resurrection."
  (let [(c (proc/cmd "sleep" (list "60")))
        (s0 (proc/sessionSpawn! "proc-sess-105" c))
        (sKilled (proc/sessionKill! s0 "SIGTERM"))
        (sStepped (proc/sessionStepWatchdog! sKilled 1000 "tmp/test-spool.spool"))
        (sTimedOut (proc/sessionStepWatchdog! s0 10000 "tmp/test-spool.spool"))
        (sIdle (proc/sessionCheckDeadlock (proc/sessionTickIdle s0 1000) 500))
        (sIdleStepped (proc/sessionStepWatchdog! sIdle 100 "tmp/test-spool.spool"))]
    (assert (= (.-state sKilled) "terminated") "Killed session is terminated")
    (assert (= (.-state sStepped) "terminated") "Stepped terminated session remains terminated")
    (assert (= (.-exitCode sStepped) (some 143)) "Exit code preserved on terminated step")
    (assert (= (.-state sTimedOut) "terminated") "Session reaching termLimit transitions directly to terminated")
    (assert (= (.-state sIdle) "idle") "Precondition: session must be idle")
    (assert (= (.-state sIdleStepped) "idle") "Watchdog step within threshold must preserve idle state")
    true))

(df runTests [] -> Bool
  :d "Runs all test suites for interactive process RPC protocol."
  (and (testProcSpawnOperation)
       (and (testProcInputOperation)
            (and (testProcSkeletonOperation)
                 (and (testProcReadSliceOperation)
                      (and (testProcSignalOperation)
                           (and (testProcDeadlockTrapping)
                                (and (testProcDynamicTimeoutExtension)
                                     (testProcWatchdogNoResurrection)))))))))
