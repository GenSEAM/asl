(module loopGuard
  :x [main]
  :i [])

fn fillBytes i: Int64 n: Int64 buf: Bytes -> Bytes
  (if (= i n) buf
    (do (bytesSet buf i (mod (+ (* i 131) 7) 256))
        (fillBytes (+ i 1) n buf)))

fn sumBytes i: Int64 n: Int64 buf: Bytes acc: Int64 -> Int64
  (if (= i n) acc
    (sumBytes (+ i 1) n buf (+ acc (bytesGet buf i))))

fn sumInts i: Int64 n: Int64 xs: I64Array acc: Int64 -> Int64
  (if (= i n) acc
    (sumInts (+ i 1) n xs (+ acc (i64ArrayGet xs i))))

fn sumEven i: Int64 n: Int64 buf: Bytes acc: Int64 -> Int64
  (if (= i n) acc
    (sumEven (+ i 2) n buf (+ acc (bytesGet buf i))))

fn ints n: Int64 -> I64Array
  (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (- (mod (* i 7919) 2000003) 1000001)))

fn big n: Int64 -> I64Array
  (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (if (= i 5) 4611686018427387904 (+ i 1))))

fn line label: String v: Int64 -> Unit
  (println (str label " " (stringFromInt64 v)))

fn ! run mode: String -> Unit
  (let [(buf (fillBytes 0 100000 (bytesAlloc 100000)))
        (xs (ints 100000))]
    (cond
      ((= mode "ok")
        (do (line "bytes" (sumBytes 0 100000 buf 0))
            (line "bytesFrom" (sumBytes 777 99001 buf -5))
            (line "bytesEmpty" (sumBytes 9 9 buf 3))
            (line "bytesNearMax" (sumBytes 0 1000 buf 9223372036854000000))
            (line "bytesZeroNearMax" (sumBytes 0 100 (bytesAlloc 100) 9223372036854775800))
            (line "bytesNegAcc" (sumBytes 0 100000 buf -9223372036854775807))
            (line "bytesEven" (sumEven 0 100000 buf 0))
            (line "ints" (sumInts 0 100000 xs 0))
            (line "intsFrom" (sumInts 3 77777 xs 11))
            (line "intsEmpty" (sumInts 4 4 xs 3))
            (line "intsBig" (sumInts 0 10 (big 10) -4611686018427387904))
            (line "intsBigAcc" (sumInts 0 100000 xs 4611686018427387904))))
      ((= mode "bytesPast") (line "bytesPast" (sumBytes 99990 100004 buf 0)))
      ((= mode "bytesNeg") (line "bytesNeg" (sumBytes -3 10 buf 0)))
      ((= mode "bytesOver") (line "bytesOver" (sumBytes 0 100000 buf 9223372036854000000)))
      ((= mode "bytesBehind") (line "bytesBehind" (sumBytes 99998 5 buf 0)))
      ((= mode "intsPast") (line "intsPast" (sumInts 99990 100004 xs 0)))
      ((= mode "intsNeg") (line "intsNeg" (sumInts -3 10 xs 0)))
      ((= mode "intsOver") (line "intsOver" (sumInts 0 10 (big 10) 4611686018427387904)))
      ((= mode "intsHuge") (line "intsHuge" (sumInts 0 4 (i64ArrayGenerate 4 (fn [(i Int64)] -> Int64 4611686018427387904)) 0)))
      ((= mode "intsUnder") (line "intsUnder" (sumInts 0 100000 xs -9223372036854775000)))
      (else (println (str "unknown mode " mode)))))

fn ! main args: (List String) -> (Result Unit String)
  (do (run (optionOr (listHead args) "ok"))
      (ok ()))
