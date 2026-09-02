(module asl-parser/reader
  :doc "100% Self-Hosted AgentScript S-Expression Reader & Dual-Projection AST Engine."
  :export [SExpr make-atom make-list make-vect is-atom? is-list?
           is-head-match? is-dual-head? sexpr-head render-compound render-sexpr])

(defenum SExpr
  (:case sexpr-atom [(val String)] "Terminal atom token (symbol, literal or keyword)")
  (:case sexpr-list [(items (List SExpr))] "Parenthesized list '( ... )'")
  (:case sexpr-vect [(items (List SExpr))] "Bracketed vector '[ ... ]'"))

(defun make-atom [(v String)] -> SExpr
  :doc "Constructs a terminal atom SExpr."
  (sexpr-atom v))

(defun make-list [(items (List SExpr))] -> SExpr
  :doc "Constructs a parenthesized list SExpr."
  (sexpr-list items))

(defun make-vect [(items (List SExpr))] -> SExpr
  :doc "Constructs a bracketed vector SExpr."
  (sexpr-vect items))

(defun is-atom? [(s SExpr)] -> Bool
  :doc "Returns true if SExpr is an atom."
  (match s
    ((sexpr-atom _) true)
    ((sexpr-list _) false)
    ((sexpr-vect _) false)))

(defun is-list? [(s SExpr)] -> Bool
  :doc "Returns true if SExpr is a list."
  (match s
    ((sexpr-atom _) false)
    ((sexpr-list _) true)
    ((sexpr-vect _) false)))

(defun sexpr-head [(s SExpr)] -> String
  :doc "Extracts the head symbol if s is a non-empty list or atom."
  (match s
    ((sexpr-atom v) v)
    ((sexpr-list items)
     (match (list-head items)
       ((some h)
        (match h
          ((sexpr-atom hv) hv)
          ((sexpr-list _)  "")
          ((sexpr-vect _)  "")))
       ((none) "")))
    ((sexpr-vect _) "")))

(defun is-head-match? [(s SExpr) (expected String)] -> Bool
  :doc "Checks if SExpr head matches expected symbol."
  (= (sexpr-head s) expected))

(defun is-dual-head? [(s SExpr) (verbose String) (nano String)] -> Bool
  :doc "Checks if SExpr matches either Verbose or Ultra-Nano head."
  (let [(h (sexpr-head s))]
    (or (= h verbose) (= h nano))))

(defun render-compound [(is-paren Bool) (items (List SExpr))] -> String
  :doc "Renders delimited list of SExpr items."
  (let [(open (if is-paren "(" "["))
        (close (if is-paren ")" "]"))
        (body (string-join (map (fn [x] (render-sexpr x)) items) " "))]
    (str open body close)))

(defun render-sexpr [(s SExpr)] -> String
  :doc "Renders an SExpr tree to string representation."
  (match s
    ((sexpr-atom v)     v)
    ((sexpr-list items) (render-compound true items))
    ((sexpr-vect items) (render-compound false items))))
