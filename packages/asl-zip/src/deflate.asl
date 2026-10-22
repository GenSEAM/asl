(module asl-zip/deflate
  :x [deflate! deflateWithLevel! deflateBitWrite!]
  :i [])

fn reverseBits code: Int64 len: Int64 acc: Int64 -> Int64
  (if (= len 0) acc
    (reverseBits (>> code 1) (- len 1) (+ (* acc 2) (mod code 2))))

fn deflateBitWrite! out: Bytes pos: Int64 bit: Int64 -> (Result Int64 String)
  (if (or (or (< pos 0) (>= (>> pos 3) (bytesLength out)))
          (or (< bit 0) (> bit 1)))
    (err "bit writer position or value is out of bounds")
    (do
      (bytesSet out (>> pos 3)
        (+ (bytesGet out (>> pos 3)) (<< bit (mod pos 8)))
        )
      (ok (+ pos 1))))

fn emitBit! out: Bytes pos: Int64 bit: Int64 -> Int64
  (match (deflateBitWrite! out pos bit)
    ((err _) (assert false "internal DEFLATE bit write exceeded its buffer"))
    ((ok next) next))

fn emitBits! out: Bytes pos: Int64 value: Int64 count: Int64 -> Int64
  (if (= count 0) pos
    (emitBits! out (emitBit! out pos (mod value 2)) (>> value 1) (- count 1)))

fn fixedCode! out: Bytes pos: Int64 sym: Int64 -> Int64
  (cond
    ((<= sym 143) (emitBits! out pos (reverseBits (+ 48 sym) 8 0) 8))
    ((<= sym 255) (emitBits! out pos (reverseBits (+ 400 (- sym 144)) 9 0) 9))
    ((<= sym 279) (emitBits! out pos (reverseBits (- sym 256) 7 0) 7))
    (else (emitBits! out pos (reverseBits (+ 192 (- sym 280)) 8 0) 8)))

schema Match {
  matchLength: Int64
  matchDistance: Int64
}

fn get32! b: Bytes i: Int64 -> Int64
  (+ (bytesGet b i)
    (+ (<< (bytesGet b (+ i 1)) 8)
      (+ (<< (bytesGet b (+ i 2)) 16) (<< (bytesGet b (+ i 3)) 24))))

fn set32! b: Bytes i: Int64 v: Int64 -> Unit
  (do
    (bytesSet b i (mod v 256))
    (bytesSet b (+ i 1) (mod (>> v 8) 256))
    (bytesSet b (+ i 2) (mod (>> v 16) 256))
    (bytesSet b (+ i 3) (mod (>> v 24) 256)))

fn hashAt! data: Bytes i: Int64 end: Int64 -> Int64
  (mod (+ (* 251 (bytesGet data i))
    (+ (* 31 (bytesGet data (+ i 1))) (bytesGet data (+ i 2)))) 32768)

fn insertChain! data: Bytes heads: Bytes prev: Bytes i: Int64 end: Int64 -> Unit
  (if (>= (+ i 2) end) ()
    (let [(h (hashAt! data i end))
          (old (get32! heads (* h 4)))]
      (do
        (set32! prev (* i 4) old)
        (set32! heads (* h 4) (+ i 1)))))

fn insertRange! data: Bytes heads: Bytes prev: Bytes i: Int64 until: Int64 end: Int64 -> Unit
  (if (>= i until) ()
    (do
      (insertChain! data heads prev i end)
      (insertRange! data heads prev (+ i 1) until end)))

fn compareMatch! data: Bytes at: Int64 candidate: Int64 limit: Int64 k: Int64 -> Int64
  (if (>= k limit) k
    (if (= (bytesGet data (+ at k)) (bytesGet data (+ candidate k)))
      (compareMatch! data at candidate limit (+ k 1))
      k))

fn findChainMatch! data: Bytes heads: Bytes prev: Bytes at: Int64 end: Int64 candidatePlusOne: Int64 tries: Int64 best: Int64 bestDist: Int64 -> Match
  (let [(candidate (- candidatePlusOne 1))]
  (if (or (<= candidatePlusOne 0) (< candidate (max 0 (- at 32768))) (>= candidate at) (= tries 0) (>= best (min 258 (- end at))))
    (Match :matchLength best :matchDistance bestDist)
    (let [(limit (min 258 (- end at)))
          (matched (compareMatch! data at candidate limit 0))]
      (if (> matched best)
        (findChainMatch! data heads prev at end (get32! prev (* candidate 4)) (- tries 1) matched (- at candidate))
        (findChainMatch! data heads prev at end (get32! prev (* candidate 4)) (- tries 1) best bestDist)))))

