(module asl-syntax/js/module
  :x [parse
      parseModule
      parseModuleTokens
      parseImportDecl
      parseExportDecl
      moduleToSExpr
      isModuleNode
      moduleKind]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)
      (asl-syntax/js/stmt :a stmt)])

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
         (let [(k (tr/tokenKind tok))]
           (if (= k "newline")
             true
             (if (= k "comment")
               (let [(sl (tokenSlice tok text))]
                 (if (stringContains? sl "\n")
                   true
                   (hasNewlineElements tl text)))
               (hasNewlineElements tl text)))))
        ((tr/elemNode _)
         (hasNewlineElements tl text)))))

fn concatLists lists: (List (List tr/TreeElement)) -> (List tr/TreeElement)
  (fold (fn [(acc (List tr/TreeElement)) (l (List tr/TreeElement))] -> (List tr/TreeElement)
          (listAppend acc l))
        (list)
        lists)

fn tokElem tok: tr/Token -> (List tr/TreeElement)
  (list (tr/elemToken tok))

fn finishDeclWithSemi nodeKids: (List tr/TreeElement) startPos: Int64 nodeKind: String rem: (List tr/Token) text: String -> (Result tr/ParseResult String)
  (let [(sp (skipTrivia rem))
        (triv (pairFirst sp))
        (afterTriv (pairSecond sp))]
    (if (listEmpty? afterTriv)
      (let [(lastElem (optionOr (listLast nodeKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
            (endPos (tr/elementEnd lastElem))
            (node (tr/makeNode nodeKind startPos endPos nodeKids))]
        (ok (tr/ParseResult :node node :rest rem)))
      (let [(firstTok (optionOr (listHead afterTriv) (tr/makeToken "" 0 0)))
            (k (tr/tokenKind firstTok))]
        (cond
          ((= k "semicolon")
           (let [(allKids (listAppend nodeKids (listAppend triv (list (tr/elemToken firstTok)))))
                 (endPos (tr/tokenEnd firstTok))
                 (node (tr/makeNode nodeKind startPos endPos allKids))]
             (ok (tr/ParseResult :node node :rest (optionOr (listTail afterTriv) (list))))))
          ((or (= k "rbrace") (hasNewlineElements triv text))
           (let [(lastElem (optionOr (listLast nodeKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
                 (endPos (tr/elementEnd lastElem))
                 (node (tr/makeNode nodeKind startPos endPos nodeKids))]
             (ok (tr/ParseResult :node node :rest rem))))
          (else
           (let [(lastElem (optionOr (listLast nodeKids) (tr/elemToken (tr/makeToken "" startPos startPos))))
                 (endPos (tr/elementEnd lastElem))
                 (node (tr/makeNode nodeKind startPos endPos nodeKids))]
             (ok (tr/ParseResult :node node :rest rem))))))))

fn parseImportAttributesLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (Pair (List tr/TreeElement) (List tr/Token)) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (err (str "Parse error at offset " (stringFromInt64 (stringLength text))))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rbrace")
          (ok (pair (listAppend acc (listAppend triv (tokElem hd))) tl))
          (let [(keyElem (tr/elemToken hd))
                (spColon (skipTrivia tl))
                (trivColon (pairFirst spColon))
                (remColon (pairSecond spColon))]
            (if (or (listEmpty? remColon) (!= (tr/tokenKind (optionOr (listHead remColon) (tr/makeToken "" 0 0))) "colon"))
              (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remColon) (tr/tokenEnd hd) (tr/tokenStart (optionOr (listHead remColon) (tr/makeToken "" 0 0)))))))
              (let [(colonTok (optionOr (listHead remColon) (tr/makeToken "" 0 0)))
                    (tlColon (optionOr (listTail remColon) (list)))
                    (spVal (skipTrivia tlColon))
                    (trivVal (pairFirst spVal))
                    (remVal (pairSecond spVal))]
                (if (listEmpty? remVal)
                  (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd colonTok))))
                  (let [(valTok (optionOr (listHead remVal) (tr/makeToken "" 0 0)))
                        (tlVal (optionOr (listTail remVal) (list)))]
                    (if (!= (tr/tokenKind valTok) "string")
                      (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart valTok))))
                      (let [(spComma (skipTrivia tlVal))
                            (trivComma (pairFirst spComma))
                            (remComma (pairSecond spComma))
                            (entryKids (concatLists (list triv (list keyElem) trivColon (tokElem colonTok) trivVal (tokElem valTok))))]
                        (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
                          (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                                (tlComma (optionOr (listTail remComma) (list)))
                                (allEntry (listAppend entryKids (listAppend trivComma (tokElem commaTok))))]
                            (parseImportAttributesLoop tlComma text (listAppend acc allEntry)))
                          (parseImportAttributesLoop remComma text (listAppend acc (listAppend entryKids trivComma)))))))))))))))

