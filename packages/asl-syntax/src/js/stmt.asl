(module asl-syntax/js/stmt
  :x [parse
      parseScript
      parseStatements
      parseStatement
      parseBlock
      parsePattern
      stmtToSExpr
      isStatementNode
      statementKind findChildNodes]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)])

(schema StmtsResult
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
         (let [(k (tr/tokenKind tok))]
           (if (= k "newline")
             true
             (if (= k "comment")
               (let [(sl (tokenSlice tok text))]
                 (if (or (stringContains? sl "
") (stringContains? sl "
"))
                   true
                   (hasNewlineElements tl text)))
               (hasNewlineElements tl text)))))
        ((tr/elemNode _)
         (hasNewlineElements tl text)))))
fn finishStatementWithSemi nodeKids: (List tr/TreeElement) startPos: Int64 nodeKind: String rem: (List tr/Token) text: String -> tr/ParseResult
  (let [(sp (skipTrivia rem))
        (triv (pairFirst sp))
        (afterTriv (pairSecond sp))]
    (if (listEmpty? afterTriv)
      (let [(lastElem (optionOr (listLast nodeKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
            (endPos (tr/elementEnd lastElem))
            (node (tr/makeNode nodeKind startPos endPos nodeKids))]
        (tr/ParseResult :node node :rest rem))
      (let [(firstTok (optionOr (listHead afterTriv) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind firstTok))]
        (cond
          ((= k "semicolon")
           (let [(allKids (listAppend nodeKids (listAppend triv (list (tr/elemToken firstTok)))))
                 (endPos (tr/tokenEnd firstTok))
                 (node (tr/makeNode nodeKind startPos endPos allKids))]
             (tr/ParseResult :node node :rest (optionOr (listTail afterTriv) (list)))))
          ((or (= k "rbrace") (hasNewlineElements triv text))
           (let [(lastElem (optionOr (listLast nodeKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
                 (endPos (tr/elementEnd lastElem))
                 (node (tr/makeNode nodeKind startPos endPos nodeKids))]
             (tr/ParseResult :node node :rest rem)))
          (else
           (let [(errTok (tr/makeToken "error" (tr/tokenStart firstTok) (tr/tokenStart firstTok)))
                 (allKids (listAppend nodeKids (list (tr/elemToken errTok))))
                 (lastElem (optionOr (listLast allKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
                 (endPos (tr/elementEnd lastElem))
                 (node (tr/makeNode nodeKind startPos endPos allKids))]
             (tr/ParseResult :node node :rest rem)))))))
fn parseDeclarator toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (tr/ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (cond
          ((or (= k "ident")
               (or (and (= k "keyword") (and (= (tokenSlice hd text) "await") (not inAsync)))
                   (and (= k "keyword") (and (= (tokenSlice hd text) "yield") (not inGen)))))
           (let [(nameElem (tr/elemToken hd))
                 (sp2 (skipTrivia tl))
                 (triv2 (pairFirst sp2))
                 (rem2 (pairSecond sp2))]
             (if (and (not (listEmpty? rem2)) (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "assign"))
               (let [(eqTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
                     (initToks (optionOr (listTail rem2) (list)))
                     (sp3 (skipTrivia initToks))
                     (triv3 (pairFirst sp3))
                     (rem3 (pairSecond sp3))
                     (initRes (parseCoverExpr rem3 text 1 inAsync inGen))
                     (initNode initRes.node)
                     (kids (cons nameElem (listAppend triv2 (cons (tr/elemToken eqTok) (listAppend triv3 (list (tr/elemNode initNode)))))))
                     (node (tr/makeNode "declarator" (tr/tokenStart hd) (tr/nodeEnd initNode) kids))]
                 (tr/ParseResult :node node :rest initRes.rest))
               (let [(kids (list nameElem))
                     (node (tr/makeNode "declarator" (tr/tokenStart hd) (tr/tokenEnd hd) kids))]
                 (tr/ParseResult :node node :rest tl)))))
          ((or (= k "lbracket") (= k "lbrace"))
           (let [(patRes (parsePattern rem text))
                 (patNode patRes.node)
                 (patElem (tr/elemNode patNode))
                 (remPat patRes.rest)
                 (sp2 (skipTrivia remPat))
                 (triv2 (pairFirst sp2))
                 (rem2 (pairSecond sp2))]
             (if (and (not (listEmpty? rem2)) (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "assign"))
               (let [(eqTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
                     (initToks (optionOr (listTail rem2) (list)))
                     (sp3 (skipTrivia initToks))
                     (triv3 (pairFirst sp3))
                     (rem3 (pairSecond sp3))
                     (initRes (parseCoverExpr rem3 text 1 inAsync inGen))
                     (initNode initRes.node)
                     (kids (cons patElem (listAppend triv2 (cons (tr/elemToken eqTok) (listAppend triv3 (list (tr/elemNode initNode)))))))
                     (node (tr/makeNode "declarator" (tr/nodeStart patNode) (tr/nodeEnd initNode) kids))]
                 (tr/ParseResult :node node :rest initRes.rest))
               (let [(kids (list patElem))
                     (node (tr/makeNode "declarator" (tr/nodeStart patNode) (tr/nodeEnd patNode) kids))]
                 (tr/ParseResult :node node :rest remPat)))))
          (else
           (let [(node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))))]
             (tr/ParseResult :node node :rest tl)))))))
fn parseDeclaratorsLoop toks: (List tr/Token) text: String inAsync: Bool inGen: Bool acc: (List tr/TreeElement) -> StmtsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (StmtsResult :elements acc :rest toks)
      (let [(declRes (parseDeclarator rem text inAsync inGen))
            (declNode declRes.node)
            (remDecl declRes.rest)
            (accWithDecl (listAppend acc (listAppend triv (list (tr/elemNode declNode)))))
            (sp2 (skipTrivia remDecl))
            (triv2 (pairFirst sp2))
            (rem2 (pairSecond sp2))]
        (if (and (not (listEmpty? rem2)) (= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "comma"))
          (let [(commaTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
                (tlComma (optionOr (listTail rem2) (list)))
                (accWithComma (listAppend accWithDecl (listAppend triv2 (list (tr/elemToken commaTok)))))]
            (parseDeclaratorsLoop tlComma text inAsync inGen accWithComma))
          (StmtsResult :elements accWithDecl :rest remDecl)))))
fn parseVarStmt varTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(kindStr (tokenSlice varTok text))
        (declKind (cond ((= kindStr "var") "varDecl") ((= kindStr "let") "letDecl") (else "constDecl")))
        (res (parseDeclaratorsLoop tl text inAsync inGen (list)))
        (elems (cons (tr/elemToken varTok) res.elements))]
    (finishStatementWithSemi elems (tr/tokenStart varTok) declKind res.rest text))
fn parseBlockBodyLoop toks: (List tr/Token) text: String inAsync: Bool inGen: Bool acc: (List tr/TreeElement) -> StmtsResult
  (if (listEmpty? toks)
    (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
          (endPos (tr/elementEnd lastElem))
          (errTok (tr/makeToken "error" endPos endPos))]
      (StmtsResult :elements (listAppend acc (list (tr/elemToken errTok))) :rest toks))
    (let [(sp (skipTrivia toks))
          (triv (pairFirst sp))
          (rem (pairSecond sp))]
      (if (listEmpty? rem)
        (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
              (endPos (tr/elementEnd lastElem))
              (errTok (tr/makeToken "error" endPos endPos))]
          (StmtsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken errTok)))) :rest rem))
        (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (k (tr/tokenKind hd))]
          (if (= k "rbrace")
            (StmtsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken hd)))) :rest (optionOr (listTail rem) (list)))
            (let [(accWithTriv (listAppend acc triv))
                  (stmtRes (parseStatement rem text inAsync inGen))
                  (stmtNode stmtRes.node)
                  (remToks stmtRes.rest)]
              (if (or (tr/isErrorNode stmtNode) (= (listLength remToks) (listLength rem)))
                (let [(advToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))]
                  (parseBlockBodyLoop advToks text inAsync inGen (listAppend accWithTriv (list (tr/elemNode stmtNode)))))
                (parseBlockBodyLoop remToks text inAsync inGen (listAppend accWithTriv (list (tr/elemNode stmtNode)))))))))))
fn parseBlock toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (if (listEmpty? toks)
    (tr/ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (!= k "lbrace")
        (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest tl)
        (let [(res (parseBlockBodyLoop tl text inAsync inGen (list (tr/elemToken hd))))
              (elems res.elements)
              (rem res.rest)
              (lastElem (optionOr (listLast elems) (tr/elemToken hd)))
              (endPos (tr/elementEnd lastElem))
              (node (tr/makeNode "block" (tr/tokenStart hd) endPos elems))]
          (tr/ParseResult :node node :rest rem)))))

fn parseCoverExpr toks: (List tr/Token) text: String minPrec: Int64 inAsync: Bool inGen: Bool -> tr/ParseResult
  (cv/parseCoverExprCtxWithBody toks text minPrec inAsync inGen parseBlock)
fn parsePattern toks: (List tr/Token) text: String -> tr/ParseResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (tr/ParseResult :node (tr/makeErrorNode 0 0 triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind hd))]
        (if (or (= k "lbracket") (= k "lbrace"))
          (let [(patRes (parseCoverExpr rem text 25 false false))
                (patNode patRes.node)
                (refined (resultOr (cv/refineToPattern patNode) patNode))]
            (tr/ParseResult :node refined :rest patRes.rest))
          (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest (optionOr (listTail rem) (list)))))))
