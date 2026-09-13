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
  (fold (fn [(acc I64) (item Str)] -> I64 (if (stringEquals? item sym) (+ acc 1) acc)) 0 stack))

(df checkBalanceStep [(chars (List Str)) (stack (List Str)) (inQuote Bool) (escape Bool)] -> BalanceResult
  :d "Recursive string-aware and escape-aware delimiter balance scanner with LIFO delimiter stack."
  (if (list-empty? chars)
    (let [(p (stackCountSymbol stack "("))
          (b (stackCountSymbol stack "["))
          (br (stackCountSymbol stack "{"))
          (isBal (and (= p 0)
                       (and (= b 0)
                            (and (= br 0)
                                 (and (list-empty? stack)
                                      (not inQuote))))))]
      (BalanceResult
        :balanced isBal
        :openParens p
        :openBrackets b
        :openBraces br))
    (let [(c (option-or (list-head chars) ""))
          (rst (option-or (list-tail chars) (list)))]
      (if inQuote
        (if escape
          (checkBalanceStep rst stack true false)
          (if (= c "\\")
            (checkBalanceStep rst stack true true)
            (if (= c "\"")
              (checkBalanceStep rst stack false false)
              (checkBalanceStep rst stack true false))))
        (if (= c "\"")
          (checkBalanceStep rst stack true false)
          (cond
            ((= c "(")
             (checkBalanceStep rst (cons "(" stack) false false))
            ((= c ")")
             (if (list-empty? stack)
               (BalanceResult :balanced false :openParens -1 :openBrackets 0 :openBraces 0)
               (let [(top (option-or (list-head stack) ""))
                     (stkRst (option-or (list-tail stack) (list)))]
                 (if (= top "(")
                   (checkBalanceStep rst stkRst false false)
                   (let [(p (stackCountSymbol stack "("))
                         (b (stackCountSymbol stack "["))
                         (br (stackCountSymbol stack "{"))]
                     (BalanceResult :balanced false :openParens p :openBrackets b :openBraces br))))))
            ((= c "[")
             (checkBalanceStep rst (cons "[" stack) false false))
            ((= c "]")
             (if (list-empty? stack)
               (BalanceResult :balanced false :openParens 0 :openBrackets -1 :openBraces 0)
               (let [(top (option-or (list-head stack) ""))
                     (stkRst (option-or (list-tail stack) (list)))]
                 (if (= top "[")
                   (checkBalanceStep rst stkRst false false)
                   (let [(p (stackCountSymbol stack "("))
                         (b (stackCountSymbol stack "["))
                         (br (stackCountSymbol stack "{"))]
                     (BalanceResult :balanced false :openParens p :openBrackets b :openBraces br))))))
            ((= c "{")
             (checkBalanceStep rst (cons "{" stack) false false))
            ((= c "}")
             (if (list-empty? stack)
               (BalanceResult :balanced false :openParens 0 :openBrackets 0 :openBraces -1)
               (let [(top (option-or (list-head stack) ""))
                     (stkRst (option-or (list-tail stack) (list)))]
                 (if (= top "{")
                   (checkBalanceStep rst stkRst false false)
                   (let [(p (stackCountSymbol stack "("))
                         (b (stackCountSymbol stack "["))
                         (br (stackCountSymbol stack "{"))]
                     (BalanceResult :balanced false :openParens p :openBrackets b :openBraces br))))))
            (:else
             (checkBalanceStep rst stack false false))))))))

(df checkDelimiterBalance [(code Str)] -> BalanceResult
  :d "Computes structural delimiter balance across parentheses, square brackets, and curly braces with string literal awareness."
  (checkBalanceStep (string-chars code) (list) false false))

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
