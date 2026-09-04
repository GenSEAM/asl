(module asl-agent-core/core
  :d "AgentScript Unified Agent Core: execution context, message framing, tool registry, and event bus."
  :x [AgentMessage AgentContext ToolDef ToolCall ToolResult AgentCompletion AgentRegistry EventBus
      make-message make-agent-context add-message
      make-tool-def make-tool-call make-tool-result
      empty-registry register-tool find-tool has-tool?
      format-message format-prompt-frame
      empty-event-bus publish-event]
  :i [])

(dfs AgentMessage
  (:f role Str "Role of message sender: system, user, assistant, tool")
  (:f content Str "Textual message body or serialized arguments")
  (:f name Str "Optional sender identity or tool name"))

(dfs AgentContext
  (:f agent-id Str "Unique identifier of agent instance")
  (:f session-id Str "Execution session trace identifier")
  (:f system-prompt Str "Base instructions and behavioral constraints")
  (:f messages (List AgentMessage) "Ordered message history transcript")
  (:f status Str "Current lifecycle state: idle, active, suspended, terminated"))

(dfs ToolDef
  (:f name Str "Canonical name of the tool")
  (:f description Str "Human and LLM readable tool description")
  (:f parameters-spec Str "Formal parameter schema specification"))

(dfs ToolCall
  (:f call-id Str "Unique invocation identifier")
  (:f tool-name Str "Target tool name to invoke")
  (:f arguments Str "Serialized arguments or S-expression payload"))

(dfs ToolResult
  (:f call-id Str "Matching invocation identifier")
  (:f tool-name Str "Executed tool name")
  (:f output Str "Result payload on success")
  (:f success Bool "True if execution completed cleanly")
  (:f error-msg Str "Error diagnostic if execution failed"))

(dfs AgentCompletion
  (:f text Str "Synthesized model response text")
  (:f tool-calls (List ToolCall) "Requested tool calls if any")
  (:f stop-reason Str "Completion reason: stop, tool_calls, error"))

(dfs AgentRegistry
  (:f agent-id Str "Agent identifier")
  (:f capabilities (List Str) "List of negotiated agent capabilities")
  (:f tools (List ToolDef) "Registered tools available to the agent"))

(dfs EventBus
  (:f subscribers (Map Str (List Str)) "Event topic to subscriber list mapping")
  (:f event-log (List Str) "Chronological log of published events"))

(df make-message [(role Str) (content Str) (name Str)] -> AgentMessage
  :d "Constructs an AgentMessage record."
  (AgentMessage
    :role role
    :content content
    :name name))

(df make-agent-context [(agent-id Str) (session-id Str) (system-prompt Str)] -> AgentContext
  :d "Constructs an initial AgentContext with empty message history."
  (AgentContext
    :agent-id agent-id
    :session-id session-id
    :system-prompt system-prompt
    :messages (list)
    :status "ready"))

(df add-message [(ctx AgentContext) (msg AgentMessage)] -> AgentContext
  :d "Appends a message to the agent context transcript."
  (AgentContext
    :agent-id (.-agent-id ctx)
    :session-id (.-session-id ctx)
    :system-prompt (.-system-prompt ctx)
    :messages (list-cons msg (.-messages ctx))
    :status (.-status ctx)))

(df make-tool-def [(name Str) (description Str) (parameters-spec Str)] -> ToolDef
  :d "Constructs a ToolDef record."
  (ToolDef
    :name name
    :description description
    :parameters-spec parameters-spec))

(df make-tool-call [(call-id Str) (tool-name Str) (arguments Str)] -> ToolCall
  :d "Constructs a ToolCall record."
  (ToolCall
    :call-id call-id
    :tool-name tool-name
    :arguments arguments))

(df make-tool-result [(call-id Str) (tool-name Str) (output Str) (success Bool) (error-msg Str)] -> ToolResult
  :d "Constructs a ToolResult record."
  (ToolResult
    :call-id call-id
    :tool-name tool-name
    :output output
    :success success
    :error-msg error-msg))

(df empty-registry [(agent-id Str)] -> AgentRegistry
  :d "Creates an empty AgentRegistry for the given agent ID."
  (AgentRegistry
    :agent-id agent-id
    :capabilities (list)
    :tools (list)))

(df register-tool [(reg AgentRegistry) (tool ToolDef)] -> AgentRegistry
  :d "Registers a new tool into the agent registry."
  (AgentRegistry
    :agent-id (.-agent-id reg)
    :capabilities (.-capabilities reg)
    :tools (list-cons tool (.-tools reg))))

(df find-tool [(reg AgentRegistry) (name Str)] -> (Option ToolDef)
  :d "Finds a registered tool definition by name."
  (let [(matches (filter (fn [(t ToolDef)] -> Bool (= (.-name t) name))
                         (.-tools reg)))]
    (list-head matches)))

(df has-tool? [(reg AgentRegistry) (name Str)] -> Bool
  :d "Checks whether a tool name is present in the registry."
  (mt (find-tool reg name)
    ((some _) true)
    ((none) false)))

(df format-message [(msg AgentMessage)] -> Str
  :d "Formats an agent message into a compact S-expression frame."
  (str "(:msg :" (.-role msg) " " (.-content msg) ")"))

(df format-prompt-frame [(ctx AgentContext)] -> Str
  :d "Compiles agent context into structured frame representation."
  (str "(frame :agent \"" (.-agent-id ctx) "\" :session \"" (.-session-id ctx) "\" :sys \"" (.-system-prompt ctx) "\")"))

(df empty-event-bus [] -> EventBus
  :d "Initializes an empty in-memory event bus."
  (EventBus
    :subscribers (map-empty)
    :event-log (list)))

(df publish-event [(bus EventBus) (topic Str) (payload Str)] -> EventBus
  :d "Publishes an event to the event bus and records in event log."
  (let [(entry (str "[" topic "] " payload))]
    (EventBus
      :subscribers (.-subscribers bus)
      :event-log (list-cons entry (.-event-log bus)))))