fn parseIfStmt ifTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (or (listEmpty? rem1) (!= (tr/tokenKind (optionOr (listHead rem1) (tr/makeToken "" 0 0))) "lparen"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart ifTok) (tr/tokenEnd ifTok) (list (tr/elemToken ifTok))) :rest tl)
      (let [(lpTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem1) (list)))
            (sp2 (skipTrivia tlLp))
            (triv2 (pairFirst sp2))
            (rem2 (pairSecond sp2))
            (condRes (parseCoverExpr rem2 text 0 inAsync inGen))
            (condNode condRes.node)
            (remCond condRes.rest)
            (sp3 (skipTrivia remCond))
            (triv3 (pairFirst sp3))
            (rem3 (pairSecond sp3))
            (rpPair (expectClose rem3 "rparen" (tr/nodeEnd condNode)))
            (rpTok (pairFirst rpPair))
            (remRp (pairSecond rpPair))
            (sp4 (skipTrivia remRp))
            (triv4 (pairFirst sp4))
            (rem4 (pairSecond sp4))
            (consRes (parseStatement rem4 text inAsync inGen))
            (consNode consRes.node)
            (remCons consRes.rest)
            (kidsBeforeElse (cons (tr/elemToken ifTok)
                              (listAppend triv1
                                (cons (tr/elemToken lpTok)
                                  (listAppend triv2
                                    (cons (tr/elemNode condNode)
                                      (listAppend triv3
                                        (cons (tr/elemToken rpTok)
                                          (listAppend triv4
                                            (list (tr/elemNode consNode)))))))))))
            (spElse (skipTrivia remCons))
            (trivElse (pairFirst spElse))
            (remElse (pairSecond spElse))]
        (if (and (not (listEmpty? remElse)) (= (tokenSlice (optionOr (listHead remElse) (tr/makeToken "" 0 0)) text) "else"))
          (let [(elseTok (optionOr (listHead remElse) (tr/makeToken "" 0 0)))
                (tlElse (optionOr (listTail remElse) (list)))
                (sp5 (skipTrivia tlElse))
                (triv5 (pairFirst sp5))
                (rem5 (pairSecond sp5))
                (altRes (parseStatement rem5 text inAsync inGen))
                (altNode altRes.node)
                (allKids (listAppend kidsBeforeElse
                           (listAppend trivElse
                             (cons (tr/elemToken elseTok)
                               (listAppend triv5
                                 (list (tr/elemNode altNode)))))))
                (endPos (tr/nodeEnd altNode))
                (node (tr/makeNode "ifStmt" (tr/tokenStart ifTok) endPos allKids))]
            (tr/ParseResult :node node :rest altRes.rest))
          (let [(endPos (tr/nodeEnd consNode))
                (node (tr/makeNode "ifStmt" (tr/tokenStart ifTok) endPos kidsBeforeElse))]
            (tr/ParseResult :node node :rest remCons))))))
fn parseWhileStmt whileTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (or (listEmpty? rem1) (!= (tr/tokenKind (optionOr (listHead rem1) (tr/makeToken "" 0 0))) "lparen"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart whileTok) (tr/tokenEnd whileTok) (list (tr/elemToken whileTok))) :rest tl)
      (let [(lpTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem1) (list)))
            (sp2 (skipTrivia tlLp))
            (triv2 (pairFirst sp2))
            (rem2 (pairSecond sp2))
            (condRes (parseCoverExpr rem2 text 0 inAsync inGen))
            (condNode condRes.node)
            (remCond condRes.rest)
            (sp3 (skipTrivia remCond))
            (triv3 (pairFirst sp3))
            (rem3 (pairSecond sp3))
            (rpPair (expectClose rem3 "rparen" (tr/nodeEnd condNode)))
            (rpTok (pairFirst rpPair))
            (remRp (pairSecond rpPair))
            (sp4 (skipTrivia remRp))
            (triv4 (pairFirst sp4))
            (rem4 (pairSecond sp4))
            (bodyRes (parseStatement rem4 text inAsync inGen))
            (bodyNode bodyRes.node)
            (kids (cons (tr/elemToken whileTok)
                    (listAppend triv1
                      (cons (tr/elemToken lpTok)
                        (listAppend triv2
                          (cons (tr/elemNode condNode)
                            (listAppend triv3
                              (cons (tr/elemToken rpTok)
                                (listAppend triv4
                                  (list (tr/elemNode bodyNode)))))))))))
            (endPos (tr/nodeEnd bodyNode))
            (node (tr/makeNode "whileStmt" (tr/tokenStart whileTok) endPos kids))]
        (tr/ParseResult :node node :rest bodyRes.rest))))
fn parseDoWhileStmt doTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))
        (bodyRes (parseStatement rem1 text inAsync inGen))
        (bodyNode bodyRes.node)
        (remBody bodyRes.rest)
        (sp2 (skipTrivia remBody))
        (triv2 (pairFirst sp2))
        (rem2 (pairSecond sp2))]
    (if (or (listEmpty? rem2) (!= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "while"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart doTok) (tr/nodeEnd bodyNode) (cons (tr/elemToken doTok) (listAppend triv1 (list (tr/elemNode bodyNode))))) :rest remBody)
      (let [(whileTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
            (tlWhile (optionOr (listTail rem2) (list)))
            (sp3 (skipTrivia tlWhile))
            (triv3 (pairFirst sp3))
            (rem3 (pairSecond sp3))]
        (if (or (listEmpty? rem3) (!= (tr/tokenKind (optionOr (listHead rem3) (tr/makeToken "" 0 0))) "lparen"))
          (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart doTok) (tr/tokenEnd whileTok) (list (tr/elemToken doTok))) :rest rem3)
          (let [(lpTok (optionOr (listHead rem3) (tr/makeToken "" 0 0)))
                (tlLp (optionOr (listTail rem3) (list)))
                (sp4 (skipTrivia tlLp))
                (triv4 (pairFirst sp4))
                (rem4 (pairSecond sp4))
                (condRes (parseCoverExpr rem4 text 0 inAsync inGen))
                (condNode condRes.node)
                (remCond condRes.rest)
                (sp5 (skipTrivia remCond))
                (triv5 (pairFirst sp5))
                (rem5 (pairSecond sp5))
                (rpPair (expectClose rem5 "rparen" (tr/nodeEnd condNode)))
                (rpTok (pairFirst rpPair))
                (remRp (pairSecond rpPair))
                (kids (cons (tr/elemToken doTok)
                        (listAppend triv1
                          (cons (tr/elemNode bodyNode)
                            (listAppend triv2
                              (cons (tr/elemToken whileTok)
                                (listAppend triv3
                                  (cons (tr/elemToken lpTok)
                                    (listAppend triv4
                                      (cons (tr/elemNode condNode)
                                        (listAppend triv5
                                          (list (tr/elemToken rpTok)))))))))))))]
            (finishStatementWithSemi kids (tr/tokenStart doTok) "doWhileStmt" remRp text))))))
