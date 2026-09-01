(module asl-fsm/fsm
  :doc "Algebraic Finite State Machine engine in ASL Nano"
  :export [AgentState AgentEvent step is-terminal-state])

(dfe AgentState
  (:case idle [] "idle state")
  (:case planning [] "planning state")
  (:case coding [] "coding state")
  (:case reviewing [] "reviewing state")
  (:case success [] "success state")
  (:case failed [] "failed state"))

(dfe AgentEvent
  (:case start [] "start task")
  (:case plan-ready [] "plan generated")
  (:case code-ready [] "code generated")
  (:case review-pass [] "review passed")
  (:case review-fail [] "review failed")
  (:case reset [] "reset agent"))

(df step [(state AgentState) (event AgentEvent)] -> AgentState
  :doc "State transition function"
  (match state
    ((idle)
     (match event
       ((start) (:planning))
       (_ state)))
    ((planning)
     (match event
       ((plan-ready) (:coding))
       ((reset) (:idle))
       (_ state)))
    ((coding)
     (match event
       ((code-ready) (:reviewing))
       ((reset) (:idle))
       (_ state)))
    ((reviewing)
     (match event
       ((review-pass) (:success))
       ((review-fail) (:coding))
       ((reset) (:idle))
       (_ state)))
    (_ state)))

(df is-terminal-state [(state AgentState)] -> Bool
  :doc "Checks if state is terminal"
  (match state
    ((success) true)
    ((failed) true)
    (_ false)))
