(module asl-forms/query
  :x [QueryPattern
      QueryCapture
      QueryMatch
      makeQueryPattern
      makeQueryCapture
      makeQueryMatch
      patternKind
      patternCapture
      patternText
      patternChildren
      queryPatternKindDummy
      queryCaptureGet
      captureName
      captureValue
      captureText
      captureStart
      captureEnd
      captureLine
      captureCol
      queryCompile
      queryExecute
      validateSemver
      validateCron
      lintUnboundReferences
      lintDuplicateDefinitions
      lintValueFormatSemver
      lintValueFormatCron
      lintReceipt]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/paren :a prn)
      (asl-syntax/asl/layout :a lay)
      (asl-syntax/asl/symbols :a aslsym)
      (asl-forms/repair :a rep)])

(schema QueryPattern
  (:f kind String)
  (:f capture String)
  (:f text String)
  (:f optional Bool)
  (:f children (List QueryPattern)))

(schema QueryCapture
  (:f name String)
  (:f value String)
  (:f text String)
  (:f start Int64)
  (:f end Int64)
  (:f line Int64)
  (:f col Int64))

(schema QueryMatch
  (:f pattern QueryPattern)
  (:f captures (List QueryCapture)))

fn makeQueryPattern kind: String capture: String text: String children: (List QueryPattern) -> QueryPattern
  (QueryPattern :kind kind :capture capture :text text :optional false :children children)

fn patternKind p: QueryPattern -> String
  p.kind

fn patternCapture p: QueryPattern -> String
  p.capture

fn patternText p: QueryPattern -> String
  p.text

fn patternChildren p: QueryPattern -> (List QueryPattern)
  p.children

fn queryPatternKindDummy -> QueryPattern
  (QueryPattern :kind "dummy" :capture "" :text "" :optional false :children (list))

fn makeQueryCapture name: String value: String text: String start: Int64 end: Int64 line: Int64 col: Int64 -> QueryCapture
  (QueryCapture :name name :value value :text text :start start :end end :line line :col col)

fn captureName c: QueryCapture -> String
  c.name

fn captureValue c: QueryCapture -> String
  c.value

fn captureText c: QueryCapture -> String
  c.text

fn captureStart c: QueryCapture -> Int64
  c.start

fn captureEnd c: QueryCapture -> Int64
  c.end

fn captureLine c: QueryCapture -> Int64
  c.line

fn captureCol c: QueryCapture -> Int64
  c.col

fn makeQueryMatch pattern: QueryPattern captures: (List QueryCapture) -> QueryMatch
  (QueryMatch :pattern pattern :captures captures)

fn findCaptureByName caps: (List QueryCapture) name: String -> (Option QueryCapture)
  (if (listEmpty? caps)
    (none)
    (let [(head (optionOr (listHead caps) (QueryCapture :name "" :value "" :text "" :start 0 :end 0 :line 0 :col 0)))
          (tail (optionOr (listTail caps) (list)))]
      (if (= head.name name)
        (some head)
        (findCaptureByName tail name))))

fn queryCaptureGet match: QueryMatch name: String -> (Option QueryCapture)
  (findCaptureByName match.captures name)

fn unquote s: String -> String
  (let [(n (stringLength s))]
    (if (and (>= n 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))
      (optionOr (stringSlice s 1 (- n 1)) "")
      s))

fn elementKind elem: tr/TreeElement -> String
  (mt elem
    ((tr/elemToken tok) tok.kind)
    ((tr/elemNode node) node.kind))

fn elementStart elem: tr/TreeElement -> Int64
  (mt elem
    ((tr/elemToken tok) tok.start)
    ((tr/elemNode node) node.start))

fn elementEnd elem: tr/TreeElement -> Int64
  (mt elem
    ((tr/elemToken tok) tok.end)
    ((tr/elemNode node) node.end))

fn elementRawText text: String elem: tr/TreeElement -> String
  (let [(s (elementStart elem))
        (e (elementEnd elem))]
    (optionOr (stringSlice text s e) ""))

fn elementValue text: String elem: tr/TreeElement -> String
  (unquote (elementRawText text elem))

fn isTriviaOrDelim elem: tr/TreeElement -> Bool
  (mt elem
    ((tr/elemToken tok)
     (let [(k tok.kind)]
       (or (tr/isTriviaToken tok)
       (or (= k "lparen") (or (= k "rparen")
       (or (= k "lbracket") (or (= k "rbracket")
       (or (= k "lbrace") (= k "rbrace")))))))))
    ((tr/elemNode _) false))

