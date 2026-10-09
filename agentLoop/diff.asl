(module asl/agentLoop/diff
  :x [unifiedDiff! ratio getOpcodes splitLinesKeepEnds DiffOpcode BestMatch]
  :i [])

(schema BestMatch (:f i Int64) (:f j Int64) (:f size Int64))
(schema DiffOpcode (:f tag String) (:f i1 Int64) (:f i2 Int64) (:f j1 Int64) (:f j2 Int64))

fn firstOf xs: (List T) -> T
  (mt (listHead xs) ((some x) x))

fn restOf xs: (List T) -> (List T)
  (mt (listTail xs) ((some t) t))

fn sepLen b: Bytes n: Int64 i: Int64 c: Int64 -> Int64
  (cond
    ((or (= c 10) (= c 11) (= c 12) (= c 28) (= c 29) (= c 30)) 1)
    ((= c 13) (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 10)) 2 1))
    ((and (= c 194) (< (+ i 1) n) (= (bytesGet b (+ i 1)) 133)) 2)
    ((and (= c 226) (< (+ i 2) n) (= (bytesGet b (+ i 1)) 128) (or (= (bytesGet b (+ i 2)) 168) (= (bytesGet b (+ i 2)) 169))) 3)
    (else 0))

fn endsScan b: Bytes n: Int64 i: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n)
    (listReverse (if (< start n) (cons n acc) acc))
    (let [(k (sepLen b n i (bytesGet b i)))]
      (if (= k 0) (endsScan b n (+ i 1) start acc) (endsScan b n (+ i k) (+ i k) (cons (+ i k) acc)))))

fn lineEnds text: String -> (List Int64)
  (endsScan (stringToBytes text) (stringLength text) 0 0 (list))

fn splitLinesKeepEnds text: String -> (List String)
  (let [(ends (lineEnds text))]
    (map (fn [(p (Pair Int64 Int64))] -> String (optionOr (stringSlice text (pairFirst p) (pairSecond p)) ""))
         (zip (cons 0 ends) ends)))

fn iaNew n: Int64 -> Bytes
  (bytesAlloc (* 8 (max n 1)))

fn iaGet b: Bytes i: Int64 -> Int64
  (optionOr (float64ToInt64 (bytesGetFloat64 b i)) 0)

fn ! iaSet b: Bytes i: Int64 v: Int64 -> Bytes
  (do (bytesSetFloat64 b i (int64ToFloat64 v)) b)

(schema Sm (:f ida Bytes) (:f idb Bytes) (:f off Bytes) (:f eff Bytes) (:f flat Bytes) (:f la Int64) (:f lb Int64)
  (:f val0 Bytes) (:f val1 Bytes) (:f st0 Bytes) (:f st1 Bytes) (:f seq Bytes))

fn ! fillIds sorted: (List (Pair String Int64)) ids: Bytes prev: String next: Int64 first: Bool -> Int64
  (mt (listHead sorted)
    ((none) next)
    ((some p)
      (let [(k (pairFirst p))
            (fresh (or first (!= k prev)))
            (id (if fresh next (- next 1)))
            (w (iaSet ids (pairSecond p) id))]
        (fillIds (restOf sorted) ids k (if fresh (+ next 1) next) false))))

fn tagged xs: (List String) i: Int64 acc: (List (Pair String Int64)) -> (List (Pair String Int64))
  (mt (listHead xs) ((none) acc) ((some x) (tagged (restOf xs) (+ i 1) (cons (pair x i) acc))))

fn ! countB idb: Bytes cnt: Bytes j: Int64 lb: Int64 -> Bytes
  (if (>= j lb) cnt
    (let [(id (iaGet idb j)) (w (iaSet cnt id (+ (iaGet cnt id) 1)))] (countB idb cnt (+ j 1) lb)))

fn ! prefix cnt: Bytes off: Bytes eff: Bytes id: Int64 n: Int64 acc: Int64 popular: Int64 -> Bytes
  (if (>= id n) (iaSet off n acc)
    (let [(c (iaGet cnt id))
          (w (iaSet off id acc))
          (e (iaSet eff id (if (and (>= popular 0) (> c popular)) 0 c)))]
      (prefix cnt off eff (+ id 1) n (+ acc c) popular)))

fn ! fillFlat idb: Bytes off: Bytes fill: Bytes flat: Bytes j: Int64 lb: Int64 -> Bytes
  (if (>= j lb) flat
    (let [(id (iaGet idb j))
          (k (iaGet fill id))
          (w (iaSet flat (+ (iaGet off id) k) j))
          (v (iaSet fill id (+ k 1)))]
      (fillFlat idb off fill flat (+ j 1) lb)))

