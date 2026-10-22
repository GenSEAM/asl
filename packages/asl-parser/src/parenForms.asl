(module asl-parser/parenForms
  :x [BracketError bindPairs normalizeForm printParen bracketError strictParens letArm recordHead slotOf]
  :i [(asl-parser/reader :a rd)])

(schema BracketError (:f msg String) (:f line Int64) (:f col Int64))

fn strictParens -> Bool
  false

fn letArm -> String
  "scheme"

fn recordHead -> String
  "anonRecord"

fn atomText e: rd/SExpr -> String
  (match e ((rd/sexprAtom v) v) (_ ""))

fn atom? e: rd/SExpr -> Bool
  (match e ((rd/sexprAtom _) true) (_ false))

fn list? e: rd/SExpr -> Bool
  (match e ((rd/sexprList _) true) (_ false))

fn itemsOf e: rd/SExpr -> (List rd/SExpr)
  (match e ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) (_ (list)))

fn paramsIndex items: (List rd/SExpr) i: Int64 -> Int64
  (match (listGet items i)
    ((none) -1)
    ((some x) (cond
                ((not (atom? x)) i)
                ((= (atomText x) "->") -1)
                (else (paramsIndex items (+ i 1))))))

fn moduleListKey? k: String -> Bool
  (listContains? (list ":x" ":export" ":exports" ":i" ":import" ":imports") k)

fn slotOf items: (List rd/SExpr) i: Int64 -> String
  (let [(h (match (listHead items) ((some x) (atomText x)) ((none) "")))]
    (cond
      ((< (listLength items) 3) "expr")
      ((and (= h "let") (= i 1)) "bind")
      ((and (listContains? (list "fn" "df" "defun" "defn") h) (= i (paramsIndex items 1))) "params")
      ((and (= h "Fn") (= i 1)) "params")
      ((and (or (= h ":c") (= h ":case")) (= i 2)) "params")
      ((and (= h "module") (and (> i 1) (moduleListKey? (atomText (optionOr (listGet items (- i 1)) (rd/makeAtom "")))))) "params")
      (else "expr")))

fn pairsFlat xs: (List rd/SExpr) acc: (List rd/SExpr) -> (Option (List rd/SExpr))
  (match (listHead xs)
    ((none) (some (listReverse acc)))
    ((some a) (match (listGet xs 1)
                ((none) (none))
                ((some b) (pairsFlat (listDrop xs 2) (cons (rd/makeList (list a b)) acc))))))

fn listHeaded? xs: (List rd/SExpr) -> Bool
  (= (match (listHead xs) ((some h) (atomText h)) ((none) "")) "list")

fn listOf xs: (List rd/SExpr) -> rd/SExpr
  (rd/makeList (cons (rd/makeAtom "list") xs))

fn bindList xs: (List rd/SExpr) arm: String -> (Option rd/SExpr)
  (if (listHeaded? xs) (none) (some (listOf xs)))

fn recordForm items: (List rd/SExpr) -> rd/SExpr
  (rd/makeList (cons (rd/makeAtom "{") (listAppend items (list (rd/makeAtom "}")))))

fn namedDeclParams? items: (List rd/SExpr) i: Int64 -> Bool
  (and (>= i 2) (listContains? (list "fn" "df" "defun" "defn") (match (listHead items) ((some h) (atomText h)) ((none) ""))))

fn slotted items: (List rd/SExpr) arm: String i: Int64 x: rd/SExpr -> rd/SExpr
  (let [(n (normalizeForm x arm))]
    (match n
      ((rd/sexprList xs)
        (let [(slot (slotOf items i))]
          (cond
            ((= slot "bind") (optionOr (bindList xs arm) n))
            ((and (= slot "params") (not (listHeaded? xs))) (if (namedDeclParams? items i) (rd/makeVect xs) (listOf xs)))
            (else n))))
      (_ n)))

fn normalizeForm e: rd/SExpr arm: String -> rd/SExpr
  (match e
    ((rd/sexprAtom _) e)
    ((rd/sexprVect xs) (rd/makeVect (map (fn [x] (normalizeForm x arm)) xs)))
    ((rd/sexprList xs)
      (if (= (match (listHead xs) ((some h) (atomText h)) ((none) "")) (recordHead))
        (recordForm (map (fn [x] (normalizeForm x arm)) (listDrop xs 1)))
        (rd/makeList (map (fn [p] (slotted xs arm (pairFirst p) (pairSecond p))) (zip (range 0 (listLength xs)) xs))))))

