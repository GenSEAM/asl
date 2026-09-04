(module asl-lint/core
  :d "AgentScript native quality inspection, anti-pattern smell classification, and score gate."
  :x [SmellSeverity SmellCode Smell QualityMetrics
           is-error severity-penalty calculate-quality-score
           is-nesting-excessive should-block-gate can-autofix])

(dfe SmellSeverity
  (:c error   [] "Fatal defect that blocks compilation or pre-commit gate")
  (:c warning [] "Code smell that degrades readability or maintainability")
  (:c info    [] "Minor stylistic recommendation"))

(dfe SmellCode
  (:c duplicate-match-arm  [] "Multiple pattern match arms share identical bodies")
  (:c dead-branch          [] "Pattern branch unreachable due to prior wildcard")
  (:c excessive-nesting    [] "Expression nesting exceeds maximum cognitive depth threshold")
  (:c unused-binding       [] "Local variable binding declared but never read")
  (:c bare-result-discard  [] "Result type evaluated and discarded without inspecting error"))

(dfs Smell
  (:f code SmellCode "Smell classification code")
  (:f severity SmellSeverity "Diagnostic severity level")
  (:f file Str "Source file path")
  (:f line I64 "1-indexed line number")
  (:f col I64 "1-indexed column offset")
  (:f message Str "Human-readable diagnostic description")
  (:f can-autofix Bool "True if this smell is repairable by autonomous auto-fixer"))

(dfs QualityMetrics
  (:f total-nodes I64 "Total AST nodes traversed")
  (:f max-nesting I64 "Maximum cognitive nesting depth encountered")
  (:f error-count I64 "Total error-level violations")
  (:f warning-count I64 "Total warning-level code smells")
  (:f score I64 "Computed maintainability and quality score (0 to 100)"))

(df is-error [(sev SmellSeverity)] -> Bool
  :d "Returns true if severity level represents an error."
  (mt sev
    ((error) true)
    (_       false)))

(df severity-penalty [(sev SmellSeverity)] -> I64
  :d "Computes score deduction penalty for a smell severity."
  (mt sev
    ((error)   25)
    ((warning)  5)
    ((info)     0)))

(df calculate-quality-score [(error-count I64) (warning-count I64)] -> I64
  :d "Computes quality score out of 100 based on error and warning counts."
  (let [(penalty (+ (* error-count 25) (* warning-count 5)))]
    (if (>= penalty 100)
      0
      (- 100 penalty))))

(df is-nesting-excessive [(depth I64) (max-allowed I64)] -> Bool
  :d "Checks if expression nesting depth exceeds allowed cognitive ceiling."
  (> depth max-allowed))

(df should-block-gate [(metrics QualityMetrics)] -> Bool
  :d "Determines if pre-commit quality gate should reject the changeset."
  (if (> (.-error-count metrics) 0)
    true
    (< (.-score metrics) 70)))

(df can-autofix [(code SmellCode)] -> Bool
  :d "Determines if a given smell code supports deterministic auto-fixing."
  (mt code
    ((duplicate-match-arm) true)
    ((unused-binding)      true)
    ((excessive-nesting)   false)
    ((dead-branch)         false)
    ((bare-result-discard) false)))
