(module asl-syntax/asl/symbols
  :x [AslSymbol
      makeAslSymbol
      aslSymbolName
      aslSymbolKind
      aslSymbolStart
      aslSymbolEnd
      aslSymbolStartLine
      aslSymbolEndLine
      aslSymbolDepth
      aslSymbolContainer
      aslSymbolToSymbolDef
      extractSymbols
      extractSymbolsFromSource
      aslSymbols
      aslSymbolsFromSource
      findSymbol
      findSymbolDotted
      nearestSymbols
      aslOutlineItems
      aslOutlineReceipt]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)])

(schema AslSymbol
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f startLine Int64)
  (:f endLine Int64)
  (:f depth Int64)
  (:f container String))

fn makeAslSymbol name: String kind: String start: Int64 end: Int64 startLine: Int64 endLine: Int64 depth: Int64 container: String -> AslSymbol
  (AslSymbol :name name :kind kind :start start :end end :startLine startLine :endLine endLine :depth depth :container container)

fn aslSymbolName s: AslSymbol -> String
  s.name

fn aslSymbolKind s: AslSymbol -> String
  s.kind

fn aslSymbolStart s: AslSymbol -> Int64
  s.start

fn aslSymbolEnd s: AslSymbol -> Int64
  s.end

fn aslSymbolStartLine s: AslSymbol -> Int64
  s.startLine

fn aslSymbolEndLine s: AslSymbol -> Int64
  s.endLine

fn aslSymbolDepth s: AslSymbol -> Int64
  s.depth

fn aslSymbolContainer s: AslSymbol -> String
  s.container

fn aslSymbolToSymbolDef s: AslSymbol -> sym/SymbolDef
  (sym/makeScopedSymbolDef s.name s.kind s.start s.end s.container s.depth)

(schema RawSymbol
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f depth Int64))

(schema HeadMatch
  (:f kind String)
  (:f name String))

(schema ParenFrame
  (:f charCode Int64)
  (:f startOffset Int64))

fn isWhitespaceByte b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))

fn isDelimByte b: Int64 -> Bool
  (or (isWhitespaceByte b)
  (or (= b 40) (or (= b 41)
  (or (= b 91) (or (= b 93)
  (or (= b 123) (or (= b 125)
  (or (= b 34) (or (= b 59)
      (= b 44))))))))))

fn isAlphaByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isIdentCharByte b: Int64 -> Bool
  (or (isAlphaByte b) (or (isDigitByte b) (or (= b 95) (= b 45))))

fn isKwCharByte b: Int64 -> Bool
  (or (isIdentCharByte b) (or (= b 63) (= b 33)))

fn skipWs bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (if (isWhitespaceByte (bytesGet bs pos))
      (skipWs bs len (+ pos 1))
      pos))

fn scanDelimEnd bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (if (isDelimByte (bytesGet bs pos))
      pos
      (scanDelimEnd bs len (+ pos 1))))

fn matchDefHead text: String start: Int64 end: Int64 -> (Option String)
  (let [(head (optionOr (stringSlice text start end) ""))]
    (if (or (= head "fn")
        (or (= head "defn")
        (or (= head "defun")
        (or (= head "schema")
        (or (= head "defschema")
        (or (= head "enum")
        (or (= head "defenum")
        (or (= head "macro")
        (or (= head "struct")
        (or (= head "def")
        (or (= head "df")
        (or (= head "dfs")
        (or (= head "const")
        (or (= head "type")
        (or (= head "test")
        (or (= head "deftest")
            (= head "export")))))))))))))))))
      (some head)
      (none)))

fn stripQuotes s: String -> String
  (let [(len (stringLength s))]
    (if (and (>= len 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))
      (optionOr (stringSlice s 1 (- len 1)) "")
      (if (stringStartsWith? s "\"")
        (optionOr (stringSlice s 1 len) "")
        (if (stringEndsWith? s "\"")
          (optionOr (stringSlice s 0 (- len 1)) "")
          s))))

fn scanIdentChars bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (if (isIdentCharByte (bytesGet bs pos))
      (scanIdentChars bs len (+ pos 1))
      pos))

fn scanKwChars bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (if (isKwCharByte (bytesGet bs pos))
      (scanKwChars bs len (+ pos 1))
      pos))

