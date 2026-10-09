(module aslHarness/checkpoint :x [CheckpointRecord createCheckpoint isCheckpointValid?] :i [])

(schema CheckpointRecord (:f id Str) (:f snapshot Str) (:f valid Bool))

fn createCheckpoint id: Str data: Str -> CheckpointRecord
  (CheckpointRecord :id id :snapshot data :valid (not (stringEmpty? data)))

fn isCheckpointValid? cp: CheckpointRecord -> Bool
  (and cp.valid (not (stringEmpty? cp.id)))
