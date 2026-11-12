(module asl-media/tests/pngTest
  :x [runTests]
  :i [(asl-media/png :a png) (asl-zip/gzip :a gz)])

fn dir -> String
  "asl/packages/asl-media/tests/fixtures/"

fn readBytes! name: String -> Bytes
  (match (fileReadBytes (str (dir) name))
    ((ok b) b)
    ((err _) (bytesAlloc 0)))

fn readLine! name: String -> (List String)
  (match (fileReadString (str (dir) name))
    ((ok s) (stringSplit (stringTrim s) " "))
    ((err _) (list)))

fn decodeOk! data: Bytes -> Bytes
  (match (png/pngDecode! data 1000000)
    ((ok im) im.rgba)
    ((err e) (do (assert false (str "decode: " e)) (bytesAlloc 0))))

fn errOf data: Bytes limit: Int64 -> String
  (match (png/pngDecode! data limit)
    ((ok _) "")
    ((err e) e))

fn ! testFixtures! -> Bool
  (let [(names (list "rgba8f" "rgb8f" "pal2" "gray1t" "gray16" "ga8" "rgb16t"))]
    (do
      (map (fn [(n String)] -> Bool
             (let [(meta (readLine! (str n ".rgba.sha")))
                   (rgba (decodeOk! (readBytes! (str n ".png"))))]
               (do
                 (assert (= (bytesSha256 rgba) (optionOr (listGet meta 0) "")) (str n ": decoded RGBA8 equals the independently generated reference"))
                 true)))
           names)
      true))

fn ! testKnownPixels! -> Bool
  (let [(g (decodeOk! (readBytes! "gray16.png")))
        (p (decodeOk! (readBytes! "pal2.png")))
        (t (decodeOk! (readBytes! "gray1t.png")))]
    (do
      (assert (and (= (bytesGet g 4) 18) (= (bytesGet g 7) 255)) "gray16 pixel 1 keeps the high byte 0x12, opaque")
      (assert (and (= (bytesGet p 0) 255) (= (bytesGet p 3) 0)) "palette entry 0 is red with tRNS alpha 0")
      (assert (= (bytesGet p 7) 128) "palette entry 1 alpha 128")
      (assert (= (bytesGet t 3) 0) "gray1 white sample matches tRNS and is transparent")
      (assert (= (bytesGet t 7) 255) "gray1 black sample is opaque")
      true))

fn ! testMeta! -> Bool
  (match (png/pngDecode! (readBytes! "rgba8f.png") 1000)
    ((err e) (do (assert false e) false))
    ((ok im)
      (do
        (assert (and (= im.width 8) (= im.height 5) (= im.colorType 6) (= im.bitDepth 8)) "IHDR fields")
        (assert (= im.gamma 45455) "gAMA surfaced, not applied")
        (assert (= im.srgb 0) "sRGB intent surfaced")
        (assert (not im.hasTrns) "no tRNS")
        true)))

fn fillImage! b: Bytes i: Int64 s: Int64 -> Unit
  (if (>= i (bytesLength b)) ()
    (let [(n (mod (+ (* s 1103515245) 12345) 2147483648))]
      (do (bytesSet b i (mod (/ n 65536) (if (= (mod i 7) 0) 4 256)))
          (fillImage! b (+ i 1) n))))

fn sameBytes? a: Bytes b: Bytes i: Int64 -> Bool
  (cond
    ((!= (bytesLength a) (bytesLength b)) false)
    ((>= i (bytesLength a)) true)
    ((!= (bytesGet a i) (bytesGet b i)) false)
    (else (sameBytes? a b (+ i 1))))

fn ! roundTrip? w: Int64 h: Int64 seed: Int64 -> Bool
  (let [(src (bytesAlloc (* (* w h) 4)))
        (_ (fillImage! src 0 seed))]
    (match (png/pngEncode! w h src)
      ((err _) false)
      ((ok enc)
        (match (png/pngDecode! enc 100000000)
          ((err _) false)
          ((ok im) (and (= im.width w) (and (= im.height h) (sameBytes? src im.rgba 0))))))))

