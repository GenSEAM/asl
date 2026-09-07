(module asl-sh
  :d "AgentScript Shell & Process Automation Engine: Subprocess execution, pipelines & logging (@pcp:d-446d)."
  :x [run-cmd! exec-receipt! run-pipeline! log-info! log-warn! log-err!]
  :i [(core/process :a proc)
      (core/pipe    :a pipe)
      (core/log     :a log)
      (reducer      :a red)
      (spool        :a spool)
      (watchdog     :a wd)])

(df ! exec-receipt! [(c proc/ProcessCmd)] -> (Result proc/ProcessReceipt proc/ProcessError)
  :d "Executes a typed ProcessCmd and demuxes output into a compact ProcessReceipt with two-tier spooling and watchdog guards."
  (mt (proc/exec! c)
    ((ok out)
     (let [(spool-path (red/generate-spool-path (.-bin c) (.-duration-ms out)))
           (tt-spool (spool/make-two-tier-spool spool-path 200 10485760))
           (out-lines (if (string-empty? (.-stdout out)) (list) (string-split (.-stdout out) "\n")))
           (spooled (fold (fn [(st spool/TwoTierSpool) (ln String)] -> spool/TwoTierSpool (spool/two-tier-push st ln)) tt-spool out-lines))
           (rss-verdict (wd/check-rss-ceiling 0 512))
           (deadlock-verdict (wd/detect-deadlock 0 10000))
           (bound-port (fold (fn [(acc (Option Int64)) (ln String)] -> (Option Int64)
                               (mt acc
                                 ((some _) acc)
                                 ((none)
                                  (let [(pv (wd/detect-bound-port ln))]
                                    (if (.-detected pv)
                                        (some (.-port pv))
                                        (none))))))
                             (none)
                             out-lines))
           (_ (mt bound-port
                ((some p) (log/info! "asl-sh" (str ":port-bound " (string-from-int64 p))))
                ((none) ())))
           (closed-spool (spool/two-tier-close spooled))
           (base-receipt (red/demux-stream (.-stdout out) (.-stderr out) (.-exit-code out) (.-duration-ms out) (.-path (.-disk closed-spool))))
           (final-summary (if (.-exceeded rss-verdict)
                              (str (.-summary base-receipt) " :oom-killed")
                              (.-summary base-receipt)))
           (receipt (proc/make-process-receipt
                      (.-exit-code base-receipt)
                      (.-duration-ms base-receipt)
                      (.-peak-rss-mb base-receipt)
                      (.-spool-path base-receipt)
                      final-summary))]
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
