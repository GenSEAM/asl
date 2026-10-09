(module asl-syntax/js/cover
  :x [parse
      parseAsync
      parseGenerator
      parseExpr
      parseText
      parseTokens
      parseCoverExpr
      parseCoverExprWithBody
      parseCoverExprCtxWithBody
      refineToPattern
      isValidPattern
      coverToSExpr
      isCoverNode
      coverNodeKind findChildNodes parseCoverExprCtx unwrapExpressionNode]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)])
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
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "newline")
           true
           (if (= (tr/tokenKind tok) "comment")
             (let [(sl (tokenSlice tok text))]
               (if (stringStartsWith? sl "//")
                 true
                 (stringContains? sl "\n")))
             (hasNewlineElements tl text))))
        ((tr/elemNode _)
         (hasNewlineElements tl text)))))
fn precComma -> Int64
  1
fn precAssign -> Int64
  2
fn precYield -> Int64
  2
fn precCond -> Int64
  3
fn precNullish -> Int64
  4
fn precLogicalOr -> Int64
  5
fn precLogicalAnd -> Int64
  6
fn precBitOr -> Int64
  7
fn precBitXor -> Int64
  8
fn precBitAnd -> Int64
  9
fn precEquality -> Int64
  10
fn precRelational -> Int64
  11
fn precShift -> Int64
  12
fn precAdditive -> Int64
  13
fn precMultiplicative -> Int64
  14
fn precExponentiation -> Int64
  15
fn precUnary -> Int64
  16
fn precAwait -> Int64
  16
fn precPostfix -> Int64
  17
fn precCall -> Int64
  18
fn precNew -> Int64
  19
fn precMember -> Int64
  20
fn isRightAssociative prec: Int64 -> Bool
  (or (= prec (precAssign))
  (or (= prec (precCond))
      (= prec (precExponentiation))))
fn isAssignmentToken kind: String -> Bool
  (or (= kind "assign")
  (or (= kind "plusAssign")
  (or (= kind "minusAssign")
  (or (= kind "starAssign")
  (or (= kind "starStarAssign")
  (or (= kind "slashAssign")
  (or (= kind "percentAssign")
  (or (= kind "ampAssign")
  (or (= kind "pipeAssign")
  (or (= kind "caretAssign")
  (or (= kind "shlAssign")
  (or (= kind "shrAssign")
  (or (= kind "shruAssign")
  (or (= kind "ampAmpAssign")
  (or (= kind "pipePipeAssign")
      (= kind "questionQuestionAssign"))))))))))))))))
fn infixPrecedence tok: tr/Token text: String hasNewlineBefore: Bool -> Int64
  (let [(k (tr/tokenKind tok))]
    (cond
      ((= k "comma") (precComma))
      ((= k "arrow")
       (if hasNewlineBefore
         0
         (precAssign)))
      ((isAssignmentToken k) (precAssign))
      ((= k "question") (precCond))
      ((= k "questionQuestion") (precNullish))
      ((= k "pipePipe") (precLogicalOr))
      ((= k "ampAmp") (precLogicalAnd))
      ((= k "pipe") (precBitOr))
      ((= k "caret") (precBitXor))
      ((= k "amp") (precBitAnd))
      ((or (= k "eqEq") (or (= k "bangEq") (or (= k "eqEqEq") (= k "bangEqEq")))) (precEquality))
      ((or (= k "lt") (or (= k "gt") (or (= k "lte") (= k "gte")))) (precRelational))
      ((and (= k "keyword") (or (= (tokenSlice tok text) "instanceof") (= (tokenSlice tok text) "in"))) (precRelational))
      ((or (= k "shl") (or (= k "shr") (= k "shru"))) (precShift))
      ((or (= k "plus") (= k "minus")) (precAdditive))
      ((or (= k "star") (or (= k "slash") (= k "percent"))) (precMultiplicative))
      ((= k "starStar") (precExponentiation))
      ((or (= k "plusPlus") (= k "minusMinus")) (if hasNewlineBefore 0 (precPostfix)))
      ((= k "dot") (precMember))
      ((= k "questionDot") (precMember))
      ((= k "lbracket") (precMember))
      ((= k "lparen") (precCall))
      ((or (= k "templateNoSub") (= k "templateHead")) (precMember))
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
               (= sl "delete"))))))))))))
fn findChildNodes elems: (List tr/TreeElement) -> (List tr/Node)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n) (cons n (findChildNodes tl)))
        ((tr/elemToken _) (findChildNodes tl)))))
fn findChildTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok) (cons tok (findChildTokens tl)))
        ((tr/elemNode _) (findChildTokens tl)))))
fn findNonTriviaTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (isTriviaTok tok)
           (findNonTriviaTokens tl)
           (cons tok (findNonTriviaTokens tl))))
        ((tr/elemNode _) (findNonTriviaTokens tl)))))
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
fn parseBlock toks: (List tr/Token) text: String -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (= k "lbrace")
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
          (ParseResult :node node :rest rem))
        (let [(errTok (tr/makeToken "error" (tr/tokenStart hd) (tr/tokenStart hd)))
              (node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenStart hd) (list (tr/elemToken errTok))))]
          (ParseResult :node node :rest toks)))))
fn refineSpreadToRest node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))]
    (ok (tr/makeNode "restElement" (tr/nodeStart node) (tr/nodeEnd node) kids)))
fn refineSpreadPropertyToRest node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))]
    (ok (tr/makeNode "restProperty" (tr/nodeStart node) (tr/nodeEnd node) kids)))
fn refineAssignToPattern node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))
        (childNodes (findChildNodes kids))]
    (if (< (listLength childNodes) 1)
      (err "missing left hand side of assignment")
      (let [(left (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
            (refL (refineNodeToPattern left text))]
        (mt refL
          ((ok patLeft)
           (ok (tr/makeNode "assignmentPattern" (tr/nodeStart node) (tr/nodeEnd node) kids)))
          ((err e) (err e))))))
fn replaceNodeElement elems: (List tr/TreeElement) oldNode: tr/Node newNode: tr/Node -> (List tr/TreeElement)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _)
         (cons hd (replaceNodeElement tl oldNode newNode)))
        ((tr/elemNode n)
         (if (= (tr/nodeStart n) (tr/nodeStart oldNode))
           (cons (tr/elemNode newNode) tl)
           (cons hd (replaceNodeElement tl oldNode newNode)))))))
fn refinePropertyToPattern node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))
        (childNodes (findChildNodes kids))]
    (if (< (listLength childNodes) 1)
      (ok node)
      (let [(valNode (optionOr (listLast childNodes) (tr/makeErrorNode 0 0 (list))))
            (refVal (refineNodeToPattern valNode text))]
        (mt refVal
          ((ok patVal)
           (let [(newKids (replaceNodeElement kids valNode patVal))]
             (ok (tr/makeNode "property" (tr/nodeStart node) (tr/nodeEnd node) newKids))))
          ((err e) (err e))))))
fn refineNodeToPattern node: tr/Node text: String -> (Result tr/Node String)
  (let [(k (tr/nodeKind node))]
    (cond
      ((= k "ident") (ok node))
      ((= k "memberExpr") (ok node))
      ((= k "arrayLiteral") (refineArrayToPattern node text))
      ((= k "objectLiteral") (refineObjectToPattern node text))
      ((= k "assignExpr") (refineAssignToPattern node text))
      ((= k "spreadExpr") (refineSpreadToRest node text))
      ((= k "shorthandProperty") (ok node))
      ((= k "property") (refinePropertyToPattern node text))
      ((= k "coverInitializedName")
       (ok (tr/makeNode "assignmentPattern" (tr/nodeStart node) (tr/nodeEnd node) (tr/nodeChildren node))))
      ((= k "spreadProperty") (refineSpreadPropertyToRest node text))
      ((or (= k "arrayPattern") (= k "objectPattern")) (ok node))
      ((= k "assignmentPattern") (ok node))
      ((= k "restElement") (ok node))
      ((= k "restProperty") (ok node))
      ((= k "parenExpr")
       (let [(kids (tr/nodeChildren node))
             (innerNodes (findChildNodes kids))]
         (if (= (listLength innerNodes) 1)
           (refineNodeToPattern (optionOr (listHead innerNodes) (tr/makeErrorNode 0 0 (list))) text)
           (err "parenthesized sequence cannot be a pattern"))))
      (else
       (err (str "invalid pattern element: " k)))))
fn refineElementToPattern elem: tr/TreeElement text: String -> (Result tr/TreeElement String)
  (mt elem
    ((tr/elemToken tok)
     (ok (tr/elemToken tok)))
    ((tr/elemNode node)
     (mt (refineNodeToPattern node text)
       ((ok patNode) (ok (tr/elemNode patNode)))
       ((err e) (err e)))))
fn hasSubsequentNodeElements rem: (List tr/TreeElement) -> Bool
  (if (listEmpty? rem)
    false
    (let [(hd (optionOr (listHead rem) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail rem) (list)))]
      (mt hd
        ((tr/elemNode _) true)
        ((tr/elemToken _) (hasSubsequentNodeElements tl)))))

fn isRestNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "restElement")
        (= k "restProperty")))

fn isRestElement elem: tr/TreeElement -> Bool
  (mt elem
    ((tr/elemNode n) (isRestNode n))
    ((tr/elemToken _) false))
fn refineElementsList elems: (List tr/TreeElement) text: String acc: (List tr/TreeElement) -> (Result (List tr/TreeElement) String)
  (if (listEmpty? elems)
    (ok (listReverse acc))
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt (refineElementToPattern hd text)
        ((ok patElem)
         (if (and (isRestElement patElem) (hasSubsequentNodeElements tl))
           (err "rest element must be in trailing position")
           (refineElementsList tl text (cons patElem acc))))
        ((err e)
         (err e)))))
fn refineArrayToPattern node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))]
    (mt (refineElementsList kids text (list))
      ((ok newKids)
       (ok (tr/makeNode "arrayPattern" (tr/nodeStart node) (tr/nodeEnd node) newKids)))
      ((err e)
       (err e))))
