(module asl-zip/gzip
  :x [gunzip! gunzipWithLimit! crc32 inflate!]
  :i [(asl-zip/inflate :a inf)])

fn inflate! data: Bytes -> (Result Bytes String)
  (inf/inflate! data)

fn errText p: Int64 msg: String -> String
  (str "error at offset " (stringFromInt64 p) ": " msg)

fn lowBits x: Int64 k: Int64 -> Int64
  (- x (<< (>> x k) k))

fn getU16Le bs: Bytes off: Int64 -> Int64
  (+ (bytesGet bs off) (<< (bytesGet bs (+ off 1)) 8))

fn getU32Le bs: Bytes off: Int64 -> Int64
  (+ (getU16Le bs off) (<< (getU16Le bs (+ off 2)) 16))

fn xorFill! x: Bytes i: Int64 -> Unit
  (if (>= i 65536) ()
    (let [(a (>> i 8))
          (b (lowBits i 8))
          (v (if (= a 0) b
               (+ (* (bytesGet x (+ (* (>> a 1) 256) (>> b 1))) 2)
                  (if (= (lowBits a 1) (lowBits b 1)) 0 1))))]
      (do
        (bytesSet x i v)
        (xorFill! x (+ i 1)))))

fn xor8 tx: Bytes a: Int64 b: Int64 -> Int64
  (bytesGet tx (+ (<< a 8) b))

fn xor32 tx: Bytes a: Int64 b: Int64 -> Int64
  (+ (xor8 tx (lowBits a 8) (lowBits b 8))
     (+ (<< (xor8 tx (lowBits (>> a 8) 8) (lowBits (>> b 8) 8)) 8)
        (+ (<< (xor8 tx (lowBits (>> a 16) 8) (lowBits (>> b 16) 8)) 16)
           (<< (xor8 tx (>> a 24) (>> b 24)) 24))))

fn shiftPoly tx: Bytes c: Int64 -> Int64
  (if (= (lowBits c 1) 1) (xor32 tx (>> c 1) 3988292384) (>> c 1))

fn crcEntry tx: Bytes k: Int64 c: Int64 -> Int64
  (if (>= k 8) c (crcEntry tx (+ k 1) (shiftPoly tx c)))

fn put32! b: Bytes off: Int64 v: Int64 -> Unit
  (do
    (bytesSet b off (lowBits v 8))
    (bytesSet b (+ off 1) (lowBits (>> v 8) 8))
    (bytesSet b (+ off 2) (lowBits (>> v 16) 8))
    (bytesSet b (+ off 3) (>> v 24)))

fn crcFill! tx: Bytes i: Int64 -> Unit
  (if (>= i 256) ()
    (do
      (put32! tx (+ 65536 (* i 4)) (crcEntry tx 0 i))
      (crcFill! tx (+ i 1))))

fn crcTables! -> Bytes
  (let [(tx (bytesAlloc 66576))]
    (do
      (xorFill! tx 0)
      (crcFill! tx 0)
      tx))

fn crcStep tx: Bytes c: Int64 b: Int64 -> Int64
  (let [(k (+ 65536 (<< (xor8 tx (lowBits c 8) b) 2)))]
    (+ (xor8 tx (lowBits (>> c 8) 8) (bytesGet tx k))
       (+ (<< (xor8 tx (lowBits (>> c 16) 8) (bytesGet tx (+ k 1))) 8)
          (+ (<< (xor8 tx (>> c 24) (bytesGet tx (+ k 2))) 16)
             (<< (bytesGet tx (+ k 3)) 24)))))

fn crc1 bs: Bytes i: Int64 end: Int64 tx: Bytes c: Int64 -> Int64
  (if (>= i end) c (crc1 bs (+ i 1) end tx (crcStep tx c (bytesGet bs i))))

fn crc4! bs: Bytes tx: Bytes i: Int64 end: Int64 q: Int64 ca: Int64 cb: Int64 cc: Int64 cd: Int64 -> Unit
  (if (>= i end)
    (do
      (put32! tx 66560 ca)
      (put32! tx 66564 cb)
      (put32! tx 66568 cc)
      (put32! tx 66572 cd))
    (crc4! bs tx (+ i 1) end q
      (crcStep tx ca (bytesGet bs i))
      (crcStep tx cb (bytesGet bs (+ i q)))
      (crcStep tx cc (bytesGet bs (+ i (* 2 q))))
      (crcStep tx cd (bytesGet bs (+ i (* 3 q))))))

fn get32 b: Bytes off: Int64 -> Int64
  (+ (getU16Le b off) (<< (getU16Le b (+ off 2)) 16))

fn mulMod tx: Bytes a: Int64 b: Int64 k: Int64 p: Int64 -> Int64
  (cond
    ((< k 0) p)
    ((= (lowBits (>> a k) 1) 1)
     (let [(p1 (xor32 tx p b))]
       (if (= (lowBits a k) 0) p1 (mulMod tx a (shiftPoly tx b) (- k 1) p1))))
    (else (mulMod tx a (shiftPoly tx b) (- k 1) p)))

fn powMod tx: Bytes n: Int64 pw: Int64 p: Int64 -> Int64
  (if (= n 0) p
    (powMod tx (>> n 1) (mulMod tx pw pw 31 0) (if (= (lowBits n 1) 1) (mulMod tx pw p 31 0) p)))

