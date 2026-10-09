(module asl-syntax/jsx
  :x [parse
      parseJsx
      parseJsxExpr
      parseJsxText
      parseJsxTokens
      parseJsxElement
      parseJsxFragment
      parseJsxElementFrom
      parseJsxFragmentFrom
      parseJsxElementWithTagParser
      parseJsxElementOrFragWithTagParser
      parseJsxTagName
      skipTrivia
      findChildNodes
      scanExprBraceEnd
      jsxToSExpr
      isJsxNode
      jsxNodeKind]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)])

(schema ParseResult
  (:f node tr/Node)
  (:f restOffset Int64))

fn isWsByte b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))

fn isNlByte b: Int64 -> Bool
  (or (= b 10) (= b 13))

fn isIdentStartByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
  (or (and (>= b 97) (<= b 122))
  (or (= b 36)
  (or (= b 95)
      (>= b 128)))))

fn isIdentPartByte b: Int64 -> Bool
  (or (isIdentStartByte b)
  (or (and (>= b 48) (<= b 57))
      (= b 45)))

fn scanWsEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 32) (= b 9))
        (scanWsEnd bs len (+ i 1))
        i)))

fn scanNlEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (and (= (bytesGet bs i) 13) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 10)))
      (+ i 2)
      (+ i 1)))

fn scanLineCommentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isNlByte (bytesGet bs i))
      i
      (scanLineCommentEnd bs len (+ i 1))))

fn scanBlockCommentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (and (= (bytesGet bs i) 42) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 47)))
      (+ i 2)
      (scanBlockCommentEnd bs len (+ i 1))))

fn skipTriviaLoop bs: Bytes len: Int64 i: Int64 acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) Int64)
  (if (>= i len)
    (pair (listReverse acc) i)
    (let [(b (bytesGet bs i))]
      (if (or (= b 32) (= b 9))
        (let [(end (scanWsEnd bs len i))
              (tok (tr/makeToken "whitespace" i end))]
          (skipTriviaLoop bs len end (cons (tr/elemToken tok) acc)))
        (if (isNlByte b)
          (let [(end (scanNlEnd bs len i))
                (tok (tr/makeToken "newline" i end))]
            (skipTriviaLoop bs len end (cons (tr/elemToken tok) acc)))
          (if (and (= b 47) (< (+ i 1) len))
            (let [(b2 (bytesGet bs (+ i 1)))]
              (if (= b2 47)
                (let [(end (scanLineCommentEnd bs len (+ i 2)))
                      (tok (tr/makeToken "comment" i end))]
                  (skipTriviaLoop bs len end (cons (tr/elemToken tok) acc)))
                (if (= b2 42)
                  (let [(end (scanBlockCommentEnd bs len (+ i 2)))
                        (tok (tr/makeToken "comment" i end))]
                    (skipTriviaLoop bs len end (cons (tr/elemToken tok) acc)))
                  (pair (listReverse acc) i))))
            (pair (listReverse acc) i))))))

fn skipTrivia bs: Bytes len: Int64 i: Int64 -> (Pair (List tr/TreeElement) Int64)
  (skipTriviaLoop bs len i (list))

fn scanIdentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isIdentPartByte (bytesGet bs i))
      (scanIdentEnd bs len (+ i 1))
      i))

fn scanJsxTextEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 60) (= b 123))
        i
        (scanJsxTextEnd bs len (+ i 1)))))

fn scanStringEnd bs: Bytes len: Int64 i: Int64 quote: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (= b quote)
        (+ i 1)
        (if (and (= b 92) (< (+ i 1) len))
          (scanStringEnd bs len (+ i 2) quote)
          (scanStringEnd bs len (+ i 1) quote)))))

fn parseMemberTagLoop bs: Bytes len: Int64 cur: Int64 left: tr/Node -> (Pair tr/Node Int64)
  (if (and (< cur len) (= (bytesGet bs cur) 46))
    (let [(dotTok (tr/makeToken "dot" cur (+ cur 1)))
          (nextStart (+ cur 1))
          (nextEnd (scanIdentEnd bs len nextStart))
          (nextTok (tr/makeToken "jsxIdent" nextStart nextEnd))
          (nextIdent (tr/makeNode "jsxIdentifier" nextStart nextEnd (list (tr/elemToken nextTok))))
          (kids (list (tr/elemNode left) (tr/elemToken dotTok) (tr/elemNode nextIdent)))
          (memNode (tr/makeNode "jsxMemberExpr" (tr/nodeStart left) nextEnd kids))]
      (parseMemberTagLoop bs len nextEnd memNode))
    (pair left cur))

fn parseJsxTagName bs: Bytes len: Int64 i: Int64 -> (Pair tr/Node Int64)
  (if (or (>= i len) (not (isIdentStartByte (bytesGet bs i))))
    (pair (tr/makeErrorNode i i (list)) i)
    (let [(end1 (scanIdentEnd bs len (+ i 1)))
          (tok1 (tr/makeToken "jsxIdent" i end1))
          (node1 (tr/makeNode "jsxIdentifier" i end1 (list (tr/elemToken tok1))))]
    (if (and (< end1 len) (= (bytesGet bs end1) 58))
      (let [(colonTok (tr/makeToken "colon" end1 (+ end1 1)))
            (nextStart (+ end1 1))
            (nextEnd (scanIdentEnd bs len nextStart))
            (nextTok (tr/makeToken "jsxIdent" nextStart nextEnd))
            (nextIdent (tr/makeNode "jsxIdentifier" nextStart nextEnd (list (tr/elemToken nextTok))))
            (kids (list (tr/elemNode node1) (tr/elemToken colonTok) (tr/elemNode nextIdent)))
            (nsNode (tr/makeNode "jsxNamespacedName" i nextEnd kids))]
        (pair nsNode nextEnd))
      (if (and (< end1 len) (= (bytesGet bs end1) 46))
        (parseMemberTagLoop bs len end1 node1)
        (pair node1 end1)))))

