(module asl-forms/rewrite
  :x [Binding
      Match
      Rule
      Extraction
      makeBinding
      makeMatch
      makeRule
      makeExtraction
      bindingName
      bindingVal
      matchStart
      matchEnd
      matchText
      matchBindings
      rulePattern
      ruleReplacement
      extractionPattern
      extractionTemplate
      findMatches
      rewrite
      rewriteAll
      extract
      extractAll]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a aslLex)
      (asl-syntax/asl/paren :a aslParen)
      (asl-syntax/js/lex :a jsLex)
      (asl-syntax/js/module :a jsMod)
      (asl-syntax/ts/module :a tsMod)
      (asl-syntax/css/lex :a cssLex)
      (asl-syntax/css/rules :a cssRules)
      (asl-syntax/registry :a reg)])

(schema Binding
  (:f name String)
  (:f val String))

(schema Match
  (:f start Int64)
  (:f end Int64)
  (:f text String)
  (:f bindings (List Binding)))

(schema Rule
  (:f pattern String)
  (:f replacement String))

(schema Extraction
  (:f pattern String)
  (:f template String))

fn makeBinding name: String val: String -> Binding
  (Binding :name name :val val)

fn bindingName b: Binding -> String
  b.name

fn bindingVal b: Binding -> String
  b.val

fn makeMatch start: Int64 end: Int64 text: String bindings: (List Binding) -> Match
  (Match :start start :end end :text text :bindings bindings)

fn matchStart m: Match -> Int64
  m.start

fn matchEnd m: Match -> Int64
  m.end

fn matchText m: Match -> String
  m.text

fn matchBindings m: Match -> (List Binding)
  m.bindings

fn makeRule pattern: String replacement: String -> Rule
  (Rule :pattern pattern :replacement replacement)

fn rulePattern r: Rule -> String
  r.pattern

fn ruleReplacement r: Rule -> String
  r.replacement

fn makeExtraction pattern: String template: String -> Extraction
  (Extraction :pattern pattern :template template)

fn extractionPattern e: Extraction -> String
  e.pattern

fn extractionTemplate e: Extraction -> String
  e.template


fn isSeqMetaVar s: String -> Bool
  (let [(len (stringLength s))]
    (and (stringStartsWith? s "$$$")
    (and (> len 3)
         (= (scanIdentEnd s 3 len) len))))

fn isSingleMetaVar s: String -> Bool
  (let [(len (stringLength s))]
    (and (stringStartsWith? s "$")
    (and (not (stringStartsWith? s "$$$"))
    (and (> len 1)
         (= (scanIdentEnd s 1 len) len)))))

fn lookupBinding bindings: (List Binding) name: String -> (Option String)
  (if (listEmpty? bindings)
    (none)
    (let [(b (optionOr (listHead bindings) (Binding :name "" :val "")))
          (rest (optionOr (listTail bindings) (list)))]
      (if (= b.name name)
        (some b.val)
        (lookupBinding rest name))))

fn isTriviaElem elem: tr/TreeElement -> Bool
  (mt elem
    ((elemToken tok) (tr/isTrivia tok))
    ((elemNode _) false))

fn filterNonTrivia elems: (List tr/TreeElement) -> (List tr/TreeElement)
  (listReverse
    (fold (fn [(acc (List tr/TreeElement)) (elem tr/TreeElement)] -> (List tr/TreeElement)
            (if (isTriviaElem elem)
              acc
              (cons elem acc)))
          (list)
          elems))

fn elementSliceText text: String elem: tr/TreeElement -> String
  (let [(s (tr/elementStart elem))
        (e (tr/elementEnd elem))]
    (if (or (< s 0) (or (> e (stringLength text)) (> s e)))
      ""
      (optionOr (stringSlice text s e) "")))

