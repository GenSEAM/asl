(module asl-crypto/fernetTest
  :x [runTests]
  :i [(asl-crypto/fernet :a f) (asl-crypto/fernetFixture :a fixture)])

fn ! runTests -> Bool
  (let [(token (fixture/token))
        (tampered (stringReplace token "qDA==" "qEA=="))]
    (mt (f/fernetVerify (fixture/key) token 499162801 60)
      ((ok plaintext) (assert (= plaintext (stringToBytes (fixture/plaintext))) "spec Fernet token plaintext matches"))
      ((err reason) (assert false (str "spec token failed: " reason))))
    (assert (err? (f/fernetVerify (fixture/key) tampered 499162801 60)) "tampered Fernet token is rejected")
    (assert (err? (f/fernetVerify (fixture/key) token 499162861 60)) "expired Fernet token is rejected")
    true)
