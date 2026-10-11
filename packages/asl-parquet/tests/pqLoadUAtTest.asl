(module asl-parquet/tests/pqLoadUAtTest
  :x [runTests]
  :i [(asl-parquet/reader :a r)])

fn refPow p: Int64 -> Int64
  (if (<= p 0) 1 (* 256 (refPow (- p 1))))

fn refLoadHelper bs: Bytes at: Int64 n: Int64 j: Int64 acc: Int64 -> Int64
  (if (>= j n) acc (refLoadHelper bs at n (+ j 1) (+ acc (* (bytesGet bs (- at j)) (refPow (- (- n 1) j))))))

fn refLoad bs: Bytes at: Int64 n: Int64 -> Int64
  (refLoadHelper bs at n 0 0)

fn refLoad64 bs: Bytes i: Int64 -> Int64
  (let [(low (refLoad bs (+ i 6) 7)) (top (bytesGet bs (+ i 7)))]
    (+ low (* (if (>= top 128) (- top 256) top) (refPow 7))))

fn ! fillLoop b: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (do (bytesSet b i (mod (+ (* i 37) 11) 256)) (fillLoop b (+ i 1) n)))

fn ! fillBuf n: Int64 -> Bytes
  (let [(b (bytesAlloc n))] (do (fillLoop b 0 n) b))

fn checkWidthAt! buf: Bytes at: Int64 n: Int64 -> Bool
  (do
    (assert (= (r/pqLoadUAt buf at n 0) (refLoad buf at n))
      (str "pqLoadUAt width " (stringFromInt64 n) " at " (stringFromInt64 at) " matches the reference"))
    true)

fn checkWidthAtAcc! buf: Bytes at: Int64 n: Int64 acc: Int64 -> Bool
  (do
    (assert (= (r/pqLoadUAt buf at n acc) (+ (* acc (refPow n)) (refLoad buf at n)))
      (str "pqLoadUAt width " (stringFromInt64 n) " at " (stringFromInt64 at) " folds a nonzero carried accumulator"))
    true)

fn checkOffsets! buf: Bytes n: Int64 at: Int64 limit: Int64 -> Bool
  (if (> at limit) true
    (and (and (checkWidthAt! buf at n) (checkWidthAtAcc! buf at n 5))
      (checkOffsets! buf n (+ at 1) limit)))

fn checkWidths! buf: Bytes n: Int64 limit: Int64 -> Bool
  (if (> n 7) true
    (and (checkOffsets! buf n 8 limit) (checkWidths! buf (+ n 1) limit)))

fn checkLoad64At! buf: Bytes i: Int64 -> Bool
  (do
    (assert (= (r/pqLoad64 buf i) (refLoad64 buf i))
      (str "pqLoad64 at " (stringFromInt64 i) " matches the sign-extending reference"))
    true)

fn checkLoad64! buf: Bytes i: Int64 limit: Int64 -> Bool
  (if (> i limit) true (and (checkLoad64At! buf i) (checkLoad64! buf (+ i 1) limit)))

fn ! runTests -> Bool
  (let [(buf (fillBuf 40))]
    (and
      (and (checkWidths! buf 1 23) (checkLoad64! buf 8 23))
      (do
        (assert (= (r/pqLoadUAt buf 10 0 777) 777) "pqLoadUAt n=0 returns the carried accumulator untouched")
        true)))
