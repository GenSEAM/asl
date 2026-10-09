(module asl-regex/regex
  :x [Match Regex regex-compile! regex-compile-flags! regex-search! regex-match-full! regex-find-all! regex-replace-all! regex-group regex-match?]
  :i [])

schema Match {
  start: Int64
  end: Int64
  text: String
  groups: (List (Option String))
}

schema Regex {
  pattern: String
  unanchoredCode: I64Array
  unanchoredLen: Int64
  anchoredCode: I64Array
  anchoredLen: Int64
  nsub: Int64
  classes: (List Bytes)
  multiline: Bool
  dotall: Bool
  ignoreCase: Bool
}

schema Thread {
  pc: Int64
  saved: (List Int64)
}

enum Ast
  (astChar c: Int64)
  (astDot)
  (astClass id: Int64)
  (astAnchor atype: Int64)
  (astEmpty)
  (astSeq items: (List Ast))
  (astAlt left: Ast right: Ast)
  (astGroup gid: Int64 inner: Ast)
  (astRep inner: Ast min: Int64 max: Int64 greedy: Bool)

enum ParseRes
  (parseOk node: Ast nextPos: Int64 groupCount: Int64 classes: (List Bytes))
  (parseErr pos: Int64 msg: String)

schema StepRes {
  threads: (List Thread)
  matched: (Option (List Int64))
  visitedPcs: (List Int64)
}

fn is-word-byte b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122))
      (or (and (>= b 65) (<= b 90))
          (or (and (>= b 48) (<= b 57))
              (= b 95))))

fn is-digit-byte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn is-space-byte b: Int64 -> Bool
  (or (= b 32)
      (or (= b 9)
          (or (= b 10)
              (or (= b 13)
                  (or (= b 12)
                      (= b 11))))))

fn fill-range! bytes: Bytes from: Int64 to: Int64 val: Int64 -> Unit
  (if (> from to)
    ()
    (let [(_ (bytesSet bytes from val))]
      (fill-range! bytes (+ from 1) to val)))

fn make-digit-class! -> Bytes
  (let [(b (bytesAlloc 256))]
    (fill-range! b 48 57 1)
    b)

fn make-not-digit-class! -> Bytes
  (let [(b (bytesAlloc 256))]
    (fill-range! b 0 255 1)
    (fill-range! b 48 57 0)
    b)

fn make-word-class! -> Bytes
  (let [(b (bytesAlloc 256))]
    (fill-range! b 48 57 1)
    (fill-range! b 65 90 1)
    (fill-range! b 97 122 1)
    (bytesSet b 95 1)
    b)

fn make-not-word-class! -> Bytes
  (let [(b (bytesAlloc 256))]
    (fill-range! b 0 255 1)
    (fill-range! b 48 57 0)
    (fill-range! b 65 90 0)
    (fill-range! b 97 122 0)
    (bytesSet b 95 0)
    b)

fn make-space-class -> Bytes
  (let [(b (bytesAlloc 256))]
    (bytesSet b 32 1)
    (bytesSet b 9 1)
    (bytesSet b 10 1)
    (bytesSet b 13 1)
    (bytesSet b 12 1)
    (bytesSet b 11 1)
    b)

fn make-not-space-class! -> Bytes
  (let [(b (bytesAlloc 256))]
    (fill-range! b 0 255 1)
    (bytesSet b 32 0)
    (bytesSet b 9 0)
    (bytesSet b 10 0)
    (bytesSet b 13 0)
    (bytesSet b 12 0)
    (bytesSet b 11 0)
    b)

fn add-class classes: (List Bytes) cls: Bytes -> (Pair Int64 (List Bytes))
  (let [(id (listLength classes))
        (newClasses (listAppend classes (list cls)))]
    (pair id newClasses))

fn parse-regex! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (parse-alt! bs n pos gc classes)

fn parse-alt! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (mt (parse-concat! bs n pos gc classes)
    ((parseErr ep em) (parseErr ep em))
    ((parseOk leftNode p1 gc1 cl1)
      (if (and (< p1 n) (= (bytesGet bs p1) 124))
        (mt (parse-alt! bs n (+ p1 1) gc1 cl1)
          ((parseErr ep em) (parseErr ep em))
          ((parseOk rightNode p2 gc2 cl2)
            (parseOk (astAlt leftNode rightNode) p2 gc2 cl2)))
        (parseOk leftNode p1 gc1 cl1))))

fn parse-concat-loop! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) acc: (List Ast) -> ParseRes
  (if (or (>= pos n) (or (= (bytesGet bs pos) 124) (= (bytesGet bs pos) 41)))
    (cond
      ((listEmpty? acc) (parseOk (astEmpty) pos gc classes))
      ((= (listLength acc) 1) (parseOk (optionOr (listHead acc) (astEmpty)) pos gc classes))
      (else (parseOk (astSeq acc) pos gc classes)))
    (mt (parse-piece! bs n pos gc classes)
      ((parseErr ep em) (parseErr ep em))
      ((parseOk piece p1 gc1 cl1)
        (parse-concat-loop! bs n p1 gc1 cl1 (listAppend acc (list piece))))))

