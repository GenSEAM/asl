(module asl-zstd/encode :x [zstdCompress] :i [])

fn writeByte! out: Bytes at: Int64 value: Int64 -> Unit
  (bytesSet out at (mod value 256))

fn writeLe! out: Bytes at: Int64 value: Int64 count: Int64 -> Unit
  (if (= count 0) (do)
    (do
      (writeByte! out at value)
      (writeLe! out (+ at 1) (/ value 256) (- count 1))))

fn sameByte? input: Bytes start: Int64 end: Int64 value: Int64 -> Bool
  (if (>= start end) true
    (and (= (bytesGet input start) value) (sameByte? input (+ start 1) end value)))

fn copyRaw! input: Bytes output: Bytes src: Int64 dst: Int64 end: Int64 -> Unit
  (if (>= src end) (do)
    (do (writeByte! output dst (bytesGet input src))
        (copyRaw! input output (+ src 1) (+ dst 1) end)))

fn readLe input: Bytes at: Int64 count: Int64 -> Int64
  (if (= count 0) 0
    (+ (bytesGet input at) (* 256 (readLe input (+ at 1) (- count 1)))))

fn matchLength! input: Bytes pos: Int64 candidate: Int64 end: Int64 n: Int64 -> Int64
  (if (or (>= (+ pos n) end) (>= n 131074) (not (= (bytesGet input (+ pos n)) (bytesGet input (+ candidate n))))) n
    (matchLength! input pos candidate end (+ n 1)))

fn findMatch! input: Bytes links: Bytes ref: Int64 pos: Int64 end: Int64 depth: Int64 window: Int64 bestPos: Int64 bestLen: Int64 -> Int64
  (if (or (= ref 0) (= depth 0) (>= bestLen (if (> (- end pos) 131074) 131074 (- end pos)))) (+ (* bestPos (+ end 1)) bestLen)
    (let [(candidate (- ref 1))
          (distance (- pos candidate))
          (len (if (and (> distance 0) (<= distance window) (>= (- end pos) 4)) (matchLength! input pos candidate end 0) 0))
          (newPos (if (> len bestLen) candidate bestPos))
          (newLen (if (> len bestLen) len bestLen))]
      (findMatch! input links (readLe links (* candidate 3) 3) pos end (- depth 1) window newPos newLen)))

fn insertPosition! input: Bytes head: Bytes links: Bytes pos: Int64 end: Int64 -> Unit
  (if (> (+ pos 3) end) (do)
    (let [(bucket (mod (+ (* (bytesGet input pos) 251) (* (bytesGet input (+ pos 1)) 31) (bytesGet input (+ pos 2))) 65536))
          (old (readLe head (* bucket 3) 3))]
      (do (writeLe! links (* pos 3) old 3)
          (writeLe! head (* bucket 3) (+ pos 1) 3)))
    )

fn insertRange! input: Bytes head: Bytes links: Bytes pos: Int64 end: Int64 -> Unit
  (if (>= pos end) (do)
    (do (insertPosition! input head links pos end)
        (insertRange! input head links (+ pos 1) end)))

fn findAt! input: Bytes head: Bytes links: Bytes pos: Int64 end: Int64 depth: Int64 window: Int64 -> Int64
  (if (< (- end pos) 3) 0
    (let [(bucket (mod (+ (* (bytesGet input pos) 251) (* (bytesGet input (+ pos 1)) 31) (bytesGet input (+ pos 2))) 65536))
          (ref (readLe head (* bucket 3) 3))
          (found (findMatch! input links ref pos end depth window 0 0))]
      (if (>= (mod found (+ end 1)) 6) found 0)))

