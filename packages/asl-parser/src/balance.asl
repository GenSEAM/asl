(module asl-parser/balance
  :d "Pure AgentScript delimiter balance and structural paren/bracket/brace validation engine."
  :x [BalanceResult check-delimiter-balance is-delimiter-balanced? count-unclosed-parens balance-delimiters])

(dfs BalanceResult
  (:f balanced Bool "True if all delimiters are balanced and properly nested")
  (:f open-parens I64 "Remaining unclosed parentheses")
  (:f open-brackets I64 "Remaining unclosed square brackets")
  (:f open-braces I64 "Remaining unclosed curly braces"))

(df stack-count-symbol [(stack (List Str)) (sym Str)] -> I64
  :d "Counts occurrences of a delimiter in the LIFO stack"
  (fold (fn [(acc I64) (item Str)] -> I64 (if (string-equals? item sym) (+ acc 1) acc)) 0 stack))

(df check-balance-step [(chars (List Str)) (stack (List Str)) (in-quote Bool) (escape Bool)] -> BalanceResult
  :d "Recursive string-aware and escape-aware delimiter balance scanner with LIFO delimiter stack."
  (if (list-empty? chars)
    (let [(p (stack-count-symbol stack "("))
          (b (stack-count-symbol stack "["))
          (br (stack-count-symbol stack "{"))
          (is-bal (and (= p 0)
                       (and (= b 0)
                            (and (= br 0)
                                 (and (list-empty? stack)
                                      (not in-quote))))))]
      (BalanceResult
        :balanced is-bal
        :open-parens p
        :open-brackets b
        :open-braces br))
    (let [(c (option-or (list-head chars) ""))
          (rst (option-or (list-tail chars) (list)))]
      (if in-quote
        (if escape
          (check-balance-step rst stack true false)
          (if (= c "\\")
            (check-balance-step rst stack true true)
            (if (= c "\"")
              (check-balance-step rst stack false false)
              (check-balance-step rst stack true false))))
        (if (= c "\"")
          (check-balance-step rst stack true false)
          (cond
            ((= c "(")
             (check-balance-step rst (cons "(" stack) false false))
            ((= c ")")
             (if (list-empty? stack)
               (BalanceResult :balanced false :open-parens -1 :open-brackets 0 :open-braces 0)
               (let [(top (option-or (list-head stack) ""))
                     (stk-rst (option-or (list-tail stack) (list)))]
                 (if (= top "(")
                   (check-balance-step rst stk-rst false false)
                   (let [(p (stack-count-symbol stack "("))
                         (b (stack-count-symbol stack "["))
                         (br (stack-count-symbol stack "{"))]
                     (BalanceResult :balanced false :open-parens p :open-brackets b :open-braces br))))))
            ((= c "[")
             (check-balance-step rst (cons "[" stack) false false))
            ((= c "]")
             (if (list-empty? stack)
               (BalanceResult :balanced false :open-parens 0 :open-brackets -1 :open-braces 0)
               (let [(top (option-or (list-head stack) ""))
                     (stk-rst (option-or (list-tail stack) (list)))]
                 (if (= top "[")
                   (check-balance-step rst stk-rst false false)
                   (let [(p (stack-count-symbol stack "("))
                         (b (stack-count-symbol stack "["))
                         (br (stack-count-symbol stack "{"))]
                     (BalanceResult :balanced false :open-parens p :open-brackets b :open-braces br))))))
            ((= c "{")
             (check-balance-step rst (cons "{" stack) false false))
            ((= c "}")
             (if (list-empty? stack)
               (BalanceResult :balanced false :open-parens 0 :open-brackets 0 :open-braces -1)
               (let [(top (option-or (list-head stack) ""))
                     (stk-rst (option-or (list-tail stack) (list)))]
                 (if (= top "{")
                   (check-balance-step rst stk-rst false false)
                   (let [(p (stack-count-symbol stack "("))
                         (b (stack-count-symbol stack "["))
                         (br (stack-count-symbol stack "{"))]
                     (BalanceResult :balanced false :open-parens p :open-brackets b :open-braces br))))))
            (:else
             (check-balance-step rst stack false false))))))))

(df check-delimiter-balance [(code Str)] -> BalanceResult
  :d "Computes structural delimiter balance across parentheses, square brackets, and curly braces with string literal awareness."
  (check-balance-step (string-chars code) (list) false false))

(df is-delimiter-balanced? [(code Str)] -> Bool
  :d "Convenience predicate returning true if code has perfectly balanced delimiters."
  (.-balanced (check-delimiter-balance code)))

(df count-unclosed-parens [(code Str)] -> I64
  :d "Returns count of unclosed open parentheses in code or zero if balanced or corrupted."
  (let [(res (check-delimiter-balance code))]
    (if (and (not (.-balanced res)) (> (.-open-parens res) 0))
      (.-open-parens res)
      0)))

(df balance-delimiters [(raw Str)] -> Str
  :d "Balances unclosed parentheses in S-expressions with quote and escape awareness."
  (let [(delta (count-unclosed-parens raw))]
    (if (> delta 0)
      (let [(closers (fold (fn [(acc Str) (_ I64)] -> Str (str acc ")")) "" (range 0 delta)))]
        (str raw closers))
      raw)))
