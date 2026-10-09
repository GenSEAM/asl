(module asl-eval/main
  :x [main]
  :i [])

enum Node
  (nInt v: Int)
  (nFloat v: Float)
  (nStr v: String)
  (nSym v: String)
  (nKw v: String)
  (nList xs: (List Node))
  (nVec xs: (List Node))

enum V
  (vInt v: Int)
  (vFloat v: Float)
  (vStr v: String)
  (vBool v: Bool)
  (vKw v: String)
  (vUnit)
  (vList xs: (List V))
  (vClo params: (List String) body: Node env: (List Bind))
  (vFnRef name: String)
  (vCtor name: String args: (List V))
  (vErr msg: String)
  (vRec name: String keys: (List String) vals: (List V))

schema Tok
  kind: String
  text: String
  col0: Bool

schema Bind
  name: String
  val: V

schema Def
  name: String
  params: (List String)
  body: Node

schema Out
  v: V
  n: Int

schema Outs
  vs: (List V)
  n: Int
  err: String

schema Parsed
  node: Node
  rest: (List Tok)

fn headOf xs: (List T) -> T
  (mt (listHead xs) ((some x) x))

fn tailOf xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn sliceOf s: String i: Int j: Int -> String
  (mt (stringSlice s i j) ((some t) t))


fn charAt s: String i: Int -> String
  (sliceOf s i (+ i 1))

fn isDelim c: String -> Bool
  (stringContains? " \t\r\n()[]{};\"" c)

fn atomEnd s: String i: Int -> Int
  (if (>= i (stringLength s)) i (if (isDelim (charAt s i)) i (atomEnd s (+ i 1))))

fn lineEnd s: String i: Int -> Int
  (if (>= i (stringLength s)) i (if (= (charAt s i) "\n") i (lineEnd s (+ i 1))))

fn unescape c: String -> String
  (match c ("n" "\n") ("t" "\t") (_ c))

fn lexString s: String i: Int acc: String -> (Result Parsed String)
  (if (>= i (stringLength s))
    (err "ERR_READ_UNBALANCED unterminated string")
    (let [(c (charAt s i))]
      (cond
        ((= c "\"") (ok (Parsed :node (nStr acc) :rest (list (Tok :kind "end" :text (stringFromInt64 (+ i 1)) :col0 false)))))
        ((= c "\\") (if (>= (+ i 1) (stringLength s)) (err "ERR_READ_UNBALANCED unterminated string") (lexString s (+ i 2) (stringConcat acc (unescape (charAt s (+ i 1)))))))
        (else (lexString s (+ i 1) (stringConcat acc c))))))

fn lex s: String i: Int col: Int acc: (List Tok) -> (Result (List Tok) String)
  (if (>= i (stringLength s))
    (ok (listReverse acc))
    (let [(c (charAt s i))]
      (cond
        ((= c "\n") (lex s (+ i 1) 0 acc))
        ((stringContains? " \t\r," c) (lex s (+ i 1) (+ col 1) acc))
        ((= c ";") (lex s (lineEnd s i) 1 acc))
        ((stringContains? "([{" c) (lex s (+ i 1) (+ col 1) (cons (Tok :kind "open" :text c :col0 (= col 0)) acc)))
        ((stringContains? ")]}" c) (lex s (+ i 1) (+ col 1) (cons (Tok :kind "close" :text c :col0 (= col 0)) acc)))
        ((= c "\"")
          (mt (lexString s (+ i 1) "")
            ((err e) (err e))
            ((ok p) (let [(j (stringToInt (headOf p.rest).text))]
                      (mt p.node
                        ((nStr v) (lex s j (+ col 1) (cons (Tok :kind "str" :text v :col0 (= col 0)) acc)))
                        (_ (err "ERR_READ internal")))))))
        (else (let [(j (atomEnd s i))]
                 (lex s j (+ col 1) (cons (Tok :kind "atom" :text (sliceOf s i j) :col0 (= col 0)) acc)))))))


fn digit c: String -> Int
  (match c ("0" 0) ("1" 1) ("2" 2) ("3" 3) ("4" 4) ("5" 5) ("6" 6) ("7" 7) ("8" 8) ("9" 9) (_ -1))

fn allDigits s: String i: Int -> Bool
  (if (>= i (stringLength s)) true (if (< (digit (charAt s i)) 0) false (allDigits s (+ i 1))))

fn digitsNeg s: String i: Int acc: Int -> Int
  (if (>= i (stringLength s)) acc (digitsNeg s (+ i 1) (- (* acc 10) (digit (charAt s i)))))

fn stringToInt s: String -> Int
  (if (stringStartsWith? s "-") (digitsNeg s 1 0) (- 0 (digitsNeg s 0 0)))

fn isNumberStart t: String -> Bool
  (if (>= (digit (charAt t 0)) 0) true
    (and (> (stringLength t) 1) (and (stringContains? "-+" (charAt t 0)) (>= (digit (charAt t 1)) 0))))

fn skipDigits t: String i: Int -> Int
  (if (and (< i (stringLength t)) (>= (digit (charAt t i)) 0)) (skipDigits t (+ i 1)) i)

fn isFloatLit t: String -> Bool
  (let [(n (stringLength t))
        (i0 (if (stringContains? "+-" (charAt t 0)) 1 0))
        (i1 (skipDigits t i0))
        (hasDot (and (< i1 n) (= (charAt t i1) ".")))
        (i2 (if hasDot (skipDigits t (+ i1 1)) i1))
        (hasExp (and (< i2 n) (stringContains? "eE" (charAt t i2))))
        (i3 (if hasExp (if (and (< (+ i2 1) n) (stringContains? "+-" (charAt t (+ i2 1)))) (+ i2 2) (+ i2 1)) i2))
        (i4 (if hasExp (skipDigits t i3) i3))]
    (and (> i1 i0) (and (or hasDot hasExp) (and (or (not hasExp) (> i4 i3)) (= i4 n)))))

fn intFits ds: String neg: Bool -> Bool
  (let [(k (stringLength ds))]
    (if (< k 19) true (if (> k 19) false (<= ds (if neg "9223372036854775808" "9223372036854775807")))))

fn intLit t: String start: Int neg: Bool -> (Result Node String)
  (let [(ds (sliceOf t start (stringLength t)))]
    (if (intFits ds neg) (ok (nInt (if neg (digitsNeg ds 0 0) (- 0 (digitsNeg ds 0 0)))))
      (err (str "ERR_INT_RANGE literal " t " outside int64"))))

fn atomNode t: String -> (Result Node String)
  (cond
    ((stringStartsWith? t ":") (ok (nKw (sliceOf t 1 (stringLength t)))))
    ((not (isNumberStart t)) (ok (nSym t)))
    ((and (stringStartsWith? t "-") (allDigits t 1)) (intLit t 1 true))
    ((and (stringStartsWith? t "+") (allDigits t 1)) (intLit t 1 false))
    ((allDigits t 0) (intLit t 0 false))
    ((isFloatLit t) (mt (stringToFloat64 t) ((some f) (ok (nFloat f))) ((none) (err (str "ERR_READ malformed number " t)))))
    (else (err (str "ERR_READ malformed number " t))))


fn closerOf o: String -> String
  (match o ("(" ")") ("[" "]") (_ "}"))

fn parseSeq ts: (List Tok) close: String acc: (List Node) depth: Int -> (Result Parsed String)
  (if (listEmpty? ts)
    (err "ERR_READ_UNBALANCED missing close")
    (let [(t (headOf ts))]
      (if (= t.kind "close")
        (if (= t.text close)
          (ok (Parsed :node (nList (listReverse acc)) :rest (tailOf ts)))
          (err (str "ERR_READ_UNBALANCED expected " close " got " t.text)))
        (mt (parseDatum ts depth)
          ((err e) (err e))
          ((ok p) (parseSeq p.rest close (cons p.node acc) depth))))))

fn maxNesting -> Int
  1000

fn parseDatum ts: (List Tok) depth: Int -> (Result Parsed String)
  (let [(t (headOf ts)) (k t.kind)]
    (cond
      ((= k "str") (ok (Parsed :node (nStr t.text) :rest (tailOf ts))))
      ((= k "atom") (mt (atomNode t.text) ((ok nd) (ok (Parsed :node nd :rest (tailOf ts)))) ((err e) (err e))))
      ((= k "close") (err (str "ERR_READ_UNBALANCED unexpected " t.text)))
      ((>= depth (maxNesting)) (err (str "ERR_DEPTH expression nested deeper than " (maxNesting))))
      (else
        (mt (parseSeq (tailOf ts) (closerOf t.text) (list) (+ depth 1))
          ((err e) (err e))
          ((ok p) (mt p.node
                    ((nList xs) (cond
                                  ((= t.text "[") (ok (Parsed :node (nVec xs) :rest p.rest)))
                                  ((= t.text "{") (ok (Parsed :node (nList (cons (nSym "%map") xs)) :rest p.rest)))
                                  (else (ok p))))
                    (_ (err "ERR_READ internal"))))))))

