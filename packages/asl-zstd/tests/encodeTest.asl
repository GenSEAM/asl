(module asl-zstd/tests/encodeTest
  :x [runTests]
  :i [(asl-zstd/encode :a enc)])

fn compress! src: Bytes level: Int64 -> Bytes
  (mt (enc/zstdCompress src level)
    ((ok frame) frame)
    ((err message) (do (assert false (str "zstdCompress level " level ": " message)) (stringToBytes ""))))

fn decode! frame: Bytes label: String level: Int64 -> Bytes
  (mt (zstdDecompress frame)
    ((ok decoded) decoded)
    ((err message) (do (assert false (str label " level " level " decode: " message)) (stringToBytes ""))))

fn ! checkRoundTrip! src: Bytes label: String level: Int64 -> Bool
  (let [(frame (compress! src level))
        (decoded (decode! frame label level))]
    (do
      (assert (= decoded src) (str label " level " level " round trip"))
      true))

fn ! checkAllLevels! src: Bytes label: String -> Bool
  (do
    (checkRoundTrip! src label 1)
    (checkRoundTrip! src label 3)
    (checkRoundTrip! src label 19)
    true)

fn ! csvBytes! -> Bytes
  (mt (fileReadBytes "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10k.csv")
    ((ok bytes) bytes)
    ((err message) (do (assert false (str "read CSV fixture: " message)) (stringToBytes ""))))

fn fillPseudoRandom! output: Bytes at: Int64 state: Int64 -> Unit
  (if (>= at (bytesLength output)) (do)
    (let [(next (mod (+ (* state 1103515245) 12345) 2147483648))]
      (do
        (bytesSet output at (mod (/ next 65536) 256))
        (fillPseudoRandom! output (+ at 1) next))))

fn ! randomBytes! -> Bytes
  (let [(bytes (bytesAlloc 1048576))]
    (do (fillPseudoRandom! bytes 0 7319) bytes))

fn ! verifyExternalZstd! frame: Bytes expected: Bytes -> Bool
  (do
    (let [(created (processRun "mktemp -d /tmp/asl-zstd.XXXXXX"))
          (directory (stringTrim created.stdout))]
      (do
        (assert (= created.exitCode 0) (str "create external-zstd temporary directory: " created.stderr))
        (mt (fileWrite (str directory "/frame.zst") frame)
          ((ok _) (mt (fileWrite (str directory "/expected") expected)
            ((ok _) (let [(command (str "if command -v zstd >/dev/null 2>&1; then zstd -q -d -c '" directory "/frame.zst' > '" directory "/actual' && cmp -s '" directory "/expected' '" directory "/actual'; else echo 'zstd is required on PATH' >&2; exit 127; fi; result=$?; rm -rf '" directory "'; exit $result"))
                        (result (processRun command))]
                    (do
                      (assert (= result.exitCode 0) (str "PATH zstd decode/cmp exit: " result.stderr))
                      true)))
            ((err message) (do (assert false (str "write source for external zstd: " message)) false))
          ((err message) (do (assert false (str "write frame for external zstd: " message)) false))))))))

fn fillLiteralPrefix! output: Bytes at: Int64 -> Unit
  (if (>= at 64) (do)
    (do (bytesSet output at at) (fillLiteralPrefix! output (+ at 1))))

fn ! literalCode25Bytes! -> Bytes
  (let [(input (bytesAlloc 194))]
    (do
      (fillLiteralPrefix! input 0)
      (fillLiteralTail! input 64)
      input))

fn fillLiteralTail! output: Bytes at: Int64 -> Unit
  (if (>= at (bytesLength output)) (do)
    (do (bytesSet output at (mod (- at 64) 64)) (fillLiteralTail! output (+ at 1))))

fn ! checkMatchLength! length: Int64 -> Bool
  (let [(source (stringToBytes (stringRepeat "Z" (+ length 1))))
        (frame (compress! source 3))]
    (do
      (checkRoundTrip! source (str "match length " length) 3)
      (verifyExternalZstd! frame source)
      true))

fn ! checkMatchRange! length: Int64 -> Bool
  (if (> length 300) true
    (do (checkMatchLength! length) (checkMatchRange! (+ length 1))))

fn ! checkMatchHigh! -> Bool
  (do
    (checkMatchLength! 514) (checkMatchLength! 515) (checkMatchLength! 516) (checkMatchLength! 600)
    (checkMatchLength! 1026) (checkMatchLength! 1027) (checkMatchLength! 1500)
    (checkMatchLength! 2050) (checkMatchLength! 2051) (checkMatchLength! 3000)
    (checkMatchLength! 4098) (checkMatchLength! 4099) (checkMatchLength! 6000)
    (checkMatchLength! 8194) (checkMatchLength! 8195) (checkMatchLength! 12000)
    (checkMatchLength! 16386) (checkMatchLength! 16387) (checkMatchLength! 25000)
    (checkMatchLength! 50000) (checkMatchLength! 65538)
    true)

