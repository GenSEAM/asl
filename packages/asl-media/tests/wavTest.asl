(module asl-media/tests/wavTest
  :x [runTests]
  :i [(asl-media/wav :a wav)])

fn readBytes! name: String -> Bytes
  (match (fileReadBytes (str "asl/packages/asl-media/tests/fixtures/" name))
    ((ok b) b)
    ((err _) (bytesAlloc 0)))

fn decodeOk! name: String -> wav/WavAudio
  (match (wav/wavDecode! (readBytes! name) 1000000)
    ((ok w) w)
    ((err e) (do (assert false (str name ": " e)) (wav/WavAudio :channels 0 :sampleRate 0 :bitsPerSample 0 :isFloat false :frames 0 :samples (bytesAlloc 0)))))

fn errOf bs: Bytes -> String
  (match (wav/wavDecode! bs 1000000)
    ((ok _) "")
    ((err e) e))

fn near? a: Float64 b: Float64 tol: Float64 -> Bool
  (< (abs (- a b)) tol)

fn ! testFixtures! -> Bool
  (let [(s (decodeOk! "pcm16s.wav"))
        (m (decodeOk! "pcm24m.wav"))
        (f (decodeOk! "f32m.wav"))]
    (do
      (assert (and (= s.channels 2) (= s.sampleRate 8000) (= s.bitsPerSample 16) (= s.frames 4)) "pcm16 stereo header, LIST chunk with odd padding skipped")
      (assert (= (wav/wavSampleAt s 2) 0.5) "frame 1 left is 16384/32768")
      (assert (= (wav/wavSampleAt s 3) -0.5) "frame 1 right")
      (assert (= (wav/wavSampleAt s 5) -1.0) "frame 2 right is -32768/32768")
      (assert (= (wav/wavSampleAt s 4) (/ 32767.0 32768.0)) "frame 2 left is 32767/32768")
      (assert (and (= m.frames 3) (= m.bitsPerSample 24) (= m.sampleRate 44100)) "pcm24 mono header, odd data length padded")
      (assert (= (wav/wavSampleAt m 0) 0.5) "24-bit 4194304 is 0.5")
      (assert (= (wav/wavSampleAt m 1) -1.0) "24-bit sign extension")
      (assert (and f.isFloat (= f.frames 5)) "float32 header")
      (assert (= (wav/wavSampleAt f 0) 0.5) "float32 0.5")
      (assert (= (wav/wavSampleAt f 1) -0.25) "float32 -0.25")
      (assert (= (wav/wavSampleAt f 2) 0.15625) "float32 0.15625")
      (assert (= (wav/wavSampleAt f 3) -2.0) "float32 -2.0 outside [-1,1] kept")
      (assert (and (> (wav/wavSampleAt f 4) 0.0) (< (wav/wavSampleAt f 4) 1.0e-44)) "float32 denormal 2^-149")
      true))

fn ! testFloatBits! -> Bool
  (do
    (assert (= (wav/float32ToBits 1.0) 1065353216) "1.0 is 0x3F800000")
    (assert (= (wav/float32ToBits -2.0) 3221225472) "-2.0 is 0xC0000000")
    (assert (= (wav/float32ToBits 0.1) 1036831949) "0.1 rounds to 0x3DCCCCCD")
    (assert (= (wav/float32ToBits 0.0) 0) "zero")
    (assert (= (wav/float32ToBits 1.0e39) 2139095039) "overflow clamps to the largest finite")
    (assert (err? (wav/float32FromBits 2139095040)) "infinity is a labelled err")
    true)

fn ramp! w: Int64 i: Int64 -> Float64
  (/ (int64ToFloat64 (- (mod (* i 7919) 65536) 32768)) 32768.0)

fn fillRamp! b: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do (bytesSetFloat64 b i (ramp! 0 i)) (fillRamp! b (+ i 1) n)))

fn sameSamples? a: wav/WavAudio b: wav/WavAudio i: Int64 -> Bool
  (cond
    ((>= i (* a.frames a.channels)) true)
    ((!= (wav/wavSampleAt a i) (wav/wavSampleAt b i)) false)
    (else (sameSamples? a b (+ i 1))))