fn lengthCode! out: Bytes pos: Int64 length: Int64 -> Int64
  (cond
    ((<= length 10) (fixedCode! out pos (+ 257 (- length 3))))
    ((<= length 18) (emitBits! out (fixedCode! out pos (+ 265 (>> (- length 11) 1))) (- length 11) 1))
    ((<= length 34) (emitBits! out (fixedCode! out pos (+ 269 (>> (- length 19) 2))) (- length 19) 2))
    ((<= length 66) (emitBits! out (fixedCode! out pos (+ 273 (>> (- length 35) 3))) (- length 35) 3))
    ((<= length 130) (emitBits! out (fixedCode! out pos (+ 277 (>> (- length 67) 4))) (- length 67) 4))
    ((<= length 257) (emitBits! out (fixedCode! out pos (+ 281 (>> (- length 131) 5))) (- length 131) 5))
    (else (fixedCode! out pos 285)))

fn distanceCode! out: Bytes pos: Int64 distance: Int64 code: Int64 base: Int64 -> Int64
  (let [(extra (max 0 (- (>> code 1) 1)))
        (span (<< 1 extra))]
    (if (<= distance (+ base span -1))
      (emitBits! out
        (emitBits! out pos (reverseBits code 5 0) 5)
        (- distance base) extra)
      (distanceCode! out pos distance (+ code 1) (+ base span))))

fn fixedTokens! data: Bytes i: Int64 end: Int64 heads: Bytes prev: Bytes chainLimit: Int64 out: Bytes pos: Int64 -> Int64
  (if (>= i end) (fixedCode! out pos 256)
    (let [(hash (if (< (+ i 2) end) (hashAt! data i end) 0))
          (head (if (< (+ i 2) end) (get32! heads (* hash 4)) 0))
          (match (findChainMatch! data heads prev i end head chainLimit 0 0))]
      (if (>= match.matchLength 3)
        (do
          (insertRange! data heads prev i (+ i match.matchLength) end)
          (fixedTokens! data (+ i match.matchLength) end heads prev chainLimit out
            (distanceCode! out
              (lengthCode! out pos match.matchLength)
              match.matchDistance 0 1)))
        (do
          (insertChain! data heads prev i end)
          (fixedTokens! data (+ i 1) end heads prev chainLimit out (fixedCode! out pos (bytesGet data i)))))))

fn dynLiteral! out: Bytes pos: Int64 sym: Int64 -> Int64
  (if (<= sym 225)
    (emitBits! out pos (reverseBits sym 8 0) 8)
    (emitBits! out pos (reverseBits (+ 452 (- sym 226)) 9 0) 9))

fn dynLength! out: Bytes pos: Int64 length: Int64 -> Int64
  (let [(sym (cond
          ((<= length 10) (+ 257 (- length 3)))
          ((<= length 18) (+ 265 (>> (- length 11) 1)))
          ((<= length 34) (+ 269 (>> (- length 19) 2)))
          ((<= length 66) (+ 273 (>> (- length 35) 3)))
          ((<= length 130) (+ 277 (>> (- length 67) 4)))
          ((<= length 257) (+ 281 (>> (- length 131) 5)))
          (else 285)))
        (base (cond
          ((<= sym 264) (- sym 254))
          ((<= sym 268) (+ 11 (* 2 (- sym 265))))
          ((<= sym 272) (+ 19 (* 4 (- sym 269))))
          ((<= sym 276) (+ 35 (* 8 (- sym 273))))
          ((<= sym 280) (+ 67 (* 16 (- sym 277))))
          ((<= sym 284) (+ 131 (* 32 (- sym 281))))
          (else 258)))
        (extra (cond
          ((<= sym 264) 0)
          ((<= sym 268) 1)
          ((<= sym 272) 2)
          ((<= sym 276) 3)
          ((<= sym 280) 4)
          ((<= sym 284) 5)
          (else 0)))
        (p1 (dynLiteral! out pos sym))]
    (emitBits! out p1 (- length base) extra))

fn distanceSymbol distance: Int64 code: Int64 base: Int64 -> Int64
  (let [(extra (max 0 (- (>> code 1) 1)))
        (span (<< 1 extra))]
    (if (<= distance (- (+ base span) 1)) code
      (distanceSymbol distance (+ code 1) (+ base span))))

schema MinPair {
  first: Int64
  second: Int64
}