fn parseForStmt forTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))
        (hasAwait (and (not (listEmpty? rem1)) (= (tokenSlice (optionOr (listHead rem1) (tr/makeToken "" 0 0)) text) "await")))
        (awaitTokOpt (if hasAwait (some (optionOr (listHead rem1) (tr/makeToken "" 0 0))) (none)))
        (tlAwait (if hasAwait (optionOr (listTail rem1) (list)) rem1))
        (sp2 (if hasAwait (skipTrivia tlAwait) sp1))
        (triv2 (pairFirst sp2))
        (rem2 (pairSecond sp2))]
    (if (or (listEmpty? rem2) (!= (tr/tokenKind (optionOr (listHead rem2) (tr/makeToken "" 0 0))) "lparen"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart forTok) (tr/tokenEnd forTok) (list (tr/elemToken forTok))) :rest tl)
      (let [(lpTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem2) (list)))
            (spIn (skipTrivia tlLp))
            (trivIn (pairFirst spIn))
            (remIn (pairSecond spIn))]
        (if (listEmpty? remIn)
          (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart forTok) (tr/tokenEnd lpTok) (list (tr/elemToken forTok))) :rest remIn)
          (let [(hdIn (optionOr (listHead remIn) (tr/makeToken "" 0 0)))
                (kIn (tr/tokenKind hdIn))
                (slIn (tokenSlice hdIn text))
                (isDecl (or (= slIn "var") (or (= slIn "let") (= slIn "const"))))]
            (if isDecl
              (let [(spDecl (skipTrivia (optionOr (listTail remIn) (list))))
                    (trivDecl (pairFirst spDecl))
                    (remDecl (pairSecond spDecl))
                    (declRes (parseDeclarator remDecl text inAsync inGen))
                    (declNode declRes.node)
                    (remAfterDecl declRes.rest)
                    (spAfter (skipTrivia remAfterDecl))
                    (trivAfter (pairFirst spAfter))
                    (remAfter (pairSecond spAfter))
                    (tokAfter (if (listEmpty? remAfter) (tr/makeToken "" 0 0) (optionOr (listHead remAfter) (tr/makeToken "" 0 0))))
                    (slAfter (tokenSlice tokAfter text))]
                (cond
                  ((= slAfter "in")
                   (let [(inTok tokAfter)
                         (tlIn (optionOr (listTail remAfter) (list)))
                         (spR (skipTrivia tlIn))
                         (trivR (pairFirst spR))
                         (remR (pairSecond spR))
                         (rRes (parseCoverExpr remR text 0 inAsync inGen))
                         (rNode rRes.node)
                         (remRRes rRes.rest)
                         (spClose (skipTrivia remRRes))
                         (trivClose (pairFirst spClose))
                         (remClose (pairSecond spClose))
                         (rpPair (expectClose remClose "rparen" (tr/nodeEnd rNode)))
                         (rpTok (pairFirst rpPair))
                         (remRp (pairSecond rpPair))
                         (spB (skipTrivia remRp))
                         (trivB (pairFirst spB))
                         (remB (pairSecond spB))
                         (bodyRes (parseStatement remB text inAsync inGen))
                         (bodyNode bodyRes.node)
                         (declKids (cons (tr/elemToken hdIn) (listAppend trivDecl (list (tr/elemNode declNode)))))
                         (declKind (cond ((= slIn "var") "varDecl") ((= slIn "let") "letDecl") (else "constDecl")))
                         (varNode (tr/makeNode declKind (tr/tokenStart hdIn) (tr/nodeEnd declNode) declKids))
                         (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                         (kids (listAppend prefixElems
                                 (listAppend trivIn
                                   (cons (tr/elemNode varNode)
                                     (listAppend trivAfter
                                       (cons (tr/elemToken inTok)
                                         (listAppend trivR
                                           (cons (tr/elemNode rNode)
                                             (listAppend trivClose
                                               (cons (tr/elemToken rpTok)
                                                 (listAppend trivB
                                                   (list (tr/elemNode bodyNode)))))))))))))
                         (node (tr/makeNode "forInStmt" (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                     (tr/ParseResult :node node :rest bodyRes.rest)))
                  ((= slAfter "of")
                   (let [(ofTok tokAfter)
                         (tlOf (optionOr (listTail remAfter) (list)))
                         (spR (skipTrivia tlOf))
                         (trivR (pairFirst spR))
                         (remR (pairSecond spR))
                         (rRes (parseCoverExpr remR text 0 inAsync inGen))
                         (rNode rRes.node)
                         (remRRes rRes.rest)
                         (spClose (skipTrivia remRRes))
                         (trivClose (pairFirst spClose))
                         (remClose (pairSecond spClose))
                         (rpPair (expectClose remClose "rparen" (tr/nodeEnd rNode)))
                         (rpTok (pairFirst rpPair))
                         (remRp (pairSecond rpPair))
                         (spB (skipTrivia remRp))
                         (trivB (pairFirst spB))
                         (remB (pairSecond spB))
                         (bodyRes (parseStatement remB text inAsync inGen))
                         (bodyNode bodyRes.node)
                         (declKids (cons (tr/elemToken hdIn) (listAppend trivDecl (list (tr/elemNode declNode)))))
                         (declKind (cond ((= slIn "var") "varDecl") ((= slIn "let") "letDecl") (else "constDecl")))
                         (varNode (tr/makeNode declKind (tr/tokenStart hdIn) (tr/nodeEnd declNode) declKids))
                         (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                         (kids (listAppend prefixElems
                                 (listAppend trivIn
                                   (cons (tr/elemNode varNode)
                                     (listAppend trivAfter
                                       (cons (tr/elemToken ofTok)
                                         (listAppend trivR
                                           (cons (tr/elemNode rNode)
                                             (listAppend trivClose
                                               (cons (tr/elemToken rpTok)
                                                 (listAppend trivB
                                                   (list (tr/elemNode bodyNode)))))))))))))
                         (stmtKind (if hasAwait "forAwaitOfStmt" "forOfStmt"))
                         (node (tr/makeNode stmtKind (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                     (tr/ParseResult :node node :rest bodyRes.rest)))
                  (else
                   (let [(varRes (parseVarStmt hdIn (optionOr (listTail remIn) (list)) text inAsync inGen))
                         (varNode varRes.node)
                         (remVar varRes.rest)
                         (spT (skipTrivia remVar))
                         (trivT (pairFirst spT))
                         (remT (pairSecond spT))
                         (hasTest (and (not (listEmpty? remT)) (!= (tr/tokenKind (optionOr (listHead remT) (tr/makeToken "" 0 0))) "semicolon")))
                         (testRes (if hasTest (parseCoverExpr remT text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remT)))
                         (testNode testRes.node)
                         (remTest testRes.rest)
                         (spSemi2 (skipTrivia remTest))
                         (trivSemi2 (pairFirst spSemi2))
                         (remSemi2 (pairSecond spSemi2))
                         (semi2Pair (expectClose remSemi2 "semicolon" (tr/nodeEnd testNode)))
                         (semi2Tok (pairFirst semi2Pair))
                         (remSemi2Tok (pairSecond semi2Pair))
                         (spU (skipTrivia remSemi2Tok))
                         (trivU (pairFirst spU))
                         (remU (pairSecond spU))
                         (hasUpd (and (not (listEmpty? remU)) (!= (tr/tokenKind (optionOr (listHead remU) (tr/makeToken "" 0 0))) "rparen")))
                         (updRes (if hasUpd (parseCoverExpr remU text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remU)))
                         (updNode updRes.node)
                         (remUpd updRes.rest)
                         (spRp (skipTrivia remUpd))
                         (trivRp (pairFirst spRp))
                         (remRp (pairSecond spRp))
                         (rpPair (expectClose remRp "rparen" (tr/nodeEnd updNode)))
                         (rpTok (pairFirst rpPair))
                         (remRpTok (pairSecond rpPair))
                         (spB (skipTrivia remRpTok))
                         (trivB (pairFirst spB))
                         (remB (pairSecond spB))
                         (bodyRes (parseStatement remB text inAsync inGen))
                         (bodyNode bodyRes.node)
                         (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                         (testElems (if hasTest (listAppend trivT (list (tr/elemNode testNode))) trivT))
                         (updElems (if hasUpd (listAppend trivU (list (tr/elemNode updNode))) trivU))
                         (kids (listAppend prefixElems
                                 (listAppend trivIn
                                   (cons (tr/elemNode varNode)
                                     (listAppend testElems
                                       (listAppend trivSemi2
                                         (cons (tr/elemToken semi2Tok)
                                           (listAppend updElems
                                             (listAppend trivRp
                                               (cons (tr/elemToken rpTok)
                                                 (listAppend trivB
                                                   (list (tr/elemNode bodyNode)))))))))))))
                         (node (tr/makeNode "forStmt" (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                     (tr/ParseResult :node node :rest bodyRes.rest)))))
              (if (= kIn "semicolon")
                (let [(semi1Tok hdIn)
                      (tlSemi1 (optionOr (listTail remIn) (list)))
                      (spT (skipTrivia tlSemi1))
                      (trivT (pairFirst spT))
                      (remT (pairSecond spT))
                      (hasTest (and (not (listEmpty? remT)) (!= (tr/tokenKind (optionOr (listHead remT) (tr/makeToken "" 0 0))) "semicolon")))
                      (testRes (if hasTest (parseCoverExpr remT text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remT)))
                      (testNode testRes.node)
                      (remTest testRes.rest)
                      (spSemi2 (skipTrivia remTest))
                      (trivSemi2 (pairFirst spSemi2))
                      (remSemi2 (pairSecond spSemi2))
                      (semi2Pair (expectClose remSemi2 "semicolon" (tr/nodeEnd testNode)))
                      (semi2Tok (pairFirst semi2Pair))
                      (remSemi2Tok (pairSecond semi2Pair))
                      (spU (skipTrivia remSemi2Tok))
                      (trivU (pairFirst spU))
                      (remU (pairSecond spU))
                      (hasUpd (and (not (listEmpty? remU)) (!= (tr/tokenKind (optionOr (listHead remU) (tr/makeToken "" 0 0))) "rparen")))
                      (updRes (if hasUpd (parseCoverExpr remU text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remU)))
                      (updNode updRes.node)
                      (remUpd updRes.rest)
                      (spRp (skipTrivia remUpd))
                      (trivRp (pairFirst spRp))
                      (remRp (pairSecond spRp))
                      (rpPair (expectClose remRp "rparen" (tr/nodeEnd updNode)))
                      (rpTok (pairFirst rpPair))
                      (remRpTok (pairSecond rpPair))
                      (spB (skipTrivia remRpTok))
                      (trivB (pairFirst spB))
                      (remB (pairSecond spB))
                      (bodyRes (parseStatement remB text inAsync inGen))
                      (bodyNode bodyRes.node)
                      (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                      (testElems (if hasTest (listAppend trivT (list (tr/elemNode testNode))) trivT))
                      (updElems (if hasUpd (listAppend trivU (list (tr/elemNode updNode))) trivU))
                      (kids (listAppend prefixElems
                              (listAppend trivIn
                                (cons (tr/elemToken semi1Tok)
                                  (listAppend testElems
                                    (listAppend trivSemi2
                                      (cons (tr/elemToken semi2Tok)
                                        (listAppend updElems
                                          (listAppend trivRp
                                            (cons (tr/elemToken rpTok)
                                              (listAppend trivB
                                                (list (tr/elemNode bodyNode)))))))))))))
                      (node (tr/makeNode "forStmt" (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                  (tr/ParseResult :node node :rest bodyRes.rest))
                (let [(initRes (parseCoverExpr remIn text 0 inAsync inGen))
                      (initNode initRes.node)
                      (remInit initRes.rest)
                      (spAfter (skipTrivia remInit))
                      (trivAfter (pairFirst spAfter))
                      (remAfter (pairSecond spAfter))
                      (tokAfter (if (listEmpty? remAfter) (tr/makeToken "" 0 0) (optionOr (listHead remAfter) (tr/makeToken "" 0 0))))
                      (slAfter (tokenSlice tokAfter text))]
                  (cond
                    ((= slAfter "in")
                     (let [(inTok tokAfter)
                           (tlIn (optionOr (listTail remAfter) (list)))
                           (spR (skipTrivia tlIn))
                           (trivR (pairFirst spR))
                           (remR (pairSecond spR))
                           (rRes (parseCoverExpr remR text 0 inAsync inGen))
                           (rNode rRes.node)
                           (remRRes rRes.rest)
                           (spClose (skipTrivia remRRes))
                           (trivClose (pairFirst spClose))
                           (remClose (pairSecond spClose))
                           (rpPair (expectClose remClose "rparen" (tr/nodeEnd rNode)))
                           (rpTok (pairFirst rpPair))
                           (remRp (pairSecond rpPair))
                           (spB (skipTrivia remRp))
                           (trivB (pairFirst spB))
                           (remB (pairSecond spB))
                           (bodyRes (parseStatement remB text inAsync inGen))
                           (bodyNode bodyRes.node)
                           (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                           (kids (listAppend prefixElems
                                   (listAppend trivIn
                                     (cons (tr/elemNode initNode)
                                       (listAppend trivAfter
                                         (cons (tr/elemToken inTok)
                                           (listAppend trivR
                                             (cons (tr/elemNode rNode)
                                               (listAppend trivClose
                                                 (cons (tr/elemToken rpTok)
                                                   (listAppend trivB
                                                     (list (tr/elemNode bodyNode)))))))))))))
                           (node (tr/makeNode "forInStmt" (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                       (tr/ParseResult :node node :rest bodyRes.rest)))
                    ((= slAfter "of")
                     (let [(ofTok tokAfter)
                           (tlOf (optionOr (listTail remAfter) (list)))
                           (spR (skipTrivia tlOf))
                           (trivR (pairFirst spR))
                           (remR (pairSecond spR))
                           (rRes (parseCoverExpr remR text 0 inAsync inGen))
                           (rNode rRes.node)
                           (remRRes rRes.rest)
                           (spClose (skipTrivia remRRes))
                           (trivClose (pairFirst spClose))
                           (remClose (pairSecond spClose))
                           (rpPair (expectClose remClose "rparen" (tr/nodeEnd rNode)))
                           (rpTok (pairFirst rpPair))
                           (remRp (pairSecond rpPair))
                           (spB (skipTrivia remRp))
                           (trivB (pairFirst spB))
                           (remB (pairSecond spB))
                           (bodyRes (parseStatement remB text inAsync inGen))
                           (bodyNode bodyRes.node)
                           (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                           (kids (listAppend prefixElems
                                   (listAppend trivIn
                                     (cons (tr/elemNode initNode)
                                       (listAppend trivAfter
                                         (cons (tr/elemToken ofTok)
                                           (listAppend trivR
                                             (cons (tr/elemNode rNode)
                                               (listAppend trivClose
                                                 (cons (tr/elemToken rpTok)
                                                   (listAppend trivB
                                                     (list (tr/elemNode bodyNode)))))))))))))
                           (stmtKind (if hasAwait "forAwaitOfStmt" "forOfStmt"))
                           (node (tr/makeNode stmtKind (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                       (tr/ParseResult :node node :rest bodyRes.rest)))
                    (else
                     (let [(semi1Pair (expectClose remAfter "semicolon" (tr/nodeEnd initNode)))
                           (semi1Tok (pairFirst semi1Pair))
                           (remSemi1Tok (pairSecond semi1Pair))
                           (spT (skipTrivia remSemi1Tok))
                           (trivT (pairFirst spT))
                           (remT (pairSecond spT))
                           (hasTest (and (not (listEmpty? remT)) (!= (tr/tokenKind (optionOr (listHead remT) (tr/makeToken "" 0 0))) "semicolon")))
                           (testRes (if hasTest (parseCoverExpr remT text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remT)))
                           (testNode testRes.node)
                           (remTest testRes.rest)
                           (spSemi2 (skipTrivia remTest))
                           (trivSemi2 (pairFirst spSemi2))
                           (remSemi2 (pairSecond spSemi2))
                           (semi2Pair (expectClose remSemi2 "semicolon" (tr/nodeEnd testNode)))
                           (semi2Tok (pairFirst semi2Pair))
                           (remSemi2Tok (pairSecond semi2Pair))
                           (spU (skipTrivia remSemi2Tok))
                           (trivU (pairFirst spU))
                           (remU (pairSecond spU))
                           (hasUpd (and (not (listEmpty? remU)) (!= (tr/tokenKind (optionOr (listHead remU) (tr/makeToken "" 0 0))) "rparen")))
                           (updRes (if hasUpd (parseCoverExpr remU text 0 inAsync inGen) (tr/ParseResult :node (tr/makeNode "emptyExpr" 0 0 (list)) :rest remU)))
                           (updNode updRes.node)
                           (remUpd updRes.rest)
                           (spRp (skipTrivia remUpd))
                           (trivRp (pairFirst spRp))
                           (remRp (pairSecond spRp))
                           (rpPair (expectClose remRp "rparen" (tr/nodeEnd updNode)))
                           (rpTok (pairFirst rpPair))
                           (remRpTok (pairSecond rpPair))
                           (spB (skipTrivia remRpTok))
                           (trivB (pairFirst spB))
                           (remB (pairSecond spB))
                           (bodyRes (parseStatement remB text inAsync inGen))
                           (bodyNode bodyRes.node)
                           (prefixElems (if hasAwait (cons (tr/elemToken forTok) (listAppend triv1 (cons (tr/elemToken (optionOr awaitTokOpt forTok)) (listAppend triv2 (list (tr/elemToken lpTok)))))) (cons (tr/elemToken forTok) (listAppend triv1 (list (tr/elemToken lpTok))))))
                           (testElems (if hasTest (listAppend trivT (list (tr/elemNode testNode))) trivT))
                           (updElems (if hasUpd (listAppend trivU (list (tr/elemNode updNode))) trivU))
                           (kids (listAppend prefixElems
                                   (listAppend trivIn
                                     (cons (tr/elemNode initNode)
                                       (listAppend trivAfter
                                         (cons (tr/elemToken semi1Tok)
                                           (listAppend testElems
                                             (listAppend trivSemi2
                                               (cons (tr/elemToken semi2Tok)
                                                 (listAppend updElems
                                                   (listAppend trivRp
                                                     (cons (tr/elemToken rpTok)
                                                       (listAppend trivB
                                                         (list (tr/elemNode bodyNode)))))))))))))))
                           (node (tr/makeNode "forStmt" (tr/tokenStart forTok) (tr/nodeEnd bodyNode) kids))]
                       (tr/ParseResult :node node :rest bodyRes.rest))))))))))))
fn parseReturnStmt returnTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp (skipTrivia tl))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (or (listEmpty? rem)
        (or (hasNewlineElements triv text)
        (or (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon")
            (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "rbrace"))))
      (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon"))
        (let [(semiTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (kids (cons (tr/elemToken returnTok) (listAppend triv (list (tr/elemToken semiTok)))))
              (endPos (tr/tokenEnd semiTok))
              (node (tr/makeNode "returnStmt" (tr/tokenStart returnTok) endPos kids))]
          (tr/ParseResult :node node :rest (optionOr (listTail rem) (list))))
        (let [(kids (list (tr/elemToken returnTok)))
              (endPos (tr/tokenEnd returnTok))
              (node (tr/makeNode "returnStmt" (tr/tokenStart returnTok) endPos kids))]
          (tr/ParseResult :node node :rest tl)))
      (let [(exprRes (parseCoverExpr rem text 0 inAsync inGen))
            (exprNode exprRes.node)
            (remAfter exprRes.rest)
            (kids (cons (tr/elemToken returnTok) (listAppend triv (list (tr/elemNode exprNode)))))]
        (finishStatementWithSemi kids (tr/tokenStart returnTok) "returnStmt" remAfter text))))
fn parseThrowStmt throwTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp (skipTrivia tl))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (or (listEmpty? rem) (hasNewlineElements triv text))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart throwTok) (tr/tokenEnd throwTok) (list (tr/elemToken throwTok))) :rest tl)
      (let [(exprRes (parseCoverExpr rem text 0 inAsync inGen))
            (exprNode exprRes.node)
            (remAfter exprRes.rest)
            (kids (cons (tr/elemToken throwTok) (listAppend triv (list (tr/elemNode exprNode)))))]
        (finishStatementWithSemi kids (tr/tokenStart throwTok) "throwStmt" remAfter text))))
fn parseBreakStmt breakTok: tr/Token tl: (List tr/Token) text: String -> tr/ParseResult
  (let [(sp (skipTrivia tl))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (or (listEmpty? rem)
        (or (hasNewlineElements triv text)
        (or (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon")
            (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "rbrace"))))
      (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon"))
        (let [(semiTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (kids (cons (tr/elemToken breakTok) (listAppend triv (list (tr/elemToken semiTok)))))
              (endPos (tr/tokenEnd semiTok))
              (node (tr/makeNode "breakStmt" (tr/tokenStart breakTok) endPos kids))]
          (tr/ParseResult :node node :rest (optionOr (listTail rem) (list))))
        (let [(kids (list (tr/elemToken breakTok)))
              (endPos (tr/tokenEnd breakTok))
              (node (tr/makeNode "breakStmt" (tr/tokenStart breakTok) endPos kids))]
          (tr/ParseResult :node node :rest tl)))
      (let [(labelTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind labelTok))]
        (if (!= k "ident")
          (finishStatementWithSemi (list (tr/elemToken breakTok)) (tr/tokenStart breakTok) "breakStmt" tl text)
          (let [(kids (cons (tr/elemToken breakTok) (listAppend triv (list (tr/elemToken labelTok)))))
                (remLabel (optionOr (listTail rem) (list)))]
            (finishStatementWithSemi kids (tr/tokenStart breakTok) "breakStmt" remLabel text))))))
fn parseContinueStmt contTok: tr/Token tl: (List tr/Token) text: String -> tr/ParseResult
  (let [(sp (skipTrivia tl))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (or (listEmpty? rem)
        (or (hasNewlineElements triv text)
        (or (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon")
            (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "rbrace"))))
      (if (and (not (listEmpty? rem)) (= (tr/tokenKind (optionOr (listHead rem) (tr/makeToken "" 0 0))) "semicolon"))
        (let [(semiTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
              (kids (cons (tr/elemToken contTok) (listAppend triv (list (tr/elemToken semiTok)))))
              (endPos (tr/tokenEnd semiTok))
              (node (tr/makeNode "continueStmt" (tr/tokenStart contTok) endPos kids))]
          (tr/ParseResult :node node :rest (optionOr (listTail rem) (list))))
        (let [(kids (list (tr/elemToken contTok)))
              (endPos (tr/tokenEnd contTok))
              (node (tr/makeNode "continueStmt" (tr/tokenStart contTok) endPos kids))]
          (tr/ParseResult :node node :rest tl)))
      (let [(labelTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind labelTok))]
        (if (!= k "ident")
          (finishStatementWithSemi (list (tr/elemToken contTok)) (tr/tokenStart contTok) "continueStmt" tl text)
          (let [(kids (cons (tr/elemToken contTok) (listAppend triv (list (tr/elemToken labelTok)))))
                (remLabel (optionOr (listTail rem) (list)))]
            (finishStatementWithSemi kids (tr/tokenStart contTok) "continueStmt" remLabel text))))))
fn parseDebuggerStmt debugTok: tr/Token tl: (List tr/Token) text: String -> tr/ParseResult
  (finishStatementWithSemi (list (tr/elemToken debugTok)) (tr/tokenStart debugTok) "debuggerStmt" tl text)
fn parseEmptyStmt semiTok: tr/Token tl: (List tr/Token) -> tr/ParseResult
  (tr/ParseResult :node (tr/makeNode "emptyStmt" (tr/tokenStart semiTok) (tr/tokenEnd semiTok) (list (tr/elemToken semiTok))) :rest tl)
fn parseSwitchCasesLoop toks: (List tr/Token) text: String inAsync: Bool inGen: Bool acc: (List tr/TreeElement) -> StmtsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (StmtsResult :elements acc :rest toks)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))]
        (cond
          ((= k "rbrace")
           (StmtsResult :elements acc :rest toks))
          ((= sl "case")
           (let [(caseTok hd)
                 (tlCase (optionOr (listTail rem) (list)))
                 (spC (skipTrivia tlCase))
                 (trivC (pairFirst spC))
                 (remC (pairSecond spC))
                 (exprRes (parseCoverExpr remC text 0 inAsync inGen))
                 (exprNode exprRes.node)
                 (remExpr exprRes.rest)
                 (spColon (skipTrivia remExpr))
                 (trivColon (pairFirst spColon))
                 (remColon (pairSecond spColon))
                 (colonPair (expectClose remColon "colon" (tr/nodeEnd exprNode)))
                 (colonTok (pairFirst colonPair))
                 (remAfterColon (pairSecond colonPair))
                 (caseHeadKids (cons (tr/elemToken caseTok)
                                 (listAppend trivC
                                   (cons (tr/elemNode exprNode)
                                     (listAppend trivColon
                                       (list (tr/elemToken colonTok)))))))
                 (bodyRes (parseCaseBodyStmts remAfterColon text inAsync inGen (list)))
                 (allCaseKids (listAppend caseHeadKids bodyRes.elements))
                 (lastCaseElem (optionOr (listLast allCaseKids) (tr/elemToken colonTok)))
                 (endCasePos (tr/elementEnd lastCaseElem))
                 (caseNode (tr/makeNode "switchCase" (tr/tokenStart caseTok) endCasePos allCaseKids))
                 (newAcc (listAppend acc (listAppend triv (list (tr/elemNode caseNode)))))]
             (parseSwitchCasesLoop bodyRes.rest text inAsync inGen newAcc)))
          ((= sl "default")
           (let [(defTok hd)
                 (tlDef (optionOr (listTail rem) (list)))
                 (spColon (skipTrivia tlDef))
                 (trivColon (pairFirst spColon))
                 (remColon (pairSecond spColon))
                 (colonPair (expectClose remColon "colon" (tr/tokenEnd defTok)))
                 (colonTok (pairFirst colonPair))
                 (remAfterColon (pairSecond colonPair))
                 (defHeadKids (cons (tr/elemToken defTok)
                                (listAppend trivColon
                                  (list (tr/elemToken colonTok)))))
                 (bodyRes (parseCaseBodyStmts remAfterColon text inAsync inGen (list)))
                 (allDefKids (listAppend defHeadKids bodyRes.elements))
                 (lastDefElem (optionOr (listLast allDefKids) (tr/elemToken colonTok)))
                 (endDefPos (tr/elementEnd lastDefElem))
                 (defNode (tr/makeNode "switchDefault" (tr/tokenStart defTok) endDefPos allDefKids))
                 (newAcc (listAppend acc (listAppend triv (list (tr/elemNode defNode)))))]
             (parseSwitchCasesLoop bodyRes.rest text inAsync inGen newAcc)))
          (else
           (StmtsResult :elements acc :rest toks))))))
fn parseCaseBodyStmts toks: (List tr/Token) text: String inAsync: Bool inGen: Bool acc: (List tr/TreeElement) -> StmtsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (StmtsResult :elements (listAppend acc triv) :rest rem)
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind hd))
            (sl (tokenSlice hd text))]
        (if (or (= k "rbrace") (or (= sl "case") (= sl "default")))
          (StmtsResult :elements acc :rest toks)
          (let [(accWithTriv (listAppend acc triv))
                (stmtRes (parseStatement rem text inAsync inGen))
                (stmtNode stmtRes.node)
                (remToks stmtRes.rest)]
            (if (or (tr/isErrorNode stmtNode) (= (listLength remToks) (listLength rem)))
              (let [(advToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))]
                (StmtsResult :elements (listAppend accWithTriv (list (tr/elemNode stmtNode))) :rest advToks))
              (parseCaseBodyStmts remToks text inAsync inGen (listAppend accWithTriv (list (tr/elemNode stmtNode))))))))))
fn parseSwitchStmt switchTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (or (listEmpty? rem1) (!= (tr/tokenKind (optionOr (listHead rem1) (tr/makeToken "" 0 0))) "lparen"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart switchTok) (tr/tokenEnd switchTok) (list (tr/elemToken switchTok))) :rest tl)
      (let [(lpTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem1) (list)))
            (sp2 (skipTrivia tlLp))
            (triv2 (pairFirst sp2))
            (rem2 (pairSecond sp2))
            (exprRes (parseCoverExpr rem2 text 0 inAsync inGen))
            (exprNode exprRes.node)
            (remExpr exprRes.rest)
            (sp3 (skipTrivia remExpr))
            (triv3 (pairFirst sp3))
            (rem3 (pairSecond sp3))
            (rpPair (expectClose rem3 "rparen" (tr/nodeEnd exprNode)))
            (rpTok (pairFirst rpPair))
            (remRp (pairSecond rpPair))
            (sp4 (skipTrivia remRp))
            (triv4 (pairFirst sp4))
            (rem4 (pairSecond sp4))]
        (if (or (listEmpty? rem4) (!= (tr/tokenKind (optionOr (listHead rem4) (tr/makeToken "" 0 0))) "lbrace"))
          (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart switchTok) (tr/tokenEnd rpTok) (list (tr/elemToken switchTok))) :rest rem4)
          (let [(lbTok (optionOr (listHead rem4) (tr/makeToken "" 0 0)))
                (tlLb (optionOr (listTail rem4) (list)))
                (casesRes (parseSwitchCasesLoop tlLb text inAsync inGen (list)))
                (casesElems casesRes.elements)
                (remCases casesRes.rest)
                (spRb (skipTrivia remCases))
                (trivRb (pairFirst spRb))
                (remRb (pairSecond spRb))
                (rbPair (expectClose remRb "rbrace" (tr/tokenEnd lbTok)))
                (rbTok (pairFirst rbPair))
                (remRbTok (pairSecond rbPair))
                (kids (cons (tr/elemToken switchTok)
                        (listAppend triv1
                          (cons (tr/elemToken lpTok)
                            (listAppend triv2
                              (cons (tr/elemNode exprNode)
                                (listAppend triv3
                                  (cons (tr/elemToken rpTok)
                                    (listAppend triv4
                                      (cons (tr/elemToken lbTok)
                                        (listAppend casesElems
                                          (listAppend trivRb
                                            (list (tr/elemToken rbTok))))))))))))))
                (endPos (tr/tokenEnd rbTok))
                (node (tr/makeNode "switchStmt" (tr/tokenStart switchTok) endPos kids))]
            (tr/ParseResult :node node :rest remRbTok))))))
fn parseTryStmt tryTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))
        (blockRes (parseBlock rem1 text inAsync inGen))
        (blockNode blockRes.node)
        (remBlock blockRes.rest)
        (spCatch (skipTrivia remBlock))
        (trivCatch (pairFirst spCatch))
        (remCatch (pairSecond spCatch))
        (hasCatch (and (not (listEmpty? remCatch)) (= (tokenSlice (optionOr (listHead remCatch) (tr/makeToken "" 0 0)) text) "catch")))]
    (let [(catchRes (if hasCatch
                      (let [(catchTok (optionOr (listHead remCatch) (tr/makeToken "" 0 0)))
                            (tlCatch (optionOr (listTail remCatch) (list)))
                            (spCP (skipTrivia tlCatch))
                            (trivCP (pairFirst spCP))
                            (remCP (pairSecond spCP))]
                        (if (and (not (listEmpty? remCP)) (= (tr/tokenKind (optionOr (listHead remCP) (tr/makeToken "" 0 0))) "lparen"))
                          (let [(lpTok (optionOr (listHead remCP) (tr/makeToken "" 0 0)))
                                (tlLp (optionOr (listTail remCP) (list)))
                                (spP (skipTrivia tlLp))
                                (trivP (pairFirst spP))
                                (remP (pairSecond spP))
                                (patRes (parseCoverExpr remP text 0 inAsync inGen))
                                (patNode patRes.node)
                                (refined (resultOr (cv/refineToPattern patNode) patNode))
                                (remPat patRes.rest)
                                (spRp (skipTrivia remPat))
                                (trivRp (pairFirst spRp))
                                (remRp (pairSecond spRp))
                                (rpPair (expectClose remRp "rparen" (tr/nodeEnd patNode)))
                                (rpTok (pairFirst rpPair))
                                (remRpTok (pairSecond rpPair))
                                (spCB (skipTrivia remRpTok))
                                (trivCB (pairFirst spCB))
                                (remCB (pairSecond spCB))
                                (cBlockRes (parseBlock remCB text inAsync inGen))
                                (cBlockNode cBlockRes.node)
                                (cKids (cons (tr/elemToken catchTok)
                                         (listAppend trivCP
                                           (cons (tr/elemToken lpTok)
                                             (listAppend trivP
                                               (cons (tr/elemNode refined)
                                                 (listAppend trivRp
                                                   (cons (tr/elemToken rpTok)
                                                     (listAppend trivCB
                                                       (list (tr/elemNode cBlockNode)))))))))))
                                (cNode (tr/makeNode "catchClause" (tr/tokenStart catchTok) (tr/nodeEnd cBlockNode) cKids))]
                            (tr/ParseResult :node cNode :rest cBlockRes.rest))
                          (let [(cBlockRes (parseBlock remCP text inAsync inGen))
                                (cBlockNode cBlockRes.node)
                                (cKids (cons (tr/elemToken catchTok) (listAppend trivCP (list (tr/elemNode cBlockNode)))))
                                (cNode (tr/makeNode "catchClause" (tr/tokenStart catchTok) (tr/nodeEnd cBlockNode) cKids))]
                            (tr/ParseResult :node cNode :rest cBlockRes.rest))))
                      (tr/ParseResult :node (tr/makeNode "emptyCatch" 0 0 (list)) :rest remBlock)))
          (catchNode catchRes.node)
          (remAfterCatch catchRes.rest)
          (spFin (skipTrivia remAfterCatch))
          (trivFin (pairFirst spFin))
          (remFin (pairSecond spFin))
          (hasFinally (and (not (listEmpty? remFin)) (= (tokenSlice (optionOr (listHead remFin) (tr/makeToken "" 0 0)) text) "finally")))]
      (let [(finRes (if hasFinally
                      (let [(finTok (optionOr (listHead remFin) (tr/makeToken "" 0 0)))
                            (tlFin (optionOr (listTail remFin) (list)))
                            (spFB (skipTrivia tlFin))
                            (trivFB (pairFirst spFB))
                            (remFB (pairSecond spFB))
                            (fBlockRes (parseBlock remFB text inAsync inGen))
                            (fBlockNode fBlockRes.node)
                            (fKids (cons (tr/elemToken finTok) (listAppend trivFB (list (tr/elemNode fBlockNode)))))
                            (fNode (tr/makeNode "finallyClause" (tr/tokenStart finTok) (tr/nodeEnd fBlockNode) fKids))]
                        (tr/ParseResult :node fNode :rest fBlockRes.rest))
                      (tr/ParseResult :node (tr/makeNode "emptyFinally" 0 0 (list)) :rest remAfterCatch)))
            (finNode finRes.node)
            (remAfterFin finRes.rest)
            (kids1 (cons (tr/elemToken tryTok) (listAppend triv1 (list (tr/elemNode blockNode)))))
            (kids2 (if hasCatch (listAppend kids1 (listAppend trivCatch (list (tr/elemNode catchNode)))) kids1))
            (allKids (if hasFinally (listAppend kids2 (listAppend trivFin (list (tr/elemNode finNode)))) kids2))
            (lastElem (optionOr (listLast allKids) (tr/elemToken tryTok)))
            (endPos (tr/elementEnd lastElem))
            (node (tr/makeNode "tryStmt" (tr/tokenStart tryTok) endPos allKids))]
        (tr/ParseResult :node node :rest remAfterFin))))
