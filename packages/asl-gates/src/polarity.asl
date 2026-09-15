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
  :i [(string :a s)
      (asl-parser/lexer :a lx)])

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

(dfs PolarityState
  (:f prev Str "Previous token text")
  (:f assertPending Bool "True if assert was seen and next token awaited")
  (:f assertParenPending Bool "True if assert with paren was seen and subhead awaited")
  (:f posCount I64 "Positive assertion count")
  (:f negCount I64 "Negative assertion count"))

(df isNegHead? [(tok Str)] -> Bool
  :d "Checks if token matches an unambiguous negative assertion operator"
  (or (= tok "refute")
  (or (= tok "refute-case")
  (or (= tok "assert-reject")
  (or (= tok "assert-err")
  (or (= tok "assert-nil")
  (or (= tok "assert-null")
      (= tok "assert-false"))))))))

(df isNegSubhead? [(tok Str)] -> Bool
  :d "Checks if subform head of assert is a negative predicate"
  (or (= tok "not")
  (or (= tok "nil?")
  (or (= tok "empty?")
      (= tok "zero?")))))

(df isPosHead? [(tok Str)] -> Bool
  :d "Checks if token matches a direct positive assertion operator"
  (or (= tok "assert-eq")
      (= tok "assert-true")))

(df polarityStep [(st PolarityState) (tok lx/Token)] -> PolarityState
  :d "Processes one token in the S-expression token stream"
  (let [(raw (.-rawText tok))
        (prev (.-prev st))
        (isParen (= raw "("))]
    (cond
      ((.-assertPending st)
       (if isParen
         (PolarityState :prev raw :assertPending false :assertParenPending true :posCount (.-posCount st) :negCount (.-negCount st))
         (if (= raw "false")
           (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (.-posCount st) :negCount (+ (.-negCount st) 1))
           (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (+ (.-posCount st) 1) :negCount (.-negCount st)))))
      ((.-assertParenPending st)
       (if (isNegSubhead? raw)
         (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (.-posCount st) :negCount (+ (.-negCount st) 1))
         (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (+ (.-posCount st) 1) :negCount (.-negCount st))))
      ((= prev "(")
       (cond
         ((= raw "assert")
          (PolarityState :prev raw :assertPending true :assertParenPending false :posCount (.-posCount st) :negCount (.-negCount st)))
         ((isNegHead? raw)
          (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (.-posCount st) :negCount (+ (.-negCount st) 1)))
         ((isPosHead? raw)
          (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (+ (.-posCount st) 1) :negCount (.-negCount st)))
         (:else
          (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (.-posCount st) :negCount (.-negCount st)))))
      (:else
       (PolarityState :prev raw :assertPending false :assertParenPending false :posCount (.-posCount st) :negCount (.-negCount st))))))

(df scanPolarity [(body Str)] -> PolarityState
  :d "Tokenizes source string and counts assertions via structural token stream"
  (let [(toks (lx/tokenize body))
        (initState (PolarityState :prev "" :assertPending false :assertParenPending false :posCount 0 :negCount 0))]
    (fold polarityStep initState toks)))

(df countNegativeAssertions [(body Str)] -> I64
  :d "Counts negative and refutation assertions in a test body via AST token analysis."
  (.-negCount (scanPolarity body)))

(df isNegativeAssertion? [(expr Str)] -> Bool
  :d "Detects negative, refute, or rejection assertion forms."
  (> (countNegativeAssertions expr) 0))

(df countPositiveAssertions [(body Str)] -> I64
  :d "Counts positive assertions in a test body via AST token analysis."
  (.-posCount (scanPolarity body)))

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
