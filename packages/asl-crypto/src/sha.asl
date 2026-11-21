(module asl-crypto/sha
  :x [sha1 sha512 hmacSha512]
  :i [])

fn nth xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn mask32 x: Int64 -> Int64
  (& x 4294967295)

fn rotl32 x: Int64 k: Int64 -> Int64
  (& (| (<< x k) (>> x (- 32 k))) 4294967295)

fn lsr64 x: Int64 n: Int64 -> Int64
  (& (>> x n) (+ (* (- (<< 1 (- 63 n)) 1) 2) 1))

fn nibble c: String -> Int64
  (let [(v (charCode c))]
    (if (<= v 57) (- v 48) (- v 87)))

fn hexWord text: String -> Int64
  (fold (fn [acc c] (addWrap (mulWrap acc 16) (nibble c))) 0 (stringChars text))

fn fillZero b: Bytes i: Int64 n: Int64 -> Unit
  (if (< i n) (do (bytesSet b i 0) (fillZero b (+ i 1) n)) ())

fn copyInto dst: Bytes src: Bytes dstOff: Int64 i: Int64 n: Int64 -> Unit
  (if (< i n)
    (do (bytesSet dst (+ dstOff i) (bytesGet src i)) (copyInto dst src dstOff (+ i 1) n))
    ())

fn putLen b: Bytes off: Int64 bits: Int64 i: Int64 -> Unit
  (if (< i 8)
    (do (bytesSet b (+ off i) (& (>> bits (* 8 (- 7 i))) 255)) (putLen b off bits (+ i 1)))
    ())

fn padMessage msg: Bytes block: Int64 lenBytes: Int64 -> Bytes
  (let [(n (bytesLength msg))
        (rem (mod (+ n (+ 1 lenBytes)) block))
        (padLen (if (= rem 0) 0 (- block rem)))
        (total (+ n (+ 1 (+ padLen lenBytes))))
        (out (bytesAlloc total))]
    (do (fillZero out 0 total)
        (copyInto out msg 0 0 n)
        (bytesSet out n 128)
        (putLen out (- total 8) (* n 8) 0)
        out))

fn be32 b: Bytes off: Int64 -> Int64
  (+ (+ (+ (<< (bytesGet b off) 24) (<< (bytesGet b (+ off 1)) 16)) (<< (bytesGet b (+ off 2)) 8)) (bytesGet b (+ off 3)))

fn be64From b: Bytes off: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i 8) acc
    (be64From b off (+ i 1) (| (<< acc 8) (bytesGet b (+ off i)))))

fn be64 b: Bytes off: Int64 -> Int64
  (be64From b off 0 0)

fn words32 b: Bytes off: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i 16) acc
    (words32 b off (+ i 1) (listAppend acc (list (be32 b (+ off (* i 4)))))))

fn words64 b: Bytes off: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i 16) acc
    (words64 b off (+ i 1) (listAppend acc (list (be64 b (+ off (* i 8)))))))

fn zipAdd32 a: (List Int64) b: (List Int64) i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) acc
    (zipAdd32 a b (+ i 1) n (listAppend acc (list (mask32 (+ (nth a i) (nth b i)))))))

fn zipAdd64 a: (List Int64) b: (List Int64) i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) acc
    (zipAdd64 a b (+ i 1) n (listAppend acc (list (addWrap (nth a i) (nth b i))))))

fn sha1Extend w: (List Int64) t: Int64 -> (List Int64)
  (if (>= t 80) w
    (let [(x (^ (^ (^ (nth w (- t 3)) (nth w (- t 8))) (nth w (- t 14))) (nth w (- t 16))))]
      (sha1Extend (listAppend w (list (rotl32 x 1))) (+ t 1))))

fn sha1Rounds w: (List Int64) t: Int64 a: Int64 b: Int64 c: Int64 d: Int64 e: Int64 -> (List Int64)
  (if (>= t 80) (list a b c d e)
    (let [(fk (cond
            ((< t 20) (pair (^ (& b c) (& (^ b 4294967295) d)) 1518500249))
            ((< t 40) (pair (^ (^ b c) d) 1859775393))
            ((< t 60) (pair (| (| (& b c) (& b d)) (& c d)) 2400959708))
            (else (pair (^ (^ b c) d) 3395469782))))
          (temp (mask32 (+ (+ (+ (+ (rotl32 a 5) (pairFirst fk)) e) (pairSecond fk)) (nth w t))))]
      (sha1Rounds w (+ t 1) temp a (rotl32 b 30) c d)))