fn parseItems ts: (List Tok) cur: (List Node) acc: (List (List Node)) -> (Result (List (List Node)) String)
  (if (listEmpty? ts)
    (ok (listReverse (if (listEmpty? cur) acc (cons (listReverse cur) acc))))
    (let [(fresh (and (headOf ts).col0 (not (listEmpty? cur))))
          (acc2 (if fresh (cons (listReverse cur) acc) acc))
          (cur2 (if fresh (list) cur))]
      (mt (parseDatum ts 0)
        ((err e) (err e))
        ((ok p) (parseItems p.rest (cons p.node cur2) acc2)))))

fn readItems src: String -> (Result (List (List Node)) String)
  (mt (lex src 0 0 (list))
    ((err e) (err e))
    ((ok ts) (parseItems ts (list) (list))))


fn render v: V -> String
  (mt v
    ((vInt i) (stringFromInt64 i))
    ((vFloat f) (stringFromFloat64 f))
    ((vStr s) (str "\"" s "\""))
    ((vBool b) (if b "true" "false"))
    ((vKw k) (str ":" k))
    ((vUnit) "()")
    ((vList xs) (str "(" (renderList xs "") ")"))
    ((vClo ps b e) "<fn>")
    ((vFnRef nm) (str "<fn " nm ">"))
    ((vCtor nm as) (str "(" nm (renderArgs as) ")"))
    ((vRec nm ks vs) (str "{" nm (renderRec ks vs "") "}"))
    ((vErr m) m))

fn renderList xs: (List V) acc: String -> String
  (if (listEmpty? xs) acc
    (renderList (tailOf xs) (if (= acc "") (render (headOf xs)) (str acc " " (render (headOf xs))))))

fn renderRec ks: (List String) vs: (List V) acc: String -> String
  (if (listEmpty? ks) acc (renderRec (tailOf ks) (tailOf vs) (str acc " :" (headOf ks) " " (render (headOf vs)))))

fn renderArgs xs: (List V) -> String
  (if (listEmpty? xs) "" (str " " (renderList xs "")))

fn typeOf v: V -> String
  (mt v ((vInt i) "Int") ((vFloat f) "Float") ((vStr s) "String") ((vBool b) "Bool") ((vKw k) "Keyword")
        ((vUnit) "Unit") ((vList xs) "List") ((vClo p b e) "Fn") ((vFnRef n) "Fn") ((vCtor n a) "Ctor") ((vRec nm ks vs) "Record") ((vErr m) "Err"))

fn isErr v: V -> Bool
  (mt v ((vErr m) true) (_ false))

fn typeErr op: String a: V b: V -> V
  (vErr (str "ERR_TYPE " op " on " (typeOf a) " and " (typeOf b)))


fn arith op: String a: V b: V -> V
  (mt a
    ((vInt x) (mt b ((vInt y) (arithInt op x y)) (_ (typeErr op a b))))
    ((vFloat x) (mt b ((vFloat y) (arithFloat op x y)) (_ (typeErr op a b))))
    ((vStr x) (mt b ((vStr y) (cmpStr op x y)) (_ (typeErr op a b))))
    ((vBool x) (mt b ((vBool y) (if (= op "=") (vBool (= x y)) (if (= op "!=") (vBool (not (= x y))) (typeErr op a b)))) (_ (typeErr op a b))))
    ((vKw x) (mt b ((vKw y) (if (= op "=") (vBool (= x y)) (if (= op "!=") (vBool (not (= x y))) (typeErr op a b)))) (_ (typeErr op a b))))
    (_ (if (or (= op "=") (= op "!=")) (eqOp op a b) (typeErr op a b))))

schema DV
  v: V
  depth: Int

fn dataLimit -> Int
  10000

fn pushKids v: V d: Int rest: (List DV) -> (List DV)
  (let [(push (fn [(a (List DV)) (x V)] -> (List DV) (cons (DV :v x :depth d) a)))]
    (mt v
      ((vList xs) (fold push rest xs))
      ((vRec nm ks vs) (fold push rest vs))
      ((vCtor nm as) (fold push rest as))
      (_ rest)))

fn deeper work: (List DV) -> Bool
  (if (listEmpty? work) false
    (let [(it (headOf work))]
      (if (> it.depth (dataLimit)) true (deeper (pushKids it.v (+ it.depth 1) (tailOf work))))))

fn tooDeep v: V -> Bool
  (deeper (list (DV :v v :depth 0)))

fn anyTooDeep vs: (List V) -> Bool
  (if (listEmpty? vs) false (if (tooDeep (headOf vs)) true (anyTooDeep (tailOf vs))))

fn eqOp op: String a: V b: V -> V
  (if (or (tooDeep a) (tooDeep b))
    (vErr (str "ERR_DEPTH " op " on values nested deeper than " (dataLimit)))
    (let [(r (valEq a b))]
      (mt r ((vBool x) (vBool (if (= op "=") x (not x)))) (_ r))))

fn depthErr -> V
  (vErr (str "ERR_DEPTH printing a value nested deeper than " (dataLimit)))

fn valEq a: V b: V -> V
  (if (not (= (typeOf a) (typeOf b)))
    (typeErr "=" a b)
    (mt a
      ((vList xs) (mt b ((vList ys) (listEq xs ys)) (_ (typeErr "=" a b))))
      ((vRec n1 k1 v1) (mt b ((vRec n2 k2 v2) (if (and (= n1 n2) (= (str k1) (str k2))) (listEq v1 v2) (vBool false))) (_ (typeErr "=" a b))))
      ((vCtor n1 a1) (mt b ((vCtor n2 a2) (if (= n1 n2) (listEq a1 a2) (vBool false))) (_ (typeErr "=" a b))))
      ((vUnit) (vBool true))
      ((vInt x) (arith "=" a b))
      ((vFloat x) (arith "=" a b))
      ((vStr x) (arith "=" a b))
      ((vBool x) (arith "=" a b))
      ((vKw x) (arith "=" a b))
      (_ (typeErr "=" a b))))

fn listEq xs: (List V) ys: (List V) -> V
  (cond
    ((and (listEmpty? xs) (listEmpty? ys)) (vBool true))
    ((or (listEmpty? xs) (listEmpty? ys)) (vBool false))
    (else (let [(r (valEq (headOf xs) (headOf ys)))]
             (mt r ((vBool b) (if b (listEq (tailOf xs) (tailOf ys)) r)) (_ r)))))

fn arithInt op: String x: Int y: Int -> V
  (cond
    ((= op "+") (vInt (+ x y)))
    ((= op "-") (vInt (- x y)))
    ((= op "*") (vInt (* x y)))
    ((= op "/") (if (= y 0) (vErr "ERR_DIV_ZERO division by zero") (vInt (/ x y))))
    ((= op "mod") (if (= y 0) (vErr "ERR_DIV_ZERO mod by zero") (vInt (mod x y))))
    ((= op "<") (vBool (< x y)))
    ((= op "<=") (vBool (<= x y)))
    ((= op ">") (vBool (> x y)))
    ((= op ">=") (vBool (>= x y)))
    ((= op "=") (vBool (= x y)))
    (else (vBool (not (= x y)))))

fn arithFloat op: String x: Float y: Float -> V
  (cond
    ((= op "+") (vFloat (+ x y)))
    ((= op "-") (vFloat (- x y)))
    ((= op "*") (vFloat (* x y)))
    ((= op "/") (vFloat (/ x y)))
    ((= op "mod") (vFloat (mod x y)))
    ((= op "<") (vBool (< x y)))
    ((= op "<=") (vBool (<= x y)))
    ((= op ">") (vBool (> x y)))
    ((= op ">=") (vBool (>= x y)))
    ((= op "=") (vBool (= x y)))
    (else (vBool (not (= x y)))))

fn cmpStr op: String x: String y: String -> V
  (cond
    ((= op "=") (vBool (= x y)))
    ((= op "!=") (vBool (not (= x y))))
    ((= op "<") (vBool (< x y)))
    ((= op ">") (vBool (> x y)))
    (else (vErr (str "ERR_TYPE " op " on String and String"))))

fn isArith op: String -> Bool
  (match op ("+" true) ("-" true) ("*" true) ("/" true) ("mod" true) ("<" true) ("<=" true) (">" true) (">=" true) ("=" true) ("!=" true) (_ false))

