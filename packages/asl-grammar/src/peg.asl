(module asl-grammar/peg
  :x [Pe RuleTree GrammarRule Grammar grammarParse grammarLoad! grammarBuild grammarRecognize grammarAccepts? grammarRuleNames grammarDisable grammarRemove grammarWithStart grammarReachable grammarSalvage exprRefs classRanges classTable]
  :i [(asl-grammar/asn :a asn)])

(enum Pe
  (:c peCat [(first Pe) (rest Pe)] "first, then rest from where it stopped.")
  (:c peOr [(first Pe) (rest Pe)] "first, or rest from the same place when first fails.")
  (:c peEmpty [] "Matches nothing and succeeds.")
  (:c peFail [] "Always fails.")
  (:c peStar [(body Pe)] "Zero or more, greedy.")
  (:c pePlus [(body Pe)] "One or more, greedy.")
  (:c peOpt [(body Pe)] "Zero or one.")
  (:c peNot [(body Pe)] "Succeeds without consuming when body fails.")
  (:c peAnd [(body Pe)] "Succeeds without consuming when body matches.")
  (:c peLit [(bytes Bytes)] "These bytes exactly.")
  (:c peClass [(table Bytes)] "One byte whose slot in the 256-byte table is 49.")
  (:c peRef [(index Int64)] "The body of a recursive rule, looked up at match time.")
  (:c peEnd [] "The end of the input.")
  (:c peExcept [(body Pe) (words (List Bytes))] "body, unless the bytes it matched are one of words.")
  (:c peRep [(body Pe) (least Int64) (most Int64)] "least to most times, greedy."))

(enum RuleTree
  (:c ruleLeaf [] "No rule.")
  (:c ruleNode [(left RuleTree) (index Int64) (body Pe) (right RuleTree)] "A search tree of compiled recursive rules by index."))

(schema GrammarRule
  (:f name String)
  (:f expr asn/Sx)
  (:f doc String))

(schema Grammar
  (:f name String)
  (:f start String)
  (:f boundary String)
  (:f rules (List GrammarRule))
  (:f table RuleTree)
  (:f entry Pe))

(schema Ctx
  (:f rules (List GrammarRule))
  (:f names (List String))
  (:f recursive (List Bool))
  (:f boundary String))

fn ruleNamed rules: (List GrammarRule) name: String -> (Option GrammarRule)
  (mt (listHead (filter (fn [(r GrammarRule)] -> Bool (= r.name name)) rules))
    ((some r) (some r))
    ((none) (none)))

fn exprRefs e: asn/Sx -> (List String)
  (mt e
    ((asn/sxSym s) (list s))
    ((asn/sxList items)
      (mt (listHead items)
        ((some h) (mt h
                    ((asn/sxSym op) (if (or (= op "word") (or (= op "cls") (or (= op "ncls") (= op "end"))))
                                      (list)
                                      (fold (fn [(acc (List String)) (x asn/Sx)] -> (List String) (listAppend acc (exprRefs x))) (list) (optionOr (listTail items) (list)))))
                    (_ (list))))
        ((none) (list))))
    (_ (list)))

fn ruleRefs rules: (List GrammarRule) name: String -> (List String)
  (mt (ruleNamed rules name)
    ((some r) (exprRefs r.expr))
    ((none) (list)))

fn reaches? rules: (List GrammarRule) todo: (List String) seen: (List String) target: String -> Bool
  (mt (listHead todo)
    ((none) false)
    ((some r) (let [(rest (optionOr (listTail todo) (list)))]
                (cond
                  ((= r target) true)
                  ((listContains? seen r) (reaches? rules rest seen target))
                  (else (reaches? rules (listAppend (ruleRefs rules r) rest) (cons r seen) target))))))

fn tailrec classRangesFrom bs: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (cond
    ((>= i n) acc)
    ((and (< (+ i 2) n) (= (bytesGet bs (+ i 1)) 45)) (classRangesFrom bs n (+ i 3) (cons (pair (bytesGet bs i) (bytesGet bs (+ i 2))) acc)))
    (else (classRangesFrom bs n (+ i 1) (cons (pair (bytesGet bs i) (bytesGet bs i)) acc))))

fn classRanges spec: String -> (List (Pair Int64 Int64))
  (let [(bs (stringToBytes spec))]
    (listReverse (classRangesFrom bs (bytesLength bs) 0 (list))))

fn inRanges? ranges: (List (Pair Int64 Int64)) c: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (and (>= c (pairFirst r)) (<= c (pairSecond r)))) ranges)

