(module asl-intel/fixture
  :x [Asn readAsn kwArg kwStr kwInt kwItems kwKw headKw]
  :i [(asl-intel/text :a t)])

enum Asn
  (aStr s: String)
  (aInt v: Int64)
  (aKw k: String)
  (aSym s: String)
  (aList xs: (List Asn))
  (aVec xs: (List Asn))

fn skip b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) i)
    ((t/isSpaceByte (bytesGet b i)) (skip b n (+ i 1)))
    ((= (bytesGet b i) 59) (skip b n (lineEnd b n i)))
    (else i))

fn lineEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet b i) 10) (+ i 1)) (else (lineEnd b n (+ i 1))))

fn tokStop? c: Int64 -> Bool
  (or (t/isSpaceByte c) (or (= c 40) (or (= c 41) (or (= c 91) (or (= c 93) (= c 34))))))

fn tokEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (tokStop? (bytesGet b i))) i (tokEnd b n (+ i 1)))

fn readStr s: String b: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (if (>= i n) (err "unterminated string")
    (let [(c (bytesGet b i))]
      (cond
        ((= c 34) (ok (pair (t/concatAll (listReverse (cons (t/sliceStr s start i) acc))) (+ i 1))))
        ((= c 92)
          (if (>= (+ i 1) n) (err "dangling escape")
            (let [(e (bytesGet b (+ i 1))) (head (cons (t/sliceStr s start i) acc))]
              (cond
                ((= e 110) (readStr s b n (+ i 2) (+ i 2) (cons "\n" head)))
                ((= e 116) (readStr s b n (+ i 2) (+ i 2) (cons "\t" head)))
                ((= e 114) (readStr s b n (+ i 2) (+ i 2) (cons "\r" head)))
                ((= e 34) (readStr s b n (+ i 2) (+ i 2) (cons "\"" head)))
                ((= e 92) (readStr s b n (+ i 2) (+ i 2) (cons "\\" head)))
                (else (err "unknown escape"))))))
        (else (readStr s b n (+ i 1) start acc)))))

fn intTok s: String -> (Option Int64)
  (let [(b (stringToBytes s)) (n (bytesLength b)) (neg (and (> n 1) (= (bytesGet b 0) 45)))]
    (if (= n 0) (none) (digits b n (if neg 1 0) 0 neg)))

fn digits b: Bytes n: Int64 i: Int64 acc: Int64 neg: Bool -> (Option Int64)
  (cond
    ((>= i n) (some (if neg (- 0 acc) acc)))
    ((and (>= (bytesGet b i) 48) (<= (bytesGet b i) 57)) (digits b n (+ i 1) (+ (* acc 10) (- (bytesGet b i) 48)) neg))
    (else (none)))

fn readOne s: String b: Bytes n: Int64 i0: Int64 -> (Result (Pair Asn Int64) String)
  (let [(i (skip b n i0))]
    (if (>= i n) (err "unexpected end of input")
      (let [(c (bytesGet b i))]
        (cond
          ((= c 40) (mt (readSeq s b n (+ i 1) 41 (list)) ((ok r) (ok (pair (aList (pairFirst r)) (pairSecond r)))) ((err e) (err e))))
          ((= c 91) (mt (readSeq s b n (+ i 1) 93 (list)) ((ok r) (ok (pair (aVec (pairFirst r)) (pairSecond r)))) ((err e) (err e))))
          ((= c 34) (mt (readStr s b n (+ i 1) (+ i 1) (list)) ((ok r) (ok (pair (aStr (pairFirst r)) (pairSecond r)))) ((err e) (err e))))
          ((or (= c 41) (= c 93)) (err (str "unexpected closer at byte " (t/intStr i))))
          (else
            (let [(e (tokEnd b n i)) (tok (t/sliceStr s i e))]
              (cond
                ((= c 58) (ok (pair (aKw (t/sliceStr s (+ i 1) e)) e)))
                (else (mt (intTok tok) ((some v) (ok (pair (aInt v) e))) ((none) (ok (pair (aSym tok) e))))))))))))

fn readSeq s: String b: Bytes n: Int64 i0: Int64 closer: Int64 acc: (List Asn) -> (Result (Pair (List Asn) Int64) String)
  (let [(i (skip b n i0))]
    (cond
      ((>= i n) (err "unclosed form"))
      ((= (bytesGet b i) closer) (ok (pair (listReverse acc) (+ i 1))))
      (else (mt (readOne s b n i) ((ok r) (readSeq s b n (pairSecond r) closer (cons (pairFirst r) acc))) ((err e) (err e))))))

fn readAsn s: String -> (Result (List Asn) String)
  (let [(b (stringToBytes s))] (readTop s b (bytesLength b) 0 (list)))

fn readTop s: String b: Bytes n: Int64 i0: Int64 acc: (List Asn) -> (Result (List Asn) String)
  (let [(i (skip b n i0))]
    (if (>= i n) (ok (listReverse acc))
      (mt (readOne s b n i) ((ok r) (readTop s b n (pairSecond r) (cons (pairFirst r) acc))) ((err e) (err e)))))

fn itemsOf a: Asn -> (List Asn)
  (mt a ((aList xs) xs) ((aVec xs) xs) (else (list)))

fn headKw a: Asn -> String
  (mt (listHead (itemsOf a)) ((some h) (mt h ((aKw k) k) (else ""))) ((none) ""))

fn kwArg a: Asn key: String -> (Option Asn)
  (kwLoop (optionOr (listTail (itemsOf a)) (list)) key)

fn kwLoop xs: (List Asn) key: String -> (Option Asn)
  (mt (listHead xs)
    ((none) (none))
    ((some h)
      (let [(rest (optionOr (listTail xs) (list)))]
        (mt h
          ((aKw k) (if (= k key) (listHead rest) (kwLoop rest key)))
          (else (kwLoop rest key))))))

fn kwStr a: Asn key: String -> (Result String String)
  (mt (kwArg a key) ((some v) (mt v ((aStr s) (ok s)) (else (err (str ":" key " is not a string"))))) ((none) (err (str "missing :" key))))

fn kwInt a: Asn key: String -> (Result Int64 String)
  (mt (kwArg a key) ((some v) (mt v ((aInt x) (ok x)) (else (err (str ":" key " is not an integer"))))) ((none) (err (str "missing :" key))))

fn kwKw a: Asn key: String -> (Result String String)
  (mt (kwArg a key) ((some v) (mt v ((aKw x) (ok x)) ((aSym x) (ok x)) (else (err (str ":" key " is not a keyword"))))) ((none) (err (str "missing :" key))))

fn kwItems a: Asn key: String -> (Result (List Asn) String)
  (mt (kwArg a key) ((some v) (mt v ((aVec xs) (ok xs)) ((aList xs) (ok xs)) (else (err (str ":" key " is not a sequence"))))) ((none) (err (str "missing :" key))))
