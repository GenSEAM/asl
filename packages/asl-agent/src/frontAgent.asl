(module aslAgent/frontAgent
  :x [FrontAgentConfig FrontAgentState FrontAgentReceipt
      frontAgentInit frontAgentHandleDirective formatFrontAgentReceipt]
  :i [(asl/packages/asl-agent/src/omniIntent :a oi)])

(schema FrontAgentConfig
  (:f workspaceRoot Str)
  (:f daemonSocket Str)
  (:f voiceEnabled Bool))

(schema FrontAgentState
  (:f cfg FrontAgentConfig)
  (:f directivesHandled I64)
  (:f lastReceipt (Option Str)))

(schema FrontAgentReceipt
  (:f intent oi/OmniIntent)
  (:f dispatchedTarget Str)
  (:f receiptText Str)
  (:f success Bool))

fn frontAgentInit cfg: FrontAgentConfig -> FrontAgentState
  (FrontAgentState
    :cfg cfg
    :directivesHandled 0
    :lastReceipt (none))

fn frontAgentHandleDirective state: FrontAgentState rawText: Str -> (Pair FrontAgentState FrontAgentReceipt)
  (let [(intent (oi/classifyOmniIntent rawText))
        (target intent.targetSubstrate)
        (receiptText (str "(:front-agent-receipt :intent-id \"" intent.intentId "\""
                          " :target \"" target "\""
                          " :requires-gate " (if intent.requiresGate "true" "false")
                          " :requires-worktree " (if intent.requiresWorktree "true" "false") ")"))
        (receipt (FrontAgentReceipt
                   :intent intent
                   :dispatchedTarget target
                   :receiptText receiptText
                   :success true))
        (updatedState (with state :directivesHandled (+ state.directivesHandled 1) :lastReceipt (some receiptText)))]
    (pair updatedState receipt))

fn formatFrontAgentReceipt receipt: FrontAgentReceipt -> Str
  receipt.receiptText
