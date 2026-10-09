(module ws/asl/tools/observe/coverage
  :x [observeCoverage! reqMatch specReqs idToken? stem termGaps sourceSegment decodeError]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)
      (ws/asl/tools/observe/pyDump :a d)
      (ws/asl/tools/observe/pyIndex :a p)
      (ws/asl/tools/observe/pyQuery :a q)
      (ws/asl/tools/observe/callers :a cal)
      (asl-regex/regex :a re)])

fn coverageLimits -> String
  (str "python only; a requirement is served by symbols citing its id and by what a test citing it calls or "
       "patches; behaviour is not run, so a served symbol that is not a stub counts as implemented; "
       ":termGaps are requirement words absent from the serving code (advisory)")

fn byteAt bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn upper? b: Int64 -> Bool
  (and (>= b 65) (<= b 90))

fn digit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn runEnd bs: Bytes i: Int64 n: Int64 pred: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (pred (bytesGet bs i))) (runEnd bs (+ i 1) n pred) i)

fn spacesEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(k (c/spaceLenAt bs i n))] (if (> k 0) (spacesEnd bs (+ i k) n) i))

fn prefixEnd bs: Bytes i: Int64 n: Int64 -> (Option Int64)
  (let [(b (byteAt bs i n))
        (afterMark (cond
                     ((= b 35) (let [(e (runEnd bs i n (fn [(x Int64)] -> Bool (= x 35))))] (if (<= (- e i) 6) (some e) (none))))
                     ((or (= b 45) (= b 42) (= b 43)) (some (+ i 1)))
                     ((digit? b) (let [(e (runEnd bs i n digit?)) (m (byteAt bs e n))] (if (or (= m 46) (= m 41)) (some (+ e 1)) (none))))
                     (else (none))))]
    (mt afterMark
      ((none) (none))
      ((some e) (let [(s (spacesEnd bs e n))] (if (> s e) (some s) (none))))))

fn markEnd bs: Bytes i: Int64 n: Int64 closing: Bool -> (Option Int64)
  (let [(b (byteAt bs i n))]
    (cond
      ((and (= b 42) (= (byteAt bs (+ i 1) n) 42)) (some (+ i 2)))
      ((and (= b 95) (= (byteAt bs (+ i 1) n) 95)) (some (+ i 2)))
      ((and (not closing) (= b 91)) (some (+ i 1)))
      ((and closing (= b 93)) (some (+ i 1)))
      (else (none))))

fn options first: (Option Int64) fallback: Int64 -> (List Int64)
  (mt first ((some e) (list e fallback)) ((none) (list fallback)))

fn lookahead? bs: Bytes i: Int64 n: Int64 -> Bool
  (or (>= i n) (> (c/spaceLenAt bs i n) 0) (= (bytesGet bs i) 58) (= (bytesGet bs i) 46) (= (bytesGet bs i) 41))

fn firstSome xs: (List Int64) f: (fn [Int64] -> (Option (Pair String String))) -> (Option (Pair String String))
  (mt (listHead xs)
    ((none) (none))
    ((some x) (mt (f x) ((some r) (some r)) ((none) (firstSome (optionOr (listTail xs) (list)) f)))))

fn restOf line: String i: Int64 -> String
  (let [(n (stringLength line))
        (end (if (stringEndsWith? line "\n") (- n 1) n))
        (bs (stringToBytes line))
        (nl (runEnd bs i end (fn [(x Int64)] -> Bool (!= x 10))))]
    (optionOr (stringSlice line (min i nl) nl) ""))

fn reqMatch line: String -> (Option (Pair String String))
  (let [(bs (stringToBytes line)) (n (bytesLength bs)) (i0 (spacesEnd bs 0 n))]
    (firstSome (options (prefixEnd bs i0 n) i0)
      (fn [(p1 Int64)] -> (Option (Pair String String))
        (firstSome (options (markEnd bs p1 n false) p1)
          (fn [(p2 Int64)] -> (Option (Pair String String))
            (let [(le (runEnd bs p2 n upper?)) (len (- le p2))]
              (if (or (< len 1) (> len 4))
                (none)
                (let [(q0 (if (and (= (byteAt bs le n) 45) (digit? (byteAt bs (+ le 1) n))) (+ le 1) le))
                      (q1 (runEnd bs q0 n digit?))]
                  (if (= q1 q0)
                    (none)
                    (firstSome (options (if (and (= (byteAt bs q1 n) 46) (digit? (byteAt bs (+ q1 1) n))) (some (runEnd bs (+ q1 1) n digit?)) (none)) q1)
                      (fn [(p3 Int64)] -> (Option (Pair String String))
                        (firstSome (options (markEnd bs p3 n true) p3)
                          (fn [(p4 Int64)] -> (Option (Pair String String))
                            (if (lookahead? bs p4 n) (some (pair (optionOr (stringSlice line p2 p3) "") (restOf line p4))) (none)))))))))))))))

