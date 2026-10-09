(module asl-syntax/js/expr
  :x [parse
      parseExpr
      parseText
      parseTokens
      exprToSExpr
      isExpressionNode
      expressionKind
      parseFunctionExpr
      parseDefaultBlock
      parseParameters
      findFnName]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)])

(schema ParseResult
  (:f node tr/Node)
  (:f rest (List tr/Token)))

(schema ElementsResult
  (:f elements (List tr/TreeElement))
  (:f rest (List tr/Token)))

fn tokenSlice tok: tr/Token text: String -> String
  (let [(st (tr/tokenStart tok))
        (en (tr/tokenEnd tok))]
    (if (or (< st 0) (> en (stringLength text)))
      ""
      (optionOr (stringSlice text st en) "")))

fn isTriviaTok tok: tr/Token -> Bool
  (let [(k (tr/tokenKind tok))]
    (or (= k "whitespace")
    (or (= k "newline")
        (= k "comment"))))

fn skipTriviaLoop toks: (List tr/Token) acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List tr/Token))
  (if (listEmpty? toks)
    (pair (listReverse acc) toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (isTriviaTok hd)
        (skipTriviaLoop tl (cons (tr/elemToken hd) acc))
        (pair (listReverse acc) toks))))

fn skipTrivia toks: (List tr/Token) -> (Pair (List tr/TreeElement) (List tr/Token))
  (skipTriviaLoop toks (list))

fn expectClose rem: (List tr/Token) kind: String endPos: Int64 -> (Pair tr/Token (List tr/Token))
  (if (listEmpty? rem)
    (pair (tr/makeToken "error" endPos endPos) rem)
    (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
      (if (= (tr/tokenKind hd) kind)
        (pair hd (optionOr (listTail rem) (list)))
        (pair (tr/makeToken "error" endPos endPos) rem))))

fn hasNewlineElements elems: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode _) (hasNewlineElements tl text))
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "newline")
           true
           (if (= (tr/tokenKind tok) "comment")
             (let [(sl (tokenSlice tok text))]
               (if (or (stringContains? sl "\n") (stringContains? sl "\r"))
                 true
                 (hasNewlineElements tl text)))
             (hasNewlineElements tl text)))))))

fn precComma -> Int64
  1

fn precAssign -> Int64
  3

fn precCond -> Int64
  4

fn precNullish -> Int64
  5

fn precLogicalOr -> Int64
  6

fn precLogicalAnd -> Int64
  7

fn precBitOr -> Int64
  8

fn precBitXor -> Int64
  9

fn precBitAnd -> Int64
  10

fn precEquality -> Int64
  11

fn precRelational -> Int64
  12

fn precShift -> Int64
  13

fn precAdditive -> Int64
  14

fn precMultiplicative -> Int64
  15

fn precExponentiation -> Int64
  16

fn precUnary -> Int64
  17

fn precPostfix -> Int64
  18

fn precNew -> Int64
  19

fn precCall -> Int64
  20

fn isRightAssociative prec: Int64 -> Bool
  (or (= prec 16)
  (or (= prec 4)
      (= prec 3)))

fn isAssignmentToken kind: String -> Bool
  (or (= kind "assign")
  (or (= kind "plusAssign")
  (or (= kind "minusAssign")
  (or (= kind "starAssign")
  (or (= kind "starStarAssign")
  (or (= kind "slashAssign")
  (or (= kind "percentAssign")
  (or (= kind "shlAssign")
  (or (= kind "shrAssign")
  (or (= kind "shruAssign")
  (or (= kind "ampAssign")
  (or (= kind "caretAssign")
  (or (= kind "pipeAssign")
  (or (= kind "ampAmpAssign")
  (or (= kind "pipePipeAssign")
      (= kind "questionQuestionAssign"))))))))))))))))

fn isValidAssignTarget node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "ident")
    (or (= k "memberExpr")
    (or (= k "parenExpr")
    (or (= k "arrayLiteral")
        (= k "objectLiteral"))))))

fn infixPrecedence tok: tr/Token text: String hasNewlineBefore: Bool -> Int64
  (let [(k (tr/tokenKind tok))]
    (cond
      ((= k "comma") (precComma))
      ((isAssignmentToken k) (precAssign))
      ((= k "question") (precCond))
      ((= k "questionQuestion") (precNullish))
      ((= k "pipePipe") (precLogicalOr))
      ((= k "ampAmp") (precLogicalAnd))
      ((= k "pipe") (precBitOr))
      ((= k "caret") (precBitXor))
      ((= k "amp") (precBitAnd))
      ((or (= k "eqEq") (or (= k "bangEq") (or (= k "eqEqEq") (= k "bangEqEq")))) (precEquality))
      ((or (= k "lt") (or (= k "lte") (or (= k "gt") (= k "gte")))) (precRelational))
      ((and (= k "keyword") (let [(sl (tokenSlice tok text))] (or (= sl "instanceof") (= sl "in")))) (precRelational))
      ((or (= k "shl") (or (= k "shr") (= k "shru"))) (precShift))
      ((or (= k "plus") (= k "minus")) (precAdditive))
      ((or (= k "star") (or (= k "slash") (= k "percent"))) (precMultiplicative))
      ((= k "starStar") (precExponentiation))
      ((and (or (= k "plusPlus") (= k "minusMinus")) (not hasNewlineBefore)) (precPostfix))
      ((or (= k "dot") (or (= k "questionDot") (or (= k "lbracket") (= k "lparen")))) (precCall))
      ((or (= k "templateNoSub") (= k "templateHead")) (precCall))
      (else 0)))

fn isPrefixOp tok: tr/Token text: String -> Bool
  (let [(k (tr/tokenKind tok))]
    (or (= k "plus")
    (or (= k "minus")
    (or (= k "bang")
    (or (= k "tilde")
    (or (= k "plusPlus")
    (or (= k "minusMinus")
        (and (= k "keyword")
             (let [(sl (tokenSlice tok text))]
               (or (= sl "typeof")
               (or (= sl "void")
               (or (= sl "delete")
                   (= sl "await")))))))))))))