fn elementsSpanText text: String elems: (List tr/TreeElement) -> String
  (if (listEmpty? elems)
    ""
    (let [(firstElem (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (lastElem (optionOr (listLast elems) firstElem))
          (s (tr/elementStart firstElem))
          (e (tr/elementEnd lastElem))]
      (if (or (< s 0) (or (> e (stringLength text)) (> s e)))
        ""
        (optionOr (stringSlice text s e) ""))))

fn collapseCssPatternElements elems: (List tr/TreeElement) patText: String -> (List tr/TreeElement)
  (if (listEmpty? elems)
    (list)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((elemNode n)
         (let [(newKids (collapseCssPatternElements (tr/nodeChildren n) patText))
               (newN (tr/makeNode (tr/nodeKind n) (tr/nodeStart n) (tr/nodeEnd n) newKids))]
           (cons (tr/elemNode newN) (collapseCssPatternElements tl patText))))
        ((elemToken tok)
         (let [(tokStr (elementSliceText patText hd))]
           (if (= tokStr "$")
             (if (listEmpty? tl)
               (cons hd (list))
               (let [(hd2 (optionOr (listHead tl) (tr/elemToken (tr/makeToken "" 0 0))))
                     (tl2 (optionOr (listTail tl) (list)))
                     (str2 (elementSliceText patText hd2))]
                 (if (= str2 "$")
                   (if (listEmpty? tl2)
                     (cons hd (cons hd2 (list)))
                     (let [(hd3 (optionOr (listHead tl2) (tr/elemToken (tr/makeToken "" 0 0))))
                           (tl3 (optionOr (listTail tl2) (list)))
                           (str3 (elementSliceText patText hd3))]
                       (if (= str3 "$")
                         (if (listEmpty? tl3)
                           (cons hd (cons hd2 (cons hd3 (list))))
                           (let [(hd4 (optionOr (listHead tl3) (tr/elemToken (tr/makeToken "" 0 0))))
                                 (tl4 (optionOr (listTail tl3) (list)))
                                 (combinedTok (tr/makeToken "ident" (tr/tokenStart tok) (tr/elementEnd hd4)))]
                             (cons (tr/elemToken combinedTok) (collapseCssPatternElements tl4 patText))))
                         (let [(combinedTok (tr/makeToken "ident" (tr/tokenStart tok) (tr/elementEnd hd3)))]
                           (cons (tr/elemToken combinedTok) (collapseCssPatternElements tl3 patText))))))
                   (let [(combinedTok (tr/makeToken "ident" (tr/tokenStart tok) (tr/elementEnd hd2)))]
                     (cons (tr/elemToken combinedTok) (collapseCssPatternElements tl2 patText))))))
             (cons hd (collapseCssPatternElements tl patText))))))))

fn matchSingleElement pHead: tr/TreeElement tHead: tr/TreeElement patText: String targetText: String bindings: (List Binding) -> (Option (List Binding))
  (let [(pStr (elementSliceText patText pHead))]
    (if (isSingleMetaVar pStr)
      (let [(tStr (elementSliceText targetText tHead))]
        (mt (lookupBinding bindings pStr)
          ((some bound)
           (if (= bound tStr) (some bindings) (none)))
          ((none)
           (some (cons (makeBinding pStr tStr) bindings)))))
      (mt pHead
        ((elemToken pTok)
         (mt tHead
           ((elemToken tTok)
            (let [(tStr (elementSliceText targetText tHead))]
              (if (= pStr tStr) (some bindings) (none))))
           ((elemNode _) (none))))
        ((elemNode pNode)
         (mt tHead
           ((elemToken _) (none))
           ((elemNode tNode)
            (if (!= (tr/nodeKind pNode) (tr/nodeKind tNode))
              (none)
              (let [(pKids (filterNonTrivia (tr/nodeChildren pNode)))
                    (tKids (filterNonTrivia (tr/nodeChildren tNode)))]
                (matchElementsStrict pKids tKids patText targetText bindings)))))))))

fn trySeqMatch varName: String pTail: (List tr/TreeElement) targetList: (List tr/TreeElement) patText: String targetText: String bindings: (List Binding) k: Int64 maxK: Int64 -> (Option (Pair (List tr/TreeElement) (List Binding)))
  (if (> k maxK)
    (none)
    (let [(consumed (optionOr (listSlice targetList 0 k) (list)))
          (rem (optionOr (listSlice targetList k (listLength targetList)) (list)))
          (cText (elementsSpanText targetText consumed))
          (boundOpt (lookupBinding bindings varName))
          (consistent (mt boundOpt
                        ((some b) (= b cText))
                        ((none) true)))]
      (if (not consistent)
        (trySeqMatch varName pTail targetList patText targetText bindings (+ k 1) maxK)
        (let [(nextBindings (mt boundOpt
                              ((some _) bindings)
                              ((none) (cons (makeBinding varName cText) bindings))))
              (recRes (matchElements pTail rem patText targetText nextBindings))]
          (mt recRes
            ((some pairVal)
             (some (pair (listAppend consumed (pairFirst pairVal)) (pairSecond pairVal))))
            ((none)
             (trySeqMatch varName pTail targetList patText targetText bindings (+ k 1) maxK)))))))