fn dropMarks s: String -> String
  (c/catAll (filter (fn [(ch String)] -> Bool (not (listContains? (list "*" "_" "`" "[" "]") ch))) (stringChars s)))

(schema Req (:f id String) (:f text String))

fn specReqs text: String -> (List Req)
  (listReverse
    (fold (fn [(acc (List Req)) (line String)] -> (List Req)
            (mt (reqMatch line)
              ((none) acc)
              ((some m)
                (if (listAny? (fn [(r Req)] -> Bool (= r.id (pairFirst m))) acc)
                  acc
                  (cons (Req :id (pairFirst m) :text (c/stripChars (dropMarks (pairSecond m)) " :.-")) acc)))))
          (list) (c/keepEndsLines text)))

fn hex2 b: Int64 -> String
  (str (optionOr (stringSlice "0123456789abcdef" (/ b 16) (+ (/ b 16) 1)) "") (optionOr (stringSlice "0123456789abcdef" (mod b 16) (+ (mod b 16) 1)) ""))

fn posText a: Int64 k: Int64 bs: Bytes -> String
  (if (= k 1)
    (str "byte 0x" (hex2 (bytesGet bs a)) " in position ")
    "bytes in position ")

fn errMsg bs: Bytes base: Int64 at: Int64 k: Int64 reason: String -> String
  (str "UnicodeDecodeError: 'utf-8' codec can't decode " (posText at k bs)
       (if (= k 1) (stringFromInt64 (- at base)) (str (stringFromInt64 (- at base)) "-" (stringFromInt64 (- (- (+ at k) base) 1))))
       ": " reason)

fn needOf b0: Int64 -> Int64
  (cond ((< b0 128) 1) ((and (>= b0 194) (< b0 224)) 2) ((and (>= b0 224) (< b0 240)) 3) ((and (>= b0 240) (< b0 245)) 4) (else 0))

fn validPrefix bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(b0 (bytesGet bs i)) (need (needOf b0))
        (lo1 (cond ((= b0 224) 160) ((= b0 240) 144) (else 128)))
        (hi1 (cond ((= b0 237) 159) ((= b0 244) 143) (else 191)))
        (ok1 (let [(b1 (byteAt bs (+ i 1) n))] (and (>= b1 lo1) (<= b1 hi1))))
        (okc (fn [(j Int64)] -> Bool (let [(b (byteAt bs j n))] (and (>= b 128) (<= b 191)))))]
    (cond
      ((not ok1) 1)
      ((or (= need 2) (not (okc (+ i 2)))) 2)
      ((or (= need 3) (not (okc (+ i 3)))) 3)
      (else 4)))

fn decodeLoop bs: Bytes i: Int64 n: Int64 chunkEnd: Int64 base: Int64 -> (Option String)
  (cond
    ((>= i n) (none))
    ((>= i chunkEnd) (decodeLoop bs i n (+ chunkEnd 8192) i))
    (else
      (let [(b0 (bytesGet bs i)) (need (needOf b0))]
        (cond
          ((= need 1) (decodeLoop bs (+ i 1) n chunkEnd base))
          ((= need 0) (some (errMsg bs base i 1 "invalid start byte")))
          (else
            (let [(vp (validPrefix bs i n))]
              (cond
                ((= vp need) (decodeLoop bs (+ i need) n chunkEnd base))
                ((>= (+ i vp) n) (some (errMsg bs i i vp "unexpected end of data")))
                ((>= (+ i vp) chunkEnd) (decodeLoop bs i n (+ chunkEnd 8192) i))
                (else (some (errMsg bs base i vp "invalid continuation byte"))))))))))

