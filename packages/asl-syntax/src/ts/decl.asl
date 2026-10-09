(module asl-syntax/ts/decl
  :x [parse
      parseTsModule
      parseTsModuleTokens
      parseTsDecl
      parseInterfaceDecl
      parseTypeAliasDecl
      parseEnumDecl
      parseNamespaceDecl
      parseClassDecl
      parseFunctionDecl
      declToSExpr
      isDeclNode
      declKind ParseResult parseReturnTypeOpt parseTsExportDecl parseTsImportDecl]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)
      (asl-syntax/js/stmt :a stmt)
      (asl-syntax/js/module :a jsm)
      (asl-syntax/ts/types :a ts)])

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
             (stringContains? (tokenSlice tok text) "\n")
             (hasNewlineElements tl text))))
        ((tr/elemNode _)
         (hasNewlineElements tl text)))))

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

fn firstErrorOffset elems: (List tr/TreeElement) -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (firstErrorOffset tl))
        ((tr/elemNode node)
         (if (tr/isErrorNode node)
           (some (tr/nodeStart node))
           (mt (firstErrorOffset (tr/nodeChildren node))
             ((some off) (some off))
             ((none) (firstErrorOffset tl))))))))

fn expectClose rem: (List tr/Token) kind: String endPos: Int64 -> (Pair tr/Token (List tr/Token))
  (if (listEmpty? rem)
    (pair (tr/makeToken "error" endPos endPos) rem)
    (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
      (if (= (tr/tokenKind hd) kind)
        (pair hd (optionOr (listTail rem) (list)))
        (pair (tr/makeToken "error" endPos endPos) rem))))

fn isModifierWord word: String -> Bool
  (or (= word "public")
  (or (= word "private")
  (or (= word "protected")
  (or (= word "readonly")
  (or (= word "static")
  (or (= word "abstract")
  (or (= word "override")
  (or (= word "declare")
  (or (= word "accessor")
      (= word "async"))))))))))

fn isModifierToken toks: (List tr/Token) text: String -> Bool
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      false
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (word (tokenSlice hd text))]
        (if (not (isModifierWord word))
          false
          (let [(spNext (skipTrivia tl))
                (remNext (pairSecond spNext))]
            (if (listEmpty? remNext)
              false
              (let [(nextTok (optionOr (listHead remNext) (tr/makeToken "" 0 0)))
                    (nk (tr/tokenKind nextTok))]
                (not (or (= nk "colon")
                     (or (= nk "assign")
                     (or (= nk "semicolon")
                     (or (= nk "comma")
                     (or (= nk "rparen")
                     (or (= nk "rbrace")
                     (or (= nk "lparen")
                         (= nk "question"))))))))))))))))

fn parseModifiersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (if (isModifierToken toks text)
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))
          (modTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail rem) (list)))
          (newAcc (listAppend acc (listAppend triv (list (tr/elemToken modTok)))))]
      (parseModifiersLoop tl text newAcc))
    (ElementsResult :elements acc :rest toks))

fn parseSingleDecorator toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(atTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind atTok) "at")
          (ParseResult :node (tr/makeErrorNode (tr/tokenStart atTok) (tr/tokenEnd atTok) triv) :rest toks)
          (let [(spExpr (skipTrivia tl))
                (trivExpr (pairFirst spExpr))
                (exprRes (ts/parseTsExpr (pairSecond spExpr) text 1))
                (exprNode exprRes.node)
                (kids (listAppend triv (cons (tr/elemToken atTok) (listAppend trivExpr (list (tr/elemNode exprNode))))))
                (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken atTok))))
                (end (tr/nodeEnd exprNode))
                (decNode (tr/makeNode "decorator" start end kids))]
            (ParseResult :node decNode :rest exprRes.rest))))))

fn parseDecoratorsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements (listAppend acc triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "at")
          (let [(accWithTriv (listAppend acc triv))
                (decRes (parseSingleDecorator rem text))
                (decNode decRes.node)]
            (parseDecoratorsLoop decRes.rest text (listAppend accWithTriv (list (tr/elemNode decNode)))))
          (ElementsResult :elements (listAppend acc triv) :rest rem)))))

fn parseDottedIdentLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(dotTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind dotTok) "dot")
          (ElementsResult :elements acc :rest toks)
          (let [(spId (skipTrivia tl))
                (trivId (pairFirst spId))
                (remId (pairSecond spId))]
            (if (listEmpty? remId)
              (ElementsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken dotTok)))) :rest tl)
              (let [(idTok (optionOr (listHead remId) (tr/makeToken "" 0 0)))
                    (tlId (optionOr (listTail remId) (list)))]
                (if (!= (tr/tokenKind idTok) "ident")
                  (ElementsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken dotTok)))) :rest tl)
                  (let [(newAcc (listAppend acc (listAppend triv (cons (tr/elemToken dotTok) (listAppend trivId (list (tr/elemToken idTok)))))))]
                    (parseDottedIdentLoop tlId text newAcc))))))))))

fn parseTypeRef toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (!= (tr/tokenKind hd) "ident")
          (ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) triv) :rest toks)
          (let [(kids (listAppend triv (list (tr/elemToken hd))))
                (restAfterDotted (parseDottedIdentLoop tl text kids))
                (dottedKids restAfterDotted.elements)
                (remAfterDot restAfterDotted.rest)
                (spArgs (skipTrivia remAfterDot))
                (trivArgs (pairFirst spArgs))
                (remArgs (pairSecond spArgs))]
            (if (and (not (listEmpty? remArgs)) (= (tr/tokenKind (optionOr (listHead remArgs) (tr/makeToken "" 0 0))) "lt"))
              (let [(argsRes (ts/parseTypeArguments remArgs text))
                    (argsNode argsRes.node)
                    (allKids (listAppend dottedKids (listAppend trivArgs (list (tr/elemNode argsNode)))))
                    (start (tr/elementStart (optionOr (listHead allKids) (tr/elemToken hd))))
                    (end (tr/nodeEnd argsNode))
                    (node (tr/makeNode "typeReference" start end allKids))]
                (ParseResult :node node :rest argsRes.rest))
              (let [(start (tr/elementStart (optionOr (listHead dottedKids) (tr/elemToken hd))))
                    (end (tr/elementEnd (optionOr (listLast dottedKids) (tr/elemToken hd))))
                    (node (tr/makeNode "typeReference" start end dottedKids))]
                (ParseResult :node node :rest remAfterDot))))))))

fn parseTypeRefListLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(refRes (parseTypeRef rem text))
            (refNode refRes.node)
            (accWithRef (listAppend acc (listAppend triv (list (tr/elemNode refNode)))))
            (remRef refRes.rest)
            (spComma (skipTrivia remRef))
            (trivComma (pairFirst spComma))
            (remComma (pairSecond spComma))]
        (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
          (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                (tlComma (optionOr (listTail remComma) (list)))
                (accWithComma (listAppend accWithRef (listAppend trivComma (list (tr/elemToken commaTok)))))]
            (parseTypeRefListLoop tlComma text accWithComma))
          (ElementsResult :elements accWithRef :rest remRef)))))

fn parseTypeParamsOpt toks: (List tr/Token) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "lt"))
      (let [(tpRes (ts/parseTypeParameters rem text))
            (tpNode tpRes.node)]
        (pair (listAppend triv (list (tr/elemNode tpNode))) tpRes.rest))
      (pair (list) toks)))

fn parseReturnTypeOpt toks: (List tr/Token) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "colon"))
      (let [(annRes (ts/parseTypeAnnotation rem text))
            (annNode annRes.node)]
        (pair (listAppend triv (list (tr/elemNode annNode))) annRes.rest))
      (pair (list) toks)))

fn parseSingleParam toks: (List tr/Token) text: String -> ParseResult
  (let [(decsRes (parseDecoratorsLoop toks text (list)))
        (decElems decsRes.elements)
        (remAfterDecs decsRes.rest)
        (modsRes (parseModifiersLoop remAfterDecs text (list)))
        (modElems modsRes.elements)
        (remAfterMods modsRes.rest)
        (sp (skipTrivia remAfterMods))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 (listAppend decElems modElems)) :rest rem)
      (let [(firstTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (fk (tr/tokenKind firstTok))
            (isDotDotDot (or (= fk "ellipsis") (= fk "dotDotDot")))
            (spName (if isDotDotDot (skipTrivia tl) (pair (list) rem)))
            (trivName (pairFirst spName))
            (remName (pairSecond spName))
            (nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
            (tlName (optionOr (listTail remName) (list)))
            (nk (tr/tokenKind nameTok))
            (isPat (or (= nk "lbracket") (= nk "lbrace")))
            (patRes (if isPat (stmt/parsePattern remName text) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest tlName)))
            (patNode patRes.node)
            (nameKids (if isDotDotDot
                        (if isPat
                          (listAppend triv (cons (tr/elemToken firstTok) (listAppend trivName (list (tr/elemNode patNode)))))
                          (listAppend triv (cons (tr/elemToken firstTok) (listAppend trivName (list (tr/elemToken nameTok))))))
                        (if isPat
                          (listAppend triv (list (tr/elemNode patNode)))
                          (listAppend triv (list (tr/elemToken nameTok))))))
            (remAfterName (if isPat patRes.rest tlName))
            (spQ (skipTrivia remAfterName))
            (trivQ (pairFirst spQ))
            (remQ (pairSecond spQ))
            (hasQ (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "question")))
            (qPair (if hasQ
                     (let [(qTok (optionOr (listHead remQ) (tr/makeToken "" 0 0)))
                           (tlQ (optionOr (listTail remQ) (list)))]
                       (pair (listAppend trivQ (list (tr/elemToken qTok))) tlQ))
                     (pair (list) remAfterName)))
            (qElems (pairFirst qPair))
            (remAfterQ (pairSecond qPair))
            (kidsWithQ (listAppend nameKids qElems))
            (spColon (skipTrivia remAfterQ))
            (trivColon (pairFirst spColon))
            (remColon (pairSecond spColon))
            (hasColon (and (not (listEmpty? remColon)) (= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon")))
            (annPair (if hasColon
                       (let [(annRes (ts/parseTypeAnnotation remColon text))]
                         (pair (listAppend trivColon (list (tr/elemNode annRes.node))) annRes.rest))
                       (pair (list) remAfterQ)))
            (annElems (pairFirst annPair))
            (remAfterAnn (pairSecond annPair))
            (kidsWithAnn (listAppend kidsWithQ annElems))
            (spEq (skipTrivia remAfterAnn))
            (trivEq (pairFirst spEq))
            (remEq (pairSecond spEq))
            (hasEq (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign")))
            (eqTok (if hasEq (optionOr (listHead remEq) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
            (tlEq (if hasEq (optionOr (listTail remEq) (list)) (list)))
            (spInit (if hasEq (skipTrivia tlEq) (pair (list) (list))))
            (trivInit (pairFirst spInit))
            (remInit (pairSecond spInit))
            (initRes (if hasEq (ts/parseTsExpr remInit text 1) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remAfterAnn)))
            (remAfterInit (if hasEq initRes.rest remAfterAnn))
            (kidsWithInit (if hasEq (listAppend kidsWithAnn (listAppend trivEq (cons (tr/elemToken eqTok) (listAppend trivInit (list (tr/elemNode initRes.node)))))) kidsWithAnn))
            (allKids (listAppend decElems (listAppend modElems kidsWithInit)))
            (start (if (listEmpty? allKids) (tr/tokenStart firstTok) (tr/elementStart (optionOr (listHead allKids) (tr/elemToken firstTok)))))
            (end (if (listEmpty? allKids) (tr/tokenEnd firstTok) (tr/elementEnd (optionOr (listLast allKids) (tr/elemToken firstTok)))))
            (nodeKind (if (listEmpty? modElems) "parameter" "parameterProperty"))
            (node (tr/makeNode nodeKind start end allKids))]
        (ParseResult :node node :rest remAfterInit))))

fn parseParamsListLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rparen")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(paramRes (parseSingleParam rem text))
                (paramNode paramRes.node)
                (accWithParam (listAppend acc (listAppend triv (list (tr/elemNode paramNode)))))
                (remParam paramRes.rest)
                (spComma (skipTrivia remParam))
                (trivComma (pairFirst spComma))
                (remComma (pairSecond spComma))]
            (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
              (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                    (tlComma (optionOr (listTail remComma) (list)))
                    (accWithComma (listAppend accWithParam (listAppend trivComma (list (tr/elemToken commaTok)))))]
                (parseParamsListLoop tlComma text accWithComma))
              (ElementsResult :elements accWithParam :rest remParam)))))))