fn isBuiltin nm: String -> Bool
  (if (isArith nm) true
    (match nm ("ok" true) ("err" true) ("list" true) ("str" true) ("println" true) ("print" true) ("stringLength" true) ("stringConcat" true) ("%ctor" true) ("%rec" true) ("%map" true) ("%field" true) (_ false)))

fn strOf v: V -> String
  (mt v ((vStr s) s) (_ (render v)))

fn strJoin vs: (List V) acc: String -> String
  (if (listEmpty? vs) acc (strJoin (tailOf vs) (stringConcat acc (strOf (headOf vs)))))

fn arityErr nm: String want: Int got: Int -> V
  (vErr (str "ERR_ARITY " nm " takes " want " argument(s), got " got))

fn commaAt s: String i: Int -> Int
  (if (>= i (stringLength s)) -1 (if (= (charAt s i) ",") i (commaAt s (+ i 1))))

fn splitComma s: String -> (List String)
  (if (= s "") (list)
    (let [(i (commaAt s 0))]
      (if (< i 0) (list s) (cons (sliceOf s 0 i) (splitComma (sliceOf s (+ i 1) (stringLength s)))))))

fn joinComma xs: (List String) -> String
  (if (listEmpty? xs) "" (if (listEmpty? (tailOf xs)) (headOf xs) (str (headOf xs) "," (joinComma (tailOf xs)))))

fn mkRec nm: String fields: (List String) xs: (List V) ks: (List String) vs: (List V) -> V
  (if (listEmpty? xs)
    (if (or (= nm "") (and (= (listLength ks) (listLength fields)) (allIn ks fields)))
      (vRec nm (listReverse ks) (listReverse vs))
      (vErr (str "ERR_TYPE " nm " takes fields " (joinComma fields))))
    (if (listEmpty? (tailOf xs))
      (vErr (str "ERR_ARITY record " nm " has a key without a value"))
      (mt (headOf xs)
        ((vKw k) (if (or (= nm "") (inScope fields k))
                   (mkRec nm fields (tailOf (tailOf xs)) (cons k ks) (cons (headOf (tailOf xs)) vs))
                   (vErr (str "ERR_TYPE " nm " has no field " k))))
        (_ (vErr "ERR_TYPE record keys are keywords")))))

fn allIn xs: (List String) ys: (List String) -> Bool
  (if (listEmpty? xs) true (if (inScope ys (headOf xs)) (allIn (tailOf xs) ys) false))

fn fieldOf f: String ks: (List String) vs: (List V) nm: String -> V
  (if (listEmpty? ks) (vErr (str "ERR_TYPE " nm " has no field " f))
    (if (= (headOf ks) f) (headOf vs) (fieldOf f (tailOf ks) (tailOf vs) nm)))

fn getField f: String v: V -> V
  (mt v ((vRec nm ks vs) (fieldOf f ks vs nm)) (_ (vErr (str "ERR_TYPE .-" f " on " (typeOf v)))))

fn applyBuiltin! nm: String args: (List V) -> V
  (let [(k (listLength args))]
    (cond
      ((isArith nm)
        (if (= nm "-")
          (if (= k 1) (arith "-" (vInt 0) (headOf args)) (if (= k 2) (arith nm (headOf args) (headOf (tailOf args))) (arityErr nm 2 k)))
          (if (= k 2) (arith nm (headOf args) (headOf (tailOf args))) (arityErr nm 2 k))))
      ((= nm "ok") (if (= k 1) (vCtor "ok" args) (arityErr nm 1 k)))
      ((= nm "err") (if (= k 1) (vCtor "err" args) (arityErr nm 1 k)))
      ((= nm "list") (vList args))
      ((and (or (= nm "str") (or (= nm "println") (= nm "print"))) (anyTooDeep args)) (depthErr))
      ((= nm "str") (vStr (strJoin args "")))
      ((= nm "println") (do (println (strJoin args "")) (vUnit)))
      ((= nm "print") (do (print (strJoin args "")) (vUnit)))
      ((= nm "stringLength") (if (= k 1) (mt (headOf args) ((vStr s) (vInt (stringLength s))) (_ (vErr "ERR_TYPE stringLength expects String"))) (arityErr nm 1 k)))
      ((= nm "%ctor") (vCtor (strOf (headOf args)) (tailOf (tailOf (tailOf args)))))
      ((= nm "%rec") (mkRec (strOf (headOf args)) (splitComma (strOf (headOf (tailOf args)))) (tailOf (tailOf args)) (list) (list)))
      ((= nm "%map") (mkRec "" (list) args (list) (list)))
      ((= nm "%field") (getField (strOf (headOf args)) (headOf (tailOf args))))
      (else (if (= k 2)
               (mt (headOf args) ((vStr a) (mt (headOf (tailOf args)) ((vStr b) (vStr (stringConcat a b))) (_ (vErr "ERR_TYPE stringConcat expects String")))) (_ (vErr "ERR_TYPE stringConcat expects String")))
               (arityErr nm 2 k)))))


enum K
  (kIf thenN: Node elseN: Node env: (List Bind))
  (kDo rest: (List Node) env: (List Bind))
  (kLet name: String rest: (List Node) body: (List Node) env: (List Bind))
  (kHead args: (List Node) env: (List Bind))
  (kArgs f: V done: (List V) rest: (List Node) env: (List Bind))
  (kVec done: (List V) rest: (List Node) env: (List Bind))
  (kNot)
  (kAnd second: Node env: (List Bind))
  (kOr second: Node env: (List Bind))
  (kBool who: String)
  (kAssert msg: String)
  (kCond body: (List Node) arms: (List Node) env: (List Bind))
  (kRet)
  (kMt arms: (List Node) env: (List Bind))
  (kMatch arms: (List Node) env: (List Bind))

fn maxFrames -> Int
  1048576

fn lookup e: (List Bind) nm: String -> (Result V String)
  (if (listEmpty? e) (err nm)
    (if (= (headOf e).name nm) (ok (headOf e).val) (lookup (tailOf e) nm)))

fn findDef g: (List Def) nm: String -> (Result Def String)
  (if (listEmpty? g) (err nm)
    (if (= (headOf g).name nm) (ok (headOf g)) (findDef (tailOf g) nm)))

fn symValue g: (List Def) e: (List Bind) s: String -> V
  (cond
    ((= s "true") (vBool true))
    ((= s "false") (vBool false))
    (else
      (mt (lookup e s)
        ((ok v) v)
        ((err x) (mt (findDef g s)
                   ((ok d) (vFnRef s))
                   ((err y) (if (isBuiltin s) (vFnRef s) (vErr (str "ERR_UNKNOWN_SYMBOL " s)))))))))

fn bindAll ps: (List String) vs: (List V) e: (List Bind) -> (List Bind)
  (if (listEmpty? ps) e (bindAll (tailOf ps) (tailOf vs) (cons (Bind :name (headOf ps) :val (headOf vs)) e)))

fn paramNames ps: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? ps) (listReverse acc)
    (mt (headOf ps)
      ((nList p) (mt (headOf p) ((nSym s) (paramNames (tailOf ps) (cons s acc))) (_ (paramNames (tailOf ps) acc))))
      ((nSym s) (paramNames (tailOf ps) (cons s acc)))
      (_ (paramNames (tailOf ps) acc))))

fn lastNode xs: (List Node) -> Node
  (if (listEmpty? (tailOf xs)) (headOf xs) (lastNode (tailOf xs)))

fn stop v: V n: Int -> Out
  (Out :v v :n n)

fn notBool who: String v: V n: Int -> Out
  (stop (vErr (str "ERR_TYPE " who " expects Bool, got " (typeOf v))) n)

fn isRetTop k: (List K) -> Bool
  (if (listEmpty? k) false (mt (headOf k) ((kRet) true) (_ false)))

fn ev! g: (List Def) e: (List Bind) x: Node k: (List K) d: Int n: Int -> Out
  (mt x
    ((nInt i) (ret! g (vInt i) k d n))
    ((nFloat f) (ret! g (vFloat f) k d n))
    ((nStr s) (ret! g (vStr s) k d n))
    ((nKw s) (ret! g (vKw s) k d n))
    ((nSym s) (ret! g (symValue g e s) k d n))
    ((nVec xs) (if (listEmpty? xs) (ret! g (vList (list)) k d n) (ev! g e (headOf xs) (cons (kVec (list) (tailOf xs) e) k) d n)))
    ((nList xs) (evList! g e xs k d n)))

fn evSeq! g: (List Def) e: (List Bind) xs: (List Node) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? (tailOf xs))
    (ev! g e (headOf xs) k d n)
    (ev! g e (headOf xs) (cons (kDo (tailOf xs) e) k) d n))