fn filterMeaningful elements: (List tr/TreeElement) -> (List tr/TreeElement)
  (filter (fn [(elem tr/TreeElement)] -> Bool (not (isTriviaOrDelim elem))) elements)

fn findKeywordValue kids: (List tr/TreeElement) key: String text: String -> String
  (if (listEmpty? kids)
    ""
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))]
      (if (and (= (elementKind head) "keyword") (= (elementRawText text head) key))
        (if (listEmpty? tail)
          ""
          (let [(valElem (optionOr (listHead tail) head))]
            (elementValue text valElem)))
        (findKeywordValue tail key text))))

fn findKeywordVectorNode kids: (List tr/TreeElement) key: String text: String -> (Option tr/Node)
  (if (listEmpty? kids)
    (none)
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))]
      (if (and (= (elementKind head) "keyword") (= (elementRawText text head) key))
        (if (listEmpty? tail)
          (none)
          (let [(nextElem (optionOr (listHead tail) head))]
            (mt nextElem
              ((tr/elemNode n) (some n))
              ((tr/elemToken _) (findKeywordVectorNode tail key text)))))
        (findKeywordVectorNode tail key text))))

fn parseAsnQueryNode node: tr/Node text: String -> QueryPattern
  (let [(kids (filterMeaningful node.children))
        (kind (findKeywordValue kids ":kind" text))
        (capture (findKeywordValue kids ":as" text))
        (textVal (findKeywordValue kids ":text" text))
        (optVal (findKeywordValue kids ":optional" text))
        (isOpt (= optVal "true"))
        (childrenVecOpt (findKeywordVectorNode kids ":children" text))]
    (mt childrenVecOpt
      ((some vecNode)
       (let [(vecKids (filterMeaningful vecNode.children))
             (childPats (parseAsnChildList vecKids text (list)))]
         (QueryPattern :kind kind :capture capture :text textVal :optional isOpt :children childPats)))
      ((none)
       (QueryPattern :kind kind :capture capture :text textVal :optional isOpt :children (list)))))

fn parseAsnChildList kids: (List tr/TreeElement) text: String acc: (List QueryPattern) -> (List QueryPattern)
  (if (listEmpty? kids)
    (listReverse acc)
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))]
      (mt head
        ((tr/elemNode n)
         (let [(pat (parseAsnQueryNode n text))]
           (parseAsnChildList tail text (cons pat acc))))
        ((tr/elemToken _)
         (parseAsnChildList tail text acc)))))

fn parseSexprPatternNode node: tr/Node text: String -> QueryPattern
  (let [(kids (filterMeaningful node.children))]
    (if (listEmpty? kids)
      (QueryPattern :kind "" :capture "" :text "" :optional false :children (list))
      (let [(firstElem (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
            (kind (elementValue text firstElem))
            (remKids (optionOr (listTail kids) (list)))]
        (parseSexprPatternLoop remKids text kind "" "" (list)))))

fn parseSexprPatternLoop kids: (List tr/TreeElement) text: String kind: String capture: String textVal: String accKids: (List QueryPattern) -> QueryPattern
  (if (listEmpty? kids)
    (QueryPattern :kind kind :capture capture :text textVal :optional false :children (listReverse accKids))
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))]
      (mt head
        ((tr/elemToken tok)
         (let [(tokVal (elementRawText text head))]
           (if (stringStartsWith? tokVal "@")
             (if (listEmpty? accKids)
               (parseSexprPatternLoop tail text kind tokVal textVal accKids)
               (let [(lastChild (optionOr (listHead accKids) (queryPatternKindDummy)))
                     (updatedLast (QueryPattern :kind lastChild.kind :capture tokVal :text lastChild.text :optional lastChild.optional :children lastChild.children))
                     (restKids (optionOr (listTail accKids) (list)))]
                 (parseSexprPatternLoop tail text kind capture textVal (cons updatedLast restKids))))
             (if (= tokVal "?")
               (if (listEmpty? accKids)
                 (parseSexprPatternLoop tail text kind capture textVal accKids)
                 (let [(lastChild (optionOr (listHead accKids) (queryPatternKindDummy)))
                       (updatedLast (QueryPattern :kind lastChild.kind :capture lastChild.capture :text lastChild.text :optional true :children lastChild.children))
                       (restKids (optionOr (listTail accKids) (list)))]
                   (parseSexprPatternLoop tail text kind capture textVal (cons updatedLast restKids))))
               (parseSexprPatternLoop tail text kind capture (unquote tokVal) accKids)))))
        ((tr/elemNode childNode)
         (let [(childPat (parseSexprPatternNode childNode text))]
           (parseSexprPatternLoop tail text kind capture textVal (cons childPat accKids)))))))

