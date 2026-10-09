(module aslHarness/traceRecorder :x [ModelProfile InteractionTrace makeModelProfile recordInteractionTrace updateModelProfile formatTraceAsn isSlowProvider?] :i [(llmClient :a lc)])

(schema ModelProfile (:f model Str) (:f avgTokSec F64) (:f avgDurationMs I64) (:f totalCalls I64) (:f slowProvider Bool))

(schema InteractionTrace (:f traceId Str) (:f timestampMs I64) (:f modelOptions lc/ModelOptions) (:f result lc/CompletionResult) (:f status Str))

fn makeModelProfile model: Str -> ModelProfile
  (ModelProfile :model model :avgTokSec 0.0 :avgDurationMs 0 :totalCalls 0 :slowProvider false)

fn isSlowProvider? avgTokSec: F64 avgDurationMs: I64 -> Bool
  (or (< avgTokSec 10.0) (> avgDurationMs 3000))

fn updateModelProfile profile: ModelProfile res: lc/CompletionResult -> ModelProfile
  (let [(newCalls (+ profile.totalCalls 1)) (newAvgTokSec (/ (+ (* profile.avgTokSec (int64ToFloat64 profile.totalCalls)) res.tokSec) (int64ToFloat64 newCalls))) (newAvgDuration (/ (+ (* profile.avgDurationMs profile.totalCalls) res.durationMs) newCalls)) (slow (isSlowProvider? newAvgTokSec newAvgDuration))] (with profile :avgTokSec newAvgTokSec :avgDurationMs newAvgDuration :totalCalls newCalls :slowProvider slow))

fn recordInteractionTrace traceId: Str tsMs: I64 opts: lc/ModelOptions res: lc/CompletionResult status: Str -> InteractionTrace
  (InteractionTrace :traceId traceId :timestampMs tsMs :modelOptions opts :result res :status status)

fn formatTraceAsn trace: InteractionTrace -> Str
  (let [(tokSecRaw (stringFromFloat64 trace.result.tokSec)) (tokSecStr (if (stringContains? tokSecRaw ".") tokSecRaw (str tokSecRaw ".0")))] (str "(:interaction-trace :traceId \"" trace.traceId "\" :model \"" trace.modelOptions.model "\" :tokensIn " (stringFromInt64 trace.result.inputTokens) " :tokensOut " (stringFromInt64 trace.result.outputTokens) " :tokSec " tokSecStr " :status \"" trace.status "\" :text \"" trace.result.text "\")"))
