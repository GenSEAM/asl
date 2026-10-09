(module asl-parser/smoke :x [runSmoke lenList] :i [(lexer :a lex)])

fn boolYes b: Bool -> String
  (if b "T" "F")

fn kindOf s: String -> String
  (mt (lex/tokenKind s) ((lex/tokLparen) "LPAREN") ((lex/tokRparen) "RPAREN") ((lex/tokLbracket) "LBRACKET") ((lex/tokRbracket) "RBRACKET") ((lex/tokSymbol _) "SYMBOL") ((lex/tokKeyword _) "KEYWORD") ((lex/tokString _) "STRING") ((lex/tokInt _) "INT") ((lex/tokFloat _) "FLOAT") ((lex/tokError _) "ERROR") ((lex/tokEof) "EOF"))

fn lenList xs: (List Int64) -> Int64
  (mt xs ((list) 0) ((cons _ t) (+ 1 (lenList t))))

fn runSmoke -> String
  (let [(l (stringLength "hello")) (sl (mt (stringSlice "hello" 1 3) ((some v) v) ((none) ""))) (io (mt (stringIndexOf "hello" "l") ((some v) v) ((none) 0))) (ct (stringContains? "hello" "ell")) (sw (stringStartsWith? "hello" "he")) (sp (stringSplit "a,b" ",")) (jn (stringJoin sp ":")) (ch (stringJoin (stringChars "ab") "")) (n (mt (stringToInt64 "7") ((some v) v) ((none) 0))) (fs (stringFromInt64 n)) (cc (str "x" "y")) (cs (cons 1 (list 2))) (ap (listAppend (list 1) (list 2))) (hd (mt (listHead (list 9 8)) ((some v) v) ((none) 0))) (tl (mt (listTail (list 9 8)) ((some v) v) ((none) (list)))) (em (listEmpty? (list))) (rv (listReverse (list 1 2 3))) (mp (map (fn [(x Int64)] -> Int64 (+ x 1)) (list 1 2))) (pr (pair "k" 1))] (str (kindOf "(") "|" (stringFromInt64 l) "|" sl "|" (stringFromInt64 io) "|" (boolYes ct) "|" (boolYes sw) "|" jn "|" ch "|" fs "|" cc "|" (stringFromInt64 (lenList cs)) "|" (stringFromInt64 (lenList ap)) "|" (stringFromInt64 hd) "|" (stringFromInt64 (lenList tl)) "|" (boolYes em) "|" (stringFromInt64 (lenList rv)) "|" (stringFromInt64 (lenList mp)) "|" pr.first))
