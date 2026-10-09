(module aslVoice/voiceSettle :x [SettleAction BurstState SettleStepResult makeInitialBurstState ingestTranscriptFragment stepSettleTimer releaseBurstNow ceilingReached timeoutSettled holdOngoing quietEdge instantRelease] :i [(asl-text/string :a s)])

(enum SettleAction (:c holdOngoing [] "Burst is accumulating speech fragments") (:c quietEdge [] "Pause detected at quiet edge") (:c timeoutSettled [] "Settle timer fired, releasing burst") (:c ceilingReached [] "30s ceiling reached, force-releasing burst") (:c instantRelease [] "Grammatical endturn triggered instant release"))

(schema BurstState (:f isActive Bool) (:f firstArrivalMs I64) (:f lastArrivalMs I64) (:f dueAtMs I64) (:f messageCount I64) (:f accumulatedTranscript Str) (:f isHeld Bool))

(schema SettleStepResult (:f action SettleAction) (:f nextState BurstState) (:f shouldDispatch Bool) (:f finalTranscript Str) (:f heldDurationMs I64))

fn makeInitialBurstState -> BurstState
  (BurstState :isActive false :firstArrivalMs 0 :lastArrivalMs 0 :dueAtMs 0 :messageCount 0 :accumulatedTranscript "" :isHeld false)

fn ingestTranscriptFragment state: BurstState fragment: Str nowMs: I64 settleMs: I64 maxHoldMs: I64 -> BurstState
  (let [(clean (stringTrim fragment))] (if (not state.isActive) (BurstState :isActive true :firstArrivalMs nowMs :lastArrivalMs nowMs :dueAtMs (+ nowMs settleMs) :messageCount 1 :accumulatedTranscript clean :isHeld true) (let [(prev state.accumulatedTranscript) (merged (if (= prev "") clean (str prev " " clean))) (ceiling (+ state.firstArrivalMs maxHoldMs)) (normalDue (+ nowMs settleMs)) (effectiveDue (if (> normalDue ceiling) ceiling normalDue))] (with state :isActive true :lastArrivalMs nowMs :dueAtMs effectiveDue :messageCount (+ state.messageCount 1) :accumulatedTranscript merged :isHeld true))))

fn stepSettleTimer state: BurstState nowMs: I64 maxHoldMs: I64 -> SettleStepResult
  (if (not state.isActive) (SettleStepResult :action (holdOngoing) :nextState state :shouldDispatch false :finalTranscript "" :heldDurationMs 0) (let [(firstAt state.firstArrivalMs) (heldMs (- nowMs firstAt)) (dueAt state.dueAtMs) (transcript state.accumulatedTranscript)] (cond ((>= heldMs maxHoldMs) (SettleStepResult :action (ceilingReached) :nextState (makeInitialBurstState) :shouldDispatch true :finalTranscript transcript :heldDurationMs heldMs)) ((>= nowMs dueAt) (SettleStepResult :action (timeoutSettled) :nextState (makeInitialBurstState) :shouldDispatch true :finalTranscript transcript :heldDurationMs heldMs)) (else (SettleStepResult :action (holdOngoing) :nextState state :shouldDispatch false :finalTranscript "" :heldDurationMs heldMs)))))

fn releaseBurstNow state: BurstState nowMs: I64 -> SettleStepResult
  (if (not state.isActive) (SettleStepResult :action (instantRelease) :nextState state :shouldDispatch false :finalTranscript "" :heldDurationMs 0) (let [(heldMs (- nowMs state.firstArrivalMs)) (transcript state.accumulatedTranscript)] (SettleStepResult :action (instantRelease) :nextState (makeInitialBurstState) :shouldDispatch true :finalTranscript transcript :heldDurationMs heldMs)))