fn refineObjectToPattern node: tr/Node text: String -> (Result tr/Node String)
  (let [(kids (tr/nodeChildren node))]
    (mt (refineElementsList kids text (list))
      ((ok newKids)
       (ok (tr/makeNode "objectPattern" (tr/nodeStart node) (tr/nodeEnd node) newKids)))
      ((err e)
       (err e))))
fn refineToPattern node: tr/Node -> (Result tr/Node String)
  (refineNodeToPattern node "")
fn isValidPattern node: tr/Node -> Bool
  (ok? (refineToPattern node))
fn parseElementsListUntil toks: (List tr/Token) text: String closeKind: String acc: (List tr/TreeElement) bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ElementsResult
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
                (parseElementsListUntil tl text closeKind newAcc bodyParser))
              (if (= k "ellipsis")
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (sp2 (skipTrivia tl))
                      (triv2 (pairFirst sp2))
                      (subRes (parseCoverExprWithBody (pairSecond sp2) text (precComma) bodyParser))
                      (subNode subRes.node)
                      (sprKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode subNode)))))
                      (sprNode (tr/makeNode "spreadExpr" (tr/tokenStart hd) (tr/nodeEnd subNode) sprKids))
                      (newAcc (cons (tr/elemNode sprNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc bodyParser))
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (subRes (parseCoverExprWithBody rem text (precComma) bodyParser))
                      (subNode subRes.node)
                      (newAcc (cons (tr/elemNode subNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc bodyParser)))))))))
fn parseObjectPropertyList toks: (List tr/Token) text: String acc: (List tr/TreeElement) bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ElementsResult
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
                (parseObjectPropertyList tl text newAcc bodyParser))
              (if (= k "ellipsis")
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (sp2 (skipTrivia tl))
                      (triv2 (pairFirst sp2))
                      (subRes (parseCoverExprWithBody (pairSecond sp2) text (precComma) bodyParser))
                      (subNode subRes.node)
                      (sprKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode subNode)))))
                      (sprNode (tr/makeNode "spreadProperty" (tr/tokenStart hd) (tr/nodeEnd subNode) sprKids))
                      (newAcc (cons (tr/elemNode sprNode) accWithTriv))]
                  (parseObjectPropertyList subRes.rest text newAcc bodyParser))
                (if (= k "lbracket")
                  (let [(accWithTriv (listAppend (listReverse triv) acc))
                        (spComp (skipTrivia tl))
                        (trivComp (pairFirst spComp))
                        (keyRes (parseCoverExprWithBody (pairSecond spComp) text 0 bodyParser))
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
                        (valRes (parseCoverExprWithBody (pairSecond spVal) text (precComma) bodyParser))
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
                    (parseObjectPropertyList valRes.rest text newAcc bodyParser))
                  (let [(accWithTriv (listAppend (listReverse triv) acc))
                        (keyTok hd)
                        (spAfterKey (skipTrivia tl))
                        (trivAfterKey (pairFirst spAfterKey))
                        (remAfterKey (pairSecond spAfterKey))
                        (nextTok (optionOr (listHead remAfterKey) (tr/makeToken "" 0 0)))
                        (nextKind (tr/tokenKind nextTok))]
                    (if (= nextKind "colon")
                      (let [(colonTok nextTok)
                            (tlColon (optionOr (listTail remAfterKey) (list)))
                            (spVal (skipTrivia tlColon))
                            (trivVal (pairFirst spVal))
                            (valRes (parseCoverExprWithBody (pairSecond spVal) text (precComma) bodyParser))
                            (valNode valRes.node)
                            (propKids (cons (tr/elemToken keyTok)
                                        (listAppend trivAfterKey
                                          (cons (tr/elemToken colonTok)
                                            (listAppend trivVal (list (tr/elemNode valNode)))))))
                            (propNode (tr/makeNode "property" (tr/tokenStart keyTok) (tr/nodeEnd valNode) propKids))
                            (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                        (parseObjectPropertyList valRes.rest text newAcc bodyParser))
                      (if (= nextKind "assign")
                        (let [(eqTok nextTok)
                              (tlEq (optionOr (listTail remAfterKey) (list)))
                              (spVal (skipTrivia tlEq))
                              (trivVal (pairFirst spVal))
                              (valRes (parseCoverExprWithBody (pairSecond spVal) text (precComma) bodyParser))
                              (valNode valRes.node)
                              (propKids (cons (tr/elemToken keyTok)
                                          (listAppend trivAfterKey
                                            (cons (tr/elemToken eqTok)
                                              (listAppend trivVal (list (tr/elemNode valNode)))))))
                              (propNode (tr/makeNode "coverInitializedName" (tr/tokenStart keyTok) (tr/nodeEnd valNode) propKids))
                              (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                          (parseObjectPropertyList valRes.rest text newAcc bodyParser))
                        (if (= nextKind "lparen")
                          (let [(tlLp (optionOr (listTail remAfterKey) (list)))
                                (elemsRes (parseElementsListUntil tlLp text "rparen" (list) bodyParser))
                                (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd nextTok) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken nextTok)))))
                                (allParamElems (cons (tr/elemToken nextTok) elemsRes.elements))
                                (paramsNode (tr/makeNode "parameters" (tr/tokenStart nextTok) closeEnd allParamElems))
                                (tlAfterParams elemsRes.rest)
                                (spAfterRp (skipTrivia tlAfterParams))
                                (trivAfterRp (pairFirst spAfterRp))
                                (remAfterRp (pairSecond spAfterRp))
                                (bodyRes (bodyParser remAfterRp text false false))
                                (bodyNode bodyRes.node)
                                (propKids (cons (tr/elemToken keyTok)
                                            (listAppend trivAfterKey
                                              (cons (tr/elemNode paramsNode)
                                                (listAppend trivAfterRp (list (tr/elemNode bodyNode)))))))
                                (propNode (tr/makeNode "methodProperty" (tr/tokenStart keyTok) (tr/nodeEnd bodyNode) propKids))
                                (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                            (parseObjectPropertyList bodyRes.rest text newAcc bodyParser))
                          (if (and (or (= (tokenSlice keyTok text) "get") (= (tokenSlice keyTok text) "set"))
                                   (or (= nextKind "ident") (or (= nextKind "string") (= nextKind "number"))))
                            (let [(spAfterNext (skipTrivia (optionOr (listTail remAfterKey) (list))))
                                  (trivAfterNext (pairFirst spAfterNext))
                                  (remAfterNext (pairSecond spAfterNext))
                                  (tokAfterNext (optionOr (listHead remAfterNext) (tr/makeToken "" 0 0)))]
                              (if (= (tr/tokenKind tokAfterNext) "lparen")
                                (let [(tlLp (optionOr (listTail remAfterNext) (list)))
                                      (elemsRes (parseElementsListUntil tlLp text "rparen" (list) bodyParser))
                                      (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd tokAfterNext) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken tokAfterNext)))))
                                      (allParamElems (cons (tr/elemToken tokAfterNext) elemsRes.elements))
                                      (paramsNode (tr/makeNode "parameters" (tr/tokenStart tokAfterNext) closeEnd allParamElems))
                                      (tlAfterParams elemsRes.rest)
                                      (spAfterRp (skipTrivia tlAfterParams))
                                      (trivAfterRp (pairFirst spAfterRp))
                                      (remAfterRp (pairSecond spAfterRp))
                                      (bodyRes (bodyParser remAfterRp text false false))
                                      (bodyNode bodyRes.node)
                                      (accessorKind (tokenSlice keyTok text))
                                      (kind (if (= accessorKind "get") "getterProperty" "setterProperty"))
                                      (propKids (cons (tr/elemToken keyTok)
                                                  (listAppend trivAfterKey
                                                    (cons (tr/elemToken nextTok)
                                                      (listAppend trivAfterNext
                                                        (cons (tr/elemNode paramsNode)
                                                          (listAppend trivAfterRp (list (tr/elemNode bodyNode)))))))))
                                      (propNode (tr/makeNode kind (tr/tokenStart keyTok) (tr/nodeEnd bodyNode) propKids))
                                      (newAcc (cons (tr/elemNode propNode) accWithTriv))]
                                  (parseObjectPropertyList bodyRes.rest text newAcc bodyParser))
                                (let [(shorthandNode (tr/makeNode "shorthandProperty" (tr/tokenStart keyTok) (tr/tokenEnd keyTok) (list (tr/elemToken keyTok))))
                                      (newAcc (cons (tr/elemNode shorthandNode) accWithTriv))]
                                  (parseObjectPropertyList tl text newAcc bodyParser))))
                            (let [(shorthandNode (tr/makeNode "shorthandProperty" (tr/tokenStart keyTok) (tr/tokenEnd keyTok) (list (tr/elemToken keyTok))))
                                  (newAcc (cons (tr/elemNode shorthandNode) accWithTriv))]
                              (parseObjectPropertyList tl text newAcc bodyParser)))))))))))))))
fn parseTemplateSegments toks: (List tr/Token) text: String acc: (List tr/TreeElement) bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ElementsResult
  (if (listEmpty? toks)
    (ElementsResult :elements (listReverse acc) :rest toks)
    (let [(sp1 (skipTrivia toks))
          (triv1 (pairFirst sp1))
          (rem1 (pairSecond sp1))
          (exprRes (parseCoverExprWithBody rem1 text 0 bodyParser))
          (exprNode exprRes.node)
          (rem exprRes.rest)
          (sp2 (skipTrivia rem))
          (triv2 (pairFirst sp2))
          (remToks (pairSecond sp2))
          (accWithExpr (cons (tr/elemNode exprNode) (listAppend (listReverse triv1) acc)))
          (accWithTriv2 (listAppend (listReverse triv2) accWithExpr))]
      (if (listEmpty? remToks)
        (ElementsResult :elements (listReverse accWithTriv2) :rest remToks)
        (let [(midTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
              (tl (optionOr (listTail remToks) (list)))
              (k (tr/tokenKind midTok))]
          (if (= k "templateTail")
            (ElementsResult :elements (listReverse (cons (tr/elemToken midTok) accWithTriv2)) :rest tl)
            (if (= k "templateMiddle")
              (parseTemplateSegments tl text (cons (tr/elemToken midTok) accWithTriv2) bodyParser)
              (ElementsResult :elements (listReverse accWithTriv2) :rest remToks)))))))
fn parseMemberLoop left: tr/Node toks: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
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
             (parseMemberLoop newLeft tlProp text bodyParser)))
          ((= k "lbracket")
           (let [(spIdx (skipTrivia tl))
                 (trivIdx (pairFirst spIdx))
                 (idxRes (parseCoverExprWithBody (pairSecond spIdx) text 0 bodyParser))
                 (idxNode idxRes.node)
                 (spClose (skipTrivia idxRes.rest))
                 (trivClose (pairFirst spClose))
                 (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                 (closeTok (pairFirst expClose))
                 (tlClose (pairSecond expClose))
                 (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                 (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
             (parseMemberLoop newLeft tlClose text bodyParser)))
          (else
           (ParseResult :node left :rest toks))))))
