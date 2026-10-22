(module aslAgentCore/statemachine :x [assertTransition isTerminalState? validTransition?] :i [(tasktypes :a tt)])

fn isTerminalState? state: tt/TaskState -> Bool
  (match state ((stateDone) true) ((stateFailed) true) ((stateCancelled) true) (_ false))

fn validTransition? from: tt/TaskState to: tt/TaskState -> Bool
  (match from ((stateQueued) (match to ((stateRouting) true) ((stateCancelled) true) (_ false))) ((stateRouting) (match to ((stateClarification) true) ((stateReady) true) ((stateFailed) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateClarification) (match to ((stateRouting) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateReady) (match to ((stateExecuting) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateExecuting) (match to ((stateVerifying) true) ((stateFailed) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateVerifying) (match to ((stateDone) true) ((stateFailed) true) ((stateExecuting) true) ((stateQueued) true) (_ false))) (_ false))

fn assertTransition from: tt/TaskState to: tt/TaskState -> (Result tt/TaskState Str)
  (if (validTransition? from to) (ok to) (err "Illegal state transition"))