fn matchParenKwHead text: String bs: Bytes len: Int64 pos: Int64 -> (Option HeadMatch)
  (let [(kwStart (+ pos 1))]
    (if (or (>= kwStart len) (not (isAlphaByte (bytesGet bs kwStart))))
      (none)
      (let [(kpos (scanIdentChars bs len (+ kwStart 1)))
            (kind (optionOr (stringSlice text kwStart kpos) ""))]
        (if (or (>= kpos len) (not (isWhitespaceByte (bytesGet bs kpos))))
          (none)
          (let [(posAfterKw (skipWs bs len kpos))]
            (if (>= posAfterKw len)
              (none)
              (if (and (<= (+ posAfterKw 3) len)
                       (and (= (bytesGet bs posAfterKw) 58)
                            (and (= (bytesGet bs (+ posAfterKw 1)) 105)
                                 (and (= (bytesGet bs (+ posAfterKw 2)) 100)
                                      (or (= (+ posAfterKw 3) len)
                                          (isWhitespaceByte (bytesGet bs (+ posAfterKw 3))))))))
                (let [(posAfterId (skipWs bs len (+ posAfterKw 3)))]
                  (if (>= posAfterId len)
                    (none)
                    (if (= (bytesGet bs posAfterId) 34)
                      (let [(qstart (+ posAfterId 1))
                            (qend (scanDelimEnd bs len qstart))
                            (name (stripQuotes (optionOr (stringSlice text qstart qend) "")))]
                        (if (stringEmpty? name)
                          (none)
                          (some (HeadMatch :kind kind :name name))))
                      (let [(nstart posAfterId)
                            (nstart2 (if (and (< nstart len) (= (bytesGet bs nstart) 33)) (+ nstart 1) nstart))
                            (nend (scanDelimEnd bs len nstart2))
                            (name (stripQuotes (optionOr (stringSlice text nstart nend) "")))]
                        (if (stringEmpty? name)
                          (none)
                          (some (HeadMatch :kind kind :name name)))))))
                (if (= (bytesGet bs posAfterKw) 58)
                  (let [(kw2Start (+ posAfterKw 1))]
                    (if (or (>= kw2Start len) (not (isAlphaByte (bytesGet bs kw2Start))))
                      (none)
                      (let [(kpos2 (scanKwChars bs len (+ kw2Start 1)))
                            (name (optionOr (stringSlice text kw2Start kpos2) ""))
                            (posAfterKw2 (skipWs bs len kpos2))]
                        (if (and (< posAfterKw2 len) (or (= (bytesGet bs posAfterKw2) 58) (= (bytesGet bs posAfterKw2) 41)))
                          (some (HeadMatch :kind kind :name name))
                          (none)))))
                  (none)))))))))

fn matchParenHead text: String bs: Bytes len: Int64 start: Int64 -> (Option HeadMatch)
  (let [(pos (skipWs bs len (+ start 1)))]
    (if (>= pos len)
      (none)
      (if (= (bytesGet bs pos) 58)
        (matchParenKwHead text bs len pos)
        (let [(hend (scanDelimEnd bs len pos))]
          (mt (matchDefHead text pos hend)
            ((none) (none))
            ((some head)
             (let [(posAfterHead (skipWs bs len hend))]
               (if (or (= posAfterHead hend) (>= posAfterHead len))
                 (none)
                 (let [(nstart posAfterHead)
                       (nstart2 (if (and (< nstart len) (= (bytesGet bs nstart) 33)) (+ nstart 1) nstart))
                       (nend (scanDelimEnd bs len nstart2))
                       (name (stripQuotes (optionOr (stringSlice text nstart nend) "")))]
                   (if (stringEmpty? name)
                     (none)
                     (some (HeadMatch :kind head :name name))))))))))))

fn scanSpacesAndTabs bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(b (bytesGet bs pos))]
      (if (or (= b 32) (= b 9))
        (scanSpacesAndTabs bs len (+ pos 1))
        pos)))

fn scanIndentHeadEnd bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(b (bytesGet bs pos))]
      (if (or (isAlphaByte b) (or (isDigitByte b) (or (= b 95) (= b 45))))
        (scanIndentHeadEnd bs len (+ pos 1))
        pos)))

