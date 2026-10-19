(module asl-checker/tailPos
  :x [tailrecNames notTailCount notTailDiags]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

fn headerWords line: String -> (List String)
  (let [(body (if (stringStartsWith? line "(") (optionOr (stringSlice line 1 (stringLength line)) "") line))]
    (filter (fn [(w String)] -> Bool (and (not (stringEmpty? w)) (!= w "!"))) (stringSplit body " ")))

fn tailrecHeader words: (List String) -> (Option String)
  (if (and (or (= (listGet words 0) (some "fn")) (= (listGet words 0) (some "defun")))
           (or (= (listGet words 1) (some "tailrec")) (= (listGet words 1) (some ":tailrec"))))
    (listGet words 2)
    (none))

fn tailrecNames src: String -> (List String)
  (fold (fn [(acc (List String)) (l String)] -> (List String)
          (if (or (stringStartsWith? l "fn ") (or (stringStartsWith? l "(fn ") (stringStartsWith? l "(defun ")))
            (mt (tailrecHeader (headerWords l)) ((some n) (cons n acc)) ((none) acc))
            acc))
        (list) (stringLines src))

fn itemsOf e: rd/SExpr -> (List rd/SExpr)
  (mt e ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) ((rd/sexprAtom _) (list)))

fn vectItems e: rd/SExpr -> (List rd/SExpr)
  (mt e
    ((rd/sexprList xs) (if (= (mt (listHead xs) ((some h) (atomText h)) ((none) (none))) (some "list")) (dropN xs 1) xs))
    (_ (itemsOf e)))

fn atomText e: rd/SExpr -> (Option String)
  (mt e ((rd/sexprAtom v) (some v)) (_ (none)))

fn dropN xs: (List rd/SExpr) n: Int64 -> (List rd/SExpr)
  (optionOr (listSlice xs n (listLength xs)) (list))

fn named? e: rd/SExpr name: String -> Bool
  (= (atomText e) (some name))

fn sumOf xs: (List Int64) -> Int64
  (fold (fn [(acc Int64) (x Int64)] -> Int64 (+ acc x)) 0 xs)

fn walkAll name: String ctors: (List String) shadowed: Bool xs: (List rd/SExpr) -> Int64
  (sumOf (map (fn [(x rd/SExpr)] -> Int64 (walk name ctors shadowed false x)) xs))

fn walkSeq name: String ctors: (List String) shadowed: Bool tail: Bool xs: (List rd/SExpr) -> Int64
  (let [(last (- (listLength xs) 1))]
    (sumOf (map (fn [(p (Pair Int64 rd/SExpr))] -> Int64 (walk name ctors shadowed (and tail (= (pairFirst p) last)) (pairSecond p))) (enumerate xs))))

fn walkAt name: String ctors: (List String) shadowed: Bool tail: Bool xs: (List rd/SExpr) i: Int64 -> Int64
  (mt (listGet xs i) ((some x) (walk name ctors shadowed tail x)) ((none) 0))

fn patternShadows? name: String ctors: (List String) pat: rd/SExpr -> Bool
  (mt pat
    ((rd/sexprAtom v) (and (= v name) (not (listContains? ctors v))))
    ((rd/sexprList xs) (listAny? (fn [(x rd/SExpr)] -> Bool (named? x name)) (dropN xs 1)))
    ((rd/sexprVect _) false))

fn walkCond name: String ctors: (List String) shadowed: Bool tail: Bool clause: rd/SExpr -> Int64
  (mt clause
    ((rd/sexprList xs) (if (listEmpty? xs) 0
                         (+ (if (named? (optionOr (listHead xs) (rd/makeAtom "")) "else") 0 (walkAt name ctors shadowed false xs 0))
                            (walkSeq name ctors shadowed tail (dropN xs 1)))))
    (_ 0))

fn walkArm name: String ctors: (List String) shadowed: Bool tail: Bool arm: rd/SExpr -> Int64
  (mt arm
    ((rd/sexprList xs) (mt (listHead xs)
                         ((none) 0)
                         ((some pat) (walkSeq name ctors (or shadowed (patternShadows? name ctors pat)) tail (dropN xs 1)))))
    (_ 0))

fn bindingStep name: String ctors: (List String) acc: (Pair Int64 Bool) nameE: rd/SExpr valE: (Option rd/SExpr) -> (Pair Int64 Bool)
  (let [(n (mt valE ((some v) (walk name ctors (pairSecond acc) false v)) ((none) 0)))]
    (pair (+ (pairFirst acc) n) (or (pairSecond acc) (named? nameE name))))

fn walkPairBindings name: String ctors: (List String) acc: (Pair Int64 Bool) bs: (List rd/SExpr) -> (Pair Int64 Bool)
  (fold (fn [(a (Pair Int64 Bool)) (b rd/SExpr)] -> (Pair Int64 Bool)
          (let [(parts (itemsOf b))]
            (bindingStep name ctors a (optionOr (listHead parts) b) (if (>= (listLength parts) 2) (listLast parts) (none)))))
        acc bs)

