(module asl-syntax/ts/types
  :x [parseType
      parseTypeTokens
      parseTypeExpr
      parseTypeAnnotation
      parseTypeArguments
      parseTypeParameters
      typeToSExpr
      isTypeNode
      typeNodeKind
      unwrapTypeNode
      parseTs
      parseTsExpr
      parseTsText
      parseTsTokens
      tsToSExpr parseFunctionParamsLoop]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)])

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
        ((tr/elemNode _) (findChildTokens tl))
        ((tr/elemToken t) (cons t (findChildTokens tl))))))

fn findNonTriviaTokens elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode _) (findNonTriviaTokens tl))
        ((tr/elemToken t)
         (if (isTriviaTok t)
           (findNonTriviaTokens tl)
           (cons t (findNonTriviaTokens tl)))))))


fn findMappedNameTok toks: (List tr/Token) text: String -> tr/Token
  (if (or (listEmpty? toks) (listEmpty? (optionOr (listTail toks) (list))))
    (tr/makeToken "" 0 0)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (nextTok (optionOr (listHead tl) (tr/makeToken "" 0 0)))]
      (if (and (= (tr/tokenKind hd) "ident") (= (tokenSlice nextTok text) "in"))
        hd
        (findMappedNameTok tl text))))

fn findFirstIdentTok toks: (List tr/Token) -> (Option tr/Token)
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (= (tr/tokenKind hd) "ident")
        (some hd)
        (findFirstIdentTok tl))))

fn findFirstParamNameTok toks: (List tr/Token) text: String -> (Option tr/Token)
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (or (= (tr/tokenKind hd) "ident") (isKeywordTypeName (tokenSlice hd text)))
        (some hd)
        (findFirstParamNameTok tl text))))

fn isKeywordTypeName name: String -> Bool
  (or (= name "string")
  (or (= name "number")
  (or (= name "boolean")
  (or (= name "any")
  (or (= name "unknown")
  (or (= name "void")
  (or (= name "never")
  (or (= name "undefined")
  (or (= name "null")
  (or (= name "bigint")
  (or (= name "symbol")
      (= name "object"))))))))))))

fn parseTypeArgumentsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (let [(endPos (if (listEmpty? acc) (stringLength text) (tr/elementEnd (optionOr (listHead acc) (tr/elemToken (tr/makeToken "" 0 0))))))
            (errTok (tr/makeToken "error" endPos endPos))]
        (ElementsResult :elements (listReverse (cons (tr/elemToken errTok) (listAppend (listReverse triv) acc))) :rest rem))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "gt")
          (let [(accWithGt (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
            (ElementsResult :elements (listReverse accWithGt) :rest tl))
          (if (= k "comma")
            (let [(accWithComma (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
              (parseTypeArgumentsLoop tl text accWithComma))
            (let [(typeRes (parseTypeExpr rem text 0))
                  (typeNode typeRes.node)
                  (accWithType (cons (tr/elemNode typeNode) (listAppend (listReverse triv) acc)))]
              (parseTypeArgumentsLoop typeRes.rest text accWithType)))))))

fn parseTypeArguments toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind hd) "lt")
          (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list)) :rest toks)
          (let [(elemsRes (parseTypeArgumentsLoop tl text (list (tr/elemToken hd))))
                (allElems (listAppend triv elemsRes.elements))
                (start (if (listEmpty? allElems) (tr/tokenStart hd) (tr/elementStart (optionOr (listHead allElems) (tr/elemToken hd)))))
                (end (if (listEmpty? allElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allElems) (tr/elemToken hd)))))
                (node (tr/makeNode "typeArguments" start end allElems))]
            (ParseResult :node node :rest elemsRes.rest))))))

fn tryParseTypeArguments toks: (List tr/Token) text: String -> (Option ParseResult)
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (none)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (!= (tr/tokenKind hd) "lt")
          (none)
          (let [(res (parseTypeArguments toks text))
                (node res.node)]
            (if (or (tr/isErrorNode node) (= (tr/nodeKind node) "error"))
              (none)
              (let [(remAfter res.rest)
                    (spAfter (skipTrivia remAfter))
                    (remToks (pairSecond spAfter))]
                (if (listEmpty? remToks)
                  (none)
                  (let [(nextTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
                        (nk (tr/tokenKind nextTok))]
                    (if (or (= nk "lparen")
                        (or (= nk "templateNoSub")
                            (= nk "templateHead")))
                      (some res)
                      (none)))))))))))

fn parseTypeParam toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(nameTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (spExt (skipTrivia tl))
            (trivExt (pairFirst spExt))
            (remExt (pairSecond spExt))]
        (if (listEmpty? remExt)
          (let [(kids (listAppend triv (list (tr/elemToken nameTok))))
                (node (tr/makeNode "typeParameter" (tr/tokenStart nameTok) (tr/tokenEnd nameTok) kids))]
            (ParseResult :node node :rest tl))
          (let [(maybeExtTok (optionOr (listHead remExt) (tr/makeToken "" 0 0)))
                (extName (tokenSlice maybeExtTok text))]
            (if (= extName "extends")
              (let [(spAfterExt (skipTrivia (optionOr (listTail remExt) (list))))
                    (trivAfterExt (pairFirst spAfterExt))
                    (boundRes (parseTypeExpr (pairSecond spAfterExt) text 0))
                    (boundNode boundRes.node)
                    (remBound boundRes.rest)
                    (spEq (skipTrivia remBound))
                    (trivEq (pairFirst spEq))
                    (remEq (pairSecond spEq))]
                (if (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign"))
                  (let [(eqTok (optionOr (listHead remEq) (tr/makeToken "" 0 0)))
                        (spDef (skipTrivia (optionOr (listTail remEq) (list))))
                        (trivDef (pairFirst spDef))
                        (defRes (parseTypeExpr (pairSecond spDef) text 0))
                        (defNode defRes.node)
                        (kids (listAppend triv
                                (cons (tr/elemToken nameTok)
                                  (listAppend trivExt
                                    (cons (tr/elemToken maybeExtTok)
                                      (listAppend trivAfterExt
                                        (cons (tr/elemNode boundNode)
                                          (listAppend trivEq
                                            (cons (tr/elemToken eqTok)
                                              (listAppend trivDef (list (tr/elemNode defNode))))))))))))
                        (node (tr/makeNode "typeParameter" (tr/tokenStart nameTok) (tr/nodeEnd defNode) kids))]
                    (ParseResult :node node :rest defRes.rest))
                  (let [(kids (listAppend triv
                                (cons (tr/elemToken nameTok)
                                  (listAppend trivExt
                                    (cons (tr/elemToken maybeExtTok)
                                      (listAppend trivAfterExt (list (tr/elemNode boundNode))))))))
                        (node (tr/makeNode "typeParameter" (tr/tokenStart nameTok) (tr/nodeEnd boundNode) kids))]
                    (ParseResult :node node :rest remBound))))
              (if (= (tr/tokenKind maybeExtTok) "assign")
                (let [(spDef (skipTrivia (optionOr (listTail remExt) (list))))
                      (trivDef (pairFirst spDef))
                      (defRes (parseTypeExpr (pairSecond spDef) text 0))
                      (defNode defRes.node)
                      (kids (listAppend triv
                              (cons (tr/elemToken nameTok)
                                (listAppend trivExt
                                  (cons (tr/elemToken maybeExtTok)
                                    (listAppend trivDef (list (tr/elemNode defNode))))))))
                      (node (tr/makeNode "typeParameter" (tr/tokenStart nameTok) (tr/nodeEnd defNode) kids))]
                  (ParseResult :node node :rest defRes.rest))
                (let [(kids (listAppend triv (list (tr/elemToken nameTok))))
                      (node (tr/makeNode "typeParameter" (tr/tokenStart nameTok) (tr/tokenEnd nameTok) kids))]
                  (ParseResult :node node :rest tl)))))))))

fn parseTypeParamsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements (listReverse acc) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "gt")
          (let [(accWithGt (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
            (ElementsResult :elements (listReverse accWithGt) :rest tl))
          (if (= k "comma")
            (let [(accWithComma (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
              (parseTypeParamsLoop tl text accWithComma))
            (let [(paramRes (parseTypeParam rem text))
                  (paramNode paramRes.node)
                  (accWithParam (cons (tr/elemNode paramNode) (listAppend (listReverse triv) acc)))]
              (parseTypeParamsLoop paramRes.rest text accWithParam)))))))

fn parseTypeParameters toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind hd) "lt")
          (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list)) :rest toks)
          (let [(elemsRes (parseTypeParamsLoop tl text (list (tr/elemToken hd))))
                (allElems (listAppend triv elemsRes.elements))
                (start (if (listEmpty? allElems) (tr/tokenStart hd) (tr/elementStart (optionOr (listHead allElems) (tr/elemToken hd)))))
                (end (if (listEmpty? allElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allElems) (tr/elemToken hd)))))
                (node (tr/makeNode "typeParameters" start end allElems))]
            (ParseResult :node node :rest elemsRes.rest))))))

fn parseTypeAnnotation toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(colonTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind colonTok) "colon")
          (ParseResult :node (tr/makeErrorNode (tr/tokenStart colonTok) (tr/tokenEnd colonTok) (list)) :rest toks)
          (let [(spType (skipTrivia tl))
                (trivType (pairFirst spType))
                (typeRes (parseTypeExpr (pairSecond spType) text 0))
                (typeNode typeRes.node)
                (kids (listAppend triv (cons (tr/elemToken colonTok) (listAppend trivType (list (tr/elemNode typeNode))))))
                (start (if (listEmpty? kids) (tr/tokenStart colonTok) (tr/elementStart (optionOr (listHead kids) (tr/elemToken colonTok)))))
                (node (tr/makeNode "typeAnnotation" start (tr/nodeEnd typeNode) kids))]
            (ParseResult :node node :rest typeRes.rest))))))

