(module asl-media/image
  :x [Image imageNew imageSolid imageCrop imagePad imageFlipH imageFlipV imagePremultiply imageUnpremultiply imageComposite imageAlpha imageHistogram imageMean imageGray maxImagePixels dimOk? fillBytes! gatherBytes! roundHalfUp clampByte]
  :i [])

; (:m :ref workspace-20261031-imageOps :do "an Image is RGBA8 straight alpha, row-major, top row first, rgba length exactly width*height*4; every operation returns a new Image and never edits its input; any out-of-range request is an err labelled image<Kind>, never a clamp")
schema Image
  (:f width Int64)
  (:f height Int64)
  (:f rgba Bytes)

fn maxImagePixels -> Int64
  67108864

fn dimOk? w: Int64 h: Int64 -> Bool
  (and (> w 0) (and (> h 0) (and (<= w (maxImagePixels)) (and (<= h (maxImagePixels)) (<= (* w h) (maxImagePixels))))))

fn clampByte v: Int64 -> Int64
  (max 0 (min 255 v))

fn roundHalfUp f: Float64 -> Int64
  (optionOr (float64ToInt64 (floor (+ f 0.5))) 0)

fn imageNew w: Int64 h: Int64 rgba: Bytes -> (Result Image String)
  (cond
    ((not (dimOk? w h)) (err (str "imageSize: bad dimensions " (stringFromInt64 w) "x" (stringFromInt64 h))))
    ((!= (bytesLength rgba) (* (* w h) 4)) (err (str "imageSize: rgba has " (stringFromInt64 (bytesLength rgba)) " bytes, want " (stringFromInt64 (* (* w h) 4)))))
    (else (ok (Image :width w :height h :rgba rgba))))

fn ! fillBytes! out: Bytes f: (fn [Int64] -> Int64) j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (do (bytesSet out j (f j))
        (fillBytes! out f (+ j 1) n)))

fn ! gatherBytes! out: Bytes src: Bytes f: (fn [Int64] -> Int64) j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (do (bytesSet out j (bytesGet src (f j)))
        (gatherBytes! out src f (+ j 1) n)))

fn chanOk? v: Int64 -> Bool
  (and (>= v 0) (<= v 255))

fn imageSolid w: Int64 h: Int64 r: Int64 g: Int64 b: Int64 a: Int64 -> (Result Image String)
  (cond
    ((not (dimOk? w h)) (err "imageSize: bad dimensions"))
    ((not (and (chanOk? r) (and (chanOk? g) (and (chanOk? b) (chanOk? a))))) (err "imageChannel: a channel is outside 0..255"))
    (else
      (let [(n (* (* w h) 4))
            (out (bytesAlloc n))
            (_ (fillBytes! out (fn [(j Int64)] -> Int64 (cond ((= (mod j 4) 0) r) ((= (mod j 4) 1) g) ((= (mod j 4) 2) b) (else a))) 0 n))]
        (ok (Image :width w :height h :rgba out)))))

fn imageCrop img: Image x: Int64 y: Int64 w: Int64 h: Int64 -> (Result Image String)
  (cond
    ((not (dimOk? w h)) (err "imageBounds: empty or oversized crop"))
    ((or (< x 0) (< y 0)) (err "imageBounds: negative crop origin"))
    ((or (> x (- img.width w)) (> y (- img.height h))) (err (str "imageBounds: crop " (stringFromInt64 x) "," (stringFromInt64 y) " " (stringFromInt64 w) "x" (stringFromInt64 h) " leaves the " (stringFromInt64 img.width) "x" (stringFromInt64 img.height) " image")))
    (else
      (let [(n (* (* w h) 4))
            (out (bytesAlloc n))
            (rowBytes (* w 4))
            (srcRow (* img.width 4))
            (_ (gatherBytes! out img.rgba (fn [(j Int64)] -> Int64 (+ (+ (* (+ y (/ j rowBytes)) srcRow) (* x 4)) (mod j rowBytes))) 0 n))]
        (ok (Image :width w :height h :rgba out)))))

fn ! blitRows! dst: Bytes dw: Int64 src: Bytes sw: Int64 dx: Int64 dy: Int64 j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (let [(rowBytes (* sw 4))
          (sy (/ j rowBytes))
          (r (mod j rowBytes))]
      (do (bytesSet dst (+ (* (+ (* (+ dy sy) dw) dx) 4) r) (bytesGet src j))
          (blitRows! dst dw src sw dx dy (+ j 1) n))))

fn imagePad img: Image top: Int64 right: Int64 bottom: Int64 left: Int64 r: Int64 g: Int64 b: Int64 a: Int64 -> (Result Image String)
  (if (or (< top 0) (or (< right 0) (or (< bottom 0) (or (< left 0) (or (> top (maxImagePixels)) (or (> right (maxImagePixels)) (or (> bottom (maxImagePixels)) (> left (maxImagePixels)))))))))
    (err "imageBounds: padding is negative or above the pixel cap")
    (let [(w (+ (+ img.width left) right))
          (h (+ (+ img.height top) bottom))]
      (match (imageSolid w h r g b a)
        ((err e) (err e))
        ((ok canvas)
          (do (blitRows! canvas.rgba w img.rgba img.width left top 0 (bytesLength img.rgba))
              (ok canvas))))))

fn imageFlipH img: Image -> Image
  (let [(n (bytesLength img.rgba))
        (out (bytesAlloc n))
        (rowBytes (* img.width 4))
        (_ (gatherBytes! out img.rgba (fn [(j Int64)] -> Int64 (+ (* (/ j rowBytes) rowBytes) (+ (* (- (- img.width 1) (/ (mod j rowBytes) 4)) 4) (mod j 4)))) 0 n))]
    (Image :width img.width :height img.height :rgba out))

