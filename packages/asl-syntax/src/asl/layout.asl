(module asl-syntax/asl/layout
  :x [parseTokens
      parseBytes
      parseSource
      parseString
      parse
      hasErrors
      treeErrors
      topLevelForms
      topLevelFormCount
      countTopLevelForms
      lowerTopForm!
      lowerForms
      lowerSource
      lowerString lowerTopFormText]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/paren :a prn)
      (asl-parser/reader :a rd)
      (asl-parser/indentParser :a ip)
      (asl-parser/ast :a a)])

(schema ParenFormSplitResult
  (:f formToks (List tr/Token))
  (:f remaining (List tr/Token)))

fn takeParenFormTokens toks: (List tr/Token) depth: Int64 acc: (List tr/Token) -> ParenFormSplitResult
  (if (listEmpty? toks)
    (ParenFormSplitResult :formToks (listReverse acc) :remaining (list))
    (let [(t (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail toks) (list)))
          (k t.kind)
          (isOpen (or (= k "lparen") (or (= k "lbracket") (= k "lbrace"))))
          (isClose (or (= k "rparen") (or (= k "rbracket") (= k "rbrace"))))
          (dInc (if isOpen 1 0))
          (dDec (if isClose 1 0))
          (newDepth (- (+ depth dInc) dDec))
          (newAcc (cons t acc))]
      (if (<= newDepth 0)
        (ParenFormSplitResult :formToks (listReverse newAcc) :remaining rest)
        (takeParenFormTokens rest newDepth newAcc))))

(schema SplitTriviaResult
  (:f declToks (List tr/Token))
  (:f trailing (List tr/Token)))

fn findFirstNonTriviaIndex revToks: (List tr/Token) idx: Int64 -> Int64
  (if (listEmpty? revToks)
    -1
    (let [(t (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail revToks) (list)))]
      (if (tr/isTrivia t)
        (findFirstNonTriviaIndex rest (+ idx 1))
        idx)))

fn findNewlineAfterNonTrivia revToks: (List tr/Token) curIdx: Int64 targetIdx: Int64 foundNl: Int64 -> Int64
  (if (>= curIdx targetIdx)
    foundNl
    (let [(t (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail revToks) (list)))
          (newNl (if (= t.kind "newline") curIdx foundNl))]
      (findNewlineAfterNonTrivia rest (+ curIdx 1) targetIdx newNl)))

fn splitTrailingTrivia revToks: (List tr/Token) -> SplitTriviaResult
  (let [(firstNonTrivia (findFirstNonTriviaIndex revToks 0))]
    (if (< firstNonTrivia 0)
      (SplitTriviaResult :declToks (list) :trailing (listReverse revToks))
      (let [(nlIdx (findNewlineAfterNonTrivia revToks 0 firstNonTrivia -1))]
        (if (< nlIdx 0)
          (SplitTriviaResult :declToks (listReverse revToks) :trailing (list))
          (let [(cutIdx nlIdx)
                (trailingRev (optionOr (listSlice revToks 0 cutIdx) (list)))
                (cleanRev (optionOr (listSlice revToks cutIdx (listLength revToks)) (list)))]
            (SplitTriviaResult :declToks (listReverse cleanRev) :trailing (listReverse trailingRev)))))))

(schema DeclCollectResult
  (:f declToks (List tr/Token))
  (:f remaining (List tr/Token))
  (:f curLineStart Int64))

