(module asl-checker/constAssert
  :x [constantAssertDiags foldsToConstant? hostSubjectFns]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

fn atomOf e: rd/SExpr -> (Option String)
  (mt e ((rd/sexprAtom v) (some v)) (_ (none)))

fn kidsOf e: rd/SExpr -> (List rd/SExpr)
  (mt e ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) ((rd/sexprAtom _) (list)))

fn dropN xs: (List rd/SExpr) n: Int64 -> (List rd/SExpr)
  (optionOr (listSlice xs n (listLength xs)) (list))

fn literalAtom? v: String -> Bool
  (or (or (= v "true") (= v "false"))
      (or (stringStartsWith? v "\"")
          (or (and (stringStartsWith? v ":") (> (stringLength v) 1))
              (and (numberStart? v) (or (some? (stringToInt64 v)) (some? (stringToFloat64 v)))))))

fn digit? c: String -> Bool
  (and (= (stringLength c) 1) (stringContains? "0123456789" c))

fn numberStart? v: String -> Bool
  (let [(c0 (optionOr (stringSlice v 0 1) ""))
        (c1 (optionOr (stringSlice v 1 2) ""))]
    (or (digit? c0) (and (or (= c0 "-") (= c0 "+")) (digit? c1))))

fn literal? e: rd/SExpr -> Bool
  (mt (atomOf e) ((some v) (literalAtom? v)) ((none) false))

fn foldingOps -> (List String)
  (list "=" "!=" "<" ">" "<=" ">=" "+" "-" "*" "/" "mod" "not" "and" "or")

fn foldingOp? h: String env: (Map String Bool) funs: (List String) -> Bool
  (and (listContains? (foldingOps) h) (and (not (mapHas? env h)) (not (listContains? funs h))))

fn foldsToConstant? e: rd/SExpr env: (Map String Bool) funs: (List String) -> Bool
  (mt e
    ((rd/sexprAtom v) (or (literalAtom? v) (= (mapGet env v) (some true))))
    ((rd/sexprVect xs) (listAll? (fn [(x rd/SExpr)] -> Bool (foldsToConstant? x env funs)) xs))
    ((rd/sexprList xs)
      (mt (mt (listHead xs) ((some h) (atomOf h)) ((none) (none)))
        ((some h) (and (>= (listLength xs) 2)
                       (and (foldingOp? h env funs)
                            (listAll? (fn [(x rd/SExpr)] -> Bool (foldsToConstant? x env funs)) (dropN xs 1)))))
        ((none) false))))

fn bindAll env: (Map String Bool) names: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapSet acc n false)) env names)

fn vectItems e: rd/SExpr -> (List rd/SExpr)
  (mt e
    ((rd/sexprList xs) (if (= (mt (listHead xs) ((some h) (atomOf h)) ((none) (none))) (some "list")) (dropN xs 1) xs))
    (_ (kidsOf e)))

fn paramNames e: rd/SExpr -> (List String)
  (fold (fn [(acc (List String)) (q rd/SExpr)] -> (List String)
          (mt (atomOf q)
            ((some v) (cons v acc))
            ((none) (mt (mt (listHead (kidsOf q)) ((some h) (atomOf h)) ((none) (none))) ((some v) (cons v acc)) ((none) acc)))))
        (list) (vectItems e))

fn patternNames pat: rd/SExpr -> (List String)
  (mt pat
    ((rd/sexprAtom v) (list v))
    (_ (fold (fn [(acc (List String)) (x rd/SExpr)] -> (List String) (listAppend (patternNames x) acc)) (list) (dropN (kidsOf pat) 1))))

fn checkCond isAssert: Bool cond: rd/SExpr env: (Map String Bool) funs: (List String) -> (List String)
  (let [(name (if isAssert "assert" "refute"))
        (fails (if isAssert "false" "true"))]
    (mt (atomOf cond)
      ((some v) (cond
                  ((= v fails) (list))
                  ((or (= v "true") (= v "false")) (list (str name " " v " can never fail; test a computed value (D152)")))
                  ((literalAtom? v) (list))
                  ((foldsToConstant? cond env funs) (list (str name " condition folds to a constant; test a computed value (D152)")))
                  (else (list))))
      ((none) (if (foldsToConstant? cond env funs) (list (str name " condition folds to a constant; test a computed value (D152)")) (list)))))

fn walkAll xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x rd/SExpr)] -> (List String) (listAppend acc (walk x env funs))) (list) xs)

fn letStep acc: (Pair (List String) (Map String Bool)) nameE: rd/SExpr valE: (Option rd/SExpr) funs: (List String) -> (Pair (List String) (Map String Bool))
  (let [(env (pairSecond acc))
        (found (mt valE ((some v) (walk v env funs)) ((none) (list))))
        (lit (mt valE ((some v) (literal? v)) ((none) false)))
        (env2 (mt (atomOf nameE) ((some n) (mapSet env n lit)) ((none) env)))]
    (pair (listAppend (pairFirst acc) found) env2))

