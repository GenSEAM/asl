(module asl-parser/tokenizeDriver
  :d "Driver for the self-hosted lexer: tokenize any source and render its tokens."
  :x [dump]
  :i [(lexer :a lex)])

(df renderToken [(t lex/Token)] -> String
  :d "Renders one token as kind|raw."
  (str (lex/tokenTypeName (.-kind t)) "|" (.-rawText t)))

(df dump [(src String)] -> (List String)
  :d "Tokenize a source string and render every token but the EOF sentinel."
  (map (fn [(t lex/Token)] -> String (renderToken t))
       (filter (fn [(t lex/Token)] -> Bool (not (string-empty? (.-rawText t))))
               (lex/tokenize src))))