fn minActivePair! weights: Bytes active: Bytes end: Int64 i: Int64 first: Int64 second: Int64 -> MinPair
  (if (>= i end) (MinPair :first first :second second)
    (if (= (bytesGet active i) 0)
      (minActivePair! weights active end (+ i 1) first second)
      (let [(weight (get32! weights (* i 4)))]
        (if (or (< first 0) (< weight (get32! weights (* first 4))))
          (minActivePair! weights active end (+ i 1) i first)
          (if (or (< second 0) (< weight (get32! weights (* second 4))))
            (minActivePair! weights active end (+ i 1) first i)
            (minActivePair! weights active end (+ i 1) first second))))))

fn buildTree! weights: Bytes left: Bytes right: Bytes active: Bytes n: Int64 node: Int64 activeCount: Int64 -> Int64
  (if (<= activeCount 1) node
    (let [(pair (minActivePair! weights active node 0 -1 -1))
          (a pair.first)
          (b pair.second)]
      (do
        (bytesSet active a 0) (bytesSet active b 0)
        (set32! left (* node 4) (+ a 1))
        (set32! right (* node 4) (+ b 1))
        (set32! weights (* node 4) (+ (get32! weights (* a 4)) (get32! weights (* b 4))))
        (bytesSet active node 1)
        (buildTree! weights left right active n (+ node 1) (- activeCount 1)))))

fn assignTreeDepth! left: Bytes right: Bytes lengths: Bytes n: Int64 node: Int64 depth: Int64 -> Unit
  (if (< node n)
    (bytesSet lengths node depth)
    (do
      (assignTreeDepth! left right lengths n (- (get32! left (* node 4)) 1) (+ depth 1))
      (assignTreeDepth! left right lengths n (- (get32! right (* node 4)) 1) (+ depth 1))))

fn countLimitedLengths! lengths: Bytes n: Int64 i: Int64 counts: Bytes overflow: Int64 -> Int64
  (if (>= i n) overflow
    (let [(length (bytesGet lengths i))]
      (if (= length 0)
        (countLimitedLengths! lengths n (+ i 1) counts overflow)
        (let [(limited (min 15 length))]
          (do
            (bytesSet lengths i limited)
            (bytesSet counts limited (+ (bytesGet counts limited) 1))
            (countLimitedLengths! lengths n (+ i 1) counts (+ overflow (if (> length 15) 1 0))))))))

fn repairLengthCounts! counts: Bytes overflow: Int64 -> Unit
  (if (<= overflow 0) ()
    (let [(bits (repairLengthSource! counts 14))]
      (do
        (bytesSet counts bits (- (bytesGet counts bits) 1))
        (bytesSet counts (+ bits 1) (+ (bytesGet counts (+ bits 1)) 2))
        (bytesSet counts 15 (- (bytesGet counts 15) 1))
        (repairLengthCounts! counts (- overflow 2)))))

fn repairLengthSource! counts: Bytes bits: Int64 -> Int64
  (if (or (< bits 1) (> (bytesGet counts bits) 0)) bits
    (repairLengthSource! counts (- bits 1)))

fn minSymbol! freq: Bytes active: Bytes n: Int64 i: Int64 best: Int64 -> Int64
  (if (>= i n) best
    (if (= (bytesGet active i) 0)
      (minSymbol! freq active n (+ i 1) best)
      (if (or (< best 0) (< (get32! freq (* i 4)) (get32! freq (* best 4))))
        (minSymbol! freq active n (+ i 1) i)
        (minSymbol! freq active n (+ i 1) best))))

fn assignLimitedLength! freq: Bytes active: Bytes lengths: Bytes counts: Bytes n: Int64 bits: Int64 -> Unit
  (if (< bits 1) ()
    (assignLengthSymbols! freq active lengths counts n bits (bytesGet counts bits)))

fn assignLengthSymbols! freq: Bytes active: Bytes lengths: Bytes counts: Bytes n: Int64 bits: Int64 remaining: Int64 -> Unit
  (if (= remaining 0)
    (assignLimitedLength! freq active lengths counts n (- bits 1))
    (let [(sym (minSymbol! freq active n 0 -1))]
      (do
        (bytesSet active sym 0)
        (bytesSet lengths sym bits)
        (assignLengthSymbols! freq active lengths counts n bits (- remaining 1)))))

fn limitHuffmanLengths! freq: Bytes lengths: Bytes n: Int64 -> Unit
  (let [(counts (bytesAlloc 16))
        (overflow (countLimitedLengths! lengths n 0 counts 0))
        (active (bytesAlloc n))]
    (do
      (repairLengthCounts! counts overflow)
      (activateSymbols! freq active n 0)
      (assignLimitedLength! freq active lengths counts n 15)))