fn classTable spec: String negate: Bool -> Bytes
  (let [(ranges (classRanges spec))]
    (stringToBytes (stringJoin (map (fn [(c Int64)] -> String (if (= (inRanges? ranges c) negate) "0" "1")) (range 0 256)) "")))

fn joinPes parts: (List Pe) isSeq: Bool -> Pe
  (mt (listHead parts)
    ((none) (if isSeq (peEmpty) (peFail)))
    ((some p) (let [(rest (optionOr (listTail parts) (list)))]
                (if (listEmpty? rest) p (if isSeq (peCat p (joinPes rest true)) (peOr p (joinPes rest false)))))))

fn compileAll ctx: Ctx xs: (List asn/Sx) acc: (List Pe) -> (Result (List Pe) String)
  (mt (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (mt (compileExpr ctx x)
                ((err e) (err e))
                ((ok p) (compileAll ctx (optionOr (listTail xs) (list)) (cons p acc))))))

fn compileOne ctx: Ctx op: String args: (List asn/Sx) -> (Result Pe String)
  (if (!= (listLength args) 1)
    (err (str "(" op " ...) takes one argument"))
    (mt (compileExpr ctx (optionOr (listHead args) (asn/sxList (list))))
      ((err e) (err e))
      ((ok p) (ok (cond
                    ((= op "star") (peStar p))
                    ((= op "plus") (pePlus p))
                    ((= op "opt") (peOpt p))
                    ((= op "not") (peNot p))
                    (else (peAnd p)))))))

fn compileText ctx: Ctx op: String args: (List asn/Sx) -> (Result Pe String)
  (mt (listHead args)
    ((some a) (mt a
                ((asn/sxStr s)
                  (cond
                    ((!= (listLength args) 1) (err (str "(" op " \"...\") takes one string")))
                    ((= op "cls") (ok (peClass (classTable s false))))
                    ((= op "ncls") (ok (peClass (classTable s true))))
                    (else (mt (compileExpr ctx (asn/sxSym ctx.boundary))
                            ((err e) (err e))
                            ((ok b) (ok (peCat (peLit (stringToBytes s)) (peNot b))))))))
                (_ (err (str "(" op " ...) takes a string")))))
    ((none) (err (str "(" op " ...) takes a string"))))

fn exceptWords xs: (List asn/Sx) acc: (List Bytes) -> (Option (List Bytes))
  (mt (listHead xs)
    ((none) (some (listReverse acc)))
    ((some x) (mt x
                ((asn/sxStr s) (exceptWords (optionOr (listTail xs) (list)) (cons (stringToBytes s) acc)))
                (_ (none)))))

fn compileExcept ctx: Ctx args: (List asn/Sx) -> (Result Pe String)
  (mt (exceptWords (optionOr (listTail args) (list)) (list))
    ((none) (err "(except e \"word\" ...) takes strings after the expression"))
    ((some ws) (if (listEmpty? ws)
                 (err "(except e \"word\" ...) needs at least one word")
                 (mt (compileExpr ctx (optionOr (listHead args) (asn/sxList (list))))
                   ((err e) (err e))
                   ((ok b) (ok (peExcept b ws)))))))

fn sxCount x: (Option asn/Sx) -> (Option Int64)
  (mt x
    ((some v) (mt v ((asn/sxInt k) (if (>= k 0) (some k) (none))) (_ (none))))
    ((none) (none)))

fn compileRep ctx: Ctx args: (List asn/Sx) -> (Result Pe String)
  (mt (sxCount (listGet args 1))
    ((none) (err "(rep e least most) takes two counts 0 or more"))
    ((some least) (mt (sxCount (listGet args 2))
                    ((none) (err "(rep e least most) takes two counts 0 or more"))
                    ((some most) (cond
                                   ((!= (listLength args) 3) (err "(rep e least most) takes three arguments"))
                                   ((or (< most least) (= most 0)) (err "(rep e least most) needs 0 < most and least <= most"))
                                   (else (mt (compileExpr ctx (optionOr (listHead args) (asn/sxList (list))))
                                           ((err e) (err e))
                                           ((ok b) (ok (peRep b least most))))))))))

fn compileForm ctx: Ctx op: String args: (List asn/Sx) -> (Result Pe String)
  (cond
    ((= op "rep") (compileRep ctx args))
    ((or (= op "seq") (= op "alt")) (mt (compileAll ctx args (list)) ((err e) (err e)) ((ok ps) (ok (joinPes ps (= op "seq"))))))
    ((or (= op "star") (or (= op "plus") (or (= op "opt") (or (= op "not") (= op "and"))))) (compileOne ctx op args))
    ((or (= op "word") (or (= op "cls") (= op "ncls"))) (compileText ctx op args))
    ((= op "except") (compileExcept ctx args))
    ((= op "end") (if (listEmpty? args) (ok (peEnd)) (err "(end) takes no arguments")))
    (else (err (str "unknown grammar form " op))))