fn ! roundTrip? bits: Int64 isFloat: Bool -> Bool
  (let [(s (bytesAlloc (* 301 8)))
        (_ (fillRamp! s 0 301))
        (w (wav/WavAudio :channels 3 :sampleRate 22050 :bitsPerSample bits :isFloat isFloat :frames 100 :samples (bytesSub! s 100)))]
    (match (wav/wavEncode! w)
      ((err _) false)
      ((ok enc)
        (match (wav/wavDecode! enc 1000)
          ((err _) false)
          ((ok d) (and (= d.frames 100) (and (= d.channels 3) (and (= d.sampleRate 22050) (sameSamples? w d 0)))))))))

fn bytesSub! s: Bytes n: Int64 -> Bytes
  (let [(o (bytesAlloc (* (* n 3) 8)))]
    (do (cpy! s o 0 (* (* n 3) 8)) o))

fn cpy! a: Bytes b: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) () (do (bytesSet b i (bytesGet a i)) (cpy! a b (+ i 1) n)))

fn ! testRoundTrips! -> Bool
  (do
    (assert (roundTrip? 16 false) "pcm16 encode then decode is exact")
    (assert (roundTrip? 24 false) "pcm24 round trip exact")
    (assert (roundTrip? 32 false) "pcm32 round trip exact")
    (assert (roundTrip? 32 true) "float32 round trip exact on 16-bit-grid values")
    true)

fn ! testErrors! -> Bool
  (let [(good (readBytes! "pcm16s.wav"))
        (n (bytesLength good))]
    (do
      (assert (stringStartsWith? (errOf (bytesAlloc 4)) "wavTruncated") "truncated header")
      (assert (stringStartsWith? (errOf (headOf! good 12)) "wavStructure") "a RIFF header with no chunks has no fmt")
      (assert (stringStartsWith? (errOf (headOf! good (- n 2))) "wavTruncated") "data chunk cut short")
      (assert (stringStartsWith? (errOf (bytesAlloc 64)) "wavFormat") "zeros are not RIFF")
      (assert (stringStartsWith? (errOf (patched! good 20 7)) "wavUnsupported") "format tag 7 is refused")
      (assert (stringStartsWith? (errOf (patched! good 34 12)) "wavUnsupported") "12-bit is refused")
      (assert (stringStartsWith? (match (wav/wavDecode! good 3) ((err e) e) ((ok _) "")) "wavLimit") "frame budget enforced")
      true))

fn headOf! b: Bytes n: Int64 -> Bytes
  (let [(o (bytesAlloc n))] (do (cpy! b o 0 n) o))

fn patched! b: Bytes at: Int64 v: Int64 -> Bytes
  (let [(o (headOf! b (bytesLength b)))] (do (bytesSet o at v) o))

fn ! testStats! -> Bool
  (let [(s (bytesAlloc 80))
        (_ (do (bytesSetFloat64 s 0 0.0) (bytesSetFloat64 s 1 0.0) (bytesSetFloat64 s 2 1.0) (bytesSetFloat64 s 3 -1.0)
               (bytesSetFloat64 s 4 0.5) (bytesSetFloat64 s 5 0.0) (bytesSetFloat64 s 6 0.0) (bytesSetFloat64 s 7 0.5)
               (bytesSetFloat64 s 8 0.25) (bytesSetFloat64 s 9 0.75)))
        (w (wav/WavAudio :channels 2 :sampleRate 8000 :bitsPerSample 16 :isFloat false :frames 5 :samples s))
        (st (wav/wavStats w 0.9999 0.01))]
    (do
      (assert (= st.peak 1.0) "peak")
      (assert (= st.clipCount 2) "two samples reach full scale")
      (assert (= (wav/wavStats w 1.0 0.01).clipCount 2) "a sample exactly at the threshold counts")
      (assert (near? st.silenceRatio 0.2 0.0001) "only frame 0 is silent: a loud second channel breaks silence")
      (assert (near? st.rms (sqrt (/ 3.125 10.0)) 0.000001) "rms")
      (assert (near? st.dcOffset (/ 2.0 10.0) 0.000001) "dc offset is the mean")
      (assert (= (wav/wavStats (wav/WavAudio :channels 1 :sampleRate 8000 :bitsPerSample 16 :isFloat false :frames 0 :samples (bytesAlloc 0)) 0.9 0.01).clipCount 0) "empty audio does not divide")
      true))

fn ! runTests -> Bool
  (do
    (testFloatBits!)
    (testFixtures!)
    (testRoundTrips!)
    (testErrors!)
    (testStats!)
    true)
