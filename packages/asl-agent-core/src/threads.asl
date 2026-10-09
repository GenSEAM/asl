(module aslAgentCore/threads :x [ThreadRecord ThreadHandoff threadCreate threadAddTask threadLinkFollowup threadAttachHandoff threadGetParentBrief threadIsActive?] :i [(tasktypes :a tt)])

(schema ThreadHandoff (:f parentTaskId Str) (:f terminalSummary Str) (:f artifacts (List Str)) (:f completedAt I64))

(schema ThreadRecord (:f id Str) (:f lane Str) (:f rootTaskId Str) (:f taskIds (List Str)) (:f parentId (Option Str)) (:f handoff (Option ThreadHandoff)) (:f active Bool) (:f createdAt I64) (:f updatedAt I64))

fn threadCreate id: Str lane: Str rootTaskId: Str nowMs: I64 -> ThreadRecord
  (ThreadRecord :id id :lane lane :rootTaskId rootTaskId :taskIds (list rootTaskId) :parentId (none) :handoff (none) :active true :createdAt nowMs :updatedAt nowMs)

fn threadAddTask th: ThreadRecord taskId: Str nowMs: I64 -> ThreadRecord
  (with th :taskIds (listAppend th.taskIds (list taskId)) :updatedAt nowMs)

fn threadAttachHandoff th: ThreadRecord handoff: ThreadHandoff nowMs: I64 -> ThreadRecord
  (with th :parentId (some handoff.parentTaskId) :handoff (some handoff) :updatedAt nowMs)

fn threadLinkFollowup parentTh: ThreadRecord childTask: tt/TaskRecord handoff: ThreadHandoff nowMs: I64 -> (Pair ThreadRecord tt/TaskRecord)
  (let [(parentId handoff.parentTaskId) (summary handoff.terminalSummary) (updatedTh (with parentTh :taskIds (listAppend parentTh.taskIds (list childTask.id)) :parentId (some parentId) :handoff (some handoff) :active true :updatedAt nowMs)) (briefBlock (str "[Parent Task Handoff: " parentId "]\n" summary)) (augmentedPayload (if (stringEmpty? childTask.payload) briefBlock (str briefBlock "\n\n" childTask.payload))) (updatedChild (tt/TaskRecord :id childTask.id :lane parentTh.lane :projectPath childTask.projectPath :state childTask.state :priority childTask.priority :createdAt childTask.createdAt :updatedAt nowMs :payload augmentedPayload))] (pair updatedTh updatedChild))

fn threadGetParentBrief th: ThreadRecord -> (Option Str)
  (mt th.handoff ((some h) (some h.terminalSummary)) ((none) (none)))

fn threadIsActive? th: ThreadRecord -> Bool
  th.active
