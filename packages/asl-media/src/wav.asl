(module asl-media/wav
  :x [WavAudio WavStats wavDecode! wavEncode! wavStats wavSampleAt wavFrames wavSilentFrames pow2f float32FromBits float32ToBits]
  :i [])

; (:m :ref U-MEDIA :do "samples are Float64 in [-1, 1) interleaved, 8 bytes each in a Bytes, so every PCM depth and float32 share one analysis path; PCM decode divides by 2^(bits-1) and encode multiplies by it with clamping, which makes encode then decode exact for PCM")
schema WavAudio
  (:f channels Int64)
  (:f sampleRate Int64)
  (:f bitsPerSample Int64)
  (:f isFloat Bool)
  (:f frames Int64)
  (:f samples Bytes)

schema WavStats
  (:f peak Float64)
  (:f rms Float64)
  (:f clipCount Int64)
  (:f silenceRatio Float64)
  (:f dcOffset Float64)

fn le16 bs: Bytes off: Int64 -> Int64
  (+ (bytesGet bs off) (* (bytesGet bs (+ off 1)) 256))

fn le32 bs: Bytes off: Int64 -> Int64
  (+ (le16 bs off) (* (le16 bs (+ off 2)) 65536))

fn tag? bs: Bytes off: Int64 a: Int64 b: Int64 c: Int64 d: Int64 -> Bool
  (and (= (bytesGet bs off) a) (and (= (bytesGet bs (+ off 1)) b) (and (= (bytesGet bs (+ off 2)) c) (= (bytesGet bs (+ off 3)) d))))

fn pow2f n: Int64 -> Float64
  (pow 2.0 (int64ToFloat64 n))

fn wavFrames w: WavAudio -> Int64
  w.frames

fn wavSampleAt w: WavAudio i: Int64 -> Float64
  (bytesGetFloat64 w.samples i)

fn float32FromBits bits: Int64 -> (Result Float64 String)
  (let [(sign (if (>= bits 2147483648) -1.0 1.0))
        (e (mod (/ bits 8388608) 256))
        (m (mod bits 8388608))]
    (cond
      ((= e 255) (err "wavFloat: non-finite sample"))
      ((= e 0) (ok (* sign (* (int64ToFloat64 m) (pow2f -149)))))
      (else (ok (* sign (* (+ 1.0 (/ (int64ToFloat64 m) 8388608.0)) (pow2f (- e 127))))))))

fn float32ToBits x: Float64 -> Int64
  (let [(neg (< x 0.0))
        (a (abs x))
        (s (if neg 2147483648 0))]
    (cond
      ((= a 0.0) s)
      ((>= a 3.4028234663852886e38) (+ s 2139095039))
      ((< a (pow2f -126)) (+ s (roundInt (* a (pow2f 149)))))
      (else
        (let [(e0 (floatToInt (floor (log2 a))))
              (e (if (< a (pow2f e0)) (- e0 1) (if (>= a (pow2f (+ e0 1))) (+ e0 1) e0)))
              (m (roundInt (* (- (/ a (pow2f e)) 1.0) 8388608.0)))]
          (if (>= m 8388608)
            (+ s (* (+ e 128) 8388608))
            (+ s (+ (* (+ e 127) 8388608) m)))))))

fn roundInt x: Float64 -> Int64
  (optionOr (float64ToInt64 (round x)) 0)

fn floatToInt x: Float64 -> Int64
  (optionOr (float64ToInt64 x) 0)

fn signed v: Int64 bits: Int64 -> Int64
  (if (>= v (pow2i (- bits 1))) (- v (pow2i bits)) v)

fn pow2i n: Int64 -> Int64
  (if (<= n 0) 1 (* 2 (pow2i (- n 1))))

fn ! decodeSamples! bs: Bytes off: Int64 bytesPer: Int64 isFloat: Bool total: Int64 out: Bytes i: Int64 -> (Result Unit String)
  (if (>= i total) (ok ())
    (let [(p (+ off (* i bytesPer)))
          (raw (cond ((= bytesPer 1) (bytesGet bs p))
                     ((= bytesPer 2) (le16 bs p))
                     ((= bytesPer 3) (+ (le16 bs p) (* (bytesGet bs (+ p 2)) 65536)))
                     (else (le32 bs p))))]
      (if isFloat
        (match (float32FromBits raw)
          ((err e) (err e))
          ((ok f) (do (bytesSetFloat64 out i f) (decodeSamples! bs off bytesPer isFloat total out (+ i 1)))))
        (let [(v (if (= bytesPer 1)
                   (/ (int64ToFloat64 (- raw 128)) 128.0)
                   (/ (int64ToFloat64 (signed raw (* bytesPer 8))) (int64ToFloat64 (pow2i (- (* bytesPer 8) 1))))))]
          (do (bytesSetFloat64 out i v)
              (decodeSamples! bs off bytesPer isFloat total out (+ i 1)))))))

