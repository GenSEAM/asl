(module asl-text/case
  :x [splitWords toCamel toPascal toKebab toSnake]
  :i [])

fn isUpper c: String -> Bool
  (and (= c (stringUpper c)) (!= c (stringLower c)))

fn isLower c: String -> Bool
  (and (= c (stringLower c)) (!= c (stringUpper c)))

fn isDigit c: String -> Bool
  (stringContains? "0123456789" c)

fn isSep c: String -> Bool
  (or (= c "_") (= c "-") (= c " ") (= c "\t") (= c "\n") (= c "\r"))

fn lastChar s: String -> String
  (optionOr (stringSlice s (- (stringLength s) 1) (stringLength s)) "")

fn dropLast s: String -> String
  (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")

fn flush st: (Pair (List String) String) -> (Pair (List String) String)
  (let [(done (pairFirst st)) (cur (pairSecond st))]
    (if (stringEmpty? cur)
      st
      (pair (cons cur done) "")))

fn step st: (Pair (List String) String) c: String -> (Pair (List String) String)
  (let [(done (pairFirst st)) (cur (pairSecond st))]
    (if (isSep c)
      (flush st)
      (if (isDigit c)
        (pair done (str cur c))
        (if (isUpper c)
          (if (and (not (stringEmpty? cur)) (isLower (lastChar cur)))
            (pair (cons cur done) c)
            (pair done (str cur c)))
          (if (isLower c)
            (if (and (>= (stringLength cur) 2) (isUpper (lastChar cur)))
              (pair (cons (dropLast cur) done) (str (lastChar cur) c))
              (pair done (str cur c)))
            (flush st))))))

fn splitWords s: String -> (List String)
  (let [(st (fold (fn [(acc (Pair (List String) String)) (c String)] -> (Pair (List String) String)
                    (step acc c))
                  (pair (list) "")
                  (stringChars s)))]
    (listReverse (pairFirst (flush st))))

fn capWord w: String -> String
  (if (stringEmpty? w)
    ""
    (str (stringUpper (optionOr (stringSlice w 0 1) ""))
         (stringLower (optionOr (stringSlice w 1 (stringLength w)) ""))))

fn camelJoin words: (List String) -> String
  (pairFirst
    (fold (fn [(acc (Pair String Int64)) (w String)] -> (Pair String Int64)
            (let [(txt (pairFirst acc)) (i (pairSecond acc))]
              (pair (str txt (if (= i 0) (stringLower w) (capWord w))) (+ i 1))))
          (pair "" 0)
          words))

fn pascalJoin words: (List String) -> String
  (stringJoin (map capWord words) "")

fn toCamel s: String -> String
  (camelJoin (splitWords s))

fn toPascal s: String -> String
  (pascalJoin (splitWords s))

fn toKebab s: String -> String
  (stringJoin (map stringLower (splitWords s)) "-")

fn toSnake s: String -> String
  (stringJoin (map stringLower (splitWords s)) "_")
