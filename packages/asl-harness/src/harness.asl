(module asl-harness/harness
  :d "Universal Multi-Modal Agent Harness in ASL"
  :x [AdapterKind AgentHarness get-adapter-name])

(dfe AdapterKind
  (:c code [] "Code generation adapter")
  (:c browser [] "Browser automation adapter")
  (:c computer-use [] "OS interaction adapter")
  (:c chat [] "Conversational adapter"))

(dfs AgentHarness
  (:f name Str "harness name")
  (:f adapter AdapterKind "adapter kind")
  (:f timeout-ms I64 "execution timeout"))

(df get-adapter-name [(adapter AdapterKind)] -> Str
  :d "Gets human-readable adapter name"
  (mt adapter
    ((code) "Code Engine")
    ((browser) "Browser Agent")
    ((computer-use) "Computer-Use Controller")
    ((chat) "Chat RAG Assistant")))
