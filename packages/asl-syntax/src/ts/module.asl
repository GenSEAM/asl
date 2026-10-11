(module asl-syntax/ts/module
  :x [parse
      parseModule
      parseModuleTokens
      parseTsModule
      parseTsModuleTokens
      parseImportDecl
      parseExportDecl
      isModuleNode
      moduleKind firstErrorOffset skipTrivia splitTypeTokens]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/ts/types :a ts)
      (asl-syntax/ts/decl :a decl)])

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

fn treeHasError? node: tr/Node -> Bool
  (if (tr/isErrorNode node)
    true
    (elementsHaveError? (tr/nodeChildren node)))

fn elementsHaveError? elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n) (if (treeHasError? n) true (elementsHaveError? tl)))
        ((tr/elemToken t) (if (tr/isErrorToken t) true (elementsHaveError? tl))))))

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

fn parseTsExprStmt toks: (List tr/Token) text: String -> tr/ParseResult
  (let [(exprRes (ts/parseTsExpr toks text 0))
        (exprNode exprRes.node)
        (rem exprRes.rest)
        (spSemi (skipTrivia rem))
        (trivSemi (pairFirst spSemi))
        (remSemi (pairSecond spSemi))]
    (if (and (not (listEmpty? remSemi)) (= (tr/tokenKind (optionOr (listHead remSemi) (tr/makeToken "" 0 0))) "semicolon"))
      (let [(semiTok (optionOr (listHead remSemi) (tr/makeToken "" 0 0)))
            (tlSemi (optionOr (listTail remSemi) (list)))
            (kids (cons (tr/elemNode exprNode) (listAppend trivSemi (list (tr/elemToken semiTok)))))
            (node (tr/makeNode "exprStmt" (tr/nodeStart exprNode) (tr/tokenEnd semiTok) kids))]
        (tr/ParseResult :node node :rest tlSemi))
      (let [(kids (list (tr/elemNode exprNode)))
            (node (tr/makeNode "exprStmt" (tr/nodeStart exprNode) (tr/nodeEnd exprNode) kids))]
        (tr/ParseResult :node node :rest rem))))

fn parseTsItem toks: (List tr/Token) text: String -> tr/ParseResult
  (let [(declRes (decl/parseTsDecl toks text))
        (declNode declRes.node)
        (remDecl declRes.rest)]
    (if (and (!= (listLength remDecl) (listLength toks)) (not (treeHasError? declNode)))
      declRes
      (let [(exprRes (parseTsExprStmt toks text))
            (exprNode exprRes.node)
            (remExpr exprRes.rest)]
        (if (and (!= (listLength remExpr) (listLength toks)) (not (treeHasError? exprNode)))
          exprRes
          declRes))))

fn parseModuleItemsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (List tr/TreeElement) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ok (listAppend acc triv))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind hd) "rbrace")
          (ok (listAppend acc triv))
          (let [(itemRes (parseTsItem rem text))
                (itemNode itemRes.node)
                (remItem itemRes.rest)
                (accWithItem (listAppend acc (listAppend triv (list (tr/elemNode itemNode)))))]
            (if (= (listLength remItem) (listLength rem))
              (let [(advToks (optionOr (listTail rem) (list)))
                    (errElem (tr/elemToken hd))]
                (parseModuleItemsLoop advToks text (listAppend accWithItem (list errElem))))
              (parseModuleItemsLoop remItem text accWithItem)))))))

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
         (if (tr/isErrorNode node)
           (some (tr/nodeStart node))
           (mt (firstErrorOffset (tr/nodeChildren node))
             ((some off) (some off))
             ((none) (firstErrorOffset tl))))))))

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

fn parseTsModule text: String -> (Result tr/Node String)
  (let [(rawToks (lx/tokenize text))
        (toks (splitTypeTokens rawToks))]
    (parseTsModuleTokens toks text))

fn parseModule text: String -> (Result tr/Node String)
  (parseTsModule text)

fn parseModuleTokens toks: (List tr/Token) text: String -> (Result tr/Node String)
  (parseTsModuleTokens toks text)

fn parse text: String -> (Result tr/Node String)
  (parseTsModule text)

fn parseImportDecl toks: (List tr/Token) text: String -> tr/ParseResult
  (decl/parseTsImportDecl toks text)

fn parseExportDecl toks: (List tr/Token) text: String -> tr/ParseResult
  (decl/parseTsExportDecl toks text)

fn isModuleNode node: tr/Node -> Bool
  (= (tr/nodeKind node) "module")

fn moduleKind node: tr/Node -> String
  (tr/nodeKind node)
