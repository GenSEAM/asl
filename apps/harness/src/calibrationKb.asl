(module aslHarness/calibrationKb :x [ModelProfile HarnessSetupRecommendation ModelRunRecord InvariantCheckRecord CalibrationRegistry makeModelProfile standardModelProfiles findProfileById recommendHarnessSetup formatModelProfileAsn makeModelRun canonicalInvariants canonicalModelRuns makeCalibrationRegistry findBestRunByTier formatModelRunAsn formatCalibrationRegistryAsn] :i [(contextAssembler :a ca)])

(schema ModelProfile (:f modelId Str) (:f tier Str) (:f optimalStrategy Str) (:f optimalTemperature F64) (:f tokenCeiling I64) (:f keepRecent I64) (:f clampKnowledge I64) (:f pathologies (List Str)) (:f recommendation Str))

(schema HarnessSetupRecommendation (:f modelId Str) (:f knownProfile Bool) (:f contextConfig ca/ContextAssemblyConfig) (:f temperature F64) (:f clampKnowledge I64) (:f rationale Str))

(schema ModelRunRecord (:f runId Str) (:f modelId Str) (:f tier Str) (:f strategy Str) (:f temperature F64) (:f budgetCeiling I64) (:f passRate F64) (:f ctrfProgress F64) (:f avgTokens I64) (:f latencyMs I64) (:f amnesiaDetected Bool) (:f paretoScore F64) (:f timestampMs I64))

(schema InvariantCheckRecord (:f invariantId Str) (:f ruleName Str) (:f status Str) (:f evidence Str))

(schema CalibrationRegistry (:f version Str) (:f runs (List ModelRunRecord)) (:f invariants (List InvariantCheckRecord)) (:f profiles (List ModelProfile)))

fn makeModelProfile id: Str tier: Str strat: Str temp: F64 ceiling: I64 recent: I64 clamp: I64 pathologies: (List Str) rec: Str -> ModelProfile
  (ModelProfile :modelId id :tier tier :optimalStrategy strat :optimalTemperature temp :tokenCeiling ceiling :keepRecent recent :clampKnowledge clamp :pathologies pathologies :recommendation rec)

fn standardModelProfiles -> (List ModelProfile)
  (let [(p1 (makeModelProfile "qwen-2.5-0.5b" "micro-slm" "jit-memory" 0.1 1024 0 200 (list "Attention saturation on verbose conversational prose" "Pass rate degrades from 94% down to 31% if multi-turn history uncompressed") "Use pure affirmative S-expression schema and zero conversational history")) (p2 (makeModelProfile "qwen-2.5-3b" "small-slm" "agent-directed" 0.2 2048 1 300 (list "Occasional unclosed markdown backticks on multi-file refactors") "Use agent self-directed context eviction (:ctx-op) to clear prior tool logs")) (p3 (makeModelProfile "gemma-4-31b-it" "midweight" "agent-directed" 0.15 4096 1 350 (list "Unclosed markdown code fences if prompted with raw prose" "Overdumps bash stdout unless constrained by S-expression tools") "Use Eddie ASL cognitive harness with agent self-eviction and 350-token knowledge clamping")) (p4 (makeModelProfile "gpt-5.6-luna" "frontier" "receipts" 0.2 8192 2 600 (list "High per-token billing cost and latency on raw terminal dumps") "Use rolling 1-line receipts (S2) to cut prompt cost by ~50% with zero quality degradation")) (p5 (makeModelProfile "ling-3.0-flash" "fast-classifier" "jit-memory" 0.0 1024 0 200 (list "Not suited for long-horizon planning; designed for single-shot triage") "Use for live parameter normalization, gate validation, and sub-220ms dispatch"))] (list p1 p2 p3 p4 p5))

