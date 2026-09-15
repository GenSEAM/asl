(module asl-sh/coreProcess
  :d "Native AgentScript Process Execution and Typed Command Builder (d-446d)."
  :x [ProcessCmd
      ProcessOutput
      ProcessError
      ProcessReceipt
      ProcessSession
      cmd
      withCwd
      withTimeout
      withStdin
      withEnv
      buildShellCmd
      exec!
      runSimple!
      sessionSpawn!
      sessionSpawnWithPid!
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
      receiptTokens
]
  :i [(asl-text/text :a txt)])

(dfs ProcessCmd
  (:f bin        String              "Executable binary path or system command")
  (:f args       (List String)       "Explicit argument vector preventing shell injection")
  (:f env        (Map String String) "Environment variable overrides")
  (:f cwd        (Option String)     "Working directory for process execution")
  (:f timeoutMs Int64               "Execution timeout deadline in milliseconds" :default 5000)
  (:f stdinData (Option String)     "Optional input string piped to process stdin"))

(dfs ProcessOutput
  (:f exitCode   Int64  "Process exit status (0 = success)")
  (:f stdout      String "Captured standard output stream")
  (:f stderr      String "Captured standard error stream")
  (:f durationMs Int64  "Execution elapsed time in milliseconds"))

(dfs ProcessReceipt
  (:f exitCode   Int64  "Process return code (0 = success)")
  (:f durationMs Int64  "Execution duration in milliseconds")
  (:f peakRssMb Int64  "Peak memory resident set size in megabytes")
  (:f spoolPath  String "Filesystem path to ephemeral disk spool")
  (:f summary     String "Compact diagnostic string (<100 tokens, errors only)"))

(dfs ProcessSession
  (:f id String "Unique session identifier e.g. sess-1")
  (:f pid Int64 "Operating system process identifier")
  (:f state String "Session lifecycle state: active, idle, or terminated")
  (:f cmd ProcessCmd "Underlying command specification")
  (:f stdinBuffer (List String) "Pending or injected standard input lines")
  (:f stdoutBuffer (List String) "Captured standard output lines in FIFO order")
  (:f stderrBuffer (List String) "Captured standard error lines in FIFO order")
  (:f exitCode (Option Int64) "Termination exit status code if finished")
  (:f idleMs Int64 "Milliseconds elapsed since last stdin or stdout event")
  (:f timeoutMs Int64 "Configurable watchdog timeout ceiling in milliseconds")
  (:f deadlockDetected Bool "True if process reached idle deadlock threshold")
  (:f deadlocked Bool "Alias for deadlock-detected")
  (:f termDeadlineMs Int64 "Configured SIGTERM deadlock ceiling in milliseconds (default 10000)")
  (:f killDeadlineMs Int64 "Configured SIGKILL deadlock ceiling in milliseconds (default 12000)")
  (:f terminationReceipt (Option ProcessReceipt) "Structured teardown receipt on watchdog termination"))

(dfe ProcessError
  (:c not-found         [(bin String)]              "Command binary was not found")
  (:c timeout           [(ms Int64)]                "Command execution timed out")
  (:c permission-denied [(path String)]             "Access permission denied to executable")
  (:c executionFailed  [(code Int64) (msg String)] "Process exited with non-zero status"))

(df cmd [(bin String) (args (List String))] -> ProcessCmd
  :d "Constructs a safe, typed command with an argument vector."
  (ProcessCmd
    :bin bin
    :args args
    :env (map-empty)
    :cwd (none)
    :timeoutMs 5000
    :stdinData (none)))

(df withCwd [(c ProcessCmd) (dir String)] -> ProcessCmd
  :d "Sets the execution working directory."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (some dir)
    :timeoutMs (.-timeoutMs c)
    :stdinData (.-stdinData c)))

(df withTimeout [(c ProcessCmd) (ms Int64)] -> ProcessCmd
  :d "Sets the execution timeout in milliseconds."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (.-cwd c)
    :timeoutMs ms
    :stdinData (.-stdinData c)))

(df withStdin [(c ProcessCmd) (input String)] -> ProcessCmd
  :d "Sets standard input data for the process."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (.-cwd c)
    :timeoutMs (.-timeoutMs c)
    :stdinData (some input)))

(df withEnv [(c ProcessCmd) (k String) (v String)] -> ProcessCmd
  :d "Sets or overrides an environment variable."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (map-set (.-env c) k v)
    :cwd (.-cwd c)
    :timeoutMs (.-timeoutMs c)
    :stdinData (.-stdinData c)))

