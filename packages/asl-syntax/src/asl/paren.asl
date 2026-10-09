(module asl-syntax/asl/paren
  :x [ParenFrame
      parseStep
      unwindAllFrames
      closerMatchesOpen?
      parseTokens
      parseBytes
      parseSource
      parseString
      parse
      hasErrors
      treeErrors
      isTriviaElement
      topLevelForms
      topLevelFormCount
      countTopLevelForms]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)])

(schema ParenFrame
  (:f kind String)
  (:f openTok tr/Token)
  (:f kids (List tr/TreeElement)))

fn closerMatchesOpen? closerKind: String openKind: String -> Bool
  (or (and (= closerKind "rparen") (= openKind "list"))
  (or (and (= closerKind "rbracket") (= openKind "vector"))
      (and (= closerKind "rbrace") (= openKind "map"))))

fn closerMatchesFrame? closerKind: String frame: ParenFrame -> Bool
  (closerMatchesOpen? closerKind frame.kind)

fn findMatchingFrameDepth stack: (List ParenFrame) closerKind: String depth: Int64 -> (Option Int64)
  (if (listEmpty? stack)
    (none)
    (let [(frame (optionOr (listHead stack) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))
          (rest (optionOr (listTail stack) (list)))]
      (if (closerMatchesFrame? closerKind frame)
        (some depth)
        (findMatchingFrameDepth rest closerKind (+ depth 1)))))

fn lastChildEnd kids: (List tr/TreeElement) fallback: Int64 -> Int64
  (if (listEmpty? kids)
    fallback
    (let [(lastChild (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 fallback))))]
      (tr/elementEnd lastChild)))

fn closeUnclosedFrame frame: ParenFrame -> tr/Node
  (let [(openTok frame.openTok)
        (start openTok.start)
        (end (lastChildEnd frame.kids openTok.end))
        (k frame.kind)
        (expected (cond
                    ((= k "list") ")")
                    ((= k "vector") "]")
                    ((= k "map") "}")
                    (else ")")))
        (mis (tr/makeMissing end expected))
        (allKids (cons (tr/elemToken openTok) (listReverse frame.kids)))]
    (tr/makeErrorNodeWithMissing start end allKids mis))

fn unwindOneStackLevel stack: (List ParenFrame) topKids: (List tr/TreeElement) -> (Pair (List ParenFrame) (List tr/TreeElement))
  (if (listEmpty? stack)
    (pair (list) topKids)
    (let [(top (optionOr (listHead stack) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))
          (rest (optionOr (listTail stack) (list)))
          (errNode (closeUnclosedFrame top))]
      (if (listEmpty? rest)
        (pair (list) (cons (tr/elemNode errNode) topKids))
        (let [(parentFrame (optionOr (listHead rest) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))
              (grandRest (optionOr (listTail rest) (list)))
              (newParentKids (cons (tr/elemNode errNode) parentFrame.kids))
              (newParent (ParenFrame :kind parentFrame.kind :openTok parentFrame.openTok :kids newParentKids))]
          (pair (cons newParent grandRest) topKids)))))

fn unwindStackToDepth stack: (List ParenFrame) topKids: (List tr/TreeElement) targetDepth: Int64 -> (Pair (List ParenFrame) (List tr/TreeElement))
  (if (<= targetDepth 0)
    (pair stack topKids)
    (let [(unwound (unwindOneStackLevel stack topKids))]
      (unwindStackToDepth (pairFirst unwound) (pairSecond unwound) (- targetDepth 1))))

fn unwindAllFrames stack: (List ParenFrame) topKids: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? stack)
    topKids
    (let [(unwound (unwindOneStackLevel stack topKids))]
      (unwindAllFrames (pairFirst unwound) (pairSecond unwound))))

fn addElement stack: (List ParenFrame) topKids: (List tr/TreeElement) elem: tr/TreeElement -> (Pair (List ParenFrame) (List tr/TreeElement))
  (if (listEmpty? stack)
    (pair (list) (cons elem topKids))
    (let [(top (optionOr (listHead stack) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))
          (rest (optionOr (listTail stack) (list)))
          (newTop (ParenFrame :kind top.kind :openTok top.openTok :kids (cons elem top.kids)))]
      (pair (cons newTop rest) topKids)))

fn closeMatchingTopFrame stack: (List ParenFrame) topKids: (List tr/TreeElement) closeTok: tr/Token -> (Pair (List ParenFrame) (List tr/TreeElement))
  (if (listEmpty? stack)
    (let [(errNode (tr/makeErrorNode closeTok.start closeTok.end (list (tr/elemToken closeTok))))]
      (pair (list) (cons (tr/elemNode errNode) topKids)))
    (let [(top (optionOr (listHead stack) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))
          (rest (optionOr (listTail stack) (list)))
          (allKids (cons (tr/elemToken top.openTok)
                         (listReverse (cons (tr/elemToken closeTok) top.kids))))
          (closedNode (tr/makeNode top.kind
                                   top.openTok.start
                                   closeTok.end
                                   allKids))]
      (addElement rest topKids (tr/elemNode closedNode))))