fn evLet! g: (List Def) e: (List Bind) bs: (List Node) body: (List Node) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? bs)
    (evSeq! g e body k d n)
    (mt (headOf bs)
      ((nList pair)
        (mt (headOf pair)
          ((nSym nm) (ev! g e (headOf (tailOf pair)) (cons (kLet nm (tailOf bs) body e) k) d n))
          (_ (stop (vErr "ERR_SYNTAX let binding name") n))))
      (_ (stop (vErr "ERR_SYNTAX let binding") n))))

fn evCond! g: (List Def) e: (List Bind) arms: (List Node) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? arms)
    (stop (vErr "ERR_MATCH_NONEXHAUSTIVE cond") n)
    (mt (headOf arms)
      ((nList arm)
        (mt (headOf arm)
          ((nKw kw) (evSeq! g e (tailOf arm) k d n))
          (_ (ev! g e (headOf arm) (cons (kCond (tailOf arm) (tailOf arms) e) k) d n))))
      (_ (stop (vErr "ERR_SYNTAX cond arm") n))))

fn evList! g: (List Def) e: (List Bind) xs: (List Node) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? xs) (ret! g (vUnit) k d n)
    (let [(h (headOf xs)) (rest (tailOf xs)) (cnt (listLength rest))
          (form (mt h ((nSym s) s) (_ "")))]
      (cond
        ((stringStartsWith? form ".-")
          (if (= cnt 1) (ev! g e (nList (list (nSym "%field") (nStr (sliceOf form 2 (stringLength form))) (headOf rest))) k d n) (stop (vErr (str "ERR_ARITY " form " takes 1 argument(s)")) n)))
        ((= form "mt") (if (< cnt 1) (stop (vErr "ERR_SYNTAX mt without subject") n) (ev! g e (headOf rest) (cons (kMt (tailOf rest) e) k) d n)))
        ((= form "match") (if (< cnt 1) (stop (vErr "ERR_SYNTAX match without subject") n) (ev! g e (headOf rest) (cons (kMatch (tailOf rest) e) k) d n)))
        ((= form "if")
          (if (= cnt 3)
            (ev! g e (headOf rest) (cons (kIf (headOf (tailOf rest)) (headOf (tailOf (tailOf rest))) e) k) d n)
            (stop (vErr "ERR_SYNTAX if takes 3 forms") n)))
        ((= form "do") (if (= cnt 0) (ret! g (vUnit) k d n) (evSeq! g e rest k d n)))
        ((= form "let") (mt (headOf rest) ((nVec bs) (evLet! g e bs (tailOf rest) k d n)) (_ (stop (vErr "ERR_SYNTAX let bindings") n))))
        ((= form "fn") (mt (headOf rest) ((nVec ps) (ret! g (vClo (paramNames ps (list)) (lastNode rest) e) k d n)) (_ (stop (vErr "ERR_SYNTAX fn parameters") n))))
        ((= form "not") (ev! g e (headOf rest) (cons (kNot) k) d n))
        ((= form "and") (ev! g e (headOf rest) (cons (kAnd (headOf (tailOf rest)) e) k) d n))
        ((= form "or") (ev! g e (headOf rest) (cons (kOr (headOf (tailOf rest)) e) k) d n))
        ((= form "cond") (evCond! g e rest k d n))
        ((= form "assert")
          (ev! g e (headOf rest) (cons (kAssert (mt (headOf (tailOf rest)) ((nStr s) s) (_ ""))) k) d n))
        (else (ev! g e h (cons (kHead rest e) k) d n)))))

fn ret! g: (List Def) v: V k: (List K) d: Int n: Int -> Out
  (if (or (isErr v) (listEmpty? k))
    (stop v n)
    (let [(k2 (tailOf k))]
      (mt (headOf k)
        ((kIf t el e) (mt v ((vBool b) (ev! g e (if b t el) k2 d n)) (_ (notBool "if" v n))))
        ((kDo rest e) (evSeq! g e rest k2 d n))
        ((kLet nm rest body e) (evLet! g (cons (Bind :name nm :val v) e) rest body k2 d n))
        ((kHead args e) (if (listEmpty? args) (applyV! g v (list) k2 d n) (ev! g e (headOf args) (cons (kArgs v (list) (tailOf args) e) k2) d n)))
        ((kArgs f done rest e)
          (if (listEmpty? rest)
            (applyV! g f (listReverse (cons v done)) k2 d n)
            (ev! g e (headOf rest) (cons (kArgs f (cons v done) (tailOf rest) e) k2) d n)))
        ((kVec done rest e)
          (if (listEmpty? rest)
            (ret! g (vList (listReverse (cons v done))) k2 d n)
            (ev! g e (headOf rest) (cons (kVec (cons v done) (tailOf rest) e) k2) d n)))
        ((kNot) (mt v ((vBool b) (ret! g (vBool (not b)) k2 d n)) (_ (notBool "not" v n))))
        ((kAnd second e) (mt v ((vBool b) (if b (ev! g e second (cons (kBool "and") k2) d n) (ret! g v k2 d n))) (_ (notBool "and" v n))))
        ((kOr second e) (mt v ((vBool b) (if b (ret! g v k2 d n) (ev! g e second (cons (kBool "or") k2) d n))) (_ (notBool "or" v n))))
        ((kBool who) (mt v ((vBool b) (ret! g v k2 d n)) (_ (notBool who v n))))
        ((kAssert msg) (mt v ((vBool b) (if b (ret! g (vUnit) k2 d (+ n 1)) (stop (vErr (str "ERR_ASSERT: assertion failed: " msg)) (+ n 1)))) (_ (notBool "assert" v n))))
        ((kCond body arms e) (mt v ((vBool b) (if b (evSeq! g e body k2 d n) (evCond! g e arms k2 d n))) (_ (notBool "cond" v n))))
        ((kMt arms e) (mtArms! g v arms e k2 d n))
        ((kMatch arms e) (matchArms! g v arms e k2 d n))
        ((kRet) (ret! g v k2 (- d 1) n)))))

fn bindPat ps: (List Node) vs: (List V) e: (List Bind) -> (List Bind)
  (if (listEmpty? ps) e
    (bindPat (tailOf ps) (tailOf vs) (if (= (symText (headOf ps)) "_") e (cons (Bind :name (symText (headOf ps)) :val (headOf vs)) e))))

fn mtArms! g: (List Def) v: V arms: (List Node) e: (List Bind) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? arms)
    (stop (vErr (str "ERR_MATCH_NONEXHAUSTIVE no mt arm matches " (renderSafe v))) n)
    (mt (headOf arms)
      ((nList arm)
        (mt (headOf arm)
          ((nSym s) (if (= s "_") (evSeq! g e (tailOf arm) k d n) (mtArms! g v (tailOf arms) e k d n)))
          ((nList ps)
            (mt v
              ((vCtor nm args)
                (if (and (= nm (lastSeg (symTail (symText (headOf ps))))) (= (listLength args) (listLength (tailOf ps))))
                  (evSeq! g (bindPat (tailOf ps) args e) (tailOf arm) k d n)
                  (mtArms! g v (tailOf arms) e k d n)))
              (_ (mtArms! g v (tailOf arms) e k d n))))
          (_ (stop (vErr "ERR_BAD_PATTERN mt arm") n))))
      (_ (stop (vErr "ERR_SYNTAX mt arm") n))))

fn litMatch pat: Node v: V -> V
  (mt pat
    ((nInt i) (mt v ((vInt x) (vBool (= i x))) ((vFloat f) (vErr "ERR_TYPE match Int arm against Float")) (_ (vBool false))))
    ((nFloat f) (mt v ((vFloat x) (vBool (= f x))) ((vInt i) (vErr "ERR_TYPE match Float arm against Int")) (_ (vBool false))))
    ((nStr s) (mt v ((vStr x) (vBool (= s x))) (_ (vBool false))))
    ((nKw s) (mt v ((vKw x) (vBool (= s x))) (_ (vBool false))))
    ((nSym s) (cond
                ((= s "true") (mt v ((vBool b) (vBool b)) (_ (vBool false))))
                ((= s "false") (mt v ((vBool b) (vBool (not b))) (_ (vBool false))))
                (else (vErr (str "ERR_BAD_PATTERN match arm " s)))))
    (_ (vErr "ERR_BAD_PATTERN match arm")))

