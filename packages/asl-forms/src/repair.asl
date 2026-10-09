(module asl-forms/repair
  :x [RepairedItem
      LeftItem
      RepairResult
      makeRepairedItem
      makeLeftItem
      makeRepairResult
      repairedItemKind
      repairedItemTok
      repairedItemLine
      repairedItemCol
      leftItemLine
      leftItemCol
      leftItemExpected
      leftItemNear
      repairResultText
      repairResultRepaired
      repairResultLeft
      repairResultReceipt
      formatReceipt
      repair
      repairText
      repairTextInSpan
      repairTextPick
      repairEdit
      repairAtSite
      repairOptionLine
      repairOptionCol
      repairOptionReparents
      RepairOption
      leftItemOptions
      formatOption
      repairAlternatives
      repairReceipt]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/paren :a prn)
      (asl-syntax/asl/layout :a lay)])

(schema RepairedItem
  (:f kind String)
  (:f tok String)
  (:f line Int64)
  (:f col Int64))

(schema RepairOption
  (:f kind String)
  (:f tok String)
  (:f with String)
  (:f line Int64)
  (:f col Int64)
  (:f off Int64)
  (:f delLen Int64)
  (:f ins String)
  (:f reparents Bool))

(schema LeftItem
  (:f line Int64)
  (:f col Int64)
  (:f expected String)
  (:f near String)
  (:f options (Option (List RepairOption))))

(schema RepairResult
  (:f text String)
  (:f repaired (List RepairedItem))
  (:f left (List LeftItem))
  (:f receipt String))

(schema Tok
  (:f kind Int64)
  (:f start Int64)
  (:f end Int64)
  (:f line Int64)
  (:f col Int64)
  (:f endLine Int64)
  (:f endCol Int64)
  (:f synthetic Bool))

(schema Bound
  (:f index Int64)
  (:f pre (Option (List Int64)))
  (:f suf (Option (List Int64)))
  (:f prev (Option Tok))
  (:f next (Option Tok)))

(schema Cand
  (:f kind String)
  (:f index Int64)
  (:f tokKind Int64)
  (:f oldKind Int64))

(schema DelimError
  (:f kind String)
  (:f index Int64)
  (:f start Int64)
  (:f end Int64)
  (:f expected Int64)
  (:f at (Option Tok)))

(schema Region
  (:f start Int64)
  (:f end Int64)
  (:f firstLine Int64)
  (:f lastLine Int64))

(schema Frame
  (:f col Int64)
  (:f lastCol Int64)
  (:f lastLine Int64))

(schema Segment
  (:f toks (List Tok))
  (:f start Int64)
  (:f end Int64)
  (:f firstLine Int64)
  (:f lastLine Int64))

(schema Elem
  (:f id Int64)
  (:f parent Int64))

(schema SiteFix
  (:f cand Cand)
  (:f kind String)
  (:f expected Int64)
  (:f at Tok))

(schema SiteResult
  (:f item LeftItem)
  (:f unique (Option RepairOption)))

fn makeRepairedItem kind: String tok: String line: Int64 col: Int64 -> RepairedItem
  (RepairedItem :kind kind :tok tok :line line :col col)

fn makeLeftItem line: Int64 col: Int64 expected: String near: String -> LeftItem
  (LeftItem :line line :col col :expected expected :near near :options (none))

fn makeRepairResult text: String repaired: (List RepairedItem) left: (List LeftItem) receipt: String -> RepairResult
  (RepairResult :text text :repaired repaired :left left :receipt receipt)

fn repairedItemKind item: RepairedItem -> String
  item.kind

fn repairedItemTok item: RepairedItem -> String
  item.tok

fn repairedItemLine item: RepairedItem -> Int64
  item.line

fn repairedItemCol item: RepairedItem -> Int64
  item.col

fn leftItemLine item: LeftItem -> Int64
  item.line

fn leftItemCol item: LeftItem -> Int64
  item.col

fn leftItemExpected item: LeftItem -> String
  item.expected

fn repairOptionLine o: RepairOption -> Int64
  o.line

fn repairOptionCol o: RepairOption -> Int64
  o.col

fn repairOptionReparents o: RepairOption -> Bool
  o.reparents

fn leftItemOptions item: LeftItem -> (Option (List RepairOption))
  item.options

fn leftItemNear item: LeftItem -> String
  item.near

fn repairResultText res: RepairResult -> String
  res.text

fn repairResultRepaired res: RepairResult -> (List RepairedItem)
  res.repaired

fn repairResultLeft res: RepairResult -> (List LeftItem)
  res.left

fn repairResultReceipt res: RepairResult -> String
  res.receipt

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

fn formatRepairedItem item: RepairedItem -> String
  (str "(:kind " item.kind " :tok \"" (escapeAsnString item.tok) "\" :line " (stringFromInt64 item.line) " :col " (stringFromInt64 item.col) ")")

fn formatLeftItem item: LeftItem -> String
  (str "(:line " (stringFromInt64 item.line) " :col " (stringFromInt64 item.col) " :expected \"" (escapeAsnString item.expected) "\" :near \"" (escapeAsnString item.near) "\""
       (mt item.options
         ((some os) (str " :options (" (stringJoin (map formatOption os) " ") ")"))
         ((none) ""))
       ")")

fn formatOption o: RepairOption -> String
  (let [(at (str " :line " (stringFromInt64 o.line) " :col " (stringFromInt64 o.col) (if o.reparents " :reparents true" "") ")"))]
    (if (= o.kind "replace")
      (str "(:replace :tok \"" o.tok "\" :with \"" o.with "\"" at)
      (str "(:" o.kind " :tok \"" o.tok "\"" at)))

fn formatRepairedList items: (List RepairedItem) -> String
  (if (listEmpty? items)
    "()"
    (str "(" (stringJoin (map formatRepairedItem items) " ") ")"))

fn formatLeftList items: (List LeftItem) -> String
  (if (listEmpty? items)
    "()"
    (let [(n (listLength items))]
      (if (<= n 5)
        (str "(" (stringJoin (map formatLeftItem items) " ") ")")
        (let [(first5 (listTake items 5))
              (rem (- n 5))]
          (str "(" (stringJoin (map formatLeftItem first5) " ") " :more " (stringFromInt64 rem) ")")))))

fn formatReceipt repaired: (List RepairedItem) left: (List LeftItem) -> String
  (str "(:repaired " (formatRepairedList repaired) " :left " (formatLeftList left) ")")

fn isAsnLang lang: String -> Bool
  (or (= lang "asn") (stringEndsWith? lang ".asn"))

fn parseInLang text: String lang: String -> tr/Node
  (if (isAsnLang lang)
    (prn/parse text)
    (lay/parse text))

fn langHasErrors root: tr/Node lang: String -> Bool
  (if (isAsnLang lang)
    (prn/hasErrors root)
    (lay/hasErrors root))

fn langTreeErrors root: tr/Node lang: String -> (List tr/Node)
  (if (isAsnLang lang)
    (prn/treeErrors root)
    (lay/treeErrors root))

fn leftItemKey item: LeftItem -> String
  (str (stringFromInt64 item.line) ":" (stringFromInt64 item.col) ":" item.expected)

fn dedupeLeftItems items: (List LeftItem) seen: (List String) acc: (List LeftItem) -> (List LeftItem)
  (if (listEmpty? items)
    (listReverse acc)
    (let [(h (optionOr (listHead items) (LeftItem :line 0 :col 0 :expected "" :near "" :options (none))))
          (tail (optionOr (listTail items) (list)))
          (k (leftItemKey h))]
      (if (listContains? seen k)
        (dedupeLeftItems tail seen acc)
        (dedupeLeftItems tail (cons k seen) (cons h acc)))))

fn collectLeftItems text: String s: src/Source nodes: (List tr/Node) acc: (List LeftItem) -> (List LeftItem)
  (if (listEmpty? nodes)
    (dedupeLeftItems (listReverse acc) (list) (list))
    (let [(n (optionOr (listHead nodes) (tr/makeErrorNode 0 0 (list))))
          (tail (optionOr (listTail nodes) (list)))
          (startOff (tr/nodeStart n))
          (posOpt (src/sourcePosAt s startOff))
          (line (mt posOpt ((some p) p.line) ((none) 1)))
          (col (mt posOpt ((some p) p.byteCol) ((none) 1)))
          (expected (mt (tr/nodeMissing n)
                      ((some m) (tr/missingTok m))
                      ((none) (if (tr/isStrayNode n) "" "\""))))
          (near (nearSnippet text s line col))
          (item (LeftItem :line line :col col :expected expected :near near :options (none)))]
      (collectLeftItems text s tail (cons item acc))))

