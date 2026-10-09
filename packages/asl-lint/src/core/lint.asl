(module asl-lint/core :x [SmellSeverity SmellCode Smell QualityMetrics isError severityPenalty calculateQualityScore isNestingExcessive shouldBlockGate canAutofix checkC1Balance] :i [(asl-parser/balance :a bal)])

(enum SmellSeverity (:c error [] "Fatal defect that blocks compilation or pre-commit gate") (:c warning [] "Code smell that degrades readability or maintainability") (:c info [] "Minor stylistic recommendation"))

(enum SmellCode (:c duplicateMatchArm [] "Multiple pattern match arms share identical bodies") (:c deadBranch [] "Pattern branch unreachable due to prior wildcard") (:c excessiveNesting [] "Expression nesting exceeds maximum cognitive depth threshold") (:c unusedBinding [] "Local variable binding declared but never read") (:c bareResultDiscard [] "Result type evaluated and discarded without inspecting error") (:c fileTooLarge [] "Module line count exceeds single-pass context window ceiling") (:c microFragmentation [] "Overly granular micro-file; consider consolidating into subsystem") (:c excessiveComments [] "Prose density too high; prefer Knowledge Plane records over code comments"))

(schema Smell (:f code SmellCode) (:f severity SmellSeverity) (:f file Str) (:f line I64) (:f col I64) (:f message Str) (:f canAutofix Bool))

(schema QualityMetrics (:f totalNodes I64) (:f maxNesting I64) (:f errorCount I64) (:f warningCount I64) (:f score I64))

fn isError sev: SmellSeverity -> Bool
  (mt sev ((error) true) (_ false))

fn severityPenalty sev: SmellSeverity -> I64
  (mt sev ((error) 25) ((warning) 5) ((info) 0))

fn calculateQualityScore errorCount: I64 warningCount: I64 -> I64
  (let [(penalty (+ (* errorCount 25) (* warningCount 5)))] (if (>= penalty 100) 0 (- 100 penalty)))

fn isNestingExcessive depth: I64 maxAllowed: I64 -> Bool
  (> depth maxAllowed)

fn shouldBlockGate metrics: QualityMetrics -> Bool
  (if (> metrics.errorCount 0) true (< metrics.score 70))

fn canAutofix code: SmellCode -> Bool
  (mt code ((duplicateMatchArm) true) ((unusedBinding) true) ((excessiveNesting) false) ((deadBranch) false) ((bareResultDiscard) false) ((fileTooLarge) false) ((microFragmentation) false) ((excessiveComments) false))

fn checkC1Balance code: Str -> bal/BalanceResult
  (bal/checkDyck1Balance code)
