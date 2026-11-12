(module asl-media/png
  :x [PngImage pngDecode! pngEncode! adler32 zlibWrap!]
  :i [(asl-zip/gzip :a gz) (asl-zip/inflate :a inf) (asl-zip/deflate :a df)])

; (:m :ref U-MEDIA :do "rgba is always RGBA8 (16-bit samples keep the high byte); gamma is gAMA*100000 or -1, srgb is the intent or -1, iccp and trns only flag the chunks, none is applied to the pixels")
schema PngImage
  (:f width Int64)
  (:f height Int64)
  (:f bitDepth Int64)
  (:f colorType Int64)
  (:f gamma Int64)
  (:f srgb Int64)
  (:f hasIccp Bool)
  (:f hasTrns Bool)
  (:f rgba Bytes)

fn be32 bs: Bytes off: Int64 -> Int64
  (+ (* (bytesGet bs off) 16777216) (+ (* (bytesGet bs (+ off 1)) 65536) (+ (* (bytesGet bs (+ off 2)) 256) (bytesGet bs (+ off 3)))))

fn put32be! bs: Bytes off: Int64 v: Int64 -> Unit
  (do
    (bytesSet bs off (mod (/ v 16777216) 256))
    (bytesSet bs (+ off 1) (mod (/ v 65536) 256))
    (bytesSet bs (+ off 2) (mod (/ v 256) 256))
    (bytesSet bs (+ off 3) (mod v 256)))

fn absInt x: Int64 -> Int64
  (if (< x 0) (- 0 x) x)

fn copyRange! src: Bytes from: Int64 dst: Bytes to: Int64 n: Int64 -> Unit
  (if (<= n 0) ()
    (do (bytesSet dst to (bytesGet src from))
        (copyRange! src (+ from 1) dst (+ to 1) (- n 1))))

fn adlerLoop bs: Bytes i: Int64 n: Int64 a: Int64 b: Int64 -> Int64
  (if (>= i n)
    (+ (* b 65536) a)
    (let [(a2 (mod (+ a (bytesGet bs i)) 65521))]
      (adlerLoop bs (+ i 1) n a2 (mod (+ b a2) 65521))))

fn adler32 bs: Bytes -> Int64
  (adlerLoop bs 0 (bytesLength bs) 1 0)

fn zlibWrap! raw: Bytes -> (Result Bytes String)
  (match (df/deflate! raw)
    ((err e) (err (str "pngEncode: " e)))
    ((ok z)
      (let [(n (bytesLength z))
            (out (bytesAlloc (+ n 6)))]
        (do
          (bytesSet out 0 120)
          (bytesSet out 1 156)
          (copyRange! z 0 out 2 n)
          (put32be! out (+ n 2) (adler32 raw))
          (ok out)))))


schema Chunks
  (:f ihdr Int64)
  (:f plte Int64)
  (:f plteLen Int64)
  (:f trns Int64)
  (:f trnsLen Int64)
  (:f gamma Int64)
  (:f srgb Int64)
  (:f iccp Bool)
  (:f idat (List (Pair Int64 Int64)))
  (:f end Bool)

fn typeIs? bs: Bytes off: Int64 a: Int64 b: Int64 c: Int64 d: Int64 -> Bool
  (and (= (bytesGet bs off) a) (and (= (bytesGet bs (+ off 1)) b) (and (= (bytesGet bs (+ off 2)) c) (= (bytesGet bs (+ off 3)) d))))

fn sliceOf bs: Bytes off: Int64 n: Int64 -> Bytes
  (let [(o (bytesAlloc n))]
    (do (copyRange! bs off o 0 n) o))

fn ! walkChunks! bs: Bytes pos: Int64 ch: Chunks -> (Result Chunks String)
  (cond
    (ch.end (ok ch))
    ((> (+ pos 12) (bytesLength bs)) (err "pngTruncated: chunk header or end past the data"))
    (else
      (let [(len (be32 bs pos))
            (data (+ pos 8))]
        (cond
          ((> len (- (bytesLength bs) (+ pos 12))) (err "pngTruncated: chunk length runs past the data"))
          ((!= (gz/crc32 (sliceOf bs (+ pos 4) (+ len 4))) (be32 bs (+ data len)))
           (err "pngCrc: chunk checksum mismatch"))
          (else
            (let [(next (+ pos (+ len 12)))
                  (ch2 (cond
                         ((typeIs? bs (+ pos 4) 73 72 68 82) (with ch :ihdr data))
                         ((typeIs? bs (+ pos 4) 80 76 84 69) (with (with ch :plte data) :plteLen len))
                         ((typeIs? bs (+ pos 4) 116 82 78 83) (with (with ch :trns data) :trnsLen len))
                         ((typeIs? bs (+ pos 4) 103 65 77 65) (if (= len 4) (with ch :gamma (be32 bs data)) ch))
                         ((typeIs? bs (+ pos 4) 115 82 71 66) (if (= len 1) (with ch :srgb (bytesGet bs data)) ch))
                         ((typeIs? bs (+ pos 4) 105 67 67 80) (with ch :iccp true))
                         ((typeIs? bs (+ pos 4) 73 68 65 84) (with ch :idat (listAppend ch.idat (list (pair data len)))))
                         ((typeIs? bs (+ pos 4) 73 69 78 68) (with ch :end true))
                         (else ch)))]
              (walkChunks! bs next ch2)))))))

