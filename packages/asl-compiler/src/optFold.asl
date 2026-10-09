(module asl-compiler/optFold
  :x [foldConstants foldArithmetic foldLogic foldBranches asInt asBool simplifyBoolean dceBlock evalComptimeConstant foldLetBindings substituteVar sexprEquals?]
  :i [(asl-parser/reader :a rd)])

fn asInt s: rd/SExpr -> (Option Int64)
  (mt s
    ((rd/sexprAtom a) (stringToInt64 a))
    (_ (none)))

fn asBool s: rd/SExpr -> (Option Bool)
  (mt s
    ((rd/sexprAtom a)
      (if (= a "true") (some true)
        (if (= a "false") (some false) (none))))
    (_ (none)))

fn isZero? s: rd/SExpr -> Bool
  (mt (asInt s)
    ((some i) (= i 0))
    ((none) false))

fn isOne? s: rd/SExpr -> Bool
  (mt (asInt s)
    ((some i) (= i 1))
    ((none) false))

fn sexprEquals? a: rd/SExpr b: rd/SExpr -> Bool
  (= (rd/renderSexpr a) (rd/renderSexpr b))

fn foldArithmetic op: Str a1: rd/SExpr a2: rd/SExpr -> (Option rd/SExpr)
  (mt (asInt a1)
    ((some i1)
      (mt (asInt a2)
        ((some i2)
          (if (= op "+") (some (rd/makeAtom (stringFromInt64 (+ i1 i2))))
            (if (= op "-") (some (rd/makeAtom (stringFromInt64 (- i1 i2))))
              (if (= op "*") (some (rd/makeAtom (stringFromInt64 (* i1 i2))))
                (if (and (= op "/") (!= i2 0)) (some (rd/makeAtom (stringFromInt64 (/ i1 i2))))
                  (none))))))
        ((none)
          (if (and (= op "+") (= i1 0)) (some a2)
            (if (and (= op "*") (= i1 0)) (some (rd/makeAtom "0"))
              (if (and (= op "*") (= i1 1)) (some a2)
                (none)))))))
    ((none)
      (mt (asInt a2)
        ((some i2)
          (if (and (= op "+") (= i2 0)) (some a1)
            (if (and (= op "-") (= i2 0)) (some a1)
              (if (and (= op "*") (= i2 0)) (some (rd/makeAtom "0"))
                (if (and (= op "*") (= i2 1)) (some a1)
                  (if (and (= op "/") (= i2 1)) (some a1)
                    (none)))))))
        ((none)
          (if (and (= op "-") (sexprEquals? a1 a2))
            (some (rd/makeAtom "0"))
            (if (and (= op "/") (sexprEquals? a1 a2))
              (some (rd/makeAtom "1"))
              (none)))))))

fn foldLogic op: Str a1: rd/SExpr a2: rd/SExpr -> (Option rd/SExpr)
  (mt (asBool a1)
    ((some b1)
      (mt (asBool a2)
        ((some b2)
          (if (= op "and") (some (rd/makeAtom (if (and b1 b2) "true" "false")))
            (if (= op "or") (some (rd/makeAtom (if (or b1 b2) "true" "false")))
              (none))))
        ((none)
          (if (= op "and")
            (if b1 (some a2) (some (rd/makeAtom "false")))
            (if (= op "or")
              (if b1 (some (rd/makeAtom "true")) (some a2))
              (none))))))
    ((none)
      (mt (asBool a2)
        ((some b2)
          (if (= op "and")
            (if b2 (some a1) (some (rd/makeAtom "false")))
            (if (= op "or")
              (if b2 (some (rd/makeAtom "true")) (some a1))
              (none))))
        ((none) (none)))))

fn foldBranches condExpr: rd/SExpr thenExpr: rd/SExpr elseExpr: rd/SExpr -> rd/SExpr
  (mt (asBool condExpr)
    ((some b) (if b thenExpr elseExpr))
    ((none) (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr))))

