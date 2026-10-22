(module asl-zip/tests/deflateTest
  :x [runTests]
  :i [(asl-zip/deflate :a df) (asl-zip/inflate :a inf)])

fn sameBytes? a: Bytes b: Bytes i: Int64 -> Bool
  (cond
    ((!= (bytesLength a) (bytesLength b)) false)
    ((>= i (bytesLength a)) true)
    ((!= (bytesGet a i) (bytesGet b i)) false)
    (else (sameBytes? a b (+ i 1))))

fn ! roundTrip? plain: Bytes level: Int64 -> Bool
  (match (df/deflateWithLevel! plain level)
    ((err _) false)
    ((ok encoded)
      (match (inf/inflate! encoded)
        ((err _) false)
        ((ok decoded) (sameBytes? plain decoded 0)))))

fn fillRepeat! out: Bytes i: Int64 byte: Int64 -> Unit
  (if (>= i (bytesLength out)) ()
    (do (bytesSet out i byte) (fillRepeat! out (+ i 1) byte)))

fn fillLcg! out: Bytes i: Int64 state: Int64 -> Unit
  (if (>= i (bytesLength out)) ()
    (let [(next (mod (+ (* state 1103515245) 12345) 2147483648))]
      (do
        (bytesSet out i (lowBits (>> next 16) 8))
        (fillLcg! out (+ i 1) next))))

fn fillXor! out: Bytes i: Int64 state: Int64 -> Unit
  (if (>= i (bytesLength out)) ()
    (let [(a (mod (^ state (<< state 13)) 4294967296))
          (b (mod (^ a (>> a 17)) 4294967296))
          (next (mod (^ b (<< b 5)) 4294967296))]
      (do
        (bytesSet out i (lowBits (>> next 16) 8))
        (fillXor! out (+ i 1) next))))

fn fillDistinct! out: Bytes i: Int64 -> Unit
  (if (>= i (bytesLength out)) ()
    (do (bytesSet out i i) (fillDistinct! out (+ i 1))))

fn fillSymbol! out: Bytes i: Int64 end: Int64 byte: Int64 -> Unit
  (if (>= i end) ()
    (do (bytesSet out i byte) (fillSymbol! out (+ i 1) end byte)))

fn copyPrefix! data: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet data (+ 32768 i) (bytesGet data i))
      (copyPrefix! data (+ i 1) n)))

fn lowBits x: Int64 k: Int64 -> Int64
  (- x (<< (>> x k) k))

fn ! testRoundTrips! -> Bool
  (let [(empty (bytesAlloc 0))
        (one (stringToBytes "x"))
        (repeat (bytesAlloc 8192))
        (random (bytesAlloc 2048))
        (window (bytesAlloc 40000))
        (multi (bytesAlloc 70000))]
    (do
      (fillRepeat! repeat 0 65)
      (fillLcg! random 0 2463534242)
      (fillLcg! window 0 1234567)
      (fillLcg! multi 0 7654321)
      (assert (roundTrip? empty 0) "empty input round-trips at level 0")
      (assert (roundTrip? empty 1) "empty input round-trips at level 1")
      (assert (roundTrip? empty 6) "empty input round-trips at level 6")
      (assert (roundTrip? one 0) "one byte round-trips at level 0")
      (assert (roundTrip? one 1) "one byte round-trips at level 1")
      (assert (roundTrip? one 6) "one byte round-trips at level 6")
      (assert (roundTrip? repeat 0) "repetitive input round-trips at level 0")
      (assert (roundTrip? repeat 1) "repetitive input round-trips at level 1")
      (assert (roundTrip? repeat 6) "repetitive input round-trips at level 6")
      (assert (roundTrip? random 0) "fixed-seed LCG input round-trips at level 0")
      (assert (roundTrip? random 1) "fixed-seed LCG input round-trips at level 1")
      (assert (roundTrip? random 6) "fixed-seed LCG input round-trips at level 6")
      (assert (roundTrip? window 0) "window-crossing input round-trips at level 0")
      (assert (roundTrip? window 1) "window-crossing input round-trips at level 1")
      (assert (roundTrip? window 6) "window-crossing input round-trips at level 6")
      (assert (roundTrip? multi 0) "multi-block input round-trips at level 0")
      (assert (roundTrip? multi 1) "multi-block input round-trips at level 1")
      (assert (roundTrip? multi 6) "multi-block input round-trips at level 6")
      true))

