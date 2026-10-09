(module aslAgentCore/types :x [AgentMessage ToolParam ToolDef ToolArg ToolCall ToolInvocation ToolResult makeAgentMessage makeToolDef makeToolCall makeToolResult])

(schema AgentMessage (:f id Str) (:f source Str) (:f target Str) (:f payload Str) (:f timestamp Int64) (:f correlationId Str) (:f role Str) (:f content Str) (:f toolCallId Str))

(schema ToolParam (:f name Str) (:f typeDesc Str) (:f doc Str) (:f required Bool))

(schema ToolDef (:f name Str) (:f description Str) (:f doc Str) (:f parametersSpec Str) (:f params (List ToolParam)))

(schema ToolArg (:f name Str) (:f val Str))

(schema ToolCall (:f id Str) (:f name Str) (:f arguments Str))

(schema ToolInvocation (:f toolName Str) (:f callId Str) (:f args (List ToolArg)))

(schema ToolResult (:f callId Str) (:f toolCallId Str) (:f toolName Str) (:f output Str) (:f payload Str) (:f ok Bool) (:f isError Bool) (:f status Str))

fn makeAgentMessage id: Str source: Str target: Str payload: Str timestamp: Int64 correlationId: Str role: Str content: Str toolCallId: Str -> AgentMessage
  (AgentMessage :id id :source source :target target :payload payload :timestamp timestamp :correlationId correlationId :role role :content content :toolCallId toolCallId)

fn makeToolDef name: Str description: Str doc: Str parametersSpec: Str params: (List ToolParam) -> ToolDef
  (ToolDef :name name :description description :doc doc :parametersSpec parametersSpec :params params)

fn makeToolCall id: Str name: Str arguments: Str -> ToolCall
  (ToolCall :id id :name name :arguments arguments)

fn makeToolResult callId: Str toolName: Str ok: Bool payload: Str status: Str -> ToolResult
  (ToolResult :callId callId :toolCallId callId :toolName toolName :output payload :payload payload :ok ok :isError (not ok) :status status)
