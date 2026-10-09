(module aslAgent/feedback :x [ClarificationOption RefinedRequirement DialogueStage IntentContract stageInterview stageCorridorNegotiation stageGrounded stageDelegated isAmbiguousPrompt? stripPoliteFluff refineUserPrompt formatClarifyingQuestion formatConciseDirective formatTradeoffBlock makeIntentContract groundIntentToMemory decomposeIntentToDag advanceDialogueStage] :i [(corridor :a corr) (taskDag :a dag)])

(schema ClarificationOption (:f key Str) (:f label Str))

(schema RefinedRequirement (:f originalPrompt Str) (:f clarifiedGoal Str) (:f targetFiles (List Str)) (:f acceptanceCriteria (List Str)) (:f isAmbiguous Bool))

(enum DialogueStage (:c stageInterview [] "Conversational discovery and ambiguity resolution") (:c stageCorridorNegotiation [] "Aligning invariants and degrees of freedom") (:c stageGrounded [] "Persisted to memory ledger, explain-once contract locked") (:c stageDelegated [] "Dispatched to Swarm Supervisor DAG for worker execution"))

(schema IntentContract (:f id Str) (:f title Str) (:f clarifiedGoal Str) (:f corridor corr/FreedomCorridor) (:f stage DialogueStage) (:f isGrounded Bool))

fn isAmbiguousPrompt? prompt: Str -> Bool
  (let [(trimmed (stringTrim prompt)) (len (stringLength trimmed))] (cond ((< len 15) true) ((and (not (stringContains? trimmed ".")) (not (stringContains? trimmed "/"))) true) ((stringStartsWith? trimmed "help") true) ((stringStartsWith? trimmed "do something") true) (else false)))

fn stripPoliteFluff text: Str -> Str
  (let [(t1 (stringReplace text "Certainly! I'd be happy to help with that." "")) (t2 (stringReplace t1 "Sure thing! " "")) (t3 (stringReplace t2 "Hello! " "")) (t4 (stringReplace t3 "I hope you are doing well. " "")) (t5 (stringReplace t4 "Please let me know if you need anything else." ""))] (stringTrim t5))

fn refineUserPrompt prompt: Str detectedFiles: (List Str) -> RefinedRequirement
  (let [(ambig (isAmbiguousPrompt? prompt)) (cleanPrompt (stripPoliteFluff prompt))] (if ambig (RefinedRequirement :originalPrompt prompt :clarifiedGoal (str "Clarification required: " cleanPrompt) :targetFiles detectedFiles :acceptanceCriteria (list "User selects execution target") :isAmbiguous true) (RefinedRequirement :originalPrompt prompt :clarifiedGoal cleanPrompt :targetFiles detectedFiles :acceptanceCriteria (list "Code compiles cleanly" "All test gates pass") :isAmbiguous false)))

fn formatClarifyingQuestion req: RefinedRequirement options: (List ClarificationOption) -> Str
  (let [(optStr (fold (fn [(acc Str) (opt ClarificationOption)] -> Str (str acc "\n  [" opt.key "] " opt.label)) "" options))] (str "Need clarification for: \"" req.originalPrompt "\"" optStr "\nSelect option:"))

fn formatConciseDirective req: RefinedRequirement -> Str
  (str "Goal: " req.clarifiedGoal " | Targets: " (stringFromInt64 (listLength req.targetFiles)) " files | Verification: " (stringJoin req.acceptanceCriteria "; "))

fn formatTradeoffBlock tradeoffs: (List Str) -> Str
  (if (listEmpty? tradeoffs) "" (str "Trade-offs: " (stringJoin tradeoffs ", ")))

fn makeIntentContract id: Str title: Str goal: Str corridor: corr/FreedomCorridor -> IntentContract
  (IntentContract :id id :title title :clarifiedGoal goal :corridor corridor :stage (stageCorridorNegotiation) :isGrounded false)

fn groundIntentToMemory intent: IntentContract -> Str
  (let [(corrAsn (corr/corridorToAsn intent.corridor))] (str "(:intent :id \"" intent.id "\" :title \"" intent.title "\" :goal \"" intent.clarifiedGoal "\" :grounded true :corridor " corrAsn ")"))

fn decomposeIntentToDag intent: IntentContract -> dag/TaskDAG
  (let [(t1 (dag/makeTaskNode (str intent.id "-scout") "Scout perceptual discovery and AST outline" "triage" (list))) (t2 (dag/makeTaskNode (str intent.id "-design") "Architectural concept and visual layout" "design" (list (str intent.id "-scout")))) (t3 (dag/makeTaskNode (str intent.id "-impl") "Deterministic implementation of verified changes" "coding" (list (str intent.id "-design")))) (t4 (dag/makeTaskNode (str intent.id "-audit") "Empirical gate verification and critic audit" "review" (list (str intent.id "-impl"))))] (dag/makeTaskDag (str "dag-" intent.id) (list t1 t2 t3 t4)))

fn advanceDialogueStage intent: IntentContract nextStage: DialogueStage -> IntentContract
  (let [(grounded? (mt nextStage ((stageGrounded) true) ((stageDelegated) true) ((stageInterview) false) ((stageCorridorNegotiation) false)))] (with intent :stage nextStage :isGrounded grounded?))
