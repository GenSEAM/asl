(module aslPreludeNative/sha256
  :x [bytesSha256]
  :i [])

fn mask32 x: Int64 -> Int64
  (& x 4294967295)

fn addWord2 a: Int64 b: Int64 -> Int64
  (mask32 (+ a b))

fn addWord3 a: Int64 b: Int64 c: Int64 -> Int64
  (addWord2 (addWord2 a b) c)

fn addWord5 a: Int64 b: Int64 c: Int64 d: Int64 e: Int64 -> Int64
  (addWord2 (addWord3 a b c) (addWord2 d e))

fn shrWord x: Int64 n: Int64 -> Int64
  (>> x n)

fn shlWord x: Int64 n: Int64 -> Int64
  (mask32 (<< x n))

fn rotr x: Int64 n: Int64 -> Int64
  (| (shrWord x n) (shlWord x (- 32 n)))

fn bigSigma0 a: Int64 -> Int64
  (^ (^ (rotr a 2) (rotr a 13)) (rotr a 22))

fn bigSigma1 e: Int64 -> Int64
  (^ (^ (rotr e 6) (rotr e 11)) (rotr e 25))

fn smallSigma0 x: Int64 -> Int64
  (^ (^ (rotr x 7) (rotr x 18)) (shrWord x 3))

fn smallSigma1 x: Int64 -> Int64
  (^ (^ (rotr x 17) (rotr x 19)) (shrWord x 10))

fn choose e: Int64 f: Int64 g: Int64 -> Int64
  (^ (& e f) (& (^ e 4294967295) g))

fn majority a: Int64 b: Int64 c: Int64 -> Int64
  (^ (^ (& a b) (& a c)) (& b c))

fn roundK t: Int64 -> Int64
  (cond
    ((< t 8) (cond ((= t 0) 1116352408) ((= t 1) 1899447441) ((= t 2) 3049323471) ((= t 3) 3921009573)
                    ((= t 4) 961987163) ((= t 5) 1508970993) ((= t 6) 2453635748) (else 2870763221)))
    ((< t 16) (cond ((= t 8) 3624381080) ((= t 9) 310598401) ((= t 10) 607225278) ((= t 11) 1426881987)
                     ((= t 12) 1925078388) ((= t 13) 2162078206) ((= t 14) 2614888103) (else 3248222580)))
    ((< t 24) (cond ((= t 16) 3835390401) ((= t 17) 4022224774) ((= t 18) 264347078) ((= t 19) 604807628)
                     ((= t 20) 770255983) ((= t 21) 1249150122) ((= t 22) 1555081692) (else 1996064986)))
    ((< t 32) (cond ((= t 24) 2554220882) ((= t 25) 2821834349) ((= t 26) 2952996808) ((= t 27) 3210313671)
                     ((= t 28) 3336571891) ((= t 29) 3584528711) ((= t 30) 113926993) (else 338241895)))
    ((< t 40) (cond ((= t 32) 666307205) ((= t 33) 773529912) ((= t 34) 1294757372) ((= t 35) 1396182291)
                     ((= t 36) 1695183700) ((= t 37) 1986661051) ((= t 38) 2177026350) (else 2456956037)))
    ((< t 48) (cond ((= t 40) 2730485921) ((= t 41) 2820302411) ((= t 42) 3259730800) ((= t 43) 3345764771)
                     ((= t 44) 3516065817) ((= t 45) 3600352804) ((= t 46) 4094571909) (else 275423344)))
    ((< t 56) (cond ((= t 48) 430227734) ((= t 49) 506948616) ((= t 50) 659060556) ((= t 51) 883997877)
                     ((= t 52) 958139571) ((= t 53) 1322822218) ((= t 54) 1537002063) (else 1747873779)))
    (else (cond ((= t 56) 1955562222) ((= t 57) 2024104815) ((= t 58) 2227730452) ((= t 59) 2361852424)
                ((= t 60) 2428436474) ((= t 61) 2756734187) ((= t 62) 3204031479) (else 3329325298))))

fn initialH i: Int64 -> Int64
  (cond ((= i 0) 1779033703) ((= i 1) 3144134277) ((= i 2) 1013904242) ((= i 3) 2773480762)
        ((= i 4) 1359893119) ((= i 5) 2600822924) ((= i 6) 528734635) (else 1541459225))

fn get32 b: Bytes i: Int64 -> Int64
  (addWord2 (shlWord (bytesGet b i) 24)
            (addWord3 (shlWord (bytesGet b (+ i 1)) 16) (shlWord (bytesGet b (+ i 2)) 8) (bytesGet b (+ i 3))))

fn ! set32 b: Bytes i: Int64 v: Int64 -> Bool
  (do
    (bytesSet b i (/ v 16777216))
    (bytesSet b (+ i 1) (mod (/ v 65536) 256))
    (bytesSet b (+ i 2) (mod (/ v 256) 256))
    (bytesSet b (+ i 3) (mod v 256))
    true)

fn paddedLen n: Int64 -> Int64
  (* (/ (+ n 72) 64) 64)

