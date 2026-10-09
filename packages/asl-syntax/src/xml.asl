(module asl-syntax/xml
  :x [XmlAttr
      makeXmlAttr
      attrName
      attrValue
      attrStart
      attrEnd
      tokenize
      tokenizeBytes
      parse
      parseBytes
      parseXml
      parseXmlBytes
      isWellFormed
      documentRootElement
      elementName
      elementAttributes
      attributeValue
      elementId
      elementChildren
      extractSymbols
      extractSymbolsFromText]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/print :a pr)])

(schema XmlAttr
  (:f name String)
  (:f value String)
  (:f start Int64)
  (:f end Int64))

(schema OpenElem
  (:f tag String)
  (:f start Int64)
  (:f children (List tr/TreeElement)))

(schema TagParseResult
  (:f kind String)
  (:f tag String)
  (:f node tr/Node)
  (:f attrs (List XmlAttr))
  (:f endIdx Int64)
  (:f error? Bool))

fn makeXmlAttr name: String value: String start: Int64 end: Int64 -> XmlAttr
  (XmlAttr :name name :value value :start start :end end)

fn attrName a: XmlAttr -> String
  a.name

fn attrValue a: XmlAttr -> String
  a.value

fn attrStart a: XmlAttr -> Int64
  a.start

fn attrEnd a: XmlAttr -> Int64
  a.end

fn isWhitespaceByte b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 10)
      (= b 13))))

fn isNameStartByte b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122))
  (or (and (>= b 65) (<= b 90))
  (or (= b 95)
  (or (= b 58)
      (>= b 128)))))

fn isNameByte b: Int64 -> Bool
  (or (isNameStartByte b)
  (or (and (>= b 48) (<= b 57))
  (or (= b 45)
      (= b 46))))

fn sliceString bs: Bytes start: Int64 end: Int64 textOpt: (Option String) -> String
  (mt textOpt
    ((some text)
     (optionOr (stringSlice text start end) ""))
    ((none)
     (let [(len (- end start))]
       (if (<= len 0)
         ""
         (let [(table " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
               (chars (map (fn [(i Int64)] -> String
                             (let [(b (bytesGet bs (+ start i)))]
                               (if (and (>= b 32) (<= b 126))
                                 (optionOr (stringSlice table (- b 32) (- b 31)) "")
                                 "")))
                           (range 0 len)))]
           (stringJoin chars ""))))))

fn scanWhitespace bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isWhitespaceByte (bytesGet bs idx))
      (scanWhitespace bs len (+ idx 1))
      idx))

fn scanNameLoop bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isNameByte (bytesGet bs idx))
      (scanNameLoop bs len (+ idx 1))
      idx))

fn scanName bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isNameStartByte (bytesGet bs idx))
      (scanNameLoop bs len (+ idx 1))
      idx))

fn bytesMatchSub bs: Bytes len: Int64 idx: Int64 sub: Bytes subLen: Int64 k: Int64 -> Bool
  (if (>= k subLen)
    true
    (if (>= (+ idx k) len)
      false
      (if (!= (bytesGet bs (+ idx k)) (bytesGet sub k))
        false
        (bytesMatchSub bs len idx sub subLen (+ k 1)))))

fn scanUntilSubLoop bs: Bytes len: Int64 idx: Int64 sub: Bytes subLen: Int64 -> (Option Int64)
  (if (> (+ idx subLen) len)
    (none)
    (if (bytesMatchSub bs len idx sub subLen 0)
      (some idx)
      (scanUntilSubLoop bs len (+ idx 1) sub subLen)))

fn commentContainsDoubleHyphen bs: Bytes idx: Int64 endIdx: Int64 -> Bool
  (if (>= (+ idx 1) endIdx)
    false
    (if (and (= (bytesGet bs idx) 45) (= (bytesGet bs (+ idx 1)) 45))
      true
      (commentContainsDoubleHyphen bs (+ idx 1) endIdx)))

fn scanDoctypeLoop bs: Bytes len: Int64 idx: Int64 inSubset: Bool -> (Option Int64)
  (if (>= idx len)
    (none)
    (let [(b (bytesGet bs idx))]
      (if inSubset
        (if (= b 93)
          (scanDoctypeLoop bs len (+ idx 1) false)
          (scanDoctypeLoop bs len (+ idx 1) true))
        (if (= b 91)
          (scanDoctypeLoop bs len (+ idx 1) true)
          (if (= b 62)
            (some (+ idx 1))
            (scanDoctypeLoop bs len (+ idx 1) false))))))

fn textContainsCDataEnd bs: Bytes idx: Int64 endIdx: Int64 -> Bool
  (if (>= (+ idx 2) endIdx)
    false
    (if (and (= (bytesGet bs idx) 93)
        (and (= (bytesGet bs (+ idx 1)) 93)
             (= (bytesGet bs (+ idx 2)) 62)))
      true
      (textContainsCDataEnd bs (+ idx 1) endIdx)))