fn parseTemplateTypeSegments toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (if (listEmpty? toks)
    (let [(endPos (if (listEmpty? acc) (stringLength text) (tr/elementEnd (optionOr (listHead acc) (tr/elemToken (tr/makeToken "" 0 0))))))
          (errTok (tr/makeToken "error" endPos endPos))]
      (ElementsResult :elements (listReverse (cons (tr/elemToken errTok) acc)) :rest toks))
    (let [(typeRes (parseTypeExpr toks text 0))
          (typeNode typeRes.node)
          (rem typeRes.rest)
          (sp (skipTrivia rem))
          (triv (pairFirst sp))
          (remToks (pairSecond sp))
          (accWithType (cons (tr/elemNode typeNode) (listAppend (listReverse triv) acc)))]
      (if (listEmpty? remToks)
        (let [(endPos (if (listEmpty? accWithType) (stringLength text) (tr/elementEnd (optionOr (listHead accWithType) (tr/elemToken (tr/makeToken "" 0 0))))))
              (errTok (tr/makeToken "error" endPos endPos))]
          (ElementsResult :elements (listReverse (cons (tr/elemToken errTok) accWithType)) :rest remToks))
        (let [(midTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
              (tl (optionOr (listTail remToks) (list)))
              (k (tr/tokenKind midTok))]
          (if (= k "templateTail")
            (ElementsResult :elements (listReverse (cons (tr/elemToken midTok) accWithType)) :rest tl)
            (if (or (= k "templateMiddle") (= k "templateMid"))
              (parseTemplateTypeSegments tl text (cons (tr/elemToken midTok) accWithType))
              (let [(endPos (tr/tokenStart midTok))
                    (errTok (tr/makeToken "error" endPos endPos))]
                (ElementsResult :elements (listReverse (cons (tr/elemToken errTok) accWithType)) :rest remToks))))))))

fn parseTupleElement toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "ellipsis")
          (let [(spType (skipTrivia tl))
                (trivType (pairFirst spType))
                (typeRes (parseTypeExpr (pairSecond spType) text 0))
                (typeNode typeRes.node)
                (kids (listAppend triv (cons (tr/elemToken hd) (listAppend trivType (list (tr/elemNode typeNode))))))
                (node (tr/makeNode "restType" (tr/tokenStart hd) (tr/nodeEnd typeNode) kids))]
            (ParseResult :node node :rest typeRes.rest))
          (let [(spNext (skipTrivia tl))
                (trivNext (pairFirst spNext))
                (remNext (pairSecond spNext))]
            (if (and (or (= k "ident") (isKeywordTypeName (tokenSlice hd text)))
                     (not (listEmpty? remNext)))
              (let [(tok1 (optionOr (listHead remNext) (tr/makeToken "" 0 0)))
                    (k1 (tr/tokenKind tok1))]
                (if (= k1 "colon")
                  (let [(spType (skipTrivia (optionOr (listTail remNext) (list))))
                        (trivType (pairFirst spType))
                        (typeRes (parseTypeExpr (pairSecond spType) text 0))
                        (typeNode typeRes.node)
                        (kids (listAppend triv
                                (cons (tr/elemToken hd)
                                  (listAppend trivNext
                                    (cons (tr/elemToken tok1)
                                      (listAppend trivType (list (tr/elemNode typeNode))))))))
                        (node (tr/makeNode "tupleElement" (tr/tokenStart hd) (tr/nodeEnd typeNode) kids))]
                    (ParseResult :node node :rest typeRes.rest))
                  (if (= k1 "question")
                    (let [(tl1 (optionOr (listTail remNext) (list)))
                          (spColon (skipTrivia tl1))
                          (trivColon (pairFirst spColon))
                          (remColon (pairSecond spColon))]
                      (if (and (not (listEmpty? remColon)) (= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon"))
                        (let [(colonTok (optionOr (listHead remColon) (tr/makeToken "" 0 0)))
                              (spType (skipTrivia (optionOr (listTail remColon) (list))))
                              (trivType (pairFirst spType))
                              (typeRes (parseTypeExpr (pairSecond spType) text 0))
                              (typeNode typeRes.node)
                              (kids (listAppend triv
                                      (cons (tr/elemToken hd)
                                        (listAppend trivNext
                                          (cons (tr/elemToken tok1)
                                            (listAppend trivColon
                                              (cons (tr/elemToken colonTok)
                                                (listAppend trivType (list (tr/elemNode typeNode))))))))))
                              (node (tr/makeNode "tupleElement" (tr/tokenStart hd) (tr/nodeEnd typeNode) kids))]
                          (ParseResult :node node :rest typeRes.rest))
                        (parseTypeExpr rem text 0)))
                    (parseTypeExpr rem text 0))))
              (parseTypeExpr rem text 0)))))))

fn parseTupleElementsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (let [(endPos (if (listEmpty? acc) (stringLength text) (tr/elementEnd (optionOr (listHead acc) (tr/elemToken (tr/makeToken "" 0 0))))))
            (errTok (tr/makeToken "error" endPos endPos))]
        (ElementsResult :elements (listReverse (cons (tr/elemToken errTok) (listAppend (listReverse triv) acc))) :rest rem))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rbracket")
          (let [(accWithRb (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
            (ElementsResult :elements (listReverse accWithRb) :rest tl))
          (if (= k "comma")
            (let [(accWithComma (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
              (parseTupleElementsLoop tl text accWithComma))
            (let [(elemRes (parseTupleElement rem text))
                  (elemNode elemRes.node)
                  (accWithElem (cons (tr/elemNode elemNode) (listAppend (listReverse triv) acc)))]
              (parseTupleElementsLoop elemRes.rest text accWithElem)))))))

fn checkInInsideBracket toks: (List tr/Token) text: String -> Bool
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      false
      (let [(tl (optionOr (listTail rem) (list)))
            (sp2 (skipTrivia tl))
            (rem2 (pairSecond sp2))]
        (if (listEmpty? rem2)
          false
          (let [(tok2 (optionOr (listHead rem2) (tr/makeToken "" 0 0)))]
            (= (tokenSlice tok2 text) "in"))))))

fn isMappedTypeStart toks: (List tr/Token) text: String -> Bool
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      false
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))]
        (if (= k "lbracket")
          (checkInInsideBracket tl text)
          (if (or (and (or (= k "plus") (= k "minus")) (not (listEmpty? tl)))
                  (and (= sl "readonly") (not (listEmpty? tl))))
            (let [(sp2 (skipTrivia (if (or (= k "plus") (= k "minus")) (optionOr (listTail tl) (list)) tl)))
                  (rem2 (pairSecond sp2))]
              (if (listEmpty? rem2)
                false
                (let [(hd2 (optionOr (listHead rem2) (tr/makeToken "" 0 0)))]
                  (if (= (tr/tokenKind hd2) "lbracket")
                    (checkInInsideBracket (optionOr (listTail rem2) (list)) text)
                    (if (= (tokenSlice hd2 text) "readonly")
                      (let [(sp3 (skipTrivia (optionOr (listTail rem2) (list))))
                            (rem3 (pairSecond sp3))]
                        (if (listEmpty? rem3)
                          false
                          (= (tr/tokenKind (optionOr (listHead rem3) (tr/makeToken "" 0 0))) "lbracket")))
                      false)))))
            false)))))