fn parseParamsParenthesized toks: (List tr/Token) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (or (listEmpty? rem) (!= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "lparen"))
      (pair (list) toks)
      (let [(lpTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem) (list)))
            (loopRes (parseParamsListLoop tlLp text (list)))
            (paramElems loopRes.elements)
            (remAfterLoop loopRes.rest)
            (spRp (skipTrivia remAfterLoop))
            (trivRp (pairFirst spRp))
            (remRp (pairSecond spRp))
            (closePair (expectClose remRp "rparen" (tr/tokenEnd lpTok)))
            (rpTok (pairFirst closePair))
            (remAfterClose (pairSecond closePair))
            (allElems (listAppend triv (cons (tr/elemToken lpTok) (listAppend paramElems (listAppend trivRp (list (tr/elemToken rpTok)))))))]
        (pair allElems remAfterClose))))

fn parseOptionalSemiOrComma toks: (List tr/Token) -> (Pair (List tr/TreeElement) (List tr/Token))
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (pair triv rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind hd))]
        (if (or (= k "semicolon") (= k "comma"))
          (pair (listAppend triv (list (tr/elemToken hd))) (optionOr (listTail rem) (list)))
          (pair triv rem)))))

fn parseMemberName toks: (List tr/Token) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (pair (list) toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (cond
          ((= k "lbracket")
           (let [(exprRes (ts/parseTsExpr tl text 0))
                 (exprNode exprRes.node)
                 (remExpr exprRes.rest)
                 (spRb (skipTrivia remExpr))
                 (trivRb (pairFirst spRb))
                 (remRb (pairSecond spRb))
                 (closePair (expectClose remRb "rbracket" (tr/nodeEnd exprNode)))
                 (rbTok (pairFirst closePair))
                 (remAfterClose (pairSecond closePair))
                 (kids (listAppend triv (cons (tr/elemToken hd) (cons (tr/elemNode exprNode) (listAppend trivRb (list (tr/elemToken rbTok)))))))]
             (pair kids remAfterClose)))
          (else
           (pair (listAppend triv (list (tr/elemToken hd))) tl))))))

fn parseIndexSignatureRest nameElem: (List tr/TreeElement) toks: (List tr/Token) text: String prefixElems: (List tr/TreeElement) -> ParseResult
  (let [(spColon (skipTrivia toks))
        (trivColon (pairFirst spColon))
        (remColon (pairSecond spColon))
        (typeRes (ts/parseTypeAnnotation remColon text))
        (typeNode typeRes.node)
        (remType typeRes.rest)
        (semiPair (parseOptionalSemiOrComma remType))
        (semiElems (pairFirst semiPair))
        (remSemi (pairSecond semiPair))
        (kids (listAppend prefixElems (listAppend nameElem (listAppend trivColon (cons (tr/elemNode typeNode) semiElems)))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0)))))
        (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken (tr/makeToken "" 0 0)))))
        (node (tr/makeNode "indexSignature" start end kids))]
    (ParseResult :node node :rest remSemi))

fn isIndexSignatureStart toks: (List tr/Token) -> Bool
  (let [(sp (skipTrivia toks))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      false
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (!= (tr/tokenKind hd) "lbracket")
          false
          (let [(tl (optionOr (listTail rem) (list)))
                (sp2 (skipTrivia tl))
                (rem2 (pairSecond sp2))]
            (if (listEmpty? rem2)
              false
              (let [(idTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
                    (tl2 (optionOr (listTail rem2) (list)))
                    (sp3 (skipTrivia tl2))
                    (rem3 (pairSecond sp3))]
                (and (= (tr/tokenKind idTok) "ident")
                     (and (not (listEmpty? rem3))
                          (= (tr/tokenKind (optionOr (listHead rem3) (tr/makeToken "" 0 0))) "colon"))))))))))

fn parseIndexSignature toks: (List tr/Token) text: String prefixElems: (List tr/TreeElement) -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))
        (lbTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (tlLb (optionOr (listTail rem) (list)))
        (spId (skipTrivia tlLb))
        (trivId (pairFirst spId))
        (remId (pairSecond spId))
        (idTok (optionOr (listHead remId) (tr/makeToken "" 0 0)))
        (tlId (optionOr (listTail remId) (list)))
        (annRes (ts/parseTypeAnnotation tlId text))
        (annNode annRes.node)
        (remAnn annRes.rest)
        (spRb (skipTrivia remAnn))
        (trivRb (pairFirst spRb))
        (remRb (pairSecond spRb))
        (closePair (expectClose remRb "rbracket" (tr/nodeEnd annNode)))
        (rbTok (pairFirst closePair))
        (remAfterClose (pairSecond closePair))
        (nameKids (listAppend triv (cons (tr/elemToken lbTok) (listAppend trivId (cons (tr/elemToken idTok) (cons (tr/elemNode annNode) (listAppend trivRb (list (tr/elemToken rbTok)))))))))]
    (parseIndexSignatureRest nameKids remAfterClose text prefixElems))

fn parseInterfaceMember toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (w (tokenSlice hd text))]
        (cond
          ((or (= k "semicolon") (= k "comma"))
           (let [(kids (listAppend triv (list (tr/elemToken hd))))
                 (node (tr/makeNode "emptyMember" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
             (ParseResult :node node :rest tl)))
          ((isIndexSignatureStart rem)
           (parseIndexSignature rem text triv))
          ((and (= w "readonly") (isIndexSignatureStart tl))
           (let [(roKids (listAppend triv (list (tr/elemToken hd))))]
             (parseIndexSignature tl text roKids)))
          ((or (= k "lt") (= k "lparen"))
           (let [(tpPair (parseTypeParamsOpt rem text))
                 (tpElems (pairFirst tpPair))
                 (remTp (pairSecond tpPair))
                 (paramsPair (parseParamsParenthesized remTp text))
                 (paramElems (pairFirst paramsPair))
                 (remParams (pairSecond paramsPair))
                 (retPair (parseReturnTypeOpt remParams text))
                 (retElems (pairFirst retPair))
                 (remRet (pairSecond retPair))
                 (semiPair (parseOptionalSemiOrComma remRet))
                 (semiElems (pairFirst semiPair))
                 (remSemi (pairSecond semiPair))
                 (kids (listAppend triv (listAppend tpElems (listAppend paramElems (listAppend retElems semiElems)))))
                 (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken hd))))
                 (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken hd))))
                 (node (tr/makeNode "callSignature" start end kids))]
             (ParseResult :node node :rest remSemi)))
          ((and (= w "new")
                (let [(spNew (skipTrivia tl))
                      (remNew (pairSecond spNew))]
                  (and (not (listEmpty? remNew))
                       (let [(nk (tr/tokenKind (optionOr (listHead remNew) (tr/makeToken "" 0 0))))]
                         (or (= nk "lt") (= nk "lparen"))))))
           (let [(newElems (listAppend triv (list (tr/elemToken hd))))
                 (tpPair (parseTypeParamsOpt tl text))
                 (tpElems (pairFirst tpPair))
                 (remTp (pairSecond tpPair))
                 (paramsPair (parseParamsParenthesized remTp text))
                 (paramElems (pairFirst paramsPair))
                 (remParams (pairSecond paramsPair))
                 (retPair (parseReturnTypeOpt remParams text))
                 (retElems (pairFirst retPair))
                 (remRet (pairSecond retPair))
                 (semiPair (parseOptionalSemiOrComma remRet))
                 (semiElems (pairFirst semiPair))
                 (remSemi (pairSecond semiPair))
                 (kids (listAppend newElems (listAppend tpElems (listAppend paramElems (listAppend retElems semiElems)))))
                 (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken hd))))
                 (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken hd))))
                 (node (tr/makeNode "constructSignature" start end kids))]
             (ParseResult :node node :rest remSemi)))
          (else
           (let [(isReadonly (= w "readonly"))
                 (roPair (if isReadonly (pair (listAppend triv (list (tr/elemToken hd))) tl) (pair triv rem)))
                 (roElems (pairFirst roPair))
                 (remAfterRo (pairSecond roPair))
                 (namePair (parseMemberName remAfterRo text))
                 (nameElems (pairFirst namePair))
                 (remName (pairSecond namePair))
                 (spQ (skipTrivia remName))
                 (trivQ (pairFirst spQ))
                 (remQ (pairSecond spQ))
                 (hasQ (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "question")))
                 (qPair (if hasQ
                          (let [(qTok (optionOr (listHead remQ) (tr/makeToken "" 0 0)))
                                (tlQ (optionOr (listTail remQ) (list)))]
                            (pair (listAppend trivQ (list (tr/elemToken qTok))) tlQ))
                          (pair (list) remName)))
                 (qElems (pairFirst qPair))
                 (remAfterQ (pairSecond qPair))
                 (nameAndQ (listAppend nameElems qElems))
                 (spNext (skipTrivia remAfterQ))
                 (remNext (pairSecond spNext))
                 (firstAfterName (if (listEmpty? remNext) (tr/makeToken "" 0 0) (optionOr (listHead remNext) (tr/makeToken "" 0 0))))
                 (isMethod (or (= (tr/tokenKind firstAfterName) "lparen") (= (tr/tokenKind firstAfterName) "lt")))]
             (if isMethod
               (let [(tpPair (parseTypeParamsOpt remAfterQ text))
                     (tpElems (pairFirst tpPair))
                     (remTp (pairSecond tpPair))
                     (paramsPair (parseParamsParenthesized remTp text))
                     (paramElems (pairFirst paramsPair))
                     (remParams (pairSecond paramsPair))
                     (retPair (parseReturnTypeOpt remParams text))
                     (retElems (pairFirst retPair))
                     (remRet (pairSecond retPair))
                     (semiPair (parseOptionalSemiOrComma remRet))
                     (semiElems (pairFirst semiPair))
                     (remSemi (pairSecond semiPair))
                     (kids (listAppend roElems (listAppend nameAndQ (listAppend tpElems (listAppend paramElems (listAppend retElems semiElems))))))
                     (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken hd))))
                     (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken hd))))
                     (node (tr/makeNode "methodSignature" start end kids))]
                 (ParseResult :node node :rest remSemi))
               (let [(retPair (parseReturnTypeOpt remAfterQ text))
                     (retElems (pairFirst retPair))
                     (remRet (pairSecond retPair))
                     (semiPair (parseOptionalSemiOrComma remRet))
                     (semiElems (pairFirst semiPair))
                     (remSemi (pairSecond semiPair))
                     (kids (listAppend roElems (listAppend nameAndQ (listAppend retElems semiElems))))
                     (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken hd))))
                     (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken hd))))
                     (node (tr/makeNode "propertySignature" start end kids))]
                 (ParseResult :node node :rest remSemi)))))))))