fn matchElements patList: (List tr/TreeElement) targetList: (List tr/TreeElement) patText: String targetText: String bindings: (List Binding) -> (Option (Pair (List tr/TreeElement) (List Binding)))
  (if (listEmpty? patList)
    (some (pair (list) bindings))
    (let [(pHead (optionOr (listHead patList) (tr/elemToken (tr/makeToken "" 0 0))))
          (pTail (optionOr (listTail patList) (list)))
          (pStr (elementSliceText patText pHead))]
      (if (isSeqMetaVar pStr)
        (trySeqMatch pStr pTail targetList patText targetText bindings 0 (listLength targetList))
        (if (listEmpty? targetList)
          (none)
          (let [(tHead (optionOr (listHead targetList) (tr/elemToken (tr/makeToken "" 0 0))))
                (tTail (optionOr (listTail targetList) (list)))]
            (mt (matchSingleElement pHead tHead patText targetText bindings)
              ((none) (none))
              ((some nextBindings)
               (mt (matchElements pTail tTail patText targetText nextBindings)
                 ((some pairVal)
                  (some (pair (cons tHead (pairFirst pairVal)) (pairSecond pairVal))))
                 ((none) (none))))))))))

fn matchElementsStrict patList: (List tr/TreeElement) targetList: (List tr/TreeElement) patText: String targetText: String bindings: (List Binding) -> (Option (List Binding))
  (mt (matchElements patList targetList patText targetText bindings)
    ((none) (none))
    ((some pairVal)
     (let [(matched (pairFirst pairVal))]
       (if (= (listLength matched) (listLength targetList))
         (some (pairSecond pairVal))
         (none)))))

fn scanSiblingsLoop kids: (List tr/TreeElement) patElements: (List tr/TreeElement) patText: String targetText: String idx: Int64 maxIdx: Int64 acc: (List Match) -> (List Match)
  (if (>= idx maxIdx)
    acc
    (let [(suffix (optionOr (listSlice kids idx maxIdx) (list)))
          (mRes (matchElements patElements suffix patText targetText (list)))]
      (mt mRes
        ((some pairVal)
         (let [(matched (pairFirst pairVal))
               (bindings (pairSecond pairVal))
               (matchedLen (listLength matched))]
           (if (> matchedLen 0)
             (let [(firstElem (optionOr (listHead matched) (tr/elemToken (tr/makeToken "" 0 0))))
                   (lastElem (optionOr (listLast matched) firstElem))
                   (st (tr/elementStart firstElem))
                   (en (tr/elementEnd lastElem))
                   (mText (elementSliceText targetText firstElem))
                   (fullSpanText (optionOr (stringSlice targetText st en) mText))
                   (m (makeMatch st en fullSpanText bindings))
                   (newAcc (cons m acc))]
               (scanSiblingsLoop kids patElements patText targetText (+ idx matchedLen) maxIdx newAcc))
             (scanSiblingsLoop kids patElements patText targetText (+ idx 1) maxIdx acc))))
        ((none)
         (let [(curElem (optionOr (listGet kids idx) (tr/elemToken (tr/makeToken "" 0 0))))
               (childAcc (mt curElem
                           ((elemNode childNode)
                            (collectMatchesInNode childNode patElements patText targetText acc))
                           ((elemToken _) acc)))]
           (scanSiblingsLoop kids patElements patText targetText (+ idx 1) maxIdx childAcc))))))

fn collectMatchesInNode targetNode: tr/Node patElements: (List tr/TreeElement) patText: String targetText: String acc: (List Match) -> (List Match)
  (let [(nonTriviaKids (filterNonTrivia (tr/nodeChildren targetNode)))]
    (scanSiblingsLoop nonTriviaKids patElements patText targetText 0 (listLength nonTriviaKids) acc))

