(module asl-grammar/gbnf
  :x [grammarGbnf grammarGbnfFrom gbnfRuleName main]
  :i [(asl-grammar/asn :a asn) (asl-grammar/peg :a peg)])

fn textSlice text: String start: Int64 end: Int64 -> String
  (optionOr (stringSlice text start end) "")

fn printable -> String
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

fn charText c: Int64 -> String
  (textSlice (printable) (- c 32) (- c 31))

fn hexByte c: Int64 -> String
  (let [(digits "0123456789ABCDEF")]
    (str "\\x" (textSlice digits (/ c 16) (+ (/ c 16) 1)) (textSlice digits (mod c 16) (+ (mod c 16) 1))))

fn alnum? c: Int64 -> Bool
  (or (and (>= c 48) (<= c 57)) (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122))))

fn literalChar c: Int64 -> String
  (cond
    ((= c 10) "\\n")
    ((= c 13) "\\r")
    ((= c 9) "\\t")
    ((or (= c 34) (= c 92)) (str "\\" (charText c)))
    ((and (>= c 32) (<= c 126)) (charText c))
    (else (hexByte c)))

fn classChar c: Int64 -> String
  (if (alnum? c) (charText c) (hexByte c))

fn ascii? bs: Bytes -> Bool
  (listAll? (fn [(i Int64)] -> Bool (< (bytesGet bs i) 128)) (range 0 (bytesLength bs)))

fn gbnfLiteral s: String -> (Result String String)
  (let [(bs (stringToBytes s))]
    (if (ascii? bs)
      (ok (str "\"" (stringJoin (map (fn [(i Int64)] -> String (literalChar (bytesGet bs i))) (range 0 (bytesLength bs))) "") "\""))
      (err (str "literal " s " is not ASCII"))))

fn gbnfClass spec: String negate: Bool -> (Result String String)
  (if (ascii? (stringToBytes spec))
    (ok (str (if negate "[^" "[")
             (stringJoin (map (fn [(r (Pair Int64 Int64))] -> String
                                (if (= (pairFirst r) (pairSecond r)) (classChar (pairFirst r)) (str (classChar (pairFirst r)) "-" (classChar (pairSecond r)))))
                              (peg/classRanges spec)) "")
             "]"))
    (err (str "class " spec " is not ASCII")))

fn gbnfRuleName name: String -> String
  (stringJoin (map (fn [(c String)] -> String (if (= c (stringLower c)) c (str "-" (stringLower c)))) (stringChars name)) "")

fn gbnfAll xs: (List asn/Sx) acc: (List String) -> (Result (List String) String)
  (mt (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (mt (gbnfExpr x)
                ((err e) (err e))
                ((ok s) (gbnfAll (optionOr (listTail xs) (list)) (if (= s "") acc (cons s acc)))))))

fn gbnfForm op: String args: (List asn/Sx) -> (Result String String)
  (cond
    ((or (= op "not") (or (= op "and") (= op "end"))) (ok ""))
    ((= op "rep") (gbnfRep args))
    ((or (= op "word") (or (= op "cls") (= op "ncls")))
      (mt (listHead args)
        ((some a) (mt a
                    ((asn/sxStr s) (cond ((= op "word") (gbnfLiteral s)) ((= op "cls") (gbnfClass s false)) (else (gbnfClass s true))))
                    (_ (err (str "(" op " ...) takes a string")))))
        ((none) (err (str "(" op " ...) takes a string")))))
    (else (mt (gbnfAll args (list))
            ((err e) (err e))
            ((ok parts) (cond
                          ((listEmpty? parts) (err (str "(" op " ...) has nothing GBNF can express")))
                          ((= op "seq") (ok (stringJoin parts " ")))
                          ((= op "alt") (ok (str "(" (stringJoin parts " | ") ")")))
                          ((= op "star") (ok (str "(" (stringJoin parts " ") ")*")))
                          ((= op "plus") (ok (str "(" (stringJoin parts " ") ")+")))
                          ((= op "opt") (ok (str "(" (stringJoin parts " ") ")?")))
                          (else (err (str "unknown grammar form " op))))))))

