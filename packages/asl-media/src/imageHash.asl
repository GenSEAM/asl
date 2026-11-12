(module asl-media/imageHash
  :x [imageDHash imagePHash hashHex hammingDistance]
  :i [(asl-media/image :a im) (asl-media/imageResize :a rs)])

; (:m :ref workspace-20261031-imageOps :do "hashes are 64 bits in an Int64, first bit most significant: dHash is BT.601 gray area-resized to 9x8 with bit (row,col) = left pixel greater than right, row-major; pHash is gray area-resized to 32x32, DCT-II of the 8x8 lowest frequencies row-major by (v,u), bit = coefficient greater than the median of the 63 AC coefficients (the DC coefficient is compared to it but is not part of it); a resize err is returned as an err; alpha is ignored; hashes are this module's own definition, not bit-compatible with other libraries")
fn grayAt img: im/Image x: Int64 y: Int64 -> Int64
  (bytesGet img.rgba (* (+ (* y img.width) x) 4))

fn ! dBits! img: im/Image i: Int64 acc: Int64 -> Int64
  (if (>= i 64) acc
    (let [(r (/ i 8))
          (c (mod i 8))
          (bit (if (> (grayAt img c r) (grayAt img (+ c 1) r)) 1 0))]
      (dBits! img (+ i 1) (| (<< acc 1) bit))))

fn imageDHash img: im/Image -> (Result Int64 String)
  (match (rs/imageResize (im/imageGray img) "area" 9 8)
    ((ok small) (ok (dBits! small 0 0)))
    ((err e) (err e)))

fn cosAt x: Int64 u: Int64 -> Float64
  (cos (/ (* (* (+ (* 2.0 (int64ToFloat64 x)) 1.0) (int64ToFloat64 u)) 3.141592653589793) 64.0))

fn ! rowSum! img: im/Image y: Int64 u: Int64 x: Int64 acc: Float64 -> Float64
  (if (>= x 32) acc
    (rowSum! img y u (+ x 1) (+ acc (* (int64ToFloat64 (grayAt img x y)) (cosAt x u)))))

fn ! rowDct! img: im/Image mid: Bytes y: Int64 u: Int64 -> Unit
  (if (>= y 32) ()
    (if (>= u 8)
      (rowDct! img mid (+ y 1) 0)
      (do (bytesSetFloat64 mid (+ (* y 8) u) (rowSum! img y u 0 0.0))
          (rowDct! img mid y (+ u 1)))))

fn ! colSum! mid: Bytes u: Int64 v: Int64 y: Int64 acc: Float64 -> Float64
  (if (>= y 32) acc
    (colSum! mid u v (+ y 1) (+ acc (* (bytesGetFloat64 mid (+ (* y 8) u)) (cosAt y v)))))

fn coefs mid: Bytes i: Int64 -> (List Float64)
  (if (>= i 64) (list)
    (cons (colSum! mid (mod i 8) (/ i 8) 0 0.0) (coefs mid (+ i 1))))

fn medianOf xs: (List Float64) -> Float64
  (optionOr (listGet (listSort xs) 31) 0.0)

fn bitsOf cs: (List Float64) med: Float64 acc: Int64 -> Int64
  (match (listHead cs)
    ((none) acc)
    ((some c) (bitsOf (optionOr (listTail cs) (list)) med (| (<< acc 1) (if (> c med) 1 0)))))

fn ! imagePHash img: im/Image -> (Result Int64 String)
  (match (rs/imageResize (im/imageGray img) "area" 32 32)
    ((err e) (err e))
    ((ok small)
      (let [(mid (bytesAlloc (* (* 32 8) 8)))
            (_ (rowDct! small mid 0 0))
            (cs (coefs mid 0))]
        (ok (bitsOf cs (medianOf (listDrop cs 1)) 0)))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "?")

fn hashHex h: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String (hexDigit (& (>> h (* 4 (- 15 i))) 15))) (range 0 16)) "")

fn hammingDistance a: Int64 b: Int64 -> Int64
  (popcount64 (^ a b))
