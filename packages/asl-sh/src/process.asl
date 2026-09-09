(module asl-sh/process
  :d "Pure AgentScript process supervision modular aliases per d46 and d47."
  :x [status
      list
      proc-status
      proc-list
      proc/status
      proc/list]
  :i [(apm :a apm)])

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
