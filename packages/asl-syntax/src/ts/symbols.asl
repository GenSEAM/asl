(module asl-syntax/ts/symbols
  :x [TsSymbol
      makeTsSymbol
      tsSymbolName
      tsSymbolKind
      tsSymbolStart
      tsSymbolEnd
      tsSymbolStartLine
      tsSymbolEndLine
      tsSymbolDepth
      tsSymbolContainer
      tsSymbolToSymbolDef
      extractSymbols!
      extractSymbolsWithSource!
      extractSymbolsFromSource!
      tsSymbols!
      tsSymbolsFromSource!
      findSymbol
      findSymbolDotted
      nearestSymbols
      tsOutlineItems
      tsOutlineReceipt!]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)])

(schema TsSymbol
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f startLine Int64)
  (:f endLine Int64)
  (:f depth Int64)
  (:f container String))

(schema LineCandidate
  (:f kind String)
  (:f name String)
  (:f dstart Int64))

fn makeTsSymbol name: String kind: String start: Int64 end: Int64 startLine: Int64 endLine: Int64 depth: Int64 container: String -> TsSymbol
  (TsSymbol :name name :kind kind :start start :end end :startLine startLine :endLine endLine :depth depth :container container)

fn tsSymbolName s: TsSymbol -> String
  s.name

fn tsSymbolKind s: TsSymbol -> String
  s.kind

fn tsSymbolStart s: TsSymbol -> Int64
  s.start

fn tsSymbolEnd s: TsSymbol -> Int64
  s.end

fn tsSymbolStartLine s: TsSymbol -> Int64
  s.startLine

fn tsSymbolEndLine s: TsSymbol -> Int64
  s.endLine

fn tsSymbolDepth s: TsSymbol -> Int64
  s.depth

fn tsSymbolContainer s: TsSymbol -> String
  s.container

fn tsSymbolToSymbolDef s: TsSymbol -> sym/SymbolDef
  (sym/makeScopedSymbolDef s.name s.kind s.start s.end s.container s.depth)

fn isSpaceOrTab b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn isIdentStart b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
  (or (and (>= b 97) (<= b 122))
  (or (= b 95) (= b 36))))

fn isIdentPart b: Int64 -> Bool
  (or (isIdentStart b) (and (>= b 48) (<= b 57)))

fn isAlpha b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isWhitespaceByte b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))

fn skipSpaces bs: Bytes i: Int64 limit: Int64 -> Int64
  (if (and (< i limit) (isSpaceOrTab (bytesGet bs i)))
    (skipSpaces bs (+ i 1) limit)
    i)

fn readIdentEnd bs: Bytes i: Int64 limit: Int64 -> Int64
  (if (and (< i limit) (isIdentPart (bytesGet bs i)))
    (readIdentEnd bs (+ i 1) limit)
    i)

fn findChar bs: Bytes i: Int64 limit: Int64 target: Int64 -> Int64
  (if (>= i limit)
    -1
    (if (= (bytesGet bs i) target)
      i
      (findChar bs (+ i 1) limit target)))

fn textWordEq text: String st: Int64 en: Int64 kw: String -> Bool
  (if (!= (- en st) (stringLength kw))
    false
    (= (optionOr (stringSlice text st en) "") kw))

fn copyBytesLoop! src: Bytes dst: Bytes len: Int64 i: Int64 -> Unit
  (if (< i len)
    (do
      (bytesSet dst i (bytesGet src i))
      (copyBytesLoop! src dst len (+ i 1)))
    ())

fn blankLoop! masked: Bytes i: Int64 endOff: Int64 len: Int64 -> Unit
  (if (and (< i endOff) (< i len))
    (do
      (if (!= (bytesGet masked i) 10)
        (bytesSet masked i 32)
        ())
      (blankLoop! masked (+ i 1) endOff len))
    ())

fn findLineEnd bs: Bytes i: Int64 len: Int64 -> Int64
  (if (>= i len)
    len
    (if (= (bytesGet bs i) 10)
      i
      (findLineEnd bs (+ i 1) len)))

fn findBlockCommentEnd bs: Bytes i: Int64 len: Int64 -> Int64
  (if (>= (+ i 1) len)
    len
    (if (and (= (bytesGet bs i) 42) (= (bytesGet bs (+ i 1)) 47))
      (+ i 2)
      (findBlockCommentEnd bs (+ i 1) len)))

