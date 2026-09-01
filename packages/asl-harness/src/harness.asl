(module asl-harness/harness
  :doc "Universal Multi-Modal Agent Harness in ASL Nano"
  :export [AdapterKind AgentHarness get-adapter-name])

(dfe AdapterKind
  (:case code [] "Code generation adapter")
  (:case browser [] "Browser automation adapter")
  (:case computer-use [] "OS interaction adapter")
  (:case chat [] "Conversational adapter"))

(dfs AgentHarness
  (:field name Str "harness name")
  (:field adapter AdapterKind "adapter kind")
  (:field timeout-ms I64 "execution timeout"))

(df get-adapter-name [(adapter AdapterKind)] -> Str
  :doc "Gets human-readable adapter name"
  (match adapter
    ((code) "Code Engine")
    ((browser) "Browser Agent")
    ((computer-use) "Computer-Use Controller")
    ((chat) "Chat RAG Assistant")))
