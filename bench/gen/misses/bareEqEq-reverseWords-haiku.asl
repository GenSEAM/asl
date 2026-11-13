fn joinWord cur: String res: String -> String
  (cond
    ((= cur "") res)
    ((= res "") cur)
    (else (stringConcat (stringConcat cur " ") res)))

fn scanWords s: String i: Int64 cur: String res: String -> String
  (match (stringSlice s i (+ i 1))
    ((some c)
      (cond
        ((= c " ") (scanWords s (+ i 1) "" (joinWord cur res)))
        (else (scanWords s (+ i 1) (stringConcat cur c) res))))
    ((none) (joinWord cur res)))

fn reverseWords text: String -> String
  (scanWords text 0 "" "")
