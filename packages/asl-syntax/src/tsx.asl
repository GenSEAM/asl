(module asl-syntax/tsx
  :x [parse
      parseTsx
      parseTsxModule
      parseTsxExpr
      parseTsxElement
      parseTsxFragment
      tsxToSExpr
      isTsxNode
      tsxNodeKind]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/ts/types :a ts)
      (asl-syntax/ts/decl :a decl)
      (asl-syntax/ts/module :a tsMod)
      (asl-syntax/js/stmt :a stmt)
      (asl-syntax/jsx :a jsx)])

fn rejectTypeAssertions node: tr/Node -> tr/Node
  (let [(k (tr/nodeKind node))
        (kids (tr/nodeChildren node))
        (newKids (rejectTypeAssertionsInElements kids))]
    (if (= k "typeAssertion")
      (tr/makeErrorNode (tr/nodeStart node) (tr/nodeEnd node) newKids)
      (tr/makeNode k (tr/nodeStart node) (tr/nodeEnd node) newKids)))

fn rejectTypeAssertionsInElements elems: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (cons hd (rejectTypeAssertionsInElements tl)))
        ((tr/elemNode n) (cons (tr/elemNode (rejectTypeAssertions n)) (rejectTypeAssertionsInElements tl))))))

fn scanBalancedAngles bs: Bytes len: Int64 i: Int64 depth: Int64 -> Int64
  (if (>= i len)
    -1
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 60)
         (scanBalancedAngles bs len (+ i 1) (+ depth 1)))
        ((= b 62)
         (if (and (> i 0) (= (bytesGet bs (- i 1)) 61))
           (scanBalancedAngles bs len (+ i 1) depth)
           (if (= depth 1)
             (+ i 1)
             (scanBalancedAngles bs len (+ i 1) (- depth 1)))))
        ((or (= b 34) (= b 39))
         (let [(qEnd (skipQuoteEnd bs len b (+ i 1)))]
           (scanBalancedAngles bs len qEnd depth)))
        ((or (= b 10) (= b 59))
         -1)
        (else
         (scanBalancedAngles bs len (+ i 1) depth)))))

fn scanBalancedParens bs: Bytes len: Int64 i: Int64 depth: Int64 -> Int64
  (if (>= i len)
    -1
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 40)
         (scanBalancedParens bs len (+ i 1) (+ depth 1)))
        ((= b 41)
         (if (<= depth 1)
           (+ i 1)
           (scanBalancedParens bs len (+ i 1) (- depth 1))))
        (else
         (scanBalancedParens bs len (+ i 1) depth)))))

fn parseTsxTagName bs: Bytes len: Int64 i: Int64 text: String -> (Pair (Pair tr/Node (Option tr/Node)) Int64)
  (let [(baseRes (jsx/parseJsxTagName bs len i))
        (nameNode (pairFirst baseRes))
        (cAfterName (pairSecond baseRes))]
    (if (and (< cAfterName len) (= (bytesGet bs cAfterName) 60))
      (let [(cAfterArgs (scanBalancedAngles bs len cAfterName 0))]
        (if (> cAfterArgs cAfterName)
          (let [(argSlice (optionOr (stringSlice text cAfterName cAfterArgs) ""))
                (rawToks (lx/tokenize argSlice))
                (splitToks (tsMod/splitTypeTokens rawToks))
                (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cAfterName) (+ t.end cAfterName))) splitToks))
                (parsedArgs (ts/parseTypeArguments shifted text))
                (candNode parsedArgs.node)
                (argsNode (if (or (tr/isErrorNode candNode) (= (tr/nodeKind candNode) "error"))
                            (tr/makeNode "typeArguments" cAfterName cAfterArgs (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) shifted))
                            candNode))]
            (pair (pair nameNode (some argsNode)) cAfterArgs))
          (pair (pair nameNode (none)) cAfterName)))
      (pair (pair nameNode (none)) cAfterName)))