fn decodeError raw: String -> (Option String)
  (let [(bs (stringToBytes raw))] (decodeLoop bs 0 (bytesLength bs) 8192 0))

fn asciiLower s: String -> String
  (let [(low (c/catAll (map (fn [(ch String)] -> String (let [(k (charCode ch))] (if (and (>= k 65) (<= k 90) (= (stringLength ch) 1)) (stringLower ch) ch))) (stringChars s))))]
    (stringReplace (stringReplace low "\xe2\x84\xaa" "k") "\xc4\xb0" "i\xcc\x87"))

(schema Split (:f words (List String)) (:f cur (List String)) (:f prev Int64))

fn nameWords name: String -> (List String)
  (let [(bs (stringToBytes name)) (n (bytesLength bs))
        (st (fold (fn [(s Split) (i Int64)] -> Split
                    (let [(b (bytesGet bs i)) (ch (optionOr (stringSlice name i (+ i 1)) ""))]
                      (cond
                        ((= b 95) (Split :words (cons (c/catAll (listReverse s.cur)) s.words) :cur (list) :prev b))
                        ((and (upper? b) (or (digit? s.prev) (and (>= s.prev 97) (<= s.prev 122))))
                          (Split :words (cons (c/catAll (listReverse s.cur)) s.words) :cur (list ch) :prev b))
                        (else (Split :words s.words :cur (cons ch s.cur) :prev b)))))
                  (Split :words (list) :cur (list) :prev -1) (range 0 n)))]
    (listReverse (cons (c/catAll (listReverse st.cur)) st.words)))

fn idToken? name: String rid: String -> Bool
  (let [(want (asciiLower (stringReplace rid "-" "")))]
    (or (listContains? (map asciiLower (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (nameWords name))) want)
        (listContains? (stringSplit (asciiLower name) "_") want)))

fn ridIn? text: String rid: String -> Bool
  (let [(bs (stringToBytes text)) (n (bytesLength bs)) (pat (stringToBytes rid)) (m (bytesLength pat))
        (hits (fn [(i Int64)] -> Bool
                (let [(before (byteAt bs (- i 1) n)) (after (byteAt bs (+ i m) n))]
                  (and (not (or (digit? before) (upper? before) (and (>= before 97) (<= before 122)))) (not (digit? after))))))]
    (ridFrom bs n pat m 0 hits))

fn ridFrom bs: Bytes n: Int64 pat: Bytes m: Int64 i: Int64 hits: (fn [Int64] -> Bool) -> Bool
  (let [(j (c/findFrom bs n pat i))]
    (cond ((< j 0) false) ((hits j) true) (else (ridFrom bs n pat m (+ j 1) hits))))

fn docOf dd: p/PyDef -> (Option String)
  (if (= dd.kind "lambda")
    (none)
    (mt (listHead (d/kids dd.node "body"))
      ((some b0) (if (d/isType? b0 "Expr") (mt (d/kid b0 "value") ((some v) (d/constStr v)) ((none) (none))) (none)))
      ((none) (none))))

fn cites? pi: p/PyIndex dd: p/PyDef rid: String -> Bool
  (or (idToken? dd.name rid)
      (mt (docOf dd) ((some doc) (and (not (stringEmpty? doc)) (ridIn? doc rid))) ((none) false))
      (mt (p/modOf pi.ix dd.modName)
        ((some m) (listAny? (fn [(cm (Pair Int64 String))] -> Bool (and (<= dd.line (pairFirst cm)) (<= (pairFirst cm) dd.end) (ridIn? (pairSecond cm) rid))) (q/commentsOf m)))
        ((none) false)))

fn stem w: String -> String
  (let [(n (stringLength w))
        (cut (fn [(k Int64)] -> String (optionOr (stringSlice w 0 (- n k)) w)))]
    (cond
      ((and (stringEndsWith? w "ies") (> n 5)) (str (cut 3) "y"))
      ((and (stringEndsWith? w "ing") (not (stringEndsWith? w "ss")) (>= (- n 3) 3)) (cut 3))
      ((and (stringEndsWith? w "ed") (not (stringEndsWith? w "ss")) (>= (- n 2) 3)) (cut 2))
      ((and (stringEndsWith? w "s") (not (stringEndsWith? w "ss")) (>= (- n 1) 3)) (cut 1))
      (else w)))

