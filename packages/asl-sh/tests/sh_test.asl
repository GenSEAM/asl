(module asl-sh/tests
  :d "Verification suite for AgentScript process automation and piping (@pcp:d-446d)."
  :x [run-tests run-tests!]
  :i [(asl-sh/process :a proc)
      (asl-sh/log     :a log)
      (reducer      :a red)])

(df test-command-builder [] -> Bool
  :d "Verifies command constructor and field setters."
  (let [(c (proc/cmd "git" (list "status" "-s")))
        (c2 (proc/with-timeout c 2500))]
    (assert (= (.-bin c) "git") "cmd bin git")
    (assert (= (.-timeout-ms c2) 2500) "timeout 2500")
    true))

(df test-log-formatter [] -> Bool
  :d "Verifies log entry rendering."
  (let [(entry (log/LogEntry
                 :level (log/info)
                 :message "Process started"
                 :timestamp 1700000000
                 :subsystem "worker"))
        (formatted (log/format-entry entry))]
    (assert (not (string-empty? formatted)) "formatted log not empty")
    (assert (string-contains? formatted "Process started") "formatted log contains message")
    true))

(df test-reducer-integration [] -> Bool
  :d "Verifies stream reducer defaults and execution."
  (let [(cfg (red/default-config))
        (stream (red/reduce-text "test line"))]
    (assert (= (.-head-limit cfg) 500) "head limit 500")
    (assert (= (.-reduced-line-count stream) 1) "reduced line count 1")
    true))

(df run-tests [] -> Bool
  :d "Runs all validation checks for asl-sh."
  (do
    (assert (test-command-builder) "test-command-builder must pass")
    (assert (test-log-formatter) "test-log-formatter must pass")
    (assert (test-reducer-integration) "test-reducer-integration must pass")
    true))

(df ! run-tests! [] -> (Result Unit String)
  :d "Runs all validation checks for asl-sh."
  (if (run-tests)
      (ok ())
      (err "asl-sh tests failed")))