fn parseJsxAttrName bs: Bytes len: Int64 i: Int64 -> (Pair tr/Node Int64)
  (if (or (>= i len) (not (isIdentStartByte (bytesGet bs i))))
    (pair (tr/makeErrorNode i i (list)) i)
    (let [(end1 (scanIdentEnd bs len (+ i 1)))
          (tok1 (tr/makeToken "jsxIdent" i end1))
          (node1 (tr/makeNode "jsxIdentifier" i end1 (list (tr/elemToken tok1))))]
    (if (and (< end1 len) (= (bytesGet bs end1) 58))
      (let [(colonTok (tr/makeToken "colon" end1 (+ end1 1)))
            (nextStart (+ end1 1))
            (nextEnd (scanIdentEnd bs len nextStart))
            (nextTok (tr/makeToken "jsxIdent" nextStart nextEnd))
            (nextIdent (tr/makeNode "jsxIdentifier" nextStart nextEnd (list (tr/elemToken nextTok))))
            (kids (list (tr/elemNode node1) (tr/elemToken colonTok) (tr/elemNode nextIdent)))
            (nsNode (tr/makeNode "jsxNamespacedName" i nextEnd kids))]
        (pair nsNode nextEnd))
      (pair node1 end1))))

fn defaultJsxTagParser bs: Bytes len: Int64 i: Int64 text: String -> (Pair (Pair tr/Node (Option tr/Node)) Int64)
  (let [(baseRes (parseJsxTagName bs len i))]
    (pair (pair (pairFirst baseRes) (none)) (pairSecond baseRes)))

fn parseJsxElementOrFragWithTagParser text: String bs: Bytes len: Int64 i: Int64 tagParser: (Fn [Bytes Int64 Int64 String] -> (Pair (Pair tr/Node (Option tr/Node)) Int64)) -> (Result (Pair tr/Node Int64) String)
  (if (>= i len)
    (err (str "Unexpected EOF at offset " (stringFromInt64 i)))
    (if (!= (bytesGet bs i) 60)
      (err (str "Expected '<' at offset " (stringFromInt64 i)))
      (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 62))
        (parseJsxFragmentFrom text bs len i)
        (parseJsxElementWithTagParser text bs len i tagParser))))

fn parseJsxElementOrFrag text: String bs: Bytes len: Int64 i: Int64 -> (Result (Pair tr/Node Int64) String)
  (parseJsxElementOrFragWithTagParser text bs len i defaultJsxTagParser)

fn parseJsxExprFromOffset text: String bs: Bytes len: Int64 cur: Int64 -> (Pair tr/Node Int64)
  (let [(sp (skipTrivia bs len cur))
        (triv (pairFirst sp))
        (c (pairSecond sp))]
    (if (>= c len)
      (pair (tr/makeErrorNode cur cur triv) c)
      (let [(b (bytesGet bs c))]
        (if (= b 60)
          (let [(elemRes (parseJsxElementOrFrag text bs len c))]
            (mt elemRes
              ((ok resPair)
               (let [(elemNode (pairFirst resPair))
                     (nextCur (pairSecond resPair))]
                 (if (listEmpty? triv)
                   (pair elemNode nextCur)
                   (let [(kids (listAppend triv (list (tr/elemNode elemNode))))
                         (wNode (tr/makeNode "expression" cur nextCur kids))]
                     (pair wNode nextCur)))))
              ((err _)
               (let [(errTok (tr/makeToken "error" c (+ c 1)))
                     (errNode (tr/makeErrorNode cur (+ c 1) (listAppend triv (list (tr/elemToken errTok)))))]
                 (pair errNode (+ c 1))))))
          (parseJsxSubExpr text bs len cur)))))

fn scanExprBraceEnd bs: Bytes len: Int64 i: Int64 depth: Int64 -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (cond
        ((or (= b 34) (= b 39))
         (let [(end (scanStringEnd bs len (+ i 1) b))]
           (scanExprBraceEnd bs len end depth)))
        ((and (= b 47) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 47)))
         (let [(end (scanLineCommentEnd bs len (+ i 2)))]
           (scanExprBraceEnd bs len end depth)))
        ((and (= b 47) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 42)))
         (let [(end (scanBlockCommentEnd bs len (+ i 2)))]
           (scanExprBraceEnd bs len end depth)))
        ((= b 123)
         (scanExprBraceEnd bs len (+ i 1) (+ depth 1)))
        ((= b 125)
         (if (<= depth 1)
           i
           (scanExprBraceEnd bs len (+ i 1) (- depth 1))))
        (else
         (scanExprBraceEnd bs len (+ i 1) depth)))))

fn findNextLt bs: Bytes endOff: Int64 i: Int64 -> Int64
  (if (>= i endOff)
    endOff
    (if (= (bytesGet bs i) 60)
      i
      (findNextLt bs endOff (+ i 1))))

