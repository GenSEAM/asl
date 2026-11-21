(module asl-text/queryString :x [parseQuery buildQuery urlEncode urlDecode] :i [])

(schema DecState (:f out String) (:f pend String))

fn hexVal c: String -> Int64
  (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) -1)

fn isHex c: String -> Bool
  (>= (hexVal c) 0)

fn asciiChar code: Int64 -> (Option String)
  (if (and (>= code 32) (<= code 126))
    (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- code 32) (- code 31))
    (none))

fn decFlush st: DecState -> DecState
  (with st :out (str st.out st.pend) :pend "")

fn decStep st: DecState c: String -> DecState
  (if (stringEmpty? st.pend)
    (if (= c "+")
      (with st :out (str st.out " "))
      (if (= c "%")
        (with st :pend "%")
        (with st :out (str st.out c))))
    (if (and (< (stringLength st.pend) 3) (isHex c))
      (let [(p2 (str st.pend c))]
        (if (= (stringLength p2) 3)
          (let [(code (+ (* 16 (hexVal (optionOr (stringSlice p2 1 2) "")))
                         (hexVal (optionOr (stringSlice p2 2 3) ""))))]
            (with st :out (str st.out (optionOr (asciiChar code) p2)) :pend ""))
          (with st :pend p2)))
      (decStep (decFlush st) c)))

fn urlDecode s: String -> String
  (let [(st (fold decStep (DecState :out "" :pend "") (stringChars s)))]
    (str st.out st.pend))

fn urlEncode s: String -> String
  (fold (fn [(acc String) (c String)] -> String
          (str acc
            (if (= c " ")
              "+"
              (match (stringIndexOf "!\"#$%&'()*+,/:;<=>?@[\\]^`{|}" c)
                ((some i) (optionOr (stringSlice "%21%22%23%24%25%26%27%28%29%2A%2B%2C%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E%60%7B%7C%7D" (* i 3) (+ (* i 3) 3)) c))
                ((none) c)))))
        ""
        (stringChars s))

fn splitFirst s: String sep: String -> (Pair String String)
  (match (stringIndexOf s sep)
    ((some i) (pair (optionOr (stringSlice s 0 i) "")
                    (optionOr (stringSlice s (+ i (stringLength sep)) (stringLength s)) "")))
    ((none) (pair s "")))

fn parseQuery s: String -> (List (Pair String String))
  (map (fn [(p String)] -> (Pair String String)
         (let [(kv (splitFirst p "="))]
           (pair (urlDecode (pairFirst kv))
                 (urlDecode (pairSecond kv)))))
       (filter (fn [(p String)] -> Bool (not (stringEmpty? p)))
               (stringSplit s "&")))

fn buildQuery pairs: (List (Pair String String)) -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String
                     (str (urlEncode (pairFirst p)) "=" (urlEncode (pairSecond p))))
                   pairs)
              "&")