fn parseImportAttributes toks: (List tr/Token) text: String -> (Result (Pair (List tr/TreeElement) (List tr/Token)) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ok (pair (list) toks))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (sl (tokenSlice hd text))]
        (if (or (= sl "with") (= sl "assert"))
          (let [(tl (optionOr (listTail rem) (list)))
                (spBrace (skipTrivia tl))
                (trivBrace (pairFirst spBrace))
                (remBrace (pairSecond spBrace))]
            (if (or (listEmpty? remBrace) (!= (tr/tokenKind (optionOr (listHead remBrace) (tr/makeToken "" 0 0))) "lbrace"))
              (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remBrace) (tr/tokenEnd hd) (tr/tokenStart (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))))))
              (let [(braceTok (optionOr (listHead remBrace) (tr/makeToken "" 0 0)))
                    (tlBrace (optionOr (listTail remBrace) (list)))
                    (pref (concatLists (list (tokElem hd) trivBrace (tokElem braceTok))))
                    (bodyRes (parseImportAttributesLoop tlBrace text (list)))]
                (mt bodyRes
                  ((err msg) (err msg))
                  ((ok p)
                   (let [(attrKids (listAppend pref (pairFirst p)))
                         (lastElem (optionOr (listLast attrKids) (tr/elemToken braceTok)))
                         (endPos (tr/elementEnd lastElem))
                         (node (tr/makeNode "importAttributes" (tr/tokenStart hd) endPos attrKids))]
                     (ok (pair (listAppend triv (list (tr/elemNode node))) (pairSecond p)))))))))
          (ok (pair (list) toks))))))

fn parseImportSpecifiersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (Pair (List tr/TreeElement) (List tr/Token)) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (err (str "Parse error at offset " (stringFromInt64 (stringLength text))))
      (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (tl (optionOr (listTail rem) (list)))
            (k (tr/tokenKind hd))]
        (if (= k "rbrace")
          (ok (pair (listAppend acc (listAppend triv (tokElem hd))) tl))
          (if (and (= (tokenSlice hd text) "from")
                   (let [(spAfterFrom (skipTrivia tl))
                         (remAfterFrom (pairSecond spAfterFrom))]
                     (and (not (listEmpty? remAfterFrom))
                          (= (tr/tokenKind (optionOr (listHead remAfterFrom) (tr/makeToken "" 0 0))) "string"))))
            (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart hd))))
            (let [(spAs (skipTrivia tl))
                  (trivAs (pairFirst spAs))
                  (remAs (pairSecond spAs))
                  (isAs (and (not (listEmpty? remAs)) (= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as")))]
              (if isAs
                (let [(asTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                      (tlAs (optionOr (listTail remAs) (list)))
                      (spLoc (skipTrivia tlAs))
                      (trivLoc (pairFirst spLoc))
                      (remLoc (pairSecond spLoc))]
                  (if (listEmpty? remLoc)
                    (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd asTok))))
                    (let [(locTok (optionOr (listHead remLoc) (tr/makeToken "" 0 0)))
                          (locKind (tr/tokenKind locTok))]
                      (if (or (= locKind "rbrace") (or (= locKind "comma") (= locKind "semicolon")))
                        (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart locTok))))
                        (let [(tlLoc (optionOr (listTail remLoc) (list)))
                              (spComma (skipTrivia tlLoc))
                              (trivComma (pairFirst spComma))
                              (remComma (pairSecond spComma))
                              (specKids (concatLists (list triv (tokElem hd) trivAs (tokElem asTok) trivLoc (tokElem locTok))))]
                          (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
                            (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                                  (tlComma (optionOr (listTail remComma) (list)))
                                  (allSpec (listAppend specKids (listAppend trivComma (tokElem commaTok))))]
                              (parseImportSpecifiersLoop tlComma text (listAppend acc allSpec)))
                            (parseImportSpecifiersLoop remComma text (listAppend acc (listAppend specKids trivComma)))))))))
                (let [(spComma (skipTrivia tl))
                      (trivComma (pairFirst spComma))
                      (remComma (pairSecond spComma))
                      (specKids (listAppend triv (tokElem hd)))]
                  (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
                    (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                          (tlComma (optionOr (listTail remComma) (list)))
                          (allSpec (listAppend specKids (listAppend trivComma (tokElem commaTok))))]
                      (parseImportSpecifiersLoop tlComma text (listAppend acc allSpec)))
                    (parseImportSpecifiersLoop remComma text (listAppend acc (listAppend specKids trivComma))))))))))))

