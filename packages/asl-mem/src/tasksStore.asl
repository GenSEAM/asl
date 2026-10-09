(module aslMem/tasksStore :x [TaskReceipt AnticipatedRisk TaskTolerance TaskRecord makeTaskReceipt receiptIsVerified? formatReceiptAsn makeAnticipatedRisk makeTaskTolerance taskIsWithinLeeway? taskHasEscalationTrigger? formatAnticipatedRiskAsn formatTaskToleranceAsn makeHolisticTask makeTask makeGapTask makeCyberneticTask taskFormatAsn taskFormatHolisticAsn state PostAction PostActionQueue makePostAction makePostActionQueue postActionEnqueue postActionDrain formatPostActionAsn] :i [(asl-text/escape :a esc)])

(schema TaskReceipt (:f exitCode I64) (:f durationMs I64) (:f rssMb I64) (:f assertsEvaluated I64) (:f testsPassed I64) (:f testsFailed I64) (:f diffHash Str) (:f checkedInvariants (List Str)))

fn makeTaskReceipt exitCode: I64 durationMs: I64 rssMb: I64 assertsEvaluated: I64 testsPassed: I64 testsFailed: I64 diffHash: Str checkedInvariants: (List Str) -> TaskReceipt
  (TaskReceipt :exitCode exitCode :durationMs durationMs :rssMb rssMb :assertsEvaluated assertsEvaluated :testsPassed testsPassed :testsFailed testsFailed :diffHash diffHash :checkedInvariants checkedInvariants)

fn receiptIsVerified? receipt: TaskReceipt -> Bool
  (and (= receipt.exitCode 0) (and (= receipt.testsFailed 0) (> receipt.assertsEvaluated 0)))

fn formatReceiptAsn receipt: TaskReceipt -> Str
  (let [(invQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) receipt.checkedInvariants)) (invStr (str "[" (stringJoin invQuoted " ") "]"))] (str "(:receipt" " :exit " (stringFromInt64 receipt.exitCode) " :duration-ms " (stringFromInt64 receipt.durationMs) " :rss-mb " (stringFromInt64 receipt.rssMb) " :asserts " (stringFromInt64 receipt.assertsEvaluated) " :passed " (stringFromInt64 receipt.testsPassed) " :failed " (stringFromInt64 receipt.testsFailed) " :hash \"" receipt.diffHash "\"" " :invariants " invStr ")"))

(schema AnticipatedRisk (:f condition Str) (:f impact Str) (:f prescribedMitigation Str) (:f contingencyGate Str))

(schema TaskTolerance (:f strictInvariants (List Str)) (:f varianceLeeway (List Str)) (:f anticipatedRisks (List AnticipatedRisk)) (:f escalationTriggers (List Str)))

fn makeAnticipatedRisk condition: Str impact: Str mitigation: Str gate: Str -> AnticipatedRisk
  (AnticipatedRisk :condition condition :impact impact :prescribedMitigation mitigation :contingencyGate gate)

fn makeTaskTolerance invariants: (List Str) leeway: (List Str) risks: (List AnticipatedRisk) triggers: (List Str) -> TaskTolerance
  (TaskTolerance :strictInvariants invariants :varianceLeeway leeway :anticipatedRisks risks :escalationTriggers triggers)

fn taskIsWithinLeeway? tolerance: TaskTolerance proposedAction: Str -> Bool
  (let [(violates (filter (fn [(inv Str)] -> Bool (= inv proposedAction)) tolerance.strictInvariants)) (permitted (filter (fn [(lee Str)] -> Bool (= lee proposedAction)) tolerance.varianceLeeway))] (and (= (listLength violates) 0) (> (listLength permitted) 0)))

fn taskHasEscalationTrigger? tolerance: TaskTolerance eventDesc: Str -> Bool
  (let [(matches (filter (fn [(trig Str)] -> Bool (= trig eventDesc)) tolerance.escalationTriggers))] (> (listLength matches) 0))

