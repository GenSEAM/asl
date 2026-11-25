(module asl-text/tests/romanTest :x [runTests] :i [(asl-text/roman :a rm)])

fn roundTripRange i: Int64 end: Int64 -> Bool
  (if (> i end) true
      (match (rm/toRoman i)
          ((err e) false)
          ((ok s)
           (match (rm/fromRoman s)
               ((err e) false)
               ((ok v)
                (if (= v i)
                    (roundTripRange (+ i 1) end)
                    false))))))

fn testToRoman -> Bool
  (do (assert (= (rm/toRoman 1) (ok "I")) "1 is I")
      (assert (= (rm/toRoman 4) (ok "IV")) "4 is IV")
      (assert (= (rm/toRoman 9) (ok "IX")) "9 is IX")
      (assert (= (rm/toRoman 14) (ok "XIV")) "14 is XIV")
      (assert (= (rm/toRoman 40) (ok "XL")) "40 is XL")
      (assert (= (rm/toRoman 90) (ok "XC")) "90 is XC")
      (assert (= (rm/toRoman 400) (ok "CD")) "400 is CD")
      (assert (= (rm/toRoman 900) (ok "CM")) "900 is CM")
      (assert (= (rm/toRoman 1994) (ok "MCMXCIV")) "1994 is MCMXCIV")
      (assert (= (rm/toRoman 3999) (ok "MMMCMXCIX")) "3999 is MMMCMXCIX")
      (assert (err? (rm/toRoman 0)) "0 is out of range")
      (assert (err? (rm/toRoman 4000)) "4000 is out of range")
      (assert (err? (rm/toRoman -1)) "negative is out of range")
      true)

fn testFromRoman -> Bool
  (do (assert (= (rm/fromRoman "I") (ok 1)) "I is 1")
      (assert (= (rm/fromRoman "IV") (ok 4)) "IV is 4")
      (assert (= (rm/fromRoman "IX") (ok 9)) "IX is 9")
      (assert (= (rm/fromRoman "MCMXCIV") (ok 1994)) "MCMXCIV is 1994")
      (assert (= (rm/fromRoman "MMMCMXCIX") (ok 3999)) "MMMCMXCIX is 3999")
      (assert (err? (rm/fromRoman "")) "empty is err")
      (assert (err? (rm/fromRoman "IIII")) "IIII is non-canonical")
      (assert (err? (rm/fromRoman "VX")) "VX is non-canonical")
      (assert (err? (rm/fromRoman "ABC")) "ABC has invalid chars")
      (assert (err? (rm/fromRoman "MMMM")) "MMMM is out of range")
      true)

fn testRoundTrip -> Bool
  (do (assert (roundTripRange 1 3999) "round-trip 1..3999")
      true)

fn runTests -> Bool
  (and (testToRoman) (testFromRoman) (testRoundTrip))
