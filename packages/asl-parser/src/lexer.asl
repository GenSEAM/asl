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
  (:c tok-float     [(f Float64)] "IEEE-754 binary64 literal")
  (:c tok-error     [(msg String)] "Malformed token the reader must report")
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
    ((tok-float _)    "FLOAT")
    ((tok-error _)    "ERROR")
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
  :d "True when the character may continue a symbol or keyword run.

  One membership test, not a chain of `and`s: `and` is binary, so the chain this
  replaced silently dropped every clause past the second and let `{`, `\"` and `:`
  extend a symbol run."
  (and (not (string-empty? c))
       (not (string-contains? " \t\n\r()[]{}\";:" c))))

(df delim-kind [(c String)] -> TokenType
  :d "The nullary token kind a delimiter character names."
  (mt c
    ("(" (tok-lparen))
    (")" (tok-rparen))
    ("[" (tok-lbracket))
    (_   (tok-rbracket))))

(dfe RunMode
  (:c run-symbol     [] "Symbol or identifier run")
  (:c run-keyword    [] "Keyword run after a leading colon")
  (:c run-sign       [] "A lone '-' whose next character decides its meaning")
  (:c run-int        [] "Integer literal run")
  (:c run-int-dot    [] "Numeric run that has consumed a point but no fraction")
  (:c run-float      [] "Float literal run past its decimal point")
  (:c run-string     [] "String literal run")
  (:c run-string-esc [] "String literal run just past a backslash"))

(dfe RunStep
  (:c step-continue [(mode RunMode)] "Character joins the run, which takes a new mode")
  (:c step-finish   [] "Character joins the run and the run emits its token")
  (:c step-emit     [] "Run emits without the character, which is read afresh"))

(df run-next [(mode RunMode) (ch String)] -> RunStep
  :d "What the open run does with ch: continue in some mode, close, emit or drop."
  (mt mode
    ((run-string)     (cond
                        ((= ch "\\")  (step-continue (run-string-esc)))
                        ((= ch "\"")  (step-finish))
                        (:else        (step-continue (run-string)))))
    ((run-string-esc) (step-continue (run-string)))
    ((run-int)        (cond
                        ((is-digit ch) (step-continue (run-int)))
                        ((= ch ".")    (step-continue (run-int-dot)))
                        (:else         (step-emit))))
    ((run-int-dot)    (if (is-digit ch) (step-continue (run-float)) (step-emit)))
    ((run-float)      (if (is-digit ch) (step-continue (run-float)) (step-emit)))
    ((run-sign)       (cond
                        ((is-digit ch)      (step-continue (run-int)))
                        ((is-symbol-char ch) (step-continue (run-symbol)))
                        (:else              (step-emit))))
    (_                (if (is-symbol-char ch) (step-continue mode) (step-emit)))))

(df symbol-token [(raw String)] -> TokenType
  :d "A finished symbol run, rejecting `.5`-shaped atoms §3 says are not numbers."
  (if (and (string-starts-with? raw ".") (is-digit (char-at raw 1)))
    (tok-error "a float needs a digit before its decimal point")
    (tok-symbol raw)))

(df run-token [(mode RunMode) (raw String)] -> TokenType
  :d "The token kind a finished run produces from its accumulated text."
  (mt mode
    ((run-symbol)     (symbol-token raw))
    ((run-keyword)    (tok-keyword raw))
    ((run-sign)       (tok-symbol raw))
    ((run-string)     (tok-error "unterminated string literal"))
    ((run-string-esc) (tok-error "unterminated string literal"))
    ((run-int-dot)    (tok-error "a float needs a digit after its decimal point"))
    ((run-float)
     (tok-float (mt (string-to-float64 raw) ((some v) v) ((none) 0.0))))
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

(df advance [(st ScanState) (ch String)] -> ScanState
  :d "The scan position after ch, with the run left untouched."
  (ScanState :toks (.-toks st)
             :line (if (= ch "\n") (+ (.-line st) 1) (.-line st))
             :col (if (= ch "\n") 1 (+ (.-col st) 1))
             :run (.-run st)))

(df open-run [(st ScanState) (mode RunMode) (raw String) (ch String)] -> ScanState
  :d "Open a run whose first character is ch and advance past it."
  (let [(moved (advance st ch))]
    (ScanState :toks (.-toks moved)
               :line (.-line moved)
               :col (.-col moved)
               :run (some (RunState :mode mode :raw raw
                                    :start-line (.-line st) :start-col (.-col st))))))

(df consume-run [(st ScanState) (run RunState) (mode RunMode) (ch String)] -> ScanState
  :d "Fold step when ch belongs to the open run: append it and advance position."
  (let [(moved (advance st ch))]
    (ScanState :toks (.-toks moved)
               :line (.-line moved)
               :col (.-col moved)
               :run (some (RunState :mode mode
                                    :raw (str (.-raw run) ch)
                                    :start-line (.-start-line run)
                                    :start-col (.-start-col run))))))

(df close-run [(st ScanState) (run RunState) (ch String)] -> ScanState
  :d "Fold step on a string's closing quote: the quote joins the raw and emits."
  (let [(closed (str (.-raw run) ch))]
    (ScanState :toks (list-cons (make-token (tok-string closed) closed
                                            (.-start-line run) (.-start-col run))
                                (.-toks st))
               :line (.-line st)
               :col (+ (.-col st) 1)
               :run (none))))

(df emit-run [(st ScanState) (run RunState)] -> ScanState
  :d "The state with the open run's token emitted and the run cleared."
  (ScanState :toks (list-cons (make-token (run-token (.-mode run) (.-raw run))
                                          (.-raw run)
                                          (.-start-line run) (.-start-col run))
                              (.-toks st))
             :line (.-line st)
             :col (.-col st)
             :run (none)))

(df open-char [(st ScanState) (ch String)] -> ScanState
  :d "Fold step for a character outside any run."
  (cond
    ((is-whitespace ch) (advance st ch))
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
    ((= ch "\"")   (open-run st (run-string) "\"" ch))
    ((= ch ";")    (ScanState :toks (list-cons (make-token (tok-error "unexpected ';'") ";" (.-line st) (.-col st))
                                             (.-toks st))
                               :line (.-line st) :col (+ (.-col st) 1) :run (none)))
    ((is-digit ch) (open-run st (run-int) ch ch))
    ((= ch "-")    (open-run st (run-sign) ch ch))
    ((= ch ":")    (open-run st (run-keyword) ":" ch))
    (:else         (open-run st (run-symbol) ch ch))))

(df step [(st ScanState) (ch String)] -> ScanState
  :d "One fold step: continue, close or emit the open run, else open ch."
  (mt (.-run st)
    ((some run)
     (mt (run-next (.-mode run) ch)
       ((step-continue m) (consume-run st run m ch))
       ((step-finish)     (close-run st run ch))
       ((step-emit)       (open-char (emit-run st run) ch))))
    ((none) (open-char st ch))))

(df flush [(st ScanState)] -> (List Token)
  :d "Emit an open run and the EOF sentinel, then restore token order."
  (let [(closed (mt (.-run st)
                  ((some run) (emit-run st run))
                  ((none)     st)))]
    (list-reverse (list-cons (make-token (tok-eof) "" (.-line closed) (.-col closed))
                             (.-toks closed)))))

(df tokenize [(s String)] -> (List Token)
  :d "Scans source text into tokens with 1-based line and column positions."
  (flush (fold step (ScanState :toks (list) :line 1 :col 1 :run (none))
               (string-chars s))))
