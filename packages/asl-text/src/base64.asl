(module asl-text/base64
  :x [encode encodeBytes encodeNoPad encodeUrlSafe encodeUrlSafeNoPad decode decodeStr decodeUrlSafe decodeUrlSafeStr]
  :i [])

fn stdAlphabet -> String
  (str "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

fn urlAlphabet -> String
  (str "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

fn alphaAt a: String i: Int64 -> String
  (optionOr (stringSlice a i (+ i 1)) "")

fn encPiece alpha: String pad: Bool b0: Int64 b1: Int64 b2: Int64 rem: Int64 -> String
  (let [(v (+ (* b0 65536) (+ (* b1 256) b2)))
        (c0 (alphaAt alpha (/ v 262144)))
        (c1 (alphaAt alpha (mod (/ v 4096) 64)))
        (c2 (alphaAt alpha (mod (/ v 64) 64)))
        (c3 (alphaAt alpha (mod v 64)))]
    (cond
      ((>= rem 3) (str c0 c1 c2 c3))
      ((= rem 2) (str c0 c1 c2 (if pad "=" "")))
      (else (str c0 c1 (if pad "==" "")))))

fn encLoop alpha: String pad: Bool bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(rem (- n i))
          (b0 (bytesGet bs i))
          (b1 (if (< (+ i 1) n) (bytesGet bs (+ i 1)) 0))
          (b2 (if (< (+ i 2) n) (bytesGet bs (+ i 2)) 0))]
      (encLoop alpha pad bs n (+ i 3) (cons (encPiece alpha pad b0 b1 b2 rem) acc))))

fn encodeBytes bs: Bytes -> String
  (encLoop (stdAlphabet) true bs (bytesLength bs) 0 (list))

fn encode s: String -> String
  (encodeBytes (stringToBytes s))

fn encodeNoPad s: String -> String
  (let [(bs (stringToBytes s))]
    (encLoop (stdAlphabet) false bs (bytesLength bs) 0 (list)))

fn encodeUrlSafe s: String -> String
  (let [(bs (stringToBytes s))]
    (encLoop (urlAlphabet) true bs (bytesLength bs) 0 (list)))

fn encodeUrlSafeNoPad s: String -> String
  (let [(bs (stringToBytes s))]
    (encLoop (urlAlphabet) false bs (bytesLength bs) 0 (list)))

fn padCount s: String n: Int64 k: Int64 -> Int64
  (if (and (< k n) (= (alphaAt s (- (- n 1) k)) "="))
    (padCount s n (+ k 1))
    k)

fn putByte out: Bytes n: Int64 i: Int64 v: Int64 -> Int64
  (if (< i n) (do (bytesSet out i v) 0) 0)

fn decFill vals: (List Int64) out: Bytes outLen: Int64 vi: Int64 bi: Int64 -> Bytes
  (if (>= bi outLen)
    out
    (let [(v0 (optionOr (listGet vals vi) 0))
          (v1 (optionOr (listGet vals (+ vi 1)) 0))
          (v2 (optionOr (listGet vals (+ vi 2)) 0))
          (v3 (optionOr (listGet vals (+ vi 3)) 0))
          (x (+ (* v0 262144) (+ (* v1 4096) (+ (* v2 64) v3))))]
      (do
        (putByte out outLen bi (/ x 65536))
        (putByte out outLen (+ bi 1) (mod (/ x 256) 256))
        (putByte out outLen (+ bi 2) (mod x 256))
        (decFill vals out outLen (+ vi 4) (+ bi 3)))))

fn decodeWith alpha: String s: String -> (Result Bytes String)
  (let [(n (stringLength s))
        (pad (padCount s n 0))
        (coreLen (- n pad))
        (core (optionOr (stringSlice s 0 coreLen) ""))
        (vals (map (fn [(c String)] -> Int64 (optionOr (stringIndexOf alpha c) -1)) (stringChars core)))
        (q (mod coreLen 4))
        (outLen (+ (* (/ coreLen 4) 3) (cond ((= q 2) 1) ((= q 3) 2) (else 0))))]
    (cond
      ((> pad 2) (err (str "base64: too much padding in " s)))
      ((stringContains? core "=") (err (str "base64: misplaced padding in " s)))
      ((listAny? (fn [(v Int64)] -> Bool (< v 0)) vals) (err (str "base64: invalid character in " s)))
      ((= q 1) (err (str "base64: dangling quantum in " s)))
      ((and (> pad 0) (!= (+ q pad) 4)) (err (str "base64: wrong padding length in " s)))
      ((and (= q 2) (!= (mod (optionOr (listLast vals) 0) 16) 0)) (err (str "base64: nonzero pad bits in " s)))
      ((and (= q 3) (!= (mod (optionOr (listLast vals) 0) 4) 0)) (err (str "base64: nonzero pad bits in " s)))
      (else (ok (decFill vals (bytesAlloc outLen) outLen 0 0)))))

fn decode s: String -> (Result Bytes String)
  (decodeWith (stdAlphabet) s)

fn decodeUrlSafe s: String -> (Result Bytes String)
  (decodeWith (urlAlphabet) s)

fn byteStr b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn strFromBytes bs: Bytes -> String
  (let [(len (bytesLength bs))]
    (if (<= len 0)
      ""
      (stringJoin (map (fn [(i Int64)] -> String (byteStr (bytesGet bs i))) (range 0 len)) "")))

fn decodeStr s: String -> (Result String String)
  (match (decode s)
    ((ok bs) (ok (strFromBytes bs)))
    ((err e) (err e)))

fn decodeUrlSafeStr s: String -> (Result String String)
  (match (decodeUrlSafe s)
    ((ok bs) (ok (strFromBytes bs)))
    ((err e) (err e)))
