(module ws/asl/tools/observe/aslIndex
  :x [Tok AslMod AslIndex CallRow Mention AslCallers aslLex buildAslIndex! aslCallers defNames]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)])

(schema Tok (:f kind String) (:f val String) (:f line Int64) (:f idx Int64))

(schema AslMod
  (:f rel String) (:f name String) (:f imports (List (Pair String String))) (:f exports (List Int64))
  (:f named (List (Pair String String))) (:f imported (List Int64)) (:f defs (List (Pair String Int64))) (:f toks (List Tok))
  (:f alias (List (Pair String (Option String)))) (:f namedRel (List (Pair String (Option String)))) (:f full Bool))

(schema AslIndex (:f mods (List AslMod)) (:f byName (h/HMap (List AslMod))))

(schema CallRow (:f rel String) (:f line Int64) (:f kind String) (:f via (Option String)) (:f through (Option String)) (:f of String))

(schema Mention (:f rel String) (:f line Int64) (:f why String))

(schema AslCallers (:f defs (List (Pair String Int64))) (:f calls (List CallRow)) (:f possible (List Mention)) (:f excluded (List Mention)))

fn sliceOf s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn delim? b: Int64 -> Bool
  (or (= b 40) (= b 41) (= b 91) (= b 93) (= b 123) (= b 125) (= b 34) (= b 59) (= b 44))

fn atomEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (delim? (bytesGet bs i)) (> (c/spaceLenAt bs i n) 0)) i (atomEnd bs (+ i 1) n))

fn strEnd bs: Bytes j: Int64 n: Int64 line: Int64 -> (Pair Int64 Int64)
  (if (or (>= j n) (= (bytesGet bs j) 34))
    (pair j line)
    (let [(b (bytesGet bs j))]
      (cond ((= b 92) (strEnd bs (+ j 2) n line))
            ((= b 10) (strEnd bs (+ j 1) n (+ line 1)))
            (else (strEnd bs (+ j 1) n line)))))

fn lineEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEnd bs (+ i 1) n))

fn lexLoop text: String bs: Bytes i: Int64 n: Int64 line: Int64 k: Int64 depth: Int64 stop: Bool acc: (List Tok) -> (List Tok)
  (if (or (>= i n) (and stop (> k 0) (<= depth 0)))
    (listReverse acc)
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 10) (lexLoop text bs (+ i 1) n (+ line 1) k depth stop acc))
        ((= b 44) (lexLoop text bs (+ i 1) n line k depth stop acc))
        ((> (c/spaceLenAt bs i n) 0) (lexLoop text bs (+ i (c/spaceLenAt bs i n)) n line k depth stop acc))
        ((= b 59) (let [(j (lineEnd bs i n))] (lexLoop text bs j n line (+ k 1) depth stop (cons (Tok :kind "comment" :val (sliceOf text i j) :line line :idx k) acc))))
        ((= b 34) (let [(e (strEnd bs (+ i 1) n line)) (j (pairFirst e))]
                    (lexLoop text bs (+ j 1) n (pairSecond e) (+ k 1) depth stop (cons (Tok :kind "str" :val (sliceOf text (+ i 1) (min j n)) :line line :idx k) acc))))
        ((or (= b 40) (= b 123)) (lexLoop text bs (+ i 1) n line (+ k 1) (+ depth 1) stop (cons (Tok :kind "(" :val (sliceOf text i (+ i 1)) :line line :idx k) acc)))
        ((or (= b 41) (= b 125)) (lexLoop text bs (+ i 1) n line (+ k 1) (- depth 1) stop (cons (Tok :kind ")" :val (sliceOf text i (+ i 1)) :line line :idx k) acc)))
        ((= b 91) (lexLoop text bs (+ i 1) n line (+ k 1) (+ depth 1) stop (cons (Tok :kind "[" :val "[" :line line :idx k) acc)))
        ((= b 93) (lexLoop text bs (+ i 1) n line (+ k 1) (- depth 1) stop (cons (Tok :kind "]" :val "]" :line line :idx k) acc)))
        (else (let [(j (atomEnd bs i n))] (lexLoop text bs j n line (+ k 1) depth stop (cons (Tok :kind "atom" :val (sliceOf text i j) :line line :idx k) acc)))))))

