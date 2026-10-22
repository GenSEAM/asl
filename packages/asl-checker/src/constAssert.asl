(module asl-checker/constAssert
  :x [constantAssertDiags foldsToConstant? hostSubjectFns]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

fn atomOf e: rd/SExpr -> (Option String)
  (match e ((rd/sexprAtom v) (some v)) (_ (none)))

fn kidsOf e: rd/SExpr -> (List rd/SExpr)
  (match e ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) ((rd/sexprAtom _) (list)))

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
  (match (atomOf e) ((some v) (literalAtom? v)) ((none) false))

fn foldingOps -> (List String)
  (list "=" "!=" "<" ">" "<=" ">=" "+" "-" "*" "/" "mod" "not" "and" "or")

fn foldingOp? h: String env: (Map String Bool) funs: (List String) -> Bool
  (and (listContains? (foldingOps) h) (and (not (mapHas? env h)) (not (listContains? funs h))))

fn foldsToConstant? e: rd/SExpr env: (Map String Bool) funs: (List String) -> Bool
  (match e
    ((rd/sexprAtom v) (or (literalAtom? v) (= (mapGet env v) (some true))))
    ((rd/sexprVect xs) (listAll? (fn [(x rd/SExpr)] -> Bool (foldsToConstant? x env funs)) xs))
    ((rd/sexprList xs)
      (match (match (listHead xs) ((some h) (atomOf h)) ((none) (none)))
        ((some h) (and (>= (listLength xs) 2)
                       (and (foldingOp? h env funs)
                            (listAll? (fn [(x rd/SExpr)] -> Bool (foldsToConstant? x env funs)) (dropN xs 1)))))
        ((none) false))))

fn bindAll env: (Map String Bool) names: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapSet acc n false)) env names)

fn vectItems e: rd/SExpr -> (List rd/SExpr)
  (match e
    ((rd/sexprList xs) (if (= (match (listHead xs) ((some h) (atomOf h)) ((none) (none))) (some "list")) (dropN xs 1) xs))
    (_ (kidsOf e)))

fn paramNames e: rd/SExpr -> (List String)
  (fold (fn [(acc (List String)) (q rd/SExpr)] -> (List String)
          (match (atomOf q)
            ((some v) (cons v acc))
            ((none) (match (match (listHead (kidsOf q)) ((some h) (atomOf h)) ((none) (none))) ((some v) (cons v acc)) ((none) acc)))))
        (list) (vectItems e))

fn patternNames pat: rd/SExpr -> (List String)
  (match pat
    ((rd/sexprAtom v) (list v))
    (_ (fold (fn [(acc (List String)) (x rd/SExpr)] -> (List String) (listAppend (patternNames x) acc)) (list) (dropN (kidsOf pat) 1))))

; (:m :ref CHECKER-R1GAPS :do "checkCond used to return bare messages, which forced constantAssertDiags to stamp every hit with the whole function's position; it now pairs each message with the exact source spelling of the offending condition (the bare true/false/literal-variable atom, or the full rendered text of a compound condition via rd/renderSexpr, needed to disambiguate repeated operators like two separate (= ...) conditions in the same function) so placeDiags can resolve the real line:col via a/findTokenPos instead of defunPos")
fn checkCond isAssert: Bool cond: rd/SExpr env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (let [(name (if isAssert "assert" "refute"))
        (fails (if isAssert "false" "true"))]
    (match (atomOf cond)
      ((some v) (cond
                  ((= v fails) (list))
                  ((or (= v "true") (= v "false")) (list (pair (str name " " v " can never fail; test a computed value (D152)") v)))
                  ((literalAtom? v) (list))
                  ((foldsToConstant? cond env funs) (list (pair (str name " condition folds to a constant; test a computed value (D152)") v)))
                  (else (list))))
      ((none) (if (foldsToConstant? cond env funs) (list (pair (str name " condition folds to a constant; test a computed value (D152)") (rd/renderSexpr cond))) (list)))))

fn walkAll xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (x rd/SExpr)] -> (List (Pair String String)) (listAppend acc (walk x env funs))) (list) xs)

fn letStep acc: (Pair (List (Pair String String)) (Map String Bool)) nameE: rd/SExpr valE: (Option rd/SExpr) funs: (List String) -> (Pair (List (Pair String String)) (Map String Bool))
  (let [(env (pairSecond acc))
        (found (match valE ((some v) (walk v env funs)) ((none) (list))))
        (lit (match valE ((some v) (literal? v)) ((none) false)))
        (env2 (match (atomOf nameE) ((some n) (mapSet env n lit)) ((none) env)))]
    (pair (listAppend (pairFirst acc) found) env2))

fn walkLet xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (let [(bs (match (listGet xs 1) ((some b) (vectItems b)) ((none) (list))))
        (pairs (match (listHead bs) ((some b) (rd/isList? b)) ((none) false)))
        (bound (if pairs
                 (fold (fn [(acc (Pair (List (Pair String String)) (Map String Bool))) (b rd/SExpr)] -> (Pair (List (Pair String String)) (Map String Bool))
                         (let [(parts (kidsOf b))] (letStep acc (optionOr (listHead parts) b) (if (>= (listLength parts) 2) (listLast parts) (none)) funs)))
                       (pair (list) env) bs)
                 (flatLet (pair (list) env) bs funs)))]
    (listAppend (pairFirst bound) (walkAll (dropN xs 2) (pairSecond bound) funs)))