fn parseWithStmt withTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (or (listEmpty? rem1) (!= (tr/tokenKind (optionOr (listHead rem1) (tr/makeToken "" 0 0))) "lparen"))
      (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart withTok) (tr/tokenEnd withTok) (list (tr/elemToken withTok))) :rest tl)
      (let [(lpTok (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tlLp (optionOr (listTail rem1) (list)))
            (sp2 (skipTrivia tlLp))
            (triv2 (pairFirst sp2))
            (rem2 (pairSecond sp2))
            (exprRes (parseCoverExpr rem2 text 0 inAsync inGen))
            (exprNode exprRes.node)
            (remExpr exprRes.rest)
            (sp3 (skipTrivia remExpr))
            (triv3 (pairFirst sp3))
            (rem3 (pairSecond sp3))
            (rpPair (expectClose rem3 "rparen" (tr/nodeEnd exprNode)))
            (rpTok (pairFirst rpPair))
            (remRp (pairSecond rpPair))
            (sp4 (skipTrivia remRp))
            (triv4 (pairFirst sp4))
            (rem4 (pairSecond sp4))
            (bodyRes (parseStatement rem4 text inAsync inGen))
            (bodyNode bodyRes.node)
            (kids (cons (tr/elemToken withTok)
                    (listAppend triv1
                      (cons (tr/elemToken lpTok)
                        (listAppend triv2
                          (cons (tr/elemNode exprNode)
                            (listAppend triv3
                              (cons (tr/elemToken rpTok)
                                (listAppend triv4
                                  (list (tr/elemNode bodyNode)))))))))))
            (endPos (tr/nodeEnd bodyNode))
            (node (tr/makeNode "withStmt" (tr/tokenStart withTok) endPos kids))]
        (tr/ParseResult :node node :rest bodyRes.rest))))
