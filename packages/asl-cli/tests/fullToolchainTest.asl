(module asl-cli/tests/fullToolchainTest
  :x [testFullBinaryDispatch! testCoreLanguageOperations! runTests]
  :i [(asl-tools/fleet/run :a run)])

fn testFullBinaryDispatch! -> Bool
  (let [(version (run/runOneLimited (run/job (list "./bin/asl" "--version") "." (run/childEnv (list))) (run/limits 180 8)))]
    (assert (= version.exit 0) "bin/asl --version must exit 0")
    (assert (stringContains? version.out "asl 0.1.0") "bin/asl version must contain asl 0.1.0")
    (refute (stringContains? version.out "ERROR") "Must refute ERROR in asl version")
    true)

fn testCoreLanguageOperations! -> Bool
  (let [(rEval (run/runOneLimited (run/job (list "./bin/asl" "eval" "(+ 40 2)") "." (run/childEnv (list))) (run/limits 180 8)))
        (hasMesh (fileExists? "asl/tools/mesh/cmd.asl"))]
    (assert (= rEval.exit 0) "bin/asl eval must exit 0")
    (assert (stringContains? rEval.out "42") "bin/asl eval (+ 40 2) must equal 42")
    (refute (stringContains? rEval.out "ERROR") "Must refute ERROR in eval")
    (assert hasMesh "asl/tools/mesh/cmd.asl must exist")
    (refute (not hasMesh) "Must refute missing asl/tools/mesh/cmd.asl")
    true)

fn ! runTests -> Bool
  (do
    (assert (testFullBinaryDispatch!) "testFullBinaryDispatch must pass")
    (assert (testCoreLanguageOperations!) "testCoreLanguageOperations must pass")
    true)
