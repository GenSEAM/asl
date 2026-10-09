(module aslWeb/components/agentPerception :x [renderAgentPerceptionTree getPerceptionTokenStats isPerceptionSupported toggleAgentPerceptionMode] :i [(asl-text/string :a s)])

fn isPerceptionSupported -> Bool
  true

fn getPerceptionTokenStats -> (Map Keyword Num)
  (mapSet (mapSet (mapSet (mapEmpty) :htmlTokens 2840) :axTokens 412) :savingsPercent 85)

fn renderAgentPerceptionTree -> Str
  "(:ax-node :role \"document\" :name \"aslang.dev\" :tokens 412\n  (:ax-node :role \"banner\" :name \"Navbar\" :tokens 64)\n  (:ax-node :role \"main\" :name \"Hero\" :tokens 186\n    (:ax-node :role \"heading\" :level 1 :name \"The Language Your Agents Write\" :tokens 14)\n    (:ax-node :role \"mascot\" :name \"Schematic Cyber Chameleon AX-4\" :tokens 38)\n    (:ax-node :role \"terminal\" :name \"Install\" :command \"curl -fsSL https://aslang.dev/install.sh | sh\" :tokens 28))\n  (:ax-node :role \"contentinfo\" :name \"Footer\" :tokens 42))"

fn toggleAgentPerceptionMode currentMode: Bool -> Bool
  (not currentMode)
