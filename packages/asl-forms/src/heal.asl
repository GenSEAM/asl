(module asl-forms/heal
  :x [HealResult Sx Edit healRuleNames healSource healSourceWith healSourceRules heal! healDiags healScore lowerDiags readSx applyEdits
      preludeVocab! vocabFromSource formatHealReceipt diagText symbolCandidates editDistance retiredHeadFor healSourceEnv ruleRetiredSpelling ruleImportAdd]
  :i [(asl-parser/ast :a a) (asl-checker/types :a ty) (asl-checker/check :a chk) (asl-checker/resolve :a r) (asl-forms/repair :a rep) (asl-checker/hints :a hn) (asl-forms/indent :a ind)])

; (:m :do "the one heal pipeline for generated ASL (HEAL 2026-10-15): a text that already checks and lowers is returned unchanged; otherwise named rules run in order and an edit is kept only when it strictly lowers the diagnostic score, until no rule improves; the receipt is (:repaired (rule ...) :left (diag ...))")

(schema HealResult (:f text String) (:f repaired (List String)) (:f left (List ty/Diagnostic)) (:f receipt String) (:f changed Bool))

(enum Sx
  (:c sxAtom [(text String) (start Int64) (end Int64)] "an atom or string literal with its byte span")
  (:c sxList [(open Int64) (items (List Sx)) (start Int64) (end Int64)] "a delimited list: open is the opener byte, end is one past the closer"))

(schema Edit (:f start Int64) (:f end Int64) (:f with String))

fn healRuleNames -> (List String)
  (list "bareForm" "delimiterBalance" "indentBalance" "lineHeader" "freeComment" "retiredSpelling" "fnHeaderUnwrap" "headerParens" "bodyIndent" "condClauses" "letBindingVector" "testPredicate" "argShape" "exportAdd" "importAdd" "symbolRename" "effectMark")

; (:m :do "reader: byte-offset S-expressions; strings and ; comments are skipped as atoms/blank so edits never land inside them")

fn spaceByte? b: Int64 -> Bool
  (or (= b 32) (or (= b 10) (or (= b 9) (= b 13))))

fn openByte? b: Int64 -> Bool
  (or (= b 40) (or (= b 91) (= b 123)))

fn closeByte? b: Int64 -> Bool
  (or (= b 41) (or (= b 93) (= b 125)))

fn tailrec lineEndAt bs: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) 10) i) (else (lineEndAt bs n (+ i 1))))

fn tailrec skipBlank bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((spaceByte? (bytesGet bs i)) (skipBlank bs n (+ i 1)))
    ((= (bytesGet bs i) 59) (skipBlank bs n (lineEndAt bs n i)))
    (else i))

fn tailrec stringEndAt bs: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) 92) (stringEndAt bs n (+ i 2))) ((= (bytesGet bs i) 34) (+ i 1)) (else (stringEndAt bs n (+ i 1))))

fn tailrec atomEndAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n)
    n
    (let [(b (bytesGet bs i))]
      (if (or (spaceByte? b) (or (openByte? b) (or (closeByte? b) (or (= b 34) (= b 59))))) i (atomEndAt bs n (+ i 1)))))

fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn readSeq text: String bs: Bytes n: Int64 i0: Int64 acc: (List Sx) -> (Pair (List Sx) Int64)
  (let [(i (skipBlank bs n i0))]
    (cond
      ((>= i n) (pair (listReverse acc) n))
      ((closeByte? (bytesGet bs i)) (pair (listReverse acc) (+ i 1)))
      ((openByte? (bytesGet bs i))
        (let [(inner (readSeq text bs n (+ i 1) (list)))
              (node (sxList (bytesGet bs i) (pairFirst inner) i (pairSecond inner)))]
          (readSeq text bs n (pairSecond inner) (cons node acc))))
      ((= (bytesGet bs i) 34)
        (let [(e (stringEndAt bs n (+ i 1)))]
          (readSeq text bs n e (cons (sxAtom (slice text i e) i e) acc))))
      (else
        (let [(e (atomEndAt bs n i))]
          (readSeq text bs n e (cons (sxAtom (slice text i e) i e) acc))))))

fn readSx text: String -> (List Sx)
  (let [(bs (stringToBytes text))]
    (pairFirst (readSeq text bs (bytesLength bs) 0 (list))))

fn sxStart x: Sx -> Int64
  (match x ((sxAtom _ s _) s) ((sxList _ _ s _) s))

fn sxEnd x: Sx -> Int64
  (match x ((sxAtom _ _ e) e) ((sxList _ _ _ e) e))

fn atomText x: Sx -> String
  (match x ((sxAtom t _ _) t) ((sxList _ _ _ _) ""))

fn listItems x: Sx -> (List Sx)
  (match x ((sxAtom _ _ _) (list)) ((sxList _ items _ _) items))

fn parenList? x: Sx -> Bool
  (match x ((sxAtom _ _ _) false) ((sxList o _ _ _) (= o 40)))

fn bracketList? x: Sx -> Bool
  (match x ((sxAtom _ _ _) false) ((sxList o _ _ _) (= o 91)))

fn headIs? x: Sx name: String -> Bool
  (match (listHead (listItems x)) ((some h) (= (atomText h) name)) ((none) false))

fn allLists x: Sx -> (List Sx)
  (match x
    ((sxAtom _ _ _) (list))
    ((sxList _ items _ _) (cons x (fold (fn [(acc (List Sx)) (c Sx)] -> (List Sx) (listAppend acc (allLists c))) (list) items))))

fn allAtoms x: Sx -> (List Sx)
  (match x
    ((sxAtom _ _ _) (list x))
    ((sxList _ items _ _) (fold (fn [(acc (List Sx)) (c Sx)] -> (List Sx) (listAppend acc (allAtoms c))) (list) items)))

fn forestLists forest: (List Sx) -> (List Sx)
  (fold (fn [(acc (List Sx)) (x Sx)] -> (List Sx) (listAppend acc (allLists x))) (list) forest)

fn forestAtoms forest: (List Sx) -> (List Sx)
  (fold (fn [(acc (List Sx)) (x Sx)] -> (List Sx) (listAppend acc (allAtoms x))) (list) forest)

; (:m :do "edits: sorted by start (an insertion before a replacement at the same offset), an edit overlapping the previously kept one is dropped (a later round takes it), then applied right to left")

fn tailrec keepDisjoint es: (List Edit) lastEnd: Int64 acc: (List Edit) -> (List Edit)
  (match (listHead es)
    ((none) (listReverse acc))
    ((some e) (let [(rest (optionOr (listTail es) (list)))]
                (if (< e.start lastEnd) (keepDisjoint rest lastEnd acc) (keepDisjoint rest (max lastEnd e.end) (cons e acc))))))

fn applyEdits text: String es: (List Edit) -> String
  (let [(sorted (keepDisjoint (listSortBy (fn [(e Edit)] -> Int64 (+ (* e.start 2) (if (= e.start e.end) 0 1))) es) 0 (list)))]
    (fold (fn [(t String) (e Edit)] -> String (str (slice t 0 e.start) e.with (slice t e.end (stringLength t))))
          text (listReverse sorted)))