fn lookupJsxNode start: Int64 end: Int64 entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> (Option tr/Node)
  (if (listEmpty? entries)
    (none)
    (let [(hd (optionOr (listHead entries) (pair (pair 0 0) (tr/makeErrorNode 0 0 (list)))))
          (tl (optionOr (listTail entries) (list)))
          (span (pairFirst hd))
          (s (pairFirst span))
          (e (pairSecond span))]
      (if (and (= s start) (= e end))
        (some (pairSecond hd))
        (lookupJsxNode start end tl))))

fn substituteJsxInElement elem: tr/TreeElement entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> tr/TreeElement
  (mt elem
    ((tr/elemToken tok)
     (let [(st (tr/tokenStart tok))
           (en (tr/tokenEnd tok))
           (found (lookupJsxNode st en entries))]
       (mt found
         ((some n) (tr/elemNode n))
         ((none) elem))))
    ((tr/elemNode node)
     (let [(st (tr/nodeStart node))
           (en (tr/nodeEnd node))
           (found (lookupJsxNode st en entries))]
       (mt found
         ((some n) (tr/elemNode n))
         ((none) (tr/elemNode (substituteJsxNodes node entries)))))))

fn substituteJsxNodes node: tr/Node entries: (List (Pair (Pair Int64 Int64) tr/Node)) -> tr/Node
  (let [(st (tr/nodeStart node))
        (en (tr/nodeEnd node))
        (found (lookupJsxNode st en entries))]
    (mt found
      ((some n) n)
      ((none)
       (let [(k (tr/nodeKind node))
             (kids (tr/nodeChildren node))
             (newKids (map (fn [(el tr/TreeElement)] -> tr/TreeElement (substituteJsxInElement el entries)) kids))]
         (tr/makeNode k st en newKids)))))

fn tryParseGenericArrow text: String bs: Bytes len: Int64 cur: Int64 -> (Option (Pair tr/Node Int64))
  (if (or (>= cur len) (!= (bytesGet bs cur) 60))
    (none)
    (let [(endTp (scanBalancedAngles bs len cur 0))]
      (if (or (<= endTp cur) (>= endTp len))
        (none)
        (let [(tpSlice (optionOr (stringSlice text cur endTp) ""))
              (rawTpToks (lx/tokenize tpSlice))
              (splitTpToks (tsMod/splitTypeTokens rawTpToks))
              (shiftedTpToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) splitTpToks))
              (tpRes (ts/parseTypeParameters shiftedTpToks text))
              (tpNode tpRes.node)
              (spParams (jsx/skipTrivia bs len endTp))
              (trivParams (pairFirst spParams))
              (cParams (pairSecond spParams))]
          (if (or (or (tr/isErrorNode tpNode) (= (tr/nodeKind tpNode) "error")) (or (>= cParams len) (!= (bytesGet bs cParams) 40)))
            (none)
            (let [(endParams (scanBalancedParens bs len cParams 0))]
              (if (or (<= endParams cParams) (> endParams len))
                (none)
                (let [(paramsSlice (optionOr (stringSlice text cParams endParams) ""))
                      (rawParamsToks (lx/tokenize paramsSlice))
                      (shiftedParamsToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cParams) (+ t.end cParams))) rawParamsToks))
                      (lpTok (optionOr (listHead shiftedParamsToks) (tr/makeToken "lparen" cParams (+ cParams 1))))
                      (tlLp (optionOr (listTail shiftedParamsToks) (list)))
                      (paramsRes (ts/parseFunctionParamsLoop tlLp text (list (tr/elemToken lpTok))))
                      (allParamElems paramsRes.elements)
                      (paramsNode (tr/makeNode "parameters" cParams endParams allParamElems))
                      (remSlice (optionOr (stringSlice text endParams len) ""))
                      (rawRemToks (lx/tokenize remSlice))
                      (splitRemToks (tsMod/splitTypeTokens rawRemToks))
                      (shiftedRemToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start endParams) (+ t.end endParams))) splitRemToks))
                      (retPair (decl/parseReturnTypeOpt shiftedRemToks text))
                      (retElems (pairFirst retPair))
                      (remRetToks (pairSecond retPair))
                      (spArrow (tsMod/skipTrivia remRetToks))
                      (trivArrow (pairFirst spArrow))
                      (remArrow (pairSecond spArrow))]
                  (if (or (listEmpty? remArrow) (!= (tr/tokenKind (optionOr (listHead remArrow) (tr/makeToken "" 0 0))) "arrow"))
                    (none)
                    (let [(arrowTok (optionOr (listHead remArrow) (tr/makeToken "" 0 0)))
                          (remBody (optionOr (listTail remArrow) (list)))
                          (spBody (tsMod/skipTrivia remBody))
                          (trivBody (pairFirst spBody))
                          (remBodyAfterTriv (pairSecond spBody))]
                      (if (listEmpty? remBodyAfterTriv)
                        (none)
                        (let [(firstBodyTok (optionOr (listHead remBodyAfterTriv) (tr/makeToken "" 0 0)))
                              (isBlock (= (tr/tokenKind firstBodyTok) "lbrace"))
                              (bodyRes (if isBlock
                                         (stmt/parseBlock remBodyAfterTriv text true false)
                                         (ts/parseTsExpr remBodyAfterTriv text 1)))
                              (bodyNode bodyRes.node)]
                          (if (or (tr/isErrorNode bodyNode) (= (tr/nodeKind bodyNode) "error"))
                            (none)
                            (let [(allKids (cons (tr/elemNode tpNode)
                                             (listAppend trivParams
                                               (cons (tr/elemNode paramsNode)
                                                 (listAppend retElems
                                                   (listAppend trivArrow
                                                     (cons (tr/elemToken arrowTok)
                                                       (listAppend trivBody (list (tr/elemNode bodyNode))))))))))
                                  (arrowNode (tr/makeNode "arrowFunction" cur (tr/nodeEnd bodyNode) allKids))]
                              (some (pair arrowNode (tr/nodeEnd bodyNode)))))))))))))))))

