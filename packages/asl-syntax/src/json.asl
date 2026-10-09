(module asl-syntax/json
  :x [parse
      parseBytes
      parseJson
      parseJsonBytes
      parseJsonc
      parseJsoncBytes
      tokenize
      tokenizeBytes
      isValid
      isWellFormed
      lower
      lowerBytes
      lowerJson
      extractSymbols
      extractSymbolsFromText
      findSymbolByPath
      jsonOutlineItems
      jsonOutlineReceipt
      jsonOutlineReceiptFromSource]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a otl)
      (asl-syntax/core/print :a pr)
      (asl-json/json :a j)
      (asl-syntax/core/bytesText :a btxt)])

fn encodeCp cp: Int64 -> String
  (cond
    ((< cp 128) (btxt/byteStr cp))
    ((< cp 2048)
     (stringConcat (btxt/byteStr (| 192 (/ cp 64)))
                    (btxt/byteStr (| 128 (mod cp 64)))))
    ((< cp 65536)
     (stringConcat (stringConcat (btxt/byteStr (| 224 (/ cp 4096)))
                                  (btxt/byteStr (| 128 (mod (/ cp 64) 64))))
                    (btxt/byteStr (| 128 (mod cp 64)))))
    (else
     (stringConcat (stringConcat (btxt/byteStr (| 240 (/ cp 262144)))
                                  (btxt/byteStr (| 128 (mod (/ cp 4096) 64))))
                    (stringConcat (btxt/byteStr (| 128 (mod (/ cp 64) 64)))
                                  (btxt/byteStr (| 128 (mod cp 64)))))))

fn hexVal b: Int64 -> Int64
  (cond
    ((and (>= b 48) (<= b 57)) (- b 48))
    ((and (>= b 65) (<= b 70)) (+ (- b 65) 10))
    ((and (>= b 97) (<= b 102)) (+ (- b 97) 10))
    (else -1))

fn parseHex4 bs: Bytes offset: Int64 len: Int64 -> Int64
  (if (> (+ offset 4) len) -1
    (let [(h0 (hexVal (bytesGet bs offset)))
          (h1 (hexVal (bytesGet bs (+ offset 1))))
          (h2 (hexVal (bytesGet bs (+ offset 2))))
          (h3 (hexVal (bytesGet bs (+ offset 3))))]
      (if (or (< h0 0) (or (< h1 0) (or (< h2 0) (< h3 0))))
        -1
        (+ (* h0 4096) (+ (* h1 256) (+ (* h2 16) h3))))))

fn isWsByte b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn isNlByte b: Int64 -> Bool
  (or (= b 10) (= b 13))

fn scanWhitespace bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (if (isWsByte (bytesGet bs pos))
      (scanWhitespace bs len (+ pos 1))
      pos))

fn scanNewline bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(b (bytesGet bs pos))]
      (cond
        ((= b 10) (+ pos 1))
        ((= b 13)
         (if (and (< (+ pos 1) len) (= (bytesGet bs (+ pos 1)) 10))
           (+ pos 2)
           (+ pos 1)))
        (else pos))))

fn scanLineComment bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(b (bytesGet bs pos))]
      (if (isNlByte b)
        pos
        (scanLineComment bs len (+ pos 1)))))

fn scanBlockComment bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= (+ pos 1) len)
    len
    (if (and (= (bytesGet bs pos) 42) (= (bytesGet bs (+ pos 1)) 47))
      (+ pos 2)
      (scanBlockComment bs len (+ pos 1))))

(schema TriviaScan
  (:f elems (List tr/TreeElement))
  (:f pos Int64))

fn scanTriviaLoop bs: Bytes len: Int64 pos: Int64 jsonc: Bool acc: (List tr/TreeElement) -> TriviaScan
  (if (>= pos len)
    (TriviaScan :elems (listReverse acc) :pos pos)
    (let [(b (bytesGet bs pos))]
      (cond
        ((isWsByte b)
         (let [(endPos (scanWhitespace bs len (+ pos 1)))
               (tok (tr/makeToken "whitespace" pos endPos))]
           (scanTriviaLoop bs len endPos jsonc (cons (tr/elemToken tok) acc))))
        ((isNlByte b)
         (let [(endPos (scanNewline bs len pos))
               (tok (tr/makeToken "newline" pos endPos))]
           (scanTriviaLoop bs len endPos jsonc (cons (tr/elemToken tok) acc))))
        ((and (= b 47) (< (+ pos 1) len) (= (bytesGet bs (+ pos 1)) 47))
         (let [(endPos (scanLineComment bs len (+ pos 2)))
               (kind (if jsonc "lineComment" "error"))
               (tok (tr/makeToken kind pos endPos))]
           (scanTriviaLoop bs len endPos jsonc (cons (tr/elemToken tok) acc))))
        ((and (= b 47) (< (+ pos 1) len) (= (bytesGet bs (+ pos 1)) 42))
         (let [(endPos (scanBlockComment bs len (+ pos 2)))
               (kind (if jsonc "blockComment" "error"))
               (tok (tr/makeToken kind pos endPos))]
           (scanTriviaLoop bs len endPos jsonc (cons (tr/elemToken tok) acc))))
        (else
         (TriviaScan :elems (listReverse acc) :pos pos)))))