fn findProfileById profiles: (List ModelProfile) modelId: Str -> (Option ModelProfile)
  (if (listEmpty? profiles) (none) (let [(headP (optionOr (listHead profiles) (makeModelProfile "" "" "" 0.0 0 0 0 (list) ""))) (tailP (optionOr (listTail profiles) (list)))] (if (or (= headP.modelId modelId) (or (stringContains? modelId headP.modelId) (stringContains? headP.modelId modelId))) (some headP) (findProfileById tailP modelId))))

fn recommendHarnessSetup modelId: Str -> HarnessSetupRecommendation
  (let [(profiles (standardModelProfiles)) (matched (findProfileById profiles modelId))] (mt matched ((some prof) (let [(cfg (ca/ContextAssemblyConfig :strategy prof.optimalStrategy :tokenCeiling prof.tokenCeiling :keepRecent prof.keepRecent))] (HarnessSetupRecommendation :modelId modelId :knownProfile true :contextConfig cfg :temperature prof.optimalTemperature :clampKnowledge prof.clampKnowledge :rationale (str "Matched verified profile in Knowledge Base: " prof.recommendation)))) ((none) (let [(cfg (ca/ContextAssemblyConfig :strategy "receipts" :tokenCeiling 4096 :keepRecent 1))] (HarnessSetupRecommendation :modelId modelId :knownProfile false :contextConfig cfg :temperature 0.2 :clampKnowledge 350 :rationale "Unknown model fallback: applied Universal Golden Default Canvas (S2 Receipts + 350-token knowledge clamp, temp 0.2)")))))

fn formatModelProfileAsn profile: ModelProfile -> Str
  (str "(:model-profile\n" "  :model-id \"" profile.modelId "\"\n" "  :tier \"" profile.tier "\"\n" "  :optimal-strategy \"" profile.optimalStrategy "\"\n" "  :optimal-temperature " (stringFromFloat64 profile.optimalTemperature) "\n" "  :token-ceiling " (stringFromInt64 profile.tokenCeiling) "\n" "  :keep-recent " (stringFromInt64 profile.keepRecent) "\n" "  :clamp-knowledge " (stringFromInt64 profile.clampKnowledge) "\n" "  :recommendation \"" profile.recommendation "\"\n" ")")

fn makeModelRun runId: Str modelId: Str tier: Str strat: Str temp: F64 budget: I64 passRate: F64 progress: F64 tokens: I64 lat: I64 amnesia: Bool pareto: F64 ts: I64 -> ModelRunRecord
  (ModelRunRecord :runId runId :modelId modelId :tier tier :strategy strat :temperature temp :budgetCeiling budget :passRate passRate :ctrfProgress progress :avgTokens tokens :latencyMs lat :amnesiaDetected amnesia :paretoScore pareto :timestampMs ts)

fn canonicalInvariants -> (List InvariantCheckRecord)
  (list (InvariantCheckRecord :invariantId "C0001" :ruleName "pure-asl-zero-comment" :status "verified" :evidence "721 source files audited cleanly in gate 2") (InvariantCheckRecord :invariantId "C0002" :ruleName "machine-asn-zero-emoji" :status "verified" :evidence "3363 grammar symbols audited cleanly in gate 6") (InvariantCheckRecord :invariantId "C0003" :ruleName "boundary-universalism" :status "verified" :evidence "Canonical package separation enforced (D0034)") (InvariantCheckRecord :invariantId "l7-cot" :ruleName "reasoning-channel-quarantine" :status "verified" :evidence "Demux stream isolates think from user channel (D0037)") (InvariantCheckRecord :invariantId "l7-esh" :ruleName "verbal-esh-rejection" :status "verified" :evidence "Unverified test passage claims rejected with esh_rejected") (InvariantCheckRecord :invariantId "l7-gateway" :ruleName "single-llm-nexus" :status "verified" :evidence "All inference routed to http://127.0.0.1:8765/v1") (InvariantCheckRecord :invariantId "affirmative-priming" :ruleName "distractor-free-schema" :status "verified" :evidence "118-token schema reduces SLM syntax errors to 1.8%") (InvariantCheckRecord :invariantId "dual-harness" :ruleName "hermetic-vs-production" :status "verified" :evidence "Benchmark profile airgapped, Production profile epistemic-dag"))

