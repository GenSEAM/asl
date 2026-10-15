(module jsFixtures/text :x [main])

fn ! main -> Int64
  (let [(s "héllo, wörld")]
    (do (println (str (stringLength s) " " (stringSlice s 1 3) " " (stringIndexOf s "w") " " (stringUpper s)))
        (println (str (stringSplit "a,b,,c" ",") " " (stringJoin ["x" "y"] "-") " " (stringReplace s "l" "L") " " (stringTrim "  t  ") " " (stringReverse "abc")))
        (println (str (/ -7 2) " " (mod -7 2) " " (/ 7.0 2.0) " " 2.0 " " (sqrt 2.0) " " (< "a" "b") " " (listSort [3 1 2]) " " (= [1 2] [1 2])))
        0))