fn gbnfRep args: (List asn/Sx) -> (Result String String)
  (mt (listGet args 1)
    ((some a) (mt (listGet args 2)
                ((some b) (mt a
                            ((asn/sxInt least) (mt b
                                                 ((asn/sxInt most) (mt (gbnfExpr (optionOr (listHead args) (asn/sxList (list))))
                                                                     ((err e) (err e))
                                                                     ((ok body) (if (= body "")
                                                                                  (err "(rep ...) has nothing GBNF can express")
                                                                                  (ok (str "(" body "){" least "," most "}"))))))
                                                 (_ (err "(rep e least most) takes counts"))))
                            (_ (err "(rep e least most) takes counts"))))
                ((none) (err "(rep e least most) takes counts"))))
    ((none) (err "(rep e least most) takes counts")))

fn gbnfExpr e: asn/Sx -> (Result String String)
  (mt e
    ((asn/sxStr s) (gbnfLiteral s))
    ((asn/sxSym name) (ok (gbnfRuleName name)))
    ((asn/sxList items)
      (mt (listHead items)
        ((some h) (mt h
                    ((asn/sxSym op) (gbnfForm op (optionOr (listTail items) (list))))
                    (_ (err "a grammar form starts with a symbol"))))
        ((none) (err "empty grammar form"))))
    (_ (err "a grammar expression is a string, a rule name or a form")))

fn runsOf members: (List Int64) -> (List (Pair Int64 Int64))
  (listReverse (fold (fn [(acc (List (Pair Int64 Int64))) (c Int64)] -> (List (Pair Int64 Int64))
                       (mt (listHead acc)
                         ((some r) (if (= (+ (pairSecond r) 1) c) (cons (pair (pairFirst r) c) (optionOr (listTail acc) (list))) (cons (pair c c) acc)))
                         ((none) (list (pair c c)))))
                     (list) members))

fn runText r: (Pair Int64 Int64) -> String
  (cond
    ((= (pairFirst r) (pairSecond r)) (classChar (pairFirst r)))
    ((= (+ (pairFirst r) 1) (pairSecond r)) (str (classChar (pairFirst r)) (classChar (pairSecond r))))
    (else (str (classChar (pairFirst r)) "-" (classChar (pairSecond r)))))

fn tableClass table: Bytes negate: Bool -> String
  (let [(members (filter (fn [(c Int64)] -> Bool (= (bytesGet table c) 49)) (range 0 128)))]
    (str "[" (if negate "^" "") (stringJoin (map runText (runsOf members)) "") "]"))

fn tableMinus table: Bytes cs: (List Int64) -> Bytes
  (stringToBytes (stringJoin (map (fn [(c Int64)] -> String (if (and (= (bytesGet table c) 49) (not (listContains? cs c))) "1" "0")) (range 0 256)) ""))

fn tableEmpty? table: Bytes -> Bool
  (not (listAny? (fn [(c Int64)] -> Bool (= (bytesGet table c) 49)) (range 0 256)))

fn ruleExpr rules: (List peg/GrammarRule) name: String -> (Option asn/Sx)
  (mt (listHead (filter (fn [(r peg/GrammarRule)] -> Bool (= r.name name)) rules))
    ((some r) (some r.expr))
    ((none) (none)))

fn clsSpec e: asn/Sx -> (Option String)
  (mt e
    ((asn/sxList items) (if (= (listLength items) 2)
                          (mt (listGet items 0)
                            ((some h) (mt h
                                        ((asn/sxSym op) (if (= op "cls") (mt (listGet items 1) ((some s) (mt s ((asn/sxStr x) (some x)) (_ (none)))) ((none) (none))) (none)))
                                        (_ (none))))
                            ((none) (none)))
                          (none)))
    (_ (none)))