fn tokenizeJsxExprLoop text: String bs: Bytes len: Int64 cur: Int64 endOff: Int64 accToks: (List tr/Token) accMap: (List (Pair (Pair Int64 Int64) tr/Node)) -> (Pair (List tr/Token) (List (Pair (Pair Int64 Int64) tr/Node)))
  (if (>= cur endOff)
    (pair accToks accMap)
    (let [(nextLt (findNextLt bs endOff cur))]
      (if (>= nextLt endOff)
        (let [(slice (optionOr (stringSlice text cur endOff) ""))
              (subToks (lx/tokenize slice))
              (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
              (allToks (listAppend accToks shifted))]
          (pair allToks accMap))
        (let [(elemRes (parseJsxElementOrFrag text bs len nextLt))]
          (mt elemRes
            ((ok resPair)
             (let [(elemNode (pairFirst resPair))
                   (nextC (pairSecond resPair))]
               (if (<= nextC endOff)
                 (let [(beforeSlice (optionOr (stringSlice text cur nextLt) ""))
                       (subToks (lx/tokenize beforeSlice))
                       (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                       (identTok (tr/makeToken "ident" nextLt nextC))
                       (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                       (newMap (cons (pair (pair nextLt nextC) elemNode) accMap))]
                   (tokenizeJsxExprLoop text bs len nextC endOff allToks newMap))
                 (let [(beforeSlice (optionOr (stringSlice text cur (+ nextLt 1)) ""))
                       (subToks (lx/tokenize beforeSlice))
                       (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                       (allToks (listAppend accToks shifted))]
                   (tokenizeJsxExprLoop text bs len (+ nextLt 1) endOff allToks accMap)))))
            ((err _)
             (let [(beforeSlice (optionOr (stringSlice text cur (+ nextLt 1)) ""))
                   (subToks (lx/tokenize beforeSlice))
                   (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                   (allToks (listAppend accToks shifted))]
               (tokenizeJsxExprLoop text bs len (+ nextLt 1) endOff allToks accMap))))))))

fn lookupJsxNode start: Int64 end: Int64 entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> (Option tr/Node)
  (if (listEmpty? entries)
    (none)
    (let [(hd (optionOr (listHead entries) (pair (pair 0 0) (tr/makeNode "" 0 0 (list)))))
          (tl (optionOr (listTail entries) (list)))
          (span (pairFirst hd))
          (s (pairFirst span))
          (e (pairSecond span))]
      (if (and (= s start) (= e end))
        (some (pairSecond hd))
        (lookupJsxNode start end tl))))

fn substituteJsxInElement elem: tr/TreeElement entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> tr/TreeElement
  (mt elem
    ((tr/elemToken tok) elem)
    ((tr/elemNode node) (tr/elemNode (substituteJsxNodes node entries))))

fn substituteJsxNodes node: tr/Node entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> tr/Node
  (let [(s (tr/nodeStart node))
        (e (tr/nodeEnd node))
        (found (lookupJsxNode s e entries))]
    (mt found
      ((some jsxN) jsxN)
      ((none)
       (let [(kids (tr/nodeChildren node))
             (newKids (map (fn [(el tr/TreeElement)] -> tr/TreeElement (substituteJsxInElement el entries)) kids))]
         (tr/makeNode (tr/nodeKind node) s e newKids)))))

fn parseJsxSubExpr text: String bs: Bytes len: Int64 cur: Int64 -> (Pair tr/Node Int64)
  (let [(exprEnd (scanExprBraceEnd bs len cur 1))
        (exprSlice (optionOr (stringSlice text cur exprEnd) ""))]
    (if (stringContains? exprSlice "<")
      (parseJsxExprWithTokens cur text exprEnd)
      (let [(subToks (lx/tokenize exprSlice))
            (shiftedToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
            (parsedNode (cv/parseTokens shiftedToks text))]
        (pair parsedNode exprEnd))))

fn parseJsxExprWithTokens startOff: Int64 text: String endOff: Int64 -> (Pair tr/Node Int64)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (tokenizeJsxExprLoop text bs len startOff endOff (list) (list)))
        (newToks (pairFirst res))
        (jsxMap (pairSecond res))
        (parsedDoc (cv/parseTokens newToks text))
        (substituted (substituteJsxNodes parsedDoc jsxMap))]
    (pair substituted endOff))

fn parseJsxAttributesLoop bs: Bytes len: Int64 text: String cur: Int64 acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) Int64)
  (let [(sp (skipTrivia bs len cur))
        (triv (pairFirst sp))
        (c (pairSecond sp))]
    (if (>= c len)
      (pair (listReverse (listAppend (listReverse triv) acc)) c)
      (let [(b (bytesGet bs c))]
        (if (or (= b 62) (and (= b 47) (and (< (+ c 1) len) (= (bytesGet bs (+ c 1)) 62))))
          (pair (listReverse (listAppend (listReverse triv) acc)) c)
          (if (= b 123)
            (let [(lbTok (tr/makeToken "lbrace" c (+ c 1)))
                  (spIn (skipTrivia bs len (+ c 1)))
                  (inTriv (pairFirst spIn))
                  (cIn (pairSecond spIn))]
              (if (and (< (+ cIn 2) len) (and (= (bytesGet bs cIn) 46) (and (= (bytesGet bs (+ cIn 1)) 46) (= (bytesGet bs (+ cIn 2)) 46))))
                (let [(ellTok (tr/makeToken "ellipsis" cIn (+ cIn 3)))
                      (spAfterEll (skipTrivia bs len (+ cIn 3)))
                      (ellTriv (pairFirst spAfterEll))
                      (cExpr (pairSecond spAfterEll))
                      (exprRes (parseJsxExprFromOffset text bs len cExpr))
                      (exprNode (pairFirst exprRes))
                      (cAfterExpr (pairSecond exprRes))
                      (spRb (skipTrivia bs len cAfterExpr))
                      (rbTriv (pairFirst spRb))
                      (cRb (pairSecond spRb))
                      (rbTok (tr/makeToken "rbrace" cRb (+ cRb 1)))
                      (spreadKids (listAppend triv
                                    (cons (tr/elemToken lbTok)
                                      (listAppend inTriv
                                        (cons (tr/elemToken ellTok)
                                          (listAppend ellTriv
                                            (cons (tr/elemNode exprNode)
                                              (listAppend rbTriv (list (tr/elemToken rbTok))))))))))
                      (spreadNode (tr/makeNode "jsxSpreadAttribute" c (+ cRb 1) spreadKids))]
                  (parseJsxAttributesLoop bs len text (+ cRb 1) (cons (tr/elemNode spreadNode) acc)))
                (let [(exprRes (parseJsxExprFromOffset text bs len cIn))
                      (exprNode (pairFirst exprRes))
                      (cAfterExpr (pairSecond exprRes))
                      (spRb (skipTrivia bs len cAfterExpr))
                      (rbTriv (pairFirst spRb))
                      (cRb (pairSecond spRb))
                      (rbTok (tr/makeToken "rbrace" cRb (+ cRb 1)))
                      (containerKids (listAppend triv
                                       (cons (tr/elemToken lbTok)
                                         (listAppend inTriv
                                           (cons (tr/elemNode exprNode)
                                             (listAppend rbTriv (list (tr/elemToken rbTok))))))))
                      (containerNode (tr/makeNode "jsxExpressionContainer" c (+ cRb 1) containerKids))]
                  (parseJsxAttributesLoop bs len text (+ cRb 1) (cons (tr/elemNode containerNode) acc)))))
            (let [(nameRes (parseJsxAttrName bs len c))
                  (nameNode (pairFirst nameRes))
                  (cNameEnd (pairSecond nameRes))]
              (if (<= cNameEnd c)
                (pair (listReverse (listAppend (listReverse triv) acc)) c)
                (let [(spEq (skipTrivia bs len cNameEnd))
                      (eqTriv (pairFirst spEq))
                      (cEq (pairSecond spEq))]
                  (if (and (< cEq len) (= (bytesGet bs cEq) 61))
                    (let [(eqTok (tr/makeToken "assign" cEq (+ cEq 1)))
                          (spVal (skipTrivia bs len (+ cEq 1)))
                          (valTriv (pairFirst spVal))
                          (cVal (pairSecond spVal))]
                      (if (>= cVal len)
                        (let [(attrKids (listAppend triv (cons (tr/elemNode nameNode) (listAppend eqTriv (list (tr/elemToken eqTok))))))
                              (attrNode (tr/makeNode "jsxAttribute" c (+ cEq 1) attrKids))]
                          (parseJsxAttributesLoop bs len text (+ cEq 1) (cons (tr/elemNode attrNode) acc)))
                        (let [(valB (bytesGet bs cVal))]
                          (cond
                            ((or (= valB 34) (= valB 39))
                             (let [(strEnd (scanStringEnd bs len (+ cVal 1) valB))
                                   (strTok (tr/makeToken "string" cVal strEnd))
                                   (valNode (tr/makeNode "literal" cVal strEnd (list (tr/elemToken strTok))))
                                   (attrKids (listAppend triv
                                               (cons (tr/elemNode nameNode)
                                                 (listAppend eqTriv
                                                   (cons (tr/elemToken eqTok)
                                                     (listAppend valTriv (list (tr/elemNode valNode))))))))
                                   (attrNode (tr/makeNode "jsxAttribute" c strEnd attrKids))]
                               (parseJsxAttributesLoop bs len text strEnd (cons (tr/elemNode attrNode) acc))))
                            ((= valB 123)
                             (let [(lbTok (tr/makeToken "lbrace" cVal (+ cVal 1)))
                                   (spIn (skipTrivia bs len (+ cVal 1)))
                                   (inTriv (pairFirst spIn))
                                   (cIn (pairSecond spIn))]
                               (if (and (< cIn len) (= (bytesGet bs cIn) 125))
                                 (let [(emptyNode (tr/makeNode "jsxEmptyExpr" cIn cIn (list)))
                                       (rbTok (tr/makeToken "rbrace" cIn (+ cIn 1)))
                                       (containerKids (cons (tr/elemToken lbTok) (listAppend inTriv (cons (tr/elemNode emptyNode) (list (tr/elemToken rbTok))))))
                                       (containerNode (tr/makeNode "jsxExpressionContainer" cVal (+ cIn 1) containerKids))
                                       (attrKids (listAppend triv
                                                   (cons (tr/elemNode nameNode)
                                                     (listAppend eqTriv
                                                       (cons (tr/elemToken eqTok)
                                                         (listAppend valTriv (list (tr/elemNode containerNode))))))))
                                       (attrNode (tr/makeNode "jsxAttribute" c (+ cIn 1) attrKids))]
                                   (parseJsxAttributesLoop bs len text (+ cIn 1) (cons (tr/elemNode attrNode) acc)))
                                 (let [(exprRes (parseJsxExprFromOffset text bs len cIn))
                                       (exprNode (pairFirst exprRes))
                                       (cAfterExpr (pairSecond exprRes))
                                       (spRb (skipTrivia bs len cAfterExpr))
                                       (rbTriv (pairFirst spRb))
                                       (cRb (pairSecond spRb))
                                       (rbTok (tr/makeToken "rbrace" cRb (+ cRb 1)))
                                       (containerKids (cons (tr/elemToken lbTok) (listAppend inTriv (cons (tr/elemNode exprNode) (listAppend rbTriv (list (tr/elemToken rbTok)))))))
                                       (containerNode (tr/makeNode "jsxExpressionContainer" cVal (+ cRb 1) containerKids))
                                       (attrKids (listAppend triv
                                                   (cons (tr/elemNode nameNode)
                                                     (listAppend eqTriv
                                                       (cons (tr/elemToken eqTok)
                                                         (listAppend valTriv (list (tr/elemNode containerNode))))))))
                                       (attrNode (tr/makeNode "jsxAttribute" c (+ cRb 1) attrKids))]
                                   (parseJsxAttributesLoop bs len text (+ cRb 1) (cons (tr/elemNode attrNode) acc))))))
                            ((= valB 60)
                             (let [(elemRes (parseJsxElementOrFrag text bs len cVal))]
                               (mt elemRes
                                 ((ok resPair)
                                  (let [(valNode (pairFirst resPair))
                                        (nextC (pairSecond resPair))
                                        (attrKids (listAppend triv
                                                    (cons (tr/elemNode nameNode)
                                                      (listAppend eqTriv
                                                        (cons (tr/elemToken eqTok)
                                                          (listAppend valTriv (list (tr/elemNode valNode))))))))
                                        (attrNode (tr/makeNode "jsxAttribute" c nextC attrKids))]
                                    (parseJsxAttributesLoop bs len text nextC (cons (tr/elemNode attrNode) acc))))
                                 ((err _)
                                  (pair (listReverse acc) cVal)))))
                            (else
                             (let [(errKids (listAppend triv (cons (tr/elemNode nameNode) (listAppend eqTriv (list (tr/elemToken eqTok))))))
                                   (errNode (tr/makeErrorNode c (+ cEq 1) errKids))]
                               (parseJsxAttributesLoop bs len text (+ cEq 1) (cons (tr/elemNode errNode) acc))))))))
                    (let [(attrKids (listAppend triv (list (tr/elemNode nameNode))))
                          (attrNode (tr/makeNode "jsxAttribute" c cNameEnd attrKids))]
                      (parseJsxAttributesLoop bs len text cNameEnd (cons (tr/elemNode attrNode) acc))))))))))))
fn parseJsxChildrenLoop bs: Bytes len: Int64 text: String cur: Int64 openTagName: String acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) Int64)
  (if (>= cur len)
    (pair (listReverse acc) cur)
    (let [(b (bytesGet bs cur))]
      (if (= b 60)
        (if (and (< (+ cur 1) len) (= (bytesGet bs (+ cur 1)) 47))
          (if (stringEmpty? openTagName)
            (let [(ltTok (tr/makeToken "lt" cur (+ cur 1)))
                  (slashTok (tr/makeToken "slash" (+ cur 1) (+ cur 2)))
                  (spGt (skipTrivia bs len (+ cur 2)))
                  (gtTriv (pairFirst spGt))
                  (cGt (pairSecond spGt))]
              (if (and (< cGt len) (= (bytesGet bs cGt) 62))
                (let [(gtTok (tr/makeToken "gt" cGt (+ cGt 1)))
                      (closeKids (cons (tr/elemToken ltTok) (cons (tr/elemToken slashTok) (listAppend gtTriv (list (tr/elemToken gtTok))))))
                      (closeFrag (tr/makeNode "jsxClosingFragment" cur (+ cGt 1) closeKids))]
                  (pair (listReverse (cons (tr/elemNode closeFrag) acc)) (+ cGt 1)))
                (pair (listReverse acc) cur)))
            (let [(ltTok (tr/makeToken "lt" cur (+ cur 1)))
                  (slashTok (tr/makeToken "slash" (+ cur 1) (+ cur 2)))
                  (spName (skipTrivia bs len (+ cur 2)))
                  (nameTriv (pairFirst spName))
                  (cName (pairSecond spName))
                  (nameRes (parseJsxTagName bs len cName))
                  (closeNameNode (pairFirst nameRes))
                  (cAfterName (pairSecond nameRes))
                  (spGt (skipTrivia bs len cAfterName))
                  (gtTriv (pairFirst spGt))
                  (cGt (pairSecond spGt))]
              (if (and (< cGt len) (= (bytesGet bs cGt) 62))
                (let [(gtTok (tr/makeToken "gt" cGt (+ cGt 1)))
                      (closeKids (cons (tr/elemToken ltTok)
                                   (cons (tr/elemToken slashTok)
                                     (listAppend nameTriv
                                       (cons (tr/elemNode closeNameNode)
                                         (listAppend gtTriv (list (tr/elemToken gtTok))))))))
                      (closeElem (tr/makeNode "jsxClosingElement" cur (+ cGt 1) closeKids))]
                  (pair (listReverse (cons (tr/elemNode closeElem) acc)) (+ cGt 1)))
                (pair (listReverse acc) cur))))
          (let [(spFrag (skipTrivia bs len (+ cur 1)))
                (cGt (pairSecond spFrag))]
            (if (and (< cGt len) (= (bytesGet bs cGt) 62))
              (let [(fragRes (parseJsxFragmentFrom text bs len cur))]
              (mt fragRes
                ((ok resPair)
                 (let [(fragNode (pairFirst resPair))
                       (nextCur (pairSecond resPair))]
                   (parseJsxChildrenLoop bs len text nextCur openTagName (cons (tr/elemNode fragNode) acc))))
                ((err _)
                 (pair (listReverse acc) cur))))
            (let [(elemRes (parseJsxElementFrom text bs len cur))]
              (mt elemRes
                ((ok resPair)
                 (let [(elemNode (pairFirst resPair))
                       (nextCur (pairSecond resPair))]
                   (parseJsxChildrenLoop bs len text nextCur openTagName (cons (tr/elemNode elemNode) acc))))
                ((err _)
                 (pair (listReverse acc) cur)))))))
        (if (= b 123)
          (let [(lbTok (tr/makeToken "lbrace" cur (+ cur 1)))
                (spIn (skipTrivia bs len (+ cur 1)))
                (inTriv (pairFirst spIn))
                (cIn (pairSecond spIn))]
            (if (and (< cIn len) (= (bytesGet bs cIn) 125))
              (let [(emptyNode (tr/makeNode "jsxEmptyExpr" cIn cIn (list)))
                    (rbTok (tr/makeToken "rbrace" cIn (+ cIn 1)))
                    (containerKids (cons (tr/elemToken lbTok) (listAppend inTriv (cons (tr/elemNode emptyNode) (list (tr/elemToken rbTok))))))
                    (containerNode (tr/makeNode "jsxExpressionContainer" cur (+ cIn 1) containerKids))]
                (parseJsxChildrenLoop bs len text (+ cIn 1) openTagName (cons (tr/elemNode containerNode) acc)))
              (if (and (< (+ cIn 2) len) (and (= (bytesGet bs cIn) 46) (and (= (bytesGet bs (+ cIn 1)) 46) (= (bytesGet bs (+ cIn 2)) 46))))
                (let [(ellTok (tr/makeToken "ellipsis" cIn (+ cIn 3)))
                      (spAfterEll (skipTrivia bs len (+ cIn 3)))
                      (ellTriv (pairFirst spAfterEll))
                      (cExpr (pairSecond spAfterEll))
                      (exprRes (parseJsxExprFromOffset text bs len cExpr))
                      (exprNode (pairFirst exprRes))
                      (cAfterExpr (pairSecond exprRes))
                      (spRb (skipTrivia bs len cAfterExpr))
                      (rbTriv (pairFirst spRb))
                      (cRb (pairSecond spRb))
                      (rbTok (tr/makeToken "rbrace" cRb (+ cRb 1)))
                      (spreadKids (cons (tr/elemToken lbTok)
                                    (listAppend inTriv
                                      (cons (tr/elemToken ellTok)
                                        (listAppend ellTriv
                                          (cons (tr/elemNode exprNode)
                                            (listAppend rbTriv (list (tr/elemToken rbTok)))))))))
                      (spreadNode (tr/makeNode "jsxSpreadChild" cur (+ cRb 1) spreadKids))]
                  (parseJsxChildrenLoop bs len text (+ cRb 1) openTagName (cons (tr/elemNode spreadNode) acc)))
                (let [(exprRes (parseJsxExprFromOffset text bs len cIn))
                      (exprNode (pairFirst exprRes))
                      (cAfterExpr (pairSecond exprRes))
                      (spRb (skipTrivia bs len cAfterExpr))
                      (rbTriv (pairFirst spRb))
                      (cRb (pairSecond spRb))
                      (rbTok (tr/makeToken "rbrace" cRb (+ cRb 1)))
                      (containerKids (cons (tr/elemToken lbTok) (listAppend inTriv (cons (tr/elemNode exprNode) (listAppend rbTriv (list (tr/elemToken rbTok)))))))
                      (containerNode (tr/makeNode "jsxExpressionContainer" cur (+ cRb 1) containerKids))]
                  (parseJsxChildrenLoop bs len text (+ cRb 1) openTagName (cons (tr/elemNode containerNode) acc))))))
          (let [(textEnd (scanJsxTextEnd bs len cur))]
            (if (> textEnd cur)
              (let [(textTok (tr/makeToken "jsxText" cur textEnd))
                    (textNode (tr/makeNode "jsxText" cur textEnd (list (tr/elemToken textTok))))]
                (parseJsxChildrenLoop bs len text textEnd openTagName (cons (tr/elemNode textNode) acc)))
              (pair (listReverse acc) cur)))))))