fn parseMappedType lbraceTok: tr/Token tl: (List tr/Token) text: String -> ParseResult
  (let [(spLead (skipTrivia tl))
        (trivLead (pairFirst spLead))
        (remLead (pairSecond spLead))
        (accInit (cons (tr/elemToken lbraceTok) trivLead))]
    (let [(spMod (skipTrivia remLead))
          (trivMod (pairFirst spMod))
          (remMod (pairSecond spMod))
          (hdMod (optionOr (listHead remMod) (tr/makeToken "" 0 0)))
          (slMod (tokenSlice hdMod text))
          (hasPlusMinus (or (= (tr/tokenKind hdMod) "plus") (= (tr/tokenKind hdMod) "minus")))
          (accAfterRo
            (if hasPlusMinus
              (let [(tlMod (optionOr (listTail remMod) (list)))
                    (spRo (skipTrivia tlMod))
                    (trivRo (pairFirst spRo))
                    (roTok (optionOr (listHead (pairSecond spRo)) (tr/makeToken "" 0 0)))]
                (listAppend accInit (cons (tr/elemToken hdMod) (listAppend trivRo (list (tr/elemToken roTok))))))
              (if (= slMod "readonly")
                (listAppend accInit (list (tr/elemToken hdMod)))
                accInit)))
          (remAfterRo
            (if hasPlusMinus
              (optionOr (listTail (pairSecond (skipTrivia (optionOr (listTail remMod) (list))))) (list))
              (if (= slMod "readonly")
                (optionOr (listTail remMod) (list))
                remMod)))
          (spLb (skipTrivia remAfterRo))
          (trivLb (pairFirst spLb))
          (remLb (pairSecond spLb))
          (lbTok (optionOr (listHead remLb) (tr/makeToken "" 0 0)))
          (tlLb (optionOr (listTail remLb) (list)))
          (spName (skipTrivia tlLb))
          (trivName (pairFirst spName))
          (nameTok (optionOr (listHead (pairSecond spName)) (tr/makeToken "" 0 0)))
          (tlName (optionOr (listTail (pairSecond spName)) (list)))
          (spIn (skipTrivia tlName))
          (trivIn (pairFirst spIn))
          (inTok (optionOr (listHead (pairSecond spIn)) (tr/makeToken "" 0 0)))
          (tlIn (optionOr (listTail (pairSecond spIn)) (list)))
          (spType (skipTrivia tlIn))
          (trivType (pairFirst spType))
          (constraintRes (parseTypeExpr (pairSecond spType) text 0))
          (constraintNode constraintRes.node)
          (remCons constraintRes.rest)
          (spAs (skipTrivia remCons))
          (trivAs (pairFirst spAs))
          (remAs (pairSecond spAs))
          (hdAs (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
          (hasAs (= (tokenSlice hdAs text) "as"))
          (spAfterAs (if hasAs (skipTrivia (optionOr (listTail remAs) (list))) (pair (list) (list))))
          (trivAfterAs (pairFirst spAfterAs))
          (asRes (if hasAs (parseTypeExpr (pairSecond spAfterAs) text 0) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remAs)))
          (asNode asRes.node)
          (remAfterAs (if hasAs asRes.rest remAs))
          (spRb (skipTrivia remAfterAs))
          (trivRb (pairFirst spRb))
          (expRb (expectClose (pairSecond spRb) "rbracket" (tr/nodeEnd constraintNode)))
          (rbTok (pairFirst expRb))
          (tlRb (pairSecond expRb))
          (spQ (skipTrivia tlRb))
          (trivQ (pairFirst spQ))
          (remQ (pairSecond spQ))
          (hdQ (optionOr (listHead remQ) (tr/makeToken "" 0 0)))
          (hasPlusMinusQ (or (= (tr/tokenKind hdQ) "plus") (= (tr/tokenKind hdQ) "minus")))
          (hasQ (or (= (tr/tokenKind hdQ) "question") hasPlusMinusQ))
          (qToks (if hasPlusMinusQ
                   (let [(spQ2 (skipTrivia (optionOr (listTail remQ) (list))))
                         (q2Tok (optionOr (listHead (pairSecond spQ2)) (tr/makeToken "" 0 0)))]
                     (list (tr/elemToken hdQ) (tr/elemToken q2Tok)))
                   (if (= (tr/tokenKind hdQ) "question")
                     (list (tr/elemToken hdQ))
                     (list))))
          (remAfterQ (if hasPlusMinusQ
                       (optionOr (listTail (pairSecond (skipTrivia (optionOr (listTail remQ) (list))))) (list))
                       (if (= (tr/tokenKind hdQ) "question")
                         (optionOr (listTail remQ) (list))
                         remQ)))
          (spColon (skipTrivia remAfterQ))
          (trivColon (pairFirst spColon))
          (expColon (expectClose (pairSecond spColon) "colon" (tr/tokenEnd rbTok)))
          (colonTok (pairFirst expColon))
          (tlColon (pairSecond expColon))
          (spVal (skipTrivia tlColon))
          (trivVal (pairFirst spVal))
          (valRes (parseTypeExpr (pairSecond spVal) text 0))
          (valNode valRes.node)
          (remVal valRes.rest)
          (spSemi (skipTrivia remVal))
          (trivSemi (pairFirst spSemi))
          (remSemi (pairSecond spSemi))
          (hdSemi (optionOr (listHead remSemi) (tr/makeToken "" 0 0)))
          (hasSemi (or (= (tr/tokenKind hdSemi) "semicolon") (= (tr/tokenKind hdSemi) "comma")))
          (remAfterSemi (if hasSemi (optionOr (listTail remSemi) (list)) remSemi))
          (spRc (skipTrivia remAfterSemi))
          (trivRc (pairFirst spRc))
          (expRc (expectClose (pairSecond spRc) "rbrace" (tr/nodeEnd valNode)))
          (rcTok (pairFirst expRc))
          (tlRc (pairSecond expRc))
          (allKids (listAppend accAfterRo
                     (listAppend trivLb
                       (cons (tr/elemToken lbTok)
                         (listAppend trivName
                           (cons (tr/elemToken nameTok)
                             (listAppend trivIn
                               (cons (tr/elemToken inTok)
                                 (listAppend trivType
                                   (cons (tr/elemNode constraintNode)
                                     (listAppend (if hasAs (listAppend trivAs (cons (tr/elemToken hdAs) (listAppend trivAfterAs (list (tr/elemNode asNode))))) (list))
                                       (listAppend trivRb
                                         (cons (tr/elemToken rbTok)
                                           (listAppend trivQ
                                             (listAppend qToks
                                               (listAppend trivColon
                                                 (cons (tr/elemToken colonTok)
                                                   (listAppend trivVal
                                                     (cons (tr/elemNode valNode)
                                                       (listAppend (if hasSemi (listAppend trivSemi (list (tr/elemToken hdSemi))) (list))
                                                         (listAppend trivRc (list (tr/elemToken rcTok)))))))))))))))))))))))
          (node (tr/makeNode "mappedType" (tr/tokenStart lbraceTok) (tr/tokenEnd rcTok) allKids))]
      (ParseResult :node node :rest tlRc)))

fn parseTypeLiteralMember toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))]
        (if (= k "lbracket")
          (let [(spName (skipTrivia tl))
                (trivName (pairFirst spName))
                (nameTok (optionOr (listHead (pairSecond spName)) (tr/makeToken "" 0 0)))
                (tlName (optionOr (listTail (pairSecond spName)) (list)))
                (spCol (skipTrivia tlName))
                (trivCol (pairFirst spCol))
                (colTok (optionOr (listHead (pairSecond spCol)) (tr/makeToken "" 0 0)))
                (tlCol (optionOr (listTail (pairSecond spCol)) (list)))
                (spKeyType (skipTrivia tlCol))
                (trivKeyType (pairFirst spKeyType))
                (keyTypeRes (parseTypeExpr (pairSecond spKeyType) text 0))
                (keyTypeNode keyTypeRes.node)
                (spClose (skipTrivia keyTypeRes.rest))
                (trivClose (pairFirst spClose))
                (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd keyTypeNode)))
                (closeTok (pairFirst expClose))
                (tlClose (pairSecond expClose))
                (spVal (skipTrivia tlClose))
                (trivVal (pairFirst spVal))
                (valColon (optionOr (listHead (pairSecond spVal)) (tr/makeToken "" 0 0)))
                (tlVal (optionOr (listTail (pairSecond spVal)) (list)))
                (spValType (skipTrivia tlVal))
                (trivValType (pairFirst spValType))
                (valTypeRes (parseTypeExpr (pairSecond spValType) text 0))
                (valTypeNode valTypeRes.node)
                (kids (listAppend triv
                        (cons (tr/elemToken hd)
                          (listAppend trivName
                            (cons (tr/elemToken nameTok)
                              (listAppend trivCol
                                (cons (tr/elemToken colTok)
                                  (listAppend trivKeyType
                                    (cons (tr/elemNode keyTypeNode)
                                      (listAppend trivClose
                                        (cons (tr/elemToken closeTok)
                                          (listAppend trivVal
                                            (cons (tr/elemToken valColon)
                                              (listAppend trivValType (list (tr/elemNode valTypeNode))))))))))))))))
                (node (tr/makeNode "indexSignature" (tr/tokenStart hd) (tr/nodeEnd valTypeNode) kids))]
            (ParseResult :node node :rest valTypeRes.rest))
          (let [(isReadonly (= sl "readonly"))
                (remAfterRo (if isReadonly tl rem))
                (spName (skipTrivia remAfterRo))
                (trivName (pairFirst spName))
                (nameTok (optionOr (listHead (pairSecond spName)) (tr/makeToken "" 0 0)))
                (tlName (optionOr (listTail (pairSecond spName)) (list)))
                (spQ (skipTrivia tlName))
                (trivQ (pairFirst spQ))
                (remQ (pairSecond spQ))
                (hasQ (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "question")))
                (qTok (if hasQ (optionOr (listHead remQ) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (remAfterQ (if hasQ (optionOr (listTail remQ) (list)) remQ))
                (spColon (skipTrivia remAfterQ))
                (trivColon (pairFirst spColon))
                (remColon (pairSecond spColon))
                (hasColon (and (not (listEmpty? remColon)) (= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon")))
                (colonTok (if hasColon (optionOr (listHead remColon) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (spType (if hasColon (skipTrivia (optionOr (listTail remColon) (list))) (pair (list) (list))))
                (trivType (pairFirst spType))
                (typeRes (if hasColon (parseTypeExpr (pairSecond spType) text 0) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remColon)))
                (typeNode typeRes.node)
                (kids (listAppend triv
                        (listAppend (if isReadonly (list (tr/elemToken hd)) (list))
                          (listAppend trivName
                            (cons (tr/elemToken nameTok)
                              (listAppend (if hasQ (listAppend trivQ (list (tr/elemToken qTok))) (list))
                                (if hasColon (listAppend trivColon (cons (tr/elemToken colonTok) (listAppend trivType (list (tr/elemNode typeNode))))) (list))))))))
                (end (if hasColon (tr/nodeEnd typeNode) (tr/tokenEnd nameTok)))
                (node (tr/makeNode "propertySignature" (tr/tokenStart (if isReadonly hd nameTok)) end kids))]
            (ParseResult :node node :rest (if hasColon typeRes.rest remColon)))))))

fn parseTypeLiteralMembersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements (listReverse acc) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rbrace")
          (let [(accWithRb (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
            (ElementsResult :elements (listReverse accWithRb) :rest tl))
          (if (or (= k "semicolon") (= k "comma"))
            (let [(accWithSep (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
              (parseTypeLiteralMembersLoop tl text accWithSep))
            (let [(memberRes (parseTypeLiteralMember rem text))
                  (memberNode memberRes.node)
                  (accWithMember (cons (tr/elemNode memberNode) (listAppend (listReverse triv) acc)))]
              (parseTypeLiteralMembersLoop memberRes.rest text accWithMember)))))))

fn parseFunctionParam toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (isRest (= (tr/tokenKind hd) "ellipsis"))
            (remName (if isRest tl rem))
            (spName (skipTrivia remName))
            (trivName (pairFirst spName))
            (nameTok (optionOr (listHead (pairSecond spName)) (tr/makeToken "" 0 0)))
            (tlName (optionOr (listTail (pairSecond spName)) (list)))
            (spQ (skipTrivia tlName))
            (trivQ (pairFirst spQ))
            (remQ (pairSecond spQ))
            (hasQ (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "question")))
            (qTok (if hasQ (optionOr (listHead remQ) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
            (remAfterQ (if hasQ (optionOr (listTail remQ) (list)) remQ))
            (spCol (skipTrivia remAfterQ))
            (trivCol (pairFirst spCol))
            (remCol (pairSecond spCol))
            (hasCol (and (not (listEmpty? remCol)) (= (tr/tokenKind (optionOr (listHead remCol) (tr/makeToken "" 0 0))) "colon")))
            (colTok (if hasCol (optionOr (listHead remCol) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
            (spType (if hasCol (skipTrivia (optionOr (listTail remCol) (list))) (pair (list) (list))))
            (trivType (pairFirst spType))
            (typeRes (if hasCol (parseTypeExpr (pairSecond spType) text 0) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remCol)))
            (typeNode typeRes.node)
            (kids (listAppend triv
                    (listAppend (if isRest (list (tr/elemToken hd)) (list))
                      (listAppend trivName
                        (cons (tr/elemToken nameTok)
                          (listAppend (if hasQ (listAppend trivQ (list (tr/elemToken qTok))) (list))
                            (if hasCol (listAppend trivCol (cons (tr/elemToken colTok) (listAppend trivType (list (tr/elemNode typeNode))))) (list))))))))
            (start (if isRest (tr/tokenStart hd) (tr/tokenStart nameTok)))
            (end (if hasCol (tr/nodeEnd typeNode) (tr/tokenEnd nameTok)))
            (node (tr/makeNode "parameter" start end kids))]
        (ParseResult :node node :rest (if hasCol typeRes.rest remCol)))))

fn parseFunctionParamsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements (listReverse acc) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rparen")
          (let [(accWithRp (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
            (ElementsResult :elements (listReverse accWithRp) :rest tl))
          (if (= k "comma")
            (let [(accWithComma (cons (tr/elemToken hd) (listAppend (listReverse triv) acc)))]
              (parseFunctionParamsLoop tl text accWithComma))
            (let [(paramRes (parseFunctionParam rem text))
                  (paramNode paramRes.node)
                  (accWithParam (cons (tr/elemNode paramNode) (listAppend (listReverse triv) acc)))]
              (parseFunctionParamsLoop paramRes.rest text accWithParam)))))))

fn checkArrowAfterCloseParen toks: (List tr/Token) -> Bool
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      false
      (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "arrow")))

fn parsePrimaryType toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode (stringLength text) (stringLength text) (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))]
        (cond
          ((isKeywordTypeName sl)
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "keywordType" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((= k "null")
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "keywordType" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((or (= k "string") (= k "number") (= k "bigint") (= k "boolean"))
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "literalType" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((= k "templateNoSub")
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "templateLiteralType" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((= k "templateHead")
           (let [(segsRes (parseTemplateTypeSegments tl text (list (tr/elemToken hd))))
                 (allElems (listAppend triv segsRes.elements))
                 (start (tr/tokenStart hd))
                 (end (if (listEmpty? allElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allElems) (tr/elemToken hd)))))
                 (node (tr/makeNode "templateLiteralType" start end allElems))]
             (ParseResult :node node :rest segsRes.rest)))
          ((= sl "this")
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "thisType" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((= sl "keyof")
           (let [(spIn (skipTrivia tl))
                 (trivIn (pairFirst spIn))
                 (innerRes (parseTypeExpr (pairSecond spIn) text 0))
                 (innerNode innerRes.node)
                 (kids (cons (tr/elemToken hd) (listAppend trivIn (list (tr/elemNode innerNode)))))
                 (node (tr/makeNode "typeOperator" (tr/tokenStart hd) (tr/nodeEnd innerNode) kids))]
             (ParseResult :node node :rest innerRes.rest)))
          ((= sl "readonly")
           (let [(spIn (skipTrivia tl))
                 (trivIn (pairFirst spIn))
                 (innerRes (parseTypeExpr (pairSecond spIn) text 0))
                 (innerNode innerRes.node)
                 (kids (cons (tr/elemToken hd) (listAppend trivIn (list (tr/elemNode innerNode)))))
                 (node (tr/makeNode "typeOperator" (tr/tokenStart hd) (tr/nodeEnd innerNode) kids))]
             (ParseResult :node node :rest innerRes.rest)))
          ((= sl "typeof")
           (let [(spIn (skipTrivia tl))
                 (trivIn (pairFirst spIn))
                 (exprRes (cv/parseCoverExpr (pairSecond spIn) text 16))
                 (exprNode exprRes.node)
                 (kids (cons (tr/elemToken hd) (listAppend trivIn (list (tr/elemNode exprNode)))))
                 (node (tr/makeNode "typeQuery" (tr/tokenStart hd) (tr/nodeEnd exprNode) kids))]
             (ParseResult :node node :rest exprRes.rest)))
          ((= sl "infer")
           (let [(spName (skipTrivia tl))
                 (trivName (pairFirst spName))
                 (nameTok (optionOr (listHead (pairSecond spName)) (tr/makeToken "" 0 0)))
                 (tlName (optionOr (listTail (pairSecond spName)) (list)))
                 (spExt (skipTrivia tlName))
                 (trivExt (pairFirst spExt))
                 (remExt (pairSecond spExt))
                 (hasExt (and (not (listEmpty? remExt)) (= (tokenSlice (optionOr (listHead remExt) (tr/makeToken "" 0 0)) text) "extends")))]
             (if hasExt
               (let [(extTok (optionOr (listHead remExt) (tr/makeToken "" 0 0)))
                     (spBound (skipTrivia (optionOr (listTail remExt) (list))))
                     (trivBound (pairFirst spBound))
                     (boundRes (parseTypeExpr (pairSecond spBound) text 0))
                     (boundNode boundRes.node)
                     (kids (cons (tr/elemToken hd)
                             (listAppend trivName
                               (cons (tr/elemToken nameTok)
                                 (listAppend trivExt
                                   (cons (tr/elemToken extTok)
                                     (listAppend trivBound (list (tr/elemNode boundNode)))))))))
                     (node (tr/makeNode "inferType" (tr/tokenStart hd) (tr/nodeEnd boundNode) kids))]
                 (ParseResult :node node :rest boundRes.rest))
               (let [(kids (listAppend triv (cons (tr/elemToken hd) (listAppend trivName (list (tr/elemToken nameTok))))))
                     (node (tr/makeNode "inferType" (tr/tokenStart hd) (tr/tokenEnd nameTok) kids))]
                 (ParseResult :node node :rest tlName)))))
          ((= sl "new")
           (let [(spLp (skipTrivia tl))
                 (trivLp (pairFirst spLp))
                 (remLp (pairSecond spLp))
                 (lpTok (optionOr (listHead remLp) (tr/makeToken "" 0 0)))
                 (tlLp (optionOr (listTail remLp) (list)))
                 (paramsRes (parseFunctionParamsLoop tlLp text (list (tr/elemToken lpTok))))
                 (allParamElems (listAppend trivLp paramsRes.elements))
                 (paramsStart (tr/tokenStart lpTok))
                 (paramsEnd (if (listEmpty? allParamElems) (tr/tokenEnd lpTok) (tr/elementEnd (optionOr (listLast allParamElems) (tr/elemToken lpTok)))))
                 (paramsNode (tr/makeNode "parameters" paramsStart paramsEnd allParamElems))
                 (remParams paramsRes.rest)
                 (spArrow (skipTrivia remParams))
                 (trivArrow (pairFirst spArrow))
                 (arrowTok (optionOr (listHead (pairSecond spArrow)) (tr/makeToken "" 0 0)))
                 (spRet (skipTrivia (optionOr (listTail (pairSecond spArrow)) (list))))
                 (trivRet (pairFirst spRet))
                 (retRes (parseTypeExpr (pairSecond spRet) text 0))
                 (retNode retRes.node)
                 (kids (listAppend triv
                         (cons (tr/elemToken hd)
                           (cons (tr/elemNode paramsNode)
                             (listAppend trivArrow
                               (cons (tr/elemToken arrowTok)
                                 (listAppend trivRet (list (tr/elemNode retNode)))))))))
                 (node (tr/makeNode "constructorType" (tr/tokenStart hd) (tr/nodeEnd retNode) kids))]
             (ParseResult :node node :rest retRes.rest)))
          ((= k "lt")
           (let [(tpRes (parseTypeParameters rem text))
                 (tpNode tpRes.node)]
             (if (or (tr/isErrorNode tpNode) (= (tr/nodeKind tpNode) "error"))
               (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                 (ParseResult :node node :rest tl))
               (let [(remTp tpRes.rest)
                     (spLp (skipTrivia remTp))
                     (trivLp (pairFirst spLp))
                     (remLp (pairSecond spLp))
                     (lpTok (optionOr (listHead remLp) (tr/makeToken "" 0 0)))
                     (tlLp (optionOr (listTail remLp) (list)))]
                 (if (!= (tr/tokenKind lpTok) "lparen")
                   (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                     (ParseResult :node node :rest tl))
                   (let [(paramsRes (parseFunctionParamsLoop tlLp text (list (tr/elemToken lpTok))))
                         (isArrow (checkArrowAfterCloseParen paramsRes.rest))]
                     (if isArrow
                       (let [(allParamElems paramsRes.elements)
                             (paramsStart (tr/tokenStart lpTok))
                             (paramsEnd (if (listEmpty? allParamElems) (tr/tokenEnd lpTok) (tr/elementEnd (optionOr (listLast allParamElems) (tr/elemToken lpTok)))))
                             (paramsNode (tr/makeNode "parameters" paramsStart paramsEnd allParamElems))
                             (spArrow (skipTrivia paramsRes.rest))
                             (trivArrow (pairFirst spArrow))
                             (arrowTok (optionOr (listHead (pairSecond spArrow)) (tr/makeToken "" 0 0)))
                             (spRet (skipTrivia (optionOr (listTail (pairSecond spArrow)) (list))))
                             (trivRet (pairFirst spRet))
                             (retRes (parseTypeExpr (pairSecond spRet) text 0))
                             (retNode retRes.node)
                             (kids (listAppend triv
                                     (cons (tr/elemNode tpNode)
                                       (listAppend trivLp
                                         (cons (tr/elemNode paramsNode)
                                           (listAppend trivArrow
                                             (cons (tr/elemToken arrowTok)
                                               (listAppend trivRet (list (tr/elemNode retNode))))))))))
                             (node (tr/makeNode "functionType" (tr/tokenStart hd) (tr/nodeEnd retNode) kids))]
                         (ParseResult :node node :rest retRes.rest))
                       (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
                         (ParseResult :node node :rest tl)))))))))
          ((= k "lparen")
           (let [(paramsRes (parseFunctionParamsLoop tl text (list (tr/elemToken hd))))
                 (isArrow (checkArrowAfterCloseParen paramsRes.rest))]
             (if isArrow
               (let [(allParamElems paramsRes.elements)
                     (paramsStart (tr/tokenStart hd))
                     (paramsEnd (if (listEmpty? allParamElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allParamElems) (tr/elemToken hd)))))
                     (paramsNode (tr/makeNode "parameters" paramsStart paramsEnd allParamElems))
                     (spArrow (skipTrivia paramsRes.rest))
                     (trivArrow (pairFirst spArrow))
                     (arrowTok (optionOr (listHead (pairSecond spArrow)) (tr/makeToken "" 0 0)))
                     (spRet (skipTrivia (optionOr (listTail (pairSecond spArrow)) (list))))
                     (trivRet (pairFirst spRet))
                     (retRes (parseTypeExpr (pairSecond spRet) text 0))
                     (retNode retRes.node)
                     (kids (listAppend triv
                             (cons (tr/elemNode paramsNode)
                               (listAppend trivArrow
                                 (cons (tr/elemToken arrowTok)
                                   (listAppend trivRet (list (tr/elemNode retNode))))))))
                     (node (tr/makeNode "functionType" (tr/tokenStart hd) (tr/nodeEnd retNode) kids))]
                 (ParseResult :node node :rest retRes.rest))
               (let [(innerRes (parseTypeExpr tl text 0))
                     (innerNode innerRes.node)
                     (spClose (skipTrivia innerRes.rest))
                     (trivClose (pairFirst spClose))
                     (expClose (expectClose (pairSecond spClose) "rparen" (tr/nodeEnd innerNode)))
                     (closeTok (pairFirst expClose))
                     (kids (listAppend triv
                             (cons (tr/elemToken hd)
                               (cons (tr/elemNode innerNode)
                                 (listAppend trivClose (list (tr/elemToken closeTok)))))))
                     (node (tr/makeNode "parenType" (tr/tokenStart hd) (tr/tokenEnd closeTok) kids))]
                 (ParseResult :node node :rest (pairSecond expClose))))))
          ((= k "lbracket")
           (let [(elemsRes (parseTupleElementsLoop tl text (list (tr/elemToken hd))))
                 (allElems (listAppend triv elemsRes.elements))
                 (start (tr/tokenStart hd))
                 (end (if (listEmpty? allElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allElems) (tr/elemToken hd)))))
                 (node (tr/makeNode "tupleType" start end allElems))]
             (ParseResult :node node :rest elemsRes.rest)))
          ((= k "lbrace")
           (if (isMappedTypeStart tl text)
             (parseMappedType hd tl text)
             (let [(elemsRes (parseTypeLiteralMembersLoop tl text (list (tr/elemToken hd))))
                   (allElems (listAppend triv elemsRes.elements))
                   (start (tr/tokenStart hd))
                   (end (if (listEmpty? allElems) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast allElems) (tr/elemToken hd)))))
                   (node (tr/makeNode "typeLiteral" start end allElems))]
               (ParseResult :node node :rest elemsRes.rest))))
          ((or (= k "ident") (or (= k "keyword") (= k "privateIdent")))
           (let [(spDot (skipTrivia tl))
                 (remDot (pairSecond spDot))]
             (parseTypeRefLoop hd (list (tr/elemToken hd)) tl text)))
          (else
           (let [(node (tr/makeNode "error" (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
             (ParseResult :node node :rest tl)))))))