fn totalLen xs: (List (Pair Int64 Int64)) -> Int64
  (fold (fn [(acc Int64) (p (Pair Int64 Int64))] -> Int64 (+ acc (pairSecond p))) 0 xs)

fn joinIdat! bs: Bytes xs: (List (Pair Int64 Int64)) out: Bytes at: Int64 -> Unit
  (match (listHead xs)
    ((none) ())
    ((some p)
      (do (copyRange! bs (pairFirst p) out at (pairSecond p))
          (joinIdat! bs (optionOr (listTail xs) (list)) out (+ at (pairSecond p))))))

fn channelsOf ct: Int64 -> Int64
  (cond ((= ct 0) 1) ((= ct 2) 3) ((= ct 3) 1) ((= ct 4) 2) ((= ct 6) 4) (else 0))

fn depthOk? ct: Int64 d: Int64 -> Bool
  (cond
    ((= ct 0) (or (= d 1) (or (= d 2) (or (= d 4) (or (= d 8) (= d 16))))))
    ((= ct 3) (or (= d 1) (or (= d 2) (or (= d 4) (= d 8)))))
    ((or (= ct 2) (or (= ct 4) (= ct 6))) (or (= d 8) (= d 16)))
    (else false))

fn paeth a: Int64 b: Int64 c: Int64 -> Int64
  (let [(p (- (+ a b) c))
        (pa (absInt (- p a)))
        (pb (absInt (- p b)))
        (pc (absInt (- p c)))]
    (if (and (<= pa pb) (<= pa pc)) a (if (<= pb pc) b c)))

fn predictor ft: Int64 a: Int64 b: Int64 c: Int64 -> Int64
  (cond ((= ft 0) 0) ((= ft 1) a) ((= ft 2) b) ((= ft 3) (/ (+ a b) 2)) (else (paeth a b c)))

fn ! unfilterRow! raw: Bytes rin: Int64 un: Bytes rout: Int64 stride: Int64 bpp: Int64 hasPrev: Bool ft: Int64 i: Int64 -> Unit
  (if (>= i stride) ()
    (let [(a (if (>= i bpp) (bytesGet un (- (+ rout i) bpp)) 0))
          (b (if hasPrev (bytesGet un (- (+ rout i) stride)) 0))
          (c (if (and hasPrev (>= i bpp)) (bytesGet un (- (- (+ rout i) stride) bpp)) 0))]
      (do
        (bytesSet un (+ rout i) (mod (+ (bytesGet raw (+ rin (+ 1 i))) (predictor ft a b c)) 256))
        (unfilterRow! raw rin un rout stride bpp hasPrev ft (+ i 1)))))

fn ! unfilter! raw: Bytes un: Bytes stride: Int64 bpp: Int64 h: Int64 y: Int64 -> (Result Unit String)
  (if (>= y h) (ok ())
    (let [(rin (* y (+ stride 1)))
          (ft (bytesGet raw rin))]
      (if (> ft 4)
        (err (str "pngFilter: unknown filter type " (stringFromInt64 ft) " on row " (stringFromInt64 y)))
        (do
          (unfilterRow! raw rin un (* y stride) stride bpp (> y 0) ft 0)
          (unfilter! raw un stride bpp h (+ y 1))))))

