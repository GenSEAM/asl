(module asl-know/examples/coreString :x [shout selfTest] :i [])

fn shout s: String -> String
  (let [(words (stringSplit (stringTrim s) " "))
        (n (optionOr (stringToInt64 "12") 0))]
    (str (stringUpper (stringJoin (listReverse words) "-")) "!" n (stringLength "ab")))

fn selfTest -> Bool
  (and (= (shout " a b ") "B-A!122") (stringContains? "hello" "ell") (= (stringReplace "a.b" "." "/") "a/b")
       (= (stringSlice "hello" 1 3) (some "el")))