fn parseInterfaceMembersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(memRes (parseInterfaceMember rem text))
                (memNode memRes.node)
                (remMem memRes.rest)
                (accWithMem (listAppend acc (listAppend triv (list (tr/elemNode memNode)))))]
            (if (= (listLength remMem) (listLength rem))
              (let [(advToks (optionOr (listTail rem) (list)))
                    (errElem (tr/elemToken hd))]
                (parseInterfaceMembersLoop advToks text (listAppend accWithMem (list errElem))))
              (parseInterfaceMembersLoop remMem text accWithMem)))))))

fn parseInterfaceDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(ifaceTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (spName (skipTrivia tl))
            (trivName (pairFirst spName))
            (remName (pairSecond spName))]
        (if (listEmpty? remName)
          (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest tl)
          (let [(nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                (tlName (optionOr (listTail remName) (list)))
                (tpPair (parseTypeParamsOpt tlName text))
                (tpElems (pairFirst tpPair))
                (remTp (pairSecond tpPair))
                (spExt (skipTrivia remTp))
                (trivExt (pairFirst spExt))
                (remExt (pairSecond spExt))
                (hasExt (and (not (listEmpty? remExt)) (= (tokenSlice (optionOr (listHead remExt) (tr/makeToken "" 0 0)) text) "extends")))
                (extPair (if hasExt
                           (let [(extTok (optionOr (listHead remExt) (tr/makeToken "" 0 0)))
                                 (tlExt (optionOr (listTail remExt) (list)))
                                 (extListRes (parseTypeRefListLoop tlExt text (list)))]
                             (pair (listAppend trivExt (cons (tr/elemToken extTok) extListRes.elements)) extListRes.rest))
                           (pair (list) remTp)))
                (extElems (pairFirst extPair))
                (remAfterExt (pairSecond extPair))
                (spBrace (skipTrivia remAfterExt))
                (trivBrace (pairFirst spBrace))
                (remBrace (pairSecond spBrace))
                (lbTok (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))
                (tlLb (optionOr (listTail remBrace) (list)))
                (bodyRes (parseInterfaceMembersLoop tlLb text (list)))
                (bodyElems bodyRes.elements)
                (remBody bodyRes.rest)
                (closePair (expectClose remBody "rbrace" (tr/tokenEnd lbTok)))
                (rbTok (pairFirst closePair))
                (remRb (pairSecond closePair))
                (kids (listAppend triv
                        (cons (tr/elemToken ifaceTok)
                          (listAppend trivName
                            (cons (tr/elemToken nameTok)
                              (listAppend tpElems
                                (listAppend extElems
                                  (listAppend trivBrace
                                    (cons (tr/elemToken lbTok)
                                      (listAppend bodyElems
                                        (list (tr/elemToken rbTok))))))))))))
                (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken ifaceTok))))
                (end (tr/tokenEnd rbTok))
                (node (tr/makeNode "interfaceDecl" start end kids))]
            (ParseResult :node node :rest remRb))))))

fn parseTypeAliasDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(typeTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (spName (skipTrivia tl))
            (trivName (pairFirst spName))
            (remName (pairSecond spName))
            (nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
            (tlName (optionOr (listTail remName) (list)))
            (tpPair (parseTypeParamsOpt tlName text))
            (tpElems (pairFirst tpPair))
            (remTp (pairSecond tpPair))
            (spEq (skipTrivia remTp))
            (trivEq (pairFirst spEq))
            (remEq (pairSecond spEq))
            (eqTok (optionOr (listHead remEq) (tr/makeToken "" 0 0)))
            (tlEq (optionOr (listTail remEq) (list)))
            (spVal (skipTrivia tlEq))
            (trivVal (pairFirst spVal))
            (typeValRes (ts/parseTypeExpr (pairSecond spVal) text 0))
            (typeValNode typeValRes.node)
            (remTypeVal typeValRes.rest)
            (semiPair (parseOptionalSemiOrComma remTypeVal))
            (semiElems (pairFirst semiPair))
            (remSemi (pairSecond semiPair))
            (kids (listAppend triv
                    (cons (tr/elemToken typeTok)
                      (listAppend trivName
                        (cons (tr/elemToken nameTok)
                          (listAppend tpElems
                            (listAppend trivEq
                              (cons (tr/elemToken eqTok)
                                (listAppend trivVal
                                  (cons (tr/elemNode typeValNode)
                                    semiElems))))))))))
            (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken typeTok))))
            (end (if (listEmpty? semiElems) (tr/nodeEnd typeValNode) (tr/elementEnd (optionOr (listLast semiElems) (tr/elemNode typeValNode)))))
            (node (tr/makeNode "typeAliasDecl" start end kids))]
        (ParseResult :node node :rest remSemi))))

fn parseEnumMembersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(namePair (parseMemberName rem text))
                (nameElems (pairFirst namePair))
                (remName (pairSecond namePair))
                (spEq (skipTrivia remName))
                (trivEq (pairFirst spEq))
                (remEq (pairSecond spEq))
                (hasEq (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign")))
                (eqTok (if hasEq (optionOr (listHead remEq) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (tlEq (if hasEq (optionOr (listTail remEq) (list)) remEq))
                (spVal (if hasEq (skipTrivia tlEq) (pair (list) (list))))
                (trivVal (pairFirst spVal))
                (remVal (pairSecond spVal))
                (valRes (if hasEq (ts/parseTsExpr remVal text 1) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remName)))
                (valNode valRes.node)
                (remAfterVal (if hasEq valRes.rest remName))
                (valElems (if hasEq (listAppend trivEq (cons (tr/elemToken eqTok) (listAppend trivVal (list (tr/elemNode valNode))))) (list)))
                (spComma (skipTrivia remAfterVal))
                (trivComma (pairFirst spComma))
                (remComma (pairSecond spComma))
                (hasComma (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma")))
                (commaTok (if hasComma (optionOr (listHead remComma) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (remAfterComma (if hasComma (optionOr (listTail remComma) (list)) remAfterVal))
                (commaElems (if hasComma (listAppend trivComma (list (tr/elemToken commaTok))) (list)))
                (memKids (listAppend triv (listAppend nameElems (listAppend valElems commaElems))))
                (start (tr/elementStart (optionOr (listHead memKids) (tr/elemToken hd))))
                (end (tr/elementEnd (optionOr (listLast memKids) (tr/elemToken hd))))
                (memNode (tr/makeNode "enumMember" start end memKids))
                (accWithMem (listAppend acc (list (tr/elemNode memNode))))]
            (if (= (listLength remAfterComma) (listLength rem))
              (let [(advToks (optionOr (listTail rem) (list)))]
                (parseEnumMembersLoop advToks text accWithMem))
              (parseEnumMembersLoop remAfterComma text accWithMem)))))))

fn parseEnumDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))
        (firstTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (tl (optionOr (listTail rem) (list)))
        (isConst (= (tokenSlice firstTok text) "const"))
        (constPair (if isConst (pair (listAppend triv (list (tr/elemToken firstTok))) tl) (pair triv rem)))
        (constElems (pairFirst constPair))
        (remAfterConst (pairSecond constPair))
        (spEnum (skipTrivia remAfterConst))
        (trivEnum (pairFirst spEnum))
        (remEnum (pairSecond spEnum))
        (enumTok (optionOr (listHead remEnum) (tr/makeToken "" 0 0)))
        (tlEnum (optionOr (listTail remEnum) (list)))
        (spName (skipTrivia tlEnum))
        (trivName (pairFirst spName))
        (remName (pairSecond spName))
        (nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
        (tlName (optionOr (listTail remName) (list)))
        (spBrace (skipTrivia tlName))
        (trivBrace (pairFirst spBrace))
        (remBrace (pairSecond spBrace))
        (lbTok (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))
        (tlLb (optionOr (listTail remBrace) (list)))
        (bodyRes (parseEnumMembersLoop tlLb text (list)))
        (bodyElems bodyRes.elements)
        (remBody bodyRes.rest)
        (closePair (expectClose remBody "rbrace" (tr/tokenEnd lbTok)))
        (rbTok (pairFirst closePair))
        (remRb (pairSecond closePair))
        (kids (listAppend constElems
                (listAppend trivEnum
                  (cons (tr/elemToken enumTok)
                    (listAppend trivName
                      (cons (tr/elemToken nameTok)
                        (listAppend trivBrace
                          (cons (tr/elemToken lbTok)
                            (listAppend bodyElems
                              (list (tr/elemToken rbTok)))))))))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken firstTok))))
        (end (tr/tokenEnd rbTok))
        (node (tr/makeNode "enumDecl" start end kids))]
    (ParseResult :node node :rest remRb))

