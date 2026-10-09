(module aslBrowserPlugin/localSlm :x [InferenceRoute InferenceTarget selectInferenceRoute dispatchLocalPerception evaluateConfidence] :i [(aslAgentBus/mesh :a m)])

(enum InferenceTarget (:c onDeviceWebgpu [] "Local in-browser WebLLM / WebGPU execution") (:c remoteGatewayProxy [] "Forwarded to Agent Bus L7 Gateway proxy"))

(schema InferenceRoute (:f target InferenceTarget) (:f modelName Str) (:f estimatedLatencyMs I64) (:f reason Str) (:f tier m/ComputeTier))

fn selectInferenceRoute taskKind: Str hasWebgpu: Bool requiresDeepReasoning: Bool -> InferenceRoute
  (if (and hasWebgpu (not requiresDeepReasoning)) (InferenceRoute :target (onDeviceWebgpu) :modelName "gemma-2b-it-webgpu" :estimatedLatencyMs 15 :reason "Low-latency in-browser WebGPU perception" :tier (m/tier1EdgeMediator)) (InferenceRoute :target (remoteGatewayProxy) :modelName "gateway-l7-reasoning" :estimatedLatencyMs 450 :reason "High-reasoning task delegated to Agent Bus Gateway" :tier (m/tier3FrontierReasoning)))

fn evaluateConfidence confidence: F64 threshold: F64 -> Bool
  (>= confidence threshold)

fn dispatchLocalPerception prompt: Str context: Str -> Str
  (let [(cleanPrompt (stringTrim prompt)) (cleanCtx (stringTrim context)) (totalChars (+ (stringLength cleanPrompt) (stringLength cleanCtx))) (estTokens (if (<= totalChars 0) 0 (/ (+ totalChars 3) 4))) (summary (if (> (stringLength cleanPrompt) 80) (optionOr (stringSlice cleanPrompt 0 80) cleanPrompt) cleanPrompt))] (str "(:perception-result :summary \"" summary "\" :tokens " (stringFromInt64 estTokens) ")"))
