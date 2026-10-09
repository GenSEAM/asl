(module aslHarness/checkpointTest :x [runTests] :i [(checkpoint :a cp)])

fn testCreateCheckpoint -> Bool
  (let [(c (cp/createCheckpoint "cp-1" "data")) (emptyC (cp/createCheckpoint "cp-2" ""))] (assert c.valid "checkpoint with data should be valid") (assert (not emptyC.valid) "checkpoint with empty data should be invalid") true)

fn testIsCheckpointValid -> Bool
  (let [(c1 (cp/CheckpointRecord :id "cp-1" :snapshot "data" :valid true)) (c2 (cp/CheckpointRecord :id "" :snapshot "data" :valid true)) (c3 (cp/CheckpointRecord :id "cp-3" :snapshot "data" :valid false))] (assert (cp/isCheckpointValid? c1) "valid checkpoint") (assert (not (cp/isCheckpointValid? c2)) "invalid if id is empty") (assert (not (cp/isCheckpointValid? c3)) "invalid if flag is false") true)

fn runTests -> Bool
  (do (assert (testCreateCheckpoint) "test-create-checkpoint must pass") (assert (testIsCheckpointValid) "test-is-checkpoint-valid must pass") true)