fn isUnrepairableErrorNode n: tr/Node -> Bool
  (and (tr/isErrorNode n)
    (and (not (some? (tr/nodeMissing n)))
         (not (tr/isStrayNode n))))

fn hasUnrepairableError nodes: (List tr/Node) -> Bool
  (not (listEmpty? (filter isUnrepairableErrorNode nodes)))


fn delimKindOf k: String -> Int64
  (cond
    ((= k "lparen") 1)
    ((= k "lbracket") 2)
    ((= k "lbrace") 3)
    ((= k "rparen") -1)
    ((= k "rbracket") -2)
    ((= k "rbrace") -3)
    (else 0))

fn delimText kind: Int64 -> String
  (cond
    ((= kind 1) "(")
    ((= kind 2) "[")
    ((= kind 3) "{")
    ((= kind -1) ")")
    ((= kind -2) "]")
    ((= kind -3) "}")
    (else ""))

fn posAt s: src/Source offset: Int64 -> (Pair Int64 Int64)
  (mt (src/sourcePosAt s offset)
    ((some p) (pair p.line p.byteCol))
    ((none)
     (let [(len (src/sourceLength s))]
       (if (and (> offset 0) (>= offset len))
         (mt (src/sourcePosAt s (- len 1))
           ((some p) (pair p.line (+ p.byteCol 1)))
           ((none) (pair 1 1)))
         (pair 1 1)))))

fn buildToks s: src/Source raw: (List tr/Token) acc: (List Tok) -> (List Tok)
  (if (listEmpty? raw)
    (listReverse acc)
    (let [(t (optionOr (listHead raw) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail raw) (list)))]
      (if (tr/isTrivia t)
        (buildToks s rest acc)
        (let [(st (posAt s t.start))
              (en (if (= t.kind "string")
                    (posAt s t.end)
                    (pair (pairFirst st) (+ (pairSecond st) (- t.end t.start)))))
              (tok (Tok :kind (delimKindOf t.kind) :start t.start :end t.end
                        :line (pairFirst st) :col (pairSecond st) :endLine (pairFirst en) :endCol (pairSecond en) :synthetic false))]
          (buildToks s rest (cons tok acc))))))

fn stepPrefix st: (Option (List Int64)) k: Int64 -> (Option (List Int64))
  (mt st
    ((none) (none))
    ((some p)
     (cond
       ((> k 0) (some (cons k p)))
       ((< k 0)
        (mt (listHead p)
          ((some h) (if (= h (- 0 k)) (some (optionOr (listTail p) (list))) (none)))
          ((none) (none))))
       (else st))))

fn buildPrefix toks: (List Tok) st: (Option (List Int64)) acc: (List (Option (List Int64))) -> (List (Option (List Int64)))
  (let [(acc2 (cons st acc))]
    (if (listEmpty? toks)
      (listReverse acc2)
      (let [(t (optionOr (listHead toks) (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false)))
            (rest (optionOr (listTail toks) (list)))]
        (buildPrefix rest (stepPrefix st t.kind) acc2))))

fn stepSuffix st: (Option (List Int64)) k: Int64 -> (Option (List Int64))
  (mt st
    ((none) (none))
    ((some q)
     (cond
       ((< k 0) (some (cons (- 0 k) q)))
       ((> k 0)
        (mt (listHead q)
          ((some h) (if (= h k) (some (optionOr (listTail q) (list))) (none)))
          ((none) (none))))
       (else st))))

fn buildSuffix revToks: (List Tok) st: (Option (List Int64)) acc: (List (Option (List Int64))) -> (List (Option (List Int64)))
  (if (listEmpty? revToks)
    acc
    (let [(t (optionOr (listHead revToks) (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false)))
          (rest (optionOr (listTail revToks) (list)))
          (nst (stepSuffix st t.kind))]
      (buildSuffix rest nst (cons nst acc))))

fn stackEq a: (List Int64) b: (List Int64) -> Bool
  (mt (listHead a)
    ((none) (listEmpty? b))
    ((some x)
     (mt (listHead b)
       ((none) false)
       ((some y)
        (if (= x y)
          (stackEq (optionOr (listTail a) (list)) (optionOr (listTail b) (list)))
          false)))))

fn topIs st: (List Int64) k: Int64 -> Bool
  (mt (listHead st) ((some h) (= h k)) ((none) false))

fn popStack st: (List Int64) -> (List Int64)
  (optionOr (listTail st) (list))

fn findDelimError toks: (List Tok) stack: (List Tok) idx: Int64 textLen: Int64 -> DelimError
  (mt (listHead toks)
    ((none)
     (mt (listHead stack)
       ((none) (DelimError :kind "none" :index idx :start textLen :end textLen :expected 0 :at (none)))
       ((some o) (DelimError :kind "missing" :index idx :start textLen :end textLen :expected (- 0 o.kind) :at (some o)))))
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (k t.kind)]
       (cond
         ((> k 0) (findDelimError rest (cons t stack) (+ idx 1) textLen))
         ((< k 0)
          (mt (listHead stack)
            ((none) (DelimError :kind "stray" :index idx :start t.start :end t.end :expected 0 :at (some t)))
            ((some o)
             (if (= o.kind (- 0 k))
               (findDelimError rest (optionOr (listTail stack) (list)) (+ idx 1) textLen)
               (DelimError :kind "mismatch" :index idx :start t.start :end t.end :expected (- 0 o.kind) :at (some t))))))
         (else (findDelimError rest stack (+ idx 1) textLen))))))

fn buildBounds pres: (List (Option (List Int64))) sufs: (List (Option (List Int64))) toks: (List Tok) prev: (Option Tok) idx: Int64 acc: (List Bound) -> (List Bound)
  (mt (listHead pres)
    ((none) (listReverse acc))
    ((some p)
     (let [(sq (optionOr (listHead sufs) (none)))
           (nxt (listHead toks))
           (b (Bound :index idx :pre p :suf sq :prev prev :next nxt))]
       (buildBounds (optionOr (listTail pres) (list)) (optionOr (listTail sufs) (list)) (optionOr (listTail toks) (list)) nxt (+ idx 1) (cons b acc)))))

fn boundInRegion b: Bound r: Region -> Bool
  (and (mt b.next ((some t) (>= t.start r.start)) ((none) true))
       (mt b.prev ((some t) (<= t.end r.end)) ((none) true)))

fn tokInRegion t: Tok r: Region -> Bool
  (and (>= t.start r.start) (<= t.end r.end))

fn closerInsertBalances b: Bound c: Int64 -> Bool
  (mt b.pre
    ((none) false)
    ((some p)
     (mt b.suf
       ((none) false)
       ((some q) (and (topIs p (- 0 c)) (stackEq (popStack p) q))))))

fn openerInsertBalances b: Bound o: Int64 -> Bool
  (mt b.pre
    ((none) false)
    ((some p)
     (mt b.suf
       ((none) false)
       ((some q) (and (topIs q o) (stackEq p (popStack q)))))))

fn tokenEditBalances b: Bound after: Bound c: Int64 -> Bool
  (mt b.pre
    ((none) false)
    ((some p)
     (mt after.suf
       ((none) false)
       ((some q)
        (if (= c 0)
          (stackEq p q)
          (and (topIs p (- 0 c)) (stackEq (popStack p) q)))))))

fn tokIs t: (Option Tok) k: Int64 -> Bool
  (mt t ((some x) (= x.kind k)) ((none) false))

fn closerInserts b: Bound r: Region kinds: (List Int64) acc: (List Cand) -> (List Cand)
  (mt (listHead kinds)
    ((none) acc)
    ((some c)
     (let [(rest (optionOr (listTail kinds) (list)))
           (dup (mt b.next ((some t) (and (= t.kind c) (tokInRegion t r))) ((none) false)))]
       (if (and (not dup) (closerInsertBalances b c))
         (closerInserts b r rest (cons (Cand :kind "insert" :index b.index :tokKind c :oldKind 0) acc))
         (closerInserts b r rest acc)))))