fn parseElementsListUntil toks: (List tr/Token) text: String closeKind: String acc: (List tr/TreeElement) -> ElementsResult
  (if (listEmpty? toks)
    (let [(exp (expectClose toks closeKind (stringLength text)))
          (tok (pairFirst exp))]
      (ElementsResult :elements (listReverse (cons (tr/elemToken tok) acc)) :rest (pairSecond exp)))
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))]
      (if (listEmpty? rem)
        (let [(exp (expectClose rem closeKind (stringLength text)))
              (tok (pairFirst exp))]
          (ElementsResult :elements (listReverse (cons (tr/elemToken tok) (listAppend (listReverse triv) acc))) :rest (pairSecond exp)))
        (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (tl (optionOr (listTail rem) (list)))
              (k (tr/tokenKind hd))]
          (if (= k closeKind)
            (let [(accWithTriv (listAppend (listReverse triv) acc))
                  (finalAcc (cons (tr/elemToken hd) accWithTriv))]
              (ElementsResult :elements (listReverse finalAcc) :rest tl))
            (if (= k "comma")
              (let [(accWithTriv (listAppend (listReverse triv) acc))
                    (newAcc (cons (tr/elemToken hd) accWithTriv))]
                (parseElementsListUntil tl text closeKind newAcc))
              (if (= k "ellipsis")
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (sp2 (skipTrivia tl))
                      (triv2 (pairFirst sp2))
                      (subRes (parseExprCore (pairSecond sp2) text 3))
                      (subNode subRes.node)
                      (sprKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode subNode)))))
                      (sprNode (tr/makeNode "spreadExpr" (tr/tokenStart hd) (tr/nodeEnd subNode) sprKids))
                      (newAcc (cons (tr/elemNode sprNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc))
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (subRes (parseExprCore rem text 3))
                      (subNode subRes.node)
                      (newAcc (cons (tr/elemNode subNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc)))))))))

fn parseObjectPropertyList toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (if (listEmpty? toks)
    (let [(exp (expectClose toks "rbrace" (stringLength text)))
          (tok (pairFirst exp))]
      (ElementsResult :elements (listReverse (cons (tr/elemToken tok) acc)) :rest (pairSecond exp)))
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))]
      (if (listEmpty? rem)
        (let [(exp (expectClose rem "rbrace" (stringLength text)))
              (tok (pairFirst exp))]
          (ElementsResult :elements (listReverse (cons (tr/elemToken tok) (listAppend (listReverse triv) acc))) :rest (pairSecond exp)))
        (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (tl (optionOr (listTail rem) (list)))
              (k (tr/tokenKind hd))]
          (if (= k "rbrace")
            (let [(accWithTriv (listAppend (listReverse triv) acc))
                  (finalAcc (cons (tr/elemToken hd) accWithTriv))]
              (ElementsResult :elements (listReverse finalAcc) :rest tl))
            (if (= k "comma")
              (let [(accWithTriv (listAppend (listReverse triv) acc))
                    (newAcc (cons (tr/elemToken hd) accWithTriv))]
                (parseObjectPropertyList tl text newAcc))
              (if (= k "ellipsis")
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (sp2 (skipTrivia tl))
                      (triv2 (pairFirst sp2))
                      (subRes (parseExprCore (pairSecond sp2) text 3))
                      (subNode subRes.node)
                      (sprKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode subNode)))))
                      (sprNode (tr/makeNode "spreadProperty" (tr/tokenStart hd) (tr/nodeEnd subNode) sprKids))
                      (newAcc (cons (tr/elemNode sprNode) accWithTriv))]
                  (parseObjectPropertyList subRes.rest text newAcc))
                (if (= k "lbracket")
                  (let [(accWithTriv (listAppend (listReverse triv) acc))
                        (spComp (skipTrivia tl))
                        (trivComp (pairFirst spComp))
                        (keyRes (parseExprCore (pairSecond spComp) text 0))
                        (keyNode keyRes.node)
                        (spRbr (skipTrivia keyRes.rest))
                        (trivRbr (pairFirst spRbr))
                        (expRbr (expectClose (pairSecond spRbr) "rbracket" (tr/nodeEnd keyNode)))
                        (rbrTok (pairFirst expRbr))
                        (tlRbr (pairSecond expRbr))
                        (spColon (skipTrivia tlRbr))
                        (trivColon (pairFirst spColon))
                        (expColon (expectClose (pairSecond spColon) "colon" (tr/tokenEnd rbrTok)))
                        (colonTok (pairFirst expColon))
                        (tlColon (pairSecond expColon))
                        (spVal (skipTrivia tlColon))
                        (trivVal (pairFirst spVal))
                        (valRes (parseExprCore (pairSecond spVal) text 3))
                        (valNode valRes.node)
                        (propKids (listAppend (cons (tr/elemToken hd) trivComp)
                                    (cons (tr/elemNode keyNode)
                                      (listAppend trivRbr
                                        (cons (tr/elemToken rbrTok)
                                          (listAppend trivColon
                                            (cons (tr/elemToken colonTok)
                                              (listAppend trivVal (list (tr/elemNode valNode))))))))))
                        (propNode (tr/makeNode "property" (tr/tokenStart hd) (tr/nodeEnd valNode) propKids))
                        (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                    (parseObjectPropertyList valRes.rest text newAcc))
                  (let [(accWithTriv (listAppend (listReverse triv) acc))
                        (keyTok hd)
                        (spColon (skipTrivia tl))
                        (trivColon (pairFirst spColon))
                        (remColon (pairSecond spColon))]
                    (if (and (not (listEmpty? remColon)) (= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon"))
                      (let [(colonTok (optionOr (listHead remColon) (tr/makeToken "" 0 0)))
                            (tlColon (optionOr (listTail remColon) (list)))
                            (spVal (skipTrivia tlColon))
                            (trivVal (pairFirst spVal))
                            (valRes (parseExprCore (pairSecond spVal) text 3))
                            (valNode valRes.node)
                            (propKids (cons (tr/elemToken keyTok)
                                        (listAppend trivColon
                                          (cons (tr/elemToken colonTok)
                                            (listAppend trivVal (list (tr/elemNode valNode)))))))
                            (propNode (tr/makeNode "property" (tr/tokenStart keyTok) (tr/nodeEnd valNode) propKids))
                            (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                        (parseObjectPropertyList valRes.rest text newAcc))
                      (let [(shorthandNode (tr/makeNode "shorthandProperty" (tr/tokenStart keyTok) (tr/tokenEnd keyTok) (list (tr/elemToken keyTok))))
                            (newAcc (cons (tr/elemNode shorthandNode) accWithTriv))]
                        (parseObjectPropertyList tl text newAcc))))))))))))

