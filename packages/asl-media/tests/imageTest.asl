(module asl-media/tests/imageTest
  :x [runTests]
  :i [(asl-media/image :a im)])

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

fn okImg r: (Result im/Image String) -> im/Image
  (match r
    ((ok i) i)
    ((err e) (do (assert false e) (im/Image :width 1 :height 1 :rgba (bytesAlloc 4)))))

fn errOf r: (Result im/Image String) -> String
  (match r
    ((ok _) "")
    ((err e) e))

fn grid3x2 -> im/Image
  (mk 3 2 (list 0 1 2 255 10 11 12 255 20 21 22 255 30 31 32 255 40 41 42 255 50 51 52 255))

fn testNew! -> Bool
  (do
    (assert (stringStartsWith? (errOf (im/imageNew 2 2 (bytesAlloc 15))) "imageSize") "a wrong byte count is imageSize")
    (assert (stringStartsWith? (errOf (im/imageNew 0 2 (bytesAlloc 0))) "imageSize") "a zero width is imageSize")
    (assert (stringStartsWith? (errOf (im/imageNew -1 2 (bytesAlloc 0))) "imageSize") "a negative width is imageSize")
    (assert (stringStartsWith? (errOf (im/imageNew 100000000 1 (bytesAlloc 4))) "imageSize") "an oversized width is imageSize without overflow")
    (assert (= (px (okImg (im/imageNew 1 1 (bytesAlloc 4)))) (list 0 0 0 0)) "a valid buffer is kept")
    (assert (= (px (okImg (im/imageSolid 2 1 9 8 7 6))) (list 9 8 7 6 9 8 7 6)) "solid fills every pixel")
    (assert (stringStartsWith? (errOf (im/imageSolid 1 1 256 0 0 0)) "imageChannel") "a channel above 255 is imageChannel")
    (assert (stringStartsWith? (errOf (im/imageSolid 1 1 0 0 -1 0)) "imageChannel") "a negative channel is imageChannel")
    true)

fn testCrop! -> Bool
  (do
    (assert (= (px (okImg (im/imageCrop (grid3x2) 1 0 2 2))) (list 10 11 12 255 20 21 22 255 40 41 42 255 50 51 52 255)) "crop 1,0 2x2 takes pixels 1 2 4 5")
    (assert (= (px (okImg (im/imageCrop (grid3x2) 0 1 1 1))) (list 30 31 32 255)) "crop of the bottom-left pixel")
    (assert (= (px (okImg (im/imageCrop (grid3x2) 0 0 3 2))) (px (grid3x2))) "a full crop is the image")
    (assert (stringStartsWith? (errOf (im/imageCrop (grid3x2) 2 0 2 1)) "imageBounds") "a crop past the right edge is imageBounds")
    (assert (stringStartsWith? (errOf (im/imageCrop (grid3x2) 0 1 1 2)) "imageBounds") "a crop past the bottom edge is imageBounds")
    (assert (stringStartsWith? (errOf (im/imageCrop (grid3x2) -1 0 1 1)) "imageBounds") "a negative origin is imageBounds")
    (assert (stringStartsWith? (errOf (im/imageCrop (grid3x2) 0 0 0 1)) "imageBounds") "an empty crop is imageBounds")
    true)

fn testPad! -> Bool
  (let [(one (mk 1 1 (list 1 2 3 4)))
        (p (okImg (im/imagePad one 1 2 0 1 9 8 7 6)))]
    (do
      (assert (and (= p.width 4) (= p.height 2)) "pad grows by left+right and top+bottom")
      (assert (= (px p) (list 9 8 7 6 9 8 7 6 9 8 7 6 9 8 7 6 9 8 7 6 1 2 3 4 9 8 7 6 9 8 7 6)) "the source sits at left,top in the fill colour")
      (assert (stringStartsWith? (errOf (im/imagePad one -1 0 0 0 0 0 0 0)) "imageBounds") "negative padding is imageBounds")
      (assert (stringStartsWith? (errOf (im/imagePad one 0 0 0 0 0 0 0 300)) "imageChannel") "a bad fill channel is imageChannel")
      true))

fn testFlip! -> Bool
  (let [(g (grid3x2))]
    (do
      (assert (= (px (im/imageFlipH g)) (list 20 21 22 255 10 11 12 255 0 1 2 255 50 51 52 255 40 41 42 255 30 31 32 255)) "flipH reverses each row")
      (assert (= (px (im/imageFlipV g)) (list 30 31 32 255 40 41 42 255 50 51 52 255 0 1 2 255 10 11 12 255 20 21 22 255)) "flipV swaps the rows")
      (assert (= (px (im/imageFlipH (im/imageFlipH g))) (px g)) "flipH twice is the identity")
      (assert (= (px (im/imageFlipV (im/imageFlipV g))) (px g)) "flipV twice is the identity")
      true))

fn maxRoundTrip a: Int64 c: Int64 worst: Int64 -> Int64
  (if (> c 255) worst
    (let [(i (mk 1 1 (list c c c a)))
          (back (im/imageUnpremultiply (im/imagePremultiply i)))
          (d (abs (- (optionOr (listHead (px back)) 0) c)))]
      (maxRoundTrip a (+ c 1) (max worst d))))