fn parseMemberExpr toks: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(prefixRes (parseCoverPrefix toks text false false bodyParser))]
    (parseMemberLoop prefixRes.node prefixRes.rest text bodyParser))
fn parseComputedPropName lbracketTok: tr/Token tl: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> (Pair tr/TreeElement (List tr/Token))
  (let [(spInside (skipTrivia tl))
        (trivInside (pairFirst spInside))
        (exprRes (parseCoverExprCtxWithBody (pairSecond spInside) text 0 false false bodyParser))
        (exprNode exprRes.node)
        (spClose (skipTrivia exprRes.rest))
        (trivClose (pairFirst spClose))
        (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd exprNode)))
        (closeTok (pairFirst expClose))
        (tlClose (pairSecond expClose))
        (kids (cons (tr/elemToken lbracketTok)
                (listAppend trivInside
                  (cons (tr/elemNode exprNode)
                    (listAppend trivClose (list (tr/elemToken closeTok)))))))
        (node (tr/makeNode "computedProperty" (tr/tokenStart lbracketTok) (tr/tokenEnd closeTok) kids))]
    (pair (tr/elemNode node) tlClose))

fn parseClassMethodRest nameElem: tr/TreeElement prefixElems: (List tr/TreeElement) accessorKind: String trivAfterName: (List tr/TreeElement) lparenTok: tr/Token tlAfterLp: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(elemsRes (parseElementsListUntil tlAfterLp text "rparen" (list) bodyParser))
        (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd lparenTok) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken lparenTok)))))
        (allParamElems (cons (tr/elemToken lparenTok) elemsRes.elements))
        (paramsNode (tr/makeNode "parameters" (tr/tokenStart lparenTok) closeEnd allParamElems))
        (tlAfterParams elemsRes.rest)
        (spAfterRp (skipTrivia tlAfterParams))
        (trivAfterRp (pairFirst spAfterRp))
        (remAfterRp (pairSecond spAfterRp))
        (bodyRes (parseBlock remAfterRp text))
        (bodyNode bodyRes.node)
        (kind (cond
                ((= accessorKind "get") "classGetter")
                ((= accessorKind "set") "classSetter")
                (else "classMethod")))
        (kids (listAppend prefixElems
                (cons nameElem
                  (listAppend trivAfterName
                    (cons (tr/elemNode paramsNode)
                      (listAppend trivAfterRp (list (tr/elemNode bodyNode))))))))
        (start (tr/elementStart (optionOr (listHead kids) nameElem)))
        (methodNode (tr/makeNode kind start (tr/nodeEnd bodyNode) kids))]
    (ParseResult :node methodNode :rest bodyRes.rest))

fn parseClassFieldRest nameElem: tr/TreeElement prefixElems: (List tr/TreeElement) trivAfterName: (List tr/TreeElement) remAfterName: (List tr/Token) toksAfterName: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? remAfterName)
    (let [(kids (listAppend prefixElems (list nameElem)))
          (start (tr/elementStart (optionOr (listHead kids) nameElem)))
          (end (tr/elementEnd nameElem))
          (fieldNode (tr/makeNode "classField" start end kids))]
      (ParseResult :node fieldNode :rest toksAfterName))
    (let [(firstTok (optionOr (listHead remAfterName) (tr/makeToken "" 0 0)))
          (firstKind (tr/tokenKind firstTok))]
      (cond
        ((= firstKind "assign")
         (let [(assignTok firstTok)
               (tlAssign (optionOr (listTail remAfterName) (list)))
               (spInit (skipTrivia tlAssign))
               (trivInit (pairFirst spInit))
               (initRes (parseCoverExprCtxWithBody (pairSecond spInit) text (precComma) false false bodyParser))
               (initNode initRes.node)
               (tlInit initRes.rest)
               (spSemi (skipTrivia tlInit))
               (trivSemi (pairFirst spSemi))
               (remSemi (pairSecond spSemi))
               (maybeSemiTok (optionOr (listHead remSemi) (tr/makeToken "" 0 0)))]
           (if (= (tr/tokenKind maybeSemiTok) "semicolon")
             (let [(semiElems (listAppend trivSemi (list (tr/elemToken maybeSemiTok))))
                   (kids (listAppend prefixElems
                           (cons nameElem
                             (listAppend trivAfterName
                               (cons (tr/elemToken assignTok)
                                 (listAppend trivInit
                                   (cons (tr/elemNode initNode) semiElems)))))))
                   (start (tr/elementStart (optionOr (listHead kids) nameElem)))
                   (fieldNode (tr/makeNode "classField" start (tr/tokenEnd maybeSemiTok) kids))]
               (ParseResult :node fieldNode :rest (optionOr (listTail remSemi) (list))))
             (let [(kids (listAppend prefixElems
                           (cons nameElem
                             (listAppend trivAfterName
                               (cons (tr/elemToken assignTok)
                                 (listAppend trivInit (list (tr/elemNode initNode))))))))
                   (start (tr/elementStart (optionOr (listHead kids) nameElem)))
                   (fieldNode (tr/makeNode "classField" start (tr/nodeEnd initNode) kids))]
               (ParseResult :node fieldNode :rest tlInit)))))
        ((= firstKind "semicolon")
         (let [(semiTok firstTok)
               (kids (listAppend prefixElems
                       (cons nameElem
                         (listAppend trivAfterName (list (tr/elemToken semiTok))))))
               (start (tr/elementStart (optionOr (listHead kids) nameElem)))
               (fieldNode (tr/makeNode "classField" start (tr/tokenEnd semiTok) kids))]
           (ParseResult :node fieldNode :rest (optionOr (listTail remAfterName) (list)))))
        (else
         (let [(kids (listAppend prefixElems (list nameElem)))
               (start (tr/elementStart (optionOr (listHead kids) nameElem)))
               (end (tr/elementEnd nameElem))
               (fieldNode (tr/makeNode "classField" start end kids))]
           (ParseResult :node fieldNode :rest toksAfterName))))))

fn parseClassMemberNamed nameTok: tr/Token prefixElems: (List tr/TreeElement) tl: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (= (tr/tokenKind nameTok) "lbracket")
    (let [(compRes (parseComputedPropName nameTok tl text bodyParser))
          (nameElem (pairFirst compRes))
          (toksAfterName (pairSecond compRes))
          (spAfter (skipTrivia toksAfterName))
          (trivAfter (pairFirst spAfter))
          (remAfter (pairSecond spAfter))]
      (if (and (not (listEmpty? remAfter)) (= (tr/tokenKind (optionOr (listHead remAfter) (tr/makeToken "" 0 0))) "lparen"))
        (let [(lparenTok (optionOr (listHead remAfter) (tr/makeToken "" 0 0)))
              (tlAfterLp (optionOr (listTail remAfter) (list)))]
          (parseClassMethodRest nameElem prefixElems "" trivAfter lparenTok tlAfterLp text bodyParser))
        (parseClassFieldRest nameElem prefixElems trivAfter remAfter toksAfterName text bodyParser)))
    (let [(nameElem (tr/elemToken nameTok))
          (toksAfterName tl)
          (spAfter (skipTrivia toksAfterName))
          (trivAfter (pairFirst spAfter))
          (remAfter (pairSecond spAfter))]
      (if (and (not (listEmpty? remAfter)) (= (tr/tokenKind (optionOr (listHead remAfter) (tr/makeToken "" 0 0))) "lparen"))
        (let [(lparenTok (optionOr (listHead remAfter) (tr/makeToken "" 0 0)))
              (tlAfterLp (optionOr (listTail remAfter) (list)))]
          (parseClassMethodRest nameElem prefixElems "" trivAfter lparenTok tlAfterLp text bodyParser))
        (parseClassFieldRest nameElem prefixElems trivAfter remAfter toksAfterName text bodyParser))))

fn parseClassMemberAccessor accessorTok: tr/Token prefixElems: (List tr/TreeElement) isStatic: Bool remName: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? remName)
    (ParseResult :node (tr/makeErrorNode 0 0 prefixElems) :rest remName)
    (let [(nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail remName) (list)))
          (accessorKind (tokenSlice accessorTok text))]
      (if (= (tr/tokenKind nameTok) "lbracket")
        (let [(compRes (parseComputedPropName nameTok tl text bodyParser))
              (nameElem (pairFirst compRes))
              (toksAfterName (pairSecond compRes))
              (spAfter (skipTrivia toksAfterName))
              (trivAfter (pairFirst spAfter))
              (remAfter (pairSecond spAfter))]
          (if (and (not (listEmpty? remAfter)) (= (tr/tokenKind (optionOr (listHead remAfter) (tr/makeToken "" 0 0))) "lparen"))
            (let [(lparenTok (optionOr (listHead remAfter) (tr/makeToken "" 0 0)))
                  (tlAfterLp (optionOr (listTail remAfter) (list)))]
              (parseClassMethodRest nameElem prefixElems accessorKind trivAfter lparenTok tlAfterLp text bodyParser))
            (parseClassFieldRest nameElem prefixElems trivAfter remAfter toksAfterName text bodyParser)))
        (let [(nameElem (tr/elemToken nameTok))
              (toksAfterName tl)
              (spAfter (skipTrivia toksAfterName))
              (trivAfter (pairFirst spAfter))
              (remAfter (pairSecond spAfter))]
          (if (and (not (listEmpty? remAfter)) (= (tr/tokenKind (optionOr (listHead remAfter) (tr/makeToken "" 0 0))) "lparen"))
            (let [(lparenTok (optionOr (listHead remAfter) (tr/makeToken "" 0 0)))
                  (tlAfterLp (optionOr (listTail remAfter) (list)))]
              (parseClassMethodRest nameElem prefixElems accessorKind trivAfter lparenTok tlAfterLp text bodyParser))
            (parseClassFieldRest nameElem prefixElems trivAfter remAfter toksAfterName text bodyParser))))))

