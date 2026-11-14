fn romanFrom n: Int64 table: (List (Pair Int64 String)) -> String
  (match (listHead table)
    ((none) "")
    ((some p)
      (if (>= n (pairFirst p))
        (str (pairSecond p) (romanFrom (- n (pairFirst p)) table))
        (romanFrom n (listDrop table 1)))))

fn romanNumeral n: Int64 -> String
  (romanFrom n (list (pair 1000 "M") (pair 900 "CM") (pair 500 "D") (pair 400 "CD") (pair 100 "C") (pair 90 "XC") (pair 50 "L") (pair 40 "XL") (pair 10 "X") (pair 9 "IX") (pair 5 "V") (pair 4 "IV") (pair 1 "I")))
