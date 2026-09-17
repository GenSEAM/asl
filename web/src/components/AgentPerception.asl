(module aslWeb/components/agentPerception
  :d "Agent Perception Mode visualizer and AXNode semantic tree emitter"
  :x [renderAgentPerceptionTree
      getPerceptionTokenStats
      isPerceptionSupported
      toggleAgentPerceptionMode]
  :i [(asl-text/string :a s)])

(df isPerceptionSupported [] -> Bool
  :d "Returns true indicating Agent Perception mode capability"
  true)

(df getPerceptionTokenStats [] -> (Map Keyword Num)
  :d "Returns token counts and savings percentage comparing HTML vs AXNode representation"
  (map-set (map-set (map-set (map-empty) :htmlTokens 2840) :axTokens 412) :savingsPercent 85))

(df renderAgentPerceptionTree [] -> Str
  :d "Emits semantic AXNode S-expression tree with prompt token counts"
  "(:ax-node :role \"document\" :name \"aslang.dev\" :tokens 412\n  (:ax-node :role \"banner\" :name \"Navbar\" :tokens 64)\n  (:ax-node :role \"main\" :name \"Hero\" :tokens 186\n    (:ax-node :role \"heading\" :level 1 :name \"The Language Your Agents Write\" :tokens 14)\n    (:ax-node :role \"mascot\" :name \"Schematic Cyber Chameleon AX-4\" :tokens 38)\n    (:ax-node :role \"terminal\" :name \"Install\" :command \"curl -fsSL https://aslang.dev/install.sh | sh\" :tokens 28))\n  (:ax-node :role \"contentinfo\" :name \"Footer\" :tokens 42))")

(df toggleAgentPerceptionMode [(currentMode Bool)] -> Bool
  :d "Toggles active agent perception lens"
  (not currentMode))
