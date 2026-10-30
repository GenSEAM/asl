(module asl-syntax/html/lex
  :x [HtmlAttribute
      HtmlTag
      HtmlDoctype
      HtmlComment
      HtmlToken
      tokDoctype
      tokStartTag
      tokEndTag
      tokComment
      tokCharacter
      tokenize
      tokenizeBytes
      tokenizeSource
      tokenizeHtml
      tokensToNode
      tokenSliceString
      tokenSliceBytes!
      isStartTagToken
      isEndTagToken
      isCommentToken
      isDoctypeToken
      isCharacterToken
      isScriptDataToken
      isRawtextToken
      isRcdataToken
      isBomToken
      isCharRefToken
      isCharacterReferenceToken
      parseTag
      parseDoctype
      parseComment
      tagTokenName
      tagTokenAttrs
      tagTokenAttrValue
      tagTokenSelfClosing
      tagTokenClosed
      endTagTokenName
      doctypeTokenName
      doctypeTokenPublicId
      doctypeTokenSystemId
      doctypeTokenForceQuirks
      commentTokenData]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)])

(schema HtmlAttribute
  (:f name String)
  (:f value String)
  (:f nameStart Int64)
  (:f nameEnd Int64)
  (:f valueStart Int64)
  (:f valueEnd Int64))

(schema HtmlTag
  (:f name String)
  (:f isEnd Bool)
  (:f selfClosing Bool)
  (:f attrs (List HtmlAttribute))
  (:f start Int64)
  (:f end Int64))

(schema HtmlDoctype
  (:f name (Option String))
  (:f publicId (Option String))
  (:f systemId (Option String))
  (:f forceQuirks Bool)
  (:f start Int64)
  (:f end Int64))

(schema HtmlComment
  (:f data String)
  (:f bogus Bool)
  (:f start Int64)
  (:f end Int64))

(enum HtmlToken
  (:c tokDoctype [(doctype HtmlDoctype)])
  (:c tokStartTag [(tag HtmlTag)])
  (:c tokEndTag [(name String) (start Int64) (end Int64)])
  (:c tokComment [(comment HtmlComment)])
  (:c tokCharacter [(data String) (start Int64) (end Int64)]))

fn isStartTagToken tok: tr/Token -> Bool
  (= tok.kind "startTag")

fn isEndTagToken tok: tr/Token -> Bool
  (= tok.kind "endTag")

fn isCommentToken tok: tr/Token -> Bool
  (= tok.kind "comment")

fn isDoctypeToken tok: tr/Token -> Bool
  (= tok.kind "doctype")

fn isCharRefToken tok: tr/Token -> Bool
  (= tok.kind "charRef")

fn isCharacterReferenceToken tok: tr/Token -> Bool
  (= tok.kind "charRef")

fn isCharacterToken tok: tr/Token -> Bool
  (or (= tok.kind "character")
  (or (= tok.kind "charRef")
  (or (= tok.kind "scriptData")
  (or (= tok.kind "rawtext")
      (= tok.kind "rcdata")))))

fn isScriptDataToken tok: tr/Token -> Bool
  (= tok.kind "scriptData")

fn isRawtextToken tok: tr/Token -> Bool
  (= tok.kind "rawtext")

fn isRcdataToken tok: tr/Token -> Bool
  (= tok.kind "rcdata")

fn isBomToken tok: tr/Token -> Bool
  (= tok.kind "bom")

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
    (tr/makeNode "html" 0 len elems))

fn isWhitespaceByte b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 10)
  (or (= b 13)
      (= b 12)))))

fn isAsciiAlphaByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
      (and (>= b 97) (<= b 122)))

fn toLowerByte b: Int64 -> Int64
  (if (and (>= b 65) (<= b 90))
    (+ b 32)
    b)

fn isTagDelimByte b: Int64 -> Bool
  (or (isWhitespaceByte b)
  (or (= b 47)
  (or (= b 62)
      (= b 0))))

fn isDoctypeKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 6) len)
       (and (= (toLowerByte (bytesGet bs i)) 100)
       (and (= (toLowerByte (bytesGet bs (+ i 1))) 111)
       (and (= (toLowerByte (bytesGet bs (+ i 2))) 99)
       (and (= (toLowerByte (bytesGet bs (+ i 3))) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 4))) 121)
       (and (= (toLowerByte (bytesGet bs (+ i 5))) 112)
            (= (toLowerByte (bytesGet bs (+ i 6))) 101))))))))

fn isCdataKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 6) len)
       (and (= (bytesGet bs i) 91)
       (and (= (bytesGet bs (+ i 1)) 67)
       (and (= (bytesGet bs (+ i 2)) 68)
       (and (= (bytesGet bs (+ i 3)) 65)
       (and (= (bytesGet bs (+ i 4)) 84)
       (and (= (bytesGet bs (+ i 5)) 65)
            (= (bytesGet bs (+ i 6)) 91))))))))