schema WavScan
  (:f fmtAt Int64)
  (:f fmtLen Int64)
  (:f dataAt Int64)
  (:f dataLen Int64)

fn ! scanChunks! bs: Bytes pos: Int64 sc: WavScan -> (Result WavScan String)
  (cond
    ((and (>= sc.fmtAt 0) (>= sc.dataAt 0)) (ok sc))
    ((> (+ pos 8) (bytesLength bs)) (ok sc))
    (else
      (let [(len (le32 bs (+ pos 4)))
            (body (+ pos 8))
            (isData (tag? bs pos 100 97 116 97))
            (avail (- (bytesLength bs) body))
            (clamped (if (and isData (or (> len avail) (= len 4294967295))) avail len))]
        (cond
          ((and (not isData) (> len avail)) (err "wavTruncated: chunk runs past the end"))
          ((and isData (> len avail) (!= len 4294967295)) (err "wavTruncated: data chunk runs past the end"))
          (else
            (let [(sc2 (cond
                         ((tag? bs pos 102 109 116 32) (with (with sc :fmtAt body) :fmtLen len))
                         (isData (with (with sc :dataAt body) :dataLen clamped))
                         (else sc)))]
              (scanChunks! bs (+ body (+ clamped (mod clamped 2))) sc2)))))))

fn ! wavDecode! bs: Bytes maxFrames: Int64 -> (Result WavAudio String)
  (cond
    ((< (bytesLength bs) 12) (err "wavTruncated: shorter than a RIFF header"))
    ((not (and (tag? bs 0 82 73 70 70) (tag? bs 8 87 65 86 69))) (err "wavFormat: not RIFF/WAVE"))
    (else
      (match (scanChunks! bs 12 (WavScan :fmtAt -1 :fmtLen 0 :dataAt -1 :dataLen 0))
        ((err e) (err e))
        ((ok sc)
          (cond
            ((< sc.fmtAt 0) (err "wavStructure: no fmt chunk"))
            ((< sc.fmtLen 16) (err "wavStructure: fmt chunk too short"))
            ((< sc.dataAt 0) (err "wavStructure: no data chunk"))
            (else (decodeFmt! bs sc maxFrames)))))))

fn ! decodeFmt! bs: Bytes sc: WavScan maxFrames: Int64 -> (Result WavAudio String)
  (let [(tagRaw (le16 bs sc.fmtAt))
        (ch (le16 bs (+ sc.fmtAt 2)))
        (rate (le32 bs (+ sc.fmtAt 4)))
        (bits (le16 bs (+ sc.fmtAt 14)))
        (tagId (if (and (= tagRaw 65534) (>= sc.fmtLen 26)) (le16 bs (+ sc.fmtAt 24)) tagRaw))
        (isFloat (= tagId 3))
        (bytesPer (/ bits 8))]
    (cond
      ((not (or (= tagId 1) (= tagId 3))) (err (str "wavUnsupported: format tag " (stringFromInt64 tagId))))
      ((or (< ch 1) (> ch 64)) (err "wavStructure: channel count out of range"))
      ((<= rate 0) (err "wavStructure: sample rate is zero"))
      ((not (if isFloat (= bits 32) (or (= bits 8) (or (= bits 16) (or (= bits 24) (= bits 32)))))) (err (str "wavUnsupported: " (stringFromInt64 bits) " bits")))
      (else
        (let [(frames (/ sc.dataLen (* ch bytesPer)))]
          (if (> frames maxFrames)
            (err (str "wavLimit: more than " (stringFromInt64 maxFrames) " frames"))
            (let [(out (bytesAlloc (* (* frames ch) 8)))]
              (match (decodeSamples! bs sc.dataAt bytesPer isFloat (* frames ch) out 0)
                ((err e) (err e))
                ((ok _) (ok (WavAudio :channels ch :sampleRate rate :bitsPerSample bits :isFloat isFloat :frames frames :samples out))))))))))

fn put16! b: Bytes off: Int64 v: Int64 -> Unit
  (do (bytesSet b off (mod v 256)) (bytesSet b (+ off 1) (mod (/ v 256) 256)))

fn put32! b: Bytes off: Int64 v: Int64 -> Unit
  (do (put16! b off (mod v 65536)) (put16! b (+ off 2) (/ v 65536)))

fn putTag! b: Bytes off: Int64 a: Int64 c: Int64 d: Int64 e: Int64 -> Unit
  (do (bytesSet b off a) (bytesSet b (+ off 1) c) (bytesSet b (+ off 2) d) (bytesSet b (+ off 3) e))

fn clampInt v: Int64 lo: Int64 hi: Int64 -> Int64
  (if (< v lo) lo (if (> v hi) hi v))