(df quoteShellArg [(arg String)] -> String
  (str "'" (string-replace arg "'" "'\\''") "'"))

(df stripTrailingNewline [(s String)] -> String
  (if (string-ends-with? s "\n")
    (option-or (string-slice s 0 (- (string-length s) 1)) s)
    s))

(df formatTimeoutSeconds [(ms Int64)] -> String
  (let [(sec (/ ms 1000))
        (fraction (mod (/ ms 100) 10))]
    (if (< ms 1000)
        (str "0." (string-from-int64 (/ ms 100)))
        (if (> fraction 0)
            (str (string-from-int64 sec) "." (string-from-int64 fraction))
            (string-from-int64 sec)))))

(df buildShellCmd [(c ProcessCmd) (stdinPath String)] -> String
  :d "Constructs the full shell execution pipeline for a ProcessCmd with cwd, env, quoting, timeout, watchdog sentinel, and safe stdin."
  (let [(b (.-bin c))
        (args (.-args c))
        (quotedBin (quoteShellArg b))
        (quotedArgs (map quoteShellArg args))
        (baseCmd (if (list-empty? quotedArgs)
                     quotedBin
                     (str quotedBin " " (string-join " " quotedArgs))))
        (envKeys (map-keys (.-env c)))
        (envPrefix (if (list-empty? envKeys)
                       ""
                       (let [(entries (map (fn [(k String)] -> String
                                             (let [(v (option-or (map-get (.-env c) k) ""))]
                                               (str k "=" (quoteShellArg v))))
                                           envKeys))]
                         (str "env " (string-join " " entries) " "))))
        (cwdPrefix (mt (.-cwd c)
                     ((some d) (str "cd " (quoteShellArg d) " && "))
                     ((none) "")))
        (cmdWithEnv (str cwdPrefix envPrefix baseCmd))
        (stdinOpt (.-stdinData c))
        (stdinPart (mt stdinOpt
                     ((some s)
                      (if (string-empty? s)
                          "< /dev/null"
                          (str "< " (quoteShellArg stdinPath))))
                     ((none) "< /dev/null")))
        (innerCmd (str "( " cmdWithEnv " ) " stdinPart))
        (timeout (.-timeoutMs c))]
    (if (<= timeout 0)
        innerCmd
        (let [(tSec (formatTimeoutSeconds timeout))]
          (str "S=$(mktemp 2>/dev/null || echo /tmp/.asl_wd_sentinel_$$); rm -f $S; ( " innerCmd " ) & P=$!; (sleep " tSec " && touch $S && kill -9 $P 2>/dev/null) & W=$!; wait $P 2>/dev/null; R=$?; kill -9 $W 2>/dev/null; wait $W 2>/dev/null; if [ -f $S ]; then rm -f $S; exit 124; else rm -f $S; exit $R; fi")))))

(df buildShellCmdArgs [(b String) (args (List String)) (stdinVal String)] -> String
  :d "Legacy helper for buildShellCmd."
  (let [(c (ProcessCmd
             :bin b
             :args args
             :env (map-empty)
             :cwd (none)
             :timeoutMs 5000
             :stdinData (if (string-empty? stdinVal) (none) (some stdinVal))))]
    (buildShellCmd c "")))

(df ! exec! [(c ProcessCmd)] -> (Result ProcessOutput ProcessError)
  :d "Executes a typed process command with timeout enforcement and captured output."
  (let [(b (.-bin c))
        (timeoutMsVal (.-timeoutMs c))]
    (cond
      ((<= timeoutMsVal 0)
       (err (timeout timeoutMsVal)))
      (:else
       (let [(stdinOpt (.-stdinData c))
             (stdinRes (mt stdinOpt
                         ((some s)
                          (if (string-empty? s)
                              (ok "")
                              (let [(canon (pathCanonicalize "."))
                                    (root (mt canon ((ok r) r) ((err _) ".")))
                                    (tmpRes (execCmd "uuidgen"))
                                    (uuid (stripTrailingNewline (.-stdout tmpRes)))
                                    (relPath (str "tmp/.asl_proc_stdin_" uuid ".tmp"))
                                    (absPath (str root "/" relPath))
                                    (wRes (file-write relPath s))]
                                (mt wRes
                                  ((ok _) (ok absPath))
                                  ((err _) (err (executionFailed -1 "Failed to write stdin spool file")))))))
                         ((none) (ok ""))))]
         (mt stdinRes
           ((err e) (err e))
           ((ok stdinPath)
            (let [(fullCmd (buildShellCmd c stdinPath))
                  (res (execCmd fullCmd))
                  (code (.-exitCode res))
                  (cleanRes (if (not (string-empty? stdinPath))
                                (execCmd (str "rm -f " (quoteShellArg stdinPath)))
                                (:exitCode 0 :stdout "" :stderr "")))]
         (cond
           ((= code 124)
            (err (timeout timeoutMsVal)))
           ((= code 127)
            (err (not-found b)))
           ((= code 126)
            (err (permission-denied b)))
           (:else
            (ok (ProcessOutput
                  :exitCode code
                  :stdout (stripTrailingNewline (.-stdout res))
                  :stderr (stripTrailingNewline (.-stderr res))
                  :durationMs 1))))))))))))


