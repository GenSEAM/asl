(module aslMem/taskRecovery :x [RecoverySnapshot recoverTaskSession resumeActionDag extractHandoffState verifyCheckpointIntegrity formatRecoveryAsn snapshot resume extract verify formatRecovery] :i [(tasksStore :a t) (asl-text/escape :a esc)])

(schema RecoverySnapshot (:f taskId Str) (:f previousSessionId Str) (:f recoveredSessionId Str) (:f stepIndex I64) (:f totalSteps I64) (:f remainingSteps (List Str)) (:f handoffState Str) (:f isValid Bool) (:f recoveredAt I64))

fn verifyCheckpointIntegrity task: t/TaskRecord -> Bool
  (let [(dagLen (listLength task.actionDag)) (idx task.stepIndex) (handoff task.handoffContext)] (and (> (stringLength task.id) 0) (and (>= idx 0) (and (<= idx dagLen) (not (stringContains? handoff "CORRUPTED"))))))

fn extractHandoffState task: t/TaskRecord -> Str
  (if (verifyCheckpointIntegrity task) task.handoffContext "")

fn resumeActionDag actionDag: (List Str) fromStepIndex: I64 -> (List Str)
  (let [(total (listLength actionDag))] (if (<= fromStepIndex 0) actionDag (if (>= fromStepIndex total) (list) (optionOr (listSlice actionDag fromStepIndex total) (list)))))

fn recoverTaskSession task: t/TaskRecord newSessionId: Str nowEpoch: I64 -> RecoverySnapshot
  (let [(valid? (verifyCheckpointIntegrity task)) (handoff (extractHandoffState task)) (remaining (resumeActionDag task.actionDag task.stepIndex))] (RecoverySnapshot :taskId task.id :previousSessionId task.sessionId :recoveredSessionId newSessionId :stepIndex task.stepIndex :totalSteps (listLength task.actionDag) :remainingSteps remaining :handoffState handoff :isValid valid? :recoveredAt nowEpoch))

fn formatRecoveryAsn snap: RecoverySnapshot -> Str
  (let [(stepsQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) snap.remainingSteps)) (stepsStr (str "[" (stringJoin stepsQuoted " ") "]"))] (str "(:recovery-snapshot\n" "  :task-id \"" (esc/escapeAsnStr snap.taskId) "\"\n" "  :previous-session-id \"" (esc/escapeAsnStr snap.previousSessionId) "\"\n" "  :recovered-session-id \"" (esc/escapeAsnStr snap.recoveredSessionId) "\"\n" "  :step-index " (stringFromInt64 snap.stepIndex) "\n" "  :total-steps " (stringFromInt64 snap.totalSteps) "\n" "  :remaining-steps " stepsStr "\n" "  :handoff-state \"" (esc/escapeAsnStr snap.handoffState) "\"\n" "  :is-valid " (if snap.isValid "true" "false") "\n" "  :recovered-at " (stringFromInt64 snap.recoveredAt) ")\n"))

fn snapshot task: t/TaskRecord newSessionId: Str nowEpoch: I64 -> RecoverySnapshot
  (recoverTaskSession task newSessionId nowEpoch)

fn resume actionDag: (List Str) fromStepIndex: I64 -> (List Str)
  (resumeActionDag actionDag fromStepIndex)

fn extract task: t/TaskRecord -> Str
  (extractHandoffState task)

fn verify task: t/TaskRecord -> Bool
  (verifyCheckpointIntegrity task)

fn formatRecovery snap: RecoverySnapshot -> Str
  (formatRecoveryAsn snap)
