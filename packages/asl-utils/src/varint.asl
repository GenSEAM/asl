(module asl-utils/varint
  :x [uvarintLength encodeU decodeU decodeUAt zigzagEncode zigzagDecode svarintLength encodeS decodeS decodeSAt]
  :i [])

fn uvarintLength v: Int64 -> Int64
  (if (< v 128) 1 (+ 1 (uvarintLength (/ v 128))))

fn ! fillU! b: Bytes i: Int64 v: Int64 -> Unit
  (if (< v 128)
    (bytesSet b i v)
    (do (bytesSet b i (+ 128 (mod v 128)))
        (fillU! b (+ i 1) (/ v 128))))

fn ! encodeU v: Int64 -> Bytes
  (let [(b (bytesAlloc (uvarintLength v)))]
    (do (fillU! b 0 v) b))

fn decodeULoop bs: Bytes start: Int64 i: Int64 mult: Int64 acc: Int64 -> (Result (Pair Int64 Int64) String)
  (if (>= i (bytesLength bs))
    (err "varint: truncated input")
    (let [(b (bytesGet bs i))
          (low (mod b 128))
          (more (>= b 128))
          (last? (not more))
          (minimal? (or (= i start) (> low 0)))
          (room? (< i (+ start 8)))]
      (cond ((and more (not room?)) (err "varint: overlong encoding"))
            ((and last? (not minimal?)) (err "varint: overlong encoding"))
            (last? (ok (pair (+ acc (* low mult)) (- (+ i 1) start))))
            (else (decodeULoop bs start (+ i 1) (* mult 128) (+ acc (* low mult)))))))

fn decodeUAt bs: Bytes off: Int64 -> (Result (Pair Int64 Int64) String)
  (if (< off 0)
    (err "varint: negative offset")
    (decodeULoop bs off off 1 0))

fn decodeU bs: Bytes -> (Result (Pair Int64 Int64) String)
  (decodeUAt bs 0)

fn zigzagEncode v: Int64 -> (Result Int64 String)
  (if (>= v 0)
    (if (>= v 4611686018427387904)
      (err "varint: zigzagEncode overflow")
      (ok (* 2 v)))
    (if (<= v -4611686018427387905)
      (err "varint: zigzagEncode overflow")
      (ok (- 0 (+ (* 2 v) 1)))))

fn zigzagDecode u: Int64 -> Int64
  (if (= (mod u 2) 0) (/ u 2) (/ (- (- 0 u) 1) 2))

fn svarintLength v: Int64 -> (Result Int64 String)
  (match (zigzagEncode v)
    ((ok u) (ok (uvarintLength u)))
    ((err e) (err e)))

fn ! encodeS v: Int64 -> (Result Bytes String)
  (match (zigzagEncode v)
    ((ok u) (ok (encodeU u)))
    ((err e) (err e)))

fn decodeSAt bs: Bytes off: Int64 -> (Result (Pair Int64 Int64) String)
  (match (decodeUAt bs off)
    ((ok p) (ok (pair (zigzagDecode (pairFirst p)) (pairSecond p))))
    ((err e) (err e)))

fn decodeS bs: Bytes -> (Result (Pair Int64 Int64) String)
  (decodeSAt bs 0)