fn parseParametersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> StmtsResult
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (let [(lastElem (optionOr (listLast acc) (tr/elemToken (tr/makeToken "" 0 0))))
            (endPos (tr/elementEnd lastElem))
            (errTok (tr/makeToken "error" endPos endPos))]
        (StmtsResult :elements (listAppend acc (list (tr/elemToken errTok))) :rest toks))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rparen")
          (StmtsResult :elements (listAppend acc (listAppend triv (list (tr/elemToken hd)))) :rest tl)
          (if (= k "comma")
            (parseParametersLoop tl text (listAppend acc (listAppend triv (list (tr/elemToken hd)))))
            (if (= k "ellipsis")
              (let [(accWithEll (listAppend acc (listAppend triv (list (tr/elemToken hd)))))
                    (sp2 (skipTrivia tl))
                    (triv2 (pairFirst sp2))
                    (rem2 (pairSecond sp2))
                    (patRes (parseCoverExpr rem2 text 1 false false))
                    (patNode patRes.node)
                    (refined (resultOr (cv/refineToPattern patNode) patNode))
                    (restKids (cons (tr/elemToken hd) (listAppend triv2 (list (tr/elemNode refined)))))
                    (restNode (tr/makeNode "restElement" (tr/tokenStart hd) (tr/nodeEnd refined) restKids))
                    (newAcc (listAppend acc (listAppend triv (list (tr/elemNode restNode)))))]
                (parseParametersLoop patRes.rest text newAcc))
              (let [(paramRes (parseDeclarator rem text false false))
                    (paramNode paramRes.node)
                    (newAcc (listAppend acc (listAppend triv (list (tr/elemNode paramNode)))))]
                (parseParametersLoop paramRes.rest text newAcc))))))))
