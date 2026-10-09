(module asl-lint/tokens :x [TokenCategory TokenSmell TokenMetrics tokenCeiling isTokenSmell estimateIdentifierTokens computeDensityScore shouldBlockTokenGate formatTokenSmell])

(enum TokenCategory (:c primitive [] "Core language primitive (head, expression, option)") (:c builtin [] "Standard library builtin or standard alias") (:c identifier [] "User-defined symbol, binding, or function name") (:c literal [] "Literal constant value"))

(schema TokenSmell (:f symbol Str) (:f category TokenCategory) (:f estimatedTokens I64) (:f threshold I64) (:f file Str) (:f line I64) (:f col I64) (:f message Str))

(schema TokenMetrics (:f totalSymbols I64) (:f compliantSymbols I64) (:f violationCount I64) (:f maxTokens I64) (:f score I64))

fn tokenCeiling -> I64
  2

fn isTokenSmell estimatedTokens: I64 ceiling: I64 -> Bool
  (> estimatedTokens ceiling)

fn estimateIdentifierTokens name: Str -> I64
  (let [(parts (stringSplit name "-")) (partCount (listLength parts)) (charCount (stringLength name))] (if (> partCount 2) partCount (if (<= charCount 4) 1 (if (<= charCount 10) 2 (+ 2 (/ (- charCount 10) 4))))))

fn computeDensityScore total: I64 violations: I64 -> I64
  (if (<= total 0) 100 (let [(penalty (/ (* violations 100) total))] (if (>= penalty 100) 0 (- 100 penalty))))

fn shouldBlockTokenGate metrics: TokenMetrics -> Bool
  (if (> metrics.violationCount 0) true (< metrics.score 80))

fn formatTokenSmell smell: TokenSmell -> Str
  (str "Token ceiling violation in " smell.file ":" (stringFromInt64 smell.line) ": '" smell.symbol "' takes " (stringFromInt64 smell.estimatedTokens) " tokens (ceiling is " (stringFromInt64 smell.threshold) ")")
