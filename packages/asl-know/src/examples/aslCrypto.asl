(module asl-know/examples/aslCrypto :x [signHex selfTest] :i [(asl-crypto/hmac :a h)])

fn signHex key: String msg: String -> String
  (h/hmacSha256Hex (stringToBytes key) (stringToBytes msg))

fn selfTest -> Bool
  (= (signHex "key" "The quick brown fox jumps over the lazy dog") "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