fn scanDigits bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(b (bytesGet bs pos))]
      (if (and (>= b 48) (<= b 57))
        (scanDigits bs len (+ pos 1))
        pos)))

fn scanStringContent bs: Bytes len: Int64 pos: Int64 hasError: Bool -> (Pair Int64 Bool)
  (if (>= pos len)
    (pair len true)
    (let [(b (bytesGet bs pos))]
      (cond
        ((< b 32)
         (scanStringContent bs len (+ pos 1) true))
        ((= b 34)
         (pair (+ pos 1) hasError))
        ((= b 92)
         (let [(escPos (+ pos 1))]
           (if (>= escPos len)
             (pair len true)
             (let [(esc (bytesGet bs escPos))]
               (cond
                 ((or (= esc 34) (or (= esc 92) (or (= esc 47)
                  (or (= esc 98) (or (= esc 102) (or (= esc 110)
                  (or (= esc 114) (= esc 116))))))))
                  (scanStringContent bs len (+ escPos 1) hasError))
                 ((= esc 117)
                  (let [(cp1 (parseHex4 bs (+ escPos 1) len))]
                    (if (< cp1 0)
                      (scanStringContent bs len (+ escPos 1) true)
                      (cond
                        ((and (>= cp1 55296) (<= cp1 56319))
                         (if (or (> (+ escPos 10) len)
                                 (or (!= (bytesGet bs (+ escPos 5)) 92)
                                     (!= (bytesGet bs (+ escPos 6)) 117)))
                           (scanStringContent bs len (+ escPos 5) true)
                           (let [(cp2 (parseHex4 bs (+ escPos 7) len))]
                             (if (or (< cp2 56320) (> cp2 57343))
                               (scanStringContent bs len (+ escPos 5) true)
                               (scanStringContent bs len (+ escPos 11) hasError)))))
                        ((and (>= cp1 56320) (<= cp1 57343))
                         (scanStringContent bs len (+ escPos 5) true))
                        (else
                         (scanStringContent bs len (+ escPos 5) hasError))))))
                 (else
                  (scanStringContent bs len (+ escPos 1) true)))))))
        (else
         (scanStringContent bs len (+ pos 1) hasError)))))

fn scanStringTok bs: Bytes len: Int64 start: Int64 -> tr/Token
  (let [(res (scanStringContent bs len (+ start 1) false))
        (endPos (pairFirst res))
        (err? (pairSecond res))
        (kind (if err? "error" "string"))]
    (tr/makeToken kind start endPos))

fn scanNumberTok bs: Bytes len: Int64 start: Int64 -> tr/Token
  (let [(p0 (if (and (< start len) (= (bytesGet bs start) 45)) (+ start 1) start))]
    (if (>= p0 len)
      (tr/makeToken "error" start len)
      (let [(b0 (bytesGet bs p0))]
        (if (or (< b0 48) (> b0 57))
          (tr/makeToken "error" start (+ p0 1))
          (let [(leadingZero? (and (= b0 48) (< (+ p0 1) len) (>= (bytesGet bs (+ p0 1)) 48) (<= (bytesGet bs (+ p0 1)) 57)))
                (pInt (if (= b0 48) (+ p0 1) (scanDigits bs len (+ p0 1))))]
            (if leadingZero?
              (let [(pEnd (scanDigits bs len pInt))]
                (tr/makeToken "error" start pEnd))
              (let [(pFrac (if (and (< pInt len) (= (bytesGet bs pInt) 46))
                             (if (or (>= (+ pInt 1) len) (< (bytesGet bs (+ pInt 1)) 48) (> (bytesGet bs (+ pInt 1)) 57))
                               -1
                               (scanDigits bs len (+ pInt 2)))
                             pInt))]
                (if (< pFrac 0)
                  (tr/makeToken "error" start (+ pInt 1))
                  (let [(pExp (if (and (< pFrac len) (or (= (bytesGet bs pFrac) 101) (= (bytesGet bs pFrac) 69)))
                                (let [(pSign (if (and (< (+ pFrac 1) len) (or (= (bytesGet bs (+ pFrac 1)) 43) (= (bytesGet bs (+ pFrac 1)) 45)))
                                               (+ pFrac 2)
                                               (+ pFrac 1)))]
                                  (if (or (>= pSign len) (< (bytesGet bs pSign) 48) (> (bytesGet bs pSign) 57))
                                    -1
                                    (scanDigits bs len pSign)))
                                pFrac))]
                    (if (< pExp 0)
                      (tr/makeToken "error" start (+ pFrac 1))
                      (tr/makeToken "number" start pExp)))))))))))