fn readTestLe input: Bytes at: Int64 count: Int64 -> Int64
  (if (= count 0) 0
    (+ (bytesGet input at) (* 256 (readTestLe input (+ at 1) (- count 1)))))

fn ! checkCsvSequences! frame: Bytes -> Unit
  (let [(blockAt 9)
        (blockHeader (readTestLe frame blockAt 3))
        (blockType (mod (/ blockHeader 2) 4))
        (payloadAt (+ blockAt 3))
        (litHeader (bytesGet frame payloadAt))
        (litFormat (mod (/ litHeader 4) 4))
        (litHeaderBytes (if (= litFormat 0) 1 (if (= litFormat 1) 2 3)))
        (litSize (if (= litFormat 0) (/ litHeader 8)
          (if (= litFormat 1)
            (+ (mod (/ litHeader 16) 16) (* (bytesGet frame (+ payloadAt 1)) 16))
            (+ (mod (/ litHeader 16) 16)
              (* (bytesGet frame (+ payloadAt 1)) 16)
              (* (bytesGet frame (+ payloadAt 2)) 4096)))) )
        (seqAt (+ payloadAt litHeaderBytes litSize))
        (seqFirst (bytesGet frame seqAt))
        (countBytes (if (< seqFirst 128) 1 (if (< seqFirst 255) 2 3)))
        (seqCount (if (< seqFirst 128) seqFirst
          (if (< seqFirst 255)
            (+ (* (- seqFirst 128) 256) (bytesGet frame (+ seqAt 1)))
            (+ 32512 (bytesGet frame (+ seqAt 1)) (* (bytesGet frame (+ seqAt 2)) 256)))))
        (modeAt (+ seqAt countBytes))]
    (do
      (assert (= blockType 2) "CSV starts with a compressed block")
      (assert (> seqCount 1) "CSV block carries multiple sequences")
      (assert (= (bytesGet frame modeAt) 0) "CSV sequence block uses the predefined FSE tables")))

fn ! testFrames! -> Bool
  (let [(csv (csvBytes!))
        (empty (stringToBytes ""))
        (single (stringToBytes "Z"))
        (zeros (stringToBytes (stringRepeat "\x00" 1048576)))
        (longZeros (stringToBytes (stringRepeat "\x00" 300000)))
        (mixedLong (stringToBytes (str "XY" (stringRepeat "abcdefgh" 40000))))
        (literal25 (literalCode25Bytes!))
        (random (randomBytes!))]
    (do
      (checkAllLevels! csv "CSV fixture")
      (checkAllLevels! empty "empty")
      (checkAllLevels! single "one byte")
      (checkAllLevels! zeros "1 MiB zeros")
      (checkAllLevels! random "1 MiB pseudo-random")
        (let [(csv1 (compress! csv 1))
            (csv3 (compress! csv 3))
            (csv19 (compress! csv 19))
            (zero19 (compress! zeros 19))
            (random19 (compress! random 19))]
        (do
          (checkMatchRange! 39)
          (checkMatchHigh!)
          (checkRoundTrip! literal25 "literal length code 25" 3)
          (verifyExternalZstd! (compress! literal25 3) literal25)
          (checkRoundTrip! longZeros "300000-byte zero run" 3)
          (verifyExternalZstd! (compress! longZeros 3) longZeros)
          (checkRoundTrip! mixedLong "mixed long match" 3)
          (verifyExternalZstd! (compress! mixedLong 3) mixedLong)
          (verifyExternalZstd! csv3 csv)
          (checkCsvSequences! csv3)
          (assert (<= (bytesLength csv19) (bytesLength csv1)) (str "level 19 no larger than level 1: " (bytesLength csv19) "/" (bytesLength csv1)))
          (assert (< (* (bytesLength zero19) 100) (bytesLength zeros)) "zeros compress below 1 percent")
          (assert (< (bytesLength random19) (+ (bytesLength random) 1049)) "random input growth below 0.1 percent")
          (assert (<= (* (bytesLength csv3) 2) (bytesLength csv)) (str "CSV level 3 size at most half input: " (bytesLength csv3) "/" (bytesLength csv)))
          true))))

fn ! runTests -> Bool
  (do
    (testFrames!)
    true)