fn matchArms! g: (List Def) v: V arms: (List Node) e: (List Bind) k: (List K) d: Int n: Int -> Out
  (if (listEmpty? arms)
    (stop (vErr (str "ERR_MATCH_NONEXHAUSTIVE no match arm matches " (renderSafe v))) n)
    (mt (headOf arms)
      ((nList arm)
        (if (= (symText (headOf arm)) "_")
          (evSeq! g e (tailOf arm) k d n)
          (let [(r (litMatch (headOf arm) v))]
            (mt r
              ((vBool b) (if b (evSeq! g e (tailOf arm) k d n) (matchArms! g v (tailOf arms) e k d n)))
              (_ (stop r n))))))
      (_ (stop (vErr "ERR_SYNTAX match arm") n))))

fn enter! g: (List Def) e: (List Bind) body: Node k: (List K) d: Int n: Int nm: String -> Out
  (if (isRetTop k)
    (ev! g e body k d n)
    (if (>= d (maxFrames))
      (stop (vErr (str "ERR_STACK_DEPTH: call depth exceeds " (maxFrames) " frames in " nm)) n)
      (ev! g e body (cons (kRet) k) (+ d 1) n)))

fn applyV! g: (List Def) f: V args: (List V) k: (List K) d: Int n: Int -> Out
  (mt f
    ((vClo ps body env)
      (if (= (listLength ps) (listLength args))
        (enter! g (bindAll ps args env) body k d n "fn")
        (stop (arityErr "fn" (listLength ps) (listLength args)) n)))
    ((vFnRef nm)
      (mt (findDef g nm)
        ((ok df) (if (= (listLength df.params) (listLength args))
                   (enter! g (bindAll df.params args (list)) df.body k d n nm)
                   (stop (arityErr nm (listLength df.params) (listLength args)) n)))
        ((err x) (ret! g (applyBuiltin! nm args) k d n))))
    (_ (stop (vErr (str "ERR_TYPE cannot call " (typeOf f))) n)))

fn callEntry! g: (List Def) nm: String args: (List V) n: Int -> Out
  (applyV! g (vFnRef nm) args (list) 0 n)


fn builtinArity nm: String -> Int
  (cond
    ((isArith nm) (if (= nm "-") -1 2))
    ((= nm "ok") 1)
    ((= nm "err") 1)
    ((= nm "stringLength") 1)
    ((= nm "stringConcat") 2)
    (else -1))

fn inScope sc: (List String) s: String -> Bool
  (if (listEmpty? sc) false (if (= (headOf sc) s) true (inScope (tailOf sc) s)))

fn resolveSym g: (List Def) sc: (List String) s: String acc: (List String) -> (List String)
  (if (or (= s "true") (or (= s "false") (or (inScope sc s) (or (isBuiltin s) (mt (findDef g s) ((ok d) true) ((err x) false))))))
    acc
    (cons (str "ERR_UNKNOWN_SYMBOL " s) acc))

fn resolveAll g: (List Def) sc: (List String) xs: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? xs) acc (resolveAll g sc (tailOf xs) (resolve g sc (headOf xs) acc)))

fn resolveLet g: (List Def) sc: (List String) bs: (List Node) body: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? bs)
    (resolveAll g sc body acc)
    (mt (headOf bs)
      ((nList pair) (mt (headOf pair)
                      ((nSym nm) (resolveLet g (cons nm sc) (tailOf bs) body (resolveAll g sc (tailOf pair) acc)))
                      (_ (cons "ERR_SYNTAX let binding name" acc))))
      (_ (cons "ERR_SYNTAX let binding" acc))))

fn resolveArms g: (List Def) sc: (List String) arms: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? arms) acc
    (resolveArms g sc (tailOf arms)
      (mt (headOf arms) ((nList arm) (resolveAll g sc arm acc)) (_ (cons "ERR_SYNTAX cond arm" acc)))))

fn arityCheck g: (List Def) sc: (List String) nm: String got: Int acc: (List String) -> (List String)
  (if (inScope sc nm) acc
    (mt (findDef g nm)
      ((ok d) (if (= (listLength d.params) got) acc (cons (render (arityErr nm (listLength d.params) got)) acc)))
      ((err x) (let [(want (builtinArity nm))]
                 (cond
                   ((and (= nm "-") (or (< got 1) (> got 2))) (cons (render (arityErr nm 2 got)) acc))
                   ((and (>= want 0) (not (= want got))) (cons (render (arityErr nm want got)) acc))
                   (else acc))))))

fn resolve g: (List Def) sc: (List String) x: Node acc: (List String) -> (List String)
  (mt x
    ((nSym s) (resolveSym g sc s acc))
    ((nVec xs) (resolveAll g sc xs acc))
    ((nList xs)
      (if (listEmpty? xs) acc
        (let [(h (headOf xs)) (rest (tailOf xs)) (form (symText h))]
          (cond
            ((or (= form "if") (or (= form "do") (or (= form "not") (or (= form "and") (or (= form "or") (= form "assert"))))))
              (resolveAll g sc rest acc))
            ((= form "let") (mt (headOf rest) ((nVec bs) (resolveLet g sc bs (tailOf rest) acc)) (_ (cons "ERR_SYNTAX let bindings" acc))))
            ((= form "fn") (mt (headOf rest) ((nVec ps) (resolve g (fold (fn [(s (List String)) (p String)] -> (List String) (cons p s)) sc (paramNames ps (list))) (lastNode rest) acc)) (_ (cons "ERR_SYNTAX fn parameters" acc))))
            ((stringStartsWith? form ".-") (resolveAll g sc rest acc))
            ((= form "mt") (if (listEmpty? rest) (cons "ERR_SYNTAX mt without subject" acc) (resolveMt g sc (tailOf rest) (resolve g sc (headOf rest) acc))))
            ((= form "match") (if (listEmpty? rest) (cons "ERR_SYNTAX match without subject" acc) (resolveMatch g sc (tailOf rest) (resolve g sc (headOf rest) acc))))
            ((= form "cond") (resolveArms g sc rest acc))
            ((= form "") (resolveAll g sc xs acc))
            (else (resolveAll g sc rest (arityCheck g sc form (listLength rest) (resolveSym g sc form acc))))))))
    (_ acc))

fn ctorBody g: (List Def) cn: String -> (List Node)
  (mt (findDef g cn)
    ((ok d) (mt d.body ((nList xs) (if (= (symText (headOf xs)) "%ctor") xs (list))) (_ (list))))
    ((err x) (list)))

fn ctorArity g: (List Def) cn: String -> Int
  (if (or (= cn "ok") (= cn "err")) 1
    (let [(b (ctorBody g cn))] (if (listEmpty? b) -1 (- (listLength b) 4))))

fn nthStr xs: (List Node) i: Int -> String
  (if (= i 0) (mt (headOf xs) ((nStr s) s) (_ "")) (nthStr (tailOf xs) (- i 1)))

fn allSyms xs: (List Node) -> Bool
  (if (listEmpty? xs) true (mt (headOf xs) ((nSym s) (allSyms (tailOf xs))) (_ false)))

fn resolveMtArm g: (List Def) sc: (List String) arm: Node acc: (List String) -> (List String)
  (mt arm
    ((nList xs)
      (mt (headOf xs)
        ((nSym s) (if (= s "_") (resolveAll g sc (tailOf xs) acc) (cons (str "ERR_BAD_PATTERN mt arm " s) acc)))
        ((nList ps)
          (let [(cn (symText (headOf ps))) (bs (tailOf ps)) (ar (ctorArity g cn))]
            (cond
              ((not (allSyms bs)) (cons (str "ERR_BAD_PATTERN nested pattern under " cn) acc))
              ((< ar 0) (cons (str "ERR_UNKNOWN_SYMBOL constructor " cn) acc))
              ((not (= ar (listLength bs))) (cons (str "ERR_ARITY pattern " cn " binds " (listLength bs) " of " ar) acc))
              (else (resolveAll g (fold (fn [(s (List String)) (b Node)] -> (List String) (cons (symText b) s)) sc bs) (tailOf xs) acc)))))
        (_ (cons "ERR_BAD_PATTERN mt arm" acc))))
    (_ (cons "ERR_SYNTAX mt arm" acc)))

fn armCtor arm: Node -> String
  (mt arm ((nList xs) (mt (headOf xs) ((nList ps) (symText (headOf ps))) (_ ""))) (_ ""))

fn hasWild arms: (List Node) -> Bool
  (if (listEmpty? arms) false
    (if (mt (headOf arms) ((nList xs) (= (symText (headOf xs)) "_")) (_ false)) true (hasWild (tailOf arms))))

fn missingOf vs: (List String) covered: (List String) acc: (List String) -> (List String)
  (if (listEmpty? vs) (listReverse acc)
    (missingOf (tailOf vs) covered (if (inScope covered (headOf vs)) acc (cons (headOf vs) acc))))

