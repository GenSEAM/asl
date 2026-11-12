(module asl-media/tests/imageHashTest
  :x [runTests]
  :i [(asl-media/image :a im) (asl-media/imageResize :a rs) (asl-media/imageHash :a ih)])

fn ! setAll! b: Bytes xs: (List Int64) i: Int64 -> Unit
  (match (listHead xs)
    ((none) ())
    ((some v) (do (bytesSet b i v) (setAll! b (optionOr (listTail xs) (list)) (+ i 1)))))

fn ! gray w: Int64 h: Int64 vs: (List Int64) -> im/Image
  (let [(xs (listFlatMap (fn [(v Int64)] -> (List Int64) (list v v v 255)) vs))
        (b (bytesAlloc (listLength xs)))
        (_ (setAll! b xs 0))]
    (im/Image :width w :height h :rgba b))

fn okImg r: (Result im/Image String) -> im/Image
  (match r
    ((ok i) i)
    ((err e) (do (assert false e) (im/Image :width 1 :height 1 :rgba (bytesAlloc 4)))))

fn zigzag -> (List Int64)
  (listFlatMap (fn [(r Int64)] -> (List Int64) (if (= (mod r 2) 0) (list 9 8 7 6 5 4 3 2 1) (list 1 2 3 4 5 6 7 8 9))) (range 0 8))

fn rowZero -> (List Int64)
  (listAppend (list 5 3 3 9 9 1 0 0 7) (map (fn [(i Int64)] -> Int64 4) (range 0 63)))

fn pat x: Int64 y: Int64 -> Int64
  (mod (+ (+ (* x 7) (* y 13)) (* (mod (* x y) 11) 5)) 256)

fn pat32 -> (List Int64)
  (listFlatMap (fn [(y Int64)] -> (List Int64) (map (fn [(x Int64)] -> Int64 (pat x y)) (range 0 32))) (range 0 32))

fn pat64 -> (List Int64)
  (listFlatMap (fn [(y Int64)] -> (List Int64) (map (fn [(x Int64)] -> Int64 (pat (/ x 2) (/ y 2))) (range 0 64))) (range 0 64))

fn testD! -> Bool
  (do
    (assert (= (ih/hashHex (ih/imageDHash (gray 9 8 (zigzag)))) "ff00ff00ff00ff00") "dHash of alternating descending and ascending rows is ff00ff00ff00ff00")
    (assert (= (ih/hashHex (ih/imageDHash (gray 9 8 (rowZero)))) "8c00000000000000") "row 0 5 3 3 9 9 1 0 0 7 gives bits 10001100 and equal rows give 0")
    (assert (= (ih/imageDHash (gray 9 8 (listFlatMap (fn [(r Int64)] -> (List Int64) (list 1 1 1 1 1 1 1 1 1)) (range 0 8)))) 0) "a flat image hashes to 0")
    (let [(base (gray 9 8 (zigzag)))
          (up (okImg (rs/imageResize base "nearest" 18 16)))]
      (do
        (assert (= (ih/imageDHash up) (ih/imageDHash base)) "a 2x nearest upscale keeps the dHash")
        (assert (= (ih/imageDHash (im/imageFlipH base)) (ih/imageDHash (gray 9 8 (listFlatMap (fn [(r Int64)] -> (List Int64) (if (= (mod r 2) 0) (list 1 2 3 4 5 6 7 8 9) (list 9 8 7 6 5 4 3 2 1))) (range 0 8))))) "mirroring flips the comparison direction")
        true)))

fn testHamming! -> Bool
  (do
    (assert (= (ih/hammingDistance 0 -1) 64) "0 and all ones differ in 64 bits")
    (assert (= (ih/hammingDistance 255 15) 4) "ff and 0f differ in 4 bits")
    (assert (= (ih/hammingDistance 123456789 123456789) 0) "equal hashes are distance 0")
    (assert (= (ih/hashHex -1) "ffffffffffffffff") "hashHex of -1 is 16 f digits")
    (assert (= (ih/hashHex 255) "00000000000000ff") "hashHex pads to 16 digits")
    true)

fn testP! -> Bool
  (let [(a (gray 32 32 (pat32)))
        (b (gray 64 64 (pat64)))]
    (do
      (assert (= (ih/hashHex (ih/imagePHash a)) "c815c39f3770a54d") "pHash of the pattern image is c815c39f3770a54d (python DCT oracle)")
      (assert (= (ih/imagePHash b) (ih/imagePHash a)) "a 2x blocky upscale area-resizes back to the same pHash")
      (assert (> (ih/hammingDistance (ih/imagePHash a) (ih/imagePHash (im/imageFlipV a))) 0) "a vertical flip changes the pHash")
      (assert (= (ih/imagePHash (gray 32 32 (map (fn [(i Int64)] -> Int64 0) (range 0 1024)))) 0) "a black image hashes to 0")
      true))

fn ! runTests -> Bool
  (do
    (testD!)
    (testHamming!)
    (testP!)
    true)