fn parseClassMember toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(firstTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind firstTok))]
        (cond
          ((= k "semicolon")
           (let [(kids (listAppend triv (list (tr/elemToken firstTok))))
                 (node (tr/makeNode "emptyMember" (tr/tokenStart firstTok) (tr/tokenEnd firstTok) kids))]
             (ParseResult :node node :rest tl)))
          ((and (= (tokenSlice firstTok text) "static")
                (let [(sp2 (skipTrivia tl))
                      (rem2 (pairSecond sp2))]
                  (and (not (listEmpty? rem2)) (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "lbrace"))))
           (let [(spBr (skipTrivia tl))
                 (trivBr (pairFirst spBr))
                 (remBr (pairSecond spBr))
                 (blockRes (stmt/parseBlock remBr text true false))
                 (blockNode blockRes.node)
                 (kids (listAppend triv (cons (tr/elemToken firstTok) (listAppend trivBr (list (tr/elemNode blockNode))))))
                 (node (tr/makeNode "staticBlock" (tr/tokenStart firstTok) (tr/nodeEnd blockNode) kids))]
             (ParseResult :node node :rest blockRes.rest)))
          (else
           (let [(decsRes (parseDecoratorsLoop rem text (list)))
                 (decElems decsRes.elements)
                 (remAfterDecs decsRes.rest)
                 (modsRes (parseModifiersLoop remAfterDecs text (list)))
                 (modElems modsRes.elements)
                 (remAfterMods modsRes.rest)
                 (prefixElems (listAppend triv (listAppend decElems modElems)))]
             (if (isIndexSignatureStart remAfterMods)
               (parseIndexSignature remAfterMods text prefixElems)
               (let [(spStar (skipTrivia remAfterMods))
                     (trivStar (pairFirst spStar))
                     (remStar (pairSecond spStar))
                     (hasStar (and (not (listEmpty? remStar)) (= (tr/tokenKind (optionOr (listHead remStar) (tr/makeToken "" 0 0))) "star")))
                     (starPair (if hasStar
                                 (let [(starTok (optionOr (listHead remStar) (tr/makeToken "" 0 0)))
                                       (tlStar (optionOr (listTail remStar) (list)))]
                                   (pair (listAppend trivStar (list (tr/elemToken starTok))) tlStar))
                                 (pair (list) remAfterMods)))
                     (starElems (pairFirst starPair))
                     (remAfterStar (pairSecond starPair))
                     (prefixWithStar (listAppend prefixElems starElems))
                     (namePair (parseMemberName remAfterStar text))
                     (nameElems (pairFirst namePair))
                     (remName (pairSecond namePair))
                     (nameTok (if (listEmpty? nameElems) (tr/makeToken "" 0 0) (optionOr (listHead (findChildTokens nameElems)) (tr/makeToken "" 0 0))))
                     (nameStr (tokenSlice nameTok text))
                     (spQ (skipTrivia remName))
                     (trivQ (pairFirst spQ))
                     (remQ (pairSecond spQ))
                     (hasQ (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "question")))
                     (qPair (if hasQ
                              (let [(qTok (optionOr (listHead remQ) (tr/makeToken "" 0 0)))
                                    (tlQ (optionOr (listTail remQ) (list)))]
                                (pair (listAppend trivQ (list (tr/elemToken qTok))) tlQ))
                              (pair (list) remName)))
                     (qElems (pairFirst qPair))
                     (remAfterQ (pairSecond qPair))
                     (spAfterName (skipTrivia remAfterQ))
                     (trivAfterName (pairFirst spAfterName))
                     (remAfterName (pairSecond spAfterName))
                     (nextTokAfterName (if (listEmpty? remAfterName) (tr/makeToken "" 0 0) (optionOr (listHead remAfterName) (tr/makeToken "" 0 0))))
                     (nextK (tr/tokenKind nextTokAfterName))
                     (isAccessor (and (not hasQ) (or (= nameStr "get") (= nameStr "set"))))
                     (isMethod (or (= nextK "lparen") (= nextK "lt")))]
                 (cond
                   ((and isAccessor (and (not isMethod) (not (listEmpty? remAfterName))))
                    (let [(subNamePair (parseMemberName remAfterName text))
                          (subNameElems (pairFirst subNamePair))
                          (remSubName (pairSecond subNamePair))
                          (paramsPair (parseParamsParenthesized remSubName text))
                          (paramElems (pairFirst paramsPair))
                          (remParams (pairSecond paramsPair))
                          (retPair (parseReturnTypeOpt remParams text))
                          (retElems (pairFirst retPair))
                          (remRet (pairSecond retPair))
                          (spBody (skipTrivia remRet))
                          (trivBody (pairFirst spBody))
                          (remBody (pairSecond spBody))
                          (hasBody (and (not (listEmpty? remBody)) (= (tr/tokenKind (optionOr (listHead remBody) (tr/makeToken "" 0 0))) "lbrace")))
                          (bodyRes (if hasBody (stmt/parseBlock remBody text true false) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remRet)))
                          (remAfterBody (if hasBody bodyRes.rest remRet))
                          (semiPair (if hasBody (pair (list) remAfterBody) (parseOptionalSemiOrComma remAfterBody)))
                          (semiElems (pairFirst semiPair))
                          (remSemi (pairSecond semiPair))
                          (bodyElems (if hasBody (listAppend trivBody (list (tr/elemNode bodyRes.node))) semiElems))
                          (kind (if (= nameStr "get") "classGetter" "classSetter"))
                          (kids (listAppend prefixWithStar (listAppend nameElems (listAppend trivAfterName (listAppend subNameElems (listAppend paramElems (listAppend retElems bodyElems)))))))
                          (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken firstTok))))
                          (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken firstTok))))
                          (node (tr/makeNode kind start end kids))]
                      (ParseResult :node node :rest remSemi)))
                   ((or (= nameStr "constructor") isMethod)
                    (let [(tpPair (parseTypeParamsOpt remAfterQ text))
                          (tpElems (pairFirst tpPair))
                          (remTp (pairSecond tpPair))
                          (paramsPair (parseParamsParenthesized remTp text))
                          (paramElems (pairFirst paramsPair))
                          (remParams (pairSecond paramsPair))
                          (retPair (parseReturnTypeOpt remParams text))
                          (retElems (pairFirst retPair))
                          (remRet (pairSecond retPair))
                          (spBody (skipTrivia remRet))
                          (trivBody (pairFirst spBody))
                          (remBody (pairSecond spBody))
                          (hasBody (and (not (listEmpty? remBody)) (= (tr/tokenKind (optionOr (listHead remBody) (tr/makeToken "" 0 0))) "lbrace")))
                          (bodyRes (if hasBody (stmt/parseBlock remBody text true false) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remRet)))
                          (remAfterBody (if hasBody bodyRes.rest remRet))
                          (semiPair (if hasBody (pair (list) remAfterBody) (parseOptionalSemiOrComma remAfterBody)))
                          (semiElems (pairFirst semiPair))
                          (remSemi (pairSecond semiPair))
                          (bodyElems (if hasBody (listAppend trivBody (list (tr/elemNode bodyRes.node))) semiElems))
                          (kind (if (= nameStr "constructor") "classConstructor" "classMethod"))
                          (kids (listAppend prefixWithStar (listAppend nameElems (listAppend qElems (listAppend tpElems (listAppend paramElems (listAppend retElems bodyElems)))))))
                          (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken firstTok))))
                          (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken firstTok))))
                          (node (tr/makeNode kind start end kids))]
                      (ParseResult :node node :rest remSemi)))
                   (else
                    (let [(hasExcl (and (not hasQ) (and (not (listEmpty? remQ)) (= (tr/tokenKind (optionOr (listHead remQ) (tr/makeToken "" 0 0))) "not"))))
                          (modSuffixPair (cond
                                           (hasQ (pair qElems remAfterQ))
                                           (hasExcl
                                            (let [(exclTok (optionOr (listHead remQ) (tr/makeToken "" 0 0)))
                                                  (tlExcl (optionOr (listTail remQ) (list)))]
                                              (pair (listAppend trivQ (list (tr/elemToken exclTok))) tlExcl)))
                                           (else
                                            (pair (list) remName))))
                          (modSuffixElems (pairFirst modSuffixPair))
                          (remAfterExcl (pairSecond modSuffixPair))
                          (retPair (parseReturnTypeOpt remAfterExcl text))
                          (retElems (pairFirst retPair))
                          (remRet (pairSecond retPair))
                          (spEq (skipTrivia remRet))
                          (trivEq (pairFirst spEq))
                          (remEq (pairSecond spEq))
                          (hasEq (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign")))
                          (eqTok (if hasEq (optionOr (listHead remEq) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                          (tlEq (if hasEq (optionOr (listTail remEq) (list)) remEq))
                          (spVal (if hasEq (skipTrivia tlEq) (pair (list) (list))))
                          (trivVal (pairFirst spVal))
                          (remVal (pairSecond spVal))
                          (valRes (if hasEq (ts/parseTsExpr remVal text 1) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remRet)))
                          (valNode valRes.node)
                          (remAfterVal (if hasEq valRes.rest remRet))
                          (valElems (if hasEq (listAppend trivEq (cons (tr/elemToken eqTok) (listAppend trivVal (list (tr/elemNode valNode))))) (list)))
                          (semiPair (parseOptionalSemiOrComma remAfterVal))
                          (semiElems (pairFirst semiPair))
                          (remSemi (pairSecond semiPair))
                          (kids (listAppend prefixWithStar (listAppend nameElems (listAppend modSuffixElems (listAppend retElems (listAppend valElems semiElems))))))
                          (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken firstTok))))
                          (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken firstTok))))
                          (node (tr/makeNode "classField" start end kids))]
                      (ParseResult :node node :rest remSemi))))))))))))

fn parseClassMembersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(memRes (parseClassMember rem text))
                (memNode memRes.node)
                (remMem memRes.rest)
                (accWithMem (listAppend acc (listAppend triv (list (tr/elemNode memNode)))))]
            (if (= (listLength remMem) (listLength rem))
              (let [(advToks (optionOr (listTail rem) (list)))
                    (errElem (tr/elemToken hd))]
                (parseClassMembersLoop advToks text (listAppend accWithMem (list errElem))))
              (parseClassMembersLoop remMem text accWithMem)))))))

fn parseClassDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(decsRes (parseDecoratorsLoop toks text (list)))
        (decElems decsRes.elements)
        (remAfterDecs decsRes.rest)
        (modsRes (parseModifiersLoop remAfterDecs text (list)))
        (modElems modsRes.elements)
        (remAfterMods modsRes.rest)
        (spClass (skipTrivia remAfterMods))
        (trivClass (pairFirst spClass))
        (remClass (pairSecond spClass))
        (classTok (optionOr (listHead remClass) (tr/makeToken "" 0 0)))
        (tlClass (optionOr (listTail remClass) (list)))
        (spName (skipTrivia tlClass))
        (trivName (pairFirst spName))
        (remName (pairSecond spName))
        (hasName (and (not (listEmpty? remName)) (= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident")))
        (nameTok (if hasName (optionOr (listHead remName) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
        (tlName (if hasName (optionOr (listTail remName) (list)) remName))
        (nameElems (if hasName (listAppend trivName (list (tr/elemToken nameTok))) trivName))
        (tpPair (parseTypeParamsOpt tlName text))
        (tpElems (pairFirst tpPair))
        (remTp (pairSecond tpPair))
        (spExt (skipTrivia remTp))
        (trivExt (pairFirst spExt))
        (remExt (pairSecond spExt))
        (hasExt (and (not (listEmpty? remExt)) (= (tokenSlice (optionOr (listHead remExt) (tr/makeToken "" 0 0)) text) "extends")))
        (extPair (if hasExt
                   (let [(extTok (optionOr (listHead remExt) (tr/makeToken "" 0 0)))
                         (tlExt (optionOr (listTail remExt) (list)))
                         (extRefRes (parseTypeRef tlExt text))]
                     (pair (listAppend trivExt (cons (tr/elemToken extTok) (list (tr/elemNode extRefRes.node)))) extRefRes.rest))
                   (pair (list) remTp)))
        (extElems (pairFirst extPair))
        (remAfterExt (pairSecond extPair))
        (spImp (skipTrivia remAfterExt))
        (trivImp (pairFirst spImp))
        (remImp (pairSecond spImp))
        (hasImp (and (not (listEmpty? remImp)) (= (tokenSlice (optionOr (listHead remImp) (tr/makeToken "" 0 0)) text) "implements")))
        (impPair (if hasImp
                   (let [(impTok (optionOr (listHead remImp) (tr/makeToken "" 0 0)))
                         (tlImp (optionOr (listTail remImp) (list)))
                         (impListRes (parseTypeRefListLoop tlImp text (list)))]
                     (pair (listAppend trivImp (cons (tr/elemToken impTok) impListRes.elements)) impListRes.rest))
                   (pair (list) remAfterExt)))
        (impElems (pairFirst impPair))
        (remAfterImp (pairSecond impPair))
        (spBrace (skipTrivia remAfterImp))
        (trivBrace (pairFirst spBrace))
        (remBrace (pairSecond spBrace))
        (lbTok (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))
        (tlLb (optionOr (listTail remBrace) (list)))
        (bodyRes (parseClassMembersLoop tlLb text (list)))
        (bodyElems bodyRes.elements)
        (remBody bodyRes.rest)
        (closePair (expectClose remBody "rbrace" (tr/tokenEnd lbTok)))
        (rbTok (pairFirst closePair))
        (remRb (pairSecond closePair))
        (kids (listAppend decElems
                (listAppend modElems
                  (listAppend trivClass
                    (cons (tr/elemToken classTok)
                      (listAppend nameElems
                        (listAppend tpElems
                          (listAppend extElems
                            (listAppend impElems
                              (listAppend trivBrace
                                (cons (tr/elemToken lbTok)
                                  (listAppend bodyElems
                                    (list (tr/elemToken rbTok))))))))))))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken classTok))))
        (end (tr/tokenEnd rbTok))
        (node (tr/makeNode "classDecl" start end kids))]
    (ParseResult :node node :rest remRb))

fn parseFunctionDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(decsRes (parseDecoratorsLoop toks text (list)))
        (decElems decsRes.elements)
        (remAfterDecs decsRes.rest)
        (modsRes (parseModifiersLoop remAfterDecs text (list)))
        (modElems modsRes.elements)
        (remAfterMods modsRes.rest)
        (spFn (skipTrivia remAfterMods))
        (trivFn (pairFirst spFn))
        (remFn (pairSecond spFn))
        (fnTok (optionOr (listHead remFn) (tr/makeToken "" 0 0)))
        (tlFn (optionOr (listTail remFn) (list)))
        (spStar (skipTrivia tlFn))
        (trivStar (pairFirst spStar))
        (remStar (pairSecond spStar))
        (hasStar (and (not (listEmpty? remStar)) (= (tr/tokenKind (optionOr (listHead remStar) (tr/makeToken "" 0 0))) "star")))
        (starPair (if hasStar
                    (let [(starTok (optionOr (listHead remStar) (tr/makeToken "" 0 0)))
                          (tlStar (optionOr (listTail remStar) (list)))]
                      (pair (listAppend trivStar (list (tr/elemToken starTok))) tlStar))
                    (pair (list) tlFn)))
        (starElems (pairFirst starPair))
        (remAfterStar (pairSecond starPair))
        (spName (skipTrivia remAfterStar))
        (trivName (pairFirst spName))
        (remName (pairSecond spName))
        (hasName (and (not (listEmpty? remName)) (= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident")))
        (nameTok (if hasName (optionOr (listHead remName) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
        (tlName (if hasName (optionOr (listTail remName) (list)) remName))
        (nameElems (if hasName (listAppend trivName (list (tr/elemToken nameTok))) trivName))
        (tpPair (parseTypeParamsOpt tlName text))
        (tpElems (pairFirst tpPair))
        (remTp (pairSecond tpPair))
        (paramsPair (parseParamsParenthesized remTp text))
        (paramElems (pairFirst paramsPair))
        (remParams (pairSecond paramsPair))
        (retPair (parseReturnTypeOpt remParams text))
        (retElems (pairFirst retPair))
        (remRet (pairSecond retPair))
        (spBody (skipTrivia remRet))
        (trivBody (pairFirst spBody))
        (remBody (pairSecond spBody))
        (hasBody (and (not (listEmpty? remBody)) (= (tr/tokenKind (optionOr (listHead remBody) (tr/makeToken "" 0 0))) "lbrace")))
        (bodyRes (if hasBody (stmt/parseBlock remBody text true false) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remRet)))
        (remAfterBody (if hasBody bodyRes.rest remRet))
        (semiPair (if hasBody (pair (list) remAfterBody) (parseOptionalSemiOrComma remAfterBody)))
        (semiElems (pairFirst semiPair))
        (remSemi (pairSecond semiPair))
        (bodyElems (if hasBody (listAppend trivBody (list (tr/elemNode bodyRes.node))) semiElems))
        (kids (listAppend decElems
                (listAppend modElems
                  (listAppend trivFn
                    (cons (tr/elemToken fnTok)
                      (listAppend starElems
                        (listAppend nameElems
                          (listAppend tpElems
                            (listAppend paramElems
                              (listAppend retElems bodyElems))))))))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken fnTok))))
        (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken fnTok))))
        (node (tr/makeNode "functionDecl" start end kids))]
    (ParseResult :node node :rest remSemi))

fn parseTsVarDeclaratorsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))
            (isPat (or (= k "lbracket") (= k "lbrace")))
            (patRes (if isPat (stmt/parsePattern rem text) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest tl)))
            (nameKids (if isPat (list (tr/elemNode patRes.node)) (list (tr/elemToken hd))))
            (remAfterName (if isPat patRes.rest tl))
            (spExcl (skipTrivia remAfterName))
            (trivExcl (pairFirst spExcl))
            (remExcl (pairSecond spExcl))
            (hasExcl (and (not isPat) (and (not (listEmpty? remExcl)) (= (tr/tokenKind (optionOr (listHead remExcl) (tr/makeToken "" 0 0))) "not"))))
            (exclPair (if hasExcl
                        (let [(exclTok (optionOr (listHead remExcl) (tr/makeToken "" 0 0)))
                              (tlExcl (optionOr (listTail remExcl) (list)))]
                          (pair (listAppend trivExcl (list (tr/elemToken exclTok))) tlExcl))
                        (pair (list) remAfterName)))
            (exclElems (pairFirst exclPair))
            (remAfterExcl (pairSecond exclPair))
            (nameWithExcl (listAppend nameKids exclElems))
            (retPair (parseReturnTypeOpt remAfterExcl text))
            (retElems (pairFirst retPair))
            (remRet (pairSecond retPair))
            (spEq (skipTrivia remRet))
            (trivEq (pairFirst spEq))
            (remEq (pairSecond spEq))
            (hasEq (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign")))
            (eqTok (if hasEq (optionOr (listHead remEq) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
            (tlEq (if hasEq (optionOr (listTail remEq) (list)) remEq))
            (spVal (if hasEq (skipTrivia tlEq) (pair (list) (list))))
            (trivVal (pairFirst spVal))
            (remVal (pairSecond spVal))
            (valRes (if hasEq (ts/parseTsExpr remVal text 1) (ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest remRet)))
            (valNode valRes.node)
            (remAfterVal (if hasEq valRes.rest remRet))
            (valElems (if hasEq (listAppend trivEq (cons (tr/elemToken eqTok) (listAppend trivVal (list (tr/elemNode valNode))))) (list)))
            (declKids (listAppend nameWithExcl (listAppend retElems valElems)))
            (start (tr/elementStart (optionOr (listHead declKids) (tr/elemToken hd))))
            (end (tr/elementEnd (optionOr (listLast declKids) (tr/elemToken hd))))
            (declNode (tr/makeNode "declarator" start end declKids))
            (accWithDecl (listAppend acc (listAppend triv (list (tr/elemNode declNode)))))
            (spComma (skipTrivia remAfterVal))
            (trivComma (pairFirst spComma))
            (remComma (pairSecond spComma))]
        (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
          (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                (tlComma (optionOr (listTail remComma) (list)))
                (accWithComma (listAppend accWithDecl (listAppend trivComma (list (tr/elemToken commaTok)))))]
            (parseTsVarDeclaratorsLoop tlComma text accWithComma))
          (ElementsResult :elements accWithDecl :rest remAfterVal)))))

fn parseTsVarStmt toks: (List tr/Token) text: String -> ParseResult
  (let [(modsRes (parseModifiersLoop toks text (list)))
        (modElems modsRes.elements)
        (remAfterMods modsRes.rest)
        (spKw (skipTrivia remAfterMods))
        (trivKw (pairFirst spKw))
        (remKw (pairSecond spKw))
        (kwTok (optionOr (listHead remKw) (tr/makeToken "" 0 0)))
        (tlKw (optionOr (listTail remKw) (list)))
        (kwStr (tokenSlice kwTok text))
        (declKind (cond ((= kwStr "var") "varDecl") ((= kwStr "let") "letDecl") (else "constDecl")))
        (loopRes (parseTsVarDeclaratorsLoop tlKw text (list)))
        (declElems loopRes.elements)
        (remDecl loopRes.rest)
        (semiPair (parseOptionalSemiOrComma remDecl))
        (semiElems (pairFirst semiPair))
        (remSemi (pairSecond semiPair))
        (kids (listAppend modElems
                (listAppend trivKw
                  (cons (tr/elemToken kwTok)
                    (listAppend declElems semiElems)))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken kwTok))))
        (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken kwTok))))
        (node (tr/makeNode declKind start end kids))]
    (ParseResult :node node :rest remSemi))


fn parseNamespaceDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))
        (kwTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (tlKw (optionOr (listTail rem) (list)))
        (kwStr (tokenSlice kwTok text))
        (isGlobal (= kwStr "global"))
        (namePair (if isGlobal (pair (list) tlKw) (parseMemberName tlKw text)))
        (nameElems (pairFirst namePair))
        (remName (pairSecond namePair))
        (dottedRes (if isGlobal (ElementsResult :elements (list) :rest tlKw) (parseDottedIdentLoop remName text nameElems)))
        (allNameElems (if isGlobal (list) dottedRes.elements))
        (remAfterName (if isGlobal tlKw dottedRes.rest))
        (spBrace (skipTrivia remAfterName))
        (trivBrace (pairFirst spBrace))
        (remBrace (pairSecond spBrace))
        (hasBrace (and (not (listEmpty? remBrace)) (= (tr/tokenKind (optionOr (listHead remBrace) (tr/makeToken "" 0 0))) "lbrace")))
        (kind (if (= kwStr "module") "moduleDecl" "namespaceDecl"))]
    (if (not hasBrace)
      (let [(semiPair (parseOptionalSemiOrComma remAfterName))
            (semiElems (pairFirst semiPair))
            (remSemi (pairSecond semiPair))
            (kids (listAppend triv (cons (tr/elemToken kwTok) (listAppend allNameElems semiElems))))
            (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken kwTok))))
            (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken kwTok))))
            (node (tr/makeNode kind start end kids))]
        (ParseResult :node node :rest remSemi))
      (let [(lbTok (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))
            (tlLb (optionOr (listTail remBrace) (list)))
            (bodyRes (parseModuleItemsLoop tlLb text (list)))
            (bodyElems (resultOr bodyRes (list)))
            (remBody (findRemainingTokens tlLb bodyElems))
            (closePair (expectClose remBody "rbrace" (tr/tokenEnd lbTok)))
            (rbTok (pairFirst closePair))
            (remRb (pairSecond closePair))
            (kids (listAppend triv
                    (cons (tr/elemToken kwTok)
                      (listAppend allNameElems
                        (listAppend trivBrace
                          (cons (tr/elemToken lbTok)
                            (listAppend bodyElems
                              (list (tr/elemToken rbTok)))))))))
            (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken kwTok))))
            (end (tr/tokenEnd rbTok))
            (node (tr/makeNode kind start end kids))]
        (ParseResult :node node :rest remRb))))

