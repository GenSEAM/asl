(module asl-checker/sizedCheckTest :x [runTests] :i [(types :a ty) (check :a c) (lowLevelSigs :a ll)])

; (:m :ref LL-SIZED-CHECK :do "sized integers in the checker: U8 U16 U32 U64 I8 I16 are integral types with their literal ranges, two different sized types never mix in arithmetic and the diagnostic names the conversion, the integral bit operators accept any sized type, and the overflow, conversion, Buf and atomic signatures are registered")
fn diagsOf body: String -> (List ty/Diagnostic)
  (c/checkSource (str "(module m :x [] :i [])\n\n" body) (mapEmpty) "m.asl")

fn showDiags ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str "[" d.code "] " d.message)) ds) "; ")

fn clean? body: String label: String -> Bool
  (let [(ds (diagsOf body))] (do (assert (listEmpty? ds) (str label " is accepted; got " (showDiags ds))) true))

fn rejected? body: String needle: String label: String -> Bool
  (let [(ds (diagsOf body))]
    (do (assert (not (listEmpty? ds)) (str label " is rejected"))
        (assert (stringContains? (showDiags ds) needle) (str label ": the diagnostic mentions " needle "; got " (showDiags ds)))
        true))

fn testTypes -> Bool
  (do (assert (ty/isIntegralType? "U8") "U8 is integral")
      (assert (ty/isIntegralType? "I16") "I16 is integral")
      (assert (ty/isNumericType? "U64") "U64 is numeric")
      (assert (not (ty/isIntegralType? "Float64")) "Float64 is not integral")
      (assert (= (ty/intRangeBounds "U8") (some (pair 0 255))) "U8 ranges 0..255")
      (assert (= (ty/intRangeBounds "I8") (some (pair -128 127))) "I8 ranges -128..127")
      (assert (= (ty/intRangeBounds "U32") (some (pair 0 4294967295))) "U32 ranges 0..4294967295")
      true)

fn testLiterals -> Bool
  (do (clean? "fn f -> U8\n  255\n" "255 as U8")
      (rejected? "fn f -> U8\n  256\n" "literal-range" "256 as U8")
      (rejected? "fn f -> U8\n  -1\n" "literal-range" "-1 as U8")
      (clean? "fn f -> I8\n  -128\n" "-128 as I8")
      (rejected? "fn f -> I8\n  128\n" "literal-range" "128 as I8")
      (clean? "fn f -> U16\n  0xFFFF\n" "0xFFFF as U16")
      (rejected? "fn f -> U16\n  0x10000\n" "literal-range" "0x10000 as U16")
      (clean? "fn f -> U32\n  0xFFFFFFFF\n" "0xFFFFFFFF as U32")
      (clean? "fn f -> U64\n  0xFFFFFFFFFFFFFFFF\n" "the full U64 bit pattern")
      (rejected? "fn f -> U64\n  -1\n" "literal-range" "-1 as U64")
      true)

fn testArithmetic -> Bool
  (do (clean? "fn f a: U8 b: U8 -> U8\n  (+ a b)\n" "U8 plus U8")
      (clean? "fn f a: U32 -> U32\n  (+ a 1)\n" "U32 plus a literal")
      (rejected? "fn f a: U8 b: U32 -> U32\n  (+ a b)\n" "(U8 x)" "U8 plus U32 names the conversion")
      (rejected? "fn f a: U8 b: Int64 -> Int64\n  (+ b a)\n" "(I64 x)" "Int64 plus U8 names the conversion")
      (rejected? "fn f a: U8 -> Int64\n  a\n" "(I64 x)" "U8 returned as Int64")
      true)

fn testBitOps -> Bool
  (do (clean? "fn f a: U32 b: U32 -> U32\n  (^ (& a b) (| a 1))\n" "and or xor over U32")
      (clean? "fn f a: U16 -> U16\n  (~ a)\n" "not over U16")
      (clean? "fn f a: U32 n: U8 -> U32\n  (<< a n)\n" "shift by a different integral width")
      (clean? "fn f a: Int64 -> Int64\n  (>> a 3)\n" "Int64 shift still checks")
      (rejected? "fn f a: U32 b: U8 -> U32\n  (& a b)\n" "(U32 x)" "and over two sized types")
      (rejected? "fn f a: Float64 -> Float64\n  (~ a)\n" "expected" "not over a float")
      (clean? "fn f a: U32 -> U32\n  (rotateLeft a 3)\n" "rotateLeft")
      (clean? "fn f a: U64 -> Int64\n  (bitCount a)\n" "bitCount returns Int64")
      true)

fn testOverflowOps -> Bool
  (do (clean? "fn f a: U8 b: U8 -> U8\n  (addWrap a b)\n" "addWrap")
      (clean? "fn f a: I16 b: I16 -> I16\n  (subClamp a b)\n" "subClamp")
      (clean? "fn f a: U32 b: U32 -> (Option U32)\n  (mulChecked a b)\n" "mulChecked")
      (rejected? "fn f a: U8 b: U32 -> U8\n  (addWrap a b)\n" "(U8 x)" "addWrap over two sized types")
      true)

fn testConversions -> Bool
  (do (clean? "fn f a: Int64 -> U8\n  (U8 a)\n" "Int64 to U8")
      (clean? "fn f a: U8 -> Int64\n  (I64 a)\n" "U8 to Int64")
      (clean? "fn f a: U8 b: U32 -> U32\n  (+ (U32 a) b)\n" "explicit widening then add")
      (clean? "fn f a: Float64 -> U16\n  (U16 a)\n" "Float64 to U16")
      true)

fn testSigTable -> Bool
  (do (assert (some? (ll/lowLevelSig "addWrap")) "addWrap has a signature")
      (assert (some? (ll/lowLevelSig "U16")) "a conversion has a signature")
      (assert (some? (ll/lowLevelSig "atomicCas")) "atomicCas has a signature")
      (assert (some? (ll/lowLevelSig "bufGet")) "bufGet has a signature")
      (assert (none? (ll/lowLevelSig "notALowLevelName")) "an unknown name has none")
      (assert (some? (ty/builtinSig "rotateRight")) "builtinSig reaches the low-level table")
      true)

fn ! runTests -> Bool
  (do (testTypes) (testLiterals) (testArithmetic) (testBitOps) (testOverflowOps) (testConversions) (testSigTable) true)
