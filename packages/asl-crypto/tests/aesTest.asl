(module asl-crypto/aesTest
  :x [runTests]
  :i [(asl-crypto/aes :a aes) (asl-crypto/hmac :a crypto)])

fn ! gcmCase4 -> String
  (let [(key (mt (crypto/hexToBytes "feffe9928665731c6d6a8f9467308308") ((ok v) v) ((err _) (bytesAlloc 0))))
        (iv (mt (crypto/hexToBytes "cafebabefacedbaddecaf888") ((ok v) v) ((err _) (bytesAlloc 0))))
        (aad (mt (crypto/hexToBytes "feedfacedeadbeeffeedfacedeadbeefabaddad2") ((ok v) v) ((err _) (bytesAlloc 0))))
        (plain (mt (crypto/hexToBytes "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39") ((ok v) v) ((err _) (bytesAlloc 0))))]
    (mt (aes/aesGcmEncrypt key iv aad plain)
      ((err _) "ERR")
      ((ok ciphertextAndTag) (crypto/bytesToHex ciphertextAndTag))))

fn ! cbcFullVector -> Bool
  (let [(key (mt (crypto/hexToBytes "2b7e151628aed2a6abf7158809cf4f3c") ((ok v) v) ((err _) (bytesAlloc 0))))
        (iv (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f") ((ok v) v) ((err _) (bytesAlloc 0))))
        (plain (mt (crypto/hexToBytes "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710") ((ok v) v) ((err _) (bytesAlloc 0))))]
    (mt (aes/aesCbcEncrypt key iv plain)
      ((err _) false)
      ((ok ciphertext) (= (optionOr (stringSlice (crypto/bytesToHex ciphertext) 0 128) "") "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b273bed6b8e3c1743b7116e69e222295163ff1caa1681fac09120eca307586e1a7"))))

fn ! ctrFullVector -> Bool
  (let [(key (mt (crypto/hexToBytes "2b7e151628aed2a6abf7158809cf4f3c") ((ok v) v) ((err _) (bytesAlloc 0))))
        (iv (mt (crypto/hexToBytes "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff") ((ok v) v) ((err _) (bytesAlloc 0))))
        (plain (mt (crypto/hexToBytes "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710") ((ok v) v) ((err _) (bytesAlloc 0))))]
    (mt (aes/aesCtrCrypt key iv plain)
      ((err _) false)
      ((ok ciphertext) (= (crypto/bytesToHex ciphertext) "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee"))))

fn ! runTests -> Bool
  (let [(key128 (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f") ((ok v) v) ((err _) (bytesAlloc 0))))
        (key192 (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f1011121314151617") ((ok v) v) ((err _) (bytesAlloc 0))))
        (key256 (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f") ((ok v) v) ((err _) (bytesAlloc 0))))
        (ctrKey (mt (crypto/hexToBytes "2b7e151628aed2a6abf7158809cf4f3c") ((ok v) v) ((err _) (bytesAlloc 0))))
        (ctrIv (mt (crypto/hexToBytes "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff") ((ok v) v) ((err _) (bytesAlloc 0))))
        (ctrPlain (mt (crypto/hexToBytes "6bc1bee22e409f96e93d7e117393172a") ((ok v) v) ((err _) (bytesAlloc 0))))
        (fernetAesKey (mt (crypto/hexToBytes "f790b0a226bc96a92de49b5e9c05e1ee") ((ok v) v) ((err _) (bytesAlloc 0))))
        (fernetIv (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f") ((ok v) v) ((err _) (bytesAlloc 0))))
        (fernetCipher (mt (crypto/hexToBytes "2d36d5ca46556299fde13008633804b2") ((ok v) v) ((err _) (bytesAlloc 0))))
        (cbcPlain (mt (crypto/hexToBytes "6bc1bee22e409f96e93d7e117393172a") ((ok v) v) ((err _) (bytesAlloc 0))))
        (cbcIv (mt (crypto/hexToBytes "000102030405060708090a0b0c0d0e0f") ((ok v) v) ((err _) (bytesAlloc 0))))
        (zeroKey (bytesAlloc 16))
        (zeroIv (bytesAlloc 12))
        (zeroPlain (bytesAlloc 16))
        (zeroPlain32 (bytesAlloc 32))
        (empty (bytesAlloc 0))
        (nistGcmKey (mt (crypto/hexToBytes "feffe9928665731c6d6a8f9467308308") ((ok v) v) ((err _) (bytesAlloc 0))))
        (nistGcmIv (mt (crypto/hexToBytes "cafebabefacedbaddecaf888") ((ok v) v) ((err _) (bytesAlloc 0))))
        (nistGcmAad (mt (crypto/hexToBytes "feedfacedeadbeeffeedfacedeadbeefabaddad2") ((ok v) v) ((err _) (bytesAlloc 0))))
        (nistGcmPlain (mt (crypto/hexToBytes "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255") ((ok v) v) ((err _) (bytesAlloc 0))))
        (plain (mt (crypto/hexToBytes "00112233445566778899aabbccddeeff") ((ok v) v) ((err _) (bytesAlloc 0))))]
    (let [(schedule128 (mt (aes/aesExpandKey key128) ((ok v) v) ((err _) (bytesAlloc 0))))
          (enc128 (mt (aes/aesEncryptBlock key128 plain) ((ok v) v) ((err _) (bytesAlloc 0))))
          (enc192 (mt (aes/aesEncryptBlock key192 plain) ((ok v) v) ((err _) (bytesAlloc 0))))
          (enc256 (mt (aes/aesEncryptBlock key256 plain) ((ok v) v) ((err _) (bytesAlloc 0))))]
      (do
        (assert (= (crypto/bytesToHex enc128) "69c4e0d86a7b0430d8cdb78070b4c55a") (crypto/bytesToHex enc128))
        (assert (= (crypto/bytesToHex enc192) "dda97ca4864cdfe06eaf70a0ec0d7191") "FIPS AES-192 block")
        (assert (= (crypto/bytesToHex enc256) "8ea2b7ca516745bfeafc49904b496089") (crypto/bytesToHex enc256))
        (assert (= (crypto/bytesToHex (mt (aes/aesCtrCrypt ctrKey ctrIv ctrPlain) ((ok v) v) ((err _) (bytesAlloc 0)))) "874d6191b620e3261bef6864990db6ce") "NIST AES-CTR first block")
        (assert (= (crypto/bytesToHex (mt (aes/aesDecryptBlock fernetAesKey fernetCipher) ((ok v) v) ((err _) (bytesAlloc 0)))) "68646e6f6b0e0d0c0302010007060504") "AES Fernet block")
        (assert (= (crypto/bytesToHex (mt (aes/aesCbcDecrypt fernetAesKey fernetIv fernetCipher) ((ok v) v) ((err _) (bytesAlloc 0)))) "68656c6c6f") "CBC Fernet padding and plaintext")
        (let [(cbcCipher (mt (aes/aesCbcEncrypt ctrKey cbcIv cbcPlain) ((ok v) v) ((err _) (bytesAlloc 0))))
              (firstBlock (bytesAlloc 16))
              (copy (fn [copy i] -> Unit (if (< i 16) (do (bytesSet firstBlock i (bytesGet cbcCipher i)) (copy copy (+ i 1))) ())))
              (badIv (bytesAlloc 16))
              (copyIv (fn [copyIv i] -> Unit (if (< i 16) (do (bytesSet badIv i (bytesGet fernetIv i)) (copyIv copyIv (+ i 1))) ())))]
          (do (copy copy 0) (copyIv copyIv 0)
            (assert (= (crypto/bytesToHex firstBlock) "7649abac8119b246cee98e9b12e9197d") "NIST AES-CBC first block")
            (assert (= (crypto/bytesToHex (mt (aes/aesCbcDecrypt ctrKey cbcIv cbcCipher) ((ok v) v) ((err _) (bytesAlloc 0)))) "6bc1bee22e409f96e93d7e117393172a") "CBC encrypt/decrypt PKCS#7 roundtrip")
            (bytesSet badIv 15 (^ (bytesGet badIv 15) 1))
            (assert (mt (aes/aesCbcDecrypt fernetAesKey badIv fernetCipher) ((ok _) false) ((err e) (= e "badPadding"))) "CBC malformed PKCS#7 returns badPadding")
            true))
        (let [(gcmEmpty (mt (aes/aesGcmEncrypt zeroKey zeroIv empty empty) ((ok v) v) ((err _) (bytesAlloc 0))))
              (gcmBlock (mt (aes/aesGcmEncrypt zeroKey zeroIv empty zeroPlain) ((ok v) v) ((err _) (bytesAlloc 0))))]
          (do
            (assert (= (crypto/bytesToHex gcmEmpty) "58e2fccefa7e3061367f1d57a4e7455a") "GCM test case 1 empty message and tag")
            (assert (= (crypto/bytesToHex gcmBlock) "0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf") "GCM test case 2 ciphertext and tag")
            (assert (= (crypto/bytesToHex (mt (aes/aesGcmEncrypt zeroKey zeroIv empty zeroPlain32) ((ok v) v) ((err _) (bytesAlloc 0)))) "0388dace60b6a392f328c2b971b2fe78f795aaab494b5923f7fd89ff948bc1e040490af4805606b2a3a2e793e3500066") "GCM test case 3 multiblock ciphertext and tag")
            (assert (= (crypto/bytesToHex (mt (aes/aesGcmEncrypt nistGcmKey nistGcmIv nistGcmAad nistGcmPlain) ((ok v) v) ((err _) (bytesAlloc 0)))) "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985da80ce830cfda02da2a218a1744f4c76") "GCM long vector with partial AAD and tag")
            (assert (= (gcmCase4) "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47") (str "GCM McGrew-Viega test case 4: " (gcmCase4)))
            (assert (= (crypto/bytesToHex (mt (aes/aesGcmDecrypt nistGcmKey nistGcmIv nistGcmAad (mt (aes/aesGcmEncrypt nistGcmKey nistGcmIv nistGcmAad nistGcmPlain) ((ok v) v) ((err _) (bytesAlloc 0)))) ((ok v) v) ((err _) (bytesAlloc 0)))) (crypto/bytesToHex nistGcmPlain)) "GCM long vector verified decrypt")
            (assert (= (crypto/bytesToHex (mt (aes/aesGcmDecrypt zeroKey zeroIv empty gcmBlock) ((ok v) v) ((err _) (bytesAlloc 0)))) "00000000000000000000000000000000") "GCM verified decrypt")
            (bytesSet gcmBlock 16 (^ (bytesGet gcmBlock 16) 1))
            (assert (mt (aes/aesGcmDecrypt zeroKey zeroIv empty gcmBlock) ((ok _) false) ((err e) (= e "authFailed"))) "GCM wrong tag returns authFailed")
            true))
        (assert (= (crypto/bytesToHex (mt (aes/aesDecryptBlock key128 enc128) ((ok v) v) ((err _) (bytesAlloc 0)))) "00112233445566778899aabbccddeeff") "AES-128 inverse")
        (assert (= (crypto/bytesToHex (mt (aes/aesDecryptBlock key192 enc192) ((ok v) v) ((err _) (bytesAlloc 0)))) "00112233445566778899aabbccddeeff") "AES-192 inverse")
        (assert (= (crypto/bytesToHex (mt (aes/aesDecryptBlock key256 enc256) ((ok v) v) ((err _) (bytesAlloc 0)))) "00112233445566778899aabbccddeeff") "AES-256 inverse")
        (assert (mt (aes/aesEncryptBlock key128 (bytesAlloc 15)) ((ok _) false) ((err _) true)) "bad block length rejected")
        (assert (mt (aes/aesCtrCrypt (bytesAlloc 15) ctrIv empty) ((ok _) false) ((err _) true)) "CTR rejects an invalid AES key even for empty input")
        (assert (= (gcmCase4) "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47") (str "GCM McGrew-Viega test case 4: " (gcmCase4)))
        (assert (cbcFullVector) "NIST AES-CBC four-block vector")
        (assert (ctrFullVector) "NIST AES-CTR four-block vector")
        true)))