fn ! testRoundTrip! -> Bool
  (do
    (assert (roundTrip? 1 1 1) "1x1")
    (assert (roundTrip? 8 5 2) "8x5")
    (assert (roundTrip? 33 17 3) "33x17")
    (assert (roundTrip? 64 64 4) "64x64")
    (assert (roundTrip? 100 3 5) "100x3")
    true)

fn ! testDeterministic! -> Bool
  (let [(src (bytesAlloc 2048))
        (_ (fillImage! src 0 9))]
    (match (png/pngEncode! 16 32 src)
      ((err _) (do (assert false "encode") false))
      ((ok a)
        (match (png/pngEncode! 16 32 src)
          ((ok b) (do (assert (= (bytesSha256 a) (bytesSha256 b)) "encode is deterministic") true))
          ((err _) false)))))

fn flip! b: Bytes i: Int64 -> Bytes
  (let [(c (bytesAlloc (bytesLength b)))
        (_ (copyAll! b c 0))]
    (do (bytesSet c i (mod (+ (bytesGet c i) 1) 256)) c))

fn copyAll! a: Bytes b: Bytes i: Int64 -> Unit
  (if (>= i (bytesLength a)) () (do (bytesSet b i (bytesGet a i)) (copyAll! a b (+ i 1))))

fn head! b: Bytes n: Int64 -> Bytes
  (let [(c (bytesAlloc n)) (_ (copyN! b c 0 n))] c)

fn copyN! a: Bytes b: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) () (do (bytesSet b i (bytesGet a i)) (copyN! a b (+ i 1) n)))

fn ! testErrors! -> Bool
  (let [(good (readBytes! "rgba8f.png"))
        (n (bytesLength good))]
    (do
      (assert (stringStartsWith? (errOf (head! good 40) 1000) "pngTruncated") "truncated file is a labelled err")
      (assert (stringStartsWith? (errOf (head! good 5) 1000) "pngSignature") "short file is not a PNG")
      (assert (stringStartsWith? (errOf (flip! good 20) 1000) "pngCrc") "IHDR corruption fails the chunk CRC")
      (assert (stringStartsWith? (errOf (flip! good (- n 20)) 1000) "pngCrc") "IDAT corruption fails the chunk CRC")
      (assert (stringStartsWith? (errOf good 39) "pngLimit") "pixel budget is enforced")
      (assert (= (errOf good 40) "") "pixel budget exactly met")
      (assert (stringStartsWith? (errOf (readBytes! "adlerBad.png") 1000) "pngZlib") "valid chunk CRCs but a wrong zlib adler32 is refused")
      (assert (stringStartsWith? (errOf (bytesAlloc 0) 10) "pngSignature") "empty input")
      true))

fn put32! b: Bytes off: Int64 v: Int64 -> Unit
  (do (bytesSet b off (mod (/ v 16777216) 256)) (bytesSet b (+ off 1) (mod (/ v 65536) 256))
      (bytesSet b (+ off 2) (mod (/ v 256) 256)) (bytesSet b (+ off 3) (mod v 256)))

fn ! chunk! typ: String body: Bytes -> Bytes
  (let [(n (bytesLength body))
        (tb (stringToBytes typ))
        (crcIn (bytesAlloc (+ n 4)))
        (out (bytesAlloc (+ n 12)))
        (_ (cpyAt! tb crcIn 0 4))
        (_ (cpyAt! body crcIn 4 n))
        (_ (put32! out 0 n))
        (_ (cpyAt! crcIn out 4 (+ n 4)))
        (_ (put32! out (+ n 8) (gz/crc32 crcIn)))]
    out)

fn cpy! a: Bytes b: Bytes i: Int64 -> Unit
  (if (>= i 4) () (do (bytesSet b i (bytesGet a i)) (cpy! a b (+ i 1))))

fn cpyAt! a: Bytes b: Bytes at: Int64 n: Int64 -> Unit
  (if (<= n 0) () (do (bytesSet b at (bytesGet a (- (bytesLength a) n)))  (cpyAt! a b (+ at 1) (- n 1))))

