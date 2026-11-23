(module asl-target-llvm/tests/bitRtTest
  :x [runTests]
  :i [(asl-target-llvm/bitRt :a bit)])

fn ! testWidths -> Bool
  (do
    (assert (= (bit/kindWidth "U8") 8) "U8 is 8 bits")
    (assert (= (bit/kindWidth "U16") 16) "U16 is 16 bits")
    (assert (= (bit/kindWidth "U32") 32) "U32 is 32 bits")
    (assert (= (bit/kindWidth "U64") 64) "U64 is 64 bits")
    (assert (= (bit/kindWidth "I8") 8) "I8 is 8 bits")
    (assert (= (bit/kindWidth "I64") 64) "I64 is 64 bits")
    (assert (= (bit/kindWidth "Nope") 0) "an unknown kind has width 0")
    true)

fn ! testSigned -> Bool
  (do
    (assert (bit/kindSigned? "I8") "I8 is signed")
    (assert (bit/kindSigned? "I64") "I64 is signed")
    (assert (not (bit/kindSigned? "U8")) "U8 is unsigned")
    (assert (not (bit/kindSigned? "U64")) "U64 is unsigned")
    true)

fn ! testBinaryOps -> Bool
  (do
    (assert (= (bit/binaryOpText "&" "U8") "and i8 %a, %b") "and on U8")
    (assert (= (bit/binaryOpText "|" "I16") "or i16 %a, %b") "or on I16")
    (assert (= (bit/binaryOpText "^" "U32") "xor i32 %a, %b") "xor on U32")
    (assert (= (bit/binaryOpText "~" "I64") "xor i64 %a, -1") "not on I64")
    (assert (= (bit/binaryOpText "<<" "U16") "shl i16 %a, %b") "shl on U16")
    (assert (= (bit/binaryOpText ">>" "U32") "lshr i32 %a, %b") "unsigned >> is lshr")
    (assert (= (bit/binaryOpText ">>" "I32") "ashr i32 %a, %b") "signed >> is ashr")
    (assert (= (bit/binaryOpText ">>" "I8") "ashr i8 %a, %b") "signed I8 >> is ashr")
    true)

fn ! testBinaryOpsText -> Bool
  (let [(signed (bit/binaryOpsText "I32"))
        (unsigned (bit/binaryOpsText "U32"))]
    (do
      (assert (= (listLength signed) 6) "six binary ops per kind")
      (assert (listContains? signed "ashr i32 %a, %b") "the signed right shift is ashr")
      (assert (not (listContains? signed "lshr i32 %a, %b")) "a signed kind has no lshr")
      (assert (listContains? unsigned "lshr i32 %a, %b") "the unsigned right shift is lshr")
      (assert (not (listContains? unsigned "ashr i32 %a, %b")) "an unsigned kind has no ashr")
      true))

fn ! testRotate -> Bool
  (do
    (assert (= (bit/rotateText "left" "U8") "call i8 @llvm.fshl.i8(i8 %a, i8 %a, i8 %b)") "rotate left uses fshl with the value twice")
    (assert (= (bit/rotateText "right" "I16") "call i16 @llvm.fshr.i16(i16 %a, i16 %a, i16 %b)") "rotate right uses fshr with the value twice")
    true)

fn ! testCount -> Bool
  (let [(cs (bit/countText "U16"))]
    (do
      (assert (= (listLength cs) 2) "countText emits ctlz and cttz")
      (assert (listContains? cs "call i16 @llvm.ctlz.i16(i16 %a, i1 false)") "ctlz passes is_zero_poison false so zero yields the width")
      (assert (listContains? cs "call i16 @llvm.cttz.i16(i16 %a, i1 false)") "cttz passes is_zero_poison false so zero yields the width")
      (assert (= (bit/clzFunc "U8") "declare i8 @llvm.ctlz.i8(i8, i1)") "clzFunc declares the intrinsic with its argument types")
      (assert (= (bit/ctzFunc "U8") "declare i8 @llvm.cttz.i8(i8, i1)") "ctzFunc declares the intrinsic with its argument types")
      true))

fn ! testByteSwap -> Bool
  (do
    (assert (= (bit/byteSwapText "U16") "call i16 @llvm.bswap.i16(i16 %a)") "byteSwap uses llvm.bswap")
    (assert (= (bit/byteSwapText "I64") "call i64 @llvm.bswap.i64(i64 %a)") "byteSwap on I64")
    true)

fn ! testNamedOps -> Bool
  (do
    (assert (= (bit/rotateLeft "U8") "call i8 @llvm.fshl.i8(i8 %a, i8 %a, i8 %b)") "rotateLeft uses fshl")
    (assert (= (bit/rotateRight "I16") "call i16 @llvm.fshr.i16(i16 %a, i16 %a, i16 %b)") "rotateRight uses fshr")
    (assert (= (bit/bitCount "U32") "call i32 @llvm.ctpop.i32(i32 %a)") "bitCount uses ctpop")
    (assert (= (bit/bitCount "I64") "call i64 @llvm.ctpop.i64(i64 %a)") "bitCount on I64")
    (assert (= (bit/leadingZeros "U16") "call i16 @llvm.ctlz.i16(i16 %a, i1 false)") "leadingZeros uses ctlz with false")
    (assert (= (bit/trailingZeros "U16") "call i16 @llvm.cttz.i16(i16 %a, i1 false)") "trailingZeros uses cttz with false")
    (assert (= (bit/byteSwap "U16") "call i16 @llvm.bswap.i16(i16 %a)") "byteSwap uses bswap")
    true)

fn ! runTests -> Bool
  (do
    (testWidths)
    (testSigned)
    (testBinaryOps)
    (testBinaryOpsText)
    (testRotate)
    (testCount)
    (testByteSwap)
    (testNamedOps)
    true)
