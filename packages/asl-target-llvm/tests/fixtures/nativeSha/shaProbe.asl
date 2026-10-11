(module asl-target-llvm/tests/fixtures/nativeSha/shaProbe
  :x [main]
  :i [])

fn ! fill b: Bytes i: Int64 n: Int64 -> Bytes
  (if (>= i n) b (do (bytesSet b i (mod (+ (* i 131) 7) 256)) (fill b (+ i 1) n)))

fn ! bestMs data: Bytes k: Int64 best: Int64 -> Int64
  (if (<= k 0) best
    (let [(t0 (monotonicNs))
          (_ (bytesSha256 data))
          (ms (/ (- (monotonicNs) t0) 1000000))]
      (bestMs data (- k 1) (min best ms))))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1048576")) 1048576))
        (data (fill (bytesAlloc n) 0 n))
        (h (bytesSha256 data))]
    (do
      (println (str "empty " (bytesSha256 (stringToBytes ""))))
      (println (str "abc " (bytesSha256 (stringToBytes "abc"))))
      (println (str "data " h))
      (eprintln (str "shaMs " (bestMs data 3 9223372036854775807)))
      (ok ())))