fn llCode len: Int64 -> Int64
  (cond
    ((<= len 15) (* len 65536))
    ((<= len 17) (+ (* 16 65536) (- len 16)))
    ((<= len 19) (+ (* 17 65536) (- len 18)))
    ((<= len 21) (+ (* 18 65536) (- len 20)))
    ((<= len 23) (+ (* 19 65536) (- len 22)))
    ((<= len 27) (+ (* 20 65536) (- len 24)))
    ((<= len 31) (+ (* 21 65536) (- len 28)))
    ((<= len 39) (+ (* 22 65536) (- len 32)))
    ((<= len 47) (+ (* 23 65536) (- len 40)))
    ((<= len 63) (+ (* 24 65536) (- len 48)))
    ((<= len 127) (+ (* 25 65536) (- len 64)))
    ((<= len 255) (+ (* 26 65536) (- len 128)))
    ((<= len 511) (+ (* 27 65536) (- len 256)))
    ((<= len 1023) (+ (* 28 65536) (- len 512)))
    ((<= len 2047) (+ (* 29 65536) (- len 1024)))
    ((<= len 4095) (+ (* 30 65536) (- len 2048)))
    ((<= len 8191) (+ (* 31 65536) (- len 4096)))
    ((<= len 16383) (+ (* 32 65536) (- len 8192)))
    ((<= len 32767) (+ (* 33 65536) (- len 16384)))
    ((<= len 65535) (+ (* 34 65536) (- len 32768)))
    (else (+ (* 35 65536) (- len 65536))))

fn llBits code: Int64 -> Int64
  (if (<= code 15) 0 (if (<= code 19) 1 (if (<= code 21) 2 (if (<= code 23) 3 (if (= code 24) 4 (if (= code 25) 6 (+ code -19)))))))

fn mlCode len: Int64 -> Int64
  (cond
    ((<= len 34) (* (- len 3) 65536))
    ((<= len 36) (+ (* 32 65536) (- len 35)))
    ((<= len 38) (+ (* 33 65536) (- len 37)))
    ((<= len 40) (+ (* 34 65536) (- len 39)))
    ((<= len 42) (+ (* 35 65536) (- len 41)))
    ((<= len 46) (+ (* 36 65536) (- len 43)))
    ((<= len 50) (+ (* 37 65536) (- len 47)))
    ((<= len 58) (+ (* 38 65536) (- len 51)))
    ((<= len 66) (+ (* 39 65536) (- len 59)))
    ((<= len 82) (+ (* 40 65536) (- len 67)))
    ((<= len 98) (+ (* 41 65536) (- len 83)))
    ((<= len 130) (+ (* 42 65536) (- len 99)))
    ((<= len 258) (+ (* 43 65536) (- len 131)))
    ((<= len 514) (+ (* 44 65536) (- len 259)))
    ((<= len 1026) (+ (* 45 65536) (- len 515)))
    ((<= len 2050) (+ (* 46 65536) (- len 1027)))
    ((<= len 4098) (+ (* 47 65536) (- len 2051)))
    ((<= len 8194) (+ (* 48 65536) (- len 4099)))
    ((<= len 16386) (+ (* 49 65536) (- len 8195)))
    ((<= len 32770) (+ (* 50 65536) (- len 16387)))
    ((<= len 65538) (+ (* 51 65536) (- len 32771)))
    (else (+ (* 52 65536) (- len 65539))))

fn mlBits code: Int64 -> Int64
  (if (<= code 31) 0 (if (<= code 35) 1 (if (<= code 37) 2 (if (<= code 39) 3 (if (<= code 41) 4 (if (= code 42) 5 (if (= code 43) 7 (+ code -36))))))))

fn writeLiteralHeader! output: Bytes dst: Int64 len: Int64 -> Int64
  (if (< len 32)
    (do (writeByte! output dst (* len 8)) (+ dst 1))
    (if (< len 4096)
      (do
        (writeByte! output dst (+ 4 (* (mod len 16) 16)))
        (writeByte! output (+ dst 1) (/ len 16))
        (+ dst 2))
      (do
        (writeByte! output dst (+ 12 (* (mod len 16) 16)))
        (writeByte! output (+ dst 1) (mod (/ len 16) 256))
        (writeByte! output (+ dst 2) (/ len 4096))
        (+ dst 3))))

fn pow2 n: Int64 -> Int64
  (if (= n 0) 1 (* 2 (pow2 (- n 1))))

fn highBit n: Int64 -> Int64
  (if (< n 2) 0 (+ 1 (highBit (/ n 2))))

fn writePacked! output: Bytes dst: Int64 value: Int64 count: Int64 -> Unit
  (if (= count 0) (do)
    (do (writeByte! output dst (mod value 256))
        (writePacked! output (+ dst 1) (/ value 256) (- count 1))))

fn writeBitsAt! output: Bytes bitAt: Int64 value: Int64 count: Int64 -> Unit
  (if (<= count 0) (do)
    (let [(byteAt (/ bitAt 8))
          (within (mod bitAt 8))
          (current (bytesGet output byteAt))]
      (do
        (if (= (mod value 2) 1) (bytesSet output byteAt (+ current (pow2 within))) (do))
        (writeBitsAt! output (+ bitAt 1) (/ value 2) (- count 1)))))