fn scanHexRefLoop bs: Bytes len: Int64 idx: Int64 endIdx: Int64 count: Int64 -> (Option Int64)
  (if (>= idx endIdx)
    (none)
    (let [(b (bytesGet bs idx))]
      (if (= b 59)
        (if (> count 0) (some (+ idx 1)) (none))
        (if (or (and (>= b 48) (<= b 57))
            (or (and (>= b 97) (<= b 102))
                (and (>= b 65) (<= b 70))))
          (scanHexRefLoop bs len (+ idx 1) endIdx (+ count 1))
          (none)))))

fn scanDecRefLoop bs: Bytes len: Int64 idx: Int64 endIdx: Int64 count: Int64 -> (Option Int64)
  (if (>= idx endIdx)
    (none)
    (let [(b (bytesGet bs idx))]
      (if (= b 59)
        (if (> count 0) (some (+ idx 1)) (none))
        (if (and (>= b 48) (<= b 57))
          (scanDecRefLoop bs len (+ idx 1) endIdx (+ count 1))
          (none)))))

fn scanCharRef bs: Bytes len: Int64 idx: Int64 endIdx: Int64 -> (Option Int64)
  (if (>= idx endIdx)
    (none)
    (let [(b (bytesGet bs idx))]
      (if (or (= b 120) (= b 88))
        (scanHexRefLoop bs len (+ idx 1) endIdx 0)
        (if (and (>= b 48) (<= b 57))
          (scanDecRefLoop bs len (+ idx 1) endIdx 1)
          (none)))))

fn scanEntityRefLoop bs: Bytes len: Int64 idx: Int64 endIdx: Int64 count: Int64 -> (Option Int64)
  (if (>= idx endIdx)
    (none)
    (let [(b (bytesGet bs idx))]
      (if (= b 59)
        (if (> count 0) (some (+ idx 1)) (none))
        (if (isNameByte b)
          (scanEntityRefLoop bs len (+ idx 1) endIdx (+ count 1))
          (none)))))

fn isValidRefAt bs: Bytes len: Int64 idx: Int64 endIdx: Int64 -> (Option Int64)
  (if (>= (+ idx 2) endIdx)
    (none)
    (if (= (bytesGet bs (+ idx 1)) 35)
      (scanCharRef bs len (+ idx 2) endIdx)
      (if (isNameStartByte (bytesGet bs (+ idx 1)))
        (scanEntityRefLoop bs len (+ idx 2) endIdx 1)
        (none))))

fn textHasInvalidAmpersand bs: Bytes idx: Int64 endIdx: Int64 len: Int64 -> Bool
  (if (>= idx endIdx)
    false
    (if (= (bytesGet bs idx) 38)
      (mt (isValidRefAt bs len idx endIdx)
        ((none) true)
        ((some nextIdx) (textHasInvalidAmpersand bs nextIdx endIdx len)))
      (textHasInvalidAmpersand bs (+ idx 1) endIdx len)))

fn textHasNonWhitespace bs: Bytes idx: Int64 endIdx: Int64 -> Bool
  (if (>= idx endIdx)
    false
    (if (isWhitespaceByte (bytesGet bs idx))
      (textHasNonWhitespace bs (+ idx 1) endIdx)
      true))

fn attrListHasName attrs: (List XmlAttr) name: String -> Bool
  (mt (listHead attrs)
    ((none) false)
    ((some a)
     (if (= a.name name)
       true
       (attrListHasName (optionOr (listTail attrs) (list)) name))))

fn scanAttrValLoop bs: Bytes len: Int64 idx: Int64 q: Int64 hasLt: Bool -> (Option (Pair Int64 Bool))
  (if (>= idx len)
    (none)
    (let [(b (bytesGet bs idx))]
      (if (= b q)
        (some (pair idx hasLt))
        (let [(nextLt (or hasLt (= b 60)))]
          (scanAttrValLoop bs len (+ idx 1) q nextLt)))))

fn scanUnquotedValLoop bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (let [(b (bytesGet bs idx))]
      (if (or (isWhitespaceByte b) (or (= b 62) (= b 47)))
        idx
        (scanUnquotedValLoop bs len (+ idx 1)))))

fn scanUnquotedVal bs: Bytes len: Int64 idx: Int64 -> Int64
  (let [(end (scanUnquotedValLoop bs len idx))]
    (if (= end idx) (+ idx 1) end))

fn findCharInString s: String ch: String idx: Int64 len: Int64 -> (Option Int64)
  (if (>= idx len)
    (none)
    (if (= (optionOr (stringSlice s idx (+ idx 1)) "") ch)
      (some idx)
      (findCharInString s ch (+ idx 1) len)))

fn parsePositiveIntLoop bs: Bytes idx: Int64 end: Int64 acc: Int64 -> Int64
  (if (>= idx end)
    acc
    (let [(b (bytesGet bs idx))]
      (if (and (>= b 48) (<= b 57))
        (parsePositiveIntLoop bs (+ idx 1) end (+ (* acc 10) (- b 48)))
        acc)))