fn parseClassMember toks: (List tr/Token) prefixElems: (List tr/TreeElement) isStatic: Bool text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 prefixElems) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (sl (tokenSlice hd text))]
      (cond
        ((and (= sl "async") (not (listEmpty? tl)))
         (let [(spA (skipTrivia tl))
               (trivA (pairFirst spA))
               (remA (pairSecond spA))
               (tokA (optionOr (listHead remA) (tr/makeToken "" 0 0)))
               (kA (tr/tokenKind tokA))]
           (if (or (= kA "lparen") (or (= kA "assign") (or (= kA "semicolon") (= kA "rbrace"))))
             (parseClassMemberNamed hd prefixElems tl text bodyParser)
             (let [(newPrefix (listAppend prefixElems (cons (tr/elemToken hd) trivA)))]
               (parseClassMember remA newPrefix isStatic text bodyParser)))))
        ((= k "star")
         (let [(spS (skipTrivia tl))
               (trivS (pairFirst spS))
               (remS (pairSecond spS))
               (newPrefix (listAppend prefixElems (cons (tr/elemToken hd) trivS)))]
           (parseClassMember remS newPrefix isStatic text bodyParser)))
        ((and (or (= sl "get") (= sl "set")) (not (listEmpty? tl)))
         (let [(spG (skipTrivia tl))
               (trivG (pairFirst spG))
               (remG (pairSecond spG))
               (tokG (optionOr (listHead remG) (tr/makeToken "" 0 0)))
               (kG (tr/tokenKind tokG))]
           (if (or (= kG "lparen") (or (= kG "assign") (or (= kG "semicolon") (= kG "rbrace"))))
             (parseClassMemberNamed hd prefixElems tl text bodyParser)
             (let [(newPrefix (listAppend prefixElems (cons (tr/elemToken hd) trivG)))]
               (parseClassMemberAccessor hd newPrefix isStatic remG text bodyParser)))))
        (else
         (parseClassMemberNamed hd prefixElems tl text bodyParser)))))

fn parseClassElement toks: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (sl (tokenSlice hd text))]
      (cond
        ((= sl "static")
         (let [(sp1 (skipTrivia tl))
               (triv1 (pairFirst sp1))
               (rem1 (pairSecond sp1))]
           (if (listEmpty? rem1)
             (let [(node (tr/makeNode "classField" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
               (ParseResult :node node :rest tl))
             (let [(tok1 (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
                   (k1 (tr/tokenKind tok1))]
               (cond
                 ((= k1 "lbrace")
                  (let [(blockRes (parseBlock rem1 text))
                        (blockNode blockRes.node)
                        (kids (cons (tr/elemToken hd) (listAppend triv1 (list (tr/elemNode blockNode)))))
                        (node (tr/makeNode "staticBlock" (tr/tokenStart hd) (tr/nodeEnd blockNode) kids))]
                    (ParseResult :node node :rest blockRes.rest)))
                 ((or (= k1 "lparen") (or (= k1 "assign") (or (= k1 "semicolon") (= k1 "rbrace"))))
                  (parseClassMemberNamed hd (list) tl text bodyParser))
                 (else
                  (let [(prefixElems (cons (tr/elemToken hd) triv1))]
                    (parseClassMember rem1 prefixElems true text bodyParser))))))))
        (else
         (parseClassMember toks (list) false text bodyParser)))))

fn parseClassBodyLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> (Pair (List tr/TreeElement) (List tr/Token))
  (if (listEmpty? toks)
    (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
          (endPos (tr/elementEnd lastElem))
          (errTok (tr/makeToken "error" endPos endPos))]
      (pair (listAppend acc (list (tr/elemToken errTok))) toks))
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))]
      (if (listEmpty? rem)
        (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
              (endPos (tr/elementEnd lastElem))
              (errTok (tr/makeToken "error" endPos endPos))]
          (pair (listAppend acc (listAppend triv (list (tr/elemToken errTok)))) rem))
        (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (k (tr/tokenKind hd))]
          (cond
            ((= k "rbrace")
             (pair (listAppend acc (listAppend triv (list (tr/elemToken hd)))) (optionOr (listTail rem) (list))))
            ((= k "semicolon")
             (parseClassBodyLoop (optionOr (listTail rem) (list)) text (listAppend acc (listAppend triv (list (tr/elemToken hd)))) bodyParser))
            (else
             (let [(elemRes (parseClassElement rem text bodyParser))
                   (elemNode elemRes.node)
                   (remToks elemRes.rest)]
               (if (tr/isErrorNode elemNode)
                 (let [(advanceToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))]
                   (parseClassBodyLoop advanceToks text (listAppend acc (listAppend triv (list (tr/elemNode elemNode)))) bodyParser))
                 (let [(advanceToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))]
                   (parseClassBodyLoop advanceToks text (listAppend acc (listAppend triv (list (tr/elemNode elemNode)))) bodyParser))))))))))

fn parseClassBody toks: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (!= k "lbrace")
        (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest tl)
        (let [(bodyRes (parseClassBodyLoop tl text (list (tr/elemToken hd)) bodyParser))
              (elems (pairFirst bodyRes))
              (rem (pairSecond bodyRes))
              (lastElem (optionOr (listLast elems) (tr/elemToken hd)))
              (endOffset (tr/elementEnd lastElem))
              (bodyNode (tr/makeNode "classBody" (tr/tokenStart hd) endOffset elems))]
          (ParseResult :node bodyNode :rest rem)))))

fn parseClassExpr classTok: tr/Token tl: (List tr/Token) text: String bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))
        (firstTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
        (firstKind (tr/tokenKind firstTok))
        (firstSlice (tokenSlice firstTok text))]
    (let [(hasName (and (= firstKind "ident") (and (!= firstSlice "extends") (!= firstKind "lbrace"))))
          (nameNodes (if hasName (list (tr/elemToken firstTok)) (list)))
          (tlAfterName (if hasName (optionOr (listTail rem1) (list)) rem1))
          (sp2 (skipTrivia tlAfterName))
          (triv2 (pairFirst sp2))
          (rem2 (pairSecond sp2))
          (tokAfterName (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
          (hasExtends (and (= (tr/tokenKind tokAfterName) "keyword") (= (tokenSlice tokAfterName text) "extends")))]
      (if hasExtends
        (let [(extendsTok tokAfterName)
              (spExt (skipTrivia (optionOr (listTail rem2) (list))))
              (trivExt (pairFirst spExt))
              (superRes (parseCoverExprWithBody (pairSecond spExt) text (precCall) bodyParser))
              (superNode superRes.node)
              (spBody (skipTrivia superRes.rest))
              (trivBody (pairFirst spBody))
              (bodyRes (parseClassBody (pairSecond spBody) text bodyParser))
              (bodyNode bodyRes.node)
              (kids (listAppend (cons (tr/elemToken classTok) triv1)
                      (listAppend nameNodes
                        (listAppend triv2
                          (cons (tr/elemToken extendsTok)
                            (listAppend trivExt
                              (cons (tr/elemNode superNode)
                                (listAppend trivBody (list (tr/elemNode bodyNode))))))))))
              (classNode (tr/makeNode "classExpr" (tr/tokenStart classTok) (tr/nodeEnd bodyNode) kids))]
          (ParseResult :node classNode :rest bodyRes.rest))
        (let [(spBody (skipTrivia tlAfterName))
              (trivBody (pairFirst spBody))
              (bodyRes (parseClassBody (pairSecond spBody) text bodyParser))
              (bodyNode bodyRes.node)
              (kids (listAppend (cons (tr/elemToken classTok) triv1)
                      (listAppend nameNodes
                        (listAppend trivBody (list (tr/elemNode bodyNode))))))
              (classNode (tr/makeNode "classExpr" (tr/tokenStart classTok) (tr/nodeEnd bodyNode) kids))]
          (ParseResult :node classNode :rest bodyRes.rest)))))
fn parseArrowBody toks: (List tr/Token) text: String inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "lbrace")
          (let [(blockRes (parseBlock rem text))]
            (ParseResult :node blockRes.node :rest blockRes.rest))
          (let [(exprRes (parseCoverExprCtxWithBody rem text (precComma) inAsync inGen bodyParser))]
            (ParseResult :node exprRes.node :rest exprRes.rest))))))
