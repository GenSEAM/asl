(module asl-parser/reader
  :d "100% Self-Hosted AgentScript S-Expression Reader & Dual-Projection AST Engine."
  :x [SExpr make-atom make-list make-vect is-atom? is-list?
           is-head-match? is-dual-head? sexpr-head render-compound render-sexpr])

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

(df is-dual-head? [(s SExpr) (verbose String) (nano String)] -> Bool
  :d "Checks if SExpr matches either Verbose or Ultra-Nano head."
  (let [(h (sexpr-head s))]
    (or (= h verbose) (= h nano))))

(df render-compound [(is-paren Bool) (items (List SExpr))] -> String
  :d "Renders delimited list of SExpr items."
  (let [(open (if is-paren "(" "["))
        (close (if is-paren ")" "]"))
        (body (string-join (map (fn [x] (render-sexpr x)) items) " "))]
    (str open body close)))

(df render-sexpr [(s SExpr)] -> String
  :d "Renders an SExpr tree to string representation."
  (mt s
    ((sexpr-atom v)     v)
    ((sexpr-list items) (render-compound true items))
    ((sexpr-vect items) (render-compound false items))))