fn ins at: Int64 s: String -> Edit
  (Edit :start at :end at :with s)

fn repl x: Sx s: String -> Edit
  (Edit :start (sxStart x) :end (sxEnd x) :with s)

fn openerEdit x: Sx s: String -> Edit
  (Edit :start (sxStart x) :end (+ (sxStart x) 1) :with s)

fn closerEdit x: Sx s: String -> Edit
  (Edit :start (- (sxEnd x) 1) :end (sxEnd x) :with s)

; (:m :do "diagnostics and score: checker diagnostics plus the lowering-subset shapes the native compiler refuses although the checker accepts them")

fn diagOf code: String msg: String line: Int64 col: Int64 path: String -> ty/Diagnostic
  (ty/Diagnostic :code code :message msg :msg msg :line line :col col :path path)

fn tailrec lineOfLoop bs: Bytes i: Int64 at: Int64 line: Int64 -> Int64
  (cond ((>= i at) line) ((= (bytesGet bs i) 10) (lineOfLoop bs (+ i 1) at (+ line 1))) (else (lineOfLoop bs (+ i 1) at line)))

fn lineOf text: String at: Int64 -> Int64
  (let [(bs (stringToBytes text))] (lineOfLoop bs 0 (min at (bytesLength bs)) 1))

fn lowerDiags text: String path: String -> (List ty/Diagnostic)
  (map (fn [(x Sx)] -> ty/Diagnostic (diagOf "ERR_LOWER_UNSUPPORTED" "'let' without a binding vector is outside the lowered subset" (lineOf text (sxStart x)) 1 path))
       (filter (fn [(x Sx)] -> Bool (and (parenList? x) (and (headIs? x "let") (match (listGet (listItems x) 1) ((some b) (parenList? b)) ((none) false)))))
               (forestLists (readSx text))))

fn checkText text: String deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (match (a/parseForTypeCheck text)
    ((err pe) (list (diagOf "parse" pe.msg pe.line pe.col path)))
    ((ok forms) (let [(ds (chk/checkModuleSource forms deps path text))]
                  (if (listEmpty? ds) (exportLint forms deps path) ds))))

; (:m :do "STATICHINT gap 3: the checker filters rule-13 (an exported fn names a type this module declares but does not export) out of check as a lint; a model reply that is otherwise clean still breaks every importer, so heal reads it unfiltered, only once nothing else is wrong")
fn exportLint forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-13")) (chk/checkModule forms deps path))

fn healDiags text: String deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (let [(ds (checkText text deps path))]
    (if (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "parse")) ds) ds (listAppend ds (lowerDiags text path))))

fn typePhase? code: String -> Bool
  (or (= code "ERR_TYPE_MISMATCH") (or (= code "ERR_UNTYPED_PARAM") (= code "ERR_INVALID_MT_ARM")))

fn delimiterMessage? m: String -> Bool
  (or (stringContains? m "unmatched") (or (stringContains? m "unclosed") (stringContains? m "unbalanced")))

; (:m :do "a delimiter failure outweighs any other parse failure, which outweighs any number of resolution errors, which outweigh type errors: fixing an unbound name may surface type errors the checker hid behind it")
fn healScore ds: (List ty/Diagnostic) -> Int64
  (fold (fn [(acc Int64) (d ty/Diagnostic)] -> Int64 (+ acc (cond ((and (= d.code "parse") (delimiterMessage? d.message)) 20000) ((= d.code "parse") 10000) ((typePhase? d.code) 1) (else 100)))) 0 ds)

fn diagText d: ty/Diagnostic -> String
  (str d.code " " (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " " d.message)

; (:m :do "rule delimiterBalance: the layout-aware delimiter repair of asl-forms/repair, kept only when it leaves nothing over")
fn ruleDelimiterBalance text: String -> (List String)
  (let [(res (rep/repairAtSite text "asl"))]
    (if (listEmpty? (rep/repairResultLeft res)) (list (rep/repairResultText res)) (list)))

; (:m :do "rule lineHeader: the paren-free header lines (module X / doc \"...\" / exports a, b) become (module X :x [a b]) with the doc kept as a meta comment")
fn headerValue lines: (List String) key: String -> (Option String)
  (match (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l (str key " "))) lines))
    ((some l) (some (stringTrim (slice l (+ (stringLength key) 1) (stringLength l)))))
    ((none) none))

fn headerLine? l: String -> Bool
  (or (stringStartsWith? l "module ") (or (stringStartsWith? l "doc ") (or (stringStartsWith? l "exports ") (stringEmpty? (stringTrim l)))))

fn tailrec takeWhileLoop p: (fn [String] -> Bool) xs: (List String) acc: (List String) -> (List String)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some x) (if (p x) (takeWhileLoop p (optionOr (listTail xs) (list)) (cons x acc)) (listReverse acc))))

fn ruleLineHeader text: String -> (List String)
  (let [(lines (stringLines text))
        (headLen (listLength (takeWhileLoop headerLine? lines (list))))
        (head (optionOr (listSlice lines 0 headLen) (list)))
        (body (listDrop lines headLen))]
    (match (headerValue head "module")
      ((none) (list))
      ((some name)
        (let [(exports (match (headerValue head "exports") ((some e) (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit (stringReplace e "," " ") " "))) ((none) (list))))
              (doc (match (headerValue head "doc") ((some d) (list (str "; (:m :doc " d ")"))) ((none) (list))))]
          (list (stringJoin (listAppend (cons (str "(module " name " :x [" (stringJoin exports " ") "])") doc) (cons "" body)) "\n"))))))

; (:m :do "rule freeComment: a free ; comment line, retired by the reader (ERR_READ_COMMENT), becomes the one-line meta form ; (:m :note \"...\")")
fn freeCommentLine l: String -> String
  (let [(ind (indentOf l))
        (body (stringTrim (slice l ind (stringLength l))))]
    (if (and (stringStartsWith? body ";") (not (stringStartsWith? (stringTrim (stringReplace body ";" " ")) "(:m")))
      (str (stringRepeat " " ind) "; (:m :note " (quoteAsn (stringTrim (stringReplace body ";" ""))) ")")
      l))

fn ruleFreeComment text: String -> (List String)
  (let [(next (stringJoin (map freeCommentLine (stringLines text)) "\n"))]
    (if (= next text) (list) (list next)))

; (:m :do "rule retiredSpelling, a normal form applied once before the scored rules because a retired head hides every other diagnostic behind one parse error: the head of a form spelled (mt ...), (== ...) or (not= ...), retired by the reader (ERR_READ_SPELLING), becomes match, = or !=")
fn retiredHeadFor name: String -> (Option String)
  (cond ((= name "mt") (some "match"))
        ((= name "==") (some "="))
        ((= name "not=") (some "!="))
        ((= name "%") (some "mod"))
        (else (none)))

fn retiredSpellingEdit x: Sx -> (List Edit)
  (match (listHead (listItems x))
    ((none) (list))
    ((some h)
      (match (retiredHeadFor (atomText h))
        ((none) (list))
        ((some to) (match h ((sxAtom _ s e) (list (Edit :start s :end e :with to))) ((sxList _ _ _ _) (list)))))))