fn clearBytes! output: Bytes at: Int64 count: Int64 -> Unit
  (if (<= count 0) (do)
    (do (bytesSet output at 0)
        (clearBytes! output (+ at 1) (- count 1))))

fn fseNorms! kind: Int64 -> Bytes
  (resultOr (bytesFromBase64 (if (= kind 0) "BAMCAgICAgICAgICAgEBAQICAgICAgICAgMCAQEBAQH/////" (if (= kind 1) "AQEBAQEBAgICAQEBAQEBAQEBAQEBAQEB//////8=" "AQQDAgICAgICAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAf////////8="))) (bytesAlloc 0))

fn fseCellSym table: Bytes idx: Int64 -> Int64
  (bytesGet table (* idx 4))

fn fseCellBits table: Bytes idx: Int64 -> Int64
  (bytesGet table (+ (* idx 4) 1))

fn fseCellBase table: Bytes idx: Int64 -> Int64
  (readLe table (+ (* idx 4) 2) 2)

fn fseSetCell! table: Bytes idx: Int64 sym: Int64 bits: Int64 base: Int64 -> Unit
  (do (bytesSet table (* idx 4) sym)
      (bytesSet table (+ (* idx 4) 1) bits)
      (writeLe! table (+ (* idx 4) 2) base 2))

fn fseSpreadCount! table: Bytes sym: Int64 pos: Int64 high: Int64 count: Int64 size: Int64 step: Int64 -> Int64
  (if (<= count 0) (+ (* high 65536) pos)
    (if (> pos high)
      (fseSpreadCount! table sym (mod (+ pos step) size) high count size step)
      (let [(nextPos (mod (+ pos step) size))]
        (do (bytesSet table (* pos 4) sym)
            (fseSpreadCount! table sym nextPos high (- count 1) size step)))))

fn fseReserveLow! table: Bytes norms: Bytes next: Bytes sym: Int64 nsym: Int64 high: Int64 -> Int64
  (if (>= sym nsym) (* high 65536)
    (let [(raw (bytesGet norms sym))]
      (if (= raw 255)
        (do (bytesSet table (* high 4) sym)
            (writeLe! next (* sym 2) 1 2)
            (fseReserveLow! table norms next (+ sym 1) nsym (- high 1)))
        (do (writeLe! next (* sym 2) raw 2)
            (fseReserveLow! table norms next (+ sym 1) nsym high)))))

fn fseSpread! table: Bytes norms: Bytes sym: Int64 nsym: Int64 size: Int64 step: Int64 pos: Int64 high: Int64 -> Int64
  (if (>= sym nsym) (+ (* high 65536) pos)
    (let [(raw (bytesGet norms sym))]
      (if (= raw 255)
        (fseSpread! table norms (+ sym 1) nsym size step pos high)
        (let [(spread (fseSpreadCount! table sym pos high raw size step))
              (newHigh (/ spread 65536))
              (newPos (mod spread 65536))]
          (fseSpread! table norms (+ sym 1) nsym size step newPos newHigh)))))

fn fseBuildCells! table: Bytes next: Bytes idx: Int64 size: Int64 log: Int64 -> Unit
  (if (>= idx size) (do)
    (let [(sym (bytesGet table (* idx 4)))
          (x (readLe next (* sym 2) 2))
          (bits (- log (highBit x)))
          (base (- (* x (pow2 bits)) size))]
      (do (writeLe! next (* sym 2) (+ x 1) 2)
          (fseSetCell! table idx sym bits base)
          (fseBuildCells! table next (+ idx 1) size log))))

fn fseBuild! kind: Int64 -> Bytes
  (let [(norms (fseNorms! kind))
        (nsym (if (= kind 0) 36 (if (= kind 1) 29 53)))
        (log (if (= kind 1) 5 6))
        (size (pow2 log))
        (table (bytesAlloc (* size 4)))
        (next (bytesAlloc (* nsym 2)))
        (step (+ (/ size 2) (/ size 8) 3))
        (reserved (fseReserveLow! table norms next 0 nsym (- size 1)))
        (reservedHigh (/ reserved 65536))
        (reservedPos (mod reserved 65536))
        (spread (fseSpread! table norms 0 nsym size step reservedPos reservedHigh))
        (filled (fseBuildCells! table next 0 size log))]
    table)