fn findQuoteEnd bs: Bytes i: Int64 len: Int64 quoteChar: Int64 -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 92)
         (findQuoteEnd bs (+ i 2) len quoteChar))
        ((= b quoteChar)
         (+ i 1))
        ((= b 10)
         i)
        (else
         (findQuoteEnd bs (+ i 1) len quoteChar)))))

fn findTemplateEnd bs: Bytes i: Int64 len: Int64 depth: Int64 -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 92)
         (findTemplateEnd bs (+ i 2) len depth))
        ((and (= b 96) (= depth 0))
         (+ i 1))
        ((and (= b 36) (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 123))
         (findTemplateEnd bs (+ i 2) len (+ depth 1)))
        ((and (= b 125) (> depth 0))
         (findTemplateEnd bs (+ i 1) len (- depth 1)))
        (else
         (findTemplateEnd bs (+ i 1) len depth)))))

fn skipRegexFlags bs: Bytes i: Int64 len: Int64 -> Int64
  (if (and (< i len) (isAlpha (bytesGet bs i)))
    (skipRegexFlags bs (+ i 1) len)
    i)

fn findRegexEnd bs: Bytes i: Int64 len: Int64 inClass: Bool -> Int64
  (if (>= i len)
    0
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 10) 0)
        ((= b 92) (findRegexEnd bs (+ i 2) len inClass))
        (inClass
         (if (= b 93)
           (findRegexEnd bs (+ i 1) len false)
           (findRegexEnd bs (+ i 1) len true)))
        (else
         (cond
           ((= b 91)
            (findRegexEnd bs (+ i 1) len true))
           ((= b 47)
            (skipRegexFlags bs (+ i 1) len))
           (else
            (findRegexEnd bs (+ i 1) len false)))))))

fn isRegexPrevWord text: String st: Int64 en: Int64 -> Bool
  (or (textWordEq text st en "of")
  (or (textWordEq text st en "typeof")
  (or (textWordEq text st en "return")
  (or (textWordEq text st en "do")
  (or (textWordEq text st en "throw")
  (or (textWordEq text st en "instanceof")
  (or (textWordEq text st en "void")
  (or (textWordEq text st en "yield")
  (or (textWordEq text st en "delete")
  (or (textWordEq text st en "in")
  (or (textWordEq text st en "case")
  (or (textWordEq text st en "await")
  (or (textWordEq text st en "else")
      (textWordEq text st en "new"))))))))))))))

fn isRegexSigChar c: Int64 -> Bool
  (or (= c 40) (or (= c 44) (or (= c 61) (or (= c 58)
  (or (= c 91) (or (= c 33) (or (= c 38) (or (= c 124)
  (or (= c 63) (or (= c 123) (or (= c 125) (or (= c 59)
  (or (= c 43) (or (= c 45) (or (= c 42) (or (= c 37)
  (or (= c 60) (or (= c 62) (or (= c 126) (= c 94))))))))))))))))))))

fn isRegexContext prevSig: Int64 text: String wSt: Int64 wEn: Int64 -> Bool
  (or (= prevSig 0)
  (or (isRegexSigChar prevSig)
  (and (= prevSig 97) (isRegexPrevWord text wSt wEn))))

fn maskLoop! text: String bs: Bytes masked: Bytes len: Int64 i: Int64 prevSig: Int64 prevWordSt: Int64 prevWordEn: Int64 -> Unit
  (if (>= i len)
    ()
    (let [(c (bytesGet bs i))
          (nx (if (< (+ i 1) len) (bytesGet bs (+ i 1)) 0))]
      (cond
        ((and (= c 47) (= nx 47))
         (let [(j (findLineEnd bs i len))]
           (do
             (blankLoop! masked i j len)
             (maskLoop! text bs masked len j prevSig prevWordSt prevWordEn))))
        ((and (= c 47) (= nx 42))
         (let [(j (findBlockCommentEnd bs (+ i 2) len))]
           (do
             (blankLoop! masked i j len)
             (maskLoop! text bs masked len j prevSig prevWordSt prevWordEn))))
        ((or (= c 34) (= c 39))
         (let [(j (findQuoteEnd bs (+ i 1) len c))]
           (do
             (blankLoop! masked i j len)
             (maskLoop! text bs masked len j 97 0 0))))
        ((= c 96)
         (let [(j (findTemplateEnd bs (+ i 1) len 0))]
           (do
             (blankLoop! masked i j len)
             (maskLoop! text bs masked len j 97 0 0))))
        ((and (= c 47) (isRegexContext prevSig text prevWordSt prevWordEn))
         (let [(j (findRegexEnd bs (+ i 1) len false))]
           (if (> j (+ i 1))
             (do
               (blankLoop! masked i j len)
               (maskLoop! text bs masked len j 97 0 0))
             (maskLoop! text bs masked len (+ i 1) c 0 0))))
        ((isWhitespaceByte c)
         (maskLoop! text bs masked len (+ i 1) prevSig prevWordSt prevWordEn))
        ((isIdentStart c)
         (let [(j (readIdentEnd bs (+ i 1) len))]
           (maskLoop! text bs masked len j 97 i j)))
        (else
         (maskLoop! text bs masked len (+ i 1) c 0 0)))))