; (:m :ref U-MEDIA :do "full sample value of channel k of pixel x on the row at rowOff, 1 to 16 bits")
fn sampleAt un: Bytes rowOff: Int64 x: Int64 k: Int64 ch: Int64 depth: Int64 -> Int64
  (cond
    ((= depth 8) (bytesGet un (+ rowOff (+ (* x ch) k))))
    ((= depth 16) (+ (* (bytesGet un (+ rowOff (* 2 (+ (* x ch) k)))) 256) (bytesGet un (+ rowOff (+ 1 (* 2 (+ (* x ch) k)))))))
    (else
      (let [(bitPos (* (+ (* x ch) k) depth))
            (byte (bytesGet un (+ rowOff (/ bitPos 8))))
            (shift (- (- 8 depth) (mod bitPos 8)))]
        (mod (/ byte (pow2 shift)) (pow2 depth)))))

fn pow2 n: Int64 -> Int64
  (if (<= n 0) 1 (* 2 (pow2 (- n 1))))

fn to8 v: Int64 depth: Int64 -> Int64
  (cond ((= depth 16) (/ v 256)) ((= depth 8) v) ((= depth 4) (* v 17)) ((= depth 2) (* v 85)) (else (* v 255)))

fn trnsWord src: Bytes off: Int64 -> Int64
  (+ (* (bytesGet src off) 256) (bytesGet src (+ off 1)))

fn ! pixelOut! bs: Bytes un: Bytes row: Int64 x: Int64 ct: Int64 depth: Int64 pl: Int64 plN: Int64 tr: Int64 trN: Int64 out: Bytes o: Int64 -> Bool
  (cond
    ((= ct 6)
      (do (bytesSet out o (to8 (sampleAt un row x 0 4 depth) depth))
          (bytesSet out (+ o 1) (to8 (sampleAt un row x 1 4 depth) depth))
          (bytesSet out (+ o 2) (to8 (sampleAt un row x 2 4 depth) depth))
          (bytesSet out (+ o 3) (to8 (sampleAt un row x 3 4 depth) depth))
          true))
    ((= ct 2)
      (let [(r (sampleAt un row x 0 3 depth)) (g (sampleAt un row x 1 3 depth)) (b (sampleAt un row x 2 3 depth))
            (clear (and (= trN 6) (and (= r (trnsWord bs tr)) (and (= g (trnsWord bs (+ tr 2))) (= b (trnsWord bs (+ tr 4))))))) ]
        (do (bytesSet out o (to8 r depth)) (bytesSet out (+ o 1) (to8 g depth)) (bytesSet out (+ o 2) (to8 b depth))
            (bytesSet out (+ o 3) (if clear 0 255)) true)))
    ((= ct 4)
      (let [(g (to8 (sampleAt un row x 0 2 depth) depth))]
        (do (bytesSet out o g) (bytesSet out (+ o 1) g) (bytesSet out (+ o 2) g)
            (bytesSet out (+ o 3) (to8 (sampleAt un row x 1 2 depth) depth)) true)))
    ((= ct 0)
      (let [(raw (sampleAt un row x 0 1 depth))
            (g (to8 raw depth))
            (clear (and (= trN 2) (= raw (trnsWord bs tr))))]
        (do (bytesSet out o g) (bytesSet out (+ o 1) g) (bytesSet out (+ o 2) g)
            (bytesSet out (+ o 3) (if clear 0 255)) true)))
    (else
      (let [(i (sampleAt un row x 0 1 depth))]
        (if (>= i plN)
          false
          (do (bytesSet out o (bytesGet bs (+ pl (* 3 i))))
              (bytesSet out (+ o 1) (bytesGet bs (+ pl (+ 1 (* 3 i)))))
              (bytesSet out (+ o 2) (bytesGet bs (+ pl (+ 2 (* 3 i)))))
              (bytesSet out (+ o 3) (if (< i trN) (bytesGet bs (+ tr i)) 255))
              true)))))

fn ! convertRows! bs: Bytes un: Bytes w: Int64 h: Int64 stride: Int64 ct: Int64 depth: Int64 pl: Int64 plN: Int64 tr: Int64 trN: Int64 out: Bytes i: Int64 -> (Result Unit String)
  (if (>= i (* w h)) (ok ())
    (let [(y (/ i w))
          (x (mod i w))]
      (if (pixelOut! bs un (* y stride) x ct depth pl plN tr trN out (* i 4))
        (convertRows! bs un w h stride ct depth pl plN tr trN out (+ i 1))
        (err "pngPalette: index past the palette"))))

fn emptyChunks -> Chunks
  (Chunks :ihdr -1 :plte -1 :plteLen 0 :trns -1 :trnsLen 0 :gamma -1 :srgb -1 :iccp false :idat (list) :end false)

fn sigOk? bs: Bytes -> Bool
  (and (>= (bytesLength bs) 8)
       (and (typeIs? bs 0 137 80 78 71) (typeIs? bs 4 13 10 26 10)))