fn hasDisallowedTextBytes? bs: Bytes len: Int64 i: Int64 -> Bool
  (if (>= i len)
    false
    (let [(b (bytesGet bs i))]
      (if (or (= b 60) (or (= b 62) (or (= b 123) (= b 125))))
        true
        (hasDisallowedTextBytes? bs len (+ i 1)))))

fn isPlainJsxText? s: String -> Bool
  (let [(bs (stringToBytes s))
        (len (bytesLength bs))]
    (not (hasDisallowedTextBytes? bs len 0)))

fn skipLineCommentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 10) (= b 13))
        i
        (skipLineCommentEnd bs len (+ i 1)))))

fn skipBlockCommentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= (+ i 1) len)
    len
    (if (and (= (bytesGet bs i) 42) (= (bytesGet bs (+ i 1)) 47))
      (+ i 2)
      (skipBlockCommentEnd bs len (+ i 1))))

fn skipQuoteEnd bs: Bytes len: Int64 delim: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (= b delim)
        (+ i 1)
        (if (= b 92)
          (skipQuoteEnd bs len delim (+ i 2))
          (skipQuoteEnd bs len delim (+ i 1))))))

fn scanTrailingWsEnd bs: Bytes start: Int64 end: Int64 -> Int64
  (if (<= end start)
    start
    (let [(b (bytesGet bs (- end 1)))]
      (if (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))
        (scanTrailingWsEnd bs start (- end 1))
        end)))