(schema ParseValResult
  (:f elem (Option tr/TreeElement))
  (:f pos Int64))

fn parseVal bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 -> ParseValResult
  (if (> depth 512)
    (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode pos len (list)))) :pos len)
    (if (>= pos len)
      (ParseValResult :elem (none) :pos pos)
      (let [(b (bytesGet bs pos))]
        (cond
          ((= b 123) (parseObj bs len pos jsonc depth))
          ((= b 91) (parseArr bs len pos jsonc depth))
          ((= b 34)
           (let [(tok (scanStringTok bs len pos))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos tok.end)))
          ((or (= b 45) (and (>= b 48) (<= b 57)))
           (let [(tok (scanNumberTok bs len pos))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos tok.end)))
          ((and (= b 116) (<= (+ pos 4) len)
                (= (bytesGet bs (+ pos 1)) 114)
                (= (bytesGet bs (+ pos 2)) 117)
                (= (bytesGet bs (+ pos 3)) 101))
           (let [(tok (tr/makeToken "true" pos (+ pos 4)))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos (+ pos 4))))
          ((and (= b 102) (<= (+ pos 5) len)
                (= (bytesGet bs (+ pos 1)) 97)
                (= (bytesGet bs (+ pos 2)) 108)
                (= (bytesGet bs (+ pos 3)) 115)
                (= (bytesGet bs (+ pos 4)) 101))
           (let [(tok (tr/makeToken "false" pos (+ pos 5)))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos (+ pos 5))))
          ((and (= b 110) (<= (+ pos 4) len)
                (= (bytesGet bs (+ pos 1)) 117)
                (= (bytesGet bs (+ pos 2)) 108)
                (= (bytesGet bs (+ pos 3)) 108))
           (let [(tok (tr/makeToken "null" pos (+ pos 4)))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos (+ pos 4))))
          (else
           (let [(tok (tr/makeToken "error" pos (+ pos 1)))]
             (ParseValResult :elem (some (tr/elemToken tok)) :pos (+ pos 1))))))))

fn parseArrLoop bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 arrStart: Int64 acc: (List tr/TreeElement) -> ParseValResult
  (let [(ts1 (scanTriviaLoop bs len pos jsonc (list)))
        (acc1 (listAppend acc ts1.elems))
        (p1 ts1.pos)]
    (if (>= p1 len)
      (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode arrStart len acc1))) :pos len)
      (if (= (bytesGet bs p1) 93)
        (let [(rTok (tr/makeToken "rbracket" p1 (+ p1 1)))
              (finalAcc (listAppend acc1 (list (tr/elemToken rTok))))]
          (ParseValResult :elem (some (tr/elemNode (tr/makeNode "array" arrStart (+ p1 1) finalAcc))) :pos (+ p1 1)))
        (let [(valRes (parseVal bs len p1 jsonc (+ depth 1)))]
          (mt valRes.elem
            ((none)
             (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode arrStart len acc1))) :pos len))
            ((some vElem)
             (let [(pValEnd valRes.pos)
                   (acc2 (listAppend acc1 (list vElem)))
                   (ts2 (scanTriviaLoop bs len pValEnd jsonc (list)))
                   (acc3 (listAppend acc2 (listDirect ts2.elems)))
                   (p2 ts2.pos)]
               (if (>= p2 len)
                 (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode arrStart len acc3))) :pos len)
                 (let [(b2 (bytesGet bs p2))]
                   (cond
                     ((= b2 93)
                      (let [(rTok (tr/makeToken "rbracket" p2 (+ p2 1)))
                            (finalAcc (listAppend acc3 (list (tr/elemToken rTok))))]
                        (ParseValResult :elem (some (tr/elemNode (tr/makeNode "array" arrStart (+ p2 1) finalAcc))) :pos (+ p2 1))))
                     ((= b2 44)
                      (let [(cTok (tr/makeToken "comma" p2 (+ p2 1)))
                            (acc4 (listAppend acc3 (list (tr/elemToken cTok))))
                            (ts3 (scanTriviaLoop bs len (+ p2 1) jsonc (list)))
                            (acc5 (listAppend acc4 ts3.elems))
                            (p3 ts3.pos)]
                        (if (and (< p3 len) (= (bytesGet bs p3) 93))
                          (if jsonc
                            (let [(rTok (tr/makeToken "rbracket" p3 (+ p3 1)))
                                  (finalAcc (listAppend acc5 (list (tr/elemToken rTok))))]
                              (ParseValResult :elem (some (tr/elemNode (tr/makeNode "array" arrStart (+ p3 1) finalAcc))) :pos (+ p3 1)))
                            (let [(errTok (tr/makeToken "error" p2 (+ p2 1)))
                                  (rTok (tr/makeToken "rbracket" p3 (+ p3 1)))
                                  (finalAcc (listAppend acc3 (list (tr/elemToken errTok) (tr/elemToken rTok))))]
                              (ParseValResult :elem (some (tr/elemNode (tr/makeNode "array" arrStart (+ p3 1) finalAcc))) :pos (+ p3 1))))
                          (parseArrLoop bs len p3 jsonc depth arrStart acc5))))
                     (else
                      (let [(errTok (tr/makeToken "error" p2 (+ p2 1)))
                            (acc4 (listAppend acc3 (list (tr/elemToken errTok))))]
                        (ParseValResult :elem (some (tr/elemNode (tr/makeNode "array" arrStart (+ p2 1) acc4))) :pos (+ p2 1))))))))))))))

