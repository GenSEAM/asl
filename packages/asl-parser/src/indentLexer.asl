(module asl-parser/indentLexer :x [IndentTokenType IndentToken LexerDiagnostic makeIndentToken makeDiagnostic tokenTypeName tokenize tokenizeIndented tokenizeLines] :i [(reader :a rd)])

(enum IndentTokenType (:c tokIndent [(level Int64)] "Indentation block increase") (:c tokDedent [(level Int64)] "Indentation block decrease") (:c tokNewline [] "Logical newline at same indentation level") (:c tokSymbol [(name String)] "Identifier, dot-path (x.f.g), or symbol") (:c tokKeyword [(key String)] "Colon keyword option (e.g. :doc)") (:c tokString [(val String)] "Plain double-quoted string literal") (:c tokInt [(n Int64)] "64-bit integer literal") (:c tokFloat [(f Float64)] "64-bit IEEE float literal") (:c tokLparen [] "Left parenthesis '('") (:c tokRparen [] "Right parenthesis ')'") (:c tokLbracket [] "Left square bracket '['") (:c tokRbracket [] "Right square bracket ']'") (:c tokLbrace [] "Left curly brace '{'") (:c tokRbrace [] "Right curly brace '}'") (:c tokColon [] "Type annotation colon ':'") (:c tokArrow [] "Arrow operator '->'") (:c tokEqual [] "Assignment or definition '='") (:c tokBullet [] "Unordered list bullet '-'") (:c tokQuestion [] "Error propagation operator '?'") (:c tokCoalesce [] "Null coalescing operator '??'") (:c tokOptChain [] "Optional chaining operator '?.'") (:c tokPipe [] "Pipeline operator '|>'") (:c tokError [(code String) (msg String)] "Lexical or indentation diagnostic error") (:c tokEof [] "End of input stream"))

(schema LexerDiagnostic (:f code String) (:f msg String) (:f line Int64) (:f col Int64))

(schema IndentToken (:f kind IndentTokenType) (:f rawText String) (:f line Int64) (:f col Int64))

fn makeIndentToken k: IndentTokenType raw: String l: Int64 c: Int64 -> IndentToken
  (IndentToken :kind k :rawText raw :line l :col c)

fn makeDiagnostic code: String msg: String l: Int64 c: Int64 -> LexerDiagnostic
  (LexerDiagnostic :code code :msg msg :line l :col c)

fn tokenTypeName tt: IndentTokenType -> String
  (mt tt ((tokIndent l) (str "INDENT(" (stringFromInt64 l) ")")) ((tokDedent l) (str "DEDENT(" (stringFromInt64 l) ")")) ((tokNewline) "NEWLINE") ((tokSymbol s) (str "SYMBOL(" s ")")) ((tokKeyword k) (str "KEYWORD(" k ")")) ((tokString s) (str "STRING(" s ")")) ((tokInt n) (str "INT(" (stringFromInt64 n) ")")) ((tokFloat f) "FLOAT") ((tokLparen) "LPAREN") ((tokRparen) "RPAREN") ((tokLbracket) "LBRACKET") ((tokRbracket) "RBRACKET") ((tokLbrace) "LBRACE") ((tokRbrace) "RBRACE") ((tokColon) "COLON") ((tokArrow) "ARROW") ((tokEqual) "EQUAL") ((tokBullet) "BULLET") ((tokQuestion) "?") ((tokCoalesce) "??") ((tokOptChain) "?.") ((tokPipe) "|>") ((tokError c m) (str "ERROR(" c ":" m ")")) ((tokEof) "EOF"))

fn sliceStr s: String start: Int64 end: Int64 -> String
  (optionOr (stringSlice s start end) "")

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn stripCr s: String -> String
  (if (stringEndsWith? s "\r") (sliceStr s 0 (- (stringLength s) 1)) s)

fn isDigitChar c: String -> Bool
  (stringContains? "0123456789" c)

fn isSymbolChar c: String -> Bool
  (and (not (stringEmpty? c)) (not (stringContains? " \t\r\n()[]{}\";:=?|" c)))