fn parseParameters toks: (List tr/Token) text: String -> tr/ParseResult
  (if (listEmpty? toks)
    (tr/ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (!= k "lparen")
        (tr/ParseResult :node (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd hd) (list (tr/elemToken hd))) :rest tl)
        (let [(res (parseParametersLoop tl text (list (tr/elemToken hd))))
              (elems res.elements)
              (rem res.rest)
              (lastElem (optionOr (listLast elems) (tr/elemToken hd)))
              (endPos (tr/elementEnd lastElem))
              (node (tr/makeNode "parameters" (tr/tokenStart hd) endPos elems))]
          (tr/ParseResult :node node :rest rem)))))
fn parseFunctionDecl prefixElems: (List tr/TreeElement) fnTok: tr/Token tl: (List tr/Token) text: String isAsync: Bool -> tr/ParseResult
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
        (trivLP (pairFirst spLP))
        (remLP (pairSecond spLP))
        (paramsRes (parseParameters remLP text))
        (paramsNode paramsRes.node)
        (remParams paramsRes.rest)
        (spBody (skipTrivia remParams))
        (trivBody (pairFirst spBody))
        (remBody (pairSecond spBody))
        (bodyRes (parseBlock remBody text isAsync isGen))
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
        (declKind (cond
                    ((and isAsync isGen) "asyncGeneratorDecl")
                    (isAsync "asyncFunctionDecl")
                    (isGen "generatorDecl")
                    (else "functionDecl")))
        (node (tr/makeNode declKind startPos endPos allKids))]
    (tr/ParseResult :node node :rest bodyRes.rest))
