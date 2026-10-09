(module asl-syntax/llvm/validate
  :x [Item
      makeItem
      itemKind
      itemLine
      itemCol
      itemExpected
      itemNear
      formatLeftItem
      formatLeftList
      formatReceipt
      llvmValidate]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/llvm/lex :a lx)
      (asl-syntax/llvm/cst :a cst)])

(schema Item
  (:f kind String)
  (:f line Int64)
  (:f col Int64)
  (:f expected String)
  (:f near String))

fn makeItem kind: String line: Int64 col: Int64 expected: String near: String -> Item
  (Item :kind kind :line line :col col :expected expected :near near)

fn itemKind item: Item -> String
  item.kind

fn itemLine item: Item -> Int64
  item.line

fn itemCol item: Item -> Int64
  item.col

fn itemExpected item: Item -> String
  item.expected

fn itemNear item: Item -> String
  item.near

fn escapeAsnString s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))
        (s3 (stringReplace s2 "\n" "\\n"))
        (s4 (stringReplace s3 "\r" "\\r"))]
    s4)

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

fn formatLeftItem item: Item -> String
  (str "(:kind \"" (escapeAsnString item.kind) "\" :line " (stringFromInt64 item.line) " :col " (stringFromInt64 item.col) " :expected \"" (escapeAsnString item.expected) "\" :near \"" (escapeAsnString item.near) "\")")

fn formatLeftList items: (List Item) -> String
  (if (listEmpty? items)
    "()"
    (let [(n (listLength items))]
      (if (<= n 5)
        (str "(" (stringJoin (map formatLeftItem items) " ") ")")
        (let [(first5 (listTake items 5))
              (rem (- n 5))]
          (str "(" (stringJoin (map formatLeftItem first5) " ") " :more " (stringFromInt64 rem) ")")))))

fn formatReceipt items: (List Item) -> String
  (str "(:left " (formatLeftList items) ")")

fn makeItemAt text: String s: src/Source offset: Int64 expected: String -> Item
  (let [(posOpt (src/sourcePosAt s offset))
        (line (mt posOpt ((some p) p.line) ((none) 1)))
        (col (mt posOpt ((some p) p.byteCol) ((none) 1)))
        (near (nearSnippet text s line col))]
    (makeItem "llvm" line col expected near))

fn isTerminator op: String -> Bool
  (or (= op "ret")
  (or (= op "br")
  (or (= op "switch")
  (or (= op "indirectbr")
  (or (= op "invoke")
  (or (= op "resume")
  (or (= op "unreachable")
  (or (= op "cleanupret")
  (or (= op "catchret")
      (= op "catchswitch"))))))))))

fn instructionDest instrNode: tr/Node text: String -> (Option String)
  (let [(toks (cst/nonTriviaTokens (cst/instructionTokens instrNode)))]
    (if (>= (listLength toks) 2)
      (let [(t0 (optionOr (listGet toks 0) (tr/makeToken "" 0 0)))
            (t1 (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))]
        (if (and (= (tr/tokenKind t0) "local") (= (tr/tokenKind t1) "="))
          (some (cst/tokenSlice t0 text))
          (none)))
      (none)))

fn instructionOpcode instrNode: tr/Node text: String -> String
  (let [(toks (cst/nonTriviaTokens (cst/instructionTokens instrNode)))]
    (if (listEmpty? toks)
      ""
      (let [(t0 (optionOr (listGet toks 0) (tr/makeToken "" 0 0)))
            (s0 (cst/tokenSlice t0 text))]
        (if (and (= (tr/tokenKind t0) "local") (>= (listLength toks) 2))
          (let [(t1 (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))]
            (if (= (tr/tokenKind t1) "=")
              (let [(t2 (optionOr (listGet toks 2) (tr/makeToken "" 0 0)))
                    (s2 (cst/tokenSlice t2 text))]
                (if (or (= s2 "musttail") (= s2 "tail"))
                  "call"
                  s2))
              s0))
          (if (or (= s0 "musttail") (= s0 "tail"))
            "call"
            s0)))))

(schema ParamShape
  (:f names (List String))
  (:f fixed Int64)
  (:f vararg Bool)
  (:f nextNumber Int64))

(schema Use
  (:f role String)
  (:f tok tr/Token)
  (:f pred String))