fn openerInserts b: Bound kinds: (List Int64) acc: (List Cand) -> (List Cand)
  (mt (listHead kinds)
    ((none) acc)
    ((some o)
     (let [(rest (optionOr (listTail kinds) (list)))]
       (if (and (not (tokIs b.prev o)) (openerInsertBalances b o))
         (openerInserts b rest (cons (Cand :kind "insert" :index b.index :tokKind o :oldKind 0) acc))
         (openerInserts b rest acc)))))

fn closerEdits b: Bound after: Bound r: Region acc: (List Cand) -> (List Cand)
  (mt b.next
    ((none) acc)
    ((some t)
     (let [(k t.kind)]
       (if (or (>= k 0) (or t.synthetic (not (tokInRegion t r))))
         acc
         (let [(dupDel (mt after.next ((some u) (and (= u.kind k) (tokInRegion u r))) ((none) false)))
               (acc1 (if (and (not dupDel) (tokenEditBalances b after 0))
                       (cons (Cand :kind "delete" :index b.index :tokKind 0 :oldKind k) acc)
                       acc))
               (others (filter (fn [(c Int64)] -> Bool (not (= c k))) (list -1 -2 -3)))]
           (listAppend (listReverse (map (fn [(c Int64)] -> Cand (Cand :kind "replace" :index b.index :tokKind c :oldKind k))
                                         (filter (fn [(c Int64)] -> Bool (tokenEditBalances b after c)) others)))
                       acc1))))))

fn lostOpenerAllowed b: Bound e: DelimError -> Bool
  (and (or (= e.kind "stray") (= e.kind "mismatch"))
       (< b.index e.index))

fn enumerateBalanced bounds: (List Bound) r: Region e: DelimError acc: (List Cand) -> (List Cand)
  (mt (listHead bounds)
    ((none) (listReverse acc))
    ((some b)
     (let [(rest (optionOr (listTail bounds) (list)))
           (inR (boundInRegion b r))
           (acc1 (if inR (closerInserts b r (list -1 -2 -3) acc) acc))
           (acc2 (if (and inR (lostOpenerAllowed b e)) (openerInserts b (list 1 2 3) acc1) acc1))
           (acc3 (mt (listHead rest) ((some after) (closerEdits b after r acc2)) ((none) acc2)))]
       (enumerateBalanced rest r e acc3))))

fn tokAt toks: (List Tok) i: Int64 -> (Option Tok)
  (listGet toks i)

fn candOffset toks: (List Tok) c: Cand textLen: Int64 -> Int64
  (if (= c.kind "insert")
    (if (> c.tokKind 0)
      (mt (tokAt toks c.index) ((some t) t.start) ((none) textLen))
      (if (= c.index 0) 0 (mt (tokAt toks (- c.index 1)) ((some t) t.end) ((none) 0))))
    (mt (tokAt toks c.index) ((some t) t.start) ((none) 0)))

fn candPos toks: (List Tok) c: Cand -> (Pair Int64 Int64)
  (if (= c.kind "insert")
    (if (> c.tokKind 0)
      (mt (tokAt toks c.index) ((some t) (pair t.line t.col)) ((none) (pair 1 1)))
      (if (= c.index 0) (pair 1 1) (mt (tokAt toks (- c.index 1)) ((some t) (pair t.endLine t.endCol)) ((none) (pair 1 1)))))
    (mt (tokAt toks c.index) ((some t) (pair t.line t.col)) ((none) (pair 1 1))))

fn applyCand text: String toks: (List Tok) c: Cand -> String
  (let [(len (stringLength text))
        (off (candOffset toks c len))
        (pre (optionOr (stringSlice text 0 off) ""))]
    (if (= c.kind "insert")
      (str pre (delimText c.tokKind) (optionOr (stringSlice text off len) ""))
      (let [(post (optionOr (stringSlice text (+ off 1) len) ""))]
        (if (= c.kind "delete")
          (str pre post)
          (str pre (delimText c.tokKind) post)))))

fn shiftedCol t: Tok line: Int64 off: Int64 delta: Int64 -> Int64
  (if (and (= t.line line) (>= t.start off)) (+ t.col delta) t.col)

fn candToks toks: (List Tok) c: Cand idx: Int64 line: Int64 col: Int64 off: Int64 acc: (List Tok) -> (List Tok)
  (let [(isIns (= c.kind "insert"))
        (here (= idx c.index))
        (insTok (Tok :kind c.tokKind :start off :end off :line line :col col :endLine line :endCol (+ col 1) :synthetic true))
        (acc1 (if (and isIns here) (cons insTok acc) acc))]
    (mt (listHead toks)
      ((none) (listReverse acc1))
      ((some t)
       (let [(rest (optionOr (listTail toks) (list)))
             (delta (cond (isIns 1) ((= c.kind "delete") -1) (else 0)))
             (moved (Tok :kind t.kind :start t.start :end t.end :line t.line
                         :col (shiftedCol t line (if isIns off (+ off 1)) delta) :endLine t.endLine :endCol t.endCol :synthetic t.synthetic))
             (acc2 (cond
                     ((and here (= c.kind "delete")) acc1)
                     ((and here (= c.kind "replace"))
                      (cons (Tok :kind c.tokKind :start t.start :end t.end :line t.line :col t.col :endLine t.endLine :endCol t.endCol :synthetic t.synthetic) acc1))
                     (else (cons moved acc1))))]
         (candToks rest c (+ idx 1) line col off acc2)))))

fn frameColGte frames: (List Frame) col: Int64 -> Bool
  (mt (listHead frames)
    ((none) false)
    ((some f) (if (>= f.col col) true (frameColGte (optionOr (listTail frames) (list)) col))))

fn lineStartViolates frames: (List Frame) t: Tok -> Bool
  (or (frameColGte frames t.col)
      (mt (listHead frames)
        ((none) false)
        ((some f) (and (>= f.lastCol 0) (and (< f.lastLine t.line) (< f.lastCol t.col))))))

fn setLast frames: (List Frame) col: Int64 line: Int64 -> (List Frame)
  (mt (listHead frames)
    ((none) frames)
    ((some f) (cons (Frame :col f.col :lastCol col :lastLine line) (optionOr (listTail frames) (list)))))

fn layoutScan toks: (List Tok) frames: (List Frame) prevEndLine: Int64 firstLine: Int64 lastLine: Int64 -> Bool
  (mt (listHead toks)
    ((none) true)
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (lineStart (> t.line prevEndLine))
           (checked (and lineStart (and (>= t.kind 0) (and (>= t.line firstLine) (<= t.line lastLine)))))]
       (if (and checked (lineStartViolates frames t))
         false
         (let [(f1 (if lineStart (setLast frames -1 0) frames))
               (k t.kind)
               (f2 (cond
                     ((> k 0) (cons (Frame :col t.col :lastCol -1 :lastLine 0) f1))
                     ((< k 0)
                      (mt (listHead f1)
                        ((none) f1)
                        ((some top)
                         (let [(below (optionOr (listTail f1) (list)))]
                           (if (listEmpty? below) f1 (setLast below top.col t.line))))))
                     (else f1)))]
           (layoutScan rest f2 t.endLine firstLine lastLine))))))

fn candLayoutOk toks: (List Tok) c: Cand r: Region textLen: Int64 -> Bool
  (let [(pos (candPos toks c))
        (off (candOffset toks c textLen))
        (ctoks (candToks toks c 0 (pairFirst pos) (pairSecond pos) off (list)))]
    (layoutScan ctoks (list (Frame :col 0 :lastCol -1 :lastLine 0)) 0 r.firstLine r.lastLine))

fn lineStartOff s: src/Source line: Int64 -> Int64
  (optionOr (src/sourceLineStart s line) 0)