fn aslLex text: String -> (List Tok)
  (let [(bs (stringToBytes text))] (lexLoop text bs 0 (bytesLength bs) 1 0 0 false (list)))

fn headLex text: String -> (List Tok)
  (let [(bs (stringToBytes text))] (lexLoop text bs 0 (bytesLength bs) 1 0 0 true (list)))

fn nameCharsEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (> (c/spaceLenAt bs i n) 0)
          (let [(b (bytesGet bs i))] (or (= b 40) (= b 41) (= b 91) (= b 93) (= b 34) (= b 59))))
    i
    (nameCharsEnd bs (+ i 1) n))

fn spacesEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(k (c/spaceLenAt bs i n))] (if (= k 0) i (spacesEnd bs (+ i k) n)))

fn defOfLine raw: String -> (Option String)
  (let [(bs (stringToBytes raw)) (n (bytesLength bs))
        (s0 (if (and (> n 0) (= (bytesGet bs 0) 40)) 1 0))
        (kw (cond ((= (sliceOf raw s0 (+ s0 2)) "fn") (+ s0 2)) ((= (sliceOf raw s0 (+ s0 4)) "defn") (+ s0 4))
                  ((= (sliceOf raw s0 (+ s0 5)) "const") (+ s0 5)) ((= (sliceOf raw s0 (+ s0 4)) "test") (+ s0 4)) (else -1)))]
    (if (< kw 0) (none)
      (let [(sp (spacesEnd bs kw n))]
        (if (= sp kw) (none)
          (let [(e (nameCharsEnd bs sp n))]
            (if (= e sp) (none) (some (sliceOf raw sp e))))))))

fn pairGet kv: (List (Pair String Int64)) k: String -> (Option Int64)
  (mt (listHead (filter (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) k)) kv)) ((some p) (some (pairSecond p))) ((none) (none)))

fn strGet kv: (List (Pair String String)) k: String -> (Option String)
  (c/mapGetOr kv k)

fn optGet kv: (List (Pair String (Option String))) k: String -> (Option String)
  (mt (listHead (filter (fn [(p (Pair String (Option String)))] -> Bool (= (pairFirst p) k)) kv)) ((some p) (pairSecond p)) ((none) (none)))

fn setKv kv: (List (Pair String String)) k: String v: String -> (List (Pair String String))
  (if (some? (strGet kv k)) (map (fn [(p (Pair String String))] -> (Pair String String) (if (= (pairFirst p) k) (pair k v) p)) kv) (listAppend kv (list (pair k v))))

fn setDefault kv: (List (Pair String String)) k: String v: String -> (List (Pair String String))
  (if (some? (strGet kv k)) kv (listAppend kv (list (pair k v))))

fn defStart? b: Int64 -> Bool
  (or (= b 40) (= b 102) (= b 100) (= b 99) (= b 116))

fn defsLoop text: String bs: Bytes i: Int64 n: Int64 line: Int64 acc: (List (Pair String Int64)) -> (List (Pair String Int64))
  (if (> i n)
    acc
    (let [(e (lineEnd bs i n))
          (acc2 (if (and (< i n) (defStart? (bytesGet bs i)))
                  (mt (defOfLine (sliceOf text i e))
                    ((some name) (if (some? (pairGet acc name)) acc (cons (pair name line) acc)))
                    ((none) acc))
                  acc))]
      (defsLoop text bs (+ e 1) n (+ line 1) acc2)))

fn defsOf text: String -> (List (Pair String Int64))
  (let [(bs (stringToBytes text))] (defsLoop text bs 0 (bytesLength bs) 1 (list)))

(schema Hdr (:f name (Option String)) (:f imports (List (Pair String String))) (:f exports (List Int64))
            (:f named (List (Pair String String))) (:f imported (List Int64)))

fn emptyHdr -> Hdr
  (Hdr :name (none) :imports (list) :exports (list) :named (list) :imported (list))

fn tail xs: (List Tok) -> (List Tok)
  (optionOr (listTail xs) (list))