fn compileRef ctx: Ctx name: String -> (Result Pe String)
  (mt (listIndexOf ctx.names name)
    ((none) (err (str "unknown rule " name)))
    ((some i) (if (optionOr (listGet ctx.recursive i) false)
                (ok (peRef i))
                (mt (ruleNamed ctx.rules name)
                  ((some r) (compileExpr ctx r.expr))
                  ((none) (err (str "unknown rule " name)))))))

fn compileExpr ctx: Ctx e: asn/Sx -> (Result Pe String)
  (mt e
    ((asn/sxStr s) (ok (peLit (stringToBytes s))))
    ((asn/sxSym name) (compileRef ctx name))
    ((asn/sxList items)
      (mt (listHead items)
        ((some h) (mt h
                    ((asn/sxSym op) (compileForm ctx op (optionOr (listTail items) (list))))
                    (_ (err "a grammar form starts with a symbol"))))
        ((none) (err "empty grammar form"))))
    (_ (err "a grammar expression is a string, a rule name or a form")))

fn buildTree entries: (List (Pair Int64 Pe)) -> RuleTree
  (let [(n (listLength entries))]
    (if (= n 0)
      (ruleLeaf)
      (let [(mid (/ n 2))]
        (mt (listGet entries mid)
          ((some e) (ruleNode (buildTree (listTake entries mid)) (pairFirst e) (pairSecond e) (buildTree (listDrop entries (+ mid 1)))))
          ((none) (ruleLeaf))))))

fn compileRecursive ctx: Ctx i: Int64 acc: (List (Pair Int64 Pe)) -> (Result (List (Pair Int64 Pe)) String)
  (mt (listGet ctx.rules i)
    ((none) (ok (listReverse acc)))
    ((some r) (if (optionOr (listGet ctx.recursive i) false)
                (mt (compileExpr ctx r.expr)
                  ((err e) (err (str "rule " r.name ": " e)))
                  ((ok p) (compileRecursive ctx (+ i 1) (cons (pair i p) acc))))
                (compileRecursive ctx (+ i 1) acc))))

fn duplicateName names: (List String) -> (Option String)
  (mt (listHead names)
    ((none) (none))
    ((some n) (let [(rest (optionOr (listTail names) (list)))]
                (if (listContains? rest n) (some n) (duplicateName rest)))))

fn grammarBuild name: String start: String boundary: String rules: (List GrammarRule) -> (Result Grammar String)
  (let [(names (map (fn [(r GrammarRule)] -> String r.name) rules))
        (recursive (map (fn [(r GrammarRule)] -> Bool (reaches? rules (exprRefs r.expr) (list) r.name)) rules))
        (ctx (Ctx :rules rules :names names :recursive recursive :boundary boundary))]
    (mt (duplicateName names)
      ((some d) (err (str "duplicate rule " d)))
      ((none) (mt (compileRecursive ctx 0 (list))
                ((err e) (err e))
                ((ok entries) (mt (compileExpr ctx (asn/sxSym start))
                                ((err e) (err (str "start rule " start ": " e)))
                                ((ok entry) (ok (Grammar :name name :start start :boundary boundary :rules rules :table (buildTree entries) :entry entry)))))))))

fn sxKwIs? x: (Option asn/Sx) key: String -> Bool
  (mt x
    ((some v) (mt v ((asn/sxKw k) (= k key)) (_ false)))
    ((none) false))

fn sxSymName x: (Option asn/Sx) -> (Option String)
  (mt x
    ((some v) (mt v ((asn/sxSym s) (some s)) (_ (none))))
    ((none) (none)))

fn ruleFromSx x: asn/Sx -> (Result GrammarRule String)
  (mt x
    ((asn/sxList items)
      (cond
        ((not (sxKwIs? (listGet items 0) "rule")) (err "a rule form starts with :rule"))
        (else (mt (sxSymName (listGet items 1))
                ((none) (err "a rule name is a symbol"))
                ((some name) (mt (listGet items 2)
                               ((none) (err (str "rule " name " has no body")))
                               ((some e) (ok (GrammarRule :name name :expr e :doc (optionOr (asn/asnKeyString (listDrop items 3) "d") ""))))))))))
    (_ (err "a rule is a (:rule name expr :d doc) form")))