fn fseFindState table: Bytes size: Int64 sym: Int64 target: Int64 idx: Int64 -> Int64
  (if (>= idx size) -1
    (let [(cellSym (fseCellSym table idx))
          (bits (fseCellBits table idx))
          (base (fseCellBase table idx))]
      (if (and (= cellSym sym) (or (< target 0) (and (>= target base) (< target (+ base (pow2 bits)))))) idx
        (fseFindState table size sym target (+ idx 1)))))

fn fseSetStates! records: Bytes states: Bytes table: Bytes idx: Int64 field: Int64 size: Int64 target: Int64 -> Unit
  (if (< idx 0) (do)
    (let [(code (readLe records (+ (* idx 16) field) 4))
          (sym (if (= field 8) code (/ code 65536)))
          (state (fseFindState table size sym target 0))]
      (do (writeLe! states (* idx 2) state 2)
          (fseSetStates! records states table (- idx 1) field size state))))

fn fseTransitionBits! output: Bytes bitAt: Int64 table: Bytes states: Bytes idx: Int64 -> Int64
  (let [(source (readLe states (* (- idx 1) 2) 2))
        (target (readLe states (* idx 2) 2))
        (bits (fseCellBits table source))
        (value (- target (fseCellBase table source)))]
    (do (writeBitsAt! output bitAt value bits) (+ bitAt bits)))

fn ! writeFseSequences! output: Bytes records: Bytes llStates: Bytes ofStates: Bytes mlStates: Bytes llTable: Bytes ofTable: Bytes mlTable: Bytes idx: Int64 bitAt: Int64 -> Int64
  (if (< idx 0)
    (do (writeBitsAt! output bitAt 1 1) (+ bitAt 1))
    (let [(base (* idx 16))
          (llCodeValue (/ (readLe records base 4) 65536))
          (mlCodeValue (/ (readLe records (+ base 4) 4) 65536))
          (offCodeValue (readLe records (+ base 8) 4))
          (llExtra (mod (readLe records base 4) 65536))
          (mlExtra (mod (readLe records (+ base 4) 4) 65536))
          (offExtra (readLe records (+ base 12) 4))
          (llN (llBits llCodeValue))
          (mlN (mlBits mlCodeValue))
          (offN offCodeValue)
          (a (+ bitAt llN))
          (b (+ a mlN))
          (c (+ b offN))]
      (do
        (writeBitsAt! output bitAt llExtra llN)
        (writeBitsAt! output a mlExtra mlN)
        (writeBitsAt! output b offExtra offN)
        (if (= idx 0)
          (let [(d (+ c 6))
                (e (+ d 5))]
            (do (writeBitsAt! output c (readLe mlStates 0 2) 6)
                (writeBitsAt! output d (readLe ofStates 0 2) 5)
                (writeBitsAt! output e (readLe llStates 0 2) 6)
                (writeFseSequences! output records llStates ofStates mlStates llTable ofTable mlTable -1 (+ e 6))))
          (let [(d (fseTransitionBits! output c ofTable ofStates idx))
                (e (fseTransitionBits! output d mlTable mlStates idx))
                (f (fseTransitionBits! output e llTable llStates idx))]
            (writeFseSequences! output records llStates ofStates mlStates llTable ofTable mlTable (- idx 1) f))))))