fn ! pngDecode! data: Bytes maxPixels: Int64 -> (Result PngImage String)
  (cond
    ((not (sigOk? data)) (err "pngSignature: not a PNG"))
    (else
      (match (walkChunks! data 8 (emptyChunks))
        ((err e) (err e))
        ((ok ch) (decodeChunks! data ch maxPixels)))))

fn ! decodeChunks! data: Bytes ch: Chunks maxPixels: Int64 -> (Result PngImage String)
  (if (< ch.ihdr 0)
    (err "pngStructure: no IHDR")
    (let [(w (be32 data ch.ihdr))
          (h (be32 data (+ ch.ihdr 4)))
          (depth (bytesGet data (+ ch.ihdr 8)))
          (ct (bytesGet data (+ ch.ihdr 9)))
          (inter (bytesGet data (+ ch.ihdr 12)))]
      (cond
        ((or (<= w 0) (<= h 0)) (err "pngStructure: zero dimension"))
        ((> w (/ maxPixels h)) (err (str "pngLimit: more than " (stringFromInt64 maxPixels) " pixels")))
        ((not (depthOk? ct depth)) (err "pngStructure: bad bit depth for the colour type"))
        ((!= inter 0) (err "pngUnsupported: interlaced (Adam7) images"))
        ((and (= ct 3) (< ch.plte 0)) (err "pngStructure: palette image without PLTE"))
        ((listEmpty? ch.idat) (err "pngStructure: no IDAT"))
        (else (inflateAndConvert! data ch w h depth ct)))))

fn ! inflateAndConvert! data: Bytes ch: Chunks w: Int64 h: Int64 depth: Int64 ct: Int64 -> (Result PngImage String)
  (let [(zn (totalLen ch.idat))
        (z (bytesAlloc zn))
        (_ (joinIdat! data ch.idat z 0))
        (bitsPerPixel (* depth (channelsOf ct)))
        (stride (/ (+ (* w bitsPerPixel) 7) 8))
        (bpp (max 1 (/ bitsPerPixel 8)))]
    (cond
      ((< zn 6) (err "pngZlib: stream shorter than header and checksum"))
      ((or (!= (mod (bytesGet z 0) 16) 8) (!= (mod (+ (* (bytesGet z 0) 256) (bytesGet z 1)) 31) 0)) (err "pngZlib: bad header"))
      ((= (mod (/ (bytesGet z 1) 32) 2) 1) (err "pngZlib: preset dictionary"))
      (else
        (match (inf/inflateInternal! z 2)
          ((err e) (err (str "pngZlib: " e)))
          ((ok r)
            (cond
              ((> (+ r.nextOffset 4) zn) (err "pngZlib: missing adler32"))
              ((!= (adler32 r.bytes) (be32 z r.nextOffset)) (err "pngZlib: adler32 mismatch"))
              ((!= (bytesLength r.bytes) (* h (+ stride 1))) (err "pngStructure: pixel data length does not match the header"))
              (else (finishDecode! data ch w h depth ct stride bpp r.bytes))))))))

fn ! finishDecode! data: Bytes ch: Chunks w: Int64 h: Int64 depth: Int64 ct: Int64 stride: Int64 bpp: Int64 raw: Bytes -> (Result PngImage String)
  (let [(un (bytesAlloc (* h stride)))
        (out (bytesAlloc (* (* w h) 4)))]
    (match (unfilter! raw un stride bpp h 0)
      ((err e) (err e))
      ((ok _)
        (match (convertRows! data un w h stride ct depth ch.plte (/ ch.plteLen 3) ch.trns ch.trnsLen out 0)
          ((err e) (err e))
          ((ok _) (ok (PngImage :width w :height h :bitDepth depth :colorType ct :gamma ch.gamma :srgb ch.srgb :hasIccp ch.iccp :hasTrns (>= ch.trns 0) :rgba out)))))))


fn rowCost! f: Bytes off: Int64 n: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n) acc
    (let [(v (bytesGet f (+ off i)))]
      (rowCost! f off n (+ i 1) (+ acc (if (> v 127) (- 256 v) v)))))

fn ! filterRow! px: Bytes rowIn: Int64 stride: Int64 hasPrev: Bool ft: Int64 out: Bytes rowOut: Int64 i: Int64 -> Unit
  (if (>= i stride) ()
    (let [(a (if (>= i 4) (bytesGet px (- (+ rowIn i) 4)) 0))
          (b (if hasPrev (bytesGet px (- (+ rowIn i) stride)) 0))
          (c (if (and hasPrev (>= i 4)) (bytesGet px (- (- (+ rowIn i) stride) 4)) 0))]
      (do
        (bytesSet out (+ rowOut i) (mod (+ (- (bytesGet px (+ rowIn i)) (predictor ft a b c)) 256) 256))
        (filterRow! px rowIn stride hasPrev ft out rowOut (+ i 1)))))