fn findRemainingTokens toks: (List tr/Token) elems: (List tr/TreeElement) -> (List tr/Token)
  (if (listEmpty? elems)
    toks
    (let [(lastElem (optionOr (listLast elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (endPos (tr/elementEnd lastElem))]
      (dropTokensUntilOffset toks endPos)))

fn dropTokensUntilOffset toks: (List tr/Token) endPos: Int64 -> (List tr/Token)
  (if (listEmpty? toks)
    toks
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (<= (tr/tokenEnd hd) endPos)
        (dropTokensUntilOffset tl endPos)
        toks)))

fn parseTsImportSpecifiersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(isType (and (= (tokenSlice hd text) "type")
                             (let [(sp2 (skipTrivia tl))
                                   (rem2 (pairSecond sp2))]
                               (and (not (listEmpty? rem2))
                                    (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "ident")))))
                (typePair (if isType (pair (listAppend triv (list (tr/elemToken hd))) tl) (pair triv rem)))
                (typeElems (pairFirst typePair))
                (remAfterType (pairSecond typePair))
                (spName (skipTrivia remAfterType))
                (trivName (pairFirst spName))
                (remName (pairSecond spName))
                (nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                (tlName (optionOr (listTail remName) (list)))
                (nameElems (listAppend typeElems (listAppend trivName (list (tr/elemToken nameTok)))))
                (spAs (skipTrivia tlName))
                (trivAs (pairFirst spAs))
                (remAs (pairSecond spAs))
                (hasAs (and (not (listEmpty? remAs)) (= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as")))
                (asTok (if hasAs (optionOr (listHead remAs) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (tlAs (if hasAs (optionOr (listTail remAs) (list)) remAs))
                (spAlias (if hasAs (skipTrivia tlAs) (pair (list) (list))))
                (trivAlias (pairFirst spAlias))
                (remAlias (pairSecond spAlias))
                (aliasTok (if hasAs (optionOr (listHead remAlias) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (tlAlias (if hasAs (optionOr (listTail remAlias) (list)) tlName))
                (specKids (if hasAs
                            (listAppend nameElems (listAppend trivAs (cons (tr/elemToken asTok) (listAppend trivAlias (list (tr/elemToken aliasTok))))))
                            nameElems))
                (start (tr/elementStart (optionOr (listHead specKids) (tr/elemToken hd))))
                (end (tr/elementEnd (optionOr (listLast specKids) (tr/elemToken hd))))
                (specNode (tr/makeNode "importSpecifier" start end specKids))
                (accWithSpec (listAppend acc (list (tr/elemNode specNode))))
                (spComma (skipTrivia tlAlias))
                (trivComma (pairFirst spComma))
                (remComma (pairSecond spComma))]
            (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
              (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                    (tlComma (optionOr (listTail remComma) (list)))
                    (accWithComma (listAppend accWithSpec (listAppend trivComma (list (tr/elemToken commaTok)))))]
                (parseTsImportSpecifiersLoop tlComma text accWithComma))
              (ElementsResult :elements accWithSpec :rest tlAlias)))))))

fn parseTsImportClauseRest toks: (List tr/Token) text: String prefixElems: (List tr/TreeElement) -> ParseResult
  (let [(spFrom (skipTrivia toks))
        (trivFrom (pairFirst spFrom))
        (remFrom (pairSecond spFrom))
        (fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
        (tlFrom (optionOr (listTail remFrom) (list)))
        (spSrc (skipTrivia tlFrom))
        (trivSrc (pairFirst spSrc))
        (remSrc (pairSecond spSrc))
        (srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
        (tlSrc (optionOr (listTail remSrc) (list)))
        (semiPair (parseOptionalSemiOrComma tlSrc))
        (semiElems (pairFirst semiPair))
        (remSemi (pairSecond semiPair))
        (kids (listAppend prefixElems
                (listAppend trivFrom
                  (cons (tr/elemToken fromTok)
                    (listAppend trivSrc
                      (cons (tr/elemToken srcTok)
                        semiElems))))))
        (start (tr/elementStart (optionOr (listHead kids) (tr/elemToken fromTok))))
        (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken srcTok))))
        (node (tr/makeNode "importDecl" start end kids))]
    (ParseResult :node node :rest remSemi))

fn parseTsImportDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))
        (importTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (tl (optionOr (listTail rem) (list)))
        (spNext (skipTrivia tl))
        (trivNext (pairFirst spNext))
        (remNext (pairSecond spNext))
        (firstAfterImport (if (listEmpty? remNext) (tr/makeToken "" 0 0) (optionOr (listHead remNext) (tr/makeToken "" 0 0))))
        (firstStr (tokenSlice firstAfterImport text))
        (tlNext (if (listEmpty? remNext) (list) (optionOr (listTail remNext) (list))))]
    (cond
      ((and (= (tr/tokenKind firstAfterImport) "ident")
            (let [(spEq (skipTrivia tlNext))
                  (remEq (pairSecond spEq))]
              (and (not (listEmpty? remEq)) (= (tr/tokenKind (optionOr (listHead remEq) (tr/makeToken "" 0 0))) "assign"))))
       (let [(spEq (skipTrivia tlNext))
             (trivEq (pairFirst spEq))
             (remEq (pairSecond spEq))
             (eqTok (optionOr (listHead remEq) (tr/makeToken "" 0 0)))
             (tlEq (optionOr (listTail remEq) (list)))
             (spReq (skipTrivia tlEq))
             (trivReq (pairFirst spReq))
             (remReq (pairSecond spReq))
             (reqTok (optionOr (listHead remReq) (tr/makeToken "" 0 0)))
             (tlReq (optionOr (listTail remReq) (list)))
             (isRequire (and (= (tokenSlice reqTok text) "require")
                             (let [(spLp2 (skipTrivia tlReq)) (remLp2 (pairSecond spLp2))]
                               (and (not (listEmpty? remLp2)) (= (tr/tokenKind (optionOr (listHead remLp2) (tr/makeToken "" 0 0))) "lparen")))))]
         (if isRequire
           (let [(spLp (skipTrivia tlReq))
                 (trivLp (pairFirst spLp))
                 (remLp (pairSecond spLp))
                 (lpTok (optionOr (listHead remLp) (tr/makeToken "" 0 0)))
                 (tlLp (optionOr (listTail remLp) (list)))
                 (spPath (skipTrivia tlLp))
                 (trivPath (pairFirst spPath))
                 (remPath (pairSecond spPath))
                 (pathTok (optionOr (listHead remPath) (tr/makeToken "" 0 0)))
                 (tlPath (optionOr (listTail remPath) (list)))
                 (spRp (skipTrivia tlPath))
                 (trivRp (pairFirst spRp))
                 (remRp (pairSecond spRp))
                 (closePair (expectClose remRp "rparen" (tr/tokenEnd pathTok)))
                 (rpTok (pairFirst closePair))
                 (remAfterClose (pairSecond closePair))
                 (semiPair (parseOptionalSemiOrComma remAfterClose))
                 (semiElems (pairFirst semiPair))
                 (remSemi (pairSecond semiPair))
                 (kids (listAppend triv
                         (cons (tr/elemToken importTok)
                           (listAppend trivNext
                             (cons (tr/elemToken firstAfterImport)
                               (listAppend trivEq
                                 (cons (tr/elemToken eqTok)
                                   (listAppend trivReq
                                     (cons (tr/elemToken reqTok)
                                       (listAppend trivLp
                                         (cons (tr/elemToken lpTok)
                                           (listAppend trivPath
                                             (cons (tr/elemToken pathTok)
                                               (listAppend trivRp
                                                 (cons (tr/elemToken rpTok)
                                                   semiElems)))))))))))))))
                 (start (tr/tokenStart importTok))
                 (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken eqTok))))
                 (node (tr/makeNode "importEqualsDecl" start end kids))]
             (ParseResult :node node :rest remSemi))
           (let [(dottedRes (parseDottedIdentLoop tlReq text (list (tr/elemToken reqTok))))
                 (dottedElems (listAppend trivReq dottedRes.elements))
                 (semiPair (parseOptionalSemiOrComma dottedRes.rest))
                 (semiElems (pairFirst semiPair))
                 (remSemi (pairSecond semiPair))
                 (kids (listAppend triv
                         (cons (tr/elemToken importTok)
                           (listAppend trivNext
                             (cons (tr/elemToken firstAfterImport)
                               (listAppend trivEq
                                 (cons (tr/elemToken eqTok)
                                   (listAppend dottedElems semiElems))))))))
                 (start (tr/tokenStart importTok))
                 (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken eqTok))))
                 (node (tr/makeNode "importEqualsDecl" start end kids))]
             (ParseResult :node node :rest remSemi)))))
      ((= firstStr "type")
       (let [(typeElems (listAppend triv (cons (tr/elemToken importTok) (listAppend trivNext (list (tr/elemToken firstAfterImport))))))
             (spClause (skipTrivia tlNext))
             (trivClause (pairFirst spClause))
             (remClause (pairSecond spClause))
             (clauseFirst (if (listEmpty? remClause) (tr/makeToken "" 0 0) (optionOr (listHead remClause) (tr/makeToken "" 0 0))))
             (ck (tr/tokenKind clauseFirst))]
         (cond
           ((= ck "lbrace")
            (let [(lbTok clauseFirst)
                  (tlLb (optionOr (listTail remClause) (list)))
                  (specRes (parseTsImportSpecifiersLoop tlLb text (list)))
                  (specElems specRes.elements)
                  (remSpec specRes.rest)
                  (spRb (skipTrivia remSpec))
                  (trivRb (pairFirst spRb))
                  (remRb (pairSecond spRb))
                  (closePair (expectClose remRb "rbrace" (tr/tokenEnd lbTok)))
                  (rbTok (pairFirst closePair))
                  (remAfterClose (pairSecond closePair))
                  (prefix (listAppend typeElems (listAppend trivClause (cons (tr/elemToken lbTok) (listAppend specElems (listAppend trivRb (list (tr/elemToken rbTok))))))))]
              (parseTsImportClauseRest remAfterClose text prefix)))
           ((= ck "star")
            (let [(starTok clauseFirst)
                  (tlStar (optionOr (listTail remClause) (list)))
                  (spAs (skipTrivia tlStar))
                  (trivAs (pairFirst spAs))
                  (remAs (pairSecond spAs))
                  (asTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                  (tlAs (optionOr (listTail remAs) (list)))
                  (spNs (skipTrivia tlAs))
                  (trivNs (pairFirst spNs))
                  (remNs (pairSecond spNs))
                  (nsTok (optionOr (listHead remNs) (tr/makeToken "" 0 0)))
                  (tlNs (optionOr (listTail remNs) (list)))
                  (prefix (listAppend typeElems (listAppend trivClause (cons (tr/elemToken starTok) (listAppend trivAs (cons (tr/elemToken asTok) (listAppend trivNs (list (tr/elemToken nsTok)))))))))]
              (parseTsImportClauseRest tlNs text prefix)))
           (else
            (let [(idTok clauseFirst)
                  (tlId (optionOr (listTail remClause) (list)))
                  (prefix (listAppend typeElems (listAppend trivClause (list (tr/elemToken idTok)))))]
              (parseTsImportClauseRest tlId text prefix))))))
      ((= (tr/tokenKind firstAfterImport) "lbrace")
       (let [(lbTok firstAfterImport)
             (tlLb tlNext)
             (specRes (parseTsImportSpecifiersLoop tlLb text (list)))
             (specElems specRes.elements)
             (remSpec specRes.rest)
             (spRb (skipTrivia remSpec))
             (trivRb (pairFirst spRb))
             (remRb (pairSecond spRb))
             (closePair (expectClose remRb "rbrace" (tr/tokenEnd lbTok)))
             (rbTok (pairFirst closePair))
             (remAfterClose (pairSecond closePair))
             (prefix (listAppend triv (cons (tr/elemToken importTok) (listAppend trivNext (cons (tr/elemToken lbTok) (listAppend specElems (listAppend trivRb (list (tr/elemToken rbTok)))))))))]
         (parseTsImportClauseRest remAfterClose text prefix)))
      (else
       (let [(res (jsm/parseImportDecl rem text))]
         (mt res
           ((err _)
            (let [(advToks (optionOr (listTail rem) (list)))
                  (errNode (tr/makeErrorNode (tr/tokenStart importTok) (tr/tokenEnd importTok) (list (tr/elemToken importTok))))]
              (ParseResult :node errNode :rest advToks)))
           ((ok parseRes) parseRes))))))