fn formatAnticipatedRiskAsn risk: AnticipatedRisk -> Str
  (str "(:risk :condition \"" (esc/escapeAsnStr risk.condition) "\" :impact \"" (esc/escapeAsnStr risk.impact) "\" :mitigation \"" (esc/escapeAsnStr risk.prescribedMitigation) "\" :gate \"" (esc/escapeAsnStr risk.contingencyGate) "\")")

fn formatTaskToleranceAsn tolerance: TaskTolerance -> Str
  (let [(invQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) tolerance.strictInvariants)) (invStr (str "[" (stringJoin invQuoted " ") "]")) (leeQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) tolerance.varianceLeeway)) (leeStr (str "[" (stringJoin leeQuoted " ") "]")) (riskStrs (map (fn [(r AnticipatedRisk)] -> Str (formatAnticipatedRiskAsn r)) tolerance.anticipatedRisks)) (riskBody (stringJoin riskStrs " ")) (trigQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) tolerance.escalationTriggers)) (trigStr (str "[" (stringJoin trigQuoted " ") "]"))] (str "(:tolerance :strict " invStr " :leeway " leeStr " :risks [" riskBody "] :escalate " trigStr ")"))

(schema TaskRecord (:f id Str) (:f parentId Str) (:f phase Str) (:f title Str) (:f kind Str) (:f lane Str) (:f state Str) (:f priority Str) (:f ownerRole Str) (:f createdAt I64) (:f updatedAt I64) (:f startedAt I64) (:f completedAt I64) (:f owns (List Str)) (:f targetSymbols (List Str)) (:f relatedSymbols (List Str)) (:f dependsOn (List Str)) (:f gate Str) (:f why Str) (:f spec Str) (:f acceptanceCriteria (List Str)) (:f stepIndex I64) (:f actionDag (List Str)) (:f handoffContext Str) (:f receipts (List Str)) (:f sessionId Str) (:f leaseExpiresAt I64) (:f effort Str) (:f risk Str) (:f rootCause Str) (:f consequences (List Str)) (:f drawbacks (List Str)))

fn makeHolisticTask id: Str parentId: Str phase: Str title: Str kind: Str lane: Str state: Str priority: Str ownerRole: Str createdAt: I64 owns: (List Str) targetSymbols: (List Str) relatedSymbols: (List Str) dependsOn: (List Str) gate: Str why: Str spec: Str acceptanceCriteria: (List Str) actionDag: (List Str) -> TaskRecord
  (TaskRecord :id id :parentId parentId :phase phase :title title :kind kind :lane lane :state state :priority priority :ownerRole ownerRole :createdAt createdAt :updatedAt createdAt :startedAt 0 :completedAt 0 :owns owns :targetSymbols targetSymbols :relatedSymbols relatedSymbols :dependsOn dependsOn :gate gate :why why :spec spec :acceptanceCriteria acceptanceCriteria :stepIndex 0 :actionDag actionDag :handoffContext "" :receipts (list) :sessionId "" :leaseExpiresAt 0 :effort "m" :risk "low" :rootCause "" :consequences (list) :drawbacks (list))

fn makeTask id: Str phase: Str title: Str lane: Str state: Str priority: Str createdAt: I64 owns: (List Str) dependsOn: (List Str) gate: Str why: Str -> TaskRecord
  (TaskRecord :id id :parentId "" :phase phase :title title :kind "code-mutation" :lane lane :state state :priority priority :ownerRole "implementer" :createdAt createdAt :updatedAt createdAt :startedAt 0 :completedAt 0 :owns owns :targetSymbols (list) :relatedSymbols (list) :dependsOn dependsOn :gate gate :why why :spec "" :acceptanceCriteria (list) :stepIndex 0 :actionDag (list) :handoffContext "" :receipts (list) :sessionId "" :leaseExpiresAt 0 :effort "s" :risk "low" :rootCause "" :consequences (list) :drawbacks (list))