fn queryCompile input: String -> QueryPattern
  (let [(trimmed (stringTrim input))]
    (if (stringStartsWith? trimmed "(:")
      (let [(root (prn/parseString trimmed))
            (forms (prn/topLevelForms root))]
        (if (listEmpty? forms)
          (queryPatternKindDummy)
          (let [(f (optionOr (listHead forms) (tr/elemNode root)))]
            (mt f
              ((tr/elemNode n) (parseAsnQueryNode n trimmed))
              ((tr/elemToken _) (queryPatternKindDummy))))))
      (let [(root (prn/parseString trimmed))
            (forms (prn/topLevelForms root))]
        (if (listEmpty? forms)
          (queryPatternKindDummy)
          (let [(f (optionOr (listHead forms) (tr/elemNode root)))]
            (mt f
              ((tr/elemNode n) (parseSexprPatternNode n trimmed))
              ((tr/elemToken _) (queryPatternKindDummy))))))))


fn isLanguageKeyword kw: String -> Bool
  (listContains? (list "fn" "module" "schema" "enum" "macro" "test" "type" "let" "if" "cond" "mt" "do" "assert") kw)

fn kindMatches pat: QueryPattern elem: tr/TreeElement text: String -> Bool
  (let [(patKind pat.kind)
        (eKind (elementKind elem))]
    (if (= patKind "keyword")
      (if (= eKind "keyword")
        true
        (if (= eKind "symbol")
          (isLanguageKeyword (elementRawText text elem))
          false))
      (if (= patKind "symbol")
        (if (!= eKind "symbol")
          false
          (if (and (= pat.text "") (= (elementRawText text elem) "!"))
            false
            true))
        (= patKind eKind))))

fn matchElement pat: QueryPattern elem: tr/TreeElement text: String -> Bool
  (if (not (kindMatches pat elem text))
    false
    (if (and (!= pat.text "") (and (!= (elementRawText text elem) pat.text) (!= (elementValue text elem) pat.text)))
      false
      (let [(pKids pat.children)]
        (if (listEmpty? pKids)
          true
          (mt elem
            ((tr/elemToken _) false)
            ((tr/elemNode node)
             (let [(elemKids (filterMeaningful node.children))]
               (sublistMatches elemKids 0 pKids text))))))))

fn sublistMatches elemKids: (List tr/TreeElement) idx: Int64 pKids: (List QueryPattern) text: String -> Bool
  (let [(nElem (listLength elemKids))]
    (if (> idx nElem)
      false
      (if (allPatternsMatch elemKids idx 0 pKids text)
        true
        (sublistMatches elemKids (+ idx 1) pKids text))))

fn allPatternsMatch elemKids: (List tr/TreeElement) eIdx: Int64 pIdx: Int64 pKids: (List QueryPattern) text: String -> Bool
  (let [(nPat (listLength pKids))
        (nElem (listLength elemKids))]
    (if (>= pIdx nPat)
      true
      (let [(pat (optionOr (listGet pKids pIdx) (queryPatternKindDummy)))]
        (if pat.optional
          (if (and (< eIdx nElem) (matchElement pat (optionOr (listGet elemKids eIdx) (tr/elemToken (tr/makeToken "" 0 0))) text))
            (if (allPatternsMatch elemKids (+ eIdx 1) (+ pIdx 1) pKids text)
              true
              (allPatternsMatch elemKids eIdx (+ pIdx 1) pKids text))
            (allPatternsMatch elemKids eIdx (+ pIdx 1) pKids text))
          (if (>= eIdx nElem)
            false
            (let [(elem (optionOr (listGet elemKids eIdx) (tr/elemToken (tr/makeToken "" 0 0))))]
              (if (matchElement pat elem text)
                (allPatternsMatch elemKids (+ eIdx 1) (+ pIdx 1) pKids text)
                false)))))))

