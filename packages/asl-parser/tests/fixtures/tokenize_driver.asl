(module asl-parser/tokenize-driver
  :d "Driver for the self-hosted lexer: tokenize any source and render its tokens."
  :x [dump]
  :i [(lexer :a lex)])

(df render-token [(t lex/Token)] -> String
  :d "Renders one token as kind|raw."
  (str (lex/token-type-name (.-kind t)) "|" (.-raw-text t)))

(df dump [(src String)] -> (List String)
  :d "Tokenize a source string and render every token but the EOF sentinel."
  (map (fn [(t lex/Token)] -> String (render-token t))
       (filter (fn [(t lex/Token)] -> Bool (not (string-empty? (.-raw-text t))))
               (lex/tokenize src))))
