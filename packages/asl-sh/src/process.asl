(module asl-sh/process
  :d "Pure AgentScript process supervision modular aliases and core process API delegation."
  :x [status
      list
      proc-status
      proc-list
      proc/status
      proc/list
      cmd
      with-cwd
      with-timeout
      with-stdin
      exec!
      run-simple!
      session-spawn!
      session-send-input!
      session-input!
      session-poll-tail!
      session-tail!
      session-emit-stdout!
      session-emit-stderr!
      session-kill!
      session-check-deadlock
      session-step-watchdog!
      session-tick-idle
      session-extend-timeout
      session-set-timeout
      make-process-receipt
      render-receipt
      estimate-tokens
      receipt-tokens]
  :i [(core/process :a cp)
      (apm :a apm)])

(df status [(elapsed-ms I64) (deadline-ms I64) (op-name Str)] -> apm/SupervisorVerdict
  :d "1-to-2 token alias for process supervision step status."
  (apm/supervise-step elapsed-ms deadline-ms op-name))

(df list [(entries (List apm/DaemonEntry))] -> Str
  :d "1-to-2 token alias for formatting supervised process table list."
  (apm/format-daemon-table entries))

(df proc-status [(elapsed-ms I64) (deadline-ms I64) (op-name Str)] -> apm/SupervisorVerdict
  :d "Compatibility alias for proc/status."
  (apm/supervise-step elapsed-ms deadline-ms op-name))

(df proc-list [(entries (List apm/DaemonEntry))] -> Str
  :d "Compatibility alias for proc/list."
  (apm/format-daemon-table entries))

(df proc/status [(elapsed-ms I64) (deadline-ms I64) (op-name Str)] -> apm/SupervisorVerdict
  :d "Modular alias for proc/status."
  (apm/supervise-step elapsed-ms deadline-ms op-name))

(df proc/list [(entries (List apm/DaemonEntry))] -> Str
  :d "Modular alias for proc/list."
  (apm/format-daemon-table entries))

(df cmd [(bin String) (args (List String))] -> cp/ProcessCmd
  :d "Constructs a safe, typed command with an argument vector."
  (cp/cmd bin args))

(df with-cwd [(c cp/ProcessCmd) (dir String)] -> cp/ProcessCmd
  :d "Sets the execution working directory."
  (cp/with-cwd c dir))

(df with-timeout [(c cp/ProcessCmd) (ms Int64)] -> cp/ProcessCmd
  :d "Sets the execution timeout in milliseconds."
  (cp/with-timeout c ms))

(df with-stdin [(c cp/ProcessCmd) (input String)] -> cp/ProcessCmd
  :d "Sets standard input data for the process."
  (cp/with-stdin c input))

(df ! exec! [(c cp/ProcessCmd)] -> (Result cp/ProcessOutput cp/ProcessError)
  :d "Executes a typed process command with timeout enforcement and captured output."
  (cp/exec! c))

(df ! run-simple! [(bin String) (args (List String))] -> (Result String cp/ProcessError)
  :d "Quick helper to run a command and return trimmed stdout on success."
  (cp/run-simple! bin args))

(df ! session-spawn! [(id String) (c cp/ProcessCmd)] -> cp/ProcessSession
  :d "Initializes an interactive process session bound to a ProcessCmd."
  (cp/session-spawn! id c))

(df ! session-send-input! [(s cp/ProcessSession) (input String)] -> cp/ProcessSession
  :d "Injects standard input data into an active session resetting idle timer."
  (cp/session-send-input! s input))

(df ! session-input! [(s cp/ProcessSession) (input String)] -> cp/ProcessSession
  :d "Short alias for session-send-input!."
  (cp/session-input! s input))

(df session-poll-tail! [(s cp/ProcessSession) (n Int64)] -> (List String)
  :d "Retrieves the trailing n lines from the session stdout buffer."
  (cp/session-poll-tail! s n))

(df session-tail! [(s cp/ProcessSession) (n Int64)] -> (List String)
  :d "Short alias for session-poll-tail!."
  (cp/session-tail! s n))

(df ! session-emit-stdout! [(s cp/ProcessSession) (line String)] -> cp/ProcessSession
  :d "Appends a line of captured stdout to session buffer and resets idle timer."
  (cp/session-emit-stdout! s line))