fn parseClassDecl classTok: tr/Token tl: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(exprRes (parseCoverExpr (cons classTok tl) text 0 inAsync inGen))
        (exprNode exprRes.node)
        (node (tr/makeNode "classDecl" (tr/nodeStart exprNode) (tr/nodeEnd exprNode) (tr/nodeChildren exprNode)))]
    (tr/ParseResult :node node :rest exprRes.rest))
fn parseLabeledStmt labelTok: tr/Token colonTok: tr/Token triv1: (List tr/TreeElement) triv2: (List tr/TreeElement) rem: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(stmtRes (parseStatement rem text inAsync inGen))
        (stmtNode stmtRes.node)
        (kids (cons (tr/elemToken labelTok)
                (listAppend triv1
                  (cons (tr/elemToken colonTok)
                    (listAppend triv2
                      (list (tr/elemNode stmtNode)))))))
        (endPos (tr/nodeEnd stmtNode))
        (node (tr/makeNode "labeledStmt" (tr/tokenStart labelTok) endPos kids))]
    (tr/ParseResult :node node :rest stmtRes.rest))
fn parseExprStmt toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (let [(exprRes (parseCoverExpr toks text 0 inAsync inGen))
        (exprNode exprRes.node)
        (rem exprRes.rest)]
    (finishStatementWithSemi (list (tr/elemNode exprNode)) (tr/nodeStart exprNode) "exprStmt" rem text))
fn parseStatement toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> tr/ParseResult
  (if (listEmpty? toks)
    (tr/ParseResult :node (tr/makeErrorNode 0 0 (list)) :rest toks)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (sl (tokenSlice hd text))]
      (cond
        ((= k "semicolon")
         (parseEmptyStmt hd tl))
        ((= k "lbrace")
         (parseBlock toks text inAsync inGen))
        ((or (= sl "var") (or (= sl "let") (= sl "const")))
         (parseVarStmt hd tl text inAsync inGen))
        ((= sl "if")
         (parseIfStmt hd tl text inAsync inGen))
        ((= sl "while")
         (parseWhileStmt hd tl text inAsync inGen))
        ((= sl "do")
         (parseDoWhileStmt hd tl text inAsync inGen))
        ((= sl "for")
         (parseForStmt hd tl text inAsync inGen))
        ((= sl "return")
         (parseReturnStmt hd tl text inAsync inGen))
        ((= sl "throw")
         (parseThrowStmt hd tl text inAsync inGen))
        ((= sl "break")
         (parseBreakStmt hd tl text))
        ((= sl "continue")
         (parseContinueStmt hd tl text))
        ((= sl "debugger")
         (parseDebuggerStmt hd tl text))
        ((= sl "switch")
         (parseSwitchStmt hd tl text inAsync inGen))
        ((= sl "try")
         (parseTryStmt hd tl text inAsync inGen))
        ((= sl "with")
         (parseWithStmt hd tl text inAsync inGen))
        ((= sl "function")
         (parseFunctionDecl (list) hd tl text false))
        ((= sl "class")
         (parseClassDecl hd tl text inAsync inGen))
        ((and (= sl "async") (not (listEmpty? tl)))
         (let [(spA (skipTrivia tl))
               (trivA (pairFirst spA))
               (remA (pairSecond spA))]
           (if (and (not (hasNewlineElements trivA text))
                    (and (not (listEmpty? remA))
                         (= (tokenSlice (optionOr (listHead remA) (tr/makeToken "" 0 0)) text) "function")))
             (let [(fnTok (optionOr (listHead remA) (tr/makeToken "" 0 0)))
                   (tlFn (optionOr (listTail remA) (list)))
                   (pref (cons (tr/elemToken hd) trivA))]
               (parseFunctionDecl pref fnTok tlFn text true))
             (parseExprStmt toks text inAsync inGen))))
        ((= k "ident")
         (let [(spColon (skipTrivia tl))
               (trivColon (pairFirst spColon))
               (remColon (pairSecond spColon))]
           (if (and (not (listEmpty? remColon)) (= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon"))
             (let [(colonTok (optionOr (listHead remColon) (tr/makeToken "" 0 0)))
                   (tlColon (optionOr (listTail remColon) (list)))
                   (spAfterColon (skipTrivia tlColon))
                   (trivAfterColon (pairFirst spAfterColon))
                   (remAfterColon (pairSecond spAfterColon))]
               (parseLabeledStmt hd colonTok trivColon trivAfterColon remAfterColon text inAsync inGen))
             (parseExprStmt toks text inAsync inGen))))
        (else
         (parseExprStmt toks text inAsync inGen)))))
fn parseStatementsLoop toks: (List tr/Token) text: String inAsync: Bool inGen: Bool acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (listAppend acc triv)
      (let [(accWithTriv (listAppend acc triv))
            (stmtRes (parseStatement rem text inAsync inGen))
            (stmtNode stmtRes.node)
            (remToks stmtRes.rest)]
        (if (or (tr/isErrorNode stmtNode) (= (listLength remToks) (listLength rem)))
          (let [(advToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))
                (errElem (if (tr/isErrorNode stmtNode) (tr/elemNode stmtNode) (tr/elemToken (optionOr (listHead rem) (tr/makeToken "" 0 0)))))]
            (parseStatementsLoop advToks text inAsync inGen (listAppend accWithTriv (list errElem))))
          (parseStatementsLoop remToks text inAsync inGen (listAppend accWithTriv (list (tr/elemNode stmtNode))))))))
fn parseStatements toks: (List tr/Token) text: String inAsync: Bool inGen: Bool -> (List tr/TreeElement)
  (parseStatementsLoop toks text inAsync inGen (list))
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
         (if (tr/isErrorNode node)
           (some (tr/nodeStart node))
           (mt (firstErrorOffset (tr/nodeChildren node))
             ((some off) (some off))
             ((none) (firstErrorOffset tl))))))))
fn parseScript text: String -> (Result tr/Node String)
  (let [(tokens (lx/tokenize text))
        (elems (parseStatements tokens text false false))
        (root (tr/makeNode "script" 0 (stringLength text) elems))]
    (mt (firstErrorOffset elems)
      ((some off)
       (err (str "Parse error at offset " (stringFromInt64 off))))
      ((none)
       (ok root))))
fn parse text: String -> (Result tr/Node String)
  (parseScript text)
fn isStatementNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "exprStmt")
    (or (= k "varDecl")
    (or (= k "letDecl")
    (or (= k "constDecl")
    (or (= k "block")
    (or (= k "emptyStmt")
    (or (= k "ifStmt")
    (or (= k "whileStmt")
    (or (= k "doWhileStmt")
    (or (= k "forStmt")
    (or (= k "forInStmt")
    (or (= k "forOfStmt")
    (or (= k "forAwaitOfStmt")
    (or (= k "returnStmt")
    (or (= k "throwStmt")
    (or (= k "breakStmt")
    (or (= k "continueStmt")
    (or (= k "switchStmt")
    (or (= k "tryStmt")
    (or (= k "withStmt")
    (or (= k "debuggerStmt")
    (or (= k "labeledStmt")
    (or (= k "functionDecl")
    (or (= k "generatorDecl")
    (or (= k "asyncFunctionDecl")
    (or (= k "asyncGeneratorDecl")
        (= k "classDecl"))))))))))))))))))))))))))))
fn statementKind node: tr/Node -> String
  (tr/nodeKind node)
fn findChildNodes elems: (List tr/TreeElement) -> (List tr/Node)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (findChildNodes tl))
        ((tr/elemNode node) (cons node (findChildNodes tl))))))
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
fn formatStmtsSExpr nodes: (List tr/Node) text: String -> String
  (if (listEmpty? nodes)
    ""
    (let [(hd (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))))
          (tl (optionOr (listTail nodes) (list)))
          (s (stmtToSExpr hd text))]
      (if (listEmpty? tl)
        s
        (str s " " (formatStmtsSExpr tl text)))))
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