fn maskCode! text: String bs: Bytes len: Int64 -> Bytes
  (let [(masked (bytesAlloc len))]
    (do
      (copyBytesLoop! bs masked len 0)
      (maskLoop! text bs masked len 0 0 0 0)
      masked))

fn skipTrailingSpacesAndSemicolon bs: Bytes j: Int64 n: Int64 -> Int64
  (let [(jSp (skipSpaces bs j n))]
    (if (< jSp n)
      (let [(ch (bytesGet bs jSp))]
        (if (or (= ch 59) (= ch 44))
          (+ jSp 1)
          jSp))
      jSp))

fn isContPrevChar c: Int64 -> Bool
  (or (= c 61) (or (= c 62) (or (= c 44) (or (= c 40)
  (or (= c 58) (or (= c 124) (or (= c 38) (or (= c 43)
  (or (= c 45) (or (= c 42) (or (= c 47) (= c 63))))))))))))

fn isContNextChar c: Int64 -> Bool
  (or (= c 123) (or (= c 46) (or (= c 61) (or (= c 124)
  (or (= c 38) (or (= c 63) (= c 58)))))))

fn findLastNonSpaceBefore bs: Bytes p: Int64 floor: Int64 -> Int64
  (if (< p floor)
    (- floor 1)
    (let [(b (bytesGet bs p))]
      (if (isWhitespaceByte b)
        (findLastNonSpaceBefore bs (- p 1) floor)
        p)))

fn findFirstNonSpaceAfter bs: Bytes k: Int64 limit: Int64 -> Int64
  (if (>= k limit)
    limit
    (let [(b (bytesGet bs k))]
      (if (isWhitespaceByte b)
        (findFirstNonSpaceAfter bs (+ k 1) limit)
        k)))

fn braceBlockEndLoop bs: Bytes i: Int64 n: Int64 start: Int64 stackDepth: Int64 body: Bool -> Int64
  (if (>= i n)
    n
    (let [(ch (bytesGet bs i))]
      (cond
        ((or (= ch 40) (or (= ch 91) (= ch 123)))
         (let [(newBody (if (and (= ch 123) (= stackDepth 0)) true body))]
           (braceBlockEndLoop bs (+ i 1) n start (+ stackDepth 1) newBody)))
        ((or (= ch 41) (or (= ch 93) (= ch 125)))
         (let [(newDepth (if (> stackDepth 0) (- stackDepth 1) 0))]
           (if (and (= newDepth 0) (and body (= ch 125)))
             (skipTrailingSpacesAndSemicolon bs (+ i 1) n)
             (braceBlockEndLoop bs (+ i 1) n start newDepth body))))
        ((and (= ch 59) (and (= stackDepth 0) (not body)))
         (+ i 1))
        ((and (= ch 10) (and (= stackDepth 0) (not body)))
         (let [(p (findLastNonSpaceBefore bs (- i 1) start))]
           (if (< p start)
             (braceBlockEndLoop bs (+ i 1) n start stackDepth body)
             (let [(prevChar (bytesGet bs p))
                   (k (findFirstNonSpaceAfter bs (+ i 1) n))
                   (nxtChar (if (< k n) (bytesGet bs k) 0))]
               (if (and (not (isContPrevChar prevChar)) (not (isContNextChar nxtChar)))
                 i
                 (braceBlockEndLoop bs (+ i 1) n start stackDepth body))))))
        (else
         (braceBlockEndLoop bs (+ i 1) n start stackDepth body)))))