fn listDirect xs: (List tr/TreeElement) -> (List tr/TreeElement)
  xs

fn parseArr bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 -> ParseValResult
  (let [(lTok (tr/makeToken "lbracket" pos (+ pos 1)))]
    (parseArrLoop bs len (+ pos 1) jsonc depth pos (list (tr/elemToken lTok))))

fn parseProp bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 -> ParseValResult
  (let [(keyTok (if (and (< pos len) (= (bytesGet bs pos) 34))
                  (scanStringTok bs len pos)
                  (tr/makeToken "error" pos (if (< pos len) (+ pos 1) len))))
        (pKeyEnd keyTok.end)
        (propStart pos)
        (acc1 (list (tr/elemToken keyTok)))
        (ts1 (scanTriviaLoop bs len pKeyEnd jsonc (list)))
        (acc2 (listAppend acc1 ts1.elems))
        (pColon ts1.pos)]
    (if (or (>= pColon len) (!= (bytesGet bs pColon) 58))
      (let [(errTok (tr/makeToken "error" pColon (if (< pColon len) (+ pColon 1) len)))
            (acc3 (listAppend acc2 (list (tr/elemToken errTok))))]
        (ParseValResult :elem (some (tr/elemNode (tr/makeNode "property" propStart errTok.end acc3))) :pos errTok.end))
      (let [(cTok (tr/makeToken "colon" pColon (+ pColon 1)))
            (acc3 (listAppend acc2 (list (tr/elemToken cTok))))
            (ts2 (scanTriviaLoop bs len (+ pColon 1) jsonc (list)))
            (acc4 (listAppend acc3 ts2.elems))
            (pVal ts2.pos)
            (valRes (parseVal bs len pVal jsonc (+ depth 1)))]
        (mt valRes.elem
          ((none)
           (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode propStart len acc4))) :pos len))
          ((some vElem)
           (let [(acc5 (listAppend acc4 (list vElem)))
                 (propEnd valRes.pos)]
             (ParseValResult :elem (some (tr/elemNode (tr/makeNode "property" propStart propEnd acc5))) :pos propEnd)))))))

