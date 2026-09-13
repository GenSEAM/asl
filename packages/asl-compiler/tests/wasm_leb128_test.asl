(module asl-compiler/wasm-leb128-test
  :d "Unit tests for pure ASL LEB128 variable-length integer encoding and byte vector primitives."
  :x [testLeb128U32Zero
      testLeb128U32MultiByte
      testLeb128I32NegativeOne
      testLeb128I32Negative128
      testLeb128I32Boundaries
      testEncodeUtf8
      testByteLength
      runTests]
  :i [(wasm :a w)])

(df testLeb128U32Zero [] -> Bool
  :d "Verifies unsigned LEB128 encoding of zero."
  (let [(res (w/leb128EncodeU32 0))]
    (assert (= res (list 0)) "LEB128 U32 0 must produce [0]")
    (refute (list-empty? res) "LEB128 U32 0 must not be empty")
    (refute (= (option-or (list-get res 0) -1) 128) "LEB128 U32 0 must not have continuation bit set")
    true))

(df testLeb128U32MultiByte [] -> Bool
  :d "Verifies unsigned LEB128 encoding of multi-byte numbers."
  (let [(res1 (w/leb128EncodeU32 1))
        (res127 (w/leb128EncodeU32 127))
        (res128 (w/leb128EncodeU32 128))
        (res624485 (w/leb128EncodeU32 624485))]
    (assert (= res1 (list 1)) "LEB128 U32 1 must produce [1]")
    (assert (= res127 (list 127)) "LEB128 U32 127 must produce [127]")
    (assert (= res128 (list 128 1)) "LEB128 U32 128 must produce [128 1]")
    (assert (= res624485 (list 229 142 38)) "LEB128 U32 624485 must produce [229 142 38]")
    (refute (= res624485 (list 229 142)) "LEB128 U32 624485 must not truncate to 2 bytes")
    true))

(df testLeb128I32NegativeOne [] -> Bool
  :d "Verifies signed LEB128 encoding of -1."
  (let [(res (w/leb128EncodeI32 -1))]
    (assert (= res (list 127)) "LEB128 I32 -1 must produce [127]")
    (refute (= res (list 255)) "LEB128 I32 -1 must not produce [255]")
    (refute (list-empty? res) "LEB128 I32 -1 must not be empty")
    true))

(df testLeb128I32Negative128 [] -> Bool
  :d "Verifies signed LEB128 encoding of -128."
  (let [(res (w/leb128EncodeI32 -128))]
    (assert (= res (list 128 127)) "LEB128 I32 -128 must produce [128 127]")
    (refute (= res (list 128)) "LEB128 I32 -128 must require sign continuation byte")
    true))

(df testLeb128I32Boundaries [] -> Bool
  :d "Verifies signed LEB128 boundary cases."
  (let [(res0 (w/leb128EncodeI32 0))
        (res63 (w/leb128EncodeI32 63))
        (res64 (w/leb128EncodeI32 64))
        (resNeg64 (w/leb128EncodeI32 -64))
        (resNeg65 (w/leb128EncodeI32 -65))
        (res127 (w/leb128EncodeI32 127))
        (res128 (w/leb128EncodeI32 128))]
    (assert (= res0 (list 0)) "LEB128 I32 0 must produce [0]")
    (assert (= res63 (list 63)) "LEB128 I32 63 must produce [63]")
    (assert (= res64 (list 192 0)) "LEB128 I32 64 must produce [192 0]")
    (assert (= resNeg64 (list 64)) "LEB128 I32 -64 must produce [64]")
    (assert (= resNeg65 (list 191 127)) "LEB128 I32 -65 must produce [191 127]")
    (assert (= res127 (list 255 0)) "LEB128 I32 127 must produce [255 0]")
    (assert (= res128 (list 128 1)) "LEB128 I32 128 must produce [128 1]")
    (refute (= res64 (list 64)) "LEB128 I32 64 without sign bit padding would be negative")
    true))

(df testEncodeUtf8 [] -> Bool
  :d "Verifies UTF-8 string encoding into byte vector."
  (let [(emptyBytes (w/encodeUtf8 ""))
        (helloBytes (w/encodeUtf8 "hello"))
        (memBytes (w/encodeUtf8 "memory"))]
    (assert (list-empty? emptyBytes) "Empty string must encode to empty byte list")
    (refute (not (list-empty? emptyBytes)) "Empty string must not contain bytes")
    (assert (= helloBytes (list 104 101 108 108 111)) "hello must encode to ASCII bytes")
    (assert (= memBytes (list 109 101 109 111 114 121)) "memory must encode to ASCII bytes")
    true))

(df testByteLength [] -> Bool
  :d "Verifies byte vector length calculation."
  (let [(b (list 10 20 30 40 50))]
    (assert (= (w/byteLength b) 5) "byteLength of 5 bytes must be 5")
    (refute (= (w/byteLength b) 0) "byteLength of non-empty list must not be 0")
    true))

(df runTests [] -> Bool
  :d "Runs all LEB128 and byte vector unit tests."
  (do
    (assert (testLeb128U32Zero) "testLeb128U32Zero must pass")
    (assert (testLeb128U32MultiByte) "testLeb128U32MultiByte must pass")
    (assert (testLeb128I32NegativeOne) "testLeb128I32NegativeOne must pass")
    (assert (testLeb128I32Negative128) "testLeb128I32Negative128 must pass")
    (assert (testLeb128I32Boundaries) "testLeb128I32Boundaries must pass")
    (assert (testEncodeUtf8) "testEncodeUtf8 must pass")
    (assert (testByteLength) "testByteLength must pass")
    true))
