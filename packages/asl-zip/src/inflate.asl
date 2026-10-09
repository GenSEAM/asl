(module asl-zip/inflate
  :x [inflate! inflateInternal! inflateAppend!]
  :i [])

schema InflateResult {
  bytes: Bytes
  nextOffset: Int64
}

schema InflateState {
  stOut: Bytes
  stPos: Int64
  stNext: Int64
}

schema BlockEnd {
  eOut: Bytes
  eOp: Int64
  ePos: Int64
  eBuf: Int64
  eCnt: Int64
}

schema Bits {
  bPos: Int64
  bBuf: Int64
  bCnt: Int64
}

fn defaultLimit -> Int64
  4294967296

fn lowBits x: Int64 k: Int64 -> Int64
  (- x (<< (>> x k) k))

fn errText p: Int64 msg: String -> String
  (str "error at offset " (stringFromInt64 p) ": " msg)

fn consumedPos pos: Int64 cnt: Int64 -> Int64
  (- pos (/ cnt 8))

fn overrun? pos: Int64 cnt: Int64 inLen: Int64 -> Bool
  (> (- (* pos 8) cnt) (* inLen 8))

fn failText pos: Int64 cnt: Int64 inLen: Int64 msg: String -> String
  (if (overrun? pos cnt inLen)
    (errText inLen "truncated input")
    (errText (consumedPos pos cnt) msg))

fn tGet t: Bytes i: Int64 -> Int64
  (+ (bytesGet t i) (<< (bytesGet t (+ i 1)) 8))

fn tSet! t: Bytes i: Int64 v: Int64 -> Unit
  (do
    (bytesSet t i (lowBits v 8))
    (bytesSet t (+ i 1) (>> v 8)))

fn countLens! t: Bytes lens: Bytes off: Int64 n: Int64 i: Int64 -> Unit
  (if (>= i n) ()
    (let [(l (bytesGet lens (+ off i)))]
      (do
        (if (> l 0) (tSet! t (+ 2048 (* 2 l)) (+ (tGet t (+ 2048 (* 2 l))) 1)) ())
        (countLens! t lens off n (+ i 1)))))

fn oversubscribed? t: Bytes len: Int64 left: Int64 -> Bool
  (if (> len 15) false
    (let [(left1 (- (* left 2) (tGet t (+ 2048 (* 2 len)))))]
      (if (< left1 0) true (oversubscribed? t (+ len 1) left1))))

fn offsets! t: Bytes offs: Bytes len: Int64 acc: Int64 -> Unit
  (if (> len 15) ()
    (do
      (tSet! offs (* 2 len) acc)
      (offsets! t offs (+ len 1) (+ acc (tGet t (+ 2048 (* 2 len)))))))

fn sortSyms! t: Bytes offs: Bytes lens: Bytes off: Int64 n: Int64 sym: Int64 -> Unit
  (if (>= sym n) ()
    (let [(l (bytesGet lens (+ off sym)))]
      (do
        (if (> l 0)
          (let [(k (tGet offs (* 2 l)))]
            (do
              (tSet! t (+ 2080 (* 2 k)) sym)
              (tSet! offs (* 2 l) (+ k 1))))
          ())
        (sortSyms! t offs lens off n (+ sym 1)))))

fn reverseBits code: Int64 len: Int64 acc: Int64 -> Int64
  (if (= len 0) acc
    (reverseBits (>> code 1) (- len 1) (+ (* acc 2) (lowBits code 1))))

fn fillPrimary! t: Bytes idx: Int64 step: Int64 entry: Int64 -> Unit
  (if (>= idx 1024) ()
    (do
      (tSet! t (* 2 idx) entry)
      (fillPrimary! t (+ idx step) step entry)))

fn primaryLen! t: Bytes len: Int64 code: Int64 k: Int64 left: Int64 -> Int64
  (if (= left 0) code
    (let [(sym (tGet t (+ 2080 (* 2 k))))]
      (do
        (fillPrimary! t (reverseBits code len 0) (<< 1 len) (+ (* sym 16) len))
        (primaryLen! t len (+ code 1) (+ k 1) (- left 1)))))

fn primary! t: Bytes len: Int64 code: Int64 k: Int64 -> Unit
  (if (> len 10) ()
    (let [(c (tGet t (+ 2048 (* 2 len))))
          (next (primaryLen! t len code k c))]
      (primary! t (+ len 1) (* next 2) (+ k c))))

