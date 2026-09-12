(module asl-sh/process
  :d "Native AgentScript Process Execution and Typed Command Builder (@pcp:d-446d)."
  :x [ProcessCmd
      ProcessOutput
      ProcessError
      ProcessReceipt
      ProcessSession
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
      session-tick-idle
      session-extend-timeout
      session-set-timeout
      make-process-receipt
      render-receipt
      estimate-tokens
      receipt-tokens])

(dfs ProcessCmd
  (:f bin        String              "Executable binary path or system command")
  (:f args       (List String)       "Explicit argument vector preventing shell injection")
  (:f env        (Map String String) "Environment variable overrides")
  (:f cwd        (Option String)     "Working directory for process execution")
  (:f timeout-ms Int64               "Execution timeout deadline in milliseconds" :default 5000)
  (:f stdin-data (Option String)     "Optional input string piped to process stdin"))

(dfs ProcessOutput
  (:f exit-code   Int64  "Process exit status (0 = success)")
  (:f stdout      String "Captured standard output stream")
  (:f stderr      String "Captured standard error stream")
  (:f duration-ms Int64  "Execution elapsed time in milliseconds"))

(dfs ProcessReceipt
  (:f exit-code   Int64  "Process return code (0 = success)")
  (:f duration-ms Int64  "Execution duration in milliseconds")
  (:f peak-rss-mb Int64  "Peak memory resident set size in megabytes")
  (:f spool-path  String "Filesystem path to ephemeral disk spool")
  (:f summary     String "Compact diagnostic string (<100 tokens, errors only)"))

(dfs ProcessSession
  (:f id String "Unique session identifier e.g. sess-1")
  (:f pid Int64 "Operating system process identifier")
  (:f state String "Session lifecycle state: active, idle, or terminated")
  (:f cmd ProcessCmd "Underlying command specification")
  (:f stdin-buffer (List String) "Pending or injected standard input lines")
  (:f stdout-buffer (List String) "Captured standard output lines in FIFO order")
  (:f stderr-buffer (List String) "Captured standard error lines in FIFO order")
  (:f exit-code (Option Int64) "Termination exit status code if finished")
  (:f idle-ms Int64 "Milliseconds elapsed since last stdin or stdout event")
  (:f timeout-ms Int64 "Configurable watchdog timeout ceiling in milliseconds")
  (:f deadlock-detected Bool "True if process reached idle deadlock threshold"))

(dfe ProcessError
  (:c not-found         [(bin String)]              "Command binary was not found")
  (:c timeout           [(ms Int64)]                "Command execution timed out")
  (:c permission-denied [(path String)]             "Access permission denied to executable")
  (:c execution-failed  [(code Int64) (msg String)] "Process exited with non-zero status"))

(df cmd [(bin String) (args (List String))] -> ProcessCmd
  :d "Constructs a safe, typed command with an argument vector."
  (ProcessCmd
    :bin bin
    :args args
    :env (map-empty)
    :cwd (none)
    :timeout-ms 5000
    :stdin-data (none)))

(df with-cwd [(c ProcessCmd) (dir String)] -> ProcessCmd
  :d "Sets the execution working directory."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (some dir)
    :timeout-ms (.-timeout-ms c)
    :stdin-data (.-stdin-data c)))

(df with-timeout [(c ProcessCmd) (ms Int64)] -> ProcessCmd
  :d "Sets the execution timeout in milliseconds."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (.-cwd c)
    :timeout-ms ms
    :stdin-data (.-stdin-data c)))

(df with-stdin [(c ProcessCmd) (input String)] -> ProcessCmd
  :d "Sets standard input data for the process."
  (ProcessCmd
    :bin (.-bin c)
    :args (.-args c)
    :env (.-env c)
    :cwd (.-cwd c)
    :timeout-ms (.-timeout-ms c)
    :stdin-data (some input)))

(df ! exec! [(c ProcessCmd)] -> (Result ProcessOutput ProcessError)
  :d "Executes a typed process command with timeout enforcement and captured output."
  (err (ProcessError :code -1 :message "ERR_UNSUPPORTED: process execution is not implemented")))