fn parseObjLoop bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 objStart: Int64 acc: (List tr/TreeElement) -> ParseValResult
  (let [(ts1 (scanTriviaLoop bs len pos jsonc (list)))
        (acc1 (listAppend acc ts1.elems))
        (p1 ts1.pos)]
    (if (>= p1 len)
      (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode objStart len acc1))) :pos len)
      (if (= (bytesGet bs p1) 125)
        (let [(rTok (tr/makeToken "rbrace" p1 (+ p1 1)))
              (finalAcc (listAppend acc1 (list (tr/elemToken rTok))))]
          (ParseValResult :elem (some (tr/elemNode (tr/makeNode "object" objStart (+ p1 1) finalAcc))) :pos (+ p1 1)))
        (let [(propRes (parseProp bs len p1 jsonc depth))]
          (mt propRes.elem
            ((none)
             (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode objStart len acc1))) :pos len))
            ((some pElem)
             (let [(pPropEnd propRes.pos)
                   (acc2 (listAppend acc1 (list pElem)))
                   (ts2 (scanTriviaLoop bs len pPropEnd jsonc (list)))
                   (acc3 (listAppend acc2 ts2.elems))
                   (p2 ts2.pos)]
               (if (>= p2 len)
                 (ParseValResult :elem (some (tr/elemNode (tr/makeErrorNode objStart len acc3))) :pos len)
                 (let [(b2 (bytesGet bs p2))]
                   (cond
                     ((= b2 125)
                      (let [(rTok (tr/makeToken "rbrace" p2 (+ p2 1)))
                            (finalAcc (listAppend acc3 (list (tr/elemToken rTok))))]
                        (ParseValResult :elem (some (tr/elemNode (tr/makeNode "object" objStart (+ p2 1) finalAcc))) :pos (+ p2 1))))
                     ((= b2 44)
                      (let [(cTok (tr/makeToken "comma" p2 (+ p2 1)))
                            (acc4 (listAppend acc3 (list (tr/elemToken cTok))))
                            (ts3 (scanTriviaLoop bs len (+ p2 1) jsonc (list)))
                            (acc5 (listAppend acc4 ts3.elems))
                            (p3 ts3.pos)]
                        (if (and (< p3 len) (= (bytesGet bs p3) 125))
                          (if jsonc
                            (let [(rTok (tr/makeToken "rbrace" p3 (+ p3 1)))
                                  (finalAcc (listAppend acc5 (list (tr/elemToken rTok))))]
                              (ParseValResult :elem (some (tr/elemNode (tr/makeNode "object" objStart (+ p3 1) finalAcc))) :pos (+ p3 1)))
                            (let [(errTok (tr/makeToken "error" p2 (+ p2 1)))
                                  (rTok (tr/makeToken "rbracket" p3 (+ p3 1)))
                                  (finalAcc (listAppend acc3 (list (tr/elemToken errTok) (tr/elemToken rTok))))]
                              (ParseValResult :elem (some (tr/elemNode (tr/makeNode "object" objStart (+ p3 1) finalAcc))) :pos (+ p3 1))))
                          (parseObjLoop bs len p3 jsonc depth objStart acc5))))
                     (else
                      (let [(errTok (tr/makeToken "error" p2 (+ p2 1)))
                            (acc4 (listAppend acc3 (list (tr/elemToken errTok))))]
                        (ParseValResult :elem (some (tr/elemNode (tr/makeNode "object" objStart (+ p2 1) acc4))) :pos (+ p2 1))))))))))))))

fn parseObj bs: Bytes len: Int64 pos: Int64 jsonc: Bool depth: Int64 -> ParseValResult
  (let [(lTok (tr/makeToken "lbrace" pos (+ pos 1)))]
    (parseObjLoop bs len (+ pos 1) jsonc depth pos (list (tr/elemToken lTok))))

fn scanTrailingGarbage bs: Bytes len: Int64 pos: Int64 acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (>= pos len)
    (listReverse acc)
    (let [(tok (tr/makeToken "error" pos (+ pos 1)))]
      (scanTrailingGarbage bs len (+ pos 1) (cons (tr/elemToken tok) acc))))

fn parseDocBytes bs: Bytes jsonc: Bool -> tr/Node
  (let [(len (bytesLength bs))
        (ts1 (scanTriviaLoop bs len 0 jsonc (list)))
        (p1 ts1.pos)
        (acc1 ts1.elems)]
    (if (>= p1 len)
      (tr/makeNode "document" 0 len (list (tr/elemNode (tr/makeErrorNode 0 len acc1))))
      (let [(valRes (parseVal bs len p1 jsonc 0))]
        (mt valRes.elem
          ((none)
           (let [(errTok (tr/makeToken "error" p1 len))]
             (tr/makeNode "document" 0 len (listAppend acc1 (list (tr/elemToken errTok))))))
          ((some valElem)
           (let [(p2 valRes.pos)
                 (acc2 (listAppend acc1 (list valElem)))
                 (ts2 (scanTriviaLoop bs len p2 jsonc (list)))
                 (p3 ts2.pos)
                 (acc3 (listAppend acc2 ts2.elems))]
             (if (>= p3 len)
               (tr/makeNode "document" 0 len acc3)
               (let [(garbage (scanTrailingGarbage bs len p3 (list)))
                     (acc4 (listAppend acc3 garbage))]
                 (tr/makeNode "document" 0 len acc4)))))))))

fn parseJsonBytes bs: Bytes -> tr/Node
  (parseDocBytes bs false)

fn parseJson text: String -> tr/Node
  (parseJsonBytes (stringToBytes text))

fn parseJsoncBytes bs: Bytes -> tr/Node
  (parseDocBytes bs true)

fn parseJsonc text: String -> tr/Node
  (parseJsoncBytes (stringToBytes text))

fn isWellFormed root: tr/Node -> Bool
  (not (sym/hasErrorNode root))

fn isValid root: tr/Node -> Bool
  (isWellFormed root)

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tr/nodeLeaves (parseJsonBytes bs))

fn tokenize text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))

fn firstErrorOffsetNode node: tr/Node -> (Option Int64)
  (if (tr/isErrorNode node)
    (some (tr/nodeStart node))
    (firstErrorOffsetList node.children))