fn parseParenOrArrow lparenTok: tr/Token tl: (List tr/Token) text: String isAsync: Bool inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(spAfterLp (skipTrivia tl))
        (trivAfterLp (pairFirst spAfterLp))
        (remAfterLp (pairSecond spAfterLp))]
    (if (and (not (listEmpty? remAfterLp)) (= (tr/tokenKind (optionOr (listHead remAfterLp) (tr/makeToken "" 0 0))) "rparen"))
      (let [(rparenTok (optionOr (listHead remAfterLp) (tr/makeToken "" 0 0)))
            (tlAfterRp (optionOr (listTail remAfterLp) (list)))
            (spAfterRp (skipTrivia tlAfterRp))
            (trivAfterRp (pairFirst spAfterRp))
            (remAfterRp (pairSecond spAfterRp))
            (hasNl (hasNewlineElements trivAfterRp text))
            (nextTok (optionOr (listHead remAfterRp) (tr/makeToken "" 0 0)))]
        (if (and (= (tr/tokenKind nextTok) "arrow") (not hasNl))
          (let [(arrowTok nextTok)
                (spBody (skipTrivia (optionOr (listTail remAfterRp) (list))))
                (trivBody (pairFirst spBody))
                (bodyRes (parseArrowBody (pairSecond spBody) text isAsync false bodyParser))
                (bodyNode bodyRes.node)
                (paramKids (cons (tr/elemToken lparenTok) (listAppend trivAfterLp (list (tr/elemToken rparenTok)))))
                (paramsNode (tr/makeNode "parameters" (tr/tokenStart lparenTok) (tr/tokenEnd rparenTok) paramKids))
                (allKids (cons (tr/elemNode paramsNode)
                           (listAppend trivAfterRp
                             (cons (tr/elemToken arrowTok)
                               (listAppend trivBody (list (tr/elemNode bodyNode)))))))
                (arrowNode (tr/makeNode "arrowFunction" (tr/tokenStart lparenTok) (tr/nodeEnd bodyNode) allKids))]
            (ParseResult :node arrowNode :rest bodyRes.rest))
          (let [(paramKids (cons (tr/elemToken lparenTok) (listAppend trivAfterLp (list (tr/elemToken rparenTok)))))
                (emptyNode (tr/makeNode "emptyParen" (tr/tokenStart lparenTok) (tr/tokenEnd rparenTok) paramKids))]
            (ParseResult :node emptyNode :rest tlAfterRp))))
      (let [(elemsRes (parseElementsListUntil tl text "rparen" (list) bodyParser))
            (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd lparenTok) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken lparenTok)))))
            (allElems (cons (tr/elemToken lparenTok) elemsRes.elements))
            (tlAfterClose elemsRes.rest)
            (spAfterClose (skipTrivia tlAfterClose))
            (trivAfterClose (pairFirst spAfterClose))
            (remAfterClose (pairSecond spAfterClose))
            (hasNl (hasNewlineElements trivAfterClose text))
            (nextTok (optionOr (listHead remAfterClose) (tr/makeToken "" 0 0)))]
        (if (and (= (tr/tokenKind nextTok) "arrow") (not hasNl))
          (let [(arrowTok nextTok)
                (spBody (skipTrivia (optionOr (listTail remAfterClose) (list))))
                (trivBody (pairFirst spBody))
                (bodyRes (parseArrowBody (pairSecond spBody) text isAsync false bodyParser))
                (bodyNode bodyRes.node)
                (refinedElems (refineElementsList allElems text (list)))]
            (mt refinedElems
              ((ok okElems)
               (let [(paramsNode (tr/makeNode "parameters" (tr/tokenStart lparenTok) closeEnd okElems))
                     (allKids (cons (tr/elemNode paramsNode)
                                (listAppend trivAfterClose
                                  (cons (tr/elemToken arrowTok)
                                    (listAppend trivBody (list (tr/elemNode bodyNode)))))))
                     (arrowNode (tr/makeNode "arrowFunction" (tr/tokenStart lparenTok) (tr/nodeEnd bodyNode) allKids))]
                 (ParseResult :node arrowNode :rest bodyRes.rest)))
              ((err _)
               (let [(paramsNode (tr/makeErrorNode (tr/tokenStart lparenTok) closeEnd allElems))
                     (allKids (cons (tr/elemNode paramsNode)
                                (listAppend trivAfterClose
                                  (cons (tr/elemToken arrowTok)
                                    (listAppend trivBody (list (tr/elemNode bodyNode)))))))
                     (errNode (tr/makeErrorNode (tr/tokenStart lparenTok) (tr/nodeEnd bodyNode) allKids))]
                 (ParseResult :node errNode :rest bodyRes.rest)))))
          (let [(hasSpread (listAny? (fn [(elem tr/TreeElement)] -> Bool
                                       (mt elem
                                         ((tr/elemNode n) (= (tr/nodeKind n) "spreadExpr"))
                                         ((tr/elemToken _) false)))
                                     allElems))]
            (if hasSpread
              (let [(errNode (tr/makeErrorNode (tr/tokenStart lparenTok) closeEnd allElems))]
                (ParseResult :node errNode :rest tlAfterClose))
              (let [(node (tr/makeNode "parenExpr" (tr/tokenStart lparenTok) closeEnd allElems))]
                (ParseResult :node node :rest tlAfterClose))))))))
fn parseAsyncPrefix asyncTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))
        (hasNl (hasNewlineElements triv1 text))]
    (if (or (listEmpty? rem1) hasNl)
      (let [(node (tr/makeNode "ident" (tr/tokenStart asyncTok) (tr/tokenEnd asyncTok) (list (tr/elemToken asyncTok))))]
        (ParseResult :node node :rest tl))
      (let [(nextTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (nextKind (tr/tokenKind nextTok))
            (tl2 (optionOr (listTail rem1) (list)))]
        (if (and (or (= nextKind "keyword") (= nextKind "ident")) (= (tokenSlice nextTok text) "function"))
          (let [(pref (cons (tr/elemToken asyncTok) triv1))]
            (expr/parseFunctionExpr pref nextTok tl2 text true inAsync inGen bodyParser))
          (if (= nextKind "ident")
          (let [(sp2 (skipTrivia tl2))
                (triv2 (pairFirst sp2))
                (rem2 (pairSecond sp2))
                (hasNl2 (hasNewlineElements triv2 text))
                (tokAfterIdent (optionOr (listHead rem2) (tr/makeToken "" 0 0)))]
            (if (and (= (tr/tokenKind tokAfterIdent) "arrow") (not hasNl2))
              (let [(arrowTok tokAfterIdent)
                    (spBody (skipTrivia (optionOr (listTail rem2) (list))))
                    (trivBody (pairFirst spBody))
                    (bodyRes (parseArrowBody (pairSecond spBody) text true false bodyParser))
                    (bodyNode bodyRes.node)
                    (paramNode (tr/makeNode "ident" (tr/tokenStart nextTok) (tr/tokenEnd nextTok) (list (tr/elemToken nextTok))))
                    (allKids (cons (tr/elemToken asyncTok)
                               (listAppend triv1
                                 (cons (tr/elemNode paramNode)
                                   (listAppend triv2
                                     (cons (tr/elemToken arrowTok)
                                       (listAppend trivBody (list (tr/elemNode bodyNode)))))))))
                    (arrowNode (tr/makeNode "arrowFunction" (tr/tokenStart asyncTok) (tr/nodeEnd bodyNode) allKids))]
                (ParseResult :node arrowNode :rest bodyRes.rest))
              (let [(node (tr/makeNode "ident" (tr/tokenStart asyncTok) (tr/tokenEnd asyncTok) (list (tr/elemToken asyncTok))))]
                (ParseResult :node node :rest tl))))
          (if (= nextKind "lparen")
            (let [(parenRes (parseParenOrArrow nextTok tl2 text true inAsync inGen bodyParser))
                  (innerNode parenRes.node)]
              (if (= (tr/nodeKind innerNode) "arrowFunction")
                (let [(innerKids (tr/nodeChildren innerNode))
                      (allKids (cons (tr/elemToken asyncTok) (listAppend triv1 innerKids)))
                      (arrowNode (tr/makeNode "arrowFunction" (tr/tokenStart asyncTok) (tr/nodeEnd innerNode) allKids))]
                  (ParseResult :node arrowNode :rest parenRes.rest))
                (let [(node (tr/makeNode "ident" (tr/tokenStart asyncTok) (tr/tokenEnd asyncTok) (list (tr/elemToken asyncTok))))]
                  (ParseResult :node node :rest tl))))
            (let [(node (tr/makeNode "ident" (tr/tokenStart asyncTok) (tr/tokenEnd asyncTok) (list (tr/elemToken asyncTok))))]
              (ParseResult :node node :rest tl))))))))
