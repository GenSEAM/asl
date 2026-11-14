fn joinWord cur: String acc: String -> String
  (cond
    ((= cur "") acc)
    ((= acc "") cur)
    (else (str (str cur " ") acc)))

fn scanWords text: String i: Int64 cur: String acc: String -> String
  (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
    (cond
      ((= c "") (joinWord cur acc))
      ((= c " ") (scanWords text (+ i 1) "" (joinWord cur acc)))
      (else (scanWords text (+ i 1) (str cur c) acc))))

fn reverseWords text: String -> String
  (scanWords text 0 "" "")