fn parseJsxElementWithTagParser text: String bs: Bytes len: Int64 i: Int64 tagParser: (Fn [Bytes Int64 Int64 String] -> (Pair (Pair tr/Node (Option tr/Node)) Int64)) -> (Result (Pair tr/Node Int64) String)
  (if (or (>= i len) (!= (bytesGet bs i) 60))
    (err (str "Expected '<' at offset " (stringFromInt64 i)))
    (let [(ltTok (tr/makeToken "lt" i (+ i 1)))
          (spName (skipTrivia bs len (+ i 1)))
          (nameTriv (pairFirst spName))
          (cName (pairSecond spName))
          (tagRes (tagParser bs len cName text))
          (tagPair (pairFirst tagRes))
          (nameNode (pairFirst tagPair))
          (maybeArgs (pairSecond tagPair))
          (cAfterName (pairSecond tagRes))]
      (if (<= cAfterName cName)
        (err (str "Expected tag name at offset " (stringFromInt64 cName)))
        (let [(attrRes (parseJsxAttributesLoop bs len text cAfterName (list)))
          (attrElems (pairFirst attrRes))
          (cAfterAttrs (pairSecond attrRes))]
      (if (listAny? (fn [(el tr/TreeElement)] -> Bool (mt el ((tr/elemNode n) (= (tr/nodeKind n) "error")) ((tr/elemToken _) false))) attrElems)
        (err (str "Invalid attribute at offset " (stringFromInt64 cAfterAttrs)))
        (if (>= cAfterAttrs len)
        (err (str "Unclosed JSX element at offset " (stringFromInt64 cAfterAttrs)))
        (let [(b (bytesGet bs cAfterAttrs))
              (argsList (mt maybeArgs ((some an) (list (tr/elemNode an))) ((none) (list))))]
          (if (and (= b 47) (and (< (+ cAfterAttrs 1) len) (= (bytesGet bs (+ cAfterAttrs 1)) 62)))
            (let [(slashTok (tr/makeToken "slash" cAfterAttrs (+ cAfterAttrs 1)))
                  (gtTok (tr/makeToken "gt" (+ cAfterAttrs 1) (+ cAfterAttrs 2)))
                  (openKids (cons (tr/elemToken ltTok)
                              (listAppend nameTriv
                                (cons (tr/elemNode nameNode)
                                  (listAppend argsList
                                    (listAppend attrElems
                                      (list (tr/elemToken slashTok) (tr/elemToken gtTok))))))))
                  (openNode (tr/makeNode "jsxOpeningElement" i (+ cAfterAttrs 2) openKids))
                  (elemNode (tr/makeNode "jsxElement" i (+ cAfterAttrs 2) (list (tr/elemNode openNode))))]
              (ok (pair elemNode (+ cAfterAttrs 2))))
            (if (= b 62)
              (let [(gtTok (tr/makeToken "gt" cAfterAttrs (+ cAfterAttrs 1)))
                    (openKids (cons (tr/elemToken ltTok)
                                (listAppend nameTriv
                                  (cons (tr/elemNode nameNode)
                                    (listAppend argsList
                                      (listAppend attrElems (list (tr/elemToken gtTok))))))))
                    (openNode (tr/makeNode "jsxOpeningElement" i (+ cAfterAttrs 1) openKids))
                    (tagName (optionOr (stringSlice text (tr/nodeStart nameNode) (tr/nodeEnd nameNode)) ""))
                    (chRes (parseJsxChildrenLoop bs len text (+ cAfterAttrs 1) tagName (list)))
                    (chElems (pairFirst chRes))
                    (cAfterCh (pairSecond chRes))]
                (if (= (listLength chElems) 0)
                  (err (str "Missing closing tag for <" tagName "> at offset " (stringFromInt64 cAfterCh)))
                  (let [(lastElem (optionOr (listLast chElems) (tr/elemToken (tr/makeToken "" 0 0))))]
                    (mt lastElem
                      ((tr/elemToken _)
                       (err (str "Missing closing tag for <" tagName "> at offset " (stringFromInt64 cAfterCh))))
                      ((tr/elemNode lastNode)
                       (if (!= (tr/nodeKind lastNode) "jsxClosingElement")
                         (err (str "Missing closing tag for <" tagName "> at offset " (stringFromInt64 cAfterCh)))
                         (let [(closeNameNode (optionOr (listHead (findChildNodes (tr/nodeChildren lastNode))) (tr/makeNode "" 0 0 (list))))
                               (closeTagName (optionOr (stringSlice text (tr/nodeStart closeNameNode) (tr/nodeEnd closeNameNode)) ""))]
                           (if (!= closeTagName tagName)
                             (err (str "Mismatched closing tag: expected </" tagName ">, got </" closeTagName "> at offset " (stringFromInt64 (tr/nodeStart lastNode))))
                             (let [(allKids (cons (tr/elemNode openNode) chElems))
                                   (elemNode (tr/makeNode "jsxElement" i cAfterCh allKids))]
                               (ok (pair elemNode cAfterCh)))))))))))
              (err (str "Expected '>' or '/>' in tag at offset " (stringFromInt64 cAfterAttrs))))))))))))