fn spellNormal text: String rules: (List String) -> String
  (if (listContains? rules "retiredSpelling") (optionOr (listHead (ruleRetiredSpelling text)) text) text)

fn spellApplied before: String after: String -> (List String)
  (if (= before after) (list) (list "retiredSpelling"))

fn ruleRetiredSpelling text: String -> (List String)
  (let [(es (fold (fn [(acc (List Edit)) (x Sx)] -> (List Edit) (listAppend acc (retiredSpellingEdit x))) (list) (listFlatMap allLists (readSx text))))]
    (if (listEmpty? es) (list) (list (applyEdits text es))))

; (:m :do "rule fnHeaderUnwrap: a top-level (fn name p: T -> R body) written in header style becomes the header line with its body indented below")
fn headerStyleFn? x: Sx -> Bool
  (and (parenList? x)
    (and (headIs? x "fn")
      (let [(items (listItems x))
            (afterBang (if (match (listGet items 1) ((some b) (= (atomText b) "!")) ((none) false)) 2 1))]
        (match (listGet items (+ afterBang 1)) ((some p) (not (bracketList? p))) ((none) false)))))

fn unwrapEdits text: String x: Sx -> (List Edit)
  (let [(items (listItems x))]
    (match (listIndexOf (map atomText items) "->")
      ((none) (list))
      ((some ai)
        (match (listGet items (+ ai 2))
          ((none) (list))
          ((some body)
            (let [(retEnd (sxEnd (optionOr (listGet items (+ ai 1)) body)))
                  (gap (slice text retEnd (sxStart body)))]
              (list (openerEdit x "") (closerEdit x "")
                    (if (stringContains? gap "\n") (ins (sxStart body) "") (Edit :start retEnd :end (sxStart body) :with "\n  ")))))))))

fn ruleFnHeaderUnwrap text: String -> (List String)
  (let [(es (fold (fn [(acc (List Edit)) (x Sx)] -> (List Edit) (if (headerStyleFn? x) (listAppend acc (unwrapEdits text x)) acc)) (list) (readSx text)))]
    (if (listEmpty? es) (list) (list (applyEdits text es))))

; (:m :do "rule bodyIndent: a defun body at column zero (which the parser cannot attach to its header; any deeper indent opens the block) is shifted right until its least-indented line sits at two")
fn tailrec skipSpacesOnly bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (= (bytesGet bs i) 32)) (skipSpacesOnly bs n (+ i 1)) i)

fn indentOf l: String -> Int64
  (let [(bs (stringToBytes l))] (skipSpacesOnly bs (bytesLength bs) 0))

fn fnHeaderLine? l: String -> Bool
  (stringStartsWith? l "fn ")

fn blockEnd lines: (List String) from: Int64 -> Int64
  (let [(n (listLength lines))]
    (optionOr (listHead (filter (fn [(i Int64)] -> Bool (let [(l (optionOr (listGet lines i) ""))] (or (fnHeaderLine? l) (stringStartsWith? l "(module")))) (range from n))) n))

fn reindentBlock lines: (List String) hdr: Int64 -> (List String)
  (let [(stop (blockEnd lines (+ hdr 1)))
        (block (optionOr (listSlice lines (+ hdr 1) stop) (list)))
        (nonBlank (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) block))
        (least (fold (fn [(m Int64) (l String)] -> Int64 (min m (indentOf l))) 1000 nonBlank))
        (shift (- 2 least))]
    (if (or (listEmpty? nonBlank) (<= shift 0))
      lines
      (listAppend (optionOr (listSlice lines 0 (+ hdr 1)) (list))
        (listAppend (map (fn [(l String)] -> String (if (stringEmpty? (stringTrim l)) l (str (stringRepeat " " shift) l))) block)
          (listDrop lines stop)))))

fn ruleBodyIndent text: String -> (List String)
  (let [(lines (stringLines text))
        (hdrs (filter (fn [(i Int64)] -> Bool (fnHeaderLine? (optionOr (listGet lines i) ""))) (range 0 (listLength lines))))
        (next (stringJoin (fold reindentBlock lines hdrs) "\n"))]
    (if (= next text) (list) (list next)))

; (:m :ref FIX-COND-SHAPE-20261016 :do "rule condClauses: [test expr] clauses become (test expr), a wrapped [(else x)] or ((else x)) loses its outer delimiters, an else swallowed by the last clause is hoisted out, a flat (cond t1 e1 t2 e2 (else x)) is paired into clauses, and a two-item clause whose test and value are reversed is tried swapped one clause at a time, kept only when the swap strictly lowers the diagnostic score")
fn elseItem? x: Sx -> Bool
  (or (headIs? x "else") (headIs? x ":else"))

fn wrappedElse? c: Sx -> Bool
  (and (= (listLength (listItems c)) 1) (elseItem? (optionOr (listHead (listItems c)) c)))

fn bracketClauseEdits c: Sx -> (List Edit)
  (cond
    ((and (or (bracketList? c) (parenList? c)) (wrappedElse? c)) (list (openerEdit c "") (closerEdit c "")))
    ((bracketList? c) (list (openerEdit c "(") (closerEdit c ")")))
    (else (list)))

fn nestedElseEdits c: Sx -> (List Edit)
  (let [(items (listItems c))
        (k (listLength items))]
    (if (and (parenList? c) (and (>= k 3) (elseItem? (optionOr (listLast items) c))))
      (list (ins (sxEnd (optionOr (listGet items (- k 2)) c)) ")") (closerEdit c ""))
      (list)))

fn tailrec flatPairEdits cs: (List Sx) acc: (List Edit) -> (List Edit)
  (match (listHead cs)
    ((none) acc)
    ((some t)
      (let [(rest (optionOr (listTail cs) (list)))]
        (cond
          ((= (atomText t) "else") (match (listHead rest) ((some e) (listAppend acc (list (ins (sxStart t) "(") (ins (sxEnd e) ")")))) ((none) acc)))
          ((= (atomText t) ":else") (match (listHead rest) ((some e) (listAppend acc (list (repl t "(else") (ins (sxEnd e) ")")))) ((none) acc)))
          ((elseItem? t) acc)
          (else (match (listHead rest)
                  ((some e) (flatPairEdits (optionOr (listTail rest) (list)) (listAppend acc (list (ins (sxStart t) "(") (ins (sxEnd e) ")")))))
                  ((none) acc)))))))

fn condEdits mode: String x: Sx -> (List Edit)
  (let [(clauses (optionOr (listTail (listItems x)) (list)))]
    (cond
      ((= mode "flat") (flatPairEdits clauses (list)))
      ((= mode "else") (match (listLast clauses) ((some c) (nestedElseEdits c)) ((none) (list))))
      (else (fold (fn [(acc (List Edit)) (c Sx)] -> (List Edit) (listAppend acc (bracketClauseEdits c))) (list) clauses))))

