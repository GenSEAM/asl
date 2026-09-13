(module asl-sh/process
  :d "Pure AgentScript process supervision modular aliases and core process API delegation."
  :x [status
      list
      procStatus
      procList
      proc/status
      proc/list
      cmd
      withCwd
      withTimeout
      withStdin
      exec!
      runSimple!
      sessionSpawn!
      sessionSendInput!
      sessionInput!
      sessionPollTail!
      sessionTail!
      sessionEmitStdout!
      sessionEmitStderr!
      sessionKill!
      sessionCheckDeadlock
      sessionStepWatchdog!
      sessionTickIdle
      sessionExtendTimeout
      sessionSetTimeout
      makeProcessReceipt
      renderReceipt
      receiptTokens]
  :i [(asl-sh/coreProcess :a cp)
      (apm :a apm)])

(df status [(elapsedMs I64) (deadlineMs I64) (opName Str)] -> apm/SupervisorVerdict
  :d "1-to-2 token alias for process supervision step status."
  (apm/superviseStep elapsedMs deadlineMs opName))

(df list [(entries (List apm/DaemonEntry))] -> Str
  :d "1-to-2 token alias for formatting supervised process table list."
  (apm/formatDaemonTable entries))

(df procStatus [(elapsedMs I64) (deadlineMs I64) (opName Str)] -> apm/SupervisorVerdict
  :d "Compatibility alias for proc/status."
  (apm/superviseStep elapsedMs deadlineMs opName))

(df procList [(entries (List apm/DaemonEntry))] -> Str
  :d "Compatibility alias for proc/list."
  (apm/formatDaemonTable entries))

(df proc/status [(elapsedMs I64) (deadlineMs I64) (opName Str)] -> apm/SupervisorVerdict
  :d "Modular alias for proc/status."
  (apm/superviseStep elapsedMs deadlineMs opName))

(df proc/list [(entries (List apm/DaemonEntry))] -> Str
  :d "Modular alias for proc/list."
  (apm/formatDaemonTable entries))

(df cmd [(bin String) (args (List String))] -> cp/ProcessCmd
  :d "Constructs a safe, typed command with an argument vector."
  (cp/cmd bin args))

(df withCwd [(c cp/ProcessCmd) (dir String)] -> cp/ProcessCmd
  :d "Sets the execution working directory."
  (cp/withCwd c dir))

(df withTimeout [(c cp/ProcessCmd) (ms Int64)] -> cp/ProcessCmd
  :d "Sets the execution timeout in milliseconds."
  (cp/withTimeout c ms))

(df withStdin [(c cp/ProcessCmd) (input String)] -> cp/ProcessCmd
  :d "Sets standard input data for the process."
  (cp/withStdin c input))

(df ! exec! [(c cp/ProcessCmd)] -> (Result cp/ProcessOutput cp/ProcessError)
  :d "Executes a typed process command with timeout enforcement and captured output."
  (cp/exec! c))

(df ! runSimple! [(bin String) (args (List String))] -> (Result String cp/ProcessError)
  :d "Quick helper to run a command and return trimmed stdout on success."
  (cp/runSimple! bin args))

(df ! sessionSpawn! [(id String) (c cp/ProcessCmd)] -> cp/ProcessSession
  :d "Initializes an interactive process session bound to a ProcessCmd."
  (cp/sessionSpawn! id c))

(df ! sessionSendInput! [(s cp/ProcessSession) (input String)] -> cp/ProcessSession
  :d "Injects standard input data into an active session resetting idle timer."
  (cp/sessionSendInput! s input))

(df ! sessionInput! [(s cp/ProcessSession) (input String)] -> cp/ProcessSession
  :d "Short alias for session-send-input!."
  (cp/sessionInput! s input))

(df sessionPollTail! [(s cp/ProcessSession) (n Int64)] -> (List String)
  :d "Retrieves the trailing n lines from the session stdout buffer."
  (cp/sessionPollTail! s n))

(df sessionTail! [(s cp/ProcessSession) (n Int64)] -> (List String)
  :d "Short alias for session-poll-tail!."
  (cp/sessionTail! s n))

(df ! sessionEmitStdout! [(s cp/ProcessSession) (line String)] -> cp/ProcessSession
  :d "Appends a line of captured stdout to session buffer and resets idle timer."
  (cp/sessionEmitStdout! s line))