(df runSimple! [(bin String) (args (List String))] -> (Result String ProcessError)
  :d "Quick helper to run a command and return trimmed stdout on success."
  (mt (exec! (cmd bin args))
    ((ok out)
     (if (= (.-exitCode out) 0)
         (ok (.-stdout out))
         (err (executionFailed (.-exitCode out) (.-stderr out)))))
    ((err e) (err e))))

(df makeProcessReceipt [(exitCode Int64) (durationMs Int64) (peakRssMb Int64) (spoolPath String) (summary String)] -> ProcessReceipt
  :d "Constructs a compact ProcessReceipt."
  (ProcessReceipt
    :exitCode exitCode
    :durationMs durationMs
    :peakRssMb peakRssMb
    :spoolPath spoolPath
    :summary summary))

(df renderReceipt [(r ProcessReceipt)] -> String
  :d "Renders a ProcessReceipt as a compact S-expression string."
  (str "(:proc-receipt :exit " (string-from-int64 (.-exitCode r))
       " :duration-ms " (string-from-int64 (.-durationMs r))
       " :peak-rss-mb " (string-from-int64 (.-peakRssMb r))
       " :spool-path \"" (.-spoolPath r) "\""
       " :summary \"" (.-summary r) "\")"))

(df receiptTokens [(r ProcessReceipt)] -> Int64
  :d "Estimates total BPE tokens for a rendered ProcessReceipt."
  (txt/estimateTokens (renderReceipt r)))

(df sessionSpawnWithPid! [(id String) (pid Int64) (c ProcessCmd)] -> ProcessSession
  :d "Initializes an interactive process session bound to a ProcessCmd with an explicit PID."
  (ProcessSession
    :id id
    :pid pid
    :state "active"
    :cmd c
    :stdinBuffer (list)
    :stdoutBuffer (list)
    :stderrBuffer (list)
    :exitCode (none)
    :idleMs 0
    :timeoutMs (.-timeoutMs c)
    :deadlockDetected false
    :termDeadlineMs 10000
    :killDeadlineMs 12000
    :terminationReceipt (none)))

(df sessionSpawn! [(id String) (c ProcessCmd)] -> ProcessSession
  :d "Initializes an interactive process session bound to a ProcessCmd."
  (sessionSpawnWithPid! id 1001 c))

(df sessionSendInput! [(s ProcessSession) (input String)] -> ProcessSession
  :d "Injects standard input data into an active session resetting idle timer."
  (if (= (.-state s) "terminated")
      s
      (ProcessSession
        :id (.-id s)
        :pid (.-pid s)
        :state "active"
        :cmd (.-cmd s)
        :stdinBuffer (list-append (.-stdinBuffer s) (list input))
        :stdoutBuffer (.-stdoutBuffer s)
        :stderrBuffer (.-stderrBuffer s)
        :exitCode (.-exitCode s)
        :idleMs 0
        :timeoutMs (.-timeoutMs s)
        :deadlockDetected false
        :termDeadlineMs (.-termDeadlineMs s)
        :killDeadlineMs (.-killDeadlineMs s)
        :terminationReceipt (.-terminationReceipt s))))

(df sessionInput! [(s ProcessSession) (input String)] -> ProcessSession
  :d "Short alias for session-send-input!."
  (sessionSendInput! s input))

(df sessionEmitStdout! [(s ProcessSession) (line String)] -> ProcessSession
  :d "Appends a line of captured stdout to session buffer and resets idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (if (= (.-state s) "terminated") "terminated" "active")
    :cmd (.-cmd s)
    :stdinBuffer (.-stdinBuffer s)
    :stdoutBuffer (list-append (.-stdoutBuffer s) (list line))
    :stderrBuffer (.-stderrBuffer s)
    :exitCode (.-exitCode s)
    :idleMs 0
    :timeoutMs (.-timeoutMs s)
    :deadlockDetected false
    :termDeadlineMs (.-termDeadlineMs s)
    :killDeadlineMs (.-killDeadlineMs s)
    :terminationReceipt (.-terminationReceipt s)))

