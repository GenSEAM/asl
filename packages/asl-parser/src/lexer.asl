(module asl-parser/lexer :x [TokenType Token makeToken tokenKind isWhitespace isDelimiter tokenTypeName tokenize charAt isDigit])

(enum TokenType (:c tokLparen [] "Left parenthesis delimiter '('") (:c tokRparen [] "Right parenthesis delimiter ')'") (:c tokLbracket [] "Left square bracket delimiter '['") (:c tokRbracket [] "Right square bracket delimiter ']'") (:c tokSymbol [(name String)] "Identifier or language symbol") (:c tokKeyword [(key String)] "Option keyword starting with colon (e.g. :doc)") (:c tokString [(val String)] "Double-quoted string literal") (:c tokInt [(n Int64)] "64-bit integer literal") (:c tokFloat [(f Float64)] "IEEE-754 binary64 literal") (:c tokError [(msg String)] "Malformed token the reader must report") (:c tokEof [] "End of input stream"))

(schema Token (:f kind TokenType) (:f rawText String) (:f line Int64) (:f col Int64))

fn makeToken k: TokenType raw: String l: Int64 c: Int64 -> Token
  (Token :kind k :rawText raw :line l :col c)

fn isWhitespace ch: String -> Bool
  (stringContains? " \t\n\r" ch)

fn isDelimiter ch: String -> Bool
  (stringContains? "()[]" ch)

fn isBrace ch: String -> Bool
  (or (= ch "{") (= ch "}"))

fn tokenKind atom: String -> TokenType
  (if (isDelimiter atom) (delimKind atom) (if (stringStartsWith? atom ":") (tokKeyword atom) (if (stringStartsWith? atom "\"") (tokString atom) (tokSymbol atom))))

fn tokenTypeName tt: TokenType -> String
  (mt tt ((tokLparen) "LPAREN") ((tokRparen) "RPAREN") ((tokLbracket) "LBRACKET") ((tokRbracket) "RBRACKET") ((tokSymbol _) "SYMBOL") ((tokKeyword _) "KEYWORD") ((tokString _) "STRING") ((tokInt _) "INT") ((tokFloat _) "FLOAT") ((tokError _) "ERROR") ((tokEof) "EOF"))

fn charAt s: String i: Int64 -> String
  (mt (stringSlice s i (+ i 1)) ((some c) c) ((none) ""))

fn isDigit c: String -> Bool
  (stringContains? "0123456789" c)

fn isSymbolChar c: String -> Bool
  (and (not (stringEmpty? c)) (not (stringContains? " \t\n\r()[]{}\";:@" c)))

fn delimKind c: String -> TokenType
  (if (= c "(") (tokLparen) (if (= c ")") (tokRparen) (if (= c "[") (tokLbracket) (tokRbracket))))

(enum RunMode (:c runSymbol [] "Symbol or identifier run") (:c runKeyword [] "Keyword run after a leading colon") (:c runSign [] "A lone '-' whose next character decides its meaning") (:c runInt [] "Integer literal run") (:c runIntDot [] "Numeric run that has consumed a point but no fraction") (:c runFloat [] "Float literal run past its decimal point") (:c runExpSign [] "ASL1-floatExponentLiteral: numeric run just past e or E, no sign or digit yet") (:c runExpSigned [] "ASL1-floatExponentLiteral: numeric run past the exponent's own + or -, no digit yet") (:c runExp [] "ASL1-floatExponentLiteral: numeric run with at least one exponent digit") (:c runString [] "String literal run") (:c runStringEsc [] "String literal run just past a backslash") (:c runComment [] "Line comment from ';' to the end of the line, dropped"))

(enum RunStep (:c stepContinue [(mode RunMode)] "Character joins the run, which takes a new mode") (:c stepFinish [] "Character joins the run and the run emits its token") (:c stepEmit [] "Run emits without the character, which is read afresh"))

fn isExpMarker? ch: String -> Bool
  (or (= ch "e") (= ch "E"))

fn runNext mode: RunMode ch: String -> RunStep
  (mt mode ((runComment) (if (= ch "\n") (stepEmit) (stepContinue (runComment)))) ((runString) (cond ((= ch "\\") (stepContinue (runStringEsc))) ((= ch "\"") (stepFinish)) (else (stepContinue (runString))))) ((runStringEsc) (stepContinue (runString))) ((runInt) (cond ((isDigit ch) (stepContinue (runInt))) ((= ch ".") (stepContinue (runIntDot))) ((isExpMarker? ch) (stepContinue (runExpSign))) (else (stepEmit)))) ((runIntDot) (if (isDigit ch) (stepContinue (runFloat)) (stepEmit))) ((runFloat) (cond ((isDigit ch) (stepContinue (runFloat))) ((isExpMarker? ch) (stepContinue (runExpSign))) (else (stepEmit)))) ((runExpSign) (cond ((isDigit ch) (stepContinue (runExp))) ((or (= ch "+") (= ch "-")) (stepContinue (runExpSigned))) (else (stepEmit)))) ((runExpSigned) (if (isDigit ch) (stepContinue (runExp)) (stepEmit))) ((runExp) (if (isDigit ch) (stepContinue (runExp)) (stepEmit))) ((runSign) (cond ((isDigit ch) (stepContinue (runInt))) ((isSymbolChar ch) (stepContinue (runSymbol))) (else (stepEmit)))) (_ (if (isSymbolChar ch) (stepContinue mode) (stepEmit))))