fn rulesFromSx xs: (List asn/Sx) acc: (List GrammarRule) -> (Result (List GrammarRule) String)
  (mt (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (mt (ruleFromSx x)
                ((err e) (err (str "rule " (+ (listLength acc) 1) ": " e)))
                ((ok r) (rulesFromSx (optionOr (listTail xs) (list)) (cons r acc))))))

fn grammarParse text: String -> (Result Grammar String)
  (mt (asn/asnReadAll text)
    ((err e) (err e))
    ((ok forms) (mt (listHead forms)
                  ((none) (err "empty grammar file"))
                  ((some f) (mt f
                              ((asn/sxList items)
                                (cond
                                  ((not (sxKwIs? (listHead items) "grammar")) (err "a grammar file is one (:grammar ...) form"))
                                  (else (mt (asn/asnKeyValue items "rules")
                                          ((some rv) (mt rv
                                                       ((asn/sxVec rs) (mt (rulesFromSx rs (list))
                                                                         ((err e) (err e))
                                                                         ((ok rules) (grammarBuild (optionOr (asn/asnKeyString items "name") "")
                                                                                       (optionOr (asn/asnKeyString items "start") "")
                                                                                       (optionOr (asn/asnKeyString items "wordBoundary") "")
                                                                                       rules))))
                                                       (_ (err ":rules is a vector"))))
                                          ((none) (err "grammar without :rules"))))))
                              (_ (err "a grammar file is one (:grammar ...) form")))))))

fn ! grammarLoad! path: String -> (Result Grammar String)
  (mt (fileReadString path)
    ((err e) (err (str path ": " e)))
    ((ok text) (mt (grammarParse text)
                 ((err e) (err (str path ": " e)))
                 ((ok g) (ok g)))))

fn ruleAt t: RuleTree i: Int64 -> Pe
  (mt t
    ((ruleLeaf) (peFail))
    ((ruleNode l k b r) (cond ((= i k) b) ((< i k) (ruleAt l i)) (else (ruleAt r i)))))

fn tailrec litAt bs: Bytes n: Int64 p: Int64 far: Int64 lb: Bytes i: Int64 m: Int64 -> Int64
  (cond
    ((>= i m) (hit (+ p i) far))
    ((>= (+ p i) n) (miss (max far (+ p i))))
    ((= (bytesGet bs (+ p i)) (bytesGet lb i)) (litAt bs n p far lb (+ i 1) m))
    (else (miss (max far (+ p i)))))

fn farUnit -> Int64
  4294967296

fn endOf r: Int64 -> Int64
  (mod r (farUnit))

fn farOf r: Int64 -> Int64
  (if (< r 0) (- -1 r) (/ r (farUnit)))

fn hit pos: Int64 far: Int64 -> Int64
  (+ (* far (farUnit)) pos)

fn miss far: Int64 -> Int64
  (- -1 far)

fn tailrec starAt t: RuleTree bs: Bytes n: Int64 p: Int64 far: Int64 b: Pe -> Int64
  (let [(q (pm t bs n p far b))]
    (if (< q 0)
      (hit p (farOf q))
      (if (= (endOf q) p) (hit p (farOf q)) (starAt t bs n (endOf q) (farOf q) b))))

fn tailrec repAt t: RuleTree bs: Bytes n: Int64 p: Int64 far: Int64 b: Pe k: Int64 least: Int64 most: Int64 -> Int64
  (if (>= k most)
    (hit p far)
    (let [(q (pm t bs n p far b))]
      (if (or (< q 0) (= (endOf q) p))
        (if (>= k least) (hit p (farOf q)) (miss (farOf q)))
        (repAt t bs n (endOf q) (farOf q) b (+ k 1) least most))))

fn pm t: RuleTree bs: Bytes n: Int64 p: Int64 far: Int64 e: Pe -> Int64
  (mt e
    ((peClass tb) (if (< p n) (if (= (bytesGet tb (bytesGet bs p)) 49) (hit (+ p 1) far) (miss (max far p))) (miss (max far p))))
    ((peCat a b) (let [(q (pm t bs n p far a))] (if (< q 0) q (pm t bs n (endOf q) (farOf q) b))))
    ((peOr a b) (let [(q (pm t bs n p far a))] (if (< q 0) (pm t bs n p (farOf q) b) q)))
    ((peStar b) (starAt t bs n p far b))
    ((pePlus b) (let [(q (pm t bs n p far b))] (if (< q 0) q (starAt t bs n (endOf q) (farOf q) b))))
    ((peOpt b) (let [(q (pm t bs n p far b))] (if (< q 0) (hit p (farOf q)) q)))
    ((peNot b) (if (< (pm t bs n p 0 b) 0) (hit p far) (miss (max far p))))
    ((peAnd b) (if (< (pm t bs n p 0 b) 0) (miss (max far p)) (hit p far)))
    ((peLit lb) (litAt bs n p far lb 0 (bytesLength lb)))
    ((peRef i) (pm t bs n p far (ruleAt t i)))
    ((peEmpty) (hit p far))
    ((peFail) (miss (max far p)))
    ((peExcept b ws) (let [(q (pm t bs n p far b))] (if (< q 0) q (if (matchedWord? bs p (endOf q) ws) (miss (max far p)) q))))
    ((peRep b least most) (repAt t bs n p far b 0 least most))
    ((peEnd) (if (= p n) (hit p far) (miss (max far p)))))

