(module aslContracts/stageTest :x [testStageCreation testStageTransitions testStageOutput testStageErrorHandling testStageTerminalStates testStageInvariants runTests] :i [(stage :a st)])

fn testStageCreation -> Bool
  (let [(c (st/makeStageContract "stage-001" (st/stageScript)))] (assert (= c.id "stage-001") "Stage id must match stage-001") (assert (stringEmpty? c.errorMsg) "Stage error-msg must be empty") (assert (mt c.status ((st/statusPending) true) (_ false)) "Initial status must be pending") true)

fn testStageTransitions -> Bool
  (let [(c0 (st/makeStageContract "stage-002" (st/stageAudio))) (c1 (st/stageTransition c0 (st/statusRunning))) (c2 (st/stageTransition c1 (st/statusCompleted)))] (assert (mt c1.status ((st/statusRunning) true) (_ false)) "Status must transition to running") (assert (mt c2.status ((st/statusCompleted) true) (_ false)) "Status must transition to completed") (assert (st/isStageSuccessful? c2) "c2 must be classified as successful") true)

fn testStageOutput -> Bool
  (let [(c0 (st/makeStageContract "stage-003" (st/stageVisuals))) (c1 (st/stageSetOutput c0 "asset_count" "12")) (c2 (st/stageSetOutput c1 "resolution" "1080x1920"))] (assert (mapHas? c2.outputs "asset_count") "Outputs must contain asset_count") (assert (mapHas? c2.outputs "resolution") "Outputs must contain resolution") true)

fn testStageErrorHandling -> Bool
  (let [(c0 (st/makeStageContract "stage-004" (st/stageRender))) (c1 (st/stageSetError c0 "Remotion bundle failed: out of memory"))] (assert (mt c1.status ((st/statusFailed) true) (_ false)) "Status must transition to failed") (assert (= c1.errorMsg "Remotion bundle failed: out of memory") "Error msg must match") (assert (not (st/isStageSuccessful? c1)) "Failed stage must not be classified as successful") true)

fn testStageTerminalStates -> Bool
  (do (assert (not (st/isStageTerminal? (st/statusPending))) "Pending must not be terminal") (assert (not (st/isStageTerminal? (st/statusRunning))) "Running must not be terminal") (assert (st/isStageTerminal? (st/statusCompleted)) "Completed must be terminal") (assert (st/isStageTerminal? (st/statusFailed)) "Failed must be terminal") true)

fn testStageInvariants -> Bool
  (let [(validPending (st/makeStageContract "stage-005" (st/stagePublish))) (validFailed (st/stageSetError validPending "Failed to upload to S3"))] (assert (st/validateStageContract validPending) "valid-pending contract must be valid") (assert (st/validateStageContract validFailed) "valid-failed contract must be valid") true)

fn runTests -> Bool
  (do (assert (testStageCreation) "test-stage-creation must pass") (assert (testStageTransitions) "test-stage-transitions must pass") (assert (testStageOutput) "test-stage-output must pass") (assert (testStageErrorHandling) "test-stage-error-handling must pass") (assert (testStageTerminalStates) "test-stage-terminal-states must pass") (assert (testStageInvariants) "test-stage-invariants must pass") true)
