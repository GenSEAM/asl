(module aslAgentCore/tasktypes :x [TaskState TaskPriority TaskKind TaskOutcome TaskRecord TaskLane taskRecordCreate taskLaneCreate makeTaskOutcome taskStateInFlight?] :i [])

(enum TaskState (:c stateQueued [] "Task born on disk, awaiting scheduler drain") (:c stateRouting [] "Claimed by scheduler, determining route and spec") (:c stateClarification [] "Awaiting external spec clarification") (:c stateReady [] "Spec confirmed and queued for harness execution") (:c stateExecuting [] "Active execution in harness loop") (:c stateVerifying [] "Verification gate inspection") (:c stateDone [] "Verified terminal success") (:c stateFailed [] "Terminal failure") (:c stateCancelled [] "Cancelled by user or precondition"))

(enum TaskPriority (:c priorityLow [] "Low priority background task") (:c priorityNormal [] "Standard execution priority") (:c priorityHigh [] "Elevated interactive priority") (:c priorityUrgent [] "Urgent priority bypassing standard queue delay"))

(enum TaskKind (:c kindCodeMutation [] "Direct source code AST modifications") (:c kindTaskSpawn [] "Discovery or planning task spawning child items") (:c kindAuditVerdict [] "Verification audit producing compliance verdict") (:c kindDocArtifact [] "Architecture or memory ledger documentation update") (:c kindOperational [] "Operational execution or benchmark validation"))

(schema TaskOutcome (:f kind TaskKind) (:f mutatedPaths (List Str)) (:f spawnedTaskIds (List Str)) (:f artifactPath Str) (:f receipt Str))

(schema TaskRecord (:f id Str) (:f lane Str) (:f projectPath Str) (:f state TaskState) (:f priority TaskPriority) (:f createdAt I64) (:f updatedAt I64) (:f payload Str))

(schema TaskLane (:f id Str) (:f maxConcurrent I64) (:f activeCount I64))

fn taskRecordCreate id: Str lane: Str projectPath: Str priority: TaskPriority createdAt: I64 payload: Str -> TaskRecord
  (TaskRecord :id id :lane lane :projectPath projectPath :state (stateQueued) :priority priority :createdAt createdAt :updatedAt createdAt :payload payload)

fn taskLaneCreate id: Str maxConcurrent: I64 -> TaskLane
  (TaskLane :id id :maxConcurrent maxConcurrent :activeCount 0)

fn makeTaskOutcome kind: TaskKind mutatedPaths: (List Str) spawnedTaskIds: (List Str) artifactPath: Str receipt: Str -> TaskOutcome
  (TaskOutcome :kind kind :mutatedPaths mutatedPaths :spawnedTaskIds spawnedTaskIds :artifactPath artifactPath :receipt receipt)

fn taskStateInFlight? state: TaskState -> Bool
  (mt state ((stateRouting) true) ((stateClarification) true) ((stateReady) true) ((stateExecuting) true) ((stateVerifying) true) ((stateQueued) false) ((stateDone) false) ((stateFailed) false) ((stateCancelled) false))
