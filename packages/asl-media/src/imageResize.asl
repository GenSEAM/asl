(module asl-media/imageResize
  :x [imageResize resizeMethods weightRange kernelWeight]
  :i [(asl-media/image :a im)])

; (:m :ref workspace-20261031-imageOps :do "resize is separable: a horizontal then a vertical weighted pass over straight RGBA channels in Float64, result rounded half up and clamped to 0..255; area is the exact box overlap so integer downscales are plain means, bilinear and lanczos3 widen their support by the scale on downscale; nearest samples the centre; resize on premultiplied pixels when colour must not bleed from transparent ones")
fn resizeMethods -> (List String)
  (list "nearest" "bilinear" "area" "lanczos3")

fn pi -> Float64
  3.141592653589793

fn sinc x: Float64 -> Float64
  (if (= x 0.0) 1.0 (/ (sin (* (pi) x)) (* (pi) x)))

fn scaleOf s: Int64 d: Int64 -> Float64
  (/ (int64ToFloat64 s) (int64ToFloat64 d))

fn filterScale scale: Float64 -> Float64
  (max scale 1.0)

fn support kind: String scale: Float64 -> Float64
  (cond
    ((= kind "area") (/ scale 2.0))
    ((= kind "bilinear") (filterScale scale))
    (else (* 3.0 (filterScale scale))))

fn kernelWeight kind: String i: Int64 o: Int64 scale: Float64 -> Float64
  (let [(c (* (+ (int64ToFloat64 o) 0.5) scale))
        (fs (filterScale scale))
        (t (/ (- (+ (int64ToFloat64 i) 0.5) c) fs))]
    (cond
      ((= kind "area")
        (let [(lo (* (int64ToFloat64 o) scale))
              (hi (* (+ (int64ToFloat64 o) 1.0) scale))]
          (max 0.0 (- (min (+ (int64ToFloat64 i) 1.0) hi) (max (int64ToFloat64 i) lo)))))
      ((= kind "bilinear") (max 0.0 (- 1.0 (abs t))))
      (else (if (< (abs t) 3.0) (* (sinc t) (sinc (/ t 3.0))) 0.0))))

fn weightRange kind: String o: Int64 s: Int64 scale: Float64 -> (Pair Int64 Int64)
  (let [(c (* (+ (int64ToFloat64 o) 0.5) scale))
        (sup (support kind scale))
        (a (max 0 (optionOr (float64ToInt64 (floor (- c sup))) 0)))
        (b (min (- s 1) (optionOr (float64ToInt64 (floor (+ c sup))) 0)))]
    (pair a (max a b)))

fn tapStride kind: String scale: Float64 -> Int64
  (+ 4 (optionOr (float64ToInt64 (floor (* 2.0 (support kind scale)))) 0))

fn ! sumWeights! kind: String o: Int64 scale: Float64 i: Int64 b: Int64 acc: Float64 -> Float64
  (if (> i b) acc (sumWeights! kind o scale (+ i 1) b (+ acc (kernelWeight kind i o scale))))

fn ! writeTaps! tbl: Bytes base: Int64 kind: String o: Int64 scale: Float64 a: Int64 i: Int64 b: Int64 total: Float64 -> Unit
  (if (> i b) ()
    (do (bytesSetFloat64 tbl (+ (+ base 2) (- i a)) (/ (kernelWeight kind i o scale) total))
        (writeTaps! tbl base kind o scale a (+ i 1) b total)))

fn ! buildRows! tbl: Bytes stride: Int64 kind: String s: Int64 scale: Float64 o: Int64 d: Int64 -> Unit
  (if (>= o d) ()
    (let [(r (weightRange kind o s scale))
          (a (pairFirst r))
          (b (pairSecond r))
          (base (* o stride))
          (total (sumWeights! kind o scale a b 0.0))]
      (do (bytesSetFloat64 tbl base (int64ToFloat64 a))
          (bytesSetFloat64 tbl (+ base 1) (int64ToFloat64 (+ (- b a) 1)))
          (if (> total 0.0)
            (writeTaps! tbl base kind o scale a a b total)
            (bytesSetFloat64 tbl (+ base 2) 1.0))
          (buildRows! tbl stride kind s scale (+ o 1) d))))