fn collectDeclTokens toks: (List tr/Token) depth: Int64 curLineStart: Int64 isFirst: Bool acc: (List tr/Token) -> DeclCollectResult
  (if (listEmpty? toks)
    (let [(splitRes (splitTrailingTrivia acc))]
      (DeclCollectResult :declToks splitRes.declToks :remaining splitRes.trailing :curLineStart curLineStart))
    (let [(t (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail toks) (list)))
          (k t.kind)
          (isNl (= k "newline"))
          (nxtLineStart (if isNl t.end curLineStart))
          (isCol0 (= t.start curLineStart))
          (isTrivia (tr/isTrivia t))
          (isOpen (or (= k "lparen") (or (= k "lbracket") (= k "lbrace"))))
          (isClose (or (= k "rparen") (or (= k "rbracket") (= k "rbrace"))))
          (nxtDepth (if isOpen (+ depth 1) (if isClose (if (> depth 0) (- depth 1) 0) depth)))]
      (if (and (not isFirst) (and (= depth 0) (and isCol0 (not isTrivia))))
        (let [(splitRes (splitTrailingTrivia acc))
              (remWithTrailing (listAppend splitRes.trailing toks))]
          (DeclCollectResult :declToks splitRes.declToks :remaining remWithTrailing :curLineStart curLineStart))
        (collectDeclTokens rest nxtDepth nxtLineStart false (cons t acc)))))

(schema HeaderSplitResult
  (:f headerToks (List tr/Token))
  (:f headerNl (Option tr/Token))
  (:f bodyToks (List tr/Token)))

fn lastNonTriviaKind toks: (List tr/Token) -> String
  (let [(nonTrivia (filter (fn [(t tr/Token)] -> Bool (not (tr/isTrivia t))) toks))]
    (mt (listLast nonTrivia)
      ((some t) t.kind)
      ((none) "")))

fn endsInLbrace? toks: (List tr/Token) -> Bool
  (= (lastNonTriviaKind toks) "lbrace")

fn popPostBrace revToks: (List tr/Token) acc: (List tr/Token) -> (Pair (List tr/Token) (List tr/Token))
  (if (listEmpty? revToks)
    (pair (list) (listReverse acc))
    (let [(t (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail revToks) (list)))]
      (if (= t.kind "lbrace")
        (pair rest (cons t (listReverse acc)))
        (popPostBrace rest (cons t acc)))))

fn popPreBrace revToks: (List tr/Token) acc: (List tr/Token) -> (Pair (List tr/Token) (List tr/Token))
  (if (listEmpty? revToks)
    (pair (list) (listReverse acc))
    (let [(t (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail revToks) (list)))]
      (if (tr/isTrivia t)
        (popPreBrace rest (cons t acc))
        (pair revToks (listReverse acc)))))

fn splitHeaderBrace lineToks: (List tr/Token) nl: tr/Token rest: (List tr/Token) -> HeaderSplitResult
  (let [(revToks (listReverse lineToks))
        (p1 (popPostBrace revToks (list)))
        (afterBraceToks (pairFirst p1))
        (braceAndPost (pairSecond p1))
        (p2 (popPreBrace afterBraceToks (list)))
        (hToksRev (pairFirst p2))
        (preBrace (pairSecond p2))
        (hToks (listReverse hToksRev))
        (bPrefix (listAppend preBrace braceAndPost))
        (bToks (listAppend bPrefix (cons nl rest)))]
    (HeaderSplitResult :headerToks hToks :headerNl (none) :bodyToks bToks))

fn splitHeaderAndBody toks: (List tr/Token) acc: (List tr/Token) -> HeaderSplitResult
  (if (listEmpty? toks)
    (HeaderSplitResult :headerToks (listReverse acc) :headerNl (none) :bodyToks (list))
    (let [(t (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail toks) (list)))]
      (if (= t.kind "newline")
        (let [(lineToks (listReverse acc))]
          (if (endsInLbrace? lineToks)
            (splitHeaderBrace lineToks t rest)
            (HeaderSplitResult :headerToks lineToks :headerNl (some t) :bodyToks rest)))
        (splitHeaderAndBody rest (cons t acc)))))

fn lastTokenEnd toks: (List tr/Token) fallback: Int64 -> Int64
  (mt (listLast toks)
    ((some t) t.end)
    ((none) fallback))

