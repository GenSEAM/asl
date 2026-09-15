(module asl-parser/balance
  :d "Pure AgentScript delimiter balance and structural paren/bracket/brace validation engine."
  :x [BalanceResult checkDelimiterBalance isDelimiterBalanced? countUnclosedParens balanceDelimiters])

(dfs BalanceResult
  (:f balanced Bool "True if all delimiters are balanced and properly nested")
  (:f openParens I64 "Remaining unclosed parentheses")
  (:f openBrackets I64 "Remaining unclosed square brackets")
  (:f openBraces I64 "Remaining unclosed curly braces"))

(df stackCountSymbol [(stack (List Str)) (sym Str)] -> I64
  :d "Counts occurrences of a delimiter in the LIFO stack"
  (fold (fn [(acc I64) (item Str)] -> I64 (if (string-equals? item sym) (+ acc 1) acc)) 0 stack))

(dfs BalanceScanState
  (:f stack (List Str) "LIFO delimiter stack")
  (:f inQuote Bool "Currently inside a string literal")
  (:f escape Bool "Previous character was a backslash")
  (:f earlyError Bool "Encountered unmatched closing delimiter"))

(df balanceScanStep [(state BalanceScanState) (c Str)] -> BalanceScanState
  :d "Fold step function: processes one character against the balance scan state."
  (if (.-earlyError state)
    state
    (if (.-inQuote state)
      (if (.-escape state)
        (BalanceScanState :stack (.-stack state) :inQuote true :escape false :earlyError false)
        (if (= c "\\")
          (BalanceScanState :stack (.-stack state) :inQuote true :escape true :earlyError false)
          (if (= c "\"")
            (BalanceScanState :stack (.-stack state) :inQuote false :escape false :earlyError false)
            (BalanceScanState :stack (.-stack state) :inQuote true :escape false :earlyError false))))
      (if (= c "\"")
        (BalanceScanState :stack (.-stack state) :inQuote true :escape false :earlyError false)
        (cond
          ((= c "(")
           (BalanceScanState :stack (cons "(" (.-stack state)) :inQuote false :escape false :earlyError false))
          ((= c ")")
           (if (list-empty? (.-stack state))
             (BalanceScanState :stack (list) :inQuote false :escape false :earlyError true)
             (let [(top (option-or (list-head (.-stack state)) ""))
                   (stkRst (option-or (list-tail (.-stack state)) (list)))]
               (if (= top "(")
                 (BalanceScanState :stack stkRst :inQuote false :escape false :earlyError false)
                 (BalanceScanState :stack (.-stack state) :inQuote false :escape false :earlyError true)))))
          ((= c "[")
           (BalanceScanState :stack (cons "[" (.-stack state)) :inQuote false :escape false :earlyError false))
          ((= c "]")
           (if (list-empty? (.-stack state))
             (BalanceScanState :stack (list) :inQuote false :escape false :earlyError true)
             (let [(top (option-or (list-head (.-stack state)) ""))
                   (stkRst (option-or (list-tail (.-stack state)) (list)))]
               (if (= top "[")
                 (BalanceScanState :stack stkRst :inQuote false :escape false :earlyError false)
                 (BalanceScanState :stack (.-stack state) :inQuote false :escape false :earlyError true)))))
          ((= c "{")
           (BalanceScanState :stack (cons "{" (.-stack state)) :inQuote false :escape false :earlyError false))
          ((= c "}")
           (if (list-empty? (.-stack state))
             (BalanceScanState :stack (list) :inQuote false :escape false :earlyError true)
             (let [(top (option-or (list-head (.-stack state)) ""))
                   (stkRst (option-or (list-tail (.-stack state)) (list)))]
               (if (= top "{")
                 (BalanceScanState :stack stkRst :inQuote false :escape false :earlyError false)
                 (BalanceScanState :stack (.-stack state) :inQuote false :escape false :earlyError true)))))
          (:else state))))))

(df checkDelimiterBalance [(code Str)] -> BalanceResult
  :d "Computes structural delimiter balance across parentheses, square brackets, and curly braces with string literal awareness. Uses fold to avoid stack overflow on large inputs."
  (let [(initState (BalanceScanState :stack (list) :inQuote false :escape false :earlyError false))
        (finalState (fold balanceScanStep initState (string-chars code)))
        (p (stackCountSymbol (.-stack finalState) "("))
        (b (stackCountSymbol (.-stack finalState) "["))
        (br (stackCountSymbol (.-stack finalState) "{"))
        (isBal (and (not (.-earlyError finalState))
                     (and (= p 0)
                          (and (= b 0)
                               (and (= br 0)
                                    (and (list-empty? (.-stack finalState))
                                         (not (.-inQuote finalState))))))))]
    (BalanceResult
      :balanced isBal
      :openParens (if (.-earlyError finalState) -1 p)
      :openBrackets (if (.-earlyError finalState) -1 b)
      :openBraces (if (.-earlyError finalState) -1 br))))

(df isDelimiterBalanced? [(code Str)] -> Bool
  :d "Convenience predicate returning true if code has perfectly balanced delimiters."
  (.-balanced (checkDelimiterBalance code)))

(df countUnclosedParens [(code Str)] -> I64
  :d "Returns count of unclosed open parentheses in code or zero if balanced or corrupted."
  (let [(res (checkDelimiterBalance code))]
    (if (and (not (.-balanced res)) (> (.-openParens res) 0))
      (.-openParens res)
      0)))

(df balanceDelimiters [(raw Str)] -> Str
  :d "Balances unclosed parentheses in S-expressions with quote and escape awareness."
  (let [(delta (countUnclosedParens raw))]
    (if (> delta 0)
      (let [(closers (fold (fn [(acc Str) (_ I64)] -> Str (str acc ")")) "" (range 0 delta)))]
        (str raw closers))
      raw)))