fn parsePatternElements pattern: String lang: String -> (List tr/TreeElement)
  (cond
    ((or (= lang "asl") (= lang "asn"))
     (let [(root (aslParen/parseString pattern))]
       (if (aslParen/hasErrors root)
         (list)
         (filterNonTrivia (tr/nodeChildren root)))))
    ((or (= lang "javascript") (or (= lang "js") (= lang "jsx")))
     (mt (jsMod/parse pattern)
       ((ok root)
        (let [(kids (filterNonTrivia (tr/nodeChildren root)))]
          (if (and (= (listLength kids) 1) (not (stringEndsWith? (stringTrim pattern) ";")))
            (let [(singleChild (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))]
              (mt singleChild
                ((elemNode sn)
                 (if (or (= (tr/nodeKind sn) "exprStmt") (= (tr/nodeKind sn) "expressionStatement"))
                   (filterNonTrivia (tr/nodeChildren sn))
                   kids))
                ((elemToken _) kids)))
            kids)))
       ((err _) (list))))
    ((or (= lang "typescript") (or (= lang "ts") (= lang "tsx")))
     (mt (tsMod/parse pattern)
       ((ok root)
        (let [(kids (filterNonTrivia (tr/nodeChildren root)))]
          (if (and (= (listLength kids) 1) (not (stringEndsWith? (stringTrim pattern) ";")))
            (let [(singleChild (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))]
              (mt singleChild
                ((elemNode sn)
                 (if (or (= (tr/nodeKind sn) "exprStmt") (= (tr/nodeKind sn) "expressionStatement"))
                   (filterNonTrivia (tr/nodeChildren sn))
                   kids))
                ((elemToken _) kids)))
            kids)))
       ((err _) (list))))
    ((= lang "css")
     (if (stringContains? pattern "{")
       (let [(root (cssRules/parseStylesheet pattern))
             (rawKids (filterNonTrivia (tr/nodeChildren root)))]
         (collapseCssPatternElements rawKids pattern))
       (let [(root (cssRules/parseDeclarationList pattern))
             (rawKids (filterNonTrivia (tr/nodeChildren root)))]
         (collapseCssPatternElements rawKids pattern))))
    (else
     (let [(root (aslParen/parseString pattern))]
       (if (aslParen/hasErrors root)
         (list)
         (filterNonTrivia (tr/nodeChildren root))))))

fn parseSourceNode sourceText: String lang: String -> (Option tr/Node)
  (cond
    ((or (= lang "asl") (= lang "asn"))
     (let [(root (aslParen/parseString sourceText))]
       (if (aslParen/hasErrors root)
         (none)
         (some root))))
    ((or (= lang "javascript") (or (= lang "js") (= lang "jsx")))
     (mt (jsMod/parse sourceText)
       ((ok root) (some root))
       ((err _) (none))))
    ((or (= lang "typescript") (or (= lang "ts") (= lang "tsx")))
     (mt (tsMod/parse sourceText)
       ((ok root) (some root))
       ((err _) (none))))
    ((= lang "css")
     (some (cssRules/parseStylesheet sourceText)))
    (else
     (let [(root (aslParen/parseString sourceText))]
       (if (aslParen/hasErrors root)
         (none)
         (some root)))))

fn findMatches sourceText: String pattern: String lang: String -> (List Match)
  (let [(patElems (parsePatternElements pattern lang))]
    (if (listEmpty? patElems)
      (list)
      (mt (parseSourceNode sourceText lang)
        ((none) (list))
        ((some root)
         (let [(matchesRev (collectMatchesInNode root patElems pattern sourceText (list)))
               (sortedMatches (listSortBy (fn [(m Match)] -> Int64 (matchStart m)) matchesRev))]
           sortedMatches)))))

fn isIdentCode code: Int64 -> Bool
  (or (and (>= code 65) (<= code 90))
  (or (and (>= code 97) (<= code 122))
  (or (and (>= code 48) (<= code 57))
  (or (= code 95)
      (= code 45)))))

fn scanIdentEnd s: String i: Int64 len: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))
          (code (charCode c))]
      (if (isIdentCode code)
        (scanIdentEnd s (+ i 1) len)
        i)))