fn parse-concat! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (parse-concat-loop! bs n pos gc classes (list))

fn desugar-repeat atom: Ast min: Int64 max: Int64 greedy: Bool -> Ast
  (cond
    ((and (= min 0) (= max 1)) (astRep atom 0 1 greedy))
    ((and (= min 0) (= max -1)) (astRep atom 0 -1 greedy))
    ((and (= min 1) (= max -1)) (astRep atom 1 -1 greedy))
    ((= min max)
      (let [(copies (make-copies atom min (list)))]
        (if (= min 1) atom (astSeq copies))))
    ((= max -1)
      (let [(exactCopies (make-copies atom (- min 1) (list)))
            (repTail (astRep atom 1 -1 greedy))]
        (astSeq (listAppend exactCopies (list repTail)))))
    (else
      (let [(exactCopies (make-copies atom min (list)))
            (optCopies (make-copies (astRep atom 0 1 greedy) (- max min) (list)))]
        (astSeq (listAppend exactCopies optCopies)))))

fn make-copies atom: Ast count: Int64 acc: (List Ast) -> (List Ast)
  (if (<= count 0)
    acc
    (make-copies atom (- count 1) (cons atom acc)))

fn parse-digits bs: Bytes n: Int64 pos: Int64 acc: Int64 count: Int64 -> (Pair Int64 Int64)
  (if (>= pos n)
    (pair pos (if (> count 0) acc -1))
    (let [(b (bytesGet bs pos))]
      (if (is-digit-byte b)
        (parse-digits bs n (+ pos 1) (+ (* acc 10) (- b 48)) (+ count 1))
        (pair pos (if (> count 0) acc -1)))))

fn parse-repeat bs: Bytes n: Int64 pos: Int64 atom: Ast gc: Int64 classes: (List Bytes) -> ParseRes
  (let [(d1 (parse-digits bs n (+ pos 1) 0 0))
        (p1 (pairFirst d1))
        (m (pairSecond d1))]
    (if (< m 0)
      (parseErr pos "invalid repeat count in '{...}'")
      (if (>= p1 n)
        (parseErr pos "unclosed repeat '{...'")
        (let [(b1 (bytesGet bs p1))]
          (cond
            ((= b1 125)
              (let [(p2 (+ p1 1))
                    (greedy (not (and (< p2 n) (= (bytesGet bs p2) 63))))
                    (nextP (if greedy p2 (+ p2 1)))]
                (parseOk (desugar-repeat atom m m greedy) nextP gc classes)))
            ((= b1 44)
              (let [(d2 (parse-digits bs n (+ p1 1) 0 0))
                    (p2 (pairFirst d2))
                    (maxVal (pairSecond d2))]
                (if (>= p2 n)
                  (parseErr pos "unclosed repeat '{...'")
                  (if (= (bytesGet bs p2) 125)
                    (let [(p3 (+ p2 1))
                          (greedy (not (and (< p3 n) (= (bytesGet bs p3) 63))))
                          (nextP (if greedy p3 (+ p3 1)))]
                      (if (>= maxVal 0)
                        (if (< maxVal m)
                          (parseErr pos "min repeat greater than max")
                          (parseOk (desugar-repeat atom m maxVal greedy) nextP gc classes))
                        (parseOk (desugar-repeat atom m -1 greedy) nextP gc classes)))
                    (parseErr p2 "expected '}' in repeat")))))
            (else (parseErr p1 "expected ',' or '}' in repeat")))))))

fn parse-piece! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (mt (parse-atom! bs n pos gc classes)
    ((parseErr ep em) (parseErr ep em))
    ((parseOk atom p1 gc1 cl1)
      (if (>= p1 n)
        (parseOk atom p1 gc1 cl1)
        (let [(b (bytesGet bs p1))]
          (cond
            ((= b 42)
              (let [(lazy (and (< (+ p1 1) n) (= (bytesGet bs (+ p1 1)) 63)))
                    (nextP (if lazy (+ p1 2) (+ p1 1)))]
                (parseOk (astRep atom 0 -1 (not lazy)) nextP gc1 cl1)))
            ((= b 43)
              (let [(lazy (and (< (+ p1 1) n) (= (bytesGet bs (+ p1 1)) 63)))
                    (nextP (if lazy (+ p1 2) (+ p1 1)))]
                (parseOk (astRep atom 1 -1 (not lazy)) nextP gc1 cl1)))
            ((= b 63)
              (let [(lazy (and (< (+ p1 1) n) (= (bytesGet bs (+ p1 1)) 63)))
                    (nextP (if lazy (+ p1 2) (+ p1 1)))]
                (parseOk (astRep atom 0 1 (not lazy)) nextP gc1 cl1)))
            ((= b 123)
              (parse-repeat bs n p1 atom gc1 cl1))
            (else (parseOk atom p1 gc1 cl1)))))))