fn isScriptKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 5) len)
       (and (= (toLowerByte (bytesGet bs i)) 115)
       (and (= (toLowerByte (bytesGet bs (+ i 1))) 99)
       (and (= (toLowerByte (bytesGet bs (+ i 2))) 114)
       (and (= (toLowerByte (bytesGet bs (+ i 3))) 105)
       (and (= (toLowerByte (bytesGet bs (+ i 4))) 112)
            (= (toLowerByte (bytesGet bs (+ i 5))) 116)))))))

fn isStyleKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 4) len)
       (and (= (toLowerByte (bytesGet bs i)) 115)
       (and (= (toLowerByte (bytesGet bs (+ i 1))) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 2))) 121)
       (and (= (toLowerByte (bytesGet bs (+ i 3))) 108)
            (= (toLowerByte (bytesGet bs (+ i 4))) 101))))))

fn isTitleKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 4) len)
       (and (= (toLowerByte (bytesGet bs i)) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 1))) 105)
       (and (= (toLowerByte (bytesGet bs (+ i 2))) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 3))) 108)
            (= (toLowerByte (bytesGet bs (+ i 4))) 101))))))

fn isTextareaKeyword bs: Bytes len: Int64 i: Int64 -> Bool
  (and (< (+ i 7) len)
       (and (= (toLowerByte (bytesGet bs i)) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 1))) 101)
       (and (= (toLowerByte (bytesGet bs (+ i 2))) 120)
       (and (= (toLowerByte (bytesGet bs (+ i 3))) 116)
       (and (= (toLowerByte (bytesGet bs (+ i 4))) 97)
       (and (= (toLowerByte (bytesGet bs (+ i 5))) 114)
       (and (= (toLowerByte (bytesGet bs (+ i 6))) 101)
            (= (toLowerByte (bytesGet bs (+ i 7))) 97)))))))))

fn scanCommentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (< (+ i 2) len)
             (and (= (bytesGet bs i) 45)
                  (and (= (bytesGet bs (+ i 1)) 45)
                       (= (bytesGet bs (+ i 2)) 62))))
      (+ i 3)
      (if (and (< (+ i 3) len)
               (and (= (bytesGet bs i) 45)
                    (and (= (bytesGet bs (+ i 1)) 45)
                         (and (= (bytesGet bs (+ i 2)) 33)
                              (= (bytesGet bs (+ i 3)) 62)))))
        (+ i 4)
        (scanCommentEnd bs len (+ i 1)))))

fn scanUntilGt bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (= (bytesGet bs i) 62)
      (+ i 1)
      (scanUntilGt bs len (+ i 1))))

fn scanCdataEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (< (+ i 2) len)
             (and (= (bytesGet bs i) 93)
                  (and (= (bytesGet bs (+ i 1)) 93)
                       (= (bytesGet bs (+ i 2)) 62))))
      (+ i 3)
      (scanCdataEnd bs len (+ i 1))))

fn scanStartTagQuote bs: Bytes len: Int64 i: Int64 quote: Int64 -> Int64
  (if (>= i len)
    len
    (if (= (bytesGet bs i) quote)
      (+ i 1)
      (scanStartTagQuote bs len (+ i 1) quote)))

fn scanStartTagEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (if (= b 62)
        (+ i 1)
        (if (or (= b 34) (= b 39))
          (let [(next (scanStartTagQuote bs len (+ i 1) b))]
            (scanStartTagEnd bs len next))
          (scanStartTagEnd bs len (+ i 1))))))

fn scanTagNameEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isTagDelimByte b)
        i
        (scanTagNameEnd bs len (+ i 1)))))

fn checkTagSelfClosing bs: Bytes start: Int64 end: Int64 -> Bool
  (if (< (- end start) 3)
    false
    (if (= (bytesGet bs (- end 1)) 62)
      (= (bytesGet bs (- end 2)) 47)
      false))

fn classifySpecialTag bs: Bytes len: Int64 tagStart: Int64 tagEnd: Int64 -> String
  (let [(tagLen (- tagEnd tagStart))]
    (cond
      ((and (= tagLen 6) (isScriptKeyword bs len tagStart)) "script")
      ((and (= tagLen 5) (isStyleKeyword bs len tagStart)) "style")
      ((and (= tagLen 5) (isTitleKeyword bs len tagStart)) "title")
      ((and (= tagLen 8) (isTextareaKeyword bs len tagStart)) "textarea")
      (else "")))

fn isTagStart bs: Bytes len: Int64 pos: Int64 -> Bool
  (if (>= (+ pos 1) len)
    false
    (let [(b1 (bytesGet bs (+ pos 1)))]
      (or (= b1 33)
      (or (= b1 63)
      (or (= b1 47)
          (isAsciiAlphaByte b1))))))

fn scanUntilTagStart bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (= (bytesGet bs i) 60)
      (if (isTagStart bs len i)
        i
        (scanUntilTagStart bs len (+ i 1)))
      (scanUntilTagStart bs len (+ i 1))))

fn scanScriptEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (= (bytesGet bs i) 60)
             (and (< (+ i 1) len)
                  (and (= (bytesGet bs (+ i 1)) 47)
                       (and (isScriptKeyword bs len (+ i 2))
                            (or (>= (+ i 8) len)
                                (isTagDelimByte (bytesGet bs (+ i 8))))))))
      i
      (scanScriptEnd bs len (+ i 1))))