fn matchIndentHead text: String bs: Bytes len: Int64 lineStart: Int64 -> (Option HeadMatch)
  (let [(hend (scanIndentHeadEnd bs len lineStart))]
    (if (= hend lineStart)
      (none)
      (mt (matchDefHead text lineStart hend)
        ((none) (none))
        ((some head)
         (let [(spEnd (scanSpacesAndTabs bs len hend))]
           (if (= spEnd hend)
             (none)
             (let [(nstart spEnd)
                   (nstart2 (if (and (< nstart len) (= (bytesGet bs nstart) 33)) (+ nstart 1) nstart))
                   (nend (scanDelimEnd bs len nstart2))]
               (if (= nend nstart)
                 (none)
                 (let [(name (optionOr (stringSlice text nstart nend) ""))]
                   (some (HeadMatch :kind head :name name)))))))))))

fn scanParenLoop text: String bs: Bytes len: Int64 idx: Int64 stack: (List ParenFrame) inComment: Bool inStr: Bool esc: Bool acc: (List RawSymbol) -> (List RawSymbol)
  (if (>= idx len)
    acc
    (let [(b (bytesGet bs idx))]
      (if inComment
        (if (= b 10)
          (scanParenLoop text bs len (+ idx 1) stack false inStr esc acc)
          (scanParenLoop text bs len (+ idx 1) stack true inStr esc acc))
        (if inStr
          (if esc
            (scanParenLoop text bs len (+ idx 1) stack false true false acc)
            (if (= b 92)
              (scanParenLoop text bs len (+ idx 1) stack false true true acc)
              (if (= b 34)
                (scanParenLoop text bs len (+ idx 1) stack false false false acc)
                (scanParenLoop text bs len (+ idx 1) stack false true false acc))))
          (if (= b 34)
            (scanParenLoop text bs len (+ idx 1) stack false true false acc)
            (if (= b 59)
              (scanParenLoop text bs len (+ idx 1) stack true false false acc)
              (if (or (= b 40) (or (= b 91) (= b 123)))
                (scanParenLoop text bs len (+ idx 1) (cons (ParenFrame :charCode b :startOffset idx) stack) false false false acc)
                (if (or (= b 41) (or (= b 93) (= b 125)))
                  (if (listEmpty? stack)
                    (scanParenLoop text bs len (+ idx 1) (list) false false false acc)
                    (let [(frame (optionOr (listHead stack) (ParenFrame :charCode 0 :startOffset 0)))
                          (remStack (optionOr (listTail stack) (list)))
                          (endOff (+ idx 1))]
                      (if (= frame.charCode 40)
                        (mt (matchParenHead text bs len frame.startOffset)
                          ((none)
                           (scanParenLoop text bs len (+ idx 1) remStack false false false acc))
                          ((some m)
                           (let [(raw (RawSymbol :name m.name :kind m.kind :start frame.startOffset :end endOff :depth (listLength remStack)))]
                             (scanParenLoop text bs len (+ idx 1) remStack false false false (cons raw acc)))))
                        (scanParenLoop text bs len (+ idx 1) remStack false false false acc))))
                  (scanParenLoop text bs len (+ idx 1) stack false false false acc)))))))))

fn lineIsBlank? bs: Bytes lStart: Int64 lEnd: Int64 pos: Int64 -> Bool
  (if (>= pos lEnd)
    true
    (if (not (isWhitespaceByte (bytesGet bs pos)))
      false
      (lineIsBlank? bs lStart lEnd (+ pos 1))))

(schema IndentScanState
  (:f stackDepth Int64)
  (:f inStr Bool)
  (:f esc Bool)
  (:f curSym (Option RawSymbol))
  (:f acc (List RawSymbol)))

fn updateLineDepth bs: Bytes pos: Int64 lEnd: Int64 stackDepth: Int64 inStr: Bool esc: Bool inComment: Bool -> (Pair Int64 (Pair Bool Bool))
  (if (>= pos lEnd)
    (pair stackDepth (pair inStr esc))
    (let [(b (bytesGet bs pos))]
      (if inComment
        (pair stackDepth (pair inStr esc))
        (if inStr
          (if esc
            (updateLineDepth bs (+ pos 1) lEnd stackDepth inStr false false)
            (if (= b 92)
              (updateLineDepth bs (+ pos 1) lEnd stackDepth inStr true false)
              (if (= b 34)
                (updateLineDepth bs (+ pos 1) lEnd stackDepth false false false)
                (updateLineDepth bs (+ pos 1) lEnd stackDepth inStr false false))))
          (if (= b 34)
            (updateLineDepth bs (+ pos 1) lEnd stackDepth true false false)
            (if (= b 59)
              (pair stackDepth (pair inStr esc))
              (if (or (= b 40) (or (= b 91) (= b 123)))
                (updateLineDepth bs (+ pos 1) lEnd (+ stackDepth 1) false false false)
                (if (or (= b 41) (or (= b 93) (= b 125)))
                  (let [(newDepth (if (> stackDepth 0) (- stackDepth 1) 0))]
                    (updateLineDepth bs (+ pos 1) lEnd newDepth false false false))
                  (updateLineDepth bs (+ pos 1) lEnd stackDepth false false false)))))))))

