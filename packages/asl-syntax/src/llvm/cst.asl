(module asl-syntax/llvm/cst
  :x [parseLlvm
      parseLlvmTokens
      moduleFunctions
      moduleDeclarations
      moduleNodes
      functionHeaderTokens
      isTriviaTok
      functionBlocks
      blockInstructions
      instructionTokens
      nonTriviaTokens
      blockLabel
      tokenSlice]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/llvm/lex :a lx)])

fn isOpenBracket k: String -> Bool
  (or (= k "(") (or (= k "[") (= k "{")))

fn isCloseBracket k: String -> Bool
  (or (= k ")") (or (= k "]") (= k "}")))

fn isTriviaTok tok: tr/Token -> Bool
  (tr/isTrivia tok)

fn tokenSlice tok: tr/Token text: String -> String
  (lx/tokenSlice tok text)

fn nonTriviaTokens tokens: (List tr/Token) -> (List tr/Token)
  (listReverse
    (fold (fn [(acc (List tr/Token)) (t tr/Token)] -> (List tr/Token)
            (if (isTriviaTok t)
              acc
              (cons t acc)))
          (list)
          tokens))

fn elemStart elem: tr/TreeElement -> Int64
  (tr/elementStart elem)

fn elemEnd elem: tr/TreeElement -> Int64
  (tr/elementEnd elem)

fn firstElemStart elems: (List tr/TreeElement) fallback: Int64 -> Int64
  (if (listEmpty? elems)
    fallback
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" fallback fallback))))]
      (elemStart hd)))

fn lastElemEnd elems: (List tr/TreeElement) fallback: Int64 -> Int64
  (if (listEmpty? elems)
    fallback
    (let [(rev (listReverse elems))
          (hd (optionOr (listHead rev) (tr/elemToken (tr/makeToken "" fallback fallback))))]
      (elemEnd hd)))

fn makeInstrNode toks: (List tr/Token) -> tr/Node
  (let [(firstTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
        (revToks (listReverse toks))
        (lastTok (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
        (st (tr/tokenStart firstTok))
        (en (tr/tokenEnd lastTok))
        (elems (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) toks))]
    (tr/makeNode "llvmInstruction" st en elems))

fn makeBlockNode elems: (List tr/TreeElement) -> tr/Node
  (let [(st (firstElemStart elems 0))
        (en (lastElemEnd elems 0))]
    (tr/makeNode "llvmBlock" st en elems))

fn makeFuncNode elems: (List tr/TreeElement) -> tr/Node
  (let [(st (firstElemStart elems 0))
        (en (lastElemEnd elems 0))]
    (tr/makeNode "llvmFunction" st en elems))

fn groupInstructions toks: (List tr/Token) accInstr: (List tr/Token) depth: Int64 accElems: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (let [(finalElems (if (listEmpty? accInstr)
                        accElems
                        (cons (tr/elemNode (makeInstrNode (listReverse accInstr))) accElems)))]
      (listReverse finalElems))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (listEmpty? accInstr)
        (if (or (isTriviaTok hd) (= k "label"))
          (groupInstructions tl (list) 0 (cons (tr/elemToken hd) accElems))
          (let [(newDepth (if (isOpenBracket k) 1 (if (isCloseBracket k) -1 0)))]
            (groupInstructions tl (list hd) newDepth accElems)))
        (let [(newDepth (if (isOpenBracket k) (+ depth 1) (if (isCloseBracket k) (- depth 1) depth)))]
          (if (and (<= depth 0) (= k "newline"))
            (let [(instrNode (makeInstrNode (listReverse accInstr)))]
              (groupInstructions tl (list) 0 (cons (tr/elemToken hd) (cons (tr/elemNode instrNode) accElems))))
            (groupInstructions tl (cons hd accInstr) newDepth accElems))))))


fn hasNonTrivia toks: (List tr/Token) -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (isTriviaTok hd)
        (hasNonTrivia tl)
        true)))

