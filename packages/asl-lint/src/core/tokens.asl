(module asl-lint/tokens
  :d "AgentScript native token density inspection, BPE ceiling enforcement, and token smell diagnostics."
  :x [TokenCategory TokenSmell TokenMetrics
      tokenCeiling isTokenSmell estimateIdentifierTokens
      computeDensityScore shouldBlockTokenGate
      formatTokenSmell])

(dfe TokenCategory
  (:c primitive  [] "Core language primitive (head, expression, option)")
  (:c builtin    [] "Standard library builtin or standard alias")
  (:c identifier [] "User-defined symbol, binding, or function name")
  (:c literal    [] "Literal constant value"))

(dfs TokenSmell
  (:f symbol Str "The symbol or form exceeding token threshold")
  (:f category TokenCategory "Classification of the tokenized item")
  (:f estimatedTokens I64 "Estimated or actual BPE token count")
  (:f threshold I64 "Maximum allowed token ceiling (default 2)")
  (:f file Str "Source file path")
  (:f line I64 "1-indexed line number")
  (:f col I64 "1-indexed column offset")
  (:f message Str "Diagnostic explanation of the token smell"))

(dfs TokenMetrics
  (:f totalSymbols I64 "Total symbols inspected")
  (:f compliantSymbols I64 "Symbols adhering to the token ceiling")
  (:f violationCount I64 "Count of symbols exceeding ceiling")
  (:f maxTokens I64 "Maximum token count encountered in a symbol")
  (:f score I64 "Computed token efficiency score (0 to 100)"))

(df tokenCeiling [] -> I64
  :d "Returns the strict 2-token ceiling for standard ASL forms."
  2)

(df isTokenSmell [(estimatedTokens I64) (ceiling I64)] -> Bool
  :d "Returns true if the estimated token count exceeds allowable ceiling."
  (> estimatedTokens ceiling))

(df estimateIdentifierTokens [(name Str)] -> I64
  :d "Estimates BPE token count based on identifier length and hyphenated segments."
  (let [(parts (string-split name "-"))
        (partCount (list-length parts))
        (charCount (string-length name))]
    (if (> partCount 2)
      partCount
      (if (<= charCount 4)
        1
        (if (<= charCount 10)
          2
          (+ 2 (/ (- charCount 10) 4)))))))

(df computeDensityScore [(total I64) (violations I64)] -> I64
  :d "Computes token efficiency score out of 100 based on violation ratio."
  (if (<= total 0)
    100
    (let [(penalty (/ (* violations 100) total))]
      (if (>= penalty 100)
        0
        (- 100 penalty)))))

(df shouldBlockTokenGate [(metrics TokenMetrics)] -> Bool
  :d "Determines if token violations should block the pre-commit gate."
  (if (> (.-violationCount metrics) 0)
    true
    (< (.-score metrics) 80)))

(df formatTokenSmell [(smell TokenSmell)] -> Str
  :d "Formats a token smell into a human-readable diagnostic message."
  (str "Token ceiling violation in "
       (.-file smell)
       ":"
       (string-from-int64 (.-line smell))
       ": '"
       (.-symbol smell)
       "' takes "
       (string-from-int64 (.-estimatedTokens smell))
       " tokens (ceiling is "
       (string-from-int64 (.-threshold smell))
       ")"))