fn emitGroup! output: Bytes dst: Int64 literals: Bytes litCount: Int64 records: Bytes seqCount: Int64 -> Int64
  (let [(litAt (writeLiteralHeader! output (+ dst 3) litCount))
        (seqStart (+ litAt litCount))
        (countBytes (if (< seqCount 128) 1 2))
        (bitsAt (+ seqStart countBytes 1))
        (llTable (fseBuild! 0))
        (ofTable (fseBuild! 1))
        (mlTable (fseBuild! 2))
        (llStates (bytesAlloc (* seqCount 2)))
        (ofStates (bytesAlloc (* seqCount 2)))
        (mlStates (bytesAlloc (* seqCount 2)))
        (llReady (fseSetStates! records llStates llTable (- seqCount 1) 0 64 -1))
        (ofReady (fseSetStates! records ofStates ofTable (- seqCount 1) 8 32 -1))
        (mlReady (fseSetStates! records mlStates mlTable (- seqCount 1) 4 64 -1))
        (scratch (+ 4 (* seqCount 16)))
        (cleared (clearBytes! output bitsAt scratch))
        (written (writeFseSequences! output records llStates ofStates mlStates llTable ofTable mlTable (- seqCount 1) (* bitsAt 8)))
        (bitBytes (/ (+ (- written (* bitsAt 8)) 7) 8))
        (payloadSize (+ (- bitsAt (+ dst 3)) bitBytes))]
    (do
      (writeLe! output dst (+ (* payloadSize 8) 4) 3)
      (copyRaw! literals output 0 litAt litCount)
      (if (< seqCount 128)
        (writeByte! output seqStart seqCount)
        (do
          (writeByte! output seqStart (+ 128 (/ seqCount 256)))
          (writeByte! output (+ seqStart 1) (mod seqCount 256))))
      (writeByte! output (+ seqStart countBytes) 0)
      payloadSize))

fn scanGroup! input: Bytes output: Bytes head: Bytes links: Bytes pos: Int64 litStart: Int64 indexed: Int64 dst: Int64 end: Int64 depth: Int64 window: Int64 literals: Bytes litCount: Int64 records: Bytes seqCount: Int64 totalOut: Int64 groupLl: Int64 -> Int64
  (if (>= (- end pos) 3)
    (let [(found (findAt! input head links pos end depth window))]
      (if (= found 0)
        (if (> seqCount 0)
          (if (>= (+ totalOut (- pos litStart)) 131072)
            (let [(payload (emitGroup! output dst literals litCount records seqCount))]
              (scanMatches! input output head links pos litStart indexed (+ dst 3 payload) end depth window))
            (do
              (insertPosition! input head links pos end)
              (scanGroup! input output head links (+ pos 1) litStart (+ indexed 1) dst end depth window literals litCount records seqCount totalOut groupLl)))
          (do
            (insertPosition! input head links pos end)
            (scanMatches! input output head links (+ pos 1) litStart (+ pos 1) dst end depth window)))
        (let [(matchLen (mod found (+ end 1)))
              (candidate (/ found (+ end 1)))
              (litLen (- pos litStart))
              (offset (- pos candidate))
              (offValue (+ offset 3))
              (offCode (highBit offValue))
              (offExtra (- offValue (pow2 offCode)))
              (ll (llCode litLen))
              (llSym (/ ll 65536))
              (llExtra (mod ll 65536))
              (ml (mlCode matchLen))
              (mlSym (/ ml 65536))
              (mlExtra (mod ml 65536))
              (fits? (<= (+ totalOut litLen matchLen) 131072))
]
          (if fits?
            (let [(next (+ pos matchLen))
              (base (* seqCount 16))]
              (do
                (copyRaw! input literals litStart litCount pos)
                (writeLe! records base ll 4)
                (writeLe! records (+ base 4) ml 4)
                (writeLe! records (+ base 8) offCode 4)
                (writeLe! records (+ base 12) offExtra 4)
                (insertRange! input head links indexed next)
                (if (>= (+ totalOut litLen matchLen) 131072)
                  (let [(payload (emitGroup! output dst literals (+ litCount litLen) records (+ seqCount 1)))]
                    (scanMatches! input output head links next next next (+ dst 3 payload) end depth window))
                  (scanGroup! input output head links next next next dst end depth window literals (+ litCount litLen) records (+ seqCount 1) (+ totalOut litLen matchLen) (if (= seqCount 0) llSym groupLl)))))
            (if (> seqCount 0)
              (if (= llSym groupLl)
                (if (>= (+ totalOut litLen) 131072)
                  (let [(payload (emitGroup! output dst literals litCount records seqCount))]
                    (scanMatches! input output head links pos litStart indexed (+ dst 3 payload) end depth window))
                  (do
                    (insertPosition! input head links pos end)
                    (scanGroup! input output head links (+ pos 1) litStart (+ pos 1) dst end depth window literals litCount records seqCount totalOut groupLl)))
                (let [(payload (emitGroup! output dst literals litCount records seqCount))]
                  (scanMatches! input output head links pos litStart indexed (+ dst 3 payload) end depth window)))
              (let [(safeLen (if (> (+ litLen matchLen) 131072) (- 131072 litLen) matchLen))
                    (next (+ pos safeLen))]
                (do
                  (copyRaw! input literals litStart 0 pos)
                  (let [(actualMl (mlCode safeLen))]
                    (do
                      (writeLe! records 0 ll 4)
                      (writeLe! records 4 actualMl 4)
                      (writeLe! records 8 offCode 4)
                      (writeLe! records 12 offExtra 4)
                      (insertRange! input head links indexed next)
                      (let [(payload (emitGroup! output dst literals litLen records 1))]
                        (scanMatches! input output head links next next next (+ dst 3 payload) end depth window)))))))))))
    (if (> seqCount 0)
      (let [(payload (emitGroup! output dst literals litCount records seqCount))]
        (encodeBlocks! input output litStart (+ dst 3 payload)))
      (encodeBlocks! input output litStart dst)))

