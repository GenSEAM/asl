(module asl-syntax/css/rules
  :x [parseRules
      parseStylesheet
      parseDeclarationList
      extractSymbols
      extractOutlineSymbols
      ruleKind
      rulePreludeText
      isImportantDeclaration?
      rulesToJson
      declarationsToJson]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/css/lex :a lex)
      (asl-json/json :a j)])

fn tokenSlice tok: tr/Token text: String -> String
  (let [(st (tr/tokenStart tok))
        (en (tr/tokenEnd tok))]
    (if (or (< st 0) (> en (stringLength text)))
      ""
      (optionOr (stringSlice text st en) "")))
fn firstElementStart elems: (List tr/TreeElement) fallback: Int64 -> Int64
  (if (listEmpty? elems)
    fallback
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" fallback fallback))))]
      (tr/elementStart hd)))
fn lastElementEndLoop elems: (List tr/TreeElement) prevEnd: Int64 -> Int64
  (if (listEmpty? elems)
    prevEnd
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" prevEnd prevEnd))))
          (tl (optionOr (listTail elems) (list)))]
      (lastElementEndLoop tl (tr/elementEnd hd))))
fn lastElementEnd elems: (List tr/TreeElement) fallback: Int64 -> Int64
  (if (listEmpty? elems)
    fallback
    (lastElementEndLoop elems fallback))
fn hasBraceBeforeSemiOrCloseLoop toks: (List tr/Token) closeKind: String -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((= k "lbrace") true)
        ((or (= k "semicolon") (= k closeKind)) false)
        (else (hasBraceBeforeSemiOrCloseLoop tl closeKind)))))
fn checkColonNext toks: (List tr/Token) -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((= k "colon") true)
        ((or (= k "whitespace") (= k "comment")) (checkColonNext tl))
        (else false))))
fn isDeclarationStart toks: (List tr/Token) -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (!= (tr/tokenKind hd) "ident")
        false
        (let [(tl (optionOr (listTail toks) (list)))]
          (checkColonNext tl)))))
fn consumeSimpleBlockLoop kind: String closeKind: String openTok: tr/Token acc: (List tr/TreeElement) toks: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (if (listEmpty? toks)
    (let [(st (tr/tokenStart openTok))
          (revAcc (listReverse acc))
          (en (lastElementEnd revAcc (tr/tokenEnd openTok)))
          (node (tr/makeNode kind st en (cons (tr/elemToken openTok) revAcc)))]
      (pair (tr/elemNode node) (list)))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (= (tr/tokenKind hd) closeKind)
        (let [(st (tr/tokenStart openTok))
              (en (tr/tokenEnd hd))
              (revAcc (listReverse acc))
              (all (cons (tr/elemToken openTok) (listAppend revAcc (list (tr/elemToken hd)))))
              (node (tr/makeNode kind st en all))]
          (pair (tr/elemNode node) tl))
        (mt (consumeComponentValue toks text)
          ((none)
           (let [(st (tr/tokenStart openTok))
                 (revAcc (listReverse acc))
                 (en (lastElementEnd revAcc (tr/tokenEnd openTok)))
                 (node (tr/makeNode kind st en (cons (tr/elemToken openTok) revAcc)))]
             (pair (tr/elemNode node) (list))))
          ((some p)
           (consumeSimpleBlockLoop kind closeKind openTok (cons (pairFirst p) acc) (pairSecond p) text))))))