fn condRewrite text: String mode: String -> (List String)
  (let [(conds (filter (fn [(x Sx)] -> Bool (and (parenList? x) (headIs? x "cond"))) (forestLists (readSx text))))
        (es (fold (fn [(acc (List Edit)) (x Sx)] -> (List Edit) (listAppend acc (condEdits mode x))) (list) conds))]
    (if (listEmpty? es) (list) (list (applyEdits text es))))

; (:m :do "rule condClauses, swap candidates: a two-item (test value) clause written (value test) is only ever a guess, one candidate text per clause rather than one combined edit, since swapping an already-correct clause would make a working cond worse; firstImproving keeps a candidate only when it strictly lowers the diagnostic score, so a wrong guess is dropped and the checker's own cond-test/else-branch diagnostic is what is left to name the shape")
fn swappableClause? c: Sx -> Bool
  (and (parenList? c) (and (not (elseItem? c)) (= (listLength (listItems c)) 2)))

fn swapCandidateAt text: String c: Sx -> (Option String)
  (match (listGet (listItems c) 0)
    ((none) none)
    ((some a)
      (match (listGet (listItems c) 1)
        ((none) none)
        ((some b)
          (some (applyEdits text (list (repl a (slice text (sxStart b) (sxEnd b))) (repl b (slice text (sxStart a) (sxEnd a))))))))))

fn condSwapCandidates text: String -> (List String)
  (let [(conds (filter (fn [(x Sx)] -> Bool (and (parenList? x) (headIs? x "cond"))) (forestLists (readSx text))))
        (clauses (fold (fn [(acc (List Sx)) (x Sx)] -> (List Sx) (listAppend acc (optionOr (listTail (listItems x)) (list)))) (list) conds))
        (swappable (filter swappableClause? clauses))]
    (filter (fn [(s String)] -> Bool (!= s text))
      (map (fn [(c Sx)] -> String (optionOr (swapCandidateAt text c) text)) swappable)))

fn ruleCondClauses text: String -> (List String)
  (listAppend (condRewrite text "brackets") (listAppend (condRewrite text "else") (listAppend (condRewrite text "flat") (condSwapCandidates text))))

; (:m :do "rule letBindingVector: (let ((a 1) (b 2)) e) and (let (a 1 b 2) e) become (let [(a 1) (b 2)] e), the only let shape the native lowering takes")
fn pairItem? x: Sx -> Bool
  (and (parenList? x) (= (listLength (listItems x)) 2))

fn tailrec flatBindEdits items: (List Sx) acc: (List Edit) -> (List Edit)
  (match (listHead items)
    ((none) acc)
    ((some name)
      (match (listGet items 1)
        ((none) acc)
        ((some v) (flatBindEdits (listDrop items 2) (listAppend acc (list (ins (sxStart name) "(") (ins (sxEnd v) ")"))))))))

fn letEdits x: Sx -> (List Edit)
  (match (listGet (listItems x) 1)
    ((none) (list))
    ((some g)
      (if (not (parenList? g))
        (list)
        (let [(items (listItems g))
              (k (listLength items))
              (brackets (list (openerEdit g "[") (closerEdit g "]")))]
          (cond
            ((listAll? pairItem? items) brackets)
            ((and (> k 0) (= (mod k 2) 0)) (listAppend brackets (flatBindEdits items (list))))
            (else (list)))))))

fn ruleLetBindingVector text: String -> (List String)
  (let [(lets (filter (fn [(x Sx)] -> Bool (and (parenList? x) (headIs? x "let"))) (forestLists (readSx text))))
        (es (fold (fn [(acc (List Edit)) (x Sx)] -> (List Edit) (listAppend acc (letEdits x))) (list) lets))]
    (if (listEmpty? es) (list) (list (applyEdits text es))))

; (:m :do "rule testPredicate: in a cond or if test, (some x) and (none x) can only mean the presence checks some? and none?; an Option is never a Bool")
fn testHeadEdit t: Sx -> (List Edit)
  (if (and (parenList? t) (= (listLength (listItems t)) 2))
    (let [(h (optionOr (listHead (listItems t)) t))
          (name (atomText h))]
      (cond ((= name "some") (list (repl h "some?"))) ((= name "none") (list (repl h "none?"))) (else (list))))
    (list))

fn testsOf x: Sx -> (List Sx)
  (cond
    ((headIs? x "if") (match (listGet (listItems x) 1) ((some t) (list t)) ((none) (list))))
    ((headIs? x "cond") (fold (fn [(acc (List Sx)) (c Sx)] -> (List Sx) (match (listHead (listItems c)) ((some t) (listAppend acc (list t))) ((none) acc))) (list) (optionOr (listTail (listItems x)) (list))))
    (else (list)))

fn ruleTestPredicate text: String -> (List String)
  (let [(tests (fold (fn [(acc (List Sx)) (x Sx)] -> (List Sx) (listAppend acc (testsOf x))) (list) (filter parenList? (forestLists (readSx text)))))
        (es (fold (fn [(acc (List Edit)) (t Sx)] -> (List Edit) (listAppend acc (testHeadEdit t))) (list) tests))]
    (if (listEmpty? es) (list) (list (applyEdits text es))))

; (:m :do "rule symbolRename: an unbound name is replaced by the checker's own renamed-to hint, its current spelling (isSome -> some?, println! -> println, snake or kebab -> camel) or the unique nearest vocabulary name; each candidate is kept only if the score drops")
fn unboundName d: ty/Diagnostic -> (Option String)
  (hn/unboundName d)

fn renamedHintOf d: ty/Diagnostic -> (Option String)
  (match (stringIndexOf d.message "; renamed to ")
    ((none) none)
    ((some i) (listHead (stringSplit (slice d.message (+ i 13) (stringLength d.message)) " "))))

fn lowerFirst s: String -> String
  (str (stringLower (slice s 0 1)) (slice s 1 (stringLength s)))

fn upperFirst s: String -> String
  (str (stringUpper (slice s 0 1)) (slice s 1 (stringLength s)))

fn camelOf s: String -> String
  (let [(parts (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit (stringReplace s "-" "_") "_")))]
    (match (listHead parts) ((some h) (str h (stringJoin (map upperFirst (optionOr (listTail parts) (list))) ""))) ((none) s)))

fn tailrec distRow a: (List String) bc: String prev: (List Int64) j: Int64 left: Int64 diag: Int64 acc: (List Int64) -> (List Int64)
  (match (listHead a)
    ((none) (listReverse acc))
    ((some ac)
      (let [(up (optionOr (listGet prev (+ j 1)) 0))
            (cost (if (= ac bc) 0 1))
            (v (min (+ up 1) (min (+ left 1) (+ diag cost))))]
        (distRow (optionOr (listTail a) (list)) bc prev (+ j 1) v up (cons v acc)))))

fn editDistance x: String y: String -> Int64
  (let [(xs (stringChars x))
        (row0 (range 0 (+ (listLength xs) 1)))
        (last (fold (fn [(prev (List Int64)) (iy (Pair Int64 String))] -> (List Int64)
                       (let [(i (+ (pairFirst iy) 1))] (cons i (distRow xs (pairSecond iy) prev 0 i (- i 1) (list)))))
                     row0 (enumerate (stringChars y))))]
    (optionOr (listLast last) 0))