fn parseExportSpecifiersLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (Pair (List tr/TreeElement) (List tr/Token)) String)
  (parseImportSpecifiersLoop toks text acc)

fn parseImportDecl toks: (List tr/Token) text: String -> (Result tr/ParseResult String)
  (let [(importTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
        (tl (optionOr (listTail toks) (list)))
        (startPos (tr/tokenStart importTok))
        (sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (listEmpty? rem1)
      (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd importTok))))
      (let [(hd1 (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tl1 (optionOr (listTail rem1) (list)))
            (k1 (tr/tokenKind hd1))]
        (cond
          ((= k1 "string")
           (let [(kids (concatLists (list (tokElem importTok) triv1 (tokElem hd1))))
                 (attrRes (parseImportAttributes tl1 text))]
             (mt attrRes
               ((err msg) (err msg))
               ((ok attrPair)
                (let [(attrKids (pairFirst attrPair))
                      (remAttr (pairSecond attrPair))
                      (allKids (listAppend kids attrKids))]
                  (finishDeclWithSemi allKids startPos "importDecl" remAttr text))))))
          ((= k1 "dot")
           (let [(spMeta (skipTrivia tl1))
                 (remMeta (pairSecond spMeta))]
             (if (listEmpty? remMeta)
               (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd hd1))))
               (let [(metaTok (optionOr (listHead remMeta) (tr/makeToken "" 0 0)))]
                 (if (!= (tokenSlice metaTok text) "meta")
                   (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart metaTok))))
                   (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart hd1)))))))))
          ((= k1 "star")
           (let [(spAs (skipTrivia tl1))
                 (trivAs (pairFirst spAs))
                 (remAs (pairSecond spAs))]
             (if (or (listEmpty? remAs) (!= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as"))
               (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remAs) (tr/tokenEnd hd1) (tr/tokenStart (optionOr (listHead remAs) (tr/makeToken "" 0 0)))))))
               (let [(asTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                     (tlAs (optionOr (listTail remAs) (list)))
                     (spName (skipTrivia tlAs))
                     (trivName (pairFirst spName))
                     (remName (pairSecond spName))]
                 (if (or (listEmpty? remName) (!= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident"))
                   (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remName) (tr/tokenEnd asTok) (tr/tokenStart (optionOr (listHead remName) (tr/makeToken "" 0 0)))))))
                   (let [(nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                         (tlName (optionOr (listTail remName) (list)))
                         (spFrom (skipTrivia tlName))
                         (trivFrom (pairFirst spFrom))
                         (remFrom (pairSecond spFrom))]
                     (if (or (listEmpty? remFrom) (!= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from"))
                       (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remFrom) (tr/tokenEnd nameTok) (tr/tokenStart (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))))))
                       (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                             (tlFrom (optionOr (listTail remFrom) (list)))
                             (spSrc (skipTrivia tlFrom))
                             (trivSrc (pairFirst spSrc))
                             (remSrc (pairSecond spSrc))]
                         (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                           (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                           (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                                 (tlSrc (optionOr (listTail remSrc) (list)))
                                 (baseKids (concatLists (list (tokElem importTok) triv1 (tokElem hd1) trivAs (tokElem asTok) trivName (tokElem nameTok) trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                                 (attrRes (parseImportAttributes tlSrc text))]
                             (mt attrRes
                               ((err msg) (err msg))
                               ((ok attrPair)
                                (let [(attrKids (pairFirst attrPair))
                                      (remAttr (pairSecond attrPair))
                                      (allKids (listAppend baseKids attrKids))]
                                  (finishDeclWithSemi allKids startPos "importDecl" remAttr text))))))))))))))
          ((= k1 "lbrace")
           (let [(specRes (parseImportSpecifiersLoop tl1 text (list)))]
             (mt specRes
               ((err msg) (err msg))
               ((ok specPair)
                (let [(specKids (pairFirst specPair))
                      (remSpec (pairSecond specPair))
                      (spFrom (skipTrivia remSpec))
                      (trivFrom (pairFirst spFrom))
                      (remFrom (pairSecond spFrom))]
                  (if (or (listEmpty? remFrom) (!= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from"))
                    (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remFrom) (stringLength text) (tr/tokenStart (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))))))
                    (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                          (tlFrom (optionOr (listTail remFrom) (list)))
                          (spSrc (skipTrivia tlFrom))
                          (trivSrc (pairFirst spSrc))
                          (remSrc (pairSecond spSrc))]
                      (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                        (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                        (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                              (tlSrc (optionOr (listTail remSrc) (list)))
                              (baseKids (concatLists (list (tokElem importTok) triv1 (tokElem hd1) specKids trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                              (attrRes (parseImportAttributes tlSrc text))]
                          (mt attrRes
                            ((err msg) (err msg))
                            ((ok attrPair)
                             (let [(attrKids (pairFirst attrPair))
                                   (remAttr (pairSecond attrPair))
                                   (allKids (listAppend baseKids attrKids))]
                               (finishDeclWithSemi allKids startPos "importDecl" remAttr text)))))))))))))
          (else
           (let [(defNameTok hd1)
                 (spComma (skipTrivia tl1))
                 (trivComma (pairFirst spComma))
                 (remComma (pairSecond spComma))]
             (if (and (not (listEmpty? remComma)) (= (tr/tokenKind (optionOr (listHead remComma) (tr/makeToken "" 0 0))) "comma"))
               (let [(commaTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                     (tlComma (optionOr (listTail remComma) (list)))
                     (spNext (skipTrivia tlComma))
                     (trivNext (pairFirst spNext))
                     (remNext (pairSecond spNext))]
                 (if (listEmpty? remNext)
                   (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd commaTok))))
                   (let [(hdNext (optionOr (listHead remNext) (tr/makeToken "" 0 0)))
                         (tlNext (optionOr (listTail remNext) (list)))
                         (kNext (tr/tokenKind hdNext))]
                     (if (= kNext "star")
                       (let [(spAs (skipTrivia tlNext))
                             (trivAs (pairFirst spAs))
                             (remAs (pairSecond spAs))]
                         (if (or (listEmpty? remAs) (!= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as"))
                           (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remAs) (tr/tokenEnd hdNext) (tr/tokenStart (optionOr (listHead remAs) (tr/makeToken "" 0 0)))))))
                           (let [(asTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                                 (tlAs (optionOr (listTail remAs) (list)))
                                 (spName (skipTrivia tlAs))
                                 (trivName (pairFirst spName))
                                 (remName (pairSecond spName))]
                             (if (or (listEmpty? remName) (!= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident"))
                               (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remName) (tr/tokenEnd asTok) (tr/tokenStart (optionOr (listHead remName) (tr/makeToken "" 0 0)))))))
                               (let [(nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                                     (tlName (optionOr (listTail remName) (list)))
                                     (spFrom (skipTrivia tlName))
                                     (trivFrom (pairFirst spFrom))
                                     (remFrom (pairSecond spFrom))]
                                 (if (or (listEmpty? remFrom) (!= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from"))
                                   (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remFrom) (tr/tokenEnd nameTok) (tr/tokenStart (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))))))
                                   (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                                         (tlFrom (optionOr (listTail remFrom) (list)))
                                         (spSrc (skipTrivia tlFrom))
                                         (trivSrc (pairFirst spSrc))
                                         (remSrc (pairSecond spSrc))]
                                     (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                                       (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                                       (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                                             (tlSrc (optionOr (listTail remSrc) (list)))
                                             (baseKids (concatLists (list (tokElem importTok) triv1 (tokElem defNameTok) trivComma (tokElem commaTok) trivNext (tokElem hdNext) trivAs (tokElem asTok) trivName (tokElem nameTok) trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                                             (attrRes (parseImportAttributes tlSrc text))]
                                         (mt attrRes
                                           ((err msg) (err msg))
                                           ((ok attrPair)
                                            (let [(attrKids (pairFirst attrPair))
                                                  (remAttr (pairSecond attrPair))
                                                  (allKids (listAppend baseKids attrKids))]
                                              (finishDeclWithSemi allKids startPos "importDecl" remAttr text)))))))))))))
                       (if (= kNext "lbrace")
                         (let [(specRes (parseImportSpecifiersLoop tlNext text (list)))]
                           (mt specRes
                             ((err msg) (err msg))
                             ((ok specPair)
                              (let [(specKids (pairFirst specPair))
                                    (remSpec (pairSecond specPair))
                                    (spFrom (skipTrivia remSpec))
                                    (trivFrom (pairFirst spFrom))
                                    (remFrom (pairSecond spFrom))]
                                (if (or (listEmpty? remFrom) (!= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from"))
                                  (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remFrom) (stringLength text) (tr/tokenStart (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))))))
                                  (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                                        (tlFrom (optionOr (listTail remFrom) (list)))
                                        (spSrc (skipTrivia tlFrom))
                                        (trivSrc (pairFirst spSrc))
                                        (remSrc (pairSecond spSrc))]
                                    (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                                      (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                                      (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                                            (tlSrc (optionOr (listTail remSrc) (list)))
                                            (baseKids (concatLists (list (tokElem importTok) triv1 (tokElem defNameTok) trivComma (tokElem commaTok) trivNext (tokElem hdNext) specKids trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                                            (attrRes (parseImportAttributes tlSrc text))]
                                        (mt attrRes
                                          ((err msg) (err msg))
                                          ((ok attrPair)
                                           (let [(attrKids (pairFirst attrPair))
                                                 (remAttr (pairSecond attrPair))
                                                 (allKids (listAppend baseKids attrKids))]
                                             (finishDeclWithSemi allKids startPos "importDecl" remAttr text))))))))))))
                         (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart hdNext)))))))))
               (if (or (listEmpty? remComma) (!= (tokenSlice (optionOr (listHead remComma) (tr/makeToken "" 0 0)) text) "from"))
                 (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remComma) (tr/tokenEnd defNameTok) (tr/tokenStart (optionOr (listHead remComma) (tr/makeToken "" 0 0)))))))
                 (let [(fromTok (optionOr (listHead remComma) (tr/makeToken "" 0 0)))
                       (tlFrom (optionOr (listTail remComma) (list)))
                       (spSrc (skipTrivia tlFrom))
                       (trivSrc (pairFirst spSrc))
                       (remSrc (pairSecond spSrc))]
                   (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                     (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                     (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                           (tlSrc (optionOr (listTail remSrc) (list)))
                           (baseKids (concatLists (list (tokElem importTok) triv1 (tokElem defNameTok) trivComma (tokElem fromTok) trivSrc (tokElem srcTok))))
                           (attrRes (parseImportAttributes tlSrc text))]
                       (mt attrRes
                         ((err msg) (err msg))
                         ((ok attrPair)
                          (let [(attrKids (pairFirst attrPair))
                                (remAttr (pairSecond attrPair))
                                (allKids (listAppend baseKids attrKids))]
                            (finishDeclWithSemi allKids startPos "importDecl" remAttr text)))))))))))))))