fn parseTypeRefLoop rootTok: tr/Token acc: (List tr/TreeElement) toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (let [(start (tr/elementStart (optionOr (listHead acc) (tr/elemToken rootTok))))
            (end (tr/elementEnd (optionOr (listLast acc) (tr/elemToken rootTok))))
            (node (tr/makeNode "typeRef" start end acc))]
        (ParseResult :node node :rest toks))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "dot")
          (let [(spProp (skipTrivia tl))
                (trivProp (pairFirst spProp))
                (propTok (optionOr (listHead (pairSecond spProp)) (tr/makeToken "" 0 0)))
                (newAcc (listAppend acc
                          (listAppend triv
                            (cons (tr/elemToken hd)
                              (listAppend trivProp (list (tr/elemToken propTok)))))))]
            (parseTypeRefLoop rootTok newAcc (optionOr (listTail (pairSecond spProp)) (list)) text))
          (if (= k "lt")
            (let [(typeArgsRes (parseTypeArguments rem text))
                  (typeArgsNode typeArgsRes.node)]
              (if (or (tr/isErrorNode typeArgsNode) (= (tr/nodeKind typeArgsNode) "error"))
                (let [(start (tr/elementStart (optionOr (listHead acc) (tr/elemToken rootTok))))
                      (end (tr/elementEnd (optionOr (listLast acc) (tr/elemToken rootTok))))
                      (node (tr/makeNode "typeRef" start end acc))]
                  (ParseResult :node node :rest toks))
                (let [(newAcc (listAppend acc (listAppend triv (list (tr/elemNode typeArgsNode)))))
                      (start (tr/elementStart (optionOr (listHead newAcc) (tr/elemToken rootTok))))
                      (end (tr/elementEnd (optionOr (listLast newAcc) (tr/elemToken rootTok))))
                      (node (tr/makeNode "typeRef" start end newAcc))]
                  (ParseResult :node node :rest typeArgsRes.rest))))
            (let [(start (tr/elementStart (optionOr (listHead acc) (tr/elemToken rootTok))))
                  (end (tr/elementEnd (optionOr (listLast acc) (tr/elemToken rootTok))))
                  (node (tr/makeNode "typeRef" start end acc))]
              (ParseResult :node node :rest toks)))))))