fn symbolToken raw: String -> TokenType
  (cond
    ((and (stringStartsWith? raw ".") (isDigit (charAt raw 1))) (tokError "a float needs a digit before its decimal point"))
    ((and (stringStartsWith? raw ".-") (> (stringLength raw) 2)) (let [(f (optionOr (stringSlice raw 2 (stringLength raw)) ""))] (tokError (str "ERR_READ_FIELD (" raw " x) is retired: write x." f ", or (expr)." f " for an expression"))))
    (else (tokSymbol raw)))

fn floatToken raw: String -> TokenType
  (mt (stringToFloat64 raw) ((some f) (tokFloat f)) ((none) (tokError (str "malformed float literal " raw))))

fn runToken mode: RunMode raw: String -> TokenType
  (mt mode ((runSymbol) (symbolToken raw)) ((runKeyword) (tokKeyword raw)) ((runSign) (tokSymbol raw)) ((runString) (tokError "unterminated string literal")) ((runStringEsc) (tokError "unterminated string literal")) ((runComment) (tokError "a comment emits no token")) ((runIntDot) (tokError "a float needs a digit after its decimal point")) ((runExpSign) (tokError "a float needs a digit after its e or E")) ((runExpSigned) (tokError "a float needs a digit after its exponent sign")) ((runExp) (floatToken raw)) ((runFloat) (floatToken raw)) ((runInt) (tokInt (optionOr (stringToInt64 raw) 0))))

(schema RunState (:f mode RunMode) (:f raw (List String)) (:f startLine Int64) (:f startCol Int64))

(schema ScanState (:f toks (List Token)) (:f line Int64) (:f col Int64) (:f run (Option RunState)))

fn advance st: ScanState ch: String -> ScanState
  (with st :line (if (= ch "\n") (+ st.line 1) st.line) :col (if (= ch "\n") 1 (+ st.col 1)))

fn openRun st: ScanState mode: RunMode raw: String ch: String -> ScanState
  (let [(moved (advance st ch))] (ScanState :toks moved.toks :line moved.line :col moved.col :run (some (RunState :mode mode :raw (list raw) :startLine st.line :startCol st.col))))

fn consumeRun st: ScanState run: RunState mode: RunMode ch: String -> ScanState
  (let [(moved (advance st ch))] (ScanState :toks moved.toks :line moved.line :col moved.col :run (some (with run :mode mode :raw (cons ch run.raw)))))

fn closeRun st: ScanState run: RunState ch: String -> ScanState
  (let [(raw (stringJoin (listReverse run.raw) ""))
        (closed (stringConcat raw ch))]
    (with st :toks (cons (makeToken (tokString closed) closed run.startLine run.startCol) st.toks) :col (+ st.col 1) :run (none)))

fn afterRparen? toks: (List Token) line: Int64 col: Int64 -> Bool
  (mt (listHead toks) ((some t) (and (mt t.kind ((tokRparen) true) (_ false)) (and (= t.line line) (= t.col (- col 1))))) ((none) false))

fn postfixCheck st: ScanState run: RunState raw: String kind: TokenType -> TokenType
  (if (and (stringStartsWith? raw ".") (and (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" (charAt raw 1)) (and (not (stringEmpty? (charAt raw 1))) (not (afterRparen? st.toks run.startLine run.startCol)))))
    (tokError "ERR_READ_FIELD a postfix field chain .name follows ')' directly")
    kind)

fn emitRun st: ScanState run: RunState -> ScanState
  (mt run.mode ((runComment) (with st :run (none))) (_ (let [(raw (stringJoin (listReverse run.raw) ""))]
       (with st :toks (cons (makeToken (postfixCheck st run raw (runToken run.mode raw)) raw run.startLine run.startCol) st.toks) :run (none)))))

fn openChar st: ScanState ch: String -> ScanState
  (cond ((isWhitespace ch) (advance st ch)) ((isDelimiter ch) (with st :toks (cons (makeToken (delimKind ch) ch st.line st.col) st.toks) :col (+ st.col 1) :run (none))) ((isBrace ch) (with st :toks (cons (makeToken (tokSymbol ch) ch st.line st.col) st.toks) :col (+ st.col 1) :run (none))) ((= ch "\"") (openRun st (runString) "\"" ch)) ((= ch ";") (openRun st (runComment) ";" ch)) ((= ch "@") (with st :toks (cons (makeToken (tokError "invalid character '@': sigils are forbidden in AgentSlang grammar") "@" st.line st.col) st.toks) :col (+ st.col 1) :run (none))) ((isDigit ch) (openRun st (runInt) ch ch)) ((= ch "-") (openRun st (runSign) ch ch)) ((= ch ":") (openRun st (runKeyword) ":" ch)) (else (openRun st (runSymbol) ch ch)))

fn step st: ScanState ch: String -> ScanState
  (mt st.run ((some run) (mt (runNext run.mode ch) ((stepContinue m) (consumeRun st run m ch)) ((stepFinish) (closeRun st run ch)) ((stepEmit) (openChar (emitRun st run) ch)))) ((none) (openChar st ch)))

fn flush st: ScanState -> (List Token)
  (let [(closed (mt st.run ((some run) (emitRun st run)) ((none) st)))] (listReverse (cons (makeToken (tokEof) "" closed.line closed.col) closed.toks)))

fn tokenize s: String -> (List Token)
  (flush (fold step (ScanState :toks (list) :line 1 :col 1 :run (none)) (stringChars s)))
