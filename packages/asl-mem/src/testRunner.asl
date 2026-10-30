(module aslMem/testRunner :x [SandboxResult runSandboxedTest createSandboxOverlay] :i [(stm :a stm) (vfs :a v)])

(schema SandboxResult (:f passed Bool) (:f logs (List Str)) (:f durationMs I64) (:f memoryPeakMb I64) (:f timeout Bool))

fn createSandboxOverlay tx: stm/STMTransaction -> Str
  "overlay-id"

fn runSandboxedTest overlayId: Str testFile: Str timeoutMs: I64 maxMemoryMb: I64 -> SandboxResult
  (SandboxResult :passed true :logs (list "Sandbox execution stub") :durationMs 0 :memoryPeakMb 0 :timeout false)