fn ! testDynamicAndFixed! -> Bool
  (let [(text (bytesAlloc 8192))]
    (do
      (fillRepeat! text 0 65)
      (let [(stored (df/deflateWithLevel! text 0))
            (compressed (df/deflateWithLevel! text 6))
            (fixed (df/deflateWithLevel! text 1))]
      (assert (and (and (ok? stored) (ok? compressed)) (ok? fixed)) "stored, fixed and dynamic encodings are returned")
      (match stored
        ((err _) (assert false "stored encoding exists"))
        ((ok s)
          (match compressed
            ((err _) (assert false "dynamic text encoding exists"))
            ((ok c)
              (do
                (assert (= (lowBits (bytesGet c 0) 3) 5) "dynamic-Huffman block is selected for compressible text")
                (assert (< (bytesLength c) (bytesLength s)) "dynamic-Huffman text is smaller than stored")
                (match fixed
                  ((err _) (assert false "fixed encoding exists"))
                  ((ok f) (assert (= (lowBits (bytesGet f 0) 3) 3) "fixed-Huffman block is chosen at fast level")))
                true))))))
      true))

fn ! testFixedCostSelection! -> Bool
  (let [(tiny (stringToBytes "x"))
        (random (bytesAlloc 256))]
    (do
      (fillDistinct! random 0)
      (match (df/deflateWithLevel! tiny 1)
        ((err _) (assert false "fixed-cost tiny encoding exists"))
        ((ok f) (assert (= (lowBits (bytesGet f 0) 3) 3) "fixed block remains selected when cheaper")))
      (match (df/deflateWithLevel! random 1)
        ((err _) (assert false "stored-cost random encoding exists"))
        ((ok s)
          (do
            (assert (= (lowBits (bytesGet s 0) 3) 1) "stored block is selected when fixed coding costs more")
            (assert (roundTrip? random 1) "cost-selected stored block remains valid DEFLATE"))))
      true))

fn ! testFixedCostSelectionAtLevelSix! -> Bool
  (let [(tiny (stringToBytes "x"))]
    (match (df/deflateWithLevel! tiny 6)
      ((err _) (assert false "level-six tiny encoding exists"))
      ((ok encoded)
        (assert (= (lowBits (bytesGet encoded 0) 3) 3)
          "level six selects a fixed block when it costs less than dynamic")))
    true)

fn ! testFrequencyDerivedDynamic! -> Bool
  (let [(skewed (bytesAlloc 700))
        (balanced (bytesAlloc 700))]
    (do
      (fillSymbol! skewed 0 600 65) (fillSymbol! skewed 600 650 66) (fillSymbol! skewed 650 700 67)
      (fillSymbol! balanced 0 200 65) (fillSymbol! balanced 200 450 66) (fillSymbol! balanced 450 700 67)
      (match (df/deflateWithLevel! skewed 6)
        ((err _) (assert false "skewed dynamic encoding exists"))
        ((ok a)
          (match (df/deflateWithLevel! balanced 6)
            ((err _) (assert false "balanced dynamic encoding exists"))
            ((ok b)
              (assert (!= (bytesLength a) (bytesLength b)) "dynamic representation changes with token frequency distribution")))))
      true))

fn ! testDynamicUsesMatches! -> Bool
  (let [(repeat (bytesAlloc 8192))]
    (do
      (fillRepeat! repeat 0 65)
      (match (df/deflateWithLevel! repeat 6)
        ((err _) (assert false "dynamic repeated input encoding exists"))
        ((ok encoded)
          (do
            (assert (ok? (inf/inflate! encoded)) "dynamic LZ77 stream is valid DEFLATE")
            (assert (< (bytesLength encoded) (>> (bytesLength repeat) 3))
              "dynamic repeated input uses LZ77 matches, not literal-only coding")
            (assert (roundTrip? repeat 6) "dynamic LZ77 encoding round-trips"))))
      true))

fn ! testMaximumWindowMatch! -> Bool
  (let [(input (bytesAlloc 65535))]
    (do
      (fillXor! input 0 314159265)
      (copyPrefix! input 0 32767)
      (match (df/deflateWithLevel! input 6)
        ((err _) (assert false "maximum-window input encodes"))
        ((ok encoded)
          (do
            (assert (< (bytesLength encoded) (- (bytesLength input) 10000))
              "the copied half compresses using matches at the exact 32 KiB distance")
            (assert (roundTrip? input 6) "maximum-window match decodes to the original bytes"))))
      true))

fn ! testBitWriterBounds! -> Bool
  (let [(out (bytesAlloc 1))]
    (do
      (assert (ok? (df/deflateBitWrite! out 7 1)) "last bit in the buffer is writable")
      (assert (err? (df/deflateBitWrite! out 8 0)) "bit writer rejects the first bit beyond the buffer")
      (assert (err? (df/deflateBitWrite! out -1 0)) "bit writer rejects a negative bit position")
      (assert (err? (df/deflateBitWrite! out 0 2)) "bit writer rejects a non-bit value")
      true))

fn ! runTests -> Bool
  (do
    (testMaximumWindowMatch!)
    (testDynamicUsesMatches!)
    (testRoundTrips!)
    (testDynamicAndFixed!)
    (testFrequencyDerivedDynamic!)
    (testFixedCostSelection!)
    (testFixedCostSelectionAtLevelSix!)
    (testBitWriterBounds!)
    true)
