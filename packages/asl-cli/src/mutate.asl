(module asl-cli/mutate
  :x [Mutant opNames knownOp? bodyOf mutantsIn mutantsOf applyMutant siteOf lineAt mutantCopyName mutantCopyPid]
  :i [(asl-syntax/asl/paren :a paren) (asl-syntax/core/tree :a tr)])

; (:m :ref TEST-MUTATE :do "one single-site change of a function body: the byte span start..end of the source is replaced by text; op names the operator, from and to what the site read before and after; order sorts mutants by site offset, then operator, then variant")
(schema Mutant (:f start Int64) (:f end Int64) (:f text String) (:f op String) (:f from String) (:f to String) (:f order Int64))

fn opNames -> (List String)
  (list "cmpFlip" "argSwap" "logicFlip" "notDrop" "ifConst" "intShift" "floatPerturb" "boolFlip")

fn knownOp? op: String -> Bool
  (listContains? (opNames) op)

fn opIndex op: String -> Int64
  (fold (fn [(acc Int64) (p (Pair Int64 String))] -> Int64 (if (= (pairSecond p) op) (pairFirst p) acc)) 0 (enumerate (opNames)))

fn slice text: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice text a b) "")

fn textOf text: String e: tr/TreeElement -> String
  (slice text (tr/elementStart e) (tr/elementEnd e))

fn delimKind? k: String -> Bool
  (listContains? (list "lparen" "rparen" "lbracket" "rbracket" "lbrace" "rbrace") k)

fn item? e: tr/TreeElement -> Bool
  (match e
    ((tr/elemToken t) (not (or (tr/isTrivia t) (delimKind? t.kind))))
    ((tr/elemNode _) true))

fn items n: tr/Node -> (List tr/TreeElement)
  (filter item? n.children)

fn tokenKindOf e: tr/TreeElement -> String
  (match e ((tr/elemToken t) t.kind) ((tr/elemNode _) ""))

fn lineStart? text: String e: tr/TreeElement -> Bool
  (let [(s (tr/elementStart e))]
    (or (= s 0) (= (slice text (- s 1) s) "\n")))

fn fnNameAfter text: String xs: (List tr/TreeElement) -> String
  (match (listHead xs)
    ((none) "")
    ((some e) (let [(t (textOf text e))] (if (= t "!") (fnNameAfter text (listDrop xs 1)) t))))

fn defAfter text: String forms: (List tr/TreeElement) name: String -> (Option (List tr/TreeElement))
  (match (listHead forms)
    ((none) (none))
    ((some e) (let [(rest (listDrop forms 1))]
                (if (and (lineStart? text e) (and (= (textOf text e) "fn") (= (fnNameAfter text rest) name)))
                  (some rest)
                  (defAfter text rest name)))))

fn afterArrow text: String xs: (List tr/TreeElement) -> (Option (List tr/TreeElement))
  (match (listHead xs)
    ((none) (none))
    ((some e) (cond
                ((lineStart? text e) (none))
                ((= (textOf text e) "->") (some (listDrop xs 2)))
                (else (afterArrow text (listDrop xs 1))))))

fn takeBody text: String xs: (List tr/TreeElement) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some e) (if (lineStart? text e) (listReverse acc) (takeBody text (listDrop xs 1) (cons e acc)))))

; (:m :ref TEST-MUTATE :do "the body of top-level fn name, read from the lossless paren tree of asl-syntax: the forms after the return type that follows ->, up to the next form at the start of a line (the next definition or comment); the parameters and the return type are never mutated")
fn bodyOf text: String name: String -> (Result (List tr/TreeElement) String)
  (let [(forms (filter item? (paren/parseString text).children))]
    (match (defAfter text forms name)
      ((none) (err (str "no top-level fn " name)))
      ((some rest) (match (afterArrow text rest)
                     ((none) (err (str "fn " name " has no -> return type in its header")))
                     ((some xs) (ok (takeBody text xs (list))))))))

fn oneLine s: String -> String
  (let [(flat (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace s "\n" " ") "\t" " ") " ")) " "))]
    (if (> (stringLength flat) 60) (str (slice flat 0 57) "...") flat))

