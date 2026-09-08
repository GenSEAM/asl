(module asl-parser/lexer-test
  :d "Execution driver for the self-hosted lexer: tokenize a sample."
  :x [run-tokenize run-tests]
  :i [(lexer :a lex)])

(df render-token [(t lex/Token)] -> String
  :d "Render one token as kind|raw|line|col."
  (str (lex/token-type-name (.-kind t)) "|" (.-raw-text t) "|"
       (string-from-int64 (.-line t)) "|" (string-from-int64 (.-col t))))

(df run-tokenize [] -> (List String)
  :d "Tokenize the multi-line sample and render every token."
  (map (fn [(t lex/Token)] -> String (render-token t))
       (lex/tokenize "(a 12\n:b \"xy\")")))

(df run-tests [] -> Bool
  :d "Runs lexer tokenize tests"
  (let [(tokens (run-tokenize))]
    (assert (> (list-length tokens) 0) "tokens must not be empty")
    (assert (string-contains? (option-or (list-head tokens) "") "LPAREN") "first token is LPAREN")
    true))