fn consumeBlockLoop kind: String closeKind: String openTok: tr/Token acc: (List tr/TreeElement) toks: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (if (listEmpty? toks)
    (let [(st (tr/tokenStart openTok))
          (revAcc (listReverse acc))
          (en (lastElementEnd revAcc (tr/tokenEnd openTok)))
          (node (tr/makeNode kind st en (cons (tr/elemToken openTok) revAcc)))]
      (pair (tr/elemNode node) (list)))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((= k closeKind)
         (let [(st (tr/tokenStart openTok))
               (en (tr/tokenEnd hd))
               (revAcc (listReverse acc))
               (all (cons (tr/elemToken openTok) (listAppend revAcc (list (tr/elemToken hd)))))
               (node (tr/makeNode kind st en all))]
           (pair (tr/elemNode node) tl)))
        ((or (= k "whitespace") (or (= k "comment") (= k "semicolon")))
         (consumeBlockLoop kind closeKind openTok (cons (tr/elemToken hd) acc) tl text))
        ((= k "at-keyword")
         (let [(p (consumeAtRule toks text))]
           (consumeBlockLoop kind closeKind openTok (cons (pairFirst p) acc) (pairSecond p) text)))
        ((hasBraceBeforeSemiOrCloseLoop toks closeKind)
         (let [(p (consumeQualifiedRule toks text))]
           (consumeBlockLoop kind closeKind openTok (cons (pairFirst p) acc) (pairSecond p) text)))
        ((isDeclarationStart toks)
         (let [(p (consumeDeclaration toks text))]
           (consumeBlockLoop kind closeKind openTok (cons (pairFirst p) acc) (pairSecond p) text)))
        (else
         (mt (consumeComponentValue toks text)
           ((none)
            (let [(st (tr/tokenStart openTok))
                  (revAcc (listReverse acc))
                  (en (lastElementEnd revAcc (tr/tokenEnd openTok)))
                  (node (tr/makeNode kind st en (cons (tr/elemToken openTok) revAcc)))]
              (pair (tr/elemNode node) (list))))
           ((some p)
            (consumeBlockLoop kind closeKind openTok (cons (pairFirst p) acc) (pairSecond p) text)))))))
fn consumeSimpleBlock kind: String closeKind: String openTok: tr/Token toks: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (consumeSimpleBlockLoop kind closeKind openTok (list) toks text)
fn consumeBlock kind: String closeKind: String openTok: tr/Token toks: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (consumeBlockLoop kind closeKind openTok (list) toks text)
fn consumeComponentValue tokens: (List tr/Token) text: String -> (Option (Pair tr/TreeElement (List tr/Token)))
  (if (listEmpty? tokens)
    (none)
    (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail tokens) (list)))
          (k (tr/tokenKind tok))]
      (cond
        ((= k "lbrace")
         (some (consumeBlock "block" "rbrace" tok rest text)))
        ((= k "lbracket")
         (some (consumeSimpleBlock "simple-block-bracket" "rbracket" tok rest text)))
        ((= k "lparen")
         (some (consumeSimpleBlock "simple-block-paren" "rparen" tok rest text)))
        ((= k "function")
         (some (consumeSimpleBlock "function" "rparen" tok rest text)))
        (else
         (some (pair (tr/elemToken tok) rest))))))
fn consumeComponentValuesUntilLoop toks: (List tr/Token) stopPred: (fn [tr/Token] -> Bool) acc: (List tr/TreeElement) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (if (listEmpty? toks)
    (pair (listReverse acc) (list))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (stopPred hd)
        (pair (listReverse acc) toks)
        (mt (consumeComponentValue toks text)
          ((none) (pair (listReverse acc) (list)))
          ((some p)
           (consumeComponentValuesUntilLoop (pairSecond p) stopPred (cons (pairFirst p) acc) text))))))
fn consumeComponentValuesUntil toks: (List tr/Token) stopPred: (fn [tr/Token] -> Bool) text: String -> (Pair (List tr/TreeElement) (List tr/Token))
  (consumeComponentValuesUntilLoop toks stopPred (list) text)
fn consumeAtRule tokens: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (let [(atTok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
        (rest (optionOr (listTail tokens) (list)))
        (isStop (fn [(t tr/Token)] -> Bool (or (= (tr/tokenKind t) "semicolon") (= (tr/tokenKind t) "lbrace"))))
        (pPrelude (consumeComponentValuesUntil rest isStop text))
        (preludeElems (pairFirst pPrelude))
        (remToks (pairSecond pPrelude))]
    (if (listEmpty? remToks)
      (let [(en (lastElementEnd preludeElems (tr/tokenEnd atTok)))
            (all (cons (tr/elemToken atTok) preludeElems))
            (node (tr/makeNode "at-rule" (tr/tokenStart atTok) en all))]
        (pair (tr/elemNode node) (list)))
      (let [(nextTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind nextTok) "semicolon")
          (let [(semiElem (tr/elemToken nextTok))
                (all (listAppend (cons (tr/elemToken atTok) preludeElems) (list semiElem)))
                (node (tr/makeNode "at-rule" (tr/tokenStart atTok) (tr/tokenEnd nextTok) all))]
            (pair (tr/elemNode node) (optionOr (listTail remToks) (list))))
          (if (= (tr/tokenKind nextTok) "lbrace")
            (let [(pBlock (consumeBlock "block" "rbrace" nextTok (optionOr (listTail remToks) (list)) text))
                  (blockElem (pairFirst pBlock))
                  (all (listAppend (cons (tr/elemToken atTok) preludeElems) (list blockElem)))
                  (node (tr/makeNode "at-rule" (tr/tokenStart atTok) (tr/elementEnd blockElem) all))]
              (pair (tr/elemNode node) (pairSecond pBlock)))
            (let [(en (lastElementEnd preludeElems (tr/tokenEnd atTok)))
                  (all (cons (tr/elemToken atTok) preludeElems))
                  (node (tr/makeNode "at-rule" (tr/tokenStart atTok) en all))]
              (pair (tr/elemNode node) remToks)))))))
