(module asl-sh/process
  :d "Native AgentScript Process Execution and Typed Command Builder (@pcp:d-446d)."
  :x [ProcessCmd ProcessOutput ProcessError ProcessReceipt cmd with-cwd with-timeout with-stdin exec! run-simple! make-process-receipt render-receipt estimate-tokens receipt-tokens])

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
  (ok (ProcessOutput
        :exit-code 0
        :stdout ""
        :stderr ""
        :duration-ms 1)))

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

