(module aslHarness/supervisor :x [SupervisorVerdict SupervisorState makeSupervisorState runSupervisorCycle adjudicateCleanAudit rollbackTaskState setTaskCheckpoint getTaskCheckpoint] :i [(delegate :a del) (handoff :a hnd) (taskWorker :a tw)])

(schema SupervisorVerdict (:f taskId Str) (:f chosenLane Str) (:f status Str) (:f confidence Float) (:f hint Str))

(schema SupervisorState (:f activeTasks (List Str)) (:f checkpoints (Map Str Str)) (:f speculativeEnabled Bool) (:f cleanAuditEnabled Bool))

fn makeSupervisorState -> SupervisorState
  (SupervisorState :activeTasks (list) :checkpoints (mapEmpty) :speculativeEnabled true :cleanAuditEnabled true)

fn filterOutTask tasks: (List Str) target: Str -> (List Str)
  (if (listEmpty? tasks) (list) (let [(h (optionOr (listHead tasks) "")) (t (optionOr (listTail tasks) (list)))] (if (= h target) (filterOutTask t target) (cons h (filterOutTask t target)))))

fn setTaskCheckpoint st: SupervisorState taskId: Str hash: Str -> SupervisorState
  (with st :checkpoints (mapSet st.checkpoints taskId hash))

fn getTaskCheckpoint st: SupervisorState taskId: Str -> Str
  (optionOr (mapGet st.checkpoints taskId) "")

fn adjudicateCleanAudit audit: hnd/CleanAuditEnvelope -> SupervisorVerdict
  (let [(code audit.exitCode) (lane audit.candidateLane) (taskId audit.taskId) (err audit.stderr)] (if (= code 0) (SupervisorVerdict :taskId taskId :chosenLane lane :status "pass" :confidence 1.0 :hint "") (if (or (stringContains? err "syntax") (or (stringContains? err "timeout") (stringContains? err "delimiter"))) (SupervisorVerdict :taskId taskId :chosenLane "none" :status "retry" :confidence 0.85 :hint (str "Fix syntax and verify delimiter balance for " taskId)) (SupervisorVerdict :taskId taskId :chosenLane "none" :status "fail" :confidence 0.95 :hint ""))))

fn rollbackTaskState st: SupervisorState taskId: Str -> SupervisorState
  (let [(remaining (filterOutTask st.activeTasks taskId))] (with st :activeTasks remaining))

fn runSupervisorCycle st: SupervisorState audit: hnd/CleanAuditEnvelope -> SupervisorVerdict
  (let [(verdict (adjudicateCleanAudit audit))] (if (!= verdict.status "pass") (let [(rolledBack (rollbackTaskState st audit.taskId))] verdict) verdict))