fn scanStyleEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (= (bytesGet bs i) 60)
             (and (< (+ i 1) len)
                  (and (= (bytesGet bs (+ i 1)) 47)
                       (and (isStyleKeyword bs len (+ i 2))
                            (or (>= (+ i 7) len)
                                (isTagDelimByte (bytesGet bs (+ i 7))))))))
      i
      (scanStyleEnd bs len (+ i 1))))

fn scanTitleEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (= (bytesGet bs i) 60)
             (and (< (+ i 1) len)
                  (and (= (bytesGet bs (+ i 1)) 47)
                       (and (isTitleKeyword bs len (+ i 2))
                            (or (>= (+ i 7) len)
                                (isTagDelimByte (bytesGet bs (+ i 7))))))))
      i
      (scanTitleEnd bs len (+ i 1))))

fn scanTextareaEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (= (bytesGet bs i) 60)
             (and (< (+ i 1) len)
                  (and (= (bytesGet bs (+ i 1)) 47)
                       (and (isTextareaKeyword bs len (+ i 2))
                            (or (>= (+ i 10) len)
                                (isTagDelimByte (bytesGet bs (+ i 10))))))))
      i
      (scanTextareaEnd bs len (+ i 1))))


fn isAsciiDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isAsciiHexByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
  (or (and (>= b 65) (<= b 70))
      (and (>= b 97) (<= b 102))))

fn isAsciiAlphanumericByte b: Int64 -> Bool
  (or (isAsciiAlphaByte b)
      (isAsciiDigitByte b))

fn checkLegacyRef bs: Bytes len: Int64 start: Int64 -> Int64
  (let [(rem (- len start))]
    (cond
      ((and (>= rem 7)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 97)
            (and (= (bytesGet bs (+ start 3)) 99)
            (and (= (bytesGet bs (+ start 4)) 117)
            (and (= (bytesGet bs (+ start 5)) 116)
                 (= (bytesGet bs (+ start 6)) 101))))))))
       (+ start 7))
      ((and (>= rem 7)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 103)
            (and (= (bytesGet bs (+ start 3)) 114)
            (and (= (bytesGet bs (+ start 4)) 97)
            (and (= (bytesGet bs (+ start 5)) 118)
                 (= (bytesGet bs (+ start 6)) 101))))))))
       (+ start 7))
      ((and (>= rem 7)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 116)
            (and (= (bytesGet bs (+ start 3)) 105)
            (and (= (bytesGet bs (+ start 4)) 108)
            (and (= (bytesGet bs (+ start 5)) 100)
                 (= (bytesGet bs (+ start 6)) 101))))))))
       (+ start 7))
      ((and (>= rem 7)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 67)
            (and (= (bytesGet bs (+ start 2)) 99)
            (and (= (bytesGet bs (+ start 3)) 101)
            (and (= (bytesGet bs (+ start 4)) 100)
            (and (= (bytesGet bs (+ start 5)) 105)
                 (= (bytesGet bs (+ start 6)) 108))))))))
       (+ start 7))
      ((and (>= rem 6)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 69)
            (and (= (bytesGet bs (+ start 3)) 108)
            (and (= (bytesGet bs (+ start 4)) 105)
                 (= (bytesGet bs (+ start 5)) 103)))))))
       (+ start 6))
      ((and (>= rem 6)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 99)
            (and (= (bytesGet bs (+ start 3)) 105)
            (and (= (bytesGet bs (+ start 4)) 114)
                 (= (bytesGet bs (+ start 5)) 99)))))))
       (+ start 6))
      ((and (>= rem 6)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 114)
            (and (= (bytesGet bs (+ start 3)) 105)
            (and (= (bytesGet bs (+ start 4)) 110)
                 (= (bytesGet bs (+ start 5)) 103)))))))
       (+ start 6))
      ((and (>= rem 6)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 110)
            (and (= (bytesGet bs (+ start 2)) 111)
            (and (= (bytesGet bs (+ start 3)) 116)
            (and (= (bytesGet bs (+ start 4)) 105)
                 (= (bytesGet bs (+ start 5)) 116)))))))
       (+ start 6))
      ((and (>= rem 6)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 110)
            (and (= (bytesGet bs (+ start 2)) 111)
            (and (= (bytesGet bs (+ start 3)) 116)
            (and (= (bytesGet bs (+ start 4)) 105)
                 (= (bytesGet bs (+ start 5)) 110)))))))
       (+ start 6))
      ((and (>= rem 5)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 117)
            (and (= (bytesGet bs (+ start 3)) 109)
                 (= (bytesGet bs (+ start 4)) 108))))))
       (+ start 5))
      ((and (>= rem 5)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 67)
            (and (= (bytesGet bs (+ start 2)) 79)
            (and (= (bytesGet bs (+ start 3)) 80)
                 (= (bytesGet bs (+ start 4)) 89))))))
       (+ start 5))
      ((and (>= rem 5)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 110)
            (and (= (bytesGet bs (+ start 2)) 111)
            (and (= (bytesGet bs (+ start 3)) 116)
                 (= (bytesGet bs (+ start 4)) 105))))))
       (+ start 5))
      ((and (>= rem 4)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 65)
            (and (= (bytesGet bs (+ start 2)) 77)
                 (= (bytesGet bs (+ start 3)) 80)))))
       (+ start 4))
      ((and (>= rem 4)
            (and (= (bytesGet bs start) 38)
            (and (= (bytesGet bs (+ start 1)) 110)
            (and (= (bytesGet bs (+ start 2)) 111)
                 (= (bytesGet bs (+ start 3)) 116)))))
       (+ start 4))
      (else -1)))