fn ! buildPadded data: Bytes -> Bytes
  (let [(n (bytesLength data))
        (total (paddedLen n))
        (out (bytesAlloc total))
        (bits (* n 8))]
    (do
      (copyInto data out 0 n)
      (bytesSet out n 128)
      (zeroFrom out (+ n 1) total)
      (writeLen out (- total 8) bits)
      out))

fn ! copyInto src: Bytes dst: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (do (bytesSet dst i (bytesGet src i)) (copyInto src dst (+ i 1) n)))

fn ! zeroFrom b: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (do (bytesSet b i 0) (zeroFrom b (+ i 1) n)))

fn ! writeLen b: Bytes at: Int64 bits: Int64 -> Bool
  (do
    (bytesSet b at (mod (/ bits 72057594037927936) 256))
    (bytesSet b (+ at 1) (mod (/ bits 281474976710656) 256))
    (bytesSet b (+ at 2) (mod (/ bits 1099511627776) 256))
    (bytesSet b (+ at 3) (mod (/ bits 4294967296) 256))
    (bytesSet b (+ at 4) (mod (/ bits 16777216) 256))
    (bytesSet b (+ at 5) (mod (/ bits 65536) 256))
    (bytesSet b (+ at 6) (mod (/ bits 256) 256))
    (bytesSet b (+ at 7) (mod bits 256))
    true)

fn ! loadSchedule src: Bytes blockOff: Int64 w: Bytes i: Int64 -> Bool
  (if (>= i 16) true
    (do (set32 w (* i 4) (get32 src (+ blockOff (* i 4)))) (loadSchedule src blockOff w (+ i 1))))

fn ! extendSchedule w: Bytes i: Int64 -> Bool
  (if (>= i 64) true
    (let [(w15 (get32 w (* (- i 15) 4)))
          (w2 (get32 w (* (- i 2) 4)))
          (w16 (get32 w (* (- i 16) 4)))
          (w7 (get32 w (* (- i 7) 4)))
          (next (addWord3 w16 (smallSigma0 w15) (addWord2 w7 (smallSigma1 w2))))]
      (do (set32 w (* i 4) (mask32 next)) (extendSchedule w (+ i 1)))))

(schema ShaState
  (:f a Int64 "Working variable a")
  (:f b Int64 "Working variable b")
  (:f c Int64 "Working variable c")
  (:f d Int64 "Working variable d")
  (:f e Int64 "Working variable e")
  (:f f Int64 "Working variable f")
  (:f g Int64 "Working variable g")
  (:f h Int64 "Working variable h"))

fn ! round w: Bytes t: Int64 a: Int64 b: Int64 c: Int64 d: Int64 e: Int64 f: Int64 g: Int64 h: Int64 -> ShaState
  (if (>= t 64) (ShaState :a a :b b :c c :d d :e e :f f :g g :h h)
    (let [(t1 (addWord5 h (bigSigma1 e) (choose e f g) (roundK t) (get32 w (* t 4))))
          (t2 (addWord2 (bigSigma0 a) (majority a b c)))]
      (round w (+ t 1) (mask32 (+ t1 t2)) a b c (mask32 (+ d t1)) e f g)))

fn ! compressBlock src: Bytes blockOff: Int64 w: Bytes hs: ShaState -> ShaState
  (do
    (loadSchedule src blockOff w 0)
    (extendSchedule w 16)
    (let [(out (round w 0 hs.a hs.b hs.c hs.d hs.e hs.f hs.g hs.h))]
      (ShaState :a (mask32 (+ hs.a out.a)) :b (mask32 (+ hs.b out.b))
                :c (mask32 (+ hs.c out.c)) :d (mask32 (+ hs.d out.d))
                :e (mask32 (+ hs.e out.e)) :f (mask32 (+ hs.f out.f))
                :g (mask32 (+ hs.g out.g)) :h (mask32 (+ hs.h out.h)))))

fn ! compressAll padded: Bytes off: Int64 total: Int64 w: Bytes hs: ShaState -> ShaState
  (if (>= off total) hs (compressAll padded (+ off 64) total w (compressBlock padded off w hs)))

fn hexDigit i: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" i (+ i 1)) "0")

fn hexByte b: Int64 -> String
  (stringConcat (hexDigit (/ b 16)) (hexDigit (mod b 16)))

fn hexWord v: Int64 -> String
  (str (hexByte (mod (/ v 16777216) 256)) (hexByte (mod (/ v 65536) 256)) (hexByte (mod (/ v 256) 256)) (hexByte (mod v 256)))

fn hexDigest s: ShaState -> String
  (str (hexWord s.a) (hexWord s.b) (hexWord s.c) (hexWord s.d)
       (hexWord s.e) (hexWord s.f) (hexWord s.g) (hexWord s.h))

fn ! bytesSha256 data: Bytes -> String
  (let [(padded (buildPadded data))
        (w (bytesAlloc 256))
        (initial (ShaState :a (initialH 0) :b (initialH 1) :c (initialH 2) :d (initialH 3)
                            :e (initialH 4) :f (initialH 5) :g (initialH 6) :h (initialH 7)))
        (final (compressAll padded 0 (bytesLength padded) w initial))]
    (hexDigest final))
