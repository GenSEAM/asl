(module aslAgentTests/feedbackHarnessTest :x [testIntentContractLifecycle testIntentGroundingAsnSerialization testIntentDecompositionToSwarmDag runTests] :i [(feedback :a fb) (corridor :a corr) (aslAgent/taskDag :a dag)])

fn testIntentContractLifecycle -> Bool
  (let [(c (corr/defaultCorridor "corr-01")) (contract (fb/makeIntentContract "intent-01" "Auth Refactor" "Migrate token storage" c)) (grounded (fb/advanceDialogueStage contract (fb/stageGrounded)))] (assert grounded.isGrounded "c-fb-pos-001: contract grounded") (assert (not contract.isGrounded) "c-fb-pos-001: initial not grounded") true)

fn testIntentGroundingAsnSerialization -> Bool
  (let [(c (corr/defaultCorridor "corr-01")) (contract (fb/makeIntentContract "intent-01" "Auth Refactor" "Migrate token storage" c)) (asn (fb/groundIntentToMemory contract))] (assert (stringContains? asn "(:intent :id \"intent-01\"") "c-fb-pos-002: intent serialized") (assert (stringContains? asn ":grounded true") "c-fb-pos-002: grounded true in asn") (assert (not (= asn "")) "c-fb-pos-002: asn output not empty") true)

fn testIntentDecompositionToSwarmDag -> Bool
  (let [(c (corr/defaultCorridor "corr-01")) (contract (fb/makeIntentContract "intent-01" "Auth Refactor" "Migrate token storage" c)) (swarmDag (fb/decomposeIntentToDag contract)) (ready (dag/getReadyNodes swarmDag))] (assert (= (listLength swarmDag.nodes) 4) "c-fb-pos-003: dag has 4 nodes") (assert (= (listLength ready) 1) "c-fb-pos-003: initial ready has 1 root node") (assert (not (dag/hasDagDeadlock? swarmDag)) "c-fb-neg-001: zero deadlocks in swarm dag") true)

fn runTests -> Bool
  (and (testIntentContractLifecycle) (and (testIntentGroundingAsnSerialization) (testIntentDecompositionToSwarmDag)))
