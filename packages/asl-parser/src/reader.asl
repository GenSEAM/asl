(module asl-parser/reader
  :d "100% Self-Hosted AgentScript S-Expression Reader & Dual-Projection AST Engine."
  :x [SExpr make-atom make-list make-vect is-atom? is-list? is-vect?
           is-head-match? sexpr-head render-compound render-sexpr])

(dfe SExpr
  (:c sexpr-atom [(val String)] "Terminal atom token (symbol, literal or keyword)")
  (:c sexpr-list [(items (List SExpr))] "Parenthesized list '( ... )'")
  (:c sexpr-vect [(items (List SExpr))] "Bracketed vector '[ ... ]'"))

(df make-atom [(v String)] -> SExpr
  :d "Constructs a terminal atom SExpr."
  (sexpr-atom v))

(df make-list [(items (List SExpr))] -> SExpr
  :d "Constructs a parenthesized list SExpr."
  (sexpr-list items))

(df make-vect [(items (List SExpr))] -> SExpr
  :d "Constructs a bracketed vector SExpr."
  (sexpr-vect items))

(df is-atom? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is an atom."
  (mt s
    ((sexpr-atom _) true)
    ((sexpr-list _) false)
    ((sexpr-vect _) false)))

(df is-list? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is a list."
  (mt s
    ((sexpr-atom _) false)
    ((sexpr-list _) true)
    ((sexpr-vect _) false)))

(df is-vect? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is a bracketed vector."
  (mt s
    ((sexpr-atom _) false)
    ((sexpr-list _) false)
    ((sexpr-vect _) true)))

(df sexpr-head [(s SExpr)] -> String
  :d "Extracts the head symbol if s is a non-empty list or atom."
  (mt s
    ((sexpr-atom v) v)
    ((sexpr-list items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexpr-atom hv) hv)
          ((sexpr-list _)  "")
          ((sexpr-vect _)  "")))
       ((none) "")))
    ((sexpr-vect _) "")))

(df is-head-match? [(s SExpr) (expected String)] -> Bool
  :d "Checks if SExpr head matches expected symbol."
  (= (sexpr-head s) expected))

(dfe RItem
  (:c r-text [(t String)] "Literal output text, already final")
  (:c r-expr [(e SExpr)] "An SExpr still to be expanded"))

(dfs RState
  (:f work (List RItem) "Pending items, head first")
  (:f out (List String) "Emitted pieces, reversed"))

(df r-tail [(items (List RItem))] -> (List RItem)
  :d "The work list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df r-separated [(items (List SExpr))] -> (List RItem)
  :d "Child expressions with a single space between neighbours."
  (mt (list-head items)
    ((some h)
     (list-cons (r-expr h)
                (list-reverse
                  (fold (fn [(acc (List RItem)) (x SExpr)] -> (List RItem)
                          (list-cons (r-expr x) (list-cons (r-text " ") acc)))
                        (list)
                        (option-or (list-tail items) (list))))))
    ((none) (list))))

(df r-expand [(open String) (items (List SExpr)) (close String)] -> (List RItem)
  :d "One delimited form pushed onto the work list, outermost piece first."
  (list-cons (r-text open)
             (list-append (r-separated items) (list (r-text close)))))

(df r-tick [(st RState) (tick Int64)] -> RState
  :d "One work-list step: emit a piece, or expand one form in place."
  (mt (list-head (.-work st))
    ((some it)
     (let [(rest (r-tail (.-work st)))]
       (mt it
         ((r-text t) (RState :work rest :out (list-cons t (.-out st))))
         ((r-expr e)
          (mt e
            ((sexpr-atom v)     (RState :work rest :out (list-cons v (.-out st))))
            ((sexpr-list items) (RState :work (list-append (r-expand "(" items ")") rest)
                                        :out (.-out st)))
            ((sexpr-vect items) (RState :work (list-append (r-expand "[" items "]") rest)
                                        :out (.-out st))))))))
    ((none) st)))

(df r-run [(st RState) (budget Int64)] -> RState
  :d "Run work-list steps in doubling batches until the work list drains.

  The batch size doubles because `fold` needs its step count up front and a
  tree's node count is not known without walking it; recursion is then O(log n)
  in the node count rather than O(depth), which is what overflowed before."
  (let [(next (fold r-tick st (range 0 budget)))]
    (if (list-empty? (.-work next))
      next
      (r-run next (* budget 2)))))

(df r-render [(items (List RItem))] -> String
  :d "Drain a work list to its concatenated text."
  (string-join (list-reverse (.-out (r-run (RState :work items :out (list)) 64))) ""))

(df render-compound [(is-paren Bool) (items (List SExpr))] -> String
  :d "Renders delimited list of SExpr items."
  (r-render (r-expand (if is-paren "(" "[") items (if is-paren ")" "]"))))

(df render-sexpr [(s SExpr)] -> String
  :d "Renders an SExpr tree to string representation."
  (r-render (list (r-expr s))))
