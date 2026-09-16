(module asl-parser/indentLexer
  :d "Pure ASL v0.4 Indentation-Aware Lexer with Interpolation and Diagnostics."
  :x [IndentTokenType IndentToken LexerDiagnostic
      makeIndentToken makeDiagnostic tokenTypeName
      tokenizeIndented tokenizeLines isInterpolatedString?]
  :i [(reader :a rd)])

(dfe IndentTokenType
  (:c tokIndent    [(level Int64)] "Indentation block increase")
  (:c tokDedent    [(level Int64)] "Indentation block decrease")
  (:c tokNewline   [] "Logical newline at same indentation level")
  (:c tokSymbol    [(name String)] "Identifier, dot-path (x.f.g), or symbol")
  (:c tokKeyword   [(key String)] "Colon keyword option (e.g. :doc)")
  (:c tokString    [(val String)] "Plain double-quoted string literal")
  (:c tokInterp    [(parts (List String)) (exprs (List String))] "Interpolated string with {expr} expressions")
  (:c tokInt       [(n Int64)] "64-bit integer literal")
  (:c tokFloat     [(f Float64)] "64-bit IEEE float literal")
  (:c tokLparen    [] "Left parenthesis '('")
  (:c tokRparen    [] "Right parenthesis ')'")
  (:c tokLbracket  [] "Left square bracket '['")
  (:c tokRbracket  [] "Right square bracket ']'")
  (:c tokLbrace    [] "Left curly brace '{'")
  (:c tokRbrace    [] "Right curly brace '}'")
  (:c tokColon     [] "Type annotation colon ':'")
  (:c tokArrow     [] "Arrow operator '->'")
  (:c tokEqual     [] "Assignment or definition '='")
  (:c tokBullet    [] "Unordered list bullet '-'")
  (:c tokError     [(code String) (msg String)] "Lexical or indentation diagnostic error")
  (:c tokEof       [] "End of input stream"))

(dfs LexerDiagnostic
  (:f code String "Diagnostic code (e.g. W001, W002, E010, E017, E018)")
  (:f msg String "Diagnostic description")
  (:f line Int64 "1-based line number")
  (:f col Int64 "1-based column number"))

(dfs IndentToken
  (:f kind IndentTokenType "Token category")
  (:f rawText String "Source text slice")
  (:f line Int64 "1-based line number")
  (:f col Int64 "1-based column number"))

(df makeIndentToken [(k IndentTokenType) (raw String) (l Int64) (c Int64)] -> IndentToken
  :d "Constructs an IndentToken record."
  (IndentToken :kind k :rawText raw :line l :col c))

(df makeDiagnostic [(code String) (msg String) (l Int64) (c Int64)] -> LexerDiagnostic
  :d "Constructs a LexerDiagnostic record."
  (LexerDiagnostic :code code :msg msg :line l :col c))

(df isInterpolatedString? [(tok IndentToken)] -> Bool
  :d "Returns true if token is an interpolated string."
  (mt (.-kind tok)
    ((tokInterp _ _) true)
    (_ false)))

(df tokenTypeName [(tt IndentTokenType)] -> String
  :d "Renders human-readable name of token type."
  (mt tt
    ((tokIndent l)      (str "INDENT(" (string-from-int64 l) ")"))
    ((tokDedent l)      (str "DEDENT(" (string-from-int64 l) ")"))
    ((tokNewline)       "NEWLINE")
    ((tokSymbol s)      (str "SYMBOL(" s ")"))
    ((tokKeyword k)     (str "KEYWORD(" k ")"))
    ((tokString s)      (str "STRING(" s ")"))
    ((tokInterp _ _)    "INTERP_STRING")
    ((tokInt n)         (str "INT(" (string-from-int64 n) ")"))
    ((tokFloat f)       "FLOAT")
    ((tokLparen)        "LPAREN")
    ((tokRparen)        "RPAREN")
    ((tokLbracket)      "LBRACKET")
    ((tokRbracket)      "RBRACKET")
    ((tokLbrace)        "LBRACE")
    ((tokRbrace)        "RBRACE")
    ((tokColon)         "COLON")
    ((tokArrow)         "ARROW")
    ((tokEqual)         "EQUAL")
    ((tokBullet)        "BULLET")
    ((tokError c m)     (str "ERROR(" c ":" m ")"))
    ((tokEof)           "EOF")))

