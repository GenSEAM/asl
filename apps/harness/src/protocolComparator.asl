(module aslHarness/protocolComparator :x [ProtocolProfile ComparisonMetrics ProtocolBenchmarkReport measureProtocolTokens compareProtocolEfficiency formatProtocolComparison] :i [(asnProtocolAgent :a apa)])

(schema ProtocolProfile (:f name Str) (:f promptTokens I64) (:f completionTokens I64) (:f parseErrors I64))

(schema ComparisonMetrics (:f conditionATokens I64) (:f conditionBTokens I64) (:f tokenSavingsPct F64) (:f errorReductionPct F64))

(schema ProtocolBenchmarkReport (:f benchmarkId Str) (:f taskCount I64) (:f metrics ComparisonMetrics) (:f recommendation Str))

fn measureProtocolTokens payload: Str -> I64
  (let [(len (stringLength payload))] (if (<= len 0) 0 (let [(q (/ len 4))] (if (<= q 0) 1 q))))

fn compareProtocolEfficiency condA: ProtocolProfile condB: ProtocolProfile -> ComparisonMetrics
  (let [(tokA (+ condA.promptTokens condA.completionTokens)) (tokB (+ condB.promptTokens condB.completionTokens)) (errA condA.parseErrors) (errB condB.parseErrors) (savings (if (<= tokA 0) 0.0 (/ (* (int64ToFloat64 (- tokA tokB)) 100.0) (int64ToFloat64 tokA)))) (errRed (if (<= errA 0) 0.0 (/ (* (int64ToFloat64 (- errA errB)) 100.0) (int64ToFloat64 errA))))] (ComparisonMetrics :conditionATokens tokA :conditionBTokens tokB :tokenSavingsPct savings :errorReductionPct errRed))

fn formatProtocolComparison report: ProtocolBenchmarkReport -> Str
  (let [(m report.metrics)] (str "(:protocol-comparison :benchmark-id \"" report.benchmarkId "\" :task-count " (stringFromInt64 report.taskCount) " :condition-a-tokens " (stringFromInt64 m.conditionATokens) " :condition-b-tokens " (stringFromInt64 m.conditionBTokens) " :token-savings-pct " (stringFromFloat64 m.tokenSavingsPct) " :error-reduction-pct " (stringFromFloat64 m.errorReductionPct) " :recommendation \"" report.recommendation "\")"))
