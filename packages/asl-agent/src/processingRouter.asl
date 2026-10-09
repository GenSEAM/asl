(module aslAgent/processingRouter :x [ProcessingTier RouteDecision tier0Ast tier1Audio tier2Slm tier3Cloud tierToStr resolveProcessingTier formatRouteDecisionAsn] :i [(asl-text/string :a s)])

(enum ProcessingTier (:c tier0Ast [] "Sub-millisecond deterministic AST / regex in-memory") (:c tier1Audio [] "Sub-20ms local ONNX audio engine on Apple Silicon") (:c tier2Slm [] "Sub-100ms local Apple Silicon SLM for triage and computer use") (:c tier3Cloud [] "500-2000ms cloud frontier LLM for deep architectural waves"))

(schema RouteDecision (:f prompt Str) (:f tier ProcessingTier) (:f targetEngine Str) (:f expectedLatencyMs Int64) (:f rationale Str))

fn tierToStr tier: ProcessingTier -> Str
  (mt tier ((tier0Ast) "tier-0-ast") ((tier1Audio) "tier-1-audio") ((tier2Slm) "tier-2-slm") ((tier3Cloud) "tier-3-cloud"))

fn isInstantCommand? low: Str -> Bool
  (or (= low "stop") (or (= low "стоп") (or (= low "cancel") (or (= low "отмена") (or (= low "pause") (or (= low "пауза") (or (= low "status") (= low "статус"))))))))

fn isAudioCommand? low: Str -> Bool
  (or (stringContains? low "озвучь") (or (stringContains? low "скажи голосом") (or (stringContains? low "громкость") (or (stringContains? low "speak") (stringContains? low "volume")))))

fn isFastActionCommand? low: Str -> Bool
  (or (stringContains? low "кликни") (or (stringContains? low "открой") (or (stringContains? low "перейди") (or (stringContains? low "click") (or (stringContains? low "open") (stringContains? low "navigate"))))))

fn resolveProcessingTier prompt: Str -> RouteDecision
  (let [(low (stringLower (stringTrim prompt)))] (cond ((isInstantCommand? low) (RouteDecision :prompt prompt :tier (tier0Ast) :targetEngine "in-memory-ast" :expectedLatencyMs 1 :rationale "Instant local deterministic control action")) ((isAudioCommand? low) (RouteDecision :prompt prompt :tier (tier1Audio) :targetEngine "silero-onnx" :expectedLatencyMs 18 :rationale "Local acoustic ONNX synthesis on Apple Neural Engine")) ((isFastActionCommand? low) (RouteDecision :prompt prompt :tier (tier2Slm) :targetEngine "mlx-qwen-3b" :expectedLatencyMs 85 :rationale "Fast local SLM computer use and CDP action matching")) (else (RouteDecision :prompt prompt :tier (tier3Cloud) :targetEngine "claude-frontier" :expectedLatencyMs 1200 :rationale "Complex architectural reasoning or multi-file coding wave"))))

fn formatRouteDecisionAsn decision: RouteDecision -> Str
  (str "(:route-decision :tier \"" (tierToStr decision.tier) "\" :engine \"" decision.targetEngine "\" :sla-ms " (stringFromInt64 decision.expectedLatencyMs) ")")
