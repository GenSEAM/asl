(module asl-compiler/wasiCapabilityTest
  :d "Unit tests for sandboxed capability boundaries and explicit sys-exec refusal receipts."
  :x [testCapabilityCheck
      testMakeCapabilityRefusalReceipt
      testSandboxedWasiSysExecRefusal
      testNativeTierSysExec
      runTests]
  :i [(wasi :a wasi)])

(df testCapabilityCheck [] -> Bool
  :d "Verifies capability checking under sandboxed and native capability maps."
  (let [(sandboxed (wasi/sandboxedWasiCapabilities))
        (native (wasi/nativeTierCapabilities))]
    (assert (not (wasi/wasiCapabilityCheck "execCmd" sandboxed)) "execCmd must be denied in sandboxed WASI")
    (refute (wasi/wasiCapabilityCheck "execCmd" sandboxed) "execCmd must not be granted in sandbox")
    (assert (not (wasi/wasiCapabilityCheck "sys-exec" sandboxed)) "sys-exec must be denied in sandboxed WASI")
    (refute (wasi/wasiCapabilityCheck "sys-exec" sandboxed) "sys-exec must not be granted in sandbox")
    (assert (wasi/wasiCapabilityCheck "fileRead" sandboxed) "fileRead must be granted in sandbox")
    (assert (wasi/wasiCapabilityCheck "fileWrite" sandboxed) "fileWrite must be granted in sandbox")
    (assert (wasi/wasiCapabilityCheck "execCmd" native) "execCmd must be granted in native tier")
    (assert (wasi/wasiCapabilityCheck "sys-exec" native) "sys-exec must be granted in native tier")
    (refute (not (wasi/wasiCapabilityCheck "execCmd" native)) "execCmd must not be denied in native tier")
    true))

(df testMakeCapabilityRefusalReceipt [] -> Bool
  :d "Verifies structure of typed capability denial receipt."
  (let [(receipt (wasi/makeCapabilityRefusalReceipt "execCmd"))]
    (assert (= (.-status receipt) "refused") "Status must be refused")
    (refute (!= (.-status receipt) "refused") "Status must not deviate from refused")
    (assert (= (.-code receipt) 126) "Code must be 126 (POSIX command invoked cannot execute)")
    (refute (!= (.-code receipt) 126) "Code must not deviate from 126")
    (assert (string-contains? (.-stderr receipt) "ERR_CAPABILITY_DENIED") "Stderr must contain ERR_CAPABILITY_DENIED")
    (assert (string-contains? (.-stderr receipt) "execCmd") "Stderr must name denied capability")
    (assert (= (.-stdout receipt) "") "Stdout must be empty")
    (refute (!= (.-stdout receipt) "") "Stdout must be empty on denial")
    true))

(df testSandboxedWasiSysExecRefusal [] -> Bool
  :d "Verifies that executing sys-exec in sandboxed WASI returns explicit refusal."
  (let [(sandboxed (wasi/sandboxedWasiCapabilities))
        (res (wasi/wasiSysExec "echo test" sandboxed))]
    (assert (= (.-status res) "refused") "SysExec under sandbox must return status refused")
    (refute (= (.-status res) "ok") "SysExec under sandbox must not return ok")
    (assert (= (.-code res) 126) "Exit code must be 126")
    (refute (!= (.-code res) 126) "Exit code must strictly be 126")
    (assert (string-contains? (.-stderr res) "ERR_CAPABILITY_DENIED") "Stderr must report ERR_CAPABILITY_DENIED")
    (refute (string-empty? (.-stderr res)) "Stderr must not be empty on refusal")
    true))

(df testNativeTierSysExec [] -> Bool
  :d "Verifies that native tier capabilities allow subprocess execution."
  (let [(native (wasi/nativeTierCapabilities))
        (res (wasi/wasiSysExec "echo native-tier-ok" native))]
    (assert (= (.-status res) "ok") "SysExec under native tier must return status ok")
    (refute (!= (.-status res) "ok") "Native tier execution must succeed")
    (assert (= (.-code res) 0) "Exit code must be 0")
    (assert (string-contains? (.-stdout res) "native-tier-ok") "Stdout must contain echo output")
    true))

(df runTests [] -> Bool
  :d "Runs all WASI capability unit tests."
  (do
    (assert (testCapabilityCheck) "testCapabilityCheck must pass")
    (assert (testMakeCapabilityRefusalReceipt) "testMakeCapabilityRefusalReceipt must pass")
    (assert (testSandboxedWasiSysExecRefusal) "testSandboxedWasiSysExecRefusal must pass")
    (assert (testNativeTierSysExec) "testNativeTierSysExec must pass")
    true))