fn makeGapTask id: Str phase: Str title: Str lane: Str priority: Str createdAt: I64 owns: (List Str) gate: Str why: Str effort: Str risk: Str rootCause: Str consequences: (List Str) drawbacks: (List Str) -> TaskRecord
  (TaskRecord :id id :parentId "" :phase phase :title title :kind "gap" :lane lane :state "queued" :priority priority :ownerRole "auditor" :createdAt createdAt :updatedAt createdAt :startedAt 0 :completedAt 0 :owns owns :targetSymbols (list) :relatedSymbols (list) :dependsOn (list) :gate gate :why why :spec rootCause :acceptanceCriteria (list "exit-code 0" "strict-falsify") :stepIndex 0 :actionDag (list "Diagnose gap root cause" "Apply corrective delta" "Reconcile gate") :handoffContext "" :receipts (list) :sessionId "" :leaseExpiresAt 0 :effort effort :risk risk :rootCause rootCause :consequences consequences :drawbacks drawbacks)

fn makeCyberneticTask id: Str phase: Str title: Str kind: Str lane: Str state: Str priority: Str createdAt: I64 owns: (List Str) dependsOn: (List Str) gate: Str why: Str effort: Str risk: Str rootCause: Str consequences: (List Str) drawbacks: (List Str) -> TaskRecord
  (TaskRecord :id id :parentId "" :phase phase :title title :kind kind :lane lane :state state :priority priority :ownerRole "implementer" :createdAt createdAt :updatedAt createdAt :startedAt 0 :completedAt 0 :owns owns :targetSymbols (list) :relatedSymbols (list) :dependsOn dependsOn :gate gate :why why :spec "" :acceptanceCriteria (list) :stepIndex 0 :actionDag (list) :handoffContext "" :receipts (list) :sessionId "" :leaseExpiresAt 0 :effort effort :risk risk :rootCause rootCause :consequences consequences :drawbacks drawbacks)

fn taskFormatAsn task: TaskRecord -> Str
  (let [(ownsQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.owns)) (ownsStr (str "[" (stringJoin ownsQuoted " ") "]")) (depsQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.dependsOn)) (depsStr (str "[" (stringJoin depsQuoted " ") "]")) (rcStr (str "[" (stringJoin task.receipts " ") "]")) (consQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.consequences)) (consStr (str "[" (stringJoin consQuoted " ") "]")) (drawQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.drawbacks)) (drawStr (str "[" (stringJoin drawQuoted " ") "]"))] (str "(:task\n  :id \"" task.id "\"\n  :phase \"" task.phase "\"\n  :title \"" (esc/escapeAsnStr task.title) "\"\n  :kind :" task.kind "\n  :lane \"" task.lane "\"\n  :state :" task.state "\n  :priority :" task.priority "\n  :effort :" task.effort "\n  :risk :" task.risk (if (= task.rootCause "") "" (str "\n  :rootCause \"" (esc/escapeAsnStr task.rootCause) "\"")) (if (= (listLength task.consequences) 0) "" (str "\n  :consequences " consStr)) (if (= (listLength task.drawbacks) 0) "" (str "\n  :drawbacks " drawStr)) "\n  :createdAt " (stringFromInt64 task.createdAt) "\n  :updatedAt " (stringFromInt64 task.updatedAt) "\n  :owns " ownsStr "\n  :dependsOn " depsStr "\n  :gate \"" (esc/escapeAsnStr task.gate) "\"\n  :why \"" (esc/escapeAsnStr task.why) "\"\n  :receipts " rcStr ")\n"))