fn canonicalModelRuns -> (List ModelRunRecord)
  (let [(r1 (makeModelRun "RUN-QWEN-05B-S3" "qwen2.5:0.5b" "micro-slm" "S3-jit-memory" 0.1 2048 80.0 0.88 420 42 false 48.5 1788880000000)) (r2 (makeModelRun "RUN-QWEN-3B-S4" "qwen2.5:3b-instruct" "small-slm" "S4-agent-directed" 0.2 4096 100.0 1.00 780 82 false 72.3 1788880100000)) (r3 (makeModelRun "RUN-QWEN-14B-S4" "qwen2.5:14b-instruct" "medium" "S4-agent-directed" 0.2 8192 60.0 0.65 2450 140 false 78.4 1788880300000)) (r4 (makeModelRun "RUN-GEMINI-FLASH-S4" "gemini-2.5-flash" "medium" "S4-agent-directed" 0.2 8192 60.0 0.70 2100 95 false 82.1 1788880400000)) (r5 (makeModelRun "RUN-GEMMA-31B-S4" "gemma-4-31b-it" "frontier" "S4-agent-directed" 0.2 35000 100.0 0.96 11420 310 false 94.8 1788880200000)) (r6 (makeModelRun "RUN-IMPOSSIBLE-BASELINE" "all-models-evaluated" "impossible" "S4-agent-directed" 0.2 35000 0.0 0.12 15000 900 false 0.0 1788880600000))] (list r1 r2 r3 r4 r5 r6))

fn makeCalibrationRegistry -> CalibrationRegistry
  (CalibrationRegistry :version "1.0.0" :runs (canonicalModelRuns) :invariants (canonicalInvariants) :profiles (standardModelProfiles))

fn findBestRunByTier runs: (List ModelRunRecord) tier: Str -> (Option ModelRunRecord)
  (let [(filtered (filter (fn [(r ModelRunRecord)] -> Bool (= r.tier tier)) runs))] (if (listEmpty? filtered) (none) (let [(best (fold (fn [(curr ModelRunRecord) (cand ModelRunRecord)] -> ModelRunRecord (if (> cand.paretoScore curr.paretoScore) cand curr)) (optionOr (listHead filtered) (makeModelRun "" "" "" "" 0.0 0 0.0 0.0 0 0 false 0.0 0)) filtered))] (some best))))

fn formatModelRunAsn r: ModelRunRecord -> Str
  (str "    (:run\n" "      :run-id \"" r.runId "\"\n" "      :model-id \"" r.modelId "\"\n" "      :tier \"" r.tier "\"\n" "      :strategy \"" r.strategy "\"\n" "      :temperature " (stringFromFloat64 r.temperature) "\n" "      :budget-ceiling " (stringFromInt64 r.budgetCeiling) "\n" "      :pass-rate " (stringFromFloat64 r.passRate) "\n" "      :ctrf-progress " (stringFromFloat64 r.ctrfProgress) "\n" "      :avg-tokens " (stringFromInt64 r.avgTokens) "\n" "      :latency-ms " (stringFromInt64 r.latencyMs) "\n" "      :amnesia-detected " (if r.amnesiaDetected "true" "false") "\n" "      :pareto-score " (stringFromFloat64 r.paretoScore) "\n" "    )")

fn formatCalibrationRegistryAsn reg: CalibrationRegistry -> Str
  (let [(runsStr (fold (fn [(acc Str) (r ModelRunRecord)] -> Str (str acc (formatModelRunAsn r) "\n")) "" reg.runs))] (str "(:model-calibration-registry\n" "  :schema-version \"" reg.version "\"\n" "  :runs [\n" runsStr "  ]\n" ")"))
