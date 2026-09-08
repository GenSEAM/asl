(module asl-sh/session-test
  :d "Verification test suite for interactive process sessions and streaming stdin."
  :x [run-tests]
  :i [(core/process :a proc)])

(df test-session-spawn [] -> Bool
  :d "Verifies initial session state after spawning."
  (let [(c (proc/cmd "bash" (list "-i")))
        (s (proc/session-spawn! "sess-1" c))]
    (assert (= (.-id s) "sess-1") "Session ID must match")
    (assert (= (.-state s) "active") "Initial session state must be active")
    (assert (= (.-pid s) 1001) "Mock PID must be assigned")
    (assert (list-empty? (.-stdin-buffer s)) "Initial stdin buffer must be empty")
    (assert (list-empty? (.-stdout-buffer s)) "Initial stdout buffer must be empty")
    (assert (not (.-deadlock-detected s)) "Deadlock must not be detected initially")
    true))

(df test-session-input-and-alias [] -> Bool
  :d "Verifies stdin buffer accumulation and alias."
  (let [(c (proc/cmd "cat" (list)))
        (s0 (proc/session-spawn! "sess-2" c))
        (s1 (proc/session-send-input! s0 "line 1"))
        (s2 (proc/session-input! s1 "line 2"))]
    (assert (= (list-length (.-stdin-buffer s2)) 2) "Two lines must be buffered in stdin")
    (assert (= (option-or (list-get (.-stdin-buffer s2) 0) "") "line 1") "First stdin line must match")
    (assert (= (option-or (list-get (.-stdin-buffer s2) 1) "") "line 2") "Second stdin line must match")
    (assert (= (.-idle-ms s2) 0) "Sending input must reset idle ms")
    true))

(df test-session-stdout-and-tail [] -> Bool
  :d "Verifies stdout emission and tail polling."
  (let [(c (proc/cmd "python3" (list "-i")))
        (s0 (proc/session-spawn! "sess-3" c))
        (s1 (proc/session-emit-stdout! s0 "Python 3.13.0"))
        (s2 (proc/session-emit-stdout! s1 ">>> "))
        (tail-all (proc/session-poll-tail! s2 2))
        (tail-one (proc/session-tail! s2 1))]
    (assert (= (list-length (.-stdout-buffer s2)) 2) "Stdout buffer must contain two lines")
    (assert (= (list-length tail-all) 2) "Polling 2 lines must return 2 lines")
    (assert (= (list-length tail-one) 1) "Polling 1 line must return 1 line")
    (assert (= (option-or (list-get tail-one 0) "") ">>> ") "Tail line must match prompt")
    true))

(df test-session-stderr [] -> Bool
  :d "Verifies stderr buffer accumulation."
  (let [(c (proc/cmd "test" (list)))
        (s0 (proc/session-spawn! "sess-4" c))
        (s1 (proc/session-emit-stderr! s0 "warning: deprecation"))]
    (assert (= (list-length (.-stderr-buffer s1)) 1) "Stderr buffer must contain one line")
    (assert (= (option-or (list-get (.-stderr-buffer s1) 0) "") "warning: deprecation") "Stderr line must match")
    true))

(df test-session-deadlock-detection [] -> Bool
  :d "Verifies idle deadlock auditing and flag transitions."
  (let [(c (proc/cmd "sudo" (list "ls")))
        (s0 (proc/session-spawn! "sess-5" c))
        (s1 (proc/session-tick-idle s0 12000))
        (s2 (proc/session-check-deadlock s1 10000))
        (s3 (proc/session-send-input! s2 "password\n"))]
    (assert (= (.-idle-ms s1) 12000) "Idle time must advance by 12000ms")
    (assert (.-deadlock-detected s2) "Deadlock must be detected when idle exceeds ceiling")
    (assert (= (.-state s2) "idle") "Session state must transition to idle on deadlock")
    (assert (not (.-deadlock-detected s3)) "Sending input must clear deadlock flag")
    (assert (= (.-state s3) "active") "Sending input must restore active state")
    true))

(df test-session-kill-and-termination [] -> Bool
  :d "Verifies process termination with signals and no-op input."
  (let [(c (proc/cmd "sleep" (list "100")))
        (s0 (proc/session-spawn! "sess-6" c))
        (s-term (proc/session-kill! s0 "SIGTERM"))
        (s-dead (proc/session-kill! s0 "SIGKILL"))
        (s-noop (proc/session-send-input! s-dead "ignored"))]
    (assert (= (.-state s-term) "terminated") "State must be terminated after SIGTERM")
    (assert (= (mt (.-exit-code s-term) ((some code) code) ((none) 0)) 143) "Exit code must be 143 for SIGTERM")
    (assert (= (.-state s-dead) "terminated") "State must be terminated after SIGKILL")
    (assert (= (mt (.-exit-code s-dead) ((some code) code) ((none) 0)) 137) "Exit code must be 137 for SIGKILL")
    (assert (list-empty? (.-stdin-buffer s-noop)) "Input to terminated session must be ignored")
    true))

(df run-tests [] -> Bool
  :d "Executes all session verification tests."
  (and (test-session-spawn)
       (and (test-session-input-and-alias)
            (and (test-session-stdout-and-tail)
                 (and (test-session-stderr)
                      (and (test-session-deadlock-detection)
                           (test-session-kill-and-termination)))))))