fn parseCoverPrefix toks: (List tr/Token) text: String inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (if (listEmpty? toks)
    (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (sl (tokenSlice hd text))]
      (cond
        ((or (= k "number") (or (= k "bigInt") (or (= k "string") (or (= k "boolean") (or (= k "null") (= k "regex"))))))
         (let [(node (tr/makeNode "literal" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= sl "function"))
         (expr/parseFunctionExpr (list) hd tl text false inAsync inGen bodyParser))
        ((or (= k "ident") (and (= k "keyword") (= sl "async")))
         (if (= sl "async")
           (parseAsyncPrefix hd tl text inAsync inGen bodyParser)
           (let [(sp (skipTrivia tl))
                 (triv (pairFirst sp))
                 (rem (pairSecond sp))
                 (hasNl (hasNewlineElements triv text))
                 (nextTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
             (if (and (= (tr/tokenKind nextTok) "arrow") (not hasNl))
               (let [(arrowTok nextTok)
                     (spBody (skipTrivia (optionOr (listTail rem) (list))))
                     (trivBody (pairFirst spBody))
                     (bodyRes (parseArrowBody (pairSecond spBody) text false false bodyParser))
                     (bodyNode bodyRes.node)
                     (paramNode (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))
                     (allKids (cons (tr/elemNode paramNode)
                                (listAppend triv
                                  (cons (tr/elemToken arrowTok)
                                    (listAppend trivBody (list (tr/elemNode bodyNode)))))))
                     (arrowNode (tr/makeNode "arrowFunction" (tr/tokenStart hd) (tr/nodeEnd bodyNode) allKids))]
                 (ParseResult :node arrowNode :rest bodyRes.rest))
               (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                 (ParseResult :node node :rest tl))))))
        ((= k "privateIdent")
         (let [(node (tr/makeNode "privateIdent" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= sl "await"))
         (if inAsync
           (let [(sp (skipTrivia tl))
                 (triv (pairFirst sp))
                 (argRes (parseCoverExprCtxWithBody (pairSecond sp) text (precAwait) inAsync inGen bodyParser))
                 (argNode argRes.node)
                 (kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode argNode)))))
                 (node (tr/makeNode "awaitExpr" (tr/tokenStart hd) (tr/nodeEnd argNode) kids))]
             (ParseResult :node node :rest argRes.rest))
           (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
             (ParseResult :node node :rest tl))))
        ((and (= k "keyword") (= sl "yield"))
         (if inGen
           (let [(sp (skipTrivia tl))
                 (triv (pairFirst sp))
                 (rem (pairSecond sp))
                 (hasNl (hasNewlineElements triv text))]
             (if (or (listEmpty? rem) hasNl)
               (let [(node (tr/makeNode "yieldExpr" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                 (ParseResult :node node :rest tl))
               (let [(firstAfter (optionOr (listHead rem) (tr/makeToken "" 0 0)))
                     (firstKind (tr/tokenKind firstAfter))]
                 (if (= firstKind "star")
                   (let [(starTok firstAfter)
                         (spVal (skipTrivia (optionOr (listTail rem) (list))))
                         (trivVal (pairFirst spVal))
                         (argRes (parseCoverExprCtxWithBody (pairSecond spVal) text (precYield) inAsync inGen bodyParser))
                         (argNode argRes.node)
                         (kids (cons (tr/elemToken hd)
                                 (listAppend triv
                                   (cons (tr/elemToken starTok)
                                     (listAppend trivVal (list (tr/elemNode argNode)))))))
                         (node (tr/makeNode "yieldExpr" (tr/tokenStart hd) (tr/nodeEnd argNode) kids))]
                     (ParseResult :node node :rest argRes.rest))
                   (if (or (= firstKind "semicolon") (or (= firstKind "comma") (or (= firstKind "rparen") (or (= firstKind "rbracket") (= firstKind "rbrace")))))
                     (let [(node (tr/makeNode "yieldExpr" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                       (ParseResult :node node :rest tl))
                     (let [(argRes (parseCoverExprCtxWithBody rem text (precYield) inAsync inGen bodyParser))
                           (argNode argRes.node)
                           (kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode argNode)))))
                           (node (tr/makeNode "yieldExpr" (tr/tokenStart hd) (tr/nodeEnd argNode) kids))]
                       (ParseResult :node node :rest argRes.rest)))))))
           (let [(node (tr/makeNode "ident" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
             (ParseResult :node node :rest tl))))
        ((and (= k "keyword") (= sl "class"))
         (parseClassExpr hd tl text bodyParser))
        ((and (= k "keyword") (= sl "this"))
         (let [(node (tr/makeNode "this" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= sl "super"))
         (let [(node (tr/makeNode "super" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((and (= k "keyword") (= sl "import"))
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
        ((and (= k "keyword") (= sl "new"))
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
               (let [(calleeRes (parseMemberExpr rem text bodyParser))
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
                             (argsRes (parseElementsListUntil (optionOr (listTail remParen) (list)) text "rparen" (list) bodyParser))
                             (allArgs (cons (tr/elemToken lparenTok) argsRes.elements))
                             (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd lparenTok) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken lparenTok)))))
                             (kids (cons (tr/elemToken hd) (listAppend triv (cons (tr/elemNode calleeNode) (listAppend trivParen allArgs)))))
                             (newNode (tr/makeNode "newExpr" (tr/tokenStart hd) closeEnd kids))]
                         (parseMemberLoop newNode argsRes.rest text bodyParser))
                       (let [(kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode calleeNode)))))
                             (node (tr/makeNode "newExpr" (tr/tokenStart hd) (tr/nodeEnd calleeNode) kids))]
                         (ParseResult :node node :rest remCallee))))))))))
        ((isPrefixOp hd text)
         (let [(sp (skipTrivia tl))
               (triv (pairFirst sp))
               (argRes (parseCoverExprCtxWithBody (pairSecond sp) text (precUnary) inAsync inGen bodyParser))
               (argNode argRes.node)
               (isUpd (or (= k "plusPlus") (= k "minusMinus")))
               (kind (if isUpd "updateExpr" "unaryExpr"))
               (kids (cons (tr/elemToken hd) (listAppend triv (list (tr/elemNode argNode)))))]
           (if (tr/isErrorNode argNode)
             (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/nodeEnd argNode) kids) :rest argRes.rest)
             (let [(node (tr/makeNode kind (tr/tokenStart hd) (tr/nodeEnd argNode) kids))]
               (ParseResult :node node :rest argRes.rest)))))
        ((= k "lparen")
         (parseParenOrArrow hd tl text false inAsync inGen bodyParser))
        ((= k "lbracket")
         (let [(elemsRes (parseElementsListUntil tl text "rbracket" (list) bodyParser))
               (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) elemsRes.elements))
               (node (tr/makeNode "arrayLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest elemsRes.rest)))
        ((= k "lbrace")
         (let [(elemsRes (parseObjectPropertyList tl text (list) bodyParser))
               (closeEnd (if (listEmpty? elemsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast elemsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) elemsRes.elements))
               (node (tr/makeNode "objectLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest elemsRes.rest)))
        ((= k "templateNoSub")
         (let [(node (tr/makeNode "templateLiteral" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl)))
        ((= k "templateHead")
         (let [(segsRes (parseTemplateSegments tl text (list) bodyParser))
               (closeEnd (if (listEmpty? segsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast segsRes.elements) (tr/elemToken hd)))))
               (kids (cons (tr/elemToken hd) segsRes.elements))
               (node (tr/makeNode "templateLiteral" (tr/tokenStart hd) closeEnd kids))]
           (ParseResult :node node :rest segsRes.rest)))
        (else
         (let [(node (tr/makeNode "error" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
           (ParseResult :node node :rest tl))))))
fn parsePrattLoop left: tr/Node toks: (List tr/Token) text: String minPrec: Int64 inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
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
              ((= k "arrow")
               (if hasNl
                 (let [(errTok (tr/makeToken "error" (tr/tokenStart hd) (tr/tokenEnd hd)))
                       (kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemToken errTok)))))
                       (errNode (tr/makeErrorNode (tr/nodeStart left) (tr/tokenEnd hd) kids))]
                   (ParseResult :node errNode :rest tl))
                 (let [(spBody (skipTrivia tl))
                       (trivBody (pairFirst spBody))
                       (bodyRes (parseArrowBody (pairSecond spBody) text false false bodyParser))
                       (bodyNode bodyRes.node)
                       (allKids (cons (tr/elemNode left)
                                  (listAppend triv
                                    (cons (tr/elemToken hd)
                                      (listAppend trivBody (list (tr/elemNode bodyNode)))))))
                       (arrowNode (tr/makeNode "arrowFunction" (tr/nodeStart left) (tr/nodeEnd bodyNode) allKids))]
                   (parsePrattLoop arrowNode bodyRes.rest text minPrec inAsync inGen bodyParser))))
              ((or (= k "plusPlus") (= k "minusMinus"))
               (let [(kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemToken hd)))))
                     (newLeft (tr/makeNode "updateExpr" (tr/nodeStart left) (tr/tokenEnd hd) kids))]
                 (parsePrattLoop newLeft tl text minPrec inAsync inGen bodyParser)))
              ((= k "dot")
               (let [(spProp (skipTrivia tl))
                     (trivProp (pairFirst spProp))
                     (remProp (pairSecond spProp))
                     (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                     (tlProp (optionOr (listTail remProp) (list)))
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                     (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
                 (parsePrattLoop newLeft tlProp text minPrec inAsync inGen bodyParser)))
              ((= k "questionDot")
               (let [(spProp (skipTrivia tl))
                     (trivProp (pairFirst spProp))
                     (remProp (pairSecond spProp))
                     (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                     (propKind (tr/tokenKind propTok))]
                 (if (= propKind "lbracket")
                   (let [(spIdx (skipTrivia (optionOr (listTail remProp) (list))))
                         (trivIdx (pairFirst spIdx))
                         (idxRes (parseCoverExprWithBody (pairSecond spIdx) text 0 bodyParser))
                         (idxNode idxRes.node)
                         (spClose (skipTrivia idxRes.rest))
                         (trivClose (pairFirst spClose))
                         (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                         (closeTok (pairFirst expClose))
                         (tlClose (pairSecond expClose))
                         (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (cons (tr/elemToken propTok) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))))
                         (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
                     (parsePrattLoop newLeft tlClose text minPrec inAsync inGen bodyParser))
                   (if (= propKind "lparen")
                     (let [(argsRes (parseElementsListUntil (optionOr (listTail remProp) (list)) text "rparen" (list) bodyParser))
                           (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd propTok) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken propTok)))))
                           (allArgs (cons (tr/elemToken propTok) argsRes.elements))
                           (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp allArgs)))))
                           (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) closeEnd kids))]
                       (parsePrattLoop newLeft argsRes.rest text minPrec inAsync inGen bodyParser))
                     (let [(tlProp (optionOr (listTail remProp) (list)))
                           (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                           (newLeft (tr/makeNode "optionalChain" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
                       (parsePrattLoop newLeft tlProp text minPrec inAsync inGen bodyParser))))))
              ((= k "lbracket")
               (let [(spIdx (skipTrivia tl))
                     (trivIdx (pairFirst spIdx))
                     (idxRes (parseCoverExprWithBody (pairSecond spIdx) text 0 bodyParser))
                     (idxNode idxRes.node)
                     (spClose (skipTrivia idxRes.rest))
                     (trivClose (pairFirst spClose))
                     (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                     (closeTok (pairFirst expClose))
                     (tlClose (pairSecond expClose))
                     (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                     (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
                 (parsePrattLoop newLeft tlClose text minPrec inAsync inGen bodyParser)))
              ((= k "lparen")
               (let [(argsRes (parseElementsListUntil tl text "rparen" (list) bodyParser))
                     (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken hd)))))
                     (allArgs (cons (tr/elemToken hd) argsRes.elements))
                     (kids (cons (tr/elemNode left) (listAppend triv allArgs)))
                     (newLeft (tr/makeNode "callExpr" (tr/nodeStart left) closeEnd kids))]
                 (parsePrattLoop newLeft argsRes.rest text minPrec inAsync inGen bodyParser)))
              ((or (= k "templateNoSub") (= k "templateHead"))
               (let [(spT (skipTrivia rem))
                     (tmplRes (parseCoverPrefix (pairSecond spT) text inAsync inGen bodyParser))
                     (tmplNode tmplRes.node)
                     (kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemNode tmplNode)))))
                     (newLeft (tr/makeNode "taggedTemplate" (tr/nodeStart left) (tr/nodeEnd tmplNode) kids))]
                 (parsePrattLoop newLeft tmplRes.rest text minPrec inAsync inGen bodyParser)))
              ((= k "question")
               (let [(spCons (skipTrivia tl))
                     (trivCons (pairFirst spCons))
                     (consRes (parseCoverExprCtxWithBody (pairSecond spCons) text (precAssign) inAsync inGen bodyParser))
                     (consNode consRes.node)
                     (spColon (skipTrivia consRes.rest))
                     (trivColon (pairFirst spColon))
                     (expColon (expectClose (pairSecond spColon) "colon" (tr/nodeEnd consNode)))
                     (colonTok (pairFirst expColon))
                     (tlColon (pairSecond expColon))
                     (spAlt (skipTrivia tlColon))
                     (trivAlt (pairFirst spAlt))
                     (altRes (parseCoverExprCtxWithBody (pairSecond spAlt) text (- (precCond) 1) inAsync inGen bodyParser))
                     (altNode altRes.node)
                     (kids (cons (tr/elemNode left)
                             (listAppend triv
                               (cons (tr/elemToken hd)
                                 (listAppend trivCons
                                   (cons (tr/elemNode consNode)
                                     (listAppend trivColon
                                       (cons (tr/elemToken colonTok)
                                         (listAppend trivAlt (list (tr/elemNode altNode)))))))))))
                     (newLeft (tr/makeNode "conditionalExpr" (tr/nodeStart left) (tr/nodeEnd altNode) kids))]
                 (parsePrattLoop newLeft altRes.rest text minPrec inAsync inGen bodyParser)))
              ((isAssignmentToken k)
               (let [(patLeft (if (= k "assign")
                                (let [(lk (tr/nodeKind left))]
                                  (if (or (= lk "arrayLiteral") (= lk "objectLiteral"))
                                    (mt (refineToPattern left)
                                      ((ok pat) pat)
                                      ((err _) (tr/makeErrorNode (tr/nodeStart left) (tr/nodeEnd left) (tr/nodeChildren left))))
                                    left))
                                left))
                     (spRhs (skipTrivia tl))
                     (trivRhs (pairFirst spRhs))
                     (nextMinPrec (- (precAssign) 1))
                     (rhsRes (parseCoverExprCtxWithBody (pairSecond spRhs) text nextMinPrec inAsync inGen bodyParser))
                     (rhsNode rhsRes.node)
                     (kids (cons (tr/elemNode patLeft)
                             (listAppend triv
                               (cons (tr/elemToken hd)
                                 (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                     (newLeft (tr/makeNode "assignExpr" (tr/nodeStart patLeft) (tr/nodeEnd rhsNode) kids))]
                 (parsePrattLoop newLeft rhsRes.rest text minPrec inAsync inGen bodyParser)))
              ((= k "comma")
               (let [(spRhs (skipTrivia tl))
                     (trivRhs (pairFirst spRhs))
                     (rhsRes (parseCoverExprCtxWithBody (pairSecond spRhs) text (precComma) inAsync inGen bodyParser))
                     (rhsNode rhsRes.node)
                     (kids (cons (tr/elemNode left)
                             (listAppend triv
                               (cons (tr/elemToken hd)
                                 (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                     (newLeft (tr/makeNode "seqExpr" (tr/nodeStart left) (tr/nodeEnd rhsNode) kids))]
                 (parsePrattLoop newLeft rhsRes.rest text minPrec inAsync inGen bodyParser)))
              (else
               (let [(spRhs (skipTrivia tl))
                     (trivRhs (pairFirst spRhs))
                     (nextMinPrec (if (isRightAssociative prec) (- prec 1) prec))
                     (rhsRes (parseCoverExprCtxWithBody (pairSecond spRhs) text nextMinPrec inAsync inGen bodyParser))
                     (rhsNode rhsRes.node)
                     (isLog (or (= k "questionQuestion") (or (= k "pipePipe") (= k "ampAmp"))))
                     (kind (if isLog "logicalExpr" "binaryExpr"))
                     (kids (cons (tr/elemNode left)
                             (listAppend triv
                               (cons (tr/elemToken hd)
                                 (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                     (newLeft (tr/makeNode kind (tr/nodeStart left) (tr/nodeEnd rhsNode) kids))]
                 (parsePrattLoop newLeft rhsRes.rest text minPrec inAsync inGen bodyParser)))))))))
fn parseCoverExprCtxWithBody toks: (List tr/Token) text: String minPrec: Int64 inAsync: Bool inGen: Bool bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (let [(prefixRes (parseCoverPrefix toks text inAsync inGen bodyParser))]
    (parsePrattLoop prefixRes.node prefixRes.rest text minPrec inAsync inGen bodyParser))

fn parseCoverExprWithBody toks: (List tr/Token) text: String minPrec: Int64 bodyParser: (Fn [(List tr/Token) String Bool Bool] -> ParseResult) -> ParseResult
  (parseCoverExprCtxWithBody toks text minPrec false false bodyParser)

fn parseCoverExprCtx toks: (List tr/Token) text: String minPrec: Int64 inAsync: Bool inGen: Bool -> ParseResult
  (parseCoverExprCtxWithBody toks text minPrec inAsync inGen expr/parseDefaultBlock)

fn parseCoverExpr toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (parseCoverExprCtx toks text minPrec false false)
fn trailingElementsLoop toks: (List tr/Token) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (listReverse acc)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (trailingElementsLoop tl (cons (tr/elemToken hd) acc))))
fn parseTokensCtx tokens: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/Node
  (let [(res (parseCoverExprCtx tokens text 0 inAsync inGen))
        (node res.node)
        (rem res.rest)
        (trailing (trailingElementsLoop rem (list)))
        (allKids (listAppend (list (tr/elemNode node)) trailing))
        (endOffset (if (listEmpty? trailing) (tr/nodeEnd node) (tr/elementEnd (optionOr (listLast trailing) (tr/elemNode node)))))]
    (tr/makeNode "expression" (tr/nodeStart node) endOffset allKids))
fn parseTokens tokens: (List tr/Token) text: String -> tr/Node
  (parseTokensCtx tokens text false false)
fn parseTextCtx text: String inAsync: Bool inGen: Bool -> tr/Node
  (let [(tokens (lx/tokenize text))]
    (parseTokensCtx tokens text inAsync inGen))
fn parseText text: String -> tr/Node
  (parseTextCtx text false false)
fn parseExpr text: String -> tr/Node
  (parseText text)
fn hasDirectErrorToken elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "error")
           true
           (hasDirectErrorToken tl)))
        ((tr/elemNode _)
         (hasDirectErrorToken tl)))))
fn firstErrorOffset elems: (List tr/TreeElement) -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "error")
           (some (tr/tokenStart tok))
           (firstErrorOffset tl)))
        ((tr/elemNode node)
         (if (or (= (tr/nodeKind node) "emptyParen") (tr/isErrorNode node))
           (some (tr/nodeStart node))
           (if (hasDirectErrorToken (tr/nodeChildren node))
             (some (tr/nodeStart node))
             (mt (firstErrorOffset (tr/nodeChildren node))
               ((some off) (some off))
               ((none) (firstErrorOffset tl)))))))))