(schema LineMeasure (:f spaces Int64) (:f rest String) (:f diagnostics (List LexerDiagnostic)))

(schema IndentScanState (:f idx Int64) (:f spaces Int64) (:f inIndent Bool) (:f diags (List LexerDiagnostic)))

fn indentScan bs: Bytes len: Int64 i: Int64 spaces: Int64 lineNum: Int64 diags: (List LexerDiagnostic) -> IndentScanState
  (if (>= i len)
    (IndentScanState :idx i :spaces spaces :inIndent true :diags diags)
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 32) (indentScan bs len (+ i 1) (+ spaces 1) lineNum diags))
        ((= b 9) (indentScan bs len (+ i 1) (+ spaces 2) lineNum (cons (makeDiagnostic "W001" "tab in indentation converted to 2 spaces" lineNum (+ i 1)) diags)))
        (else (IndentScanState :idx i :spaces spaces :inIndent false :diags diags)))))

fn measureIndent rawLine: String lineNum: Int64 -> LineMeasure
  (let [(clean (stripCr rawLine)) (len (stringLength clean)) (finalState (indentScan (stringToBytes clean) len 0 0 lineNum (list)))] (let [(firstNonWhite finalState.idx) (rawSpaces finalState.spaces) (diags (listReverse finalState.diags)) (restContent (if (>= firstNonWhite len) "" (sliceStr clean firstNonWhite len)))] (if (= (mod rawSpaces 2) 1) (let [(w002 (makeDiagnostic "W002" "odd indentation rounded down to 2-space boundary" lineNum 1))] (LineMeasure :spaces (- rawSpaces 1) :rest restContent :diagnostics (cons w002 diags))) (LineMeasure :spaces rawSpaces :rest restContent :diagnostics diags))))

(schema SymbolRun (:f nextIdx Int64) (:f sym String))

fn symbolByte? b: Int64 -> Bool
  (not (or (= b 32) (or (= b 9) (or (= b 13) (or (= b 10) (or (= b 40) (or (= b 41) (or (= b 91) (or (= b 93) (or (= b 123) (or (= b 125) (or (= b 34) (or (= b 59) (or (= b 58) (or (= b 61) (or (= b 63) (= b 124)))))))))))))))))

fn symbolEnd bs: Bytes k: Int64 len: Int64 -> Int64
  (if (and (< k len) (symbolByte? (bytesGet bs k))) (symbolEnd bs (+ k 1) len) k)

fn scanSymbolRun content: String bs: Bytes startIdx: Int64 len: Int64 -> SymbolRun
  (let [(e (symbolEnd bs startIdx len))] (SymbolRun :nextIdx e :sym (sliceStr content startIdx e)))

fn scanKeywordRun content: String bs: Bytes startIdx: Int64 len: Int64 -> SymbolRun
  (let [(run (scanSymbolRun content bs (+ startIdx 1) len))] (SymbolRun :nextIdx run.nextIdx :sym (str ":" run.sym)))

(schema TokenScanResult (:f nextIdx Int64) (:f tok IndentToken))

fn scanNumberOrSymbol content: String bs: Bytes startIdx: Int64 len: Int64 lineNum: Int64 colOffset: Int64 -> TokenScanResult
  (let [(run (scanSymbolRun content bs startIdx len)) (endK run.nextIdx) (raw run.sym)] (let [(isNum (or (and (> (stringLength raw) 0) (isDigitChar (charAt raw 0))) (and (> (stringLength raw) 1) (= (charAt raw 0) "-") (isDigitChar (charAt raw 1)))))] (if isNum (if (or (stringContains? raw ".") (or (stringContains? raw "e") (stringContains? raw "E"))) (let [(tok (makeIndentToken (mt (stringToFloat64 raw) ((some f) (tokFloat f)) ((none) (tokSymbol raw))) raw lineNum (+ colOffset startIdx 1)))] (TokenScanResult :nextIdx endK :tok tok)) (let [(ival (optionOr (stringToInt64 raw) 0)) (tok (makeIndentToken (tokInt ival) raw lineNum (+ colOffset startIdx 1)))] (TokenScanResult :nextIdx endK :tok tok))) (let [(tok (makeIndentToken (tokSymbol raw) raw lineNum (+ colOffset startIdx 1)))] (TokenScanResult :nextIdx endK :tok tok)))))

