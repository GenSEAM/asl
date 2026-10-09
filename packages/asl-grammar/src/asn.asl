(module asl-grammar/asn
  :x [Sx asnReadAll asnKeyValue asnKeyString]
  :i [])

(enum Sx
  (:c sxList [(items (List Sx))] "A parenthesised form.")
  (:c sxVec [(items (List Sx))] "A bracketed vector.")
  (:c sxKw [(name String)] "A keyword, without its colon.")
  (:c sxSym [(name String)] "A symbol.")
  (:c sxStr [(text String)] "A string with its escapes resolved.")
  (:c sxInt [(value Int64)] "A decimal integer."))

fn textSlice text: String start: Int64 end: Int64 -> String
  (optionOr (stringSlice text start end) "")

fn blank? b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (or (= b 13) (= b 44)))))

fn delimiter? b: Int64 -> Bool
  (or (blank? b) (or (= b 40) (or (= b 41) (or (= b 91) (or (= b 93) (or (= b 123) (or (= b 125) (or (= b 34) (= b 59)))))))))

fn tailrec lineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) i (if (= (bytesGet bs i) 10) i (lineEnd bs n (+ i 1))))

fn tailrec skipBlank bs: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) i
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 59) (skipBlank bs n (lineEnd bs n i)))
        ((blank? b) (skipBlank bs n (+ i 1)))
        (else i))))

fn tailrec atomEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) i (if (delimiter? (bytesGet bs i)) i (atomEnd bs n (+ i 1))))

fn escapeText b: Int64 -> (Option String)
  (cond
    ((= b 110) (some "\n"))
    ((= b 116) (some "\t"))
    ((= b 114) (some "\r"))
    ((= b 92) (some "\\"))
    ((= b 34) (some "\""))
    (else (none)))

fn tailrec readString text: String bs: Bytes n: Int64 start: Int64 i: Int64 parts: (List String) -> (Result (Pair Sx Int64) String)
  (cond
    ((>= i n) (err (str "unterminated string at byte " start)))
    ((= (bytesGet bs i) 34) (ok (pair (sxStr (stringJoin (listReverse (cons (textSlice text start i) parts)) "")) (+ i 1))))
    ((= (bytesGet bs i) 92)
      (if (>= (+ i 1) n)
        (err (str "unterminated string at byte " start))
        (mt (escapeText (bytesGet bs (+ i 1)))
          ((none) (err (str "unknown escape at byte " i)))
          ((some s) (readString text bs n (+ i 2) (+ i 2) (cons s (cons (textSlice text start i) parts)))))))
    (else (readString text bs n start (+ i 1) parts)))

fn readAtom text: String bs: Bytes n: Int64 p: Int64 -> (Result (Pair Sx Int64) String)
  (let [(e (atomEnd bs n p)) (s (textSlice text p e))]
    (cond
      ((and (stringStartsWith? s ":") (> (stringLength s) 1)) (ok (pair (sxKw (textSlice s 1 (stringLength s))) e)))
      (else (mt (stringToInt64 s)
              ((some v) (ok (pair (sxInt v) e)))
              ((none) (ok (pair (sxSym s) e)))))))

fn readDatum text: String bs: Bytes n: Int64 i: Int64 -> (Result (Pair Sx Int64) String)
  (let [(p (skipBlank bs n i))]
    (if (>= p n)
      (err (str "unexpected end of input at byte " p))
      (let [(b (bytesGet bs p))]
        (cond
          ((= b 40) (readSeq text bs n (+ p 1) 41 true (list)))
          ((= b 91) (readSeq text bs n (+ p 1) 93 false (list)))
          ((= b 34) (readString text bs n (+ p 1) (+ p 1) (list)))
          ((or (= b 41) (or (= b 93) (or (= b 123) (= b 125)))) (err (str "unexpected bracket at byte " p)))
          (else (readAtom text bs n p))))))

fn readSeq text: String bs: Bytes n: Int64 i: Int64 close: Int64 isList: Bool acc: (List Sx) -> (Result (Pair Sx Int64) String)
  (let [(p (skipBlank bs n i))]
    (cond
      ((>= p n) (err "unclosed form at end of input"))
      ((= (bytesGet bs p) close) (ok (pair (if isList (sxList (listReverse acc)) (sxVec (listReverse acc))) (+ p 1))))
      (else (mt (readDatum text bs n p)
              ((err e) (err e))
              ((ok r) (readSeq text bs n (pairSecond r) close isList (cons (pairFirst r) acc)))))))

fn readAll text: String bs: Bytes n: Int64 i: Int64 acc: (List Sx) -> (Result (List Sx) String)
  (let [(p (skipBlank bs n i))]
    (if (>= p n)
      (ok (listReverse acc))
      (mt (readDatum text bs n p)
        ((err e) (err e))
        ((ok r) (readAll text bs n (pairSecond r) (cons (pairFirst r) acc))))))

fn asnReadAll text: String -> (Result (List Sx) String)
  (let [(bs (stringToBytes text))]
    (readAll text bs (bytesLength bs) 0 (list)))

fn asnKeyValue items: (List Sx) key: String -> (Option Sx)
  (mt (listHead items)
    ((none) (none))
    ((some x) (let [(rest (optionOr (listTail items) (list)))]
                (mt x
                  ((sxKw k) (if (= k key) (listHead rest) (asnKeyValue rest key)))
                  (_ (asnKeyValue rest key))))))

fn asnKeyString items: (List Sx) key: String -> (Option String)
  (mt (asnKeyValue items key)
    ((some v) (mt v ((sxStr s) (some s)) ((sxSym s) (some s)) (_ (none))))
    ((none) (none)))