fn activateSymbols! freq: Bytes active: Bytes n: Int64 i: Int64 -> Unit
  (if (>= i n) ()
    (do
      (if (> (get32! freq (* i 4)) 0) (bytesSet active i 1) ())
      (activateSymbols! freq active n (+ i 1))))

fn buildLengths! freq: Bytes n: Int64 sym: Int64 weights: Bytes left: Bytes right: Bytes active: Bytes activeCount: Int64 -> Bytes
  (if (>= sym n)
    (let [(root (buildTree! weights left right active n n activeCount))
          (lengths (bytesAlloc n))]
      (do
        (assignTreeDepth! left right lengths n (- root 1) 0)
        (limitHuffmanLengths! freq lengths n)
        lengths))
    (let [(count (get32! freq (* sym 4)))]
      (do
        (set32! weights (* sym 4) count)
        (if (> count 0) (bytesSet active sym 1) ())
        (buildLengths! freq n (+ sym 1) weights left right active (+ activeCount (if (> count 0) 1 0))))))

fn huffmanLengths! freq: Bytes n: Int64 -> Bytes
  (let [(weights (bytesAlloc (* n 8)))
        (left (bytesAlloc (* n 8)))
        (right (bytesAlloc (* n 8)))
        (active (bytesAlloc (* n 2)))]
    (buildLengths! freq n 0 weights left right active 0))

fn countLength! counts: Bytes lengths: Bytes n: Int64 i: Int64 -> Unit
  (if (>= i n) ()
    (let [(length (bytesGet lengths i))]
      (do
        (if (> length 0) (bytesSet counts length (+ (bytesGet counts length) 1)) ())
        (countLength! counts lengths n (+ i 1)))))

fn canonicalNext! counts: Bytes next: Bytes bits: Int64 code: Int64 -> Unit
  (if (> bits 15) ()
    (let [(code1 (<< (+ code (bytesGet counts (- bits 1))) 1))]
      (do
        (set32! next (* bits 4) code1)
        (canonicalNext! counts next (+ bits 1) code1))))

fn canonicalCodes! lengths: Bytes codes: Bytes next: Bytes n: Int64 sym: Int64 -> Unit
  (if (>= sym n) ()
    (let [(length (bytesGet lengths sym))]
      (do
        (if (> length 0)
          (let [(code (get32! next (* length 4)))]
            (do
              (set32! codes (* sym 4) (reverseBits code length 0))
              (set32! next (* length 4) (+ code 1))))
          ())
        (canonicalCodes! lengths codes next n (+ sym 1)))))

fn makeCodes! lengths: Bytes n: Int64 -> Bytes
  (let [(counts (bytesAlloc 16))
        (next (bytesAlloc 64))
        (codes (bytesAlloc (* n 4)))]
    (do
      (countLength! counts lengths n 0)
      (canonicalNext! counts next 1 0)
      (canonicalCodes! lengths codes next n 0)
      codes))

fn countLiteralFreq! data: Bytes i: Int64 end: Int64 freq: Bytes -> Unit
  (if (>= i end) ()
    (let [(sym (bytesGet data i))
          (slot (* sym 4))]
      (do
        (set32! freq slot (+ (get32! freq slot) 1))
        (countLiteralFreq! data (+ i 1) end freq))))

fn lengthRun! lengths: Bytes i: Int64 n: Int64 value: Int64 count: Int64 -> Int64
  (if (or (>= (+ i count) n) (!= (bytesGet lengths (+ i count)) value)
          (>= count (- n i))) count
    (lengthRun! lengths i n value (+ count 1)))

fn emitLengthCode! out: Bytes pos: Int64 sym: Int64 extra: Int64 width: Int64 -> Int64
  (if (<= sym 12)
    (emitBits! out (emitBits! out pos (reverseBits sym 4 0) 4) extra width)
    (emitBits! out (emitBits! out pos (reverseBits (+ 26 (- sym 13)) 5 0) 5) extra width))

fn emitLengthRun! out: Bytes pos: Int64 value: Int64 remaining: Int64 -> Int64
  (if (= remaining 0) pos
    (if (= value 0)
      (if (>= remaining 11)
        (let [(count (min 138 remaining))]
          (emitLengthRun! out (emitLengthCode! out pos 18 (- count 11) 7) value (- remaining count)))
        (if (>= remaining 3)
          (let [(count (min 10 remaining))]
            (emitLengthRun! out (emitLengthCode! out pos 17 (- count 3) 3) value (- remaining count)))
          (emitLengthRun! out (emitLengthCode! out pos 0 0 0) value (- remaining 1))))
      (if (>= remaining 4)
        (let [(count (min 6 remaining))
              (p1 (emitLengthCode! out pos value 0 0))]
          (emitLengthRun! out (emitLengthCode! out p1 16 (- count 4) 2) value (- remaining count)))
        (emitLengthRun! out (emitLengthCode! out pos value 0 0) value (- remaining 1)))))

