(module asl-lint/test
  :d "Unit tests for asl-lint: QualityMetrics, smell codes, score calculation, and cognitive nesting."
  :x [main]
  :i [(core/lint :a l)])

(df test-quality-score [] -> Bool
  (and (and (= (l/calculate-quality-score 0 0) 100)
            (= (l/calculate-quality-score 0 2) 90))
       (and (= (l/calculate-quality-score 1 0) 75)
            (= (l/calculate-quality-score 4 0) 0))))

(df test-smell-severity [] -> Bool
  (and (and (l/is-error (l/error))
            (not (l/is-error (l/warning))))
       (and (and (not (l/is-error (l/info)))
                 (= (l/severity-penalty (l/error)) 25))
            (and (= (l/severity-penalty (l/warning)) 5)
                 (= (l/severity-penalty (l/info)) 0)))))

(df test-cognitive-nesting [] -> Bool
  (and (and (not (l/is-nesting-excessive 4 5))
            (not (l/is-nesting-excessive 5 5)))
       (l/is-nesting-excessive 6 5)))

(df test-block-gate [] -> Bool
  (let [(clean (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 0 :warning-count 1 :score 95))
        (blocked-err (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 1 :warning-count 0 :score 75))
        (blocked-score (l/QualityMetrics :total-nodes 50 :max-nesting 3 :error-count 0 :warning-count 7 :score 65))]
    (and (and (not (l/should-block-gate clean))
              (l/should-block-gate blocked-err))
         (l/should-block-gate blocked-score))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Runs unit tests for asl-lint quality metrics."
  (if (and (test-quality-score)
           (and (test-smell-severity)
                (and (test-cognitive-nesting)
                     (test-block-gate))))
    (let [(u (println "asl-lint unit tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-lint unit test failure"))]
      (err (other)))))
