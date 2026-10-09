(module asl-syntax/core/symbols
  :x [SymbolDef
      Span
      EditResult
      makeSymbolDef
      makeScopedSymbolDef
      symbolName
      symbolKind
      symbolStart
      symbolEnd
      symbolContainer
      symbolDepth
      spanStart
      spanEnd
      spanLength
      editResultNewText
      editResultRoot
      findSymbol
      findSymbolDotted
      nearestNames
      nearestSymbols
      anchorOccurrences
      countOccurrences
      resolveAnchor
      resolveAnchorOccurrence
      hasErrorNode
      applySpanEdit
      applySpanEditText
      applySpanEditWithTree
      applyAnchorEdit]
  :i [(asl-syntax/core/tree :a tr)])

(schema Span
  (:f start Int64)
  (:f end Int64))

fn spanStart span: Span -> Int64
  span.start

fn spanEnd span: Span -> Int64
  span.end

fn spanLength span: Span -> Int64
  (- span.end span.start)

(schema EditResult
  (:f newText String)
  (:f root tr/Node))

fn editResultNewText res: EditResult -> String
  res.newText

fn editResultRoot res: EditResult -> tr/Node
  res.root

(schema SymbolDef
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f container String)
  (:f depth Int64))

fn makeSymbolDef name: String kind: String start: Int64 end: Int64 -> SymbolDef
  (SymbolDef :name name :kind kind :start start :end end :container "" :depth 0)

fn makeScopedSymbolDef name: String kind: String start: Int64 end: Int64 container: String depth: Int64 -> SymbolDef
  (SymbolDef :name name :kind kind :start start :end end :container container :depth depth)

fn symbolName sym: SymbolDef -> String
  sym.name

fn symbolKind sym: SymbolDef -> String
  sym.kind

fn symbolStart sym: SymbolDef -> Int64
  sym.start

fn symbolEnd sym: SymbolDef -> Int64
  sym.end

fn symbolContainer sym: SymbolDef -> String
  sym.container

fn symbolDepth sym: SymbolDef -> Int64
  sym.depth

fn hasErrorNode node: tr/Node -> Bool
  (if (tr/isErrorNode node)
    true
    (hasErrorElementList node.children))

fn hasErrorElementList elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken tok)
         (if (tr/isErrorToken tok)
           true
           (hasErrorElementList tail)))
        ((tr/elemNode n)
         (if (hasErrorNode n)
           true
           (hasErrorElementList tail))))))

fn findOccurrencesLoop text: String anchor: String cur: Int64 totalLen: Int64 acc: (List Int64) -> (List Int64)
  (if (>= cur totalLen)
    (listReverse acc)
    (let [(slice (optionOr (stringSlice text cur totalLen) ""))
          (idxOpt (stringIndexOf slice anchor))]
      (mt idxOpt
        ((none) (listReverse acc))
        ((some relIdx)
         (let [(absIdx (+ cur relIdx))]
           (findOccurrencesLoop text anchor (+ absIdx 1) totalLen (cons absIdx acc)))))))

fn anchorOccurrences text: String anchor: String -> (List Int64)
  (let [(totalLen (stringLength text))
        (anchorLen (stringLength anchor))]
    (if (or (= anchorLen 0) (= totalLen 0))
      (list)
      (findOccurrencesLoop text anchor 0 totalLen (list))))

fn countOccurrences text: String anchor: String -> Int64
  (listLength (anchorOccurrences text anchor))

fn resolveAnchor text: String anchor: String -> (Result Span String)
  (let [(matches (anchorOccurrences text anchor))
        (cnt (listLength matches))]
    (cond
      ((= cnt 0)
       (err (str "anchor not found: " anchor)))
      ((> cnt 1)
       (err (str "ambiguous anchor: " (stringFromInt64 cnt) " occurrences of " anchor)))
      (else
       (let [(st (optionOr (listHead matches) 0))
             (en (+ st (stringLength anchor)))]
         (ok (Span :start st :end en))))))

fn resolveAnchorOccurrence text: String anchor: String occurrence: Int64 -> (Result Span String)
  (if (<= occurrence 0)
    (err "invalid occurrence: must be >= 1")
    (let [(matches (anchorOccurrences text anchor))
          (cnt (listLength matches))]
      (cond
        ((= cnt 0)
         (err (str "anchor not found: " anchor)))
        ((> occurrence cnt)
         (err (str "occurrence " (stringFromInt64 occurrence) " out of bounds: only " (stringFromInt64 cnt) " occurrences")))
        (else
         (let [(st (optionOr (listGet matches (- occurrence 1)) 0))
               (en (+ st (stringLength anchor)))]
           (ok (Span :start st :end en)))))))