fn emitLengthSequence! out: Bytes pos: Int64 lengths: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n) pos
    (let [(value (bytesGet lengths i))
          (count (lengthRun! lengths i n value 0))]
      (emitLengthSequence! out (emitLengthRun! out pos value count) lengths (+ i count) n)))

fn dynamicLiteralData! data: Bytes i: Int64 end: Int64 lengths: Bytes codes: Bytes out: Bytes pos: Int64 -> Int64
  (if (>= i end)
    (emitBits! out pos (get32! codes (* 256 4)) (bytesGet lengths 256))
    (let [(sym (bytesGet data i))]
      (dynamicLiteralData! data (+ i 1) end lengths codes out
        (emitBits! out pos (get32! codes (* sym 4)) (bytesGet lengths sym)))))

fn dynamicLiteralHeader! out: Bytes pos: Int64 final: Bool lengths: Bytes -> Int64
  (let [(p1 (emitBits! out pos (if final 1 0) 1))
        (p2 (emitBits! out p1 2 2))
        (p3 (emitBits! out p2 0 5))
        (p4 (emitBits! out p3 0 5))
        (p5 (emitBits! out p4 15 4))
        (order (bytesAlloc 19))]
    (do
      (bytesSet order 0 16) (bytesSet order 1 17) (bytesSet order 2 18)
      (bytesSet order 3 0) (bytesSet order 4 8) (bytesSet order 5 7)
      (bytesSet order 6 9) (bytesSet order 7 6) (bytesSet order 8 10)
      (bytesSet order 9 5) (bytesSet order 10 11) (bytesSet order 11 4)
      (bytesSet order 12 12) (bytesSet order 13 3) (bytesSet order 14 13)
      (bytesSet order 15 2) (bytesSet order 16 14) (bytesSet order 17 1)
      (bytesSet order 18 15)
      (dynamicLiteralHeaderCodes! out p5 order lengths 0)))

fn dynamicLiteralHeaderCodes! out: Bytes pos: Int64 order: Bytes lengths: Bytes i: Int64 -> Int64
  (if (>= i 19)
    (dynamicLiteralHeaderLengths! out pos lengths 0)
    (let [(sym (bytesGet order i))
          (len (if (<= sym 12) 4 5))]
      (dynamicLiteralHeaderCodes! out (emitBits! out pos len 3) order lengths (+ i 1))))

fn dynamicLiteralHeaderLengths! out: Bytes pos: Int64 lengths: Bytes sym: Int64 -> Int64
  (if (>= sym 257)
    (let [(all (bytesAlloc 258))]
      (do
        (copyBytes! all lengths 0 257)
        (bytesSet all 257 1)
        (emitLengthSequence! out pos all 0 258)))
    (dynamicLiteralHeaderLengths! out pos lengths (+ sym 1)))

fn distanceBase code: Int64 cur: Int64 -> Int64
  (if (= code 0) cur
    (distanceBase (- code 1) (+ cur (<< 1 (max 0 (- (>> (- code 1) 1) 1))))))

fn dynDistance! out: Bytes pos: Int64 distance: Int64 -> Int64
  (let [(sym (distanceSymbol distance 0 1))
        (base (distanceBase sym 1))
        (extra (max 0 (- (>> sym 1) 1)))
        (code (if (<= sym 1) sym (+ 4 (- sym 2))))
        (width (if (<= sym 1) 4 5))]
    (emitBits! out (emitBits! out pos (reverseBits code width 0) width) (- distance base) extra))

fn dynamicTokens! data: Bytes i: Int64 end: Int64 heads: Bytes prev: Bytes chainLimit: Int64 out: Bytes pos: Int64 -> Int64
  (if (>= i end) (dynLiteral! out pos 256)
    (let [(hash (if (< (+ i 2) end) (hashAt! data i end) 0))
          (head (if (< (+ i 2) end) (get32! heads (* hash 4)) 0))
          (match (findChainMatch! data heads prev i end head chainLimit 0 0))]
      (if (>= match.matchLength 3)
        (do
          (insertRange! data heads prev i (+ i match.matchLength) end)
          (dynamicTokens! data (+ i match.matchLength) end heads prev chainLimit out
            (dynDistance! out
              (dynLength! out pos match.matchLength)
              match.matchDistance)))
        (do
          (insertChain! data heads prev i end)
          (dynamicTokens! data (+ i 1) end heads prev chainLimit out
            (dynLiteral! out pos (bytesGet data i)))))))

