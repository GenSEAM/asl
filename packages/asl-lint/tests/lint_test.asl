(module asl-lint/test
  :d "Unit tests for asl-lint: QualityMetrics, smell codes, score calculation, cognitive nesting, and rational universalism orthogonality."
  :x [main]
  :i [(core/lint :a l) (rules :a r)])

(df test-quality-score [] -> Bool
  (assert (= (l/calculate-quality-score 0 0) 100) "Quality score with 0 errors and warnings must be 100")
  (assert (= (l/calculate-quality-score 0 2) 90) "Quality score with 2 warnings must be 90")
  (assert (= (l/calculate-quality-score 1 0) 75) "Quality score with 1 error must be 75")
  (assert (= (l/calculate-quality-score 4 0) 0) "Quality score with 4 errors must clamp to 0")
  true)

(df test-smell-severity [] -> Bool
  (assert (l/is-error (l/error)) "error severity must be classified as error")
  (assert (not (l/is-error (l/warning))) "warning severity must not be classified as error")
  (assert (not (l/is-error (l/info))) "info severity must not be classified as error")
  (assert (= (l/severity-penalty (l/error)) 25) "error penalty must be 25")
  (assert (= (l/severity-penalty (l/warning)) 5) "warning penalty must be 5")
  (assert (= (l/severity-penalty (l/info)) 0) "info penalty must be 0")
  true)

(df test-cognitive-nesting [] -> Bool
  (assert (not (l/is-nesting-excessive 4 5)) "depth 4 with max 5 must not be excessive")
  (assert (not (l/is-nesting-excessive 5 5)) "depth 5 with max 5 must not be excessive")
  (assert (l/is-nesting-excessive 6 5) "depth 6 with max 5 must be excessive")
  true)

(df test-block-gate [] -> Bool
  (let [(clean (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 0 :warning-count 1 :score 95))
        (blocked-err (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 1 :warning-count 0 :score 75))
        (blocked-score (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 0 :warning-count 7 :score 65))]
    (assert (not (l/should-block-gate clean)) "Clean metrics must not block gate")
    (assert (l/should-block-gate blocked-err) "Metrics with error must block gate")
    (assert (l/should-block-gate blocked-score) "Metrics with low score must block gate")
    true))

(df test-rational-orthogonality [] -> Bool
  :d "Verifies Rational Universalism orthogonality checks (c-0003, d-0034)."
  (let [(single (r/check-rational-orthogonality "unique-fn" 1 false false))
        (justified-divergent (r/check-rational-orthogonality "frame-codec" 3 false true))
        (unjustified-duplication (r/check-rational-orthogonality "escape-str" 2 false false))
        (redundant-with-canonical (r/check-rational-orthogonality "escape-asn-str" 2 true false))]
    (assert (r/is-orthogonal? single) "Single occurrence must be orthogonal")
    (assert (not (.-is-violation single)) "Single occurrence is not a violation")
    (assert (r/is-orthogonal? justified-divergent) "Justified divergent domain must be orthogonal")
    (assert (not (.-is-violation justified-divergent)) "Divergent domain is not a violation")
    (assert (not (r/is-orthogonal? unjustified-duplication)) "Unjustified duplication must not be orthogonal")
    (assert (.-is-violation unjustified-duplication) "Unjustified duplication must be a violation")
    (assert (not (r/is-orthogonal? redundant-with-canonical)) "Duplicate when canonical exists must not be orthogonal")
    (assert (.-is-violation redundant-with-canonical) "Duplicate when canonical exists must be a violation")
    true))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Runs unit tests for asl-lint quality metrics."
  (if (and (test-quality-score)
           (and (test-smell-severity)
                (and (test-cognitive-nesting)
                     (and (test-block-gate)
                          (test-rational-orthogonality)))))
    (let [(u (println "asl-lint unit tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-lint unit test failure"))]
      (err (other)))))
