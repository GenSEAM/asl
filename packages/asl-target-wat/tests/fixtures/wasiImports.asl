(module asl-target-wat/tests/fixtures/wasiImports
  :x [wasiFdWrite wasiFdRead wasiProcExit wasiClockTimeGet]
  :i [])

fn wasiFdWrite fd: I32 iovs: I32 iovsLen: I32 nwritten: I32 -> I32
  0

fn wasiFdRead fd: I32 iovs: I32 iovsLen: I32 nread: I32 -> I32
  0

fn wasiProcExit exitCode: I32 -> Unit
  ()

fn wasiClockTimeGet clockId: I32 precision: I64 timeOffset: I32 -> I32
  0
