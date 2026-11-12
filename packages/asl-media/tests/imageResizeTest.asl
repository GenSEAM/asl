(module asl-media/tests/imageResizeTest
  :x [runTests]
  :i [(asl-media/image :a im) (asl-media/imageResize :a rs)])

fn ! setAll! b: Bytes xs: (List Int64) i: Int64 -> Unit
  (match (listHead xs)
    ((none) ())
    ((some v) (do (bytesSet b i v) (setAll! b (optionOr (listTail xs) (list)) (+ i 1)))))

fn ! mk w: Int64 h: Int64 xs: (List Int64) -> im/Image
  (let [(b (bytesAlloc (length xs)))
        (_ (setAll! b xs 0))]
    (im/Image :width w :height h :rgba b))

fn bytesList b: Bytes i: Int64 -> (List Int64)
  (if (>= i (bytesLength b)) (list) (cons (bytesGet b i) (bytesList b (+ i 1))))

fn px img: im/Image -> (List Int64)
  (bytesList img.rgba 0)

fn reds img: im/Image -> (List Int64)
  (filterEvery (px img) 0)

fn filterEvery xs: (List Int64) k: Int64 -> (List Int64)
  (map (fn [(p (Pair Int64 Int64))] -> Int64 (pairSecond p))
       (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (mod (pairFirst p) 4) k)) (indexed xs 0)))

fn indexed xs: (List Int64) i: Int64 -> (List (Pair Int64 Int64))
  (match (listHead xs)
    ((none) (list))
    ((some v) (cons (pair i v) (indexed (optionOr (listTail xs) (list)) (+ i 1)))))

fn gray w: Int64 h: Int64 vs: (List Int64) -> im/Image
  (mk w h (listFlatMap (fn [(v Int64)] -> (List Int64) (list v v v 255)) vs))

fn rs4 img: im/Image m: String w: Int64 h: Int64 -> (List Int64)
  (match (rs/imageResize img m w h)
    ((ok r) (reds r))
    ((err e) (list -1)))

fn errOf r: (Result im/Image String) -> String
  (match r
    ((ok _) "")
    ((err e) e))

fn testArea! -> Bool
  (let [(g4 (gray 4 4 (list 0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150)))]
    (do
      (assert (= (rs4 g4 "area" 2 2) (list 25 45 105 125)) "4x4 to 2x2 area is the mean of each 2x2 block")
      (assert (= (rs4 (gray 2 2 (list 0 100 200 255)) "area" 1 1) (list 139)) "2x2 to 1x1 area mean 138.75 rounds to 139")
      (assert (= (rs4 (gray 2 1 (list 1 2)) "area" 1 1) (list 2)) "mean 1.5 rounds half up to 2")
      (assert (= (rs4 (gray 3 1 (list 0 30 60)) "area" 2 1) (list 10 50)) "3 to 2 weights the middle pixel by overlap: 10 and 50")
      (assert (= (rs4 (gray 1 1 (list 77)) "area" 3 3) (list 77 77 77 77 77 77 77 77 77)) "area upscale of one pixel repeats it")
      (assert (= (px (okImg (rs/imageResize g4 "area" 2 2))) (list 25 25 25 255 45 45 45 255 105 105 105 255 125 125 125 255)) "every channel is resized and alpha stays 255")
      true))

fn okImg r: (Result im/Image String) -> im/Image
  (match r
    ((ok i) i)
    ((err e) (do (assert false e) (im/Image :width 1 :height 1 :rgba (bytesAlloc 4)))))

fn testNearest! -> Bool
  (do
    (assert (= (rs4 (gray 2 1 (list 10 20)) "nearest" 4 1) (list 10 10 20 20)) "nearest upscale repeats pixels")
    (assert (= (rs4 (gray 4 1 (list 1 2 3 4)) "nearest" 2 1) (list 2 4)) "nearest downscale takes the centre sample, upper one on a tie")
    (assert (= (rs4 (gray 2 2 (list 1 2 3 4)) "nearest" 1 1) (list 4)) "2x2 to 1x1 nearest takes pixel 3")
    true)

fn testBilinear! -> Bool
  (do
    (assert (= (rs4 (gray 2 1 (list 0 100)) "bilinear" 4 1) (list 0 25 75 100)) "bilinear upscale 2 to 4: 0 25 75 100")
    (assert (= (rs4 (gray 2 2 (list 0 100 200 255)) "bilinear" 1 1) (list 139)) "bilinear 2x2 to 1x1 is the mean")
    true)