fn parsePositiveInt s: String -> Int64
  (let [(bs (stringToBytes s))]
    (parsePositiveIntLoop bs 0 (bytesLength bs) 0))

fn parseAttrNodeKind k: String start: Int64 end: Int64 -> (Option XmlAttr)
  (if (not (stringStartsWith? k "attr:"))
    (none)
    (let [(c1 4)
          (lenK (stringLength k))
          (c2Opt (findCharInString k ":" 5 lenK))]
      (mt c2Opt
        ((none) (none))
        ((some c2)
         (let [(nameLen (optionOr (stringSlice k 5 c2) ""))
               (n (parsePositiveInt nameLen))
               (nStart (+ c2 1))
               (nEnd (+ nStart n))
               (vStart (+ nEnd 1))]
           (if (or (> nEnd lenK) (> vStart lenK))
             (none)
             (let [(nm (optionOr (stringSlice k nStart nEnd) ""))
                   (val (optionOr (stringSlice k vStart lenK) ""))]
               (some (XmlAttr :name nm :value val :start start :end end)))))))))

fn parseAttributesLoop bs: Bytes len: Int64 idx: Int64 textOpt: (Option String)
                            tokAcc: (List tr/TreeElement)
                            attrAcc: (List XmlAttr)
                            hasErr: Bool -> (Pair (List tr/TreeElement) (Pair (List XmlAttr) (Pair Int64 Bool)))
  (let [(wsEnd (scanWhitespace bs len idx))
        (tokAcc1 (if (> wsEnd idx)
                   (cons (tr/elemToken (tr/makeToken "whitespace" idx wsEnd)) tokAcc)
                   tokAcc))]
    (if (>= wsEnd len)
      (pair (listReverse tokAcc1) (pair (listReverse attrAcc) (pair wsEnd true)))
      (let [(b (bytesGet bs wsEnd))]
        (if (= b 62)
          (pair (listReverse tokAcc1) (pair (listReverse attrAcc) (pair wsEnd hasErr)))
          (if (and (= b 47) (and (< (+ wsEnd 1) len) (= (bytesGet bs (+ wsEnd 1)) 62)))
            (pair (listReverse tokAcc1) (pair (listReverse attrAcc) (pair wsEnd hasErr)))
            (let [(nameStart wsEnd)
                  (nameEnd (scanName bs len nameStart))]
              (if (= nameEnd nameStart)
                (let [(errTok (tr/makeToken "error" nameStart (+ nameStart 1)))]
                  (parseAttributesLoop bs len (+ nameStart 1) textOpt (cons (tr/elemToken errTok) tokAcc1) attrAcc true))
                (let [(attrName (sliceString bs nameStart nameEnd textOpt))
                      (dup? (attrListHasName attrAcc attrName))
                      (nameTok (tr/makeToken "attrName" nameStart nameEnd))
                      (afterName (scanWhitespace bs len nameEnd))]
                  (if (or (>= afterName len) (!= (bytesGet bs afterName) 61))
                    (let [(errTok (tr/makeToken "error" nameStart afterName))]
                      (parseAttributesLoop bs len afterName textOpt (cons (tr/elemToken errTok) tokAcc1) attrAcc true))
                    (let [(eqTok (tr/makeToken "equals" afterName (+ afterName 1)))
                          (afterEq (scanWhitespace bs len (+ afterName 1)))]
                      (if (>= afterEq len)
                        (let [(errTok (tr/makeToken "error" nameStart len))]
                          (pair (listReverse (cons (tr/elemToken errTok) tokAcc1)) (pair (listReverse attrAcc) (pair len true))))
                        (let [(q (bytesGet bs afterEq))]
                          (if (and (!= q 34) (!= q 39))
                            (let [(valEnd (scanUnquotedVal bs len afterEq))
                                  (errTok (tr/makeToken "error" nameStart valEnd))]
                              (parseAttributesLoop bs len valEnd textOpt (cons (tr/elemToken errTok) tokAcc1) attrAcc true))
                            (mt (scanAttrValLoop bs len (+ afterEq 1) q false)
                              ((none)
                               (let [(errTok (tr/makeToken "error" nameStart len))]
                                 (pair (listReverse (cons (tr/elemToken errTok) tokAcc1)) (pair (listReverse attrAcc) (pair len true)))))
                              ((some p)
                               (let [(closeQ (pairFirst p))
                                     (hasLt (pairSecond p))
                                     (valEnd (+ closeQ 1))
                                     (rawVal (sliceString bs (+ afterEq 1) closeQ textOpt))
                                     (attrErr (or dup? hasLt))
                                     (valTok (if attrErr
                                               (tr/makeToken "error" afterEq valEnd)
                                               (tr/makeToken "attrValue" afterEq valEnd)))
                                     (cName (list (tr/elemToken nameTok)))
                                     (cWs1 (if (> afterName nameEnd)
                                             (cons (tr/elemToken (tr/makeToken "whitespace" nameEnd afterName)) cName)
                                             cName))
                                     (cEq (cons (tr/elemToken eqTok) cWs1))
                                     (cWs2 (if (> afterEq (+ afterName 1))
                                             (cons (tr/elemToken (tr/makeToken "whitespace" (+ afterName 1) afterEq)) cEq)
                                             cEq))
                                     (cVal (listReverse (cons (tr/elemToken valTok) cWs2)))
                                     (kStr (str "attr:" (stringFromInt64 (stringLength attrName)) ":" attrName ":" rawVal))
                                     (attrNode (if attrErr
                                                 (tr/makeErrorNode nameStart valEnd cVal)
                                                 (tr/makeNode kStr nameStart valEnd cVal)))
                                     (attrElem (XmlAttr :name attrName :value rawVal :start nameStart :end valEnd))
                                     (tokAcc2 (cons (tr/elemNode attrNode) tokAcc1))]
                                 (parseAttributesLoop bs len valEnd textOpt tokAcc2 (cons attrElem attrAcc) (or hasErr attrErr))))))))))))))))))