fn tryFindTypedParamsInParen text: String bs: Bytes len: Int64 cur: Int64 -> (Option (Pair (Pair Int64 Int64) tr/Node))
  (if (or (>= cur len) (!= (bytesGet bs cur) 40))
    (none)
    (let [(endParams (scanBalancedParens bs len cur 0))]
      (if (or (<= endParams cur) (> endParams len))
        (none)
        (let [(innerSlice (optionOr (stringSlice text cur endParams) ""))]
          (if (not (stringContains? innerSlice ":"))
            (none)
            (let [(spAfter (jsx/skipTrivia bs len endParams))
                  (cAfter (pairSecond spAfter))]
              (if (or (>= cAfter len) (!= (bytesGet bs cAfter) 61))
                (none)
                (let [(rawParamsToks (lx/tokenize innerSlice))
                      (shiftedToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) rawParamsToks))
                      (lpTok (optionOr (listHead shiftedToks) (tr/makeToken "lparen" cur (+ cur 1))))
                      (tlLp (optionOr (listTail shiftedToks) (list)))
                      (paramsRes (ts/parseFunctionParamsLoop tlLp text (list (tr/elemToken lpTok))))
                      (allParamElems paramsRes.elements)
                      (paramsNode (tr/makeNode "parameters" cur endParams allParamElems))]
                  (some (pair (pair cur endParams) paramsNode))))))))))

fn tryFindPlainTextInParen text: String bs: Bytes len: Int64 cur: Int64 -> (Option (Pair (Pair Int64 Int64) tr/Node))
  (if (or (>= (+ cur 8) len) (!= (bytesGet bs cur) 114))
    (none)
    (let [(sub (optionOr (stringSlice text cur (+ cur 6)) ""))]
      (if (!= sub "return")
        (none)
        (let [(spLP (jsx/skipTrivia bs len (+ cur 6)))
              (cLP (pairSecond spLP))]
          (if (or (>= cLP len) (!= (bytesGet bs cLP) 40))
            (none)
            (let [(rParen (scanBalancedParens bs len cLP 0))]
              (if (<= rParen cLP)
                (none)
                (let [(innerSlice (optionOr (stringSlice text (+ cLP 1) (- rParen 1)) ""))]
                  (if (not (isPlainJsxText? innerSlice))
                    (none)
                    (let [(spInner (jsx/skipTrivia bs len (+ cLP 1)))
                          (tStart (pairSecond spInner))
                          (tEnd (scanTrailingWsEnd bs tStart (- rParen 1)))]
                      (if (>= tStart tEnd)
                        (none)
                        (let [(tok (tr/makeToken "jsxText" tStart tEnd))
                              (node (tr/makeNode "jsxText" tStart tEnd (list (tr/elemToken tok))))]
                          (some (pair (pair tStart tEnd) node))))))))))))))

fn tryParseGenericFunctionExpr text: String bs: Bytes len: Int64 cur: Int64 -> (Option (Pair tr/Node Int64))
  (if (or (>= (+ cur 8) len) (!= (bytesGet bs cur) 102))
    (none)
    (let [(sub (optionOr (stringSlice text cur (+ cur 8)) ""))]
      (if (!= sub "function")
        (none)
        (let [(remSlice (optionOr (stringSlice text cur len) ""))
              (rawToks (lx/tokenize remSlice))
              (splitToks (tsMod/splitTypeTokens rawToks))
              (shiftedToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) splitToks))
              (hasStar (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "star")) (optionOr (listSlice shiftedToks 0 4) (list))))
              (fnRes (decl/parseFunctionDecl shiftedToks text))
              (fnNode fnRes.node)
              (remToks fnRes.rest)]
          (if (= (listLength remToks) (listLength shiftedToks))
            (none)
            (if hasStar
              (let [(kids (tr/nodeChildren fnNode))
                    (lastKid (optionOr (listLast kids) (tr/elemToken (tr/makeToken "" 0 0))))]
                (mt lastKid
                  ((tr/elemNode oldBlock)
                   (if (= (tr/nodeKind oldBlock) "block")
                     (let [(bStart (tr/nodeStart oldBlock))
                           (blockSlice (optionOr (stringSlice text bStart len) ""))
                           (rawBToks (lx/tokenize blockSlice))
                           (shiftedBToks (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start bStart) (+ t.end bStart))) rawBToks))
                           (blockRes (stmt/parseBlock shiftedBToks text true true))
                           (newBlock blockRes.node)
                           (prefixKids (optionOr (listSlice kids 0 (- (listLength kids) 1)) (list)))
                           (newKids (listAppend prefixKids (list (tr/elemNode newBlock))))
                           (repairedNode (tr/makeNode "functionDecl" (tr/nodeStart fnNode) (tr/nodeEnd newBlock) newKids))]
                       (some (pair repairedNode (tr/nodeEnd newBlock))))
                     (some (pair fnNode (tr/nodeEnd fnNode)))))
                  ((tr/elemToken _)
                   (some (pair fnNode (tr/nodeEnd fnNode))))))
              (if (= (tr/nodeKind fnNode) "error")
                (none)
                (some (pair fnNode (tr/nodeEnd fnNode))))))))))