fn testIdentity! -> Bool
  (let [(g (gray 5 3 (list 0 255 3 200 9 77 8 6 100 1 2 250 33 44 55)))]
    (do
      (assert (= (reds (okImg (rs/imageResize g "area" 5 3))) (reds g)) "area to the same size is the identity")
      (assert (= (reds (okImg (rs/imageResize g "bilinear" 5 3))) (reds g)) "bilinear to the same size is the identity")
      (assert (= (reds (okImg (rs/imageResize g "lanczos3" 5 3))) (reds g)) "lanczos3 to the same size is the identity")
      (assert (= (reds (okImg (rs/imageResize g "nearest" 5 3))) (reds g)) "nearest to the same size is the identity")
      true))

fn allEq? xs: (List Int64) v: Int64 -> Bool
  (listAll? (fn [(x Int64)] -> Bool (= x v)) xs)

fn testConstant! -> Bool
  (let [(c (gray 7 5 (map (fn [(i Int64)] -> Int64 77) (range 0 35))))]
    (do
      (assert (allEq? (rs4 c "lanczos3" 3 2) 77) "lanczos3 downscale keeps a constant image constant")
      (assert (allEq? (rs4 c "lanczos3" 13 11) 77) "lanczos3 upscale keeps a constant image constant")
      (assert (allEq? (rs4 c "bilinear" 3 2) 77) "bilinear downscale keeps a constant image constant")
      (assert (allEq? (rs4 c "area" 3 2) 77) "area downscale keeps a constant image constant")
      (assert (= (rs4 (gray 4 1 (list 0 100 100 0)) "lanczos3" 2 1) (list 61 61)) "lanczos3 of a 0 100 100 0 bump to 2 px is 61 61 (python oracle 60.51)")
      true))

fn testTaps! -> Bool
  (let [(alt (gray 10 1 (list 0 255 0 255 0 255 0 255 0 255)))
        (spike (gray 10 1 (list 0 0 0 255 0 0 0 0 0 0)))]
    (do
      (assert (= (rs4 alt "lanczos3" 7 1) (list 99 132 128 127 127 123 156)) "lanczos3 10 to 7 alternating matches the python oracle, taps with 2<=|t|<3 included")
      (assert (= (rs4 alt "lanczos3" 13 1) (list 0 196 155 22 254 43 128 212 1 233 100 59 255)) "lanczos3 10 to 13 alternating matches the python oracle")
      (assert (= (rs4 spike "lanczos3" 7 1) (list 0 8 179 0 2 0 0)) "lanczos3 of a single spike keeps the outer lobe at 2, which a |t|<2 cutoff zeroes")
      true))

fn testErrors! -> Bool
  (let [(g (gray 2 2 (list 1 2 3 4)))]
    (do
      (assert (stringStartsWith? (errOf (rs/imageResize g "cubic" 1 1)) "imageMethod") "an unknown method is imageMethod")
      (assert (stringStartsWith? (errOf (rs/imageResize g "area" 0 1)) "imageSize") "a zero target is imageSize")
      (assert (stringStartsWith? (errOf (rs/imageResize g "area" 1 -3)) "imageSize") "a negative target is imageSize")
      (assert (stringStartsWith? (errOf (rs/imageResize g "area" 70000 70000)) "imageSize") "a target above the pixel cap is imageSize")
      (assert (stringStartsWith? (errOf (rs/imageResize (gray 1 1000 (map (fn [(i Int64)] -> Int64 5) (range 0 1000))) "area" 1000000 1)) "imageSize") "a 1x1000 source to 1000000x1 is imageSize, the intermediate buffer is bounded too")
      (assert (stringStartsWith? (errOf (rs/imageResize (gray 1 1000 (map (fn [(i Int64)] -> Int64 5) (range 0 1000))) "lanczos3" 100000 1)) "imageSize") "the same bound holds for lanczos3")
      true))

fn testLarge! -> Bool
  (match (im/imageSolid 2048 2048 77 77 77 255)
    ((err e) (do (assert false e) false))
    ((ok big)
      (let [(t0 (monotonicNs))
            (r (rs/imageResize big "area" 1024 1024))
            (t1 (monotonicNs))]
        (match r
          ((err e) (do (assert false e) false))
          ((ok small)
            (do
              (assert (and (= small.width 1024) (= small.height 1024)) "2048 to 1024 gives 1024x1024")
              (assert (= (match (im/imageHistogram small 0) ((ok h) (optionOr (listGet h 77) 0)) ((err _) 0)) 1048576) "every one of the 1048576 output pixels is 77")
              (assert (< (/ (- t1 t0) 1000000) 120000) "2048x2048 area resize finishes inside 120 s")
              (print (str "(:resize2048 :areaMs " (stringFromInt64 (/ (- t1 t0) 1000000)) ")"))
              true))))))

fn ! runTests -> Bool
  (do
    (testArea!)
    (testNearest!)
    (testBilinear!)
    (testIdentity!)
    (testConstant!)
    (testTaps!)
    (testErrors!)
    (testLarge!)
    true)
