(module asl-cli/tests/buildStandaloneBinaryTest :x [testBuildNegativeRefutations! testBuildStandaloneBinary! testRunCompiledBinary! runTests] :i [(asl-tools/fleet/run :a run)])

fn testBuildNegativeRefutations! -> Bool
  (let [(done (run/runOneLimited (run/job (list "./bin/asl" "build" "non_existent_fixture_file_12345.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code done.exit)] (assert (!= code 0) "Building non-existent file must exit with non-zero code") (refute (= code 0) "Building missing file must not succeed") (let [(noArgDone (run/runOneLimited (run/job (list "./bin/asl" "build") "." (run/childEnv (list))) (run/limits 180 8))) (noArgCode noArgDone.exit)] (assert (!= noArgCode 0) "Invoking asl build without arguments must exit non-zero") (refute (= noArgCode 0) "No-arg build invocation must not return exit 0") true))

fn testBuildStandaloneBinary! -> Bool
  (let [(srcPath "tmp/task52505_sample.asl") (binPath "tmp/task52505_sample_bin") (sampleCode "(module task52505/sample\n  :x [main]\n  :i [])\n\nfn ! main -> Int64\n  (let [(a 18)\n        (b 24)]\n    (+ a b))\n") (mkRes (run/runOneLimited (run/job (list "mkdir" "-p" "tmp") "." (run/childEnv (list))) (run/limits 180 8))) (wRes (fileWrite srcPath sampleCode)) (done (run/runOneLimited (run/job (list "./bin/asl" "build" srcPath "-o" binPath) "." (run/childEnv (list))) (run/limits 900 8))) (code done.exit) (out done.out)] (assert (= code 0) (str "asl build must exit 0, got: " (stringFromInt64 code))) (assert (fileExists? binPath) "Output binary must exist on disk") (assert (stringContains? out "built") "stdout must confirm successful compilation") (refute (stringContains? out "Error") "stdout must not contain error") true)

fn testRunCompiledBinary! -> Bool
  (let [(binPath "tmp/task52505_sample_bin") (srcPath "tmp/task52505_sample.asl") (res (run/runOneLimited (run/job (list binPath) "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (_ (run/runOneLimited (run/job (list "rm" "-f" srcPath binPath) "." (run/childEnv (list))) (run/limits 180 8)))] (assert (= code 42) (str "Compiled binary must return computed exit code 42, got: " (stringFromInt64 code))) (refute (!= code 42) "Compiled binary exit code must not deviate from 42") true)

fn ! runTests -> Bool
  (do (assert (testBuildNegativeRefutations!) "testBuildNegativeRefutations") (assert (testBuildStandaloneBinary!) "testBuildStandaloneBinary") (assert (testRunCompiledBinary!) "testRunCompiledBinary") true)