fn scanCharRefDigits bs: Bytes len: Int64 i: Int64 isHex: Bool -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (= b 59)
        (+ i 1)
        (if (if isHex (isAsciiHexByte b) (isAsciiDigitByte b))
          (scanCharRefDigits bs len (+ i 1) isHex)
          i))))

fn scanCharRefNamed bs: Bytes len: Int64 i: Int64 count: Int64 -> Int64
  (if (or (>= i len) (> count 32))
    -1
    (let [(b (bytesGet bs i))]
      (if (= b 59)
        (if (> count 0) (+ i 1) -1)
        (if (isAsciiAlphanumericByte b)
          (scanCharRefNamed bs len (+ i 1) (+ count 1))
          -1))))

fn scanCharRef bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= (+ i 2) len)
    -1
    (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 35) (= (toLowerByte (bytesGet bs (+ i 2))) 120)))
      (if (and (< (+ i 3) len) (isAsciiHexByte (bytesGet bs (+ i 3))))
        (scanCharRefDigits bs len (+ i 4) true)
        -1)
      (if (= (bytesGet bs (+ i 1)) 35)
        (if (isAsciiDigitByte (bytesGet bs (+ i 2)))
          (scanCharRefDigits bs len (+ i 3) false)
          -1)
        (if (isAsciiAlphaByte (bytesGet bs (+ i 1)))
          (let [(semiEnd (scanCharRefNamed bs len (+ i 2) 1))]
            (if (> semiEnd 0)
              semiEnd
              (checkLegacyRef bs len i)))
          -1))))

fn scanUntilNextRefOrLimit bs: Bytes limit: Int64 idx: Int64 -> Int64
  (if (>= idx limit)
    limit
    (if (= (bytesGet bs idx) 38)
      (let [(refEnd (scanCharRef bs limit idx))]
        (if (> refEnd idx)
          idx
          (scanUntilNextRefOrLimit bs limit (+ idx 1))))
      (scanUntilNextRefOrLimit bs limit (+ idx 1))))

fn scanDataAndCharRefs bs: Bytes len: Int64 cur: Int64 limit: Int64 nextState: String nextRawTag: String acc: (List tr/Token) -> (List tr/Token)
  (if (>= cur limit)
    (tokenizeLoop bs len limit nextState nextRawTag acc)
    (let [(nextRef (scanUntilNextRefOrLimit bs limit cur))]
      (if (> nextRef cur)
        (let [(acc1 (cons (tr/makeToken "character" cur nextRef) acc))]
          (if (< nextRef limit)
            (let [(refEnd (scanCharRef bs limit nextRef))]
              (scanDataAndCharRefs bs len refEnd limit nextState nextRawTag (cons (tr/makeToken "charRef" nextRef refEnd) acc1)))
            (tokenizeLoop bs len limit nextState nextRawTag acc1)))
        (let [(refEnd (scanCharRef bs limit cur))]
          (scanDataAndCharRefs bs len refEnd limit nextState nextRawTag (cons (tr/makeToken "charRef" cur refEnd) acc))))))