fn buildTable! lens: Bytes off: Int64 n: Int64 -> (Result Bytes String)
  (let [(t (bytesAlloc 2720))
        (offs (bytesAlloc 32))]
    (do
      (countLens! t lens off n 0)
      (if (oversubscribed? t 1 1)
        (err "bad code lengths")
        (do
          (offsets! t offs 1 0)
          (sortSyms! t offs lens off n 0)
          (primary! t 1 0 0)
          (ok t)))))

fn slowDecode t: Bytes base: Int64 buf: Int64 len: Int64 code: Int64 first: Int64 index: Int64 -> Int64
  (if (> len 15) -1
    (let [(code1 (+ code (lowBits (>> buf (- len 1)) 1)))
          (count (tGet t (+ base (+ 2048 (* 2 len)))))]
      (if (< code1 (+ first count))
        (+ (* (tGet t (+ base (+ 2080 (* 2 (+ index (- code1 first)))))) 16) len)
        (slowDecode t base buf (+ len 1) (* code1 2) (* (+ first count) 2) (+ index count)))))

fn decodeEntry t: Bytes base: Int64 buf: Int64 -> Int64
  (let [(e (tGet t (+ base (* 2 (lowBits buf 10)))))]
    (if (= e 0) (slowDecode t base buf 1 0 0 0) e))

fn lenExtra idx: Int64 -> Int64
  (cond ((< idx 8) 0) ((= idx 28) 0) (else (- (>> idx 2) 1)))

fn lenBase idx: Int64 -> Int64
  (cond ((< idx 8) (+ idx 3)) ((= idx 28) 258) (else (+ (<< (+ 4 (lowBits idx 2)) (lenExtra idx)) 3)))

fn distExtra dsym: Int64 -> Int64
  (if (< dsym 4) 0 (- (>> dsym 1) 1))

fn distBase dsym: Int64 -> Int64
  (if (< dsym 4) (+ dsym 1) (+ (<< (+ 2 (lowBits dsym 1)) (distExtra dsym)) 1))

fn copyBytes! dst: Bytes src: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet dst i (bytesGet src i))
      (copyBytes! dst src (+ i 1) n)))

fn growOut! out: Bytes op: Int64 need: Int64 limit: Int64 -> Bytes
  (let [(cap (min limit (max need (+ (* (bytesLength out) 2) 1024))))
        (fresh (bytesAlloc cap))]
    (do
      (copyBytes! fresh out 0 op)
      fresh))

fn copyMatch! out: Bytes dst: Int64 src: Int64 end: Int64 -> Int64
  (cond
    ((<= (+ dst 4) end)
     (do
       (bytesSet out dst (bytesGet out src))
       (bytesSet out (+ dst 1) (bytesGet out (+ src 1)))
       (bytesSet out (+ dst 2) (bytesGet out (+ src 2)))
       (bytesSet out (+ dst 3) (bytesGet out (+ src 3)))
       (copyMatch! out (+ dst 4) (+ src 4) end)))
    ((>= dst end) end)
    (else
     (do
       (bytesSet out dst (bytesGet out src))
       (copyMatch! out (+ dst 1) (+ src 1) end))))

fn limitText limit: Int64 -> String
  (str "output exceeds the limit of " (stringFromInt64 limit) " bytes")

fn ! joinTables lt: Bytes dt: Bytes -> Bytes
  (let [(t (bytesAlloc 5440))]
    (do
      (copyStored! t lt 0 0 2720)
      (copyStored! t dt 2720 0 5440)
      t))