(df sessionEmitStderr! [(s ProcessSession) (line String)] -> ProcessSession
  :d "Appends a line of captured stderr to session buffer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdinBuffer (.-stdinBuffer s)
    :stdoutBuffer (.-stdoutBuffer s)
    :stderrBuffer (list-append (.-stderrBuffer s) (list line))
    :exitCode (.-exitCode s)
    :idleMs 0
    :timeoutMs (.-timeoutMs s)
    :deadlockDetected false
    :termDeadlineMs (.-termDeadlineMs s)
    :killDeadlineMs (.-killDeadlineMs s)
    :terminationReceipt (.-terminationReceipt s)))

(df sessionPollTail! [(s ProcessSession) (n Int64)] -> (List String)
  :d "Retrieves the trailing n lines from the session stdout buffer."
  (let [(buf (.-stdoutBuffer s))
        (cnt (list-length buf))]
    (cond
      ((<= n 0) (list))
      ((>= n cnt) buf)
      (:else (option-or (list-slice buf (- cnt n) cnt) (list))))))

(df sessionTail! [(s ProcessSession) (n Int64)] -> (List String)
  :d "Short alias for session-poll-tail!."
  (sessionPollTail! s n))

(df sessionKill! [(s ProcessSession) (sig String)] -> ProcessSession
  :d "Terminates an interactive session with the specified signal."
  (let [(code (cond
                ((= sig "SIGHUP") 129)
                ((= sig "SIGINT") 130)
                ((= sig "SIGQUIT") 131)
                ((= sig "SIGKILL") 137)
                ((= sig "SIGUSR1") 138)
                ((= sig "SIGUSR2") 140)
                ((= sig "SIGPIPE") 141)
                ((= sig "SIGALRM") 142)
                ((= sig "SIGTERM") 143)
                (:else 137)))]
    (ProcessSession
      :id (.-id s)
      :pid (.-pid s)
      :state "terminated"
      :cmd (.-cmd s)
      :stdinBuffer (.-stdinBuffer s)
      :stdoutBuffer (.-stdoutBuffer s)
      :stderrBuffer (.-stderrBuffer s)
      :exitCode (some code)
      :idleMs (.-idleMs s)
      :timeoutMs (.-timeoutMs s)
      :deadlockDetected false
      :termDeadlineMs (.-termDeadlineMs s)
      :killDeadlineMs (.-killDeadlineMs s)
      :terminationReceipt (.-terminationReceipt s))))

(df sessionCheckDeadlock [(s ProcessSession) (idleCeiling Int64)] -> ProcessSession
  :d "Audits session idle duration against deadlock ceiling setting deadlock flag if breached."
  (let [(cap (if (<= idleCeiling 0)
               (if (<= (.-timeoutMs s) 0) 10000 (.-timeoutMs s))
               idleCeiling))
        (breached (>= (.-idleMs s) cap))]
    (ProcessSession
      :id (.-id s)
      :pid (.-pid s)
      :state (if (= (.-state s) "terminated") "terminated" (if breached "idle" "active"))
      :cmd (.-cmd s)
      :stdinBuffer (.-stdinBuffer s)
      :stdoutBuffer (.-stdoutBuffer s)
      :stderrBuffer (.-stderrBuffer s)
      :exitCode (.-exitCode s)
      :idleMs (.-idleMs s)
      :timeoutMs (.-timeoutMs s)
      :deadlockDetected breached
      :termDeadlineMs (.-termDeadlineMs s)
      :killDeadlineMs (.-killDeadlineMs s)
      :terminationReceipt (.-terminationReceipt s))))

(df sessionTickIdle [(s ProcessSession) (deltaMs Int64)] -> ProcessSession
  :d "Advances session idle duration counter by elapsed milliseconds."
  (let [(newIdle (+ (.-idleMs s) deltaMs))
        (ceiling (if (> (.-timeoutMs s) 10000) (.-timeoutMs s) 10000))
        (isDeadlocked (>= newIdle ceiling))]
    (ProcessSession
      :id (.-id s)
      :pid (.-pid s)
      :state (if isDeadlocked "idle" (.-state s))
      :cmd (.-cmd s)
      :stdinBuffer (.-stdinBuffer s)
      :stdoutBuffer (.-stdoutBuffer s)
      :stderrBuffer (.-stderrBuffer s)
      :exitCode (.-exitCode s)
      :idleMs newIdle
      :timeoutMs (.-timeoutMs s)
      :deadlockDetected isDeadlocked
      :termDeadlineMs (.-termDeadlineMs s)
      :killDeadlineMs (.-killDeadlineMs s)
      :terminationReceipt (.-terminationReceipt s))))

