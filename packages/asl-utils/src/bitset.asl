(module asl-utils/bitset
  :x [bsNew bsSet bsClear bsTest bsCount bsUnion bsIntersect bsDifference bsToList]
  :i [])

fn bitMask i: Int64 -> Int64
  (optionOr (listGet (list 1 2 4 8 16 32 64 128) (mod i 8)) 0)

fn byteOf i: Int64 -> Int64
  (/ i 8)

fn bitOn? v: Int64 k: Int64 -> Bool
  (!= (& v (bitMask k)) 0)

fn bitsIn v: Int64 k: Int64 -> Int64
  (if (>= k 8)
    0
    (if (bitOn? v k) (+ 1 (bitsIn v (+ k 1))) (bitsIn v (+ k 1))))

fn bsNew n: Int64 -> Bytes
  (bytesAlloc (/ (+ n 7) 8))

fn bsTest b: Bytes i: Int64 -> Bool
  (bitOn? (bytesGet b (byteOf i)) i)

fn bsSet b: Bytes i: Int64 -> Unit
  (bytesSet b (byteOf i) (| (bytesGet b (byteOf i)) (bitMask i)))

fn bsClear b: Bytes i: Int64 -> Unit
  (bytesSet b (byteOf i) (& (bytesGet b (byteOf i)) (- 255 (bitMask i))))

fn countFrom b: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n) 0 (+ (bitsIn (bytesGet b i) 0) (countFrom b (+ i 1) n)))

fn bsCount b: Bytes -> Int64
  (countFrom b 0 (bytesLength b))

fn combineByte x: Int64 y: Int64 tag: String -> Int64
  (cond ((= tag "union") (| x y))
        ((= tag "intersect") (& x y))
        (else (& x (- 255 y))))

fn combineLoop a: Bytes b: Bytes out: Bytes tag: String i: Int64 n: Int64 -> Bytes
  (if (>= i n)
    out
    (do (bytesSet out i (combineByte (bytesGet a i) (bytesGet b i) tag))
        (combineLoop a b out tag (+ i 1) n)))

fn bsCombine a: Bytes b: Bytes tag: String -> Bytes
  (let [(n (min (bytesLength a) (bytesLength b)))]
    (combineLoop a b (bytesAlloc n) tag 0 n))

fn bsUnion a: Bytes b: Bytes -> Bytes
  (bsCombine a b "union")

fn bsIntersect a: Bytes b: Bytes -> Bytes
  (bsCombine a b "intersect")

fn bsDifference a: Bytes b: Bytes -> Bytes
  (bsCombine a b "difference")

fn bitsOfByte v: Int64 base: Int64 k: Int64 acc: (List Int64) -> (List Int64)
  (if (>= k 8)
    acc
    (bitsOfByte v base (+ k 1) (if (bitOn? v k) (listAppend acc (list (+ base k))) acc)))

fn bitsAll b: Bytes i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) acc (bitsAll b (+ i 1) n (bitsOfByte (bytesGet b i) (* i 8) 0 acc)))

fn bsToList b: Bytes -> (List Int64)
  (bitsAll b 0 (bytesLength b) (list))