fn parseTag bs: Bytes len: Int64 start: Int64 textOpt: (Option String) -> TagParseResult
  (if (and (< (+ start 1) len) (= (bytesGet bs (+ start 1)) 47))
    (let [(nameStart (+ start 2))
          (nameEnd (scanName bs len nameStart))
          (tagName (sliceString bs nameStart nameEnd textOpt))
          (wsEnd (scanWhitespace bs len nameEnd))]
      (if (and (> nameEnd nameStart) (and (< wsEnd len) (= (bytesGet bs wsEnd) 62)))
        (let [(openTok (tr/makeToken "endTagOpen" start nameEnd))
              (toks (list (tr/elemToken openTok)))
              (toks1 (if (> wsEnd nameEnd)
                       (cons (tr/elemToken (tr/makeToken "whitespace" nameEnd wsEnd)) toks)
                       toks))
              (closeTok (tr/makeToken "tagClose" wsEnd (+ wsEnd 1)))
              (allToks (listReverse (cons (tr/elemToken closeTok) toks1)))
              (node (tr/makeNode (str "endTag:" tagName) start (+ wsEnd 1) allToks))]
          (TagParseResult :kind "endTag" :tag tagName :node node :attrs (list) :endIdx (+ wsEnd 1) :error? false))
        (let [(closeOpt (scanUntilSubLoop bs len start (stringToBytes ">") 1))
              (endPos (mt closeOpt ((some c) (+ c 1)) ((none) len)))
              (errTok (tr/makeToken "error" start endPos))
              (node (tr/makeErrorNode start endPos (list (tr/elemToken errTok))))]
          (TagParseResult :kind "endTag" :tag tagName :node node :attrs (list) :endIdx endPos :error? true))))
    (let [(nameStart (+ start 1))
          (nameEnd (scanName bs len nameStart))
          (tagName (sliceString bs nameStart nameEnd textOpt))]
      (if (<= nameEnd nameStart)
        (let [(closeOpt (scanUntilSubLoop bs len start (stringToBytes ">") 1))
              (endPos (mt closeOpt ((some c) (+ c 1)) ((none) len)))
              (errTok (tr/makeToken "error" start endPos))
              (node (tr/makeErrorNode start endPos (list (tr/elemToken errTok))))]
          (TagParseResult :kind "startTag" :tag "" :node node :attrs (list) :endIdx endPos :error? true))
        (let [(openTok (tr/makeToken "tagOpen" start nameEnd))
              (attrRes (parseAttributesLoop bs len nameEnd textOpt (list) (list) false))
              (attrToks (pairFirst attrRes))
              (attrs (pairFirst (pairSecond attrRes)))
              (afterAttrs (pairFirst (pairSecond (pairSecond attrRes))))
              (attrErr? (pairSecond (pairSecond (pairSecond attrRes))))
              (allLeadingToks (cons (tr/elemToken openTok) attrToks))]
          (if (>= afterAttrs len)
            (let [(node (tr/makeErrorNode start len allLeadingToks))]
              (TagParseResult :kind "startTag" :tag tagName :node node :attrs attrs :endIdx len :error? true))
            (let [(b (bytesGet bs afterAttrs))]
              (if (and (= b 47) (and (< (+ afterAttrs 1) len) (= (bytesGet bs (+ afterAttrs 1)) 62)))
                (let [(closeTok (tr/makeToken "emptyTagClose" afterAttrs (+ afterAttrs 2)))
                      (allToks (listAppend allLeadingToks (list (tr/elemToken closeTok))))
                      (node (if attrErr?
                              (tr/makeErrorNode start (+ afterAttrs 2) allToks)
                              (tr/makeNode (str "emptyTag:" tagName) start (+ afterAttrs 2) allToks)))]
                  (TagParseResult :kind "emptyTag" :tag tagName :node node :attrs attrs :endIdx (+ afterAttrs 2) :error? attrErr?))
                (if (= b 62)
                  (let [(closeTok (tr/makeToken "tagClose" afterAttrs (+ afterAttrs 1)))
                        (allToks (listAppend allLeadingToks (list (tr/elemToken closeTok))))
                        (node (if attrErr?
                                (tr/makeErrorNode start (+ afterAttrs 1) allToks)
                                (tr/makeNode (str "startTag:" tagName) start (+ afterAttrs 1) allToks)))]
                    (TagParseResult :kind "startTag" :tag tagName :node node :attrs attrs :endIdx (+ afterAttrs 1) :error? attrErr?))
                  (let [(closeOpt (scanUntilSubLoop bs len afterAttrs (stringToBytes ">") 1))
                        (endPos (mt closeOpt ((some c) (+ c 1)) ((none) len)))
                        (errTok (tr/makeToken "error" afterAttrs endPos))
                        (allToks (listAppend allLeadingToks (list (tr/elemToken errTok))))
                        (node (tr/makeErrorNode start endPos allToks))]
                    (TagParseResult :kind "startTag" :tag tagName :node node :attrs attrs :endIdx endPos :error? true))))))))))

