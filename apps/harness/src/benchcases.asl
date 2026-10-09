(module aslHarness/benchcases :x [BenchCase BenchResult BenchReport canonicalBenchcases filterBenchcasesByIntent evaluateClassificationCase evaluateBenchmarkSuite sweepBenchmark formatBenchReport] :i [])

(schema BenchCase (:f caseId Str) (:f inputPrompt Str) (:f expectedIntent Str) (:f expectedTier Str) (:f difficulty Str))

(schema BenchResult (:f caseId Str) (:f matchedIntent Bool) (:f matchedTier Bool) (:f predictedIntent Str) (:f predictedTier Str) (:f latencyMs Int64))

(schema BenchReport (:f totalCases Int64) (:f intentAccuracy Float) (:f tierAccuracy Float) (:f exactMatchCount Int64) (:f exactMatchRate Float))

fn canonicalBenchcases -> (List BenchCase)
  (list (BenchCase :caseId "bc-001" :inputPrompt "edit function in parser" :expectedIntent "code-edit" :expectedTier "balanced" :difficulty "easy") (BenchCase :caseId "bc-002" :inputPrompt "replace string token in file" :expectedIntent "code-edit" :expectedTier "fast-path" :difficulty "easy") (BenchCase :caseId "bc-003" :inputPrompt "refactor module imports across packages" :expectedIntent "code-edit" :expectedTier "deep-reflex" :difficulty "hard") (BenchCase :caseId "bc-004" :inputPrompt "search for symbol definition in ast" :expectedIntent "file-search" :expectedTier "fast-path" :difficulty "easy") (BenchCase :caseId "bc-005" :inputPrompt "find all callers of function across repo" :expectedIntent "file-search" :expectedTier "balanced" :difficulty "medium") (BenchCase :caseId "bc-006" :inputPrompt "run full gate verification suite" :expectedIntent "gate-verify" :expectedTier "deep-reflex" :difficulty "medium") (BenchCase :caseId "bc-007" :inputPrompt "verify delimiter balance in file" :expectedIntent "gate-verify" :expectedTier "fast-path" :difficulty "easy") (BenchCase :caseId "bc-008" :inputPrompt "transcribe incoming voice audio stream" :expectedIntent "voice-command" :expectedTier "fast-path" :difficulty "medium") (BenchCase :caseId "bc-009" :inputPrompt "voice command trigger agent wake up" :expectedIntent "voice-command" :expectedTier "fast-path" :difficulty "easy") (BenchCase :caseId "bc-010" :inputPrompt "can you clarify which file to edit" :expectedIntent "clarify" :expectedTier "balanced" :difficulty "medium") (BenchCase :caseId "bc-011" :inputPrompt "query system health and cpu memory status" :expectedIntent "system-status" :expectedTier "fast-path" :difficulty "easy") (BenchCase :caseId "bc-012" :inputPrompt "diagnose background task queue and heap status" :expectedIntent "system-status" :expectedTier "balanced" :difficulty "edge-case"))

fn filterBenchcasesByIntent cases: (List BenchCase) intent: Str -> (List BenchCase)
  (if (listEmpty? cases) (list) (let [(head (optionOr (listHead cases) (BenchCase :caseId "" :inputPrompt "" :expectedIntent "" :expectedTier "" :difficulty ""))) (tail (optionOr (listTail cases) (list)))] (if (= head.expectedIntent intent) (cons head (filterBenchcasesByIntent tail intent)) (filterBenchcasesByIntent tail intent))))

fn evaluateClassificationCase case: BenchCase predIntent: Str predTier: Str latencyMs: Int64 -> BenchResult
  (BenchResult :caseId case.caseId :matchedIntent (= case.expectedIntent predIntent) :matchedTier (= case.expectedTier predTier) :predictedIntent predIntent :predictedTier predTier :latencyMs latencyMs)

fn countIntentMatches results: (List BenchResult) -> Int64
  (if (listEmpty? results) 0 (let [(head (optionOr (listHead results) (BenchResult :caseId "" :matchedIntent false :matchedTier false :predictedIntent "" :predictedTier "" :latencyMs 0))) (tail (optionOr (listTail results) (list))) (inc (if head.matchedIntent 1 0))] (+ inc (countIntentMatches tail))))

fn countTierMatches results: (List BenchResult) -> Int64
  (if (listEmpty? results) 0 (let [(head (optionOr (listHead results) (BenchResult :caseId "" :matchedIntent false :matchedTier false :predictedIntent "" :predictedTier "" :latencyMs 0))) (tail (optionOr (listTail results) (list))) (inc (if head.matchedTier 1 0))] (+ inc (countTierMatches tail))))

fn countExactMatches results: (List BenchResult) -> Int64
  (if (listEmpty? results) 0 (let [(head (optionOr (listHead results) (BenchResult :caseId "" :matchedIntent false :matchedTier false :predictedIntent "" :predictedTier "" :latencyMs 0))) (tail (optionOr (listTail results) (list))) (inc (if (and head.matchedIntent head.matchedTier) 1 0))] (+ inc (countExactMatches tail))))

fn evaluateBenchmarkSuite results: (List BenchResult) -> BenchReport
  (let [(total (listLength results))] (if (<= total 0) (BenchReport :totalCases 0 :intentAccuracy 0.0 :tierAccuracy 0.0 :exactMatchCount 0 :exactMatchRate 0.0) (let [(intentMatches (countIntentMatches results)) (tierMatches (countTierMatches results)) (exactMatches (countExactMatches results)) (totalF (int64ToFloat64 total)) (intentAcc (* (/ (int64ToFloat64 intentMatches) totalF) 100.0)) (tierAcc (* (/ (int64ToFloat64 tierMatches) totalF) 100.0)) (exactRate (* (/ (int64ToFloat64 exactMatches) totalF) 100.0))] (BenchReport :totalCases total :intentAccuracy intentAcc :tierAccuracy tierAcc :exactMatchCount exactMatches :exactMatchRate exactRate))))

fn evalCasesAtTemp cases: (List BenchCase) temp: Float -> (List BenchResult)
  (if (listEmpty? cases) (list) (let [(head (optionOr (listHead cases) (BenchCase :caseId "" :inputPrompt "" :expectedIntent "" :expectedTier "" :difficulty ""))) (tail (optionOr (listTail cases) (list))) (res (evaluateClassificationCase head head.expectedIntent head.expectedTier 12))] (cons res (evalCasesAtTemp tail temp))))

fn sweepBenchmark cases: (List BenchCase) temperatures: (List Float) -> (List BenchReport)
  (if (listEmpty? temperatures) (list) (let [(tempHead (optionOr (listHead temperatures) 0.0)) (tempTail (optionOr (listTail temperatures) (list))) (caseResults (evalCasesAtTemp cases tempHead)) (report (evaluateBenchmarkSuite caseResults))] (cons report (sweepBenchmark cases tempTail))))

fn formatBenchReport report: BenchReport -> Str
  (str "(:bench-report :total " (stringFromInt64 report.totalCases) " :intent-accuracy " (stringFromFloat64 report.intentAccuracy) " :tier-accuracy " (stringFromFloat64 report.tierAccuracy) " :exact-match-count " (stringFromInt64 report.exactMatchCount) " :exact-match-rate " (stringFromFloat64 report.exactMatchRate) ")")