fn leftFor text: String s: src/Source root: tr/Node lang: String e: DelimError -> (List LeftItem)
  (let [(treeLeft (collectLeftItems text s (langTreeErrors root lang) (list)))]
    (mt e.at
      ((none) treeLeft)
      ((some t)
       (let [(item (LeftItem :line t.line :col t.col :expected (delimText e.expected) :near (nearSnippet text s t.line t.col) :options (none)))]
         (dedupeLeftItems (cons item treeLeft) (list) (list))))))

fn maxRegionToks -> Int64
  6000

fn countInRegion toks: (List Tok) r: Region n: Int64 -> Int64
  (mt (listHead toks)
    ((none) n)
    ((some t) (countInRegion (optionOr (listTail toks) (list)) r (if (tokInRegion t r) (+ n 1) n))))

fn firstLexError raw: (List tr/Token) -> (Option tr/Token)
  (mt (listHead raw)
    ((none) (none))
    ((some t) (if (tr/isErrorToken t) (some t) (firstLexError (optionOr (listTail raw) (list))))))

fn leftResult text: String left: (List LeftItem) -> RepairResult
  (makeRepairResult text (list) left (formatReceipt (list) left))

fn candOption toks: (List Tok) c: Cand textLen: Int64 -> RepairOption
  (let [(pos (candPos toks c))
        (off (candOffset toks c textLen))
        (line (pairFirst pos))
        (col (pairSecond pos))]
    (cond
      ((= c.kind "insert") (RepairOption :kind "insert" :tok (delimText c.tokKind) :with "" :line line :col col :off off :delLen 0 :ins (delimText c.tokKind) :reparents false))
      ((= c.kind "delete") (RepairOption :kind "delete" :tok (delimText c.oldKind) :with "" :line line :col col :off off :delLen 1 :ins "" :reparents false))
      (else (RepairOption :kind "replace" :tok (delimText c.oldKind) :with (delimText c.tokKind) :line line :col col :off off :delLen 1 :ins (delimText c.tokKind) :reparents false))))

fn applyOption text: String o: RepairOption -> String
  (let [(len (stringLength text))]
    (str (optionOr (stringSlice text 0 o.off) "") o.ins (optionOr (stringSlice text (+ o.off o.delLen) len) "")))

fn optionItems o: RepairOption -> (List RepairedItem)
  (cond
    ((= o.kind "insert") (list (RepairedItem :kind "insert" :tok o.tok :line o.line :col o.col)))
    ((= o.kind "delete") (list (RepairedItem :kind "delete" :tok o.tok :line o.line :col o.col)))
    (else (list (RepairedItem :kind "delete" :tok o.tok :line o.line :col o.col)
                (RepairedItem :kind "insert" :tok o.with :line o.line :col o.col))))

fn startsSegment text: String t: Tok prevEndLine: Int64 -> Bool
  (and (= t.col 1)
       (and (> t.line prevEndLine)
            (or (= t.kind 1)
                (and (= t.kind 0) (listContains? (list "fn" "fn!" "schema" "enum") (optionOr (stringSlice text t.start t.end) ""))))))

fn splitSegments text: String toks: (List Tok) prevEndLine: Int64 cur: (List Tok) acc: (List (List Tok)) -> (List (List Tok))
  (mt (listHead toks)
    ((none) (listReverse (if (listEmpty? cur) acc (cons (listReverse cur) acc))))
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))]
       (if (and (startsSegment text t prevEndLine) (not (listEmpty? cur)))
         (splitSegments text rest t.endLine (list t) (cons (listReverse cur) acc))
         (splitSegments text rest t.endLine (cons t cur) acc)))))

fn makeSegment toks: (List Tok) -> Segment
  (let [(dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (f (optionOr (listHead toks) dflt))
        (l (optionOr (listLast toks) dflt))]
    (Segment :toks toks :start f.start :end l.end :firstLine f.line :lastLine l.endLine))

fn segmentParses text: String lang: String seg: Segment o: RepairOption -> Bool
  (let [(grow (- (stringLength o.ins) o.delLen))
        (cand (applyOption text o))
        (slice (optionOr (stringSlice cand seg.start (+ seg.end grow)) ""))]
    (not (langHasErrors (parseInLang slice lang) lang)))

fn makesEmptyForm toks: (List Tok) c: Cand -> Bool
  (and (= c.kind "insert")
       (if (> c.tokKind 0)
         (mt (tokAt toks c.index) ((some t) (< t.kind 0)) ((none) false))
         (mt (tokAt toks (- c.index 1)) ((some t) (> t.kind 0)) ((none) false))))

fn candDist toks: (List Tok) c: Cand textLen: Int64 site: Int64 -> Int64
  (let [(d (- (candOffset toks c textLen) site))]
    (+ (if (< d 0) (- 0 d) d) (if (makesEmptyForm toks c) 100000000 0)))

fn parsingUpTo text: String lang: String seg: Segment toks: (List Tok) cands: (List Cand) limit: Int64 acc: (List Cand) -> (List Cand)
  (if (>= (listLength acc) limit)
    (listReverse acc)
    (mt (listHead cands)
      ((none) (listReverse acc))
      ((some c)
       (let [(rest (optionOr (listTail cands) (list)))]
         (if (segmentParses text lang seg (candOption toks c (stringLength text)))
           (parsingUpTo text lang seg toks rest limit (cons c acc))
           (parsingUpTo text lang seg toks rest limit acc))))))

fn sameCand a: Cand b: Cand -> Bool
  (and (= a.kind b.kind) (and (= a.index b.index) (= a.tokKind b.tokKind)))

fn applyOptions text: String os: (List RepairOption) -> String
  (let [(indexed (listZipIndex os 0 (list)))
        (desc (listSortBy (fn [(p (Pair Int64 RepairOption))] -> Int64 (- 0 (+ (* (pairSecond p).off 4096) (pairFirst p)))) indexed))]
    (applyOptionsLoop text (map (fn [(p (Pair Int64 RepairOption))] -> RepairOption (pairSecond p)) desc)))

fn listZipIndex os: (List RepairOption) i: Int64 acc: (List (Pair Int64 RepairOption)) -> (List (Pair Int64 RepairOption))
  (mt (listHead os)
    ((none) (listReverse acc))
    ((some o) (listZipIndex (optionOr (listTail os) (list)) (+ i 1) (cons (pair i o) acc))))

fn ctxParses text: String lang: String seg: Segment opts: (List RepairOption) -> Bool
  (let [(segText (optionOr (stringSlice text seg.start seg.end) ""))
        (local (map (fn [(o RepairOption)] -> RepairOption (RepairOption :kind o.kind :tok o.tok :with o.with :line o.line :col o.col :off (- o.off seg.start) :delLen o.delLen :ins o.ins :reparents o.reparents)) opts))
        (cand (applyOptions segText local))]
    (not (langHasErrors (parseInLang cand lang) lang)))

fn listSum xs: (List Int64) -> Int64
  (mt (listHead xs) ((none) 0) ((some x) (+ x (listSum (optionOr (listTail xs) (list))))))

fn popT st: (List Tok) -> (List Tok)
  (optionOr (listTail st) (list))

fn simpleCount toks: (List Tok) stack: (List Tok) n: Int64 -> Int64
  (mt (listHead toks)
    ((none) (+ n (listLength stack)))
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (k t.kind)]
       (cond
         ((> k 0) (simpleCount rest (cons t stack) n))
         ((< k 0)
          (mt (listHead stack)
            ((none) (simpleCount rest stack (+ n 1)))
            ((some o)
             (if (= o.kind (- 0 k))
               (simpleCount rest (popT stack) n)
               (let [(below (popT stack))]
                 (if (mt (listHead below) ((some u) (= u.kind (- 0 k))) ((none) false))
                   (simpleCount rest (popT below) (+ n 1))
                   (simpleCount rest below (+ n 1))))))))
         (else (simpleCount rest stack n))))))