fn parseJsxElementFrom text: String bs: Bytes len: Int64 i: Int64 -> (Result (Pair tr/Node Int64) String)
  (parseJsxElementWithTagParser text bs len i defaultJsxTagParser)

fn parseJsxFragmentFrom text: String bs: Bytes len: Int64 i: Int64 -> (Result (Pair tr/Node Int64) String)
  (if (or (>= (+ i 1) len) (!= (bytesGet bs i) 60))
    (err (str "Expected '<>' at offset " (stringFromInt64 i)))
    (let [(spAfterLt (skipTrivia bs len (+ i 1)))
          (ltTriv (pairFirst spAfterLt))
          (cGt (pairSecond spAfterLt))]
      (if (or (>= cGt len) (!= (bytesGet bs cGt) 62))
        (err (str "Expected '>' in fragment at offset " (stringFromInt64 cGt)))
        (let [(ltTok (tr/makeToken "lt" i (+ i 1)))
              (gtTok (tr/makeToken "gt" cGt (+ cGt 1)))
              (openKids (cons (tr/elemToken ltTok) (listAppend ltTriv (list (tr/elemToken gtTok)))))
              (openFrag (tr/makeNode "jsxOpeningFragment" i (+ cGt 1) openKids))
              (chRes (parseJsxChildrenLoop bs len text (+ cGt 1) "" (list)))
              (chElems (pairFirst chRes))
              (cAfterCh (pairSecond chRes))]
      (if (= (listLength chElems) 0)
        (err (str "Missing closing tag for fragment at offset " (stringFromInt64 cAfterCh)))
        (let [(lastElem (optionOr (listLast chElems) (tr/elemToken (tr/makeToken "" 0 0))))]
          (mt lastElem
            ((tr/elemToken _)
             (err (str "Missing closing tag for fragment at offset " (stringFromInt64 cAfterCh))))
            ((tr/elemNode lastNode)
             (if (!= (tr/nodeKind lastNode) "jsxClosingFragment")
               (err (str "Missing closing tag for fragment at offset " (stringFromInt64 cAfterCh)))
               (let [(allKids (cons (tr/elemNode openFrag) chElems))
                     (fragNode (tr/makeNode "jsxFragment" i cAfterCh allKids))]
                 (ok (pair fragNode cAfterCh))))))))))))