fn taskFormatHolisticAsn task: TaskRecord -> Str
  (let [(ownsQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.owns)) (ownsStr (str "[" (stringJoin ownsQuoted " ") "]")) (tsymQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.targetSymbols)) (tsymStr (str "[" (stringJoin tsymQuoted " ") "]")) (rsymQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.relatedSymbols)) (rsymStr (str "[" (stringJoin rsymQuoted " ") "]")) (depsQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.dependsOn)) (depsStr (str "[" (stringJoin depsQuoted " ") "]")) (critQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.acceptanceCriteria)) (critStr (str "[" (stringJoin critQuoted " ") "]")) (dagQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.actionDag)) (dagStr (str "[" (stringJoin dagQuoted " ") "]")) (rcStr (str "[" (stringJoin task.receipts " ") "]")) (consQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.consequences)) (consStr (str "[" (stringJoin consQuoted " ") "]")) (drawQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) task.drawbacks)) (drawStr (str "[" (stringJoin drawQuoted " ") "]"))] (str "(:task\n  :id \"" task.id "\"\n  :parentId \"" task.parentId "\"\n  :phase \"" task.phase "\"\n  :title \"" (esc/escapeAsnStr task.title) "\"\n  :kind :" task.kind "\n  :lane \"" task.lane "\"\n  :state :" task.state "\n  :priority :" task.priority "\n  :effort :" task.effort "\n  :risk :" task.risk "\n  :ownerRole \"" task.ownerRole "\"" (if (= task.rootCause "") "" (str "\n  :rootCause \"" (esc/escapeAsnStr task.rootCause) "\"")) (if (= (listLength task.consequences) 0) "" (str "\n  :consequences " consStr)) (if (= (listLength task.drawbacks) 0) "" (str "\n  :drawbacks " drawStr)) "\n  :createdAt " (stringFromInt64 task.createdAt) "\n  :updatedAt " (stringFromInt64 task.updatedAt) "\n  :startedAt " (stringFromInt64 task.startedAt) "\n  :completedAt " (stringFromInt64 task.completedAt) "\n  :owns " ownsStr "\n  :targetSymbols " tsymStr "\n  :relatedSymbols " rsymStr "\n  :dependsOn " depsStr "\n  :gate \"" (esc/escapeAsnStr task.gate) "\"\n  :why \"" (esc/escapeAsnStr task.why) "\"\n  :spec \"" (esc/escapeAsnStr task.spec) "\"\n  :acceptanceCriteria " critStr "\n  :stepIndex " (stringFromInt64 task.stepIndex) "\n  :actionDag " dagStr "\n  :handoffContext \"" (esc/escapeAsnStr task.handoffContext) "\"\n  :sessionId \"" (esc/escapeAsnStr task.sessionId) "\"\n  :leaseExpiresAt " (stringFromInt64 task.leaseExpiresAt) "\n  :receipts " rcStr ")\n"))

fn state task: TaskRecord -> Str
  task.state

(schema PostAction (:f actionId Str) (:f triggerState Str) (:f kind Str) (:f targetPhase Str) (:f description Str) (:f payload Str))

(schema PostActionQueue (:f queueId Str) (:f actions (List PostAction)) (:f processedCount I64))

fn makePostAction actionId: Str triggerState: Str kind: Str targetPhase: Str description: Str payload: Str -> PostAction
  (PostAction :actionId actionId :triggerState triggerState :kind kind :targetPhase targetPhase :description description :payload payload)

fn makePostActionQueue queueId: Str -> PostActionQueue
  (PostActionQueue :queueId queueId :actions (list) :processedCount 0)

fn postActionEnqueue q: PostActionQueue action: PostAction -> PostActionQueue
  (with q :actions (listAppend q.actions (list action)))

fn postActionDrain q: PostActionQueue -> PostActionQueue
  (let [(count (listLength q.actions))] (with q :actions (list) :processedCount (+ q.processedCount count)))

fn formatPostActionAsn action: PostAction -> Str
  (str "(:post-action :id \"" (esc/escapeAsnStr action.actionId) "\"" " :trigger \"" (esc/escapeAsnStr action.triggerState) "\"" " :kind \"" (esc/escapeAsnStr action.kind) "\"" " :target-phase \"" (esc/escapeAsnStr action.targetPhase) "\"" " :description \"" (esc/escapeAsnStr action.description) "\"" " :payload \"" (esc/escapeAsnStr action.payload) "\")")
