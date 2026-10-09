(module asl-grammar/sample
  :x [grammarSample ruleHeights]
  :i [(asl-grammar/asn :a asn) (asl-grammar/peg :a peg)])

(schema Gen
  (:f text String)
  (:f seed Int64))

fn nextSeed s: Int64 -> Int64
  (mod (+ (* s 1103515245) 12345) 2147483648)

fn pick s: Int64 n: Int64 -> Int64
  (if (<= n 0) 0 (mod (/ (nextSeed s) 65536) n))

fn formOf e: asn/Sx -> (Pair String (List asn/Sx))
  (mt e
    ((asn/sxList items) (mt (listHead items)
                          ((some h) (mt h
                                      ((asn/sxSym op) (pair op (optionOr (listTail items) (list))))
                                      (_ (pair "" (list)))))
                          ((none) (pair "" (list)))))
    (_ (pair "" (list))))

fn heightOf hs: (List (Pair String Int64)) name: String -> Int64
  (mt (listHead (filter (fn [(h (Pair String Int64))] -> Bool (= (pairFirst h) name)) hs))
    ((some h) (pairSecond h))
    ((none) 1000000))

fn repCount args: (List asn/Sx) i: Int64 -> Int64
  (mt (listGet args i)
    ((some x) (mt x ((asn/sxInt k) k) (_ 0)))
    ((none) 0))

fn exprHeight hs: (List (Pair String Int64)) e: asn/Sx -> Int64
  (mt e
    ((asn/sxSym name) (+ (heightOf hs name) 1))
    ((asn/sxList _)
      (let [(f (formOf e)) (op (pairFirst f)) (args (pairSecond f))]
        (cond
          ((= op "seq") (fold (fn [(m Int64) (x asn/Sx)] -> Int64 (max m (exprHeight hs x))) 0 args))
          ((= op "alt") (fold (fn [(m Int64) (x asn/Sx)] -> Int64 (min m (exprHeight hs x))) 1000000 args))
          ((or (= op "plus") (= op "except")) (exprHeight hs (optionOr (listHead args) (asn/sxStr ""))))
          ((= op "rep") (if (> (repCount args 1) 0) (exprHeight hs (optionOr (listHead args) (asn/sxStr ""))) 0))
          (else 0))))
    (_ 0))

fn heightRounds rules: (List peg/GrammarRule) hs: (List (Pair String Int64)) k: Int64 -> (List (Pair String Int64))
  (if (<= k 0)
    hs
    (heightRounds rules (map (fn [(r peg/GrammarRule)] -> (Pair String Int64) (pair r.name (exprHeight hs r.expr))) rules) (- k 1)))

fn ruleHeights g: peg/Grammar -> (List (Pair String Int64))
  (let [(rules g.rules)]
    (heightRounds rules (map (fn [(r peg/GrammarRule)] -> (Pair String Int64) (pair r.name 1000000)) rules) (+ (listLength rules) 1)))

fn printableChar c: Int64 -> String
  (optionOr (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- c 32) (- c 31)) "")

fn classChoice spec: String negate: Bool s: Int64 -> String
  (let [(table (peg/classTable spec negate))
        (members (filter (fn [(c Int64)] -> Bool (= (bytesGet table c) 49)) (range 32 127)))]
    (mt (listGet members (pick s (listLength members)))
      ((some c) (printableChar c))
      ((none) (if (= (bytesGet table 10) 49) "\n" ""))))

fn ruleBody rules: (List peg/GrammarRule) name: String -> asn/Sx
  (mt (listHead (filter (fn [(r peg/GrammarRule)] -> Bool (= r.name name)) rules))
    ((some r) r.expr)
    ((none) (asn/sxStr "")))

fn shallowest hs: (List (Pair String Int64)) args: (List asn/Sx) -> asn/Sx
  (fold (fn [(best asn/Sx) (x asn/Sx)] -> asn/Sx (if (< (exprHeight hs x) (exprHeight hs best)) x best))
        (optionOr (listHead args) (asn/sxStr "")) args)