(df sessionExtendTimeout [(s ProcessSession) (extendMs Int64)] -> ProcessSession
  :d "Dynamically extends watchdog timeout ceiling on active session resetting idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdinBuffer (.-stdinBuffer s)
    :stdoutBuffer (.-stdoutBuffer s)
    :stderrBuffer (.-stderrBuffer s)
    :exitCode (.-exitCode s)
    :idleMs 0
    :timeoutMs (+ (.-timeoutMs s) extendMs)
    :deadlockDetected false
    :termDeadlineMs (+ (.-termDeadlineMs s) extendMs)
    :killDeadlineMs (+ (.-killDeadlineMs s) extendMs)
    :terminationReceipt (.-terminationReceipt s)))

(df sessionSetTimeout [(s ProcessSession) (newMs Int64)] -> ProcessSession
  :d "Explicitly updates watchdog timeout ceiling on active session resetting idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdinBuffer (.-stdinBuffer s)
    :stdoutBuffer (.-stdoutBuffer s)
    :stderrBuffer (.-stderrBuffer s)
    :exitCode (.-exitCode s)
    :idleMs 0
    :timeoutMs newMs
    :deadlockDetected false
    :termDeadlineMs newMs
    :killDeadlineMs (+ newMs 2000)
    :terminationReceipt (.-terminationReceipt s)))

(df sessionStepWatchdog! [(s ProcessSession) (deltaMs Int64) (spoolPath String)] -> ProcessSession
  :d "Advances idle timer and enforces two-stage stdin deadlock watchdog escalation (SIGTERM at 10s, SIGKILL at 12s)."
  (if (= (.-state s) "terminated")
      s
      (let [(newIdle (+ (.-idleMs s) deltaMs))
            (termLimit (.-termDeadlineMs s))
            (killLimit (.-killDeadlineMs s))]
        (cond
          ((>= newIdle killLimit)
           (let [(receipt (makeProcessReceipt 137 newIdle 0 spoolPath "Stdin deadlock watchdog: SIGKILL dispatched at 12s"))]
             (ProcessSession
               :id (.-id s)
               :pid (.-pid s)
               :state "terminated"
               :cmd (.-cmd s)
               :stdinBuffer (.-stdinBuffer s)
               :stdoutBuffer (.-stdoutBuffer s)
               :stderrBuffer (.-stderrBuffer s)
               :exitCode (some 137)
               :idleMs newIdle
               :timeoutMs (.-timeoutMs s)
               :deadlockDetected true
               :termDeadlineMs termLimit
               :killDeadlineMs killLimit
               :terminationReceipt (some receipt))))
          ((>= newIdle termLimit)
           (let [(receipt (makeProcessReceipt 143 newIdle 0 spoolPath "Stdin deadlock watchdog: SIGTERM dispatched at 10s"))]
             (ProcessSession
               :id (.-id s)
               :pid (.-pid s)
               :state "terminated"
               :cmd (.-cmd s)
               :stdinBuffer (.-stdinBuffer s)
               :stdoutBuffer (.-stdoutBuffer s)
               :stderrBuffer (.-stderrBuffer s)
               :exitCode (some 143)
               :idleMs newIdle
               :timeoutMs (.-timeoutMs s)
               :deadlockDetected true
               :termDeadlineMs termLimit
               :killDeadlineMs killLimit
               :terminationReceipt (some receipt))))
          (:else
           (ProcessSession
             :id (.-id s)
             :pid (.-pid s)
             :state (.-state s)
             :cmd (.-cmd s)
             :stdinBuffer (.-stdinBuffer s)
             :stdoutBuffer (.-stdoutBuffer s)
             :stderrBuffer (.-stderrBuffer s)
             :exitCode (.-exitCode s)
             :idleMs newIdle
             :timeoutMs (.-timeoutMs s)
             :deadlockDetected false
             :termDeadlineMs termLimit
             :killDeadlineMs killLimit
             :terminationReceipt (.-terminationReceipt s)))))))