fn braceBlockEnd bs: Bytes start: Int64 n: Int64 -> Int64
  (braceBlockEndLoop bs start n start 0 false)

fn isNotMethodName name: String -> Bool
  (or (= name "if")
  (or (= name "for")
  (or (= name "while")
  (or (= name "switch")
  (or (= name "catch")
  (or (= name "function")
  (or (= name "return")
  (or (= name "with")
  (or (= name "else")
  (or (= name "do")
  (or (= name "try")
  (or (= name "new")
  (or (= name "typeof")
  (or (= name "await")
      (= name "super")))))))))))))))

fn skipFunctionPrefixes bs: Bytes text: String idx: Int64 lend: Int64 -> Int64
  (let [(wEnd (readIdentEnd bs idx lend))]
    (if (and (> wEnd idx) (or (textWordEq text idx wEnd "export")
                          (or (textWordEq text idx wEnd "default")
                          (or (textWordEq text idx wEnd "declare")
                              (textWordEq text idx wEnd "async")))))
      (skipFunctionPrefixes bs text (skipSpaces bs wEnd lend) lend)
      idx))

fn checkFunction bs: Bytes text: String i: Int64 lend: Int64 lstart: Int64 -> (Option LineCandidate)
  (let [(fIdx (skipFunctionPrefixes bs text i lend))
        (wEnd (readIdentEnd bs fIdx lend))]
    (if (textWordEq text fIdx wEnd "function")
      (let [(afterFn (skipSpaces bs wEnd lend))
            (afterStar (if (and (< afterFn lend) (= (bytesGet bs afterFn) 42))
                         (skipSpaces bs (+ afterFn 1) lend)
                         afterFn))
            (nameEnd (readIdentEnd bs afterStar lend))]
        (if (> nameEnd afterStar)
          (let [(name (optionOr (stringSlice text afterStar nameEnd) ""))]
            (some (LineCandidate :kind "function" :name name :dstart lstart)))
          (none)))
      (none)))

fn skipClassPrefixes bs: Bytes text: String idx: Int64 lend: Int64 -> Int64
  (let [(wEnd (readIdentEnd bs idx lend))]
    (if (and (> wEnd idx) (or (textWordEq text idx wEnd "export")
                          (or (textWordEq text idx wEnd "default")
                          (or (textWordEq text idx wEnd "declare")
                              (textWordEq text idx wEnd "abstract")))))
      (skipClassPrefixes bs text (skipSpaces bs wEnd lend) lend)
      idx))

fn checkClass bs: Bytes text: String i: Int64 lend: Int64 lstart: Int64 -> (Option LineCandidate)
  (let [(cIdx (skipClassPrefixes bs text i lend))
        (wEnd (readIdentEnd bs cIdx lend))]
    (if (textWordEq text cIdx wEnd "class")
      (let [(afterCls (skipSpaces bs wEnd lend))
            (nameEnd (readIdentEnd bs afterCls lend))]
        (if (> nameEnd afterCls)
          (let [(name (optionOr (stringSlice text afterCls nameEnd) ""))]
            (some (LineCandidate :kind "class" :name name :dstart lstart)))
          (none)))
      (none)))

fn skipInterfacePrefixes bs: Bytes text: String idx: Int64 lend: Int64 -> Int64
  (let [(wEnd (readIdentEnd bs idx lend))]
    (if (and (> wEnd idx) (or (textWordEq text idx wEnd "export")
                              (textWordEq text idx wEnd "declare")))
      (skipInterfacePrefixes bs text (skipSpaces bs wEnd lend) lend)
      idx))

fn checkInterface bs: Bytes text: String i: Int64 lend: Int64 lstart: Int64 -> (Option LineCandidate)
  (let [(pIdx (skipInterfacePrefixes bs text i lend))
        (wEnd (readIdentEnd bs pIdx lend))]
    (if (or (textWordEq text pIdx wEnd "interface")
        (or (textWordEq text pIdx wEnd "enum")
            (textWordEq text pIdx wEnd "namespace")))
      (let [(afterKw (skipSpaces bs wEnd lend))
            (nameEnd (readIdentEnd bs afterKw lend))]
        (if (> nameEnd afterKw)
          (let [(name (optionOr (stringSlice text afterKw nameEnd) ""))]
            (some (LineCandidate :kind "interface" :name name :dstart lstart)))
          (none)))
      (none)))