fn foldConstants expr: rd/SExpr -> rd/SExpr
  (mt expr
    ((rd/sexprAtom _) expr)
    ((rd/sexprVect items) (rd/makeVect (map (fn [(item rd/SExpr)] (foldConstants item)) items)))
    ((rd/sexprList items)
      (if (listEmpty? items) expr
        (let [(foldedItems (map (fn [(item rd/SExpr)] (foldConstants item)) items))
              (h (optionOr (listHead foldedItems) (rd/makeAtom "")))
              (rest (optionOr (listTail foldedItems) (list)))]
          (mt h
            ((rd/sexprAtom op)
              (cond
                ((or (or (= op "+") (= op "-")) (or (= op "*") (= op "/")))
                  (if (= (listLength rest) 2)
                    (let [(a1 (optionOr (listGet rest 0) (rd/makeAtom "")))
                          (a2 (optionOr (listGet rest 1) (rd/makeAtom "")))]
                      (mt (foldArithmetic op a1 a2)
                        ((some folded) folded)
                        ((none) (rd/makeList foldedItems))))
                    (rd/makeList foldedItems)))
                ((or (= op "and") (= op "or"))
                  (if (= (listLength rest) 2)
                    (let [(a1 (optionOr (listGet rest 0) (rd/makeAtom "")))
                          (a2 (optionOr (listGet rest 1) (rd/makeAtom "")))]
                      (mt (foldLogic op a1 a2)
                        ((some folded) folded)
                        ((none) (rd/makeList foldedItems))))
                    (rd/makeList foldedItems)))
                ((= op "not")
                  (if (= (listLength rest) 1)
                    (let [(a (optionOr (listGet rest 0) (rd/makeAtom "")))]
                      (mt (asBool a)
                        ((some b) (rd/makeAtom (if b "false" "true")))
                        ((none) (rd/makeList foldedItems))))
                    (rd/makeList foldedItems)))
                ((= op "if")
                  (if (>= (listLength rest) 2)
                    (let [(c (optionOr (listGet rest 0) (rd/makeAtom "")))
                          (t (optionOr (listGet rest 1) (rd/makeAtom "")))
                          (e (if (>= (listLength rest) 3) (optionOr (listGet rest 2) (rd/makeAtom "null")) (rd/makeAtom "null")))]
                      (foldBranches c t e))
                    (rd/makeList foldedItems)))
                (else (rd/makeList foldedItems))))
            (_ (rd/makeList foldedItems)))))))

fn isNotExpr? s: rd/SExpr -> Bool
  (and (rd/isList? s) (= (rd/sexprHead s) "not"))

fn getNotInner s: rd/SExpr -> rd/SExpr
  (let [(items (rd/sexprToList s))]
    (optionOr (listGet items 1) (rd/makeAtom "")))