(df ! run-simple! [(bin String) (args (List String))] -> (Result String ProcessError)
  :d "Quick helper to run a command and return trimmed stdout on success."
  (mt (exec! (cmd bin args))
    ((ok out)
     (if (= (.-exit-code out) 0)
         (ok (.-stdout out))
         (err (execution-failed (.-exit-code out) (.-stderr out)))))
    ((err e) (err e))))

(df make-process-receipt [(exit-code Int64) (duration-ms Int64) (peak-rss-mb Int64) (spool-path String) (summary String)] -> ProcessReceipt
  :d "Constructs a compact ProcessReceipt."
  (ProcessReceipt
    :exit-code exit-code
    :duration-ms duration-ms
    :peak-rss-mb peak-rss-mb
    :spool-path spool-path
    :summary summary))

(df render-receipt [(r ProcessReceipt)] -> String
  :d "Renders a ProcessReceipt as a compact S-expression string."
  (str "(:proc-receipt :exit " (string-from-int64 (.-exit-code r))
       " :duration-ms " (string-from-int64 (.-duration-ms r))
       " :peak-rss-mb " (string-from-int64 (.-peak-rss-mb r))
       " :spool-path \"" (.-spool-path r) "\""
       " :summary \"" (.-summary r) "\")"))

(df estimate-tokens [(text String)] -> Int64
  :d "Deterministic BPE proxy token count estimation based on character length."
  (let [(len (string-length text))]
    (cond
      ((<= len 0) 0)
      ((<= len 4) 1)
      (:else (/ (+ len 3) 4)))))

(df receipt-tokens [(r ProcessReceipt)] -> Int64
  :d "Estimates total BPE tokens for a rendered ProcessReceipt."
  (estimate-tokens (render-receipt r)))

(df ! session-spawn! [(id String) (c ProcessCmd)] -> ProcessSession
  :d "Initializes an interactive process session bound to a ProcessCmd."
  (ProcessSession
    :id id
    :pid 1001
    :state "active"
    :cmd c
    :stdin-buffer (list)
    :stdout-buffer (list)
    :stderr-buffer (list)
    :exit-code (none)
    :idle-ms 0
    :timeout-ms (.-timeout-ms c)
    :deadlock-detected false))

(df ! session-send-input! [(s ProcessSession) (input String)] -> ProcessSession
  :d "Injects standard input data into an active session resetting idle timer."
  (if (= (.-state s) "terminated")
      s
      (ProcessSession
        :id (.-id s)
        :pid (.-pid s)
        :state "active"
        :cmd (.-cmd s)
        :stdin-buffer (list-append (.-stdin-buffer s) (list input))
        :stdout-buffer (.-stdout-buffer s)
        :stderr-buffer (.-stderr-buffer s)
        :exit-code (.-exit-code s)
        :idle-ms 0
        :timeout-ms (.-timeout-ms s)
        :deadlock-detected false)))

(df ! session-input! [(s ProcessSession) (input String)] -> ProcessSession
  :d "Short alias for session-send-input!."
  (session-send-input! s input))

(df ! session-emit-stdout! [(s ProcessSession) (line String)] -> ProcessSession
  :d "Appends a line of captured stdout to session buffer and resets idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdin-buffer (.-stdin-buffer s)
    :stdout-buffer (list-append (.-stdout-buffer s) (list line))
    :stderr-buffer (.-stderr-buffer s)
    :exit-code (.-exit-code s)
    :idle-ms 0
    :timeout-ms (.-timeout-ms s)
    :deadlock-detected false))

(df ! session-emit-stderr! [(s ProcessSession) (line String)] -> ProcessSession
  :d "Appends a line of captured stderr to session buffer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdin-buffer (.-stdin-buffer s)
    :stdout-buffer (.-stdout-buffer s)
    :stderr-buffer (list-append (.-stderr-buffer s) (list line))
    :exit-code (.-exit-code s)
    :idle-ms 0
    :timeout-ms (.-timeout-ms s)
    :deadlock-detected false))