fn declKindFromBytes bs: Bytes tok: tr/Token -> String
  (let [(len (bytesLength bs))
        (s tok.start)
        (e tok.end)
        (tlen (- e s))]
    (if (or (<= len 0) (> e len))
      "fn"
      (cond
        ((and (= tlen 2) (and (= (bytesGet bs s) 102) (= (bytesGet bs (+ s 1)) 110))) "fn")
        ((and (= tlen 3) (and (= (bytesGet bs s) 102) (and (= (bytesGet bs (+ s 1)) 110) (= (bytesGet bs (+ s 2)) 33)))) "fn")
        ((and (= tlen 6) (and (= (bytesGet bs s) 115) (and (= (bytesGet bs (+ s 1)) 99) (= (bytesGet bs (+ s 2)) 104)))) "schema")
        ((and (= tlen 4) (and (= (bytesGet bs s) 101) (and (= (bytesGet bs (+ s 1)) 110) (= (bytesGet bs (+ s 2)) 117)))) "enum")
        (else "decl"))))

fn parseLayoutLoop bs: Bytes tokens: (List tr/Token) curLineStart: Int64 topKidsAcc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? tokens)
    (listReverse topKidsAcc)
    (let [(t (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail tokens) (list)))
          (k t.kind)
          (isNl (= k "newline"))
          (nxtLineStart (if isNl t.end curLineStart))]
      (if (tr/isTrivia t)
        (parseLayoutLoop bs rest nxtLineStart (cons (tr/elemToken t) topKidsAcc))
        (let [(isCol0 (= t.start curLineStart))]
          (if isCol0
            (if (or (= k "lparen") (or (= k "lbracket") (= k "lbrace")))
              (let [(splitRes (takeParenFormTokens tokens 0 (list)))
                    (formToks splitRes.formToks)
                    (remToks splitRes.remaining)
                    (formFirst (optionOr (listHead formToks) t))
                    (formLast (optionOr (listLast formToks) t))
                    (formLen (- formLast.end formFirst.start))
                    (subNode (prn/parseTokens formToks formLen))
                    (subForms (prn/topLevelForms subNode))]
                (mt (listHead subForms)
                  ((some formElem)
                   (parseLayoutLoop bs remToks nxtLineStart (cons formElem topKidsAcc)))
                  ((none)
                   (parseLayoutLoop bs remToks nxtLineStart (cons (tr/elemNode subNode) topKidsAcc)))))
              (let [(collectRes (collectDeclTokens tokens 0 curLineStart true (list)))
                    (declToks collectRes.declToks)
                    (remToks collectRes.remaining)
                    (afterLineStart collectRes.curLineStart)]
                (if (listEmpty? declToks)
                  (parseLayoutLoop bs remToks afterLineStart (cons (tr/elemToken t) topKidsAcc))
                  (let [(hSplit (splitHeaderAndBody declToks (list)))
                        (hToks hSplit.headerToks)
                        (hNl hSplit.headerNl)
                        (bToks hSplit.bodyToks)
                        (hFirst (optionOr (listHead hToks) t))
                        (hStart hFirst.start)
                        (hEnd (lastTokenEnd hToks hStart))
                        (hKids (prn/parseTokens hToks (- hEnd hStart)).children)
                        (headerNode (tr/makeNode "header" hStart hEnd hKids))
                        (declKind (declKindFromBytes bs hFirst))]
                    (if (listEmpty? bToks)
                      (let [(dEnd (mt hNl ((some nl) nl.end) ((none) hEnd)))
                            (kids (mt hNl ((some nl) (list (tr/elemNode headerNode) (tr/elemToken nl))) ((none) (list (tr/elemNode headerNode)))))
                            (declNode (tr/makeNode declKind hStart dEnd kids))]
                        (parseLayoutLoop bs remToks afterLineStart (cons (tr/elemNode declNode) topKidsAcc)))
                      (let [(bFirst (optionOr (listHead bToks) t))
                            (bLast (optionOr (listLast bToks) t))
                            (bStart bFirst.start)
                            (bEnd bLast.end)
                            (bKids (prn/parseTokens bToks (- bEnd bStart)).children)
                            (bodyNode (tr/makeNode "body" bStart bEnd bKids))
                            (kids (mt hNl ((some nl) (list (tr/elemNode headerNode) (tr/elemToken nl) (tr/elemNode bodyNode))) ((none) (list (tr/elemNode headerNode) (tr/elemNode bodyNode)))))
                            (declNode (tr/makeNode declKind hStart bEnd kids))]
                        (parseLayoutLoop bs remToks afterLineStart (cons (tr/elemNode declNode) topKidsAcc))))))))
            (parseLayoutLoop bs rest nxtLineStart (cons (tr/elemToken t) topKidsAcc)))))))