fn findNextInteresting text: String bs: Bytes len: Int64 endOff: Int64 cur: Int64 -> Int64
  (if (>= cur endOff)
    endOff
    (let [(b (bytesGet bs cur))]
      (cond
        ((and (= b 47) (and (< (+ cur 1) endOff) (= (bytesGet bs (+ cur 1)) 47)))
         (findNextInteresting text bs len endOff (skipLineCommentEnd bs endOff (+ cur 2))))
        ((and (= b 47) (and (< (+ cur 1) endOff) (= (bytesGet bs (+ cur 1)) 42)))
         (findNextInteresting text bs len endOff (skipBlockCommentEnd bs endOff (+ cur 2))))
        ((or (= b 34) (or (= b 39) (= b 96)))
         (findNextInteresting text bs len endOff (skipQuoteEnd bs endOff b (+ cur 1))))
        ((= b 60)
         cur)
        ((= b 102)
         (if (stringStartsWith? (optionOr (stringSlice text cur endOff) "") "function")
           (let [(sp (jsx/skipTrivia bs endOff (+ cur 8)))
                 (c (pairSecond sp))]
             (if (and (< c endOff) (or (= (bytesGet bs c) 42) (= (bytesGet bs c) 60)))
               cur
               (findNextInteresting text bs len endOff (+ cur 1))))
           (findNextInteresting text bs len endOff (+ cur 1))))
        ((= b 114)
         (if (and (>= (+ cur 7) endOff) true)
           (findNextInteresting text bs len endOff (+ cur 1))
           (if (= (optionOr (stringSlice text cur (+ cur 6)) "") "return")
             (let [(sp (jsx/skipTrivia bs endOff (+ cur 6)))
                   (c (pairSecond sp))]
               (if (and (< c endOff) (= (bytesGet bs c) 40))
                 cur
                 (findNextInteresting text bs len endOff (+ cur 1))))
             (findNextInteresting text bs len endOff (+ cur 1)))))
        ((= b 40)
         (mt (tryFindTypedParamsInParen text bs len cur)
           ((some _) cur)
           ((none) (findNextInteresting text bs len endOff (+ cur 1)))))
        (else
         (findNextInteresting text bs len endOff (+ cur 1))))))

