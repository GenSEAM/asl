(module asl-sh/tests
  :d "Verification suite for AgentScript process automation and piping (@pcp:d-446d)."
  :x [run-tests!]
  :i [(core/process :a proc)
      (core/log     :a log)
      (reducer      :a red)])

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
    (not (string-empty? formatted))))

(df test-reducer-integration [] -> Bool
  :d "Verifies stream reducer defaults and execution."
  (let [(cfg (red/default-config))
        (stream (red/reduce-text "test line"))]
    (and (= (.-head-limit cfg) 500)
         (= (.-reduced-line-count stream) 1))))

(df ! run-tests! [] -> (Result Unit String)
  :d "Runs all validation checks for asl-sh."
  (if (and (test-command-builder)
           (and (test-log-formatter)
                (test-reducer-integration)))
      (ok ())
      (err "asl-sh tests failed")))
