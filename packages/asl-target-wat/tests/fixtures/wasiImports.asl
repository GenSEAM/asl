(module asl-target-wat/tests/fixtures/wasiImports
  :d "Localized WASI host imports test fixture for WebAssembly Text target code emission."
  :x [wasiFdWrite wasiFdRead wasiProcExit wasiClockTimeGet]
  :i [])

(df wasiFdWrite [(fd I32) (iovs I32) (iovsLen I32) (nwritten I32)] -> I32
  :d "Lowers to wasi_snapshot_preview1 fd_write host import invocation."
  0)

(df wasiFdRead [(fd I32) (iovs I32) (iovsLen I32) (nread I32)] -> I32
  :d "Lowers to wasi_snapshot_preview1 fd_read host import invocation."
  0)

(df wasiProcExit [(exitCode I32)] -> Unit
  :d "Lowers to wasi_snapshot_preview1 proc_exit host import invocation."
  ())

(df wasiClockTimeGet [(clockId I32) (precision I64) (timeOffset I32)] -> I32
  :d "Lowers to wasi_snapshot_preview1 clock_time_get host import invocation."
  0)