fn firstTrailingOffset elems: (List tr/TreeElement) seenExpr: Bool -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode node)
         (firstTrailingOffset tl true))
        ((tr/elemToken tok)
         (if (and seenExpr (not (isTriviaTok tok)))
           (some (tr/tokenStart tok))
           (firstTrailingOffset tl seenExpr))))))
fn parseCtx text: String inAsync: Bool inGen: Bool -> (Result tr/Node String)
  (let [(root (parseTextCtx text inAsync inGen))
        (elems (tr/nodeChildren root))]
    (mt (firstErrorOffset elems)
      ((some off)
       (err (str "Parse error at offset " (stringFromInt64 off))))
      ((none)
       (mt (firstTrailingOffset elems false)
         ((some off)
          (err (str "Unexpected token at offset " (stringFromInt64 off))))
         ((none)
          (ok root))))))
fn parse text: String -> (Result tr/Node String)
  (parseCtx text false false)
fn parseAsync text: String -> (Result tr/Node String)
  (parseCtx text true false)
fn parseGenerator text: String -> (Result tr/Node String)
  (parseCtx text false true)
fn isCoverNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "arrowFunction")
    (or (= k "awaitExpr")
    (or (= k "yieldExpr")
    (or (= k "classExpr")
    (or (= k "classBody")
    (or (= k "classField")
    (or (= k "classMethod")
    (or (= k "classGetter")
    (or (= k "classSetter")
    (or (= k "staticBlock")
    (or (= k "arrayPattern")
    (or (= k "objectPattern")
    (or (= k "assignmentPattern")
    (or (= k "restElement")
    (or (= k "functionExpr")
    (or (= k "generatorExpr")
    (or (= k "asyncFunctionExpr")
    (or (= k "asyncGeneratorExpr")
    (or (= k "methodProperty")
    (or (= k "getterProperty")
    (or (= k "setterProperty")
        (= k "restProperty")))))))))))))))))))))))
fn coverNodeKind node: tr/Node -> String
  (tr/nodeKind node)
fn unwrapExpressionNode root: tr/Node -> tr/Node
  (if (= (tr/nodeKind root) "expression")
    (let [(kids (tr/nodeChildren root))
          (nodes (findChildNodes kids))]
      (if (listEmpty? nodes)
        root
        (optionOr (listHead nodes) root)))
    root)
fn formatParamList elems: (List tr/TreeElement) text: String acc: (List String) -> (List String)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (isTriviaTok tok) (or (= k "comma") (or (= k "lparen") (or (= k "rparen") (or (= k "lbracket") (or (= k "rbracket") (or (= k "lbrace") (= k "rbrace"))))))))
             (formatParamList tl text acc)
             (formatParamList tl text (cons (tokenSlice tok text) acc)))))
        ((tr/elemNode node)
         (formatParamList tl text (cons (coverToSExpr node text) acc))))))