fn tailrec sameBytes? bs: Bytes p: Int64 w: Bytes i: Int64 m: Int64 -> Bool
  (if (>= i m) true (if (= (bytesGet bs (+ p i)) (bytesGet w i)) (sameBytes? bs p w (+ i 1) m) false))

fn matchedWord? bs: Bytes p: Int64 q: Int64 ws: (List Bytes) -> Bool
  (listAny? (fn [(w Bytes)] -> Bool (if (= (bytesLength w) (- q p)) (sameBytes? bs p w 0 (- q p)) false)) ws)

fn tailrec lineCol bs: Bytes i: Int64 at: Int64 line: Int64 col: Int64 -> (Pair Int64 Int64)
  (if (>= i at)
    (pair line col)
    (if (= (bytesGet bs i) 10) (lineCol bs (+ i 1) at (+ line 1) 1) (lineCol bs (+ i 1) at line (+ col 1))))

fn grammarRecognize g: Grammar text: String -> (Result Int64 String)
  (let [(bs (stringToBytes text)) (n (bytesLength bs)) (q (pm g.table bs n 0 0 g.entry))]
    (if (>= q 0)
      (ok (endOf q))
      (let [(at (farOf q)) (lc (lineCol bs 0 (if (> at n) n at) 1 1))]
        (err (str (pairFirst lc) ":" (pairSecond lc))))))

fn grammarAccepts? g: Grammar text: String -> Bool
  (ok? (grammarRecognize g text))

fn grammarRuleNames g: Grammar -> (List String)
  (map (fn [(r GrammarRule)] -> String r.name) g.rules)

fn grammarDisable g: Grammar name: String -> (Result Grammar String)
  (grammarBuild g.name g.start g.boundary
    (map (fn [(r GrammarRule)] -> GrammarRule (if (= r.name name) (GrammarRule :name name :expr (asn/sxList (list (asn/sxSym "alt"))) :doc r.doc) r)) g.rules))

fn grammarRemove g: Grammar name: String -> (Result Grammar String)
  (grammarBuild g.name g.start g.boundary (filter (fn [(r GrammarRule)] -> Bool (!= r.name name)) g.rules))

fn grammarWithStart g: Grammar start: String -> (Result Grammar String)
  (grammarBuild g.name start g.boundary g.rules)

fn grammarReachable g: Grammar start: String -> (List String)
  (let [(seen (reachFrom g.rules (list start) (list)))]
    (cons start (filter (fn [(n String)] -> Bool (and (!= n start) (listContains? seen n))) (grammarRuleNames g))))

fn reachFrom rules: (List GrammarRule) todo: (List String) seen: (List String) -> (List String)
  (mt (listHead todo)
    ((none) seen)
    ((some r) (let [(rest (optionOr (listTail todo) (list)))]
                (if (listContains? seen r)
                  (reachFrom rules rest seen)
                  (reachFrom rules (listAppend (ruleRefs rules r) rest) (cons r seen))))))

fn tailrec salvageFrom g: Grammar text: String bs: Bytes i: Int64 -> (Option String)
  (cond
    ((< i 0) (none))
    ((and (= (bytesGet bs i) 10) (not (listContains? (list 10 32 9) (bytesGet bs (+ i 1)))))
      (let [(cut (optionOr (stringSlice text 0 (+ i 1)) ""))]
        (if (grammarAccepts? g cut) (some cut) (salvageFrom g text bs (- i 1)))))
    (else (salvageFrom g text bs (- i 1))))

fn grammarSalvage g: Grammar text: String -> (Option String)
  (if (grammarAccepts? g text)
    (some text)
    (let [(bs (stringToBytes text))]
      (salvageFrom g text bs (- (bytesLength bs) 2))))