fn headKind xs: (List Tok) -> String
  (mt (listHead xs) ((some t) t.kind) ((none) ""))

fn headVal xs: (List Tok) -> String
  (mt (listHead xs) ((some t) t.val) ((none) ""))

(schema Imp (:f rest (List Tok)) (:f alias (Option String)) (:f named (List (Pair String String))) (:f imported (List Int64)))

fn namedAtoms toks: (List Tok) target: String named: (List (Pair String String)) imported: (List Int64) -> Imp
  (mt (listHead toks)
    ((some t) (if (= t.kind "atom")
                (namedAtoms (tail toks) target (setKv named t.val target) (cons t.idx imported))
                (Imp :rest toks :alias (none) :named named :imported imported)))
    ((none) (Imp :rest toks :alias (none) :named named :imported imported)))

fn importForm toks: (List Tok) target: String st: Imp -> Imp
  (mt (listHead toks)
    ((none) (with st :rest (list)))
    ((some t)
      (if (= t.kind ")")
        (with st :rest (tail toks))
        (if (and (or (= t.val ":a") (= t.val ":as")) (not (listEmpty? (tail toks))))
          (if (= (headKind (tail toks)) "[")
            (let [(na (namedAtoms (tail (tail toks)) target st.named st.imported))]
              (importForm na.rest target (Imp :rest (list) :alias st.alias :named na.named :imported na.imported)))
            (importForm (tail toks) target (with st :rest (list) :alias (some (headVal (tail toks))))))
          (importForm (tail toks) target st)))))

fn hdrLoop toks: (List Tok) depth: Int64 key: String h: Hdr -> Hdr
  (if (<= depth 0)
    h
    (mt (listHead toks)
      ((none) h)
      ((some t)
        (let [(kind t.kind) (val t.val) (imp? (or (= key ":i") (= key ":import")))]
          (cond
            ((or (= kind "(") (= kind "["))
              (if (and (= kind "(") (= depth 2) imp? (= (headKind (tail toks)) "atom"))
                (let [(target (headVal (tail toks)))
                      (st (importForm (tail (tail toks)) target (Imp :rest (list) :alias (none) :named h.named :imported h.imported)))
                      (imports (setDefault (setKv h.imports (optionOr st.alias target) target) target target))]
                  (hdrLoop st.rest depth key (Hdr :name h.name :imports imports :exports h.exports :named st.named :imported st.imported)))
                (hdrLoop (tail toks) (+ depth 1) key h)))
            ((or (= kind ")") (= kind "]")) (hdrLoop (tail toks) (- depth 1) key h))
            ((and (= kind "atom") (= depth 1) (stringStartsWith? val ":")) (hdrLoop (tail toks) depth val h))
            ((and (= kind "atom") (= depth 2) imp?)
              (let [(last (optionOr (listLast (stringSplit val "/")) val))]
                (hdrLoop (tail toks) depth key (with h :imports (setDefault (setKv h.imports val val) last val)))))
            ((and (= kind "atom") (= depth 2) (or (= key ":x") (= key ":export")))
              (hdrLoop (tail toks) depth key (with h :exports (cons t.idx h.exports))))
            (else (hdrLoop (tail toks) depth key h)))))))

fn header toks: (List Tok) -> Hdr
  (mt (listHead toks)
    ((none) (emptyHdr))
    ((some t0)
      (let [(r1 (tail toks)) (r2 (tail r1))]
        (if (or (!= t0.kind "(") (!= (headKind r1) "atom") (!= (headVal r1) "module") (!= (headKind r2) "atom"))
          (emptyHdr)
          (let [(h (hdrLoop (tail r2) 1 "" (emptyHdr)))]
            (Hdr :name (some (headVal r2)) :imports h.imports :exports h.exports :named h.named :imported h.imported))))))

fn byNameGet idx: (h/HMap (List AslMod)) name: String -> (List AslMod)
  (optionOr (h/hmGet idx name) (list))

fn byNameAdd idx: (h/HMap (List AslMod)) m: AslMod -> (h/HMap (List AslMod))
  (h/hmPut idx m.name (listAppend (byNameGet idx m.name) (list m)))