fn formArgs e: asn/Sx op: String -> (Option (List asn/Sx))
  (mt e
    ((asn/sxList items) (mt (listHead items)
                          ((some h) (mt h
                                      ((asn/sxSym o) (if (= o op) (some (optionOr (listTail items) (list))) (none)))
                                      (_ (none))))
                          ((none) (none))))
    (_ (none)))

fn restShape e: asn/Sx -> (Option (Pair String Int64))
  (mt (formArgs e "star")
    ((some inner) (mt (clsSpec (optionOr (listHead inner) e))
                    ((some b) (some (pair b -1)))
                    ((none) (none))))
    ((none) (mt (formArgs e "rep")
              ((some inner) (mt (clsSpec (optionOr (listHead inner) e))
                              ((some b) (mt (listGet inner 1)
                                          ((some lo) (mt lo
                                                       ((asn/sxInt least) (mt (listGet inner 2)
                                                                            ((some hi) (mt hi ((asn/sxInt most) (if (= least 0) (some (pair b most)) (none))) (_ (none))))
                                                                            ((none) (none))))
                                                       (_ (none))))
                                          ((none) (none))))
                              ((none) (none))))
              ((none) (none)))))

fn wordShape rules: (List peg/GrammarRule) e: asn/Sx -> (Option (Pair String (Pair String Int64)))
  (mt e
    ((asn/sxSym name) (mt (ruleExpr rules name)
                        ((some body) (mt (formArgs body "seq")
                                       ((some parts) (if (= (listLength parts) 2)
                                                       (mt (clsSpec (optionOr (listGet parts 0) e))
                                                         ((some a) (mt (restShape (optionOr (listGet parts 1) e))
                                                                     ((some b) (some (pair a b)))
                                                                     ((none) (none))))
                                                         ((none) (none)))
                                                       (none)))
                                       ((none) (none))))
                        ((none) (none))))
    (_ (none)))

fn exceptWordList xs: (List asn/Sx) -> (List String)
  (fold (fn [(acc (List String)) (x asn/Sx)] -> (List String) (mt x ((asn/sxStr s) (listAppend acc (list s))) (_ acc))) (list) xs)

fn prefixesOf words: (List String) -> (List String)
  (fold (fn [(acc (List String)) (w String)] -> (List String)
          (fold (fn [(a (List String)) (k Int64)] -> (List String)
                  (let [(p (textSlice w 0 k))] (if (listContains? a p) a (listAppend a (list p)))))
                acc (range 0 (+ (stringLength w) 1))))
        (list) words)

fn childBytes words: (List String) p: String -> (List Int64)
  (fold (fn [(acc (List Int64)) (w String)] -> (List Int64)
          (if (and (> (stringLength w) (stringLength p)) (stringStartsWith? w p))
            (let [(c (bytesGet (stringToBytes w) (stringLength p)))] (if (listContains? acc c) acc (listAppend acc (list c))))
            acc))
        (list) words)

fn trieNodeName base: String prefixes: (List String) p: String -> String
  (str base "-" (optionOr (listIndexOf prefixes p) 0))

fn trieLine base: String words: (List String) prefixes: (List String) first: Bytes rest: Bytes most: Int64 p: String -> String
  (let [(cs (childBytes words p))
        (other (tableMinus (if (= p "") first rest) cs))
        (left (- most (stringLength p)))
        (tail (cond ((< most 0) "*") ((> left 0) (str "{0," left "}")) (else "")))
        (otherAlt (if (or (tableEmpty? other) (and (>= most 0) (< left 0))) (list) (list (str (tableClass other false) (if (= tail "") "" (str " " (tableClass rest false) tail))))))
        (childAlts (map (fn [(c Int64)] -> String (str "\"" (literalChar c) "\" " (trieNodeName base prefixes (str p (charText c))))) cs))
        (body (str "(" (stringJoin (listAppend otherAlt childAlts) " | ") ")"))]
    (str (trieNodeName base prefixes p) " ::= " (if (or (= p "") (listContains? words p)) body (str body "?"))))