fn imageFlipV img: Image -> Image
  (let [(n (bytesLength img.rgba))
        (out (bytesAlloc n))
        (rowBytes (* img.width 4))
        (_ (gatherBytes! out img.rgba (fn [(j Int64)] -> Int64 (+ (* (- (- img.height 1) (/ j rowBytes)) rowBytes) (mod j rowBytes))) 0 n))]
    (Image :width img.width :height img.height :rgba out))

fn imagePremultiply img: Image -> Image
  (let [(n (bytesLength img.rgba))
        (src img.rgba)
        (out (bytesAlloc n))
        (_ (fillBytes! out (fn [(j Int64)] -> Int64
                             (let [(c (mod j 4))]
                               (if (= c 3) (bytesGet src j)
                                 (/ (+ (* (bytesGet src j) (bytesGet src (+ (- j c) 3))) 127) 255)))) 0 n))]
    (Image :width img.width :height img.height :rgba out))

fn imageUnpremultiply img: Image -> Image
  (let [(n (bytesLength img.rgba))
        (src img.rgba)
        (out (bytesAlloc n))
        (_ (fillBytes! out (fn [(j Int64)] -> Int64
                             (let [(c (mod j 4))
                                   (a (bytesGet src (+ (- j c) 3)))]
                               (cond
                                 ((= c 3) a)
                                 ((= a 0) 0)
                                 (else (clampByte (/ (+ (* (bytesGet src j) 255) (/ a 2)) a)))))) 0 n))]
    (Image :width img.width :height img.height :rgba out))

fn blendByte dv: Int64 sv: Int64 sa: Int64 da: Int64 c: Int64 -> Int64
  (let [(num (+ (* sa 255) (* da (- 255 sa))))]
    (cond
      ((= c 3) (/ (+ (* 2 num) 255) 510))
      ((= num 0) 0)
      (else (clampByte (/ (+ (* 2 (+ (* (* sv sa) 255) (* (* dv da) (- 255 sa)))) num) (* 2 num))))))

fn clampOffset o: Int64 -> Int64
  (max (- 0 (* 2 (maxImagePixels))) (min (* 2 (maxImagePixels)) o))

fn imageComposite dst: Image src: Image ox0: Int64 oy0: Int64 -> Image
  (let [(ox (clampOffset ox0))
        (oy (clampOffset oy0))
        (n (bytesLength dst.rgba))
        (out (bytesAlloc n))
        (w dst.width)
        (_ (fillBytes! out (fn [(j Int64)] -> Int64
                             (let [(px (/ j 4))
                                   (c (mod j 4))
                                   (sx (- (mod px w) ox))
                                   (sy (- (/ px w) oy))]
                               (if (or (< sx 0) (or (< sy 0) (or (>= sx src.width) (>= sy src.height))))
                                 (bytesGet dst.rgba j)
                                 (let [(si (+ (* (+ (* sy src.width) sx) 4) c))]
                                   (blendByte (bytesGet dst.rgba j) (bytesGet src.rgba si) (bytesGet src.rgba (+ (- si c) 3)) (bytesGet dst.rgba (+ (- j c) 3)) c))))) 0 n))]
    (Image :width w :height dst.height :rgba out))

fn imageAlpha img: Image -> Bytes
  (let [(n (* img.width img.height))
        (out (bytesAlloc n))
        (_ (fillBytes! out (fn [(j Int64)] -> Int64 (bytesGet img.rgba (+ (* j 4) 3))) 0 n))]
    out)

fn imageGray img: Image -> Image
  (let [(n (bytesLength img.rgba))
        (src img.rgba)
        (out (bytesAlloc n))
        (_ (fillBytes! out (fn [(j Int64)] -> Int64
                             (let [(b (- j (mod j 4)))]
                               (if (= (mod j 4) 3) 255
                                 (/ (+ (+ (* 299 (bytesGet src b)) (+ (* 587 (bytesGet src (+ b 1))) (* 114 (bytesGet src (+ b 2))))) 500) 1000)))) 0 n))]
    (Image :width img.width :height img.height :rgba out))

fn ! countLoop! src: Bytes counts: Bytes ch: Int64 j: Int64 n: Int64 -> Unit
  (if (>= j n) ()
    (let [(v (bytesGet src j))]
      (do (bytesSetFloat64 counts v (+ (bytesGetFloat64 counts v) 1.0))
          (countLoop! src counts ch (+ j 4) n))))

fn countList counts: Bytes i: Int64 -> (List Int64)
  (if (>= i 256) (list)
    (cons (optionOr (float64ToInt64 (bytesGetFloat64 counts i)) 0) (countList counts (+ i 1))))

fn imageHistogram img: Image ch: Int64 -> (Result (List Int64) String)
  (if (or (< ch 0) (> ch 3))
    (err "imageChannel: channel must be 0..3")
    (let [(counts (bytesAlloc 2048))
          (_ (countLoop! img.rgba counts ch ch (bytesLength img.rgba)))]
      (ok (countList counts 0))))

fn ! sumChannel! src: Bytes j: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= j n) acc (sumChannel! src (+ j 4) n (+ acc (bytesGet src j))))

fn imageMean img: Image ch: Int64 -> (Result Float64 String)
  (if (or (< ch 0) (> ch 3))
    (err "imageChannel: channel must be 0..3")
    (ok (/ (int64ToFloat64 (sumChannel! img.rgba ch (bytesLength img.rgba) 0)) (int64ToFloat64 (* img.width img.height)))))