fn cat! parts: (List Bytes) -> Bytes
  (let [(total (fold (fn [(acc Int64) (p Bytes)] -> Int64 (+ acc (bytesLength p))) 0 parts))
        (out (bytesAlloc total))
        (_ (fold (fn [(at Int64) (p Bytes)] -> Int64 (do (cpyAt! p out at (bytesLength p)) (+ at (bytesLength p)))) 0 parts))]
    out)

fn ihdr! w: Int64 h: Int64 depth: Int64 ct: Int64 -> Bytes
  (let [(b (bytesAlloc 13))
        (_ (put32! b 0 w))
        (_ (put32! b 4 h))
        (_ (bytesSet b 8 depth))
        (_ (bytesSet b 9 ct))]
    (chunk! "IHDR" b))

fn sig! -> Bytes
  (readBytes! "rgba8f.png")

fn ! testHostile! -> Bool
  (let [(g (readBytes! "rgba8f.png"))
        (sg (cat! (list (head! g 8))))
        (iend (chunk! "IEND" (bytesAlloc 0)))
        (zeros (match (png/zlibWrap! (bytesAlloc 2000000)) ((ok z) z) ((err _) (bytesAlloc 0))))
        (bomb (cat! (list sg (ihdr! 2 2 8 6) (chunk! "IDAT" zeros) iend)))
        (emptyIhdr (cat! (list sg (chunk! "IHDR" (bytesAlloc 0)) iend)))
        (notFirst (cat! (list sg (chunk! "IEND" (bytesAlloc 0)) (ihdr! 1 1 8 6))))
        (badPlte (cat! (list sg (ihdr! 1 1 8 3) (chunk! "PLTE" (bytesAlloc 4)) iend)))
        (bigPlte (cat! (list sg (ihdr! 1 1 8 3) (chunk! "PLTE" (bytesAlloc 771)) iend)))]
    (do
      (assert (> (bytesLength zeros) 0) "bomb stream built")
      (assert (< (bytesLength zeros) 5000) "bomb stream is tiny")
      (assert (stringStartsWith? (errOf bomb 1000) "pngZlib") "an IDAT inflating past h*(stride+1) is refused at the cap")
      (assert (stringContains? (errOf emptyIhdr 1000) "IHDR must come first") "length-0 IHDR is a structure err")
      (assert (stringContains? (errOf notFirst 1000) "first chunk is not IHDR") "a first chunk that is not IHDR is a structure err")
      (assert (stringContains? (errOf badPlte 1000) "PLTE length") "PLTE length 4 is refused")
      (assert (stringContains? (errOf bigPlte 1000) "PLTE length") "PLTE over 768 bytes is refused")
      true))

fn ! testAdler! -> Bool
  (do
    (assert (= (png/adler32 (stringToBytes "Wikipedia")) 300286872) "adler32 of Wikipedia is 0x11E60398")
    (assert (= (png/adler32 (bytesAlloc 0)) 1) "adler32 of empty is 1")
    true)

fn ! testLarge! -> Bool
  (let [(src (bytesAlloc 4194304))
        (_ (fillImage! src 0 11))
        (t0 (monotonicNs))
        (r (png/pngEncode! 1024 1024 src))]
    (match r
      ((err e) (do (assert false e) false))
      ((ok enc)
        (let [(t1 (monotonicNs))
              (d (png/pngDecode! enc 1048576))
              (t2 (monotonicNs))]
          (match d
            ((err e) (do (assert false e) false))
            ((ok im)
              (do
                (assert (sameBytes? src im.rgba 0) "1024x1024 round trip")
                (assert (< (/ (- t2 t1) 1000000) 5000) "1024x1024 decode stays under 5 s")
                (print (str "(:png1024 :encodeMs " (stringFromInt64 (/ (- t1 t0) 1000000)) " :decodeMs " (stringFromInt64 (/ (- t2 t1) 1000000)) ")"))
                true)))))))

fn ! runTests -> Bool
  (do
    (testAdler!)
    (testFixtures!)
    (testKnownPixels!)
    (testMeta!)
    (testErrors!)
    (testHostile!)
    (testRoundTrip!)
    (testDeterministic!)
    (testLarge!)
    true)
