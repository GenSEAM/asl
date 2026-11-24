(module asl-text/tests/percentTest
  :x [runTests]
  :i [(asl-text/percent :a pc)])

fn testEncode -> Bool
  (do (assert (= (pc/percentEncode "a b&c") "a%20b%26c") "space and ampersand encode")
      (assert (= (pc/percentEncode "a~b-c_d.e") "a~b-c_d.e") "unreserved pass through")
      (assert (= (pc/percentEncode "Az09") "Az09") "alnum pass through")
      (assert (= (pc/percentEncode "%") "%25") "percent encodes")
      (assert (= (pc/percentEncode "/") "%2F") "slash encodes")
      true)

fn testCyrillic -> Bool
  (let [(s "Привет, мир")]
    (match (pc/percentDecode (pc/percentEncode s))
      ((ok back) (do (assert (= back s) "cyrillic round trip")
                     (assert (= (pc/percentEncode "П") "%D0%9F") "cyrillic bytes uppercase hex")
                     true))
      ((err _) false)))

fn testBadEscape -> Bool
  (match (pc/percentDecode "%zz")
    ((err _) true)
    ((ok _) false))

fn testTruncatedUtf8 -> Bool
  (match (pc/percentDecode "%E2%82")
    ((err _) true)
    ((ok _) false))

fn testPlusLiteral -> Bool
  (match (pc/percentDecode "a+b")
    ((ok v) (= v "a+b"))
    ((err _) false))

fn testDecodeBasic -> Bool
  (match (pc/percentDecode "a%20b%26c")
    ((ok v) (= v "a b&c"))
    ((err _) false))

fn testForm -> Bool
  (= (pc/formEncode (cons (pair "a" "1") (cons (pair "b" "x y") (list))))
     "a=1&b=x%20y")

fn runTests -> Bool
  (and (testEncode)
       (testCyrillic)
       (testBadEscape)
       (testTruncatedUtf8)
       (testPlusLiteral)
       (testDecodeBasic)
       (testForm))
