(module asl-compiler/wasmLeb128Test :x [testLeb128U32Zero testLeb128U32MultiByte testLeb128I32NegativeOne testLeb128I32Negative128 testLeb128I32Boundaries testEncodeUtf8 testByteLength runTests] :i [(wasm :a w)])

fn testLeb128U32Zero -> Bool
  (let [(res (w/leb128EncodeU32 0))] (assert (= res (list 0)) "LEB128 U32 0 must produce [0]") (refute (listEmpty? res) "LEB128 U32 0 must not be empty") (refute (= (optionOr (listGet res 0) -1) 128) "LEB128 U32 0 must not have continuation bit set") true)

fn testLeb128U32MultiByte -> Bool
  (let [(res1 (w/leb128EncodeU32 1)) (res127 (w/leb128EncodeU32 127)) (res128 (w/leb128EncodeU32 128)) (res624485 (w/leb128EncodeU32 624485))] (assert (= res1 (list 1)) "LEB128 U32 1 must produce [1]") (assert (= res127 (list 127)) "LEB128 U32 127 must produce [127]") (assert (= res128 (list 128 1)) "LEB128 U32 128 must produce [128 1]") (assert (= res624485 (list 229 142 38)) "LEB128 U32 624485 must produce [229 142 38]") (refute (= res624485 (list 229 142)) "LEB128 U32 624485 must not truncate to 2 bytes") true)

fn testLeb128I32NegativeOne -> Bool
  (let [(res (w/leb128EncodeI32 -1))] (assert (= res (list 127)) "LEB128 I32 -1 must produce [127]") (refute (= res (list 255)) "LEB128 I32 -1 must not produce [255]") (refute (listEmpty? res) "LEB128 I32 -1 must not be empty") true)

fn testLeb128I32Negative128 -> Bool
  (let [(res (w/leb128EncodeI32 -128))] (assert (= res (list 128 127)) "LEB128 I32 -128 must produce [128 127]") (refute (= res (list 128)) "LEB128 I32 -128 must require sign continuation byte") true)

fn testLeb128I32Boundaries -> Bool
  (let [(res0 (w/leb128EncodeI32 0)) (res63 (w/leb128EncodeI32 63)) (res64 (w/leb128EncodeI32 64)) (resNeg64 (w/leb128EncodeI32 -64)) (resNeg65 (w/leb128EncodeI32 -65)) (res127 (w/leb128EncodeI32 127)) (res128 (w/leb128EncodeI32 128))] (assert (= res0 (list 0)) "LEB128 I32 0 must produce [0]") (assert (= res63 (list 63)) "LEB128 I32 63 must produce [63]") (assert (= res64 (list 192 0)) "LEB128 I32 64 must produce [192 0]") (assert (= resNeg64 (list 64)) "LEB128 I32 -64 must produce [64]") (assert (= resNeg65 (list 191 127)) "LEB128 I32 -65 must produce [191 127]") (assert (= res127 (list 255 0)) "LEB128 I32 127 must produce [255 0]") (assert (= res128 (list 128 1)) "LEB128 I32 128 must produce [128 1]") (refute (= res64 (list 64)) "LEB128 I32 64 without sign bit padding would be negative") true)

fn testEncodeUtf8 -> Bool
  (let [(emptyBytes (w/encodeUtf8 "")) (helloBytes (w/encodeUtf8 "hello")) (memBytes (w/encodeUtf8 "memory"))] (assert (listEmpty? emptyBytes) "Empty string must encode to empty byte list") (refute (not (listEmpty? emptyBytes)) "Empty string must not contain bytes") (assert (= helloBytes (list 104 101 108 108 111)) "hello must encode to ASCII bytes") (assert (= memBytes (list 109 101 109 111 114 121)) "memory must encode to ASCII bytes") true)

fn testByteLength -> Bool
  (let [(b (list 10 20 30 40 50))] (assert (= (w/byteLength b) 5) "byteLength of 5 bytes must be 5") (refute (= (w/byteLength b) 0) "byteLength of non-empty list must not be 0") true)

fn runTests -> Bool
  (do (assert (testLeb128U32Zero) "testLeb128U32Zero must pass") (assert (testLeb128U32MultiByte) "testLeb128U32MultiByte must pass") (assert (testLeb128I32NegativeOne) "testLeb128I32NegativeOne must pass") (assert (testLeb128I32Negative128) "testLeb128I32Negative128 must pass") (assert (testLeb128I32Boundaries) "testLeb128I32Boundaries must pass") (assert (testEncodeUtf8) "testEncodeUtf8 must pass") (assert (testByteLength) "testByteLength must pass") true)