fn parseComment bs: Bytes len: Int64 start: Int64 -> (Pair tr/Node Int64)
  (let [(closeOpt (scanUntilSubLoop bs len (+ start 4) (stringToBytes "-->") 3))]
    (mt closeOpt
      ((none)
       (let [(errTok (tr/makeToken "error" start len))
             (node (tr/makeErrorNode start len (list (tr/elemToken errTok))))]
         (pair node len)))
      ((some cIdx)
       (let [(endIdx (+ cIdx 3))
             (contentEnd cIdx)
             (hasDblHyphen (commentContainsDoubleHyphen bs (+ start 4) contentEnd))
             (endsTripleHyphen (and (> cIdx 0) (= (bytesGet bs (- cIdx 1)) 45)))
             (badComment (or hasDblHyphen endsTripleHyphen))]
         (if badComment
           (let [(errTok (tr/makeToken "error" start endIdx))
                 (node (tr/makeErrorNode start endIdx (list (tr/elemToken errTok))))]
             (pair node endIdx))
           (let [(tok (tr/makeToken "comment" start endIdx))
                 (node (tr/makeNode "comment" start endIdx (list (tr/elemToken tok))))]
              (pair node endIdx)))))))

fn parseCData bs: Bytes len: Int64 start: Int64 -> (Pair tr/Node Int64)
  (let [(closeOpt (scanUntilSubLoop bs len (+ start 9) (stringToBytes "]]>") 3))]
    (mt closeOpt
      ((none)
       (let [(errTok (tr/makeToken "error" start len))
             (node (tr/makeErrorNode start len (list (tr/elemToken errTok))))]
         (pair node len)))
      ((some cIdx)
       (let [(endIdx (+ cIdx 3))
             (tok (tr/makeToken "cdata" start endIdx))
             (node (tr/makeNode "cdata" start endIdx (list (tr/elemToken tok))))]
         (pair node endIdx)))))

fn parseDoctype bs: Bytes len: Int64 start: Int64 -> (Pair tr/Node Int64)
  (mt (scanDoctypeLoop bs len (+ start 9) false)
    ((none)
     (let [(errTok (tr/makeToken "error" start len))
           (node (tr/makeErrorNode start len (list (tr/elemToken errTok))))]
       (pair node len)))
    ((some endIdx)
     (let [(tok (tr/makeToken "doctype" start endIdx))
           (node (tr/makeNode "doctype" start endIdx (list (tr/elemToken tok))))]
        (pair node endIdx))))

fn parsePI bs: Bytes len: Int64 start: Int64 isStart: Bool textOpt: (Option String) -> (Pair tr/Node Int64)
  (let [(closeOpt (scanUntilSubLoop bs len (+ start 2) (stringToBytes "?>") 2))]
    (mt closeOpt
      ((none)
       (let [(errTok (tr/makeToken "error" start len))
             (node (tr/makeErrorNode start len (list (tr/elemToken errTok))))]
         (pair node len)))
      ((some cIdx)
       (let [(endIdx (+ cIdx 2))
             (targetStart (+ start 2))
             (targetEnd (scanName bs len targetStart))
             (target (sliceString bs targetStart targetEnd textOpt))
             (lowTarget (stringLower target))
             (isXmlDecl (= target "xml"))
             (isTargetXml (= lowTarget "xml"))
             (hasVersion (some? (scanUntilSubLoop bs endIdx start (stringToBytes "version") 7)))]
         (if isXmlDecl
           (if (and isStart hasVersion)
             (let [(tok (tr/makeToken "prolog" start endIdx))
                   (node (tr/makeNode "prolog" start endIdx (list (tr/elemToken tok))))]
               (pair node endIdx))
             (let [(errTok (tr/makeToken "error" start endIdx))
                   (node (tr/makeErrorNode start endIdx (list (tr/elemToken errTok))))]
               (pair node endIdx)))
           (if isTargetXml
             (let [(errTok (tr/makeToken "error" start endIdx))
                   (node (tr/makeErrorNode start endIdx (list (tr/elemToken errTok))))]
               (pair node endIdx))
             (let [(tok (tr/makeToken "pi" start endIdx))
                   (node (tr/makeNode "pi" start endIdx (list (tr/elemToken tok))))]
               (pair node endIdx))))))))