fn parseTypePostfixLoop left: tr/Node toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "lbracket")
          (let [(sp2 (skipTrivia tl))
                (triv2 (pairFirst sp2))
                (rem2 (pairSecond sp2))]
            (if (and (not (listEmpty? rem2)) (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "rbracket"))
              (let [(rbTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
                    (kids (cons (tr/elemNode left)
                            (listAppend triv
                              (cons (tr/elemToken hd)
                                (listAppend triv2 (list (tr/elemToken rbTok)))))))
                    (arrNode (tr/makeNode "arrayType" (tr/nodeStart left) (tr/tokenEnd rbTok) kids))]
                (parseTypePostfixLoop arrNode (optionOr (listTail rem2) (list)) text))
              (let [(idxRes (parseTypeExpr rem2 text 0))
                    (idxNode idxRes.node)
                    (spClose (skipTrivia idxRes.rest))
                    (trivClose (pairFirst spClose))
                    (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                    (closeTok (pairFirst expClose))
                    (kids (cons (tr/elemNode left)
                            (listAppend triv
                              (cons (tr/elemToken hd)
                                (listAppend triv2
                                  (cons (tr/elemNode idxNode)
                                    (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                    (accessNode (tr/makeNode "indexedAccessType" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
                (parseTypePostfixLoop accessNode (pairSecond expClose) text))))
          (ParseResult :node left :rest toks)))))

fn parsePostfixType toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode (stringLength text) (stringLength text) (list)) :rest toks)
      (let [(primRes (parsePrimaryType rem text))]
        (parseTypePostfixLoop primRes.node primRes.rest text))))

fn parseIntersectionTypeLoop left: tr/Node toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "amp")
          (let [(spNext (skipTrivia tl))
                (trivNext (pairFirst spNext))
                (nextRes (parsePostfixType (pairSecond spNext) text))
                (nextNode nextRes.node)
                (kids (if (= (tr/nodeKind left) "intersectionType")
                        (listAppend (tr/nodeChildren left)
                          (listAppend triv
                            (cons (tr/elemToken hd)
                              (listAppend trivNext (list (tr/elemNode nextNode))))))
                        (cons (tr/elemNode left)
                          (listAppend triv
                            (cons (tr/elemToken hd)
                              (listAppend trivNext (list (tr/elemNode nextNode))))))))
                (interNode (tr/makeNode "intersectionType" (tr/nodeStart left) (tr/nodeEnd nextNode) kids))]
            (parseIntersectionTypeLoop interNode nextRes.rest text))
          (ParseResult :node left :rest toks)))))

fn parseIntersectionType toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "amp"))
      (let [(ampTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (spFirst (skipTrivia tl))
            (trivFirst (pairFirst spFirst))
            (firstRes (parsePostfixType (pairSecond spFirst) text))
            (firstNode firstRes.node)
            (kids (listAppend triv (cons (tr/elemToken ampTok) (listAppend trivFirst (list (tr/elemNode firstNode))))))
            (interNode (tr/makeNode "intersectionType" (tr/tokenStart ampTok) (tr/nodeEnd firstNode) kids))]
        (parseIntersectionTypeLoop interNode firstRes.rest text))
      (let [(firstRes (parsePostfixType toks text))]
        (parseIntersectionTypeLoop firstRes.node firstRes.rest text))))

fn parseUnionTypeLoop left: tr/Node toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "pipe")
          (let [(spNext (skipTrivia tl))
                (trivNext (pairFirst spNext))
                (nextRes (parseIntersectionType (pairSecond spNext) text))
                (nextNode nextRes.node)
                (kids (if (= (tr/nodeKind left) "unionType")
                        (listAppend (tr/nodeChildren left)
                          (listAppend triv
                            (cons (tr/elemToken hd)
                              (listAppend trivNext (list (tr/elemNode nextNode))))))
                        (cons (tr/elemNode left)
                          (listAppend triv
                            (cons (tr/elemToken hd)
                              (listAppend trivNext (list (tr/elemNode nextNode))))))))
                (unionNode (tr/makeNode "unionType" (tr/nodeStart left) (tr/nodeEnd nextNode) kids))]
            (parseUnionTypeLoop unionNode nextRes.rest text))
          (ParseResult :node left :rest toks)))))

fn parseUnionType toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "pipe"))
      (let [(pipeTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (spFirst (skipTrivia tl))
            (trivFirst (pairFirst spFirst))
            (firstRes (parseIntersectionType (pairSecond spFirst) text))
            (firstNode firstRes.node)
            (kids (listAppend triv (cons (tr/elemToken pipeTok) (listAppend trivFirst (list (tr/elemNode firstNode))))))
            (unionNode (tr/makeNode "unionType" (tr/tokenStart pipeTok) (tr/nodeEnd firstNode) kids))]
        (parseUnionTypeLoop unionNode firstRes.rest text))
      (let [(firstRes (parseIntersectionType toks text))]
        (parseUnionTypeLoop firstRes.node firstRes.rest text))))

