(module asl-target-llvm/tests/fixtures/nativeData/zstdProbe
  :x [main]
  :i [])

fn errCode e: String -> String
  (optionOr (listHead (stringSplit e ":")) e)

fn sparseStep bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (sparseStep bs (+ i 997) n (mod (+ (* acc 257) (bytesGet bs i)) 1000000007)))

fn digest out: Bytes -> String
  (if (<= (bytesLength out) 262144) (bytesSha256 out) (str "sparse " (sparseStep out 0 (bytesLength out) 0)))

fn ! decodeDir dir: String -> Int64
  (mt (dirList dir)
    ((err e) (do (println (str "dir err " dir " " e)) 0))
    ((ok names)
      (fold (fn [(acc Int64) (n String)] -> Int64
              (mt (fileReadBytes (str dir "/" n))
                ((err e) (do (println (str n " read err " e)) acc))
                ((ok src)
                  (mt (zstdDecompress src)
                    ((ok out) (do (println (str n " ok " (bytesLength out) " " (digest out))) (+ acc 1)))
                    ((err e) (do (println (str n " err " (errCode e))) (+ acc 1)))))))
            0 (listSort names))))

fn ! main -> (Result Unit String)
  (let [(root "tests/acceptance/r1Host/fixtures/zstd/")
        (count (+ (decodeDir (str root "pos")) (+ (decodeDir (str root "pages")) (decodeDir (str root "neg")))))]
    (do (println (str "decoded " count)) (ok ())))