fn tokenizeLoop bs: Bytes len: Int64 i: Int64 state: String rawTag: String acc: (List tr/Token) -> (List tr/Token)
  (if (>= i len)
    (listReverse acc)
    (cond
      ((= state "script")
       (let [(endPos (scanScriptEnd bs len i))]
         (if (= endPos len)
           (if (> endPos i)
             (listReverse (cons (tr/makeToken "scriptData" i endPos) acc))
             (listReverse acc))
           (let [(acc1 (if (> endPos i)
                         (cons (tr/makeToken "scriptData" i endPos) acc)
                         acc))
                 (closeEnd (scanUntilGt bs len (+ endPos 2)))
                 (acc2 (cons (tr/makeToken "endTag" endPos closeEnd) acc1))]
             (tokenizeLoop bs len closeEnd "data" "" acc2)))))
      ((= state "style")
       (let [(endPos (scanStyleEnd bs len i))]
         (if (= endPos len)
           (if (> endPos i)
             (listReverse (cons (tr/makeToken "rawtext" i endPos) acc))
             (listReverse acc))
           (let [(acc1 (if (> endPos i)
                         (cons (tr/makeToken "rawtext" i endPos) acc)
                         acc))
                 (closeEnd (scanUntilGt bs len (+ endPos 2)))
                 (acc2 (cons (tr/makeToken "endTag" endPos closeEnd) acc1))]
             (tokenizeLoop bs len closeEnd "data" "" acc2)))))
      ((= state "title")
       (let [(endPos (scanTitleEnd bs len i))]
         (if (= endPos len)
           (if (> endPos i)
             (listReverse (cons (tr/makeToken "rcdata" i endPos) acc))
             (listReverse acc))
           (let [(acc1 (if (> endPos i)
                         (cons (tr/makeToken "rcdata" i endPos) acc)
                         acc))
                 (closeEnd (scanUntilGt bs len (+ endPos 2)))
                 (acc2 (cons (tr/makeToken "endTag" endPos closeEnd) acc1))]
             (tokenizeLoop bs len closeEnd "data" "" acc2)))))
      ((= state "textarea")
       (let [(endPos (scanTextareaEnd bs len i))]
         (if (= endPos len)
           (if (> endPos i)
             (listReverse (cons (tr/makeToken "rcdata" i endPos) acc))
             (listReverse acc))
           (let [(acc1 (if (> endPos i)
                         (cons (tr/makeToken "rcdata" i endPos) acc)
                         acc))
                 (closeEnd (scanUntilGt bs len (+ endPos 2)))
                 (acc2 (cons (tr/makeToken "endTag" endPos closeEnd) acc1))]
             (tokenizeLoop bs len closeEnd "data" "" acc2)))))
      (else
       (let [(tagStart (scanUntilTagStart bs len i))]
         (if (> tagStart i)
           (scanDataAndCharRefs bs len i tagStart "data" "" acc)
           (if (>= tagStart len)
             (listReverse acc)
             (let [(b1 (bytesGet bs (+ tagStart 1)))]
               (cond
                 ((= b1 33)
                  (if (and (< (+ tagStart 3) len)
                           (and (= (bytesGet bs (+ tagStart 2)) 45)
                                (= (bytesGet bs (+ tagStart 3)) 45)))
                    (let [(commentEnd (scanCommentEnd bs len (+ tagStart 4)))]
                      (tokenizeLoop bs len commentEnd "data" "" (cons (tr/makeToken "comment" tagStart commentEnd) acc)))
                    (if (isDoctypeKeyword bs len (+ tagStart 2))
                      (let [(doctypeEnd (scanUntilGt bs len (+ tagStart 9)))]
                        (tokenizeLoop bs len doctypeEnd "data" "" (cons (tr/makeToken "doctype" tagStart doctypeEnd) acc)))
                      (if (isCdataKeyword bs len (+ tagStart 2))
                        (let [(cdataEnd (scanCdataEnd bs len (+ tagStart 9)))]
                          (tokenizeLoop bs len cdataEnd "data" "" (cons (tr/makeToken "comment" tagStart cdataEnd) acc)))
                        (let [(bogusEnd (scanUntilGt bs len (+ tagStart 2)))]
                          (tokenizeLoop bs len bogusEnd "data" "" (cons (tr/makeToken "comment" tagStart bogusEnd) acc)))))))
                 ((= b1 63)
                  (let [(bogusEnd (scanUntilGt bs len (+ tagStart 2)))]
                    (tokenizeLoop bs len bogusEnd "data" "" (cons (tr/makeToken "comment" tagStart bogusEnd) acc))))
                 ((= b1 47)
                  (if (>= (+ tagStart 2) len)
                    (tokenizeLoop bs len (+ tagStart 2) "data" "" (cons (tr/makeToken "character" tagStart (+ tagStart 2)) acc))
                    (let [(b2 (bytesGet bs (+ tagStart 2)))]
                      (if (isAsciiAlphaByte b2)
                        (let [(endTagEnd (scanUntilGt bs len (+ tagStart 2)))]
                          (tokenizeLoop bs len endTagEnd "data" "" (cons (tr/makeToken "endTag" tagStart endTagEnd) acc)))
                        (if (= b2 62)
                          (tokenizeLoop bs len (+ tagStart 3) "data" "" (cons (tr/makeToken "endTag" tagStart (+ tagStart 3)) acc))
                          (let [(bogusEnd (scanUntilGt bs len (+ tagStart 2)))]
                            (tokenizeLoop bs len bogusEnd "data" "" (cons (tr/makeToken "comment" tagStart bogusEnd) acc))))))))
                 ((isAsciiAlphaByte b1)
                  (let [(tagEnd (scanStartTagEnd bs len (+ tagStart 1)))
                        (nameEnd (scanTagNameEnd bs len (+ tagStart 1)))
                        (special (classifySpecialTag bs len (+ tagStart 1) nameEnd))
                        (selfClosing (checkTagSelfClosing bs tagStart tagEnd))
                        (accNext (cons (tr/makeToken "startTag" tagStart tagEnd) acc))]
                    (if (or selfClosing (= special ""))
                      (tokenizeLoop bs len tagEnd "data" "" accNext)
                      (tokenizeLoop bs len tagEnd special "" accNext))))
                 (else
                  (tokenizeLoop bs len (+ tagStart 1) "data" "" (cons (tr/makeToken "character" tagStart (+ tagStart 1)) acc)))))))))))

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (let [(len (bytesLength bs))]
    (if (= len 0)
      (list)
      (if (and (>= len 3)
               (and (= (bytesGet bs 0) 239)
                    (and (= (bytesGet bs 1) 187)
                         (= (bytesGet bs 2) 191))))
        (tokenizeLoop bs len 3 "data" "" (list (tr/makeToken "bom" 0 3)))
        (tokenizeLoop bs len 0 "data" "" (list)))))