fn ! makeSm a: (List String) b: (List String) autojunk: Bool -> Sm
  (let [(la (listLength a))
        (lb (listLength b))
        (ids (iaNew (+ la lb)))
        (n (fillIds (listSortBy pairFirst (tagged b la (tagged a 0 (list)))) ids "" 0 true))
        (ida (iaNew la))
        (idb (iaNew lb))
        (wa (fold (fn [acc i] (iaSet ida i (iaGet ids i))) ida (range 0 la)))
        (wb (fold (fn [acc j] (iaSet idb j (iaGet ids (+ la j)))) idb (range 0 lb)))
        (cnt (countB idb (iaNew n) 0 lb))
        (off (iaNew (+ n 1)))
        (eff (iaNew n))
        (w1 (prefix cnt off eff 0 n 0 (if (and autojunk (>= lb 200)) (+ (/ lb 100) 1) -1)))
        (flat (fillFlat idb off (iaNew n) (iaNew lb) 0 lb))]
    (Sm :ida ida :idb idb :off off :eff eff :flat flat :la la :lb lb
        :val0 (iaNew (+ lb 1)) :val1 (iaNew (+ lb 1)) :st0 (iaNew (+ lb 1)) :st1 (iaNew (+ lb 1)) :seq (iaNew 1)))

fn ! scanJs sm: Sm p: Int64 e: Int64 i: Int64 blo: Int64 bhi: Int64 rowSeq: Int64 prevSeq: Int64 best: BestMatch -> BestMatch
  (if (>= p e) best
    (let [(j (iaGet sm.flat p))]
      (cond
        ((< j blo) (scanJs sm (+ p 1) e i blo bhi rowSeq prevSeq best))
        ((>= j bhi) best)
        (else
          (let [(odd (= (mod rowSeq 2) 1))
                (pv (if odd sm.val0 sm.val1))
                (ps (if odd sm.st0 sm.st1))
                (cv (if odd sm.val1 sm.val0))
                (cs (if odd sm.st1 sm.st0))
                (prev (if (and (> j 0) (and (> prevSeq 0) (= (iaGet ps (- j 1)) prevSeq))) (iaGet pv (- j 1)) 0))
                (k (+ prev 1))
                (w1 (iaSet cv j k))
                (w2 (iaSet cs j rowSeq))]
            (scanJs sm (+ p 1) e i blo bhi rowSeq prevSeq
              (if (> k best.size) (BestMatch :i (+ (- i k) 1) :j (+ (- j k) 1) :size k) best)))))))

fn ! scanRows sm: Sm i: Int64 ahi: Int64 blo: Int64 bhi: Int64 prevSeq: Int64 best: BestMatch -> BestMatch
  (if (>= i ahi) best
    (let [(rowSeq (+ (iaGet sm.seq 0) 1))
          (w (iaSet sm.seq 0 rowSeq))
          (id (iaGet sm.ida i))
          (s (iaGet sm.off id))]
      (scanRows sm (+ i 1) ahi blo bhi rowSeq (scanJs sm s (+ s (iaGet sm.eff id)) i blo bhi rowSeq prevSeq best))))

fn expandLeft sm: Sm alo: Int64 blo: Int64 bi: Int64 bj: Int64 bsize: Int64 -> BestMatch
  (if (and (> bi alo) (and (> bj blo) (= (iaGet sm.ida (- bi 1)) (iaGet sm.idb (- bj 1)))))
    (expandLeft sm alo blo (- bi 1) (- bj 1) (+ bsize 1))
    (BestMatch :i bi :j bj :size bsize))

fn expandRight sm: Sm ahi: Int64 bhi: Int64 bi: Int64 bj: Int64 bsize: Int64 -> Int64
  (if (and (< (+ bi bsize) ahi) (and (< (+ bj bsize) bhi) (= (iaGet sm.ida (+ bi bsize)) (iaGet sm.idb (+ bj bsize)))))
    (expandRight sm ahi bhi bi bj (+ bsize 1))
    bsize)

fn ! findLongestMatch sm: Sm alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 -> BestMatch
  (if (or (>= alo ahi) (>= blo bhi))
    (BestMatch :i alo :j blo :size 0)
    (let [(scanned (scanRows sm alo ahi blo bhi 0 (BestMatch :i alo :j blo :size 0)))
          (left (expandLeft sm alo blo scanned.i scanned.j scanned.size))]
      (BestMatch :i left.i :j left.j :size (expandRight sm ahi bhi left.i left.j left.size))))

fn ! matchingBlocksRec sm: Sm alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 -> (List BestMatch)
  (let [(m (findLongestMatch sm alo ahi blo bhi))
        (i m.i)
        (j m.j)
        (k m.size)]
    (if (= k 0)
      (list)
      (let [(left (if (and (< alo i) (< blo j)) (matchingBlocksRec sm alo i blo j) (list)))
            (right (if (and (< (+ i k) ahi) (< (+ j k) bhi)) (matchingBlocksRec sm (+ i k) ahi (+ j k) bhi) (list)))]
        (listAppend left (cons m right)))))