fn parseConditionalType toks: (List tr/Token) text: String -> ParseResult
  (let [(unionRes (parseUnionType toks text))
        (unionNode unionRes.node)
        (rem unionRes.rest)
        (sp (skipTrivia rem))
        (triv (pairFirst sp))
        (remToks (pairSecond sp))]
    (if (listEmpty? remToks)
      unionRes
      (let [(hd (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail remToks) (list)))
            (sl (tokenSlice hd text))]
        (if (= sl "extends")
          (let [(spExt (skipTrivia tl))
                (trivExt (pairFirst spExt))
                (extRes (parseUnionType (pairSecond spExt) text))
                (extNode extRes.node)
                (remExt extRes.rest)
                (spQ (skipTrivia remExt))
                (trivQ (pairFirst spQ))
                (expQ (expectClose (pairSecond spQ) "question" (tr/nodeEnd extNode)))
                (qTok (pairFirst expQ))
                (tlQ (pairSecond expQ))
                (spTrue (skipTrivia tlQ))
                (trivTrue (pairFirst spTrue))
                (trueRes (parseTypeExpr (pairSecond spTrue) text 0))
                (trueNode trueRes.node)
                (remTrue trueRes.rest)
                (spColon (skipTrivia remTrue))
                (trivColon (pairFirst spColon))
                (expColon (expectClose (pairSecond spColon) "colon" (tr/nodeEnd trueNode)))
                (colonTok (pairFirst expColon))
                (tlColon (pairSecond expColon))
                (spFalse (skipTrivia tlColon))
                (trivFalse (pairFirst spFalse))
                (falseRes (parseConditionalType (pairSecond spFalse) text))
                (falseNode falseRes.node)
                (kids (cons (tr/elemNode unionNode)
                        (listAppend triv
                          (cons (tr/elemToken hd)
                            (listAppend trivExt
                              (cons (tr/elemNode extNode)
                                (listAppend trivQ
                                  (cons (tr/elemToken qTok)
                                    (listAppend trivTrue
                                      (cons (tr/elemNode trueNode)
                                        (listAppend trivColon
                                          (cons (tr/elemToken colonTok)
                                            (listAppend trivFalse (list (tr/elemNode falseNode)))))))))))))))
                (node (tr/makeNode "conditionalType" (tr/nodeStart unionNode) (tr/nodeEnd falseNode) kids))]
            (ParseResult :node node :rest falseRes.rest))
          unionRes))))

fn parseTypeExpr toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (parseConditionalType toks text)

fn trailingElementsLoop toks: (List tr/Token) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (listReverse acc)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (trailingElementsLoop tl (cons (tr/elemToken hd) acc))))

fn parseTypeTokens tokens: (List tr/Token) text: String -> tr/Node
  (let [(res (parseTypeExpr tokens text 0))
        (node res.node)
        (rem res.rest)
        (trailing (trailingElementsLoop rem (list)))
        (allKids (listAppend (list (tr/elemNode node)) trailing))
        (endOffset (if (listEmpty? trailing) (tr/nodeEnd node) (tr/elementEnd (optionOr (listLast trailing) (tr/elemNode node)))))]
    (tr/makeNode "type" (tr/nodeStart node) endOffset allKids))

fn firstErrorOffset elems: (List tr/TreeElement) -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n)
         (if (or (tr/isErrorNode n) (= (tr/nodeKind n) "error"))
           (some (tr/nodeStart n))
           (mt (firstErrorOffset (tr/nodeChildren n))
             ((some off) (some off))
             ((none) (firstErrorOffset tl)))))
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "error")
           (some (tr/tokenStart tok))
           (firstErrorOffset tl))))))

fn firstTrailingOffset elems: (List tr/TreeElement) seenExpr: Bool -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode _)
         (firstTrailingOffset tl true))
        ((tr/elemToken tok)
         (if (and seenExpr (not (isTriviaTok tok)))
           (some (tr/tokenStart tok))
           (firstTrailingOffset tl seenExpr))))))

fn parseType text: String -> (Result tr/Node String)
  (let [(tokens (lx/tokenize text))
        (root (parseTypeTokens tokens text))
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

fn isTypeNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "type")
    (or (= k "keywordType")
    (or (= k "literalType")
    (or (= k "templateLiteralType")
    (or (= k "typeRef")
    (or (= k "typeArguments")
    (or (= k "typeParameters")
    (or (= k "typeAnnotation")
    (or (= k "arrayType")
    (or (= k "tupleType")
    (or (= k "tupleElement")
    (or (= k "restType")
    (or (= k "functionType")
    (or (= k "constructorType")
    (or (= k "conditionalType")
    (or (= k "mappedType")
    (or (= k "typeLiteral")
    (or (= k "unionType")
    (or (= k "intersectionType")
    (or (= k "typeOperator")
    (or (= k "typeQuery")
    (or (= k "inferType")
    (or (= k "indexedAccessType")
        (= k "parenType")))))))))))))))))))))))))

fn typeNodeKind node: tr/Node -> String
  (tr/nodeKind node)

fn unwrapTypeNode root: tr/Node -> tr/Node
  (if (= (tr/nodeKind root) "type")
    (let [(kids (tr/nodeChildren root))
          (nodes (findChildNodes kids))]
      (if (listEmpty? nodes)
        root
        (optionOr (listHead nodes) root)))
    root)

fn formatTypesListLoop nodes: (List tr/Node) text: String acc: (List String) -> (List String)
  (if (listEmpty? nodes)
    (listReverse acc)
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))]
      (formatTypesListLoop tl text (cons (typeToSExpr hd text) acc))))

fn formatTypesList nodes: (List tr/Node) text: String -> String
  (stringJoin (formatTypesListLoop nodes text (list)) " ")

fn formatTupleElementsLoop elems: (List tr/TreeElement) text: String acc: (List String) -> (List String)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (formatTupleElementsLoop tl text acc))
        ((tr/elemNode n)
         (formatTupleElementsLoop tl text (cons (typeToSExpr n text) acc))))))

fn formatParamsListLoop nodes: (List tr/Node) text: String acc: (List String) -> (List String)
  (if (listEmpty? nodes)
    (listReverse acc)
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))]
      (formatParamsListLoop tl text (cons (typeToSExpr hd text) acc))))

