(module asl-parser/smoke
  :d "Smoke driver for the asl-parser execution harness."
  :x [run-smoke len-list]
  :i [(lexer :a lex)])

(df bool-yes [(b Bool)] -> String
  :d "A Bool as the letters T or F."
  (if b "T" "F"))

(df kind-of [(s String)] -> String
  :d "Tag name of the kind of the first token of a string."
  (mt (lex/token-kind s)
    ((lex/tok-lparen)   "LPAREN")
    ((lex/tok-rparen)   "RPAREN")
    ((lex/tok-lbracket) "LBRACKET")
    ((lex/tok-rbracket) "RBRACKET")
    ((lex/tok-symbol _) "SYMBOL")
    ((lex/tok-keyword _) "KEYWORD")
    ((lex/tok-string _) "STRING")
    ((lex/tok-int _)    "INT")
    ((lex/tok-eof)      "EOF")))

(df len-list [(xs (List Int64))] -> Int64
  :d "Structural list length, by recursion."
  (mt xs
    ((list)     0)
    ((cons _ t) (+ 1 (len-list t)))))

(df run-smoke [] -> String
  :d "Exercise every verified builtin plus match, let, recursion and pair."
  (let [(l  (string-length "hello"))
        (sl (mt (string-slice "hello" 1 3) ((some v) v) ((none) "")))
        (io (mt (string-index-of "hello" "l") ((some v) v) ((none) 0)))
        (ct (string-contains? "hello" "ell"))
        (sw (string-starts-with? "hello" "he"))
        (sp (string-split "a,b" ","))
        (jn (string-join sp ":"))
        (ch (string-join (string-chars "ab") ""))
        (n  (mt (string-to-int64 "7") ((some v) v) ((none) 0)))
        (fs (string-from-int64 n))
        (cc (str "x" "y"))
        (cs (list-cons 1 (list 2)))
        (ap (list-append (list 1) (list 2)))
        (hd (mt (list-head (list 9 8)) ((some v) v) ((none) 0)))
        (tl (mt (list-tail (list 9 8)) ((some v) v) ((none) (list))))
        (em (list-empty? (list)))
        (rv (list-reverse (list 1 2 3)))
        (mp (map (fn [(x Int64)] -> Int64 (+ x 1)) (list 1 2)))
        (pr (pair "k" 1))]
    (str (kind-of "(") "|"
         (string-from-int64 l) "|" sl "|" (string-from-int64 io) "|"
         (bool-yes ct) "|" (bool-yes sw) "|" jn "|" ch "|" fs "|" cc "|"
         (string-from-int64 (len-list cs)) "|" (string-from-int64 (len-list ap)) "|"
         (string-from-int64 hd) "|" (string-from-int64 (len-list tl)) "|"
         (bool-yes em) "|" (string-from-int64 (len-list rv)) "|"
         (string-from-int64 (len-list mp)) "|" (.-first pr))))
