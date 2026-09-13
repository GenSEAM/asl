(module asl-gates/polarity
  :d "Pure AgentScript Gate 5 Dual-Polarity and Test Coverage Verification Engine per D77."
  :x [TestPolarityResult
      CoverageSummary
      isTestSymbol?
      isNegativeAssertion?
      countNegativeAssertions
      countPositiveAssertions
      auditTestPolarity
      calculateCoveragePct
      summarizeCoverage]
  :i [(string :a s)])

(dfs TestPolarityResult
  (:f name Str "Test function symbol name")
  (:f posCount I64 "Positive assertion count")
  (:f negCount I64 "Negative assertion count")
  (:f totalAsserts I64 "Total assertion count")
  (:f qualified Bool "True if meeting dual-polarity and assertion criteria"))

(dfs CoverageSummary
  (:f totalTests I64 "Total test functions scanned")
  (:f qualifiedTests I64 "Tests meeting dual-case criteria")
  (:f coveragePct I64 "Overall coverage percentage 0-100")
  (:f passed Bool "True if coverage meets target threshold"))

(df isTestSymbol? [(name Str)] -> Bool
  :d "Determines if a symbol represents an executable test case."
  (and (not (= name "run-tests"))
       (and (not (= name "test-runner"))
            (or (s/starts? name "test-")
                (or (s/starts? name "test_")
                    (or (s/ends? name "-test")
                        (and (s/starts? name "Test")
                             (> (string-length name) 4))))))))

(df countNegativeAssertions [(body Str)] -> I64
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

(df isNegativeAssertion? [(expr Str)] -> Bool
  :d "Detects negative, refute, or rejection assertion forms."
  (> (countNegativeAssertions expr) 0))

(df countPositiveAssertions [(body Str)] -> I64
  :d "Counts positive assertions in a test body."
  (let [(posCandidates (list "(assert (= "
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
          posCandidates)))

(df auditTestPolarity [(name Str) (body Str) (strict Bool) (minAsserts I64)] -> TestPolarityResult
  :d "Audits dual-case assertion balance for an individual test function."
  (let [(pos (countPositiveAssertions body))
        (neg (countNegativeAssertions body))
        (total (+ pos neg))
        (qual (and (>= total minAsserts)
                   (if strict
                     (and (>= pos 1) (>= neg 1))
                     true)))]
    (TestPolarityResult
      :name name
      :posCount pos
      :negCount neg
      :totalAsserts total
      :qualified qual)))

(df calculateCoveragePct [(qualified I64) (total I64)] -> I64
  :d "Calculates integer coverage percentage."
  (if (<= total 0)
    0
    (/ (* qualified 100) total)))

(df summarizeCoverage [(results (List TestPolarityResult)) (targetPct I64)] -> CoverageSummary
  :d "Aggregates test polarity results into an overall coverage summary."
  (let [(total (list-length results))
        (qual (fold (fn [(acc I64) (res TestPolarityResult)] -> I64
                      (if (.-qualified res)
                        (+ acc 1)
                        acc))
                    0
                    results))
        (pct (calculateCoveragePct qual total))]
    (CoverageSummary
      :totalTests total
      :qualifiedTests qual
      :coveragePct pct
      :passed (>= pct targetPct))))