fn huff! inp: Bytes pos: Int64 buf: Int64 cnt: Int64 out: Bytes op: Int64 memBase: Int64 limit: Int64 tabs: Bytes -> (Result BlockEnd String)
  (if (< cnt 55)
    (let [(inLen (bytesLength inp))]
      (cond
        ((< pos inLen) (huff! inp (+ pos 1) (+ buf (<< (bytesGet inp pos) cnt)) (+ cnt 8) out op memBase limit tabs))
        ((< pos (+ inLen 8)) (huff! inp (+ pos 1) buf (+ cnt 8) out op memBase limit tabs))
        (else (err (errText inLen "truncated input")))))
    (let [(e0 (tGet tabs (* 2 (lowBits buf 10))))
          (e (if (= e0 0) (slowDecode tabs 0 buf 1 0 0 0) e0))
          (l (lowBits e 4))
          (sym (>> e 4))
          (buf1 (>> buf l))
          (cnt1 (- cnt l))]
      (cond
        ((< e 0) (err (failText pos cnt (bytesLength inp) "bad code lengths")))
        ((< sym 256)
         (cond
           ((< op (bytesLength out))
            (do
              (bytesSet out op sym)
              (huff! inp pos buf1 cnt1 out (+ op 1) memBase limit tabs)))
           ((>= op limit) (err (limitText limit)))
           (else (huff! inp pos buf cnt (growOut! out op (+ op 1) limit) op memBase limit tabs))))
        ((= sym 256)
         (if (overrun? pos cnt1 (bytesLength inp))
           (err (errText (bytesLength inp) "truncated input"))
           (ok (BlockEnd :eOut out :eOp op :ePos pos :eBuf buf1 :eCnt cnt1))))
        ((> sym 285) (err (failText pos cnt1 (bytesLength inp) "bad code lengths")))
        (else
         (let [(idx (- sym 257))
               (eb (lenExtra idx))
               (matchLen (+ (lenBase idx) (lowBits buf1 eb)))
               (buf2 (>> buf1 eb))
               (cnt2 (- cnt1 eb))
               (de0 (tGet tabs (+ 2720 (* 2 (lowBits buf2 10)))))
               (de (if (= de0 0) (slowDecode tabs 2720 buf2 1 0 0 0) de0))
               (dl (lowBits de 4))
               (dsym (>> de 4))
               (buf3 (>> buf2 dl))
               (cnt3 (- cnt2 dl))
               (deb (distExtra dsym))
               (d (+ (distBase dsym) (lowBits buf3 deb)))
               (buf4 (>> buf3 deb))
               (cnt4 (- cnt3 deb))
               (end (+ op matchLen))]
           (cond
             ((or (< de 0) (> dsym 29)) (err (failText pos cnt2 (bytesLength inp) "bad code lengths")))
             ((> d (- op memBase)) (err (failText pos cnt4 (bytesLength inp) "distance beyond the window")))
             ((<= end (bytesLength out)) (huff! inp pos buf4 cnt4 out (copyMatch! out op (- op d) end) memBase limit tabs))
             ((> end limit) (err (limitText limit)))
             (else (huff! inp pos buf cnt (growOut! out op end limit) op memBase limit tabs))))))))

fn refill inp: Bytes inLen: Int64 pos: Int64 buf: Int64 cnt: Int64 -> (Result Bits String)
  (if (< cnt 55)
    (cond
      ((< pos inLen) (refill inp inLen (+ pos 1) (+ buf (<< (bytesGet inp pos) cnt)) (+ cnt 8)))
      ((< pos (+ inLen 8)) (refill inp inLen (+ pos 1) buf (+ cnt 8)))
      (else (err (errText inLen "truncated input"))))
    (ok (Bits :bPos pos :bBuf buf :bCnt cnt)))

fn clOrder i: Int64 -> Int64
  (cond
    ((= i 0) 16) ((= i 1) 17) ((= i 2) 18) ((= i 3) 0)
    ((= i 4) 8) ((= i 5) 7) ((= i 6) 9) ((= i 7) 6)
    ((= i 8) 10) ((= i 9) 5) ((= i 10) 11) ((= i 11) 4)
    ((= i 12) 12) ((= i 13) 3) ((= i 14) 13) ((= i 15) 2)
    ((= i 16) 14) ((= i 17) 1) (else 15))

fn readCl! inp: Bytes inLen: Int64 pos: Int64 buf: Int64 cnt: Int64 cl: Bytes i: Int64 numCl: Int64 -> (Result Bits String)
  (cond
    ((>= i numCl) (ok (Bits :bPos pos :bBuf buf :bCnt cnt)))
    ((< cnt 16)
     (cond
       ((< pos inLen) (readCl! inp inLen (+ pos 1) (+ buf (<< (bytesGet inp pos) cnt)) (+ cnt 8) cl i numCl))
       ((< pos (+ inLen 8)) (readCl! inp inLen (+ pos 1) buf (+ cnt 8) cl i numCl))
       (else (err (errText inLen "truncated input")))))
    (else
     (do
       (bytesSet cl (clOrder i) (lowBits buf 3))
       (readCl! inp inLen pos (>> buf 3) (- cnt 3) cl (+ i 1) numCl))))