fn checkType bs: Bytes text: String i: Int64 lend: Int64 lstart: Int64 -> (Option LineCandidate)
  (let [(pIdx (skipInterfacePrefixes bs text i lend))
        (wEnd (readIdentEnd bs pIdx lend))]
    (if (textWordEq text pIdx wEnd "type")
      (let [(afterKw (skipSpaces bs wEnd lend))
            (nameEnd (readIdentEnd bs afterKw lend))]
        (if (> nameEnd afterKw)
          (let [(name (optionOr (stringSlice text afterKw nameEnd) ""))
                (afterName (skipSpaces bs nameEnd lend))
                (afterGen (if (and (< afterName lend) (= (bytesGet bs afterName) 60))
                            (let [(eqPos (findChar bs afterName lend 61))
                                  (gtPos (findChar bs afterName lend 62))]
                              (if (and (!= gtPos -1) (or (= eqPos -1) (< gtPos eqPos)))
                                (skipSpaces bs (+ gtPos 1) lend)
                                afterName))
                            afterName))]
            (if (and (< afterGen lend) (= (bytesGet bs afterGen) 61))
              (some (LineCandidate :kind "type" :name name :dstart lstart))
              (none)))
          (none)))
      (none)))

fn skipVarPrefixes bs: Bytes text: String idx: Int64 lend: Int64 -> Int64
  (let [(wEnd (readIdentEnd bs idx lend))]
    (if (and (> wEnd idx) (or (textWordEq text idx wEnd "export")
                              (textWordEq text idx wEnd "declare")))
      (skipVarPrefixes bs text (skipSpaces bs wEnd lend) lend)
      idx))

fn checkVariable bs: Bytes text: String lstart: Int64 lend: Int64 -> (Option LineCandidate)
  (let [(vIdx (skipVarPrefixes bs text lstart lend))
        (wEnd (readIdentEnd bs vIdx lend))]
    (if (or (textWordEq text vIdx wEnd "const")
        (or (textWordEq text vIdx wEnd "let")
            (textWordEq text vIdx wEnd "var")))
      (let [(afterKw (skipSpaces bs wEnd lend))
            (nameEnd (readIdentEnd bs afterKw lend))]
        (if (> nameEnd afterKw)
          (let [(remIdx (skipSpaces bs nameEnd lend))]
            (if (< remIdx lend)
              (let [(ch (bytesGet bs remIdx))]
                (cond
                  ((= ch 61)
                   (let [(name (optionOr (stringSlice text afterKw nameEnd) ""))]
                     (some (LineCandidate :kind "variable" :name name :dstart lstart))))
                  ((= ch 58)
                   (let [(eqPos (findChar bs remIdx lend 61))]
                     (if (!= eqPos -1)
                       (let [(name (optionOr (stringSlice text afterKw nameEnd) ""))]
                         (some (LineCandidate :kind "variable" :name name :dstart lstart)))
                       (none))))
                  (else (none))))
              (none)))
          (none)))
      (none)))

fn skipMethodPrefixes bs: Bytes text: String idx: Int64 lend: Int64 -> Int64
  (let [(wEnd (readIdentEnd bs idx lend))]
    (if (and (> wEnd idx)
             (or (textWordEq text idx wEnd "public")
             (or (textWordEq text idx wEnd "private")
             (or (textWordEq text idx wEnd "protected")
             (or (textWordEq text idx wEnd "static")
             (or (textWordEq text idx wEnd "readonly")
             (or (textWordEq text idx wEnd "async")
             (or (textWordEq text idx wEnd "override")
             (or (textWordEq text idx wEnd "abstract")
             (or (textWordEq text idx wEnd "get")
                 (textWordEq text idx wEnd "set")))))))))))
      (let [(afterSp (skipSpaces bs wEnd lend))]
        (if (and (< afterSp lend) (isIdentStart (bytesGet bs afterSp)))
          (skipMethodPrefixes bs text afterSp lend)
          idx))
      idx))

