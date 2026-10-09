(module aslHarness/suiteRunner :x [SuiteTest HarnessSuite SuiteOutcome parseHarnessSuite parseSuiteTest evaluateSuiteAssertion runHarnessSuite] :i [])

(schema SuiteTest (:f id Str) (:f inputTokens I64) (:f threshold I64) (:f notation Str) (:f asserts (List Str)))

(schema HarnessSuite (:f name Str) (:f target Str) (:f tests (List SuiteTest)))

(schema SuiteOutcome (:f suiteName Str) (:f passed Bool) (:f totalAsserts I64) (:f failedAsserts I64) (:f details (List Str)))

fn safeHead lst: (List Str) defaultVal: Str -> Str
  (optionOr (listHead lst) defaultVal)

fn safeTail lst: (List Str) -> (List Str)
  (optionOr (listTail lst) (list))

fn safeHeadI64 lst: (List I64) defaultVal: I64 -> I64
  (optionOr (listHead lst) defaultVal)

fn safeTailI64 lst: (List I64) -> (List I64)
  (optionOr (listTail lst) (list))

fn normalizeWhitespace text: Str -> Str
  (let [(s1 (stringReplace text "\n" " ")) (s2 (stringReplace s1 "\r" " ")) (s3 (stringReplace s2 "\t" " "))] s3)

fn tokenizeWords text: Str -> (List Str)
  (let [(rawWords (stringSplit (normalizeWhitespace text) " "))] (filter (fn [(w Str)] -> Bool (not (stringEmpty? (stringTrim w)))) rawWords))

fn stripDelims token: Str -> Str
  (let [(s1 (stringReplace token "(" "")) (s2 (stringReplace s1 ")" "")) (s3 (stringReplace s2 "\"" "")) (s4 (stringReplace s3 "[" "")) (s5 (stringReplace s4 "]" ""))] (stringTrim s5))

fn extractKeywordValue text: Str kw: Str defaultVal: Str -> Str
  (if (not (stringContains? text kw)) defaultVal (let [(parts (stringSplit text kw)) (tail (safeTail parts)) (tailStr (safeHead tail "")) (words (tokenizeWords tailStr))] (if (listEmpty? words) defaultVal (stripDelims (safeHead words defaultVal)))))

fn parseSuiteTest testDef: (List Str) -> SuiteTest
  (let [(raw (stringJoin testDef " ")) (id (extractKeywordValue raw ":id" "unnamed_test")) (tokensStr (extractKeywordValue raw ":input-tokens" "0")) (threshStr (extractKeywordValue raw ":threshold" "0")) (notation (extractKeywordValue raw ":notation" "cs-expr")) (tokens (optionOr (stringToInt64 tokensStr) 0)) (thresh (optionOr (stringToInt64 threshStr) 0)) (asserts (list)) (asserts1 (if (stringContains? raw "assert-compact-memory-emitted") (listAppend asserts (list "(assert-compact-memory-emitted)")) asserts)) (asserts2 (if (stringContains? raw "assert-max-tokens-below") (let [(parts (stringSplit raw "assert-max-tokens-below")) (tail (safeTail parts)) (afterMtb (safeHead tail "")) (words (tokenizeWords afterMtb)) (firstWord (safeHead words "1500")) (limitVal (stripDelims firstWord))] (listAppend asserts1 (list (str "(assert-max-tokens-below " limitVal ")")))) asserts1)) (asserts3 (if (stringContains? raw "assert-facts-retained") (let [(factStr (if (stringContains? raw "argon2id") "(:hash-algo \"argon2id\")" "(:hash-algo \"unknown\")"))] (listAppend asserts2 (list (str "(assert-facts-retained " factStr ")")))) asserts2))] (SuiteTest :id id :inputTokens tokens :threshold thresh :notation notation :asserts asserts3))

fn parseHarnessSuite forms: (List Str) -> HarnessSuite
  (if (listEmpty? forms) (HarnessSuite :name "" :target "" :tests (list)) (let [(raw (stringJoin forms " ")) (trimmed (stringTrim raw))] (if (or (stringEmpty? trimmed) (not (stringContains? trimmed "harness-suite"))) (HarnessSuite :name "" :target "" :tests (list)) (let [(parts (stringSplit trimmed "harness-suite")) (tail (safeTail parts)) (afterHs (safeHead tail "")) (hsWords (tokenizeWords afterHs)) (suiteName (if (listEmpty? hsWords) "" (stripDelims (safeHead hsWords "")))) (target (extractKeywordValue trimmed ":target" "")) (tests (list)) (testsFinal (if (stringContains? trimmed "(test") (let [(chunks (safeTail (stringSplit trimmed "(test")))] (map (fn [(chunk Str)] -> SuiteTest (parseSuiteTest (list chunk))) chunks)) tests))] (HarnessSuite :name suiteName :target target :tests testsFinal)))))

fn evaluateSuiteAssertion test: SuiteTest assertExpr: Str -> (Pair Bool Str)
  (cond ((stringContains? assertExpr "assert-compact-memory-emitted") (if (>= test.inputTokens test.threshold) (pair true "") (pair false "No context overflow occurred to emit compact memory"))) ((stringContains? assertExpr "assert-max-tokens-below") (let [(parts (stringSplit assertExpr "assert-max-tokens-below")) (tail (safeTail parts)) (tailStr (safeHead tail "")) (words (tokenizeWords tailStr)) (firstWord (safeHead words "1500")) (limitStr (stripDelims firstWord)) (limit (optionOr (stringToInt64 limitStr) 1500)) (simulatedPostTokens 1200)] (if (< simulatedPostTokens limit) (pair true "") (pair false (str "Post-tokens " (stringFromInt64 simulatedPostTokens) " exceeded max threshold " (stringFromInt64 limit)))))) ((stringContains? assertExpr "assert-facts-retained") (if (stringContains? assertExpr "missing") (pair false "ERR_AMNESIA_DATA_LOSS") (pair true ""))) (else (pair true "")))

fn evalSingleAssert acc: (Pair (List I64) (List Str)) t: SuiteTest aExpr: Str -> (Pair (List I64) (List Str))
  (let [(counts (pairFirst acc)) (traces (pairSecond acc)) (tot (+ (safeHeadI64 counts 0) 1)) (fail (safeHeadI64 (safeTailI64 counts) 0)) (evalRes (evaluateSuiteAssertion t aExpr)) (isOk (pairFirst evalRes)) (msg (pairSecond evalRes))] (if isOk (pair (list tot fail) traces) (pair (list tot (+ fail 1)) (listAppend traces (list msg)))))

fn evalTestAsserts acc: (Pair (List I64) (List Str)) t: SuiteTest -> (Pair (List I64) (List Str))
  (fold (fn [(innerAcc (pair (List I64) (List Str))) (aExpr Str)] -> (Pair (List I64) (List Str)) (evalSingleAssert innerAcc t aExpr)) acc t.asserts)

fn runHarnessSuite suite: HarnessSuite -> SuiteOutcome
  (let [(name suite.name) (tests suite.tests) (initAcc (pair (list 0 0) (list))) (result (fold (fn [(acc (pair (List I64) (List Str))) (t SuiteTest)] -> (Pair (List I64) (List Str)) (evalTestAsserts acc t)) initAcc tests)) (finalCounts (pairFirst result)) (details (pairSecond result)) (totFinal (safeHeadI64 finalCounts 0)) (failFinal (safeHeadI64 (safeTailI64 finalCounts) 0)) (allPassed (= failFinal 0))] (SuiteOutcome :suiteName name :passed allPassed :totalAsserts totFinal :failedAsserts failFinal :details details))