fn tokenizeSource s: src/Source -> (List tr/Token)
  (tokenizeBytes (src/sourceBytes s))

fn tokenize text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))

fn isWhitespaceChar c: String -> Bool
  (or (= c " ")
  (or (= c "\t")
  (or (= c "\n")
  (or (= c "\r")
      (= c "\x0c")))))

fn isDelimChar c: String -> Bool
  (or (isWhitespaceChar c)
  (or (= c "/")
  (or (= c ">")
      (= c "="))))

fn scanStringWhitespace text: String len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (isWhitespaceChar c)
        (scanStringWhitespace text len (+ i 1))
        i)))

fn scanStringUntilDelim text: String len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (isDelimChar c)
        i
        (scanStringUntilDelim text len (+ i 1)))))

fn scanStringQuote text: String len: Int64 i: Int64 quote: String -> Int64
  (if (>= i len)
    len
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (= c quote)
        i
        (scanStringQuote text len (+ i 1) quote))))

fn isSlashBeforeClose text: String len: Int64 i: Int64 -> Bool
  (if (>= i len)
    false
    (if (= (optionOr (stringSlice text i (+ i 1)) "") "/")
      (let [(afterSlash (scanStringWhitespace text len (+ i 1)))]
        (if (< afterSlash len)
          (= (optionOr (stringSlice text afterSlash (+ afterSlash 1)) "") ">")
          false))
      false))

fn scanStringUnquotedVal text: String len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (or (isWhitespaceChar c) (or (= c ">") (isSlashBeforeClose text len i)))
        i
        (scanStringUnquotedVal text len (+ i 1)))))

fn sanitizeCommentData data: String -> String
  (if (stringContains? data "\u0000")
    (stringReplace data "\u0000" "\uFFFD")
    data)

fn parseAttributesLoop text: String len: Int64 cur: Int64 tokStart: Int64 acc: (List HtmlAttribute) -> (List HtmlAttribute)
  (let [(i (scanStringWhitespace text len cur))]
    (if (>= i len)
      (listReverse acc)
      (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
        (cond
          ((= c ">") (listReverse acc))
          ((isSlashBeforeClose text len i) (listReverse acc))
          ((= c "/") (parseAttributesLoop text len (+ i 1) tokStart acc))
          (else
          (let [(nameEnd (scanStringUntilDelim text len i))
                (nameEndValid (if (= nameEnd i) (+ i 1) nameEnd))
                (rawName (stringLower (optionOr (stringSlice text i nameEndValid) "")))
                (name (sanitizeCommentData rawName))
                (nameStartAbs (+ tokStart i))
                (nameEndAbs (+ tokStart nameEndValid))
                (afterName (scanStringWhitespace text len nameEndValid))]
            (if (>= afterName len)
              (let [(attr (HtmlAttribute :name name :value "" :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart nameEndAbs :valueEnd nameEndAbs))]
                (listReverse (cons attr acc)))
              (let [(eqChar (optionOr (stringSlice text afterName (+ afterName 1)) ""))]
                (if (= eqChar "=")
                  (let [(afterEq (scanStringWhitespace text len (+ afterName 1)))]
                    (if (>= afterEq len)
                      (let [(attr (HtmlAttribute :name name :value "" :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart nameEndAbs :valueEnd nameEndAbs))]
                        (listReverse (cons attr acc)))
                      (let [(quoteChar (optionOr (stringSlice text afterEq (+ afterEq 1)) ""))]
                        (cond
                          ((or (= quoteChar "\"") (= quoteChar "'"))
                           (let [(valStart (+ afterEq 1))
                                 (valEnd (scanStringQuote text len valStart quoteChar))
                                 (rawVal (optionOr (stringSlice text valStart valEnd) ""))
                                 (val (sanitizeCommentData rawVal))
                                 (valStartAbs (+ tokStart valStart))
                                 (valEndAbs (+ tokStart valEnd))
                                 (attr (HtmlAttribute :name name :value val :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart valStartAbs :valueEnd valEndAbs))
                                 (nextCur (if (< valEnd len) (+ valEnd 1) len))]
                             (parseAttributesLoop text len nextCur tokStart (cons attr acc))))
                          ((= quoteChar ">")
                           (let [(attr (HtmlAttribute :name name :value "" :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart nameEndAbs :valueEnd nameEndAbs))]
                             (listReverse (cons attr acc))))
                          (else
                           (let [(valStart afterEq)
                                 (valEnd (scanStringUnquotedVal text len valStart))
                                 (rawVal (optionOr (stringSlice text valStart valEnd) ""))
                                 (val (sanitizeCommentData rawVal))
                                 (valStartAbs (+ tokStart valStart))
                                 (valEndAbs (+ tokStart valEnd))
                                 (attr (HtmlAttribute :name name :value val :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart valStartAbs :valueEnd valEndAbs))]
                             (parseAttributesLoop text len valEnd tokStart (cons attr acc))))))))
                  (let [(attr (HtmlAttribute :name name :value "" :nameStart nameStartAbs :nameEnd nameEndAbs :valueStart nameEndAbs :valueEnd nameEndAbs))]
                    (parseAttributesLoop text len afterName tokStart (cons attr acc))))))))))))

