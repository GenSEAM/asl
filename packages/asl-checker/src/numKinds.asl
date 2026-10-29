(module asl-checker/numKinds :x [intLitShape parseIntLit parseIntLitBits intKindCode intKindWidth intKindSigned?] :i [])

; (:m :ref LL-NUMLIT :do "numeric literal grammar in one place: 0x 0b 0o radix literals and _ digit separators on top of the decimal atoms stringToInt64 reads; intLitShape names the form (plain sep radix bad none), parseIntLit is the Int64-range value, parseIntLitBits keeps radix literals up to 2^64-1 as their bit pattern")
fn unsignedBody v: String -> String
  (if (and (or (stringStartsWith? v "+") (stringStartsWith? v "-")) (> (stringLength v) 1)) (optionOr (stringSlice v 1 (stringLength v)) v) v)

fn radixOf body: String -> Int64
  (cond ((stringStartsWith? body "0x") 16) ((stringStartsWith? body "0b") 2) ((stringStartsWith? body "0o") 8) (else 0))

fn digitValue c: String base: Int64 -> Int64
  (let [(i (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) -1))]
    (if (< i base) i -1))

fn separatorsOk? s: String -> Bool
  (and (not (stringEmpty? s)) (and (not (stringStartsWith? s "_")) (and (not (stringEndsWith? s "_")) (not (stringContains? s "__")))))

fn digitsOf s: String base: Int64 -> (Option (List Int64))
  (if (separatorsOk? s)
    (let [(vals (map (fn [(c String)] -> Int64 (if (= c "_") -2 (digitValue c base))) (stringChars s)))]
      (if (listAny? (fn [(d Int64)] -> Bool (= d -1)) vals) (none) (some (filter (fn [(d Int64)] -> Bool (>= d 0)) vals))))
    (none))

fn startsDigit? s: String -> Bool
  (and (not (stringEmpty? s)) (stringContains? "0123456789" (optionOr (stringSlice s 0 1) "")))

fn mixedDecimal? body: String -> Bool
  (and (startsDigit? body) (stringContains? body "_"))

fn radixBody body: String -> String
  (optionOr (stringSlice body 2 (stringLength body)) "")

fn intLitShape v: String -> String
  (let [(body (unsignedBody v)) (base (radixOf body))]
    (cond
      ((> base 0) (match (digitsOf (radixBody body) base) ((some _) "radix") ((none) "bad")))
      ((mixedDecimal? body) (match (digitsOf body 10) ((some _) "sep") ((none) "bad")))
      ((startsDigit? body) (if (some? (stringToInt64 v)) "plain" "none"))
      (else "none")))

fn significant ds: (List Int64) -> (List Int64)
  (if (and (not (listEmpty? ds)) (= (optionOr (listHead ds) -1) 0)) (significant (optionOr (listSlice ds 1 (listLength ds)) (list))) ds)

fn radixFits? sig: (List Int64) base: Int64 -> Bool
  (let [(n (listLength sig))]
    (cond ((= base 16) (<= n 16)) ((= base 2) (<= n 64)) (else (or (< n 22) (and (= n 22) (<= (optionOr (listHead sig) 0) 1))))))

fn radixBits ds: (List Int64) k: Int64 -> Int64
  (fold (fn [(acc Int64) (d Int64)] -> Int64 (| (<< acc k) d)) 0 ds)

fn parseRadix neg: Bool base: Int64 ds: (List Int64) wide: Bool -> (Option Int64)
  (let [(sig (significant ds)) (k (cond ((= base 16) 4) ((= base 2) 1) (else 3)))]
    (if (not (radixFits? sig base))
      (none)
      (let [(bits (radixBits sig k))]
        (cond ((not neg) (if (or wide (>= bits 0)) (some bits) (none)))
              ((>= bits 0) (some (- 0 bits)))
              (else (none))))))

fn parseIntLitAs v: String wide: Bool -> (Option Int64)
  (let [(body (unsignedBody v)) (neg (stringStartsWith? v "-")) (base (radixOf body))]
    (cond
      ((> base 0) (match (digitsOf (radixBody body) base) ((some ds) (parseRadix neg base ds wide)) ((none) (none))))
      ((mixedDecimal? body) (match (digitsOf body 10) ((some _) (stringToInt64 (str (if neg "-" "") (stringReplace body "_" "")))) ((none) (none))))
      (else (stringToInt64 v))))

fn parseIntLit v: String -> (Option Int64)
  (parseIntLitAs v false)

fn parseIntLitBits v: String -> (Option Int64)
  (parseIntLitAs v true)

; (:m :ref LL-NUMLIT :do "sized integer kind table shared by checker and lowering: boxed aux kind codes U8 1 I8 2 U16 3 I16 4 U32 5 I32 6 U64 7, I64 and its aliases Int Int64 0, -1 for any other name; widths in bits, 0 for an unknown name")
fn intKindCode name: String -> Int64
  (cond ((= name "U8") 1) ((= name "I8") 2) ((= name "U16") 3) ((= name "I16") 4) ((= name "U32") 5) ((= name "I32") 6) ((= name "U64") 7) ((or (= name "I64") (or (= name "Int") (= name "Int64"))) 0) (else -1))

fn intKindWidth name: String -> Int64
  (cond ((or (= name "U8") (= name "I8")) 8) ((or (= name "U16") (= name "I16")) 16) ((or (= name "U32") (= name "I32")) 32) ((or (= name "U64") (or (= name "I64") (or (= name "Int") (= name "Int64")))) 64) (else 0))

fn intKindSigned? name: String -> Bool
  (or (= name "I8") (or (= name "I16") (or (= name "I32") (or (= name "I64") (or (= name "Int") (= name "Int64"))))))