(df sliceStr [(s String) (start Int64) (end Int64)] -> String
  :d "Safe string slice returning empty string on none."
  (option-or (string-slice s start end) ""))

(df charAt [(s String) (i Int64)] -> String
  :d "Single character at index, or empty string if out of bounds."
  (option-or (string-slice s i (+ i 1)) ""))

(df stripCr [(s String)] -> String
  :d "Strips trailing carriage return if present."
  (if (string-ends-with? s "\r")
    (sliceStr s 0 (- (string-length s) 1))
    s))

(df isDigitChar [(c String)] -> Bool
  :d "Checks if character is ASCII decimal digit."
  (string-contains? "0123456789" c))

(df isSymbolChar [(c String)] -> Bool
  :d "Checks if character can form part of an identifier or compound symbol."
  (and (not (string-empty? c))
       (not (string-contains? " \t\r\n()[]{}\";:#=" c))))

(dfs LineMeasure
  (:f spaces Int64 "Total indentation count in space units")
  (:f rest String "Line contents past leading indentation")
  (:f diagnostics (List LexerDiagnostic) "Emitted indentation warnings"))

(dfs IndentScanState
  (:f idx Int64 "Character index")
  (:f spaces Int64 "Measured space count")
  (:f inIndent Bool "Still in leading whitespace")
  (:f diags (List LexerDiagnostic) "Emitted diagnostics"))

(df measureIndent [(rawLine String) (lineNum Int64)] -> LineMeasure
  :d "Measures leading indentation, converting tabs (W001) and rounding odd spaces (W002)."
  (let [(clean (stripCr rawLine))
        (chars (string-chars clean))
        (len (string-length clean))]
    (let [(finalState (fold (fn [(st IndentScanState) (ch String)] -> IndentScanState
                              (if (.-inIndent st)
                                (cond
                                  ((= ch " ")
                                   (IndentScanState :idx (+ (.-idx st) 1)
                                                    :spaces (+ (.-spaces st) 1)
                                                    :inIndent true
                                                    :diags (.-diags st)))
                                  ((= ch "\t")
                                   (let [(d (makeDiagnostic "W001" "tab in indentation converted to 2 spaces" lineNum (+ (.-idx st) 1)))]
                                     (IndentScanState :idx (+ (.-idx st) 1)
                                                      :spaces (+ (.-spaces st) 2)
                                                      :inIndent true
                                                      :diags (cons d (.-diags st)))))
                                  (:else
                                   (IndentScanState :idx (.-idx st)
                                                    :spaces (.-spaces st)
                                                    :inIndent false
                                                    :diags (.-diags st))))
                                st))
                            (IndentScanState :idx 0 :spaces 0 :inIndent true :diags (list))
                            chars))]
      (let [(firstNonWhite (.-idx finalState))
            (rawSpaces (.-spaces finalState))
            (diags (list-reverse (.-diags finalState)))
            (restContent (if (>= firstNonWhite len) "" (sliceStr clean firstNonWhite len)))]
        (if (= (mod rawSpaces 2) 1)
          (let [(w002 (makeDiagnostic "W002" "odd indentation rounded down to 2-space boundary" lineNum 1))]
            (LineMeasure :spaces (- rawSpaces 1)
                         :rest restContent
                         :diagnostics (cons w002 diags)))
          (LineMeasure :spaces rawSpaces
                       :rest restContent
                       :diagnostics diags))))))

(dfs SymbolRun
  (:f nextIdx Int64 "Next index past symbol")
  (:f sym String "Accumulated symbol text"))

(df scanSymbolRun [(content String) (startIdx Int64) (len Int64)] -> SymbolRun
  :d "Scans identifier or symbol run."
  (fold (fn [(acc SymbolRun) (_ String)] -> SymbolRun
          (let [(k (.-nextIdx acc))
                (s (.-sym acc))]
            (if (>= k len)
              acc
              (let [(ch (charAt content k))]
                (if (isSymbolChar ch)
                  (SymbolRun :nextIdx (+ k 1) :sym (str s ch))
                  acc)))))
        (SymbolRun :nextIdx startIdx :sym "")
        (string-chars (sliceStr content startIdx len))))

(df scanKeywordRun [(content String) (startIdx Int64) (len Int64)] -> SymbolRun
  :d "Scans keyword run starting after colon."
  (let [(run (scanSymbolRun content (+ startIdx 1) len))]
    (SymbolRun :nextIdx (.-nextIdx run) :sym (str ":" (.-sym run)))))

