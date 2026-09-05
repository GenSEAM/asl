(module asl-agent-core/fsm
  :d "Algebraic Finite State Machine engine in ASL"
  :x [AgentState AgentEvent step is-terminal-state])

(dfe AgentState
  (:c idle [] "idle state")
  (:c planning [] "planning state")
  (:c coding [] "coding state")
  (:c reviewing [] "reviewing state")
  (:c success [] "success state")
  (:c failed [] "failed state"))

(dfe AgentEvent
  (:c start [] "start task")
  (:c plan-ready [] "plan generated")
  (:c code-ready [] "code generated")
  (:c review-pass [] "review passed")
  (:c review-fail [] "review failed")
  (:c reset [] "reset agent"))

(df step [(state AgentState) (event AgentEvent)] -> AgentState
  :d "State transition function"
  (mt state
    ((idle)
     (mt event
       ((start) (planning))
       (_ state)))
    ((planning)
     (mt event
       ((plan-ready) (coding))
       ((reset) (idle))
       (_ state)))
    ((coding)
     (mt event
       ((code-ready) (reviewing))
       ((reset) (idle))
       (_ state)))
    ((reviewing)
     (mt event
       ((review-pass) (success))
       ((review-fail) (coding))
       ((reset) (idle))
       (_ state)))
    (_ state)))

(df is-terminal-state [(state AgentState)] -> Bool
  :d "Checks if state is terminal"
  (mt state
    ((success) true)
    ((failed) true)
    (_ false)))
