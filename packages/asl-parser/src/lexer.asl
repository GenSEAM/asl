(module asl-parser/lexer
  :d "100% Self-Hosted AgentScript S-Expression Lexer and Token Stream Engine."
  :x [TokenType Token makeToken tokenKind isWhitespace isDelimiter
           tokenTypeName tokenize charAt isDigit])

(dfe TokenType
  (:c tokLparen    [] "Left parenthesis delimiter '('")
  (:c tokRparen    [] "Right parenthesis delimiter ')'")
  (:c tokLbracket  [] "Left square bracket delimiter '['")
  (:c tokRbracket  [] "Right square bracket delimiter ']'")
  (:c tokSymbol    [(name String)] "Identifier or language symbol")
  (:c tokKeyword   [(key String)] "Option keyword starting with colon (e.g. :doc)")
  (:c tokString    [(val String)] "Double-quoted string literal")
  (:c tokInt       [(n Int64)] "64-bit integer literal")
  (:c tokFloat     [(f Float64)] "IEEE-754 binary64 literal")
  (:c tokError     [(msg String)] "Malformed token the reader must report")
  (:c tokEof       [] "End of input stream"))

(dfs Token
  (:f kind TokenType "Token category")
  (:f rawText String "Source character slice")
  (:f line Int64 "Source line number")
  (:f col Int64 "Source column number"))

(df makeToken [(k TokenType) (raw String) (l Int64) (c Int64)] -> Token
  :d "Constructs a Token record."
  (Token :kind k :rawText raw :line l :col c))

(df isWhitespace [(ch String)] -> Bool
  :d "Returns true if character is whitespace."
  (string-contains? " \t\n\r" ch))

(df isDelimiter [(ch String)] -> Bool
  :d "Returns true if character delimits S-expression tokens."
  (string-contains? "()[]" ch))

(df isBrace [(ch String)] -> Bool
  :d "Returns true for the type-parameter braces { }."
  (or (= ch "{") (= ch "}")))

(df tokenKind [(atom String)] -> TokenType
  :d "Classifies an atom string into a TokenType enum."
  (if (isDelimiter atom)
    (delimKind atom)
    (if (string-starts-with? atom ":")
      (tokKeyword atom)
      (if (string-starts-with? atom "\"")
        (tokString atom)
        (tokSymbol atom)))))

(df tokenTypeName [(tt TokenType)] -> String
  :d "Renders a human-readable identifier for a token type."
  (mt tt
    ((tokLparen)     "LPAREN")
    ((tokRparen)     "RPAREN")
    ((tokLbracket)   "LBRACKET")
    ((tokRbracket)   "RBRACKET")
    ((tokSymbol _)   "SYMBOL")
    ((tokKeyword _)  "KEYWORD")
    ((tokString _)   "STRING")
    ((tokInt _)      "INT")
    ((tokFloat _)    "FLOAT")
    ((tokError _)    "ERROR")
    ((tokEof)        "EOF")))

(df charAt [(s String) (i Int64)] -> String
  :d "The single character at index i, or the empty string past the end."
  (mt (string-slice s i (+ i 1))
    ((some c) c)
    ((none)   "")))

(df isDigit [(c String)] -> Bool
  :d "True when the character is an ASCII decimal digit."
  (string-contains? "0123456789" c))

(df isSymbolChar [(c String)] -> Bool
  :d "True when the character may continue a symbol or keyword run.

  One membership test, not a chain of `and`s: `and` is binary, so the chain this
  replaced silently dropped every clause past the second and let `{`, `\"` and `:`
  extend a symbol run."
  (and (not (string-empty? c))
       (not (string-contains? " \t\n\r()[]{}\";:@" c))))

(df delimKind [(c String)] -> TokenType
  :d "The nullary token kind a delimiter character names."
  (if (= c "(") (tokLparen)
    (if (= c ")") (tokRparen)
      (if (= c "[") (tokLbracket)
        (tokRbracket)))))

(dfe RunMode
  (:c runSymbol     [] "Symbol or identifier run")
  (:c runKeyword    [] "Keyword run after a leading colon")
  (:c runSign       [] "A lone '-' whose next character decides its meaning")
  (:c runInt        [] "Integer literal run")
  (:c runIntDot    [] "Numeric run that has consumed a point but no fraction")
  (:c runFloat      [] "Float literal run past its decimal point")
  (:c runString     [] "String literal run")
  (:c runStringEsc [] "String literal run just past a backslash"))

(dfe RunStep
  (:c stepContinue [(mode RunMode)] "Character joins the run, which takes a new mode")
  (:c stepFinish   [] "Character joins the run and the run emits its token")
  (:c stepEmit     [] "Run emits without the character, which is read afresh"))

(df runNext [(mode RunMode) (ch String)] -> RunStep
  :d "What the open run does with ch: continue in some mode, close, emit or drop."
  (mt mode
    ((runString)     (cond
                        ((= ch "\\")  (stepContinue (runStringEsc)))
                        ((= ch "\"")  (stepFinish))
                        (:else        (stepContinue (runString)))))
    ((runStringEsc) (stepContinue (runString)))
    ((runInt)        (cond
                        ((isDigit ch) (stepContinue (runInt)))
                        ((= ch ".")    (stepContinue (runIntDot)))
                        (:else         (stepEmit))))
    ((runIntDot)    (if (isDigit ch) (stepContinue (runFloat)) (stepEmit)))
    ((runFloat)      (if (isDigit ch) (stepContinue (runFloat)) (stepEmit)))
    ((runSign)       (cond
                        ((isDigit ch)      (stepContinue (runInt)))
                        ((isSymbolChar ch) (stepContinue (runSymbol)))
                        (:else              (stepEmit))))
    (_                (if (isSymbolChar ch) (stepContinue mode) (stepEmit)))))