(dfs TokenScanResult
  (:f nextIdx Int64 "Next index past token")
  (:f tok IndentToken "Scanned token"))

(df scanNumberOrSymbol [(content String) (startIdx Int64) (len Int64) (lineNum Int64) (colOffset Int64)] -> TokenScanResult
  :d "Scans integer, float or symbol token."
  (let [(run (scanSymbolRun content startIdx len))
        (endK (.-nextIdx run))
        (raw (.-sym run))]
    (let [(isNum (and (> (string-length raw) 0) (isDigitChar (charAt raw 0))))]
      (if isNum
        (if (string-contains? raw ".")
          (let [(fval (option-or (string-to-float64 raw) 0.0))
                (tok (makeIndentToken (tokFloat fval) raw lineNum (+ colOffset startIdx 1)))]
            (TokenScanResult :nextIdx endK :tok tok))
          (let [(ival (option-or (string-to-int64 raw) 0))
                (tok (makeIndentToken (tokInt ival) raw lineNum (+ colOffset startIdx 1)))]
            (TokenScanResult :nextIdx endK :tok tok)))
        (let [(tok (makeIndentToken (tokSymbol raw) raw lineNum (+ colOffset startIdx 1)))]
          (TokenScanResult :nextIdx endK :tok tok))))))

(dfs StringScanResult
  (:f isInterp Bool "True if string contains interpolation expressions")
  (:f plainVal String "Literal string if plain")
  (:f parts (List String) "Literal text parts between expressions")
  (:f exprs (List String) "Expression text parts")
  (:f consumed Int64 "Total characters consumed from opening quote")
  (:f error (Option String) "Error message if unclosed or malformed"))

(dfs StringScanState
  (:f idx Int64 "Index")
  (:f parts (List String) "Reversed parts")
  (:f exprs (List String) "Reversed expressions")
  (:f buf String "Current segment buffer")
  (:f inExpr Bool "Inside {expr}")
  (:f esc Bool "Backslash escape")
  (:f err (Option String) "Encountered error"))

(df scanStringLiteral [(src String) (startIdx Int64) (srcLen Int64)] -> StringScanResult
  :d "Scans string literal starting at quote, parsing {expr} interpolations and escapes."
  (let [(finalState (fold (fn [(st StringScanState) (ch String)] -> StringScanState
                            (if (< (.-idx st) (+ startIdx 1))
                              (StringScanState :idx (+ (.-idx st) 1)
                                               :parts (.-parts st)
                                               :exprs (.-exprs st)
                                               :buf (.-buf st)
                                               :inExpr (.-inExpr st)
                                               :esc false
                                               :err (.-err st))
                              (if (is-some? (.-err st))
                                st
                                (if (.-esc st)
                                  (if (and (.-inExpr st) (= ch "}"))
                                    (StringScanState :idx (+ (.-idx st) 1)
                                                     :parts (.-parts st)
                                                     :exprs (.-exprs st)
                                                     :buf (str (.-buf st) "}")
                                                     :inExpr true
                                                     :esc false
                                                     :err (none))
                                    (StringScanState :idx (+ (.-idx st) 1)
                                                     :parts (.-parts st)
                                                     :exprs (.-exprs st)
                                                     :buf (str (.-buf st) ch)
                                                     :inExpr (.-inExpr st)
                                                     :esc false
                                                     :err (none)))
                                  (cond
                                    ((= ch "\\")
                                     (StringScanState :idx (+ (.-idx st) 1)
                                                      :parts (.-parts st)
                                                      :exprs (.-exprs st)
                                                      :buf (.-buf st)
                                                      :inExpr (.-inExpr st)
                                                      :esc true
                                                      :err (none)))
                                    ((and (not (.-inExpr st)) (= ch "{"))
                                     (StringScanState :idx (+ (.-idx st) 1)
                                                      :parts (cons (.-buf st) (.-parts st))
                                                      :exprs (.-exprs st)
                                                      :buf ""
                                                      :inExpr true
                                                      :esc false
                                                      :err (none)))
                                    ((and (.-inExpr st) (= ch "}"))
                                     (StringScanState :idx (+ (.-idx st) 1)
                                                      :parts (.-parts st)
                                                      :exprs (cons (.-buf st) (.-exprs st))
                                                      :buf ""
                                                      :inExpr false
                                                      :esc false
                                                      :err (none)))
                                    ((and (not (.-inExpr st)) (= ch "\""))
                                     (StringScanState :idx (+ (.-idx st) 1)
                                                      :parts (cons (.-buf st) (.-parts st))
                                                      :exprs (.-exprs st)
                                                      :buf ""
                                                      :inExpr false
                                                      :esc false
                                                      :err (none)))
                                    (:else
                                     (StringScanState :idx (+ (.-idx st) 1)
                                                      :parts (.-parts st)
                                                      :exprs (.-exprs st)
                                                      :buf (str (.-buf st) ch)
                                                      :inExpr (.-inExpr st)
                                                      :esc false
                                                      :err (none))))))))
                          (StringScanState :idx 0 :parts (list) :exprs (list) :buf "" :inExpr false :esc false :err (none))
                          (string-chars (sliceStr src 0 srcLen))))]
    (let [(consumed (.-idx finalState))
          (partsRev (.-parts finalState))
          (exprsRev (.-exprs finalState))
          (inExpr (.-inExpr finalState))]
      (if inExpr
        (StringScanResult :isInterp true :plainVal "" :parts (list) :exprs (list)
                          :consumed consumed :error (some "E018: unclosed interpolation expression in string"))
        (if (list-empty? exprsRev)
          (let [(fullStr (string-join (list-reverse partsRev) ""))]
            (StringScanResult :isInterp false :plainVal fullStr :parts (list) :exprs (list)
                              :consumed consumed :error (none)))
          (StringScanResult :isInterp true :plainVal ""
                            :parts (list-reverse partsRev)
                            :exprs (list-reverse exprsRev)
                            :consumed consumed :error (none)))))))