fn parseTag text: String tok: tr/Token -> HtmlTag
  (let [(tokStart tok.start)
        (tokEnd tok.end)
        (raw (tokenSliceString text tok))
        (len (stringLength raw))]
    (if (< len 2)
      (HtmlTag :name "" :isEnd false :selfClosing false :attrs (list) :start tokStart :end tokEnd)
      (let [(isEnd (= (optionOr (stringSlice raw 1 2) "") "/"))
            (nameStart (if isEnd 2 1))
            (nameEnd (scanStringUntilDelim raw len nameStart))
            (rawName (stringLower (optionOr (stringSlice raw nameStart nameEnd) "")))
            (name (sanitizeCommentData rawName))
            (selfClosing (checkTagSelfClosing (stringToBytes raw) 0 len))
            (attrs (if isEnd (list) (parseAttributesLoop raw len nameEnd tokStart (list))))]
        (HtmlTag :name name :isEnd isEnd :selfClosing selfClosing :attrs attrs :start tokStart :end tokEnd))))

fn parseDoctypeLoop raw: String len: Int64 i: Int64 state: Int64 name: String pubId: String sysId: String quote: String hasName: Bool hasPub: Bool hasSys: Bool forceQuirks: Bool tokStart: Int64 tokEnd: Int64 -> HtmlDoctype
  (if (>= i len)
    (let [(eofQuirks (if (not (stringEndsWith? raw ">"))
                       (if (<= state 11)
                         true
                         forceQuirks)
                       forceQuirks))]
      (HtmlDoctype :name (if hasName (some name) (none))
                   :publicId (if hasPub (some pubId) (none))
                   :systemId (if hasSys (some sysId) (none))
                   :forceQuirks eofQuirks
                   :start tokStart
                   :end tokEnd))
    (let [(c (optionOr (stringSlice raw i (+ i 1)) ""))]
      (cond
        ((= state 0)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 0 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           ((= c "\u0000")
            (parseDoctypeLoop raw len (+ i 1) 1 "\uFFFD" pubId sysId quote true hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len (+ i 1) 1 (stringLower c) pubId sysId quote true hasPub hasSys forceQuirks tokStart tokEnd))))
        ((= state 1)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 2 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c "\u0000")
            (parseDoctypeLoop raw len (+ i 1) 1 (stringConcat name "\uFFFD") pubId sysId quote true hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len (+ i 1) 1 (stringConcat name (stringLower c)) pubId sysId quote true hasPub hasSys forceQuirks tokStart tokEnd))))
        ((= state 2)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 2 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (let [(sub6 (stringUpper (optionOr (stringSlice raw i (+ i 6)) "")))]
              (cond
                ((= sub6 "PUBLIC")
                 (parseDoctypeLoop raw len (+ i 6) 3 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
                ((= sub6 "SYSTEM")
                 (parseDoctypeLoop raw len (+ i 6) 8 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
                (else
                 (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd)))))))
        ((= state 3)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 4 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 5 name "" sysId c hasName true hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 4)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 4 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 5 name "" sysId c hasName true hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 5)
         (cond
           ((= c quote)
            (parseDoctypeLoop raw len (+ i 1) 6 name pubId sysId "" hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           ((= c "\u0000")
            (parseDoctypeLoop raw len (+ i 1) 5 name (stringConcat pubId "\uFFFD") sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len (+ i 1) 5 name (stringConcat pubId c) sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))))
        ((= state 6)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 7 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId "" c hasName hasPub true forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 7)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 7 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId "" c hasName hasPub true forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 8)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 9 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId "" c hasName hasPub true forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 9)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 9 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((or (= c "\"") (= c "'"))
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId "" c hasName hasPub true forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))))
        ((= state 10)
         (cond
           ((= c quote)
            (parseDoctypeLoop raw len (+ i 1) 11 name pubId sysId "" hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys true tokStart tokEnd))
           ((= c "\u0000")
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId (stringConcat sysId "\uFFFD") quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len (+ i 1) 10 name pubId (stringConcat sysId c) quote hasName hasPub hasSys forceQuirks tokStart tokEnd))))
        ((= state 11)
         (cond
           ((isWhitespaceChar c)
            (parseDoctypeLoop raw len (+ i 1) 11 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           ((= c ">")
            (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))
           (else
            (parseDoctypeLoop raw len i 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))))
        (else
         (if (= c ">")
           (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd)
           (parseDoctypeLoop raw len (+ i 1) 12 name pubId sysId quote hasName hasPub hasSys forceQuirks tokStart tokEnd))))))

fn parseDoctype text: String tok: tr/Token -> HtmlDoctype
  (let [(tokStart tok.start)
        (tokEnd tok.end)
        (raw (tokenSliceString text tok))
        (len (stringLength raw))]
    (if (< len 9)
      (HtmlDoctype :name (none) :publicId (none) :systemId (none) :forceQuirks true :start tokStart :end tokEnd)
      (parseDoctypeLoop raw len 9 0 "" "" "" "" false false false false tokStart tokEnd)))