fn findChildNodes elems: (List tr/TreeElement) -> (List tr/Node)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (findChildNodes tl))]
      (mt hd
        ((tr/elemNode n) (cons n rest))
        ((tr/elemToken _) rest))))

fn findDirectTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (findDirectTokens tl))]
      (mt hd
        ((tr/elemToken t) (cons t rest))
        ((tr/elemNode _) rest))))

fn findChildTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (findChildTokens tl))]
      (mt hd
        ((tr/elemToken t) (cons t rest))
        ((tr/elemNode n) (listAppend (findChildTokens (tr/nodeChildren n)) rest)))))

fn parseJsxElement text: String start: Int64 -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (parseJsxElementFrom text bs len start))]
    (mt res
      ((ok p) (ok (pairFirst p)))
      ((err e) (err e))))

fn parseJsxFragment text: String start: Int64 -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (parseJsxFragmentFrom text bs len start))]
    (mt res
      ((ok p) (ok (pairFirst p)))
      ((err e) (err e))))

fn parseJsxExpr toks: (List tr/Token) text: String minPrec: Int64 -> tr/Node
  (expr/parseExpr text)

fn parseJsxTokens tokens: (List tr/Token) text: String -> tr/Node
  (expr/parseTokens tokens text)

fn parseJsxText text: String -> tr/Node
  (let [(res (parseJsx text))]
    (resultOr res (tr/makeErrorNode 0 (stringLength text) (list))))

