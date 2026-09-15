(module asl-sh/tests
  :d "Verification suite for AgentScript process automation and piping (d-446d)."
  :x [runTests runTests!]
  :i [(asl-sh/process :a proc)
      (asl-sh/log     :a log)
      (reducer      :a red)])

(df testCommandBuilder [] -> Bool
  :d "Verifies command constructor and field setters."
  (let [(c (proc/cmd "git" (list "status" "-s")))
        (c2 (proc/withTimeout c 2500))]
    (assert (= (.-bin c) "git") "cmd bin git")
    (assert (= (.-timeoutMs c2) 2500) "timeout 2500")
    true))

(df testLogFormatter [] -> Bool
  :d "Verifies log entry rendering."
  (let [(entry (log/LogEntry
                 :level (log/info)
                 :message "Process started"
                 :timestamp 1700000000
                 :subsystem "worker"))
        (formatted (log/formatEntry entry))]
    (refute (string-empty? formatted) "formatted log not empty")
    (assert (string-contains? formatted "Process started") "formatted log contains message")
    true))

(df testReducerIntegration [] -> Bool
  :d "Verifies stream reducer defaults and execution."
  (let [(cfg (red/defaultConfig))
        (stream (red/reduceText "test line"))]
    (assert (= (.-headLimit cfg) 500) "head limit 500")
    (assert (= (.-reducedLineCount stream) 1) "reduced line count 1")
    true))

(df runTests [] -> Bool
  :d "Runs all validation checks for asl-sh."
  (do
    (assert (testCommandBuilder) "test-command-builder must pass")
    (assert (testLogFormatter) "test-log-formatter must pass")
    (assert (testReducerIntegration) "test-reducer-integration must pass")
    true))

(df ! runTests! [] -> (Result Unit String)
  :d "Runs all validation checks for asl-sh."
  (if (runTests)
      (ok ())
      (err "asl-sh tests failed")))