fn greedySites toks: (List Tok) stack: (List Tok) idx: Int64 lastTok: Tok acc: (List SiteFix) -> (List SiteFix)
  (mt (listHead toks)
    ((none) (listAppend (listReverse acc) (map (fn [(o Tok)] -> SiteFix (SiteFix :cand (Cand :kind "insert" :index idx :tokKind (- 0 o.kind) :oldKind 0) :kind "missing" :expected (- 0 o.kind) :at lastTok)) stack)))
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (k t.kind)]
       (cond
         ((> k 0) (greedySites rest (cons t stack) (+ idx 1) t acc))
         ((< k 0)
          (mt (listHead stack)
            ((none) (greedySites rest stack (+ idx 1) t (cons (SiteFix :cand (Cand :kind "delete" :index idx :tokKind 0 :oldKind k) :kind "stray" :expected 0 :at t) acc)))
            ((some o)
             (if (= o.kind (- 0 k))
               (greedySites rest (popT stack) (+ idx 1) t acc)
               (let [(below (popT stack))
                     (fitsBelow (mt (listHead below) ((some u) (= u.kind (- 0 k))) ((none) false)))
                     (insCost (if fitsBelow (simpleCount rest (popT below) 0) 1000000))
                     (delCost (simpleCount rest stack 0))
                     (repCost (simpleCount rest below 0))
                     (nextFits (and (< delCost insCost) (< delCost repCost)))]
                 (cond
                   ((and fitsBelow (<= insCost repCost)) (greedySites rest (popT below) (+ idx 1) t (cons (SiteFix :cand (Cand :kind "insert" :index idx :tokKind (- 0 o.kind) :oldKind 0) :kind "mismatch" :expected (- 0 o.kind) :at t) acc)))
                   (nextFits (greedySites rest stack (+ idx 1) t (cons (SiteFix :cand (Cand :kind "delete" :index idx :tokKind 0 :oldKind k) :kind "mismatch" :expected (- 0 o.kind) :at t) acc)))
                   (else (greedySites rest below (+ idx 1) t (cons (SiteFix :cand (Cand :kind "replace" :index idx :tokKind (- 0 o.kind) :oldKind k) :kind "mismatch" :expected (- 0 o.kind) :at t) acc)))))))))
         (else (greedySites rest stack (+ idx 1) t acc))))))

fn applyTokEdits toks: (List Tok) edits: (List Cand) idx: Int64 prev: (Option Tok) acc: (List Tok) -> (List Tok)
  (let [(dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (p (optionOr prev dflt))
        (ins (filter (fn [(c Cand)] -> Bool (and (= c.kind "insert") (= c.index idx))) edits))
        (insToks (map (fn [(c Cand)] -> Tok (Tok :kind c.tokKind :start p.end :end p.end :line p.endLine :col p.endCol :endLine p.endLine :endCol (+ p.endCol 1) :synthetic true)) ins))
        (acc1 (listAppend (listReverse insToks) acc))]
    (mt (listHead toks)
      ((none) (listReverse acc1))
      ((some t)
       (let [(rest (optionOr (listTail toks) (list)))
             (del (not (listEmpty? (filter (fn [(c Cand)] -> Bool (and (= c.kind "delete") (= c.index idx))) edits))))
             (repl (filter (fn [(c Cand)] -> Bool (and (= c.kind "replace") (= c.index idx))) edits))
             (acc2 (cond
                     (del acc1)
                     ((listEmpty? repl) (cons t acc1))
                     (else (cons (Tok :kind (mt (listHead repl) ((some c) c.tokKind) ((none) t.kind)) :start t.start :end t.end :line t.line :col t.col :endLine t.endLine :endCol t.endCol :synthetic true) acc1))))]
         (applyTokEdits rest edits (+ idx 1) (some t) acc2)))))

fn nearestSurvivors text: String lang: String seg: Segment toks: (List Tok) ctx: (List RepairOption) r: Region cands: (List Cand) limit: Int64 acc: (List Cand) -> (List Cand)
  (if (>= (listLength acc) limit)
    (listReverse acc)
    (mt (listHead cands)
      ((none) (listReverse acc))
      ((some c)
       (let [(rest (optionOr (listTail cands) (list)))
             (len (stringLength text))]
         (if (and (candLayoutOk toks c r len) (ctxParses text lang seg (listAppend ctx (list (candOption toks c len)))))
           (nearestSurvivors text lang seg toks ctx r rest limit (cons c acc))
           (nearestSurvivors text lang seg toks ctx r rest limit acc))))))

fn atSiteRank toks: (List Tok) e: DelimError c: Cand -> Int64
  (cond
    ((= e.kind "stray") (if (and (= c.kind "delete") (= c.index e.index)) 1 0))
    ((and (= c.kind "insert")
          (and (= c.tokKind e.expected) (= c.index e.index)))
     1)
    ((and (= c.kind "delete") (= c.index e.index)) 2)
    ((and (= c.kind "replace") (and (= c.index e.index) (= c.tokKind e.expected))) 3)
    (else 0))

fn analyzeSite text: String lang: String s: src/Source seg: Segment sites: (List SiteFix) k: Int64 spanStart: Int64 spanEnd: Int64 wholeLayout: Bool base: (Option (List Elem)) -> SiteResult
  (let [(segToks seg.toks)
        (len (stringLength text))
        (dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (site (optionOr (listGet sites k) (SiteFix :cand (Cand :kind "" :index 0 :tokKind 0 :oldKind 0) :kind "" :expected 0 :at dflt)))
        (others (map (fn [(x SiteFix)] -> Cand x.cand) (listAppend (listTake sites k) (listDrop sites (+ k 1)))))
        (ctx (map (fn [(c Cand)] -> RepairOption (candOption segToks c len)) others))
        (toks (applyTokEdits segToks others 0 (none) (list)))
        (e (findDelimError toks (list) 0 seg.end))
        (at site.at)
        (missing (= site.kind "missing"))
        (siteLine (if missing at.endLine at.line))
        (siteCol (if missing at.endCol at.col))
        (siteOff (if missing at.end at.start))
        (expected (delimText site.expected))
        (near (nearSnippet text s siteLine siteCol))]
    (if (= e.kind "none")
      (SiteResult :item (LeftItem :line siteLine :col siteCol :expected expected :near near :options (some (list))) :unique (none))
      (let [(startLine (pairFirst (posAt s (if (< e.start spanStart) e.start spanStart))))
            (lineOff (lineStartOff s startLine))
            (spanFirst (pairFirst (posAt s spanStart)))
            (spanLast (pairFirst (posAt s (if (> spanEnd spanStart) (- spanEnd 1) spanStart))))
            (flush (flushLeft segToks))
            (r (Region :start (if (< lineOff seg.start) seg.start lineOff) :end e.end
                       :firstLine (if (or wholeLayout (< spanFirst seg.firstLine)) seg.firstLine spanFirst)
                       :lastLine (cond (flush 0) ((or wholeLayout (> spanLast seg.lastLine)) seg.lastLine) (else spanLast))))]
        (if (> (countInRegion toks r 0) (maxRegionToks))
          (SiteResult :item (LeftItem :line siteLine :col siteCol :expected expected :near near :options (some (list))) :unique (none))
          (let [(pres (buildPrefix toks (some (list)) (list)))
                (sufs (buildSuffix (listReverse toks) (some (list)) (list (some (list)))))
                (bounds (buildBounds pres sufs toks (none) 0 (list)))
                (cands (enumerateBalanced bounds r e (list)))
                (nearest (listSortBy (fn [(c Cand)] -> Int64 (candDist toks c len siteOff)) cands))
                (kept (nearestSurvivors text lang seg toks ctx r nearest 6 (list)))
                (ranked (listSortBy (fn [(c Cand)] -> Int64 (atSiteRank toks e c))
                                    (filter (fn [(c Cand)] -> Bool (> (atSiteRank toks e c) 0)) cands)))
                (atSite (listTake (filter (fn [(c Cand)] -> Bool (ctxParses text lang seg (listAppend ctx (list (candOption toks c len))))) ranked) 1))
                (others2 (mt (listHead atSite)
                           ((some a) (filter (fn [(c Cand)] -> Bool (not (sameCand a c))) kept))
                           ((none) kept)))
                (leaves (leafForms toks toks (list) (list)))
                (pool (listAppend atSite (filter (fn [(c Cand)] -> Bool (not (and (not (isAsnLang lang)) (makesEmptyForm toks c)))) others2)))
                (scored (map (fn [(c Cand)] -> RepairOption
                               (markReparents (candOption toks c len)
                                              (mt base
                                                ((some b) (candReparents toks c (filter (fn [(x Elem)] -> Bool (and (>= x.id (* 2 seg.start)) (<= x.id (* 2 seg.end)))) b) len))
                                                ((none) (altersLeaf toks c leaves len)))))
                             pool))
                (byDist (fn [(o RepairOption)] -> Int64 (let [(d (- o.off siteOff))] (if (< d 0) (- 0 d) d))))
                (ranked (listAppend (listSortBy byDist (filter (fn [(o RepairOption)] -> Bool (not o.reparents)) scored))
                                    (listSortBy byDist (filter (fn [(o RepairOption)] -> Bool o.reparents) scored))))
                (atOpt (listTake scored (listLength atSite)))
                (before (listTake (filter (fn [(o RepairOption)] -> Bool (< o.off siteOff)) ranked) 1))
                (afterOpt (listTake (filter (fn [(o RepairOption)] -> Bool (> o.off siteOff)) ranked) 1))
                (must (dedupeOptions (listAppend atOpt (listAppend before afterOpt)) (list)))
                (chosen (dedupeOptions (listAppend must ranked) (list)))
                (picked (listTake chosen (if (> (listLength must) 3) (listLength must) 3)))
                (options (filter (fn [(o RepairOption)] -> Bool (not (listEmpty? (filter (fn [(p RepairOption)] -> Bool (sameOption o p)) picked)))) ranked))
                (unique (if (and (= (listLength sites) 1) (= (listLength kept) 1))
                          (mt (listHead kept) ((some c) (some (candOption toks c len))) ((none) (none)))
                          (none)))]
            (SiteResult :item (LeftItem :line siteLine :col siteCol :expected expected :near near :options (some options)) :unique unique))))))

fn flushLeft toks: (List Tok) -> Bool
  (not (listEmpty? (filter (fn [(t Tok)] -> Bool (= t.col 1)) (optionOr (listTail toks) (list)))))

fn formEnd toks: (List Tok) stack: (List Int64) idx: Int64 -> Int64
  (mt (listHead toks)
    ((none) -1)
    ((some t)
     (let [(k t.kind)
           (rest (optionOr (listTail toks) (list)))]
       (cond
         ((> k 0) (formEnd rest (cons k stack) (+ idx 1)))
         ((< k 0)
          (if (topIs stack (- 0 k))
            (if (listEmpty? (popStack stack)) idx (formEnd rest (popStack stack) (+ idx 1)))
            -1))
         (else (if (listEmpty? stack) -1 (formEnd rest stack (+ idx 1))))))))

fn fnSurplus text: String seg: Segment -> (List Tok)
  (let [(toks seg.toks)
        (dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (head (optionOr (listHead toks) dflt))
        (isFn (and (= head.kind 0) (and (= head.col 1) (listContains? (list "fn" "fn!") (optionOr (stringSlice text head.start head.end) "")))))
        (header (filter (fn [(t Tok)] -> Bool (= t.line head.line)) toks))
        (body (listDrop toks (listLength header)))
        (first (optionOr (listHead body) dflt))
        (m (if (> first.kind 0) (formEnd body (list) 0) -1))
        (surplus (listDrop body (+ m 1)))
        (kept (listTake toks (+ (listLength header) (+ m 1))))]
    (if (and isFn
             (and (not (flushLeft toks))
                  (and (= (findDelimError header (list) 0 seg.end).kind "none")
                       (and (>= m 0)
                            (and (not (listEmpty? surplus))
                                 (and (listEmpty? (filter (fn [(t Tok)] -> Bool (>= t.kind 0)) surplus))
                                      (layoutScan kept (list (Frame :col 0 :lastCol -1 :lastLine 0)) 0 seg.firstLine seg.lastLine)))))))
      surplus
      (list)))

fn surplusOptions text: String segs: (List Segment) acc: (List RepairOption) -> (List RepairOption)
  (mt (listHead segs)
    ((none) acc)
    ((some g)
     (surplusOptions text (optionOr (listTail segs) (list))
                     (listAppend acc (map (fn [(t Tok)] -> RepairOption (RepairOption :kind "delete" :tok (delimText t.kind) :with "" :line t.line :col t.col :off t.start :delLen 1 :ins "" :reparents false))
                                          (fnSurplus text g))))))

fn promoteSurplus surplus: (List RepairOption) it: LeftItem -> LeftItem
  (mt (listHead (filter (fn [(o RepairOption)] -> Bool (and (= o.line it.line) (= o.col it.col))) surplus))
    ((none) it)
    ((some o)
     (if (= it.expected "")
       (with it :options (some (cons o (filter (fn [(p RepairOption)] -> Bool (not (sameOption o p))) (optionOr it.options (list))))))
       it)))

fn markReparents o: RepairOption b: Bool -> RepairOption
  (with o :reparents b)

fn dedupeOptions os: (List RepairOption) acc: (List RepairOption) -> (List RepairOption)
  (mt (listHead os)
    ((none) (listReverse acc))
    ((some o) (dedupeOptions (optionOr (listTail os) (list)) (if (listEmpty? (filter (fn [(p RepairOption)] -> Bool (sameOption o p)) acc)) (cons o acc) acc))))

fn leafForms all: (List Tok) toks: (List Tok) stack: (List Tok) acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (mt (listHead toks)
    ((none) acc)
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (k t.kind)]
       (cond
         ((> k 0) (leafForms all rest (cons t stack) acc))
         ((< k 0)
          (mt (listHead stack)
            ((some o) (if (and (= o.kind (- 0 k)) (not (delimBetween all o t)))
                        (leafForms all rest (optionOr (listTail stack) (list)) (cons (pair o.start t.end) acc))
                        (leafForms all rest (optionOr (listTail stack) (list)) acc)))
            ((none) (leafForms all rest stack acc))))
         (else (leafForms all rest stack acc))))))