fn tokenizeTsxTokensLoop text: String bs: Bytes len: Int64 cur: Int64 endOff: Int64 accToks: (List tr/Token) accMap: (List (Pair (Pair Int64 Int64) tr/Node)) -> (Pair (List tr/Token) (List (Pair (Pair Int64 Int64) tr/Node)))
  (if (>= cur endOff)
    (pair accToks accMap)
    (let [(nextI (findNextInteresting text bs len endOff cur))]
      (if (>= nextI endOff)
        (let [(slice (optionOr (stringSlice text cur endOff) ""))
              (subToks (lx/tokenize slice))
              (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
              (allToks (listAppend accToks shifted))]
          (pair allToks accMap))
        (let [(b (bytesGet bs nextI))]
          (cond
            ((= b 102)
             (let [(fnOpt (tryParseGenericFunctionExpr text bs endOff nextI))]
               (mt fnOpt
                 ((some fnPair)
                  (let [(fnNode (pairFirst fnPair))
                        (pEnd (pairSecond fnPair))
                        (beforeSlice (optionOr (stringSlice text cur nextI) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (identTok (tr/makeToken "ident" nextI pEnd))
                        (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                        (newMap (cons (pair (pair nextI pEnd) fnNode) accMap))]
                    (tokenizeTsxTokensLoop text bs len pEnd endOff allToks newMap)))
                 ((none)
                  (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 8)) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (allToks (listAppend accToks shifted))]
                    (tokenizeTsxTokensLoop text bs len (+ nextI 8) endOff allToks accMap))))))
            ((= b 114)
             (let [(plainOpt (tryFindPlainTextInParen text bs endOff nextI))]
               (mt plainOpt
                 ((some plainPair)
                  (let [(span (pairFirst plainPair))
                        (pStart (pairFirst span))
                        (pEnd (pairSecond span))
                        (plainNode (pairSecond plainPair))
                        (beforeSlice (optionOr (stringSlice text cur pStart) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (identTok (tr/makeToken "ident" pStart pEnd))
                        (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                        (newMap (cons plainPair accMap))]
                    (tokenizeTsxTokensLoop text bs len pEnd endOff allToks newMap)))
                 ((none)
                  (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 6)) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (allToks (listAppend accToks shifted))]
                    (tokenizeTsxTokensLoop text bs len (+ nextI 6) endOff allToks accMap))))))
            ((= b 40)
             (let [(parenOpt (tryFindTypedParamsInParen text bs len nextI))]
               (mt parenOpt
                 ((some parenPair)
                  (let [(span (pairFirst parenPair))
                        (pStart (pairFirst span))
                        (pEnd (pairSecond span))
                        (parenNode (pairSecond parenPair))
                        (beforeSlice (optionOr (stringSlice text cur pStart) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (identTok (tr/makeToken "ident" pStart pEnd))
                        (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                        (newMap (cons parenPair accMap))]
                    (tokenizeTsxTokensLoop text bs len pEnd endOff allToks newMap)))
                 ((none)
                  (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 1)) ""))
                        (subToks (lx/tokenize beforeSlice))
                        (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                        (allToks (listAppend accToks shifted))]
                    (tokenizeTsxTokensLoop text bs len (+ nextI 1) endOff allToks accMap))))))
            (else
             (let [(arrowOpt (tryParseGenericArrow text bs len nextI))]
               (mt arrowOpt
                 ((some arrowPair)
                  (let [(arrowNode (pairFirst arrowPair))
                        (nextC (pairSecond arrowPair))]
                    (if (<= nextC endOff)
                      (let [(beforeSlice (optionOr (stringSlice text cur nextI) ""))
                            (subToks (lx/tokenize beforeSlice))
                            (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                            (identTok (tr/makeToken "ident" nextI nextC))
                            (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                            (newMap (cons (pair (pair nextI nextC) arrowNode) accMap))]
                        (tokenizeTsxTokensLoop text bs len nextC endOff allToks newMap))
                      (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 1)) ""))
                            (subToks (lx/tokenize beforeSlice))
                            (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                            (allToks (listAppend accToks shifted))]
                        (tokenizeTsxTokensLoop text bs len (+ nextI 1) endOff allToks accMap)))))
                 ((none)
                  (let [(elemRes (jsx/parseJsxElementOrFragWithTagParser text bs len nextI parseTsxTagName))]
                    (mt elemRes
                      ((ok resPair)
                       (let [(elemNode (pairFirst resPair))
                             (nextC (pairSecond resPair))]
                         (if (<= nextC endOff)
                           (let [(beforeSlice (optionOr (stringSlice text cur nextI) ""))
                                 (subToks (lx/tokenize beforeSlice))
                                 (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                                 (identTok (tr/makeToken "ident" nextI nextC))
                                 (allToks (listAppend (listAppend accToks shifted) (list identTok)))
                                 (newMap (cons (pair (pair nextI nextC) elemNode) accMap))]
                             (tokenizeTsxTokensLoop text bs len nextC endOff allToks newMap))
                           (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 1)) ""))
                                 (subToks (lx/tokenize beforeSlice))
                                 (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                                 (allToks (listAppend accToks shifted))]
                             (tokenizeTsxTokensLoop text bs len (+ nextI 1) endOff allToks accMap)))))
                      ((err _)
                       (let [(beforeSlice (optionOr (stringSlice text cur (+ nextI 1)) ""))
                             (subToks (lx/tokenize beforeSlice))
                             (shifted (map (fn [(t tr/Token)] -> tr/Token (tr/makeToken t.kind (+ t.start cur) (+ t.end cur))) subToks))
                             (allToks (listAppend accToks shifted))]
                         (tokenizeTsxTokensLoop text bs len (+ nextI 1) endOff allToks accMap))))))))))))))

