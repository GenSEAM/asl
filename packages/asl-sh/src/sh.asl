(module asl-sh
  :d "AgentScript Shell & Process Automation Engine: Subprocess execution, pipelines & logging (d-446d)."
  :x [runCmd! execReceipt! runPipeline! logInfo! logWarn! logErr!]
  :i [(asl-sh/process :a proc)
      (asl-sh/pipe    :a pipe)
      (asl-sh/log     :a log)
      (reducer      :a red)
      (spool        :a spool)
      (watchdog     :a wd)
      (apm          :a apm)])

(df ! execReceipt! [(c proc/ProcessCmd)] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a typed ProcessCmd and demuxes output into a compact ProcessReceipt with two-tier spooling and watchdog guards."
  (mt (proc/exec! c)
    ((ok out)
     (let [(spoolPath (red/generateSpoolPath (.-bin c) (.-durationMs out)))
           (demuxer (apm/makeOobDemuxer spoolPath 67108864))
           (demuxed (if (string-empty? (.-stdout out))
                        demuxer
                        (apm/oobDemuxChunk demuxer (.-stdout out))))
           (rssVerdict (wd/checkRssCeiling 0 512))
           (deadlockVerdict (wd/detectDeadlock 0 10000))
           (boundPort (let [(pv (wd/detectBoundPort (.-stdout out)))]
                         (if (.-detected pv) (some (.-port pv)) (none))))
           (_ (mt boundPort
                ((some p) (log/info! "asl-sh" (str ":port-bound " (string-from-int64 p))))
                ((none) ())))
           (receipt (apm/oobDemuxFinish demuxed (.-exitCode out) (.-durationMs out)))]
       (ok receipt)))
    ((err e) (err e))))

(df ! runCmd! [(bin String) (args (List String))] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a command and returns a compact semantic ProcessReceipt (<80 tokens)."
  (execReceipt! (proc/cmd bin args)))

(df ! runPipeline! [(stages (List proc/ProcessCmd))] -> (Result proc/ProcessOutput proc/ProcessError)
  :d "Executes a multi-stage process pipeline."
  (pipe/pipe! (pipe/makePipeline stages)))

(df ! logInfo! [(subsystem String) (message String)] -> Unit
  :d "Logs informational message to standard log stream."
  (log/info! subsystem message))

(df ! logWarn! [(subsystem String) (message String)] -> Unit
  :d "Logs warning message to standard log stream."
  (log/warn! subsystem message))

(df ! logErr! [(subsystem String) (message String)] -> Unit
  :d "Logs error message to standard error stream."
  (log/err! subsystem message))