fn scanIndentedLines text: String bs: Bytes len: Int64 s: src/Source lineCount: Int64 lineNum: Int64 st: IndentScanState -> (List RawSymbol)
  (if (> lineNum lineCount)
    (mt st.curSym
      ((some cur) (cons cur st.acc))
      ((none) st.acc))
    (let [(lStart (optionOr (src/sourceLineStart s lineNum) 0))
          (lEnd (src/sourceLineEnd s lineNum))
          (stackDepth st.stackDepth)
          (inStr st.inStr)
          (esc st.esc)
          (curSym st.curSym)
          (acc st.acc)
          (lineStartDepth (if inStr -1 stackDepth))
          (blank? (lineIsBlank? bs lStart lEnd lStart))]
      (if blank?
        (let [(depthRes (updateLineDepth bs lStart lEnd stackDepth inStr esc false))
              (nextDepth (pairFirst depthRes))
              (nextStr (pairFirst (pairSecond depthRes)))
              (nextEsc (pairSecond (pairSecond depthRes)))]
          (scanIndentedLines text bs len s lineCount (+ lineNum 1)
                             (IndentScanState :stackDepth nextDepth :inStr nextStr :esc nextEsc :curSym curSym :acc acc)))
        (let [(b0 (bytesGet bs lStart))
              (isCol0 (not (or (= b0 32) (= b0 9))))]
          (if (and isCol0 (= lineStartDepth 0))
            (let [(newAcc (mt curSym ((some cur) (cons cur acc)) ((none) acc)))
                  (newCur (if (or (= b0 40) (= b0 59))
                            (none)
                            (mt (matchIndentHead text bs len lStart)
                              ((some m) (some (RawSymbol :name m.name :kind m.kind :start lStart :end lEnd :depth 0)))
                              ((none) (none)))))
                  (depthRes (updateLineDepth bs lStart lEnd stackDepth inStr esc false))
                  (nextDepth (pairFirst depthRes))
                  (nextStr (pairFirst (pairSecond depthRes)))
                  (nextEsc (pairSecond (pairSecond depthRes)))]
              (scanIndentedLines text bs len s lineCount (+ lineNum 1)
                                 (IndentScanState :stackDepth nextDepth :inStr nextStr :esc nextEsc :curSym newCur :acc newAcc)))
            (let [(updatedCur (mt curSym
                                ((some cur) (some (RawSymbol :name cur.name :kind cur.kind :start cur.start :end lEnd :depth 0)))
                                ((none) (none))))
                  (depthRes (updateLineDepth bs lStart lEnd stackDepth inStr esc false))
                  (nextDepth (pairFirst depthRes))
                  (nextStr (pairFirst (pairSecond depthRes)))
                  (nextEsc (pairSecond (pairSecond depthRes)))]
              (scanIndentedLines text bs len s lineCount (+ lineNum 1)
                                 (IndentScanState :stackDepth nextDepth :inStr nextStr :esc nextEsc :curSym updatedCur :acc acc))))))))

fn rawSymSortBefore? a: RawSymbol b: RawSymbol -> Bool
  (if (< a.start b.start)
    true
    (if (> a.start b.start)
      false
      (> a.end b.end)))

fn mergeRawLists left: (List RawSymbol) right: (List RawSymbol) acc: (List RawSymbol) -> (List RawSymbol)
  (mt (listHead left)
    ((none) (listAppend (listReverse acc) right))
    ((some lhd)
     (mt (listHead right)
       ((none) (listAppend (listReverse acc) left))
       ((some rhd)
        (if (rawSymSortBefore? lhd rhd)
          (mergeRawLists (optionOr (listTail left) (list)) right (cons lhd acc))
          (mergeRawLists left (optionOr (listTail right) (list)) (cons rhd acc)))))))

fn sortRawSymbols syms: (List RawSymbol) -> (List RawSymbol)
  (let [(n (listLength syms))]
    (if (<= n 1)
      syms
      (let [(mid (/ n 2))
            (left (sortRawSymbols (listTake syms mid)))
            (right (sortRawSymbols (listDrop syms mid)))]
        (mergeRawLists left right (list)))))