fn parseTsExportSpecifiersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> ElementsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ElementsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ElementsResult :elements (listAppend acc triv) :rest rem)
          (let [(isType (and (= (tokenSlice hd text) "type")
                             (let [(sp2 (skipTrivia tl))
                                   (rem2 (pairSecond sp2))]
                               (and (not (listEmpty? rem2))
                                    (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "ident")))))
                (typePair (if isType (pair (listAppend triv (list (tr/elemToken hd))) tl) (pair triv rem)))
                (typeElems (pairFirst typePair))
                (remAfterType (pairSecond typePair))
                (spName (skipTrivia remAfterType))
                (trivName (pairFirst spName))
                (remName (pairSecond spName))
                (nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                (tlName (optionOr (listTail remName) (list)))
                (nameElems (listAppend typeElems (listAppend trivName (list (tr/elemToken nameTok)))))
                (spAs (skipTrivia tlName))
                (trivAs (pairFirst spAs))
                (remAs (pairSecond spAs))
                (hasAs (and (not (listEmpty? remAs)) (= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as")))
                (asTok (if hasAs (optionOr (listHead remAs) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (tlAs (if hasAs (optionOr (listTail remAs) (list)) remAs))
                (spAlias (if hasAs (skipTrivia tlAs) (pair (list) (list))))
                (trivAlias (pairFirst spAlias))
                (remAlias (pairSecond spAlias))
                (aliasTok (if hasAs (optionOr (listHead remAlias) (tr/makeToken "" 0 0)) (tr/makeToken "" 0 0)))
                (tlAlias (if hasAs (optionOr (listTail remAlias) (list)) tlName))
                (specKids (if hasAs
                            (listAppend nameElems (listAppend trivAs (cons (tr/elemToken asTok) (listAppend trivAlias (list (tr/elemToken aliasTok))))))
                            nameElems))
                (start (tr/elementStart (optionOr (listHead specKids) (tr/elemToken hd))))
                (end (tr/elementEnd (optionOr (listLast specKids) (tr/elemToken hd))))
                (specNode (tr/makeNode "exportSpecifier" start end specKids))
                (accWithSpec (listAppend acc (list (tr/elemNode specNode))))
                (spComma (skipTrivia tlAlias))
                (trivComma (pairFirst spComma))
                (remComma (pairSecond spComma))]
            (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
              (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                    (tlComma (optionOr (listTail remComma) (list)))
                    (accWithComma (listAppend accWithSpec (listAppend trivComma (list (tr/elemToken commaTok)))))]
                (parseTsExportSpecifiersLoop tlComma text accWithComma))
              (ElementsResult :elements accWithSpec :rest tlAlias)))))))

fn parseTsExportDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))
        (exportTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (tl (optionOr (listTail rem) (list)))
        (spNext (skipTrivia tl))
        (trivNext (pairFirst spNext))
        (remNext (pairSecond spNext))
        (firstAfterExport (if (listEmpty? remNext) (tr/makeToken "" 0 0) (optionOr (listHead remNext) (tr/makeToken "" 0 0))))
        (firstStr (tokenSlice firstAfterExport text))
        (tlNext (if (listEmpty? remNext) (list) (optionOr (listTail remNext) (list))))]
    (cond
      ((= (tr/tokenKind firstAfterExport) "assign")
       (let [(eqTok firstAfterExport)
             (spExpr (skipTrivia tlNext))
             (trivExpr (pairFirst spExpr))
             (remExprToks (pairSecond spExpr))
             (exprRes (cv/parseCoverExprCtx remExprToks text 0 false false))
             (exprNode exprRes.node)
             (remExpr exprRes.rest)
             (semiPair (parseOptionalSemiOrComma remExpr))
             (semiElems (pairFirst semiPair))
             (remSemi (pairSecond semiPair))
             (kids (listAppend triv
                     (cons (tr/elemToken exportTok)
                       (listAppend trivNext
                         (cons (tr/elemToken eqTok)
                           (listAppend trivExpr
                             (cons (tr/elemNode exprNode)
                               semiElems)))))))
             (start (tr/tokenStart exportTok))
             (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken eqTok))))
             (node (tr/makeNode "exportAssignment" start end kids))]
         (ParseResult :node node :rest remSemi)))
      ((and (= firstStr "as")
            (let [(sp2 (skipTrivia tlNext))
                  (rem2 (pairSecond sp2))]
              (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "namespace"))))
       (let [(asTok firstAfterExport)
             (spNs (skipTrivia tlNext))
             (trivNs (pairFirst spNs))
             (remNs (pairSecond spNs))
             (nsTok (optionOr (listHead remNs) (tr/makeToken "" 0 0)))
             (tlNs (optionOr (listTail remNs) (list)))
             (spId (skipTrivia tlNs))
             (trivId (pairFirst spId))
             (remId (pairSecond spId))
             (idTok (optionOr (listHead remId) (tr/makeToken "" 0 0)))
             (tlId (optionOr (listTail remId) (list)))
             (semiPair (parseOptionalSemiOrComma tlId))
             (semiElems (pairFirst semiPair))
             (remSemi (pairSecond semiPair))
             (kids (listAppend triv
                     (cons (tr/elemToken exportTok)
                       (listAppend trivNext
                         (cons (tr/elemToken asTok)
                           (listAppend trivNs
                             (cons (tr/elemToken nsTok)
                               (listAppend trivId
                                 (cons (tr/elemToken idTok)
                                   semiElems)))))))))
             (start (tr/tokenStart exportTok))
             (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken idTok))))
             (node (tr/makeNode "exportAsNamespace" start end kids))]
         (ParseResult :node node :rest remSemi)))
      ((= firstStr "type")
       (let [(spAfterType (skipTrivia tlNext))
             (trivAfterType (pairFirst spAfterType))
             (remAfterType (pairSecond spAfterType))
             (afterTypeTok (if (listEmpty? remAfterType) (tr/makeToken "" 0 0) (optionOr (listHead remAfterType) (tr/makeToken "" 0 0))))
             (atk (tr/tokenKind afterTypeTok))]
         (if (= atk "lbrace")
           (let [(lbTok afterTypeTok)
                 (tlLb (optionOr (listTail remAfterType) (list)))
                 (specRes (parseTsExportSpecifiersLoop tlLb text (list)))
                 (specElems specRes.elements)
                 (remSpec specRes.rest)
                 (spRb (skipTrivia remSpec))
                 (trivRb (pairFirst spRb))
                 (remRb (pairSecond spRb))
                 (closePair (expectClose remRb "rbrace" (tr/tokenEnd lbTok)))
                 (rbTok (pairFirst closePair))
                 (remAfterClose (pairSecond closePair))
                 (spFrom (skipTrivia remAfterClose))
                 (trivFrom (pairFirst spFrom))
                 (remFrom (pairSecond spFrom))
                 (hasFrom (and (not (listEmpty? remFrom)) (= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from")))
                 (fromPair (if hasFrom
                             (let [(fTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                                   (tlF (optionOr (listTail remFrom) (list)))
                                   (spS (skipTrivia tlF))
                                   (trivS (pairFirst spS))
                                   (remS (pairSecond spS))
                                   (sTok (optionOr (listHead remS) (tr/makeToken "" 0 0)))
                                   (tlS (optionOr (listTail remS) (list)))]
                               (pair (listAppend trivFrom (cons (tr/elemToken fTok) (listAppend trivS (list (tr/elemToken sTok))))) tlS))
                             (pair (list) remAfterClose)))
                 (fromElems (pairFirst fromPair))
                 (remAfterFrom (pairSecond fromPair))
                 (semiPair (parseOptionalSemiOrComma remAfterFrom))
                 (semiElems (pairFirst semiPair))
                 (remSemi (pairSecond semiPair))
                 (kids (listAppend triv
                         (cons (tr/elemToken exportTok)
                           (listAppend trivNext
                             (cons (tr/elemToken firstAfterExport)
                               (listAppend trivAfterType
                                 (cons (tr/elemToken lbTok)
                                   (listAppend specElems
                                     (listAppend trivRb
                                       (cons (tr/elemToken rbTok)
                                         (listAppend fromElems semiElems)))))))))))
                 (start (tr/tokenStart exportTok))
                 (end (tr/elementEnd (optionOr (listLast kids) (tr/elemToken rbTok))))
                 (node (tr/makeNode "exportDecl" start end kids))]
             (ParseResult :node node :rest remSemi))
           (let [(typeRes (parseTypeAliasDecl remNext text))
                 (typeNode typeRes.node)
                 (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode typeNode))))))
                 (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd typeNode) kids))]
             (ParseResult :node node :rest typeRes.rest)))))
      ((= firstStr "interface")
       (let [(ifaceRes (parseInterfaceDecl remNext text))
             (ifaceNode ifaceRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode ifaceNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd ifaceNode) kids))]
         (ParseResult :node node :rest ifaceRes.rest)))
      ((or (= firstStr "enum") (and (= firstStr "const") (let [(sp2 (skipTrivia tlNext)) (rem2 (pairSecond sp2))] (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "enum")))))
       (let [(enumRes (parseEnumDecl remNext text))
             (enumNode enumRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode enumNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd enumNode) kids))]
         (ParseResult :node node :rest enumRes.rest)))
      ((or (= firstStr "namespace") (= firstStr "module"))
       (let [(nsRes (parseNamespaceDecl remNext text))
             (nsNode nsRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode nsNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd nsNode) kids))]
         (ParseResult :node node :rest nsRes.rest)))
      ((or (= firstStr "class") (= firstStr "abstract"))
       (let [(classRes (parseClassDecl remNext text))
             (classNode classRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode classNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd classNode) kids))]
         (ParseResult :node node :rest classRes.rest)))
      ((or (= firstStr "function") (and (= firstStr "async") (let [(sp2 (skipTrivia tlNext)) (rem2 (pairSecond sp2))] (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "function")))))
       (let [(fnRes (parseFunctionDecl remNext text))
             (fnNode fnRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode fnNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd fnNode) kids))]
         (ParseResult :node node :rest fnRes.rest)))
      ((or (= firstStr "var") (or (= firstStr "let") (= firstStr "const")))
       (let [(varRes (parseTsVarStmt remNext text))
             (varNode varRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode varNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd varNode) kids))]
         (ParseResult :node node :rest varRes.rest)))
      ((= firstStr "declare")
       (let [(decRes (parseTsDecl remNext text))
             (decNode decRes.node)
             (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (list (tr/elemNode decNode))))))
             (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd decNode) kids))]
         (ParseResult :node node :rest decRes.rest)))
      ((= firstStr "default")
       (let [(spDef (skipTrivia tlNext))
             (trivDef (pairFirst spDef))
             (remDef (pairSecond spDef))
             (defFirst (if (listEmpty? remDef) (tr/makeToken "" 0 0) (optionOr (listHead remDef) (tr/makeToken "" 0 0))))
             (defStr (tokenSlice defFirst text))]
         (cond
           ((= defStr "interface")
            (let [(ifaceRes (parseInterfaceDecl remDef text))
                  (ifaceNode ifaceRes.node)
                  (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (cons (tr/elemToken firstAfterExport) (listAppend trivDef (list (tr/elemNode ifaceNode))))))))
                  (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd ifaceNode) kids))]
              (ParseResult :node node :rest ifaceRes.rest)))
           ((or (= defStr "class") (and (= defStr "abstract") (let [(spAb (skipTrivia (optionOr (listTail remDef) (list)))) (remAb (pairSecond spAb))] (and (not (listEmpty? remAb)) (= (tokenSlice (optionOr (listHead remAb) (tr/makeToken "" 0 0)) text) "class")))))
            (let [(classRes (parseClassDecl remDef text))
                  (classNode classRes.node)
                  (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (cons (tr/elemToken firstAfterExport) (listAppend trivDef (list (tr/elemNode classNode))))))))
                  (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd classNode) kids))]
              (ParseResult :node node :rest classRes.rest)))
           ((or (= defStr "function") (and (= defStr "async") (let [(sp2 (skipTrivia (optionOr (listTail remDef) (list)))) (rem2 (pairSecond sp2))] (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "function")))))
            (let [(fnRes (parseFunctionDecl remDef text))
                  (fnNode fnRes.node)
                  (kids (listAppend triv (cons (tr/elemToken exportTok) (listAppend trivNext (cons (tr/elemToken firstAfterExport) (listAppend trivDef (list (tr/elemNode fnNode))))))))
                  (node (tr/makeNode "exportDecl" (tr/tokenStart exportTok) (tr/nodeEnd fnNode) kids))]
              (ParseResult :node node :rest fnRes.rest)))
           (else
            (let [(res (jsm/parseExportDecl rem text))]
              (mt res
                ((err _)
                 (let [(advToks (optionOr (listTail rem) (list)))
                       (errNode (tr/makeErrorNode (tr/tokenStart exportTok) (tr/tokenEnd exportTok) (list (tr/elemToken exportTok))))]
                   (ParseResult :node errNode :rest advToks)))
                ((ok parseRes) parseRes)))))))
      (else
       (let [(res (jsm/parseExportDecl rem text))]
         (mt res
           ((err _)
            (let [(advToks (optionOr (listTail rem) (list)))
                  (errNode (tr/makeErrorNode (tr/tokenStart exportTok) (tr/tokenEnd exportTok) (list (tr/elemToken exportTok))))]
              (ParseResult :node errNode :rest advToks)))
           ((ok parseRes) parseRes))))))

