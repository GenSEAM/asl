fn reverseWords text: String -> String
  (stringJoin (listReverse (filter (fn [w] (not (stringEmpty? w))) (stringSplit text " "))) " ")
