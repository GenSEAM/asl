(module asl-lint/test
  :d "Unit tests for asl-lint: QualityMetrics, smell codes, score calculation, cognitive nesting, and rational universalism orthogonality."
  :x [main]
  :i [(asl-lint/core :a l) (rules :a r)])

(df testQualityScore [] -> Bool
  (assert (= (l/calculateQualityScore 0 0) 100) "Quality score with 0 errors and warnings must be 100")
  (assert (= (l/calculateQualityScore 0 2) 90) "Quality score with 2 warnings must be 90")
  (assert (= (l/calculateQualityScore 1 0) 75) "Quality score with 1 error must be 75")
  (assert (= (l/calculateQualityScore 4 0) 0) "Quality score with 4 errors must clamp to 0")
  true)

(df testSmellSeverity [] -> Bool
  (assert (l/isError (l/error)) "error severity must be classified as error")
  (assert (not (l/isError (l/warning))) "warning severity must not be classified as error")
  (assert (not (l/isError (l/info))) "info severity must not be classified as error")
  (assert (= (l/severityPenalty (l/error)) 25) "error penalty must be 25")
  (assert (= (l/severityPenalty (l/warning)) 5) "warning penalty must be 5")
  (assert (= (l/severityPenalty (l/info)) 0) "info penalty must be 0")
  true)

(df testCognitiveNesting [] -> Bool
  (assert (not (l/isNestingExcessive 4 5)) "depth 4 with max 5 must not be excessive")
  (assert (not (l/isNestingExcessive 5 5)) "depth 5 with max 5 must not be excessive")
  (assert (l/isNestingExcessive 6 5) "depth 6 with max 5 must be excessive")
  true)

(df testBlockGate [] -> Bool
  (let [(clean (l/QualityMetrics :totalNodes 50 :maxNesting 3 :errorCount 0 :warningCount 1 :score 95))
        (blockedErr (l/QualityMetrics :totalNodes 50 :maxNesting 3 :errorCount 1 :warningCount 0 :score 75))
        (blockedScore (l/QualityMetrics :totalNodes 50 :maxNesting 3 :errorCount 0 :warningCount 7 :score 65))]
    (assert (not (l/shouldBlockGate clean)) "Clean metrics must not block gate")
    (assert (l/shouldBlockGate blockedErr) "Metrics with error must block gate")
    (assert (l/shouldBlockGate blockedScore) "Metrics with low score must block gate")
    true))

(df testRationalOrthogonality [] -> Bool
  :d "Verifies Rational Universalism orthogonality checks (C0003, D0034)."
  (let [(single (r/checkRationalOrthogonality "unique-fn" 1 false false))
        (justifiedDivergent (r/checkRationalOrthogonality "frame-codec" 3 false true))
        (unjustifiedDuplication (r/checkRationalOrthogonality "escape-str" 2 false false))
        (redundantWithCanonical (r/checkRationalOrthogonality "escape-asn-str" 2 true false))]
    (assert (r/isOrthogonal? single) "Single occurrence must be orthogonal")
    (assert (not (.-isViolation single)) "Single occurrence is not a violation")
    (assert (r/isOrthogonal? justifiedDivergent) "Justified divergent domain must be orthogonal")
    (assert (not (.-isViolation justifiedDivergent)) "Divergent domain is not a violation")
    (assert (not (r/isOrthogonal? unjustifiedDuplication)) "Unjustified duplication must not be orthogonal")
    (assert (.-isViolation unjustifiedDuplication) "Unjustified duplication must be a violation")
    (assert (not (r/isOrthogonal? redundantWithCanonical)) "Duplicate when canonical exists must not be orthogonal")
    (assert (.-isViolation redundantWithCanonical) "Duplicate when canonical exists must be a violation")
    true))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Runs unit tests for asl-lint quality metrics."
  (if (and (testQualityScore)
           (and (testSmellSeverity)
                (and (testCognitiveNesting)
                     (and (testBlockGate)
                          (testRationalOrthogonality)))))
    (let [(u (println "asl-lint unit tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-lint unit test failure"))]
      (err (other)))))