fn firstErrorOffsetList elems: (List tr/TreeElement) -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (if (tr/isErrorToken tok)
           (some (tr/tokenStart tok))
           (firstErrorOffsetList tail)))
        ((elemNode n)
         (mt (firstErrorOffsetNode n)
           ((some off) (some off))
           ((none) (firstErrorOffsetList tail)))))))

fn parseBytes bs: Bytes -> (Result tr/Node String)
  (let [(root (parseJsonBytes bs))]
    (if (isValid root)
      (ok root)
      (let [(off (optionOr (firstErrorOffsetNode root) 0))]
        (err (str "JSON syntax error at byte " (stringFromInt64 off))))))

fn parse text: String -> (Result tr/Node String)
  (parseBytes (stringToBytes text))

fn unescapeString src: String bs: Bytes len: Int64 scanPos: Int64 pieceStart: Int64 pieces: (List String) hasEsc: Bool -> String
  (if (>= scanPos len)
    (if (not hasEsc)
      (optionOr (stringSlice src pieceStart len) "")
      (let [(lastPiece (optionOr (stringSlice src pieceStart len) ""))
            (allPieces (cons lastPiece pieces))]
        (stringJoin (listReverse allPieces) "")))
    (let [(b (bytesGet bs scanPos))]
      (if (!= b 92)
        (unescapeString src bs len (+ scanPos 1) pieceStart pieces hasEsc)
        (let [(escPos (+ scanPos 1))]
          (if (>= escPos len)
            (unescapeString src bs len (+ scanPos 1) pieceStart pieces hasEsc)
            (let [(escChar (bytesGet bs escPos))
                  (litPiece (optionOr (stringSlice src pieceStart scanPos) ""))]
              (cond
                ((= escChar 34) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\"" (cons litPiece pieces)) true))
                ((= escChar 92) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\\" (cons litPiece pieces)) true))
                ((= escChar 47) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "/" (cons litPiece pieces)) true))
                ((= escChar 98) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\x08" (cons litPiece pieces)) true))
                ((= escChar 102) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\x0c" (cons litPiece pieces)) true))
                ((= escChar 110) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\n" (cons litPiece pieces)) true))
                ((= escChar 114) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\r" (cons litPiece pieces)) true))
                ((= escChar 116) (unescapeString src bs len (+ escPos 1) (+ escPos 1) (cons "\t" (cons litPiece pieces)) true))
                ((= escChar 117)
                 (let [(cp1 (parseHex4 bs (+ escPos 1) len))]
                   (if (< cp1 0)
                     (unescapeString src bs len (+ escPos 5) (+ escPos 5) (cons litPiece pieces) true)
                     (cond
                       ((and (>= cp1 55296) (<= cp1 56319))
                        (if (or (> (+ escPos 10) len)
                                (or (!= (bytesGet bs (+ escPos 5)) 92)
                                    (!= (bytesGet bs (+ escPos 6)) 117)))
                          (unescapeString src bs len (+ escPos 5) (+ escPos 5) (cons litPiece pieces) true)
                          (let [(cp2 (parseHex4 bs (+ escPos 7) len))]
                            (if (or (< cp2 56320) (> cp2 57343))
                              (unescapeString src bs len (+ escPos 5) (+ escPos 5) (cons litPiece pieces) true)
                              (let [(fullCp (+ 65536 (+ (* (- cp1 55296) 1024) (- cp2 56320))))
                                    (encoded (encodeCp fullCp))]
                                (unescapeString src bs len (+ escPos 11) (+ escPos 11) (cons encoded (cons litPiece pieces)) true))))))
                       (else
                        (let [(encoded (encodeCp cp1))]
                          (unescapeString src bs len (+ escPos 5) (+ escPos 5) (cons encoded (cons litPiece pieces)) true)))))))
                (else
                 (unescapeString src bs len (+ escPos 1) pieceStart pieces hasEsc)))))))))

fn decodeJsonString raw: String -> String
  (let [(bs (stringToBytes raw))
        (len (bytesLength bs))]
    (if (and (>= len 2) (= (bytesGet bs 0) 34) (= (bytesGet bs (- len 1)) 34))
      (let [(inner (optionOr (stringSlice raw 1 (- len 1)) ""))
            (innerBs (stringToBytes inner))
            (innerLen (bytesLength innerBs))]
        (unescapeString inner innerBs innerLen 0 0 (list) false))
      raw))

fn findPropValue elems: (List tr/TreeElement) colonSeen: Bool -> (Option tr/TreeElement)
  (if (listEmpty? elems)
    (none)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (if (tr/isTrivia tok)
           (findPropValue tail colonSeen)
           (if (= tok.kind "colon")
             (findPropValue tail true)
             (if colonSeen
               (some head)
               (findPropValue tail colonSeen)))))
        ((elemNode n)
         (if colonSeen
           (some head)
           (findPropValue tail colonSeen))))))

