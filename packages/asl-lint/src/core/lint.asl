(module asl-lint/core
  :doc "AgentScript native quality inspection, anti-pattern smell classification, and score gate."
  :export [SmellSeverity SmellCode Smell QualityMetrics
           is-error severity-penalty calculate-quality-score
           is-nesting-excessive should-block-gate can-autofix])

(defenum SmellSeverity
  (:case error   [] "Fatal defect that blocks compilation or pre-commit gate")
  (:case warning [] "Code smell that degrades readability or maintainability")
  (:case info    [] "Minor stylistic recommendation"))

(defenum SmellCode
  (:case duplicate-match-arm  [] "Multiple pattern match arms share identical bodies")
  (:case dead-branch          [] "Pattern branch unreachable due to prior wildcard")
  (:case excessive-nesting    [] "Expression nesting exceeds maximum cognitive depth threshold")
  (:case unused-binding       [] "Local variable binding declared but never read")
  (:case bare-result-discard  [] "Result type evaluated and discarded without inspecting error"))

(defschema Smell
  (:field code SmellCode "Smell classification code")
  (:field severity SmellSeverity "Diagnostic severity level")
  (:field file String "Source file path")
  (:field line Int64 "1-indexed line number")
  (:field col Int64 "1-indexed column offset")
  (:field message String "Human-readable diagnostic description")
  (:field can-autofix Bool "True if this smell is repairable by autonomous auto-fixer"))

(defschema QualityMetrics
  (:field total-nodes Int64 "Total AST nodes traversed")
  (:field max-nesting Int64 "Maximum cognitive nesting depth encountered")
  (:field error-count Int64 "Total error-level violations")
  (:field warning-count Int64 "Total warning-level code smells")
  (:field score Int64 "Computed maintainability and quality score (0 to 100)"))

(defun is-error [(sev SmellSeverity)] -> Bool
  :doc "Returns true if severity level represents an error."
  (match sev
    ((error) true)
    (_       false)))

(defun severity-penalty [(sev SmellSeverity)] -> Int64
  :doc "Computes score deduction penalty for a smell severity."
  (match sev
    ((error)   25)
    ((warning)  5)
    ((info)     0)))

(defun calculate-quality-score [(error-count Int64) (warning-count Int64)] -> Int64
  :doc "Computes quality score out of 100 based on error and warning counts."
  (let [(penalty (+ (* error-count 25) (* warning-count 5)))]
    (if (>= penalty 100)
      0
      (- 100 penalty))))

(defun is-nesting-excessive [(depth Int64) (max-allowed Int64)] -> Bool
  :doc "Checks if expression nesting depth exceeds allowed cognitive ceiling."
  (> depth max-allowed))

(defun should-block-gate [(metrics QualityMetrics)] -> Bool
  :doc "Determines if pre-commit quality gate should reject the changeset."
  (if (> (.-error-count metrics) 0)
    true
    (< (.-score metrics) 70)))

(defun can-autofix [(code SmellCode)] -> Bool
  :doc "Determines if a given smell code supports deterministic auto-fixing."
  (match code
    ((duplicate-match-arm) true)
    ((unused-binding)      true)
    ((excessive-nesting)   false)
    ((dead-branch)         false)
    ((bare-result-discard) false)))