fn crcCombine tx: Bytes crcA: Int64 crcB: Int64 lenB: Int64 -> Int64
  (let [(x8 (mulMod tx 1073741824 1073741824 31 0))
        (x8b (mulMod tx x8 x8 31 0))
        (x8c (mulMod tx x8b x8b 31 0))]
    (xor32 tx (mulMod tx (powMod tx lenB x8c 2147483648) crcA 31 0) crcB))

fn ! crc32Range bs: Bytes start: Int64 end: Int64 tx: Bytes -> Int64
  (let [(n (- end start))]
    (if (< n 64)
      (- 4294967295 (crc1 bs start end tx 4294967295))
      (let [(q (/ n 4))
            (_ (crc4! bs tx start (+ start q) q 4294967295 4294967295 4294967295 4294967295))
            (ca (- 4294967295 (get32 tx 66560)))
            (cb (- 4294967295 (get32 tx 66564)))
            (cc (- 4294967295 (get32 tx 66568)))
            (cd (- 4294967295 (crc1 bs (+ start (* 4 q)) end tx (get32 tx 66572))))]
        (crcCombine tx (crcCombine tx (crcCombine tx ca cb q) cc q) cd (- n (* 3 q))))))

fn ! crc32 data: Bytes -> Int64
  (crc32Range data 0 (bytesLength data) (crcTables!))

fn flag? flg: Int64 bit: Int64 -> Bool
  (= (lowBits (>> flg bit) 1) 1)

fn skipExtra data: Bytes len: Int64 flg: Int64 p: Int64 -> (Result Int64 String)
  (cond
    ((not (flag? flg 2)) (ok p))
    ((> (+ p 2) len) (err (errText p "truncated input")))
    ((> (+ (+ p 2) (getU16Le data p)) len) (err (errText p "truncated input")))
    (else (ok (+ (+ p 2) (getU16Le data p)))))

fn skipZero data: Bytes len: Int64 idx: Int64 -> (Result Int64 String)
  (cond
    ((>= idx len) (err (errText idx "truncated input")))
    ((= (bytesGet data idx) 0) (ok (+ idx 1)))
    (else (skipZero data len (+ idx 1))))

fn skipString data: Bytes len: Int64 flg: Int64 bit: Int64 p: Int64 -> (Result Int64 String)
  (if (flag? flg bit) (skipZero data len p) (ok p))

fn ! checkHcrc data: Bytes len: Int64 flg: Int64 hdrStart: Int64 p: Int64 tx: Bytes -> (Result Int64 String)
  (cond
    ((not (flag? flg 1)) (ok p))
    ((> (+ p 2) len) (err (errText p "truncated input")))
    ((!= (lowBits (crc32Range data hdrStart p tx) 16) (getU16Le data p)) (err (errText p "CRC mismatch")))
    (else (ok (+ p 2))))

fn ! headerEnd data: Bytes len: Int64 pos: Int64 tx: Bytes -> (Result Int64 String)
  (cond
    ((> (+ pos 10) len) (err (errText pos "truncated input")))
    ((or (!= (bytesGet data pos) 31) (!= (bytesGet data (+ pos 1)) 139)) (err (errText pos "invalid gzip header")))
    ((!= (bytesGet data (+ pos 2)) 8) (err (errText (+ pos 2) "unsupported compression method")))
    ((> (bytesGet data (+ pos 3)) 31) (err (errText (+ pos 3) "reserved flags set")))
    (else
     (let [(flg (bytesGet data (+ pos 3)))]
       (mt (skipExtra data len flg (+ pos 10))
         ((err e) (err e))
         ((ok p1)
          (mt (skipString data len flg 3 p1)
            ((err e) (err e))
            ((ok p2)
             (mt (skipString data len flg 4 p2)
               ((err e) (err e))
               ((ok p3) (checkHcrc data len flg pos p3 tx))))))))))

fn exact! out: Bytes n: Int64 -> Bytes
  (if (= (bytesLength out) n) out
    (let [(fresh (bytesAlloc n))]
      (do
        (copyOut! fresh out 0 n)
        fresh)))

fn copyOut! dst: Bytes src: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet dst i (bytesGet src i))
      (copyOut! dst src (+ i 1) n)))

fn members! data: Bytes len: Int64 pos: Int64 out: Bytes op: Int64 limit: Int64 tx: Bytes -> (Result Bytes String)
  (mt (headerEnd data len pos tx)
    ((err e) (err e))
    ((ok deflateStart)
     (mt (inf/inflateAppend! data deflateStart out op limit)
       ((err e) (err e))
       ((ok st)
        (let [(trailer st.stNext)
              (buf st.stOut)
              (end st.stPos)]
          (cond
            ((> (+ trailer 8) len) (err (errText trailer "truncated input")))
            ((!= (crc32Range buf op end tx) (getU32Le data trailer)) (err (errText trailer "CRC mismatch")))
            ((!= (lowBits (- end op) 32) (getU32Le data (+ trailer 4))) (err (errText (+ trailer 4) "ISIZE mismatch")))
            ((= (+ trailer 8) len) (ok (exact! buf end)))
            (else (members! data len (+ trailer 8) buf end limit tx))))))))

fn gunzipWithLimit! data: Bytes limit: Int64 -> (Result Bytes String)
  (let [(len (bytesLength data))]
    (if (< len 10)
      (err "error at offset 0: truncated input")
      (let [(isize (if (>= len 18) (getU32Le data (- len 4)) 0))
            (initCap (min limit (min isize (+ 1024 (* len 1032)))))]
        (members! data len 0 (bytesAlloc (max 0 initCap)) 0 limit (crcTables!)))))

fn gunzip! data: Bytes -> (Result Bytes String)
  (gunzipWithLimit! data 4294967296)
