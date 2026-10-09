(module asl-runtime/panic :x [rtPanic rtPanicCode] :i [])

fn ! rtPanicCode code: Int64 msg: Str -> Unit
  (do (eprintln (str "PANIC: [" (stringFromInt64 code) "] " msg)) (assert false msg))

fn ! rtPanic msg: Str -> Unit
  (rtPanicCode 1 msg)