(schema StringScanResult (:f rawVal String) (:f consumed Int64) (:f closed Bool) (:f escOpen Bool))

(schema PendingRaw (:f buf String) (:f esc Bool) (:f startCol Int64))

(schema PendingString (:f buf String) (:f esc Bool) (:f startLine Int64) (:f startCol Int64))

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteChar n: Int64 -> String
  (sliceStr (byteTable) n (+ n 1))

fn utf8Of cp: Int64 -> String
  (cond
    ((< cp 128) (byteChar cp))
    ((< cp 2048) (str (byteChar (+ 192 (/ cp 64))) (byteChar (+ 128 (mod cp 64)))))
    ((< cp 65536) (str (byteChar (+ 224 (/ cp 4096))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64)))))
    (else (str (byteChar (+ 240 (/ cp 262144))) (byteChar (+ 128 (mod (/ cp 4096) 64))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64))))))

fn hexDigitAt s: String i: Int64 -> Int64
  (let [(c (sliceStr s i (+ i 1)))]
    (if (= (stringLength c) 1) (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) -1) -1))

fn hexRun s: String i: Int64 count: Int64 acc: Int64 -> Int64
  (if (<= count 0)
    acc
    (let [(d (hexDigitAt s i))]
      (if (< d 0) -1 (hexRun s (+ i 1) (- count 1) (+ (* acc 16) d)))))

fn scalarValue? cp: Int64 -> Bool
  (and (>= cp 0) (and (<= cp 1114111) (or (< cp 55296) (> cp 57343))))

fn bracedRun s: String i: Int64 count: Int64 acc: Int64 -> (Pair Int64 Int64)
  (let [(d (hexDigitAt s i))]
    (cond
      ((= (sliceStr s i (+ i 1)) "}") (if (and (> count 0) (scalarValue? acc)) (pair acc (+ i 1)) (pair -1 i)))
      ((and (>= d 0) (< count 6)) (bracedRun s (+ i 1) (+ count 1) (+ (* acc 16) d)))
      (else (pair -1 i))))

fn unicodeAt s: String i: Int64 -> (Pair Int64 Int64)
  (if (= (sliceStr s i (+ i 1)) "{")
    (bracedRun s (+ i 1) 0 0)
    (let [(cp (hexRun s i 4 0))]
      (if (scalarValue? cp) (pair cp (+ i 4)) (pair -1 i))))

fn decodeLoop s: String i: Int64 n: Int64 acc: (List String) -> (Pair String String)
  (if (>= i n)
    (pair (stringJoin (listReverse acc) "") "")
    (let [(c (sliceStr s i (+ i 1)))]
      (if (!= c "\\")
        (decodeLoop s (+ i 1) n (cons c acc))
        (let [(e (sliceStr s (+ i 1) (+ i 2)))
              (x (hexRun s (+ i 2) 2 0))
              (u (if (= e "u") (unicodeAt s (+ i 2)) (pair -1 i)))]
          (cond
            ((= e "n") (decodeLoop s (+ i 2) n (cons "\n" acc)))
            ((= e "t") (decodeLoop s (+ i 2) n (cons "\t" acc)))
            ((= e "r") (decodeLoop s (+ i 2) n (cons "\r" acc)))
            ((or (= e "\"") (= e "\\")) (decodeLoop s (+ i 2) n (cons e acc)))
            ((and (= e "x") (>= x 0)) (decodeLoop s (+ i 4) n (cons (byteChar x) acc)))
            ((= e "x") (pair (stringJoin (listReverse acc) "") "\\x needs exactly 2 hex digits"))
            ((>= (pairFirst u) 0) (decodeLoop s (pairSecond u) n (cons (utf8Of (pairFirst u)) acc)))
            ((= e "u") (pair (stringJoin (listReverse acc) "") "\\u needs 4 hex digits or {1 to 6 hex digits} naming a scalar value"))
            (else (pair (stringJoin (listReverse acc) "") (str "unknown escape \\" e))))))))