fn noMod -> AslMod
  (AslMod :rel "" :name "" :imports (list) :exports (list) :named (list) :imported (list) :defs (list) :toks (list) :alias (list) :namedRel (list) :full false)

fn commonLen a: String b: String -> Int64
  (let [(pa (stringSplit a "/")) (pb (stringSplit b "/"))
        (common (fold (fn [(acc (Pair Bool (List String))) (p (Pair String String))] -> (Pair Bool (List String))
                        (if (and (pairFirst acc) (= (pairFirst p) (pairSecond p))) (pair true (cons (pairFirst p) (pairSecond acc))) (pair false (pairSecond acc))))
                      (pair true (list)) (zip pa pb)))]
    (stringLength (c/joinWith (listReverse (pairSecond common)) "/")))

fn bestNear ms: (List AslMod) importerRel: String -> String
  (let [(score (fn [(m AslMod)] -> Int64 (if (and (not (stringEmpty? (c/dirName m.rel))) (not (stringEmpty? (c/dirName importerRel)))) (commonLen m.rel importerRel) 0)))]
    (fold (fn [(best AslMod) (m AslMod)] -> AslMod (if (> (score m) (score best)) m best)) (optionOr (listHead ms) (noMod)) ms).rel)

(schema Near (:f suffix (h/HMap (List String))) (:f stem (h/HMap (List String))))

fn addRel m: (h/HMap (List String)) k: String rel: String -> (h/HMap (List String))
  (h/hmPut m k (cons rel (optionOr (h/hmGet m k) (list))))

fn nearOf mods: (List AslMod) -> Near
  (fold (fn [(acc Near) (m AslMod)] -> Near
          (let [(parts (stringSplit m.name "/"))
                (sufs (map (fn [(i Int64)] -> String (c/joinWith (listDrop parts i) "/")) (range 1 (listLength parts))))]
            (Near :suffix (fold (fn [(a2 (h/HMap (List String))) (k String)] -> (h/HMap (List String)) (addRel a2 k m.rel)) acc.suffix sufs)
                  :stem (addRel acc.stem (pairFirst (c/splitExt (c/baseName m.rel))) m.rel))))
        (Near :suffix (h/hmEmpty) :stem (h/hmEmpty)) mods)

fn moduleOf idx: (h/HMap (List AslMod)) near: Near target: String importer: String importerRel: String -> (Option String)
  (let [(parts (let [(ps (stringSplit importer "/"))] (listTake ps (- (listLength ps) 1))))
        (names (cons target (map (fn [(k Int64)] -> String (c/joinWith (listAppend (listTake parts k) (list target)) "/")) (listReverse (range 1 (+ (listLength parts) 1))))))
        (hit (listHead (filter (fn [(nm String)] -> Bool (not (listEmpty? (byNameGet idx nm)))) names)))]
    (mt hit
      ((some nm) (some (bestNear (byNameGet idx nm) importerRel)))
      ((none)
        (let [(cands (c/sortUnique (listAppend (optionOr (h/hmGet near.suffix target) (list)) (optionOr (h/hmGet near.stem target) (list)))))]
          (if (= (listLength cands) 1) (listHead cands) (none))))))

fn loadMod! root: String rel: String sym: String -> (Option AslMod)
  (mt (fileReadString (c/joinPath root rel))
    ((err _) (none))
    ((ok raw)
      (if (not (c/utf8Valid? raw))
        (none)
        (let [(text (c/universalNewlines raw)) (full (and (not (stringEmpty? sym)) (stringContains? text sym)))
              (toks (if full (aslLex text) (headLex text))) (h (header toks))]
          (some (AslMod :rel rel :name (optionOr h.name (pairFirst (c/splitExt (c/baseName rel)))) :imports h.imports :exports h.exports
                        :named h.named :imported h.imported :defs (defsOf text) :toks (if full toks (list)) :alias (list) :namedRel (list) :full full))))))

