(module asl-syntax/asl/lex
  :x [tokenize
      tokenizeBytes
      tokenizeSource
      tokenSliceString
      tokenSliceBytes!
      isWhitespaceToken
      isNewlineToken
      isCommentToken
      isStringToken
      isKeywordToken
      isNumberToken
      isIntToken
      isFloatToken
      isSymbolToken
      isLparen
      isRparen
      isLbracket
      isRbracket
      isLbrace
      isRbrace
      isComma
      isError
      tokensToNode
      lexResume
      isPendingToken
      stringErrorAt]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)])

fn isWhitespaceToken tok: tr/Token -> Bool
  (= tok.kind "whitespace")

fn isNewlineToken tok: tr/Token -> Bool
  (= tok.kind "newline")

fn isCommentToken tok: tr/Token -> Bool
  (= tok.kind "comment")

fn isStringToken tok: tr/Token -> Bool
  (= tok.kind "string")

fn isKeywordToken tok: tr/Token -> Bool
  (= tok.kind "keyword")

fn isIntToken tok: tr/Token -> Bool
  (= tok.kind "int")

fn isFloatToken tok: tr/Token -> Bool
  (= tok.kind "float")

fn isNumberToken tok: tr/Token -> Bool
  (or (isIntToken tok) (isFloatToken tok))

fn isSymbolToken tok: tr/Token -> Bool
  (= tok.kind "symbol")

fn isLparen tok: tr/Token -> Bool
  (= tok.kind "lparen")

fn isRparen tok: tr/Token -> Bool
  (= tok.kind "rparen")

fn isLbracket tok: tr/Token -> Bool
  (= tok.kind "lbracket")

fn isRbracket tok: tr/Token -> Bool
  (= tok.kind "rbracket")

fn isLbrace tok: tr/Token -> Bool
  (= tok.kind "lbrace")

fn isRbrace tok: tr/Token -> Bool
  (= tok.kind "rbrace")

fn isComma tok: tr/Token -> Bool
  (= tok.kind "comma")

fn isError tok: tr/Token -> Bool
  (tr/isErrorToken tok)

fn copySlice! bs: Bytes srcIdx: Int64 dst: Bytes dstIdx: Int64 count: Int64 -> Unit
  (if (<= count 0)
    ()
    (do
      (bytesSet dst dstIdx (bytesGet bs srcIdx))
      (copySlice! bs (+ srcIdx 1) dst (+ dstIdx 1) (- count 1))))

fn tokenSliceString text: String tok: tr/Token -> String
  (optionOr (stringSlice text tok.start tok.end) "")

fn tokenSliceBytes! bs: Bytes tok: tr/Token -> Bytes
  (let [(len (tr/tokenLength tok))
        (out (bytesAlloc len))]
    (copySlice! bs tok.start out 0 len)
    out)

fn tokensToNode tokens: (List tr/Token) len: Int64 -> tr/Node
  (let [(elems (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) tokens))]
    (tr/makeNode "asl" 0 len elems))

fn isDelimByte b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 10)
  (or (= b 13)
  (or (= b 40)
  (or (= b 41)
  (or (= b 91)
  (or (= b 93)
  (or (= b 123)
  (or (= b 125)
  (or (= b 34)
  (or (= b 59)
      (= b 44)))))))))))))

fn isHexDigit b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
  (or (and (>= b 65) (<= b 70))
      (and (>= b 97) (<= b 102))))

fn scanWhitespace bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 32) (= b 9))
        (scanWhitespace bs len (+ i 1))
        i)))

fn scanComment bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 10) (= b 13))
        i
        (scanComment bs len (+ i 1)))))

fn lexPending start: Int64 resume: Int64 hasError: Bool -> tr/Token
  (tr/Token :kind (if hasError "pendingError" "pending") :start start :end resume)

fn isPendingToken tok: tr/Token -> Bool
  (or (= tok.kind "pending") (= tok.kind "pendingError"))

fn lexPunct kind: String start: Int64 -> tr/Token
  (tr/Token :kind kind :start start :end (+ start 1))

fn hexValue b: Int64 -> Int64
  (cond ((<= b 57) (- b 48)) ((<= b 70) (- b 55)) (else (- b 87)))

fn scanHexRun bs: Bytes len: Int64 p: Int64 count: Int64 -> Int64
  (if (<= count 0)
    -1
    (if (>= p len)
      -2
      (if (isHexDigit (bytesGet bs p))
        (scanHexRun bs len (+ p 1) (- count 1))
        p)))