fn attachTrailingTrivia blocks: (List tr/TreeElement) triviaToks: (List tr/Token) -> (List tr/TreeElement)
  (if (or (listEmpty? blocks) (listEmpty? triviaToks))
    blocks
    (let [(rev (listReverse blocks))
          (lastElem (optionOr (listHead rev) (tr/elemToken (tr/makeToken "" 0 0))))
          (rest (optionOr (listTail rev) (list)))]
      (mt lastElem
        ((tr/elemToken _) (listAppend blocks (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) triviaToks)))
        ((tr/elemNode bNode)
         (let [(oldChildren (tr/nodeChildren bNode))
               (moreChildren (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) triviaToks))
               (newChildren (listAppend oldChildren moreChildren))
               (st (tr/nodeStart bNode))
               (lastTok (optionOr (listLast triviaToks) (tr/makeToken "" st st)))
               (en (tr/tokenEnd lastTok))
               (newBNode (tr/makeNode "llvmBlock" st en newChildren))]
           (listReverse (cons (tr/elemNode newBNode) rest)))))))

fn splitBlocks toks: (List tr/Token) curBlockToks: (List tr/Token) accBlocks: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (if (listEmpty? curBlockToks)
      (listReverse accBlocks)
      (if (hasNonTrivia curBlockToks)
        (let [(elems (groupInstructions (listReverse curBlockToks) (list) 0 (list)))]
          (listReverse (cons (tr/elemNode (makeBlockNode elems)) accBlocks)))
        (listReverse (attachTrailingTrivia accBlocks (listReverse curBlockToks)))))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (= k "label")
        (if (not (hasNonTrivia curBlockToks))
          (splitBlocks tl (cons hd curBlockToks) accBlocks)
          (let [(elems (groupInstructions (listReverse curBlockToks) (list) 0 (list)))
                (bNode (makeBlockNode elems))]
            (splitBlocks tl (list hd) (cons (tr/elemNode bNode) accBlocks))))
        (splitBlocks tl (cons hd curBlockToks) accBlocks))))

(schema FuncSplit
  (:f header (List tr/Token))
  (:f body (List tr/Token))
  (:f close (Option tr/Token))
  (:f opened Bool)
  (:f rest (List tr/Token)))

fn depthDelta k: String -> Int64
  (if (or (isOpenBracket k) (= k "<"))
    1
    (if (or (isCloseBracket k) (= k ">")) -1 0))

fn collectHeader toks: (List tr/Token) depth: Int64 seenName: Bool acc: (List tr/Token) text: String -> FuncSplit
  (if (listEmpty? toks)
    (FuncSplit :header (listReverse acc) :body (list) :close (none) :opened false :rest (list))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((and seenName (= depth 0) (= k "{"))
         (collectBody tl 1 false (list) (listReverse (cons hd acc)) text))
        ((and seenName (= depth 0) (= k "newline"))
         (FuncSplit :header (listReverse acc) :body (list) :close (none) :opened false :rest toks))
        (else
         (collectHeader tl (+ depth (depthDelta k)) (or seenName (and (= depth 0) (= k "global"))) (cons hd acc) text)))))

fn collectBody toks: (List tr/Token) depth: Int64 lineStart: Bool acc: (List tr/Token) header: (List tr/Token) text: String -> FuncSplit
  (if (listEmpty? toks)
    (FuncSplit :header header :body (listReverse acc) :close (none) :opened true :rest (list))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (txt (tokenSlice hd text))]
      (cond
        ((and (= k "}") (<= depth 1))
         (FuncSplit :header header :body (listReverse acc) :close (some hd) :opened true :rest tl))
        ((and lineStart (= depth 1) (= k "ident") (or (= txt "define") (= txt "declare")))
         (FuncSplit :header header :body (listReverse acc) :close (none) :opened true :rest toks))
        ((= k "{") (collectBody tl (+ depth 1) false (cons hd acc) header text))
        ((= k "}") (collectBody tl (- depth 1) false (cons hd acc) header text))
        ((= k "newline") (collectBody tl depth true (cons hd acc) header text))
        ((isTriviaTok hd) (collectBody tl depth lineStart (cons hd acc) header text))
        (else (collectBody tl depth false (cons hd acc) header text)))))

