(module asl-text/tests/base64Test :x [runTests] :i [(asl-text/base64 :a b64)])

fn bytesOf xs: (List Int64) -> Bytes
  (let [(out (bytesAlloc (listLength xs)))]
    (fold (fn [(acc Bytes) (p (Pair Int64 Int64))] -> Bytes
            (do (bytesSet acc (pairFirst p) (pairSecond p)) acc))
          out (enumerate xs)))

fn testVectors -> Bool
  (do
    (assert (= (b64/encode "") "") "RFC empty")
    (assert (= (b64/encode "f") "Zg==") "RFC f")
    (assert (= (b64/encode "fo") "Zm8=") "RFC fo")
    (assert (= (b64/encode "foo") "Zm9v") "RFC foo")
    (assert (= (b64/encode "foob") "Zm9vYg==") "RFC foob")
    (assert (= (b64/encode "fooba") "Zm9vYmE=") "RFC fooba")
    (assert (= (b64/encode "foobar") "Zm9vYmFy") "RFC foobar")
    (assert (= (b64/decodeStr "") (ok "")) "decode empty")
    (assert (= (b64/decodeStr "Zg==") (ok "f")) "decode f")
    (assert (= (b64/decodeStr "Zm8=") (ok "fo")) "decode fo")
    (assert (= (b64/decodeStr "Zm9v") (ok "foo")) "decode foo")
    (assert (= (b64/decodeStr "Zm9vYg==") (ok "foob")) "decode foob")
    (assert (= (b64/decodeStr "Zm9vYmE=") (ok "fooba")) "decode fooba")
    (assert (= (b64/decodeStr "Zm9vYmFy") (ok "foobar")) "decode foobar")
    true)

fn testNoPad -> Bool
  (do
    (assert (= (b64/encodeNoPad "f") "Zg") "nopad f")
    (assert (= (b64/encodeNoPad "fo") "Zm8") "nopad fo")
    (assert (= (b64/encodeNoPad "foob") "Zm9vYg") "nopad foob")
    (assert (= (b64/decodeStr "Zg") (ok "f")) "decode unpadded f")
    (assert (= (b64/decodeStr "Zm8") (ok "fo")) "decode unpadded fo")
    (assert (= (b64/decodeStr "Zm9vYg") (ok "foob")) "decode unpadded foob")
    true)

fn testUrl -> Bool
  (do
    (assert (= (b64/encode "\xfb\xff") "+/8=") "std entries 62 63")
    (assert (= (b64/encodeUrlSafe "\xfb\xff") "-_8=") "url entries 62 63")
    (assert (= (b64/encodeUrlSafeNoPad "\xfb\xff") "-_8") "url nopad")
    (assert (= (b64/decodeUrlSafeStr "-_8=") (ok "\xfb\xff")) "url decode padded")
    (assert (= (b64/decodeUrlSafeStr "-_8") (ok "\xfb\xff")) "url decode bare")
    (assert (= (b64/decodeStr "+/8=") (ok "\xfb\xff")) "std decode plus slash")
    (assert (err? (b64/decodeUrlSafe "+/8=")) "url rejects plus slash")
    (assert (err? (b64/decode "-_8=")) "std rejects minus underscore")
    true)

fn testBytes -> Bool
  (do
    (assert (= (b64/encodeBytes (bytesOf (list 102 111 111))) "Zm9v") "bytes encode foo")
    (assert (= (b64/encodeBytes (bytesOf (list))) "") "bytes encode empty")
    (assert (= (b64/encodeBytes (resultOr (b64/decode "Zm9vYmFy") (bytesAlloc 0))) "Zm9vYmFy") "bytes roundtrip")
    (assert (= (b64/encodeBytes (resultOr (b64/decodeUrlSafe "-_8") (bytesAlloc 0))) "+/8=") "url bytes roundtrip")
    true)

fn testMalformed -> Bool
  (do
    (assert (err? (b64/decode "Zg===")) "triple pad")
    (assert (err? (b64/decode "====")) "all pad")
    (assert (err? (b64/decode "Zg=")) "short pad")
    (assert (err? (b64/decode "Z")) "dangling quantum")
    (assert (err? (b64/decode "Zm9vYg=")) "pad count mismatch")
    (assert (err? (b64/decode "Zh==")) "nonzero pad bits quantum 2")
    (assert (err? (b64/decode "Zm9=")) "nonzero pad bits quantum 3")
    (assert (err? (b64/decode "Zg==x")) "trailing junk")
    (assert (err? (b64/decode "Z*9v")) "invalid char")
    (assert (err? (b64/decode "Zm 9v")) "space inside")
    (assert (err? (b64/decodeStr "Zg===")) "str decode malformed")
    (assert (err? (b64/decodeUrlSafe "Zg===")) "url malformed")
    true)

fn testLatin1 -> Bool
  (do
    (assert (= (b64/decodeStr (b64/encode "\x00\x01\xfe\xff")) (ok "\x00\x01\xfe\xff")) "latin1 roundtrip")
    true)

fn runTests -> Bool
  (and (testVectors) (testNoPad) (testUrl) (testBytes) (testMalformed) (testLatin1))
