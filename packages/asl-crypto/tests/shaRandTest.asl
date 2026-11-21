(module asl-crypto/tests/shaRandTest
  :x [runTests]
  :i [(asl-crypto/sha :a s) (asl-crypto/random :a r) (asl-crypto/hmac :a h)])

fn decoded text: String -> Bytes
  (match (h/hexToBytes text) ((ok b) b) ((err _) (bytesAlloc 0)))

fn hex b: Bytes -> String
  (h/bytesToHex b)

fn uuidOk u: String -> Bool
  (and (= (stringLength u) 36)
    (and (= (optionOr (stringSlice u 14 15) "") "4")
      (and (stringContains? "89ab" (optionOr (stringSlice u 19 20) ""))
        (and (listAll? (fn [i] (= (optionOr (stringSlice u i (+ i 1)) "") "-")) (list 8 13 18 23))
          (listAll? (fn [c] (stringContains? "0123456789abcdef-" c)) (stringChars u))))))

fn ! uuidLoop i: Int64 seen: (Map String Bool) -> Bool
  (if (>= i 1000) true
    (match (r/uuidV4)
      ((err _) (do (assert false "uuidV4 returns ok") false))
      ((ok u)
        (if (or (not (uuidOk u)) (mapHas? seen u))
          (do (assert false "uuid pattern and uniqueness") false)
          (uuidLoop (+ i 1) (mapSet seen u true))))))

fn ! runTests -> Bool
  (do
    (assert (= (hex (s/sha1 (bytesAlloc 0))) "da39a3ee5e6b4b0d3255bfef95601890afd80709") "sha1 empty")
    (assert (= (hex (s/sha1 (stringToBytes "abc"))) "a9993e364706816aba3e25717850c26c9cd0d89d") "sha1 abc")
    (assert (= (hex (s/sha512 (bytesAlloc 0))) "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e") "sha512 empty")
    (assert (= (hex (s/sha512 (stringToBytes "abc"))) "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f") "sha512 abc")
    (assert (= (hex (s/hmacSha512 (decoded (stringRepeat "0b" 20)) (stringToBytes "Hi There"))) "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854") "RFC4231 sha512 case 1")
    (assert (= (hex (s/hmacSha512 (stringToBytes "Jefe") (stringToBytes "what do ya want for nothing?"))) "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737") "RFC4231 sha512 case 2")
    (assert (= (hex (s/hmacSha512 (decoded (stringRepeat "aa" 131)) (stringToBytes "Test Using Larger Than Block-Size Key - Hash Key First"))) "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598") "RFC4231 sha512 case 6")
    (let [(b1 (r/randomBytes 32)) (b2 (r/randomBytes 32))]
      (do
        (assert (match b1 ((ok b) (= (bytesLength b) 32)) ((err _) false)) "randomBytes 32 length")
        (assert (match b2 ((ok b) (= (bytesLength b) 32)) ((err _) false)) "randomBytes second call length")
        (assert (not (= (match b1 ((ok b) (hex b)) ((err _) "e1")) (match b2 ((ok b) (hex b)) ((err _) "e2")))) "two randomBytes calls differ")))
    (assert (match (r/randomBytes -1) ((ok _) false) ((err _) true)) "randomBytes negative rejected")
    (assert (match (r/randomBytes 1048577) ((ok _) false) ((err _) true)) "randomBytes too large rejected")
    (assert (uuidLoop 0 (mapEmpty)) "1000 uuidV4 pattern and no duplicates")
    true)