fn parseTemplateSegments toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (if (listEmpty? toks)
    (let [(exp (expectClose toks "templateTail" (stringLength text)))
          (tok (pairFirst exp))]
      (ElementsResult :elements (listReverse (cons (tr/elemToken tok) acc)) :rest (pairSecond exp)))
    (let [(subRes (parseExprCore toks text 0))
          (subNode subRes.node)
          (remToks subRes.rest)]
      (if (listEmpty? remToks)
        (let [(exp (expectClose remToks "templateTail" (tr/nodeEnd subNode)))
              (tok (pairFirst exp))]
          (ElementsResult :elements (listReverse (cons (tr/elemToken tok) (cons (tr/elemNode subNode) acc))) :rest (pairSecond exp)))
        (let [(nextTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
              (tlToks (optionOr (listTail remToks) (list)))
              (k (tr/tokenKind nextTok))]
          (if (= k "templateTail")
            (let [(newAcc (cons (tr/elemToken nextTok) (cons (tr/elemNode subNode) acc)))]
              (ElementsResult :elements (listReverse newAcc) :rest tlToks))
            (if (= k "templateMiddle")
              (let [(newAcc (cons (tr/elemToken nextTok) (cons (tr/elemNode subNode) acc)))]
                (parseTemplateSegments tlToks text newAcc))
              (let [(exp (expectClose remToks "templateTail" (tr/nodeEnd subNode)))
                    (tok (pairFirst exp))
                    (newAcc (cons (tr/elemToken tok) (cons (tr/elemNode subNode) acc)))]
                (ElementsResult :elements (listReverse newAcc) :rest remToks))))))))


fn parseMemberLoop left: tr/Node toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (cond
          ((= k "dot")
           (let [(spProp (skipTrivia tl))
                 (trivProp (pairFirst spProp))
                 (remProp (pairSecond spProp))
                 (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                 (tlProp (optionOr (listTail remProp) (list)))
                 (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                 (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
             (parseMemberLoop newLeft tlProp text)))
          ((= k "lbracket")
           (let [(spIdx (skipTrivia tl))
                 (trivIdx (pairFirst spIdx))
                 (idxRes (parseExprCore (pairSecond spIdx) text 0))
                 (idxNode idxRes.node)
                 (spClose (skipTrivia idxRes.rest))
                 (trivClose (pairFirst spClose))
                 (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                 (closeTok (pairFirst expClose))
                 (tlClose (pairSecond expClose))
                 (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                 (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
             (parseMemberLoop newLeft tlClose text)))
          ((or (= k "templateNoSub") (= k "templateHead"))
           (let [(spT (skipTrivia rem))
                 (tmplRes (parsePrefix (pairSecond spT) text))
                 (tmplNode tmplRes.node)
                 (kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemNode tmplNode)))))
                 (newLeft (tr/makeNode "taggedTemplate" (tr/nodeStart left) (tr/nodeEnd tmplNode) kids))]
             (parseMemberLoop newLeft tmplRes.rest text)))
          (else
           (ParseResult :node left :rest toks))))))

fn parseMemberExpr toks: (List tr/Token) text: String -> ParseResult
  (let [(prefixRes (parsePrefix toks text))]
    (parseMemberLoop prefixRes.node prefixRes.rest text))

fn findFnName toks: (List tr/Token) text: String -> String
  (if (listEmpty? toks)
    ""
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (sl (tokenSlice hd text))]
      (if (or (= sl "async") (or (= sl "function") (= k "star")))
        (findFnName tl text)
        (if (= k "ident")
          sl
          ""))))

fn parseParametersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (if (listEmpty? toks)
    (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
          (endPos (tr/elementEnd lastElem))
          (errTok (tr/makeToken "error" endPos endPos))]
      (ElementsResult :elements (listAppend acc (list (tr/elemToken errTok))) :rest toks))
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))]
      (if (listEmpty? rem)
        (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
              (endPos (tr/elementEnd lastElem))
              (errTok (tr/makeToken "error" endPos endPos))]
          (ElementsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken errTok)))) :rest rem))
        (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (tl (optionOr (listTail rem) (list)))
              (k (tr/tokenKind hd))]
          (if (= k "rparen")
            (ElementsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken hd)))) :rest tl)
            (if (= k "comma")
              (parseParametersLoop tl text (listAppend acc (listAppend triv (list (tr/elemToken hd)))))
              (if (= k "ellipsis")
                (let [(accWithEll (listAppend acc (listAppend triv (list (tr/elemToken hd)))))
                      (sp2 (skipTrivia tl))
                      (triv2 (pairFirst sp2))
                      (rem2 (pairSecond sp2))
                      (argRes (parseExprCore (pairSecond sp2) text 1))
                      (argNode argRes.node)
                      (restKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode argNode)))))
                      (restNode (tr/makeNode "restElement" (tr/tokenStart hd) (tr/nodeEnd argNode) restKids))
                      (newAcc (listAppend acc (listAppend triv (list (tr/elemNode restNode)))))]
                  (parseParametersLoop argRes.rest text newAcc))
                (let [(paramRes (parseExprCore rem text 1))
                      (paramNode paramRes.node)
                      (newAcc (listAppend acc (listAppend triv (list (tr/elemNode paramNode)))))]
                  (parseParametersLoop paramRes.rest text newAcc)))))))))

fn parseParameters toks: (List tr/Token) text: String -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (!= k "lparen")
        (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest tl)
        (let [(res (parseParametersLoop tl text (list (tr/elemToken hd))))
              (elems res.elements)
              (rem res.rest)
              (lastElem (optionOr (listLast elems) (tr/elemToken hd)))
              (endPos (tr/elementEnd lastElem))
              (node (tr/makeNode "parameters" (tr/tokenStart hd) endPos elems))]
          (ParseResult :node node :rest rem)))))

fn parseBlockTokensLoop toks: (List tr/Token) depth: Int64 acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List tr/Token))
  (if (listEmpty? toks)
    (if (> depth 0)
      (let [(lastElem (optionOr (listHead acc) (tr/elemToken (tr/makeToken "" 0 0))))
            (endPos (tr/elementEnd lastElem))
            (errTok (tr/makeToken "error" endPos endPos))]
        (pair (listReverse (cons (tr/elemToken errTok) acc)) toks))
      (pair (listReverse acc) toks))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((= k "lbrace")
         (parseBlockTokensLoop tl (+ depth 1) (cons (tr/elemToken hd) acc)))
        ((= k "rbrace")
         (if (<= depth 1)
           (pair (listReverse (cons (tr/elemToken hd) acc)) tl)
           (parseBlockTokensLoop tl (- depth 1) (cons (tr/elemToken hd) acc))))
        (else
         (parseBlockTokensLoop tl depth (cons (tr/elemToken hd) acc))))))

fn parseDefaultBlock toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (!= k "lbrace")
        (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest tl)
        (let [(res (parseBlockTokensLoop tl 1 (list (tr/elemToken hd))))
              (elems (pairFirst res))
              (rem (pairSecond res))
              (lastElem (optionOr (listLast elems) (tr/elemToken hd)))
              (endOffset (tr/elementEnd lastElem))
              (hasErr (listAny? (fn [(e tr/TreeElement)] -> Bool
                                  (mt e
                                    ((tr/elemToken t) (= (tr/tokenKind t) "error"))
                                    ((tr/elemNode n) (= (tr/nodeKind n) "error"))))
                                elems))
              (node (if hasErr
                      (tr/makeErrorNode (tr/tokenStart hd) endOffset elems)
                      (tr/makeNode "block" (tr/tokenStart hd) endOffset elems)))]
          (ParseResult :node node :rest rem)))))

