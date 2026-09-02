(module asl-sh
  :d "AgentScript Shell & Process Automation Engine: Subprocess execution, pipelines & logging (@pcp:d-446d)."
  :x [run-cmd! run-pipeline! log-info! log-warn! log-err!]
  :i [(core/process :a proc)
           (core/pipe    :a pipe)
           (core/log     :a log)])

(df ! run-cmd! [(bin String) (args (List String))] -> (Result String proc/ProcessError)
  :d "Executes a safe vector command and returns standard output."
  (proc/run-simple! bin args))

(df ! run-pipeline! [(stages (List proc/ProcessCmd))] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Executes a multi-stage process pipeline."
  (pipe/pipe! (pipe/make-pipeline stages)))

(df ! log-info! [(subsystem String) (message String)] -> Unit
  :d "Logs informational message to standard log stream."
  (log/info! subsystem message))

(df ! log-warn! [(subsystem String) (message String)] -> Unit
  :d "Logs warning message to standard log stream."
  (log/warn! subsystem message))

(df ! log-err! [(subsystem String) (message String)] -> Unit
  :d "Logs error message to standard error stream."
  (log/err! subsystem message))