fn stopWords -> (List String)
  (stringSplit (str "a an and are as at be been by each every for from in into is it its of on or per the their "
                    "this to with without after before than that when which while all any across must shall should") " ")

fn letterWords text: String -> (List String)
  (let [(bs (stringToBytes text)) (n (bytesLength bs))
        (letter? (fn [(b Int64)] -> Bool (or (upper? b) (and (>= b 97) (<= b 122)))))]
    (lettersFrom text bs 0 n letter? (list)))

fn lettersFrom text: String bs: Bytes i: Int64 n: Int64 letter?: (fn [Int64] -> Bool) acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (letter? (bytesGet bs i))
      (let [(e (runEnd bs i n letter?))]
        (lettersFrom text bs e n letter? (if (>= (- e i) 2) (cons (optionOr (stringSlice text i e) "") acc) acc)))
      (lettersFrom text bs (+ i 1) n letter? acc)))

fn termGaps text: String sources: (List String) -> (List String)
  (let [(corpus (asciiLower (c/joinWith sources " ")))
        (gaps (fold (fn [(acc (List String)) (w0 String)] -> (List String)
                      (let [(w (asciiLower w0))]
                        (if (or (listContains? (stopWords) w) (< (stringLength w) 3))
                          acc
                          (let [(s (stem w))] (if (or (stringContains? corpus s) (listContains? acc s)) acc (listAppend acc (list s)))))))
                    (list) (letterWords text)))]
    (listTake gaps 6))

fn sourceSegment src: String node: d/PyNode -> String
  (if (not node.hasEnd)
    ""
    (let [(ls (c/keepEndsLines src))
          (a (- node.line 1)) (b (- node.endLine 1))
          (lineAt (fn [(i Int64)] -> String (optionOr (listGet ls i) "")))]
      (if (= a b)
        (optionOr (stringSlice (lineAt a) node.col node.endCol) "")
        (c/catAll (listAppend (cons (optionOr (stringSlice (lineAt a) node.col (stringLength (lineAt a))) "")
                                    (listTake (listDrop ls (+ a 1)) (max 0 (- (- b a) 1))))
                              (list (optionOr (stringSlice (lineAt b) 0 node.endCol) "")))))))

fn pyQuote s: String -> String
  (if (and (stringContains? s "'") (not (stringContains? s "\""))) (str "\"" s "\"") (str "'" (stringReplace s "'" "\\'") "'"))

fn label dd: p/PyDef -> String
  (c/quoted (str dd.rel "#" dd.qual))

fn labels ds: (List p/PyDef) -> String
  (str "(" (c/joinWith (map label (listTake ds 4)) " ") (if (> (listLength ds) 4) (str " :more " (stringFromInt64 (- (listLength ds) 4))) "") ")")

fn keysOf ds: (List p/PyDef) -> (h/HMap Bool)
  (cal/setOf (map (fn [(dd p/PyDef)] -> String dd.key) ds))

fn meets? a: (h/HMap Bool) b: (h/HMap Bool) -> Bool
  (listAny? (fn [(pr (Pair String Bool))] -> Bool (h/hmHas? b (pairFirst pr))) (h/hmPairs a))

fn union a: (h/HMap Bool) b: (h/HMap Bool) -> (h/HMap Bool)
  (fold (fn [(acc (h/HMap Bool)) (pr (Pair String Bool))] -> (h/HMap Bool) (h/hmPut acc (pairFirst pr) true)) a (h/hmPairs b))

fn inter a: (h/HMap Bool) b: (h/HMap Bool) -> (h/HMap Bool)
  (fold (fn [(acc (h/HMap Bool)) (pr (Pair String Bool))] -> (h/HMap Bool) (if (h/hmHas? b (pairFirst pr)) (h/hmPut acc (pairFirst pr) true) acc)) (h/hmEmpty) (h/hmPairs a))

(schema TI (:f t p/PyDef) (:f cut (h/HMap Bool)) (:f skip Bool) (:f reached (h/HMap Bool)) (:f callees (h/HMap Bool)))

fn boolText b: Bool -> String
  (if b "true" "false")