fn typeToSExpr node: tr/Node text: String -> String
  (let [(n (unwrapTypeNode node))
        (k (tr/nodeKind n))
        (kids (tr/nodeChildren n))]
    (cond
      ((= k "keywordType")
       (let [(toks (findNonTriviaTokens kids))
             (firstTok (optionOr (listHead toks) (tr/makeToken "" (tr/nodeStart n) (tr/nodeEnd n))))]
         (tokenSlice firstTok text)))
      ((= k "literalType")
       (let [(toks (findNonTriviaTokens kids))
             (firstTok (optionOr (listHead toks) (tr/makeToken "" (tr/nodeStart n) (tr/nodeEnd n))))]
         (tokenSlice firstTok text)))
      ((= k "templateLiteralType")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           (str "(templateType " (tokenSlice (optionOr (listHead toks) (tr/makeToken "" 0 0)) text) ")")
           (let [(segs (listAppend (formatTypesListLoop nodes text (list)) (list)))]
             (str "(templateType " (stringJoin segs " ") ")")))))
      ((= k "typeRef")
       (let [(nodes (findChildNodes kids))
             (toks (findNonTriviaTokens kids))]
         (if (listEmpty? nodes)
           (stringTrim (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeEnd n)) ""))
           (let [(argNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
                 (typeName (stringTrim (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeStart argNode)) "")))
                 (argNodes (findChildNodes (tr/nodeChildren argNode)))
                 (argsStr (formatTypesList argNodes text))]
             (str "(typeRef " typeName (if (stringEmpty? argsStr) "" (str " " argsStr)) ")")))))
      ((= k "typeArguments")
       (let [(nodes (findChildNodes kids))]
         (str "(typeArgs " (formatTypesList nodes text) ")")))
      ((= k "typeParameters")
       (let [(nodes (findChildNodes kids))]
         (str "(typeParams " (formatTypesList nodes text) ")")))
      ((= k "typeAnnotation")
       (let [(nodes (findChildNodes kids))
             (typeNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(: " (typeToSExpr typeNode text) ")")))
      ((= k "typeParameter")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (name (tokenSlice (optionOr (listHead toks) (tr/makeToken "" 0 0)) text))
             (hasExtends (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "extends")) toks))
             (hasAssign (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "assign")) toks))]
         (cond
           ((and hasExtends hasAssign)
            (let [(bound (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
                  (def (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
              (str "(= (extends " name " " (typeToSExpr bound text) ") " (typeToSExpr def text) ")")))
           (hasExtends
            (let [(bound (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
              (str "(extends " name " " (typeToSExpr bound text) ")")))
           (hasAssign
            (let [(def (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
              (str "(= " name " " (typeToSExpr def text) ")")))
           (else name))))
      ((= k "parenType")
       (let [(nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           ""
           (typeToSExpr (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))) text))))
      ((= k "arrayType")
       (let [(nodes (findChildNodes kids))
             (inner (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(arrayType " (typeToSExpr inner text) ")")))
      ((= k "indexedAccessType")
       (let [(nodes (findChildNodes kids))
             (obj (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (idx (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(indexedAccess " (typeToSExpr obj text) " " (typeToSExpr idx text) ")")))
      ((= k "tupleType")
       (let [(items (formatTupleElementsLoop kids text (list)))]
         (str "(tupleType" (if (listEmpty? items) "" (str " " (stringJoin items " "))) ")")))
      ((= k "tupleElement")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (nameTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (name (tokenSlice nameTok text))
             (hasQ (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "question")) toks))
             (label (if hasQ (str name "?") name))
             (typeNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(elem " label " " (typeToSExpr typeNode text) ")")))
      ((= k "restType")
       (let [(nodes (findChildNodes kids))
             (inner (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(... " (typeToSExpr inner text) ")")))
      ((= k "typeOperator")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (op (tokenSlice (optionOr (listHead toks) (tr/makeToken "" 0 0)) text))
             (inner (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (typeToSExpr inner text) ")")))
      ((= k "typeQuery")
       (let [(nodes (findChildNodes kids))
             (inner (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(typeof " (cv/coverToSExpr inner text) ")")))
      ((= k "inferType")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (nameTok (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))
             (name (tokenSlice nameTok text))]
         (if (listEmpty? nodes)
           (str "(infer " name ")")
           (str "(infer " name " (extends " (typeToSExpr (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))) text) "))"))))
      ((= k "conditionalType")
       (let [(nodes (findChildNodes kids))
             (checkNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (extNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))
             (trueNode (optionOr (listGet nodes 2) (tr/makeErrorNode 0 0 (list))))
             (falseNode (optionOr (listGet nodes 3) (tr/makeErrorNode 0 0 (list))))]
         (str "(? (extends " (typeToSExpr checkNode text) " " (typeToSExpr extNode text) ") "
              (typeToSExpr trueNode text) " " (typeToSExpr falseNode text) ")")))
      ((= k "mappedType")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (hasMinusRo (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "minus")) toks))
             (hasRo (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "readonly")) toks))
             (roMod (if (and hasMinusRo hasRo) "-readonly " (if hasRo "readonly " "")))
             (nameTok (findMappedNameTok toks text))
             (name (tokenSlice nameTok text))
             (consNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (hasAs (listAny? (fn [(t tr/Token)] -> Bool (= (tokenSlice t text) "as")) toks))
             (asNode (if hasAs (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))) (tr/makeErrorNode 0 0 (list))))
             (valNode (if hasAs (optionOr (listGet nodes 2) (tr/makeErrorNode 0 0 (list))) (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list)))))
             (hasPlusQ (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "plus")) toks))
             (hasQ (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "question")) toks))
             (qMod (if (and hasPlusQ hasQ) " +?" (if hasQ " ?" "")))]
         (str "(mappedType " roMod name " (in " (typeToSExpr consNode text) ")"
              (if hasAs (str " (as " (typeToSExpr asNode text) ")") "")
              qMod " " (typeToSExpr valNode text) ")")))
      ((= k "typeLiteral")
       (let [(nodes (findChildNodes kids))
             (items (formatTypesListLoop nodes text (list)))]
         (str "(typeLiteral" (if (listEmpty? items) "" (str " " (stringJoin items " "))) ")")))
      ((= k "propertySignature")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (nameTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (name (tokenSlice nameTok text))
             (hasQ (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "question")) toks))
             (propName (if hasQ (str name "?") name))
             (typeNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(prop " propName " " (typeToSExpr typeNode text) ")")))
      ((= k "indexSignature")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (nameTok (optionOr (findFirstIdentTok toks) (tr/makeToken "" 0 0)))
             (name (tokenSlice nameTok text))
             (keyNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (valNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(index [" name " " (typeToSExpr keyNode text) "] " (typeToSExpr valNode text) ")")))
      ((= k "unionType")
       (let [(nodes (findChildNodes kids))
             (items (formatTypesListLoop nodes text (list)))]
         (str "(| " (stringJoin items " ") ")")))
      ((= k "intersectionType")
       (let [(nodes (findChildNodes kids))
             (items (formatTypesListLoop nodes text (list)))]
         (str "(& " (stringJoin items " ") ")")))
      ((= k "functionType")
       (let [(nodes (findChildNodes kids))
             (hasTp (and (not (listEmpty? nodes)) (= (tr/nodeKind (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list)))) "typeParameters")))
             (tpNode (if hasTp (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))) (tr/makeErrorNode 0 0 (list))))
             (paramsNode (if hasTp (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))) (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list)))))
             (retNode (if hasTp (optionOr (listGet nodes 2) (tr/makeErrorNode 0 0 (list))) (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list)))))
             (paramNodes (findChildNodes (tr/nodeChildren paramsNode)))
             (paramItems (formatParamsListLoop paramNodes text (list)))
             (paramsStr (str "(params" (if (listEmpty? paramItems) "" (str " " (stringJoin paramItems " "))) ")"))]
         (if hasTp
           (str "(fnType " (typeToSExpr tpNode text) " " paramsStr " " (typeToSExpr retNode text) ")")
           (str "(fnType " paramsStr " " (typeToSExpr retNode text) ")"))))
      ((= k "constructorType")
       (let [(nodes (findChildNodes kids))
             (paramsNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (paramNodes (findChildNodes (tr/nodeChildren paramsNode)))
             (paramItems (formatParamsListLoop paramNodes text (list)))
             (paramsStr (str "(params" (if (listEmpty? paramItems) "" (str " " (stringJoin paramItems " "))) ")"))
             (retNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(ctorType " paramsStr " " (typeToSExpr retNode text) ")")))
      ((= k "parameter")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (isRest (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "ellipsis")) toks))
             (nameTok (optionOr (findFirstParamNameTok toks text) (tr/makeToken "" 0 0)))
             (name (tokenSlice nameTok text))
             (hasQ (listAny? (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "question")) toks))
             (label (if hasQ (str name "?") name))
             (typeNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (paramStr (if (listEmpty? nodes) label (str "(param " label " " (typeToSExpr typeNode text) ")")))]
         (if isRest (str "(... " paramStr ")") paramStr)))
      (else
       (optionOr (stringSlice text (tr/nodeStart n) (tr/nodeEnd n)) ""))))

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

fn tsInfixPrecedence tok: tr/Token text: String hasNewlineBefore: Bool rem: (List tr/Token) -> Int64
  (let [(k (tr/tokenKind tok))]
    (cond
      ((= k "comma") 1)
      ((isAssignmentToken k) 3)
      ((= k "question") 4)
      ((= k "questionQuestion") 5)
      ((= k "pipePipe") 6)
      ((= k "ampAmp") 7)
      ((= k "pipe") 8)
      ((= k "caret") 9)
      ((= k "amp") 10)
      ((or (= k "eqEq") (or (= k "bangEq") (or (= k "eqEqEq") (= k "bangEqEq")))) 11)
      ((and (= k "lt") (some? (tryParseTypeArguments rem text))) 20)
      ((or (= k "lt") (or (= k "lte") (or (= k "gt") (= k "gte")))) 12)
      ((and (= k "keyword") (let [(sl (tokenSlice tok text))] (or (= sl "instanceof") (= sl "in")))) 12)
      ((and (= k "ident") (let [(sl (tokenSlice tok text))] (or (= sl "as") (= sl "satisfies")))) 12)
      ((or (= k "shl") (or (= k "shr") (= k "shru"))) 13)
      ((or (= k "plus") (= k "minus")) 14)
      ((or (= k "star") (or (= k "slash") (= k "percent"))) 15)
      ((= k "starStar") 16)
      ((and (or (= k "plusPlus") (= k "minusMinus")) (not hasNewlineBefore)) 18)
      ((= k "bang") 18)
      ((or (= k "dot") (or (= k "questionDot") (or (= k "lbracket") (= k "lparen")))) 20)
      ((or (= k "templateNoSub") (= k "templateHead")) 20)
      (else 0)))

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
                      (subRes (parseTsExpr (pairSecond sp2) text 1))
                      (subNode subRes.node)
                      (sprKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode subNode)))))
                      (sprNode (tr/makeNode "spreadExpr" (tr/tokenStart hd) (tr/nodeEnd subNode) sprKids))
                      (newAcc (cons (tr/elemNode sprNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc))
                (let [(accWithTriv (listAppend (listReverse triv) acc))
                      (subRes (parseTsExpr rem text 1))
                      (subNode subRes.node)
                      (newAcc (cons (tr/elemNode subNode) accWithTriv))]
                  (parseElementsListUntil subRes.rest text closeKind newAcc)))))))))

fn parseTsPrefix toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode (stringLength text) (stringLength text) (list)) :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "lt")
          (let [(typeRes (parseTypeExpr tl text 0))
                (typeNode typeRes.node)
                (remType typeRes.rest)
                (spGt (skipTrivia remType))
                (trivGt (pairFirst spGt))
                (expGt (expectClose (pairSecond spGt) "gt" (tr/nodeEnd typeNode)))
                (gtTok (pairFirst expGt))
                (tlGt (pairSecond expGt))
                (innerRes (parseTsExpr tlGt text 17))
                (innerNode innerRes.node)
                (kids (listAppend triv
                        (cons (tr/elemToken hd)
                          (cons (tr/elemNode typeNode)
                            (listAppend trivGt
                              (cons (tr/elemToken gtTok) (list (tr/elemNode innerNode))))))))
                (node (tr/makeNode "typeAssertion" (tr/tokenStart hd) (tr/nodeEnd innerNode) kids))]
            (ParseResult :node node :rest innerRes.rest))
          (cv/parseCoverExpr toks text 17)))))