(dfs LineTokensResult
  (:f tokens (List IndentToken) "Tokens produced on line")
  (:f diagnostics (List LexerDiagnostic) "Line diagnostics (e.g. E017)"))

(dfs LineScanState
  (:f idx Int64 "Current char index")
  (:f toks (List IndentToken) "Accumulated tokens in reverse")
  (:f diags (List LexerDiagnostic) "Accumulated diagnostics in reverse")
  (:f openBrackets Int64 "Currently open square brackets on line"))

(df scanLineContent [(content String) (lineNum Int64) (colOffset Int64)] -> LineTokensResult
  :d "Scans tokens on a single line starting past indentation offset."
  (let [(len (string-length content))]
    (let [(finalState (fold (fn [(st LineScanState) (_ String)] -> LineScanState
                              (let [(idx (.-idx st))]
                                (if (>= idx len)
                                  st
                                  (let [(c (charAt content idx))]
                                    (cond
                                      ((or (= c " ") (= c "\t"))
                                       (LineScanState :idx (+ idx 1)
                                                      :toks (.-toks st)
                                                      :diags (.-diags st)
                                                      :openBrackets (.-openBrackets st)))
                                      ((or (= c "#") (= c ";"))
                                       (LineScanState :idx len
                                                      :toks (.-toks st)
                                                      :diags (.-diags st)
                                                      :openBrackets (.-openBrackets st)))
                                      ((= c "(")
                                       (let [(t (makeIndentToken (tokLparen) "(" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st))))
                                      ((= c ")")
                                       (let [(t (makeIndentToken (tokRparen) ")" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st))))
                                      ((= c "[")
                                       (let [(t (makeIndentToken (tokLbracket) "[" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (+ (.-openBrackets st) 1))))
                                      ((= c "]")
                                       (let [(t (makeIndentToken (tokRbracket) "]" lineNum (+ colOffset idx 1)))
                                             (nxtBrk (if (> (.-openBrackets st) 0) (- (.-openBrackets st) 1) 0))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets nxtBrk)))
                                      ((= c "{")
                                       (let [(t (makeIndentToken (tokLbrace) "{" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st))))
                                      ((= c "}")
                                       (let [(t (makeIndentToken (tokRbrace) "}" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st))))
                                      ((= c "=")
                                       (let [(t (makeIndentToken (tokEqual) "=" lineNum (+ colOffset idx 1)))]
                                         (LineScanState :idx (+ idx 1)
                                                        :toks (cons t (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st))))
                                      ((= c "-")
                                       (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))]
                                         (if (= nextC ">")
                                           (let [(t (makeIndentToken (tokArrow) "->" lineNum (+ colOffset idx 1)))]
                                             (LineScanState :idx (+ idx 2)
                                                            :toks (cons t (.-toks st))
                                                            :diags (.-diags st)
                                                            :openBrackets (.-openBrackets st)))
                                           (if (or (= nextC " ") (= nextC "\t") (= nextC ""))
                                             (let [(t (makeIndentToken (tokBullet) "-" lineNum (+ colOffset idx 1)))]
                                               (LineScanState :idx (+ idx 1)
                                                              :toks (cons t (.-toks st))
                                                              :diags (.-diags st)
                                                              :openBrackets (.-openBrackets st)))
                                             (let [(t (makeIndentToken (tokSymbol "-") "-" lineNum (+ colOffset idx 1)))]
                                               (LineScanState :idx (+ idx 1)
                                                              :toks (cons t (.-toks st))
                                                              :diags (.-diags st)
                                                              :openBrackets (.-openBrackets st)))))))
                                      ((= c ":")
                                       (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))]
                                         (if (isSymbolChar nextC)
                                           (let [(kwRun (scanKeywordRun content idx len))
                                                 (endK (.-nextIdx kwRun))
                                                 (kw (.-sym kwRun))
                                                 (t (makeIndentToken (tokKeyword kw) kw lineNum (+ colOffset idx 1)))]
                                             (LineScanState :idx endK
                                                            :toks (cons t (.-toks st))
                                                            :diags (.-diags st)
                                                            :openBrackets (.-openBrackets st)))
                                           (let [(t (makeIndentToken (tokColon) ":" lineNum (+ colOffset idx 1)))]
                                             (LineScanState :idx (+ idx 1)
                                                            :toks (cons t (.-toks st))
                                                            :diags (.-diags st)
                                                            :openBrackets (.-openBrackets st))))))
                                      ((= c "\"")
                                       (let [(strRes (scanStringLiteral content idx len))]
                                         (mt (.-error strRes)
                                           ((some errMsg)
                                            (let [(t (makeIndentToken (tokError "E018" errMsg) "\"" lineNum (+ colOffset idx 1)))
                                                  (d (makeDiagnostic "E018" errMsg lineNum (+ colOffset idx 1)))]
                                              (LineScanState :idx len
                                                             :toks (cons t (.-toks st))
                                                             :diags (cons d (.-diags st))
                                                             :openBrackets (.-openBrackets st))))
                                           ((none)
                                            (if (.-isInterp strRes)
                                              (let [(t (makeIndentToken (tokInterp (.-parts strRes) (.-exprs strRes))
                                                                        "\"...\"" lineNum (+ colOffset idx 1)))]
                                                (LineScanState :idx (.-consumed strRes)
                                                               :toks (cons t (.-toks st))
                                                               :diags (.-diags st)
                                                               :openBrackets (.-openBrackets st)))
                                              (let [(plain (.-plainVal strRes))
                                                    (t (makeIndentToken (tokString plain) plain lineNum (+ colOffset idx 1)))]
                                                (LineScanState :idx (.-consumed strRes)
                                                               :toks (cons t (.-toks st))
                                                               :diags (.-diags st)
                                                               :openBrackets (.-openBrackets st))))))))
                                      (:else
                                       (let [(numSym (scanNumberOrSymbol content idx len lineNum colOffset))
                                             (endK (.-nextIdx numSym))
                                             (tok (.-tok numSym))]
                                         (LineScanState :idx endK
                                                        :toks (cons tok (.-toks st))
                                                        :diags (.-diags st)
                                                        :openBrackets (.-openBrackets st)))))))))
                            (LineScanState :idx 0 :toks (list) :diags (list) :openBrackets 0)
                            (string-chars content)))]
      (let [(toksRev (.-toks finalState))
            (diags (.-diags finalState))
            (unclosedBrackets (.-openBrackets finalState))]
        (if (> unclosedBrackets 0)
          (let [(d (makeDiagnostic "E017" "unclosed inline bracket on line" lineNum len))]
            (LineTokensResult :tokens (list-reverse toksRev) :diagnostics (cons d diags)))
          (LineTokensResult :tokens (list-reverse toksRev) :diagnostics diags))))))

(dfs TokenizeState
  (:f stack (List Int64) "Indentation level stack (measured in 2-space units)")
  (:f tokens (List IndentToken) "Accumulated tokens in reverse order")
  (:f diagnostics (List LexerDiagnostic) "Accumulated diagnostics in reverse order")
  (:f lineCount Int64 "Current line number")
  (:f hasEmitted Bool "True if non-blank content token has been emitted"))

(df tokenizeLines [(lines (List String))] -> (Pair (List IndentToken) (List LexerDiagnostic))
  :d "Processes source lines into indented token stream with indentation/dedentation."
  (let [(finalState (fold (fn [(st TokenizeState) (line String)] -> TokenizeState
                            (let [(lNum (+ (.-lineCount st) 1))
                                  (meas (measureIndent line lNum))
                                  (content (.-rest meas))
                                  (diags (list-append (.-diagnostics meas) (.-diagnostics st)))]
                              (if (or (string-empty? content)
                                      (string-starts-with? content "#")
                                      (string-starts-with? content ";"))
                                (TokenizeState :stack (.-stack st)
                                               :tokens (.-tokens st)
                                               :diagnostics diags
                                               :lineCount lNum
                                               :hasEmitted (.-hasEmitted st))
                                (let [(curLevel (/ (.-spaces meas) 2))
                                      (topLevel (option-or (list-head (.-stack st)) 0))
                                      (lineRes (scanLineContent content lNum (.-spaces meas)))
                                      (lineToks (.-tokens lineRes))
                                      (allDiags (list-append (.-diagnostics lineRes) diags))]
                                  (cond
                                    ((> curLevel topLevel)
                                     (let [(indTok (makeIndentToken (tokIndent curLevel) "" lNum 1))
                                           (newStack (cons curLevel (.-stack st)))
                                           (newToks (list-append (list-reverse lineToks) (cons indTok (.-tokens st))))]
                                       (TokenizeState :stack newStack
                                                      :tokens newToks
                                                      :diagnostics allDiags
                                                      :lineCount lNum
                                                      :hasEmitted true)))
                                    ((< curLevel topLevel)
                                     (let [(popRes (fold (fn [(acc (Pair (List Int64) (List IndentToken))) (_ Int64)]
                                                           -> (Pair (List Int64) (List IndentToken))
                                                           (let [(stk (.-first acc))
                                                                 (dtoks (.-second acc))
                                                                 (tp (option-or (list-head stk) 0))]
                                                             (if (> tp curLevel)
                                                               (let [(nxtStk (option-or (list-tail stk) (list)))
                                                                     (nxtTp (option-or (list-head nxtStk) 0))
                                                                     (dtok (makeIndentToken (tokDedent nxtTp) "" lNum 1))]
                                                                 (pair nxtStk (cons dtok dtoks)))
                                                               acc)))
                                                         (pair (.-stack st) (list))
                                                         (.-stack st)))]
                                       (let [(nxtStack (.-first popRes))
                                             (dedToks (.-second popRes))
                                             (newToks (list-append (list-reverse lineToks)
                                                                   (list-append dedToks (.-tokens st))))]
                                         (TokenizeState :stack nxtStack
                                                        :tokens newToks
                                                        :diagnostics allDiags
                                                        :lineCount lNum
                                                        :hasEmitted true))))
                                    (:else
                                     (let [(preToks (if (.-hasEmitted st)
                                                      (cons (makeIndentToken (tokNewline) "" lNum 1) (.-tokens st))
                                                      (.-tokens st)))
                                           (newToks (list-append (list-reverse lineToks) preToks))]
                                       (TokenizeState :stack (.-stack st)
                                                      :tokens newToks
                                                      :diagnostics allDiags
                                                      :lineCount lNum
                                                      :hasEmitted true))))))))
                          (TokenizeState :stack (list 0)
                                         :tokens (list)
                                         :diagnostics (list)
                                         :lineCount 0
                                         :hasEmitted false)
                          lines))]
    (let [(finalLine (.-lineCount finalState))
          (finalStack (.-stack finalState))
          (remainingDedent (fold (fn [(acc (List IndentToken)) (lvl Int64)] -> (List IndentToken)
                                   (if (> lvl 0)
                                     (cons (makeIndentToken (tokDedent 0) "" (+ finalLine 1) 1) acc)
                                     acc))
                                 (list)
                                 finalStack))
          (eofTok (makeIndentToken (tokEof) "" (+ finalLine 1) 1))
          (allTokens (list-reverse (cons eofTok (list-append remainingDedent (.-tokens finalState)))))]
      (pair allTokens (list-reverse (.-diagnostics finalState))))))

(df tokenizeIndented [(src String)] -> (Pair (List IndentToken) (List LexerDiagnostic))
  :d "Tokenizes full v0.4 indented source into IndentToken list and diagnostic stream."
  (let [(lines (string-split src "\n"))]
    (tokenizeLines lines)))