(schema Scan
  (:f uses (List Use))
  (:f prev String)
  (:f depth Int64)
  (:f addrDepth Int64)
  (:f inIncoming Bool)
  (:f afterComma Bool)
  (:f pending (List tr/Token)))

(schema Cfg
  (:f names (List String))
  (:f rpoNum (List Int64))
  (:f idom (List Int64)))

(schema BlockState
  (:f seenNonPhi Bool)
  (:f local (List String))
  (:f seen (List String))
  (:f items (List Item)))

fn depthDelta k: String -> Int64
  (if (or (= k "(") (or (= k "[") (or (= k "{") (= k "<"))))
    1
    (if (or (= k ")") (or (= k "]") (or (= k "}") (= k ">")))) -1 0))

fn isNumberedName name: String -> Bool
  (and (stringStartsWith? name "%")
       (some? (stringToInt64 (optionOr (stringSlice name 1 (stringLength name)) "x"))))

fn finishSegment shape: ParamShape segLocal: String segCount: Int64 segDots: Bool -> ParamShape
  (cond
    ((= segCount 0) shape)
    ((and segDots (= segCount 1))
     (with shape :vararg true))
    ((= segLocal "")
     (with shape :names (cons (str "%" (stringFromInt64 shape.nextNumber)) shape.names) :fixed (+ shape.fixed 1) :nextNumber (+ shape.nextNumber 1)))
    ((isNumberedName segLocal)
     (with shape :names (cons segLocal shape.names) :fixed (+ shape.fixed 1) :nextNumber (+ shape.nextNumber 1)))
    (else
     (with shape :names (cons segLocal shape.names) :fixed (+ shape.fixed 1))))

fn scanParams toks: (List tr/Token) text: String depth: Int64 segLocal: String segCount: Int64 segDots: Bool shape: ParamShape -> ParamShape
  (if (listEmpty? toks)
    (finishSegment shape segLocal segCount segDots)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))]
      (cond
        ((cst/isTriviaTok hd) (scanParams tl text depth segLocal segCount segDots shape))
        ((= depth 0)
         (if (= k "(")
           (scanParams tl text 1 "" 0 false shape)
           (scanParams tl text 0 segLocal segCount segDots shape)))
        ((and (= depth 1) (= k ")")) (finishSegment shape segLocal segCount segDots))
        ((and (= depth 1) (= k ","))
         (scanParams tl text 1 "" 0 false (finishSegment shape segLocal segCount segDots)))
        ((and (= depth 1) (and (= k "local") (> segCount 0)))
         (scanParams tl text 1 (cst/tokenSlice hd text) (+ segCount 1) segDots shape))
        ((and (= depth 1) (= (cst/tokenSlice hd text) "..."))
         (scanParams tl text 1 segLocal (+ segCount 1) true shape))
        (else (scanParams tl text (+ depth (depthDelta k)) segLocal (+ segCount 1) segDots shape)))))

fn afterFirstGlobal toks: (List tr/Token) text: String -> (Option (Pair String (List tr/Token)))
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (= (tr/tokenKind hd) "global")
        (some (pair (cst/tokenSlice hd text) tl))
        (afterFirstGlobal tl text))))

fn headerShape toks: (List tr/Token) text: String -> (Option (Pair String ParamShape))
  (mt (afterFirstGlobal toks text)
    ((none) (none))
    ((some p)
     (some (pair (pairFirst p)
                 (listReverseNames (scanParams (pairSecond p) text 0 "" 0 false (ParamShape :names (list) :fixed 0 :vararg false :nextNumber 0)))))))

fn listReverseNames shape: ParamShape -> ParamShape
  (with shape :names (listReverse shape.names))

fn findCallee toks: (List tr/Token) depth: Int64 -> (Option (Pair tr/Token (List tr/Token)))
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (k (tr/tokenKind hd))
          (nextKind (tr/tokenKind (optionOr (listHead tl) (tr/makeToken "" 0 0))))]
      (if (and (= depth 0) (or (= k "global") (= k "local")) (= nextKind "("))
        (some (pair hd tl))
        (findCallee tl (+ depth (depthDelta k))))))

fn afterCallKeyword toks: (List tr/Token) text: String -> (List tr/Token)
  (if (listEmpty? toks)
    (list)
    (let [(hd (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail toks) (list)))
          (txt (cst/tokenSlice hd text))]
      (if (and (= (tr/tokenKind hd) "ident") (or (= txt "call") (= txt "invoke")))
        tl
        (afterCallKeyword tl text))))

