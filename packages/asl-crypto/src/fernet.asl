(module asl-crypto/fernet
  :x [fernetVerify]
  :i [(asl-crypto/hmac :a h) (asl-crypto/aes :a aes)])

fn ! fernetBase64UrlDecode encoded: String -> (Result Bytes String)
  (let [(translated (stringReplace (stringReplace encoded "-" "+") "_" "/"))
        (n (stringLength translated))]
    (if (= (mod n 4) 1) (err "invalidBase64")
      (let [(padded (if (= (mod n 4) 2) (str translated "==")
                     (if (= (mod n 4) 3) (str translated "=") translated)))]
        (mt (bytesFromBase64 padded)
          ((ok bytes) (ok bytes))
          ((err _) (err "invalidBase64"))))))

fn fernetCopy source: Bytes start: Int64 count: Int64 -> Bytes
  (let [(out (bytesAlloc count))
        (step (fn [step i] -> Unit
          (if (< i count)
            (do (bytesSet out i (bytesGet source (+ start i))) (step step (+ i 1)))
            ())))]
    (step step 0)
    out)

fn fernetTimestamp token: Bytes -> Int64
  (if (>= (bytesGet token 1) 128) -1
    (let [(step (fn [step i value] -> Int64
      (if (>= i 9) value
        (step step (+ i 1) (+ (* value 256) (bytesGet token i))))))]
      (step step 1 0)))

fn ! fernetVerify key: String token: String nowSeconds: Int64 ttlSeconds: Int64 -> (Result Bytes String)
  (mt (fernetBase64UrlDecode key)
    ((err _) (err "invalidKey"))
    ((ok keyBytes)
      (if (!= (bytesLength keyBytes) 32) (err "invalidKey")
        (mt (fernetBase64UrlDecode token)
          ((err _) (err "invalidToken"))
          ((ok raw)
            (let [(n (bytesLength raw))]
              (if (< n 73) (err "invalidToken")
                (if (!= (bytesGet raw 0) 128) (err "invalidToken")
                  (if (or (!= (mod (- n 57) 16) 0) (< (- n 57) 16)) (err "invalidToken")
                    (let [(issued (fernetTimestamp raw))
                          (signedLength (- n 32))
                          (message (fernetCopy raw 0 signedLength))
                          (receivedTag (fernetCopy raw signedLength 32))
                          (signingKey (fernetCopy keyBytes 0 16))
                          (encryptionKey (fernetCopy keyBytes 16 16))
                          (expectedTag (h/hmacSha256 signingKey message))]
                      (if (< issued 0) (err "invalidToken")
                        (if (not (h/constantTimeEqual expectedTag receivedTag)) (err "authFailed")
                        (if (and (>= ttlSeconds 0) (< nowSeconds 0)) (err "expired")
                          (if (and (>= ttlSeconds 0)
                                (or (> issued nowSeconds) (> (- nowSeconds issued) ttlSeconds)))
                            (err "expired")
                          (let [(iv (fernetCopy raw 9 16))
                                (ciphertext (fernetCopy raw 25 (- signedLength 25)))]
                            (mt (aes/aesCbcDecrypt encryptionKey iv ciphertext)
                              ((ok plaintext) (ok plaintext))
                              ((err _) (err "invalidToken"))))))))))))))))))
