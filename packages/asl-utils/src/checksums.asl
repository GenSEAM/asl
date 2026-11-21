(module asl-utils/checksums :x [adler32 fnv1a32 fnv1a64 crc32] :i [])

fn adlerStep bs: Bytes i: Int64 n: Int64 a: Int64 b: Int64 -> Int64
  (if (>= i n) (+ (* b 65536) a)
    (let [(a2 (mod (+ a (bytesGet bs i)) 65521))]
      (adlerStep bs (+ i 1) n a2 (mod (+ b a2) 65521))))

fn adler32 bs: Bytes -> Int64
  (adlerStep bs 0 (bytesLength bs) 1 0)

fn fnv32Step bs: Bytes i: Int64 n: Int64 h: Int64 -> Int64
  (if (>= i n) h
    (fnv32Step bs (+ i 1) n (mod (* (^ h (bytesGet bs i)) 16777619) 4294967296)))

fn fnv1a32 bs: Bytes -> Int64
  (fnv32Step bs 0 (bytesLength bs) 2166136261)

fn mulMod64 a: Int64 b: Int64 -> Int64
  (let [(aHi (>> a 32)) (aLo (& a 4294967295)) (bHi (>> b 32)) (bLo (& b 4294967295))]
    (let [(p0 (* aLo bLo)) (p1 (* aHi bLo)) (p2 (* aLo bHi))]
      (+ (<< (+ p1 p2) 32) p0)))

fn fnv64Step bs: Bytes i: Int64 n: Int64 h: Int64 -> Int64
  (if (>= i n) h
    (fnv64Step bs (+ i 1) n (mulMod64 (^ h (bytesGet bs i)) 1099511628211)))

fn fnv1a64 bs: Bytes -> Int64
  (fnv64Step bs 0 (bytesLength bs) -3750763034362895579)

fn crcBit c: Int64 k: Int64 -> Int64
  (if (= k 0) c
    (crcBit (if (= (& c 1) 1) (^ (>> c 1) 3988292384) (>> c 1)) (- k 1)))

fn crcStep bs: Bytes i: Int64 n: Int64 c: Int64 -> Int64
  (if (>= i n) (^ c 4294967295)
    (crcStep bs (+ i 1) n (crcBit (^ c (bytesGet bs i)) 8)))

fn crc32 bs: Bytes -> Int64
  (crcStep bs 0 (bytesLength bs) 4294967295)