fn decodeEscapes raw: String -> (Pair String String)
  (if (stringContains? raw "\\") (decodeLoop raw 0 (stringLength raw) (list)) (pair raw ""))

fn escapeDiags dec: (Pair String String) l: Int64 c: Int64 diags: (List LexerDiagnostic) -> (List LexerDiagnostic)
  (if (stringEmpty? (pairSecond dec)) diags (cons (makeDiagnostic "E019" (str "ERR_BAD_ESCAPE " (pairSecond dec)) l c) diags))

(schema StringEnd (:f idx Int64) (:f closed Bool) (:f esc Bool))

fn stringEndScan bs: Bytes i: Int64 len: Int64 esc: Bool -> StringEnd
  (if (>= i len)
    (StringEnd :idx len :closed false :esc esc)
    (let [(b (bytesGet bs i))]
      (cond
        (esc (stringEndScan bs (+ i 1) len false))
        ((= b 92) (stringEndScan bs (+ i 1) len true))
        ((= b 34) (StringEnd :idx i :closed true :esc false))
        (else (stringEndScan bs (+ i 1) len false)))))

fn scanStringBytes src: String bs: Bytes startIdx: Int64 srcLen: Int64 initBuf: String initEsc: Bool -> StringScanResult
  (let [(start (if (< startIdx 0) 0 (+ startIdx 1)))
        (effEsc (and initEsc (< startIdx 0)))
        (e (stringEndScan bs start srcLen effEsc))
        (bodyEnd (cond (e.closed e.idx) (e.esc (- srcLen 1)) (else srcLen)))
        (lead (if (and effEsc (< start srcLen)) "\\" ""))
        (body (if (< start bodyEnd) (sliceStr src start bodyEnd) ""))]
    (StringScanResult :rawVal (str initBuf lead body) :consumed (if e.closed (+ e.idx 1) srcLen) :closed e.closed :escOpen e.esc))

fn scanStringLiteral src: String startIdx: Int64 srcLen: Int64 initBuf: String initEsc: Bool -> StringScanResult
  (scanStringBytes src (stringToBytes src) startIdx srcLen initBuf initEsc)

(schema LineTokensResult (:f reversed (List IndentToken)) (:f diagnostics (List LexerDiagnostic)) (:f pendingStr (Option PendingRaw)))

(schema LineScanState (:f idx Int64) (:f toks (List IndentToken)) (:f diags (List LexerDiagnostic)) (:f openBrackets Int64) (:f pendingStr (Option PendingRaw)))

fn blankByte? b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn blankEnd bs: Bytes i: Int64 len: Int64 -> Int64
  (if (and (< i len) (blankByte? (bytesGet bs i))) (blankEnd bs (+ i 1) len) i)