fn parseFunctionExpr prefixElems: (List tr/TreeElement) fnTok: tr/Token tl: (List tr/Token) text: String isAsync: Bool inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(spStar (skipTrivia tl))
        (trivStar (pairFirst spStar))
        (remStar (pairSecond spStar))
        (isGen (and (not (listEmpty? remStar)) (= (tr/tokenKind (optionOr (listHead remStar) (tr/makeToken "" 0 0))) "star")))
        (starTokOpt (if isGen (some (optionOr (listHead remStar) (tr/makeToken "" 0 0))) (none)))
        (tlStar (if isGen (optionOr (listTail remStar) (list)) remStar))
        (spName (if isGen (skipTrivia tlStar) spStar))
        (trivName (pairFirst spName))
        (remName (pairSecond spName))
        (hasName (and (not (listEmpty? remName)) (= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident")))
        (nameTokOpt (if hasName (some (optionOr (listHead remName) (tr/makeToken "" 0 0))) (none)))
        (tlName (if hasName (optionOr (listTail remName) (list)) remName))
        (spLP (skipTrivia tlName))
        (trivLP (if hasName (pairFirst spLP) trivName))
        (remLP (if hasName (pairSecond spLP) remName))
        (paramsRes (parseParameters remLP text))
        (paramsNode paramsRes.node)
        (remParams paramsRes.rest)
        (spBody (skipTrivia remParams))
        (trivBody (pairFirst spBody))
        (remBody (pairSecond spBody))
        (bodyRes (bodyParser remBody text isAsync isGen))
        (bodyNode bodyRes.node)
        (baseKids (listAppend prefixElems (list (tr/elemToken fnTok))))
        (starKids (if isGen (listAppend baseKids (listAppend trivStar (list (tr/elemToken (optionOr starTokOpt fnTok))))) baseKids))
        (nameKids (if hasName (listAppend starKids (listAppend trivName (list (tr/elemToken (optionOr nameTokOpt fnTok))))) starKids))
        (allKids (listAppend nameKids
                   (listAppend trivLP
                     (cons (tr/elemNode paramsNode)
                       (listAppend trivBody
                         (list (tr/elemNode bodyNode)))))))
        (firstElem (optionOr (listHead allKids) (tr/elemToken fnTok)))
        (startPos (tr/elementStart firstElem))
        (endPos (tr/nodeEnd bodyNode))
        (exprKind (cond
                    ((and isAsync isGen) "asyncGeneratorExpr")
                    (isAsync "asyncFunctionExpr")
                    (isGen "generatorExpr")
                    (else "functionExpr")))
        (node (tr/makeNode exprKind startPos endPos allKids))]
    (ParseResult :node node :rest bodyRes.rest))

fn parsePrefix toks: (List tr/Token) text: String -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((or (= k "number") (or (= k "bigInt") (or (= k "string") (or (= k "boolean") (or (= k "null") (= k "regex"))))))
         (let [(node (tr/makeNode "literal" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= (tokenSlice hd text) "function"))
         (parseFunctionExpr (list) hd tl text false false false parseDefaultBlock))
        ((and (or (= k "ident") (= k "keyword")) (= (tokenSlice hd text) "async"))
         (let [(spA (skipTrivia tl))
               (trivA (pairFirst spA))
               (remA (pairSecond spA))]
           (if (and (not (hasNewlineElements trivA text))
                    (and (not (listEmpty? remA))
                         (= (tokenSlice (optionOr (listHead remA) (tr/makeToken "" 0 0)) text) "function")))
             (let [(fnTok (optionOr (listHead remA) (tr/makeToken "" 0 0)))
                   (tlFn (optionOr (listTail remA) (list)))
                   (pref (cons (tr/elemToken hd) trivA))]
               (parseFunctionExpr pref fnTok tlFn text true false false parseDefaultBlock))
             (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
               (ParseResult :node node :rest tl)))))
        ((= k "ident")
         (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((= k "privateIdent")
         (let [(node (tr/makeNode "privateIdent" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= (tokenSlice hd text) "this"))
         (let [(node (tr/makeNode "this" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= (tokenSlice hd text) "super"))
         (let [(node (tr/makeNode "super" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= (tokenSlice hd text) "import"))
         (let [(sp (skipTrivia tl))
               (triv (pairFirst sp))
               (rem (pairSecond sp))]
           (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "dot"))
             (let [(dotTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
                   (sp2 (skipTrivia (optionOr (listTail rem) (list))))
                   (triv2 (pairFirst sp2))
                   (metaTok (optionOr (listHead (pairSecond sp2)) (tr/makeToken "" 0 0)))
                   (tl2 (optionOr (listTail (pairSecond sp2)) (list)))
                   (kids (cons (tr/elemToken hd) (listAppend triv (cons (tr/elemToken dotTok) (listAppend triv2 (list (tr/elemToken metaTok)))))))
                   (node (tr/makeNode "metaProperty" (tr/tokenStart hd) (tr/tokenEnd metaTok) kids))]
               (ParseResult :node node :rest tl2))
             (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
               (ParseResult :node node :rest tl)))))
        ((and (= k "keyword") (= (tokenSlice hd text) "new"))
         (let [(sp (skipTrivia tl))
               (triv (pairFirst sp))
               (rem (pairSecond sp))]
           (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "dot"))
             (let [(dotTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
                   (sp2 (skipTrivia (optionOr (listTail rem) (list))))
                   (triv2 (pairFirst sp2))
                   (targetTok (optionOr (listHead (pairSecond sp2)) (tr/makeToken "" 0 0)))
                   (tl2 (optionOr (listTail (pairSecond sp2)) (list)))
                   (kids (cons (tr/elemToken hd) (listAppend triv (cons (tr/elemToken dotTok) (listAppend triv2 (list (tr/elemToken targetTok)))))))
                   (node (tr/makeNode "metaProperty" (tr/tokenStart hd) (tr/tokenEnd targetTok) kids))]
               (ParseResult :node node :rest tl2))
             (if (listEmpty? rem)
               (let [(errTok (tr/makeToken "error" (tr/tokenEnd hd) (tr/tokenEnd hd)))
                     (kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemToken errTok)))))
                     (node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
                 (ParseResult :node node :rest rem))
               (let [(calleeRes (parseMemberExpr rem text))
                     (calleeNode calleeRes.node)
                     (remCallee calleeRes.rest)]
                 (if (tr/isErrorNode calleeNode)
                   (let [(kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode calleeNode)))))
                         (node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd calleeNode) kids))]
                     (ParseResult :node node :rest remCallee))
                   (let [(spParen (skipTrivia remCallee))
                         (trivParen (pairFirst spParen))
                         (remParen (pairSecond spParen))]
                     (if (and (not (listEmpty? remParen)) (= (tr/tokenKind (optionOr (listHead remParen) (tr/makeToken "" 0 0))) "lparen"))
                       (let [(lparenTok (optionOr (listHead remParen) (tr/makeToken "" 0 0)))
                             (argsRes (parseElementsListUntil (optionOr (listTail remParen) (list)) text "rparen" (list)))
                             (allArgs (cons (tr/elemToken lparenTok) argsRes.elements))
                             (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd lparenTok) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken lparenTok)))))
                             (kids (cons (tr/elemToken hd) (listAppend triv (cons (tr/elemNode calleeNode) (listAppend trivParen allArgs)))))
                             (newNode (tr/makeNode "newExpr" (tr/tokenStart hd) closeEnd kids))]
                         (parseMemberLoop newNode argsRes.rest text))
                       (let [(kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode calleeNode)))))
                             (node (tr/makeNode "newExpr" (tr/tokenStart hd) (tr/nodeEnd calleeNode) kids))]
                         (ParseResult :node node :rest remCallee))))))))))
        ((isPrefixOp hd text)
         (let [(sp (skipTrivia tl))
               (triv (pairFirst sp))
               (argRes (parseExprCore (pairSecond sp) text (precUnary)))
               (argNode argRes.node)
               (isUpd (or (= k "plusPlus") (= k "minusMinus")))
               (kind (if isUpd "updateExpr" "unaryExpr"))
               (kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode argNode)))))]
           (if (tr/isErrorNode argNode)
             (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd argNode) kids) :rest argRes.rest)
             (let [(node (tr/makeNode kind (tr/tokenStart hd) (tr/nodeEnd argNode) kids))]
               (ParseResult :node node :rest argRes.rest)))))
        ((= k "lparen")
         (let [(sp (skipTrivia tl))
               (triv (pairFirst sp))
               (exprRes (parseExprCore (pairSecond sp) text 0))
               (innerNode exprRes.node)
               (spClose (skipTrivia exprRes.rest))
               (trivClose (pairFirst spClose))
               (expClose (expectClose (pairSecond spClose) "rparen" (tr/nodeEnd innerNode)))
               (closeTok (pairFirst expClose))
               (tlClose (pairSecond expClose))
               (kids (cons (tr/elemToken hd) (listAppend triv (cons (tr/elemNode innerNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))]
           (if (tr/isErrorToken closeTok)
             (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd innerNode) kids) :rest tlClose)
             (ParseResult :node (tr/makeNode "parenExpr" (tr/tokenStart hd) (tr/tokenEnd closeTok) kids) :rest tlClose))))
        ((= k "lbracket")
         (let [(elemsRes (parseElementsListUntil tl text "rbracket" (list)))
               (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) elemsRes.elements))
               (node (tr/makeNode "arrayLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest elemsRes.rest)))
        ((= k "lbrace")
         (let [(elemsRes (parseObjectPropertyList tl text (list)))
               (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) elemsRes.elements))
               (node (tr/makeNode "objectLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest elemsRes.rest)))
        ((= k "templateNoSub")
         (let [(node (tr/makeNode "templateLiteral" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((= k "templateHead")
         (let [(segsRes (parseTemplateSegments tl text (list)))
               (closeEnd (if (listEmpty? segsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast segsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) segsRes.elements))
               (node (tr/makeNode "templateLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest segsRes.rest)))
        (else
         (let [(node (tr/makeNode "error" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl))))))

fn parsePrattLoop left: tr/Node toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (hasNl (hasNewlineElements triv text))
            (prec (infixPrecedence hd text hasNl))]
        (if (<= prec minPrec)
          (ParseResult :node left :rest toks)
          (let [(k (tr/tokenKind hd))]
            (cond
              ((or (= k "plusPlus") (= k "minusMinus"))
               (let [(kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemToken hd)))))
                     (newLeft (tr/makeNode "updateExpr" (tr/nodeStart left) (tr/tokenEnd hd) kids))]
                 (parsePrattLoop newLeft tl text minPrec)))
              ((= k "dot")
               (let [(spProp (skipTrivia tl))
                     (trivProp (pairFirst spProp))
                     (remProp (pairSecond spProp))
                     (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                     (tlProp (optionOr (listTail remProp) (list)))
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                     (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
                 (parsePrattLoop newLeft tlProp text minPrec)))
              ((= k "questionDot")
               (let [(spProp (skipTrivia tl))
                     (trivProp (pairFirst spProp))
                     (remProp (pairSecond spProp))
                     (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                     (propKind (tr/tokenKind propTok))]
                 (if (= propKind "lbracket")
                   (let [(spIdx (skipTrivia (optionOr (listTail remProp) (list))))
                         (trivIdx (pairFirst spIdx))
                         (idxRes (parseExprCore (pairSecond spIdx) text 0))
                         (idxNode idxRes.node)
                         (spClose (skipTrivia idxRes.rest))
                         (trivClose (pairFirst spClose))
                         (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                         (closeTok (pairFirst expClose))
                         (tlClose (pairSecond expClose))
                         (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (cons (tr/elemToken propTok) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))))
                         (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
                     (parsePrattLoop newLeft tlClose text minPrec))
                   (if (= propKind "lparen")
                     (let [(argsRes (parseElementsListUntil (optionOr (listTail remProp) (list)) text "rparen" (list)))
                           (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd propTok) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken propTok)))))
                           (allArgs (cons (tr/elemToken propTok) argsRes.elements))
                           (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp allArgs)))))
                           (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) closeEnd kids))]
                       (parsePrattLoop newLeft argsRes.rest text minPrec))
                     (if (or (= propKind "number") (= propKind "bigInt"))
                       (let [(kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                             (node (tr/makeErrorNode (tr/tokenStart propTok) (tr/tokenEnd propTok) kids))]
                         (ParseResult :node node :rest (optionOr (listTail remProp) (list))))
                       (let [(tlProp (optionOr (listTail remProp) (list)))
                             (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                             (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
                         (parsePrattLoop newLeft tlProp text minPrec)))))))
              ((= k "lbracket")
               (let [(spIdx (skipTrivia tl))
                     (trivIdx (pairFirst spIdx))
                     (idxRes (parseExprCore (pairSecond spIdx) text 0))
                     (idxNode idxRes.node)
                     (spClose (skipTrivia idxRes.rest))
                     (trivClose (pairFirst spClose))
                     (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                     (closeTok (pairFirst expClose))
                     (tlClose (pairSecond expClose))
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                     (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
                 (parsePrattLoop newLeft tlClose text minPrec)))
              ((= k "lparen")
               (let [(argsRes (parseElementsListUntil tl text "rparen" (list)))
                     (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken hd)))))
                     (allArgs (cons (tr/elemToken hd) argsRes.elements))
                     (kids (cons (tr/elemNode left) (listAppend triv allArgs)))
                     (newLeft (tr/makeNode "callExpr" (tr/nodeStart left) closeEnd kids))]
                 (parsePrattLoop newLeft argsRes.rest text minPrec)))
              ((or (= k "templateNoSub") (= k "templateHead"))
               (let [(spT (skipTrivia rem))
                     (tmplRes (parsePrefix (pairSecond spT) text))
                     (tmplNode tmplRes.node)
                     (kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemNode tmplNode)))))
                     (newLeft (tr/makeNode "taggedTemplate" (tr/nodeStart left) (tr/nodeEnd tmplNode) kids))]
                 (parsePrattLoop newLeft tmplRes.rest text minPrec)))
              ((= k "question")
               (let [(spCons (skipTrivia tl))
                     (trivCons (pairFirst spCons))
                     (consRes (parseExprCore (pairSecond spCons) text (precAssign)))
                     (consNode consRes.node)
                     (spColon (skipTrivia consRes.rest))
                     (trivColon (pairFirst spColon))
                     (expColon (expectClose (pairSecond spColon) "colon" (tr/nodeEnd consNode)))
                     (colonTok (pairFirst expColon))
                     (tlColon (pairSecond expColon))
                     (spAlt (skipTrivia tlColon))
                     (trivAlt (pairFirst spAlt))
                     (altRes (parseExprCore (pairSecond spAlt) text (- (precCond) 1)))
                     (altNode altRes.node)
                     (kids (cons (tr/elemNode left)
                             (listAppend triv
                               (cons (tr/elemToken hd)
                                 (listAppend trivCons
                                   (cons (tr/elemNode consNode)
                                     (listAppend trivColon
                                       (cons (tr/elemToken colonTok)
                                         (listAppend trivAlt (list (tr/elemNode altNode)))))))))))]
                 (if (tr/isErrorToken colonTok)
                   (if (and (listEmpty? trivCons)
                            (and (= (tr/nodeKind consNode) "literal")
                                 (= (tr/nodeStart consNode) (tr/tokenEnd hd))))
                     (let [(node (tr/makeErrorNode (+ (tr/nodeStart consNode) 1) (tr/nodeEnd consNode) kids))]
                       (ParseResult :node node :rest altRes.rest))
                     (let [(newLeft (tr/makeNode "conditionalExpr" (tr/nodeStart left) (tr/nodeEnd altNode) kids))]
                       (parsePrattLoop newLeft altRes.rest text minPrec)))
                   (let [(newLeft (tr/makeNode "conditionalExpr" (tr/nodeStart left) (tr/nodeEnd altNode) kids))]
                     (parsePrattLoop newLeft altRes.rest text minPrec)))))
              ((= k "comma")
               (let [(spRight (skipTrivia tl))
                     (trivRight (pairFirst spRight))
                     (rightRes (parseExprCore (pairSecond spRight) text (precComma)))
                     (rightNode rightRes.node)
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivRight (list (tr/elemNode rightNode)))))))]
                 (if (tr/isErrorNode rightNode)
                   (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd rightNode) kids))]
                     (ParseResult :node node :rest rightRes.rest))
                   (let [(newLeft (tr/makeNode "seqExpr" (tr/nodeStart left) (tr/nodeEnd rightNode) kids))]
                     (parsePrattLoop newLeft rightRes.rest text minPrec)))))
              ((isAssignmentToken k)
               (let [(spRight (skipTrivia tl))
                     (trivRight (pairFirst spRight))
                     (rightRes (parseExprCore (pairSecond spRight) text (- (precAssign) 1)))
                     (rightNode rightRes.node)
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivRight (list (tr/elemNode rightNode)))))))]
                 (if (tr/isErrorNode rightNode)
                   (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd rightNode) kids))]
                     (ParseResult :node node :rest rightRes.rest))
                   (if (not (isValidAssignTarget left))
                     (let [(node (tr/makeErrorNode (tr/nodeStart left) (tr/nodeEnd rightNode) kids))]
                       (ParseResult :node node :rest rightRes.rest))
                     (let [(newLeft (tr/makeNode "assignExpr" (tr/nodeStart left) (tr/nodeEnd rightNode) kids))]
                       (parsePrattLoop newLeft rightRes.rest text minPrec))))))
              (else
               (let [(isR (isRightAssociative prec))
                     (nextMinPrec (if isR (- prec 1) prec))
                     (spRight (skipTrivia tl))
                     (trivRight (pairFirst spRight))
                     (rightRes (parseExprCore (pairSecond spRight) text nextMinPrec))
                     (rightNode rightRes.node)
                     (isLog (or (= k "ampAmp") (or (= k "pipePipe") (= k "questionQuestion"))))
                     (kind (if isLog "logicalExpr" "binaryExpr"))
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivRight (list (tr/elemNode rightNode)))))))]
                 (if (tr/isErrorNode rightNode)
                   (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd rightNode) kids))]
                     (ParseResult :node node :rest rightRes.rest))
                   (let [(newLeft (tr/makeNode kind (tr/nodeStart left) (tr/nodeEnd rightNode) kids))]
                     (parsePrattLoop newLeft rightRes.rest text minPrec)))))))))))