fn delimBetween toks: (List Tok) o: Tok c: Tok -> Bool
  (not (listEmpty? (filter (fn [(t Tok)] -> Bool (and (not (= t.kind 0)) (and (> t.start o.start) (< t.start c.start)))) toks)))

fn altersLeaf toks: (List Tok) c: Cand leaves: (List (Pair Int64 Int64)) textLen: Int64 -> Bool
  (let [(off (candOffset toks c textLen))]
    (not (listEmpty? (filter (fn [(l (Pair Int64 Int64))] -> Bool
                               (if (= c.kind "insert")
                                 (and (> off (pairFirst l)) (< off (- (pairSecond l) 1)))
                                 (and (>= off (pairFirst l)) (< off (pairSecond l)))))
                             leaves))))

fn sameOption a: RepairOption b: RepairOption -> Bool
  (and (= a.off b.off) (and (= a.delLen b.delLen) (= a.ins b.ins)))

fn tokId t: Tok -> Int64
  (+ (* 2 t.start) (if t.synthetic 1 0))

fn parentsOf toks: (List Tok) stack: (List (Pair Int64 Int64)) acc: (List Elem) -> (List Elem)
  (mt (listHead toks)
    ((none) (listReverse acc))
    ((some t)
     (let [(rest (optionOr (listTail toks) (list)))
           (top (mt (listHead stack) ((some p) (pairFirst p)) ((none) -1)))
           (k t.kind)]
       (cond
         ((> k 0) (parentsOf rest (cons (pair (tokId t) k) stack) (cons (Elem :id (tokId t) :parent top) acc)))
         ((< k 0) (parentsOf rest (popToMatch stack (- 0 k)) acc))
         (else (parentsOf rest stack (cons (Elem :id (tokId t) :parent top) acc)))))))

fn popToMatch stack: (List (Pair Int64 Int64)) k: Int64 -> (List (Pair Int64 Int64))
  (if (listEmpty? (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (pairSecond p) k)) stack))
    stack
    (dropThrough stack k))

fn dropThrough stack: (List (Pair Int64 Int64)) k: Int64 -> (List (Pair Int64 Int64))
  (mt (listHead stack)
    ((none) stack)
    ((some p) (if (= (pairSecond p) k) (optionOr (listTail stack) (list)) (dropThrough (optionOr (listTail stack) (list)) k))))