fn stmtToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))
        (kids (tr/nodeChildren node))
        (childNodes (findChildNodes kids))]
    (cond
      ((= k "parameters")
       (let [(childNodes (findChildNodes kids))
             (paramStrs (formatStmtsSExpr childNodes text))]
         (if (stringEmpty? paramStrs)
           "(params)"
           (str "(params " paramStrs ")"))))
      ((= k "script")
       (let [(inner (formatStmtsSExpr childNodes text))]
         (if (stringEmpty? inner) "(script)" (str "(script " inner ")"))))
      ((= k "emptyStmt")
       "(;)")
      ((= k "block")
       (let [(inner (formatStmtsSExpr childNodes text))]
         (if (stringEmpty? inner) "(block)" (str "(block " inner ")"))))
      ((or (= k "varDecl") (or (= k "letDecl") (= k "constDecl")))
       (let [(prefix (cond ((= k "varDecl") "var") ((= k "letDecl") "let") (else "const")))
             (inner (formatStmtsSExpr childNodes text))]
         (if (stringEmpty? inner) (str "(" prefix ")") (str "(" prefix " " inner ")"))))
      ((= k "declarator")
       (let [(toks (findNonTriviaTokens kids))]
         (if (= (listLength childNodes) 2)
           (let [(pat (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                 (init (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
             (str "(= " (stmtToSExpr pat text) " " (stmtToSExpr init text) ")"))
           (if (= (listLength childNodes) 1)
             (let [(firstNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                   (firstTok (if (listEmpty? toks) (tr/makeToken "" 0 0) (optionOr (listHead toks) (tr/makeToken "" 0 0))))]
               (if (and (>= (listLength toks) 2) (= (tr/tokenKind (optionOr (listGet toks 1) (tr/makeToken "" 0 0))) "assign"))
                 (str "(= " (tokenSlice firstTok text) " " (stmtToSExpr firstNode text) ")")
                 (stmtToSExpr firstNode text)))
             (if (listEmpty? toks) "" (tokenSlice (optionOr (listHead toks) (tr/makeToken "" 0 0)) text))))))
      ((= k "exprStmt")
       (if (listEmpty? childNodes)
         "(expr)"
         (let [(firstNode (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
           (str "(expr " (stmtToSExpr firstNode text) ")"))))
      ((= k "ifStmt")
       (let [(nKids (listLength childNodes))]
         (if (>= nKids 3)
           (let [(c (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                 (consNode (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))
                 (altNode (optionOr (listGet childNodes 2) (tr/makeNode "" 0 0 (list))))]
             (str "(if " (cv/coverToSExpr c text) " " (stmtToSExpr consNode text) " " (stmtToSExpr altNode text) ")"))
           (if (= nKids 2)
             (let [(c (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                   (consNode (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
               (str "(if " (cv/coverToSExpr c text) " " (stmtToSExpr consNode text) ")"))
             "(if)"))))
      ((= k "whileStmt")
       (if (>= (listLength childNodes) 2)
         (let [(c (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (b (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
           (str "(while " (cv/coverToSExpr c text) " " (stmtToSExpr b text) ")"))
         "(while)"))
      ((= k "doWhileStmt")
       (if (>= (listLength childNodes) 2)
         (let [(b (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (c (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
           (str "(doWhile " (stmtToSExpr b text) " " (cv/coverToSExpr c text) ")"))
         "(doWhile)"))
      ((= k "forInStmt")
       (if (>= (listLength childNodes) 3)
         (let [(l (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (r (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))
               (b (optionOr (listGet childNodes 2) (tr/makeNode "" 0 0 (list))))
               (lStr (if (isStatementNode l) (stmtToSExpr l text) (cv/coverToSExpr l text)))]
           (str "(forIn " lStr " " (cv/coverToSExpr r text) " " (stmtToSExpr b text) ")"))
         "(forIn)"))
      ((or (= k "forOfStmt") (= k "forAwaitOfStmt"))
       (let [(prefix (if (= k "forAwaitOfStmt") "forAwaitOf" "forOf"))]
         (if (>= (listLength childNodes) 3)
           (let [(l (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
                 (r (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))
                 (b (optionOr (listGet childNodes 2) (tr/makeNode "" 0 0 (list))))
                 (lStr (if (isStatementNode l) (stmtToSExpr l text) (cv/coverToSExpr l text)))]
             (str "(" prefix " " lStr " " (cv/coverToSExpr r text) " " (stmtToSExpr b text) ")"))
           (str "(" prefix ")"))))
      ((= k "forStmt")
       (let [(inner (formatStmtsSExpr childNodes text))]
         (str "(for " inner ")")))
      ((= k "returnStmt")
       (if (listEmpty? childNodes)
         "(return)"
         (let [(arg (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
           (str "(return " (cv/coverToSExpr arg text) ")"))))
      ((= k "throwStmt")
       (if (listEmpty? childNodes)
         "(throw)"
         (let [(arg (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
           (str "(throw " (cv/coverToSExpr arg text) ")"))))
      ((= k "breakStmt")
       (let [(toks (findNonTriviaTokens kids))]
         (if (>= (listLength toks) 2)
           (let [(lblTok (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))]
             (if (= (tr/tokenKind lblTok) "ident")
               (str "(break " (tokenSlice lblTok text) ")")
               "(break)"))
           "(break)")))
      ((= k "continueStmt")
       (let [(toks (findNonTriviaTokens kids))]
         (if (>= (listLength toks) 2)
           (let [(lblTok (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))]
             (if (= (tr/tokenKind lblTok) "ident")
               (str "(continue " (tokenSlice lblTok text) ")")
               "(continue)"))
           "(continue)")))
      ((= k "debuggerStmt")
       "(debugger)")
      ((= k "labeledStmt")
       (let [(toks (findNonTriviaTokens kids))
             (lbl (if (listEmpty? toks) "" (tokenSlice (optionOr (listHead toks) (tr/makeToken "" 0 0)) text)))
             (subStmt (if (listEmpty? childNodes) "" (stmtToSExpr (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))) text)))]
         (str "(label " lbl " " subStmt ")")))
      ((= k "switchStmt")
       (if (listEmpty? childNodes)
         "(switch)"
         (let [(expr (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (cases (optionOr (listTail childNodes) (list)))
               (casesStr (formatStmtsSExpr cases text))]
           (if (stringEmpty? casesStr)
             (str "(switch " (cv/coverToSExpr expr text) ")")
             (str "(switch " (cv/coverToSExpr expr text) " " casesStr ")")))))
      ((= k "switchCase")
       (if (listEmpty? childNodes)
         "(case)"
         (let [(cExpr (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (stmts (optionOr (listTail childNodes) (list)))
               (stmtsStr (formatStmtsSExpr stmts text))]
           (if (stringEmpty? stmtsStr)
             (str "(case " (cv/coverToSExpr cExpr text) ")")
             (str "(case " (cv/coverToSExpr cExpr text) " " stmtsStr ")")))))
      ((= k "switchDefault")
       (let [(stmtsStr (formatStmtsSExpr childNodes text))]
         (if (stringEmpty? stmtsStr) "(default)" (str "(default " stmtsStr ")"))))
      ((= k "tryStmt")
       (let [(inner (formatStmtsSExpr childNodes text))]
         (str "(try " inner ")")))
      ((= k "catchClause")
       (if (>= (listLength childNodes) 2)
         (let [(pat (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (b (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
           (str "(catch " (cv/coverToSExpr pat text) " " (stmtToSExpr b text) ")"))
         (if (= (listLength childNodes) 1)
           (let [(b (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
             (str "(catch " (stmtToSExpr b text) ")"))
           "(catch)")))
      ((= k "finallyClause")
       (if (listEmpty? childNodes)
         "(finally)"
         (let [(b (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))]
           (str "(finally " (stmtToSExpr b text) ")"))))
      ((= k "withStmt")
       (if (>= (listLength childNodes) 2)
         (let [(e (optionOr (listHead childNodes) (tr/makeNode "" 0 0 (list))))
               (b (optionOr (listGet childNodes 1) (tr/makeNode "" 0 0 (list))))]
           (str "(with " (cv/coverToSExpr e text) " " (stmtToSExpr b text) ")"))
         "(with)"))
      ((= k "parenExpr")
       (let [(nodes (findChildNodes kids))]
         (if (listEmpty? nodes)
           ""
           (stmtToSExpr (optionOr (listHead nodes) (tr/makeNode "" 0 0 (list))) text))))
      ((= k "callExpr")
       (let [(nodes (findChildNodes kids))
             (callee (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
             (argNodes (optionOr (listTail nodes) (list)))
             (argStrs (formatStmtsSExpr argNodes text))]
         (str "(call " (stmtToSExpr callee text) (if (stringEmpty? argStrs) "" (str " " argStrs)) ")")))
      ((or (= k "functionDecl") (or (= k "generatorDecl") (or (= k "asyncFunctionDecl") (or (= k "asyncGeneratorDecl")
        (or (= k "functionExpr") (or (= k "generatorExpr") (or (= k "asyncFunctionExpr") (= k "asyncGeneratorExpr"))))))))
       (let [(prefix (cond
                       ((or (= k "asyncGeneratorDecl") (= k "asyncGeneratorExpr")) "asyncGenerator")
                       ((or (= k "asyncFunctionDecl") (= k "asyncFunctionExpr")) "asyncFunction")
                       ((or (= k "generatorDecl") (= k "generatorExpr")) "generator")
                       (else "function")))
             (toks (findNonTriviaTokens kids))
             (name (findFnName toks text))
             (body (if (listEmpty? childNodes) "" (formatStmtsSExpr childNodes text)))]
         (if (stringEmpty? name)
           (str "(" prefix " " body ")")
           (str "(" prefix " " name " " body ")"))))
      ((= k "classDecl")
       (cv/coverToSExpr (tr/makeNode "classExpr" (tr/nodeStart node) (tr/nodeEnd node) (tr/nodeChildren node)) text))
      (else
       (cv/coverToSExpr node text))))