fn parseExprCore toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (let [(prefixRes (parsePrefix toks text))]
    (parsePrattLoop prefixRes.node prefixRes.rest text minPrec))

fn trailingElementsLoop toks: (List tr/Token) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (listReverse acc)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (trailingElementsLoop tl (cons (tr/elemToken hd) acc))))

fn parseTokens tokens: (List tr/Token) text: String -> tr/Node
  (let [(spLead (skipTrivia tokens))
        (leadTriv (pairFirst spLead))
        (remLead (pairSecond spLead))]
    (if (listEmpty? remLead)
      (tr/makeNode "document" 0 (stringLength text) leadTriv)
      (let [(exprRes (parseExprCore remLead text 0))
            (exprNode exprRes.node)
            (trailElems (trailingElementsLoop exprRes.rest (list)))
            (allKids (listAppend leadTriv (cons (tr/elemNode exprNode) trailElems)))]
        (tr/makeNode "document" 0 (stringLength text) allKids))))

fn parseText text: String -> tr/Node
  (let [(tokens (lx/tokenize text))]
    (parseTokens tokens text))

fn parseExpr text: String -> tr/Node
  (parseText text)

fn findTokenKindOffset elems: (List tr/TreeElement) targetKind: String -> (Option Int64)
  (mt (listHead elems)
    ((none) (none))
    ((some e)
     (mt e
       ((tr/elemToken tok)
        (if (= (tr/tokenKind tok) targetKind)
          (some (tr/tokenStart tok))
          (findTokenKindOffset (optionOr (listTail elems) (list)) targetKind)))
       ((tr/elemNode _)
        (findTokenKindOffset (optionOr (listTail elems) (list)) targetKind)))))