fn parseComment text: String tok: tr/Token -> HtmlComment
  (let [(tokStart tok.start)
        (tokEnd tok.end)
        (raw (tokenSliceString text tok))
        (len (stringLength raw))]
    (cond
      ((stringStartsWith? raw "<!--")
       (cond
         ((or (= raw "<!-->") (= raw "<!--->"))
          (HtmlComment :data "" :bogus false :start tokStart :end tokEnd))
         ((stringEndsWith? raw "-->")
          (let [(data (if (>= len 7) (optionOr (stringSlice raw 4 (- len 3)) "") ""))]
            (HtmlComment :data (sanitizeCommentData data) :bogus false :start tokStart :end tokEnd)))
         ((stringEndsWith? raw "--!>")
          (let [(data (if (>= len 8) (optionOr (stringSlice raw 4 (- len 4)) "") ""))]
            (HtmlComment :data (sanitizeCommentData data) :bogus false :start tokStart :end tokEnd)))
         ((stringEndsWith? raw "--")
          (let [(data (if (>= len 6) (optionOr (stringSlice raw 4 (- len 2)) "") ""))]
            (HtmlComment :data (sanitizeCommentData data) :bogus false :start tokStart :end tokEnd)))
         ((stringEndsWith? raw "-")
          (let [(data (if (>= len 5) (optionOr (stringSlice raw 4 (- len 1)) "") ""))]
            (HtmlComment :data (sanitizeCommentData data) :bogus false :start tokStart :end tokEnd)))
         (else
          (let [(data (if (>= len 4) (optionOr (stringSlice raw 4 len) "") ""))]
            (HtmlComment :data (sanitizeCommentData data) :bogus false :start tokStart :end tokEnd)))))
      ((stringStartsWith? raw "<?")
       (let [(cutEnd (if (stringEndsWith? raw ">") (- len 1) len))
             (data (if (> cutEnd 1) (optionOr (stringSlice raw 1 cutEnd) "") ""))]
         (HtmlComment :data (sanitizeCommentData data) :bogus true :start tokStart :end tokEnd)))
      ((or (stringStartsWith? raw "<!") (stringStartsWith? raw "</"))
       (let [(cutEnd (if (stringEndsWith? raw ">") (- len 1) len))
             (data (if (> cutEnd 2) (optionOr (stringSlice raw 2 cutEnd) "") ""))]
         (HtmlComment :data (sanitizeCommentData data) :bogus true :start tokStart :end tokEnd)))
      (else
       (HtmlComment :data (sanitizeCommentData raw) :bogus true :start tokStart :end tokEnd))))

fn tagTokenName text: String tok: tr/Token -> String
  (parseTag text tok).name

fn tagTokenAttrs text: String tok: tr/Token -> (List HtmlAttribute)
  (parseTag text tok).attrs

fn findAttrValue attrs: (List HtmlAttribute) targetName: String -> (Option String)
  (if (listEmpty? attrs)
    (none)
    (let [(attr (optionOr (listHead attrs) (HtmlAttribute :name "" :value "" :nameStart 0 :nameEnd 0 :valueStart 0 :valueEnd 0)))]
      (if (= attr.name targetName)
        (some attr.value)
        (findAttrValue (optionOr (listTail attrs) (list)) targetName))))

fn tagTokenAttrValue text: String tok: tr/Token name: String -> (Option String)
  (findAttrValue (tagTokenAttrs text tok) name)

fn tagTokenSelfClosing text: String tok: tr/Token -> Bool
  (parseTag text tok).selfClosing

fn tagTokenClosed text: String tok: tr/Token -> Bool
  (stringEndsWith? (tokenSliceString text tok) ">")

fn endTagTokenName text: String tok: tr/Token -> String
  (parseTag text tok).name

fn doctypeTokenName text: String tok: tr/Token -> (Option String)
  (parseDoctype text tok).name

fn doctypeTokenPublicId text: String tok: tr/Token -> (Option String)
  (parseDoctype text tok).publicId

fn doctypeTokenSystemId text: String tok: tr/Token -> (Option String)
  (parseDoctype text tok).systemId

fn doctypeTokenForceQuirks text: String tok: tr/Token -> Bool
  (parseDoctype text tok).forceQuirks

fn commentTokenData text: String tok: tr/Token -> String
  (parseComment text tok).data

fn htmlTokenFromToken text: String tok: tr/Token -> HtmlToken
  (cond
    ((isDoctypeToken tok) (tokDoctype (parseDoctype text tok)))
    ((isStartTagToken tok) (tokStartTag (parseTag text tok)))
    ((isEndTagToken tok) (tokEndTag (endTagTokenName text tok) tok.start tok.end))
    ((isCommentToken tok) (tokComment (parseComment text tok)))
    (else (tokCharacter (tokenSliceString text tok) tok.start tok.end)))

fn tokenizeHtml text: String -> (List HtmlToken)
  (let [(toks (tokenize text))]
    (map (fn [(t tr/Token)] -> HtmlToken (htmlTokenFromToken text t)) toks))