fn joined xs: (List String) -> String
  (stringJoin xs " ")

fn record? xs: (List rd/SExpr) -> Bool
  (and (= (match (listHead xs) ((some h) (atomText h)) ((none) "")) "{")
       (= (match (listLast xs) ((some h) (atomText h)) ((none) "")) "}"))

fn printVect parent: (List rd/SExpr) i: Int64 xs: (List rd/SExpr) arm: String -> String
  (let [(slot (slotOf parent i)) (inner (map (fn [x] (printParen x arm)) xs))]
    (cond
      ((and (= slot "bind") (= arm "flat")) (str "(" (joined (map (fn [b] (joined (map (fn [x] (printParen x arm)) (itemsOf b)))) (bindPairs xs))) ")"))
      ((= slot "bind") (str "(" (joined (map (fn [x] (printParen x arm)) (bindPairs xs))) ")"))
      ((= slot "params") (str "(" (joined inner) ")"))
      ((listEmpty? xs) "(list)")
      (else (str "(list " (joined inner) ")"))))

fn printChild parent: (List rd/SExpr) arm: String p: (Pair Int64 rd/SExpr) -> String
  (match (pairSecond p)
    ((rd/sexprVect xs) (printVect parent (pairFirst p) xs arm))
    ((rd/sexprList xs) (if (and (listHeaded? xs) (!= (slotOf parent (pairFirst p)) "expr")) (printVect parent (pairFirst p) (listDrop xs 1) arm) (printParen (pairSecond p) arm)))
    (_ (printParen (pairSecond p) arm)))

fn printParen e: rd/SExpr arm: String -> String
  (match e
    ((rd/sexprAtom v) v)
    ((rd/sexprVect xs) (printVect (list) 0 xs arm))
    ((rd/sexprList xs)
      (if (record? xs)
        (str "(" (joined (cons (recordHead) (map (fn [x] (printParen x arm)) (optionOr (listSlice xs 1 (- (listLength xs) 1)) (list))))) ")")
        (str "(" (joined (map (fn [p] (printChild xs arm p)) (zip (range 0 (listLength xs)) xs))) ")"))))

fn lineEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet b i) 10)) i (lineEnd b n (+ i 1)))

fn stringEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (bytesGet b i) 92) (stringEnd b n (+ i 2)))
    ((= (bytesGet b i) 34) (+ i 1))
    (else (stringEnd b n (+ i 1))))

fn bracketAt b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) -1
    (let [(c (bytesGet b i))]
      (cond
        ((= c 59) (bracketAt b n (lineEnd b n i)))
        ((= c 34) (bracketAt b n (stringEnd b n (+ i 1))))
        ((or (= c 91) (or (= c 93) (or (= c 123) (= c 125)))) i)
        (else (bracketAt b n (+ i 1))))))

fn lineColAt b: Bytes at: Int64 i: Int64 line: Int64 col: Int64 -> (Pair Int64 Int64)
  (cond
    ((>= i at) (pair line col))
    ((= (bytesGet b i) 10) (lineColAt b at (+ i 1) (+ line 1) 1))
    (else (lineColAt b at (+ i 1) line (+ col 1))))

fn bracketError src: String strict: Bool -> (Option BracketError)
  (if (not strict) (none)
    (let [(b (stringToBytes src)) (at (bracketAt b (bytesLength b) 0))]
      (if (< at 0) (none)
        (let [(lc (lineColAt b at 0 1 1))]
          (some (BracketError :msg (str "ERR_READ_BRACKET square brackets and braces are retired: write (let ((a e)) ..), (fn (x) ..), (list a b), (" (recordHead) " :k v), (mapSet (mapEmpty) k v) (tools/codemod/parens.asl --apply)") :line (pairFirst lc) :col (pairSecond lc)))))))

fn pair2? e: rd/SExpr -> Bool
  (and (list? e) (or (= (listLength (itemsOf e)) 2) (= (listLength (itemsOf e)) 3)))

fn bindPairs xs: (List rd/SExpr) -> (List rd/SExpr)
  (if (listAll? pair2? xs) xs (optionOr (pairsFlat xs (list)) xs))