fn isImmediateMismatchFrame? frame: ParenFrame -> Bool
  (listEmpty? (filter (fn [(e tr/TreeElement)] -> Bool
                        (mt e
                          ((tr/elemToken tok) (not (tr/isTrivia tok)))
                          ((tr/elemNode _) true)))
                      frame.kids))

fn handleCloseDelim stack: (List ParenFrame) topKids: (List tr/TreeElement) tok: tr/Token closerKind: String -> (Pair (List ParenFrame) (List tr/TreeElement))
  (if (listEmpty? stack)
    (let [(errNode (tr/makeStrayErrorNode tok.start tok.end (list (tr/elemToken tok))))]
      (pair (list) (cons (tr/elemNode errNode) topKids)))
    (let [(top (optionOr (listHead stack) (ParenFrame :kind "" :openTok (tr/makeToken "" 0 0) :kids (list))))]
      (if (closerMatchesFrame? closerKind top)
        (closeMatchingTopFrame stack topKids tok)
        (mt (findMatchingFrameDepth stack closerKind 0)
          ((some depth)
           (let [(unwound (unwindStackToDepth stack topKids depth))]
             (closeMatchingTopFrame (pairFirst unwound) (pairSecond unwound) tok)))
          ((none)
           (if (isImmediateMismatchFrame? top)
             (let [(rest (optionOr (listTail stack) (list)))
                   (openTok top.openTok)
                   (k top.kind)
                   (expected (cond
                               ((= k "list") ")")
                               ((= k "vector") "]")
                               ((= k "map") "}")
                               (else ")")))
                   (mis (tr/makeMissing tok.start expected))
                   (allKids (cons (tr/elemToken openTok) (listReverse top.kids)))
                   (closedNode (tr/makeErrorNodeWithMissing openTok.start tok.start allKids mis))
                   (strayNode (tr/makeStrayErrorNode tok.start tok.end (list (tr/elemToken tok))))
                   (p1 (addElement rest topKids (tr/elemNode closedNode)))]
               (addElement (pairFirst p1) (pairSecond p1) (tr/elemNode strayNode)))
             (let [(errNode (tr/makeStrayErrorNode tok.start tok.end (list (tr/elemToken tok))))]
               (addElement stack topKids (tr/elemNode errNode)))))))))

fn handleOpenDelim stack: (List ParenFrame) topKids: (List tr/TreeElement) tok: tr/Token kind: String -> (Pair (List ParenFrame) (List tr/TreeElement))
  (pair (cons (ParenFrame :kind kind :openTok tok :kids (list)) stack) topKids)

fn handleErrorToken stack: (List ParenFrame) topKids: (List tr/TreeElement) tok: tr/Token -> (Pair (List ParenFrame) (List tr/TreeElement))
  (let [(errNode (tr/makeErrorNode tok.start tok.end (list (tr/elemToken tok))))]
    (addElement stack topKids (tr/elemNode errNode)))

fn handleLeafToken stack: (List ParenFrame) topKids: (List tr/TreeElement) tok: tr/Token -> (Pair (List ParenFrame) (List tr/TreeElement))
  (addElement stack topKids (tr/elemToken tok))

fn parseStep stack: (List ParenFrame) topKids: (List tr/TreeElement) tok: tr/Token -> (Pair (List ParenFrame) (List tr/TreeElement))
  (let [(k tok.kind)]
    (cond
      ((= k "lparen") (handleOpenDelim stack topKids tok "list"))
      ((= k "lbracket") (handleOpenDelim stack topKids tok "vector"))
      ((= k "lbrace") (handleOpenDelim stack topKids tok "map"))
      ((= k "rparen") (handleCloseDelim stack topKids tok "rparen"))
      ((= k "rbracket") (handleCloseDelim stack topKids tok "rbracket"))
      ((= k "rbrace") (handleCloseDelim stack topKids tok "rbrace"))
      ((= k "error") (handleErrorToken stack topKids tok))
      (else (handleLeafToken stack topKids tok))))

fn parseTokensLoop tokens: (List tr/Token) stack: (List ParenFrame) topKids: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? tokens)
    (unwindAllFrames stack topKids)
    (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail tokens) (list)))
          (res (parseStep stack topKids tok))]
      (parseTokensLoop rest (pairFirst res) (pairSecond res))))

fn parseTokens tokens: (List tr/Token) len: Int64 -> tr/Node
  (let [(topKidsRev (parseTokensLoop tokens (list) (list)))
        (topKids (listReverse topKidsRev))]
    (tr/makeNode "asl" 0 len topKids))

fn parseBytes bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))
        (tokens (lx/tokenizeBytes bs))]
    (parseTokens tokens len))

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

fn countCol0FormsLoop s: src/Source elems: (List tr/TreeElement) count: Int64 -> Int64
  (if (listEmpty? elems)
    count
    (let [(elem (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (rest (optionOr (listTail elems) (list)))
          (startOff (tr/elementStart elem))
          (colOpt (src/sourceByteColAt s startOff))]
      (mt colOpt
        ((some col)
         (if (= col 1)
           (countCol0FormsLoop s rest (+ count 1))
           (countCol0FormsLoop s rest count)))
        ((none)
         (countCol0FormsLoop s rest count)))))

fn countTopLevelForms s: src/Source root: tr/Node -> Int64
  (let [(forms (topLevelForms root))]
    (countCol0FormsLoop s forms 0))