(df symbolToken [(raw String)] -> TokenType
  :d "A finished symbol run, rejecting `.5`-shaped atoms §3 says are not numbers."
  (if (and (string-starts-with? raw ".") (isDigit (charAt raw 1)))
    (tokError "a float needs a digit before its decimal point")
    (tokSymbol raw)))

(df runToken [(mode RunMode) (raw String)] -> TokenType
  :d "The token kind a finished run produces from its accumulated text."
  (mt mode
    ((runSymbol)     (symbolToken raw))
    ((runKeyword)    (tokKeyword raw))
    ((runSign)       (tokSymbol raw))
    ((runString)     (tokError "unterminated string literal"))
    ((runStringEsc) (tokError "unterminated string literal"))
    ((runIntDot)    (tokError "a float needs a digit after its decimal point"))
    ((runFloat)
     (tokFloat (option-or (string-to-float64 raw) 0.0)))
    ((runInt)
     (tokInt (option-or (string-to-int64 raw) 0)))))

(dfs RunState
  (:f mode RunMode "Run mode")
  (:f raw String "Accumulated run text, including any pre-consumed opener")
  (:f startLine Int64 "Line where the run opened")
  (:f startCol Int64 "Column where the run opened"))

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

(df openRun [(st ScanState) (mode RunMode) (raw String) (ch String)] -> ScanState
  :d "Open a run whose first character is ch and advance past it."
  (let [(moved (advance st ch))]
    (ScanState :toks (.-toks moved)
               :line (.-line moved)
               :col (.-col moved)
               :run (some (RunState :mode mode :raw raw
                                    :startLine (.-line st) :startCol (.-col st))))))

(df consumeRun [(st ScanState) (run RunState) (mode RunMode) (ch String)] -> ScanState
  :d "Fold step when ch belongs to the open run: append it and advance position."
  (let [(moved (advance st ch))]
    (ScanState :toks (.-toks moved)
               :line (.-line moved)
               :col (.-col moved)
               :run (some (RunState :mode mode
                                    :raw (str (.-raw run) ch)
                                    :startLine (.-startLine run)
                                    :startCol (.-startCol run))))))

(df closeRun [(st ScanState) (run RunState) (ch String)] -> ScanState
  :d "Fold step on a string's closing quote: the quote joins the raw and emits."
  (let [(closed (str (.-raw run) ch))]
    (ScanState :toks (list-cons (makeToken (tokString closed) closed
                                            (.-startLine run) (.-startCol run))
                                (.-toks st))
               :line (.-line st)
               :col (+ (.-col st) 1)
               :run (none))))

(df emitRun [(st ScanState) (run RunState)] -> ScanState
  :d "The state with the open run's token emitted and the run cleared."
  (ScanState :toks (list-cons (makeToken (runToken (.-mode run) (.-raw run))
                                          (.-raw run)
                                          (.-startLine run) (.-startCol run))
                              (.-toks st))
             :line (.-line st)
             :col (.-col st)
             :run (none)))

(df openChar [(st ScanState) (ch String)] -> ScanState
  :d "Fold step for a character outside any run."
  (cond
    ((isWhitespace ch) (advance st ch))
    ((isDelimiter ch)
     (ScanState :toks (list-cons (makeToken (delimKind ch) ch (.-line st) (.-col st))
                                 (.-toks st))
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (none)))
    ((isBrace ch)
     (ScanState :toks (list-cons (makeToken (tokSymbol ch) ch (.-line st) (.-col st))
                                 (.-toks st))
                :line (.-line st)
                :col (+ (.-col st) 1)
                :run (none)))
    ((= ch "\"")   (openRun st (runString) "\"" ch))
    ((= ch ";")    (ScanState :toks (list-cons (makeToken (tokError "unexpected ';'") ";" (.-line st) (.-col st))
                                             (.-toks st))
                               :line (.-line st) :col (+ (.-col st) 1) :run (none)))
    ((= ch "@")    (ScanState :toks (list-cons (makeToken (tokError "invalid character '@': sigils are forbidden in AgentScript grammar") "@" (.-line st) (.-col st))
                                             (.-toks st))
                               :line (.-line st) :col (+ (.-col st) 1) :run (none)))
    ((isDigit ch) (openRun st (runInt) ch ch))
    ((= ch "-")    (openRun st (runSign) ch ch))
    ((= ch ":")    (openRun st (runKeyword) ":" ch))
    (:else         (openRun st (runSymbol) ch ch))))

(df step [(st ScanState) (ch String)] -> ScanState
  :d "One fold step: continue, close or emit the open run, else open ch."
  (mt (.-run st)
    ((some run)
     (mt (runNext (.-mode run) ch)
       ((stepContinue m) (consumeRun st run m ch))
       ((stepFinish)     (closeRun st run ch))
       ((stepEmit)       (openChar (emitRun st run) ch))))
    ((none) (openChar st ch))))

(df flush [(st ScanState)] -> (List Token)
  :d "Emit an open run and the EOF sentinel, then restore token order."
  (let [(closed (mt (.-run st)
                  ((some run) (emitRun st run))
                  ((none)     st)))]
    (list-reverse (list-cons (makeToken (tokEof) "" (.-line closed) (.-col closed))
                             (.-toks closed)))))

(df tokenize [(s String)] -> (List Token)
  :d "Scans source text into tokens with 1-based line and column positions."
  (flush (fold step (ScanState :toks (list) :line 1 :col 1 :run (none))
               (string-chars s))))