fn resolveMt g: (List Def) sc: (List String) arms: (List Node) acc: (List String) -> (List String)
  (let [(acc2 (fold (fn [(a (List String)) (arm Node)] -> (List String) (resolveMtArm g sc arm a)) acc arms))]
    (if (or (hasWild arms) (listEmpty? arms)) acc2
      (let [(cn (armCtor (headOf arms)))
            (b (ctorBody g cn))
            (variants (if (or (= cn "ok") (= cn "err")) (list "ok" "err") (if (listEmpty? b) (list) (splitComma (nthStr b 3)))))
            (ename (if (or (= cn "ok") (= cn "err")) "Result" (if (listEmpty? b) "" (nthStr b 2))))
            (missing (missingOf variants (map (fn [(arm Node)] -> String (lastSeg (armCtor arm))) arms) (list)))]
        (if (listEmpty? missing) acc2 (cons (str "ERR_MATCH_NONEXHAUSTIVE mt over " ename " misses " (joinComma missing)) acc2)))))

fn resolveMatch g: (List Def) sc: (List String) arms: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? arms) acc
    (resolveMatch g sc (tailOf arms)
      (mt (headOf arms)
        ((nList xs) (mt (headOf xs)
                      ((nSym s) (if (or (= s "_") (or (= s "true") (= s "false"))) (resolveAll g sc (tailOf xs) acc) (cons (str "ERR_BAD_PATTERN match arm " s) acc)))
                      ((nList ys) (cons "ERR_BAD_PATTERN match arm is not a literal" acc))
                      ((nVec ys) (cons "ERR_BAD_PATTERN match arm is not a literal" acc))
                      (_ (resolveAll g sc (tailOf xs) acc))))
        (_ (cons "ERR_SYNTAX match arm" acc)))))

fn resolveDefs g: (List Def) ds: (List Def) acc: (List String) -> (List String)
  (if (listEmpty? ds) acc
    (let [(d (headOf ds))]
      (resolveDefs g (tailOf ds) (resolve g d.params d.body acc))))


schema Imp
  alias: String
  target: String

schema Mod
  path: String
  items: (List (List Node))
  exports: (List Node)
  imports: (List Imp)

schema Vis
  name: String
  key: String

schema MD
  mod: Mod
  defs: (List Def)
  tops: (List Node)

fn exists! p: String -> Bool
  (mt (realPath p) ((ok x) true) ((err e) false))

fn lastSlash s: String i: Int -> Int
  (if (< i 0) -1 (if (= (charAt s i) "/") i (lastSlash s (- i 1))))

fn firstSlash s: String i: Int -> Int
  (if (>= i (stringLength s)) -1 (if (= (charAt s i) "/") i (firstSlash s (+ i 1))))

fn parentDir p: String -> String
  (let [(i (lastSlash p (- (stringLength p) 1)))]
    (if (<= i 0) "/" (sliceOf p 0 i)))

fn lastSeg s: String -> String
  (let [(i (lastSlash s (- (stringLength s) 1)))]
    (if (< i 0) s (sliceOf s (+ i 1) (stringLength s))))

fn segmentsOk p: String -> Bool
  (let [(i (firstSlash p 0))
        (seg (if (< i 0) p (sliceOf p 0 i)))]
    (if (or (= seg "") (or (= seg ".") (= seg ".."))) false
      (if (< i 0) true (segmentsOk (sliceOf p (+ i 1) (stringLength p))))))

fn configDirs! dir: String nearest: String outer: String -> (List String)
  (let [(has (exists! (str dir "/.asl.config.asn")))
        (n2 (if (and has (= nearest "")) dir nearest))
        (o2 (if has dir outer))]
    (if (= dir "/") (list n2 o2) (configDirs! (parentDir dir) n2 o2)))

fn kwString xs: (List Node) kw: String -> String
  (if (or (listEmpty? xs) (listEmpty? (tailOf xs))) ""
    (mt (headOf xs)
      ((nKw k) (if (= k kw) (mt (headOf (tailOf xs)) ((nStr s) s) (_ "")) (kwString (tailOf xs) kw)))
      (_ (kwString (tailOf xs) kw))))

fn workspaceOf! dir: String -> String
  (mt (fileReadString (str dir "/.asl.config.asn"))
    ((err e) "")
    ((ok src) (mt (readItems src)
                ((err e) "")
                ((ok items) (if (listEmpty? items) ""
                              (mt (headOf (headOf items)) ((nList xs) (kwString xs "workspace")) (_ "")))))))

fn within! cand: String root: String p: String -> (Result String String)
  (mt (realPath cand)
    ((err e) (err p))
    ((ok real) (mt (realPath root)
                 ((err e) (err p))
                 ((ok rr) (if (or (= rr "/") (stringStartsWith? real (str rr "/"))) (ok real) (err p))))))

fn resolveImport! importer: String p: String -> (Result String String)
  (if (not (segmentsOk p)) (err p)
    (let [(dirs (configDirs! (parentDir importer) "" ""))
          (nearest (headOf dirs))
          (outer (headOf (tailOf dirs)))
          (i (firstSlash p 0))
          (first (if (< i 0) p (sliceOf p 0 i)))
          (rest (if (< i 0) "" (sliceOf p (+ i 1) (stringLength p))))]
      (cond
        ((= nearest "") (err p))
        ((= (workspaceOf! nearest) first) (within! (str nearest "/" rest ".asl") nearest p))
        ((exists! (str outer "/" p ".asl")) (within! (str outer "/" p ".asl") outer p))
        (else (within! (str outer "/" first "/src/" rest ".asl") outer p)))))

fn aliasOf xs: (List Node) -> String
  (if (or (listEmpty? xs) (listEmpty? (tailOf xs))) ""
    (mt (headOf xs)
      ((nKw k) (if (or (= k "a") (= k "as")) (symText (headOf (tailOf xs))) (aliasOf (tailOf xs))))
      (_ (aliasOf (tailOf xs)))))

fn importsOf! importer: String xs: (List Node) acc: (List Imp) -> (Result (List Imp) String)
  (if (listEmpty? xs) (ok (listReverse acc))
    (let [(p (mt (headOf xs) ((nSym s) s) ((nList ys) (symText (headOf ys))) (_ "")))
          (a (mt (headOf xs) ((nList ys) (aliasOf (tailOf ys))) (_ "")))]
      (if (= p "") (err "ERR_BAD_IMPORT import entry is not a module path")
        (mt (resolveImport! importer p)
          ((err e) (err (str "ERR_UNRESOLVED_IMPORT " e)))
          ((ok t) (importsOf! importer (tailOf xs) (cons (Imp :alias (if (= a "") (lastSeg p) a) :target t) acc)))))))

fn parseModule! path: String -> (Result Mod String)
  (mt (fileReadString path)
    ((err e) (err e))
    ((ok src)
      (mt (readItems src)
        ((err e) (err e))
        ((ok items)
          (if (listEmpty? items) (err "ERR_NO_ENTRY empty file")
            (let [(hdr (mt (headOf (headOf items)) ((nList xs) xs) (_ (list))))]
              (if (not (= (symText (headOf hdr)) "module"))
                (err "ERR_SYNTAX first item must be the module header")
                (mt (importsOf! path (headerField hdr "i") (list))
                  ((err e) (err e))
                  ((ok ims) (ok (Mod :path path :items (tailOf items) :exports (headerField hdr "x") :imports ims)))))))))))

fn hasMod ms: (List Mod) p: String -> Bool
  (if (listEmpty? ms) false (if (= (headOf ms).path p) true (hasMod (tailOf ms) p)))

fn findMod ms: (List Mod) p: String -> Mod
  (if (= (headOf ms).path p) (headOf ms) (findMod (tailOf ms) p))

fn loadMods! queue: (List String) ms: (List Mod) -> (Result (List Mod) String)
  (if (listEmpty? queue) (ok (listReverse ms))
    (let [(path (headOf queue))]
      (if (hasMod ms path) (loadMods! (tailOf queue) ms)
        (mt (parseModule! path)
          ((err e) (err e))
          ((ok m) (loadMods! (fold (fn [(q (List String)) (im Imp)] -> (List String) (cons im.target q)) (tailOf queue) m.imports) (cons m ms)))))))

fn keyOf path: String nm: String -> String
  (str path "#" nm)

fn ownDefs ms: (List Mod) acc: (List MD) -> (Result (List MD) String)
  (if (listEmpty? ms) (ok (listReverse acc))
    (mt (collectItems (headOf ms).items (list) (list))
      ((err e) (err e))
      ((ok its) (ownDefs (tailOf ms) (cons (MD :mod (headOf ms) :defs its.defs :tops its.tops) acc)))))