fn ! encodeSamples! s: Bytes out: Bytes off: Int64 bits: Int64 isFloat: Bool total: Int64 i: Int64 -> Unit
  (if (>= i total) ()
    (let [(x (bytesGetFloat64 s i))
          (bp (/ bits 8))
          (p (+ off (* i bp)))]
      (do
        (if isFloat
          (put32! out p (float32ToBits x))
          (let [(half (pow2i (- bits 1)))
                (v (clampInt (roundInt (* x (int64ToFloat64 half))) (- 0 half) (- half 1)))
                (u (if (< v 0) (+ v (pow2i bits)) v))]
            (if (= bp 2)
              (put16! out p u)
              (if (= bp 3)
                (do (put16! out p (mod u 65536)) (bytesSet out (+ p 2) (/ u 65536)))
                (put32! out p u)))))
        (encodeSamples! s out off bits isFloat total (+ i 1)))))

fn ! wavEncode! w: WavAudio -> (Result Bytes String)
  (let [(bits w.bitsPerSample)
        (bp (/ bits 8))
        (okBits (if w.isFloat (= bits 32) (or (= bits 16) (or (= bits 24) (= bits 32)))))
        (dataLen (* (* w.frames w.channels) bp))
        (pad (mod dataLen 2))
        (total (+ 44 (+ dataLen pad)))]
    (cond
      ((not okBits) (err (str "wavUnsupported: cannot encode " (stringFromInt64 bits) " bits")))
      ((or (< w.channels 1) (<= w.sampleRate 0)) (err "wavStructure: channels or rate out of range"))
      ((!= (bytesLength w.samples) (* (* w.frames w.channels) 8)) (err "wavStructure: samples length does not match frames*channels"))
      ((> total 4294967295) (err "wavLimit: over 4 GiB"))
      (else
        (let [(out (bytesAlloc total))]
          (do
            (putTag! out 0 82 73 70 70)
            (put32! out 4 (- total 8))
            (putTag! out 8 87 65 86 69)
            (putTag! out 12 102 109 116 32)
            (put32! out 16 16)
            (put16! out 20 (if w.isFloat 3 1))
            (put16! out 22 w.channels)
            (put32! out 24 w.sampleRate)
            (put32! out 28 (* (* w.sampleRate w.channels) bp))
            (put16! out 32 (* w.channels bp))
            (put16! out 34 bits)
            (putTag! out 36 100 97 116 97)
            (put32! out 40 dataLen)
            (encodeSamples! w.samples out 44 bits w.isFloat (* w.frames w.channels) 0)
            (ok out))))))

fn ! sumLoop! s: Bytes i: Int64 n: Int64 acc: Float64 mode: Int64 thr: Float64 -> Float64
  (if (>= i n) acc
    (let [(x (bytesGetFloat64 s i))
          (v (cond ((= mode 0) (abs x))
                   ((= mode 1) (* x x))
                   ((= mode 2) x)
                   (else (if (>= (abs x) thr) 1.0 0.0))))]
      (sumLoop! s (+ i 1) n (if (= mode 0) (if (> v acc) v acc) (+ acc v)) mode thr)))

fn ! silentLoop! w: WavAudio f: Int64 thr: Float64 c: Int64 acc: Int64 -> Int64
  (if (>= f w.frames) acc
    (let [(quiet (frameQuiet! w f 0 thr))]
      (silentLoop! w (+ f 1) thr c (if quiet (+ acc 1) acc))))

fn ! frameQuiet! w: WavAudio f: Int64 k: Int64 thr: Float64 -> Bool
  (cond
    ((>= k w.channels) true)
    ((>= (abs (bytesGetFloat64 w.samples (+ (* f w.channels) k))) thr) false)
    (else (frameQuiet! w f (+ k 1) thr)))

fn ! wavSilentFrames w: WavAudio thr: Float64 -> Int64
  (silentLoop! w 0 thr w.channels 0)

; (:m :ref U-MEDIA :do "clipping is a sample whose magnitude reaches clipAt (0.9999 flags full-scale PCM); silence is a frame whose every channel stays under silenceBelow; an empty file gives zeros, not a division")
fn ! wavStats w: WavAudio clipAt: Float64 silenceBelow: Float64 -> WavStats
  (let [(n (* w.frames w.channels))]
    (if (= n 0)
      (WavStats :peak 0.0 :rms 0.0 :clipCount 0 :silenceRatio 0.0 :dcOffset 0.0)
      (WavStats :peak (sumLoop! w.samples 0 n 0.0 0 0.0)
                :rms (sqrt (/ (sumLoop! w.samples 0 n 0.0 1 0.0) (int64ToFloat64 n)))
                :clipCount (floatToInt (sumLoop! w.samples 0 n 0.0 3 clipAt))
                :silenceRatio (/ (int64ToFloat64 (wavSilentFrames w silenceBelow)) (int64ToFloat64 w.frames))
                :dcOffset (/ (sumLoop! w.samples 0 n 0.0 2 0.0) (int64ToFloat64 n)))))
