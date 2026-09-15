(module asl-parser/reader
  :d "100% Self-Hosted AgentScript S-Expression Reader & Dual-Projection AST Engine."
  :x [SExpr makeAtom makeList makeVect isAtom? isList? isVect?
           isHeadMatch? sexprHead sexprToList renderCompound renderSexpr])

(dfe SExpr
  (:c sexprAtom [(val String)] "Terminal atom token (symbol, literal or keyword)")
  (:c sexprList [(items (List SExpr))] "Parenthesized list '( ... )'")
  (:c sexprVect [(items (List SExpr))] "Bracketed vector '[ ... ]'"))

(df makeAtom [(v String)] -> SExpr
  :d "Constructs a terminal atom SExpr."
  (sexprAtom v))

(df makeList [(items (List SExpr))] -> SExpr
  :d "Constructs a parenthesized list SExpr."
  (sexprList items))

(df makeVect [(items (List SExpr))] -> SExpr
  :d "Constructs a bracketed vector SExpr."
  (sexprVect items))

(df isAtom? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is an atom."
  (mt s
    ((sexprAtom _) true)
    ((sexprList _) false)
    ((sexprVect _) false)))

(df isList? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is a list."
  (mt s
    ((sexprAtom _) false)
    ((sexprList _) true)
    ((sexprVect _) false)))

(df isVect? [(s SExpr)] -> Bool
  :d "Returns true if SExpr is a bracketed vector."
  (mt s
    ((sexprAtom _) false)
    ((sexprList _) false)
    ((sexprVect _) true)))

(df sexprHead [(s SExpr)] -> String
  :d "Extracts the head symbol if s is a non-empty list or atom."
  (mt s
    ((sexprAtom v) v)
    ((sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexprAtom hv) hv)
          ((sexprList _)  "")
          ((sexprVect _)  "")))
       ((none) "")))
    ((sexprVect _) "")))

(df isHeadMatch? [(s SExpr) (expected String)] -> Bool
  :d "Checks if SExpr head matches expected symbol."
  (= (sexprHead s) expected))

(df sexprToList [(s SExpr)] -> (List SExpr)
  :d "Extracts elements list from vector or list S-expression, or empty list for atom."
  (mt s
    ((sexprVect items) items)
    ((sexprList items) items)
    ((sexprAtom _) (list))))

(dfe RItem
  (:c rText [(t String)] "Literal output text, already final")
  (:c rExpr [(e SExpr)] "An SExpr still to be expanded"))

(dfs RState
  (:f work (List RItem) "Pending items, head first")
  (:f out (List String) "Emitted pieces, reversed"))

(df rTail [(items (List RItem))] -> (List RItem)
  :d "The work list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df rSeparated [(items (List SExpr))] -> (List RItem)
  :d "Child expressions with a single space between neighbours."
  (mt (list-head items)
    ((some h)
     (list-cons (rExpr h)
                (list-reverse
                  (fold (fn [(acc (List RItem)) (x SExpr)] -> (List RItem)
                          (list-cons (rExpr x) (list-cons (rText " ") acc)))
                        (list)
                        (option-or (list-tail items) (list))))))
    ((none) (list))))

(df rExpand [(open String) (items (List SExpr)) (close String)] -> (List RItem)
  :d "One delimited form pushed onto the work list, outermost piece first."
  (list-cons (rText open)
             (list-append (rSeparated items) (list (rText close)))))

(df rTick [(st RState) (tick Int64)] -> RState
  :d "One work-list step: emit a piece, or expand one form in place."
  (mt (list-head (.-work st))
    ((some it)
     (let [(rest (rTail (.-work st)))]
       (mt it
         ((rText t) (RState :work rest :out (list-cons t (.-out st))))
         ((rExpr e)
          (mt e
            ((sexprAtom v)     (RState :work rest :out (list-cons v (.-out st))))
            ((sexprList items) (RState :work (list-append (rExpand "(" items ")") rest)
                                        :out (.-out st)))
            ((sexprVect items) (RState :work (list-append (rExpand "[" items "]") rest)
                                        :out (.-out st))))))))
    ((none) st)))

(df rRun [(st RState) (budget Int64)] -> RState
  :d "Run work-list steps in doubling batches until the work list drains.

  The batch size doubles because `fold` needs its step count up front and a
  tree's node count is not known without walking it; recursion is then O(log n)
  in the node count rather than O(depth), which is what overflowed before."
  (let [(next (fold rTick st (range 0 budget)))]
    (if (list-empty? (.-work next))
      next
      (rRun next (* budget 2)))))

(df rRender [(items (List RItem))] -> String
  :d "Drain a work list to its concatenated text."
  (string-join (list-reverse (.-out (rRun (RState :work items :out (list)) 64))) ""))

(df renderCompound [(isParen Bool) (items (List SExpr))] -> String
  :d "Renders delimited list of SExpr items."
  (rRender (rExpand (if isParen "(" "[") items (if isParen ")" "]"))))

(df renderSexpr [(s SExpr)] -> String
  :d "Renders an SExpr tree to string representation."
  (rRender (list (rExpr s))))