fn lastSolidEnd toks: (List tr/Token) fallback: Int64 -> Int64
  (fold (fn [(e Int64) (t tr/Token)] -> Int64 (if (isTriviaTok t) e (tr/tokenEnd t))) fallback toks)

fn buildFunctionNode split: FuncSplit -> tr/Node
  (let [(hdr split.header)
        (body split.body)
        (allToks (listAppend hdr body))
        (st (tr/tokenStart (optionOr (listHead allToks) (tr/makeToken "" 0 0))))
        (hdrElems (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) hdr))
        (blockElems (splitBlocks body (list) (list)))
        (missAt (lastSolidEnd allToks st))
        (closeElems (if split.opened
                      (mt split.close
                        ((some c) (list (tr/elemToken c)))
                        ((none) (list (tr/elemNode (tr/makeMissingNode missAt "}")))))
                      (list (tr/elemNode (tr/makeMissingNode missAt "{")))))
        (en (mt split.close
              ((some c) (tr/tokenEnd c))
              ((none) (tr/tokenEnd (optionOr (listLast allToks) (tr/makeToken "" st st))))))]
    (tr/makeNode "llvmFunction" st en (listAppend hdrElems (listAppend blockElems closeElems))))

fn collectLineTokens toks: (List tr/Token) depth: Int64 acc: (List tr/Token) -> (Pair (List tr/Token) (List tr/Token))
  (if (listEmpty? toks)
    (pair (listReverse acc) (list))
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (if (and (<= depth 0) (= k "newline"))
        (pair (listReverse (cons hd acc)) tl)
        (let [(newDepth (if (isOpenBracket k) (+ depth 1) (if (isCloseBracket k) (- depth 1) depth)))]
          (collectLineTokens tl newDepth (cons hd acc))))))

fn makeLineNode kind: String toks: (List tr/Token) -> tr/Node
  (let [(firstTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
        (revToks (listReverse toks))
        (lastTok (optionOr (listHead revToks) (tr/makeToken "" 0 0)))
        (st (tr/tokenStart firstTok))
        (en (tr/tokenEnd lastTok))
        (elems (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) toks))]
    (tr/makeNode kind st en elems))

fn parseModuleLoop toks: (List tr/Token) text: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (listReverse acc)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (txt (tokenSlice hd text))]
      (cond
        ((isTriviaTok hd)
         (parseModuleLoop tl text (cons (tr/elemToken hd) acc)))
        ((or (= txt "define") (= k "define"))
         (let [(split (collectHeader toks 0 false (list) text))
               (fNode (buildFunctionNode split))]
           (parseModuleLoop split.rest text (cons (tr/elemNode fNode) acc))))
        ((or (= txt "declare") (= k "declare"))
         (let [(res (collectLineTokens toks 0 (list)))
               (dToks (pairFirst res))
               (remToks (pairSecond res))
               (dNode (makeLineNode "llvmDeclare" dToks))]
           (parseModuleLoop remToks text (cons (tr/elemNode dNode) acc))))
        (else
         (let [(res (collectLineTokens toks 0 (list)))
               (gToks (pairFirst res))
               (remToks (pairSecond res))
               (kind (lineKind (nonTriviaTokens gToks) text))
               (gNode (if (= kind "error")
                        (tr/makeErrorNode (tr/tokenStart hd) (tr/tokenEnd (optionOr (listLast gToks) hd))
                                          (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) gToks))
                        (makeLineNode kind gToks)))]
           (parseModuleLoop remToks text (cons (tr/elemNode gNode) acc)))))))

fn lineKind toks: (List tr/Token) text: String -> String
  (let [(t0 (optionOr (listGet toks 0) (tr/makeToken "" 0 0)))
        (t1 (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))
        (t2 (optionOr (listGet toks 2) (tr/makeToken "" 0 0)))
        (k0 (tr/tokenKind t0))
        (s0 (tokenSlice t0 text))
        (isAssign (= (tr/tokenKind t1) "="))]
    (cond
      ((listContains? (list "source_filename" "target" "attributes" "module" "uselistorder" "uselistorder_bb") s0) "llvmGlobal")
      ((and (= k0 "global") isAssign) "llvmGlobal")
      ((and (= k0 "local") isAssign (= (tokenSlice t2 text) "type")) "llvmTypeDef")
      ((and (= k0 "metadata") isAssign) "llvmMetadata")
      ((and (= s0 "$") (= (tr/tokenKind t1) "ident")) "llvmGlobal")
      (else "error")))