fn parentsDiffer base: (List Elem) after: (List Elem) -> Bool
  (mt (listHead base)
    ((none) false)
    ((some b)
     (mt (listHead after)
       ((none) false)
       ((some a)
        (cond
          ((< b.id a.id) (parentsDiffer (optionOr (listTail base) (list)) after))
          ((> b.id a.id) (parentsDiffer base (optionOr (listTail after) (list))))
          ((and (>= b.parent -1) (not (= b.parent a.parent))) true)
          (else (parentsDiffer (optionOr (listTail base) (list)) (optionOr (listTail after) (list)))))))))

fn candReparents toks: (List Tok) c: Cand base: (List Elem) textLen: Int64 -> Bool
  (let [(pos (candPos toks c))
        (off (candOffset toks c textLen))
        (after (filter (fn [(x Elem)] -> Bool (= (- x.id (* 2 (/ x.id 2))) 0))
                       (parentsOf (candToks toks c 0 (pairFirst pos) (pairSecond pos) off (list)) (list) (list))))]
    (parentsDiffer base after))

fn editBaseline text: String spanStart: Int64 spanEnd: Int64 old: String -> (List Elem)
  (let [(len (stringLength text))
        (before (str (optionOr (stringSlice text 0 spanStart) "") old (optionOr (stringSlice text spanEnd len) "")))
        (oldLen (bytesLength (stringToBytes old)))
        (delta (- (- spanEnd spanStart) oldLen))
        (bs (src/sourceFromString "<before>" before))
        (btoks (buildToks bs (lx/tokenizeBytes (stringToBytes before)) (list)))
        (mapId (fn [(id Int64)] -> Int64
                 (let [(o (/ id 2))]
                   (cond
                     ((< id 0) id)
                     ((< o spanStart) (* 2 o))
                     ((>= o (+ spanStart oldLen)) (* 2 (+ o delta)))
                     (else -3)))))]
    (filter (fn [(x Elem)] -> Bool (>= x.id 0))
            (map (fn [(x Elem)] -> Elem (Elem :id (mapId x.id) :parent (mapId x.parent))) (parentsOf btoks (list) (list)))))