fn findMatchingSublistIdx elemKids: (List tr/TreeElement) idx: Int64 pKids: (List QueryPattern) text: String -> Int64
  (let [(nElem (listLength elemKids))]
    (if (> idx nElem)
      -1
      (if (allPatternsMatch elemKids idx 0 pKids text)
        idx
        (findMatchingSublistIdx elemKids (+ idx 1) pKids text))))

fn makeCaptureFromElem capName: String elem: tr/TreeElement text: String s: src/Source -> QueryCapture
  (let [(start (elementStart elem))
        (end (elementEnd elem))
        (raw (elementRawText text elem))
        (val (elementValue text elem))
        (posOpt (src/sourcePosAt s start))
        (line (mt posOpt ((some p) p.line) ((none) 1)))
        (col (mt posOpt ((some p) p.byteCol) ((none) 1)))]
    (QueryCapture :name capName :value val :text raw :start start :end end :line line :col col))

fn collectChildCaptures elemKids: (List tr/TreeElement) eIdx: Int64 pIdx: Int64 pKids: (List QueryPattern) text: String s: src/Source acc: (List QueryCapture) -> (List QueryCapture)
  (let [(nPat (listLength pKids))
        (nElem (listLength elemKids))]
    (if (>= pIdx nPat)
      (listReverse acc)
      (let [(pat (optionOr (listGet pKids pIdx) (queryPatternKindDummy)))]
        (if pat.optional
          (if (and (< eIdx nElem) (and (matchElement pat (optionOr (listGet elemKids eIdx) (tr/elemToken (tr/makeToken "" 0 0))) text) (allPatternsMatch elemKids (+ eIdx 1) (+ pIdx 1) pKids text)))
            (let [(childElem (optionOr (listGet elemKids eIdx) (tr/elemToken (tr/makeToken "" 0 0))))
                  (caps (collectCaptures pat childElem text s))
                  (newAcc (listAppend (listReverse caps) acc))]
              (collectChildCaptures elemKids (+ eIdx 1) (+ pIdx 1) pKids text s newAcc))
            (collectChildCaptures elemKids eIdx (+ pIdx 1) pKids text s acc))
          (let [(childElem (optionOr (listGet elemKids eIdx) (tr/elemToken (tr/makeToken "" 0 0))))
                (caps (collectCaptures pat childElem text s))
                (newAcc (listAppend (listReverse caps) acc))]
            (collectChildCaptures elemKids (+ eIdx 1) (+ pIdx 1) pKids text s newAcc))))))

fn collectCaptures pat: QueryPattern elem: tr/TreeElement text: String s: src/Source -> (List QueryCapture)
  (let [(topCap (if (!= pat.capture "")
                  (list (makeCaptureFromElem pat.capture elem text s))
                  (list)))
        (pKids pat.children)]
    (if (listEmpty? pKids)
      topCap
      (mt elem
        ((tr/elemToken _) topCap)
        ((tr/elemNode node)
         (let [(elemKids (filterMeaningful node.children))
               (matchIdx (findMatchingSublistIdx elemKids 0 pKids text))]
           (if (< matchIdx 0)
             topCap
             (let [(childCaps (collectChildCaptures elemKids matchIdx 0 pKids text s (list)))]
               (listAppend topCap childCaps))))))))

fn traverseKids kids: (List tr/TreeElement) pat: QueryPattern text: String s: src/Source acc: (List QueryMatch) -> (List QueryMatch)
  (if (listEmpty? kids)
    acc
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))]
      (mt head
        ((tr/elemNode n)
         (let [(nextAcc (traverseMatches n pat text s acc))]
           (traverseKids tail pat text s nextAcc)))
        ((tr/elemToken _)
         (traverseKids tail pat text s acc)))))

fn traverseMatches node: tr/Node pat: QueryPattern text: String s: src/Source acc: (List QueryMatch) -> (List QueryMatch)
  (let [(elem (tr/elemNode node))
        (curAcc (if (matchElement pat elem text)
                  (cons (QueryMatch :pattern pat :captures (collectCaptures pat elem text s)) acc)
                  acc))
        (kids node.children)]
    (traverseKids kids pat text s curAcc))

fn queryExecute queryStr: String text: String lang: String -> (List QueryMatch)
  (let [(pat (queryCompile queryStr))
        (s (src/sourceFromString "<query>" text))
        (root (if (= lang "asl") (lay/parseString text) (prn/parseString text)))
        (matchesRev (traverseMatches root pat text s (list)))]
    (listReverse matchesRev))