fn nodeOpeningOffset n: tr/Node -> Int64
  (let [(k (tr/nodeKind n))
        (kids (tr/nodeChildren n))]
    (cond
      ((= k "memberExpr")
       (optionOr (findTokenKindOffset kids "lbracket") (tr/nodeStart n)))
      ((or (= k "callExpr") (= k "parenExpr"))
       (optionOr (findTokenKindOffset kids "lparen") (tr/nodeStart n)))
      ((= k "arrayLiteral")
       (optionOr (findTokenKindOffset kids "lbracket") (tr/nodeStart n)))
      ((= k "objectLiteral")
       (optionOr (findTokenKindOffset kids "lbrace") (tr/nodeStart n)))
      ((= k "conditionalExpr")
       (optionOr (findTokenKindOffset kids "question") (tr/nodeStart n)))
      ((= k "optionalChain")
       (optionOr (findTokenKindOffset kids "lbracket")
         (optionOr (findTokenKindOffset kids "lparen")
           (optionOr (findTokenKindOffset kids "questionDot") (tr/nodeStart n)))))
      ((= k "newExpr")
       (optionOr (findTokenKindOffset kids "lparen") (tr/nodeStart n)))
      (else (tr/nodeStart n))))

fn hasDirectErrorToken elems: (List tr/TreeElement) -> Bool
  (mt (listHead elems)
    ((none) false)
    ((some e)
     (mt e
       ((tr/elemToken tok) (if (or (tr/isErrorToken tok) (= tok.kind "error")) true (hasDirectErrorToken (optionOr (listTail elems) (list)))))
       ((tr/elemNode n) (hasDirectErrorToken (optionOr (listTail elems) (list)))))))