fn lineScan content: String bs: Bytes len: Int64 lineNum: Int64 colOffset: Int64 st: LineScanState -> LineScanState
  (let [(idx st.idx)] (cond ((>= idx len) st) ((blankByte? (bytesGet bs idx)) (lineScan content bs len lineNum colOffset (with st :idx (blankEnd bs idx len)))) (else (lineScan content bs len lineNum colOffset (let [(c (bytesGet bs idx))] (cond ((or (= c 32) (= c 9)) (LineScanState :idx (+ idx 1) :toks st.toks :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) ((= c 59) (LineScanState :idx len :toks st.toks :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) ((= c 40) (let [(t (makeIndentToken (tokLparen) "(" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((= c 41) (let [(t (makeIndentToken (tokRparen) ")" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((= c 91) (let [(t (makeIndentToken (tokLbracket) "[" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets (+ st.openBrackets 1) :pendingStr st.pendingStr))) ((= c 93) (let [(t (makeIndentToken (tokRbracket) "]" lineNum (+ colOffset idx 1))) (nxtBrk (if (> st.openBrackets 0) (- st.openBrackets 1) 0))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets nxtBrk :pendingStr st.pendingStr))) ((= c 123) (let [(t (makeIndentToken (tokLbrace) "{" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((= c 125) (let [(t (makeIndentToken (tokRbrace) "}" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((= c 60) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (= nextC "=") (let [(t (makeIndentToken (tokSymbol "<=") "<=" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(numSym (scanNumberOrSymbol content bs idx len lineNum colOffset)) (endK numSym.nextIdx) (tok numSym.tok)] (LineScanState :idx endK :toks (cons tok st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 62) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (= nextC "=") (let [(t (makeIndentToken (tokSymbol ">=") ">=" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(numSym (scanNumberOrSymbol content bs idx len lineNum colOffset)) (endK numSym.nextIdx) (tok numSym.tok)] (LineScanState :idx endK :toks (cons tok st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 33) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (= nextC "=") (let [(t (makeIndentToken (tokSymbol "!=") "!=" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(numSym (scanNumberOrSymbol content bs idx len lineNum colOffset)) (endK numSym.nextIdx) (tok numSym.tok)] (LineScanState :idx endK :toks (cons tok st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 61) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (= nextC "=") (let [(t (makeIndentToken (tokSymbol "==") "==" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(t (makeIndentToken (tokEqual) "=" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 63) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (cond ((= nextC "?") (let [(t (makeIndentToken (tokCoalesce) "??" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((= nextC ".") (let [(t (makeIndentToken (tokOptChain) "?." lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) (else (let [(t (makeIndentToken (tokQuestion) "?" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)))))) ((= c 124) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (= nextC ">") (let [(t (makeIndentToken (tokPipe) "|>" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(t (makeIndentToken (tokSymbol "|") "|" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 45) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (cond ((= nextC ">") (let [(t (makeIndentToken (tokArrow) "->" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 2) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((isDigitChar nextC) (let [(numSym (scanNumberOrSymbol content bs idx len lineNum colOffset)) (endK numSym.nextIdx) (tok numSym.tok)] (LineScanState :idx endK :toks (cons tok st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))) ((or (= nextC " ") (= nextC "\t") (= nextC "")) (if (listEmpty? st.toks) (let [(t (makeIndentToken (tokBullet) "-" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(t (makeIndentToken (tokSymbol "-") "-" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)))) (else (let [(t (makeIndentToken (tokSymbol "-") "-" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)))))) ((= c 58) (let [(nextC (if (< (+ idx 1) len) (charAt content (+ idx 1)) ""))] (if (isSymbolChar nextC) (let [(kwRun (scanKeywordRun content bs idx len)) (endK kwRun.nextIdx) (kw kwRun.sym) (t (makeIndentToken (tokKeyword kw) kw lineNum (+ colOffset idx 1)))] (LineScanState :idx endK :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)) (let [(t (makeIndentToken (tokColon) ":" lineNum (+ colOffset idx 1)))] (LineScanState :idx (+ idx 1) :toks (cons t st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr))))) ((= c 34) (let [(strRes (scanStringBytes content bs idx len "" false))] (if strRes.closed (let [(dec (decodeEscapes strRes.rawVal)) (plain (pairFirst dec)) (t (makeIndentToken (tokString plain) plain lineNum (+ colOffset idx 1)))] (LineScanState :idx strRes.consumed :toks (cons t st.toks) :diags (escapeDiags dec lineNum (+ colOffset idx 1) st.diags) :openBrackets st.openBrackets :pendingStr st.pendingStr)) (LineScanState :idx strRes.consumed :toks st.toks :diags st.diags :openBrackets st.openBrackets :pendingStr (some (PendingRaw :buf strRes.rawVal :esc strRes.escOpen :startCol (+ colOffset idx 1))))))) (else (let [(numSym (scanNumberOrSymbol content bs idx len lineNum colOffset)) (endK numSym.nextIdx) (tok numSym.tok)] (LineScanState :idx endK :toks (cons tok st.toks) :diags st.diags :openBrackets st.openBrackets :pendingStr st.pendingStr)))))))))

fn scanLineContent content: String lineNum: Int64 colOffset: Int64 -> LineTokensResult
  (let [(len (stringLength content)) (bs (stringToBytes content))] (let [(finalState (lineScan content bs len lineNum colOffset (LineScanState :idx 0 :toks (list) :diags (list) :openBrackets 0 :pendingStr (none))))] (let [(toksRev finalState.toks) (diags finalState.diags)] (LineTokensResult :reversed toksRev :diagnostics diags :pendingStr finalState.pendingStr))))

(schema TokenizeState (:f stack (List Int64)) (:f tokens (List IndentToken)) (:f diagnostics (List LexerDiagnostic)) (:f lineCount Int64) (:f hasEmitted Bool) (:f depth Int64) (:f pendingString (Option PendingString)))

fn delimDelta toks: (List IndentToken) -> Int64
  (fold (fn [(acc Int64) (t IndentToken)] -> Int64 (mt t.kind ((tokLparen) (+ acc 1)) ((tokLbracket) (+ acc 1)) ((tokLbrace) (+ acc 1)) ((tokRparen) (- acc 1)) ((tokRbracket) (- acc 1)) ((tokRbrace) (- acc 1)) (_ acc))) 0 toks)

fn pendingFromLine p: (Option PendingRaw) lNum: Int64 -> (Option PendingString)
  (mt p ((some pr) (some (PendingString :buf pr.buf :esc pr.esc :startLine lNum :startCol pr.startCol))) ((none) (none)))

fn tokenizeLineNormal st: TokenizeState line: String lNum: Int64 -> TokenizeState
  (let [(meas (measureIndent line lNum)) (content meas.rest) (diags (listAppend meas.diagnostics st.diagnostics))]
    (if (stringEmpty? content)
      (with st :diagnostics diags :lineCount lNum :pendingString (none))
      (if (or (stringStartsWith? content ";") (stringStartsWith? content "#"))
        (with st :diagnostics diags :lineCount lNum :pendingString (none))
        (let [(firstRes (scanLineContent content lNum meas.spaces)) (moved (+ st.depth (delimDelta firstRes.reversed))) (nd (if (< moved 0) 0 moved)) (pendOut (pendingFromLine firstRes.pendingStr lNum))]
          (if (> st.depth 0)
            (with st :tokens (listAppend firstRes.reversed st.tokens) :diagnostics (listAppend firstRes.diagnostics diags) :lineCount lNum :hasEmitted true :depth nd :pendingString pendOut)
            (let [(curLevel (/ meas.spaces 2)) (topLevel (optionOr (listHead st.stack) 0)) (lineRes firstRes) (lineToksRev lineRes.reversed) (allDiags (listAppend lineRes.diagnostics diags))]
              (cond
                ((> curLevel topLevel) (let [(indTok (makeIndentToken (tokIndent curLevel) "" lNum 1)) (newStack (cons curLevel st.stack)) (newToks (listAppend lineToksRev (cons indTok st.tokens)))] (TokenizeState :stack newStack :tokens newToks :diagnostics allDiags :lineCount lNum :hasEmitted true :depth nd :pendingString pendOut)))
                ((< curLevel topLevel) (let [(popRes (fold (fn [(acc (Pair (List Int64) (List IndentToken))) (_ Int64)] -> (Pair (List Int64) (List IndentToken)) (let [(stk (pairFirst acc)) (dtoks (pairSecond acc)) (tp (optionOr (listHead stk) 0))] (if (> tp curLevel) (let [(nxtStk (optionOr (listTail stk) (list))) (nxtTp (optionOr (listHead nxtStk) 0)) (dtok (makeIndentToken (tokDedent nxtTp) "" lNum 1))] (pair nxtStk (cons dtok dtoks))) acc))) (pair st.stack (list)) st.stack))] (let [(nxtStack (pairFirst popRes)) (dedToks (pairSecond popRes)) (newToks (listAppend lineToksRev (listAppend dedToks st.tokens)))] (TokenizeState :stack nxtStack :tokens newToks :diagnostics allDiags :lineCount lNum :hasEmitted true :depth nd :pendingString pendOut))))
                (else (let [(preToks (if st.hasEmitted (cons (makeIndentToken (tokNewline) "" lNum 1) st.tokens) st.tokens)) (newToks (listAppend lineToksRev preToks))] (with st :tokens newToks :diagnostics allDiags :lineCount lNum :hasEmitted true :depth nd :pendingString pendOut))))))))))

fn tokenizeLineContinuation st: TokenizeState pend: PendingString line: String lNum: Int64 -> TokenizeState
  (let [(cleanLine (stripCr line)) (chunk (str "\n" cleanLine)) (r (scanStringLiteral chunk -1 (stringLength chunk) pend.buf pend.esc))]
    (if r.closed
      (let [(dec (decodeEscapes r.rawVal)) (decoded (pairFirst dec)) (tok (makeIndentToken (tokString decoded) decoded pend.startLine pend.startCol)) (remStart (- r.consumed 1)) (remainder (sliceStr cleanLine remStart (stringLength cleanLine))) (remRes (scanLineContent remainder lNum remStart)) (newToks (cons tok (listReverse remRes.reversed))) (moved (+ st.depth (delimDelta newToks))) (nd (if (< moved 0) 0 moved))]
        (with st :tokens (listAppend (listReverse newToks) st.tokens) :diagnostics (escapeDiags dec pend.startLine pend.startCol (listAppend remRes.diagnostics st.diagnostics)) :lineCount lNum :hasEmitted true :depth nd :pendingString (pendingFromLine remRes.pendingStr lNum)))
      (with st :lineCount lNum :pendingString (some (with pend :buf r.rawVal :esc r.escOpen)))))

fn tokenizeLines lines: (List String) -> (Pair (List IndentToken) (List LexerDiagnostic))
  (let [(finalState (fold (fn [(st TokenizeState) (line String)] -> TokenizeState (let [(lNum (+ st.lineCount 1))] (mt st.pendingString ((some pend) (tokenizeLineContinuation st pend line lNum)) ((none) (tokenizeLineNormal st line lNum))))) (TokenizeState :stack (list 0) :tokens (list) :diagnostics (list) :lineCount 0 :hasEmitted false :depth 0 :pendingString (none)) lines))]
    (let [(finalLine finalState.lineCount) (finalStack finalState.stack) (unterminated finalState.pendingString)
          (openTok (mt unterminated ((some pend) (let [(decoded (pairFirst (decodeEscapes pend.buf)))] (list (makeIndentToken (tokString decoded) decoded pend.startLine pend.startCol)))) ((none) (list))))
          (openDiag (mt unterminated ((some pend) (list (makeDiagnostic "E010" "unterminated string literal" pend.startLine pend.startCol))) ((none) (list))))
          (remainingDedent (fold (fn [(acc (List IndentToken)) (lvl Int64)] -> (List IndentToken) (if (> lvl 0) (cons (makeIndentToken (tokDedent 0) "" (+ finalLine 1) 1) acc) acc)) (list) finalStack))
          (eofTok (makeIndentToken (tokEof) "" (+ finalLine 1) 1))
          (allTokens (listReverse (cons eofTok (listAppend remainingDedent (listAppend openTok finalState.tokens)))))]
      (pair allTokens (listReverse (listAppend openDiag finalState.diagnostics)))))

fn tokenizeIndented src: String -> (Pair (List IndentToken) (List LexerDiagnostic))
  (let [(lines (stringSplit src "\n"))] (tokenizeLines lines))

fn tokenize src: String -> (List IndentToken)
  (pairFirst (tokenizeIndented src))
