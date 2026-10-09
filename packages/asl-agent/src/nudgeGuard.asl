(module aslAgent/nudgeGuard :x [NudgeEvent NudgeGuardState makeInitialNudgeGuard recordTaskOutcome evaluateProactiveNudge holdDisruptiveIntent releaseHeldIntentsOnIdle] :i [(asl-text/string :a s)])

(schema NudgeEvent (:f taskId Str) (:f reason Str) (:f text Str) (:f timestampMs Int64))

(schema NudgeGuardState (:f lastNudgeTimeMs Int64) (:f consecutiveFailures Int64) (:f activeProject Str) (:f heldIntentIds (List Str)))

fn makeInitialNudgeGuard -> NudgeGuardState
  (NudgeGuardState :lastNudgeTimeMs 0 :consecutiveFailures 0 :activeProject "" :heldIntentIds (list))

fn recordTaskOutcome state: NudgeGuardState project: Str isSuccess: Bool -> NudgeGuardState
  (if isSuccess (with state :consecutiveFailures 0 :activeProject project) (let [(prevProj state.activeProject) (curStreak (if (= prevProj project) state.consecutiveFailures 0))] (with state :consecutiveFailures (+ curStreak 1) :activeProject project)))

fn evaluateProactiveNudge state: NudgeGuardState nowMs: Int64 -> (Option NudgeEvent)
  (let [(streak state.consecutiveFailures) (lastTime state.lastNudgeTimeMs) (elapsed (- nowMs lastTime))] (if (and (>= streak 3) (>= elapsed 60000)) (some (NudgeEvent :taskId state.activeProject :reason "failure-run" :text (str "Project " state.activeProject " has failed 3 times consecutively") :timestampMs nowMs)) (none)))

fn holdDisruptiveIntent state: NudgeGuardState intentId: Str -> NudgeGuardState
  (let [(current state.heldIntentIds) (updated (listAppend current (list intentId)))] (with state :heldIntentIds updated))

fn releaseHeldIntentsOnIdle state: NudgeGuardState -> (Pair NudgeGuardState (List Str))
  (let [(drained state.heldIntentIds) (cleared (with state :heldIntentIds (list)))] (pair cleared drained))