fn flatLet acc: (Pair (List (Pair String String)) (Map String Bool)) bs: (List rd/SExpr) funs: (List String) -> (Pair (List (Pair String String)) (Map String Bool))
  (match (listHead bs)
    ((none) acc)
    ((some nameE) (flatLet (letStep acc nameE (listGet bs 1) funs) (dropN bs 2) funs)))

fn walkArm arm: rd/SExpr env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (match (listHead (kidsOf arm))
    ((none) (list))
    ((some pat) (walkAll (dropN (kidsOf arm) 1) (bindAll env (patternNames pat)) funs)))

fn walkHeaded h: String xs: (List rd/SExpr) env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (cond
    ((and (or (= h "assert") (= h "refute")) (not (mapHas? env h)))
      (listAppend (match (listGet xs 1) ((some c) (checkCond (= h "assert") c env funs)) ((none) (list))) (walkAll (dropN xs 1) env funs)))
    ((= h "let") (walkLet xs env funs))
    ((or (= h "fn") (= h "lambda")) (walkAll (dropN xs 2) (bindAll env (match (listGet xs 1) ((some p) (paramNames p)) ((none) (list)))) funs))
    ((= h "match")
      (listAppend (match (listGet xs 1) ((some s) (walk s env funs)) ((none) (list)))
                  (fold (fn [(acc (List (Pair String String))) (arm rd/SExpr)] -> (List (Pair String String)) (listAppend acc (walkArm arm env funs))) (list) (dropN xs 2))))
    (else (walkAll (dropN xs 1) env funs)))

fn walk e: rd/SExpr env: (Map String Bool) funs: (List String) -> (List (Pair String String))
  (match e
    ((rd/sexprAtom _) (list))
    ((rd/sexprVect xs) (walkAll xs env funs))
    ((rd/sexprList xs) (match (match (listHead xs) ((some h) (atomOf h)) ((none) (none)))
                         ((some h) (walkHeaded h xs env funs))
                         ((none) (walkAll xs env funs)))))

fn headerName line: String -> (Option String)
  (let [(words (filter (fn [(w String)] -> Bool (and (not (stringEmpty? w)) (and (!= w "!") (and (!= w "tailrec") (!= w ":tailrec"))))) (stringSplit line " ")))]
    (if (= (listHead words) (some "fn")) (listGet words 1) (none)))

fn hostSubjectFns src: String -> (List String)
  (pairSecond (fold (fn [(acc (Pair String (List String))) (l String)] -> (Pair String (List String))
                      (let [(tagged (stringContains? (pairFirst acc) "(:m :tags (hostSubject))"))
                            (named (if (and tagged (stringStartsWith? l "fn ")) (headerName l) (none)))]
                        (pair l (match named ((some n) (cons n (pairSecond acc))) ((none) (pairSecond acc))))))
                    (pair "" (list)) (stringLines src)))

fn moduleFuns forms: (List a/TopForm) -> (List String)
  (fold (fn [(acc (List String)) (f a/TopForm)] -> (List String) (match f ((a/topDefun d) (cons d.name acc)) (_ acc))) (list) forms)

fn mkDiag path: String pos: (Pair Int64 Int64) msg: String -> ty/Diagnostic
  (ty/Diagnostic :code "ERR_CONSTANT_ASSERT" :message msg :msg msg :line (pairFirst pos) :col (pairSecond pos) :path path)

fn defunPos d: a/DefunNode -> (Pair Int64 Int64)
  (match (listHead d.bodyPos) ((some p) (pair p.line p.col)) ((none) (pair 1 1)))

; (:m :ref CHECKER-R1GAPS :do "placeDiags resolves each (message, needle) pair to the needle's real position via a/findTokenPos, starting the search at a floor (the function's or top-level expression's own start) and advancing the floor past every match in order, so two identical needles in the same function (two bare 'sealed' references, for example) still land on their own distinct occurrences rather than both collapsing onto the first")
fn tailrec placeDiags path: String src: String floorLine: Int64 floorCol: Int64 ms: (List (Pair String String)) acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (match (listHead ms)
    ((none) (listReverse acc))
    ((some mn)
      (let [(pos (a/findTokenPos src floorLine floorCol (pairSecond mn)))]
        (placeDiags path src (pairFirst pos) (+ (pairSecond pos) 1) (optionOr (listTail ms) (list)) (cons (mkDiag path pos (pairFirst mn)) acc)))))

fn constantAssertDiags forms: (List a/TopForm) src: String path: String -> (List ty/Diagnostic)
  (let [(funs (moduleFuns forms))
        (exempt (hostSubjectFns src))]
    (fold (fn [(acc (List ty/Diagnostic)) (f a/TopForm)] -> (List ty/Diagnostic)
            (match f
              ((a/topDefun d)
                (if (listContains? exempt d.name)
                  acc
                  (let [(env (bindAll (mapEmpty) (map (fn [(p a/Param)] -> String p.name) d.params)))
                        (fp (defunPos d))]
                    (listAppend acc (placeDiags path src (pairFirst fp) (pairSecond fp) (walkAll d.body env funs) (list))))))
              ((a/topExpr p) (listAppend acc (placeDiags path src p.line p.col (walk p.expr (mapEmpty) funs) (list))))
              (_ acc)))
          (list) forms))