fn dynamicLengthSymbol length: Int64 -> Int64
  (cond
    ((<= length 10) (+ 257 (- length 3)))
    ((<= length 18) (+ 265 (>> (- length 11) 1)))
    ((<= length 34) (+ 269 (>> (- length 19) 2)))
    ((<= length 66) (+ 273 (>> (- length 35) 3)))
    ((<= length 130) (+ 277 (>> (- length 67) 4)))
    ((<= length 257) (+ 281 (>> (- length 131) 5)))
    (else 285))

fn countDynamicTokens! data: Bytes i: Int64 end: Int64 heads: Bytes prev: Bytes chainLimit: Int64 literalFreq: Bytes distanceFreq: Bytes -> Unit
  (if (>= i end) (set32! literalFreq (* 256 4) (+ (get32! literalFreq (* 256 4)) 1))
    (let [(hash (if (< (+ i 2) end) (hashAt! data i end) 0))
          (head (if (< (+ i 2) end) (get32! heads (* hash 4)) 0))
          (match (findChainMatch! data heads prev i end head chainLimit 0 0))]
      (if (>= match.matchLength 3)
        (do
          (insertRange! data heads prev i (+ i match.matchLength) end)
          (let [(litSym (dynamicLengthSymbol match.matchLength))
                (distSym (distanceSymbol match.matchDistance 0 1))]
            (do
              (set32! literalFreq (* litSym 4) (+ (get32! literalFreq (* litSym 4)) 1))
              (set32! distanceFreq (* distSym 4) (+ (get32! distanceFreq (* distSym 4)) 1))
              (countDynamicTokens! data (+ i match.matchLength) end heads prev chainLimit literalFreq distanceFreq))))
        (do
          (insertChain! data heads prev i end)
          (let [(sym (bytesGet data i))]
            (do
              (set32! literalFreq (* sym 4) (+ (get32! literalFreq (* sym 4)) 1))
              (countDynamicTokens! data (+ i 1) end heads prev chainLimit literalFreq distanceFreq)))))))

fn emitDynamicLength! out: Bytes pos: Int64 value: Int64 lengths: Bytes codes: Bytes -> Int64
  (let [(sym (dynamicLengthSymbol value))
        (base (cond
          ((<= sym 264) (- sym 254))
          ((<= sym 268) (+ 11 (* 2 (- sym 265))))
          ((<= sym 272) (+ 19 (* 4 (- sym 269))))
          ((<= sym 276) (+ 35 (* 8 (- sym 273))))
          ((<= sym 280) (+ 67 (* 16 (- sym 277))))
          ((<= sym 284) (+ 131 (* 32 (- sym 281))))
          (else 258)))
        (extra (cond
          ((<= sym 264) 0) ((<= sym 268) 1) ((<= sym 272) 2)
          ((<= sym 276) 3) ((<= sym 280) 4) ((<= sym 284) 5) (else 0)))]
    (emitBits! out (emitBits! out pos (get32! codes (* sym 4)) (bytesGet lengths sym)) (- value base) extra))

fn emitDynamicDistance! out: Bytes pos: Int64 distance: Int64 lengths: Bytes codes: Bytes -> Int64
  (let [(sym (distanceSymbol distance 0 1))
        (base (distanceBase sym 1))
        (extra (max 0 (- (>> sym 1) 1)))]
    (emitBits! out (emitBits! out pos (get32! codes (* sym 4)) (bytesGet lengths sym)) (- distance base) extra))

fn dynamicTokenData! data: Bytes i: Int64 end: Int64 heads: Bytes prev: Bytes chainLimit: Int64 literalLengths: Bytes literalCodes: Bytes distanceLengths: Bytes distanceCodes: Bytes out: Bytes pos: Int64 -> Int64
  (if (>= i end)
    (emitBits! out pos (get32! literalCodes (* 256 4)) (bytesGet literalLengths 256))
    (let [(hash (if (< (+ i 2) end) (hashAt! data i end) 0))
          (head (if (< (+ i 2) end) (get32! heads (* hash 4)) 0))
          (match (findChainMatch! data heads prev i end head chainLimit 0 0))]
      (if (>= match.matchLength 3)
        (do
          (insertRange! data heads prev i (+ i match.matchLength) end)
          (dynamicTokenData! data (+ i match.matchLength) end heads prev chainLimit literalLengths literalCodes distanceLengths distanceCodes out
            (emitDynamicDistance! out
              (emitDynamicLength! out pos match.matchLength literalLengths literalCodes)
              match.matchDistance distanceLengths distanceCodes)))
        (do
          (insertChain! data heads prev i end)
          (let [(sym (bytesGet data i))]
            (dynamicTokenData! data (+ i 1) end heads prev chainLimit literalLengths literalCodes distanceLengths distanceCodes out
              (emitBits! out pos (get32! literalCodes (* sym 4)) (bytesGet literalLengths sym))))))))

