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

(dfs RunState
  (:f mode RunMode "Run mode")
  (:f raw String "Accumulated run text, including any pre-consumed opener")
  (:f start-line Int64 "Line where the run opened")
  (:f start-col Int64 "Column where the run opened"))

(dfs ScanState
  (:f toks (List Token) "Emitted tokens, kept reversed so appends are cons")
  (:f line Int64 "Current line")
  (:f col Int64 "Current column")
  (:f run (Option RunState) "Open run, or none outside a run"))

(df consume-run [(st ScanState) (run RunState) (ch String)] -> ScanState
  :d "Fold step when ch belongs to the open run: append it and advance position."
  (ScanState :toks (.-toks st)
             :line (if (= ch "\n") (+ (.-line st) 1) (.-line st))
             :col (if (= ch "\n") 1 (+ (.-col st) 1))
             :run (some (RunState :mode (.-mode run)
                                  :raw (str (.-raw run) ch)
                                  :start-line (.-start-line run)
                                  :start-col (.-start-col run)))))

(df close-string-run [(st ScanState) (run RunState) (ch String)] -> ScanState
  :d "Fold step on a string's closing quote: the quote joins the raw and the run emits."
  (let [(closed (str (.-raw run) ch))]
    (ScanState :toks (list-cons (make-token (run-token (.-mode run) closed) closed
                                            (.-start-line run) (.-start-col run))
                                (.-toks st))
               :line (.-line st)
               :col (+ (.-col st) 1)
               :run (none))))

(df emit-run-and-char [(st ScanState) (run RunState) (ch String)] -> ScanState
  :d "Fold step when ch terminates the run: emit the run, then handle ch fresh."
  (open-char (ScanState :toks (list-cons (make-token (run-token (.-mode run) (.-raw run))
                                                     (.-raw run)
                                                     (.-start-line run) (.-start-col run))
                                         (.-toks st))
                        :line (.-line st)
                        :col (.-col st)
                        :run (none))
             ch))

(df open-char [(st ScanState) (ch String)] -> ScanState
  :d "Fold step for a character outside any run."
  (cond
    ((is-whitespace ch)
     (ScanState :toks (.-toks st)
                :line (if (= ch "\n") (+ (.-line st) 1) (.-line st))
                :col (if (= ch "\n") 1 (+ (.-col st) 1))
                :run (none)))
    ((is-delimiter ch)
     (ScanState :toks (list-cons (make-token (delim-kind ch) ch (.-line st) (.-col st))
                                 (.-toks st))
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (none)))
    ((is-brace ch)
     (ScanState :toks (list-cons (make-token (tok-symbol ch) ch (.-line st) (.-col st))
                                 (.-toks st))
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (none)))
    ((= ch "\"")
     (ScanState :toks (.-toks st)
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (some (RunState :mode (run-string) :raw "\""
                                     :start-line (.-line st) :start-col (.-col st)))))
    ((is-digit ch)
     ;; The opening digit is the run's first character, not a pre-consumed opener.
     (ScanState :toks (.-toks st)
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (some (RunState :mode (run-int) :raw ch
                                     :start-line (.-line st) :start-col (.-col st)))))
    ((= ch ":")
     (ScanState :toks (.-toks st)
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (some (RunState :mode (run-keyword) :raw ":"
                                     :start-line (.-line st) :start-col (.-col st)))))
    (:else
     (ScanState :toks (.-toks st)
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (some (RunState :mode (run-symbol) :raw ch
                                     :start-line (.-line st) :start-col (.-col st)))))))

(df step [(st ScanState) (ch String)] -> ScanState
  :d "One fold step: continue, close or emit an open run, else open the char."
  (mt (.-run st)
    ((some run)
     (if (run-continues? (.-mode run) ch)
       (consume-run st run ch)
       (if (and (= (.-mode run) (run-string)) (= ch "\""))
         (close-string-run st run ch)
         (emit-run-and-char st run ch))))
    ((none) (open-char st ch))))

(df flush [(st ScanState)] -> (List Token)
  :d "Emit an open run and the EOF sentinel, then restore token order."
  (let [(emitted (mt (.-run st)
                  ((some run)
                   (list-cons (make-token (run-token (.-mode run) (.-raw run))
                                          (.-raw run)
                                          (.-start-line run) (.-start-col run))
                              (.-toks st)))
                  ((none) (.-toks st))))]
    (list-reverse (list-cons (make-token (tok-eof) "" (.-line st) (.-col st))
                             emitted))))

(df tokenize [(s String)] -> (List Token)
  :d "Scans source text into tokens with 1-based line and column positions."
  (flush (fold step (ScanState :toks (list) :line 1 :col 1 :run (none))
               (string-chars s))))