fn parseTsxModuleTokens toks: (List tr/Token) text: String jsxMap: (List (Pair (Pair Int64 Int64) tr/Node)) -> (Result tr/Node String)
  (let [(modRes (tsMod/parseTsModuleTokens toks text))]
    (mt modRes
      ((err msg) (err msg))
      ((ok root)
       (let [(restoredRoot (substituteJsxNodes root jsxMap))
             (finalRoot (rejectTypeAssertions restoredRoot))]
         (mt (tsMod/firstErrorOffset (tr/nodeChildren finalRoot))
           ((some off)
            (err (str "Parse error at offset " (stringFromInt64 off))))
           ((none)
            (mt (tr/checkTiling finalRoot (stringLength text))
              ((ok _) (ok finalRoot))
              ((err msg) (err msg)))))))))

fn parseTsxModule text: String -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (tokenizeTsxTokensLoop text bs len 0 len (list) (list)))
        (rawToks (pairFirst res))
        (jsxMap (pairSecond res))
        (toks (tsMod/splitTypeTokens rawToks))]
    (parseTsxModuleTokens toks text jsxMap))

fn unwrapTsxNode node: tr/Node -> tr/Node
  (let [(k (tr/nodeKind node))]
    (if (= k "module")
      (let [(childNodes (jsx/findChildNodes (tr/nodeChildren node)))]
        (if (= (listLength childNodes) 1)
          (unwrapTsxNode (optionOr (listHead childNodes) node))
          node))
      (if (= k "exprStmt")
        (let [(childNodes (jsx/findChildNodes (tr/nodeChildren node)))]
          (if (= (listLength childNodes) 1)
            (unwrapTsxNode (optionOr (listHead childNodes) node))
            node))
        node)))

fn parseTsx text: String -> (Result tr/Node String)
  (parseTsxModule text)

fn parse text: String -> (Result tr/Node String)
  (parseTsx text)

fn parseTsxExpr toks: (List tr/Token) text: String minPrec: Int64 -> decl/ParseResult
  (let [(res (ts/parseTsExpr toks text minPrec))]
    (decl/ParseResult :node (rejectTypeAssertions res.node) :rest res.rest))

fn parseTsxElement text: String start: Int64 -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (jsx/parseJsxElementWithTagParser text bs len start parseTsxTagName))]
    (mt res
      ((ok p) (ok (pairFirst p)))
      ((err e) (err e))))

fn parseTsxFragment text: String start: Int64 -> (Result tr/Node String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))
        (res (jsx/parseJsxFragmentFrom text bs len start))]
    (mt res
      ((ok p) (ok (pairFirst p)))
      ((err e) (err e))))

fn isTsxNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (tsMod/isModuleNode node)
    (or (decl/isDeclNode node)
    (or (ts/isTypeNode node)
        (jsx/isJsxNode node)))))

fn tsxNodeKind node: tr/Node -> String
  (tr/nodeKind (unwrapTsxNode node))

fn tsxToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))]
    (cond
      ((jsx/isJsxNode node) (jsx/jsxToSExpr node text))
      ((decl/isDeclNode node) (decl/declToSExpr node text))
      (else (tr/nodeKind node))))