fn findMD mds: (List MD) p: String -> MD
  (if (= (headOf mds).mod.path p) (headOf mds) (findMD (tailOf mds) p))

fn visOf mds: (List MD) md: MD -> (List Vis)
  (let [(own (map (fn [(d Def)] -> Vis (Vis :name d.name :key (keyOf md.mod.path d.name))) md.defs))]
    (fold (fn [(acc (List Vis)) (im Imp)] -> (List Vis)
            (let [(t (findMD mds im.target))]
              (fold (fn [(a (List Vis)) (x Node)] -> (List Vis)
                      (let [(nm (symText x))]
                        (mt (findDef t.defs nm)
                          ((ok d) (cons (Vis :name (str im.alias "/" nm) :key (keyOf t.mod.path nm)) a))
                          ((err e) a))))
                    acc t.mod.exports)))
          own md.mod.imports))

fn visKey vis: (List Vis) s: String -> String
  (if (listEmpty? vis) "" (if (= (headOf vis).name s) (headOf vis).key (visKey (tailOf vis) s)))

fn defByKey mds: (List MD) key: String -> Def
  (let [(md (findMD mds (sliceOf key 0 (lastHash key (- (stringLength key) 1)))))]
    (mt (findDef md.defs (sliceOf key (+ (lastHash key (- (stringLength key) 1)) 1) (stringLength key)))
      ((ok d) d)
      ((err e) (headOf md.defs))))

fn lastHash s: String i: Int -> Int
  (if (< i 0) -1 (if (= (charAt s i) "#") i (lastHash s (- i 1))))

fn rwAll vis: (List Vis) sc: (List String) xs: (List Node) -> (List Node)
  (map (fn [(y Node)] -> Node (rw vis sc y)) xs)

fn rwLet vis: (List Vis) sc: (List String) bs: (List Node) acc: (List Node) body: (List Node) -> Node
  (if (listEmpty? bs)
    (nList (cons (nSym "let") (cons (nVec (listReverse acc)) (rwAll vis sc body))))
    (mt (headOf bs)
      ((nList pair)
        (let [(nm (symText (headOf pair)))]
          (rwLet vis (cons nm sc) (tailOf bs) (cons (nList (list (headOf pair) (rw vis sc (headOf (tailOf pair))))) acc) body)))
      (_ (rwLet vis sc (tailOf bs) (cons (headOf bs) acc) body))))

fn rwArmBody vis: (List Vis) sc: (List String) a: Node -> Node
  (mt a ((nList ys) (nList (cons (headOf ys) (rwAll vis sc (tailOf ys))))) (_ a))

fn rwMtArm vis: (List Vis) sc: (List String) a: Node -> Node
  (mt a
    ((nList ys)
      (mt (headOf ys)
        ((nList ps) (nList (cons (nList (cons (rw vis sc (headOf ps)) (tailOf ps)))
                                 (rwAll vis (fold (fn [(s (List String)) (b Node)] -> (List String) (cons (symText b) s)) sc (tailOf ps)) (tailOf ys)))))
        (_ (rwArmBody vis sc a))))
    (_ a))

fn rw vis: (List Vis) sc: (List String) x: Node -> Node
  (mt x
    ((nSym s) (if (inScope sc s) x (let [(k (visKey vis s))] (if (= k "") x (nSym k)))))
    ((nVec xs) (nVec (rwAll vis sc xs)))
    ((nList xs)
      (if (listEmpty? xs) x
        (let [(form (symText (headOf xs)))]
          (cond
            ((= form "let") (mt (headOf (tailOf xs)) ((nVec bs) (rwLet vis sc bs (list) (tailOf (tailOf xs)))) (_ x)))
            ((= form "fn") (mt (headOf (tailOf xs))
                             ((nVec ps) (nList (list (headOf xs) (headOf (tailOf xs))
                                                 (rw vis (fold (fn [(s (List String)) (p String)] -> (List String) (cons p s)) sc (paramNames ps (list))) (lastNode xs)))))
                             (_ x)))
            ((= form "mt") (nList (cons (headOf xs) (cons (rw vis sc (headOf (tailOf xs))) (map (fn [(a Node)] -> Node (rwMtArm vis sc a)) (tailOf (tailOf xs)))))))
            ((= form "match") (nList (cons (headOf xs) (cons (rw vis sc (headOf (tailOf xs))) (map (fn [(a Node)] -> Node (rwArmBody vis sc a)) (tailOf (tailOf xs)))))))
            (else (nList (rwAll vis sc xs)))))))
    (_ x))

fn linkMods mds: (List MD) rest: (List MD) entry: String acc: (List Def) -> (Result (List Def) String)
  (if (listEmpty? rest) (ok acc)
    (let [(md (headOf rest))
          (vis (visOf mds md))
          (visDefs (map (fn [(v Vis)] -> Def (let [(d (defByKey mds v.key))] (Def :name v.name :params d.params :body d.body))) vis))
          (errs (resolveAll visDefs (list) md.tops (resolveDefs visDefs md.defs (list))))
          (path md.mod.path)]
      (if (not (listEmpty? errs)) (err (str (headOf (listReverse errs)) " in " path))
        (let [(keyed (map (fn [(d Def)] -> Def (Def :name (keyOf path d.name) :params d.params :body (rw vis d.params d.body))) md.defs))
              (bare (if (= path entry) (map (fn [(d Def)] -> Def (Def :name (symTail d.name) :params d.params :body d.body)) keyed) (list)))]
          (linkMods mds (tailOf rest) entry (fold (fn [(a (List Def)) (d Def)] -> (List Def) (cons d a)) acc (fold (fn [(a (List Def)) (d Def)] -> (List Def) (cons d a)) keyed bare)))))))

fn symTail key: String -> String
  (sliceOf key (+ (lastHash key (- (stringLength key) 1)) 1) (stringLength key))


fn symText x: Node -> String
  (mt x ((nSym s) s) (_ ""))

fn fnParams xs: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? (tailOf xs)) (listReverse acc)
    (let [(s (symText (headOf xs)))]
      (cond
        ((= s "->") (listReverse acc))
        ((and (> (stringLength s) 1) (= (charAt s (- (stringLength s) 1)) ":"))
          (fnParams (tailOf (tailOf xs)) (cons (sliceOf s 0 (- (stringLength s) 1)) acc)))
        (else (fnParams (tailOf xs) acc)))))

fn headerField xs: (List Node) kw: String -> (List Node)
  (if (listEmpty? xs) (list)
    (mt (headOf xs)
      ((nKw k) (if (and (= k kw) (not (listEmpty? (tailOf xs))))
                 (mt (headOf (tailOf xs)) ((nVec v) v) (_ (list)))
                 (headerField (tailOf xs) kw)))
      (_ (headerField (tailOf xs) kw))))

schema Items
  defs: (List Def)
  tops: (List Node)

fn fnDef it: (List Node) -> Def
  (Def :name (symText (headOf (tailOf it))) :params (fnParams (tailOf (tailOf it)) (list)) :body (lastNode it))

fn isColonSym x: Node -> Bool
  (let [(s (symText x))] (and (> (stringLength s) 1) (= (charAt s (- (stringLength s) 1)) ":")))

fn fieldNames xs: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? xs) (listReverse acc)
    (if (isColonSym (headOf xs))
      (fieldNames (if (listEmpty? (tailOf xs)) (list) (tailOf (tailOf xs))) (cons (sliceOf (symText (headOf xs)) 0 (- (stringLength (symText (headOf xs))) 1)) acc))
      (fieldNames (tailOf xs) acc)))

fn listFields xs: (List Node) acc: (List String) -> (List String)
  (if (listEmpty? xs) (listReverse acc)
    (listFields (tailOf xs)
      (mt (headOf xs)
        ((nList ys) (mt (headOf ys) ((nKw k) (if (and (= k "f") (not (listEmpty? (tailOf ys)))) (cons (symText (headOf (tailOf ys))) acc) acc)) (_ acc)))
        (_ acc))))

fn genParams i: Int k: Int acc: (List String) -> (List String)
  (if (>= i k) (listReverse acc) (genParams (+ i 1) k (cons (str "p" i) acc)))

fn symNodes ps: (List String) -> (List Node)
  (map (fn [(p String)] -> Node (nSym p)) ps)

fn schemaDef nm: String fields: (List String) -> Def
  (let [(ps (genParams 0 (* 2 (listLength fields)) (list)))]
    (Def :name nm :params ps :body (nList (cons (nSym "%rec") (cons (nStr nm) (cons (nStr (joinComma fields)) (symNodes ps)))))))