fn checkMethod bs: Bytes text: String i: Int64 lend: Int64 lstart: Int64 -> (Option LineCandidate)
  (let [(mIdx (skipMethodPrefixes bs text i lend))
        (wEnd (readIdentEnd bs mIdx lend))]
    (if (> wEnd mIdx)
      (let [(word (optionOr (stringSlice text mIdx wEnd) ""))]
        (if (and (not (isNotMethodName word)) (isIdentStart (bytesGet bs mIdx)))
          (let [(afterWord (skipSpaces bs wEnd lend))
                (afterGen (if (and (< afterWord lend) (= (bytesGet bs afterWord) 60))
                            (let [(gt (findChar bs afterWord lend 62))]
                              (if (!= gt -1) (skipSpaces bs (+ gt 1) lend) afterWord))
                            afterWord))]
            (if (and (< afterGen lend) (= (bytesGet bs afterGen) 40))
              (let [(rp (findChar bs afterGen lend 41))]
                (if (!= rp -1)
                  (let [(afterRp (skipSpaces bs (+ rp 1) lend))]
                    (if (< afterRp lend)
                      (let [(ch (bytesGet bs afterRp))]
                        (cond
                          ((= ch 123)
                           (some (LineCandidate :kind "method" :name word :dstart lstart)))
                          ((= ch 58)
                           (let [(brace (findChar bs afterRp lend 123))]
                             (if (!= brace -1)
                               (some (LineCandidate :kind "method" :name word :dstart lstart))
                               (none))))
                          (else (none))))
                      (none)))
                  (none)))
              (none)))
          (none)))
      (none)))

fn checkLine bs: Bytes text: String lstart: Int64 lend: Int64 -> (Option LineCandidate)
  (let [(i (skipSpaces bs lstart lend))]
    (if (>= i lend)
      (none)
      (let [(indent (- i lstart))
            (fnCand (checkFunction bs text i lend lstart))]
        (mt fnCand
          ((some c) (some c))
          ((none)
           (let [(clsCand (checkClass bs text i lend lstart))]
             (mt clsCand
               ((some c) (some c))
               ((none)
                (let [(ifaceCand (checkInterface bs text i lend lstart))]
                  (mt ifaceCand
                    ((some c) (some c))
                    ((none)
                     (let [(typeCand (checkType bs text i lend lstart))]
                       (mt typeCand
                         ((some c) (some c))
                         ((none)
                          (if (= indent 0)
                            (checkVariable bs text lstart lend)
                            (checkMethod bs text i lend lstart))))))))))))))))

fn isLineDecorator rawBs: Bytes lstart: Int64 lend: Int64 -> Bool
  (let [(idx (skipSpaces rawBs lstart lend))]
    (if (< idx lend)
      (= (bytesGet rawBs idx) 64)
      false))

fn findDecoratedStart s: src/Source rawBs: Bytes curLi: Int64 curStart: Int64 -> Int64
  (if (<= curLi 1)
    curStart
    (let [(prevLi (- curLi 1))
          (prevStart (optionOr (src/sourceLineStart s prevLi) -1))
          (prevEnd (src/sourceLineEnd s prevLi))]
      (if (= prevStart -1)
        curStart
        (if (isLineDecorator rawBs prevStart prevEnd)
          (findDecoratedStart s rawBs prevLi prevStart)
          curStart))))

fn skipLeadingSpaces rawBs: Bytes start: Int64 len: Int64 -> Int64
  (if (and (< start len) (isSpaceOrTab (bytesGet rawBs start)))
    (skipLeadingSpaces rawBs (+ start 1) len)
    start)

fn scanLinesLoop s: src/Source text: String rawBs: Bytes maskedBs: Bytes len: Int64 lineCount: Int64 curLi: Int64 acc: (List TsSymbol) -> (List TsSymbol)
  (if (> curLi lineCount)
    acc
    (let [(lstart (optionOr (src/sourceLineStart s curLi) -1))
          (lend (src/sourceLineEnd s curLi))]
      (if (= lstart -1)
        (scanLinesLoop s text rawBs maskedBs len lineCount (+ curLi 1) acc)
        (let [(cand (checkLine maskedBs text lstart lend))]
          (mt cand
            ((none)
             (scanLinesLoop s text rawBs maskedBs len lineCount (+ curLi 1) acc))
            ((some c)
             (let [(dstart c.dstart)
                   (name c.name)
                   (kind c.kind)
                   (endOff (braceBlockEnd maskedBs dstart len))
                   (decStart (findDecoratedStart s rawBs curLi dstart))
                   (finalStart (skipLeadingSpaces rawBs decStart len))
                   (stLine (optionOr (src/sourceLineAt s finalStart) curLi))
                   (lastChar (if (> endOff finalStart) (- endOff 1) finalStart))
                   (enLine (optionOr (src/sourceLineAt s lastChar) stLine))
                   (sym (TsSymbol :name name :kind kind :start finalStart :end endOff :startLine stLine :endLine enLine :depth 0 :container ""))]
               (scanLinesLoop s text rawBs maskedBs len lineCount (+ curLi 1) (cons sym acc)))))))))