fn isAsyncFn rem: (List tr/Token) text: String -> Bool
  (let [(hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
        (sl (tokenSlice hd text))]
    (if (= sl "async")
      (let [(sp (skipTrivia (optionOr (listTail rem) (list))))
            (rem2 (pairSecond sp))]
        (and (not (listEmpty? rem2)) (= (tokenSlice (optionOr (listHead rem2) (tr/makeToken "" 0 0)) text) "function")))
      false))

fn parseExportDecl toks: (List tr/Token) text: String -> (Result tr/ParseResult String)
  (let [(exportTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
        (tl (optionOr (listTail toks) (list)))
        (startPos (tr/tokenStart exportTok))
        (sp1 (skipTrivia tl))
        (triv1 (pairFirst sp1))
        (rem1 (pairSecond sp1))]
    (if (listEmpty? rem1)
      (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd exportTok))))
      (let [(hd1 (optionOr (listHead rem1) (tr/makeToken "" 0 0)))
            (tl1 (optionOr (listTail rem1) (list)))
            (k1 (tr/tokenKind hd1))
            (sl1 (tokenSlice hd1 text))]
        (cond
          ((= sl1 "default")
           (let [(spDef (skipTrivia tl1))
                 (trivDef (pairFirst spDef))
                 (remDef (pairSecond spDef))
                 (defKids (concatLists (list (tokElem exportTok) triv1 (tokElem hd1))))]
             (if (listEmpty? remDef)
               (err (str "Parse error at offset " (stringFromInt64 (tr/tokenEnd hd1))))
               (let [(hdDef (optionOr (listHead remDef) (tr/makeToken "" 0 0)))
                     (slDef (tokenSlice hdDef text))
                     (kDef (tr/tokenKind hdDef))]
                 (if (= kDef "semicolon")
                   (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart hdDef))))
                   (if (or (= slDef "function") (or (isAsyncFn remDef text) (= slDef "class")))
                     (let [(stmtRes (stmt/parseStatement remDef text false false))
                           (stmtNode stmtRes.node)
                           (remAfter stmtRes.rest)
                           (allKids (concatLists (list defKids trivDef (list (tr/elemNode stmtNode)))))
                           (endPos (tr/nodeEnd stmtNode))
                           (node (tr/makeNode "exportDecl" startPos endPos allKids))]
                       (ok (tr/ParseResult :node node :rest remAfter)))
                     (let [(exprRes (cv/parseCoverExprCtx remDef text 0 false false))
                           (exprNode exprRes.node)
                           (remExpr exprRes.rest)
                           (allKids (concatLists (list defKids trivDef (list (tr/elemNode exprNode)))))]
                       (finishDeclWithSemi allKids startPos "exportDecl" remExpr text))))))))
          ((= k1 "star")
           (let [(spAs (skipTrivia tl1))
                 (trivAs (pairFirst spAs))
                 (remAs (pairSecond spAs))
                 (isAs (and (not (listEmpty? remAs)) (= (tokenSlice (optionOr (listHead remAs) (tr/makeToken "" 0 0)) text) "as")))]
             (if isAs
               (let [(asTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                     (tlAs (optionOr (listTail remAs) (list)))
                     (spName (skipTrivia tlAs))
                     (trivName (pairFirst spName))
                     (remName (pairSecond spName))]
                 (if (or (listEmpty? remName) (!= (tr/tokenKind (optionOr (listHead remName) (tr/makeToken "" 0 0))) "ident"))
                   (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remName) (tr/tokenEnd asTok) (tr/tokenStart (optionOr (listHead remName) (tr/makeToken "" 0 0)))))))
                   (let [(nameTok (optionOr (listHead remName) (tr/makeToken "" 0 0)))
                         (tlName (optionOr (listTail remName) (list)))
                         (spFrom (skipTrivia tlName))
                         (trivFrom (pairFirst spFrom))
                         (remFrom (pairSecond spFrom))]
                     (if (or (listEmpty? remFrom) (!= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from"))
                       (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remFrom) (tr/tokenEnd nameTok) (tr/tokenStart (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))))))
                       (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                             (tlFrom (optionOr (listTail remFrom) (list)))
                             (spSrc (skipTrivia tlFrom))
                             (trivSrc (pairFirst spSrc))
                             (remSrc (pairSecond spSrc))]
                         (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                           (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                           (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                                 (tlSrc (optionOr (listTail remSrc) (list)))
                                 (baseKids (concatLists (list (tokElem exportTok) triv1 (tokElem hd1) trivAs (tokElem asTok) trivName (tokElem nameTok) trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                                 (attrRes (parseImportAttributes tlSrc text))]
                             (mt attrRes
                               ((err msg) (err msg))
                               ((ok attrPair)
                                (let [(attrKids (pairFirst attrPair))
                                      (remAttr (pairSecond attrPair))
                                      (allKids (listAppend baseKids attrKids))]
                                  (finishDeclWithSemi allKids startPos "exportDecl" remAttr text)))))))))))
               (let [(fromTok (optionOr (listHead remAs) (tr/makeToken "" 0 0)))
                     (tlFrom (optionOr (listTail remAs) (list)))]
                 (if (or (listEmpty? remAs) (!= (tokenSlice fromTok text) "from"))
                   (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remAs) (tr/tokenEnd hd1) (tr/tokenStart fromTok)))))
                   (let [(spSrc (skipTrivia tlFrom))
                         (trivSrc (pairFirst spSrc))
                         (remSrc (pairSecond spSrc))]
                     (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                       (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                       (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                             (tlSrc (optionOr (listTail remSrc) (list)))
                             (baseKids (concatLists (list (tokElem exportTok) triv1 (tokElem hd1) trivAs (tokElem fromTok) trivSrc (tokElem srcTok))))
                             (attrRes (parseImportAttributes tlSrc text))]
                         (mt attrRes
                           ((err msg) (err msg))
                           ((ok attrPair)
                            (let [(attrKids (pairFirst attrPair))
                                  (remAttr (pairSecond attrPair))
                                  (allKids (listAppend baseKids attrKids))]
                              (finishDeclWithSemi allKids startPos "exportDecl" remAttr text))))))))))))
          ((= k1 "lbrace")
           (let [(specRes (parseExportSpecifiersLoop tl1 text (list)))]
             (mt specRes
               ((err msg) (err msg))
               ((ok specPair)
                (let [(specKids (pairFirst specPair))
                      (remSpec (pairSecond specPair))
                      (spFrom (skipTrivia remSpec))
                      (trivFrom (pairFirst spFrom))
                      (remFrom (pairSecond spFrom))
                      (isFrom (and (not (listEmpty? remFrom)) (= (tokenSlice (optionOr (listHead remFrom) (tr/makeToken "" 0 0)) text) "from")))]
                  (if isFrom
                    (let [(fromTok (optionOr (listHead remFrom) (tr/makeToken "" 0 0)))
                          (tlFrom (optionOr (listTail remFrom) (list)))
                          (spSrc (skipTrivia tlFrom))
                          (trivSrc (pairFirst spSrc))
                          (remSrc (pairSecond spSrc))]
                      (if (or (listEmpty? remSrc) (!= (tr/tokenKind (optionOr (listHead remSrc) (tr/makeToken "" 0 0))) "string"))
                        (err (str "Parse error at offset " (stringFromInt64 (if (listEmpty? remSrc) (tr/tokenEnd fromTok) (tr/tokenStart (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))))))
                        (let [(srcTok (optionOr (listHead remSrc) (tr/makeToken "" 0 0)))
                              (tlSrc (optionOr (listTail remSrc) (list)))
                              (baseKids (concatLists (list (tokElem exportTok) triv1 (tokElem hd1) specKids trivFrom (tokElem fromTok) trivSrc (tokElem srcTok))))
                              (attrRes (parseImportAttributes tlSrc text))]
                          (mt attrRes
                            ((err msg) (err msg))
                            ((ok attrPair)
                             (let [(attrKids (pairFirst attrPair))
                                   (remAttr (pairSecond attrPair))
                                   (allKids (listAppend baseKids attrKids))]
                               (finishDeclWithSemi allKids startPos "exportDecl" remAttr text)))))))
                    (let [(allKids (concatLists (list (tokElem exportTok) triv1 (tokElem hd1) specKids)))]
                      (finishDeclWithSemi allKids startPos "exportDecl" remSpec text))))))))
          ((or (= sl1 "var") (or (= sl1 "let") (or (= sl1 "const") (or (= sl1 "function") (or (= sl1 "class") (isAsyncFn rem1 text))))))
           (let [(stmtRes (stmt/parseStatement rem1 text false false))
                 (stmtNode stmtRes.node)
                 (remDecl stmtRes.rest)
                 (allKids (concatLists (list (tokElem exportTok) triv1 (list (tr/elemNode stmtNode)))))
                 (endPos (tr/nodeEnd stmtNode))
                 (node (tr/makeNode "exportDecl" startPos endPos allKids))]
             (ok (tr/ParseResult :node node :rest remDecl))))
          (else
           (err (str "Parse error at offset " (stringFromInt64 (tr/tokenStart hd1)))))))))