fn parseTsDecl toks: (List tr/Token) text: String -> ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(firstTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind firstTok))
            (w (tokenSlice firstTok text))]
        (cond
          ((= k "at")
           (let [(decsRes (parseDecoratorsLoop rem text (list)))
                 (remAfterDecs decsRes.rest)
                 (spNext (skipTrivia remAfterDecs))
                 (remNext (pairSecond spNext))
                 (nextTok (if (listEmpty? remNext) (tr/makeToken "" 0 0) (optionOr (listHead remNext) (tr/makeToken "" 0 0))))
                 (nw (tokenSlice nextTok text))]
             (if (= nw "export")
               (let [(expRes (parseTsExportDecl remNext text))
                     (expNode expRes.node)
                     (allKids (listAppend decsRes.elements (list (tr/elemNode expNode))))
                     (start (tr/elementStart (optionOr (listHead allKids) (tr/elemToken firstTok))))
                     (end (tr/nodeEnd expNode))
                     (node (tr/makeNode "exportDecl" start end allKids))]
                 (ParseResult :node node :rest expRes.rest))
               (parseClassDecl rem text))))
          ((= w "export")
           (parseTsExportDecl rem text))
          ((= w "import")
           (parseTsImportDecl rem text))
          ((= w "interface")
           (parseInterfaceDecl rem text))
          ((and (= w "type")
                (let [(sp2 (skipTrivia tl))
                      (rem2 (pairSecond sp2))]
                  (and (not (listEmpty? rem2))
                       (let [(nk (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))))]
                         (and (!= nk "assign") (!= nk "semicolon"))))))
           (parseTypeAliasDecl rem text))
          ((or (= w "enum") (and (= w "const") (let [(sp2 (skipTrivia tl)) (rem2 (pairSecond sp2))] (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "enum")))))
           (parseEnumDecl rem text))
          ((or (= w "namespace") (or (= w "module") (= w "global")))
           (parseNamespaceDecl rem text))
          ((= w "declare")
           (let [(sp2 (skipTrivia tl))
                 (triv2 (pairFirst sp2))
                 (rem2 (pairSecond sp2))
                 (nextTok (if (listEmpty? rem2) (tr/makeToken "" 0 0) (optionOr (listHead rem2) (tr/makeToken "" 0 0))))
                 (nw (tokenSlice nextTok text))]
             (cond
               ((= nw "interface")
                (let [(res (parseInterfaceDecl rem2 text))
                      (n res.node)
                      (kids (listAppend triv (cons (tr/elemToken firstTok) (listAppend triv2 (list (tr/elemNode n))))))]
                  (ParseResult :node (tr/makeNode "ambientDecl" (tr/tokenStart firstTok) (tr/nodeEnd n) kids) :rest res.rest)))
               ((= nw "type")
                (let [(res (parseTypeAliasDecl rem2 text))
                      (n res.node)
                      (kids (listAppend triv (cons (tr/elemToken firstTok) (listAppend triv2 (list (tr/elemNode n))))))]
                  (ParseResult :node (tr/makeNode "ambientDecl" (tr/tokenStart firstTok) (tr/nodeEnd n) kids) :rest res.rest)))
               ((or (= nw "enum") (and (= nw "const") (let [(sp3 (skipTrivia (optionOr (listTail rem2) (list)))) (rem3 (pairSecond sp3))] (and (not (listEmpty? rem3)) (= (tokenSlice (optionOr (listHead rem3) (tr/makeToken "" 0 0)) text) "enum")))))
                (let [(res (parseEnumDecl rem2 text))
                      (n res.node)
                      (kids (listAppend triv (cons (tr/elemToken firstTok) (listAppend triv2 (list (tr/elemNode n))))))]
                  (ParseResult :node (tr/makeNode "ambientDecl" (tr/tokenStart firstTok) (tr/nodeEnd n) kids) :rest res.rest)))
               ((or (= nw "namespace") (or (= nw "module") (= nw "global")))
                (let [(res (parseNamespaceDecl rem2 text))
                      (n res.node)
                      (kids (listAppend triv (cons (tr/elemToken firstTok) (listAppend triv2 (list (tr/elemNode n))))))]
                  (ParseResult :node (tr/makeNode "ambientDecl" (tr/tokenStart firstTok) (tr/nodeEnd n) kids) :rest res.rest)))
               ((or (= nw "class") (= nw "abstract"))
                (let [(res (parseClassDecl rem text))] res))
               ((or (= nw "function") (and (= nw "async") (let [(sp3 (skipTrivia (optionOr (listTail rem2) (list)))) (rem3 (pairSecond sp3))] (and (not (listEmpty? rem3)) (= (tokenSlice (optionOr (listHead rem3) (tr/makeToken "" 0 0)) text) "function")))))
                (let [(res (parseFunctionDecl rem text))] res))
               ((or (= nw "var") (or (= nw "let") (= nw "const")))
                (let [(res (parseTsVarStmt rem text))] res))
               (else
                (let [(res (parseTsVarStmt rem text))] res)))))
          ((or (= w "class") (= w "abstract"))
           (parseClassDecl rem text))
          ((or (= w "function") (and (= w "async") (let [(sp2 (skipTrivia tl)) (rem2 (pairSecond sp2))] (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "function")))))
           (parseFunctionDecl rem text))
          ((or (= w "var") (or (= w "let") (= w "const")))
           (parseTsVarStmt rem text))
          (else
           (let [(stmtRes (stmt/parseStatement rem text true false))
                 (stmtNode stmtRes.node)
                 (remToks stmtRes.rest)]
             (if (= (listLength remToks) (listLength rem))
               (let [(advToks (optionOr (listTail rem) (list)))
                     (errElem (tr/elemToken firstTok))]
                 (ParseResult :node (tr/makeErrorNode (tr/tokenStart firstTok) (tr/tokenEnd firstTok) (list errElem)) :rest advToks))
               stmtRes)))))))

fn parseModuleItemsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (List tr/TreeElement) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ok (listAppend acc triv))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ok (listAppend acc triv))
          (let [(declRes (parseTsDecl rem text))
                (declNode declRes.node)
                (remDecl declRes.rest)
                (accWithDecl (listAppend acc (listAppend triv (list (tr/elemNode declNode)))))]
            (if (= (listLength remDecl) (listLength rem))
              (let [(advToks (optionOr (listTail rem) (list)))
                    (errElem (tr/elemToken hd))]
                (parseModuleItemsLoop advToks text (listAppend accWithDecl (list errElem))))
              (parseModuleItemsLoop remDecl text accWithDecl)))))))

fn parseTsModuleTokens toks: (List tr/Token) text: String -> (Result tr/Node String)
  (let [(loopRes (parseModuleItemsLoop toks text (list)))]
    (mt loopRes
      ((err msg) (err msg))
      ((ok elems)
       (let [(root (tr/makeNode "module" 0 (stringLength text) elems))]
         (mt (firstErrorOffset elems)
           ((some off)
            (err (str "Parse error at offset " (stringFromInt64 off))))
           ((none)
            (mt (tr/checkTiling root (stringLength text))
              ((ok _) (ok root))
              ((err msg) (err msg)))))))))

fn splitTypeTokens toks: (List tr/Token) -> (List tr/Token)
  (if (listEmpty? toks)
    toks
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (st (tr/tokenStart hd))
          (en (tr/tokenEnd hd))]
      (cond
        ((= k "gte")
         (cons (tr/makeToken "gt" st (- en 1)) (cons (tr/makeToken "assign" (- en 1) en) (splitTypeTokens tl))))
        ((= k "rshift")
         (cons (tr/makeToken "gt" st (- en 1)) (cons (tr/makeToken "gt" (- en 1) en) (splitTypeTokens tl))))
        ((= k "urshift")
         (cons (tr/makeToken "gt" st (- en 2)) (cons (tr/makeToken "gt" (- en 2) (- en 1)) (cons (tr/makeToken "gt" (- en 1) en) (splitTypeTokens tl)))))
        (else
         (cons hd (splitTypeTokens tl))))))

fn parseTsModule text: String -> (Result tr/Node String)
  (let [(rawToks (lx/tokenize text))
        (toks (splitTypeTokens rawToks))]
    (parseTsModuleTokens toks text))

fn parse text: String -> (Result tr/Node String)
  (parseTsModule text)

fn findDeclName toks: (List tr/Token) text: String -> tr/Token
  (if (listEmpty? toks)
    (tr/makeToken "" 0 0)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (w (tokenSlice hd text))]
      (if (and (= k "ident")
               (and (!= w "export")
               (and (!= w "default")
               (and (!= w "declare")
               (and (!= w "abstract")
               (and (!= w "interface")
               (and (!= w "type")
               (and (!= w "enum")
               (and (!= w "const")
               (and (!= w "namespace")
               (and (!= w "module")
               (and (!= w "class")
                    (!= w "function")))))))))))))
        hd
        (findDeclName tl text))))

fn formatDeclItems nodes: (List tr/Node) text: String -> String
  (if (listEmpty? nodes)
    ""
    (let [(hd (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))
          (s (declToSExpr hd text))
          (restStr (formatDeclItems tl text))]
      (if (stringEmpty? restStr)
        s
        (str s " " restStr))))

fn declToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))
        (kids (tr/nodeChildren node))
        (childNodes (findChildNodes kids))]
    (cond
      ((= k "module")
       (let [(inner (formatDeclItems childNodes text))]
         (if (stringEmpty? inner) "(module)" (str "(module " inner ")"))))
      ((= k "interfaceDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(interface " (tokenSlice nameTok text) ")")))
      ((= k "typeAliasDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(type " (tokenSlice nameTok text) ")")))
      ((= k "enumDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(enum " (tokenSlice nameTok text) ")")))
      ((= k "namespaceDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(namespace " (tokenSlice nameTok text) ")")))
      ((= k "moduleDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(module " (tokenSlice nameTok text) ")")))
      ((= k "classDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(class " (tokenSlice nameTok text) ")")))
      ((= k "functionDecl")
       (let [(toks (findChildTokens kids))
             (nameTok (findDeclName toks text))]
         (str "(function " (tokenSlice nameTok text) ")")))
      ((= k "exportDecl")
       (if (listEmpty? childNodes)
         "(export)"
         (str "(export " (declToSExpr (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))) text) ")")))
      ((= k "importDecl")
       "(import)")
      ((= k "importEqualsDecl")
       "(import-equals)")
      ((= k "exportAssignment")
       "(export=)")
      ((= k "exportAsNamespace")
       "(export-as-namespace)")
      ((= k "decorator")
       "(@)")
      (else
       (stmt/stmtToSExpr node text))))

fn isDeclNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "module")
    (or (= k "interfaceDecl")
    (or (= k "typeAliasDecl")
    (or (= k "enumDecl")
    (or (= k "namespaceDecl")
    (or (= k "moduleDecl")
    (or (= k "classDecl")
    (or (= k "functionDecl")
    (or (= k "varDecl")
    (or (= k "letDecl")
    (or (= k "constDecl")
    (or (= k "importDecl")
    (or (= k "exportDecl")
    (or (= k "exportAssignment")
    (or (= k "exportAsNamespace")
    (or (= k "importEqualsDecl")
    (or (= k "decorator")
    (or (= k "parameterProperty")
    (or (= k "indexSignature")
    (or (= k "propertySignature")
    (or (= k "methodSignature")
    (or (= k "callSignature")
    (or (= k "constructSignature")
    (or (= k "classField")
    (or (= k "classMethod")
    (or (= k "classConstructor")
    (or (= k "classGetter")
    (or (= k "classSetter")
    (or (= k "staticBlock")
    (or (= k "enumMember")
        (= k "ambientDecl"))))))))))))))))))))))))))))))))

fn declKind node: tr/Node -> String
  (tr/nodeKind node)