fn parseTsPrattLoop left: tr/Node toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node left :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))
            (hasNl (hasNewlineElements triv text))
            (prec (tsInfixPrecedence hd text hasNl rem))]
        (if (<= prec minPrec)
          (ParseResult :node left :rest toks)
          (cond
            ((= k "bang")
             (let [(kids (cons (tr/elemNode left) (listAppend triv (list (tr/elemToken hd)))))
                   (newNode (tr/makeNode "nonNullExpr" (tr/nodeStart left) (tr/tokenEnd hd) kids))]
               (parseTsPrattLoop newNode tl text minPrec)))
            ((= sl "as")
             (let [(spType (skipTrivia tl))
                   (trivType (pairFirst spType))
                   (typeRes (parseTypeExpr (pairSecond spType) text 0))
                   (typeNode typeRes.node)
                   (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivType (list (tr/elemNode typeNode)))))))
                   (newNode (tr/makeNode "asExpr" (tr/nodeStart left) (tr/nodeEnd typeNode) kids))]
               (parseTsPrattLoop newNode typeRes.rest text minPrec)))
            ((= sl "satisfies")
             (let [(spType (skipTrivia tl))
                   (trivType (pairFirst spType))
                   (typeRes (parseTypeExpr (pairSecond spType) text 0))
                   (typeNode typeRes.node)
                   (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivType (list (tr/elemNode typeNode)))))))
                   (newNode (tr/makeNode "satisfiesExpr" (tr/nodeStart left) (tr/nodeEnd typeNode) kids))]
               (parseTsPrattLoop newNode typeRes.rest text minPrec)))
            ((and (= k "lt") (some? (tryParseTypeArguments rem text)))
             (let [(typeArgsRes (optionOr (tryParseTypeArguments rem text) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest (list))))
                   (typeArgsNode typeArgsRes.node)
                   (remAfterArgs typeArgsRes.rest)
                   (spLp (skipTrivia remAfterArgs))
                   (trivLp (pairFirst spLp))
                   (remLp (pairSecond spLp))
                   (lpTok (optionOr (listHead remLp) (tr/makeToken "" 0 0)))
                   (tlLp (optionOr (listTail remLp) (list)))
                   (argsRes (parseElementsListUntil tlLp text "rparen" (list)))
                   (allArgs (cons (tr/elemToken lpTok) argsRes.elements))
                   (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd lpTok) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken lpTok)))))
                   (kids (cons (tr/elemNode left)
                           (listAppend triv
                             (cons (tr/elemNode typeArgsNode)
                               (listAppend trivLp allArgs)))))
                   (newNode (tr/makeNode "callExpr" (tr/nodeStart left) closeEnd kids))]
               (parseTsPrattLoop newNode argsRes.rest text minPrec)))
            ((= k "dot")
             (let [(spProp (skipTrivia tl))
                   (trivProp (pairFirst spProp))
                   (remProp (pairSecond spProp))
                   (propTok (optionOr (listHead remProp) (tr/makeToken "ident" 0 0)))
                   (tlProp (optionOr (listTail remProp) (list)))
                   (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivProp (list (tr/elemToken propTok)))))))
                   (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd propTok) kids))]
               (parseTsPrattLoop newLeft tlProp text minPrec)))
            ((= k "lbracket")
             (let [(spIdx (skipTrivia tl))
                   (trivIdx (pairFirst spIdx))
                   (idxRes (parseTsExpr (pairSecond spIdx) text 0))
                   (idxNode idxRes.node)
                   (spClose (skipTrivia idxRes.rest))
                   (trivClose (pairFirst spClose))
                   (expClose (expectClose (pairSecond spClose) "rbracket" (tr/nodeEnd idxNode)))
                   (closeTok (pairFirst expClose))
                   (tlClose (pairSecond expClose))
                   (kids (cons (tr/elemNode left) (listAppend triv (cons (tr/elemToken hd) (listAppend trivIdx (cons (tr/elemNode idxNode) (listAppend trivClose (list (tr/elemToken closeTok)))))))))
                   (newLeft (tr/makeNode "memberExpr" (tr/nodeStart left) (tr/tokenEnd closeTok) kids))]
               (parseTsPrattLoop newLeft tlClose text minPrec)))
            ((= k "lparen")
             (let [(argsRes (parseElementsListUntil tl text "rparen" (list)))
                   (allArgs (cons (tr/elemToken hd) argsRes.elements))
                   (closeEnd (if (listEmpty? argsRes.elements) (tr/tokenEnd hd) (tr/elementEnd (optionOr (listLast argsRes.elements) (tr/elemToken hd)))))
                   (kids (cons (tr/elemNode left) (listAppend triv allArgs)))
                   (newLeft (tr/makeNode "callExpr" (tr/nodeStart left) closeEnd kids))]
               (parseTsPrattLoop newLeft argsRes.rest text minPrec)))
            ((= k "question")
             (let [(spCons (skipTrivia tl))
                   (trivCons (pairFirst spCons))
                   (consRes (parseTsExpr (pairSecond spCons) text 3))
                   (consNode consRes.node)
                   (spColon (skipTrivia consRes.rest))
                   (trivColon (pairFirst spColon))
                   (expColon (expectClose (pairSecond spColon) "colon" (tr/nodeEnd consNode)))
                   (colonTok (pairFirst expColon))
                   (tlColon (pairSecond expColon))
                   (spAlt (skipTrivia tlColon))
                   (trivAlt (pairFirst spAlt))
                   (altRes (parseTsExpr (pairSecond spAlt) text 3))
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
               (parseTsPrattLoop newLeft altRes.rest text minPrec)))
            ((isAssignmentToken k)
             (let [(spRhs (skipTrivia tl))
                   (trivRhs (pairFirst spRhs))
                   (rhsRes (parseTsExpr (pairSecond spRhs) text 2))
                   (rhsNode rhsRes.node)
                   (kids (cons (tr/elemNode left)
                           (listAppend triv
                             (cons (tr/elemToken hd)
                               (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                   (newLeft (tr/makeNode "assignExpr" (tr/nodeStart left) (tr/nodeEnd rhsNode) kids))]
               (parseTsPrattLoop newLeft rhsRes.rest text minPrec)))
            ((= k "comma")
             (let [(spRhs (skipTrivia tl))
                   (trivRhs (pairFirst spRhs))
                   (rhsRes (parseTsExpr (pairSecond spRhs) text 1))
                   (rhsNode rhsRes.node)
                   (kids (cons (tr/elemNode left)
                           (listAppend triv
                             (cons (tr/elemToken hd)
                               (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                   (newLeft (tr/makeNode "seqExpr" (tr/nodeStart left) (tr/nodeEnd rhsNode) kids))]
               (parseTsPrattLoop newLeft rhsRes.rest text minPrec)))
            (else
             (let [(spRhs (skipTrivia tl))
                   (trivRhs (pairFirst spRhs))
                   (nextMinPrec (if (= prec 16) (- prec 1) prec))
                   (rhsRes (parseTsExpr (pairSecond spRhs) text nextMinPrec))
                   (rhsNode rhsRes.node)
                   (isLog (or (= k "questionQuestion") (or (= k "pipePipe") (= k "ampAmp"))))
                   (kind (if isLog "logicalExpr" "binaryExpr"))
                   (kids (cons (tr/elemNode left)
                           (listAppend triv
                             (cons (tr/elemToken hd)
                               (listAppend trivRhs (list (tr/elemNode rhsNode)))))))
                   (newLeft (tr/makeNode kind (tr/nodeStart left) (tr/nodeEnd rhsNode) kids))]
               (parseTsPrattLoop newLeft rhsRes.rest text minPrec))))))))

fn parseTsExpr toks: (List tr/Token) text: String minPrec: Int64 -> ParseResult
  (let [(prefixRes (parseTsPrefix toks text))]
    (parseTsPrattLoop prefixRes.node prefixRes.rest text minPrec))

fn parseTsTokens tokens: (List tr/Token) text: String -> tr/Node
  (let [(res (parseTsExpr tokens text 0))
        (node res.node)
        (rem res.rest)
        (trailing (trailingElementsLoop rem (list)))
        (allKids (listAppend (list (tr/elemNode node)) trailing))
        (endOffset (if (listEmpty? trailing) (tr/nodeEnd node) (tr/elementEnd (optionOr (listLast trailing) (tr/elemNode node)))))]
    (tr/makeNode "expression" (tr/nodeStart node) endOffset allKids))

fn parseTsText text: String -> tr/Node
  (let [(tokens (lx/tokenize text))]
    (parseTsTokens tokens text))

fn parseTs text: String -> (Result tr/Node String)
  (let [(tokens (lx/tokenize text))
        (root (parseTsTokens tokens text))
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

fn formatTsArgs nodes: (List tr/Node) text: String -> String
  (if (listEmpty? nodes)
    ""
    (let [(hd (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))
          (s (tsToSExpr hd text))
          (rest (formatTsArgs tl text))]
      (if (stringEmpty? rest)
        s
        (str s " " rest))))

fn tsToSExpr node: tr/Node text: String -> String
  (let [(n (cv/unwrapExpressionNode node))
        (k (tr/nodeKind n))
        (kids (tr/nodeChildren n))]
    (cond
      ((= k "asExpr")
       (let [(nodes (findChildNodes kids))
             (exprNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (typeNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(as " (tsToSExpr exprNode text) " " (typeToSExpr typeNode text) ")")))
      ((= k "satisfiesExpr")
       (let [(nodes (findChildNodes kids))
             (exprNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (typeNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(satisfies " (tsToSExpr exprNode text) " " (typeToSExpr typeNode text) ")")))
      ((= k "nonNullExpr")
       (let [(nodes (findChildNodes kids))
             (exprNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(! " (tsToSExpr exprNode text) ")")))
      ((= k "typeAssertion")
       (let [(nodes (findChildNodes kids))
             (typeNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (exprNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(typeAssert " (typeToSExpr typeNode text) " " (tsToSExpr exprNode text) ")")))
      ((= k "callExpr")
       (let [(nodes (findChildNodes kids))
             (firstNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (hasTypeArgs (and (>= (listLength nodes) 2) (= (tr/nodeKind (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list)))) "typeArguments")))]
         (if hasTypeArgs
           (let [(typeArgsNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))
                 (argNodes (optionOr (listTail (optionOr (listTail nodes) (list))) (list)))
                 (argsStr (formatTsArgs argNodes text))]
             (str "(call " (typeToSExpr typeArgsNode text) " " (tsToSExpr firstNode text) (if (stringEmpty? argsStr) "" (str " " argsStr)) ")"))
           (let [(argNodes (optionOr (listTail nodes) (list)))
                 (argsStr (formatTsArgs argNodes text))]
             (str "(call " (tsToSExpr firstNode text) (if (stringEmpty? argsStr) "" (str " " argsStr)) ")")))))
      ((or (= k "binaryExpr") (or (= k "logicalExpr") (= k "seqExpr")))
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (tsToSExpr leftNode text) " " (tsToSExpr rightNode text) ")")))
      ((= k "assignExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (rightNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (tsToSExpr leftNode text) " " (tsToSExpr rightNode text) ")")))
      ((= k "unaryExpr")
       (let [(toks (findNonTriviaTokens kids))
             (nodes (findChildNodes kids))
             (opTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
             (op (tokenSlice opTok text))
             (argNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (str "(" op " " (tsToSExpr argNode text) ")")))
      ((= k "conditionalExpr")
       (let [(nodes (findChildNodes kids))
             (testNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (consNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))
             (altNode (optionOr (listGet nodes 2) (tr/makeErrorNode 0 0 (list))))]
         (str "(? " (tsToSExpr testNode text) " " (tsToSExpr consNode text) " " (tsToSExpr altNode text) ")")))
      ((= k "memberExpr")
       (let [(nodes (findChildNodes kids))
             (toks (findNonTriviaTokens kids))
             (leftNode (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))]
         (if (>= (listLength nodes) 2)
           (let [(idxNode (optionOr (listGet nodes 1) (tr/makeErrorNode 0 0 (list))))]
             (str "(index " (tsToSExpr leftNode text) " " (tsToSExpr idxNode text) ")"))
           (let [(lastTok (optionOr (listLast toks) (tr/makeToken "" 0 0)))
                 (prop (tokenSlice lastTok text))]
             (str "(. " (tsToSExpr leftNode text) " " prop ")")))))
      ((= k "parenExpr")
       (let [(nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           ""
           (tsToSExpr (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))) text))))
      (else
       (cv/coverToSExpr n text))))