fn hexRunValue bs: Bytes p: Int64 count: Int64 acc: Int64 -> Int64
  (if (<= count 0)
    acc
    (hexRunValue bs (+ p 1) (- count 1) (+ (* acc 16) (hexValue (bytesGet bs p)))))

fn scalarValue? cp: Int64 -> Bool
  (and (<= cp 1114111) (or (< cp 55296) (> cp 57343)))

fn scanBracedEscape bs: Bytes len: Int64 p: Int64 count: Int64 cp: Int64 -> (Pair Int64 Int64)
  (if (>= p len)
    (pair 2 p)
    (let [(b (bytesGet bs p))]
      (cond
        ((= b 125) (if (and (> count 0) (scalarValue? cp)) (pair 0 (+ p 1)) (pair 1 p)))
        ((and (isHexDigit b) (< count 6)) (scanBracedEscape bs len (+ p 1) (+ count 1) (+ (* cp 16) (hexValue b))))
        (else (pair 1 p)))))

fn scanFourHexEscape bs: Bytes len: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [(bad (scanHexRun bs len (+ i 2) 4))]
    (cond
      ((= bad -2) (pair 2 i))
      ((>= bad 0) (pair 1 bad))
      ((scalarValue? (hexRunValue bs (+ i 2) 4 0)) (pair 0 (+ i 6)))
      (else (pair 1 (+ i 5)))))

fn scanEscape bs: Bytes len: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [(e (bytesGet bs (+ i 1)))]
    (cond
      ((or (= e 110) (or (= e 116) (or (= e 114) (or (= e 92) (= e 34))))) (pair 0 (+ i 2)))
      ((= e 120)
       (let [(bad (scanHexRun bs len (+ i 2) 2))]
         (cond ((= bad -1) (pair 0 (+ i 4))) ((= bad -2) (pair 2 i)) (else (pair 1 bad)))))
      ((= e 117)
       (cond
         ((>= (+ i 2) len) (pair 2 i))
         ((= (bytesGet bs (+ i 2)) 123)
          (let [(r (scanBracedEscape bs len (+ i 3) 0 0))]
            (if (= (pairFirst r) 2) (pair 2 i) r)))
         (else (scanFourHexEscape bs len i))))
      (else (pair 1 (+ i 1)))))

fn scanStringFrom bs: Bytes len: Int64 i: Int64 start: Int64 hasError: Bool -> tr/Token
  (if (>= i len)
    (lexPending start len hasError)
    (let [(sb (bytesGet bs i))]
      (if (= sb 34)
        (tr/Token :kind (if hasError "error" "string") :start start :end (+ i 1))
        (if (= sb 92)
          (if (>= (+ i 1) len)
            (lexPending start i hasError)
            (let [(r (scanEscape bs len i))
                  (verdict (pairFirst r))]
              (cond
                ((= verdict 0) (scanStringFrom bs len (pairSecond r) start hasError))
                ((= verdict 1) (scanStringFrom bs len (+ i 2) start true))
                (else (lexPending start i hasError)))))
          (scanStringFrom bs len (+ i 1) start hasError)))))

fn finishString tok: tr/Token len: Int64 final: Bool -> tr/Token
  (if (and final (isPendingToken tok))
    (tr/Token :kind "error" :start tok.start :end len)
    tok)

fn stringErrorAt bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    -1
    (let [(sb (bytesGet bs i))]
      (cond
        ((= sb 34) -1)
        ((and (= sb 92) (< (+ i 1) len))
         (let [(r (scanEscape bs len i))
               (verdict (pairFirst r))]
           (cond
             ((= verdict 1) (pairSecond r))
             ((= verdict 0) (stringErrorAt bs len (pairSecond r)))
             (else -1))))
        ((= sb 92) -1)
        (else (stringErrorAt bs len (+ i 1))))))

fn scanAtomEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isDelimByte (bytesGet bs i))
      i
      (scanAtomEnd bs len (+ i 1))))

fn scanDigits bs: Bytes end: Int64 i: Int64 count: Int64 -> (Pair Int64 Int64)
  (if (>= i end)
    (pair i count)
    (let [(b (bytesGet bs i))]
      (if (and (>= b 48) (<= b 57))
        (scanDigits bs end (+ i 1) (+ count 1))
        (pair i count))))

