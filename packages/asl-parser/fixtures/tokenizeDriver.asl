(module asl-parser/tokenizeDriver :x [dump] :i [(lexer :a lex)])

fn renderToken t: lex/Token -> String
  (str (lex/tokenTypeName t.kind) "|" t.rawText)

fn dump src: String -> (List String)
  (map (fn [(t lex/Token)] -> String (renderToken t)) (filter (fn [(t lex/Token)] -> Bool (not (stringEmpty? t.rawText))) (lex/tokenize src)))
