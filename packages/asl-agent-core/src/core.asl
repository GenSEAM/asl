(module aslAgentCore/core :x [AgentMessage AgentContext ToolDef ToolCall ToolResult AgentCompletion AgentRegistry EventBus makeMessage makeAgentContext addMessage makeToolDef makeToolCall makeToolResult emptyRegistry registerTool findTool hasTool? formatMessage formatPromptFrame emptyEventBus publishEvent] :i [])

(schema AgentMessage (:f role Str) (:f content Str) (:f name Str))

(schema AgentContext (:f agentId Str) (:f sessionId Str) (:f systemPrompt Str) (:f messages (List AgentMessage)) (:f status Str))

(schema ToolDef (:f name Str) (:f description Str) (:f parametersSpec Str))

(schema ToolCall (:f callId Str) (:f toolName Str) (:f arguments Str))

(schema ToolResult (:f callId Str) (:f toolName Str) (:f output Str) (:f success Bool) (:f errorMsg Str))

(schema AgentCompletion (:f text Str) (:f toolCalls (List ToolCall)) (:f stopReason Str))

(schema AgentRegistry (:f agentId Str) (:f capabilities (List Str)) (:f tools (List ToolDef)))

(schema EventBus (:f subscribers (Map Str (List Str))) (:f eventLog (List Str)))

fn makeMessage role: Str content: Str name: Str -> AgentMessage
  (AgentMessage :role role :content content :name name)

fn makeAgentContext agentId: Str sessionId: Str systemPrompt: Str -> AgentContext
  (AgentContext :agentId agentId :sessionId sessionId :systemPrompt systemPrompt :messages (list) :status "ready")

fn addMessage ctx: AgentContext msg: AgentMessage -> AgentContext
  (with ctx :messages (listAppend ctx.messages (list msg)))

fn makeToolDef name: Str description: Str parametersSpec: Str -> ToolDef
  (ToolDef :name name :description description :parametersSpec parametersSpec)

fn makeToolCall callId: Str toolName: Str arguments: Str -> ToolCall
  (ToolCall :callId callId :toolName toolName :arguments arguments)

fn makeToolResult callId: Str toolName: Str output: Str success: Bool errorMsg: Str -> ToolResult
  (ToolResult :callId callId :toolName toolName :output output :success success :errorMsg errorMsg)

fn emptyRegistry agentId: Str -> AgentRegistry
  (AgentRegistry :agentId agentId :capabilities (list) :tools (list))

fn registerTool reg: AgentRegistry tool: ToolDef -> AgentRegistry
  (with reg :tools (cons tool reg.tools))

fn findTool reg: AgentRegistry name: Str -> (Option ToolDef)
  (let [(matches (filter (fn [(t ToolDef)] -> Bool (= t.name name)) reg.tools))] (listHead matches))

fn hasTool? reg: AgentRegistry name: Str -> Bool
  (mt (findTool reg name) ((some _) true) ((none) false))

fn formatMessage msg: AgentMessage -> Str
  (str "(:msg :" msg.role " " msg.content ")")

fn formatPromptFrame ctx: AgentContext -> Str
  (str "(frame :agent \"" ctx.agentId "\" :session \"" ctx.sessionId "\" :sys \"" ctx.systemPrompt "\")")

fn emptyEventBus -> EventBus
  (EventBus :subscribers (mapEmpty) :eventLog (list))

fn publishEvent bus: EventBus topic: Str payload: Str -> EventBus
  (let [(entry (str "[" topic "] " payload))] (with bus :eventLog (cons entry bus.eventLog)))
