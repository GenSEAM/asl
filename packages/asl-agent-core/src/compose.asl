(module aslAgentCore/compose :x [GoalSpecification composeGoal composeFollowupGoal extractGoalDelta formatCumulativeSpec] :i [])

(schema GoalSpecification (:f primaryIntent Str) (:f cumulativeInstructions (List Str)) (:f refinements (List Str)) (:f parentContext (Option Str)) (:f turnCount I64))

fn composeGoal messages: (List Str) -> GoalSpecification
  (if (listEmpty? messages) (GoalSpecification :primaryIntent "" :cumulativeInstructions (list) :refinements (list) :parentContext (none) :turnCount 0) (let [(headMsg (optionOr (listHead messages) "")) (tailMsgs (optionOr (listTail messages) (list)))] (GoalSpecification :primaryIntent headMsg :cumulativeInstructions messages :refinements tailMsgs :parentContext (none) :turnCount (listLength messages))))

fn composeFollowupGoal parentSpec: GoalSpecification followupMsg: Str parentBrief: (Option Str) -> GoalSpecification
  (let [(rootIntent (if (stringEmpty? parentSpec.primaryIntent) followupMsg parentSpec.primaryIntent)) (updatedInstructions (listAppend parentSpec.cumulativeInstructions (list followupMsg))) (updatedRefinements (listAppend parentSpec.refinements (list followupMsg))) (nextContext (mt parentBrief ((some _) parentBrief) ((none) parentSpec.parentContext))) (nextTurns (+ parentSpec.turnCount 1))] (GoalSpecification :primaryIntent rootIntent :cumulativeInstructions updatedInstructions :refinements updatedRefinements :parentContext nextContext :turnCount nextTurns))

fn extractGoalDelta priorIntent: Str newMsg: Str -> Str
  (if (= priorIntent newMsg) "" (if (stringEmpty? priorIntent) newMsg (str "Refinement: " newMsg)))

fn formatCumulativeSpec spec: GoalSpecification -> Str
  (let [(pCtx (mt spec.parentContext ((some ctx) (str "Parent Context: " ctx "\n")) ((none) ""))) (instructions (fold (fn [(acc Str) (inst Str)] -> Str (let [(line (str "- " inst))] (if (stringEmpty? acc) line (str acc "\n" line)))) "" spec.cumulativeInstructions))] (str "Primary Intent: " spec.primaryIntent "\n" pCtx "Cumulative Instructions (" (stringFromInt64 spec.turnCount) " turns):\n" instructions))
