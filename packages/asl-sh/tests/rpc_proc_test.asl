(module asl-sh/rpc-proc-test
  :d "Verification suite for interactive process Batch RPC operations and protocol lifecycle."
  :x [run-tests]
  :i [(asl-sh/core-process :a proc)
      (reducer :a red)])

(df test-proc-spawn-operation [] -> Bool
  :d "Verifies process session spawn operation semantics."
  (let [(c (proc/cmd "python3" (list "-i")))
        (s (proc/session-spawn! "proc-sess-100" c))]
    (assert (= (.-id s) "proc-sess-100") "Session ID matches")
    (assert (= (.-state s) "active") "Initial session state is active")
    (assert (> (.-pid s) 0) "Session PID is positive integer")
    (assert (list-empty? (.-stdin-buffer s)) "Initial stdin buffer is empty")
    (assert (list-empty? (.-stdout-buffer s)) "Initial stdout buffer is empty")
    true))

(df test-proc-input-operation [] -> Bool
  :d "Verifies streaming stdin injection and idle reset operation."
  (let [(c (proc/cmd "cat" (list)))
        (s0 (proc/session-spawn! "proc-sess-101" c))
        (s1 (proc/session-tick-idle s0 5000))
        (s2 (proc/session-send-input! s1 "import math\nmath.sqrt(16)\n"))]
    (assert (= (.-idle-ms s1) 5000) "Session idle ms updated")
    (assert (= (.-idle-ms s2) 0) "Sending input resets idle ms to 0")
    (assert (= (list-length (.-stdin-buffer s2)) 1) "Stdin line stored in buffer")
    (assert (string-contains? (option-or (list-head (.-stdin-buffer s2)) "") "math.sqrt") "Stdin content matches")
    (assert (= (.-state s2) "active") "Session remains active")
    true))

(df test-proc-skeleton-operation [] -> Bool
  :d "Verifies output skeleton extraction from process stdout stream."
  (let [(raw (str "--> [1/2] Compiling kernel\n"
                  "warning: unused variable `ctx`\n"
                  "--> [2/2] Running checks\n"
                  "src/main.rs:42:10 - error: unresolved import\n"))
        (skel (red/extract-output-skeleton raw))]
    (assert (= (.-total-lines skel) 4) "Total lines count is 4")
    (assert (= (list-length (.-sections skel)) 2) "Identified 2 sections")
    (assert (= (list-length (.-diagnostics skel)) 1) "Extracted 1 compiler diagnostic")
    (assert (red/skeleton-has-errors? skel) "Skeleton flags error section")
    (assert (string-contains? (.-summary skel) "Errors: 1") "Summary reports 1 error")
    (let [(s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))]
      (assert (.-has-error s2) "Second section marked with error"))
    true))

(df test-proc-read-slice-operation [] -> Bool
  :d "Verifies line slice reading from process output buffer."
  (let [(lines (list "line 1: header"
                     "line 2: compilation"
                     "line 3: diagnostic error"
                     "line 4: stack frame"
                     "line 5: footer"))
        (start-idx 2)
        (end-idx 4)
        (slice (option-or (list-slice lines start-idx end-idx) (list)))]
    (assert (= (list-length slice) 2) "Sliced 2 lines")
    (assert (= (option-or (list-get slice 0) "") "line 3: diagnostic error") "First sliced line matches")
    (assert (= (option-or (list-get slice 1) "") "line 4: stack frame") "Second sliced line matches")
    (assert (not (list-empty? slice)) "Slice is not empty")
    true))

(df test-proc-signal-operation [] -> Bool
  :d "Verifies process signal termination and exit state."
  (let [(c (proc/cmd "sleep" (list "60")))
        (s0 (proc/session-spawn! "proc-sess-102" c))
        (s1 (proc/session-kill! s0))]
    (assert (= (.-state s0) "active") "Original session active")
    (assert (= (.-state s1) "terminated") "Killed session state is terminated")
    (assert (= (.-exit-code s1) 137) "Exit code reflects SIGKILL 137")
    (assert (not (.-deadlock-detected s1)) "No deadlock flagged on manual kill")
    true))

(df test-proc-deadlock-trapping [] -> Bool
  :d "Verifies deadlock detection when session exceeds idle ceiling."
  (let [(c (proc/cmd "bash" (list)))
        (s0 (proc/session-spawn! "proc-sess-103" c))
        (s-normal (proc/session-tick-idle s0 8000))
        (s-over (proc/session-tick-idle s0 12000))
        (v-normal (proc/session-check-deadlock s-normal 10000))
        (v-deadlock (proc/session-check-deadlock s-over 10000))]
    (assert (not (.-deadlock-detected s-normal)) "8s idle is not deadlocked")
    (assert (.-deadlock-detected s-over) "12s idle trips deadlock")
    (assert (not (.-deadlocked v-normal)) "Verdict normal reports not deadlocked")
    (assert (.-deadlocked v-deadlock) "Verdict deadlock reports deadlocked")
    true))

(df test-proc-dynamic-timeout-extension [] -> Bool
  :d "Verifies dynamic timeout extension and set-timeout on active process session."
  (let [(c (proc/cmd "make" (list "-j8")))
        (s0 (proc/session-spawn! "proc-sess-104" c))
        (s1 (proc/session-extend-timeout s0 15000))
        (s2 (proc/session-set-timeout s1 45000))
        (s-tick (proc/session-tick-idle s2 20000))
        (v-check (proc/session-check-deadlock s-tick 0))]
    (assert (= (.-timeout-ms s0) 5000) "Initial session timeout defaults to command timeout 5000ms")
    (assert (= (.-timeout-ms s1) 20000) "Extended session timeout reflects addition")
    (assert (= (.-timeout-ms s2) 45000) "Updated session timeout reflects new ceiling")
    (assert (not (.-deadlock-detected v-check)) "20s idle is safely within 45s extended timeout ceiling")
    true))

(df run-tests [] -> Bool
  :d "Runs all test suites for interactive process RPC protocol."
  (and (test-proc-spawn-operation)
       (and (test-proc-input-operation)
            (and (test-proc-skeleton-operation)
                 (and (test-proc-read-slice-operation)
                      (and (test-proc-signal-operation)
                           (and (test-proc-deadlock-trapping)
                                (test-proc-dynamic-timeout-extension))))))))