fn findPropKey elems: (List tr/TreeElement) -> (Option tr/Token)
  (if (listEmpty? elems)
    (none)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (if (tr/isTrivia tok)
           (findPropKey tail)
           (if (= tok.kind "string")
             (some tok)
             (none))))
        ((elemNode _)
         (findPropKey tail)))))

fn lowerElem elem: tr/TreeElement text: String -> (Result j/Json String)
  (mt elem
    ((tr/elemToken tok)
     (let [(k tok.kind)]
       (cond
         ((= k "string")
          (let [(raw (optionOr (stringSlice text tok.start tok.end) ""))
                (decoded (decodeJsonString raw))]
            (ok (j/jstr decoded))))
         ((= k "number")
          (let [(numStr (optionOr (stringSlice text tok.start tok.end) ""))
                (hasFrac (stringContains? numStr "."))
                (hasExp (or (stringContains? numStr "e") (stringContains? numStr "E")))]
            (if (or hasFrac hasExp)
              (mt (stringToFloat64 numStr)
                ((some f) (ok (j/jfloat f)))
                ((none) (err (str "malformed number " numStr))))
              (mt (stringToInt64 numStr)
                ((some i) (ok (j/jint i)))
                ((none) (mt (stringToFloat64 numStr)
                          ((some f) (ok (j/jfloat f)))
                          ((none) (err (str "malformed number " numStr)))))))))
         ((= k "true") (ok (j/jbool true)))
         ((= k "false") (ok (j/jbool false)))
         ((= k "null") (ok (j/jnull)))
         (else (err (str "unexpected leaf token in lowering: " k))))))
    ((elemNode n)
     (let [(k n.kind)]
       (cond
         ((= k "object")
          (lowerObj n.children text (list)))
         ((= k "array")
          (lowerArr n.children text (list)))
         ((= k "document")
          (mt (findDocValue n.children)
            ((none) (err "empty JSON document"))
            ((some v) (lowerElem v text))))
         (else
          (err (str "unexpected node kind in lowering: " k)))))))

fn lowerObj elems: (List tr/TreeElement) text: String acc: (List (Pair String j/Json)) -> (Result j/Json String)
  (if (listEmpty? elems)
    (ok (j/jobj (listReverse acc)))
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken _) (lowerObj tail text acc))
        ((elemNode n)
         (if (= n.kind "property")
           (mt (findPropKey n.children)
             ((none) (err "missing property key"))
             ((some keyTok)
              (let [(rawKey (optionOr (stringSlice text keyTok.start keyTok.end) ""))
                    (key (decodeJsonString rawKey))]
                (mt (findPropValue n.children false)
                  ((none) (err (str "missing value for key " key)))
                  ((some valElem)
                   (mt (lowerElem valElem text)
                     ((err e) (err e))
                     ((ok val)
                      (lowerObj tail text (cons (pair key val) acc)))))))))
           (lowerObj tail text acc))))))

fn lowerArr elems: (List tr/TreeElement) text: String acc: (List j/Json) -> (Result j/Json String)
  (if (listEmpty? elems)
    (ok (j/jarr (listReverse acc)))
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (let [(k tok.kind)]
           (if (or (tr/isTrivia tok) (or (= k "lbracket") (or (= k "rbracket") (= k "comma"))))
             (lowerArr tail text acc)
             (mt (lowerElem head text)
               ((err e) (err e))
               ((ok val) (lowerArr tail text (cons val acc)))))))
        ((elemNode _)
         (mt (lowerElem head text)
           ((err e) (err e))
           ((ok val) (lowerArr tail text (cons val acc))))))))

fn findDocValue elems: (List tr/TreeElement) -> (Option tr/TreeElement)
  (if (listEmpty? elems)
    (none)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (if (tr/isTrivia tok)
           (findDocValue tail)
           (some head)))
        ((elemNode _)
         (some head)))))

fn lower root: tr/Node text: String -> (Result j/Json String)
  (if (not (isValid root))
    (err "JSON CST contains errors")
    (lowerElem (tr/elemNode root) text))

fn lowerBytes root: tr/Node bs: Bytes -> (Result j/Json String)
  (lower root (btxt/bytesToString bs))

fn lowerJson text: String -> (Result j/Json String)
  (let [(root (parseJson text))]
    (lower root text))

fn valueElementKind elem: tr/TreeElement -> String
  (mt elem
    ((tr/elemToken tok) tok.kind)
    ((elemNode n) n.kind))

fn collectSymbolsFromElem elem: tr/TreeElement container: String depth: Int64 text: String acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (mt elem
    ((tr/elemToken _) acc)
    ((elemNode n)
     (let [(k n.kind)]
       (cond
         ((= k "document")
          (mt (findDocValue n.children)
            ((none) acc)
            ((some v) (collectSymbolsFromElem v "" 1 text acc))))
         ((= k "object")
          (collectObjectSymbols n.children container depth text acc))
         ((= k "array")
          (collectArraySymbols n.children container depth 0 text acc))
         (else acc)))))