fn nearestInVocab name: String vocab: (List String) -> (List String)
  (let [(low (stringLower name))
        (same (filter (fn [(v String)] -> Bool (and (!= v name) (= (stringLower v) low))) vocab))]
    (if (not (listEmpty? same))
      same
      (let [(scored (map (fn [(v String)] -> (Pair Int64 String) (pair (editDistance name v) v)) (filter (fn [(v String)] -> Bool (< (abs (- (stringLength v) (stringLength name))) 3)) vocab)))
            (best (fold (fn [(m Int64) (p (Pair Int64 String))] -> Int64 (min m (pairFirst p))) 1000 scored))
            (at (filter (fn [(p (Pair Int64 String))] -> Bool (= (pairFirst p) best)) scored))]
        (if (and (<= best 2) (= (listLength at) 1)) (map pairSecond at) (list)))))

fn symbolCandidates name: String hint: (Option String) vocab: (List String) -> (List String)
  (let [(n (stringLength name))
        (bangless (if (and (> n 1) (stringEndsWith? name "!")) (list (slice name 0 (- n 1))) (list)))
        (isForm (if (and (> n 2) (and (stringStartsWith? name "is") (= (slice name 2 3) (stringUpper (slice name 2 3)))))
                  (list (str (lowerFirst (slice name 2 n)) "?"))
                  (list)))
        (camel (if (or (stringContains? name "_") (stringContains? name "-")) (list (camelOf name)) (list)))
        (hinted (match hint ((some h) (list h)) ((none) (list))))
        (all (listAppend hinted (listAppend bangless (listAppend isForm (listAppend camel (nearestInVocab name vocab))))))]
    (filter (fn [(c String)] -> Bool (and (!= c name) (not (stringEmpty? c)))) all))

fn renameAtoms text: String from: String to: String -> String
  (applyEdits text (map (fn [(x Sx)] -> Edit (repl x to)) (filter (fn [(x Sx)] -> Bool (= (atomText x) from)) (forestAtoms (readSx text)))))

fn ruleSymbolRename text: String ds: (List ty/Diagnostic) vocab: (List String) -> (List String)
  (fold (fn [(acc (List String)) (d ty/Diagnostic)] -> (List String)
          (match (unboundName d)
            ((none) acc)
            ((some name) (listAppend acc (map (fn [(c String)] -> String (renameAtoms text name c)) (listAppend (hn/priorNames name) (symbolCandidates name (renamedHintOf d) vocab)))))))
        (list) ds)

; (:m :do "rules exportAdd and importAdd (STATICHINT 2026-10-28): exportAdd appends to the module header :x a name this text declares when every diagnostic is an export one (rule-13 declared here and not exported, or ERR_NOT_EXPORTED naming this module); importAdd qualifies an unbound name with the alias of the one module whose :x lists it and adds (mod :a alias) to :i; both kept only on a strict score drop like every rule")
fn moduleHeader text: String -> (Option Sx)
  (listHead (filter (fn [(x Sx)] -> Bool (headIs? x "module")) (readSx text)))

fn headerVector hdr: Sx key: String -> (Option Sx)
  (let [(items (listItems hdr))
        (at (listHead (filter (fn [(i Int64)] -> Bool (= (atomText (optionOr (listGet items i) hdr)) key)) (range 0 (listLength items)))))]
    (match at
      ((none) none)
      ((some i) (match (listGet items (+ i 1)) ((some v) (if (bracketList? v) (some v) none)) ((none) none)))))

fn vectorAppendEdit vec: Sx item: String -> Edit
  (match (listLast (listItems vec))
    ((some last) (ins (sxEnd last) (str " " item)))
    ((none) (ins (+ (sxStart vec) 1) item)))

fn exportName d: ty/Diagnostic own: String -> (Option String)
  (cond
    ((stringContains? d.message " is declared here and not exported") (listHead (stringSplit d.message " ")))
    ((and (stringStartsWith? d.message "ERR_NOT_EXPORTED: ") (stringEndsWith? d.message (str " " own)))
      (listHead (stringSplit (slice d.message 18 (stringLength d.message)) " ")))
    (else none))

fn declaredHere? text: String name: String -> Bool
  (or (listContains? (vocabFromSource text (list)) name)
      (or (stringContains? text (str "(schema " name " "))
          (stringContains? text (str "(enum " name "\n"))))

fn ruleExportAdd text: String ds: (List ty/Diagnostic) -> (List String)
  (match (moduleHeader text)
    ((none) (list))
    ((some hdr)
      (let [(own (atomText (optionOr (listGet (listItems hdr) 1) hdr)))
            (names (fold (fn [(acc (List String)) (d ty/Diagnostic)] -> (List String)
                           (match (exportName d own) ((some n) (if (and (declaredHere? text n) (not (listContains? acc n))) (listAppend acc (list n)) acc)) ((none) acc)))
                         (list) ds))
            (allExport (listAll? (fn [(d ty/Diagnostic)] -> Bool (some? (exportName d own))) ds))]
        (match (headerVector hdr ":x")
          ((some vec) (if (and allExport (not (listEmpty? names))) (list (applyEdits text (list (vectorAppendEdit vec (stringJoin names " "))))) (list)))
          ((none) (list))))))

fn aliasFor modName: String -> String
  (optionOr (listLast (stringSplit modName "/")) modName)

fn importedAlias hdr: Sx modName: String -> (Option String)
  (match (headerVector hdr ":i")
    ((none) none)
    ((some vec)
      (listHead (map (fn [(it Sx)] -> String (atomText (optionOr (listGet (listItems it) 2) it)))
                     (filter (fn [(it Sx)] -> Bool (and (parenList? it) (= (atomText (optionOr (listHead (listItems it)) it)) modName))) (listItems vec))))))

fn aliasTaken? hdr: Sx alias: String -> Bool
  (match (headerVector hdr ":i")
    ((none) false)
    ((some vec) (listAny? (fn [(it Sx)] -> Bool (and (parenList? it) (= (atomText (optionOr (listGet (listItems it) 2) it)) alias))) (listItems vec))))

fn importCandidate text: String name: String modName: String -> (List String)
  (match (moduleHeader text)
    ((none) (list))
    ((some hdr)
      (match (importedAlias hdr modName)
        ((some al) (list (renameAtoms text name (str al "/" name))))
        ((none)
          (let [(al (aliasFor modName))
                (item (str "(" modName " :a " al ")"))
                (qualified (renameAtoms text name (str al "/" name)))]
            (if (aliasTaken? hdr al)
              (list)
              (match (moduleHeader qualified)
                ((none) (list))
                ((some h2)
                  (match (headerVector h2 ":i")
                    ((some vec) (list (applyEdits qualified (list (vectorAppendEdit vec item)))))
                    ((none) (match (headerVector h2 ":x") ((some xv) (list (applyEdits qualified (list (ins (sxEnd xv) (str " :i [" item "]")))))) ((none) (list)))))))))))))