fn addChildToOpenElem top: OpenElem elem: tr/TreeElement -> OpenElem
  (with top :children (cons elem top.children))

fn addTreeElem openStack: (List OpenElem) topElems: (List tr/TreeElement) elem: tr/TreeElement -> (Pair (List OpenElem) (List tr/TreeElement))
  (mt (listHead openStack)
    ((none) (pair openStack (cons elem topElems)))
    ((some top)
     (let [(updatedTop (addChildToOpenElem top elem))
           (newStack (cons updatedTop (optionOr (listTail openStack) (list))))]
       (pair newStack topElems))))

fn unwindStackAtEof stack: (List OpenElem) len: Int64 -> (Option tr/TreeElement)
  (mt (listHead stack)
    ((none) (none))
    ((some top)
     (let [(tail (optionOr (listTail stack) (list)))
           (children (listReverse top.children))
           (errNode (tr/makeErrorNode top.start len children))]
       (mt (listHead tail)
         ((none) (some (tr/elemNode errNode)))
         ((some parent)
          (let [(updatedParent (addChildToOpenElem parent (tr/elemNode errNode)))
                (newTail (cons updatedParent (optionOr (listTail tail) (list))))]
            (unwindStackAtEof newTail len)))))))

fn parseXmlLoop bs: Bytes len: Int64 idx: Int64 textOpt: (Option String)
                openStack: (List OpenElem)
                topElems: (List tr/TreeElement)
                rootSeen: Bool -> tr/Node
  (if (>= idx len)
    (let [(unwoundOpt (unwindStackAtEof openStack len))
          (allElems (mt unwoundOpt
                      ((none) (listReverse topElems))
                      ((some elem) (listReverse (cons elem topElems)))))]
      (tr/makeNode "document" 0 len allElems))
    (let [(b (bytesGet bs idx))]
      (cond
        ((!= b 60)
         (let [(nextLt (scanUntilSubLoop bs len idx (stringToBytes "<") 1))
               (textEnd (mt nextLt ((some n) n) ((none) len)))
               (isWsOnly (not (textHasNonWhitespace bs idx textEnd)))
               (hasBadCData (textContainsCDataEnd bs idx textEnd))
               (hasBadAmp (textHasInvalidAmpersand bs idx textEnd len))
               (inRoot (not (listEmpty? openStack)))
               (isErr (or hasBadCData (or hasBadAmp (and (not inRoot) (not isWsOnly)))))
               (kind (if isWsOnly "whitespace" (if isErr "error" "text")))
               (tok (tr/makeToken kind idx textEnd))
               (treeElem (if isErr (tr/elemNode (tr/makeErrorNode idx textEnd (list (tr/elemToken tok)))) (tr/elemToken tok)))
               (res (addTreeElem openStack topElems treeElem))]
           (parseXmlLoop bs len textEnd textOpt (pairFirst res) (pairSecond res) rootSeen)))
        ((and (< (+ idx 3) len) (and (= (bytesGet bs (+ idx 1)) 33) (and (= (bytesGet bs (+ idx 2)) 45) (= (bytesGet bs (+ idx 3)) 45))))
         (let [(cRes (parseComment bs len idx))
               (cNode (pairFirst cRes))
               (nextIdx (pairSecond cRes))
               (res (addTreeElem openStack topElems (tr/elemNode cNode)))]
           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))
        ((and (< (+ idx 8) len) (bytesMatchSub bs len idx (stringToBytes "<![CDATA[") 9 0))
         (let [(cdRes (parseCData bs len idx))
               (cdNode (pairFirst cdRes))
               (nextIdx (pairSecond cdRes))
               (res (addTreeElem openStack topElems (tr/elemNode cdNode)))]
           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))
        ((and (< (+ idx 8) len) (bytesMatchSub bs len idx (stringToBytes "<!DOCTYPE") 9 0))
         (let [(dtRes (parseDoctype bs len idx))
               (dtNode (pairFirst dtRes))
               (nextIdx (pairSecond dtRes))
               (res (addTreeElem openStack topElems (tr/elemNode dtNode)))]
           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))
        ((and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 63))
         (let [(isDocStart (= idx 0))
               (piRes (parsePI bs len idx isDocStart textOpt))
               (piNode (pairFirst piRes))
               (nextIdx (pairSecond piRes))
               (res (addTreeElem openStack topElems (tr/elemNode piNode)))]
           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))
        (else
         (let [(tagRes (parseTag bs len idx textOpt))
               (tKind tagRes.kind)
               (tagName tagRes.tag)
               (tNode tagRes.node)
               (tAttrs tagRes.attrs)
               (nextIdx tagRes.endIdx)
               (tErr? tagRes.error?)]
           (cond
             ((= tKind "startTag")
              (let [(newTop (OpenElem :tag tagName :start idx :children (list (tr/elemNode tNode))))
                    (newStack (cons newTop openStack))]
                (parseXmlLoop bs len nextIdx textOpt newStack topElems rootSeen)))
             ((= tKind "emptyTag")
              (let [(elemNode (if tErr?
                                (tr/makeErrorNode idx nextIdx (list (tr/elemNode tNode)))
                                (tr/makeNode (str "element:" tagName) idx nextIdx (list (tr/elemNode tNode)))))
                    (inRoot (not (listEmpty? openStack)))]
                (if inRoot
                  (let [(res (addTreeElem openStack topElems (tr/elemNode elemNode)))]
                    (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen))
                  (let [(multiRoot rootSeen)
                        (finalElemNode (if multiRoot
                                         (tr/makeErrorNode idx nextIdx (list (tr/elemNode elemNode)))
                                         elemNode))
                        (res (addTreeElem openStack topElems (tr/elemNode finalElemNode)))]
                    (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) true)))))
             ((= tKind "endTag")
              (mt (listHead openStack)
                ((none)
                 (let [(errNode (tr/makeErrorNode idx nextIdx (list (tr/elemNode tNode))))
                       (res (addTreeElem openStack topElems (tr/elemNode errNode)))]
                   (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))
                ((some top)
                 (let [(match? (and (not tErr?) (= top.tag tagName)))
                       (stackTail (optionOr (listTail openStack) (list)))]
                   (if match?
                     (let [(elemChildren (listReverse (cons (tr/elemNode tNode) top.children)))
                           (elemNode (tr/makeNode (str "element:" tagName) top.start nextIdx elemChildren))
                           (nowRootEmpty (listEmpty? stackTail))]
                       (if nowRootEmpty
                         (let [(multiRoot rootSeen)
                               (finalElemNode (if multiRoot
                                                (tr/makeErrorNode top.start nextIdx (list (tr/elemNode elemNode)))
                                                elemNode))
                               (res (addTreeElem stackTail topElems (tr/elemNode finalElemNode)))]
                           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) true))
                         (let [(res (addTreeElem stackTail topElems (tr/elemNode elemNode)))]
                           (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen))))
                     (let [(elemChildren (listReverse (cons (tr/elemNode tNode) top.children)))
                           (errElemNode (tr/makeErrorNode top.start nextIdx elemChildren))
                           (res (addTreeElem stackTail topElems (tr/elemNode errElemNode)))]
                       (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))))))
             (else
              (let [(errNode (tr/makeErrorNode idx nextIdx (list (tr/elemNode tNode))))
                    (res (addTreeElem openStack topElems (tr/elemNode errNode)))]
                (parseXmlLoop bs len nextIdx textOpt (pairFirst res) (pairSecond res) rootSeen)))))))))