fn variantName v: Node -> String
  (mt v ((nList xs) (symText (headOf xs))) ((nSym s) s) (_ ""))

fn enumDefs ename: String vs: (List Node) acc: (List Def) -> (List Def)
  (let [(names (joinComma (map (fn [(v Node)] -> String (variantName v)) vs)))]
    (fold (fn [(a (List Def)) (v Node)] -> (List Def)
            (let [(ps (mt v ((nList xs) (fieldNames (tailOf xs) (list))) (_ (list))))]
              (cons (Def :name (variantName v) :params ps :body (nList (cons (nSym "%ctor") (cons (nStr (variantName v)) (cons (nStr ename) (cons (nStr names) (symNodes ps))))))) a)))
          acc vs))

fn unsupported what: String -> (Result Items String)
  (err (str "ERR_UNSUPPORTED_TOPLEVEL " what))

fn collectItems items: (List (List Node)) defs: (List Def) tops: (List Node) -> (Result Items String)
  (if (listEmpty? items) (ok (Items :defs defs :tops (listReverse tops)))
    (let [(it (headOf items)) (h (headOf it)) (head (symText h)) (single (listEmpty? (tailOf it))) (more (tailOf items))]
      (cond
        ((and (= head "fn") (not single)) (collectItems more (cons (fnDef it) defs) tops))
        ((and (= head "schema") (not single)) (collectItems more (cons (schemaDef (symText (headOf (tailOf it))) (fieldNames (tailOf (tailOf it)) (list))) defs) tops))
        ((and (= head "enum") (not single)) (collectItems more (enumDefs (symText (headOf (tailOf it))) (tailOf (tailOf it)) defs) tops))
        ((not single) (unsupported (str "top-level item starting with " (render (nodeHead it)))))
        (else
          (mt h
            ((nSym x) (unsupported (str "top-level item starting with " x)))
            ((nList xs)
              (let [(lh (if (listEmpty? xs) "" (symText (headOf xs))))]
                (cond
                  ((and (= lh "schema") (not (listEmpty? (tailOf xs))))
                    (collectItems more (cons (schemaDef (symText (headOf (tailOf xs))) (listFields (tailOf (tailOf xs)) (list))) defs) tops))
                  ((or (= lh "def") (or (= lh "defun") (or (= lh "df") (or (= lh "fn") (= lh "enum"))))) (unsupported (str "list-form (" lh " ...) at top level")))
                  (else (collectItems more defs (cons h tops))))))
            (_ (collectItems more defs (cons h tops))))))))

fn nodeHead it: (List Node) -> V
  (mt (headOf it) ((nSym s) (vStr s)) ((nList xs) (vStr "(...)")) ((nVec xs) (vStr "[...]")) (_ (vStr "literal")))

fn isExported xs: (List Node) nm: String -> Bool
  (if (listEmpty? xs) false (if (= (symText (headOf xs)) nm) true (isExported (tailOf xs) nm)))

fn renderSafe v: V -> String
  (if (tooDeep v) (str "<value nested deeper than " (dataLimit) ">") (render v))

fn failLine path: String msg: String n: Int -> (Result Int String)
  (err (str "FAIL " path ": " msg " (after " n " asserts)"))

fn runEntry! path: String g: (List Def) exports: (List Node) n0: Int -> (Result Int String)
  (let [(useTests (and (isExported exports "runTests") (not (isErr (mt (findDef g "runTests") ((ok d) (vUnit)) ((err x) (vErr x)))))))
        (useMain (and (isExported exports "main") (not (isErr (mt (findDef g "main") ((ok d) (vUnit)) ((err x) (vErr x)))))))]
    (cond
      (useTests
        (let [(o (callEntry! g "runTests" (list) n0))]
          (mt o.v
            ((vBool b) (if b (finish! path o.n) (failLine path "ERR_TEST_FAILED runTests returned false, not true" o.n)))
            ((vErr m) (failLine path m o.n))
            (_ (failLine path (str "ERR_TEST_FAILED runTests returned " (renderSafe o.v) ", not true") o.n)))))
      (useMain
        (let [(arity (mt (findDef g "main") ((ok d) (listLength d.params)) ((err x) 0)))
              (o (callEntry! g "main" (if (= arity 1) (list (vList (list))) (list)) n0))]
          (mt o.v
            ((vCtor c as) (if (= c "ok") (finish! path o.n) (failLine path (str "ERR_TEST_FAILED main returned " (renderSafe o.v) ", not (ok ...)") o.n)))
            ((vErr m) (failLine path m o.n))
            (_ (failLine path (str "ERR_TEST_FAILED main returned " (renderSafe o.v) ", not (ok ...)") o.n)))))
      (else (failLine path "ERR_NO_ENTRY exports neither runTests nor main" n0))))

fn finish! path: String n: Int -> (Result Int String)
  (if (> n 0)
    (do (println (str path ": " n " assertion(s) executed (" n " passed)")) (ok 0))
    (failLine path "ERR_TEST_FAILED zero assertions executed" 0))

schema Prog
  defs: (List Def)
  exports: (List Node)
  tops: (List Node)

schema Walk
  seen: (List String)
  order: (List String)

fn walk mds: (List MD) path: String w: Walk -> Walk
  (if (inScope w.seen path) w
    (let [(md (findMD mds path))
          (w2 (fold (fn [(acc Walk) (im Imp)] -> Walk (walk mds im.target acc)) (with w :seen (cons path w.seen)) md.mod.imports))]
      (Walk :seen w2.seen :order (cons path w2.order))))

fn orderedTops mds: (List MD) entry: String -> (List Node)
  (let [(order (listReverse (walk mds entry (Walk :seen (list) :order (list))).order))]
    (listReverse
      (fold (fn [(acc (List Node)) (path String)] -> (List Node)
              (let [(md (findMD mds path)) (vis (visOf mds md))]
                (fold (fn [(a (List Node)) (t Node)] -> (List Node) (cons (rw vis (list) t) a)) acc md.tops)))
            (list) order)))

fn runTops! g: (List Def) tops: (List Node) n: Int -> Out
  (if (listEmpty? tops) (Out :v (vUnit) :n n)
    (let [(o (ev! g (list) (headOf tops) (list) 0 n))]
      (if (isErr o.v) o (runTops! g (tailOf tops) o.n))))

fn loadFile! path: String -> (Result Prog String)
  (mt (realPath path)
    ((err e) (err e))
    ((ok real)
      (mt (loadMods! (list real) (list))
        ((err e) (err e))
        ((ok ms)
          (mt (ownDefs ms (list))
            ((err e) (err e))
            ((ok mds) (mt (linkMods mds mds real (list))
                        ((err e) (err e))
                        ((ok g) (ok (Prog :defs g :exports (findMod ms real).exports :tops (orderedTops mds real)))))))))))

fn testFile! path: String -> (Result Int String)
  (mt (loadFile! path)
    ((err e) (failLine path e 0))
    ((ok p) (let [(o (runTops! p.defs p.tops 0))]
              (mt o.v ((vErr m) (failLine path m o.n)) (_ (runEntry! path p.defs p.exports o.n))))))

fn checkFile! path: String -> (Result Int String)
  (mt (loadFile! path)
    ((err e) (err (str e "\ncheck failed: " path ": 1 error(s)")))
    ((ok p) (do (println (str "ok " path ": 1 module(s) checked")) (ok 0))))

fn evalSource! src: String -> (Result Int String)
  (mt (readItems src)
    ((err e) (err e))
    ((ok items)
      (let [(forms (listReverse (fold (fn [(acc (List Node)) (it (List Node))] -> (List Node) (fold (fn [(a (List Node)) (x Node)] -> (List Node) (cons x a)) acc it)) (list) items)))]
        (if (listEmpty? forms) (err "ERR_SYNTAX empty expression")
          (if (not (listEmpty? (resolveAll (list) (list) forms (list)))) (err (headOf (listReverse (resolveAll (list) (list) forms (list)))))
          (let [(o (evSeq! (list) (list) forms (list) 0 0))]
            (mt o.v
              ((vErr m) (err m))
              (_ (if (tooDeep o.v) (err (render (depthErr))) (do (println (render o.v)) (ok 0)))))))))))

fn ! main args: (List String) -> (Result Int String)
  (if (< (listLength args) 2)
    (err "usage: main.asl eval EXPR | test FILE | check FILE")
    (let [(cmd (headOf args)) (arg (headOf (tailOf args)))]
      (cond
        ((= cmd "eval") (evalSource! arg))
        ((= cmd "test") (testFile! arg))
        ((= cmd "check") (checkFile! arg))
        (else (err (str "ERR_UNSUPPORTED_SUBCOMMAND " cmd))))))