fn collectObjectSymbols elems: (List tr/TreeElement) container: String depth: Int64 text: String acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (if (listEmpty? elems)
    acc
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken _) (collectObjectSymbols tail container depth text acc))
        ((elemNode n)
         (if (= n.kind "property")
           (let [(accAfterProp (collectPropertySymbol n container depth text acc))]
             (collectObjectSymbols tail container depth text accAfterProp))
           (collectObjectSymbols tail container depth text acc))))))

fn collectPropertySymbol propNode: tr/Node container: String depth: Int64 text: String acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (mt (findPropKey propNode.children)
    ((none) acc)
    ((some keyTok)
     (let [(rawKey (optionOr (stringSlice text keyTok.start keyTok.end) ""))
           (key (decodeJsonString rawKey))]
       (mt (findPropValue propNode.children false)
         ((none) acc)
         ((some valElem)
          (let [(vKind (valueElementKind valElem))
                (vStart (tr/elementStart valElem))
                (vEnd (tr/elementEnd valElem))
                (curPath (if (stringEmpty? container) key (str container "." key)))
                (symDef (sym/makeScopedSymbolDef key vKind vStart vEnd container depth))
                (acc1 (cons symDef acc))]
            (collectSymbolsFromElem valElem curPath (+ depth 1) text acc1)))))))

fn collectArraySymbols elems: (List tr/TreeElement) container: String depth: Int64 idx: Int64 text: String acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (if (listEmpty? elems)
    acc
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (let [(k tok.kind)]
           (if (or (tr/isTrivia tok) (or (= k "lbracket") (or (= k "rbracket") (= k "comma"))))
             (collectArraySymbols tail container depth idx text acc)
             (let [(key (stringFromInt64 idx))
                   (curPath (if (stringEmpty? container) key (str container "." key)))
                   (symDef (sym/makeScopedSymbolDef key k tok.start tok.end container depth))
                   (acc1 (cons symDef acc))]
               (collectArraySymbols tail container depth (+ idx 1) text acc1)))))
        ((elemNode n)
         (let [(key (stringFromInt64 idx))
               (curPath (if (stringEmpty? container) key (str container "." key)))
               (symDef (sym/makeScopedSymbolDef key n.kind n.start n.end container depth))
               (acc1 (cons symDef acc))
               (acc2 (collectSymbolsFromElem head curPath (+ depth 1) text acc1))]
           (collectArraySymbols tail container depth (+ idx 1) text acc2))))))

fn extractSymbols root: tr/Node text: String -> (List sym/SymbolDef)
  (listReverse (collectSymbolsFromElem (tr/elemNode root) "" 1 text (list)))

fn extractSymbolsFromText text: String -> (List sym/SymbolDef)
  (extractSymbols (parseJson text) text)

fn findSymbolByPath root: tr/Node text: String path: String -> (Option sym/SymbolDef)
  (sym/findSymbolDotted (extractSymbols root text) path)

fn jsonOutlineItems root: tr/Node s: src/Source text: String -> (List otl/OutlineItem)
  (let [(allSyms (extractSymbols root text))
        (depth2Syms (filter (fn [(d sym/SymbolDef)] -> Bool (<= (sym/symbolDepth d) 2)) allSyms))]
    (map (fn [(d sym/SymbolDef)] -> otl/OutlineItem
           (let [(st (sym/symbolStart d))
                 (en (sym/symbolEnd d))
                 (stLine (optionOr (src/sourceLineAt s st) 1))
                 (lastOff (if (> en st) (- en 1) st))
                 (enLine (optionOr (src/sourceLineAt s lastOff) stLine))]
             (otl/makeOutlineItem (sym/symbolName d) (sym/symbolKind d) stLine enLine)))
         depth2Syms))

fn jsonOutlineReceipt file: String text: String -> String
  (let [(s (src/sourceFromString file text))
        (root (parseJson text))
        (allSyms (extractSymbols root text))
        (depth2Syms (filter (fn [(d sym/SymbolDef)] -> Bool (<= (sym/symbolDepth d) 2)) allSyms))]
    (otl/formatOutlineReceipt file "json" depth2Syms s))

fn jsonOutlineReceiptFromSource file: String s: src/Source -> String
  (let [(text (btxt/bytesToString (src/sourceBytes s)))
        (root (parseJson text))
        (allSyms (extractSymbols root text))
        (depth2Syms (filter (fn [(d sym/SymbolDef)] -> Bool (<= (sym/symbolDepth d) 2)) allSyms))]
    (otl/formatOutlineReceipt file "json" depth2Syms s))
