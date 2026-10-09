(module aslHarness/provider :x [OpenAiConfig ChatMessage ProviderResponse defaultGatewayConfig deepseekFlashGatewayConfig museSparkPlanningConfig museSparkAuditConfig gatewayConfigForRole makeMessage buildRequestPayload parseModelResponse] :i [(coding :a c) (toolcall :a tc)])

(schema OpenAiConfig (:f apiKey Str) (:f baseUrl Str) (:f model Str) (:f temperature F64) (:f maxTokens I64))

(schema ChatMessage (:f role Str) (:f content Str) (:f toolCallId Str))

(schema ProviderResponse (:f text Str) (:f toolCalls (List c/ToolCall)) (:f finishReason Str))

fn defaultGatewayConfig -> OpenAiConfig
  (OpenAiConfig :apiKey "" :baseUrl "http://127.0.0.1:8765/v1" :model "gemma-4-31b-it" :temperature 0.2 :maxTokens 4096)

fn deepseekFlashGatewayConfig -> OpenAiConfig
  (OpenAiConfig :apiKey "" :baseUrl "http://127.0.0.1:8765/v1" :model "deepseek/deepseek-v4.1-flash" :temperature 0.25 :maxTokens 4096)

fn museSparkPlanningConfig -> OpenAiConfig
  (OpenAiConfig :apiKey "" :baseUrl "http://127.0.0.1:8765/v1" :model "meta/muse-spark-1.3" :temperature 0.4 :maxTokens 16384)

fn museSparkAuditConfig -> OpenAiConfig
  (OpenAiConfig :apiKey "" :baseUrl "http://127.0.0.1:8765/v1" :model "meta/muse-spark-1.3" :temperature 0.5 :maxTokens 8192)

fn gatewayConfigForRole role: Str -> OpenAiConfig
  (if (= role "coding") (deepseekFlashGatewayConfig) (if (= role "planning") (museSparkPlanningConfig) (if (or (= role "audit") (= role "review")) (museSparkAuditConfig) (defaultGatewayConfig))))

fn makeMessage role: Str content: Str -> ChatMessage
  (ChatMessage :role role :content content :toolCallId "")

fn buildRequestPayload cfg: OpenAiConfig messages: (List ChatMessage) tools: (List c/BuiltinTool) -> Str
  (let [(msgsJson (fold (fn [(acc Str) (m ChatMessage)] -> Str (str acc "{\"role\": \"" m.role "\", \"content\": \"" m.content "\"}, ")) "" messages)) (toolsJson (tc/agentToolsToOpenaiJson tools))] (str "{\"model\": \"" cfg.model "\", \"messages\": [" msgsJson "], \"tools\": " toolsJson ", \"temperature\": 0.2}"))

fn parseModelResponse rawContent: Str hasTools: Bool -> ProviderResponse
  (let [(idxOpen (stringIndexOf rawContent "<think>")) (idxClose (stringIndexOf rawContent "</think>"))] (let [(cleanText (mt idxOpen ((none) rawContent) ((some o) (mt idxClose ((none) (optionOr (stringSlice rawContent 0 o) "")) ((some c) (let [(prefix (optionOr (stringSlice rawContent 0 o) "")) (suffix (optionOr (stringSlice rawContent (+ c 8) (stringLength rawContent)) ""))] (stringTrim (str prefix " " suffix))))))))] (let [(lower (stringLower cleanText)) (isEsh (or (stringContains? lower "all tests pass") (or (stringContains? lower "all tests passed") (or (stringContains? lower "i have run the tests and they pass") (stringContains? lower "tests are passing")))))] (if isEsh (ProviderResponse :text cleanText :toolCalls (list) :finishReason "esh_rejected") (ProviderResponse :text cleanText :toolCalls (list) :finishReason "stop")))))