fn checkFloatExponent bs: Bytes end: Int64 i: Int64 isFloat: Bool -> (Option String)
  (if (>= i end)
    (if isFloat (some "float") (some "int"))
    (let [(b (bytesGet bs i))]
      (if (or (= b 101) (= b 69))
        (let [(afterE (+ i 1))
              (afterSign (if (and (< afterE end) (or (= (bytesGet bs afterE) 45) (= (bytesGet bs afterE) 43)))
                           (+ afterE 1)
                           afterE))
              (expRes (scanDigits bs end afterSign 0))
              (expEnd (pairFirst expRes))
              (expCount (pairSecond expRes))]
          (if (= expCount 0)
            (none)
            (if (= expEnd end)
              (some "float")
              (none))))
        (none))))

fn checkFloatPoint bs: Bytes end: Int64 i: Int64 -> (Option String)
  (if (>= i end)
    (some "int")
    (let [(b (bytesGet bs i))]
      (if (= b 46)
        (let [(fracRes (scanDigits bs end (+ i 1) 0))
              (fracEnd (pairFirst fracRes))
              (fracCount (pairSecond fracRes))]
          (if (= fracCount 0)
            (none)
            (checkFloatExponent bs end fracEnd true)))
        (checkFloatExponent bs end i false))))

fn classifyNumber bs: Bytes start: Int64 end: Int64 -> (Option String)
  (let [(afterSign (if (and (< start end) (or (= (bytesGet bs start) 45) (= (bytesGet bs start) 43)))
                     (+ start 1)
                     start))
        (intRes (scanDigits bs end afterSign 0))
        (intEnd (pairFirst intRes))
        (intCount (pairSecond intRes))]
    (if (= intCount 0)
      (none)
      (checkFloatPoint bs end intEnd)))

fn makeAtomToken bs: Bytes start: Int64 end: Int64 -> tr/Token
  (let [(n (- end start))]
    (if (and (> n 1) (= (bytesGet bs start) 58))
      (tr/makeToken "keyword" start end)
      (mt (classifyNumber bs start end)
        ((some numKind) (tr/makeToken numKind start end))
        ((none) (tr/makeToken "symbol" start end)))))

fn bomPrefix? bs: Bytes len: Int64 -> Bool
  (or (= len 1) (and (= len 2) (= (bytesGet bs 1) 187)))

fn isBom? bs: Bytes len: Int64 -> Bool
  (and (>= len 3) (and (= (bytesGet bs 1) 187) (= (bytesGet bs 2) 191)))

fn lexResume bs: Bytes len: Int64 start: Int64 resume: Int64 hasError: Bool final: Bool -> tr/Token
  (let [(b (bytesGet bs start))
        (from (if (> resume start) resume (+ start 1)))]
    (cond
      ((and (= start 0) (and (= b 239) (and (not final) (bomPrefix? bs len))))
       (lexPending start start false))
      ((and (= start 0) (and (= b 239) (isBom? bs len)))
       (tr/Token :kind "bom" :start 0 :end 3))
      ((= b 10) (lexPunct "newline" start))
      ((= b 13)
       (cond
         ((< (+ start 1) len)
          (if (= (bytesGet bs (+ start 1)) 10)
            (tr/Token :kind "newline" :start start :end (+ start 2))
            (lexPunct "whitespace" start)))
         (final (lexPunct "whitespace" start))
         (else (lexPending start start false))))
      ((or (= b 32) (= b 9))
       (let [(end (scanWhitespace bs len from))]
         (if (or final (< end len))
           (tr/Token :kind "whitespace" :start start :end end)
           (lexPending start end false))))
      ((= b 59)
       (let [(end (scanComment bs len from))]
         (if (or final (< end len))
           (tr/Token :kind "comment" :start start :end end)
           (lexPending start end false))))
      ((= b 40) (lexPunct "lparen" start))
      ((= b 41) (lexPunct "rparen" start))
      ((= b 91) (lexPunct "lbracket" start))
      ((= b 93) (lexPunct "rbracket" start))
      ((= b 123) (lexPunct "lbrace" start))
      ((= b 125) (lexPunct "rbrace" start))
      ((= b 44) (lexPunct "comma" start))
      ((= b 34) (finishString (scanStringFrom bs len from start hasError) len final))
      (else
       (let [(end (scanAtomEnd bs len from))]
         (if (or final (< end len))
           (makeAtomToken bs start end)
           (lexPending start end false))))))

fn tokenizeLoop bs: Bytes len: Int64 i: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (>= i len)
    (listReverse acc)
    (let [(tok (lexResume bs len i i false true))]
      (tokenizeLoop bs len tok.end (cons tok acc))))

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tokenizeLoop bs (bytesLength bs) 0 (list))

fn tokenizeSource s: src/Source -> (List tr/Token)
  (tokenizeBytes (src/sourceBytes s))

fn tokenize text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))
