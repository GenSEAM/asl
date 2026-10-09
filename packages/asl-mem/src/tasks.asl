(module aslMem/tasks
  :x [TaskReceipt
      AnticipatedRisk
      TaskTolerance
      TaskRecord
      PostAction
      PostActionQueue
      makeTaskReceipt
      receiptIsVerified?
      formatReceiptAsn
      makeHolisticTask
      makeTask
      makeGapTask
      makeCyberneticTask
      taskOwnsFile?
      taskOwnsIntersect?
      taskOverlapFiles
      taskOverlapBlastRadius?
      taskDependenciesSatisfied?
      taskParallelEligible?
      taskIsReady?
      taskFindReady
      taskClaim
      taskClaimSession
      taskIsClaimedBy?
      taskIsLeaseExpired?
      taskRecoverSession
      taskSpawnSubtask
      taskStart
      taskAdvanceStep
      taskCaptureHandoff
      taskAttachReceipt
      taskComplete
      taskFormatAsn
      taskFormatHolisticAsn
      makeAnticipatedRisk
      makeTaskTolerance
      taskIsWithinLeeway?
      taskHasEscalationTrigger?
      formatAnticipatedRiskAsn
      formatTaskToleranceAsn
      claim
      state
      settle
      makePostAction
      makePostActionQueue
      postActionEnqueue
      postActionDrain
      formatPostActionAsn]
  :i [(tasksStore :a ts)
      (tasksDag :a dag)
      (tasksLease :a lease)])

fn makeTaskReceipt exitCode: I64 durationMs: I64 rssMb: I64 assertsEvaluated: I64 testsPassed: I64 testsFailed: I64 diffHash: Str checkedInvariants: (List Str) -> ts/TaskReceipt
  (ts/makeTaskReceipt exitCode durationMs rssMb assertsEvaluated testsPassed testsFailed diffHash checkedInvariants)

fn receiptIsVerified? receipt: ts/TaskReceipt -> Bool
  (ts/receiptIsVerified? receipt)

fn formatReceiptAsn receipt: ts/TaskReceipt -> Str
  (ts/formatReceiptAsn receipt)

fn makeAnticipatedRisk condition: Str impact: Str mitigation: Str gate: Str -> ts/AnticipatedRisk
  (ts/makeAnticipatedRisk condition impact mitigation gate)

fn makeTaskTolerance invariants: (List Str) leeway: (List Str) risks: (List ts/AnticipatedRisk) triggers: (List Str) -> ts/TaskTolerance
  (ts/makeTaskTolerance invariants leeway risks triggers)

fn taskIsWithinLeeway? tolerance: ts/TaskTolerance proposedAction: Str -> Bool
  (ts/taskIsWithinLeeway? tolerance proposedAction)

fn taskHasEscalationTrigger? tolerance: ts/TaskTolerance eventDesc: Str -> Bool
  (ts/taskHasEscalationTrigger? tolerance eventDesc)

fn formatAnticipatedRiskAsn risk: ts/AnticipatedRisk -> Str
  (ts/formatAnticipatedRiskAsn risk)

fn formatTaskToleranceAsn tolerance: ts/TaskTolerance -> Str
  (ts/formatTaskToleranceAsn tolerance)

fn makeHolisticTask id: Str parentId: Str phase: Str title: Str kind: Str lane: Str state: Str priority: Str ownerRole: Str createdAt: I64 owns: (List Str) targetSymbols: (List Str) relatedSymbols: (List Str) dependsOn: (List Str) gate: Str why: Str spec: Str acceptanceCriteria: (List Str) actionDag: (List Str) -> ts/TaskRecord
  (ts/makeHolisticTask id parentId phase title kind lane state priority ownerRole createdAt owns targetSymbols relatedSymbols dependsOn gate why spec acceptanceCriteria actionDag)

fn makeTask id: Str phase: Str title: Str lane: Str state: Str priority: Str createdAt: I64 owns: (List Str) dependsOn: (List Str) gate: Str why: Str -> ts/TaskRecord
  (ts/makeTask id phase title lane state priority createdAt owns dependsOn gate why)

fn makeGapTask id: Str phase: Str title: Str lane: Str priority: Str createdAt: I64 owns: (List Str) gate: Str why: Str effort: Str risk: Str rootCause: Str consequences: (List Str) drawbacks: (List Str) -> ts/TaskRecord
  (ts/makeGapTask id phase title lane priority createdAt owns gate why effort risk rootCause consequences drawbacks)