fn ruleImportAdd text: String ds: (List ty/Diagnostic) ex: (Map String (List String)) -> (List String)
  (fold (fn [(acc (List String)) (d ty/Diagnostic)] -> (List String)
          (match (unboundName d)
            ((none) acc)
            ((some name)
              (match (mapGet ex name)
                ((some owners) (if (= (listLength owners) 1) (listAppend acc (importCandidate text name (optionOr (listHead owners) ""))) acc))
                ((none) acc)))))
        (list) ds)

fn unboundNames ds: (List ty/Diagnostic) -> (List String)
  (fold (fn [(acc (List String)) (d ty/Diagnostic)] -> (List String) (match (unboundName d) ((some n) (cons n acc)) ((none) acc))) (list) ds)

; (:m :do "rule effectMark: a declaration the checker reports as effectful but unmarked gets the ! after fn")
fn markLine lines: (List String) line: Int64 -> (List String)
  (let [(hdr (optionOr (listLast (filter (fn [(i Int64)] -> Bool (fnHeaderLine? (optionOr (listGet lines i) ""))) (range 0 (min line (listLength lines))))) -1))
        (l (optionOr (listGet lines hdr) ""))]
    (if (or (< hdr 0) (stringStartsWith? l "fn !"))
      lines
      (listAppend (optionOr (listSlice lines 0 hdr) (list)) (cons (str "fn ! " (slice l 3 (stringLength l))) (listDrop lines (+ hdr 1))))))

fn ruleEffectMark text: String ds: (List ty/Diagnostic) -> (List String)
  (let [(marks (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "ERR_EFFECT_UNMARKED")) ds))
        (next (stringJoin (fold (fn [(ls (List String)) (d ty/Diagnostic)] -> (List String) (markLine ls d.line)) (stringLines text) marks) "\n"))]
    (if (= next text) (list) (list next)))

; (:m :ref MISS-ABSORB :do "rule bareForm: a body written the way the header is, without the outer parens and with indentation as the structure (cond / match x / let [...] on a line of their own, a bare call such as go xs 0), gets the parens its indentation states: a line of a fn block that starts with a symbol and has a second item or deeper lines below opens a form, closed at the end of its last deeper line; a line inside an original paren is only taken when its head is a special form or its parent is such a bare line; a second candidate reruns the indentation-guided closer repair, since the closers a model adds after such a body are guesses")
(schema BareLine (:f indent Int64) (:f blank Bool) (:f bare Bool) (:f head String) (:f items Int64) (:f delta Int64))

(schema BareState (:f frames (List (Pair Int64 Int64))) (:f depth Int64) (:f out (List String)) (:f hits Int64))

fn tailrec bareScan bs: Bytes n: Int64 i: Int64 depth: Int64 items: Int64 low: Bool -> (Pair Int64 Int64)
  (if (>= i n)
    (pair items depth)
    (let [(b (bytesGet bs i))
          (more (if (and (= depth 0) (not low)) (+ items 1) items))]
      (cond
        ((spaceByte? b) (bareScan bs n (+ i 1) depth items low))
        ((= b 59) (pair items depth))
        ((= b 34) (bareScan bs n (stringEndAt bs n (+ i 1)) depth more low))
        ((openByte? b) (bareScan bs n (+ i 1) (+ depth 1) more low))
        ((closeByte? b) (bareScan bs n (+ i 1) (- depth 1) items (or low (< depth 1))))
        (else (bareScan bs n (atomEndAt bs n i) depth more low)))))

fn bareHead? head: String -> Bool
  (let [(c (slice head 0 1))]
    (not (or (stringEmpty? head)
             (or (stringContains? "0123456789:\"" c)
                 (or (= head "->") (and (= c "-") (> (stringLength head) 1)))))))

fn bareLine l: String -> BareLine
  (let [(bs (stringToBytes l))
        (n (bytesLength bs))
        (i (skipSpacesOnly bs n 0))
        (blank (or (>= i n) (= (bytesGet bs i) 59)))
        (first (if blank 32 (bytesGet bs i)))
        (head (if (or blank (or (openByte? first) (closeByte? first))) "" (slice l i (atomEndAt bs n i))))
        (scan (bareScan bs n i 0 0 false))]
    (BareLine :indent i :blank blank :bare (bareHead? head) :head head :items (pairFirst scan) :delta (pairSecond scan)))

fn specialHead? head: String -> Bool
  (listContains? (list "let" "cond" "match" "if" "do") head)

fn tailrec codeEndOf bs: Bytes i: Int64 -> Int64
  (if (and (> i 0) (spaceByte? (bytesGet bs (- i 1)))) (codeEndOf bs (- i 1)) i)

fn closeLine l: String k: Int64 -> String
  (let [(bs (stringToBytes l))
        (e (codeEndOf bs (bytesLength bs)))]
    (str (slice l 0 e) (stringRepeat ")" k) (slice l e (stringLength l))))

fn tailrec closeLastLoop out: (List String) k: Int64 kept: (List String) -> (List String)
  (match (listHead out)
    ((none) (listReverse kept))
    ((some l)
      (if (stringEmpty? (stringTrim l))
        (closeLastLoop (optionOr (listTail out) (list)) k (cons l kept))
        (listAppend (listReverse kept) (cons (closeLine l k) (optionOr (listTail out) (list)))))))

fn closeLast out: (List String) k: Int64 -> (List String)
  (if (<= k 0) out (closeLastLoop out k (list)))

fn childBelow? infos: (List BareLine) i: Int64 indent: Int64 -> Bool
  (match (listFind (fn [(b BareLine)] -> Bool (not b.blank)) (listDrop infos (+ i 1)))
    ((some b) (> b.indent indent))
    ((none) false))

fn bareStep infos: (List BareLine) st: BareState il: (Pair Int64 String) -> BareState
  (let [(i (pairFirst il))
        (l (pairSecond il))
        (info (optionOr (listGet infos i) (BareLine :indent 0 :blank true :bare false :head "" :items 0 :delta 0)))]
    (cond
      (info.blank (with st :out (cons l st.out)))
      ((= info.indent 0)
        (BareState :frames (list) :depth 0 :out (cons l (closeLast st.out (listLength st.frames))) :hits st.hits))
      (else
        (let [(gone (filter (fn [(f (Pair Int64 Int64))] -> Bool (>= (pairFirst f) info.indent)) st.frames))
              (frames (filter (fn [(f (Pair Int64 Int64))] -> Bool (< (pairFirst f) info.indent)) st.frames))
              (out (closeLast st.out (listLength gone)))
              (ctx (match (listHead frames) ((some f) (pairSecond f)) ((none) 0)))
              (opens (and info.bare
                          (and (or (>= info.items 2) (childBelow? infos i info.indent))
                               (or (= st.depth ctx) (specialHead? info.head)))))]
          (if opens
            (BareState :frames (cons (pair info.indent st.depth) frames) :depth (+ st.depth info.delta)
                       :out (cons (str (slice l 0 info.indent) "(" (slice l info.indent (stringLength l))) out) :hits (+ st.hits 1))
            (BareState :frames frames :depth (+ st.depth info.delta) :out (cons l out) :hits st.hits))))))