fn parseTokensWithBytes tokens: (List tr/Token) len: Int64 bs: Bytes -> tr/Node
  (let [(topKids (parseLayoutLoop bs tokens 0 (list)))]
    (tr/makeNode "asl" 0 len topKids))

fn parseTokens tokens: (List tr/Token) len: Int64 -> tr/Node
  (parseTokensWithBytes tokens len (bytesAlloc 0))

fn parseBytes bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))
        (tokens (lx/tokenizeBytes bs))]
    (parseTokensWithBytes tokens len bs))

fn parseSource s: src/Source -> tr/Node
  (parseBytes (src/sourceBytes s))

fn parseString text: String -> tr/Node
  (parseBytes (stringToBytes text))

fn parse text: String -> tr/Node
  (parseString text)

fn collectErrorsInElement elem: tr/TreeElement acc: (List tr/Node) -> (List tr/Node)
  (mt elem
    ((elemToken tok)
     (if (tr/isErrorToken tok)
       (cons (tr/makeErrorNode tok.start tok.end (list (tr/elemToken tok))) acc)
       acc))
    ((elemNode node)
     (collectErrorsInNode node acc)))

fn collectErrorsInChildren children: (List tr/TreeElement) acc: (List tr/Node) -> (List tr/Node)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectErrorsInChildren tail (collectErrorsInElement head acc))))

fn collectErrorsInNode node: tr/Node acc: (List tr/Node) -> (List tr/Node)
  (let [(kidsAcc (collectErrorsInChildren node.children acc))]
    (if (tr/isErrorNode node)
      (cons node kidsAcc)
      kidsAcc))

fn treeErrors root: tr/Node -> (List tr/Node)
  (listReverse (collectErrorsInNode root (list)))

fn hasErrors root: tr/Node -> Bool
  (not (listEmpty? (treeErrors root)))

fn isTriviaElement elem: tr/TreeElement -> Bool
  (mt elem
    ((elemToken tok) (tr/isTrivia tok))
    ((elemNode _) false))

fn topLevelForms root: tr/Node -> (List tr/TreeElement)
  (filter (fn [(e tr/TreeElement)] -> Bool (not (isTriviaElement e))) root.children)

fn topLevelFormCount root: tr/Node -> Int64
  (listLength (topLevelForms root))

fn countTopLevelForms s: src/Source root: tr/Node -> Int64
  (topLevelFormCount root)

fn escapeFormLoop text: String len: Int64 i: Int64 state: Int64 acc: (List String) -> String
  (if (>= i len)
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))
          (isNl (= c "\n"))
          (isQuote (= c "\""))
          (isSlash (= c "\\"))
          (isSemi (= c ";"))]
      (cond
        ((= state 1)
         (if isNl
           (escapeFormLoop text len (+ i 1) 0 (cons c acc))
           (escapeFormLoop text len (+ i 1) 1 (cons c acc))))
        ((= state 2)
         (cond
           (isSlash
            (escapeFormLoop text len (+ i 1) 3 (cons c acc)))
           (isQuote
            (escapeFormLoop text len (+ i 1) 0 (cons c acc)))
           (isNl
            (escapeFormLoop text len (+ i 1) 2 (cons "\\n" acc)))
           (else
            (escapeFormLoop text len (+ i 1) 2 (cons c acc)))))
        ((= state 3)
         (escapeFormLoop text len (+ i 1) 2 (cons c acc)))
        (else
         (cond
           (isSemi
            (escapeFormLoop text len (+ i 1) 1 (cons c acc)))
           (isQuote
            (escapeFormLoop text len (+ i 1) 2 (cons c acc)))
           (else
            (escapeFormLoop text len (+ i 1) 0 (cons c acc))))))))

