(module asl-text/tests/queryStringTest :x [runTests] :i [(asl-text/queryString :a qs)])

fn nthPair p: (List (Pair String String)) n: Int64 -> (Pair String String)
  (match (listGet p n)
    ((none) (pair "" ""))
    ((some pr) pr))

fn testUrlEncode -> Bool
  (do (assert (= (qs/urlEncode "a b") "a+b") "space encodes to +")
      (assert (= (qs/urlEncode "a&b") "a%26b") "ampersand encodes")
      (assert (= (qs/urlEncode "a=b") "a%3Db") "equals encodes")
      (assert (= (qs/urlEncode "a+b") "a%2Bb") "plus encodes")
      (assert (= (qs/urlEncode "a%b") "a%25b") "percent encodes")
      (assert (= (qs/urlEncode "a/b") "a%2Fb") "slash encodes")
      (assert (= (qs/urlEncode "a~b-c_d.e") "a~b-c_d.e") "unreserved pass through")
      (assert (= (qs/urlEncode "Az09") "Az09") "alnum pass through")
      true)

fn testUrlDecode -> Bool
  (do (assert (= (qs/urlDecode "a+b") "a b") "plus decodes to space")
      (assert (= (qs/urlDecode "a%26b") "a&b") "percent-26 decodes to ampersand")
      (assert (= (qs/urlDecode "a%3Db") "a=b") "percent-3d decodes to equals")
      (assert (= (qs/urlDecode "a%20b") "a b") "percent-20 decodes to space")
      (assert (= (qs/urlDecode "a%2Bb") "a+b") "percent-2b decodes to plus")
      true)

fn testDecodeGeneral -> Bool
  (do (assert (= (qs/urlDecode "%41") "A") "percent-41 decodes to A")
      (assert (= (qs/urlDecode "%2b") "+") "lowercase percent-2b decodes to plus")
      (assert (= (qs/urlDecode "%zz") "%zz") "invalid escape kept literally")
      (assert (= (qs/urlDecode "a%2") "a%2") "truncated escape kept literally")
      (assert (= (pairSecond (nthPair (qs/parseQuery "a==b") 0)) "=b") "split at first equals only")
      true)

fn testParseSimple -> Bool
  (let [(p (qs/parseQuery "a=1&b=2"))]
    (do (assert (= (pairFirst (nthPair p 0)) "a") "first key is a")
        (assert (= (pairSecond (nthPair p 0)) "1") "first value is 1")
        (assert (= (pairFirst (nthPair p 1)) "b") "second key is b")
        (assert (= (pairSecond (nthPair p 1)) "2") "second value is 2")
        true))

fn testParseRepeatedKeys -> Bool
  (let [(p (qs/parseQuery "a=1&a=2&a=3"))]
    (do (assert (= (listLength p) 3) "three pairs kept")
        (assert (= (pairSecond (nthPair p 0)) "1") "first value is 1")
        (assert (= (pairSecond (nthPair p 1)) "2") "second value is 2")
        (assert (= (pairSecond (nthPair p 2)) "3") "third value is 3")
        true))

fn testParseNoValue -> Bool
  (let [(p (qs/parseQuery "key"))]
    (do (assert (= (pairFirst (nthPair p 0)) "key") "key is key")
        (assert (= (pairSecond (nthPair p 0)) "") "value is empty")
        true))

fn testParseEmptySegments -> Bool
  (do (assert (listEmpty? (qs/parseQuery "")) "empty query gives no pairs")
      (assert (listEmpty? (qs/parseQuery "&&")) "only separators give no pairs")
      (assert (= (listLength (qs/parseQuery "a=1&")) 1) "trailing ampersand dropped")
      (assert (= (listLength (qs/parseQuery "a=1&&b=2&")) 2) "empty middle segment dropped")
      (assert (= (pairSecond (nthPair (qs/parseQuery "a=1&&b=2&") 1)) "2") "second pair survives")
      true)

fn testParseEncoded -> Bool
  (let [(p (qs/parseQuery "a=hello%20world&b=x%2By"))]
    (do (assert (= (pairSecond (nthPair p 0)) "hello world") "value decoded")
        (assert (= (pairSecond (nthPair p 1)) "x+y") "value decoded with plus")
        true))

fn testParseEncodedLower -> Bool
  (let [(p (qs/parseQuery "a=%41%2b&b=a%26b%3dc"))]
    (do (assert (= (pairSecond (nthPair p 0)) "A+") "general and lowercase escapes decode")
        (assert (= (pairSecond (nthPair p 1)) "a&b=c") "encoded specials decode in value")
        true))

fn testBuildExact -> Bool
  (do (assert (= (qs/buildQuery (qs/parseQuery "a=1&b=2")) "a=1&b=2") "build joins in order")
      (assert (= (qs/buildQuery (qs/parseQuery "")) "") "empty list builds empty string")
      (assert (= (qs/buildQuery (qs/parseQuery "x+y=a%2Bb")) "x+y=a%2Bb") "build escapes space and plus")
      (assert (= (qs/buildQuery (qs/parseQuery "a=1&a=2")) "a=1&a=2") "repeated keys kept in build")
      true)

fn testRoundTrip -> Bool
  (let [(original "name=John+Doe&age=30&city=New%20York&name=Jane")
        (parsed (qs/parseQuery original))
        (rebuilt (qs/buildQuery parsed))]
    (do (assert (= (qs/parseQuery rebuilt) parsed) "round-trip parse(build(parse))")
        (assert (= rebuilt "name=John+Doe&age=30&city=New+York&name=Jane") "build canonicalizes %20 to +")
        true))

fn testRoundTripSpecials -> Bool
  (let [(original "q=a%26b%3Dc&x=hello+world&q=%25zz&k=&=v&u=%7e")
        (parsed (qs/parseQuery original))]
    (do (assert (= (qs/parseQuery (qs/buildQuery parsed)) parsed) "round-trip with encoded specials")
        (assert (= (pairSecond (nthPair parsed 3)) "") "empty value kept")
        (assert (= (pairFirst (nthPair parsed 4)) "") "empty key kept")
        (assert (= (pairSecond (nthPair parsed 5)) "~") "percent-7e decodes to tilde")
        true))

fn runTests -> Bool
  (and (testUrlEncode)
       (testUrlDecode)
       (testDecodeGeneral)
       (testParseSimple)
       (testParseRepeatedKeys)
       (testParseNoValue)
       (testParseEmptySegments)
       (testParseEncoded)
       (testParseEncodedLower)
       (testBuildExact)
       (testRoundTrip)
       (testRoundTripSpecials))