fn sha1Block h: (List Int64) block: Bytes off: Int64 -> (List Int64)
  (let [(w (sha1Extend (words32 block off 0 (list)) 16))
        (r (sha1Rounds w 0 (nth h 0) (nth h 1) (nth h 2) (nth h 3) (nth h 4)))]
    (zipAdd32 h r 0 5 (list)))

fn sha1Blocks b: Bytes off: Int64 h: (List Int64) -> (List Int64)
  (if (>= off (bytesLength b)) h
    (sha1Blocks b (+ off 64) (sha1Block h b off)))

fn emitWords32 out: Bytes h: (List Int64) i: Int64 -> Unit
  (if (< i 20)
    (do (bytesSet out i (& (>> (nth h (/ i 4)) (* 8 (- 3 (mod i 4)))) 255)) (emitWords32 out h (+ i 1)))
    ())

fn sha1 msg: Bytes -> Bytes
  (let [(padded (padMessage msg 64 8))
        (h (sha1Blocks padded 0 (list 1732584193 4023233417 2562383102 271733878 3285377520)))
        (out (bytesAlloc 20))]
    (do (emitWords32 out h 0) out))

fn sha512K -> (List Int64)
  (map (fn [t] (hexWord t)) (list
    "428a2f98d728ae22" "7137449123ef65cd" "b5c0fbcfec4d3b2f" "e9b5dba58189dbbc"
    "3956c25bf348b538" "59f111f1b605d019" "923f82a4af194f9b" "ab1c5ed5da6d8118"
    "d807aa98a3030242" "12835b0145706fbe" "243185be4ee4b28c" "550c7dc3d5ffb4e2"
    "72be5d74f27b896f" "80deb1fe3b1696b1" "9bdc06a725c71235" "c19bf174cf692694"
    "e49b69c19ef14ad2" "efbe4786384f25e3" "0fc19dc68b8cd5b5" "240ca1cc77ac9c65"
    "2de92c6f592b0275" "4a7484aa6ea6e483" "5cb0a9dcbd41fbd4" "76f988da831153b5"
    "983e5152ee66dfab" "a831c66d2db43210" "b00327c898fb213f" "bf597fc7beef0ee4"
    "c6e00bf33da88fc2" "d5a79147930aa725" "06ca6351e003826f" "142929670a0e6e70"
    "27b70a8546d22ffc" "2e1b21385c26c926" "4d2c6dfc5ac42aed" "53380d139d95b3df"
    "650a73548baf63de" "766a0abb3c77b2a8" "81c2c92e47edaee6" "92722c851482353b"
    "a2bfe8a14cf10364" "a81a664bbc423001" "c24b8b70d0f89791" "c76c51a30654be30"
    "d192e819d6ef5218" "d69906245565a910" "f40e35855771202a" "106aa07032bbd1b8"
    "19a4c116b8d2d0c8" "1e376c085141ab53" "2748774cdf8eeb99" "34b0bcb5e19b48a8"
    "391c0cb3c5c95a63" "4ed8aa4ae3418acb" "5b9cca4f7763e373" "682e6ff3d6b2b8a3"
    "748f82ee5defb2fc" "78a5636f43172f60" "84c87814a1f0ab72" "8cc702081a6439ec"
    "90befffa23631e28" "a4506cebde82bde9" "bef9a3f7b2c67915" "c67178f2e372532b"
    "ca273eceea26619c" "d186b8c721c0c207" "eada7dd6cde0eb1e" "f57d4f7fee6ed178"
    "06f067aa72176fba" "0a637dc5a2c898a6" "113f9804bef90dae" "1b710b35131c471b"
    "28db77f523047d84" "32caab7b40c72493" "3c9ebe0a15c9bebc" "431d67c49c100d4c"
    "4cc5d4becb3e42b6" "597f299cfc657e2a" "5fcb6fab3ad6faec" "6c44198c4a475817"))