fn consumeQualifiedRule tokens: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (let [(isStop (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "lbrace")))
        (pPrelude (consumeComponentValuesUntil tokens isStop text))
        (preludeElems (pairFirst pPrelude))
        (remToks (pairSecond pPrelude))]
    (if (listEmpty? remToks)
      (let [(st (firstElementStart preludeElems 0))
            (en (lastElementEnd preludeElems st))
            (node (tr/makeErrorNode st en preludeElems))]
        (pair (tr/elemNode node) (list)))
      (let [(nextTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))]
        (if (= (tr/tokenKind nextTok) "lbrace")
          (let [(pBlock (consumeBlock "block" "rbrace" nextTok (optionOr (listTail remToks) (list)) text))
                (blockElem (pairFirst pBlock))
                (st (firstElementStart preludeElems (tr/elementStart blockElem)))
                (en (tr/elementEnd blockElem))
                (all (listAppend preludeElems (list blockElem)))
                (node (tr/makeNode "qualified-rule" st en all))]
            (pair (tr/elemNode node) (pairSecond pBlock)))
          (let [(st (firstElementStart preludeElems 0))
                (en (lastElementEnd preludeElems st))
                (node (tr/makeErrorNode st en preludeElems))]
            (pair (tr/elemNode node) remToks))))))
fn consumeRulesLoop tokens: (List tr/Token) text: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? tokens)
    (listReverse acc)
    (let [(hd (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (k (tr/tokenKind hd))]
      (cond
        ((or (= k "whitespace") (= k "comment"))
         (consumeRulesLoop (optionOr (listTail tokens) (list)) text (cons (tr/elemToken hd) acc)))
        ((= k "at-keyword")
         (let [(p (consumeAtRule tokens text))]
           (consumeRulesLoop (pairSecond p) text (cons (pairFirst p) acc))))
        (else
         (let [(p (consumeQualifiedRule tokens text))]
           (consumeRulesLoop (pairSecond p) text (cons (pairFirst p) acc)))))))
fn parseStylesheet text: String -> tr/Node
  (let [(tokens (lex/tokenizeText text))
        (len (stringLength text))
        (elems (consumeRulesLoop tokens text (list)))]
    (tr/makeNode "stylesheet" 0 len elems))
fn parseRules text: String -> tr/Node
  (parseStylesheet text)
fn findColonIndexLoop elems: (List tr/TreeElement) idx: Int64 -> (Option Int64)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((elemToken t)
         (let [(k (tr/tokenKind t))]
           (cond
             ((= k "colon") (some idx))
             ((or (= k "whitespace") (= k "comment")) (findColonIndexLoop tl (+ idx 1)))
             (else (none)))))
        ((elemNode _) (none)))))
fn findColonIndex elems: (List tr/TreeElement) -> (Option Int64)
  (findColonIndexLoop elems 0)
fn splitListAtLoop xs: (List tr/TreeElement) n: Int64 acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List tr/TreeElement))
  (if (or (<= n 0) (listEmpty? xs))
    (pair (listReverse acc) xs)
    (let [(hd (optionOr (listHead xs) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail xs) (list)))]
      (splitListAtLoop tl (- n 1) (cons hd acc))))
fn splitListAt xs: (List tr/TreeElement) n: Int64 -> (Pair (List tr/TreeElement) (List tr/TreeElement))
  (splitListAtLoop xs n (list))
fn filterTrailingWhitespace xs: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? xs)
    (list)
    (let [(hd (optionOr (listHead xs) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail xs) (list)))]
      (mt hd
        ((elemToken t)
         (if (= (tr/tokenKind t) "whitespace")
           (filterTrailingWhitespace tl)
           xs))
        ((elemNode _) xs))))