fn fillLens! lens: Bytes i: Int64 n: Int64 v: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet lens i v)
      (fillLens! lens (+ i 1) n v)))

fn readLens! inp: Bytes inLen: Int64 pos: Int64 buf: Int64 cnt: Int64 ct: Bytes lens: Bytes idx: Int64 total: Int64 last: Int64 -> (Result Bits String)
  (cond
    ((>= idx total) (ok (Bits :bPos pos :bBuf buf :bCnt cnt)))
    ((< cnt 16)
     (cond
       ((< pos inLen) (readLens! inp inLen (+ pos 1) (+ buf (<< (bytesGet inp pos) cnt)) (+ cnt 8) ct lens idx total last))
       ((< pos (+ inLen 8)) (readLens! inp inLen (+ pos 1) buf (+ cnt 8) ct lens idx total last))
       (else (err (errText inLen "truncated input")))))
    (else
     (let [(e (decodeEntry ct 0 buf))]
       (if (< e 0)
         (err (failText pos cnt inLen "bad code lengths"))
         (let [(l (lowBits e 4))
               (sym (>> e 4))
               (buf1 (>> buf l))
               (cnt1 (- cnt l))]
           (cond
             ((< sym 16)
              (do
                (bytesSet lens idx sym)
                (readLens! inp inLen pos buf1 cnt1 ct lens (+ idx 1) total sym)))
             (else
              (let [(eb (cond ((= sym 16) 2) ((= sym 17) 3) (else 7)))
                    (rep (+ (cond ((= sym 16) 3) ((= sym 17) 3) (else 11)) (lowBits buf1 eb)))
                    (v (if (= sym 16) last 0))
                    (buf2 (>> buf1 eb))
                    (cnt2 (- cnt1 eb))]
                (cond
                  ((and (= sym 16) (= idx 0)) (err (failText pos cnt1 inLen "bad code lengths")))
                  ((> (+ idx rep) total) (err (failText pos cnt2 inLen "bad code lengths")))
                  (else
                   (do
                     (fillLens! lens idx (+ idx rep) v)
                     (readLens! inp inLen pos buf2 cnt2 ct lens (+ idx rep) total v))))))))))))

fn dynamicTables! inp: Bytes inLen: Int64 b: Bits out: Bytes op: Int64 memBase: Int64 limit: Int64 -> (Result BlockEnd String)
  (let [(buf b.bBuf)
        (hlit (lowBits buf 5))
        (hdist (lowBits (>> buf 5) 5))
        (numCl (+ (lowBits (>> buf 10) 4) 4))
        (pos b.bPos)
        (cnt (- b.bCnt 14))]
    (if (or (> hlit 29) (> hdist 29))
      (err (failText pos cnt inLen "bad code lengths"))
      (let [(cl (bytesAlloc 19))]
        (mt (readCl! inp inLen pos (>> buf 14) cnt cl 0 numCl)
          ((err e) (err e))
          ((ok b1)
           (mt (buildTable! cl 0 19)
             ((err e) (err (failText b1.bPos b1.bCnt inLen e)))
             ((ok ct)
              (let [(numLit (+ hlit 257))
                    (total (+ numLit (+ hdist 1)))
                    (lens (bytesAlloc total))]
                (mt (readLens! inp inLen b1.bPos b1.bBuf b1.bCnt ct lens 0 total 0)
                  ((err e) (err e))
                  ((ok b2)
                   (if (= (bytesGet lens 256) 0)
                     (err (failText b2.bPos b2.bCnt inLen "bad code lengths"))
                     (mt (buildTable! lens 0 numLit)
                       ((err e) (err (failText b2.bPos b2.bCnt inLen e)))
                       ((ok lt)
                        (mt (buildTable! lens numLit (+ hdist 1))
                          ((err e) (err (failText b2.bPos b2.bCnt inLen e)))
                          ((ok dt) (huff! inp b2.bPos b2.bBuf b2.bCnt out op memBase limit (joinTables lt dt)))))))))))))))))

fn copyStored! dst: Bytes src: Bytes i: Int64 from: Int64 end: Int64 -> Unit
  (if (>= i end) ()
    (do
      (bytesSet dst i (bytesGet src from))
      (copyStored! dst src (+ i 1) (+ from 1) end)))