fn ssig0 x: Int64 -> Int64
  (^ (^ (rotateRight x 1) (rotateRight x 8)) (lsr64 x 7))

fn ssig1 x: Int64 -> Int64
  (^ (^ (rotateRight x 19) (rotateRight x 61)) (lsr64 x 6))

fn bsig0 x: Int64 -> Int64
  (^ (^ (rotateRight x 28) (rotateRight x 34)) (rotateRight x 39))

fn bsig1 x: Int64 -> Int64
  (^ (^ (rotateRight x 14) (rotateRight x 18)) (rotateRight x 41))

fn sha512Extend w: (List Int64) t: Int64 -> (List Int64)
  (if (>= t 80) w
    (let [(s0 (ssig0 (nth w (- t 15))))
          (s1 (ssig1 (nth w (- t 2))))
          (x (addWrap (addWrap (addWrap s1 (nth w (- t 7))) s0) (nth w (- t 16))))]
      (sha512Extend (listAppend w (list x)) (+ t 1))))

fn sha512Rounds k: (List Int64) w: (List Int64) t: Int64 a: Int64 b: Int64 c: Int64 d: Int64 e: Int64 f: Int64 g: Int64 h: Int64 -> (List Int64)
  (if (>= t 80) (list a b c d e f g h)
    (let [(ch (^ (& e f) (& (^ e -1) g)))
          (t1 (addWrap (addWrap (addWrap (addWrap h (bsig1 e)) ch) (nth k t)) (nth w t)))
          (maj (^ (^ (& a b) (& a c)) (& b c)))
          (t2 (addWrap (bsig0 a) maj))]
      (sha512Rounds k w (+ t 1) (addWrap t1 t2) a b c (addWrap d t1) e f g)))

fn sha512Block h: (List Int64) block: Bytes off: Int64 k: (List Int64) -> (List Int64)
  (let [(w (sha512Extend (words64 block off 0 (list)) 16))
        (r (sha512Rounds k w 0 (nth h 0) (nth h 1) (nth h 2) (nth h 3) (nth h 4) (nth h 5) (nth h 6) (nth h 7)))]
    (zipAdd64 h r 0 8 (list)))

fn sha512Blocks b: Bytes off: Int64 h: (List Int64) k: (List Int64) -> (List Int64)
  (if (>= off (bytesLength b)) h
    (sha512Blocks b (+ off 128) (sha512Block h b off k) k))

fn emitWords64 out: Bytes h: (List Int64) i: Int64 -> Unit
  (if (< i 64)
    (do (bytesSet out i (& (rotateRight (nth h (/ i 8)) (* 8 (- 7 (mod i 8)))) 255)) (emitWords64 out h (+ i 1)))
    ())

fn sha512 msg: Bytes -> Bytes
  (let [(padded (padMessage msg 128 16))
        (k (sha512K))
        (h0 (map (fn [t] (hexWord t)) (list "6a09e667f3bcc908" "bb67ae8584caa73b" "3c6ef372fe94f82b" "a54ff53a5f1d36f1" "510e527fade682d1" "9b05688c2b3e6c1f" "1f83d9abfb41bd6b" "5be0cd19137e2179")))
        (h (sha512Blocks padded 0 h0 k))
        (out (bytesAlloc 64))]
    (do (emitWords64 out h 0) out))

fn hmacPad key: Bytes inner: Bytes outer: Bytes i: Int64 keyLength: Int64 -> Unit
  (if (< i 128)
    (do (bytesSet inner i (^ (if (< i keyLength) (bytesGet key i) 0) 54))
        (bytesSet outer i (^ (if (< i keyLength) (bytesGet key i) 0) 92))
        (hmacPad key inner outer (+ i 1) keyLength))
    ())

fn hmacSha512 key: Bytes msg: Bytes -> Bytes
  (let [(normalized (if (> (bytesLength key) 128) (sha512 key) key))
        (keyLength (bytesLength normalized))
        (inner (bytesAlloc (+ 128 (bytesLength msg))))
        (outer (bytesAlloc 192))]
    (do (hmacPad normalized inner outer 0 keyLength)
        (copyInto inner msg 128 0 (bytesLength msg))
        (copyInto outer (sha512 inner) 128 0 64)
        (sha512 outer)))