fn firstErrorOffset elems: (List tr/TreeElement) -> (Option Int64)
  (mt (listHead elems)
    ((none) (none))
    ((some e)
     (let [(here (mt e
                   ((tr/elemToken tok)
                    (if (or (tr/isErrorToken tok) (= tok.kind "error"))
                      (some tok.start)
                      (none)))
                   ((tr/elemNode n)
                    (if (tr/isErrorNode n)
                      (some n.start)
                      (if (hasDirectErrorToken (tr/nodeChildren n))
                        (some (nodeOpeningOffset n))
                        (firstErrorOffset (tr/nodeChildren n)))))))]
       (if (some? here) here (firstErrorOffset (optionOr (listTail elems) (list)))))))

fn firstTrailingOffset elems: (List tr/TreeElement) seenExpr: Bool -> (Option Int64)
  (mt (listHead elems)
    ((none) (none))
    ((some e)
     (mt e
       ((tr/elemNode n) (firstTrailingOffset (optionOr (listTail elems) (list)) true))
       ((tr/elemToken tok)
        (if (and seenExpr (not (isTriviaTok tok)))
          (some tok.start)
          (firstTrailingOffset (optionOr (listTail elems) (list)) seenExpr))))))

fn parse text: String -> (Result tr/Node String)
  (let [(root (parseText text))]
    (mt (firstErrorOffset (list (tr/elemNode root)))
      ((some off) (err (str "syntax error at offset " (stringFromInt64 off))))
      ((none)
       (mt (firstTrailingOffset (tr/nodeChildren root) false)
         ((some off) (err (str "syntax error at offset " (stringFromInt64 off))))
         ((none) (ok root))))))

fn isExpressionNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (not (or (= k "document") (= k "error"))))

fn expressionKind node: tr/Node -> String
  (tr/nodeKind node)

fn unwrapExpressionNode root: tr/Node -> tr/Node
  (if (= (tr/nodeKind root) "document")
    (let [(kids (tr/nodeChildren root))
          (nodes (filter (fn [(e tr/TreeElement)] -> Bool (mt e ((tr/elemNode _) true) ((tr/elemToken _) false))) kids))]
      (if (listEmpty? nodes)
        root
        (let [(firstElem (optionOr (listHead nodes) (tr/elemNode root)))]
          (mt firstElem
            ((tr/elemNode n) n)
            ((tr/elemToken _) root)))))
    root)

fn findChildNodes elems: (List tr/TreeElement) -> (List tr/Node)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (findChildNodes tl))]
      (mt hd
        ((tr/elemToken _) rest)
        ((tr/elemNode n) (cons n rest)))))

fn findChildTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (findChildTokens tl))]
      (mt hd
        ((tr/elemToken tok) (cons tok rest))
        ((tr/elemNode _) rest))))

fn formatArgsSExpr nodes: (List tr/Node) text: String -> String
  (if (listEmpty? nodes)
    ""
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))
          (sub (exprToSExpr hd text))
          (rest (formatArgsSExpr tl text))]
      (str " " sub rest)))

fn formatArrayElemsSExpr elems: (List tr/TreeElement) text: String -> String
  (if (listEmpty? elems)
    ""
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (formatArrayElemsSExpr tl text))]
      (mt hd
        ((tr/elemNode n)
         (str " " (exprToSExpr n text) rest))
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (= k "comma") (or (= k "lbracket") (= k "rbracket")))
             rest
             (if (isTriviaTok tok)
               rest
               (str " " (tokenSlice tok text) rest))))))))