fn collapseAdjacent blocks: (List BestMatch) i1: Int64 j1: Int64 k1: Int64 acc: (List BestMatch) la: Int64 lb: Int64 -> (List BestMatch)
  (mt (listHead blocks)
    ((none)
      (let [(acc1 (if (> k1 0) (cons (BestMatch :i i1 :j j1 :size k1) acc) acc))
            (acc2 (cons (BestMatch :i la :j lb :size 0) acc1))]
        (listReverse acc2)))
    ((some b)
      (let [(i2 b.i)
            (j2 b.j)
            (k2 b.size)
            (tl (optionOr (listTail blocks) (list)))]
        (if (and (= (+ i1 k1) i2) (= (+ j1 k1) j2))
          (collapseAdjacent tl i1 j1 (+ k1 k2) acc la lb)
          (let [(nextAcc (if (> k1 0) (cons (BestMatch :i i1 :j j1 :size k1) acc) acc))]
            (collapseAdjacent tl i2 j2 k2 nextAcc la lb))))))

fn ! getMatchingBlocks sm: Sm -> (List BestMatch)
  (collapseAdjacent (matchingBlocksRec sm 0 sm.la 0 sm.lb) 0 0 0 (list) sm.la sm.lb)

fn sumMatches blocks: (List BestMatch) acc: Int64 -> Int64
  (mt (listHead blocks)
    ((none) acc)
    ((some blk)
      (sumMatches (optionOr (listTail blocks) (list)) (+ acc blk.size))))

fn ! ratio a: String b: String -> Float64
  (let [(ca (stringChars a))
        (cb (stringChars b))
        (la (listLength ca))
        (lb (listLength cb))]
    (if (= (+ la lb) 0)
      1.0
      (/ (* 2.0 (int64ToFloat64 (sumMatches (getMatchingBlocks (makeSm ca cb true)) 0))) (int64ToFloat64 (+ la lb)))))

fn opcodesLoop blocks: (List BestMatch) i: Int64 j: Int64 acc: (List DiffOpcode) -> (List DiffOpcode)
  (mt (listHead blocks)
    ((none) (listReverse acc))
    ((some blk)
      (let [(ai blk.i)
            (bj blk.j)
            (size blk.size)
            (tl (optionOr (listTail blocks) (list)))
            (tag (cond
                   ((and (< i ai) (< j bj)) "replace")
                   ((< i ai) "delete")
                   ((< j bj) "insert")
                   (else "")))
            (acc1 (if (!= tag "") (cons (DiffOpcode :tag tag :i1 i :i2 ai :j1 j :j2 bj) acc) acc))
            (newI (+ ai size))
            (newJ (+ bj size))
            (acc2 (if (> size 0) (cons (DiffOpcode :tag "equal" :i1 ai :i2 newI :j1 bj :j2 newJ) acc1) acc1))]
        (opcodesLoop tl newI newJ acc2))))

fn ! getOpcodes a: (List String) b: (List String) -> (List DiffOpcode)
  (opcodesLoop (getMatchingBlocks (makeSm a b true)) 0 0 (list))

fn fixupCodes codes: (List DiffOpcode) n: Int64 -> (List DiffOpcode)
  (let [(c0 (if (listEmpty? codes) (list (DiffOpcode :tag "equal" :i1 0 :i2 1 :j1 0 :j2 1)) codes))
        (len (listLength c0))]
    (if (= len 1)
      (let [(op (firstOf c0))]
        (if (= op.tag "equal")
          (let [(i1 (max op.i1 (- op.i2 n)))
                (j1 (max op.j1 (- op.j2 n)))
                (i2 (min op.i2 (+ i1 n)))
                (j2 (min op.j2 (+ j1 n)))]
            (list (DiffOpcode :tag "equal" :i1 i1 :i2 i2 :j1 j1 :j2 j2)))
          c0))
      (let [(hd (firstOf c0))
            (tl (restOf c0))
            (fixedHd (if (= hd.tag "equal")
                       (DiffOpcode :tag "equal"
                                   :i1 (max hd.i1 (- hd.i2 n))
                                   :i2 hd.i2
                                   :j1 (max hd.j1 (- hd.j2 n))
                                   :j2 hd.j2)
                       hd))
            (rev (listReverse tl))
            (last (firstOf rev))
            (restRev (restOf rev))
            (fixedLast (if (= last.tag "equal")
                         (DiffOpcode :tag "equal"
                                     :i1 last.i1
                                     :i2 (min last.i2 (+ last.i1 n))
                                     :j1 last.j1
                                     :j2 (min last.j2 (+ last.j1 n)))
                         last))
            (fixedTl (listReverse (cons fixedLast restRev)))]
        (cons fixedHd fixedTl))))