fn isModuleImport toks: (List tr/Token) text: String -> Bool
  (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
        (sl (tokenSlice hd text))]
    (if (= sl "import")
      (let [(sp (skipTrivia (optionOr (listTail toks) (list))))
            (rem (pairSecond sp))]
        (if (listEmpty? rem)
          true
          (let [(nextTok (optionOr (listHead rem) (tr/makeToken "" 0 0)))
                (k (tr/tokenKind nextTok))]
            (if (= k "lparen")
              false
              (if (= k "dot")
                (let [(sp2 (skipTrivia (optionOr (listTail rem) (list))))
                      (rem2 (pairSecond sp2))]
                  (if (listEmpty? rem2)
                    true
                    (let [(metaTok (optionOr (listHead rem2) (tr/makeToken "" 0 0)))]
                      (!= (tokenSlice metaTok text) "meta"))))
                true)))))
      false))

fn parseModuleItemsLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (Result (List tr/TreeElement) String)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (ok (listAppend acc triv))
      (let [(accWithTriv (listAppend acc triv))
            (hd (optionOr (listHead rem) (tr/makeToken "" 0 0)))
            (sl (tokenSlice hd text))]
        (cond
          ((isModuleImport rem text)
           (mt (parseImportDecl rem text)
             ((err msg) (err msg))
             ((ok declRes)
              (let [(node declRes.node)
                    (remToks declRes.rest)]
                (if (= (listLength remToks) (listLength rem))
                  (let [(advToks (optionOr (listTail rem) (list)))]
                    (parseModuleItemsLoop advToks text (listAppend accWithTriv (list (tr/elemNode node)))))
                  (parseModuleItemsLoop remToks text (listAppend accWithTriv (list (tr/elemNode node)))))))))
          ((= sl "export")
           (mt (parseExportDecl rem text)
             ((err msg) (err msg))
             ((ok declRes)
              (let [(node declRes.node)
                    (remToks declRes.rest)]
                (if (= (listLength remToks) (listLength rem))
                  (let [(advToks (optionOr (listTail rem) (list)))]
                    (parseModuleItemsLoop advToks text (listAppend accWithTriv (list (tr/elemNode node)))))
                  (parseModuleItemsLoop remToks text (listAppend accWithTriv (list (tr/elemNode node)))))))))
          (else
           (let [(stmtRes (stmt/parseStatement rem text true false))
                 (stmtNode stmtRes.node)
                 (remToks stmtRes.rest)]
             (if (or (tr/isErrorNode stmtNode) (= (listLength remToks) (listLength rem)))
               (let [(advToks (if (= (listLength remToks) (listLength rem)) (optionOr (listTail rem) (list)) remToks))
                     (errElem (if (tr/isErrorNode stmtNode) (tr/elemNode stmtNode) (tr/elemToken hd)))]
                 (parseModuleItemsLoop advToks text (listAppend accWithTriv (list errElem))))
               (parseModuleItemsLoop remToks text (listAppend accWithTriv (list (tr/elemNode stmtNode)))))))))))

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