fn isAsciiDigit c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isAllDigits s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0)
      false
      (isAllDigitsLoop s 0 n)))

fn isAllDigitsLoop s: String idx: Int64 len: Int64 -> Bool
  (if (>= idx len)
    true
    (let [(c (optionOr (stringSlice s idx (+ idx 1)) ""))]
      (if (isAsciiDigit c)
        (isAllDigitsLoop s (+ idx 1) len)
        false)))

fn validateSemverPart p: String -> Bool
  (let [(n (stringLength p))]
    (if (= n 0)
      false
      (if (not (isAllDigits p))
        false
        (if (and (> n 1) (stringStartsWith? p "0"))
          false
          true))))

fn validatePrereleaseId id: String -> Bool
  (let [(n (stringLength id))]
    (if (= n 0)
      false
      (if (isAllDigits id)
        (if (and (> n 1) (stringStartsWith? id "0"))
          false
          true)
        (isAlphanumericOrHyphen id 0 n))))

fn isAlphanumericOrHyphen s: String idx: Int64 len: Int64 -> Bool
  (if (>= idx len)
    true
    (let [(c (optionOr (stringSlice s idx (+ idx 1)) ""))]
      (if (or (isAsciiDigit c) (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (= c "-"))))
        (isAlphanumericOrHyphen s (+ idx 1) len)
        false)))

fn validatePrerelease s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (if (listEmpty? parts)
      false
      (allPrereleaseIdsValid parts)))

fn allPrereleaseIdsValid parts: (List String) -> Bool
  (if (listEmpty? parts)
    true
    (let [(h (optionOr (listHead parts) ""))
          (tail (optionOr (listTail parts) (list)))]
      (if (validatePrereleaseId h)
        (allPrereleaseIdsValid tail)
        false)))

fn validateBuildMetadata s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (if (listEmpty? parts)
      false
      (allBuildIdsValid parts)))

fn allBuildIdsValid parts: (List String) -> Bool
  (if (listEmpty? parts)
    true
    (let [(h (optionOr (listHead parts) ""))
          (tail (optionOr (listTail parts) (list)))
          (n (stringLength h))]
      (if (or (= n 0) (not (isAlphanumericOrHyphen h 0 n)))
        false
        (allBuildIdsValid tail))))

fn validateSemver s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0)
      false
      (let [(firstChar (optionOr (stringSlice s 0 1) ""))]
        (if (not (isAsciiDigit firstChar))
          false
          (let [(hasPlus (stringContains? s "+"))
                (noBuild (if hasPlus
                           (let [(parts (stringSplit s "+"))]
                             (if (!= (listLength parts) 2)
                               (none)
                               (let [(rest (optionOr (listGet parts 0) ""))
                                     (build (optionOr (listGet parts 1) ""))]
                                 (if (validateBuildMetadata build)
                                   (some rest)
                                   (none)))))
                           (some s)))]
            (mt noBuild
              ((none) false)
              ((some sNoBuild)
               (let [(hasHyphen (stringContains? sNoBuild "-"))
                     (coreOpt (if hasHyphen
                                (let [(hyphenIdx (optionOr (stringIndexOf sNoBuild "-") -1))]
                                  (if (< hyphenIdx 0)
                                    (none)
                                    (let [(corePart (optionOr (stringSlice sNoBuild 0 hyphenIdx) ""))
                                          (prePart (optionOr (stringSlice sNoBuild (+ hyphenIdx 1) (stringLength sNoBuild)) ""))]
                                      (if (validatePrerelease prePart)
                                        (some corePart)
                                        (none)))))
                                (some sNoBuild)))]
                 (mt coreOpt
                   ((none) false)
                   ((some core)
                    (let [(coreParts (stringSplit core "."))]
                      (if (!= (listLength coreParts) 3)
                        false
                        (let [(major (optionOr (listGet coreParts 0) ""))
                              (minor (optionOr (listGet coreParts 1) ""))
                              (patch (optionOr (listGet coreParts 2) ""))]
                          (and (validateSemverPart major) (and (validateSemverPart minor) (validateSemverPart patch))))))))))))))))

fn splitWords s: String -> (List String)
  (let [(parts (stringSplit s " "))]
    (filter (fn [(w String)] -> Bool (not (stringEmpty? (stringTrim w)))) parts))

