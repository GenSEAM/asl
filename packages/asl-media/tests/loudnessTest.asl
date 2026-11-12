(module asl-media/tests/loudnessTest
  :x [runTests]
  :i [(asl-media/wav :a wav) (asl-media/loudness :a ld)])

fn near? a: Float64 b: Float64 tol: Float64 -> Bool
  (< (abs (- a b)) tol)

; (:m :ref U-MEDIA :do "stereo test tone of freq Hz at linear amp for frames from index from, both channels identical")
fn ! tone! b: Bytes from: Int64 frames: Int64 rate: Int64 freq: Float64 amp: Float64 i: Int64 -> Unit
  (if (>= i frames) ()
    (let [(x (* amp (sin (/ (* (* 6.283185307179586 freq) (int64ToFloat64 (+ from i))) (int64ToFloat64 rate)))))]
      (do (bytesSetFloat64 b (* 2 (+ from i)) x)
          (bytesSetFloat64 b (+ 1 (* 2 (+ from i))) x)
          (tone! b from frames rate freq amp (+ i 1)))))

fn db x: Float64 -> Float64
  (pow 10.0 (/ x 20.0))

fn audio b: Bytes frames: Int64 -> wav/WavAudio
  (wav/WavAudio :channels 2 :sampleRate 48000 :bitsPerSample 32 :isFloat true :frames frames :samples b)

fn ! testCoefficients! -> Bool
  (let [(s (ld/shelfCoeffs 48000))
        (h (ld/highpassCoeffs 48000))]
    (do
      (assert (near? s.b0 1.53512485958697 0.000001) "shelf b0 at 48 kHz matches the BS.1770-4 table")
      (assert (near? s.b1 -2.69169618940638 0.000001) "shelf b1")
      (assert (near? s.b2 1.19839281085285 0.000001) "shelf b2")
      (assert (near? s.a1 -1.69065929318241 0.000001) "shelf a1")
      (assert (near? s.a2 0.73248077421585 0.000001) "shelf a2")
      (assert (near? h.a1 -1.99004745483398 0.000001) "high-pass a1")
      (assert (near? h.a2 0.99007225036621 0.000001) "high-pass a2")
      true))

fn ! testSine! -> Bool
  (let [(frames 576000)
        (b (bytesAlloc (* (* frames 2) 8)))
        (_ (tone! b 0 frames 48000 997.0 (db -23.0) 0))]
    (match (ld/integratedLufs! (audio b frames))
      ((err e) (do (assert false e) false))
      ((ok l) (do (assert (near? l -23.0 0.1) (str "997 Hz stereo sine at -23 dBFS reads -23.0 +-0.1 LU, got " (stringFromFloat64 l))) true))))

fn ! testGating! -> Bool
  (let [(half 480000)
        (b (bytesAlloc (* (* (* half 2) 2) 8)))
        (_ (tone! b 0 half 48000 997.0 (db -20.0) 0))
        (_ (tone! b half half 48000 997.0 (db -45.0) 0))]
    (match (ld/integratedLufs! (audio b (* half 2)))
      ((err e) (do (assert false e) false))
      ((ok l) (do (assert (near? l -20.0 0.15) (str "the relative gate drops the quiet half: -20 LUFS, got " (stringFromFloat64 l))) true))))

fn ! testErrors! -> Bool
  (let [(short (bytesAlloc (* (* 1000 2) 8)))
        (quiet (bytesAlloc (* (* 96000 2) 8)))
        (_ (tone! quiet 0 96000 48000 997.0 (db -90.0) 0))]
    (do
      (assert (stringStartsWith? (match (ld/integratedLufs! (audio short 1000)) ((err e) e) ((ok _) "")) "loudnessShort") "under 400 ms is a labelled err")
      (assert (stringStartsWith? (match (ld/integratedLufs! (audio quiet 96000)) ((err e) e) ((ok _) "")) "loudnessSilent") "everything under -70 LUFS is a labelled err")
      true))

fn ! runTests -> Bool
  (do
    (testCoefficients!)
    (testSine!)
    (testGating!)
    (testErrors!)
    true)
