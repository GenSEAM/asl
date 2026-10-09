(module asl-gates/polarity :x [TestPolarityResult CoverageSummary isTestSymbol? isNegativeAssertion? countNegativeAssertions countPositiveAssertions auditTestPolarity calculateCoveragePct summarizeCoverage] :i [(string :a s) (asl-parser/lexer :a lx)])

(schema TestPolarityResult (:f name Str) (:f posCount I64) (:f negCount I64) (:f totalAsserts I64) (:f qualified Bool))

(schema CoverageSummary (:f totalTests I64) (:f qualifiedTests I64) (:f coveragePct I64) (:f passed Bool))

fn isTestSymbol? name: Str -> Bool
  (and (not (= name "run-tests")) (and (not (= name "test-runner")) (or (s/starts? name "test-") (or (s/starts? name "test_") (or (s/ends? name "-test") (and (s/starts? name "Test") (> (stringLength name) 4)))))))

(schema PolarityState (:f prev Str) (:f assertPending Bool) (:f assertParenPending Bool) (:f posCount I64) (:f negCount I64))

fn isNegHead? tok: Str -> Bool
  (or (= tok "refute") (or (= tok "refute-case") (or (= tok "assert-reject") (or (= tok "assert-err") (or (= tok "assert-nil") (or (= tok "assert-null") (= tok "assert-false")))))))

fn isNegSubhead? tok: Str -> Bool
  (or (= tok "not") (or (= tok "nil?") (or (= tok "empty?") (= tok "zero?"))))

fn isPosHead? tok: Str -> Bool
  (or (= tok "assert-eq") (= tok "assert-true"))

fn polarityStep st: PolarityState tok: lx/Token -> PolarityState
  (let [(raw tok.rawText) (prev st.prev) (isParen (= raw "("))] (cond (st.assertPending (if isParen (with st :prev raw :assertPending false :assertParenPending true) (if (= raw "false") (with st :prev raw :assertPending false :assertParenPending false :negCount (+ st.negCount 1)) (with st :prev raw :assertPending false :assertParenPending false :posCount (+ st.posCount 1))))) (st.assertParenPending (if (isNegSubhead? raw) (with st :prev raw :assertPending false :assertParenPending false :negCount (+ st.negCount 1)) (with st :prev raw :assertPending false :assertParenPending false :posCount (+ st.posCount 1)))) ((= prev "(") (cond ((= raw "assert") (with st :prev raw :assertPending true :assertParenPending false)) ((isNegHead? raw) (with st :prev raw :assertPending false :assertParenPending false :negCount (+ st.negCount 1))) ((isPosHead? raw) (with st :prev raw :assertPending false :assertParenPending false :posCount (+ st.posCount 1))) (else (with st :prev raw :assertPending false :assertParenPending false)))) (else (with st :prev raw :assertPending false :assertParenPending false))))

fn scanPolarity body: Str -> PolarityState
  (let [(toks (lx/tokenize body)) (initState (PolarityState :prev "" :assertPending false :assertParenPending false :posCount 0 :negCount 0))] (fold polarityStep initState toks))

fn countNegativeAssertions body: Str -> I64
  (scanPolarity body).negCount

fn isNegativeAssertion? expr: Str -> Bool
  (> (countNegativeAssertions expr) 0)

fn countPositiveAssertions body: Str -> I64
  (scanPolarity body).posCount

fn auditTestPolarity name: Str body: Str strict: Bool minAsserts: I64 -> TestPolarityResult
  (let [(pos (countPositiveAssertions body)) (neg (countNegativeAssertions body)) (total (+ pos neg)) (qual (and (>= total minAsserts) (if strict (and (>= pos 1) (>= neg 1)) true)))] (TestPolarityResult :name name :posCount pos :negCount neg :totalAsserts total :qualified qual))

fn calculateCoveragePct qualified: I64 total: I64 -> I64
  (if (<= total 0) 0 (/ (* qualified 100) total))

fn summarizeCoverage results: (List TestPolarityResult) targetPct: I64 -> CoverageSummary
  (let [(total (listLength results)) (qual (fold (fn [(acc I64) (res TestPolarityResult)] -> I64 (if res.qualified (+ acc 1) acc)) 0 results)) (pct (calculateCoveragePct qual total))] (CoverageSummary :totalTests total :qualifiedTests qual :coveragePct pct :passed (>= pct targetPct)))
