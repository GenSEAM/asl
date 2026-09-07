(module asl-sh
  :d "AgentScript Shell & Process Automation Engine: Subprocess execution, pipelines & logging (@pcp:d-446d)."
  :x [run-cmd! exec-receipt! run-pipeline! log-info! log-warn! log-err!]
  :i [(core/process :a proc)
      (core/pipe    :a pipe)
      (core/log     :a log)
      (reducer      :a red)])

(df ! exec-receipt! [(c proc/ProcessCmd)] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a typed ProcessCmd and demuxes output into a compact ProcessReceipt."
  (mt (proc/exec! c)
    ((ok out)
     (let [(spool (red/generate-spool-path (.-bin c) (.-duration-ms out)))
           (receipt (red/demux-stream (.-stdout out) (.-stderr out) (.-exit-code out) (.-duration-ms out) spool))]
       (ok receipt)))
    ((err e) (err e))))

(df ! run-cmd! [(bin String) (args (List String))] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a command and returns a compact semantic ProcessReceipt (<80 tokens)."
  (exec-receipt! (proc/cmd bin args)))

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