fn buildAslIndex! root: String files: (List String) sym: String -> AslIndex
  (let [(mods0 (fold (fn [(acc (List AslMod)) (rel String)] -> (List AslMod)
                       (if (stringEndsWith? rel ".asl") (mt (loadMod! root rel sym) ((some m) (cons m acc)) ((none) acc)) acc))
                     (list) files))
        (mods1 (listReverse mods0))
        (byName (fold byNameAdd (h/hmEmpty) mods1))
        (near (nearOf mods1))
        (resolve (fn [(m AslMod) (kv (List (Pair String String)))] -> (List (Pair String (Option String)))
                   (if m.full (map (fn [(p (Pair String String))] -> (Pair String (Option String)) (pair (pairFirst p) (moduleOf byName near (pairSecond p) m.name m.rel))) kv) (list))))
        (mods (map (fn [(m AslMod)] -> AslMod
                     (AslMod :rel m.rel :name m.name :imports m.imports :exports m.exports :named m.named :imported m.imported
                             :defs m.defs :toks m.toks :alias (resolve m m.imports) :namedRel (resolve m m.named) :full m.full))
                   mods1))]
    (AslIndex :mods mods :byName byName))

fn defNames ai: AslIndex -> (List String)
  (fold (fn [(acc (List String)) (m AslMod)] -> (List String) (listAppend acc (map (fn [(p (Pair String Int64))] -> String (pairFirst p)) m.defs))) (list) ai.mods)

fn wordByte? b: Int64 extra: (List Int64) -> Bool
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (listContains? extra b))

fn exactIn? text: String sym: String -> Bool
  (let [(bs (stringToBytes text)) (n (bytesLength bs)) (pat (stringToBytes sym)) (m (bytesLength pat))]
    (exactFrom bs n pat m 0))

fn exactFrom bs: Bytes n: Int64 pat: Bytes m: Int64 i: Int64 -> Bool
  (let [(at (c/findFrom bs n pat i))]
    (cond
      ((< at 0) false)
      ((and (or (= at 0) (not (wordByte? (bytesGet bs (- at 1)) (list 45 47))))
            (or (>= (+ at m) n) (not (wordByte? (bytesGet bs (+ at m)) (list 45 63 33)))))
        true)
      (else (exactFrom bs n pat m (+ at 1)))))

fn afterSlash val: String -> String
  (optionOr (listLast (stringSplit val "/")) val)

fn beforeSlash val: String -> String
  (let [(parts (stringSplit val "/"))] (c/joinWith (listTake parts (- (listLength parts) 1)) "/"))

(schema Walk (:f frames (List (Option String))) (:f calls (List CallRow)) (:f possible (List Mention)) (:f excluded (List Mention)) (:f prev (Option Tok)))

fn modNameOf ai: AslIndex rel: String -> String
  (mt (listHead (filter (fn [(m AslMod)] -> Bool (= m.rel rel)) ai.mods)) ((some m) m.name) ((none) ""))

