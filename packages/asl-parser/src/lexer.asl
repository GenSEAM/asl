(module asl-parser/lexer
  :doc "100% Self-Hosted AgentScript S-Expression Lexer and Token Stream Engine."
  :export [TokenType Token make-token token-kind is-whitespace is-delimiter
           token-type-name])

(defenum TokenType
  (:case tok-lparen    [] "Left parenthesis delimiter '('")
  (:case tok-rparen    [] "Right parenthesis delimiter ')'")
  (:case tok-lbracket  [] "Left square bracket delimiter '['")
  (:case tok-rbracket  [] "Right square bracket delimiter ']'")
  (:case tok-symbol    [(name String)] "Identifier or language symbol")
  (:case tok-keyword   [(key String)] "Option keyword starting with colon (e.g. :doc)")
  (:case tok-string    [(val String)] "Double-quoted string literal")
  (:case tok-int       [(n Int64)] "64-bit integer literal")
  (:case tok-eof       [] "End of input stream"))

(defschema Token
  (:field kind TokenType "Token category")
  (:field raw-text String "Source character slice")
  (:field line Int64 "Source line number")
  (:field col Int64 "Source column number"))

(defun make-token [(k TokenType) (raw String) (l Int64) (c Int64)] -> Token
  :doc "Constructs a Token record."
  (Token :kind k :raw-text raw :line l :col c))

(defun is-whitespace [(ch String)] -> Bool
  :doc "Returns true if character is whitespace."
  (string-contains? " \t\n\r" ch))

(defun is-delimiter [(ch String)] -> Bool
  :doc "Returns true if character delimits S-expression tokens."
  (string-contains? "()[]" ch))

(defun token-kind [(atom String)] -> TokenType
  :doc "Classifies an atom string into a TokenType enum."
  (if (is-delimiter atom)
    (if (= atom "(")
      (tok-lparen)
      (if (= atom ")")
        (tok-rparen)
        (if (= atom "[")
          (tok-lbracket)
          (tok-rbracket))))
    (if (string-starts-with? atom ":")
      (tok-keyword atom)
      (if (string-starts-with? atom "\"")
        (tok-string atom)
        (tok-symbol atom)))))

(defun token-type-name [(tt TokenType)] -> String
  :doc "Renders a human-readable identifier for a token type."
  (match tt
    ((tok-lparen)     "LPAREN")
    ((tok-rparen)     "RPAREN")
    ((tok-lbracket)   "LBRACKET")
    ((tok-rbracket)   "RBRACKET")
    ((tok-symbol _)   "SYMBOL")
    ((tok-keyword _)  "KEYWORD")
    ((tok-string _)   "STRING")
    ((tok-int _)      "INT")
    ((tok-eof)        "EOF")))
