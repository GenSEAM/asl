(module asl-sh/tests
  :d "Verification suite for AgentScript process automation and piping (@pcp:d-446d)."
  :x [run-tests!]
  :i [(core/process :a proc)
           (core/log     :a log)])

(df test-command-builder [] -> Bool
  :d "Verifies command constructor and field setters."
  (let [(c (proc/cmd "git" (list "status" "-s")))
        (c2 (proc/with-timeout c 2500))]
    (and (= (.-bin c) "git")
         (= (.-timeout-ms c2) 2500))))

(df test-log-formatter [] -> Bool
  :d "Verifies log entry rendering."
  (let [(entry (log/LogEntry
                 :level (log/info)
                 :message "Process started"
                 :timestamp 1700000000
                 :subsystem "worker"))
        (formatted (log/format-entry entry))]
    (> (string-length formatted) 0)))

(df ! run-tests! [] -> (Result Unit String)
  :d "Runs all validation checks for asl-sh."
  (if (and (test-command-builder)
           (test-log-formatter))
      (ok ())
      (err "asl-sh tests failed")))