(df ! session-emit-stderr! [(s cp/ProcessSession) (line String)] -> cp/ProcessSession
  :d "Appends a line of captured stderr to session buffer."
  (cp/session-emit-stderr! s line))

(df ! session-kill! [(s cp/ProcessSession) (sig String)] -> cp/ProcessSession
  :d "Terminates an interactive session with the specified signal, defaulting to SIGKILL."
  (let [(effective-sig (if (or (nil? sig) (string-empty? sig)) "SIGKILL" sig))]
    (cp/session-kill! s effective-sig)))

(df session-check-deadlock [(s cp/ProcessSession) (idle-ceiling Int64)] -> cp/ProcessSession
  :d "Audits session idle duration against deadlock ceiling setting deadlock flag if breached."
  (let [(res (cp/session-check-deadlock s idle-ceiling))]
    (cp/ProcessSession
      :id (.-id res)
      :pid (.-pid res)
      :state (.-state res)
      :cmd (.-cmd res)
      :stdin-buffer (.-stdin-buffer res)
      :stdout-buffer (.-stdout-buffer res)
      :stderr-buffer (.-stderr-buffer res)
      :exit-code (.-exit-code res)
      :idle-ms (.-idle-ms res)
      :timeout-ms (.-timeout-ms res)
      :deadlock-detected (.-deadlock-detected res)
      :deadlocked (.-deadlock-detected res)
      :term-deadline-ms (.-term-deadline-ms res)
      :kill-deadline-ms (.-kill-deadline-ms res)
      :termination-receipt (.-termination-receipt res))))

(df ! session-step-watchdog! [(s cp/ProcessSession) (delta-ms Int64) (spool-path String)] -> cp/ProcessSession
  :d "Advances idle timer and enforces two-stage stdin deadlock watchdog escalation."
  (cp/session-step-watchdog! s delta-ms spool-path))

(df session-tick-idle [(s cp/ProcessSession) (delta-ms Int64)] -> cp/ProcessSession
  :d "Advances session idle duration counter by elapsed milliseconds."
  (let [(res (cp/session-tick-idle s delta-ms))
        (ceiling (if (> (.-timeout-ms s) 10000) (.-timeout-ms s) 10000))
        (is-deadlocked (>= (.-idle-ms res) ceiling))]
    (cp/ProcessSession
      :id (.-id res)
      :pid (.-pid res)
      :state (if is-deadlocked "idle" (.-state res))
      :cmd (.-cmd res)
      :stdin-buffer (.-stdin-buffer res)
      :stdout-buffer (.-stdout-buffer res)
      :stderr-buffer (.-stderr-buffer res)
      :exit-code (.-exit-code res)
      :idle-ms (.-idle-ms res)
      :timeout-ms (.-timeout-ms res)
      :deadlock-detected is-deadlocked
      :deadlocked is-deadlocked
      :term-deadline-ms (.-term-deadline-ms res)
      :kill-deadline-ms (.-kill-deadline-ms res)
      :termination-receipt (.-termination-receipt res))))

(df session-extend-timeout [(s cp/ProcessSession) (extend-ms Int64)] -> cp/ProcessSession
  :d "Dynamically extends watchdog timeout ceiling on active session resetting idle timer."
  (cp/session-extend-timeout s extend-ms))

(df session-set-timeout [(s cp/ProcessSession) (new-ms Int64)] -> cp/ProcessSession
  :d "Explicitly updates watchdog timeout ceiling on active session resetting idle timer."
  (cp/session-set-timeout s new-ms))

(df make-process-receipt [(exit-code Int64) (duration-ms Int64) (peak-rss-mb Int64) (spool-path String) (summary String)] -> cp/ProcessReceipt
  :d "Constructs a compact ProcessReceipt."
  (cp/make-process-receipt exit-code duration-ms peak-rss-mb spool-path summary))

(df render-receipt [(r cp/ProcessReceipt)] -> String
  :d "Renders a ProcessReceipt as a compact S-expression string."
  (cp/render-receipt r))

(df estimate-tokens [(text String)] -> Int64
  :d "Deterministic BPE proxy token count estimation based on character length."
  (cp/estimate-tokens text))

(df receipt-tokens [(r cp/ProcessReceipt)] -> Int64
  :d "Estimates total BPE tokens for a rendered ProcessReceipt."
  (cp/receipt-tokens r))
