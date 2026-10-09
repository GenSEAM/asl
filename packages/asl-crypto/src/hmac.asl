(module asl-crypto/hmac
  :x [hmacSha256 hmacSha256Hex constantTimeEqual bytesToHex hexToBytes]
  :i [])

fn hexNibble c: Int64 -> Int64
  (if (and (>= c 48) (<= c 57)) (- c 48)
    (if (and (>= c 97) (<= c 102)) (+ 10 (- c 97)) -1))

fn hexToBytes text: String -> (Result Bytes String)
  (let [(n (stringLength text)) (source (stringToBytes text))]
    (if (!= (mod n 2) 0) (err "invalid hex length")
      (let [(out (bytesAlloc (/ n 2)))
            (loop (fn [loop i] -> (Result Bytes String)
              (if (>= i (/ n 2)) (ok out)
                (let [(hi (hexNibble (bytesGet source (* i 2))))
                      (lo (hexNibble (bytesGet source (+ (* i 2) 1))))]
                  (if (or (< hi 0) (< lo 0)) (err "invalid hex digit")
                    (do (bytesSet out i (+ (* hi 16) lo)) (loop loop (+ i 1))))))))]
        (loop loop 0))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "")

fn bytesToHex bytes: Bytes -> String
  (let [(n (bytesLength bytes))
        (loop (fn [loop i acc] -> String
          (if (>= i n) acc
            (let [(v (bytesGet bytes i))]
              (loop loop (+ i 1) (str acc (hexDigit (/ v 16)) (hexDigit (mod v 16))))))))]
    (loop loop 0 ""))

fn hmacSha256 key: Bytes msg: Bytes -> Bytes
  (let [(keyLength (bytesLength key))
        (normalized (if (> keyLength 64)
          (mt (hexToBytes (bytesSha256 key)) ((ok digest) digest) ((err _) key)) key))
        (keyLength2 (bytesLength normalized))
        (inner (bytesAlloc (+ 64 (bytesLength msg))))
        (outer (bytesAlloc 96))]
    (let [(fill (fn [fill i] -> Unit
        (if (< i 64)
          (do (bytesSet inner i (^ (if (< i keyLength2) (bytesGet normalized i) 0) 54))
              (bytesSet outer i (^ (if (< i keyLength2) (bytesGet normalized i) 0) 92))
              (fill fill (+ i 1))) ())))
          (copyMsg (fn [copyMsg i] -> Unit
            (if (< i (bytesLength msg))
              (do (bytesSet inner (+ i 64) (bytesGet msg i)) (copyMsg copyMsg (+ i 1))) ())))
          (copyOuter (fn [copyOuter i digest] -> Unit
            (if (< i 32) (do (bytesSet outer (+ i 64) (bytesGet digest i)) (copyOuter copyOuter (+ i 1) digest)) ()))) ]
      (do (fill fill 0) (copyMsg copyMsg 0)
        (let [(innerDigest (mt (hexToBytes (bytesSha256 inner)) ((ok digest) digest) ((err _) (bytesAlloc 32))))]
          (copyOuter copyOuter 0 innerDigest)
          (mt (hexToBytes (bytesSha256 outer)) ((ok result) result) ((err _) (bytesAlloc 32)))))))

fn hmacSha256Hex key: Bytes msg: Bytes -> String
  (bytesToHex (hmacSha256 key msg))

fn constantTimeEqual a: Bytes b: Bytes -> Bool
  (let [(aLength (bytesLength a)) (bLength (bytesLength b))
        (shorter (if (< aLength bLength) aLength bLength))
        (different (if (= aLength bLength) 0 1))
        (loop (fn [loop i diff] -> Int64
          (if (>= i shorter) diff
            (loop loop (+ i 1) (| diff (^ (bytesGet a i) (bytesGet b i)))))))]
    (= (loop loop 0 different) 0))