fn makeCyberneticTask id: Str phase: Str title: Str kind: Str lane: Str state: Str priority: Str createdAt: I64 owns: (List Str) dependsOn: (List Str) gate: Str why: Str effort: Str risk: Str rootCause: Str consequences: (List Str) drawbacks: (List Str) -> ts/TaskRecord
  (ts/makeCyberneticTask id phase title kind lane state priority createdAt owns dependsOn gate why effort risk rootCause consequences drawbacks)

fn taskFormatAsn task: ts/TaskRecord -> Str
  (ts/taskFormatAsn task)

fn taskFormatHolisticAsn task: ts/TaskRecord -> Str
  (ts/taskFormatHolisticAsn task)

fn state task: ts/TaskRecord -> Str
  (ts/state task)

fn makePostAction actionId: Str triggerState: Str kind: Str targetPhase: Str description: Str payload: Str -> ts/PostAction
  (ts/makePostAction actionId triggerState kind targetPhase description payload)

fn makePostActionQueue queueId: Str -> ts/PostActionQueue
  (ts/makePostActionQueue queueId)

fn postActionEnqueue q: ts/PostActionQueue action: ts/PostAction -> ts/PostActionQueue
  (ts/postActionEnqueue q action)

fn postActionDrain q: ts/PostActionQueue -> ts/PostActionQueue
  (ts/postActionDrain q)

fn formatPostActionAsn action: ts/PostAction -> Str
  (ts/formatPostActionAsn action)

fn taskOwnsFile? task: ts/TaskRecord file: Str -> Bool
  (dag/taskOwnsFile? task file)

fn taskOwnsIntersect? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (dag/taskOwnsIntersect? t1 t2)

fn taskOverlapFiles t1: ts/TaskRecord t2: ts/TaskRecord -> (List Str)
  (dag/taskOverlapFiles t1 t2)

fn taskOverlapBlastRadius? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (dag/taskOverlapBlastRadius? t1 t2)

fn taskDependenciesSatisfied? task: ts/TaskRecord completedIds: (List Str) -> Bool
  (dag/taskDependenciesSatisfied? task completedIds)

fn taskParallelEligible? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (dag/taskParallelEligible? t1 t2)

fn taskIsReady? task: ts/TaskRecord completedIds: (List Str) -> Bool
  (dag/taskIsReady? task completedIds)

fn taskFindReady tasks: (List ts/TaskRecord) completedIds: (List Str) -> (List ts/TaskRecord)
  (dag/taskFindReady tasks completedIds)

fn taskClaim task: ts/TaskRecord nowEpoch: I64 -> ts/TaskRecord
  (lease/taskClaim task nowEpoch)

fn taskClaimSession task: ts/TaskRecord sessionId: Str leaseMs: I64 nowEpoch: I64 -> ts/TaskRecord
  (lease/taskClaimSession task sessionId leaseMs nowEpoch)

fn taskIsClaimedBy? task: ts/TaskRecord sessionId: Str -> Bool
  (lease/taskIsClaimedBy? task sessionId)

fn taskIsLeaseExpired? task: ts/TaskRecord nowEpoch: I64 -> Bool
  (lease/taskIsLeaseExpired? task nowEpoch)

fn taskRecoverSession task: ts/TaskRecord newSessionId: Str leaseMs: I64 nowEpoch: I64 -> ts/TaskRecord
  (lease/taskRecoverSession task newSessionId leaseMs nowEpoch)

fn taskSpawnSubtask parent: ts/TaskRecord subtaskId: Str title: Str owns: (List Str) nowEpoch: I64 -> ts/TaskRecord
  (lease/taskSpawnSubtask parent subtaskId title owns nowEpoch)

fn taskStart task: ts/TaskRecord nowEpoch: I64 -> ts/TaskRecord
  (lease/taskStart task nowEpoch)

fn taskAdvanceStep task: ts/TaskRecord nowEpoch: I64 -> ts/TaskRecord
  (lease/taskAdvanceStep task nowEpoch)

fn taskCaptureHandoff task: ts/TaskRecord contextSnapshot: Str nowEpoch: I64 -> ts/TaskRecord
  (lease/taskCaptureHandoff task contextSnapshot nowEpoch)

fn taskAttachReceipt task: ts/TaskRecord receipt: ts/TaskReceipt nowEpoch: I64 -> ts/TaskRecord
  (lease/taskAttachReceipt task receipt nowEpoch)

fn taskComplete task: ts/TaskRecord receipt: Str nowEpoch: I64 -> ts/TaskRecord
  (lease/taskComplete task receipt nowEpoch)

fn claim task: ts/TaskRecord nowEpoch: I64 -> ts/TaskRecord
  (lease/claim task nowEpoch)

fn settle task: ts/TaskRecord receipt: Str nowEpoch: I64 -> ts/TaskRecord
  (lease/settle task receipt nowEpoch)