fn validateCronItem item: String min: Int64 max: Int64 -> Bool
  (if (= item "*")
    true
    (if (stringStartsWith? item "*/")
      (let [(stepStr (optionOr (stringSlice item 2 (stringLength item)) ""))
            (stepOpt (stringToInt64 stepStr))]
        (mt stepOpt
          ((some step) (and (> step 0) (<= step max)))
          ((none) false)))
      (if (stringContains? item "-")
        (let [(rParts (stringSplit item "-"))]
          (if (!= (listLength rParts) 2)
            false
            (let [(startOpt (stringToInt64 (optionOr (listGet rParts 0) "")))
                  (endOpt (stringToInt64 (optionOr (listGet rParts 1) "")))]
              (mt startOpt
                ((some start)
                 (mt endOpt
                   ((some end) (and (>= start min) (and (<= start end) (<= end max))))
                   ((none) false)))
                ((none) false)))))
        (let [(numOpt (stringToInt64 item))]
          (mt numOpt
            ((some num) (and (>= num min) (<= num max)))
            ((none) false))))))

fn allCronItemsValid items: (List String) min: Int64 max: Int64 -> Bool
  (if (listEmpty? items)
    true
    (let [(h (optionOr (listHead items) ""))
          (tail (optionOr (listTail items) (list)))]
      (if (validateCronItem h min max)
        (allCronItemsValid tail min max)
        false)))

fn validateCronField text: String min: Int64 max: Int64 -> Bool
  (let [(trimmed (stringTrim text))]
    (if (stringEmpty? trimmed)
      false
      (let [(items (stringSplit trimmed ","))]
        (if (listEmpty? items)
          false
          (allCronItemsValid items min max)))))

fn validateCron s: String -> Bool
  (let [(trimmed (stringTrim s))]
    (if (stringEmpty? trimmed)
      false
      (let [(fields (splitWords trimmed))]
        (if (!= (listLength fields) 5)
          false
          (let [(fMin (optionOr (listGet fields 0) ""))
                (fHour (optionOr (listGet fields 1) ""))
                (fDom (optionOr (listGet fields 2) ""))
                (fMonth (optionOr (listGet fields 3) ""))
                (fDow (optionOr (listGet fields 4) ""))]
            (and (validateCronField fMin 0 59)
            (and (validateCronField fHour 0 23)
            (and (validateCronField fDom 1 31)
            (and (validateCronField fMonth 1 12)
                 (validateCronField fDow 0 7))))))))))

fn nearSnippet text: String s: src/Source line: Int64 col: Int64 -> String
  (mt (src/sourceLineStart s line)
    ((some start)
     (let [(end (src/sourceLineEnd s line))
           (lineStr (optionOr (stringSlice text start end) ""))
           (lineLen (stringLength lineStr))]
       (if (<= lineLen 60)
         lineStr
         (let [(startIdx (if (<= col 40)
                           0
                           (if (> (+ (- col 30) 60) lineLen)
                             (- lineLen 60)
                             (- col 30))))
               (sub (optionOr (stringSlice lineStr startIdx (+ startIdx 60)) ""))]
           sub))))
    ((none) ""))

fn escapeAsnString s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))
        (s3 (stringReplace s2 "\n" "\\n"))
        (s4 (stringReplace s3 "\r" "\\r"))]
    s4)

fn formatLeftItem item: rep/LeftItem -> String
  (str "(:line " (stringFromInt64 (rep/leftItemLine item)) " :col " (stringFromInt64 (rep/leftItemCol item)) " :expected \"" (escapeAsnString (rep/leftItemExpected item)) "\" :near \"" (escapeAsnString (rep/leftItemNear item)) "\")")

fn formatLeftList items: (List rep/LeftItem) -> String
  (if (listEmpty? items)
    "()"
    (let [(n (listLength items))]
      (if (<= n 5)
        (str "(" (stringJoin (map formatLeftItem items) " ") ")")
        (let [(first5 (listTake items 5))
              (rem (- n 5))]
          (str "(" (stringJoin (map formatLeftItem first5) " ") " :more " (stringFromInt64 rem) ")")))))

fn lintValueFormatSemver text: String lang: String -> (List rep/LeftItem)
  (let [(matches (queryExecute "(list (keyword \":version\") (string) @ver)" text lang))
        (s (src/sourceFromString "<input>" text))]
    (collectSemverLintItems matches text s (list)))