fn parseLlvmTokens tokens: (List tr/Token) text: String -> tr/Node
  (let [(elems (parseModuleLoop tokens text (list)))
        (len (stringLength text))]
    (tr/makeNode "llvmModule" 0 len elems))

fn parseLlvm text: String -> tr/Node
  (parseLlvmTokens (lx/tokenize text) text)

fn moduleFunctions root: tr/Node -> (List tr/Node)
  (listReverse
    (fold (fn [(acc (List tr/Node)) (elem tr/TreeElement)] -> (List tr/Node)
            (mt elem
              ((tr/elemToken _) acc)
              ((tr/elemNode n)
               (if (= (tr/nodeKind n) "llvmFunction")
                 (cons n acc)
                 acc))))
          (list)
          (tr/nodeChildren root)))

fn moduleNodes root: tr/Node -> (List tr/Node)
  (listReverse
    (fold (fn [(acc (List tr/Node)) (elem tr/TreeElement)] -> (List tr/Node)
            (mt elem
              ((tr/elemToken _) acc)
              ((tr/elemNode n) (cons n acc))))
          (list)
          (tr/nodeChildren root)))

fn functionHeaderTokens funcNode: tr/Node -> (List tr/Token)
  (listReverse
    (pairSecond
      (fold (fn [(st (Pair Bool (List tr/Token))) (elem tr/TreeElement)] -> (Pair Bool (List tr/Token))
              (if (pairFirst st)
                st
                (mt elem
                  ((tr/elemNode _) (pair true (pairSecond st)))
                  ((tr/elemToken t) (pair false (cons t (pairSecond st)))))))
            (pair false (list))
            (tr/nodeChildren funcNode))))

fn moduleDeclarations root: tr/Node -> (List tr/Node)
  (listReverse
    (fold (fn [(acc (List tr/Node)) (elem tr/TreeElement)] -> (List tr/Node)
            (mt elem
              ((tr/elemToken _) acc)
              ((tr/elemNode n)
               (if (= (tr/nodeKind n) "llvmDeclare")
                 (cons n acc)
                 acc))))
          (list)
          (tr/nodeChildren root)))

fn functionBlocks funcNode: tr/Node -> (List tr/Node)
  (listReverse
    (fold (fn [(acc (List tr/Node)) (elem tr/TreeElement)] -> (List tr/Node)
            (mt elem
              ((tr/elemToken _) acc)
              ((tr/elemNode n)
               (if (= (tr/nodeKind n) "llvmBlock")
                 (cons n acc)
                 acc))))
          (list)
          (tr/nodeChildren funcNode)))

fn blockInstructions blockNode: tr/Node -> (List tr/Node)
  (listReverse
    (fold (fn [(acc (List tr/Node)) (elem tr/TreeElement)] -> (List tr/Node)
            (mt elem
              ((tr/elemToken _) acc)
              ((tr/elemNode n)
               (if (= (tr/nodeKind n) "llvmInstruction")
                 (cons n acc)
                 acc))))
          (list)
          (tr/nodeChildren blockNode)))

fn instructionTokens instrNode: tr/Node -> (List tr/Token)
  (tr/nodeLeaves instrNode)

fn blockLabel blockNode: tr/Node text: String -> String
  (let [(elems (tr/nodeChildren blockNode))]
    (let [(found (fold (fn [(acc String) (el tr/TreeElement)] -> String
                         (if (!= acc "")
                           acc
                           (mt el
                             ((tr/elemNode _) "")
                             ((tr/elemToken t)
                              (if (= (tr/tokenKind t) "label")
                                (let [(raw (tokenSlice t text))]
                                  (if (stringEndsWith? raw ":")
                                    (optionOr (stringSlice raw 0 (- (stringLength raw) 1)) raw)
                                    raw))
                                "")))))
                       ""
                       elems))]
      found))