(df ! sessionEmitStderr! [(s cp/ProcessSession) (line String)] -> cp/ProcessSession
  :d "Appends a line of captured stderr to session buffer."
  (cp/sessionEmitStderr! s line))

(df ! sessionKill! [(s cp/ProcessSession) (sig String)] -> cp/ProcessSession
  :d "Terminates an interactive session with the specified signal, defaulting to SIGKILL."
  (let [(effectiveSig (if (or (nil? sig) (string-empty? sig)) "SIGKILL" sig))]
    (cp/sessionKill! s effectiveSig)))

(df sessionCheckDeadlock [(s cp/ProcessSession) (idleCeiling Int64)] -> cp/ProcessSession
  :d "Audits session idle duration against deadlock ceiling setting deadlock flag if breached."
  (let [(res (cp/sessionCheckDeadlock s idleCeiling))]
    (cp/ProcessSession
      :id (.-id res)
      :pid (.-pid res)
      :state (.-state res)
      :cmd (.-cmd res)
      :stdinBuffer (.-stdinBuffer res)
      :stdoutBuffer (.-stdoutBuffer res)
      :stderrBuffer (.-stderrBuffer res)
      :exitCode (.-exitCode res)
      :idleMs (.-idleMs res)
      :timeoutMs (.-timeoutMs res)
      :deadlockDetected (.-deadlockDetected res)
      :deadlocked (.-deadlockDetected res)
      :termDeadlineMs (.-termDeadlineMs res)
      :killDeadlineMs (.-killDeadlineMs res)
      :terminationReceipt (.-terminationReceipt res))))

(df ! sessionStepWatchdog! [(s cp/ProcessSession) (deltaMs Int64) (spoolPath String)] -> cp/ProcessSession
  :d "Advances idle timer and enforces two-stage stdin deadlock watchdog escalation."
  (cp/sessionStepWatchdog! s deltaMs spoolPath))

(df sessionTickIdle [(s cp/ProcessSession) (deltaMs Int64)] -> cp/ProcessSession
  :d "Advances session idle duration counter by elapsed milliseconds."
  (let [(res (cp/sessionTickIdle s deltaMs))
        (ceiling (if (> (.-timeoutMs s) 10000) (.-timeoutMs s) 10000))
        (isDeadlocked (>= (.-idleMs res) ceiling))]
    (cp/ProcessSession
      :id (.-id res)
      :pid (.-pid res)
      :state (if isDeadlocked "idle" (.-state res))
      :cmd (.-cmd res)
      :stdinBuffer (.-stdinBuffer res)
      :stdoutBuffer (.-stdoutBuffer res)
      :stderrBuffer (.-stderrBuffer res)
      :exitCode (.-exitCode res)
      :idleMs (.-idleMs res)
      :timeoutMs (.-timeoutMs res)
      :deadlockDetected isDeadlocked
      :deadlocked isDeadlocked
      :termDeadlineMs (.-termDeadlineMs res)
      :killDeadlineMs (.-killDeadlineMs res)
      :terminationReceipt (.-terminationReceipt res))))

(df sessionExtendTimeout [(s cp/ProcessSession) (extendMs Int64)] -> cp/ProcessSession
  :d "Dynamically extends watchdog timeout ceiling on active session resetting idle timer."
  (cp/sessionExtendTimeout s extendMs))

(df sessionSetTimeout [(s cp/ProcessSession) (newMs Int64)] -> cp/ProcessSession
  :d "Explicitly updates watchdog timeout ceiling on active session resetting idle timer."
  (cp/sessionSetTimeout s newMs))

(df makeProcessReceipt [(exitCode Int64) (durationMs Int64) (peakRssMb Int64) (spoolPath String) (summary String)] -> cp/ProcessReceipt
  :d "Constructs a compact ProcessReceipt."
  (cp/makeProcessReceipt exitCode durationMs peakRssMb spoolPath summary))

(df renderReceipt [(r cp/ProcessReceipt)] -> String
  :d "Renders a ProcessReceipt as a compact S-expression string."
  (cp/renderReceipt r))

(df receiptTokens [(r cp/ProcessReceipt)] -> Int64
  :d "Estimates total BPE tokens for a rendered ProcessReceipt."
  (cp/receiptTokens r))