fn parse-class! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (let [(p0 (+ pos 1))]
    (if (>= p0 n)
      (parseErr pos "unclosed character class '['")
      (let [(negated (= (bytesGet bs p0) 94))
            (p1 (if negated (+ p0 1) p0))
            (table (bytesAlloc 256))]
        (parse-class-items! bs n p1 table negated pos gc classes))))

fn parse-class-items! bs: Bytes n: Int64 p: Int64 table: Bytes negated: Bool startPos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (if (>= p n)
    (parseErr startPos "unclosed character class '['")
    (let [(b (bytesGet bs p))]
      (if (= b 93)
        (let [(finalTable (if negated (invert-class-table! table) table))
              (pCls (add-class classes finalTable))
              (clsId (pairFirst pCls))
              (newCls (pairSecond pCls))]
          (parseOk (astClass clsId) (+ p 1) gc newCls))
        (parse-one-class-item! bs n p table negated startPos gc classes))))

fn invert-class-table! table: Bytes -> Bytes
  (let [(out (bytesAlloc 256))]
    (invert-loop! table out 0)
    out)

fn invert-loop! table: Bytes out: Bytes i: Int64 -> Unit
  (if (> i 255)
    ()
    (let [(_ (bytesSet out i (if (= (bytesGet table i) 1) 0 1)))]
      (invert-loop! table out (+ i 1))))

fn parse-one-class-item! bs: Bytes n: Int64 p: Int64 table: Bytes negated: Bool startPos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (let [(b (bytesGet bs p))]
    (if (= b 92)
      (if (>= (+ p 1) n)
        (parseErr p "trailing backslash in character class")
        (let [(esc (bytesGet bs (+ p 1)))]
          (cond
            ((= esc 100)
              (fill-range! table 48 57 1)
              (parse-class-items! bs n (+ p 2) table negated startPos gc classes))
            ((= esc 119)
              (fill-range! table 48 57 1)
              (fill-range! table 65 90 1)
              (fill-range! table 97 122 1)
              (bytesSet table 95 1)
              (parse-class-items! bs n (+ p 2) table negated startPos gc classes))
            ((= esc 115)
              (bytesSet table 32 1)
              (bytesSet table 9 1)
              (bytesSet table 10 1)
              (bytesSet table 13 1)
              (bytesSet table 12 1)
              (bytesSet table 11 1)
              (parse-class-items! bs n (+ p 2) table negated startPos gc classes))
            ((= esc 110)
              (parse-range-or-char! bs n (+ p 2) 10 table negated startPos gc classes))
            ((= esc 116)
              (parse-range-or-char! bs n (+ p 2) 9 table negated startPos gc classes))
            ((= esc 114)
              (parse-range-or-char! bs n (+ p 2) 13 table negated startPos gc classes))
            (else
              (parse-range-or-char! bs n (+ p 2) esc table negated startPos gc classes)))))
      (parse-range-or-char! bs n (+ p 1) b table negated startPos gc classes)))

fn parse-range-or-char! bs: Bytes n: Int64 nextP: Int64 c1: Int64 table: Bytes negated: Bool startPos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (if (and (< (+ nextP 1) n) (and (= (bytesGet bs nextP) 45) (!= (bytesGet bs (+ nextP 1)) 93)))
    (let [(p2 (+ nextP 1))
          (b2 (bytesGet bs p2))]
      (if (= b2 92)
        (if (>= (+ p2 1) n)
          (parseErr p2 "trailing backslash in class range")
          (let [(c2 (unescape-char-byte (bytesGet bs (+ p2 1))))]
            (if (< c2 c1)
              (parseErr nextP "range out of order in character class")
              (let [(_ (fill-range! table c1 c2 1))]
                (parse-class-items! bs n (+ p2 2) table negated startPos gc classes)))))
        (if (< b2 c1)
          (parseErr nextP "range out of order in character class")
          (let [(_ (fill-range! table c1 b2 1))]
            (parse-class-items! bs n (+ p2 1) table negated startPos gc classes)))))
    (let [(_ (bytesSet table c1 1))]
      (parse-class-items! bs n nextP table negated startPos gc classes)))

fn unescape-char-byte esc: Int64 -> Int64
  (cond
    ((= esc 110) 10)
    ((= esc 114) 13)
    ((= esc 116) 9)
    ((= esc 102) 12)
    ((= esc 118) 11)
    (else esc))