fn tailrec fnBlockFlags lines: (List String) inFn: Bool acc: (List Bool) -> (List Bool)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some l)
      (let [(top (and (not (stringEmpty? (stringTrim l))) (= (indentOf l) 0)))
            (now (if top (fnHeaderLine? l) inFn))]
        (fnBlockFlags (optionOr (listTail lines) (list)) now (cons (and now (not top)) acc)))))

fn bareWrap text: String -> String
  (let [(lines (stringSplit text "\n"))
        (flags (fnBlockFlags lines false (list)))
        (infos (map (fn [(p (Pair String Bool))] -> BareLine
                      (if (pairSecond p) (bareLine (pairFirst p)) (BareLine :indent 0 :blank (stringEmpty? (stringTrim (pairFirst p))) :bare false :head "" :items 0 :delta 0)))
                    (zip lines flags)))
        (end (fold (fn [(st BareState) (il (Pair Int64 String))] -> BareState (bareStep infos st il))
                   (BareState :frames (list) :depth 0 :out (list) :hits 0)
                   (zip (range 0 (listLength lines)) lines)))]
    (if (= end.hits 0) text (stringJoin (listReverse (closeLast end.out (listLength end.frames))) "\n")))

fn ruleBareForm text: String -> (List String)
  (let [(wrapped (bareWrap text))]
    (if (= wrapped text) (list) (list wrapped (ind/guideBroken wrapped).text)))

; (:m :ref MISS-ABSORB :do "rule indentBalance: the indentation-guided closer repair of asl-forms/indent over the items whose delimiters do not balance; it covers the surplus closers at the end of several fn bodies at once, which delimiterBalance leaves when one site has more than one balanced reading, and it only speaks when delimiterBalance has no repair")
fn ruleIndentBalance text: String -> (List String)
  (let [(g (ind/guideBroken text))]
    (if (or (listEmpty? g.edits) (not (listEmpty? (ruleDelimiterBalance text)))) (list) (list g.text)))

; (:m :ref MISS-ABSORB :do "rule headerParens (FABLE-LANG-02): a header whose parameters are wrapped the way Python or TypeScript wrap them, fn f (a: T b: U) -> R or fn f(a: T, b: U) -> R, loses the wrapper and the commas")
fn headerParensLine l: String -> String
  (match (stringIndexOf l "(")
    ((none) l)
    ((some o)
      (let [(before (stringTrim (slice l 0 o)))
            (words (stringSplit before " "))
            (bs (stringToBytes l))
            (n (bytesLength bs))
            (inner (pairSecond (readSeq l bs n (+ o 1) (list))))
            (params (slice l (+ o 1) (- inner 1)))
            (after (stringTrim (slice l inner n)))]
        (if (and (fnHeaderLine? l)
                 (and (<= (listLength words) 4)
                      (and (not (stringContains? before ":"))
                           (and (stringContains? params ": ") (stringStartsWith? after "->")))))
          (str before " " (stringTrim (stringReplace params "," "")) " " after)
          l))))

fn ruleHeaderParens text: String -> (List String)
  (let [(next (stringJoin (map headerParensLine (stringSplit text "\n")) "\n"))]
    (if (= next text) (list) (list next)))

; (:m :ref MISS-ABSORB :do "rule argShape: three argument shapes the checker reports at the function, not at the call, so every site is one candidate and a candidate stays only when the score drops: (listAppend xs x) with an element where a list is due wraps it as (list x); (listTail xs) or (listSlice ...) passed where a list is due, the cdr and xs[1:] prior, becomes (optionOr (listTail xs) (list)); (+ a b) over strings becomes (str a b)")
fn diagHas? ds: (List ty/Diagnostic) a: String b: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (stringContains? d.message a) (stringContains? d.message b))) ds)

fn wrapEdits x: Sx before: String after: String -> (List Edit)
  (list (ins (sxStart x) before) (ins (sxEnd x) after))

fn appendSites x: Sx -> (List (List Edit))
  (let [(items (listItems x))]
    (if (and (parenList? x) (and (headIs? x "listAppend") (= (listLength items) 3)))
      (map (fn [(arg Sx)] -> (List Edit) (wrapEdits arg "(list " ")"))
           (filter (fn [(arg Sx)] -> Bool (not (or (headIs? arg "list") (headIs? arg "listAppend")))) (listReverse (listDrop items 1))))
      (list)))

fn optionListHead? x: Sx -> Bool
  (and (parenList? x) (or (headIs? x "listTail") (headIs? x "listSlice")))

fn tailSites x: Sx -> (List (List Edit))
  (if (or (not (parenList? x)) (or (headIs? x "optionOr") (headIs? x "match")))
    (list)
    (map (fn [(arg Sx)] -> (List Edit) (wrapEdits arg "(optionOr " " (list))"))
         (filter optionListHead? (listDrop (listItems x) 1))))

fn plusSites x: Sx -> (List (List Edit))
  (if (and (parenList? x) (headIs? x "+"))
    (match (listHead (listItems x)) ((some h) (list (list (repl h "str")))) ((none) (list)))
    (list))

fn siteCandidates text: String sites: (fn [Sx] -> (List (List Edit))) -> (List String)
  (map (fn [(es (List Edit))] -> String (applyEdits text es))
       (listTake (listFlatMap sites (forestLists (readSx text))) 16))

fn ruleArgShape text: String ds: (List ty/Diagnostic) -> (List String)
  (listAppend
    (if (diagHas? ds "argument to listAppend: expected (List " "found") (siteCandidates text appendSites) (list))
    (listAppend
      (if (diagHas? ds "expected (List " "found (Option (List ") (siteCandidates text tailSites) (list))
      (if (diagHas? ds "argument to +: expected a number" "found String") (siteCandidates text plusSites) (list))))

; (:m :do "pipeline: rules in order, the first candidate that strictly lowers the score is kept, then the rules start over; a fixpoint or the round cap ends it")
fn ruleCandidates rule: String text: String ds: (List ty/Diagnostic) vocab: (List String) ex: (Map String (List String)) -> (List String)
  (cond
    ((= rule "delimiterBalance") (ruleDelimiterBalance text))
    ((= rule "bareForm") (ruleBareForm text))
    ((= rule "indentBalance") (ruleIndentBalance text))
    ((= rule "headerParens") (ruleHeaderParens text))
    ((= rule "argShape") (ruleArgShape text ds))
    ((= rule "lineHeader") (ruleLineHeader text))
    ((= rule "freeComment") (ruleFreeComment text))
    ((= rule "fnHeaderUnwrap") (ruleFnHeaderUnwrap text))
    ((= rule "bodyIndent") (ruleBodyIndent text))
    ((= rule "condClauses") (ruleCondClauses text))
    ((= rule "letBindingVector") (ruleLetBindingVector text))
    ((= rule "testPredicate") (ruleTestPredicate text))
    ((= rule "exportAdd") (ruleExportAdd text ds))
    ((= rule "importAdd") (ruleImportAdd text ds ex))
    ((= rule "symbolRename") (ruleSymbolRename text ds vocab))
    ((= rule "effectMark") (ruleEffectMark text ds))
    (else (list)))

(schema Step (:f text String) (:f diags (List ty/Diagnostic)) (:f rule String))

