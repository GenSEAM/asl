(module asl-text/roman :x [toRoman fromRoman] :i [])

fn romanHelper n: Int64 acc: String -> String
  (if (<= n 0) acc
      (if (>= n 1000) (romanHelper (- n 1000) (stringConcat acc "M"))
          (if (>= n 900) (romanHelper (- n 900) (stringConcat acc "CM"))
              (if (>= n 500) (romanHelper (- n 500) (stringConcat acc "D"))
                  (if (>= n 400) (romanHelper (- n 400) (stringConcat acc "CD"))
                      (if (>= n 100) (romanHelper (- n 100) (stringConcat acc "C"))
                          (if (>= n 90) (romanHelper (- n 90) (stringConcat acc "XC"))
                              (if (>= n 50) (romanHelper (- n 50) (stringConcat acc "L"))
                                  (if (>= n 40) (romanHelper (- n 40) (stringConcat acc "XL"))
                                      (if (>= n 10) (romanHelper (- n 10) (stringConcat acc "X"))
                                          (if (>= n 9) (romanHelper (- n 9) (stringConcat acc "IX"))
                                              (if (>= n 5) (romanHelper (- n 5) (stringConcat acc "V"))
                                                  (if (>= n 4) (romanHelper (- n 4) (stringConcat acc "IV"))
                                                      (romanHelper (- n 1) (stringConcat acc "I")))))))))))))))

fn toRoman n: Int64 -> (Result String String)
  (if (or (< n 1) (> n 3999))
      (err "toRoman: out of range 1..3999")
      (ok (romanHelper n "")))

fn charValue c: String -> Int64
  (if (= c "I") 1
      (if (= c "V") 5
          (if (= c "X") 10
              (if (= c "L") 50
                  (if (= c "C") 100
                      (if (= c "D") 500
                          (if (= c "M") 1000 0)))))))

fn parseAt cs: (List String) i: Int64 len: Int64 acc: Int64 -> Int64
  (if (>= i len) acc
      (let [(v (charValue (optionOr (listGet cs i) "")))]
        (if (>= (+ i 1) len)
            (+ acc v)
            (let [(nv (charValue (optionOr (listGet cs (+ i 1)) "")))]
              (if (< v nv)
                  (parseAt cs (+ i 1) len (- acc v))
                  (parseAt cs (+ i 1) len (+ acc v)))))))

fn fromRoman s: String -> (Result Int64 String)
  (let [(cs (stringChars s))
        (len (listLength cs))]
    (if (<= len 0)
        (err "fromRoman: empty string")
        (if (listAny? (fn [(c String)] -> Bool (= (charValue c) 0)) cs)
            (err "fromRoman: invalid character")
            (let [(v (parseAt cs 0 len 0))]
              (match (toRoman v)
                  ((err e) (err e))
                  ((ok r)
                   (if (= r s)
                       (ok v)
                       (err "fromRoman: non-canonical numeral"))))))))