fn parseJsxModule text: String bs: Bytes len: Int64 startPos: Int64 leadTriv: (List tr/TreeElement) -> (Result tr/Node String)
  (let [(toks (lx/tokenize text))
        (doc (expr/parseTokens toks text))]
    (ok doc))

fn parseJsxDocLoop bs: Bytes len: Int64 text: String cur: Int64 acc: (List tr/TreeElement) -> (Result (Pair (List tr/TreeElement) Int64) String)
  (let [(sp (skipTrivia bs len cur))
        (triv (pairFirst sp))
        (c (pairSecond sp))]
    (if (>= c len)
      (ok (pair (listAppend acc triv) c))
      (let [(b (bytesGet bs c))]
        (if (= b 59)
          (let [(semiTok (tr/makeToken "semi" c (+ c 1)))
                (newAcc (listAppend acc (listAppend triv (list (tr/elemToken semiTok)))))]
            (parseJsxDocLoop bs len text (+ c 1) newAcc))
          (if (= b 60)
            (let [(spFrag (skipTrivia bs len (+ c 1)))
                  (cGt (pairSecond spFrag))]
              (if (and (< cGt len) (= (bytesGet bs cGt) 62))
                (let [(fragRes (parseJsxFragmentFrom text bs len c))]
                  (mt fragRes
                    ((ok p)
                     (let [(node (pairFirst p))
                           (cEnd (pairSecond p))
                           (newAcc (listAppend acc (listAppend triv (list (tr/elemNode node)))))]
                       (parseJsxDocLoop bs len text cEnd newAcc)))
                    ((err e) (err e))))
                (let [(elemRes (parseJsxElementFrom text bs len c))]
                  (mt elemRes
                    ((ok p)
                     (let [(node (pairFirst p))
                           (cEnd (pairSecond p))
                           (newAcc (listAppend acc (listAppend triv (list (tr/elemNode node)))))]
                       (parseJsxDocLoop bs len text cEnd newAcc)))
                    ((err e) (err e))))))
            (err (str "Unexpected token at offset " (stringFromInt64 c))))))))

fn parseJsx text: String -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (sp (skipTrivia bs len 0))
        (c (pairSecond sp))]
    (if (>= c len)
      (ok (tr/makeNode "document" 0 len (pairFirst sp)))
      (let [(b (bytesGet bs c))]
        (if (= b 60)
          (let [(docRes (parseJsxDocLoop bs len text 0 (list)))]
            (mt docRes
              ((ok p)
               (let [(elems (pairFirst p))]
                 (if (= (listLength elems) 1)
                   (let [(firstEl (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))]
                     (mt firstEl
                       ((tr/elemNode n) (ok n))
                       ((tr/elemToken _) (ok (tr/makeNode "document" 0 len elems)))))
                   (ok (tr/makeNode "document" 0 len elems)))))
              ((err e) (err e))))
          (parseJsxModule text bs len c (pairFirst sp))))))

fn parse text: String -> (Result tr/Node String)
  (parseJsx text)

fn isJsxNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "jsxElement")
    (or (= k "jsxFragment")
    (or (= k "jsxOpeningElement")
    (or (= k "jsxClosingElement")
    (or (= k "jsxOpeningFragment")
    (or (= k "jsxClosingFragment")
    (or (= k "jsxAttribute")
    (or (= k "jsxSpreadAttribute")
    (or (= k "jsxSpreadChild")
    (or (= k "jsxExpressionContainer")
    (or (= k "jsxText")
    (or (= k "jsxIdentifier")
    (or (= k "jsxMemberExpr")
    (or (= k "jsxNamespacedName")
        (= k "jsxEmptyExpr"))))))))))))))))

fn jsxNodeKind node: tr/Node -> String
  (tr/nodeKind node)

