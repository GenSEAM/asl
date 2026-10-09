(module aslAgentCore/fsmTest :x [testFsmTransitions testFsmTerminal runTests] :i [(fsm :a fsm)])

fn testFsmTransitions -> Bool
  (let [(s0 (fsm/idle)) (s1 (fsm/step s0 (fsm/start))) (s2 (fsm/step s1 (fsm/planReady))) (s3 (fsm/step s2 (fsm/codeReady))) (s4Pass (fsm/step s3 (fsm/reviewPass))) (s4Fail (fsm/step s3 (fsm/reviewFail))) (sReset (fsm/step s2 (fsm/reset)))] (assert (mt s1 ((fsm/planning) true) (_ false)) "idle + start must transition to planning") (assert (mt s2 ((fsm/coding) true) (_ false)) "planning + plan-ready must transition to coding") (assert (mt s3 ((fsm/reviewing) true) (_ false)) "coding + code-ready must transition to reviewing") (assert (mt s4Pass ((fsm/success) true) (_ false)) "reviewing + review-pass must transition to success") (assert (mt s4Fail ((fsm/coding) true) (_ false)) "reviewing + review-fail must transition to coding") (assert (mt sReset ((fsm/idle) true) (_ false)) "coding + reset must transition to idle") true)

fn testFsmTerminal -> Bool
  (do (assert (fsm/isTerminalState (fsm/success)) "success state must be terminal") (assert (fsm/isTerminalState (fsm/failed)) "failed state must be terminal") (assert (not (fsm/isTerminalState (fsm/idle))) "idle state must not be terminal") (assert (not (fsm/isTerminalState (fsm/planning))) "planning state must not be terminal") (assert (not (fsm/isTerminalState (fsm/coding))) "coding state must not be terminal") (assert (not (fsm/isTerminalState (fsm/reviewing))) "reviewing state must not be terminal") true)

fn runTests -> Bool
  (and (testFsmTransitions) (testFsmTerminal))