fn parseXml text: String -> tr/Node
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))]
    (parseXmlLoop bs len 0 (some text) (list) (list) false))

fn parseXmlBytes bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))]
    (parseXmlLoop bs len 0 (none) (list) (list) false))

fn firstErrorOffset node: tr/Node -> (Option Int64)
  (if (tr/isErrorNode node)
    (some (tr/nodeStart node))
    (firstErrorElementList (tr/nodeChildren node)))

fn firstErrorElementList elems: (List tr/TreeElement) -> (Option Int64)
  (mt (listHead elems)
    ((none) (none))
    ((some elem)
     (let [(tail (optionOr (listTail elems) (list)))]
       (mt elem
         ((elemToken tok)
          (if (tr/isErrorToken tok)
            (some (tr/tokenStart tok))
            (firstErrorElementList tail)))
         ((elemNode n)
          (mt (firstErrorOffset n)
            ((some off) (some off))
            ((none) (firstErrorElementList tail))))))))

fn parse text: String -> (Result tr/Node String)
  (let [(root (parseXml text))]
    (if (isWellFormed root)
      (ok root)
      (let [(off (optionOr (firstErrorOffset root) 0))]
        (err (str "not well-formed at offset " (stringFromInt64 off))))))

fn parseBytes bs: Bytes -> (Result tr/Node String)
  (let [(root (parseXmlBytes bs))]
    (if (isWellFormed root)
      (ok root)
      (let [(off (optionOr (firstErrorOffset root) 0))]
        (err (str "not well-formed at offset " (stringFromInt64 off))))))

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tr/nodeLeaves (parseXmlBytes bs))

fn tokenize text: String -> (List tr/Token)
  (tr/nodeLeaves (parseXml text))

fn isWellFormed root: tr/Node -> Bool
  (not (sym/hasErrorNode root))

fn findFirstElement elems: (List tr/TreeElement) -> (Option tr/Node)
  (mt (listHead elems)
    ((none) (none))
    ((some elem)
     (mt elem
       ((elemToken _) (findFirstElement (optionOr (listTail elems) (list))))
       ((elemNode n)
        (if (stringStartsWith? (tr/nodeKind n) "element:")
          (some n)
          (findFirstElement (optionOr (listTail elems) (list))))))))