fn scanMatches! input: Bytes output: Bytes head: Bytes links: Bytes pos: Int64 litStart: Int64 indexed: Int64 dst: Int64 end: Int64 depth: Int64 window: Int64 -> Int64
  (if (>= (- end pos) 3)
    (let [(found (findAt! input head links pos end depth window))]
      (if (= found 0)
        (do
          (insertPosition! input head links pos end)
          (scanMatches! input output head links (+ pos 1) litStart (+ pos 1) dst end depth window))
        (let [(matchLen (mod found (+ end 1)))
              (candidate (/ found (+ end 1)))
              (litLen (- pos litStart))
              (blockMatchLen (if (> (+ litLen matchLen) 131072) (- 131072 litLen) matchLen))
              (next (+ pos blockMatchLen))]
          (if (> litLen 130000)
            (let [(rawSize (if (>= litLen 131072) 131072 litLen))
                  (after (+ dst 3 rawSize))
                  (rawEnd (+ litStart rawSize))]
              (do
                (writeLe! output dst (* rawSize 8) 3)
                (copyRaw! input output litStart (+ dst 3) rawEnd)
                (insertRange! input head links indexed rawEnd)
                (scanMatches! input output head links rawEnd rawEnd rawEnd after end depth window)))
            (let [(literals (bytesAlloc 131072))
                  (records (bytesAlloc 524288))]
              (scanGroup! input output head links pos litStart indexed dst end depth window literals 0 records 0 0 -1))))))
    (let [(after (encodeBlocks! input output litStart dst))]
      after))

fn encodeBlocks! input: Bytes output: Bytes pos: Int64 dst: Int64 -> Int64
  (let [(size (if (> (- (bytesLength input) pos) 131072) 131072 (- (bytesLength input) pos)))
        (last? (= (+ pos size) (bytesLength input)))
        (value (if (> size 0) (bytesGet input pos) 0))
        (rle? (and (> size 1) (sameByte? input pos (+ pos size) value)))
        (blockType (if rle? 1 0))
        (header (+ (* size 8) (* blockType 2) (if last? 1 0)))
        (after (if rle? (+ dst 4) (+ dst 3 size)))]
    (do
      (writeLe! output dst header 3)
      (if rle? (writeByte! output (+ dst 3) value) (copyRaw! input output pos (+ dst 3) (+ pos size)))
      (if last? after (encodeBlocks! input output (+ pos size) after))))

fn ! zstdCompress input: Bytes level: Int64 -> (Result Bytes String)
  (if (or (< level 1) (> level 22)) (err "Zstandard compression level must be between 1 and 22")
    (let [(n (bytesLength input))
          (capacity (+ 1024 (* n 4)))
          (frame (bytesAlloc capacity))
          (desc (if (< n 256) 32 (if (< n 65792) 96 160)))
          (contentBytes (if (< n 256) 1 (if (< n 65792) 2 4)))]
      (do
        (writeByte! frame 0 40) (writeByte! frame 1 181) (writeByte! frame 2 47) (writeByte! frame 3 253)
        (writeByte! frame 4 desc)
        (writeLe! frame 5 (if (= contentBytes 2) (- n 256) n) contentBytes)
        (let [(heads (bytesAlloc 196608))
              (links (bytesAlloc (* n 3)))
              (dst (+ 5 contentBytes))
              (window (pow2 (if (> level 11) 27 (+ level 16))))
              (end (scanMatches! input frame heads links 0 0 0 dst n (* 16 level) window))
              (result (bytesAlloc end))]
          (do (copyRaw! frame result 0 0 end) (ok result))))))