fn collectModulePrototypes root: tr/Node text: String -> (List (Pair String ParamShape))
  (fold (fn [(acc (List (Pair String ParamShape))) (n tr/Node)] -> (List (Pair String ParamShape))
          (let [(k (tr/nodeKind n))
                (toks (if (= k "llvmFunction") (cst/functionHeaderTokens n) (tr/nodeLeaves n)))]
            (if (or (= k "llvmFunction") (= k "llvmDeclare"))
              (mt (headerShape (cst/nonTriviaTokens toks) text)
                ((none) acc)
                ((some p) (cons p acc)))
              acc)))
        (list)
        (cst/moduleNodes root))

fn lookupPrototype protos: (List (Pair String ParamShape)) callee: String -> (Option ParamShape)
  (mt (listHead (filter (fn [(p (Pair String ParamShape))] -> Bool (= (pairFirst p) callee)) protos))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn collectTypeNames root: tr/Node text: String -> (List String)
  (fold (fn [(acc (List String)) (n tr/Node)] -> (List String)
          (if (= (tr/nodeKind n) "llvmTypeDef")
            (cons (cst/tokenSlice (optionOr (listHead (tr/nodeLeaves n)) (tr/makeToken "" 0 0)) text) acc)
            acc))
        (list)
        (cst/moduleNodes root))

fn addUse sc: Scan role: String tok: tr/Token pred: String -> (List Use)
  (cons (Use :role role :tok tok :pred pred) sc.uses)

fn scanStep sc: Scan tok: tr/Token text: String isPhi: Bool -> Scan
  (let [(k (tr/tokenKind tok))
        (txt (cst/tokenSlice tok text))
        (d sc.depth)
        (nd (+ d (depthDelta k)))
        (enterAddr (and (= k "(") (= sc.prev "blockaddress")))
        (addr (if enterAddr nd (if (and (= k ")") (= d sc.addrDepth)) -1 sc.addrDepth)))
        (enterIncoming (and isPhi (= k "[") (= d 0)))
        (leaveIncoming (and sc.inIncoming (= k "]") (= d 1)))
        (keep (fn [(uses (List Use)) (inInc Bool) (after Bool) (pend (List tr/Token))] -> Scan
                (Scan :uses uses :prev txt :depth nd :addrDepth addr :inIncoming inInc :afterComma after :pending pend)))]
    (cond
      (enterIncoming (keep sc.uses true false (list)))
      (leaveIncoming
       (keep (fold (fn [(us (List Use)) (t tr/Token)] -> (List Use) (cons (Use :role "value" :tok t :pred "") us)) sc.uses sc.pending)
             false false (list)))
      ((and sc.inIncoming (= d 1) (= k ","))
       (keep sc.uses true true sc.pending))
      ((and sc.inIncoming sc.afterComma (= k "local"))
       (keep (fold (fn [(us (List Use)) (t tr/Token)] -> (List Use) (cons (Use :role "value" :tok t :pred txt) us))
                   (addUse sc "label" tok "") sc.pending)
             true true (list)))
      ((and sc.inIncoming (= k "local"))
       (keep sc.uses true false (cons tok sc.pending)))
      ((and (= k "local") (or (= sc.prev "label") (and (>= addr 0) (= d addr) (= sc.prev ","))))
       (keep (addUse sc "label" tok "") sc.inIncoming sc.afterComma sc.pending))
      ((= k "local")
       (keep (addUse sc "value" tok "") sc.inIncoming sc.afterComma sc.pending))
      (else (keep sc.uses sc.inIncoming sc.afterComma sc.pending))))

fn instructionUses instrNode: tr/Node text: String isPhi: Bool -> (List Use)
  (let [(toks (cst/nonTriviaTokens (cst/instructionTokens instrNode)))
        (hasDest (some? (instructionDest instrNode text)))
        (operands (if hasDest (listDrop toks 2) toks))
        (final (fold (fn [(sc Scan) (t tr/Token)] -> Scan (scanStep sc t text isPhi))
                     (Scan :uses (list) :prev "" :depth 0 :addrDepth -1 :inIncoming false :afterComma false :pending (list))
                     operands))]
    (listReverse (fold (fn [(us (List Use)) (t tr/Token)] -> (List Use) (cons (Use :role "value" :tok t :pred "") us))
                       final.uses final.pending)))

fn blockNames blocks: (List tr/Node) text: String entryNumber: Int64 -> (List String)
  (map (fn [(i Int64)] -> String
         (let [(lbl (cst/blockLabel (optionOr (listGet blocks i) (tr/makeNode "" 0 0 (list))) text))]
           (if (= lbl "")
             (if (= i 0) (str "%" (stringFromInt64 entryNumber)) (str "%<unnamed" (stringFromInt64 i) ">"))
             (str "%" lbl))))
       (range 0 (listLength blocks)))

fn blockSuccessors block: tr/Node names: (List String) text: String -> (List Int64)
  (mt (listLast (cst/blockInstructions block))
    ((none) (list))
    ((some ins)
     (if (isTerminator (instructionOpcode ins text))
       (fold (fn [(acc (List Int64)) (u Use)] -> (List Int64)
               (if (= u.role "label")
                 (mt (listIndexOf names (cst/tokenSlice u.tok text))
                   ((some j) (cons j acc))
                   ((none) acc))
                 acc))
             (list)
             (instructionUses ins text false))
       (list))))

fn dfsVisit succs: (List (List Int64)) node: Int64 st: (Pair (List Int64) (List Int64)) -> (Pair (List Int64) (List Int64))
  (if (listContains? (pairFirst st) node)
    st
    (let [(kids (optionOr (listGet succs node) (list)))
          (after (fold (fn [(s (Pair (List Int64) (List Int64))) (kid Int64)] -> (Pair (List Int64) (List Int64)) (dfsVisit succs kid s))
                       (pair (cons node (pairFirst st)) (pairSecond st))
                       kids))]
      (pair (pairFirst after) (cons node (pairSecond after)))))

fn listSetAt xs: (List Int64) i: Int64 v: Int64 -> (List Int64)
  (listAppend (listTake xs i) (cons v (listDrop xs (+ i 1))))

fn intersectDom idom: (List Int64) rpoNum: (List Int64) a: Int64 b: Int64 -> Int64
  (if (= a b)
    a
    (if (> (optionOr (listGet rpoNum a) 0) (optionOr (listGet rpoNum b) 0))
      (intersectDom idom rpoNum (optionOr (listGet idom a) 0) b)
      (intersectDom idom rpoNum a (optionOr (listGet idom b) 0))))

fn domPass order: (List Int64) preds: (List (List Int64)) rpoNum: (List Int64) st: (Pair Bool (List Int64)) -> (Pair Bool (List Int64))
  (fold (fn [(s (Pair Bool (List Int64))) (b Int64)] -> (Pair Bool (List Int64))
          (let [(idom (pairSecond s))
                (ready (filter (fn [(p Int64)] -> Bool (>= (optionOr (listGet idom p) -1) 0))
                               (optionOr (listGet preds b) (list))))]
            (if (listEmpty? ready)
              s
              (let [(first (optionOr (listHead ready) 0))
                    (newIdom (fold (fn [(acc Int64) (p Int64)] -> Int64 (intersectDom idom rpoNum p acc))
                                   first
                                   (optionOr (listTail ready) (list))))]
                (if (= newIdom (optionOr (listGet idom b) -1))
                  s
                  (pair true (listSetAt idom b newIdom)))))))
        (pair false (pairSecond st))
        order)

fn domFix order: (List Int64) preds: (List (List Int64)) rpoNum: (List Int64) idom: (List Int64) -> (List Int64)
  (let [(res (domPass order preds rpoNum (pair false idom)))]
    (if (pairFirst res)
      (domFix order preds rpoNum (pairSecond res))
      (pairSecond res)))

fn buildCfg blocks: (List tr/Node) names: (List String) text: String -> Cfg
  (let [(n (listLength blocks))
        (idxs (range 0 n))
        (succs (map (fn [(b tr/Node)] -> (List Int64) (blockSuccessors b names text)) blocks))
        (preds (map (fn [(i Int64)] -> (List Int64)
                      (filter (fn [(p Int64)] -> Bool (listContains? (optionOr (listGet succs p) (list)) i)) idxs))
                    idxs))
        (rpo (if (= n 0) (list) (pairSecond (dfsVisit succs 0 (pair (list) (list))))))
        (rpoNum (map (fn [(i Int64)] -> Int64 (optionOr (listIndexOf rpo i) -1)) idxs))
        (idom0 (map (fn [(i Int64)] -> Int64 (if (= i 0) 0 -1)) idxs))
        (idom (domFix (optionOr (listTail rpo) (list)) preds rpoNum idom0))]
    (Cfg :names names :rpoNum rpoNum :idom idom))

fn dominates cfg: Cfg a: Int64 b: Int64 -> Bool
  (cond
    ((= a b) true)
    ((<= b 0) false)
    (else
     (let [(up (optionOr (listGet cfg.idom b) -1))]
       (if (or (< up 0) (= up b)) false (dominates cfg a up)))))

fn unreachable? cfg: Cfg b: Int64 -> Bool
  (< (optionOr (listGet cfg.rpoNum b) -1) 0)

(schema FnCtx
  (:f text String)
  (:f srcObj src/Source)
  (:f protos (List (Pair String ParamShape)))
  (:f typeNames (List String))
  (:f params (List String))
  (:f defNames (List String))
  (:f defBlocks (List Int64))
  (:f cfg Cfg)
  (:f cc String)
  (:f arity Int64))

fn checkValueUse ctx: FnCtx bi: Int64 local: (List String) u: Use -> (Option Item)
  (let [(text ctx.text)
        (nm (cst/tokenSlice u.tok text))
        (at (fn [(msg String)] -> (Option Item) (some (makeItemAt text ctx.srcObj (tr/tokenStart u.tok) msg))))
        (isValue (or (listContains? ctx.params nm) (listContains? ctx.defNames nm)))]
    (cond
      ((and (not isValue) (listContains? ctx.typeNames nm)) (none))
      ((listContains? ctx.params nm) (none))
      ((not isValue) (at (str "undefined local %value '" nm "'")))
      (else
       (let [(di (optionOr (listGet ctx.defBlocks (optionOr (listIndexOf ctx.defNames nm) 0)) 0))
             (cfg ctx.cfg)]
         (if (= u.pred "")
           (cond
             ((= di bi) (if (listContains? local nm) (none) (at (str "local %value '" nm "' is used before its definition"))))
             ((or (unreachable? cfg bi) (dominates cfg di bi)) (none))
             (else (at (str "local %value '" nm "' is used where its definition does not dominate"))))
           (mt (listIndexOf cfg.names u.pred)
             ((none) (none))
             ((some pi)
              (if (or (unreachable? cfg pi) (dominates cfg di pi))
                (none)
                (at (str "local %value '" nm "' does not dominate incoming block " u.pred))))))))))

fn checkCall ctx: FnCtx instr: tr/Node -> (Option Item)
  (let [(text ctx.text)
        (toks (cst/nonTriviaTokens (cst/instructionTokens instr)))]
    (mt (findCallee (afterCallKeyword toks text) 0)
      ((none) (none))
      ((some c)
       (let [(callee (cst/tokenSlice (pairFirst c) text))
             (got (scanParams (pairSecond c) text 0 "" 0 false (ParamShape :names (list) :fixed 0 :vararg false :nextNumber 0)).fixed)]
         (mt (if (= (tr/tokenKind (pairFirst c)) "global") (lookupPrototype ctx.protos callee) (none))
           ((none) (none))
           ((some want)
            (let [(need want.fixed)
                  (bad (if want.vararg (< got need) (!= got need)))]
              (if bad
                (some (makeItemAt text ctx.srcObj (tr/nodeStart instr)
                                  (str "call to " callee " expects " (if want.vararg "at least " "") (stringFromInt64 need) " arguments, got " (stringFromInt64 got))))
                (none)))))))))

fn ccKeyword? t: String -> Bool
  (listContains? (list "ccc" "fastcc" "coldcc" "tailcc" "swiftcc" "swifttailcc" "ghccc" "cfguard_checkcc" "preserve_mostcc" "preserve_allcc" "cxx_fast_tlscc" "webkit_jscc" "anyregcc") t)

fn callingConv toks: (List tr/Token) text: String -> String
  (mt (listHead toks)
    ((none) "ccc")
    ((some hd) (cond
                 ((= (tr/tokenKind hd) "global") "ccc")
                 ((ccKeyword? (cst/tokenSlice hd text)) (cst/tokenSlice hd text))
                 (else (callingConv (optionOr (listTail toks) (list)) text)))))

fn musttail? toks: (List tr/Token) text: String -> Bool
  (listAny? (fn [(t tr/Token)] -> Bool (and (= (tr/tokenKind t) "ident") (= (cst/tokenSlice t text) "musttail"))) toks)

fn checkMusttail ctx: FnCtx instr: tr/Node next: (Option tr/Node) -> (Option Item)
  (let [(text ctx.text)
        (toks (cst/nonTriviaTokens (cst/instructionTokens instr)))
        (at (fn [(m String)] -> (Option Item) (some (makeItemAt text ctx.srcObj (tr/nodeStart instr) m))))]
    (if (not (musttail? toks text))
      (none)
      (let [(afterCall (afterCallKeyword toks text))
            (cc (callingConv afterCall text))
            (dest (instructionDest instr text))
            (nextToks (mt next ((some n) (cst/nonTriviaTokens (cst/instructionTokens n))) ((none) (list))))
            (nextOp (mt next ((some n) (instructionOpcode n text)) ((none) "")))
            (retValue (cst/tokenSlice (optionOr (listGet nextToks (- (listLength nextToks) 1)) (tr/makeToken "" 0 0)) text))
            (got (mt (findCallee afterCall 0)
                   ((some c) (scanParams (pairSecond c) text 0 "" 0 false (ParamShape :names (list) :fixed 0 :vararg false :nextNumber 0)).fixed)
                   ((none) ctx.arity)))]
        (cond
          ((or (!= nextOp "ret") (!= retValue (optionOr dest "void"))) (at "musttail call must be followed by ret of its result"))
          ((!= cc ctx.cc) (at (str "musttail call uses calling convention " cc " but its caller uses " ctx.cc)))
          ((and (not (or (= cc "tailcc") (= cc "swifttailcc"))) (!= got ctx.arity))
           (at (str "musttail call passes " (stringFromInt64 got) " arguments where its " cc " caller takes " (stringFromInt64 ctx.arity))))
          (else (none))))))

fn withItem opt: (Option Item) items: (List Item) -> (List Item)
  (mt opt ((some i) (cons i items)) ((none) items))

fn validateInstruction ctx: FnCtx bi: Int64 isLast: Bool st: BlockState ins: tr/Node -> BlockState
  (let [(text ctx.text)
        (srcObj ctx.srcObj)
        (op (instructionOpcode ins text))
        (isPhi (= op "phi"))
        (items0 st.items)
        (items1 (if (and isPhi st.seenNonPhi)
                  (cons (makeItemAt text srcObj (tr/nodeStart ins) "phi instructions must appear at block start before non-phi instructions") items0)
                  items0))
        (items2 (cond
                  ((and (not isLast) (isTerminator op))
                   (cons (makeItemAt text srcObj (tr/nodeStart ins) (str "terminator '" op "' must be the last instruction of its block")) items1))
                  ((and isLast (not (isTerminator op)))
                   (cons (makeItemAt text srcObj (tr/nodeStart ins) "expected terminator instruction at end of block") items1))
                  (else items1)))
        (destOpt (instructionDest ins text))
        (items3 (mt destOpt
                  ((none) items2)
                  ((some d)
                   (if (listContains? st.seen d)
                     (cons (makeItemAt text srcObj (tr/nodeStart ins) (str "local %value '" d "' defined more than once in function")) items2)
                     items2))))
        (names ctx.cfg.names)
        (items4 (fold (fn [(acc (List Item)) (u Use)] -> (List Item)
                        (if (= u.role "label")
                          (let [(nm (cst/tokenSlice u.tok text))]
                            (if (listContains? names nm)
                              acc
                              (cons (makeItemAt text srcObj (tr/tokenStart u.tok) (str "undefined label '" nm "'")) acc)))
                          (withItem (checkValueUse ctx bi st.local u) acc)))
                      items3
                      (instructionUses ins text isPhi)))
        (items5 (if (or (= op "call") (= op "invoke")) (withItem (checkCall ctx ins) items4) items4))
        (addDef (fn [(xs (List String))] -> (List String) (mt destOpt ((some d) (cons d xs)) ((none) xs))))]
    (BlockState :seenNonPhi (if isPhi st.seenNonPhi true) :local (addDef st.local) :seen (addDef st.seen) :items items5))

fn validateBlock ctx: FnCtx bi: Int64 block: tr/Node seen: (List String) items: (List Item) -> (Pair (List String) (List Item))
  (let [(instrs (cst/blockInstructions block))
        (n (listLength instrs))]
    (if (= n 0)
      (pair seen (cons (makeItemAt ctx.text ctx.srcObj (tr/nodeStart block) "expected terminator instruction at end of block") items))
      (let [(final (fold (fn [(st BlockState) (i Int64)] -> BlockState
                           (validateInstruction ctx bi (= i (- n 1)) st (optionOr (listGet instrs i) (tr/makeNode "" 0 0 (list)))))
                         (BlockState :seenNonPhi false :local (list) :seen seen :items items)
                         (range 0 n)))]
        (pair final.seen (fold (fn [(acc (List Item)) (i Int64)] -> (List Item)
                                     (withItem (checkMusttail ctx (optionOr (listGet instrs i) (tr/makeNode "" 0 0 (list))) (listGet instrs (+ i 1))) acc))
                                   final.items (range 0 n))))))

fn collectDefs blocks: (List tr/Node) text: String -> (Pair (List String) (List Int64))
  (let [(res (fold (fn [(acc (Pair (List String) (List Int64))) (i Int64)] -> (Pair (List String) (List Int64))
                     (fold (fn [(a (Pair (List String) (List Int64))) (ins tr/Node)] -> (Pair (List String) (List Int64))
                             (mt (instructionDest ins text)
                               ((some d) (if (listContains? (pairFirst a) d) a (pair (cons d (pairFirst a)) (cons i (pairSecond a)))))
                               ((none) a)))
                           acc
                           (cst/blockInstructions (optionOr (listGet blocks i) (tr/makeNode "" 0 0 (list))))))
                   (pair (list) (list))
                   (range 0 (listLength blocks))))]
    (pair (listReverse (pairFirst res)) (listReverse (pairSecond res))))

fn validateFunction funcNode: tr/Node text: String srcObj: src/Source protos: (List (Pair String ParamShape)) typeNames: (List String) acc: (List Item) -> (List Item)
  (let [(shape (mt (headerShape (cst/nonTriviaTokens (cst/functionHeaderTokens funcNode)) text)
                 ((some p) (pairSecond p))
                 ((none) (ParamShape :names (list) :fixed 0 :vararg false :nextNumber 0))))
        (blocks (cst/functionBlocks funcNode))
        (names (blockNames blocks text shape.nextNumber))
        (defs (collectDefs blocks text))
        (ctx (FnCtx :text text :srcObj srcObj :protos protos :typeNames typeNames :params shape.names
                    :cc (callingConv (cst/nonTriviaTokens (cst/functionHeaderTokens funcNode)) text) :arity shape.fixed
                    :defNames (pairFirst defs) :defBlocks (pairSecond defs) :cfg (buildCfg blocks names text)))
        (res (fold (fn [(st (Pair (List String) (List Item))) (i Int64)] -> (Pair (List String) (List Item))
                     (validateBlock ctx i (optionOr (listGet blocks i) (tr/makeNode "" 0 0 (list))) (pairFirst st) (pairSecond st)))
                   (pair shape.names acc)
                   (range 0 (listLength blocks))))]
    (pairSecond res))

fn syntaxItems tree: tr/Node text: String srcObj: src/Source -> (List Item)
  (let [(errs (fold (fn [(acc (List Item)) (n tr/Node)] -> (List Item)
                      (if (tr/isErrorNode n)
                        (cons (makeItemAt text srcObj (tr/nodeStart n) "expected top-level entity (define, declare, global, type, metadata or attributes)") acc)
                        acc))
                    (list)
                    (cst/moduleNodes tree)))]
    (fold (fn [(acc (List Item)) (m tr/Node)] -> (List Item)
            (cons (makeItemAt text srcObj (tr/missingNodeOffset m) (str "expected '" (tr/missingNodeText m) "'")) acc))
          errs
          (tr/treeMissingNodes tree)))

fn llvmValidate text: String -> (Result Unit (List Item))
  (let [(tree (cst/parseLlvm text))
        (srcObj (src/sourceFromString "<input>" text))
        (protos (collectModulePrototypes tree text))
        (typeNames (collectTypeNames tree text))
        (items (fold (fn [(acc (List Item)) (f tr/Node)] -> (List Item)
                       (validateFunction f text srcObj protos typeNames acc))
                     (syntaxItems tree text srcObj)
                     (cst/moduleFunctions tree)))]
    (if (listEmpty? items)
      (ok ())
      (err (listReverse items))))