fn testPremul! -> Bool
  (do
    (assert (= (px (im/imagePremultiply (mk 1 1 (list 200 100 50 128)))) (list 100 50 25 128)) "premultiply rounds 100.89 50.69 25.6 down by the +127/255 rule")
    (assert (= (px (im/imageUnpremultiply (mk 1 1 (list 100 50 25 128)))) (list 199 100 50 128)) "unpremultiply rounds half up")
    (assert (= (px (im/imagePremultiply (mk 1 1 (list 7 8 9 0)))) (list 0 0 0 0)) "alpha 0 premultiplies to zero")
    (assert (= (px (im/imageUnpremultiply (mk 1 1 (list 0 0 0 0)))) (list 0 0 0 0)) "alpha 0 unpremultiplies to zero without dividing")
    (assert (= (px (im/imagePremultiply (mk 1 1 (list 7 8 9 255)))) (list 7 8 9 255)) "alpha 255 is unchanged")
    (assert (<= (maxRoundTrip 128 0 0) 1) "premultiply then unpremultiply is within one level at alpha 128")
    (assert (<= (maxRoundTrip 200 0 0) 1) "premultiply then unpremultiply is within one level at alpha 200")
    (assert (= (maxRoundTrip 255 0 0) 0) "alpha 255 round trips exactly")
    true)

fn testComposite! -> Bool
  (do
    (assert (= (px (im/imageComposite (mk 1 1 (list 0 0 255 255)) (mk 1 1 (list 255 0 0 255)) 0 0)) (list 255 0 0 255)) "an opaque source replaces the destination")
    (assert (= (px (im/imageComposite (mk 1 1 (list 0 0 255 255)) (mk 1 1 (list 255 0 0 128)) 0 0)) (list 128 0 127 255)) "half-opaque red over blue: 128 0 127 255, order matters")
    (assert (= (px (im/imageComposite (mk 1 1 (list 255 0 0 128)) (mk 1 1 (list 0 0 255 255)) 0 0)) (list 0 0 255 255)) "the reverse order is opaque blue")
    (assert (= (px (im/imageComposite (mk 1 1 (list 0 0 0 0)) (mk 1 1 (list 10 20 30 100)) 0 0)) (list 10 20 30 100)) "over a transparent destination keeps the source colour and alpha")
    (assert (= (px (im/imageComposite (mk 1 1 (list 0 200 0 128)) (mk 1 1 (list 200 0 0 128)) 0 0)) (list 134 66 0 192)) "two half-alpha pixels: 134 66 0 192 (round half up)")
    (assert (= (px (im/imageComposite (mk 1 1 (list 5 6 7 255)) (mk 1 1 (list 200 0 0 0)) 0 0)) (list 5 6 7 255)) "a transparent source leaves the destination")
    (let [(dst (mk 2 2 (list 1 1 1 255 2 2 2 255 3 3 3 255 4 4 4 255)))
          (s (mk 2 2 (list 9 9 9 255 8 8 8 255 7 7 7 255 6 6 6 255)))]
      (do
        (assert (= (px (im/imageComposite dst s 1 1)) (list 1 1 1 255 2 2 2 255 3 3 3 255 9 9 9 255)) "an offset source covers only the overlap")
        (assert (= (px (im/imageComposite dst s -1 -1)) (list 6 6 6 255 2 2 2 255 3 3 3 255 4 4 4 255)) "a negative offset clips the source")
        (assert (= (px (im/imageComposite dst s 5 5)) (px dst)) "a source fully outside changes nothing")
        (assert (= (px dst) (list 1 1 1 255 2 2 2 255 3 3 3 255 4 4 4 255)) "the destination is not edited")
        true)))

fn testStats! -> Bool
  (let [(i (mk 2 2 (list 0 5 9 255 0 6 9 128 255 7 9 0 10 8 9 255)))]
    (do
      (assert (= (px (im/imageGray (mk 1 1 (list 255 0 0 77)))) (list 76 76 76 255)) "BT.601 gray of pure red is 76 with alpha 255")
      (assert (= (px (im/imageGray (mk 1 1 (list 255 255 255 255)))) (list 255 255 255 255)) "white stays white")
      (assert (= (bytesList (im/imageAlpha i) 0) (list 255 128 0 255)) "alpha extraction")
      (assert (= (match (im/imageHistogram i 0) ((ok h) (list (optionOr (listGet h 0) -1) (optionOr (listGet h 10) -1) (optionOr (listGet h 255) -1) (listLength h) (sum h))) ((err _) (list))) (list 2 1 1 256 4)) "red histogram: two 0, one 10, one 255, 256 bins, total 4")
      (assert (= (match (im/imageMean i 0) ((ok m) m) ((err _) -1.0)) 66.25) "mean red is 265/4")
      (assert (= (match (im/imageMean i 3) ((ok m) m) ((err _) -1.0)) 159.5) "mean alpha is 638/4")
      (assert (stringStartsWith? (match (im/imageHistogram i 4) ((err e) e) ((ok _) "")) "imageChannel") "channel 4 is imageChannel")
      (assert (stringStartsWith? (match (im/imageMean i -1) ((err e) e) ((ok _) "")) "imageChannel") "channel -1 is imageChannel")
      true))

fn sum xs: (List Int64) -> Int64
  (fold (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 0 xs)

fn ! runTests -> Bool
  (do
    (testNew!)
    (testCrop!)
    (testPad!)
    (testFlip!)
    (testPremul!)
    (testComposite!)
    (testStats!)
    true)
