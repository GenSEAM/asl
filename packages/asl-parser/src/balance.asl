(module asl-parser/balance
  :d "Pure AgentScript delimiter balance and structural paren/bracket/brace validation engine."
  :x [BalanceResult check-delimiter-balance is-delimiter-balanced? count-unclosed-parens])

(dfs BalanceResult
  (:f balanced Bool "True if all delimiters are balanced and properly nested")
  (:f open-parens I64 "Remaining unclosed parentheses")
  (:f open-brackets I64 "Remaining unclosed square brackets")
  (:f open-braces I64 "Remaining unclosed curly braces"))

(df check-balance-step [(chars (List Str)) (p I64) (b I64) (br I64) (in-quote Bool) (escape Bool)] -> BalanceResult
  :d "Recursive string-aware and escape-aware delimiter balance scanner."
  (if (list-empty? chars)
    (let [(is-bal (and (= p 0)
                       (and (= b 0)
                            (and (= br 0)
                                 (not in-quote)))))]
      (BalanceResult
        :balanced is-bal
        :open-parens p
        :open-brackets b
        :open-braces br))
    (let [(c (option-or (list-head chars) ""))
          (rst (option-or (list-tail chars) (list)))]
      (if in-quote
        (if escape
          (check-balance-step rst p b br true false)
          (if (= c "\\")
            (check-balance-step rst p b br true true)
            (if (= c "\"")
              (check-balance-step rst p b br false false)
              (check-balance-step rst p b br true false))))
        (if (= c "\"")
          (check-balance-step rst p b br true false)
          (cond
            ((= c "(") (check-balance-step rst (+ p 1) b br false false))
            ((= c ")") (if (<= p 0) (BalanceResult :balanced false :open-parens -1 :open-brackets b :open-braces br) (check-balance-step rst (- p 1) b br false false)))
            ((= c "[") (check-balance-step rst p (+ b 1) br false false))
            ((= c "]") (if (<= b 0) (BalanceResult :balanced false :open-parens p :open-brackets -1 :open-braces br) (check-balance-step rst p (- b 1) br false false)))
            ((= c "{") (check-balance-step rst p b (+ br 1) false false))
            ((= c "}") (if (<= br 0) (BalanceResult :balanced false :open-parens p :open-brackets b :open-braces -1) (check-balance-step rst p b (- br 1) false false)))
            (:else (check-balance-step rst p b br false false))))))))

(df check-delimiter-balance [(code Str)] -> BalanceResult
  :d "Computes structural delimiter balance across parentheses, square brackets, and curly braces with string literal awareness."
  (check-balance-step (string-chars code) 0 0 0 false false))

(df is-delimiter-balanced? [(code Str)] -> Bool
  :d "Convenience predicate returning true if code has perfectly balanced delimiters."
  (.-balanced (check-delimiter-balance code)))

(df count-unclosed-parens [(code Str)] -> I64
  :d "Returns count of unclosed open parentheses in code or zero if balanced or corrupted."
  (let [(res (check-delimiter-balance code))]
    (if (and (not (.-balanced res)) (> (.-open-parens res) 0))
      (.-open-parens res)
      0)))
