(module aslAgentCore/fsm :x [AgentState AgentEvent step isTerminalState])

(enum AgentState (:c idle [] "idle state") (:c planning [] "planning state") (:c coding [] "coding state") (:c reviewing [] "reviewing state") (:c success [] "success state") (:c failed [] "failed state"))

(enum AgentEvent (:c start [] "start task") (:c planReady [] "plan generated") (:c codeReady [] "code generated") (:c reviewPass [] "review passed") (:c reviewFail [] "review failed") (:c reset [] "reset agent"))

fn step state: AgentState event: AgentEvent -> AgentState
  (mt state ((idle) (mt event ((start) (planning)) (_ state))) ((planning) (mt event ((planReady) (coding)) ((reset) (idle)) (_ state))) ((coding) (mt event ((codeReady) (reviewing)) ((reset) (idle)) (_ state))) ((reviewing) (mt event ((reviewPass) (success)) ((reviewFail) (coding)) ((reset) (idle)) (_ state))) (_ state))

fn isTerminalState state: AgentState -> Bool
  (mt state ((success) true) ((failed) true) (_ false))