fn documentRootElement root: tr/Node -> (Option tr/Node)
  (findFirstElement (tr/nodeChildren root))

fn elementName node: tr/Node -> String
  (let [(k (tr/nodeKind node))]
    (if (stringStartsWith? k "element:")
      (optionOr (stringSlice k 8 (stringLength k)) "")
      (if (stringStartsWith? k "startTag:")
        (optionOr (stringSlice k 9 (stringLength k)) "")
        (if (stringStartsWith? k "emptyTag:")
          (optionOr (stringSlice k 9 (stringLength k)) "")
          ""))))

fn filterElementChildren elems: (List tr/TreeElement) acc: (List tr/Node) -> (List tr/Node)
  (mt (listHead elems)
    ((none) (listReverse acc))
    ((some elem)
     (mt elem
       ((elemToken _) (filterElementChildren (optionOr (listTail elems) (list)) acc))
       ((elemNode n)
        (if (stringStartsWith? (tr/nodeKind n) "element:")
          (filterElementChildren (optionOr (listTail elems) (list)) (cons n acc))
          (filterElementChildren (optionOr (listTail elems) (list)) acc))))))

fn elementChildren node: tr/Node -> (List tr/Node)
  (filterElementChildren (tr/nodeChildren node) (list))

fn findTagNodeInElem elems: (List tr/TreeElement) -> (Option tr/Node)
  (mt (listHead elems)
    ((none) (none))
    ((some elem)
     (mt elem
       ((elemToken _) (findTagNodeInElem (optionOr (listTail elems) (list))))
       ((elemNode n)
        (let [(k (tr/nodeKind n))]
          (if (or (stringStartsWith? k "startTag:") (stringStartsWith? k "emptyTag:"))
            (some n)
            (findTagNodeInElem (optionOr (listTail elems) (list)))))))))

fn collectAttrsFromElements elems: (List tr/TreeElement) acc: (List XmlAttr) -> (List XmlAttr)
  (mt (listHead elems)
    ((none) (listReverse acc))
    ((some elem)
     (mt elem
       ((elemToken _) (collectAttrsFromElements (optionOr (listTail elems) (list)) acc))
       ((elemNode n)
        (mt (parseAttrNodeKind (tr/nodeKind n) (tr/nodeStart n) (tr/nodeEnd n))
          ((none) (collectAttrsFromElements (optionOr (listTail elems) (list)) acc))
          ((some a) (collectAttrsFromElements (optionOr (listTail elems) (list)) (cons a acc))))))))

fn elementAttributes node: tr/Node -> (List XmlAttr)
  (mt (findTagNodeInElem (tr/nodeChildren node))
    ((none) (list))
    ((some tagNode)
     (collectAttrsFromElements (tr/nodeChildren tagNode) (list))))

fn findNamedAttr attrs: (List XmlAttr) name: String -> (Option String)
  (mt (listHead attrs)
    ((none) (none))
    ((some a)
     (if (= a.name name)
       (some a.value)
       (findNamedAttr (optionOr (listTail attrs) (list)) name))))

fn findIdAttr attrs: (List XmlAttr) -> (Option String)
  (mt (listHead attrs)
    ((none) (none))
    ((some a)
     (if (or (= a.name "id") (= a.name "xml:id"))
       (some a.value)
       (findIdAttr (optionOr (listTail attrs) (list))))))

fn attributeValue node: tr/Node name: String -> (Option String)
  (findNamedAttr (elementAttributes node) name)

fn elementId node: tr/Node -> (Option String)
  (findIdAttr (elementAttributes node))

fn collectSymbolsLoop node: tr/Node parentTag: String depth: Int64 acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (let [(k (tr/nodeKind node))]
    (if (not (stringStartsWith? k "element:"))
      acc
      (let [(tag (elementName node))
            (start (tr/nodeStart node))
            (end (tr/nodeEnd node))
            (elemSym (sym/makeScopedSymbolDef tag "element" start end parentTag depth))
            (acc1 (cons elemSym acc))
            (acc2 (mt (elementId node)
                    ((none) acc1)
                    ((some idVal)
                     (cons (sym/makeScopedSymbolDef idVal "id" start end tag (+ depth 1)) acc1))))
            (children (elementChildren node))]
        (fold (fn [(currAcc (List sym/SymbolDef)) (child tr/Node)] -> (List sym/SymbolDef)
                (collectSymbolsLoop child tag (+ depth 1) currAcc))
              acc2
              children))))

fn extractSymbols root: tr/Node -> (List sym/SymbolDef)
  (mt (documentRootElement root)
    ((none) (list))
    ((some rootElem)
     (listReverse (collectSymbolsLoop rootElem "" 0 (list)))))

fn extractSymbolsFromText text: String -> (List sym/SymbolDef)
  (extractSymbols (parseXml text))
