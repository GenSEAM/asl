(module asl-text/tests/distanceTest
  :x [runTests]
  :i [(asl-text/distance :a d)])

fn testBasic -> Bool
  (do (assert (= (d/levenshtein "kitten" "sitting") 3) "kitten/sitting is 3")
      (assert (= (d/levenshtein "" "abc") 3) "empty/abc is 3")
      (assert (= (d/levenshtein "abc" "abc") 0) "equal is 0")
      true)

fn testCyrillic -> Bool
  (do (assert (= (d/levenshtein "привет" "привед") 1) "one Cyrillic substitution is 1")
      true)

fn testPrefix -> Bool
  (do (assert (= (d/commonPrefixLength "abc" "abd") 2) "prefix abc/abd is 2")
      (assert (= (d/commonPrefixLength "abc" "abc") 3) "prefix equal is 3")
      (assert (= (d/commonPrefixLength "" "abc") 0) "prefix empty is 0")
      true)

fn testNearest -> Bool
  (let [(r (d/nearest "symbl" (list "symbol" "sym" "start") 5))]
    (do (assert (= (listLength r) 2) "symbol and sym are within range")
        (assert (= (optionOr (listGet r 0) "") "symbol") "symbol is first")
        (assert (= (optionOr (listGet r 1) "") "sym") "sym is second")
        true))

fn testNearestNone -> Bool
  (do (assert (= (listLength (d/nearest "zzzzz" (list "symbol" "sym" "start") 5)) 0) "nothing within range")
      true)

fn testNearestLimit -> Bool
  (let [(r (d/nearest "symbl" (list "symbol" "sym" "start") 1))]
    (do (assert (= (listLength r) 1) "limit 1 keeps one")
        (assert (= (optionOr (listGet r 0) "") "symbol") "limit 1 keeps symbol")
        true))

fn repeat10 s: String -> String
  (fold (fn [acc _] (stringConcat acc s)) "" (stringChars "0123456789"))

fn base30 -> String
  "abcdefghijklmnopqrstuvwxyz0123"

fn testLong -> Bool
  (let [(a (repeat10 (base30)))
        (b (repeat10 (base30)))]
    (do (assert (= (stringLength a) 300) "built a 300-char string")
        (assert (= (d/levenshtein a b) 0) "300 equal is 0")
        (assert (= (d/levenshtein a (stringConcat "x" b)) 1) "300 vs 301 is 1")
        true))

fn runTests -> Bool
  (and (testBasic)
       (testCyrillic)
       (testPrefix)
       (testNearest)
       (testNearestNone)
       (testNearestLimit)
       (testLong))