fn dynamicHeader! out: Bytes pos: Int64 final: Bool literalLengths: Bytes distanceLengths: Bytes -> Int64
  (let [(p1 (emitBits! out pos (if final 1 0) 1))
        (p2 (emitBits! out p1 2 2))
        (p3 (emitBits! out p2 29 5))
        (p4 (emitBits! out p3 29 5))
        (p5 (emitBits! out p4 15 4))
        (order (bytesAlloc 19))
        (all (bytesAlloc 316))]
    (do
      (bytesSet order 0 16) (bytesSet order 1 17) (bytesSet order 2 18)
      (bytesSet order 3 0) (bytesSet order 4 8) (bytesSet order 5 7)
      (bytesSet order 6 9) (bytesSet order 7 6) (bytesSet order 8 10)
      (bytesSet order 9 5) (bytesSet order 10 11) (bytesSet order 11 4)
      (bytesSet order 12 12) (bytesSet order 13 3) (bytesSet order 14 13)
      (bytesSet order 15 2) (bytesSet order 16 14) (bytesSet order 17 1)
      (bytesSet order 18 15)
      (copyBytes! all literalLengths 0 286)
      (copyDistanceLengths! all distanceLengths 0)
      (dynamicHeaderLengths! out p5 order all 0)))

fn copyDistanceLengths! all: Bytes lengths: Bytes i: Int64 -> Unit
  (if (< i 30)
    (do
      (bytesSet all (+ 286 i) (bytesGet lengths i))
      (copyDistanceLengths! all lengths (+ i 1)))
    ())


fn dynamicHeaderLengths! out: Bytes pos: Int64 order: Bytes lengths: Bytes i: Int64 -> Int64
  (if (>= i 19)
    (emitLengthSequence! out pos lengths 0 316)
    (let [(sym (bytesGet order i))
          (len (if (<= sym 12) 4 5))]
      (dynamicHeaderLengths! out (emitBits! out pos len 3) order lengths (+ i 1))))

fn codeLengthCode! out: Bytes pos: Int64 value: Int64 -> Int64
  (if (<= value 12)
    (emitBits! out pos (reverseBits value 4 0) 4)
    (emitBits! out pos (reverseBits (+ 26 (- value 13)) 5 0) 5))

fn emitRun! out: Bytes pos: Int64 value: Int64 count: Int64 -> Int64
  (if (= count 0) pos
    (let [(p1 (codeLengthCode! out pos value))
          (remaining (- count 1))]
      (emitRunRest! out p1 value remaining)))

fn emitRunRest! out: Bytes pos: Int64 value: Int64 remaining: Int64 -> Int64
  (if (= remaining 0) pos
    (if (>= remaining 3)
      (let [(repeat (min 6 remaining))
            (p1 (emitBits! out pos (reverseBits 7 3 0) 3))]
        (emitRunRest! out (emitBits! out p1 (- repeat 3) 2) value (- remaining repeat)))
      (emitRunRest! out (codeLengthCode! out pos value) value (- remaining 1))))

fn dynamicBlocks! data: Bytes n: Int64 start: Int64 chainLimit: Int64 out: Bytes pos: Int64 -> Int64
  (let [(count (min 65535 (- n start)))
        (final (= (+ start count) n))
        (literalFreq (bytesAlloc (* 286 4)))
        (distanceFreq (bytesAlloc (* 30 4)))
        (countHeads (bytesAlloc (* 32768 4)))
        (countPrev (bytesAlloc (* (bytesLength data) 4)))]
    (do
      (countDynamicTokens! data start (+ start count) countHeads countPrev chainLimit literalFreq distanceFreq)
      (if (= count 0) (set32! literalFreq 0 1) ())
      (if (= (get32! distanceFreq 0) 0) (set32! distanceFreq 0 1) ())
      (if (= (get32! distanceFreq 4) 0) (set32! distanceFreq 4 1) ())
      (let [(literalLengths (huffmanLengths! literalFreq 286))
            (distanceLengths (huffmanLengths! distanceFreq 30))
            (literalCodes (makeCodes! literalLengths 286))
            (distanceCodes (makeCodes! distanceLengths 30))
            (p1 (dynamicHeader! out pos final literalLengths distanceLengths))
            (heads (bytesAlloc (* 32768 4)))
            (prev (bytesAlloc (* (bytesLength data) 4)))
            (p2 (dynamicTokenData! data start (+ start count) heads prev chainLimit literalLengths literalCodes distanceLengths distanceCodes out p1))]
        (if final p2 (dynamicBlocks! data n (+ start count) chainLimit out p2)))))