fn applySpanEdit text: String start: Int64 end: Int64 replacement: String parse: (fn [String] -> (Result tr/Node String)) -> (Result EditResult String)
  (let [(totalLen (stringLength text))]
    (cond
      ((< start 0)
       (err "span start cannot be negative"))
      ((< end start)
       (err "span end cannot be before start"))
      ((> end totalLen)
       (err "span end exceeds text length"))
      (else
       (let [(prefix (optionOr (stringSlice text 0 start) ""))
             (suffix (optionOr (stringSlice text end totalLen) ""))
             (newText (str prefix replacement suffix))
             (parseRes (parse newText))]
         (mt parseRes
           ((err msg) (err (str "parse failed: " msg)))
           ((ok root)
            (if (hasErrorNode root)
              (err "edit introduced Error node")
              (ok (EditResult :newText newText :root root)))))))))

fn applySpanEditText text: String start: Int64 end: Int64 replacement: String parse: (fn [String] -> (Result tr/Node String)) -> (Result String String)
  (mt (applySpanEdit text start end replacement parse)
    ((ok res) (ok res.newText))
    ((err msg) (err msg)))

fn applySpanEditWithTree text: String start: Int64 end: Int64 replacement: String parse: (fn [String] -> tr/Node) -> (Result EditResult String)
  (applySpanEdit text start end replacement (fn [(t String)] -> (Result tr/Node String) (ok (parse t))))

fn applyAnchorEdit text: String anchor: String replacement: String parse: (fn [String] -> (Result tr/Node String)) -> (Result EditResult String)
  (mt (resolveAnchor text anchor)
    ((err msg) (err msg))
    ((ok span)
     (applySpanEdit text span.start span.end replacement parse)))

fn symBefore? a: SymbolDef b: SymbolDef -> Bool
  (if (< a.depth b.depth)
    true
    (if (> a.depth b.depth)
      false
      (< a.start b.start)))

fn insertSymbolSort sym: SymbolDef sorted: (List SymbolDef) -> (List SymbolDef)
  (mt (listHead sorted)
    ((none) (list sym))
    ((some hd)
     (if (symBefore? sym hd)
       (cons sym sorted)
       (cons hd (insertSymbolSort sym (optionOr (listTail sorted) (list)))))))

fn sortSymbolCandidates cands: (List SymbolDef) -> (List SymbolDef)
  (fold (fn [(acc (List SymbolDef)) (s SymbolDef)] -> (List SymbolDef)
          (insertSymbolSort s acc))
        (list)
        cands)

fn matchesCandidate? cand: SymbolDef name: String parentOpt: (Option SymbolDef) -> Bool
  (if (not (= cand.name name))
    false
    (mt parentOpt
      ((none) true)
      ((some parent)
       (let [(same? (and (= cand.start parent.start)
                         (and (= cand.end parent.end)
                              (= cand.name parent.name))))
             (inside? (and (>= cand.start parent.start)
                           (<= cand.end parent.end)))
             (contained? (= cand.container parent.name))]
         (and (not same?) (or inside? contained?))))))

fn collectCandidates syms: (List SymbolDef) name: String parentOpt: (Option SymbolDef) -> (List SymbolDef)
  (filter (fn [(s SymbolDef)] -> Bool (matchesCandidate? s name parentOpt)) syms)

fn searchCandidatesList parts: (List String) syms: (List SymbolDef) idx: Int64 lastPart?: Bool cands: (List SymbolDef) -> (Option SymbolDef)
  (mt (listHead cands)
    ((none) (none))
    ((some cand)
     (if lastPart?
       (some cand)
       (let [(deeper (searchParts parts syms (+ idx 1) (some cand)))]
         (mt deeper
           ((some res) (some res))
           ((none) (searchCandidatesList parts syms idx lastPart? (optionOr (listTail cands) (list)))))))))

fn searchParts parts: (List String) syms: (List SymbolDef) idx: Int64 parentOpt: (Option SymbolDef) -> (Option SymbolDef)
  (mt (listGet parts idx)
    ((none) (none))
    ((some partName)
     (let [(cands (sortSymbolCandidates (collectCandidates syms partName parentOpt)))
           (lastPart? (= idx (- (listLength parts) 1)))]
       (searchCandidatesList parts syms idx lastPart? cands))))

fn normalizeSymbolQuery q: String -> String
  (if (and (stringStartsWith? q ":") (> (stringLength q) 1))
    (optionOr (stringSlice q 1 (stringLength q)) q)
    q)

fn findSymbolDotted syms: (List SymbolDef) query: String -> (Option SymbolDef)
  (let [(norm (normalizeSymbolQuery query))]
    (if (stringEmpty? norm)
      (none)
      (let [(parts (if (stringContains? norm ".") (stringSplit norm ".") (list norm)))]
        (searchParts parts syms 0 (none)))))

