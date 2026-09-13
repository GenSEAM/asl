(module asl-lint/core
  :d "AgentScript native quality inspection, anti-pattern smell classification, and score gate."
  :x [SmellSeverity SmellCode Smell QualityMetrics
           isError severityPenalty calculateQualityScore
           isNestingExcessive shouldBlockGate canAutofix])

(dfe SmellSeverity
  (:c error   [] "Fatal defect that blocks compilation or pre-commit gate")
  (:c warning [] "Code smell that degrades readability or maintainability")
  (:c info    [] "Minor stylistic recommendation"))

(dfe SmellCode
  (:c duplicateMatchArm  [] "Multiple pattern match arms share identical bodies")
  (:c deadBranch          [] "Pattern branch unreachable due to prior wildcard")
  (:c excessiveNesting    [] "Expression nesting exceeds maximum cognitive depth threshold")
  (:c unusedBinding       [] "Local variable binding declared but never read")
  (:c bareResultDiscard  [] "Result type evaluated and discarded without inspecting error")
  (:c fileTooLarge       [] "Module line count exceeds single-pass context window ceiling")
  (:c microFragmentation  [] "Overly granular micro-file; consider consolidating into subsystem")
  (:c excessiveComments   [] "Prose density too high; prefer Knowledge Plane records over code comments"))

(dfs Smell
  (:f code SmellCode "Smell classification code")
  (:f severity SmellSeverity "Diagnostic severity level")
  (:f file Str "Source file path")
  (:f line I64 "1-indexed line number")
  (:f col I64 "1-indexed column offset")
  (:f message Str "Human-readable diagnostic description")
  (:f canAutofix Bool "True if this smell is repairable by autonomous auto-fixer"))

(dfs QualityMetrics
  (:f totalNodes I64 "Total AST nodes traversed")
  (:f maxNesting I64 "Maximum cognitive nesting depth encountered")
  (:f errorCount I64 "Total error-level violations")
  (:f warningCount I64 "Total warning-level code smells")
  (:f score I64 "Computed maintainability and quality score (0 to 100)"))

(df isError [(sev SmellSeverity)] -> Bool
  :d "Returns true if severity level represents an error."
  (mt sev
    ((error) true)
    (_       false)))

(df severityPenalty [(sev SmellSeverity)] -> I64
  :d "Computes score deduction penalty for a smell severity."
  (mt sev
    ((error)   25)
    ((warning)  5)
    ((info)     0)))

(df calculateQualityScore [(errorCount I64) (warningCount I64)] -> I64
  :d "Computes quality score out of 100 based on error and warning counts."
  (let [(penalty (+ (* errorCount 25) (* warningCount 5)))]
    (if (>= penalty 100)
      0
      (- 100 penalty))))

(df isNestingExcessive [(depth I64) (maxAllowed I64)] -> Bool
  :d "Checks if expression nesting depth exceeds allowed cognitive ceiling."
  (> depth maxAllowed))

(df shouldBlockGate [(metrics QualityMetrics)] -> Bool
  :d "Determines if pre-commit quality gate should reject the changeset."
  (if (> (.-errorCount metrics) 0)
    true
    (< (.-score metrics) 70)))

(df canAutofix [(code SmellCode)] -> Bool
  :d "Determines if a given smell code supports deterministic auto-fixing."
  (mt code
    ((duplicateMatchArm) true)
    ((unusedBinding)      true)
    ((excessiveNesting)   false)
    ((deadBranch)         false)
    ((bareResultDiscard) false)
    ((fileTooLarge)      false)
    ((microFragmentation) false)
    ((excessiveComments)  false)))
