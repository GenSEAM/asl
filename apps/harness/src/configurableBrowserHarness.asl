(module aslHarness/configurableBrowserHarness :x [BrowserExecutionContext DynamicHarnessRoute SpecializedHarnessPreset PresetExecutionPlan TranspiledOutput ThreadProfileMetrics makeBrowserExecutionContext makeDynamicHarnessRoute routeDynamicHarness makeSpecializedHarnessPreset generatePresetExecutionPlan evaluateExecutionThreadProfile transpilePresetToBrowser formatDynamicRouteAsn formatPresetPlanAsn formatThreadProfileAsn] :i [])

(schema BrowserExecutionContext (:f mode Str) (:f threadId Str) (:f workerCount I64) (:f sharedBufferSupported Bool))

(schema DynamicHarnessRoute (:f capability Str) (:f modelId Str) (:f tier Str) (:f executionMode Str) (:f schemaTokens I64) (:f fsmDepth I64))

(schema SpecializedHarnessPreset (:f presetId Str) (:f category Str) (:f targetTier Str) (:f recommendedModel Str) (:f executionContext Str) (:f affirmativeSchema Str) (:f fsmMaskDepth I64))

(schema PresetExecutionPlan (:f planId Str) (:f presetId Str) (:f route DynamicHarnessRoute) (:f inputPrompt Str) (:f expectedFormat Str) (:f maxTokens I64))

(schema TranspiledOutput (:f outputId Str) (:f presetKind Str) (:f rawAsn Str) (:f targetFormat Str) (:f renderedOutput Str) (:f success Bool))

(schema ThreadProfileMetrics (:f mode Str) (:f estimatedLatencyMs I64) (:f uiFrameDropRisk Str) (:f memoryOverheadMb I64) (:f fps60Guaranteed Bool))

fn makeBrowserExecutionContext mode: Str threadId: Str workerCount: I64 sharedBufferSupported: Bool -> BrowserExecutionContext
  (BrowserExecutionContext :mode mode :threadId threadId :workerCount workerCount :sharedBufferSupported sharedBufferSupported)

fn makeDynamicHarnessRoute capability: Str modelId: Str tier: Str executionMode: Str schemaTokens: I64 fsmDepth: I64 -> DynamicHarnessRoute
  (DynamicHarnessRoute :capability capability :modelId modelId :tier tier :executionMode executionMode :schemaTokens schemaTokens :fsmDepth fsmDepth)

fn routeDynamicHarness capability: Str -> DynamicHarnessRoute
  (if (= capability "toys") (makeDynamicHarnessRoute "toys" "qwen2.5:3b-instruct" "browser-ceiling-slm" "multi-thread" 140 16) (if (= capability "websites") (makeDynamicHarnessRoute "websites" "qwen2.5:1.5b" "small-slm-edge" "multi-thread" 118 12) (if (= capability "svgs") (makeDynamicHarnessRoute "svgs" "qwen2.5:1.5b" "small-slm-edge" "single-thread" 118 8) (if (= capability "nano") (makeDynamicHarnessRoute "nano" "hanse-nano:100m" "nano-slm" "single-thread" 30 4) (makeDynamicHarnessRoute "micro" "qwen2.5:0.5b" "micro-slm" "single-thread" 118 8)))))

fn makeSpecializedHarnessPreset presetId: Str category: Str targetTier: Str recommendedModel: Str executionContext: Str affirmativeSchema: Str fsmMaskDepth: I64 -> SpecializedHarnessPreset
  (SpecializedHarnessPreset :presetId presetId :category category :targetTier targetTier :recommendedModel recommendedModel :executionContext executionContext :affirmativeSchema affirmativeSchema :fsmMaskDepth fsmMaskDepth)

fn generatePresetExecutionPlan planId: Str presetId: Str category: Str inputPrompt: Str expectedFormat: Str -> PresetExecutionPlan
  (let [(route (routeDynamicHarness category)) (maxToks (if (= category "toys") 512 (if (= category "websites") 384 256)))] (PresetExecutionPlan :planId planId :presetId presetId :route route :inputPrompt inputPrompt :expectedFormat expectedFormat :maxTokens maxToks))

fn evaluateExecutionThreadProfile mode: Str tier: Str -> ThreadProfileMetrics
  (if (= mode "multi-thread") (ThreadProfileMetrics :mode "multi-thread" :estimatedLatencyMs (if (= tier "browser-ceiling-slm") 35 22) :uiFrameDropRisk "none" :memoryOverheadMb 32 :fps60Guaranteed true) (if (= tier "browser-ceiling-slm") (ThreadProfileMetrics :mode "single-thread" :estimatedLatencyMs 35 :uiFrameDropRisk "high" :memoryOverheadMb 0 :fps60Guaranteed false) (if (= tier "nano-slm") (ThreadProfileMetrics :mode "single-thread" :estimatedLatencyMs 12 :uiFrameDropRisk "none" :memoryOverheadMb 0 :fps60Guaranteed true) (ThreadProfileMetrics :mode "single-thread" :estimatedLatencyMs 18 :uiFrameDropRisk "low" :memoryOverheadMb 0 :fps60Guaranteed true))))

fn transpilePresetToBrowser outputId: Str presetKind: Str rawAsn: Str -> TranspiledOutput
  (let [(isSvg (stringContains? presetKind "vector")) (isVdom (stringContains? presetKind "vdom"))] (if isSvg (TranspiledOutput :outputId outputId :presetKind presetKind :rawAsn rawAsn :targetFormat "image/svg+xml" :renderedOutput (str "<svg xmlns=\"http://www.w3.org/2000/svg\" " rawAsn "</svg>") :success true) (if isVdom (TranspiledOutput :outputId outputId :presetKind presetKind :rawAsn rawAsn :targetFormat "text/html" :renderedOutput (str "<div class=\"vdom-container\">" rawAsn "</div>") :success true) (TranspiledOutput :outputId outputId :presetKind presetKind :rawAsn rawAsn :targetFormat "application/json" :renderedOutput (str "{\"simulation\": \"" rawAsn "\"}") :success true))))

fn formatDynamicRouteAsn route: DynamicHarnessRoute -> Str
  (str "(:route :capability \"" route.capability "\" :model-id \"" route.modelId "\" :tier \"" route.tier "\" :execution-mode \"" route.executionMode "\" :schema-tokens " (stringFromInt64 route.schemaTokens) " :fsm-depth " (stringFromInt64 route.fsmDepth) ")")

fn formatPresetPlanAsn plan: PresetExecutionPlan -> Str
  (str "(:plan :plan-id \"" plan.planId "\" :preset-id \"" plan.presetId "\" :max-tokens " (stringFromInt64 plan.maxTokens) " :format \"" plan.expectedFormat "\")")

fn formatThreadProfileAsn profile: ThreadProfileMetrics -> Str
  (str "(:thread-profile :mode \"" profile.mode "\" :latency-ms " (stringFromInt64 profile.estimatedLatencyMs) " :frame-drop-risk \"" profile.uiFrameDropRisk "\" :fps60-guaranteed " (if profile.fps60Guaranteed "true" "false") ")")