fn simplifyBoolean expr: rd/SExpr -> rd/SExpr
  (let [(f (foldConstants expr))]
    (mt f
      ((rd/sexprAtom _) f)
      ((rd/sexprVect items) (rd/makeVect (map (fn [(item rd/SExpr)] (simplifyBoolean item)) items)))
      ((rd/sexprList items)
        (if (listEmpty? items)
          f
          (let [(head (rd/sexprHead f))]
            (cond
              ((= head "not")
                (let [(arg (simplifyBoolean (optionOr (listGet items 1) (rd/makeAtom ""))))]
                  (if (isNotExpr? arg)
                    (getNotInner arg)
                    (let [(argHead (rd/sexprHead arg))
                          (argItems (rd/sexprToList arg))]
                      (cond
                        ((and (= argHead "and") (= (listLength argItems) 3))
                          (let [(p (optionOr (listGet argItems 1) (rd/makeAtom "")))
                                (q (optionOr (listGet argItems 2) (rd/makeAtom "")))]
                            (rd/makeList (list (rd/makeAtom "or")
                                               (simplifyBoolean (rd/makeList (list (rd/makeAtom "not") p)))
                                               (simplifyBoolean (rd/makeList (list (rd/makeAtom "not") q)))))))
                        ((and (= argHead "or") (= (listLength argItems) 3))
                          (let [(p (optionOr (listGet argItems 1) (rd/makeAtom "")))
                                (q (optionOr (listGet argItems 2) (rd/makeAtom "")))]
                            (rd/makeList (list (rd/makeAtom "and")
                                               (simplifyBoolean (rd/makeList (list (rd/makeAtom "not") p)))
                                               (simplifyBoolean (rd/makeList (list (rd/makeAtom "not") q)))))))
                        (else (foldConstants (rd/makeList (list (rd/makeAtom "not") arg)))))))))
              ((= head "and")
                (if (= (listLength items) 3)
                  (let [(p (simplifyBoolean (optionOr (listGet items 1) (rd/makeAtom ""))))
                        (q (simplifyBoolean (optionOr (listGet items 2) (rd/makeAtom ""))))]
                    (cond
                      ((sexprEquals? p q) p)
                      ((and (isNotExpr? q) (sexprEquals? p (getNotInner q))) (rd/makeAtom "false"))
                      ((and (isNotExpr? p) (sexprEquals? q (getNotInner p))) (rd/makeAtom "false"))
                      (else (foldConstants (rd/makeList (list (rd/makeAtom "and") p q))))))
                  (rd/makeList (map (fn [(item rd/SExpr)] (simplifyBoolean item)) items))))
              ((= head "or")
                (if (= (listLength items) 3)
                  (let [(p (simplifyBoolean (optionOr (listGet items 1) (rd/makeAtom ""))))
                        (q (simplifyBoolean (optionOr (listGet items 2) (rd/makeAtom ""))))]
                    (cond
                      ((sexprEquals? p q) p)
                      ((and (isNotExpr? q) (sexprEquals? p (getNotInner q))) (rd/makeAtom "true"))
                      ((and (isNotExpr? p) (sexprEquals? q (getNotInner p))) (rd/makeAtom "true"))
                      (else (foldConstants (rd/makeList (list (rd/makeAtom "or") p q))))))
                  (rd/makeList (map (fn [(item rd/SExpr)] (simplifyBoolean item)) items))))
              (else (rd/makeList (map (fn [(item rd/SExpr)] (simplifyBoolean item)) items)))))))))

fn isPureLiteral? s: rd/SExpr -> Bool
  (mt s
    ((rd/sexprAtom a)
      (or (some? (stringToInt64 a))
          (or (= a "true")
              (or (= a "false")
                  (or (= a "null")
                      (and (stringStartsWith? a "\"") (stringEndsWith? a "\"")))))))
    (_ false))

fn dceBlock expr: rd/SExpr -> rd/SExpr
  (mt expr
    ((rd/sexprAtom _) expr)
    ((rd/sexprVect items) (rd/makeVect (map (fn [(item rd/SExpr)] (dceBlock item)) items)))
    ((rd/sexprList items)
      (if (listEmpty? items)
        expr
        (let [(head (rd/sexprHead expr))]
          (cond
            ((= head "do")
              (let [(stmts (optionOr (listTail items) (list)))]
                (if (listEmpty? stmts)
                  (rd/makeAtom "null")
                  (if (= (listLength stmts) 1)
                    (dceBlock (optionOr (listHead stmts) (rd/makeAtom "null")))
                    (let [(lastStmt (optionOr (listGet stmts (- (listLength stmts) 1)) (rd/makeAtom "null")))
                          (priorStmts (optionOr (listSlice stmts 0 (- (listLength stmts) 1)) (list)))
                          (filteredPrior (filter (fn [(s rd/SExpr)] -> Bool (not (isPureLiteral? s))) priorStmts))
                          (newStmts (listAppend (map (fn [(s rd/SExpr)] (dceBlock s)) filteredPrior) (list (dceBlock lastStmt))))]
                      (if (= (listLength newStmts) 1)
                        (optionOr (listHead newStmts) (rd/makeAtom "null"))
                        (rd/makeList (cons (rd/makeAtom "do") newStmts))))))))
            ((= head "if")
              (let [(c (dceBlock (optionOr (listGet items 1) (rd/makeAtom ""))))
                    (t (dceBlock (optionOr (listGet items 2) (rd/makeAtom ""))))
                    (e (dceBlock (if (>= (listLength items) 4) (optionOr (listGet items 3) (rd/makeAtom "null")) (rd/makeAtom "null"))))
                    (cFold (foldConstants c))]
                (mt (asBool cFold)
                  ((some b) (if b t e))
                  ((none) (rd/makeList (list (rd/makeAtom "if") cFold t e))))))
            ((= head "let")
              (let [(bindingsNode (optionOr (listGet items 1) (rd/makeVect (list))))
                    (body (if (>= (listLength items) 3) (optionOr (listGet items 2) (rd/makeAtom "null")) (rd/makeAtom "null")))
                    (bindList (rd/sexprToList bindingsNode))]
                (if (listEmpty? bindList)
                  (dceBlock body)
                  (rd/makeList (list (rd/makeAtom "let") bindingsNode (dceBlock body))))))
            (else (rd/makeList (map (fn [(item rd/SExpr)] (dceBlock item)) items))))))))

