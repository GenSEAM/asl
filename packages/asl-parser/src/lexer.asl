(module asl-parser/lexer
  :d "100% Self-Hosted AgentScript S-Expression Lexer and Token Stream Engine."
  :x [TokenType Token make-token token-kind is-whitespace is-delimiter
           token-type-name tokenize])

(dfe TokenType
  (:c tok-lparen    [] "Left parenthesis delimiter '('")
  (:c tok-rparen    [] "Right parenthesis delimiter ')'")
  (:c tok-lbracket  [] "Left square bracket delimiter '['")
  (:c tok-rbracket  [] "Right square bracket delimiter ']'")
  (:c tok-symbol    [(name String)] "Identifier or language symbol")
  (:c tok-keyword   [(key String)] "Option keyword starting with colon (e.g. :doc)")
  (:c tok-string    [(val String)] "Double-quoted string literal")
  (:c tok-int       [(n Int64)] "64-bit integer literal")
  (:c tok-eof       [] "End of input stream"))

(dfs Token
  (:f kind TokenType "Token category")
  (:f raw-text String "Source character slice")
  (:f line Int64 "Source line number")
  (:f col Int64 "Source column number"))

(df make-token [(k TokenType) (raw String) (l Int64) (c Int64)] -> Token
  :d "Constructs a Token record."
  (Token :kind k :raw-text raw :line l :col c))

(df is-whitespace [(ch String)] -> Bool
  :d "Returns true if character is whitespace."
  (string-contains? " \t\n\r" ch))

(df is-delimiter [(ch String)] -> Bool
  :d "Returns true if character delimits S-expression tokens."
  (string-contains? "()[]" ch))

(df is-brace [(ch String)] -> Bool
  :d "Returns true for the type-parameter braces { }."
  (or (= ch "{") (= ch "}")))

(df token-kind [(atom String)] -> TokenType
  :d "Classifies an atom string into a TokenType enum."
  (if (is-delimiter atom)
    (delim-kind atom)
    (if (string-starts-with? atom ":")
      (tok-keyword atom)
      (if (string-starts-with? atom "\"")
        (tok-string atom)
        (tok-symbol atom)))))

(df token-type-name [(tt TokenType)] -> String
  :d "Renders a human-readable identifier for a token type."
  (mt tt
    ((tok-lparen)     "LPAREN")
    ((tok-rparen)     "RPAREN")
    ((tok-lbracket)   "LBRACKET")
    ((tok-rbracket)   "RBRACKET")
    ((tok-symbol _)   "SYMBOL")
    ((tok-keyword _)  "KEYWORD")
    ((tok-string _)   "STRING")
    ((tok-int _)      "INT")
    ((tok-eof)        "EOF")))

(df char-at [(s String) (i Int64)] -> String
  :d "The single character at index i, or the empty string past the end."
  (mt (string-slice s i (+ i 1))
    ((some c) c)
    ((none)   "")))

(df is-digit [(c String)] -> Bool
  :d "True when the character is an ASCII decimal digit."
  (string-contains? "0123456789" c))

(df is-symbol-char [(c String)] -> Bool
  :d "True when the character may continue a symbol or keyword run."
  (and (not (is-whitespace c))
       (not (is-delimiter c))
       (not (is-brace c))
       (not (= c "\""))
       (not (= c ":"))))

(df delim-kind [(c String)] -> TokenType
  :d "The nullary token kind a delimiter character names."
  (mt c
    ("(" (tok-lparen))
    (")" (tok-rparen))
    ("[" (tok-lbracket))
    (_   (tok-rbracket))))

(df tokenize [(s String)] -> (List Token)
  :d "Scans source text into tokens with 1-based line and column positions."
  (scan s 0 1 1))

(dfe RunMode
  (:c run-symbol  [] "Symbol or identifier run")
  (:c run-keyword [] "Keyword run after a leading colon")
  (:c run-int     [] "Integer literal run")
  (:c run-string  [] "String literal run"))

(df run-continues? [(mode RunMode) (ch String)] -> Bool
  :d "True while ch belongs to the run selected by mode."
  (mt mode
    ((run-int)    (is-digit ch))
    ((run-string) (not (= ch "\"")))
    (_ (is-symbol-char ch))))

(df run-token [(mode RunMode) (raw String)] -> TokenType
  :d "The token kind a finished run produces from its accumulated text."
  (mt mode
    ((run-symbol)  (tok-symbol raw))
    ((run-keyword) (tok-keyword raw))
    ((run-string)  (tok-string raw))
    ((run-int)
     (tok-int (mt (string-to-int64 raw) ((some v) v) ((none) 0))))))

(df run-emit [(mode RunMode) (raw String) (s String) (i Int64) (line Int64) (col Int64)
              (start-line Int64) (start-col Int64)] -> (List Token)
  :d "Emits the finished run and resumes scanning after it."
  (mt mode
    ((run-string)
     (if (>= i (string-length s))
       (list-cons (make-token (tok-string raw) raw start-line start-col)
                  (scan s i line col))
       (let [(closed (str raw (char-at s i)))]
         (list-cons (make-token (tok-string closed) closed start-line start-col)
                    (scan s (+ i 1) line (+ col 1))))))
    (_ (list-cons (make-token (run-token mode raw) raw start-line start-col)
                  (scan s i line col)))))

(df scan-run [(mode RunMode) (s String) (i Int64) (line Int64) (col Int64)
              (start-line Int64) (start-col Int64) (acc String)] -> (List Token)
  :d "Consumes one run selected by mode and resumes scanning at its end."
  (if (>= i (string-length s))
    (run-emit mode acc s i line col start-line start-col)
    (let [(ch (char-at s i))]
      (if (run-continues? mode ch)
        (scan-run mode s (+ i 1)
                  (if (= ch "\n") (+ line 1) line)
                  (if (= ch "\n") 1 (+ col 1))
                  start-line start-col (str acc ch))
        (run-emit mode acc s i line col start-line start-col)))))

(df scan [(s String) (i Int64) (line Int64) (col Int64)] -> (List Token)
  :d "One scan step: skip a whitespace char, emit a delimiter, or start a run."
  (if (>= i (string-length s))
    (list (make-token (tok-eof) "" line col))
    (let [(ch (char-at s i))]
      (cond
        ((is-whitespace ch)
         (scan s (+ i 1)
               (if (= ch "\n") (+ line 1) line)
               (if (= ch "\n") 1 (+ col 1))))
        ((is-delimiter ch)
         (list-cons (make-token (delim-kind ch) ch line col)
                    (scan s (+ i 1) line (+ col 1))))
        ((is-brace ch)
         (list-cons (make-token (tok-symbol ch) ch line col)
                    (scan s (+ i 1) line (+ col 1))))
        ((= ch "\"")
         (scan-run (run-string) s (+ i 1) line (+ col 1) line col "\""))
        ((is-digit ch)
         (scan-run (run-int) s i line col line col ""))
        ((= ch ":")
         (scan-run (run-keyword) s (+ i 1) line (+ col 1) line col ":"))
        (:else
         (scan-run (run-symbol) s (+ i 1) line (+ col 1) line col ch))))))
