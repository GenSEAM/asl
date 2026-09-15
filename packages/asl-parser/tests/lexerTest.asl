(module asl-parser/lexerTest
  :d "Execution driver for the self-hosted lexer: tokenize a sample."
  :x [runTokenize runTests]
  :i [(lexer :a lex)])

(df renderToken [(t lex/Token)] -> String
  :d "Render one token as kind|raw|line|col."
  (str (lex/tokenTypeName (.-kind t)) "|" (.-rawText t) "|"
       (string-from-int64 (.-line t)) "|" (string-from-int64 (.-col t))))

(df runTokenize [] -> (List String)
  :d "Tokenize the multi-line sample and render every token."
  (map (fn [(t lex/Token)] -> String (renderToken t))
       (lex/tokenize "(a 12\n:b \"xy\")")))

(df testSigilRejection [] -> Bool
  :d "Verifies that @ character produces an ERROR token in lexer."
  (let [(tokens (lex/tokenize "@bad"))]
    (assert (> (list-length tokens) 0) "tokens must not be empty")
    (let [(t0 (option-or (list-head tokens) (lex/makeToken (lex/tokEof) "" 0 0)))]
      (assert (= (lex/tokenTypeName (.-kind t0)) "ERROR") "sigil @ must produce ERROR token")
      (assert (= (.-rawText t0) "@") "raw-text of rejected sigil must be @")
      (let [(msg (mt (.-kind t0) ((lex/tokError m) m) (_ "")))]
        (assert (string-contains? msg "invalid character '@'") "error message contains invalid character notice"))
      true)))

(df runTests [] -> Bool
  :d "Runs lexer tokenize tests"
  (let [(tokens (runTokenize))]
    (assert (> (list-length tokens) 0) "tokens must not be empty")
    (assert (string-contains? (option-or (list-head tokens) "") "LPAREN") "first token is LPAREN")
    (assert (testSigilRejection) "sigil @ rejection verified")
    true))
