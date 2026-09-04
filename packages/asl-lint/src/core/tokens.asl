(module asl-lint/tokens
  :d "AgentScript native token density inspection, BPE ceiling enforcement, and token smell diagnostics."
  :x [TokenCategory TokenSmell TokenMetrics
      token-ceiling is-token-smell estimate-identifier-tokens
      compute-density-score should-block-token-gate
      format-token-smell])

(dfe TokenCategory
  (:c primitive  [] "Core language primitive (head, expression, option)")
  (:c builtin    [] "Standard library builtin or standard alias")
  (:c identifier [] "User-defined symbol, binding, or function name")
  (:c literal    [] "Literal constant value"))

(dfs TokenSmell
  (:f symbol Str "The symbol or form exceeding token threshold")
  (:f category TokenCategory "Classification of the tokenized item")
  (:f estimated-tokens I64 "Estimated or actual BPE token count")
  (:f threshold I64 "Maximum allowed token ceiling (default 2)")
  (:f file Str "Source file path")
  (:f line I64 "1-indexed line number")
  (:f col I64 "1-indexed column offset")
  (:f message Str "Diagnostic explanation of the token smell"))

(dfs TokenMetrics
  (:f total-symbols I64 "Total symbols inspected")
  (:f compliant-symbols I64 "Symbols adhering to the token ceiling")
  (:f violation-count I64 "Count of symbols exceeding ceiling")
  (:f max-tokens I64 "Maximum token count encountered in a symbol")
  (:f score I64 "Computed token efficiency score (0 to 100)"))

(df token-ceiling [] -> I64
  :d "Returns the strict 2-token ceiling for standard ASL forms."
  2)

(df is-token-smell [(estimated-tokens I64) (ceiling I64)] -> Bool
  :d "Returns true if the estimated token count exceeds allowable ceiling."
  (> estimated-tokens ceiling))

(df estimate-identifier-tokens [(name Str)] -> I64
  :d "Estimates BPE token count based on identifier length and hyphenated segments."
  (let [(parts (string-split name "-"))
        (part-count (list-length parts))
        (char-count (string-length name))]
    (if (> part-count 2)
      part-count
      (if (<= char-count 4)
        1
        (if (<= char-count 10)
          2
          (+ 2 (/ (- char-count 10) 4)))))))

(df compute-density-score [(total I64) (violations I64)] -> I64
  :d "Computes token efficiency score out of 100 based on violation ratio."
  (if (<= total 0)
    100
    (let [(penalty (/ (* violations 100) total))]
      (if (>= penalty 100)
        0
        (- 100 penalty)))))

(df should-block-token-gate [(metrics TokenMetrics)] -> Bool
  :d "Determines if token violations should block the pre-commit gate."
  (if (> (.-violation-count metrics) 0)
    true
    (< (.-score metrics) 80)))

(df format-token-smell [(smell TokenSmell)] -> Str
  :d "Formats a token smell into a human-readable diagnostic message."
  (str "Token ceiling violation in "
       (.-file smell)
       ":"
       (string-from-int64 (.-line smell))
       ": '"
       (.-symbol smell)
       "' takes "
       (string-from-int64 (.-estimated-tokens smell))
       " tokens (ceiling is "
       (string-from-int64 (.-threshold smell))
       ")"))