fn groupCodes codes: (List DiffOpcode) n: Int64 currGroup: (List DiffOpcode) accGroups: (List (List DiffOpcode)) -> (List (List DiffOpcode))
  (mt (listHead codes)
    ((none)
      (let [(revGroup (listReverse currGroup))
            (finalGroups (if (and (not (listEmpty? revGroup))
                                  (not (and (= (listLength revGroup) 1)
                                            (= (firstOf revGroup).tag "equal"))))
                           (cons revGroup accGroups)
                           accGroups))]
        (listReverse finalGroups)))
    ((some op)
      (let [(tag op.tag)
            (i1 op.i1)
            (i2 op.i2)
            (j1 op.j1)
            (j2 op.j2)
            (tl (optionOr (listTail codes) (list)))
            (nn (+ n n))]
        (if (and (= tag "equal") (> (- i2 i1) nn))
          (let [(splitOp (DiffOpcode :tag "equal" :i1 i1 :i2 (min i2 (+ i1 n)) :j1 j1 :j2 (min j2 (+ j1 n))))
                (completedGroup (listReverse (cons splitOp currGroup)))
                (newI1 (max i1 (- i2 n)))
                (newJ1 (max j1 (- j2 n)))
                (remOp (DiffOpcode :tag "equal" :i1 newI1 :i2 i2 :j1 newJ1 :j2 j2))]
            (groupCodes tl n (list remOp) (cons completedGroup accGroups)))
          (groupCodes tl n (cons op currGroup) accGroups)))))

fn formatRange start: Int64 stop: Int64 -> String
  (let [(beginning (+ start 1))
        (len (- stop start))]
    (cond
      ((= len 1) (stringFromInt64 beginning))
      ((= len 0) (str (stringFromInt64 (- beginning 1)) ",0"))
      (else (str (stringFromInt64 beginning) "," (stringFromInt64 len)))))

fn prefixLines prefix: String lines: (List String) -> (List String)
  (map (fn [l] (str prefix l)) lines)

fn renderOp a: (List String) b: (List String) op: DiffOpcode -> (List String)
  (let [(tag op.tag)
        (i1 op.i1)
        (i2 op.i2)
        (j1 op.j1)
        (j2 op.j2)]
    (cond
      ((= tag "equal")
        (prefixLines " " (optionOr (listSlice a i1 i2) (list))))
      ((= tag "replace")
        (listAppend (prefixLines "-" (optionOr (listSlice a i1 i2) (list)))
                    (prefixLines "+" (optionOr (listSlice b j1 j2) (list)))))
      ((= tag "delete")
        (prefixLines "-" (optionOr (listSlice a i1 i2) (list))))
      ((= tag "insert")
        (prefixLines "+" (optionOr (listSlice b j1 j2) (list))))
      (else (list))))

fn renderHunkLines a: (List String) b: (List String) ops: (List DiffOpcode) acc: (List String) -> (List String)
  (mt (listHead ops)
    ((none) acc)
    ((some op)
      (let [(opLines (renderOp a b op))
            (tl (optionOr (listTail ops) (list)))]
        (renderHunkLines a b tl (listAppend acc opLines)))))

fn renderGroup a: (List String) b: (List String) group: (List DiffOpcode) -> (List String)
  (let [(first (firstOf group))
        (last (firstOf (listReverse group)))
        (r1 (formatRange first.i1 last.i2))
        (r2 (formatRange first.j1 last.j2))
        (hunkHeader (str "@@ -" r1 " +" r2 " @@
"))
        (lines (renderHunkLines a b group (list)))]
    (cons hunkHeader lines))

fn renderAllGroups a: (List String) b: (List String) groups: (List (List DiffOpcode)) acc: (List String) -> (List String)
  (mt (listHead groups)
    ((none) acc)
    ((some g)
      (let [(glines (renderGroup a b g))
            (tl (optionOr (listTail groups) (list)))]
        (renderAllGroups a b tl (listAppend acc glines)))))

fn unifiedDiff! a: String b: String fromName: String toName: String context: Int64 -> String
  (let [(linesA (splitLinesKeepEnds a))
        (linesB (splitLinesKeepEnds b))
        (opcodes (getOpcodes linesA linesB))
        (fixed (fixupCodes opcodes context))
        (groups (groupCodes fixed context (list) (list)))]
    (if (listEmpty? groups)
      ""
      (let [(fileHeaders (list (str "--- " fromName "
") (str "+++ " toName "
")))
            (body (renderAllGroups linesA linesB groups (list)))]
        (stringJoin (listAppend fileHeaders body) ""))))