fn firstImproving rule: String cands: (List String) text: String score: Int64 deps: (Map String r/ModuleSummary) path: String -> (Option Step)
  (match (listHead cands)
    ((none) none)
    ((some c)
      (let [(rest (optionOr (listTail cands) (list)))]
        (if (= c text)
          (firstImproving rule rest text score deps path)
          (let [(ds (healDiags c deps path))]
            (if (< (healScore ds) score) (some (Step :text c :diags ds :rule rule)) (firstImproving rule rest text score deps path)))))))

fn tryRules rules: (List String) text: String ds: (List ty/Diagnostic) deps: (Map String r/ModuleSummary) path: String vocab: (List String) ex: (Map String (List String)) -> (Option Step)
  (match (listHead rules)
    ((none) none)
    ((some rule)
      (match (firstImproving rule (ruleCandidates rule text ds vocab ex) text (healScore ds) deps path)
        ((some s) (some s))
        ((none) (tryRules (optionOr (listTail rules) (list)) text ds deps path vocab ex)))))

fn quoteAsn s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn formatHealReceipt rules: (List String) left: (List ty/Diagnostic) -> String
  (str "(:repaired (" (stringJoin rules " ") ") :left (" (stringJoin (map (fn [(d ty/Diagnostic)] -> String (quoteAsn (diagText d))) left) " ") "))")

fn finish text: String ds: (List ty/Diagnostic) applied: (List String) -> HealResult
  (let [(rules (listReverse applied))]
    (HealResult :text text :repaired rules :left ds :receipt (formatHealReceipt rules ds) :changed (not (listEmpty? rules))))

fn parseFailed? ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "parse")) ds)

fn parseRuleNames -> (List String)
  (list "bareForm" "delimiterBalance" "indentBalance" "lineHeader" "fnHeaderUnwrap" "headerParens" "bodyIndent")

; (:m :do "parseOnly runs only the parse-level rules and stops as soon as the text parses: the phase heal! runs before it can read the imports it needs for the full check")
fn healLoop text: String ds: (List ty/Diagnostic) deps: (Map String r/ModuleSummary) path: String vocab: (List String) ex: (Map String (List String)) rules: (List String) parseOnly: Bool rounds: Int64 applied: (List String) -> HealResult
  (if (or (listEmpty? ds) (or (<= rounds 0) (and parseOnly (not (parseFailed? ds)))))
    (finish text ds applied)
    (match (tryRules (if parseOnly (filter (fn [(r String)] -> Bool (listContains? (parseRuleNames) r)) rules) rules) text ds deps path vocab ex)
      ((none) (finish text ds applied))
      ((some s) (healLoop s.text s.diags deps path vocab ex rules parseOnly (- rounds 1) (cons s.rule applied)))))

; (:m :do "vocabulary for nearest-name repair: the module's own defun names plus a base list (the prelude's, from preludeVocab!)")
fn vocabFromSource text: String base: (List String) -> (List String)
  (let [(own (fold (fn [(acc (List String)) (l String)] -> (List String)
                     (if (fnHeaderLine? l)
                       (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit l " ")))
                             (i0 (if (= (optionOr (listGet ws 1) "") "!") 2 1))
                             (i1 (if (= (optionOr (listGet ws i0) "") "tailrec") (+ i0 1) i0))
                             (name (optionOr (listGet ws i1) ""))]
                         (if (stringEmpty? name) acc (cons name acc)))
                       acc))
                   (list) (stringLines text)))]
    (listAppend own base))

; (:m :do "healSourceRules runs a chosen subset of the rules: the rule fixtures use it to show each rule is the cause of its repair (the pipeline without it leaves the fixture broken)")
fn healSourceRules text: String path: String deps: (Map String r/ModuleSummary) vocab: (List String) rules: (List String) -> HealResult
  (healSourceEnv text path deps vocab (mapEmpty) rules)

; (:m :do "healSourceEnv adds ex, the name -> exporting modules map importAdd reads (heal! builds it from the package index; fixtures pass it directly)")
fn healSourceEnv text: String path: String deps: (Map String r/ModuleSummary) vocab: (List String) ex: (Map String (List String)) rules: (List String) -> HealResult
  (let [(t0 (spellNormal text rules))]
    (healLoop t0 (healDiags t0 deps path) deps path (vocabFromSource t0 vocab) ex rules false 24 (spellApplied text t0)))

fn healSourceWith text: String path: String deps: (Map String r/ModuleSummary) vocab: (List String) -> HealResult
  (healSourceRules text path deps vocab (healRuleNames))

fn healSource text: String path: String -> HealResult
  (healSourceWith text path (mapEmpty) (list))

fn ! preludeVocab! path: String -> (List String)
  (match (fileReadString path)
    ((err _) (list))
    ((ok src) (vocabFromSource src (list))))

; (:m :do "the effectful entry: a text that does not parse first gets the parse-level rules alone, then the imports load the way checkFileCached! (asl check) loads them, the vocabulary comes from the prelude at preludePath, and maxRounds caps the rule applications over both phases")
; (:m :ref HEAL-KEEP-STAGE1 :do "imports that do not load (a module the same reply writes, not on disk yet) keep the parse-level repair: the stage-1 text comes back with one importsUnloaded diagnostic left instead of an err that drops it")
fn ! heal! path: String text: String roots: (List String) preludePath: String maxRounds: Int64 -> (Result HealResult String)
  (let [(t0 (spellNormal text (healRuleNames)))
        (vocab (vocabFromSource t0 (preludeVocab! preludePath)))
        (ds0 (checkText t0 (mapEmpty) path))
        (first (if (parseFailed? ds0) (healLoop t0 ds0 (mapEmpty) path vocab (mapEmpty) (healRuleNames) true maxRounds (spellApplied text t0)) (finish t0 (list) (spellApplied text t0))))]
    (match (a/parseForTypeCheck first.text)
      ((err _) (ok first))
      ((ok forms)
        (let [(summary (r/collectSummary forms path))
              (ex (hn/exportersOf! (optionOr (listHead roots) ".") (unboundNames (healDiags first.text (mapEmpty) path))))
              (owners (fold (fn [(acc (List String)) (os (List String))] -> (List String) (if (= (listLength os) 1) (listAppend acc (filter (fn [(o String)] -> Bool (not (listContains? acc o))) os)) acc)) (list) (mapValues ex)))
              (cl (r/loadModuleDepsFrom! (cons (r/parentDirOf path) roots) (listAppend (r/mapValuesList summary.imports) owners) (mapEmpty) (r/emptyModIndex)))]
          (if (and (listEmpty? cl.unresolved) (listEmpty? cl.errors))
            (let [(second (healLoop first.text (healDiags first.text cl.deps path) cl.deps path vocab ex (healRuleNames) false (- maxRounds (listLength first.repaired)) (list)))]
              (ok (finish second.text second.left (listReverse (listAppend first.repaired second.repaired)))))
            (ok (finish first.text (list (diagOf "importsUnloaded" (str "cannot load the imports of " path ": " (stringJoin (listAppend cl.unresolved cl.errors) "; ")) 1 1 path)) (listReverse first.repaired))))))))