fn collectSemverLintItems matches: (List QueryMatch) text: String s: src/Source acc: (List rep/LeftItem) -> (List rep/LeftItem)
  (if (listEmpty? matches)
    (listReverse acc)
    (let [(head (optionOr (listHead matches) (QueryMatch :pattern (queryPatternKindDummy) :captures (list))))
          (tail (optionOr (listTail matches) (list)))
          (cOpt (queryCaptureGet head "@ver"))]
      (mt cOpt
        ((none) (collectSemverLintItems tail text s acc))
        ((some c)
         (let [(val (captureValue c))]
           (if (validateSemver val)
             (collectSemverLintItems tail text s acc)
             (let [(line (captureLine c))
                   (col (captureCol c))
                   (expected (str "invalid semver format '" val "'"))
                   (near (nearSnippet text s line col))
                   (item (rep/makeLeftItem line col expected near))]
               (collectSemverLintItems tail text s (cons item acc)))))))))

fn lintValueFormatCron text: String lang: String -> (List rep/LeftItem)
  (let [(matches (queryExecute "(list (keyword \":cron\") (string) @cron)" text lang))
        (s (src/sourceFromString "<input>" text))]
    (collectCronLintItems matches text s (list)))

fn collectCronLintItems matches: (List QueryMatch) text: String s: src/Source acc: (List rep/LeftItem) -> (List rep/LeftItem)
  (if (listEmpty? matches)
    (listReverse acc)
    (let [(head (optionOr (listHead matches) (QueryMatch :pattern (queryPatternKindDummy) :captures (list))))
          (tail (optionOr (listTail matches) (list)))
          (cOpt (queryCaptureGet head "@cron"))]
      (mt cOpt
        ((none) (collectCronLintItems tail text s acc))
        ((some c)
         (let [(val (captureValue c))]
           (if (validateCron val)
             (collectCronLintItems tail text s acc)
             (let [(line (captureLine c))
                   (col (captureCol c))
                   (expected (str "invalid cron expression '" val "'"))
                   (near (nearSnippet text s line col))
                   (item (rep/makeLeftItem line col expected near))]
               (collectCronLintItems tail text s (cons item acc)))))))))

fn lintDuplicateDefinitions text: String lang: String -> (List rep/LeftItem)
  (let [(s (src/sourceFromString "<input>" text))]
    (if (= lang "asl")
      (lintDuplicateAsl text s)
      (lintDuplicateAsn text s)))

fn lintDuplicateAsl text: String s: src/Source -> (List rep/LeftItem)
  (let [(mFn (queryExecute "(header (keyword \"fn\") (symbol \"!\")? (symbol) @name)" text "asl"))
        (mSchema (queryExecute "(header (keyword \"schema\") (symbol) @name)" text "asl"))
        (mEnum (queryExecute "(header (keyword \"enum\") (symbol) @name)" text "asl"))
        (mMacro (queryExecute "(header (keyword \"macro\") (symbol) @name)" text "asl"))
        (allMatches (listAppend mFn (listAppend mSchema (listAppend mEnum mMacro))))]
    (collectDuplicateItems allMatches "@name" text s (list) (list)))

fn lintDuplicateAsn text: String s: src/Source -> (List rep/LeftItem)
  (let [(mStr (queryExecute "(list (keyword \":unit\") (keyword \":id\") (string) @id)" text "asn"))
        (mSym (queryExecute "(list (keyword \":unit\") (keyword \":id\") (symbol) @id)" text "asn"))
        (allMatches (listAppend mStr mSym))]
    (collectDuplicateItems allMatches "@id" text s (list) (list)))

fn collectDuplicateItems matches: (List QueryMatch) capName: String text: String s: src/Source seen: (List String) acc: (List rep/LeftItem) -> (List rep/LeftItem)
  (if (listEmpty? matches)
    (listReverse acc)
    (let [(head (optionOr (listHead matches) (QueryMatch :pattern (queryPatternKindDummy) :captures (list))))
          (tail (optionOr (listTail matches) (list)))
          (cOpt (queryCaptureGet head capName))]
      (mt cOpt
        ((none) (collectDuplicateItems tail capName text s seen acc))
        ((some c)
         (let [(name (captureValue c))]
           (if (listContains? seen name)
             (let [(line (captureLine c))
                   (col (captureCol c))
                   (expected (str "duplicate definition '" name "'"))
                   (near (nearSnippet text s line col))
                   (item (rep/makeLeftItem line col expected near))]
               (collectDuplicateItems tail capName text s seen (cons item acc)))
             (collectDuplicateItems tail capName text s (cons name seen) acc)))))))