fn mk start: Int64 end: Int64 text: String op: String from: String to: String variant: Int64 -> Mutant
  (Mutant :start start :end end :text text :op op :from (oneLine from) :to (oneLine to) :order (+ (* start 64) (+ (* (opIndex op) 4) variant)))

fn cmpPartner h: String -> String
  (cond ((= h "<") "<=") ((= h "<=") "<") ((= h ">") ">=") ((= h ">=") ">") ((= h "=") "!=") ((= h "!=") "=") (else ""))

fn swapHead? h: String -> Bool
  (listContains? (list "-" "/" "<" ">" "str" "stringConcat" "listAppend") h)

fn sameShape? a: tr/TreeElement b: tr/TreeElement -> Bool
  (match a
    ((tr/elemToken _) (match b ((tr/elemToken _) true) ((tr/elemNode _) false)))
    ((tr/elemNode _) (match b ((tr/elemToken _) false) ((tr/elemNode _) true))))

fn el xs: (List tr/TreeElement) i: Int64 -> tr/TreeElement
  (optionOr (listGet xs i) (tr/elemToken (tr/makeToken "" 0 0)))

fn listMutants text: String n: tr/Node -> (List Mutant)
  (let [(xs (items n))
        (k (listLength xs))
        (hd (el xs 0))
        (h (if (and (> k 0) (= (tokenKindOf hd) "symbol")) (textOf text hd) ""))
        (whole (slice text n.start n.end))
        (cmp (if (stringEmpty? (cmpPartner h)) (list) (list (mk (tr/elementStart hd) (tr/elementEnd hd) (cmpPartner h) "cmpFlip" h (cmpPartner h) 0))))
        (a (el xs 1))
        (b (el xs 2))
        (swapped (str (textOf text b) (slice text (tr/elementEnd a) (tr/elementStart b)) (textOf text a)))
        (swap (if (and (swapHead? h) (and (= k 3) (and (sameShape? a b) (!= (textOf text a) (textOf text b)))))
                (list (mk (tr/elementStart a) (tr/elementEnd b) swapped "argSwap" whole (str (slice text n.start (tr/elementStart a)) swapped (slice text (tr/elementEnd b) n.end)) 0))
                (list)))
        (logic (cond ((= h "and") (list (mk (tr/elementStart hd) (tr/elementEnd hd) "or" "logicFlip" "and" "or" 0)))
                     ((= h "or") (list (mk (tr/elementStart hd) (tr/elementEnd hd) "and" "logicFlip" "or" "and" 0)))
                     (else (list))))
        (notD (if (and (= h "not") (= k 2)) (list (mk n.start n.end (textOf text a) "notDrop" whole (textOf text a) 0)) (list)))
        (cond0 (textOf text a))
        (ifC (if (and (= h "if") (>= k 3))
               (filter (fn [(m Mutant)] -> Bool (!= m.text cond0))
                       (list (mk (tr/elementStart a) (tr/elementEnd a) "true" "ifConst" cond0 "true" 0)
                             (mk (tr/elementStart a) (tr/elementEnd a) "false" "ifConst" cond0 "false" 1)))
               (list)))]
    (if (!= n.kind "list") (list) (listAppend cmp (listAppend swap (listAppend logic (listAppend notD ifC))))))

fn floatText f: Float64 -> String
  (let [(s (stringFromFloat64 f))]
    (if (or (stringContains? s ".") (or (stringContains? s "e") (or (stringContains? s "n") (stringContains? s "i")))) s (str s ".0")))