fn testIsTest? pi: p/PyIndex k: String -> Bool
  (mt (p/defOf pi.ix k)
    ((some dd) (mt (p/modOf pi.ix dd.modName) ((some m) m.isTest) ((none) false)))
    ((none) true))

fn srcOf pi: p/PyIndex dd: p/PyDef -> String
  (mt (p/modOf pi.ix dd.modName) ((some m) (sourceSegment m.src dd.node)) ((none) ""))

fn reqItem pi: p/PyIndex code: (List p/PyDef) infos: (List TI) r: Req -> (Pair String Bool)
  (let [(rid r.id)
        (cited (keysOf (filter (fn [(dd p/PyDef)] -> Bool (cites? pi dd rid)) code)))
        (rtests (filter (fn [(ti TI)] -> Bool (cites? pi ti.t rid)) infos))
        (rkeys (cal/setOf (map (fn [(ti TI)] -> String ti.t.key) rtests)))
        (served (fold (fn [(acc (h/HMap Bool)) (ti TI)] -> (h/HMap Bool)
                        (fold (fn [(a2 (h/HMap Bool)) (pr (Pair String Bool))] -> (h/HMap Bool)
                                (if (and (some? (p/defOf pi.ix (pairFirst pr))) (not (testIsTest? pi (pairFirst pr)))) (h/hmPut a2 (pairFirst pr) true) a2))
                              acc (h/hmPairs (union ti.callees ti.cut))))
                      cited rtests))
        (servedDefs (listSortBy (fn [(dd p/PyDef)] -> String (str dd.rel "\x00" (cal/padLine dd.line)))
                                (fold (fn [(acc (List p/PyDef)) (pr (Pair String Bool))] -> (List p/PyDef) (mt (p/defOf pi.ix (pairFirst pr)) ((some dd) (cons dd acc)) ((none) acc))) (list) (h/hmPairs served))))
        (stubs (filter (fn [(dd p/PyDef)] -> Bool (some? (q/stubWhy pi dd))) servedDefs))
        (implemented (and (not (listEmpty? servedDefs)) (listEmpty? stubs)))
        (live (keysOf (filter (fn [(dd p/PyDef)] -> Bool (not (some? (q/stubWhy pi dd)))) servedDefs)))
        (cls (fold (fn [(acc (Pair (List p/PyDef) (Pair (List p/PyDef) (List p/PyDef)))) (ti TI)] -> (Pair (List p/PyDef) (Pair (List p/PyDef) (List p/PyDef)))
                     (let [(reachCut (union ti.reached ti.cut))]
                       (if (and (not (h/hmHas? rkeys ti.t.key)) (not (meets? (inter cited live) reachCut)))
                         acc
                         (cond
                           ((meets? ti.cut served) (pair (pairFirst acc) (pair (cons ti.t (pairFirst (pairSecond acc))) (pairSecond (pairSecond acc)))))
                           (ti.skip (pair (pairFirst acc) (pair (pairFirst (pairSecond acc)) (cons ti.t (pairSecond (pairSecond acc))))))
                           ((meets? live (union ti.reached ti.callees)) (pair (cons ti.t (pairFirst acc)) (pairSecond acc)))
                           (else acc)))))
                   (pair (list) (pair (list) (list))) infos))
        (counted (listReverse (pairFirst cls)))
        (mocked (listReverse (pairFirst (pairSecond cls))))
        (skippedL (listReverse (pairSecond (pairSecond cls))))
        (tested (not (listEmpty? counted)))
        (why0 (cond
                ((listEmpty? servedDefs) (str "no symbol or test cites " rid))
                ((not (listEmpty? stubs)) (c/joinWith (map (fn [(dd p/PyDef)] -> String (str dd.qual " is a stub (" (optionOr (q/stubWhy pi dd) "") ")")) (listTake stubs 2)) ", "))
                (else (str "served by " (c/joinWith (map (fn [(dd p/PyDef)] -> String dd.qual) (listTake servedDefs 2)) ", ")))))
        (why (if tested
               why0
               (str why0 "; " (cond
                                ((and (not (listEmpty? mocked)) (listEmpty? skippedL)) "its tests are mocked")
                                ((and (not (listEmpty? skippedL)) (listEmpty? mocked)) "its tests are skipped")
                                ((not (listEmpty? mocked)) "mocked and skipped tests only")
                                (else "no test executes a serving symbol")))))
        (sources (listAppend (map (fn [(dd p/PyDef)] -> String (srcOf pi dd)) servedDefs) (map (fn [(ti TI)] -> String (srcOf pi ti.t)) rtests)))
        (gaps (if (listEmpty? servedDefs) (list) (termGaps r.text sources)))]
    (pair (str "(:id " rid " :implemented " (boolText implemented) " :tested " (boolText tested)
               " :by " (labels servedDefs) " :tests " (labels counted) " :mocked " (labels mocked)
               " :skipped " (labels skippedL) " :termGaps (" (c/joinWith (map c/quoted gaps) " ") ")"
               " :why " (c/quoted why) ")")
          (and implemented tested)))

