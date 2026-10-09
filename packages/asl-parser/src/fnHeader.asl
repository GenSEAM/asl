(module asl-parser/fnHeader
  :x [stripCrLine arrowScan headerArrow? paramLine? headerJoin stripTailrecPrefix joinFnHeader]
  :i [])

fn stripCrLine line: String -> String
  (if (stringEndsWith? line "\r") (optionOr (stringSlice line 0 (- (stringLength line) 1)) line) line)

fn arrowScan bs: Bytes len: Int64 i: Int64 depth: Int64 inStr: Bool -> Bool
  (if (>= i len)
    false
    (let [(b (bytesGet bs i))]
      (cond
        (inStr (cond
                 ((= b 92) (arrowScan bs len (+ i 2) depth true))
                 ((= b 34) (arrowScan bs len (+ i 1) depth false))
                 (else (arrowScan bs len (+ i 1) depth true))))
        ((= b 34) (arrowScan bs len (+ i 1) depth true))
        ((= b 59) false)
        ((or (= b 40) (or (= b 91) (= b 123))) (arrowScan bs len (+ i 1) (+ depth 1) false))
        ((or (= b 41) (or (= b 93) (= b 125))) (arrowScan bs len (+ i 1) (- depth 1) false))
        ((and (= depth 0) (and (= b 45) (and (< (+ i 1) len) (and (= (bytesGet bs (+ i 1)) 62) (or (= i 0) (= (bytesGet bs (- i 1)) 32)))))) true)
        (else (arrowScan bs len (+ i 1) depth false)))))

fn headerArrow? s: String -> Bool
  (let [(bs (stringToBytes s))]
    (arrowScan bs (bytesLength bs) 0 0 false))

fn paramLine? line: String -> Bool
  (let [(w (optionOr (listHead (stringSplit (stringTrim line) " ")) ""))]
    (and (stringStartsWith? line " ")
         (or (= w "->") (and (> (stringLength w) 1) (and (stringEndsWith? w ":") (not (stringStartsWith? w ":")))))))

fn headerJoin header: String rest: (List String) taken: Int64 -> (Option (Pair String Int64))
  (mt (listHead rest)
    ((none) (none))
    ((some line) (let [(joined (str header " " (stringTrim line)))]
                   (cond
                     ((not (paramLine? line)) (none))
                     ((headerArrow? joined) (some (pair joined (+ taken 1))))
                     (else (headerJoin joined (optionOr (listTail rest) (list)) (+ taken 1)))))))

fn stripTailrecPrefix header: String -> String
  (let [(start (cond
                 ((stringStartsWith? header "fn tailrec ") 11)
                 ((stringStartsWith? header "fn :tailrec ") 12)
                 (else 0)))]
    (if (= start 0) header (str "fn " (optionOr (stringSlice header start (stringLength header)) ""))))

fn joinFnHeader text: String -> String
  (let [(lines (stringSplit text "\n"))
        (originalFirst (optionOr (listHead lines) ""))
        (first (stripTailrecPrefix (stripCrLine originalFirst)))
        (rest (optionOr (listTail lines) (list)))
        (rewritten (if (= originalFirst first) text (stringJoin (cons first rest) "\n")))]
    (if (or (not (or (stringStartsWith? first "fn ") (stringStartsWith? first "fn!"))) (headerArrow? first))
      rewritten
      (mt (headerJoin first rest 0)
        ((none) rewritten)
        ((some j) (stringJoin (cons (pairFirst j) (listAppend (map (fn [(_ Int64)] -> String "") (range 0 (pairSecond j))) (listDrop rest (pairSecond j)))) "\n")))))