fn findSymbol syms: (List SymbolDef) query: String -> (Option SymbolDef)
  (findSymbolDotted syms query)

(schema MatchBlock (:f i Int64) (:f j Int64) (:f size Int64))
(schema ScoredCandidate (:f score Float64) (:f text String))

fn commonRunLength a: Bytes b: Bytes i: Int64 j: Int64 ahi: Int64 bhi: Int64 k: Int64 -> Int64
  (if (and (< (+ i k) ahi)
      (and (< (+ j k) bhi)
           (= (bytesGet a (+ i k)) (bytesGet b (+ j k)))))
    (commonRunLength a b i j ahi bhi (+ k 1))
    k)

fn scanJMatch a: Bytes b: Bytes i: Int64 j: Int64 ahi: Int64 bhi: Int64 best: MatchBlock -> MatchBlock
  (if (>= j bhi)
    best
    (let [(k (commonRunLength a b i j ahi bhi 0))]
      (scanJMatch a b i (+ j 1) ahi bhi (if (> k best.size) (MatchBlock :i i :j j :size k) best))))

fn longestMatchBlock a: Bytes b: Bytes i: Int64 ahi: Int64 blo: Int64 bhi: Int64 best: MatchBlock -> MatchBlock
  (if (>= i ahi)
    best
    (longestMatchBlock a b (+ i 1) ahi blo bhi (scanJMatch a b i blo ahi bhi best)))

fn totalMatchedBytes a: Bytes b: Bytes alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 -> Int64
  (if (or (>= alo ahi) (>= blo bhi))
    0
    (let [(m (longestMatchBlock a b alo ahi blo bhi (MatchBlock :i alo :j blo :size 0)))
          (k m.size)]
      (if (= k 0)
        0
        (+ k
           (+ (totalMatchedBytes a b alo m.i blo m.j)
              (totalMatchedBytes a b (+ m.i k) ahi (+ m.j k) bhi))))))

fn stringSimilarityRatio a: String b: String -> Float64
  (let [(la (stringLength a))
        (lb (stringLength b))]
    (if (= (+ la lb) 0)
      1.0
      (/ (* 2.0 (int64ToFloat64 (totalMatchedBytes (stringToBytes a) (stringToBytes b) 0 la 0 lb)))
         (int64ToFloat64 (+ la lb)))))

fn betterScored? x: ScoredCandidate y: ScoredCandidate -> Bool
  (or (> x.score y.score)
      (and (= x.score y.score) (> x.text y.text)))

fn insertScoredCandidate item: ScoredCandidate items: (List ScoredCandidate) -> (List ScoredCandidate)
  (mt (listHead items)
    ((none) (list item))
    ((some hd)
     (if (betterScored? item hd)
       (cons item items)
       (cons hd (insertScoredCandidate item (optionOr (listTail items) (list)))))))

fn getCloseStringMatches word: String possibilities: (List String) n: Int64 cutoff: Float64 -> (List String)
  (let [(scored (fold (fn [(acc (List ScoredCandidate)) (x String)] -> (List ScoredCandidate)
                        (let [(r (stringSimilarityRatio x word))]
                          (if (>= r cutoff)
                            (insertScoredCandidate (ScoredCandidate :score r :text x) acc)
                            acc)))
                      (list)
                      possibilities))]
    (map (fn [(s ScoredCandidate)] -> String s.text) (listTake scored n)))

fn dedupSortedStrings items: (List String) acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listReverse acc))
    ((some x)
     (dedupSortedStrings (optionOr (listTail items) (list))
                         (if (and (not (listEmpty? acc)) (= (optionOr (listHead acc) "") x))
                           acc
                           (cons x acc)))))

fn fillNearSubstrings names: (List String) low: String near: (List String) k: Int64 -> (List String)
  (mt (listHead names)
    ((none) near)
    ((some nm)
     (if (>= (listLength near) k)
       near
       (let [(lowNm (stringLower nm))
             (take (and (not (listContains? near nm))
                        (or (stringContains? lowNm low) (stringContains? low lowNm))))]
         (fillNearSubstrings (optionOr (listTail names) (list))
                             low
                             (if take (listAppend near (list nm)) near)
                             k)))))

fn nearestNames sym: String names: (List String) k: Int64 -> (List String)
  (let [(sorted (dedupSortedStrings (listSort names) (list)))
        (near (getCloseStringMatches sym sorted k 0.5))]
    (listTake (fillNearSubstrings sorted (stringLower sym) near k) k))

fn nearestSymbols sym: String syms: (List SymbolDef) k: Int64 -> (List String)
  (let [(names (map (fn [(s SymbolDef)] -> String s.name) syms))]
    (nearestNames sym names k))