fn evalComptimeConstant expr: rd/SExpr -> (Option rd/SExpr)
  (let [(folded (foldConstants expr))]
    (if (or (isPureLiteral? folded) (some? (asInt folded)))
      (some folded)
      (none)))

fn substituteVar expr: rd/SExpr varName: Str replacement: rd/SExpr -> rd/SExpr
  (mt expr
    ((rd/sexprAtom a)
      (if (= a varName)
        replacement
        expr))
    ((rd/sexprVect items)
      (rd/makeVect (map (fn [(it rd/SExpr)] (substituteVar it varName replacement)) items)))
    ((rd/sexprList items)
      (if (listEmpty? items)
        expr
        (let [(h (rd/sexprHead expr))]
          (if (= h "let")
            (let [(bindNode (optionOr (listGet items 1) (rd/makeVect (list))))
                  (body (if (>= (listLength items) 3) (optionOr (listGet items 2) (rd/makeAtom "null")) (rd/makeAtom "null")))
                  (bindList (rd/sexprToList bindNode))
                  (shadowed (fold (fn [(acc Bool) (b rd/SExpr)]
                                    (let [(bItems (rd/sexprToList b))
                                          (vName (if (listEmpty? bItems) "" (rd/sexprHead b)))]
                                      (or acc (= vName varName))))
                                  false
                                  bindList))]
              (if shadowed
                expr
                (let [(subBindings (rd/makeVect (map (fn [(b rd/SExpr)] (substituteVar b varName replacement)) bindList)))
                      (subBody (substituteVar body varName replacement))]
                  (rd/makeList (list (rd/makeAtom "let") subBindings subBody)))))
            (rd/makeList (map (fn [(it rd/SExpr)] (substituteVar it varName replacement)) items)))))))

fn foldLetBindings expr: rd/SExpr -> rd/SExpr
  (let [(folded (foldConstants expr))]
    (mt folded
      ((rd/sexprList items)
        (if (listEmpty? items)
          folded
          (let [(h (rd/sexprHead folded))]
            (if (= h "let")
              (let [(bindingsNode (optionOr (listGet items 1) (rd/makeVect (list))))
                    (body (if (>= (listLength items) 3) (optionOr (listGet items 2) (rd/makeAtom "null")) (rd/makeAtom "null")))
                    (bindList (rd/sexprToList bindingsNode))
                    (foldedBody (fold (fn [(bBody rd/SExpr) (binding rd/SExpr)]
                                        (let [(bItems (rd/sexprToList binding))]
                                          (if (< (listLength bItems) 2)
                                            bBody
                                            (let [(varName (rd/sexprHead binding))
                                                  (valExpr (optionOr (listGet bItems 1) (rd/makeAtom "")))
                                                  (comptimeVal (evalComptimeConstant valExpr))]
                                              (mt comptimeVal
                                                ((some constVal)
                                                  (substituteVar bBody varName constVal))
                                                ((none)
                                                  bBody))))))
                                      body
                                      bindList))]
                (foldConstants foldedBody))
              folded))))
      (_ folded)))

