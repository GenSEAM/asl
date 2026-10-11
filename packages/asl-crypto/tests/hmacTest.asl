(module asl-crypto/tests/hmacTest
  :x [runTests]
  :i [(asl-crypto/hmac :a h)] )

fn decoded text: String -> Bytes
  (mt (h/hexToBytes text) ((ok b) b) ((err _) (bytesAlloc 0)))

fn repeatedByte value: Int64 count: Int64 -> Bytes
  (let [(out (bytesAlloc count))
        (step (fn [step i] -> Bytes
          (if (>= i count) out
            (do (bytesSet out i value) (step step (+ i 1))))))]
    (step step 0))

fn runTests -> Bool
  (let [(key1 (decoded (stringRepeat "0b" 20)))
        (key3 (decoded (stringRepeat "aa" 20)))
        (key4 (decoded "0102030405060708090a0b0c0d0e0f10111213141516171819"))
        (key5 (decoded (stringRepeat "0c" 20)))
        (key6 (decoded (stringRepeat "aa" 131)))
        (key7 (decoded (stringRepeat "aa" 131)))
        (msg3 (repeatedByte 221 50))]
    (assert (= (h/hmacSha256Hex key1 (stringToBytes "Hi There")) "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7") "RFC4231 case 1")
    (assert (= (h/hmacSha256Hex (stringToBytes "Jefe") (stringToBytes "what do ya want for nothing?")) "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843") "RFC4231 case 2")
    (assert (= (h/hmacSha256Hex key3 msg3) "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe") "RFC4231 case 3")
    (assert (= (h/hmacSha256Hex key4 (repeatedByte 205 50)) "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b") "RFC4231 case 4")
    (assert (= (optionOr (stringSlice (h/hmacSha256Hex key5 (stringToBytes "Test With Truncation")) 0 32) "") "a3b6167473100ee06e0c796c2955552b") "RFC4231 case 5 truncated 128 bits")
    (assert (= (h/hmacSha256Hex key6 (stringToBytes "Test Using Larger Than Block-Size Key - Hash Key First")) "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54") "RFC4231 case 6")
    (assert (= (h/hmacSha256Hex key7 (stringToBytes "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.")) "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2") "RFC4231 case 7")
    (assert (h/constantTimeEqual (decoded "00ff10") (decoded "00ff10")) "equal bytes")
    (assert (not (h/constantTimeEqual (decoded "00ff10") (decoded "00ff11"))) "last-byte difference")
    (assert (not (h/constantTimeEqual (decoded "00ff10") (decoded "01ff10"))) "first-byte difference")
    (assert (not (h/constantTimeEqual (decoded "00ff10") (decoded "00ff"))) "different length")
    (assert (= (h/bytesToHex (decoded "ab12cd")) "ab12cd") "hex round trip")
    (assert (mt (h/hexToBytes "0xz1") ((ok _) false) ((err _) true)) "hex rejects invalid characters")
    true)
