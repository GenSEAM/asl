(module asl-text/slug :x [slugify] :i [])

fn isLetter c: String -> Bool
  (or (= c "a") (= c "b") (= c "c") (= c "d") (= c "e") (= c "f") (= c "g") (= c "h") (= c "i") (= c "j") (= c "k") (= c "l") (= c "m") (= c "n") (= c "o") (= c "p") (= c "q") (= c "r") (= c "s") (= c "t") (= c "u") (= c "v") (= c "w") (= c "x") (= c "y") (= c "z"))

fn isDigit c: String -> Bool
  (or (= c "0") (= c "1") (= c "2") (= c "3") (= c "4") (= c "5") (= c "6") (= c "7") (= c "8") (= c "9"))

fn foldCase c: String -> String
  (if (= c "A") "a" (if (= c "B") "b" (if (= c "C") "c" (if (= c "D") "d" (if (= c "E") "e" (if (= c "F") "f" (if (= c "G") "g" (if (= c "H") "h" (if (= c "I") "i" (if (= c "J") "j" (if (= c "K") "k" (if (= c "L") "l" (if (= c "M") "m" (if (= c "N") "n" (if (= c "O") "o" (if (= c "P") "p" (if (= c "Q") "q" (if (= c "R") "r" (if (= c "S") "s" (if (= c "T") "t" (if (= c "U") "u" (if (= c "V") "v" (if (= c "W") "w" (if (= c "X") "x" (if (= c "Y") "y" (if (= c "Z") "z" c))))))))))))))))))))))))))

fn accentFold c: String -> String
  (if (or (= c "à") (= c "á") (= c "â") (= c "ã") (= c "ä") (= c "å") (= c "À") (= c "Á") (= c "Â") (= c "Ã") (= c "Ä") (= c "Å")) "a"
    (if (or (= c "æ") (= c "Æ")) "ae"
      (if (or (= c "ç") (= c "Ç")) "c"
        (if (or (= c "è") (= c "é") (= c "ê") (= c "ë") (= c "È") (= c "É") (= c "Ê") (= c "Ë")) "e"
          (if (or (= c "ì") (= c "í") (= c "î") (= c "ï") (= c "Ì") (= c "Í") (= c "Î") (= c "Ï")) "i"
            (if (or (= c "ð") (= c "Ð")) "d"
              (if (or (= c "ñ") (= c "Ñ")) "n"
                (if (or (= c "ò") (= c "ó") (= c "ô") (= c "õ") (= c "ö") (= c "ø") (= c "Ò") (= c "Ó") (= c "Ô") (= c "Õ") (= c "Ö") (= c "Ø")) "o"
                  (if (or (= c "œ") (= c "Œ")) "oe"
                    (if (or (= c "ù") (= c "ú") (= c "û") (= c "ü") (= c "Ù") (= c "Ú") (= c "Û") (= c "Ü")) "u"
                      (if (or (= c "ý") (= c "ÿ") (= c "Ý") (= c "Ÿ")) "y"
                        (if (or (= c "þ") (= c "Þ")) "th"
                          (if (= c "ß") "ss" "")))))))))))))

fn sepOr acc: String sep: String -> String
  (if (= acc "")
    ""
    (if (and (>= (stringLength acc) (stringLength sep))
             (= (optionOr (stringSlice acc (- (stringLength acc) (stringLength sep)) (stringLength acc)) "") sep))
      acc
      (str acc sep)))

fn trimEnd acc: String sep: String -> String
  (if (and (>= (stringLength acc) (stringLength sep))
           (= (optionOr (stringSlice acc (- (stringLength acc) (stringLength sep)) (stringLength acc)) "") sep))
    (optionOr (stringSlice acc 0 (- (stringLength acc) (stringLength sep))) "")
    acc)

fn joinHead parts: (List String) sep: String -> String
  (let [(n (listLength parts))]
    (let [(j (fold (fn [(acc (Pair String Int64)) (p String)] -> (Pair String Int64)
                     (let [(txt (pairFirst acc)) (cnt (pairSecond acc))]
                       (if (>= cnt (- n 1))
                         acc
                         (if (= cnt 0)
                           (pair p 1)
                           (pair (str txt sep p) (+ cnt 1))))))
                   (pair "" 0)
                   parts))]
      (pairFirst j)))

fn trimPartial s: String sep: String -> String
  (let [(n (stringLength s)) (m (stringLength sep))
        (best (fold (fn [(bk Int64) (ic (Pair Int64 String))] -> Int64
                      (let [(k (+ (pairFirst ic) 1))]
                        (if (and (< k m) (<= k n)
                                 (= (optionOr (stringSlice s (- n k) n) "")
                                    (optionOr (stringSlice sep 0 k) "")))
                          k
                          bk)))
                    0
                    (enumerate (stringChars sep))))]
    (optionOr (stringSlice s 0 (- n best)) s))

fn cutAt trimmed: String sep: String maxLen: Int64 -> String
  (if (<= (stringLength trimmed) maxLen)
    trimmed
    (let [(cut (optionOr (stringSlice trimmed 0 maxLen) ""))
          (parts (stringSplit cut sep))]
      (if (<= (listLength parts) 1)
        (trimPartial cut sep)
        (joinHead parts sep))))

fn foldChar acc: String c: String sep: String -> String
  (let [(repl (accentFold c))]
    (if (= repl "")
      (let [(ch (foldCase c))]
        (if (or (isLetter ch) (isDigit ch))
          (str acc ch)
          (sepOr acc sep)))
      (str acc repl)))

fn slugify s: String sep: String maxLen: Int64 -> String
  (let [(acc (fold (fn [(a String) (c String)] -> String (foldChar a c sep)) "" (stringChars s)))]
    (cutAt (trimEnd acc sep) sep maxLen))
