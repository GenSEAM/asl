(module asl-runtime/panic
  :d "AgentScript runtime panic handling and process abort routines"
  :x [rtPanic
      rtPanicCode]
  :i [])

(df ! rtPanicCode [(code Int64) (msg Str)] -> Unit
  :d "Emits a runtime panic message to standard error/output and terminates with exit code."
  (do
    (println (str "PANIC: " msg))
    (exit code)))

(df ! rtPanic [(msg Str)] -> Unit
  :d "Emits a runtime panic message and terminates with default exit code 1."
  (rtPanicCode 1 msg))
