(module asl-compiler/tests/wasiAbiAcceptanceTest :x [testWasiAbiDynamicExecution! testWasiAbiInvariants testWasiDualPolarityRefutations runTests] :i [(asl-compiler/wasi :a wasi) (asl-tools/fleet/run :a run)])

fn testWasiAbiDynamicExecution! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-compiler/tests/wasiAbiTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (stdout res.out)] (assert (= code 0) (str "wasiAbiTest must exit 0, stderr: " "")) (refute (!= code 0) "wasiAbiTest must not fail") (assert (stringContains? stdout "assertion(s) executed") "wasiAbiTest must report executed assertions") (assert (stringContains? stdout "refutation(s) executed") "wasiAbiTest must report executed refutations") (refute (stringContains? stdout "ASL_ASSERTION_FAILURE") "wasiAbiTest must not fail assertions") true)

; (:m :ref HLFIXB :do "a4ad48c1e deleted asl-compiler/src/wasm.asl (no live consumer) and trimmed wasiRuntimeTest/wasiAbiTest/evaluatorWasiTest to drop only their wasm.asl-dependent functions, keeping wasi-only coverage; this acceptance test's own encodeImportSection/encodeImportEntry/buildFunctionTypeIndexOffset assertions against the deleted wasm.asl were missed by that pass and left an unresolved import; dropped them here the same way, keeping the wasi-only errno coverage")
fn testWasiAbiInvariants -> Bool
  (let [(e0 (wasi/wasiErrnoName 0)) (e44 (wasi/wasiErrnoName 44))] (assert (= e0 "ESUCCESS") "wasiErrnoName 0 must produce ESUCCESS") (assert (= e44 "ENOENT") "wasiErrnoName 44 must produce ENOENT") true)

fn testWasiDualPolarityRefutations -> Bool
  (let [(e8 (wasi/wasiErrnoName 8)) (e63 (wasi/wasiErrnoName 63))] (refute (= e8 "ESUCCESS") "EBADF must not map to ESUCCESS") (refute (= e63 "ESUCCESS") "EPERM must not map to ESUCCESS") (refute (= (wasi/wasiErrno "INVALID_ERRNO") 0) "Invalid errno name must not return 0") true)

fn ! runTests -> Bool
  (do (assert (testWasiAbiDynamicExecution!) "testWasiAbiDynamicExecution must pass") (assert (testWasiAbiInvariants) "testWasiAbiInvariants must pass") (assert (testWasiDualPolarityRefutations) "testWasiDualPolarityRefutations must pass") true)