fn formatPropSExpr propNode: tr/Node text: String -> String
  (let [(k (tr/nodeKind propNode))
        (kids (tr/nodeChildren propNode))]
    (cond
      ((= k "shorthandProperty")
       (let [(toks (findNonTriviaTokens kids))
             (firstTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
         (str "(:prop " (tokenSlice firstTok text) " " (tokenSlice firstTok text) ")")))
      ((= k "spreadProperty")
       (let [(nodes (findChildNodes kids))
             (arg (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(... " (exprToSExpr arg text) ")")))
      ((= k "property")
       (let [(nodes (findChildNodes kids))
             (toks (findNonTriviaTokens kids))]
         (if (= (listLength nodes) 2)
           (let [(keyNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
                 (valNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
             (str "(:prop [" (exprToSExpr keyNode text) "] " (exprToSExpr valNode text) ")"))
           (if (= (listLength nodes) 1)
             (let [(valNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
                   (keyTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
               (str "(:prop " (tokenSlice keyTok text) " " (exprToSExpr valNode text) ")"))
             ""))))
      (else "")))

fn formatObjPropsSExpr nodes: (List tr/Node) text: String -> String
  (if (listEmpty? nodes)
    ""
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))
          (p (formatPropSExpr hd text))
          (rest (formatObjPropsSExpr tl text))]
      (if (= p "")
        rest
        (str " " p rest))))

fn formatTemplateContentSExpr elems: (List tr/TreeElement) text: String -> String
  (if (listEmpty? elems)
    ""
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))
          (rest (formatTemplateContentSExpr tl text))]
      (mt hd
        ((tr/elemNode n)
         (str " " (exprToSExpr n text) rest))
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (= k "templateNoSub") (or (= k "templateHead") (or (= k "templateMiddle") (= k "templateTail"))))
             (let [(sl (tokenSlice tok text))
                   (len (stringLength sl))]
               (cond
                 ((= k "templateNoSub")
                  (let [(inner (if (>= len 2) (optionOr (stringSlice sl 1 (- len 1)) "") sl))]
                    (str " \"" inner "\"" rest)))
                 ((= k "templateHead")
                  (let [(inner (if (>= len 3) (optionOr (stringSlice sl 1 (- len 2)) "") sl))]
                    (str " \"" inner "\"" rest)))
                 ((= k "templateMiddle")
                  (let [(inner (if (>= len 3) (optionOr (stringSlice sl 1 (- len 2)) "") sl))]
                    (str " \"" inner "\"" rest)))
                 ((= k "templateTail")
                  (let [(inner (if (>= len 2) (optionOr (stringSlice sl 1 (- len 1)) "") sl))]
                    (str " \"" inner "\"" rest)))
                 (else rest)))
             rest))))))


fn findNonTriviaTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (filter (fn [(t tr/Token)] -> Bool (not (isTriviaTok t))) (findChildTokens elems))

fn exprToSExpr node: tr/Node text: String -> String
  (let [(n (unwrapExpressionNode node))
        (k (tr/nodeKind n))
        (kids (tr/nodeChildren n))]
    (cond
      ((= k "literal")
       (let [(sl (tokenSlice (optionOr (listHead (findChildTokens kids)) (tr/makeToken "" (tr/nodeStart n) (tr/nodeEnd n))) text))]
         (if (or (stringStartsWith? sl "'") (stringStartsWith? sl "\""))
           (let [(len (stringLength sl))
                 (inner (if (>= len 2) (optionOr (stringSlice sl 1 (- len 1)) "") sl))]
             (str "\"" inner "\""))
           sl)))
      ((or (= k "ident") (or (= k "privateIdent") (or (= k "this") (= k "super"))))
       (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeEnd n)) ""))
      ((= k "metaProperty")
       (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeEnd n)) ""))
      ((= k "parenExpr")
       (let [(childNodes (findChildNodes kids))]
         (if (listEmpty? childNodes)
           ""
           (exprToSExpr (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))) text))))
      ((= k "unaryExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (argNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (exprToSExpr argNode text) ")")))
      ((= k "updateExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (firstElem (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
             (isPost (mt firstElem ((tr/elemNode _) true) ((tr/elemToken _) false)))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (argNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (if isPost
           (str "(post" op " " (exprToSExpr argNode text) ")")
           (str "(" op " " (exprToSExpr argNode text) ")"))))
      ((or (= k "binaryExpr") (or (= k "logicalExpr") (or (= k "assignExpr") (= k "seqExpr"))))
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (exprToSExpr leftNode text) " " (exprToSExpr rightNode text) ")")))
      ((= k "conditionalExpr")
       (let [(nodes (findChildNodes kids))
             (testNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (consNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))
             (altNode (optionOr (listGet nodes 2) (tr/makeErrorNode 0 0 (list))))]
         (str "(? " (exprToSExpr testNode text) " " (exprToSExpr consNode text) " " (exprToSExpr altNode text) ")")))
      ((= k "memberExpr")
       (let [(nodes (findChildNodes kids))
             (toks (findNonTriviaTokens kids))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (if (>= (listLength nodes) 2)
           (let [(idxNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
             (str "(index " (exprToSExpr leftNode text) " " (exprToSExpr idxNode text) ")"))
           (let [(lastTok (optionOr (listLast toks) (tr/makeToken "" 0 0)))
                 (prop (tokenSlice lastTok text))]
             (str "(. " (exprToSExpr leftNode text) " " prop ")")))))
      ((= k "optionalChain")
       (let [(nodes (findChildNodes kids))
             (toks (findNonTriviaTokens kids))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (if (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "lbracket")) toks)
           (let [(idxNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
             (str "(?index " (exprToSExpr leftNode text) " " (exprToSExpr idxNode text) ")"))
           (if (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "lparen")) toks)
             (let [(argNodes (optionOr (listTail nodes) (list)))]
               (str "(?call " (exprToSExpr leftNode text) (formatArgsSExpr argNodes text) ")"))
             (let [(lastTok (optionOr (listLast toks) (tr/makeToken "" 0 0)))
                   (prop (tokenSlice lastTok text))]
               (str "(?. " (exprToSExpr leftNode text) " " prop ")"))))))
      ((= k "callExpr")
       (let [(nodes (findChildNodes kids))
             (callee (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (argNodes (optionOr (listTail nodes) (list)))]
         (str "(call " (exprToSExpr callee text) (formatArgsSExpr argNodes text) ")")))
      ((= k "newExpr")
       (let [(nodes (findChildNodes kids))
             (callee (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (argNodes (optionOr (listTail nodes) (list)))]
         (str "(new " (exprToSExpr callee text) (formatArgsSExpr argNodes text) ")")))
      ((= k "arrayLiteral")
       (str "(array" (formatArrayElemsSExpr kids text) ")"))
      ((= k "objectLiteral")
       (let [(propNodes (findChildNodes kids))]
         (str "(object" (formatObjPropsSExpr propNodes text) ")")))
      ((= k "templateLiteral")
       (str "(template" (formatTemplateContentSExpr kids text) ")"))
      ((= k "taggedTemplate")
       (let [(nodes (findChildNodes kids))
             (tagNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (tmplNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(tagged " (exprToSExpr tagNode text) " " (exprToSExpr tmplNode text) ")")))
      ((= k "spreadExpr")
       (let [(nodes (findChildNodes kids))
             (arg (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(... " (exprToSExpr arg text) ")")))
      ((= k "parameters")
       (let [(childNodes (findChildNodes kids))
             (args (formatArgsSExpr childNodes text))]
         (str "(params" args ")")))
      ((= k "restElement")
       (let [(childNodes (findChildNodes kids))]
         (if (listEmpty? childNodes)
           "(...)"
           (str "(... " (exprToSExpr (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))) text) ")"))))
      ((= k "block")
       (let [(childNodes (findChildNodes kids))
             (args (formatArgsSExpr childNodes text))]
         (str "(block" args ")")))
      ((or (= k "functionExpr") (or (= k "generatorExpr") (or (= k "asyncFunctionExpr") (= k "asyncGeneratorExpr"))))
       (let [(prefix (cond
                       ((= k "asyncGeneratorExpr") "asyncGenerator")
                       ((= k "asyncFunctionExpr") "asyncFunction")
                       ((= k "generatorExpr") "generator")
                       (else "function")))
             (toks (findNonTriviaTokens kids))
             (name (findFnName toks text))
             (childNodes (findChildNodes kids))
             (paramsNode (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
             (bodyNode (optionOr (listGet childNodes 1) (tr/makeErrorNode 0 0 (list))))
             (paramsStr (exprToSExpr paramsNode text))
             (bodyStr (exprToSExpr bodyNode text))]
         (if (stringEmpty? name)
           (str "(" prefix " " paramsStr " " bodyStr ")")
           (str "(" prefix " " name " " paramsStr " " bodyStr ")"))))
      (else
       (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeEnd n)) ""))))
