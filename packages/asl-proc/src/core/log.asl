(module asl-proc/log :x [LogLevel LogEntry info! warn! err! formatEntry])

(enum LogLevel (:c debug [] "Debug log level") (:c info [] "Informational log level") (:c warn [] "Warning log level") (:c error [] "Error log level"))

(schema LogEntry (:f level LogLevel) (:f message String) (:f timestamp Int64) (:f subsystem String))

fn formatEntry entry: LogEntry -> String
  (let [(lvlStr (mt entry.level ((debug) "DEBUG") ((info) "INFO ") ((warn) "WARN ") ((error) "ERROR")))] (str "[" lvlStr "] [" entry.subsystem "] " entry.message))

fn ! info! subsystem: String message: String -> Unit
  (let [(entry (LogEntry :level (info) :message message :timestamp 0 :subsystem subsystem))]
    (eprintln (formatEntry entry)))

fn ! warn! subsystem: String message: String -> Unit
  (let [(entry (LogEntry :level (warn) :message message :timestamp 0 :subsystem subsystem))]
    (eprintln (formatEntry entry)))

fn ! err! subsystem: String message: String -> Unit
  (let [(entry (LogEntry :level (error) :message message :timestamp 0 :subsystem subsystem))]
    (eprintln (formatEntry entry)))