fn ! coverageOver! root: String spec: String reqs: (List Req) pi: p/PyIndex limit: Int64 ctx: c/Ctx -> (Result String String)
  (let [(tests (q/testDefs pi))
        (code (filter (fn [(dd p/PyDef)] -> Bool (and (not (testIsTest? pi dd.key)) (!= dd.kind "lambda"))) (q/allDefs pi)))
        (infos (map (fn [(t p/PyDef)] -> TI (let [(cut (q/patches pi t))] (TI :t t :cut cut :skip (q/skipped pi t) :reached (q/reach pi t cut) :callees (q/directCallees pi t)))) tests))
        (items (map (fn [(r Req)] -> (Pair Req (Pair String Bool)) (pair r (reqItem pi code infos r))) reqs))
        (done (map (fn [(pr (Pair Req (Pair String Bool)))] -> String (pairFirst pr).id) (filter (fn [(pr (Pair Req (Pair String Bool)))] -> Bool (pairSecond (pairSecond pr))) items)))
        (texts (map (fn [(pr (Pair Req (Pair String Bool)))] -> String (pairFirst (pairSecond pr))) items))]
    (mt (c/shortRev! root ctx)
      ((err e) (err e))
      ((ok rev)
        (let [(head (str "(:observe :dim coverage :v 1 :spec " (c/quoted spec) " :rev " rev " :count (:reqs " (stringFromInt64 (listLength reqs))
                         " :implemented " (stringFromInt64 (listLength (filter (fn [(t String)] -> Bool (stringContains? t ":implemented true")) texts)))
                         " :tested " (stringFromInt64 (listLength (filter (fn [(t String)] -> Bool (stringContains? t ":tested true")) texts)))
                         ") :done (" (c/joinWith done " ") ")"))]
          (c/fitReceipt head (list (c/Section :key "reqs" :items texts :limit limit)) (str " :limits " (c/quoted (coverageLimits))) "coverage")))))

fn ! observeCoverage! root: String spec: String idRx: (Option re/Regex) limit: Int64 ctx: c/Ctx -> (Pair String (Result String String))
  (mt (fileReadString (c/joinPath root spec))
    ((err e) (pair "" (err (if (= e "permissionDenied") (str "PermissionError: [Errno 13] Permission denied: " (pyQuote (c/joinPath root spec))) (str "OSError: " e ": " (pyQuote (c/joinPath root spec)))))))
    ((ok raw)
      (mt (decodeError raw)
        ((some msg) (pair "" (err msg)))
        ((none)
          (let [(all (specReqs (c/universalNewlines raw)))
                (reqs (mt idRx ((some rx) (filter (fn [(r Req)] -> Bool (some? (re/regex-match-full! rx r.id))) all)) ((none) all)))]
            (if (listEmpty? reqs)
              (pair "" (err (c/rejectLine "ERR_NO_REQUIREMENTS" (str "no requirement ids (e.g. R1, REQ-2 at the start of a heading or list item) in " spec) "")))
              (mt (c/workspaceFiles! root ctx)
                ((err e) (pair "" (err e)))
                ((ok files)
                  (mt (p/buildPyIndex root "" files ctx)
                    ((err e) (pair "" (err e)))
                    ((ok b)
                      (mt b
                        ((p/pyAbsent why) (pair "" (err (cal/absentLine "coverage" why))))
                        ((p/built pi) (pair pi.warnings (coverageOver! root spec reqs pi limit ctx))))))))))))))