fn collectDefinedIds matches: (List QueryMatch) acc: (List String) -> (List String)
  (if (listEmpty? matches)
    acc
    (let [(head (optionOr (listHead matches) (QueryMatch :pattern (queryPatternKindDummy) :captures (list))))
          (tail (optionOr (listTail matches) (list)))
          (cOpt (queryCaptureGet head "@id"))]
      (mt cOpt
        ((some c) (collectDefinedIds tail (cons (captureValue c) acc)))
        ((none) (collectDefinedIds tail acc)))))

fn lintUnboundReferences text: String lang: String -> (List rep/LeftItem)
  (let [(s (src/sourceFromString "<input>" text))
        (m1 (queryExecute "(list (keyword \":id\") (string) @id)" text lang))
        (m2 (queryExecute "(list (keyword \":id\") (symbol) @id)" text lang))
        (allIdMatches (listAppend m1 m2))
        (definedIds (collectDefinedIds allIdMatches (list)))
        (depMatches (queryExecute "(list (keyword \":dependsOn\") (list) @deps)" text lang))]
    (collectUnboundItems depMatches definedIds text s (list)))

fn collectUnboundItems matches: (List QueryMatch) definedIds: (List String) text: String s: src/Source acc: (List rep/LeftItem) -> (List rep/LeftItem)
  (if (listEmpty? matches)
    (listReverse acc)
    (let [(head (optionOr (listHead matches) (QueryMatch :pattern (queryPatternKindDummy) :captures (list))))
          (tail (optionOr (listTail matches) (list)))
          (cOpt (queryCaptureGet head "@deps"))]
      (mt cOpt
        ((none) (collectUnboundItems tail definedIds text s acc))
        ((some c)
         (let [(start (captureStart c))
               (end (captureEnd c))
               (sliceStr (optionOr (stringSlice text start end) ""))
               (innerRoot (prn/parseString sliceStr))
               (forms (prn/topLevelForms innerRoot))]
           (if (listEmpty? forms)
             (collectUnboundItems tail definedIds text s acc)
             (let [(formNode (optionOr (listHead forms) (tr/elemToken (tr/makeToken "" 0 0))))]
               (mt formNode
                 ((tr/elemToken _) (collectUnboundItems tail definedIds text s acc))
                 ((tr/elemNode n)
                  (let [(kids (filterMeaningful n.children))
                        (unboundInDep (checkDepKids kids definedIds sliceStr start text s (list)))]
                    (collectUnboundItems tail definedIds text s (listAppend (listReverse unboundInDep) acc))))))))))))

fn checkDepKids kids: (List tr/TreeElement) definedIds: (List String) sliceText: String baseOffset: Int64 fullText: String s: src/Source acc: (List rep/LeftItem) -> (List rep/LeftItem)
  (if (listEmpty? kids)
    (listReverse acc)
    (let [(head (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail kids) (list)))
          (refName (elementValue sliceText head))]
      (if (or (stringEmpty? refName) (listContains? definedIds refName))
        (checkDepKids tail definedIds sliceText baseOffset fullText s acc)
        (let [(relStart (elementStart head))
              (absStart (+ baseOffset relStart))
              (posOpt (src/sourcePosAt s absStart))
              (line (mt posOpt ((some p) p.line) ((none) 1)))
              (col (mt posOpt ((some p) p.byteCol) ((none) 1)))
              (expected (str "unbound reference '" refName "'"))
              (near (nearSnippet fullText s line col))
              (item (rep/makeLeftItem line col expected near))]
          (checkDepKids tail definedIds sliceText baseOffset fullText s (cons item acc))))))

fn lintReceipt text: String lang: String -> String
  (let [(unbound (lintUnboundReferences text lang))
        (dups (lintDuplicateDefinitions text lang))
        (semver (lintValueFormatSemver text lang))
        (cron (lintValueFormatCron text lang))
        (all (listAppend unbound (listAppend dups (listAppend semver cron))))]
    (str "(:left " (formatLeftList all) ")"))
