(module asl-sh
  :d "AgentScript Shell & Process Automation Engine: Subprocess execution, pipelines & logging (@pcp:d-446d)."
  :x [run-cmd! exec-receipt! run-pipeline! log-info! log-warn! log-err!]
  :i [(asl-sh/process :a proc)
      (asl-sh/pipe    :a pipe)
      (asl-sh/log     :a log)
      (reducer      :a red)
      (spool        :a spool)
      (watchdog     :a wd)
      (apm          :a apm)])

(df ! exec-receipt! [(c proc/ProcessCmd)] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a typed ProcessCmd and demuxes output into a compact ProcessReceipt with two-tier spooling and watchdog guards."
  (mt (proc/exec! c)
    ((ok out)
     (let [(spool-path (red/generate-spool-path (.-bin c) (.-duration-ms out)))
           (demuxer (apm/make-oob-demuxer spool-path 67108864))
           (demuxed (if (string-empty? (.-stdout out))
                        demuxer
                        (apm/oob-demux-chunk demuxer (.-stdout out))))
           (rss-verdict (wd/check-rss-ceiling 0 512))
           (deadlock-verdict (wd/detect-deadlock 0 10000))
           (bound-port (let [(pv (wd/detect-bound-port (.-stdout out)))]
                         (if (.-detected pv) (some (.-port pv)) (none))))
           (_ (mt bound-port
                ((some p) (log/info! "asl-sh" (str ":port-bound " (string-from-int64 p))))
                ((none) ())))
           (receipt (apm/oob-demux-finish demuxed (.-exit-code out) (.-duration-ms out)))]
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