fn ! weightTable! kind: String s: Int64 d: Int64 -> Bytes
  (let [(scale (scaleOf s d))
        (stride (tapStride kind scale))
        (tbl (bytesAlloc (* (* d stride) 8)))
        (_ (buildRows! tbl stride kind s scale 0 d))]
    tbl)

fn slotI tbl: Bytes i: Int64 -> Int64
  (optionOr (float64ToInt64 (bytesGetFloat64 tbl i)) 0)

fn ! tapSum! tbl: Bytes base: Int64 k: Int64 n: Int64 start: Int64 acc: Float64 get: (fn [Int64] -> Float64) -> Float64
  (if (>= k n) acc
    (tapSum! tbl base (+ k 1) n start (+ acc (* (bytesGetFloat64 tbl (+ (+ base 2) k)) (get (+ start k)))) get))

fn ! hPass! tbl: Bytes stride: Int64 src: Bytes sw: Int64 dw: Int64 sh: Int64 mid: Bytes j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (let [(c (mod j 4))
          (px (/ j 4))
          (ox (mod px dw))
          (y (/ px dw))
          (base (* ox stride))
          (start (slotI tbl base))
          (cnt (slotI tbl (+ base 1)))
          (rowBase (* (* y sw) 4))]
      (do (bytesSetFloat64 mid j (tapSum! tbl base 0 cnt start 0.0 (fn [(i Int64)] -> Float64 (int64ToFloat64 (bytesGet src (+ (+ rowBase (* i 4)) c))))))
          (hPass! tbl stride src sw dw sh mid (+ j 1) n))))

fn ! vPass! tbl: Bytes stride: Int64 mid: Bytes dw: Int64 out: Bytes j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (let [(c (mod j 4))
          (px (/ j 4))
          (ox (mod px dw))
          (oy (/ px dw))
          (base (* oy stride))
          (start (slotI tbl base))
          (cnt (slotI tbl (+ base 1)))]
      (do (bytesSet out j (im/clampByte (im/roundHalfUp (tapSum! tbl base 0 cnt start 0.0 (fn [(i Int64)] -> Float64 (bytesGetFloat64 mid (+ (* (+ (* i dw) ox) 4) c)))))))
          (vPass! tbl stride mid dw out (+ j 1) n))))

fn nearestImage img: im/Image w: Int64 h: Int64 -> im/Image
  (let [(n (* (* w h) 4))
        (out (bytesAlloc n))
        (sw img.width)
        (sh img.height)
        (_ (im/gatherBytes! out img.rgba (fn [(j Int64)] -> Int64
                                            (let [(px (/ j 4))
                                                  (sx (/ (* (+ (* 2 (mod px w)) 1) sw) (* 2 w)))
                                                  (sy (/ (* (+ (* 2 (/ px w)) 1) sh) (* 2 h)))]
                                              (+ (* (+ (* sy sw) sx) 4) (mod j 4)))) 0 n))]
    (im/Image :width w :height h :rgba out))

fn ! weightedImage! img: im/Image kind: String w: Int64 h: Int64 -> im/Image
  (let [(th (weightTable! kind img.width w))
        (tv (weightTable! kind img.height h))
        (hs (tapStride kind (scaleOf img.width w)))
        (vs (tapStride kind (scaleOf img.height h)))
        (mid (bytesAlloc (* (* (* w img.height) 4) 8)))
        (out (bytesAlloc (* (* w h) 4)))
        (_ (hPass! th hs img.rgba img.width w img.height mid 0 (* (* w img.height) 4)))
        (_ (vPass! tv vs mid w out 0 (* (* w h) 4)))]
    (im/Image :width w :height h :rgba out))

fn imageResize img: im/Image method: String w: Int64 h: Int64 -> (Result im/Image String)
  (cond
    ((not (and (im/dimOk? w h) (im/dimOk? w img.height))) (err (str "imageSize: bad target or intermediate " (stringFromInt64 w) "x" (stringFromInt64 h))))
    ((not (listContains? (resizeMethods) method)) (err (str "imageMethod: unknown method " method)))
    ((= method "nearest") (ok (nearestImage img w h)))
    (else (ok (weightedImage! img method w h))))