fn walkLet xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List String)
  (let [(bs (mt (listGet xs 1) ((some b) (vectItems b)) ((none) (list))))
        (pairs (mt (listHead bs) ((some b) (rd/isList? b)) ((none) false)))
        (bound (if pairs
                 (fold (fn [(acc (Pair (List String) (Map String Bool))) (b rd/SExpr)] -> (Pair (List String) (Map String Bool))
                         (let [(parts (kidsOf b))] (letStep acc (optionOr (listHead parts) b) (if (>= (listLength parts) 2) (listLast parts) (none)) funs)))
                       (pair (list) env) bs)
                 (flatLet (pair (list) env) bs funs)))]
    (listAppend (pairFirst bound) (walkAll (dropN xs 2) (pairSecond bound) funs)))

fn flatLet acc: (Pair (List String) (Map String Bool)) bs: (List rd/SExpr) funs: (List String) -> (Pair (List String) (Map String Bool))
  (mt (listHead bs)
    ((none) acc)
    ((some nameE) (flatLet (letStep acc nameE (listGet bs 1) funs) (dropN bs 2) funs)))

fn walkArm arm: rd/SExpr env: (Map String Bool) funs: (List String) -> (List String)
  (mt (listHead (kidsOf arm))
    ((none) (list))
    ((some pat) (walkAll (dropN (kidsOf arm) 1) (bindAll env (patternNames pat)) funs)))

fn walkHeaded h: String xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List String)
  (cond
    ((and (or (= h "assert") (= h "refute")) (not (mapHas? env h)))
      (listAppend (mt (listGet xs 1) ((some c) (checkCond (= h "assert") c env funs)) ((none) (list))) (walkAll (dropN xs 1) env funs)))
    ((= h "let") (walkLet xs env funs))
    ((or (= h "fn") (= h "lambda")) (walkAll (dropN xs 2) (bindAll env (mt (listGet xs 1) ((some p) (paramNames p)) ((none) (list)))) funs))
    ((or (= h "mt") (= h "match"))
      (listAppend (mt (listGet xs 1) ((some s) (walk s env funs)) ((none) (list)))
                  (fold (fn [(acc (List String)) (arm rd/SExpr)] -> (List String) (listAppend acc (walkArm arm env funs))) (list) (dropN xs 2))))
    (else (walkAll (dropN xs 1) env funs)))

fn walk e: rd/SExpr env: (Map String Bool) funs: (List String) -> (List String)
  (mt e
    ((rd/sexprAtom _) (list))
    ((rd/sexprVect xs) (walkAll xs env funs))
    ((rd/sexprList xs) (mt (mt (listHead xs) ((some h) (atomOf h)) ((none) (none)))
                         ((some h) (walkHeaded h xs env funs))
                         ((none) (walkAll xs env funs)))))

fn headerName line: String -> (Option String)
  (let [(words (filter (fn [(w String)] -> Bool (and (not (stringEmpty? w)) (and (!= w "!") (and (!= w "tailrec") (!= w ":tailrec"))))) (stringSplit line " ")))]
    (if (= (listHead words) (some "fn")) (listGet words 1) (none)))

fn hostSubjectFns src: String -> (List String)
  (pairSecond (fold (fn [(acc (Pair String (List String))) (l String)] -> (Pair String (List String))
                      (let [(tagged (stringContains? (pairFirst acc) "(:m :tags (hostSubject))"))
                            (named (if (and tagged (stringStartsWith? l "fn ")) (headerName l) (none)))]
                        (pair l (mt named ((some n) (cons n (pairSecond acc))) ((none) (pairSecond acc))))))
                    (pair "" (list)) (stringLines src)))

fn moduleFuns forms: (List a/TopForm) -> (List String)
  (fold (fn [(acc (List String)) (f a/TopForm)] -> (List String) (mt f ((a/topDefun d) (cons d.name acc)) (_ acc))) (list) forms)

fn mkDiag path: String pos: (Pair Int64 Int64) msg: String -> ty/Diagnostic
  (ty/Diagnostic :code "ERR_CONSTANT_ASSERT" :message msg :msg msg :line (pairFirst pos) :col (pairSecond pos) :path path)

fn defunPos d: a/DefunNode -> (Pair Int64 Int64)
  (mt (listHead d.bodyPos) ((some p) (pair p.line p.col)) ((none) (pair 1 1)))

fn constantAssertDiags forms: (List a/TopForm) src: String path: String -> (List ty/Diagnostic)
  (let [(funs (moduleFuns forms))
        (exempt (hostSubjectFns src))]
    (fold (fn [(acc (List ty/Diagnostic)) (f a/TopForm)] -> (List ty/Diagnostic)
            (mt f
              ((a/topDefun d)
                (if (listContains? exempt d.name)
                  acc
                  (let [(env (bindAll (mapEmpty) (map (fn [(p a/Param)] -> String p.name) d.params)))]
                    (listAppend acc (map (fn [(m String)] -> ty/Diagnostic (mkDiag path (defunPos d) m)) (walkAll d.body env funs))))))
              ((a/topExpr p) (listAppend acc (map (fn [(m String)] -> ty/Diagnostic (mkDiag path (pair p.line p.col) m)) (walk p.expr (mapEmpty) funs))))
              (_ acc)))
          (list) forms))