fn pruneStack stack: (List AslSymbol) endOff: Int64 -> (List AslSymbol)
  (mt (listHead stack)
    ((none) (list))
    ((some top)
     (if (< top.end endOff)
       (pruneStack (optionOr (listTail stack) (list)) endOff)
       stack)))

fn buildAslSymbolsLoop s: src/Source raws: (List RawSymbol) stack: (List AslSymbol) acc: (List AslSymbol) -> (List AslSymbol)
  (mt (listHead raws)
    ((none) (listReverse acc))
    ((some raw)
     (let [(st raw.start)
           (en raw.end)
           (pruned (pruneStack stack en))
           (container (mt (listHead pruned)
                        ((some parent) parent.name)
                        ((none) "")))
           (stLine (optionOr (src/sourceLineAt s st) 1))
           (lastChar (if (> en st) (- en 1) st))
           (enLine (optionOr (src/sourceLineAt s lastChar) stLine))
           (aslSym (AslSymbol :name raw.name
                              :kind raw.kind
                              :start st
                              :end en
                              :startLine stLine
                              :endLine enLine
                              :depth raw.depth
                              :container container))]
       (buildAslSymbolsLoop s (optionOr (listTail raws) (list)) (cons aslSym pruned) (cons aslSym acc)))))

fn extractSymbolsWithSource text: String s: src/Source -> (List AslSymbol)
  (let [(bs (src/sourceBytes s))
        (len (src/sourceLength s))
        (lineCount (src/sourceLineCount s))
        (parenRaws (scanParenLoop text bs len 0 (list) false false false (list)))
        (initSt (IndentScanState :stackDepth 0 :inStr false :esc false :curSym (none) :acc (list)))
        (allRaws (scanIndentedLines text bs len s lineCount 1 initSt))
        (combined (listAppend parenRaws allRaws))
        (sorted (sortRawSymbols combined))]
    (buildAslSymbolsLoop s sorted (list) (list)))

fn extractSymbols text: String -> (List AslSymbol)
  (extractSymbolsWithSource text (src/sourceFromString "" text))

fn extractSymbolsFromSource s: src/Source text: String -> (List AslSymbol)
  (extractSymbolsWithSource text s)

fn aslSymbolsFromSource s: src/Source text: String -> (List sym/SymbolDef)
  (map (fn [(s AslSymbol)] -> sym/SymbolDef (aslSymbolToSymbolDef s))
       (extractSymbolsWithSource text s))

fn aslSymbols text: String -> (List sym/SymbolDef)
  (map (fn [(s AslSymbol)] -> sym/SymbolDef (aslSymbolToSymbolDef s))
       (extractSymbols text))

fn findFirstAslSymbol syms: (List AslSymbol) start: Int64 end: Int64 -> (Option AslSymbol)
  (mt (listHead (filter (fn [(s AslSymbol)] -> Bool
                          (and (= s.start start) (= s.end end)))
                        syms))
    ((some s) (some s))
    ((none) (none)))

fn findSymbolDotted syms: (List AslSymbol) query: String -> (Option AslSymbol)
  (let [(defs (map (fn [(s AslSymbol)] -> sym/SymbolDef (aslSymbolToSymbolDef s)) syms))
        (foundDef (sym/findSymbolDotted defs query))]
    (mt foundDef
      ((none) (none))
      ((some d)
       (findFirstAslSymbol syms (sym/symbolStart d) (sym/symbolEnd d)))))

fn findSymbol syms: (List AslSymbol) query: String -> (Option AslSymbol)
  (findSymbolDotted syms query)

fn nearestSymbols name: String syms: (List AslSymbol) k: Int64 -> (List String)
  (let [(names (map (fn [(s AslSymbol)] -> String s.name) syms))]
    (sym/nearestNames name names k))

fn aslOutlineItems s: src/Source syms: (List AslSymbol) -> (List out/OutlineItem)
  (map (fn [(sym AslSymbol)] -> out/OutlineItem
         (out/makeOutlineItem sym.name sym.kind sym.startLine sym.endLine))
       syms)

fn aslOutlineReceipt file: String lang: String text: String -> String
  (let [(s (src/sourceFromString file text))
        (syms (extractSymbolsWithSource text s))
        (symDefs (map (fn [(x AslSymbol)] -> sym/SymbolDef (aslSymbolToSymbolDef x)) syms))]
    (out/formatOutlineReceipt file lang symDefs s))

