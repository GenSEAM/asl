(module asl-sh/log
  :d "Structured Administrative Logging & Error Streams for Agent Scripts (@pcp:d-446d)."
  :x [LogLevel LogEntry info! warn! err! format-entry])

(dfe LogLevel
  (:c debug [] "Debug log level")
  (:c info  [] "Informational log level")
  (:c warn  [] "Warning log level")
  (:c error [] "Error log level"))

(dfs LogEntry
  (:f level     LogLevel "Severity level of log event")
  (:f message   String   "Primary human/agent-readable log message")
  (:f timestamp Int64    "Epoch millisecond timestamp")
  (:f subsystem String   "Originating module or task subsystem"))

(df format-entry [(entry LogEntry)] -> String
  :d "Renders a structured log entry into canonical text format."
  (let [(lvl-str (mt (.-level entry)
                  ((debug) "DEBUG")
                  ((info)  "INFO ")
                  ((warn)  "WARN ")
                  ((error) "ERROR")))]
    (str "[" lvl-str "] [" (.-subsystem entry) "] " (.-message entry))))

(df ! info! [(subsystem String) (message String)] -> Unit
  :d "Emits an informational log line to standard log channel."
  ())

(df ! warn! [(subsystem String) (message String)] -> Unit
  :d "Emits a warning log line to standard log channel."
  ())

(df ! err! [(subsystem String) (message String)] -> Unit
  :d "Emits an error log line to standard error channel."
  ())