fn escapeFormStringNewlines text: String -> String
  (let [(len (stringLength text))]
    (escapeFormLoop text len 0 0 (list)))

fn formScanMultiline bs: Bytes end: Int64 i: Int64 state: Int64 -> Bool
  (if (>= i end)
    false
    (let [(b (bytesGet bs i))
          (isNl (= b 10))
          (isQuote (= b 34))
          (isSlash (= b 92))
          (isSemi (= b 59))]
      (cond
        ((= state 1)
         (if isNl
           (formScanMultiline bs end (+ i 1) 0)
           (formScanMultiline bs end (+ i 1) 1)))
        ((= state 2)
         (cond
           (isSlash
            (formScanMultiline bs end (+ i 1) 3))
           (isQuote
            (formScanMultiline bs end (+ i 1) 0))
           (isNl
            true)
           (else
            (formScanMultiline bs end (+ i 1) 2))))
        ((= state 3)
         (formScanMultiline bs end (+ i 1) 2))
        (else
         (cond
           (isSemi
            (formScanMultiline bs end (+ i 1) 1))
           (isQuote
            (formScanMultiline bs end (+ i 1) 2))
           (else
            (formScanMultiline bs end (+ i 1) 0)))))))

fn formHasMultilineString? bs: Bytes -> Bool
  (formScanMultiline bs (bytesLength bs) 0 0)


fn lowerTopFormText text: String node: tr/Node -> (Result rd/SExpr String)
  (if (hasErrors node)
    (err "form contains syntax errors")
    (let [(formText (optionOr (stringSlice text node.start node.end) ""))
          (formBs (stringToBytes formText))
          (escapedText (if (formHasMultilineString? formBs) (escapeFormStringNewlines formText) formText))
          (cleanText (a/joinFnHeader escapedText))]
      (mt (ip/parseIndented cleanText)
        ((ok form) (ok (ip/stripInferredUnit form)))
        ((err e) (err e)))))

fn lowerTopForm! s: src/Source node: tr/Node -> (Result rd/SExpr String)
  (if (hasErrors node)
    (err "form contains syntax errors")
    (let [(bs (src/sourceBytes s))
          (formBs (lx/tokenSliceBytes! bs (tr/makeToken "" node.start node.end)))]
      (err "use lowerTopFormText with text")))

fn lowerFormsList text: String forms: (List tr/TreeElement) acc: (List rd/SExpr) -> (Result (List rd/SExpr) String)
  (if (listEmpty? forms)
    (ok (listReverse acc))
    (let [(elem (optionOr (listHead forms) (tr/elemToken (tr/makeToken "" 0 0))))
          (rest (optionOr (listTail forms) (list)))]
      (mt elem
        ((elemNode node)
         (mt (lowerTopFormText text node)
           ((ok sexpr) (lowerFormsList text rest (cons sexpr acc)))
           ((err msg) (err msg))))
        ((elemToken _)
         (lowerFormsList text rest acc)))))

fn lowerForms root: tr/Node text: String -> (Result (List rd/SExpr) String)
  (if (hasErrors root)
    (err "CST contains syntax errors")
    (lowerFormsList text (topLevelForms root) (list)))

fn lowerString text: String -> (Result (List rd/SExpr) String)
  (let [(root (parse text))]
    (lowerForms root text))

fn lowerSource s: src/Source -> (Result (List rd/SExpr) String)
  (lowerForms (parseSource s) "")
