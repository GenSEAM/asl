(module asl-pack/tests/releaseOrchestratorAcceptanceTest :x [testReleaseOrchestratorInvariants testReleaseStepExecution! testDualPolarityRefutations! runTests] :i [(aslPack/release :a rel) (asl-tools/fleet/run :a run)])

fn testReleaseOrchestratorInvariants -> Bool
  (let [(plan (rel/makeReleasePlan "0.2.0")) (step (rel/ReleaseStepResult :name "verification" :ok true :message "Gate passed" :durationMs 42)) (receipt (rel/ReleaseReceipt :plan plan :ok true :steps (list step) :publishedArtifacts (list "dist/v0.2.0/asl.tar.gz")))] (assert step.ok "step ok must be true") (assert (= step.name "verification") "step name must match") (assert (= step.message "Gate passed") "step message must match") (assert (= step.durationMs 42) "step duration must match") (assert receipt.ok "receipt ok must be true") (assert (= (listLength receipt.steps) 1) "receipt steps count must match") (assert (= (listLength receipt.publishedArtifacts) 1) "receipt artifacts count must match") true)

fn testReleaseStepExecution! -> Bool
  (let [(resOk (rel/executeReleaseStep! "echoStep" "echo" (list "test-release-step"))) (resFail (rel/executeReleaseStep! "failStep" "false" (list)))] (assert resOk.ok "echo step must succeed") (assert (= resOk.name "echoStep") "echo step name must match") (assert (not resFail.ok) "false step must fail") (assert (= resFail.name "failStep") "false step name must match") true)

fn testDualPolarityRefutations! -> Bool
  (let [(plan (rel/makeReleasePlan "0.2.0")) (resBad (rel/executeReleaseStep! "missingBin" "nonexistent-cmd-xyz-999" (list))) (gRes (run/runOneLimited (run/job (list "cat" "asl/packages/asl-pack/src/release.asl") "." (run/childEnv (list))) (run/limits 180 8))) (gText gRes.out)] (refute resBad.ok "nonexistent command execution must be refuted") (refute (!= resBad.name "missingBin") "bad step name must not change") (assert (stringContains? gText "ReleaseStepResult") "release source must declare ReleaseStepResult") (assert (stringContains? gText "ReleaseReceipt") "release source must declare ReleaseReceipt") (assert (stringContains? gText "executeReleasePlan") "release source must declare executeReleasePlan") (assert (stringContains? gText "executeReleaseStep") "release source must declare executeReleaseStep") true)

fn ! runTests -> Bool
  (do (assert (testReleaseOrchestratorInvariants) "testReleaseOrchestratorInvariants must pass") (assert (testReleaseStepExecution!) "testReleaseStepExecution must pass") (assert (testDualPolarityRefutations!) "testDualPolarityRefutations must pass") true)