fn parse-atom! bs: Bytes n: Int64 pos: Int64 gc: Int64 classes: (List Bytes) -> ParseRes
  (if (>= pos n)
    (parseErr pos "unexpected end of pattern")
    (let [(b (bytesGet bs pos))]
      (cond
        ((= b 40)
          (if (and (< (+ pos 2) n) (and (= (bytesGet bs (+ pos 1)) 63) (= (bytesGet bs (+ pos 2)) 58)))
            (mt (parse-regex! bs n (+ pos 3) gc classes)
              ((parseErr ep em) (parseErr ep em))
              ((parseOk inner p1 gc1 cl1)
                (if (and (< p1 n) (= (bytesGet bs p1) 41))
                  (parseOk (astGroup 0 inner) (+ p1 1) gc1 cl1)
                  (parseErr p1 "unclosed non-capturing group '(?:'"))))
            (let [(newGc (+ gc 1))]
              (mt (parse-regex! bs n (+ pos 1) newGc classes)
                ((parseErr ep em) (parseErr ep em))
                ((parseOk inner p1 gc1 cl1)
                  (if (and (< p1 n) (= (bytesGet bs p1) 41))
                    (parseOk (astGroup newGc inner) (+ p1 1) gc1 cl1)
                    (parseErr pos "unclosed group '('")))))))
        ((= b 41) (parseErr pos "unmatched close parenthesis ')'"))
        ((= b 91) (parse-class! bs n pos gc classes))
        ((= b 46) (parseOk (astDot) (+ pos 1) gc classes))
        ((= b 94) (parseOk (astAnchor 1) (+ pos 1) gc classes))
        ((= b 36) (parseOk (astAnchor 2) (+ pos 1) gc classes))
        ((or (= b 42) (or (= b 43) (= b 63))) (parseErr pos "quantifier without preceding token"))
        ((= b 92)
          (if (>= (+ pos 1) n)
            (parseErr pos "trailing backslash '\\'")
            (let [(esc (bytesGet bs (+ pos 1)))]
              (cond
                ((= esc 100)
                  (let [(pCls (add-class classes (make-digit-class!)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 68)
                  (let [(pCls (add-class classes (make-not-digit-class!)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 119)
                  (let [(pCls (add-class classes (make-word-class!)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 87)
                  (let [(pCls (add-class classes (make-not-word-class!)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 115)
                  (let [(pCls (add-class classes (make-space-class)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 83)
                  (let [(pCls (add-class classes (make-not-space-class!)))]
                    (parseOk (astClass (pairFirst pCls)) (+ pos 2) gc (pairSecond pCls))))
                ((= esc 98) (parseOk (astAnchor 3) (+ pos 2) gc classes))
                ((= esc 66) (parseOk (astAnchor 4) (+ pos 2) gc classes))
                ((= esc 110) (parseOk (astChar 10) (+ pos 2) gc classes))
                ((= esc 114) (parseOk (astChar 13) (+ pos 2) gc classes))
                ((= esc 116) (parseOk (astChar 9) (+ pos 2) gc classes))
                ((= esc 102) (parseOk (astChar 12) (+ pos 2) gc classes))
                ((= esc 118) (parseOk (astChar 11) (+ pos 2) gc classes))
                ((= esc 48) (parseOk (astChar 0) (+ pos 2) gc classes))
                (else (parseOk (astChar esc) (+ pos 2) gc classes))))))
        (else (parseOk (astChar b) (+ pos 1) gc classes)))))

fn astSize node: Ast -> Int64
  (mt node
    ((astChar c) 1)
    ((astDot) 1)
    ((astClass id) 1)
    ((astAnchor atype) 1)
    ((astEmpty) 0)
    ((astSeq items) (fold (fn [acc x] (+ acc (astSize x))) 0 items))
    ((astGroup gid inner) (if (> gid 0) (+ (astSize inner) 2) (astSize inner)))
    ((astAlt left right) (+ (+ (astSize left) (astSize right)) 2))
    ((astRep inner min max greedy)
      (let [(sz (astSize inner))]
        (cond
          ((and (= min 0) (= max 1)) (+ sz 1))
          ((and (= min 0) (= max -1)) (+ sz 2))
          ((and (= min 1) (= max -1)) (+ sz 1))
          (else (+ sz 2))))))

fn compileAst node: Ast pc: Int64 dotall: Bool -> (List (List Int64))
  (mt node
    ((astChar c) (list (list 1 c 0)))
    ((astDot) (list (list (if dotall 4 3) 0 0)))
    ((astClass id) (list (list 2 id 0)))
    ((astAnchor atype)
      (list (list (cond ((= atype 1) 8) ((= atype 2) 9) ((= atype 3) 10) (else 11)) 0 0)))
    ((astEmpty) (list))
    ((astSeq items) (compileSeq items pc dotall (list)))
    ((astGroup gid inner)
      (if (> gid 0)
        (let [(sStart (list 7 (* 2 gid) 0))
              (innerInsts (compileAst inner (+ pc 1) dotall))
              (sEnd (list 7 (+ (* 2 gid) 1) 0))]
          (cons sStart (listAppend innerInsts (list sEnd))))
        (compileAst inner pc dotall)))
    ((astAlt left right)
      (let [(sizeL (astSize left))
            (sizeR (astSize right))
            (split (list 5 (+ pc 1) (+ (+ pc 1 sizeL) 1)))
            (codeL (compileAst left (+ pc 1) dotall))
            (jump (list 6 (+ (+ (+ pc 1 sizeL) 1) sizeR) 0))
            (codeR (compileAst right (+ (+ pc 1 sizeL) 1) dotall))]
        (cons split (listAppend codeL (cons jump codeR)))))
    ((astRep inner min max greedy)
      (let [(sz (astSize inner))]
        (cond
          ((and (= min 0) (= max 1))
            (let [(split (if greedy (list 5 (+ pc 1) (+ pc 1 sz)) (list 5 (+ pc 1 sz) (+ pc 1))))
                  (code (compileAst inner (+ pc 1) dotall))]
              (cons split code)))
          ((and (= min 0) (= max -1))
            (let [(split (if greedy (list 5 (+ pc 1) (+ (+ pc 1 sz) 1)) (list 5 (+ (+ pc 1 sz) 1) (+ pc 1))))
                  (code (compileAst inner (+ pc 1) dotall))
                  (jump (list 6 pc 0))]
              (cons split (listAppend code (list jump)))))
          ((and (= min 1) (= max -1))
            (let [(code (compileAst inner pc dotall))
                  (split (if greedy (list 5 pc (+ (+ pc sz) 1)) (list 5 (+ (+ pc sz) 1) pc)))]
              (listAppend code (list split))))
          (else (list))))))

fn compileSeq items: (List Ast) pc: Int64 dotall: Bool acc: (List (List Int64)) -> (List (List Int64))
  (if (listEmpty? items)
    acc
    (let [(item (optionOr (listHead items) (astEmpty)))
          (rest (optionOr (listTail items) (list)))
          (code (compileAst item pc dotall))]
      (compileSeq rest (+ pc (astSize item)) dotall (listAppend acc code))))

fn flattenTriples triples: (List (List Int64)) acc: (List Int64) -> (List Int64)
  (if (listEmpty? triples)
    (listReverse acc)
    (let [(trip (optionOr (listHead triples) (list)))
          (rest (optionOr (listTail triples) (list)))
          (op (optionOr (listHead trip) 0))
          (rest1 (optionOr (listTail trip) (list)))
          (arg1 (optionOr (listHead rest1) 0))
          (rest2 (optionOr (listTail rest1) (list)))
          (arg2 (optionOr (listHead rest2) 0))]
      (flattenTriples rest (cons arg2 (cons arg1 (cons op acc))))))

fn assembleCode insts: (List (List Int64)) -> (Pair I64Array Int64)
  (let [(numInsts (listLength insts))
        (flat (flattenTriples insts (list)))
        (arr (i64ArrayGenerate (* 3 numInsts) (fn [i] (optionOr (listGet flat i) 0))))]
    (pair arr numInsts))

fn saved-init count: Int64 -> (List Int64)
  (make-saved-init count (list))

fn make-saved-init count: Int64 acc: (List Int64) -> (List Int64)
  (if (<= count 0)
    acc
    (make-saved-init (- count 1) (cons -1 acc)))

fn saved-set lst: (List Int64) idx: Int64 val: Int64 -> (List Int64)
  (if (<= idx 0)
    (cons val (optionOr (listTail lst) (list)))
    (mt (listHead lst)
      ((none) (list val))
      ((some h) (cons h (saved-set (optionOr (listTail lst) (list)) (- idx 1) val)))))

fn clear-visited! visited: Bytes pcs: (List Int64) -> Unit
  (if (listEmpty? pcs)
    ()
    (let [(h (optionOr (listHead pcs) 0))
          (rest (optionOr (listTail pcs) (list)))
          (_ (bytesSet visited h 0))]
      (clear-visited! visited rest)))

fn addthread! pc: Int64 saved: (List Int64) pos: Int64 bytes: Bytes len: Int64 visited: Bytes code: I64Array ninst: Int64 multiline: Bool threads: (List Thread) matched: (Option (List Int64)) visitedPcs: (List Int64) -> StepRes
  (if (or (>= pc ninst) (= (bytesGet visited pc) 1))
    (StepRes :threads threads :matched matched :visitedPcs visitedPcs)
    (let [(_ (bytesSet visited pc 1))
          (newVpcs (cons pc visitedPcs))
          (op (i64ArrayGet code (* 3 pc)))
          (arg1 (i64ArrayGet code (+ (* 3 pc) 1)))
          (arg2 (i64ArrayGet code (+ (* 3 pc) 2)))]
      (cond
        ((= op 5)
          (let [(res1 (addthread! arg1 saved pos bytes len visited code ninst multiline threads matched newVpcs))]
            (if (some? res1.matched)
              res1
              (addthread! arg2 saved pos bytes len visited code ninst multiline res1.threads res1.matched res1.visitedPcs))))
        ((= op 6)
          (addthread! arg1 saved pos bytes len visited code ninst multiline threads matched newVpcs))
        ((= op 7)
          (let [(newSaved (saved-set saved arg1 pos))]
            (addthread! (+ pc 1) newSaved pos bytes len visited code ninst multiline threads matched newVpcs)))
        ((= op 8)
          (let [(ok (if multiline
                      (or (= pos 0) (= (bytesGet bytes (- pos 1)) 10))
                      (= pos 0)))]
            (if ok
              (addthread! (+ pc 1) saved pos bytes len visited code ninst multiline threads matched newVpcs)
              (StepRes :threads threads :matched matched :visitedPcs newVpcs))))
        ((= op 9)
          (let [(ok (if multiline
                      (or (= pos len) (and (< pos len) (= (bytesGet bytes pos) 10)))
                      (or (= pos len) (and (= pos (- len 1)) (= (bytesGet bytes pos) 10)))))]
            (if ok
              (addthread! (+ pc 1) saved pos bytes len visited code ninst multiline threads matched newVpcs)
              (StepRes :threads threads :matched matched :visitedPcs newVpcs))))
        ((= op 10)
          (let [(prevWord (if (> pos 0) (is-word-byte (bytesGet bytes (- pos 1))) false))
                (currWord (if (< pos len) (is-word-byte (bytesGet bytes pos)) false))]
            (if (!= prevWord currWord)
              (addthread! (+ pc 1) saved pos bytes len visited code ninst multiline threads matched newVpcs)
              (StepRes :threads threads :matched matched :visitedPcs newVpcs))))
        ((= op 11)
          (let [(prevWord (if (> pos 0) (is-word-byte (bytesGet bytes (- pos 1))) false))
                (currWord (if (< pos len) (is-word-byte (bytesGet bytes pos)) false))]
            (if (= prevWord currWord)
              (addthread! (+ pc 1) saved pos bytes len visited code ninst multiline threads matched newVpcs)
              (StepRes :threads threads :matched matched :visitedPcs newVpcs))))
        ((= op 12)
          (StepRes :threads threads :matched (some saved) :visitedPcs newVpcs))
        (else
          (StepRes :threads (cons (Thread :pc pc :saved saved) threads) :matched matched :visitedPcs newVpcs)))))

fn step-one-char! threads: (List Thread) b: Int64 nextPos: Int64 bytes: Bytes len: Int64 visited: Bytes code: I64Array ninst: Int64 classes: (List Bytes) multiline: Bool accThreads: (List Thread) matched: (Option (List Int64)) vpcs: (List Int64) -> StepRes
  (if (listEmpty? threads)
    (StepRes :threads accThreads :matched matched :visitedPcs vpcs)
    (let [(t (optionOr (listHead threads) (Thread :pc 0 :saved (list))))
          (rest (optionOr (listTail threads) (list)))
          (pc t.pc)
          (op (i64ArrayGet code (* 3 pc)))
          (arg1 (i64ArrayGet code (+ (* 3 pc) 1)))
          (match (cond
                   ((= op 1) (= b arg1))
                   ((= op 2)
                     (let [(cls (optionOr (listGet classes arg1) (bytesAlloc 256)))]
                       (= (bytesGet cls b) 1)))
                   ((= op 3) (!= b 10))
                   ((= op 4) true)
                   (else false)))]
      (if match
        (let [(res1 (addthread! (+ pc 1) t.saved nextPos bytes len visited code ninst multiline accThreads matched vpcs))]
          (if (some? res1.matched)
            res1
            (step-one-char! rest b nextPos bytes len visited code ninst classes multiline res1.threads res1.matched res1.visitedPcs)))
        (step-one-char! rest b nextPos bytes len visited code ninst classes multiline accThreads matched vpcs))))

fn is-better-match newSaved: (List Int64) oldMatch: (Option (List Int64)) -> Bool
  (mt oldMatch
    ((none) true)
    ((some oldSaved)
      (let [(newStart (optionOr (listGet newSaved 0) -1))
            (oldStart (optionOr (listGet oldSaved 0) -1))]
        (cond
          ((< newStart oldStart) true)
          ((= newStart oldStart)
            (let [(newEnd (optionOr (listGet newSaved 1) -1))
                  (oldEnd (optionOr (listGet oldSaved 1) -1))]
              (>= newEnd oldEnd)))
          (else false)))))

fn keep-candidate-thread t: Thread bestStart: Int64 -> Bool
  (= (optionOr (listGet t.saved 0) -1) bestStart)

fn vm-loop! pos: Int64 len: Int64 bytes: Bytes visited: Bytes code: I64Array ninst: Int64 classes: (List Bytes) multiline: Bool curThreads: (List Thread) bestMatch: (Option (List Int64)) -> (Option (List Int64))
  (if (or (>= pos len) (listEmpty? curThreads))
    bestMatch
    (let [(b (bytesGet bytes pos))
          (res (step-one-char! curThreads b (+ pos 1) bytes len visited code ninst classes multiline (list) (none) (list)))
          (_ (clear-visited! visited res.visitedPcs))
          (nextThreads (listReverse res.threads))
          (newMatched res.matched)
          (updatedBest (if (some? newMatched)
                         (if (is-better-match (unwrap-saved newMatched) bestMatch)
                           newMatched
                           bestMatch)
                         bestMatch))]
      (if (some? updatedBest)
        (let [(bestStart (optionOr (listGet (unwrap-saved updatedBest) 0) -1))
              (validThreads (filter (fn [(t Thread)] -> Bool (keep-candidate-thread t bestStart)) nextThreads))]
          (if (listEmpty? validThreads)
            updatedBest
            (vm-loop! (+ pos 1) len bytes visited code ninst classes multiline validThreads updatedBest)))
        (vm-loop! (+ pos 1) len bytes visited code ninst classes multiline nextThreads updatedBest))))

fn extract-groups text: String saved: (List Int64) nsub: Int64 -> (List (Option String))
  (extract-groups-loop text saved 1 nsub (list))

fn extract-groups-loop text: String saved: (List Int64) i: Int64 nsub: Int64 acc: (List (Option String)) -> (List (Option String))
  (if (> i nsub)
    (listReverse acc)
    (let [(s (optionOr (listGet saved (* 2 i)) -1))
          (e (optionOr (listGet saved (+ (* 2 i) 1)) -1))
          (val (if (and (>= s 0) (>= e s))
                 (some (optionOr (stringSlice text s e) ""))
                 (none)))]
      (extract-groups-loop text saved (+ i 1) nsub (cons val acc))))

fn make-match-record text: String saved: (List Int64) nsub: Int64 -> Match
  (let [(s0 (optionOr (listGet saved 0) 0))
        (e0 (optionOr (listGet saved 1) 0))
        (matchedText (optionOr (stringSlice text s0 e0) ""))
        (groups (extract-groups text saved nsub))]
    (Match :start s0 :end e0 :text matchedText :groups groups))

fn regex-compile-flags! pattern: String multiline: Bool dotall: Bool ignoreCase: Bool -> (Result Regex String)
  (let [(bs (stringToBytes pattern))
        (n (bytesLength bs))]
    (mt (parse-regex! bs n 0 0 (list))
      ((parseErr ep em)
        (err (str "regex-compile: error at position " (stringFromInt64 ep) ": " em)))
      ((parseOk ast nextP gc classes)
        (let [(coreSize (astSize ast))
              (anchoredCore (compileAst ast 1 dotall))
              (anchoredInsts (cons (list 7 0 0) (listAppend anchoredCore (list (list 7 1 0) (list 12 0 0)))))
              (pAnch (assembleCode anchoredInsts))
              (unanchCore (compileAst ast 4 dotall))
              (prefix (list (list 5 3 1) (list 4 0 0) (list 6 0 0) (list 7 0 0)))
              (unanchInsts (listAppend prefix (listAppend unanchCore (list (list 7 1 0) (list 12 0 0)))))
              (pUnanch (assembleCode unanchInsts))]
          (ok (Regex :pattern pattern
                     :unanchoredCode (pairFirst pUnanch)
                     :unanchoredLen (pairSecond pUnanch)
                     :anchoredCode (pairFirst pAnch)
                     :anchoredLen (pairSecond pAnch)
                     :nsub gc
                     :classes classes
                     :multiline multiline
                     :dotall dotall
                     :ignoreCase ignoreCase))))))

fn regex-compile! pattern: String -> (Result Regex String)
  (regex-compile-flags! pattern false false false)

fn regex-search! re: Regex s: String -> (Option Match)
  (let [(code re.unanchoredCode)
        (ninst re.unanchoredLen)
        (bs (stringToBytes s))
        (len (bytesLength bs))
        (visited (bytesAlloc ninst))
        (initSaved (saved-init (* 2 (+ re.nsub 1))))
        (step0 (addthread! 0 initSaved 0 bs len visited code ninst re.multiline (list) (none) (list)))
        (_ (clear-visited! visited step0.visitedPcs))
        (threads0 (listReverse step0.threads))
        (matched0 step0.matched)]
    (if (and (some? matched0) (listEmpty? threads0))
      (some (make-match-record s (unwrap-saved matched0) re.nsub))
      (let [(finalMatched (vm-loop! 0 len bs visited code ninst re.classes re.multiline threads0 matched0))]
        (mt finalMatched
          ((none) (none))
          ((some saved)
            (some (make-match-record s saved re.nsub)))))))

fn regex-match-full! re: Regex s: String -> (Option Match)
  (let [(code re.anchoredCode)
        (ninst re.anchoredLen)
        (bs (stringToBytes s))
        (len (bytesLength bs))
        (visited (bytesAlloc ninst))
        (initSaved (saved-init (* 2 (+ re.nsub 1))))
        (step0 (addthread! 0 initSaved 0 bs len visited code ninst re.multiline (list) (none) (list)))
        (_ (clear-visited! visited step0.visitedPcs))
        (threads0 (listReverse step0.threads))
        (matched0 step0.matched)]
    (if (and (some? matched0) (listEmpty? threads0))
      (let [(saved (unwrap-saved matched0))]
        (if (= (optionOr (listGet saved 1) -1) len)
          (some (make-match-record s saved re.nsub))
          (none)))
      (let [(finalMatched (vm-loop! 0 len bs visited code ninst re.classes re.multiline threads0 matched0))]
        (mt finalMatched
          ((none) (none))
          ((some saved)
            (if (= (optionOr (listGet saved 1) -1) len)
              (some (make-match-record s saved re.nsub))
              (none)))))))

fn unwrap-saved opt: (Option (List Int64)) -> (List Int64)
  (mt opt
    ((none) (list))
    ((some s) s))

fn ! regex-match? re: Regex s: String -> Bool
  (some? (regex-search! re s))

fn regex-group m: Match i: Int64 -> (Option String)
  (cond
    ((= i 0) (some m.text))
    ((> i 0) (optionOr (listGet m.groups (- i 1)) (none)))
    (else (none)))

fn regex-find-all! re: Regex s: String -> (List Match)
  (find-all-from! re s 0 (list))

fn find-all-from! re: Regex s: String pos: Int64 acc: (List Match) -> (List Match)
  (let [(slen (stringLength s))]
    (if (> pos slen)
      (listReverse acc)
      (let [(sub (optionOr (stringSlice s pos slen) ""))]
        (mt (regex-search! re sub)
          ((none) (listReverse acc))
          ((some m)
            (let [(realStart (+ pos m.start))
                  (realEnd (+ pos m.end))
                  (realText (optionOr (stringSlice s realStart realEnd) ""))
                  (realGroups m.groups)
                  (realMatch (Match :start realStart :end realEnd :text realText :groups realGroups))
                  (nextPos (if (> m.end m.start)
                             realEnd
                             (+ realStart 1)))]
              (find-all-from! re s nextPos (cons realMatch acc))))))))

fn regex-replace-all! re: Regex s: String template: String -> String
  (let [(matches (regex-find-all! re s))]
    (if (listEmpty? matches)
      s
      (replace-all-loop s template matches 0 (list))))

fn replace-all-loop s: String template: String matches: (List Match) prevEnd: Int64 acc: (List String) -> String
  (if (listEmpty? matches)
    (let [(tail (optionOr (stringSlice s prevEnd (stringLength s)) ""))]
      (stringJoin (listReverse (cons tail acc)) ""))
    (let [(m (optionOr (listHead matches) (Match :start 0 :end 0 :text "" :groups (list))))
          (rest (optionOr (listTail matches) (list)))
          (prefix (optionOr (stringSlice s prevEnd m.start) ""))
          (expanded (expand-template template m))
          (newAcc (cons expanded (cons prefix acc)))]
      (replace-all-loop s template rest m.end newAcc)))

fn expand-template template: String m: Match -> String
  (let [(tlen (stringLength template))]
    (expand-template-loop template tlen 0 m (list)))

fn expand-template-loop template: String tlen: Int64 i: Int64 m: Match acc: (List String) -> String
  (if (>= i tlen)
    (stringJoin (listReverse acc) "")
    (let [(ch (optionOr (stringSlice template i (+ i 1)) ""))]
      (if (= ch "\\")
        (let [(nextCh (optionOr (stringSlice template (+ i 1) (+ i 2)) ""))
              (nextCode (if (stringEmpty? nextCh) 0 (charCode nextCh)))]
          (cond
            ((= nextCh "\\")
              (expand-template-loop template tlen (+ i 2) m (cons "\\" acc)))
            ((or (= nextCh "0") (= nextCh "&"))
              (expand-template-loop template tlen (+ i 2) m (cons m.text acc)))
            ((and (>= nextCode 49) (<= nextCode 57))
              (let [(gid (- nextCode 48))
                    (rep (optionOr (regex-group m gid) ""))]
                (expand-template-loop template tlen (+ i 2) m (cons rep acc))))
            (else
              (expand-template-loop template tlen (+ i 2) m (cons (str "\\" nextCh) acc)))))
        (expand-template-loop template tlen (+ i 1) m (cons ch acc)))))
