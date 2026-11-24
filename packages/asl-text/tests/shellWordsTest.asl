(module asl-text/tests/shellWordsTest :x [runTests] :i [(asl-text/shellWords :a sw)])

fn testSplit -> Bool
  (do (assert (= (sw/splitWords "a b  c") (ok (list "a" "b" "c"))) "plain words")
      (assert (= (sw/splitWords "'a b' c") (ok (list "a b" "c"))) "single quotes group")
      (assert (= (sw/splitWords "\"a b\" c") (ok (list "a b" "c"))) "double quotes group")
      (assert (= (sw/splitWords "a\\ b") (ok (list "a b"))) "backslash escapes a space")
      (assert (err? (sw/splitWords "'a")) "unterminated single quote is an err")
      true)

fn testJoin -> Bool
  (do (assert (= (sw/joinWords (list "a" "b c")) "a 'b c'") "space forces single quotes")
      (assert (= (sw/joinWords (list "a'b")) "\"a'b\"") "a single quote forces double quotes")
      (assert (= (sw/joinWords (list "")) "''") "empty word is quoted")
      true)

fn testRoundTrip -> Bool
  (let [(ws (list "a b" "c'd" "e\\f" "" "x\"y" "a'b\\c"))]
    (do (assert (= (sw/splitWords (sw/joinWords ws)) (ok ws)) "join then split returns the words")
        true))

fn runTests -> Bool
  (and (testSplit) (testJoin) (testRoundTrip))