fn columnAtLoop text: String i: Int64 col: Int64 -> Int64
  (if (< i 0)
    col
    (let [(ch (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (= ch "\n")
        col
        (columnAtLoop text (- i 1) (+ col 1)))))

fn columnAt text: String idx: Int64 -> Int64
  (columnAtLoop text (- idx 1) 0)

fn countLeadingSpaces acc: (List String) count: Int64 -> Int64
  (if (listEmpty? acc)
    count
    (let [(hd (optionOr (listHead acc) ""))]
      (if (= hd " ")
        (countLeadingSpaces (optionOr (listTail acc) (list)) (+ count 1))
        count)))

fn trimEmptyBinding acc: (List String) col: Int64 -> (List String)
  (if (listEmpty? acc)
    acc
    (let [(spCount (countLeadingSpaces acc 0))
          (rest (listDrop acc spCount))]
      (if (and (not (listEmpty? rest)) (= (optionOr (listHead rest) "") "\n"))
        (if (or (= spCount col) (or (= spCount (+ col 2)) (= spCount 2)))
          (listDrop rest 1)
          acc)
        (if (= spCount 1)
          (listDrop acc 1)
          acc))))

fn substituteReplacementLoop tmpl: String i: Int64 len: Int64 bindings: (List Binding) acc: (List String) col: Int64 -> String
  (if (>= i len)
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (stringSlice tmpl i (+ i 1)) ""))]
      (if (!= c "$")
        (substituteReplacementLoop tmpl (+ i 1) len bindings (cons c acc) col)
        (let [(isSeq (and (<= (+ i 3) len) (= (optionOr (stringSlice tmpl i (+ i 3)) "") "$$$")))
              (identStart (if isSeq (+ i 3) (+ i 1)))
              (identEnd (scanIdentEnd tmpl identStart len))]
          (if (= identStart identEnd)
            (substituteReplacementLoop tmpl (+ i 1) len bindings (cons c acc) col)
            (let [(varName (optionOr (stringSlice tmpl i identEnd) ""))
                  (boundOpt (lookupBinding bindings varName))]
              (mt boundOpt
                ((none)
                 (substituteReplacementLoop tmpl identEnd len bindings (cons varName acc) col))
                ((some bVal)
                 (if (= bVal "")
                   (let [(accTrimmed (trimEmptyBinding acc col))]
                     (substituteReplacementLoop tmpl identEnd len bindings accTrimmed col))
                   (substituteReplacementLoop tmpl identEnd len bindings (cons bVal acc) col))))))))))

fn substituteReplacementCol tmpl: String bindings: (List Binding) col: Int64 -> String
  (substituteReplacementLoop tmpl 0 (stringLength tmpl) bindings (list) col)

fn substituteReplacement tmpl: String bindings: (List Binding) -> String
  (substituteReplacementLoop tmpl 0 (stringLength tmpl) bindings (list) 0)

fn applyMatchesLoop text: String matches: (List Match) cur: Int64 replacement: String acc: (List String) -> String
  (if (listEmpty? matches)
    (let [(tailSlice (optionOr (stringSlice text cur (stringLength text)) ""))
          (allSlices (cons tailSlice acc))]
      (stringJoin (listReverse allSlices) ""))
    (let [(m (optionOr (listHead matches) (makeMatch 0 0 "" (list))))
          (restMatches (optionOr (listTail matches) (list)))
          (st (matchStart m))
          (en (matchEnd m))]
      (if (< st cur)
        (applyMatchesLoop text restMatches cur replacement acc)
        (let [(prefix (optionOr (stringSlice text cur st) ""))
              (col (columnAt text st))
              (sub (substituteReplacementCol replacement (matchBindings m) col))
              (newAcc (cons sub (cons prefix acc)))]
          (applyMatchesLoop text restMatches en replacement newAcc)))))

fn rewrite sourceText: String pattern: String replacement: String lang: String -> String
  (let [(matches (findMatches sourceText pattern lang))]
    (if (listEmpty? matches)
      sourceText
      (applyMatchesLoop sourceText matches 0 replacement (list))))

fn rewriteAll sourceText: String rules: (List Rule) lang: String -> String
  (fold (fn [(text String) (r Rule)] -> String
          (rewrite text (rulePattern r) (ruleReplacement r) lang))
        sourceText
        rules)

fn extract sourceText: String pattern: String template: String lang: String -> (List String)
  (let [(matches (findMatches sourceText pattern lang))]
    (map (fn [(m Match)] -> String
           (let [(col (columnAt sourceText (matchStart m)))]
             (substituteReplacementCol template (matchBindings m) col)))
         matches))

fn extractAll sourceText: String extractions: (List Extraction) lang: String -> (List String)
  (listReverse
    (fold (fn [(acc (List String)) (e Extraction)] -> (List String)
            (let [(items (extract sourceText (extractionPattern e) (extractionTemplate e) lang))]
              (listAppend (listReverse items) acc)))
          (list)
          extractions))