; (:m :ref U-MEDIA :do "per row the filter with the smallest sum of absolute signed residuals wins, ties to the lower type, so output is deterministic")
fn ! bestFilter! px: Bytes rowIn: Int64 stride: Int64 hasPrev: Bool scratch: Bytes ft: Int64 bestFt: Int64 bestCost: Int64 -> Int64
  (if (> ft 4) bestFt
    (let [(_ (filterRow! px rowIn stride hasPrev ft scratch 0 0))
          (cost (rowCost! scratch 0 stride 0 0))]
      (if (< cost bestCost)
        (bestFilter! px rowIn stride hasPrev scratch (+ ft 1) ft cost)
        (bestFilter! px rowIn stride hasPrev scratch (+ ft 1) bestFt bestCost))))

fn ! filterAll! px: Bytes stride: Int64 h: Int64 y: Int64 scratch: Bytes raw: Bytes -> Unit
  (if (>= y h) ()
    (let [(best (bestFilter! px (* y stride) stride (> y 0) scratch 0 0 9223372036854775807))
          (ro (* y (+ stride 1)))]
      (do
        (bytesSet raw ro best)
        (filterRow! px (* y stride) stride (> y 0) best raw (+ ro 1) 0)
        (filterAll! px stride h (+ y 1) scratch raw))))

fn chunkOf! typ: (List Int64) body: Bytes -> Bytes
  (let [(n (bytesLength body))
        (crcIn (bytesAlloc (+ n 4)))
        (out (bytesAlloc (+ n 12)))]
    (do
      (put32be! out 0 n)
      (putType! typ crcIn)
      (copyRange! body 0 crcIn 4 n)
      (copyRange! crcIn 0 out 4 (+ n 4))
      (put32be! out (+ n 8) (gz/crc32 crcIn))
      out))

fn putType! typ: (List Int64) b: Bytes -> Unit
  (do
    (bytesSet b 0 (optionOr (listGet typ 0) 0))
    (bytesSet b 1 (optionOr (listGet typ 1) 0))
    (bytesSet b 2 (optionOr (listGet typ 2) 0))
    (bytesSet b 3 (optionOr (listGet typ 3) 0)))

fn ! pngEncode! w: Int64 h: Int64 rgba: Bytes -> (Result Bytes String)
  (cond
    ((or (<= w 0) (<= h 0)) (err "pngEncode: zero dimension"))
    ((> w (/ 536870911 h)) (err "pngEncode: image too large"))
    ((!= (bytesLength rgba) (* (* w h) 4)) (err "pngEncode: rgba length is not width*height*4"))
    (else
      (let [(stride (* w 4))
            (raw (bytesAlloc (* h (+ stride 1))))
            (_ (filterAll! rgba stride h 0 (bytesAlloc stride) raw))]
        (match (zlibWrap! raw)
          ((err e) (err e))
          ((ok z)
            (let [(ihdr (bytesAlloc 13))
                  (_ (put32be! ihdr 0 w))
                  (_ (put32be! ihdr 4 h))
                  (_ (bytesSet ihdr 8 8))
                  (_ (bytesSet ihdr 9 6))
                  (a (chunkOf! (list 73 72 68 82) ihdr))
                  (b (chunkOf! (list 73 68 65 84) z))
                  (c (chunkOf! (list 73 69 78 68) (bytesAlloc 0)))
                  (na (bytesLength a))
                  (nb (bytesLength b))
                  (out (bytesAlloc (+ 8 (+ na (+ nb (bytesLength c))))))]
              (do
                (copyRange! (pngSignature) 0 out 0 8)
                (copyRange! a 0 out 8 na)
                (copyRange! b 0 out (+ 8 na) nb)
                (copyRange! c 0 out (+ 8 (+ na nb)) (bytesLength c))
                (ok out))))))))

fn pngSignature -> Bytes
  (let [(s (bytesAlloc 8))]
    (do (bytesSet s 0 137) (bytesSet s 1 80) (bytesSet s 2 78) (bytesSet s 3 71)
        (bytesSet s 4 13) (bytesSet s 5 10) (bytesSet s 6 26) (bytesSet s 7 10)
        s))