fn fixedBlocks! data: Bytes n: Int64 start: Int64 chainLimit: Int64 out: Bytes pos: Int64 -> Int64
  (let [(count (min 65535 (- n start)))
        (final (= (+ start count) n))]
    (let [(p1 (emitBits! out pos (if final 1 0) 1))
          (p2 (emitBits! out p1 1 2))]
      (let [(heads (bytesAlloc (* 32768 4)))
            (prev (bytesAlloc (* (bytesLength data) 4)))
            (p3 (fixedTokens! data start (+ start count) heads prev chainLimit out p2))]
        (if final p3 (fixedBlocks! data n (+ start count) chainLimit out p3)))))

fn storedPayload! data: Bytes i: Int64 end: Int64 out: Bytes pos: Int64 -> Int64
  (if (>= i end) pos
    (storedPayload! data (+ i 1) end out (emitBits! out pos (bytesGet data i) 8)))

fn storedBlocks! data: Bytes n: Int64 start: Int64 out: Bytes pos: Int64 -> Int64
  (let [(count (min 65535 (- n start)))
        (final (= (+ start count) n))]
    (let [(p1 (emitBits! out pos (if final 1 0) 1))
          (p2 (emitBits! out p1 0 2))
          (p3 (if (= (mod p2 8) 0) p2 (emitBits! out p2 0 (- 8 (mod p2 8)))))
          (p4 (emitBits! out p3 count 16))
          (p5 (emitBits! out p4 (- 65535 count) 16))
          (p6 (storedPayload! data start (+ start count) out p5))]
      (if final p6 (storedBlocks! data n (+ start count) out p6))))

fn copyBytes! dst: Bytes src: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet dst i (bytesGet src i))
      (copyBytes! dst src (+ i 1) n)))

fn exact! out: Bytes n: Int64 -> Bytes
  (if (= (bytesLength out) n) out
    (let [(fresh (bytesAlloc n))]
      (do (copyBytes! fresh out 0 n) fresh)))

fn bestFastBlock! data: Bytes n: Int64 capacity: Int64 -> Bytes
  (let [(fixedOut (bytesAlloc capacity))
        (storedOut (bytesAlloc capacity))
        (fixedBits (fixedBlocks! data n 0 16 fixedOut 0))
        (storedBits (storedBlocks! data n 0 storedOut 0))]
    (if (<= fixedBits storedBits)
      (exact! fixedOut (>> (+ fixedBits 7) 3))
      (exact! storedOut (>> (+ storedBits 7) 3))))

fn bestLevelSixBlock! data: Bytes n: Int64 capacity: Int64 -> Bytes
  (let [(fixedOut (bytesAlloc capacity))
        (dynamicOut (bytesAlloc capacity))
        (storedOut (bytesAlloc capacity))
        (fixedBits (fixedBlocks! data n 0 96 fixedOut 0))
        (dynamicBits (dynamicBlocks! data n 0 96 dynamicOut 0))
        (storedBits (storedBlocks! data n 0 storedOut 0))]
    (if (and (<= fixedBits dynamicBits) (<= fixedBits storedBits))
      (exact! fixedOut (>> (+ fixedBits 7) 3))
      (if (<= dynamicBits storedBits)
        (exact! dynamicOut (>> (+ dynamicBits 7) 3))
        (exact! storedOut (>> (+ storedBits 7) 3)))))

fn deflateWithLevel! data: Bytes level: Int64 -> (Result Bytes String)
  (let [(n (bytesLength data))]
    (if (not (or (= level 0) (= level 1) (= level 6)))
      (err "unsupported deflate level")
      (let [(capacity (+ (* 2 n) 256))]
        (if (= level 1)
          (ok (bestFastBlock! data n capacity))
          (if (= level 6)
            (ok (bestLevelSixBlock! data n capacity))
            (let [(out (bytesAlloc capacity))
                  (bits (storedBlocks! data n 0 out 0))]
              (ok (exact! out (>> (+ bits 7) 3)))))))))

fn deflate! data: Bytes -> (Result Bytes String)
  (deflateWithLevel! data 6)