fn parseModuleTokens toks: (List tr/Token) text: String -> (Result tr/Node String)
  (let [(loopRes (parseModuleItemsLoop toks text (list)))]
    (mt loopRes
      ((err msg)
       (err msg))
      ((ok elems)
       (let [(root (tr/makeNode "module" 0 (stringLength text) elems))]
         (mt (firstErrorOffset elems)
           ((some off)
            (err (str "Parse error at offset " (stringFromInt64 off))))
           ((none)
            (mt (tr/checkTiling root (stringLength text))
              ((ok _) (ok root))
              ((err msg) (err msg)))))))))

fn parseModule text: String -> (Result tr/Node String)
  (let [(toks (lx/tokenize text))]
    (parseModuleTokens toks text))

fn parse text: String -> (Result tr/Node String)
  (parseModule text)

fn isModuleNode node: tr/Node -> Bool
  (let [(k (tr/nodeKind node))]
    (or (= k "module")
    (or (= k "importDecl")
    (or (= k "exportDecl")
        (= k "importAttributes")))))

fn moduleKind node: tr/Node -> String
  (tr/nodeKind node)

fn moduleItemToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))]
    (cond
      ((= k "importDecl")
       "(import)")
      ((= k "exportDecl")
       "(export)")
      ((= k "importAttributes")
       "(attributes)")
      (else
       (stmt/stmtToSExpr node text))))

fn formatModuleItems items: (List tr/Node) text: String -> String
  (if (listEmpty? items)
    ""
    (let [(hd (optionOr (listHead items) (tr/makeNode "" 0 0 (list))))
          (tl (optionOr (listTail items) (list)))
          (s (moduleItemToSExpr hd text))]
      (if (listEmpty? tl)
        s
        (str s " " (formatModuleItems tl text)))))

fn moduleToSExpr node: tr/Node text: String -> String
  (let [(k (tr/nodeKind node))
        (kids (tr/nodeChildren node))
        (childNodes (stmt/findChildNodes kids))]
    (cond
      ((= k "module")
       (let [(inner (formatModuleItems childNodes text))]
         (if (stringEmpty? inner) "(module)" (str "(module " inner ")"))))
      ((= k "importDecl")
       "(import)")
      ((= k "exportDecl")
       "(export)")
      ((= k "importAttributes")
       "(attributes)")
      (else
       (stmt/stmtToSExpr node text))))