fn storedBlock! inp: Bytes inLen: Int64 pos: Int64 buf: Int64 cnt: Int64 out: Bytes op: Int64 limit: Int64 -> (Result BlockEnd String)
  (let [(skip (lowBits cnt 3))
        (aligned (consumedPos pos (- cnt skip)))]
    (cond
      ((> (+ aligned 4) inLen) (err (errText aligned "truncated input")))
      ((!= (+ (tGet inp aligned) (tGet inp (+ aligned 2))) 65535) (err (errText aligned "bad stored block length")))
      (else
       (let [(len (tGet inp aligned))
             (dataPos (+ aligned 4))
             (end (+ op len))]
         (cond
           ((> (+ dataPos len) inLen) (err (errText dataPos "truncated input")))
           ((> end limit) (err (limitText limit)))
           (else
            (let [(dst (if (<= end (bytesLength out)) out (growOut! out op end limit)))]
              (do
                (copyStored! dst inp op dataPos end)
                (ok (BlockEnd :eOut dst :eOp end :ePos (+ dataPos len) :eBuf 0 :eCnt 0))))))))))

fn fixedLens! lens: Bytes i: Int64 -> Unit
  (if (>= i 320) ()
    (do
      (bytesSet lens i (cond ((<= i 143) 8) ((<= i 255) 9) ((<= i 279) 7) ((<= i 287) 8) (else 5)))
      (fixedLens! lens (+ i 1))))

fn blocks! inp: Bytes inLen: Int64 pos: Int64 buf: Int64 cnt: Int64 out: Bytes op: Int64 memBase: Int64 limit: Int64 ftabs: Bytes -> (Result InflateState String)
  (mt (refill inp inLen pos buf cnt)
    ((err e) (err e))
    ((ok b)
     (let [(hb b.bBuf)
           (final (lowBits hb 1))
           (btype (lowBits (>> hb 1) 2))
           (p1 b.bPos)
           (buf1 (>> hb 3))
           (cnt1 (- b.bCnt 3))
           (res (cond
                  ((= btype 0) (storedBlock! inp inLen p1 buf1 cnt1 out op limit))
                  ((= btype 1) (huff! inp p1 buf1 cnt1 out op memBase limit ftabs))
                  ((= btype 2) (dynamicTables! inp inLen (Bits :bPos p1 :bBuf buf1 :bCnt cnt1) out op memBase limit))
                  (else (err (failText p1 cnt1 inLen "bad block type")))))]
       (mt res
         ((err e) (err e))
         ((ok be)
          (if (= final 1)
            (ok (InflateState :stOut be.eOut :stPos be.eOp :stNext (consumedPos be.ePos be.eCnt)))
            (blocks! inp inLen be.ePos be.eBuf be.eCnt be.eOut be.eOp memBase limit ftabs)))))))

fn inflateAppend! data: Bytes start: Int64 out: Bytes op: Int64 limit: Int64 -> (Result InflateState String)
  (let [(inLen (bytesLength data))]
    (if (< inLen start)
      (err (errText inLen "truncated input"))
      (let [(fixed (bytesAlloc 320))]
        (do
          (fixedLens! fixed 0)
          (mt (buildTable! fixed 0 288)
            ((err e) (err e))
            ((ok flt)
             (mt (buildTable! fixed 288 32)
               ((err e) (err e))
               ((ok fdt) (blocks! data inLen start 0 0 out op op limit (joinTables flt fdt))))))))))

fn exact! out: Bytes n: Int64 -> Bytes
  (if (= (bytesLength out) n) out
    (let [(fresh (bytesAlloc n))]
      (do
        (copyBytes! fresh out 0 n)
        fresh)))

fn inflateInternal! data: Bytes startOffset: Int64 -> (Result InflateResult String)
  (let [(inLen (bytesLength data))
        (initCap (min (defaultLimit) (+ 1024 (* 4 (max 0 (- inLen startOffset))))))]
    (mt (inflateAppend! data startOffset (bytesAlloc initCap) 0 (defaultLimit))
      ((err e) (err e))
      ((ok st) (ok (InflateResult :bytes (exact! st.stOut st.stPos) :nextOffset st.stNext)))))

fn inflate! data: Bytes -> (Result Bytes String)
  (mt (inflateInternal! data 0)
    ((err e) (err e))
    ((ok res) (ok res.bytes)))