fn mergedMissing text: String lang: String s: src/Source seg: Segment sites: (List SiteFix) -> SiteResult
  (let [(dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (len (stringLength text))
        (miss (filter (fn [(x SiteFix)] -> Bool (= x.kind "missing")) sites))
        (rest (filter (fn [(x SiteFix)] -> Bool (not (= x.kind "missing"))) sites))
        (at (mt (listHead miss) ((some x) x.at) ((none) dflt)))
        (closers (stringJoin (map (fn [(x SiteFix)] -> String (delimText x.expected)) miss) ""))
        (opt (RepairOption :kind "insert" :tok closers :with "" :line at.endLine :col at.endCol :off at.end :delLen 0 :ins closers :reparents false))
        (ctx (map (fn [(x SiteFix)] -> RepairOption (candOption seg.toks x.cand len)) rest))
        (ok (ctxParses text lang seg (listAppend ctx (list opt))))]
    (SiteResult :item (LeftItem :line at.endLine :col at.endCol :expected closers :near (nearSnippet text s at.endLine at.endCol) :options (some (if ok (list opt) (list)))) :unique (none)))

fn analyzeSegment text: String lang: String s: src/Source seg: Segment spanStart: Int64 spanEnd: Int64 wholeLayout: Bool base: (Option (List Elem)) budget: Int64 -> (List SiteResult)
  (let [(dflt (Tok :kind 0 :start 0 :end 0 :line 1 :col 1 :endLine 1 :endCol 1 :synthetic false))
        (sites (greedySites seg.toks (list) 0 dflt (list)))
        (nMiss (listLength (filter (fn [(x SiteFix)] -> Bool (= x.kind "missing")) sites)))
        (nNormal (if (>= nMiss 2) (- (listLength sites) nMiss) (listLength sites)))
        (normal (map (fn [(k Int64)] -> SiteResult
                       (if (< k budget)
                         (analyzeSite text lang s seg sites k spanStart spanEnd wholeLayout base)
                         (bareSite text s (optionOr (listGet sites k) (SiteFix :cand (Cand :kind "" :index 0 :tokKind 0 :oldKind 0) :kind "" :expected 0 :at dflt)))))
                     (listRange 0 nNormal)))]
    (if (>= nMiss 2) (listAppend normal (list (mergedMissing text lang s seg sites))) normal))

fn bareSite text: String s: src/Source site: SiteFix -> SiteResult
  (let [(at site.at)
        (missing (= site.kind "missing"))
        (line (if missing at.endLine at.line))
        (col (if missing at.endCol at.col))]
    (SiteResult :item (LeftItem :line line :col col :expected (delimText site.expected) :near (nearSnippet text s line col) :options (none)) :unique (none)))

fn analyzeSegments text: String lang: String s: src/Source segs: (List Segment) spanStart: Int64 spanEnd: Int64 wholeLayout: Bool base: (Option (List Elem)) budget: Int64 acc: (List SiteResult) -> (List SiteResult)
  (mt (listHead segs)
    ((none) acc)
    ((some g)
     (let [(rs (analyzeSegment text lang s g spanStart spanEnd wholeLayout base budget))
           (left (- budget (listLength rs)))]
       (analyzeSegments text lang s (optionOr (listTail segs) (list)) spanStart spanEnd wholeLayout base (if (< left 0) 0 left) (listAppend acc rs)))))

fn listRange a: Int64 b: Int64 -> (List Int64)
  (if (>= a b) (list) (cons a (listRange (+ a 1) b)))

fn repairAlternatives text: String lang: String -> (List String)
  (let [(s (src/sourceFromString "<input>" text))
        (len (stringLength text))
        (toks (buildToks s (lx/tokenizeBytes (stringToBytes text)) (list)))
        (segs (map makeSegment (splitSegments text toks 0 (list) (list))))
        (bad (filter (fn [(g Segment)] -> Bool (not (= (findDelimError g.toks (list) 0 g.end).kind "none"))) segs))]
    (mt (listHead bad)
      ((none) (list))
      ((some seg)
       (let [(stoks seg.toks)
             (e (findDelimError stoks (list) 0 seg.end))
             (r (Region :start seg.start :end e.end :firstLine seg.firstLine :lastLine seg.lastLine))
             (pres (buildPrefix stoks (some (list)) (list)))
             (sufs (buildSuffix (listReverse stoks) (some (list)) (list (some (list)))))
             (bounds (buildBounds pres sufs stoks (none) 0 (list)))
             (cands (filter (fn [(c Cand)] -> Bool (candLayoutOk stoks c r len)) (enumerateBalanced bounds r e (list))))]
         (map (fn [(c Cand)] -> String (applyCand text stoks c)) (parsingUpTo text lang seg stoks cands 64 (list)))))))

fn parsePicks p: String -> (Option (List (Pair Int64 Int64)))
  (let [(words (filter (fn [(w String)] -> Bool (not (= w ""))) (stringSplit (stringTrim p) " ")))
        (pairs (map (fn [(w String)] -> (Option (Pair Int64 Int64))
                      (let [(parts (stringSplit w "."))]
                        (if (= (listLength parts) 2)
                          (mt (stringToInt64 (optionOr (listGet parts 0) ""))
                            ((some k) (mt (stringToInt64 (optionOr (listGet parts 1) "")) ((some n) (some (pair k n))) ((none) (none))))
                            ((none) (none)))
                          (none))))
                    words))]
    (if (or (listEmpty? pairs) (not (listEmpty? (filter (fn [(x (Option (Pair Int64 Int64)))] -> Bool (not (some? x))) pairs))))
      (none)
      (some (map (fn [(x (Option (Pair Int64 Int64)))] -> (Pair Int64 Int64) (optionOr x (pair 0 0))) pairs))))

fn pickedOption items: (List LeftItem) k: Int64 n: Int64 -> (Option RepairOption)
  (mt (listGet items (- k 1))
    ((none) (none))
    ((some it) (mt it.options ((some os) (listGet os (- n 1))) ((none) (none)))))

fn applyOptionsLoop text: String os: (List RepairOption) -> String
  (mt (listHead os)
    ((none) text)
    ((some o) (applyOptionsLoop (applyOption text o) (optionOr (listTail os) (list)))))

fn optionsItems os: (List RepairOption) acc: (List RepairedItem) -> (List RepairedItem)
  (mt (listHead os)
    ((none) acc)
    ((some o) (optionsItems (optionOr (listTail os) (list)) (listAppend acc (optionItems o)))))

fn textParses text: String lang: String -> Bool
  (let [(s (src/sourceFromString "<input>" text))
        (toks (buildToks s (lx/tokenizeBytes (stringToBytes text)) (list)))]
    (and (= (findDelimError toks (list) 0 (stringLength text)).kind "none")
         (not (langHasErrors (parseInLang text lang) lang))))

fn pickReceipt repaired: (List RepairedItem) left: (List LeftItem) pick: String parses: Bool -> String
  (let [(base (formatReceipt repaired left))]
    (str (optionOr (stringSlice base 0 (- (stringLength base) 1)) "") " :pick \"" (escapeAsnString pick) "\"" (if parses "" " :pickParses false") ")"))

fn applyPicks text: String lang: String items: (List LeftItem) pick: String -> RepairResult
  (let [(chosen (mt (parsePicks pick)
                  ((none) (none))
                  ((some ps)
                   (let [(os (map (fn [(p (Pair Int64 Int64))] -> (Option RepairOption) (pickedOption items (pairFirst p) (pairSecond p))) ps))]
                     (if (listEmpty? (filter (fn [(o (Option RepairOption))] -> Bool (not (some? o))) os))
                       (some (map (fn [(o (Option RepairOption))] -> RepairOption (optionOr o (RepairOption :kind "" :tok "" :with "" :line 0 :col 0 :off 0 :delLen 0 :ins "" :reparents false))) os))
                       (none))))))]
    (mt chosen
      ((some os)
       (let [(next (applyOptions text os))]
         (if (textParses next lang)
           (let [(done (optionsItems os (list)))]
             (makeRepairResult next done (list) (pickReceipt done (list) pick true)))
           (makeRepairResult text (list) items (pickReceipt (list) items pick false)))))
      ((none) (makeRepairResult text (list) items (pickReceipt (list) items pick false)))))

fn repairCore text: String lang: String spanStart: Int64 spanEnd: Int64 wholeLayout: Bool pick: String base: (Option (List Elem)) trimOk: Bool -> RepairResult
  (let [(root (parseInLang text lang))
        (s (src/sourceFromString "<input>" text))
        (len (stringLength text))
        (raw (lx/tokenizeBytes (stringToBytes text)))
        (toks (buildToks s raw (list)))
        (e (findDelimError toks (list) 0 len))
        (treeErrs (langTreeErrors root lang))]
    (mt (firstLexError raw)
      ((some bad)
       (let [(pos (posAt s bad.start))
             (item (LeftItem :line (pairFirst pos) :col (pairSecond pos) :expected "\"" :near (nearSnippet text s (pairFirst pos) (pairSecond pos)) :options (none)))]
         (leftResult text (dedupeLeftItems (cons item (collectLeftItems text s treeErrs (list))) (list) (list)))))
      ((none)
       (cond
         ((and (= e.kind "none") (not (langHasErrors root lang))) (makeRepairResult text (list) (list) "(:repaired () :left ())"))
         ((or (= e.kind "none") (hasUnrepairableError treeErrs)) (leftResult text (leftFor text s root lang e)))
         (else
          (let [(segs (map makeSegment (splitSegments text toks 0 (list) (list))))
                (surplus (if (or (isAsnLang lang) (not trimOk)) (list) (surplusOptions text segs (list))))
                (trimmed (applyOptions text surplus))]
            (if (and (= (stringTrim pick) "") (and (not (listEmpty? surplus)) (textParses trimmed lang)))
              (let [(done (optionsItems surplus (list)))]
                (makeRepairResult trimmed done (list) (formatReceipt done (list))))
              (let [(ordered (analyzeSegments text lang s segs spanStart spanEnd wholeLayout base (if (= (stringTrim pick) "") 5 1000000) (list)))
                    (items (map (fn [(x SiteResult)] -> LeftItem (promoteSurplus surplus x.item)) ordered))]
                (cond
                  ((listEmpty? items) (leftResult text (leftFor text s root lang e)))
                  ((not (= (stringTrim pick) "")) (applyPicks text lang items pick))
                  (else
                   (let [(only (if (= (listLength ordered) 1) (mt (listHead ordered) ((some x) x.unique) ((none) (none))) (none)))]
                     (mt only
                       ((some o)
                        (let [(next (applyOption text o))]
                          (if (textParses next lang)
                            (let [(done (optionItems o))]
                              (makeRepairResult next done (list) (formatReceipt done (list))))
                            (leftResult text items))))
                       ((none) (leftResult text items))))))))))))))

fn repairTextInSpan text: String lang: String spanStart: Int64 spanEnd: Int64 -> RepairResult
  (repairCore text lang spanStart spanEnd false "" (none) true)

fn repairTextPick text: String lang: String spanStart: Int64 spanEnd: Int64 pick: String -> RepairResult
  (if (< spanStart 0)
    (repairCore text lang 0 (stringLength text) true pick (none) true)
    (repairCore text lang spanStart spanEnd false pick (none) true))

fn delimCounts text: String -> (Pair Int64 Int64)
  (let [(ks (map (fn [(t tr/Token)] -> Int64 (delimKindOf t.kind)) (lx/tokenizeBytes (stringToBytes text))))]
    (pair (listLength (filter (fn [(k Int64)] -> Bool (> k 0)) ks)) (listLength (filter (fn [(k Int64)] -> Bool (< k 0)) ks))))

fn addsClosers new: String old: String -> Bool
  (let [(n (delimCounts new))
        (o (delimCounts old))
        (dOpen (- (pairFirst n) (pairFirst o)))
        (dClose (- (pairSecond n) (pairSecond o)))]
    (and (>= dOpen 0) (> dClose dOpen)))

fn repairEdit text: String lang: String spanStart: Int64 spanEnd: Int64 old: String pick: String -> RepairResult
  (repairCore text lang spanStart spanEnd false pick (some (editBaseline text spanStart spanEnd old)) (addsClosers (optionOr (stringSlice text spanStart spanEnd) "") old))

fn commentFollows text: String off: Int64 -> Bool
  (let [(rest (optionOr (stringSlice text off (stringLength text)) ""))
        (line (optionOr (listHead (stringSplit rest "\n")) ""))]
    (stringStartsWith? (stringTrim line) ";"))

fn atSiteOption text: String s: src/Source it: LeftItem -> (Option RepairOption)
  (mt (listHead (filter (fn [(o RepairOption)] -> Bool (and (= o.line it.line) (= o.col it.col))) (optionOr it.options (list))))
    ((none) (none))
    ((some o)
     (if (and (= o.kind "insert") (and (> (stringLength it.expected) 0) (commentFollows text o.off)))
       (let [(len (stringLength text))
             (pos (posAt s len))]
         (some (RepairOption :kind "insert" :tok o.tok :with "" :line (pairFirst pos) :col (pairSecond pos) :off len :delLen 0 :ins o.ins :reparents false)))
       (some o))))

fn repairAtSite text: String lang: String -> RepairResult
  (let [(res (repairText text lang))
        (left res.left)
        (s (src/sourceFromString "<input>" text))
        (picks (map (fn [(it LeftItem)] -> (Option RepairOption) (atSiteOption text s it)) left))]
    (if (or (listEmpty? left) (not (listEmpty? (filter (fn [(o (Option RepairOption))] -> Bool (not (some? o))) picks))))
      res
      (let [(os (map (fn [(o (Option RepairOption))] -> RepairOption (optionOr o (RepairOption :kind "" :tok "" :with "" :line 0 :col 0 :off 0 :delLen 0 :ins "" :reparents false))) picks))
            (next (applyOptions text os))]
        (if (textParses next lang)
          (let [(done (optionsItems os (list)))]
            (makeRepairResult next done (list) (formatReceipt done (list))))
          res))))

fn repairText text: String lang: String -> RepairResult
  (repairCore text lang 0 (stringLength text) true "" (none) true)

fn repair text: String lang: String -> RepairResult
  (repairText text lang)

fn repairReceipt text: String lang: String -> String
  (repairText text lang).receipt
