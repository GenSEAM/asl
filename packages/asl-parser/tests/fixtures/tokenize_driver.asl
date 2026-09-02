(module asl-parser/tokenize-driver
  :d "Driver for the self-hosted lexer: tokenize a sample and render tokens."
  :x [run-tokenize]
  :i [(lexer :a lex)])

(df render-token [(t lex/Token)] -> String
  :d "Renders one token as kind|raw|line|col."
  (str (lex/token-type-name (.-kind t)) "|" (.-raw-text t) "|"
       (string-from-int64 (.-line t)) "|" (string-from-int64 (.-col t))))

(df run-tokenize [] -> (List String)
  :d "Tokenize the multi-line sample and render every token."
  (map (fn [(t lex/Token)] -> String (render-token t))
       (lex/tokenize "(a 12\n:b \"xy\")")))
