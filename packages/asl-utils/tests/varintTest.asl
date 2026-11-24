(module asl-utils/tests/varintTest
  :x [runTests]
  :i [(asl-utils/varint :a v)])

fn ! fillFrom! b: Bytes i: Int64 xs: (List Int64) -> Unit
  (match (listHead xs)
    ((none) ())
    ((some x) (do (bytesSet b i x) (fillFrom! b (+ i 1) (optionOr (listTail xs) (list))))))

fn ! bytesOf xs: (List Int64) -> Bytes
  (let [(b (bytesAlloc (listLength xs)))]
    (do (fillFrom! b 0 xs) b))

fn collect bs: Bytes i: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i (bytesLength bs))
    (listReverse acc)
    (collect bs (+ i 1) (cons (bytesGet bs i) acc)))

fn bytesList bs: Bytes -> (List Int64)
  (collect bs 0 (list))

fn ! testEncodeU -> Bool
  (do (assert (= (bytesList (v/encodeU 0)) (list 0)) "0 encodes as 00")
      (assert (= (bytesList (v/encodeU 1)) (list 1)) "1 encodes as 01")
      (assert (= (bytesList (v/encodeU 127)) (list 127)) "127 is one byte")
      (assert (= (bytesList (v/encodeU 128)) (list 128 1)) "128 is 80 01")
      (assert (= (bytesList (v/encodeU 300)) (list 172 2)) "300 is ac 02")
      (assert (= (bytesList (v/encodeU 624485)) (list 229 142 38)) "624485 is e5 8e 26")
      (assert (= (v/uvarintLength 624485) 3) "624485 takes three bytes")
      true)

fn ! testDecodeU -> Bool
  (do (assert (= (v/decodeU (v/encodeU 0)) (ok (pair 0 1))) "decode 0")
      (assert (= (v/decodeU (v/encodeU 300)) (ok (pair 300 2))) "decode 300")
      (assert (= (v/decodeU (v/encodeU 624485)) (ok (pair 624485 3))) "decode 624485")
      (assert (= (v/decodeUAt (bytesOf (list 7 172 2)) 1) (ok (pair 300 2))) "decode at offset 1")
      (assert (= (v/decodeUAt (bytesOf (list 7 172 2)) 0) (ok (pair 7 1))) "decode at offset 0")
      (assert (= (v/decodeU (bytesOf (list 172 2 99))) (ok (pair 300 2))) "trailing bytes are not consumed")
      true)

fn ! testBadU -> Bool
  (do (assert (err? (v/decodeU (bytesOf (list)))) "empty input is truncated")
      (assert (err? (v/decodeU (bytesOf (list 128)))) "a lone continuation byte is truncated")
      (assert (err? (v/decodeU (bytesOf (list 255 255)))) "two continuation bytes are truncated")
      (assert (err? (v/decodeU (bytesOf (list 128 0)))) "a non-minimal encoding is overlong")
      (assert (err? (v/decodeU (bytesOf (list 255 255 255 255 255 255 255 255 255 1)))) "ten bytes are overlong")
      (assert (err? (v/decodeUAt (bytesOf (list 1)) 1)) "an offset past the end is truncated")
      true)

fn testZigzag -> Bool
  (do (assert (= (v/zigzagEncode 0) (ok 0)) "zigzag 0 is ok 0")
      (assert (= (v/zigzagEncode -1) (ok 1)) "zigzag -1 is ok 1")
      (assert (= (v/zigzagEncode 1) (ok 2)) "zigzag 1 is ok 2")
      (assert (= (v/zigzagEncode -2) (ok 3)) "zigzag -2 is ok 3")
      (assert (= (v/zigzagDecode 0) 0) "unzigzag 0 is 0")
      (assert (= (v/zigzagDecode 1) -1) "unzigzag 1 is -1")
      (assert (= (v/zigzagDecode 2) 1) "unzigzag 2 is 1")
      (assert (= (v/zigzagDecode 3) -2) "unzigzag 3 is -2")
      true)

fn ! testZigzagBoundary -> Bool
  (do (assert (= (v/zigzagEncode 4611686018427387903) (ok 9223372036854775806)) "max safe positive")
      (assert (= (v/zigzagEncode -4611686018427387904) (ok 9223372036854775807)) "max safe negative")
      (assert (err? (v/zigzagEncode 4611686018427387904)) "overflow positive")
      (assert (err? (v/zigzagEncode -4611686018427387905)) "overflow negative")
      (assert (err? (v/zigzagEncode -9223372036854775808)) "min Int64 overflows")
      true)

fn ! testSigned -> Bool
  (do (assert (= (bytesList (resultOr (v/encodeS -1) (bytesAlloc 0))) (list 1)) "-1 is 01")
      (assert (= (bytesList (resultOr (v/encodeS 1) (bytesAlloc 0))) (list 2)) "1 is 02")
      (assert (= (bytesList (resultOr (v/encodeS -300) (bytesAlloc 0))) (list 215 4)) "-300 is d7 04")
      (assert (= (bytesList (resultOr (v/encodeS 300) (bytesAlloc 0))) (list 216 4)) "300 is d8 04")
      (assert (= (v/decodeS (resultOr (v/encodeS -300) (bytesAlloc 0))) (ok (pair -300 2))) "round trip -300")
      (assert (= (v/decodeS (resultOr (v/encodeS 1000000) (bytesAlloc 0))) (ok (pair 1000000 3))) "round trip 1000000")
      (assert (= (v/decodeS (resultOr (v/encodeS -1000000) (bytesAlloc 0))) (ok (pair -1000000 3))) "round trip -1000000")
      (assert (= (v/decodeS (bytesOf (list 2 99))) (ok (pair 1 1))) "a signed decode stops at its last byte")
      (assert (err? (v/decodeS (bytesOf (list 128)))) "a truncated signed varint is an err")
      (assert (= (v/svarintLength -300) (ok 2)) "svarintLength of -300 is ok 2")
      true)

fn ! runTests -> Bool
  (do (assert (testEncodeU) "unsigned encode")
      (assert (testDecodeU) "unsigned decode with consumed length")
      (assert (testBadU) "truncated and overlong input is an err")
      (assert (testZigzag) "zigzag mapping")
      (assert (testZigzagBoundary) "zigzag boundary and overflow")
      (assert (testSigned) "signed encode and decode")
      true)