fn tsSymbolSortBefore? a: TsSymbol b: TsSymbol -> Bool
  (if (< a.start b.start)
    true
    (if (> a.start b.start)
      false
      (> a.end b.end)))

fn mergeTsSymbolLists left: (List TsSymbol) right: (List TsSymbol) acc: (List TsSymbol) -> (List TsSymbol)
  (mt (listHead left)
    ((none) (listAppend (listReverse acc) right))
    ((some lhd)
     (mt (listHead right)
       ((none) (listAppend (listReverse acc) left))
       ((some rhd)
        (if (tsSymbolSortBefore? lhd rhd)
          (mergeTsSymbolLists (optionOr (listTail left) (list)) right (cons lhd acc))
          (mergeTsSymbolLists left (optionOr (listTail right) (list)) (cons rhd acc)))))))

fn sortTsSymbols syms: (List TsSymbol) -> (List TsSymbol)
  (let [(n (listLength syms))]
    (if (<= n 1)
      syms
      (let [(mid (/ n 2))
            (left (sortTsSymbols (listTake syms mid)))
            (right (sortTsSymbols (listDrop syms mid)))]
        (mergeTsSymbolLists left right (list)))))

fn extractSymbolsWithSource! text: String s: src/Source -> (List TsSymbol)
  (let [(rawBs (src/sourceBytes s))
        (len (src/sourceLength s))
        (lineCount (src/sourceLineCount s))
        (maskedBs (maskCode! text rawBs len))
        (unsorted (scanLinesLoop s text rawBs maskedBs len lineCount 1 (list)))]
    (sortTsSymbols (listReverse unsorted)))

fn extractSymbols! text: String -> (List TsSymbol)
  (extractSymbolsWithSource! text (src/sourceFromString "" text))

fn extractSymbolsFromSource! s: src/Source text: String -> (List TsSymbol)
  (extractSymbolsWithSource! text s)

fn tsSymbolsFromSource! s: src/Source text: String -> (List sym/SymbolDef)
  (map (fn [(s TsSymbol)] -> sym/SymbolDef (tsSymbolToSymbolDef s))
       (extractSymbolsWithSource! text s))

fn tsSymbols! text: String -> (List sym/SymbolDef)
  (map (fn [(s TsSymbol)] -> sym/SymbolDef (tsSymbolToSymbolDef s))
       (extractSymbols! text))

fn findFirstTsSymbol syms: (List TsSymbol) start: Int64 end: Int64 -> (Option TsSymbol)
  (mt (listHead (filter (fn [(s TsSymbol)] -> Bool
                          (and (= s.start start) (= s.end end)))
                        syms))
    ((some s) (some s))
    ((none) (none)))

fn findSymbolDotted syms: (List TsSymbol) query: String -> (Option TsSymbol)
  (let [(defs (map (fn [(s TsSymbol)] -> sym/SymbolDef (tsSymbolToSymbolDef s)) syms))
        (foundDef (sym/findSymbolDotted defs query))]
    (mt foundDef
      ((none) (none))
      ((some d)
       (findFirstTsSymbol syms (sym/symbolStart d) (sym/symbolEnd d)))))

fn findSymbol syms: (List TsSymbol) query: String -> (Option TsSymbol)
  (findSymbolDotted syms query)

fn nearestSymbols name: String syms: (List TsSymbol) k: Int64 -> (List String)
  (let [(names (map (fn [(s TsSymbol)] -> String s.name) syms))]
    (sym/nearestNames name names k))

fn tsOutlineItems s: src/Source syms: (List TsSymbol) -> (List out/OutlineItem)
  (map (fn [(sym TsSymbol)] -> out/OutlineItem
         (out/makeOutlineItem sym.name sym.kind sym.startLine sym.endLine))
       syms)

fn tsOutlineReceipt! file: String lang: String text: String -> String
  (let [(s (src/sourceFromString file text))
        (syms (extractSymbolsWithSource! text s))
        (symDefs (map (fn [(x TsSymbol)] -> sym/SymbolDef (tsSymbolToSymbolDef x)) syms))]
    (out/formatOutlineReceipt file lang symDefs s))