fn exceptLines rules: (List peg/GrammarRule) name: String args: (List asn/Sx) -> (Result (List String) String)
  (mt (wordShape rules (optionOr (listHead args) (asn/sxList (list))))
    ((none) (err (str "rule " name ": GBNF needs (except r ...) with r a (seq (cls A) (star (cls B))) or (seq (cls A) (rep (cls B) 0 n)) rule")))
    ((some shape) (let [(ab (pair (pairFirst shape) (pairFirst (pairSecond shape))))
                        (most (pairSecond (pairSecond shape)))
                        (words (exceptWordList (optionOr (listTail args) (list))))
                        (base (gbnfRuleName name))
                        (prefixes (prefixesOf words))
                        (first (peg/classTable (pairFirst ab) false))
                        (rest (peg/classTable (pairSecond ab) false))]
                    (ok (cons (str base " ::= " (trieNodeName base prefixes ""))
                              (map (fn [(p String)] -> String (trieLine base words prefixes first rest most p)) prefixes))))))

fn ruleLines rules: (List peg/GrammarRule) r: peg/GrammarRule -> (Result (List String) String)
  (mt (formArgs r.expr "except")
    ((some args) (exceptLines rules r.name args))
    ((none) (mt (gbnfExpr r.expr)
              ((err e) (err (str "rule " r.name ": " e)))
              ((ok body) (ok (list (str (gbnfRuleName r.name) " ::= " body)))))))

fn gbnfRules rules: (List peg/GrammarRule) todo: (List peg/GrammarRule) acc: (List String) -> (Result (List String) String)
  (mt (listHead todo)
    ((none) (ok acc))
    ((some r) (mt (ruleLines rules r)
                ((err e) (err e))
                ((ok lines) (gbnfRules rules (optionOr (listTail todo) (list)) (listAppend acc lines))))))

fn grammarGbnfFrom g: peg/Grammar start: String -> (Result String String)
  (let [(names (peg/grammarReachable g start))
        (rules (filter (fn [(r peg/GrammarRule)] -> Bool (listContains? names r.name)) g.rules))]
    (mt (gbnfRules g.rules rules (list))
      ((err e) (err e))
      ((ok lines) (ok (str "# generated by asl-grammar/gbnf from grammar " g.name ", start " start "; lookahead dropped, so this accepts a superset of the recognizer\n"
                           "root ::= " (gbnfRuleName start) "\n"
                           (stringJoin lines "\n") "\n")))))

fn grammarGbnf g: peg/Grammar -> (Result String String)
  (grammarGbnfFrom g g.start)

fn ! writeGbnf! g: peg/Grammar start: String path: String -> (Result String String)
  (mt (grammarGbnfFrom g start)
    ((err e) (err e))
    ((ok text) (mt (fileWrite path text)
                 ((err _) (err (str "cannot write " path)))
                 ((ok _) (ok path)))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(path (optionOr (listHead args) "asl/grammar/aslGrammar.asn"))
        (dir (optionOr (listGet args 1) (str (optionOr (envGet "HOME") ".") "/.asl/run/grammar")))
        (made (dirCreate dir))]
    (mt made
      ((err _) (err (str "cannot create " dir)))
      ((ok _) (mt (peg/grammarLoad! path)
        ((err e) (err e))
        ((ok g) (mt (writeGbnf! g g.start (str dir "/hostExact.gbnf"))
                  ((err e) (err e))
                  ((ok a) (mt (writeGbnf! g "genFile" (str dir "/generation.gbnf"))
                            ((err e) (err e))
                            ((ok b) (do (println (str "(:gbnf :hostExact \"" a "\" :generation \"" b "\")")) (ok 0)))))))))))