fn checkImportant elems: (List tr/TreeElement) text: String -> Bool
  (let [(rev (filterTrailingWhitespace (listReverse elems)))]
    (if (< (listLength rev) 2)
      false
      (let [(e1 (optionOr (listHead rev) (tr/elemToken (tr/makeToken "" 0 0))))
            (r1 (optionOr (listTail rev) (list)))
            (e2 (optionOr (listHead r1) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt e1
          ((elemToken t1)
           (mt e2
             ((elemToken t2)
              (and (= (tr/tokenKind t1) "ident")
              (and (= (stringLower (tokenSlice t1 text)) "important")
              (and (= (tr/tokenKind t2) "delim")
                   (= (tokenSlice t2 text) "!")))))
             ((elemNode _) false)))
          ((elemNode _) false)))))
fn trimImportantFromValueLoop rev: (List tr/TreeElement) -> (List tr/TreeElement)
  (let [(rev1 (filterTrailingWhitespace rev))]
    (if (< (listLength rev1) 2)
      rev
      (let [(r1 (optionOr (listTail rev1) (list)))
            (r2 (optionOr (listTail r1) (list)))]
        (filterTrailingWhitespace r2))))
fn trimImportantFromValue elems: (List tr/TreeElement) text: String -> (List tr/TreeElement)
  (if (checkImportant elems text)
    (listReverse (trimImportantFromValueLoop (listReverse elems)))
    elems)
fn consumeDeclaration tokens: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (let [(identTok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
        (rest (optionOr (listTail tokens) (list)))
        (isStop (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "semicolon")))
        (pVals (consumeComponentValuesUntil rest isStop text))
        (valElems (pairFirst pVals))
        (remToks (pairSecond pVals))
        (colonOpt (findColonIndex valElems))]
    (mt colonOpt
      ((none)
       (let [(all (cons (tr/elemToken identTok) valElems))
             (st (tr/tokenStart identTok))]
         (if (not (listEmpty? remToks))
           (let [(semiTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
                 (semiElem (tr/elemToken semiTok))
                 (allWithSemi (listAppend all (list semiElem)))
                 (node (tr/makeErrorNode st (tr/tokenEnd semiTok) allWithSemi))]
             (pair (tr/elemNode node) (optionOr (listTail remToks) (list))))
           (let [(en (lastElementEnd valElems (tr/tokenEnd identTok)))
                 (node (tr/makeErrorNode st en all))]
             (pair (tr/elemNode node) (list))))))
      ((some cIdx)
       (let [(all (cons (tr/elemToken identTok) valElems))
             (st (tr/tokenStart identTok))]
         (if (not (listEmpty? remToks))
           (let [(semiTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
                 (semiElem (tr/elemToken semiTok))
                 (allWithSemi (listAppend all (list semiElem)))
                 (node (tr/makeNode "declaration" st (tr/tokenEnd semiTok) allWithSemi))]
             (pair (tr/elemNode node) (optionOr (listTail remToks) (list))))
           (let [(en (lastElementEnd valElems (tr/tokenEnd identTok)))
                 (node (tr/makeNode "declaration" st en all))]
             (pair (tr/elemNode node) (list))))))))
fn consumeDeclarationError tokens: (List tr/Token) text: String -> (Pair tr/TreeElement (List tr/Token))
  (let [(isStop (fn [(t tr/Token)] -> Bool (= (tr/tokenKind t) "semicolon")))
        (p (consumeComponentValuesUntil tokens isStop text))
        (errElems (pairFirst p))
        (remToks (pairSecond p))
        (st (firstElementStart errElems 0))]
    (if (not (listEmpty? remToks))
      (let [(semiTok (optionOr (listHead remToks) (tr/makeToken "" 0 0)))
            (semiElem (tr/elemToken semiTok))
            (allWithSemi (listAppend errElems (list semiElem)))
            (node (tr/makeErrorNode st (tr/tokenEnd semiTok) allWithSemi))]
        (pair (tr/elemNode node) (optionOr (listTail remToks) (list))))
      (let [(en (lastElementEnd errElems st))
            (node (tr/makeErrorNode st en errElems))]
        (pair (tr/elemNode node) (list)))))
fn consumeDeclarationListLoop tokens: (List tr/Token) text: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? tokens)
    (listReverse acc)
    (let [(hd (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (k (tr/tokenKind hd))]
      (cond
        ((or (= k "whitespace") (or (= k "comment") (= k "semicolon")))
         (consumeDeclarationListLoop (optionOr (listTail tokens) (list)) text (cons (tr/elemToken hd) acc)))
        ((= k "at-keyword")
         (let [(p (consumeAtRule tokens text))]
           (consumeDeclarationListLoop (pairSecond p) text (cons (pairFirst p) acc))))
        ((= k "ident")
         (let [(p (consumeDeclaration tokens text))]
           (consumeDeclarationListLoop (pairSecond p) text (cons (pairFirst p) acc))))
        (else
         (let [(p (consumeDeclarationError tokens text))]
           (consumeDeclarationListLoop (pairSecond p) text (cons (pairFirst p) acc)))))))
fn parseDeclarationList text: String -> tr/Node
  (let [(tokens (lex/tokenizeText text))
        (len (stringLength text))
        (elems (consumeDeclarationListLoop tokens text (list)))]
    (tr/makeNode "declaration-list" 0 len elems))
fn unquoteString s: String -> String
  (let [(len (stringLength s))]
    (if (< len 2)
      s
      (let [(q1 (optionOr (stringSlice s 0 1) ""))
            (q2 (optionOr (stringSlice s (- len 1) len) ""))]
        (if (and (or (= q1 "\"") (= q1 "'")) (= q1 q2))
          (optionOr (stringSlice s 1 (- len 1)) "")
          s))))
fn blockInteriorElems node: tr/Node -> (List tr/TreeElement)
  (let [(children (tr/nodeChildren node))]
    (if (listEmpty? children)
      (list)
      (let [(afterOpen (optionOr (listTail children) (list)))]
        (if (listEmpty? afterOpen)
          (list)
          (let [(rev (listReverse afterOpen))
                (lastChild (optionOr (listHead rev) (tr/elemToken (tr/makeToken "" 0 0))))]
            (mt lastChild
              ((elemToken t)
               (let [(k (tr/tokenKind t))]
                 (if (or (= k "rbrace") (or (= k "rbracket") (= k "rparen")))
                   (listReverse (optionOr (listTail rev) (list)))
                   afterOpen)))
              ((elemNode _) afterOpen)))))))
fn componentValueToJson elem: tr/TreeElement text: String -> (Option j/Json)
  (mt elem
    ((elemToken tok)
     (let [(k (tr/tokenKind tok))]
       (cond
         ((or (= k "comment") (= k "bom")) (none))
         ((= k "whitespace") (some (j/jstr " ")))
         ((= k "ident") (some (j/jarr (list (j/jstr "ident") (j/jstr (tokenSlice tok text))))))
         ((= k "at-keyword")
          (let [(s (tokenSlice tok text))
                (name (if (stringStartsWith? s "@") (optionOr (stringSlice s 1 (stringLength s)) "") s))]
            (some (j/jarr (list (j/jstr "at-keyword") (j/jstr name))))))
         ((= k "hash")
          (let [(s (tokenSlice tok text))
                (name (if (stringStartsWith? s "#") (optionOr (stringSlice s 1 (stringLength s)) "") s))]
            (some (j/jarr (list (j/jstr "hash") (j/jstr name) (j/jstr "id"))))))
         ((= k "string")
          (let [(s (tokenSlice tok text))]
            (some (j/jarr (list (j/jstr "string") (j/jstr (unquoteString s)))))))
         ((= k "number")
          (let [(s (tokenSlice tok text))
                (numVal (optionOr (stringToInt64 s) 0))
                (isInt (not (stringContains? s ".")))]
            (some (j/jarr (list (j/jstr "number") (j/jstr s) (j/jnum (int64ToFloat64 numVal)) (j/jstr (if isInt "integer" "number")))))))
         ((= k "colon") (some (j/jstr ":")))
         ((= k "semicolon") (some (j/jstr ";")))
         ((= k "comma") (some (j/jstr ",")))
         ((= k "cdo") (some (j/jstr "<!--")))
         ((= k "cdc") (some (j/jstr "-->")))
         ((= k "delim") (some (j/jstr (tokenSlice tok text))))
         ((= k "include-match") (some (j/jstr "~=")))
         ((= k "dash-match") (some (j/jstr "|=")))
         ((= k "prefix-match") (some (j/jstr "^=")))
         ((= k "suffix-match") (some (j/jstr "$=")))
         ((= k "substring-match") (some (j/jstr "*=")))
         ((= k "column") (some (j/jstr "||")))
         (else (none)))))
    ((elemNode node)
     (let [(nk (tr/nodeKind node))]
       (cond
         ((= nk "simple-block-bracket")
          (let [(inner (componentValuesToJson (blockInteriorElems node) text))]
            (some (j/jarr (cons (j/jstr "[]") inner)))))
         ((= nk "simple-block-paren")
          (let [(inner (componentValuesToJson (blockInteriorElems node) text))]
            (some (j/jarr (cons (j/jstr "()") inner)))))
         ((= nk "simple-block-brace")
          (let [(inner (componentValuesToJson (blockInteriorElems node) text))]
            (some (j/jarr (cons (j/jstr "{}") inner)))))
         ((= nk "block")
          (let [(inner (componentValuesToJson (blockInteriorElems node) text))]
            (some (j/jarr (cons (j/jstr "{}") inner)))))
         ((= nk "declaration")
          (none))
         ((= nk "qualified-rule")
          (let [(pre (componentValuesToJson (rulePreludeElems node) text))
                (bOpt (ruleBlockNode node))
                (bJson (mt bOpt
                         ((none) (j/jarr (list)))
                         ((some bn) (j/jarr (cons (j/jstr "{}") (componentValuesToJson (blockInteriorElems bn) text))))))]
            (some (j/jarr (list (j/jarr pre) bJson)))))
         ((= nk "function")
          (let [(children (tr/nodeChildren node))
                (fnTok (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
                (fnName (mt fnTok ((elemToken t) (tokenSlice t text)) ((elemNode _) "")))
                (inner (componentValuesToJson (blockInteriorElems node) text))]
            (some (j/jarr (cons (j/jstr "function") (cons (j/jstr fnName) inner))))))
         (else (none))))))
fn componentValuesToJsonLoop elems: (List tr/TreeElement) text: String acc: (List j/Json) -> (List j/Json)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((elemNode n)
         (let [(nk (tr/nodeKind n))]
           (cond
             ((= nk "declaration")
              (let [(declElems (tr/nodeChildren n))
                    (declJsons (componentValuesToJson declElems text))]
                (componentValuesToJsonLoop tl text (listAppend (listReverse declJsons) acc))))
             ((= nk "qualified-rule")
              (let [(pre (componentValuesToJson (rulePreludeElems n) text))
                    (bOpt (ruleBlockNode n))
                    (bJson (mt bOpt
                             ((none) (j/jarr (list (j/jstr "{}"))))
                             ((some bn) (j/jarr (cons (j/jstr "{}") (componentValuesToJson (blockInteriorElems bn) text))))))
                    (ruleJsons (listAppend pre (list bJson)))]
                (componentValuesToJsonLoop tl text (listAppend (listReverse ruleJsons) acc))))
             (else
              (mt (componentValueToJson hd text)
                ((none) (componentValuesToJsonLoop tl text acc))
                ((some v) (componentValuesToJsonLoop tl text (cons v acc))))))))
        ((elemToken _)
         (mt (componentValueToJson hd text)
           ((none) (componentValuesToJsonLoop tl text acc))
           ((some v) (componentValuesToJsonLoop tl text (cons v acc))))))))
fn componentValuesToJson elems: (List tr/TreeElement) text: String -> (List j/Json)
  (componentValuesToJsonLoop elems text (list))
fn ruleKind node: tr/Node -> String
  (tr/nodeKind node)
fn rulePreludeElems node: tr/Node -> (List tr/TreeElement)
  (let [(children (tr/nodeChildren node))]
    (filter (fn [(e tr/TreeElement)] -> Bool
              (mt e
                ((elemToken t) (!= (tr/tokenKind t) "semicolon"))
                ((elemNode n) (!= (tr/nodeKind n) "block"))))
            children))
fn ruleBlockNode node: tr/Node -> (Option tr/Node)
  (let [(children (tr/nodeChildren node))
        (blockElems (filter (fn [(e tr/TreeElement)] -> Bool
                              (mt e
                                ((elemToken _) false)
                                ((elemNode n) (= (tr/nodeKind n) "block"))))
                            children))]
    (if (listEmpty? blockElems)
      (none)
      (let [(hd (optionOr (listHead blockElems) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt hd
          ((elemNode n) (some n))
          ((elemToken _) (none))))))
fn rulePreludeText node: tr/Node text: String -> String
  (let [(elems (rulePreludeElems node))]
    (if (listEmpty? elems)
      ""
      (let [(st (firstElementStart elems 0))
            (en (lastElementEnd elems st))]
        (stringTrim (optionOr (stringSlice text st en) "")))))
fn ruleToJson elem: tr/TreeElement text: String -> (Option j/Json)
  (mt elem
    ((elemToken _) (none))
    ((elemNode node)
     (let [(k (tr/nodeKind node))]
       (cond
         ((= k "error")
          (some (j/jarr (list (j/jstr "error") (j/jstr "invalid")))))
         ((= k "qualified-rule")
          (let [(prelude (componentValuesToJson (rulePreludeElems node) text))
                (bOpt (ruleBlockNode node))
                (blockJson (mt bOpt
                             ((none) (j/jarr (list)))
                             ((some bn) (j/jarr (componentValuesToJson (blockInteriorElems bn) text)))))]
            (some (j/jarr (list (j/jstr "qualified rule") (j/jarr prelude) blockJson)))))
         ((= k "at-rule")
          (let [(children (tr/nodeChildren node))
                (firstElem (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
                (atName (mt firstElem
                          ((elemToken t)
                           (let [(s (tokenSlice t text))]
                             (if (stringStartsWith? s "@") (optionOr (stringSlice s 1 (stringLength s)) "") s)))
                          ((elemNode _) "")))
                (prelude (componentValuesToJson (optionOr (listTail (rulePreludeElems node)) (list)) text))
                (bOpt (ruleBlockNode node))
                (blockJson (mt bOpt
                             ((none) (j/jnull))
                             ((some bn) (j/jarr (componentValuesToJson (blockInteriorElems bn) text)))))]
            (some (j/jarr (list (j/jstr "at-rule") (j/jstr atName) (j/jarr prelude) blockJson)))))
         (else (none))))))
fn rulesToJson root: tr/Node text: String -> j/Json
  (let [(children (tr/nodeChildren root))
        (rules (filter (fn [(e tr/TreeElement)] -> Bool
                         (mt e
                           ((elemToken _) false)
                           ((elemNode n)
                            (let [(k (tr/nodeKind n))]
                              (or (= k "qualified-rule") (or (= k "at-rule") (= k "error")))))))
                       children))
        (items (map (fn [(e tr/TreeElement)] -> j/Json
                      (optionOr (ruleToJson e text) (j/jnull)))
                    rules))]
    (j/jarr items))
fn declarationName node: tr/Node text: String -> String
  (let [(children (tr/nodeChildren node))]
    (if (listEmpty? children)
      ""
      (let [(hd (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt hd
          ((elemToken t) (tokenSlice t text))
          ((elemNode _) "")))))
fn declarationValueElems node: tr/Node -> (List tr/TreeElement)
  (let [(children (tr/nodeChildren node))
        (afterIdent (optionOr (listTail children) (list)))]
    (mt (findColonIndex afterIdent)
      ((none) (list))
      ((some cIdx)
       (let [(p (splitListAt afterIdent (+ cIdx 1)))
             (valsWithSemi (pairSecond p))
             (rev (listReverse valsWithSemi))]
         (if (listEmpty? rev)
           (list)
           (let [(hd (optionOr (listHead rev) (tr/elemToken (tr/makeToken "" 0 0))))]
             (mt hd
               ((elemToken t)
                (if (= (tr/tokenKind t) "semicolon")
                  (listReverse (optionOr (listTail rev) (list)))
                  valsWithSemi))
               ((elemNode _) valsWithSemi))))))))
fn isImportantDeclaration? node: tr/Node text: String -> Bool
  (let [(valElems (declarationValueElems node))]
    (checkImportant valElems text))
fn declarationToJson elem: tr/TreeElement text: String -> (Option j/Json)
  (mt elem
    ((elemToken _) (none))
    ((elemNode node)
     (let [(k (tr/nodeKind node))]
       (cond
         ((= k "error")
          (some (j/jarr (list (j/jstr "error") (j/jstr "invalid")))))
         ((= k "at-rule")
          (ruleToJson elem text))
         ((= k "declaration")
          (let [(name (declarationName node text))
                (rawValElems (declarationValueElems node))
                (imp (isImportantDeclaration? node text))
                (valElems (trimImportantFromValue rawValElems text))
                (valJson (j/jarr (componentValuesToJson valElems text)))]
            (some (j/jarr (list (j/jstr "declaration") (j/jstr name) valJson (j/jbool imp))))))
         (else (none))))))
fn declarationsToJson root: tr/Node text: String -> j/Json
  (let [(children (tr/nodeChildren root))
        (items (filter (fn [(e tr/TreeElement)] -> Bool
                         (mt e
                           ((elemToken _) false)
                           ((elemNode n)
                            (let [(k (tr/nodeKind n))]
                              (or (= k "declaration") (or (= k "at-rule") (= k "error")))))))
                       children))
        (jsons (map (fn [(e tr/TreeElement)] -> j/Json
                      (optionOr (declarationToJson e text) (j/jnull)))
                    items))]
    (j/jarr jsons))
fn extractSymbolsFromNode node: tr/Node text: String container: String depth: Int64 acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (let [(k (tr/nodeKind node))]
    (cond
      ((= k "qualified-rule")
       (let [(sel (rulePreludeText node text))
             (symDef (sym/makeScopedSymbolDef sel "selector" (tr/nodeStart node) (tr/nodeEnd node) container depth))
             (acc1 (cons symDef acc))
             (bOpt (ruleBlockNode node))]
         (mt bOpt
           ((none) acc1)
           ((some bn)
            (extractSymbolsFromElems (tr/nodeChildren bn) text sel (+ depth 1) acc1)))))
      ((= k "at-rule")
       (let [(children (tr/nodeChildren node))
             (firstElem (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
             (atName (mt firstElem
                       ((elemToken t)
                        (let [(s (tokenSlice t text))]
                          (if (stringStartsWith? s "@") (optionOr (stringSlice s 1 (stringLength s)) "") s)))
                       ((elemNode _) "")))
             (preludeElems (optionOr (listTail (rulePreludeElems node)) (list)))
             (preludeStr (if (listEmpty? preludeElems)
                           ""
                           (let [(st (firstElementStart preludeElems 0))
                                 (en (lastElementEnd preludeElems st))]
                             (stringTrim (optionOr (stringSlice text st en) "")))))
             (symKind (cond
                        ((= atName "media") "media")
                        ((= atName "layer") "layer")
                        ((= atName "supports") "supports")
                        ((= atName "container") "container")
                        ((= atName "keyframes") "keyframes")
                        (else "at-rule")))
             (symName (cond
                        ((or (= symKind "media") (or (= symKind "layer") (or (= symKind "supports") (or (= symKind "container") (= symKind "keyframes")))))
                         preludeStr)
                        (else
                         (if (stringEmpty? preludeStr)
                           (str "@" atName)
                           (str "@" atName " " preludeStr)))))
             (symDef (sym/makeScopedSymbolDef symName symKind (tr/nodeStart node) (tr/nodeEnd node) container depth))
             (acc1 (cons symDef acc))
             (bOpt (ruleBlockNode node))]
         (mt bOpt
           ((none) acc1)
           ((some bn)
            (extractSymbolsFromElems (tr/nodeChildren bn) text symName (+ depth 1) acc1)))))
      ((= k "declaration")
       (let [(prop (declarationName node text))]
         (if (stringStartsWith? prop "--")
           (let [(symDef (sym/makeScopedSymbolDef prop "property" (tr/nodeStart node) (tr/nodeEnd node) container depth))]
             (cons symDef acc))
           acc)))
      ((or (= k "stylesheet") (or (= k "block") (= k "declaration-list")))
       (extractSymbolsFromElems (tr/nodeChildren node) text container depth acc))
      (else acc)))
fn extractSymbolsFromElems elems: (List tr/TreeElement) text: String container: String depth: Int64 acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (if (listEmpty? elems)
    acc
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((elemToken _) (extractSymbolsFromElems tl text container depth acc))
        ((elemNode n)
         (let [(acc1 (extractSymbolsFromNode n text container depth acc))]
           (extractSymbolsFromElems tl text container depth acc1))))))
fn extractSymbols root: tr/Node text: String -> (List sym/SymbolDef)
  (listReverse (extractSymbolsFromNode root text "" 0 (list)))
fn isOutlineSymbol sym: sym/SymbolDef -> Bool
  (let [(k (sym/symbolKind sym))]
    (or (= k "selector")
    (or (= k "media")
    (or (= k "layer")
    (or (= k "supports")
    (or (= k "container")
    (or (= k "keyframes")
        (= k "at-rule"))))))))
fn extractOutlineSymbols root: tr/Node text: String -> (List sym/SymbolDef)
  (filter isOutlineSymbol (extractSymbols root text))