fn repeatDerive rules: (List peg/GrammarRule) hs: (List (Pair String Int64)) budget: Int64 depth: Int64 e: asn/Sx k: Int64 st: Gen -> Gen
  (if (<= k 0) st (repeatDerive rules hs budget depth e (- k 1) (derive rules hs budget depth e st)))

fn exceptDerive rules: (List peg/GrammarRule) hs: (List (Pair String Int64)) budget: Int64 depth: Int64 body: asn/Sx words: (List String) tries: Int64 st: Gen -> Gen
  (let [(fresh (derive rules hs budget depth body (with st :text "")))]
    (cond
      ((not (listContains? words fresh.text)) (Gen :text (str st.text fresh.text) :seed fresh.seed))
      ((> tries 0) (exceptDerive rules hs budget depth body words (- tries 1) (with st :seed (nextSeed fresh.seed))))
      (else (Gen :text (str st.text fresh.text "x") :seed fresh.seed))))

fn derive rules: (List peg/GrammarRule) hs: (List (Pair String Int64)) budget: Int64 depth: Int64 e: asn/Sx st: Gen -> Gen
  (mt e
    ((asn/sxStr s) (with st :text (str st.text s)))
    ((asn/sxSym name) (derive rules hs budget (+ depth 1) (ruleBody rules name) st))
    ((asn/sxList _)
      (let [(f (formOf e)) (op (pairFirst f)) (args (pairSecond f)) (over (> depth budget)) (s st.seed) (next (with st :seed (nextSeed s)))]
        (cond
          ((= op "seq") (fold (fn [(acc Gen) (x asn/Sx)] -> Gen (derive rules hs budget depth x acc)) st args))
          ((= op "alt") (derive rules hs budget depth (if over (shallowest hs args) (optionOr (listGet args (pick s (listLength args))) (asn/sxStr ""))) next))
          ((= op "star") (repeatDerive rules hs budget depth (optionOr (listHead args) (asn/sxStr "")) (if over 0 (pick s 3)) next))
          ((= op "plus") (repeatDerive rules hs budget depth (optionOr (listHead args) (asn/sxStr "")) (if over 1 (+ 1 (pick s 2))) next))
          ((= op "rep") (let [(least (repCount args 1))]
                          (repeatDerive rules hs budget depth (optionOr (listHead args) (asn/sxStr "")) (if over least (+ least (pick s (+ (min (- (repCount args 2) least) 2) 1)))) next)))
          ((= op "opt") (repeatDerive rules hs budget depth (optionOr (listHead args) (asn/sxStr "")) (if over 0 (pick s 2)) next))
          ((= op "word") (mt (listHead args) ((some w) (derive rules hs budget depth w st)) ((none) st)))
          ((= op "cls") (mt (listHead args) ((some a) (mt a ((asn/sxStr spec) (Gen :text (str st.text (classChoice spec false s)) :seed (nextSeed s))) (_ st))) ((none) st)))
          ((= op "ncls") (mt (listHead args) ((some a) (mt a ((asn/sxStr spec) (Gen :text (str st.text (classChoice spec true s)) :seed (nextSeed s))) (_ st))) ((none) st)))
          ((= op "except") (exceptDerive rules hs budget depth (optionOr (listHead args) (asn/sxStr ""))
                             (fold (fn [(acc (List String)) (x asn/Sx)] -> (List String) (mt x ((asn/sxStr w) (cons w acc)) (_ acc))) (list) (optionOr (listTail args) (list)))
                             10 st))
          (else st))))
    (_ st))

fn sampleLoop rules: (List peg/GrammarRule) hs: (List (Pair String Int64)) start: String budget: Int64 k: Int64 seed: Int64 acc: (List String) -> (List String)
  (if (<= k 0)
    (listReverse acc)
    (let [(r (derive rules hs budget 0 (asn/sxSym start) (Gen :text "" :seed seed)))]
      (sampleLoop rules hs start budget (- k 1) (nextSeed r.seed) (cons r.text acc))))

fn grammarSample g: peg/Grammar start: String seed: Int64 count: Int64 budget: Int64 -> (List String)
  (sampleLoop g.rules (ruleHeights g) start budget count seed (list))