fn tokenMutants text: String t: tr/Token head: Bool -> (List Mutant)
  (let [(raw (slice text t.start t.end))]
    (cond
      ((= t.kind "int")
        (match (stringToInt64 raw)
          ((some v) (list (mk t.start t.end (stringFromInt64 (+ v 1)) "intShift" raw (stringFromInt64 (+ v 1)) 0)
                          (mk t.start t.end (stringFromInt64 (- v 1)) "intShift" raw (stringFromInt64 (- v 1)) 1)))
          ((none) (list))))
      ((= t.kind "float")
        (match (stringToFloat64 raw)
          ((some f) (if (= f 0.0)
                      (list (mk t.start t.end "1.0" "floatPerturb" raw "1.0" 0))
                      (list (mk t.start t.end (floatText (* f 2.0)) "floatPerturb" raw (floatText (* f 2.0)) 0)
                            (mk t.start t.end "0.0" "floatPerturb" raw "0.0" 1))))
          ((none) (list))))
      ((and (= t.kind "symbol") (and (not head) (= raw "true"))) (list (mk t.start t.end "false" "boolFlip" "true" "false" 0)))
      ((and (= t.kind "symbol") (and (not head) (= raw "false"))) (list (mk t.start t.end "true" "boolFlip" "false" "true" 0)))
      (else (list))))

fn walkKids text: String n: tr/Node acc: (List Mutant) -> (List Mutant)
  (fold (fn [(a (List Mutant)) (p (Pair Int64 tr/TreeElement))] -> (List Mutant) (walk text (pairSecond p) (and (= n.kind "list") (= (pairFirst p) 0)) a))
        acc (enumerate (items n)))

fn walk text: String e: tr/TreeElement head: Bool acc: (List Mutant) -> (List Mutant)
  (match e
    ((tr/elemToken t) (listAppend (tokenMutants text t head) acc))
    ((tr/elemNode n) (walkKids text n (listAppend (listMutants text n) acc))))

; (:m :ref TEST-MUTATE :do "every single-site mutant of the body forms, in source order of the replaced span, then operator order (opNames), then variant: comparison flips, operand swaps of - / < > and two-argument str stringConcat listAppend of the same shape, and/or flips, a dropped not, an if condition fixed to true and false, an integer literal plus and minus one, a float doubled and zeroed (a zero becomes 1.0), a boolean literal flipped; ops keeps the named operators, an empty list all of them")
fn mutantsIn text: String body: (List tr/TreeElement) ops: (List String) -> (List Mutant)
  (filter (fn [(m Mutant)] -> Bool (or (listEmpty? ops) (listContains? ops m.op)))
          (listSortBy (fn [(m Mutant)] -> Int64 m.order)
                      (fold (fn [(acc (List Mutant)) (e tr/TreeElement)] -> (List Mutant) (walk text e false acc)) (list) body)))

fn mutantsOf text: String name: String ops: (List String) -> (Result (List Mutant) String)
  (match (bodyOf text name)
    ((err e) (err e))
    ((ok body) (ok (mutantsIn text body ops))))

fn applyMutant text: String m: Mutant -> String
  (str (slice text 0 m.start) m.text (slice text m.end (stringLength text)))

; (:m :ref TEST-MUTATE :do "line:column of a byte offset, both from 1, the column in bytes")
fn siteOf text: String offset: Int64 -> String
  (let [(lines (stringSplit (slice text 0 offset) "\n"))]
    (str (stringFromInt64 (listLength lines)) ":" (stringFromInt64 (+ 1 (stringLength (optionOr (listLast lines) ""))))))

fn lineAt text: String offset: Int64 -> String
  (let [(before (listLength (stringSplit (slice text 0 offset) "\n")))]
    (stringTrim (optionOr (listGet (stringSplit text "\n") (- before 1)) "")))

; (:m :ref TEST-MUTATE :do "the hidden copy of mutant n beside its file, .STEM.mut.PID.N.asl: a dot file is no suite and is not indexed as a module, and the pid lets a later run remove the copies of a dead one")
fn mutantCopyName base: String pid: Int64 n: Int64 -> String
  (let [(stem (if (stringEndsWith? base ".asl") (slice base 0 (- (stringLength base) 4)) base))]
    (str "." stem ".mut." (stringFromInt64 pid) "." (stringFromInt64 n) ".asl"))

fn mutantCopyPid name: String -> (Option Int64)
  (let [(parts (stringSplit name "."))
        (n (listLength parts))]
    (if (and (stringStartsWith? name ".") (and (>= n 6) (and (= (listGet parts (- n 1)) (some "asl")) (= (listGet parts (- n 4)) (some "mut")))))
      (stringToInt64 (optionOr (listGet parts (- n 3)) ""))
      (none)))