fn walkFlatBindings name: String ctors: (List String) acc: (Pair Int64 Bool) bs: (List rd/SExpr) -> (Pair Int64 Bool)
  (mt (listHead bs)
    ((none) acc)
    ((some nameE) (walkFlatBindings name ctors (bindingStep name ctors acc nameE (listGet bs 1)) (dropN bs 2))))

fn walkLet name: String ctors: (List String) shadowed: Bool tail: Bool xs: (List rd/SExpr) -> Int64
  (let [(bs (mt (listGet xs 1) ((some b) (vectItems b)) ((none) (list))))
        (pairs (mt (listHead bs) ((some b) (rd/isList? b)) ((none) false)))
        (start (pair 0 shadowed))
        (bound (if pairs (walkPairBindings name ctors start bs) (walkFlatBindings name ctors start bs)))]
    (+ (pairFirst bound) (walkSeq name ctors (pairSecond bound) tail (dropN xs 2))))

fn paramShadows? name: String params: rd/SExpr -> Bool
  (mt params
    ((rd/sexprAtom _) false)
    (_ (listAny? (fn [(q rd/SExpr)] -> Bool (or (named? q name) (mt q ((rd/sexprList ys) (mt (listHead ys) ((some y) (named? y name)) ((none) false))) (_ false))))
                 (vectItems params))))

fn walkHeaded name: String ctors: (List String) shadowed: Bool tail: Bool h: String xs: (List rd/SExpr) -> Int64
  (cond
    ((= h "if") (+ (walkAt name ctors shadowed false xs 1) (+ (walkAt name ctors shadowed tail xs 2) (walkAt name ctors shadowed tail xs 3))))
    ((or (= h "when") (= h "unless")) (+ (walkAt name ctors shadowed false xs 1) (walkSeq name ctors shadowed tail (dropN xs 2))))
    ((= h "cond") (sumOf (map (fn [(c rd/SExpr)] -> Int64 (walkCond name ctors shadowed tail c)) (dropN xs 1))))
    ((or (= h "do") (= h "begin")) (walkSeq name ctors shadowed tail (dropN xs 1)))
    ((= h "let") (walkLet name ctors shadowed tail xs))
    ((or (= h "mt") (= h "match")) (+ (walkAt name ctors shadowed false xs 1) (sumOf (map (fn [(arm rd/SExpr)] -> Int64 (walkArm name ctors shadowed tail arm)) (dropN xs 2)))))
    ((or (= h "fn") (= h "lambda")) (walkAll name ctors (or shadowed (mt (listGet xs 1) ((some p) (paramShadows? name p)) ((none) false))) (dropN xs 2)))
    ((or (= h "and") (= h "or")) (walkAll name ctors shadowed (dropN xs 1)))
    ((and (= h name) (not shadowed)) (+ (if tail 0 1) (walkAll name ctors shadowed (dropN xs 1))))
    (else (walkAll name ctors shadowed (dropN xs 1))))

fn walk name: String ctors: (List String) shadowed: Bool tail: Bool e: rd/SExpr -> Int64
  (mt e
    ((rd/sexprAtom _) 0)
    ((rd/sexprVect xs) (walkAll name ctors shadowed xs))
    ((rd/sexprList xs) (mt (mt (listHead xs) ((some x) (atomText x)) ((none) (none)))
                         ((some h) (walkHeaded name ctors shadowed tail h xs))
                         ((none) (walkAll name ctors shadowed xs)))))

fn notTailCount d: a/DefunNode ctors: (List String) -> Int64
  (walkSeq d.name ctors (listAny? (fn [(p a/Param)] -> Bool (= p.name d.name)) d.params) true d.body)

fn moduleCtors forms: (List a/TopForm) -> (List String)
  (fold (fn [(acc (List String)) (f a/TopForm)] -> (List String)
          (mt f ((a/topEnum e) (listAppend (map (fn [(c a/EnumCase)] -> String c.name) e.cases) acc)) (_ acc)))
        (list "some" "none" "ok" "err" "true" "false") forms)

fn bodyPos d: a/DefunNode -> (Pair Int64 Int64)
  (mt (listHead d.bodyPos) ((some p) (pair p.line p.col)) ((none) (pair 1 1)))

fn notTailDiags forms: (List a/TopForm) src: String path: String -> (List ty/Diagnostic)
  (let [(names (tailrecNames src))
        (ctors (moduleCtors forms))]
    (if (listEmpty? names)
      (list)
      (fold (fn [(acc (List ty/Diagnostic)) (f a/TopForm)] -> (List ty/Diagnostic)
              (mt f
                ((a/topDefun d)
                  (if (and (listContains? names d.name) (> (notTailCount d ctors) 0))
                    (let [(msg (str "self-call in tailrec fn " d.name " is not in tail position"))
                          (pos (bodyPos d))]
                      (cons (ty/Diagnostic :code "ERR_NOT_TAIL" :message msg :msg msg :line (pairFirst pos) :col (pairSecond pos) :path path) acc))
                    acc))
                (_ acc)))
            (list) forms)))