fn formatCoverArgsLoop nodes: (List tr/Node) text: String acc: (List String) -> (List String)
  (if (listEmpty? nodes)
    (listReverse acc)
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))]
      (formatCoverArgsLoop tl text (cons (coverToSExpr hd text) acc))))

fn formatCoverArgs nodes: (List tr/Node) text: String -> String
  (let [(strs (formatCoverArgsLoop nodes text (list)))]
    (stringJoin strs " "))

fn findMethodNameTok toks: (List tr/Token) text: String isStatic: Bool isAccessor: Bool -> tr/Token
  (let [(toksAfterStatic (if isStatic (optionOr (listTail toks) (list)) toks))
        (toksAfterAccessor (if isAccessor (optionOr (listTail toksAfterStatic) (list)) toksAfterStatic))]
    (if (listEmpty? toksAfterAccessor)
      (tr/makeToken "" 0 0)
      (let [(hd (optionOr (listHead toksAfterAccessor) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail toksAfterAccessor) (list)))
            (sl (tokenSlice hd text))]
        (if (or (= sl "async") (= sl "*"))
          (findMethodNameTok tl text false false)
          hd))))

fn coverToSExpr node: tr/Node text: String -> String
  (let [(n (unwrapExpressionNode node))
        (k (tr/nodeKind n))
        (kids (tr/nodeChildren n))]
    (cond
      ((= k "arrowFunction")
       (let [(firstToks (findChildTokens kids))
             (isAsync (listAny? (fn [(t tr/Token)] -> Bool (and (or (= (tr/tokenKind t) "ident") (= (tr/tokenKind t) "keyword")) (= (tokenSlice t text) "async"))) firstToks))
             (prefix (if isAsync "asyncArrow" "arrow"))
             (childNodes (findChildNodes kids))
             (paramsNode (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
             (bodyNode (optionOr (listLast childNodes) (tr/makeErrorNode 0 0 (list))))
             (paramItems (if (= (tr/nodeKind paramsNode) "ident")
                           (list (tokenSlice (optionOr (listHead (findChildTokens (tr/nodeChildren paramsNode))) (tr/makeToken "" (tr/nodeStart paramsNode) (tr/nodeEnd paramsNode))) text))
                           (formatParamList (tr/nodeChildren paramsNode) text (list))))
             (paramsStr (str "(params" (if (listEmpty? paramItems) "" (str " " (stringJoin paramItems " "))) ")"))
             (bodyStr (coverToSExpr bodyNode text))]
         (str "(" prefix " " paramsStr " " bodyStr ")")))
      ((= k "block")
       "(block)")
      ((= k "parameters")
       (let [(childNodes (findChildNodes kids))
             (paramStrs (formatCoverArgs childNodes text))]
         (if (stringEmpty? paramStrs)
           "(params)"
           (str "(params " paramStrs ")"))))
      ((or (= k "getterProperty") (= k "setterProperty"))
       (let [(toks (findNonTriviaTokens kids))
             (isGet (= k "getterProperty"))
             (prefix (if isGet "get" "set"))
             (keyTok (if (>= (listLength toks) 2) (optionOr (listGet toks 1) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
             (key (tokenSlice keyTok text))
             (childNodes (findChildNodes kids))
             (body (if (listEmpty? childNodes) "" (formatCoverArgs childNodes text)))]
         (str "(" prefix " " key " " body ")")))
      ((= k "methodProperty")
       (let [(toks (findNonTriviaTokens kids))
             (keyTok (if (listEmpty? toks) (tr/makeToken "" 0 0) (optionOr (listHead toks) (tr/makeToken "" 0 0))))
             (key (tokenSlice keyTok text))
             (childNodes (findChildNodes kids))
             (body (if (listEmpty? childNodes) "" (formatCoverArgs childNodes text)))]
         (str "(method " key " " body ")")))
      ((or (= k "functionExpr") (or (= k "generatorExpr") (or (= k "asyncFunctionExpr") (= k "asyncGeneratorExpr"))))
       (let [(prefix (cond
                       ((= k "asyncGeneratorExpr") "asyncGenerator")
                       ((= k "asyncFunctionExpr") "asyncFunction")
                       ((= k "generatorExpr") "generator")
                       (else "function")))
             (toks (findNonTriviaTokens kids))
             (name (expr/findFnName toks text))
             (childNodes (findChildNodes kids))
             (paramsNode (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
             (bodyNode (optionOr (listGet childNodes 1) (tr/makeErrorNode 0 0 (list))))
             (paramsStr (coverToSExpr paramsNode text))
             (bodyStr (coverToSExpr bodyNode text))]
         (if (stringEmpty? name)
           (str "(" prefix " " paramsStr " " bodyStr ")")
           (str "(" prefix " " name " " paramsStr " " bodyStr ")"))))
      ((= k "awaitExpr")
       (let [(nodes (findChildNodes kids))
             (arg (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(await " (coverToSExpr arg text) ")")))
      ((= k "yieldExpr")
       (let [(toks (findChildTokens kids))
             (hasStar (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "star")) toks))
             (nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           "(yield)"
           (let [(arg (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
                 (op (if hasStar "yield*" "yield"))]
             (str "(" op " " (coverToSExpr arg text) ")")))))
      ((= k "classBody")
       (let [(childNodes (findChildNodes kids))]
         (if (listEmpty? childNodes)
           "(body)"
           (let [(memberStrs (formatCoverArgs childNodes text))]
             (if (stringEmpty? memberStrs)
               "(body)"
               (str "(body " memberStrs ")"))))))
      ((= k "staticBlock")
       (let [(nodes (findChildNodes kids))
             (blockNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(staticBlock " (coverToSExpr blockNode text) ")")))
      ((= k "classField")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (isStatic (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "static")) toks))
             (nameTok (if isStatic
                        (optionOr (listGet toks 1) (tr/makeToken "" 0 0))
                        (optionOr (listHead toks) (tr/makeToken "" 0 0))))
             (nameStr (tokenSlice nameTok text))
             (initNode (if (listEmpty? nodes)
                         (tr/makeErrorNode 0 0 (list))
                         (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list)))))
             (hasInit (not (tr/isErrorNode initNode)))]
         (if isStatic
           (if hasInit
             (str "(field static " nameStr " " (coverToSExpr initNode text) ")")
             (str "(field static " nameStr ")"))
           (if hasInit
             (str "(field " nameStr " " (coverToSExpr initNode text) ")")
             (str "(field " nameStr ")")))))
      ((or (= k "classMethod") (or (= k "classGetter") (= k "classSetter")))
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (isStatic (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "static")) toks))
             (op (cond
                   ((= k "classGetter") (if isStatic "get static" "get"))
                   ((= k "classSetter") (if isStatic "set static" "set"))
                   (else (if isStatic "method static" "method"))))
             (isAccessor (or (= k "classGetter") (= k "classSetter")))
             (nameTok (findMethodNameTok toks text isStatic isAccessor))
             (nameStr (tokenSlice nameTok text))
             (paramsNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (bodyNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))
             (paramItems (formatParamList (tr/nodeChildren paramsNode) text (list)))
             (paramsStr (str "(params" (if (listEmpty? paramItems) "" (str " " (stringJoin paramItems " "))) ")"))
             (bodyStr (coverToSExpr bodyNode text))]
         (str "(" op " " nameStr " " paramsStr " " bodyStr ")")))
      ((= k "classExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (hasExtends (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "extends")) toks))
             (hasName (and (>= (listLength toks) 2) (and (= (tr/tokenKind (optionOr (listGet toks 1) (tr/makeToken "" 0 0))) "ident") (!= (tokenSlice (optionOr (listGet toks 1) (tr/makeToken "" 0 0)) text) "extends"))))
             (nameStr (if hasName (str " " (tokenSlice (optionOr (listGet toks 1) (tr/makeToken "" 0 0)) text)) ""))
             (bodyNode (optionOr (listLast nodes) (tr/makeErrorNode 0 0 (list))))
             (bodyStr (coverToSExpr bodyNode text))]
         (if hasExtends
           (let [(superNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
             (str "(class" nameStr " (extends " (coverToSExpr superNode text) ") " bodyStr ")"))
           (str "(class" nameStr " " bodyStr ")"))))
      ((= k "arrayPattern")
       (let [(items (formatParamList kids text (list)))]
         (str "(arrayPattern" (if (listEmpty? items) "" (str " " (stringJoin items " "))) ")")))
      ((= k "objectPattern")
       (let [(items (formatParamList kids text (list)))]
         (str "(objectPattern" (if (listEmpty? items) "" (str " " (stringJoin items " "))) ")")))
      ((= k "assignmentPattern")
       (let [(nodes (findChildNodes kids))
             (left (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (right (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(= " (coverToSExpr left text) " " (coverToSExpr right text) ")")))
      ((or (= k "restElement") (= k "restProperty"))
       (let [(nodes (findChildNodes kids))
             (arg (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(... " (coverToSExpr arg text) ")")))
      ((or (= k "binaryExpr") (or (= k "logicalExpr") (= k "seqExpr")))
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (coverToSExpr leftNode text) " " (coverToSExpr rightNode text) ")")))
      ((= k "callExpr")
       (let [(nodes (findChildNodes kids))
             (callee (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (argNodes (optionOr (listTail nodes) (list)))
             (argStrs (formatCoverArgs argNodes text))]
         (str "(call " (coverToSExpr callee text) (if (stringEmpty? argStrs) "" (str " " argStrs)) ")")))
      ((= k "arrayLiteral")
       (let [(items (formatParamList kids text (list)))]
         (str "(array" (if (listEmpty? items) "" (str " " (stringJoin items " "))) ")")))
      ((= k "parenExpr")
       (let [(nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           ""
           (coverToSExpr (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))) text))))
      ((= k "assignExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (coverToSExpr leftNode text) " " (coverToSExpr rightNode text) ")")))
      (else
       (expr/exprToSExpr n text))))
