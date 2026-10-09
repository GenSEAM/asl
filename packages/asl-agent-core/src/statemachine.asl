(module aslAgentCore/statemachine :x [assertTransition isTerminalState? validTransition?] :i [(tasktypes :a tt)])

fn isTerminalState? state: tt/TaskState -> Bool
  (mt state ((stateDone) true) ((stateFailed) true) ((stateCancelled) true) (_ false))

fn validTransition? from: tt/TaskState to: tt/TaskState -> Bool
  (mt from ((stateQueued) (mt to ((stateRouting) true) ((stateCancelled) true) (_ false))) ((stateRouting) (mt to ((stateClarification) true) ((stateReady) true) ((stateFailed) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateClarification) (mt to ((stateRouting) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateReady) (mt to ((stateExecuting) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateExecuting) (mt to ((stateVerifying) true) ((stateFailed) true) ((stateCancelled) true) ((stateQueued) true) (_ false))) ((stateVerifying) (mt to ((stateDone) true) ((stateFailed) true) ((stateExecuting) true) ((stateQueued) true) (_ false))) (_ false))

fn assertTransition from: tt/TaskState to: tt/TaskState -> (Result tt/TaskState Str)
  (if (validTransition? from to) (ok to) (err "Illegal state transition"))