fn jsxToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))
        (kids (tr/nodeChildren node))]
    (cond
      ((= k "jsxElement")
       (let [(childNodes (findChildNodes kids))
             (openNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
             (openKids (tr/nodeChildren openNode))
             (openChildNodes (findChildNodes openKids))
             (nameNode (optionOr (listHead openChildNodes) (tr/makeNode "" 0 0 (list))))
             (nameStr (jsxToSExpr nameNode text))
             (attrNodes (optionOr (listTail openChildNodes) (list)))
             (attrStrs (map (fn [(n tr/Node)] -> String (jsxToSExpr n text)) attrNodes))
             (attrsFormatted (str "[" (stringJoin attrStrs " ") "]"))
             (isSelfClosing (= (listLength childNodes) 1))]
         (if isSelfClosing
           (str "(jsxElement " nameStr " " attrsFormatted ")")
           (let [(bodyNodes (optionOr (listSlice childNodes 1 (- (listLength childNodes) 1)) (list)))
                 (chStrs (map (fn [(n tr/Node)] -> String (jsxToSExpr n text)) bodyNodes))
                 (chFormatted (str "[" (stringJoin chStrs " ") "]"))]
             (str "(jsxElement " nameStr " " attrsFormatted " " chFormatted ")")))))
      ((= k "jsxFragment")
       (let [(childNodes (findChildNodes kids))
             (bodyNodes (if (>= (listLength childNodes) 2)
                          (optionOr (listSlice childNodes 1 (- (listLength childNodes) 1)) (list))
                          (list)))
             (chStrs (map (fn [(n tr/Node)] -> String (jsxToSExpr n text)) bodyNodes))
             (chFormatted (str "[" (stringJoin chStrs " ") "]"))]
         (str "(jsxFragment " chFormatted ")")))
      ((= k "jsxAttribute")
       (let [(childNodes (findChildNodes kids))]
         (if (= (listLength childNodes) 1)
           (let [(nameNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
             (str "(jsxAttr " (jsxToSExpr nameNode text) ")"))
           (if (>= (listLength childNodes) 2)
             (let [(nameNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                   (valNode (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
               (str "(jsxAttr " (jsxToSExpr nameNode text) " " (jsxToSExpr valNode text) ")"))
             "(jsxAttr)"))))
      ((or (= k "jsxSpreadAttribute") (= k "jsxSpreadChild"))
       (let [(childNodes (findChildNodes kids))
             (argNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
         (str "(jsxSpread " (jsxToSExpr argNode text) ")")))
      ((= k "jsxExpressionContainer")
       (let [(childNodes (findChildNodes kids))]
         (if (listEmpty? childNodes)
           "(jsxExpr)"
           (let [(exprNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
             (if (= (tr/nodeKind exprNode) "jsxEmptyExpr")
               "(jsxExpr)"
               (str "(jsxExpr " (jsxToSExpr exprNode text) ")"))))))
      ((= k "jsxText")
       (let [(sl (optionOr (stringSlice text (tr/nodeStart node) (tr/nodeEnd node)) ""))]
         (str "(jsxText \"" sl "\")")))
      ((= k "jsxIdentifier")
       (optionOr (stringSlice text (tr/nodeStart node) (tr/nodeEnd node)) ""))
      ((= k "jsxMemberExpr")
       (let [(childNodes (findChildNodes kids))
             (objNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
             (propNode (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
         (str "(. " (jsxToSExpr objNode text) " " (jsxToSExpr propNode text) ")")))
      ((= k "jsxNamespacedName")
       (let [(childNodes (findChildNodes kids))
             (nsNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
             (nameNode (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
         (str "(: " (jsxToSExpr nsNode text) " " (jsxToSExpr nameNode text) ")")))
      ((= k "jsxEmptyExpr")
       "")
      ((or (= k "document") (= k "expression"))
       (let [(childNodes (findChildNodes kids))]
         (if (listEmpty? childNodes)
           ""
           (jsxToSExpr (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))) text))))
      ((or (= k "binaryExpr") (or (= k "logicalExpr") (or (= k "assignExpr") (= k "seqExpr"))))
       (let [(toks (findDirectTokens kids))
             (nonTrivToks (filter (fn [(t tr/Token)] -> Bool (not (tr/isTriviaToken t))) toks))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead nonTrivToks) (tr/makeToken "" 0 0)))
             (op (optionOr (stringSlice text opTok.start opTok.end) ""))
             (leftNode (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeNode "" 0 0 (list))))]
         (str "(" op " " (jsxToSExpr leftNode text) " " (jsxToSExpr rightNode text) ")")))
      ((= k "conditionalExpr")
       (let [(nodes (findChildNodes kids))
             (testNode (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))
             (consNode (optionOr (listGet nodes 1) (tr/makeNode "" 0 0 (list))))
             (altNode (optionOr (listGet nodes 2) (tr/makeNode "" 0 0 (list))))]
         (str "(? " (jsxToSExpr testNode text) " " (jsxToSExpr consNode text) " " (jsxToSExpr altNode text) ")")))
      ((= k "arrowFunction")
       (let [(childNodes (findChildNodes kids))
             (paramsNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
             (bodyNode (optionOr (listLast childNodes) (tr/makeNode "" 0 0 (list))))
             (paramStr (if (= (tr/nodeKind paramsNode) "ident")
                         (str "(params " (jsxToSExpr paramsNode text) ")")
                         (jsxToSExpr paramsNode text)))]
         (str "(arrow " paramStr " " (jsxToSExpr bodyNode text) ")")))
      ((= k "parameters")
       (let [(childNodes (findChildNodes kids))
             (argStrs (map (fn [(n tr/Node)] -> String (str " " (jsxToSExpr n text))) childNodes))]
         (str "(params" (stringJoin argStrs "") ")")))
      ((= k "callExpr")
       (let [(nodes (findChildNodes kids))
             (callee (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))
             (argNodes (optionOr (listTail nodes) (list)))
             (argStrs (map (fn [(n tr/Node)] -> String (str " " (jsxToSExpr n text))) argNodes))]
         (str "(call " (jsxToSExpr callee text) (stringJoin argStrs "") ")")))
      ((= k "memberExpr")
       (let [(nodes (findChildNodes kids))
             (toks (findDirectTokens kids))
             (nonTrivToks (filter (fn [(t tr/Token)] -> Bool (not (tr/isTriviaToken t))) toks))
             (leftNode (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))]
         (if (>= (listLength nodes) 2)
           (let [(idxNode (optionOr (listGet nodes 1) (tr/makeNode "" 0 0 (list))))]
             (str "(index " (jsxToSExpr leftNode text) " " (jsxToSExpr idxNode text) ")"))
           (let [(lastTok (optionOr (listLast nonTrivToks) (tr/makeToken "" 0 0)))
                 (prop (optionOr (stringSlice text lastTok.start lastTok.end) ""))]
             (str "(. " (jsxToSExpr leftNode text) " " prop ")")))))
      ((= k "literal")
       (optionOr (stringSlice text (tr/nodeStart node) (tr/nodeEnd node)) ""))
      ((= k "ident")
       (optionOr (stringSlice text (tr/nodeStart node) (tr/nodeEnd node)) ""))
      (else
       (expr/exprToSExpr node text))))