fn onAtom ai: AslIndex m: AslMod sym: String targets: (List String) defLine: (Option Int64) t: Tok w: Walk -> Walk
  (let [(val t.val) (line t.line) (rel m.rel)
        (prevAtomKw (mt w.prev ((some p) (and (= p.kind "atom") (listContains? (list "fn" "defn" "const" "test") p.val))) ((none) false)))
        (isDef (and prevAtomKw (mt defLine ((some d) (= d line)) ((none) false))))
        (ex (fn [(why String)] -> Walk (with w :excluded (cons (Mention :rel rel :line line :why why) w.excluded) :prev (some t))))
        (po (fn [(why String)] -> Walk (with w :possible (cons (Mention :rel rel :line line :why why) w.possible) :prev (some t))))
        (same (with w :prev (some t)))]
    (cond
      ((and (listContains? m.exports t.idx) (= val sym)) (ex "export"))
      ((and (listContains? m.imported t.idx) (= val sym)) (ex "importOnly"))
      (else
        (let [(slashed (and (stringContains? val "/") (not (stringStartsWith? val "/"))))
              (res (cond
                     ((and slashed (= (afterSlash val) sym)) (pair (optGet m.alias (beforeSlash val)) (some val)))
                     (slashed (pair (none) (none)))
                     ((= val sym)
                       (let [(tr (if (some? (pairGet m.defs sym)) (some rel) (optGet m.namedRel sym)))]
                         (pair tr (if (= (optionOr tr "\x00") rel) (none) (some (str "import " (optionOr (strGet m.named sym) "")))))))
                     (else (pair (none) (none)))))
              (targetRel (pairFirst res)) (via (pairSecond res))]
          (mt targetRel
            ((none)
              (cond
                ((or (= val sym) (= (afterSlash val) sym))
                  (cond ((and isDef (not (listContains? targets rel))) (ex "otherDefinition"))
                        ((not isDef) (po (str "unresolved name " val)))
                        (else same)))
                ((and (stringContains? val sym) (not (stringStartsWith? val ":"))) (ex "similarName"))
                (else same)))
            ((some tr)
              (cond
                ((not (listContains? targets tr)) (ex "otherDefinition"))
                (isDef same)
                (else
                  (let [(isHead (and (mt w.prev ((some p) (= p.kind "(")) ((none) false))
                                     (mt (listHead w.frames) ((some fh) (= (optionOr fh "\x00") val)) ((none) false))))]
                    (if (not isHead)
                      (po "value reference")
                      (let [(ctx (listAny? (fn [(h (Option String))] -> Bool (= (optionOr h "") "fn")) (optionOr (listTail w.frames) (list))))
                            (how (cond ((stringContains? val "/") "attribute") ((some? via) "alias") (else "direct")))
                            (row (CallRow :rel rel :line line :kind (if ctx "lambda" how) :via via
                                          :through (if (and ctx (!= how "direct")) (some how) (none)) :of (modNameOf ai tr)))]
                        (with w :calls (cons row w.calls) :prev (some t)))))))))))))

fn walkToks ai: AslIndex m: AslMod sym: String targets: (List String) defLine: (Option Int64) toks: (List Tok) w: Walk -> Walk
  (mt (listHead toks)
    ((none) w)
    ((some t)
      (let [(rest (tail toks)) (kind t.kind)]
        (cond
          ((or (= kind "(") (= kind "["))
            (let [(head (if (and (= kind "(") (= (headKind rest) "atom")) (some (headVal rest)) (none)))]
              (walkToks ai m sym targets defLine rest (with w :frames (cons head w.frames) :prev (some t)))))
          ((or (= kind ")") (= kind "]"))
            (walkToks ai m sym targets defLine rest (with w :frames (optionOr (listTail w.frames) (list)) :prev (some t))))
          ((or (= kind "comment") (= kind "str"))
            (walkToks ai m sym targets defLine rest
                      (with w :excluded (if (exactIn? t.val sym) (cons (Mention :rel m.rel :line t.line :why (if (= kind "comment") "comment" "string")) w.excluded) w.excluded) :prev (some t))))
          (else (walkToks ai m sym targets defLine rest (onAtom ai m sym targets defLine t w)))))))

fn aslCallers ai: AslIndex sym: String module: String -> AslCallers
  (let [(targets (listSort (map (fn [(m AslMod)] -> String m.rel)
                                (filter (fn [(m AslMod)] -> Bool (and (some? (pairGet m.defs sym))
                                                                      (or (stringEmpty? module) (= module m.rel) (= module m.name) (stringEndsWith? m.name (str "/" module)))))
                                        ai.mods))))
        (defs (map (fn [(rel String)] -> (Pair String Int64) (pair rel (optionOr (mt (listHead (filter (fn [(m AslMod)] -> Bool (= m.rel rel)) ai.mods)) ((some m) (pairGet m.defs sym)) ((none) (none))) 0))) targets))
        (sorted (listSortBy (fn [(m AslMod)] -> String m.rel) (filter (fn [(m AslMod)] -> Bool m.full) ai.mods)))
        (w (fold (fn [(acc Walk) (m AslMod)] -> Walk
                   (let [(r (walkToks ai m sym targets (pairGet m.defs sym) m.toks (Walk :frames (list) :calls acc.calls :possible acc.possible :excluded acc.excluded :prev (none))))]
                     r))
                 (Walk :frames (list) :calls (list) :possible (list) :excluded (list) :prev (none)) sorted))]
    (AslCallers :defs defs :calls (listReverse w.calls) :possible (listReverse w.possible) :excluded (listReverse w.excluded)))