(df session-poll-tail! [(s ProcessSession) (n Int64)] -> (List String)
  :d "Retrieves the trailing n lines from the session stdout buffer."
  (let [(buf (.-stdout-buffer s))
        (cnt (list-length buf))]
    (cond
      ((<= n 0) (list))
      ((>= n cnt) buf)
      (:else (option-or (list-slice buf (- cnt n) cnt) (list))))))

(df session-tail! [(s ProcessSession) (n Int64)] -> (List String)
  :d "Short alias for session-poll-tail!."
  (session-poll-tail! s n))

(df ! session-kill! [(s ProcessSession) (sig String)] -> ProcessSession
  :d "Terminates an interactive session with the specified signal."
  (let [(code (if (= sig "SIGKILL") 137 (if (= sig "SIGTERM") 143 1)))]
    (ProcessSession
      :id (.-id s)
      :pid (.-pid s)
      :state "terminated"
      :cmd (.-cmd s)
      :stdin-buffer (.-stdin-buffer s)
      :stdout-buffer (.-stdout-buffer s)
      :stderr-buffer (.-stderr-buffer s)
      :exit-code (some code)
      :idle-ms (.-idle-ms s)
      :timeout-ms (.-timeout-ms s)
      :deadlock-detected false)))

(df session-check-deadlock [(s ProcessSession) (idle-ceiling Int64)] -> ProcessSession
  :d "Audits session idle duration against deadlock ceiling setting deadlock flag if breached."
  (let [(cap (if (<= idle-ceiling 0)
               (if (<= (.-timeout-ms s) 0) 10000 (.-timeout-ms s))
               idle-ceiling))
        (breached (>= (.-idle-ms s) cap))]
    (ProcessSession
      :id (.-id s)
      :pid (.-pid s)
      :state (if breached "idle" (.-state s))
      :cmd (.-cmd s)
      :stdin-buffer (.-stdin-buffer s)
      :stdout-buffer (.-stdout-buffer s)
      :stderr-buffer (.-stderr-buffer s)
      :exit-code (.-exit-code s)
      :idle-ms (.-idle-ms s)
      :timeout-ms (.-timeout-ms s)
      :deadlock-detected breached)))

(df session-tick-idle [(s ProcessSession) (delta-ms Int64)] -> ProcessSession
  :d "Advances session idle duration counter by elapsed milliseconds."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdin-buffer (.-stdin-buffer s)
    :stdout-buffer (.-stdout-buffer s)
    :stderr-buffer (.-stderr-buffer s)
    :exit-code (.-exit-code s)
    :idle-ms (+ (.-idle-ms s) delta-ms)
    :timeout-ms (.-timeout-ms s)
    :deadlock-detected (.-deadlock-detected s)))

(df session-extend-timeout [(s ProcessSession) (extend-ms Int64)] -> ProcessSession
  :d "Dynamically extends watchdog timeout ceiling on active session resetting idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdin-buffer (.-stdin-buffer s)
    :stdout-buffer (.-stdout-buffer s)
    :stderr-buffer (.-stderr-buffer s)
    :exit-code (.-exit-code s)
    :idle-ms 0
    :timeout-ms (+ (.-timeout-ms s) extend-ms)
    :deadlock-detected false))

(df session-set-timeout [(s ProcessSession) (new-ms Int64)] -> ProcessSession
  :d "Explicitly updates watchdog timeout ceiling on active session resetting idle timer."
  (ProcessSession
    :id (.-id s)
    :pid (.-pid s)
    :state (.-state s)
    :cmd (.-cmd s)
    :stdin-buffer (.-stdin-buffer s)
    :stdout-buffer (.-stdout-buffer s)
    :stderr-buffer (.-stderr-buffer s)
    :exit-code (.-exit-code s)
    :idle-ms 0
    :timeout-ms new-ms
    :deadlock-detected false))

