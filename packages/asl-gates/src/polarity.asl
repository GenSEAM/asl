(module asl-gates/polarity
  :d "Pure AgentScript Gate 5 Dual-Polarity and Test Coverage Verification Engine per D77."
  :x [TestPolarityResult
      CoverageSummary
      is-test-symbol?
      is-negative-assertion?
      count-negative-assertions
      count-positive-assertions
      audit-test-polarity
      calculate-coverage-pct
      summarize-coverage]
  :i [(string :a s)])

(dfs TestPolarityResult
  (:f name Str "Test function symbol name")
  (:f pos-count I64 "Positive assertion count")
  (:f neg-count I64 "Negative assertion count")
  (:f total-asserts I64 "Total assertion count")
  (:f qualified Bool "True if meeting dual-polarity and assertion criteria"))

(dfs CoverageSummary
  (:f total-tests I64 "Total test functions scanned")
  (:f qualified-tests I64 "Tests meeting dual-case criteria")
  (:f coverage-pct I64 "Overall coverage percentage 0-100")
  (:f passed Bool "True if coverage meets target threshold"))

(df is-test-symbol? [(name Str)] -> Bool
  :d "Determines if a symbol represents an executable test case."
  (and (not (= name "run-tests"))
       (and (not (= name "test-runner"))
            (or (s/starts? name "test-")
                (or (s/starts? name "test_")
                    (or (s/ends? name "-test")
                        (and (s/starts? name "Test")
                             (> (string-length name) 4))))))))

(df count-negative-assertions [(body Str)] -> I64
  :d "Counts negative and refutation assertions in a test body."
  (let [(patterns (list "(refute"
                        "(refute-case"
                        "(assert-reject"
                        "(assert-err"
                        "(assert-nil"
                        "(assert-null"
                        "(assert-false"
                        "(assert (not"
                        "(assert (nil?"
                        "(assert (empty?"
                        "(assert (zero?"
                        "(assert false"))]
    (fold (fn [(acc I64) (pat Str)] -> I64
            (if (s/has? body pat)
              (+ acc 1)
              acc))
          0
          patterns)))

(df is-negative-assertion? [(expr Str)] -> Bool
  :d "Detects negative, refute, or rejection assertion forms."
  (> (count-negative-assertions expr) 0))

(df count-positive-assertions [(body Str)] -> I64
  :d "Counts positive assertions in a test body."
  (let [(pos-candidates (list "(assert (= "
                              "(assert (="
                              "(assert (> "
                              "(assert (< "
                              "(assert (>= "
                              "(assert (<= "
                              "(assert (not="
                              "(assert (!= "
                              "(assert (string-"
                              "(assert (list-"
                              "(assert (ok"
                              "(assert (err"
                              "(assert (some"
                              "(assert (is-"
                              "(assert true"
                              "(assert-eq"
                              "(assert-true"))]
    (fold (fn [(acc I64) (pat Str)] -> I64
            (if (s/has? body pat)
              (+ acc 1)
              acc))
          0
          pos-candidates)))

(df audit-test-polarity [(name Str) (body Str) (strict Bool) (min-asserts I64)] -> TestPolarityResult
  :d "Audits dual-case assertion balance for an individual test function."
  (let [(pos (count-positive-assertions body))
        (neg (count-negative-assertions body))
        (total (+ pos neg))
        (qual (and (>= total min-asserts)
                   (if strict
                     (and (>= pos 1) (>= neg 1))
                     true)))]
    (TestPolarityResult
      :name name
      :pos-count pos
      :neg-count neg
      :total-asserts total
      :qualified qual)))

(df calculate-coverage-pct [(qualified I64) (total I64)] -> I64
  :d "Calculates integer coverage percentage."
  (if (<= total 0)
    100
    (/ (* qualified 100) total)))

(df summarize-coverage [(results (List TestPolarityResult)) (target-pct I64)] -> CoverageSummary
  :d "Aggregates test polarity results into an overall coverage summary."
  (let [(total (list-length results))
        (qual (fold (fn [(acc I64) (res TestPolarityResult)] -> I64
                      (if (.-qualified res)
                        (+ acc 1)
                        acc))
                    0
                    results))
        (pct (calculate-coverage-pct qual total))]
    (CoverageSummary
      :total-tests total
      :qualified-tests qual
      :coverage-pct pct
      :passed (>= pct target-pct))))
