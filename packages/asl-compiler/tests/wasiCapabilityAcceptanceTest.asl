(module asl-compiler/tests/wasiCapabilityAcceptanceTest :x [testWasiCapabilityDynamicExecution! testWasiCapabilityInvariants! testWasiCapabilityDualPolarityRefutations! runTests] :i [(asl-compiler/wasi :a wasi) (asl-tools/fleet/run :a run)])

fn testWasiCapabilityDynamicExecution! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-compiler/tests/wasiCapabilityTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (stdout res.out)] (assert (= code 0) (str "wasiCapabilityTest must exit 0, stderr: " "")) (refute (!= code 0) "wasiCapabilityTest must not fail") (assert (stringContains? stdout "assertion(s) executed") "wasiCapabilityTest must report executed assertions") (assert (stringContains? stdout "refutation(s) executed") "wasiCapabilityTest must report executed refutations") (refute (stringContains? stdout "ASL_ASSERTION_FAILURE") "wasiCapabilityTest must not fail assertions") true)

fn testWasiCapabilityInvariants! -> Bool
  (let [(sandboxed (wasi/sandboxedWasiCapabilities)) (receipt (wasi/wasiSysExec! "date" sandboxed))] (assert (= receipt.status "refused") "Status under sandbox must be refused") (assert (= receipt.code 126) "Refusal code must be 126") (assert (stringContains? receipt.stderr "ERR_CAPABILITY_DENIED") "Stderr must contain ERR_CAPABILITY_DENIED") (assert (= receipt.stdout "") "Stdout must be empty on capability refusal") (refute (= receipt.status "ok") "Status must not be ok") (refute (!= receipt.code 126) "Code must not deviate from 126") true)

fn testWasiCapabilityDualPolarityRefutations! -> Bool
  (let [(sandboxed (wasi/sandboxedWasiCapabilities)) (res (wasi/wasiSysExec! "echo should_not_run" sandboxed))] (refute (wasi/wasiCapabilityCheck "execCmd" sandboxed) "execCmd must not be granted in sandbox") (refute (wasi/wasiCapabilityCheck "sys-exec" sandboxed) "sys-exec must not be granted in sandbox") (refute (= res.status "ok") "Subprocess execution must not succeed when capability is false") (refute (stringContains? res.stdout "should_not_run") "Subprocess stdout must not leak when capability is false") true)

fn ! runTests -> Bool
  (do (assert (testWasiCapabilityDynamicExecution!) "testWasiCapabilityDynamicExecution must pass") (assert (testWasiCapabilityInvariants!) "testWasiCapabilityInvariants must pass") (assert (testWasiCapabilityDualPolarityRefutations!) "testWasiCapabilityDualPolarityRefutations must pass") true)
