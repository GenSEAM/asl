(module asl-zip/gzipWriter
  :x [gzip! crc32!]
  :i [(asl-zip/deflate :a df)])

fn copyBytes! dst: Bytes dstOff: Int64 src: Bytes srcOff: Int64 n: Int64 i: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet dst (+ dstOff i) (bytesGet src (+ srcOff i)))
      (copyBytes! dst dstOff src srcOff n (+ i 1))))

fn put32! b: Bytes off: Int64 v: Int64 -> Unit
  (do
    (bytesSet b off (lowBits v 8))
    (bytesSet b (+ off 1) (lowBits (>> v 8) 8))
    (bytesSet b (+ off 2) (lowBits (>> v 16) 8))
    (bytesSet b (+ off 3) (>> v 24)))

fn lowBits x: Int64 k: Int64 -> Int64
  (- x (<< (>> x k) k))

fn xor32 a: Int64 b: Int64 k: Int64 acc: Int64 -> Int64
  (if (>= k 32) acc
    (xor32 (>> a 1) (>> b 1) (+ k 1)
      (if (= (lowBits a 1) (lowBits b 1)) acc (+ acc (<< 1 k)))))

fn crcEntry c: Int64 n: Int64 -> Int64
  (if (>= n 8) c
    (crcEntry (if (= (lowBits c 1) 1)
               (xor32 (>> c 1) 3988292384 0 0)
               (>> c 1)) (+ n 1)))

fn putTable32! table: Bytes p: Int64 x: Int64 -> Unit
  (do
    (bytesSet table p (lowBits x 8))
    (bytesSet table (+ p 1) (lowBits (>> x 8) 8))
    (bytesSet table (+ p 2) (lowBits (>> x 16) 8))
    (bytesSet table (+ p 3) (>> x 24)))

fn crcTable! table: Bytes i: Int64 -> Unit
  (if (>= i 256) ()
    (do
      (putTable32! table (* i 4) (crcEntry i 0))
      (crcTable! table (+ i 1))))

fn getTable32 table: Bytes p: Int64 -> Int64
  (+ (bytesGet table p)
    (+ (<< (bytesGet table (+ p 1)) 8)
      (+ (<< (bytesGet table (+ p 2)) 16)
        (<< (bytesGet table (+ p 3)) 24))))

fn crcLoop data: Bytes i: Int64 c: Int64 table: Bytes -> Int64
  (if (>= i (bytesLength data))
    (xor32 c 4294967295 0 0)
    (let [(idx (lowBits (xor32 c (bytesGet data i) 0 0) 8))]
      (crcLoop data (+ i 1) (xor32 (>> c 8) (getTable32 table (* idx 4)) 0 0) table)))

fn crc32! data: Bytes -> Int64
  (let [(table (bytesAlloc 1024))]
    (do
      (crcTable! table 0)
      (crcLoop data 0 4294967295 table)))

fn gzip! data: Bytes level: Int64 -> (Result Bytes String)
  (match (df/deflateWithLevel! data level)
    ((err e) (err e))
    ((ok body)
      (let [(n (bytesLength data))
            (m (bytesLength body))
            (out (bytesAlloc (+ 18 m)))]
        (do
          (bytesSet out 0 31)
          (bytesSet out 1 139)
          (bytesSet out 2 8)
          (bytesSet out 3 0)
          (bytesSet out 4 0)
          (bytesSet out 5 0)
          (bytesSet out 6 0)
          (bytesSet out 7 0)
          (bytesSet out 8 (if (= level 1) 4 0))
          (bytesSet out 9 255)
          (copyBytes! out 10 body 0 m 0)
          (put32! out (+ 10 m) (crc32! data))
          (put32! out (+ 14 m) n)
          (ok out)))))
