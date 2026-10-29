(module asl-checker/numKinds :x [intLitShape parseIntLit parseIntLitBits] :i [])

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
