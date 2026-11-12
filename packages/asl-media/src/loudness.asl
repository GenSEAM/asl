(module asl-media/loudness
  :x [Biquad shelfCoeffs highpassCoeffs integratedLufs! blockEnergies!]
  :i [(asl-media/wav :a wav)])

schema Biquad
  (:f b0 Float64)
  (:f b1 Float64)
  (:f b2 Float64)
  (:f a1 Float64)
  (:f a2 Float64)

; (:m :ref U-MEDIA :do "ITU-R BS.1770-4 K-weighting derived for any sample rate from the analog prototype (the 48 kHz table values are what these give at 48000, pinned in the test); the high-pass numerator stays 1 -2 1 unnormalised as in the standard")
fn shelfCoeffs fs: Int64 -> Biquad
  (let [(g 3.999843853973347)
        (q 0.7071752369554196)
        (fc 1681.9744509555319)
        (k (tan (/ (* 3.141592653589793 fc) (int64ToFloat64 fs))))
        (vh (pow 10.0 (/ g 20.0)))
        (vb (pow vh 0.4996667741545416))
        (a0 (+ (+ 1.0 (/ k q)) (* k k)))]
    (Biquad :b0 (/ (+ (+ vh (/ (* vb k) q)) (* k k)) a0)
            :b1 (/ (* 2.0 (- (* k k) vh)) a0)
            :b2 (/ (+ (- vh (/ (* vb k) q)) (* k k)) a0)
            :a1 (/ (* 2.0 (- (* k k) 1.0)) a0)
            :a2 (/ (+ (- 1.0 (/ k q)) (* k k)) a0)))

fn highpassCoeffs fs: Int64 -> Biquad
  (let [(q 0.5003270373253953)
        (fc 38.13547087613982)
        (k (tan (/ (* 3.141592653589793 fc) (int64ToFloat64 fs))))
        (a0 (+ (+ 1.0 (/ k q)) (* k k)))]
    (Biquad :b0 1.0 :b1 -2.0 :b2 1.0
            :a1 (/ (* 2.0 (- (* k k) 1.0)) a0)
            :a2 (/ (+ (- 1.0 (/ k q)) (* k k)) a0)))

fn channelWeight c: Int64 n: Int64 -> Float64
  (cond ((< n 6) 1.0) ((= c 3) 0.0) ((>= c 4) 1.41) (else 1.0))

; (:m :ref U-MEDIA :do "one channel through both K-weighting stages, adding weight times y squared into the per-frame energy slots")
fn ! filterChannel! w: wav/WavAudio c: Int64 f: Int64 s1: Biquad s2: Biquad weight: Float64 en: Bytes x1: Float64 x2: Float64 y1: Float64 y2: Float64 u1: Float64 u2: Float64 v1: Float64 v2: Float64 -> Unit
  (if (>= f w.frames) ()
    (let [(x (wav/wavSampleAt w (+ (* f w.channels) c)))
          (y (- (+ (+ (* s1.b0 x) (* s1.b1 x1)) (* s1.b2 x2)) (+ (* s1.a1 y1) (* s1.a2 y2))))
          (v (- (+ (+ (* s2.b0 y) (* s2.b1 u1)) (* s2.b2 u2)) (+ (* s2.a1 v1) (* s2.a2 v2))))]
      (do
        (bytesSetFloat64 en f (+ (bytesGetFloat64 en f) (* weight (* v v))))
        (filterChannel! w c (+ f 1) s1 s2 weight en x x1 y y1 y u1 v v1))))

fn ! allChannels! w: wav/WavAudio c: Int64 s1: Biquad s2: Biquad en: Bytes -> Unit
  (if (>= c w.channels) ()
    (do (filterChannel! w c 0 s1 s2 (channelWeight c w.channels) en 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)
        (allChannels! w (+ c 1) s1 s2 en)))

fn ! cumulate! en: Bytes cum: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do (bytesSetFloat64 cum (+ i 1) (+ (bytesGetFloat64 cum i) (bytesGetFloat64 en i)))
        (cumulate! en cum (+ i 1) n)))

fn roundI x: Float64 -> Int64
  (optionOr (float64ToInt64 (round x)) 0)

; (:m :ref U-MEDIA :do "gating blocks are 400 ms long with a 100 ms hop (75 percent overlap); the returned Bytes holds one mean-square slot per block")
fn ! blockEnergies! w: wav/WavAudio -> (Pair Bytes Int64)
  (let [(en (bytesAlloc (* w.frames 8)))
        (cum (bytesAlloc (* (+ w.frames 1) 8)))
        (_ (allChannels! w 0 (shelfCoeffs w.sampleRate) (highpassCoeffs w.sampleRate) en))
        (_ (cumulate! en cum 0 w.frames))
        (len (roundI (* 0.4 (int64ToFloat64 w.sampleRate))))
        (hop (roundI (* 0.1 (int64ToFloat64 w.sampleRate))))
        (nb (if (< w.frames len) 0 (+ 1 (/ (- w.frames len) hop))))
        (z (bytesAlloc (* (max nb 1) 8)))
        (_ (fillBlocks! cum z 0 nb len hop))]
    (pair z nb))

fn ! fillBlocks! cum: Bytes z: Bytes j: Int64 nb: Int64 len: Int64 hop: Int64 -> Unit
  (if (>= j nb) ()
    (do (bytesSetFloat64 z j (/ (- (bytesGetFloat64 cum (+ (* j hop) len)) (bytesGetFloat64 cum (* j hop))) (int64ToFloat64 len)))
        (fillBlocks! cum z (+ j 1) nb len hop)))

fn lufsOf z: Float64 -> Float64
  (- (* 10.0 (log10 z)) 0.691)

fn ! gatedSum! z: Bytes j: Int64 nb: Int64 thr: Float64 sum: Float64 cnt: Int64 -> (Pair Float64 Int64)
  (if (>= j nb) (pair sum cnt)
    (let [(v (bytesGetFloat64 z j))]
      (if (and (> v 0.0) (> (lufsOf v) thr))
        (gatedSum! z (+ j 1) nb thr (+ sum v) (+ cnt 1))
        (gatedSum! z (+ j 1) nb thr sum cnt))))

; (:m :ref U-MEDIA :do "integrated loudness: absolute gate -70 LUFS, then a relative gate 10 LU under the mean of the survivors, then the mean of what passes both; a file with no 400 ms block or no block above -70 is a labelled err, not a number")
fn ! integratedLufs! w: wav/WavAudio -> (Result Float64 String)
  (let [(zb (blockEnergies! w))
        (z (pairFirst zb))
        (nb (pairSecond zb))
        (abs1 (gatedSum! z 0 nb -70.0 0.0 0))]
    (cond
      ((= nb 0) (err "loudnessShort: under one 400 ms block"))
      ((= (pairSecond abs1) 0) (err "loudnessSilent: every block is under -70 LUFS"))
      (else
        (let [(rel (- (lufsOf (/ (pairFirst abs1) (int64ToFloat64 (pairSecond abs1)))) 10.0))
              (thr (if (> rel -70.0) rel -70.0))
              (fin (gatedSum! z 0 nb thr 0.0 0))]
          (if (= (pairSecond fin) 0)
            (err "loudnessSilent: nothing passes the relative gate")
            (ok (lufsOf (/ (pairFirst fin) (int64ToFloat64 (pairSecond fin))))))))))
