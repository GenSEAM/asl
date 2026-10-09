(module asl-intel/graph
  :x [GraphNode Graph Rated GraphSummary resolveWorkspace! buildGraph! analyzeGraph! analyzeGraphAt! ratedJson runGraph! fl flag]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/host :a h)
      (asl-intel/tab :a tb)
      (asl-intel/coupling :a c)
      (asl-intel/stubs :a st)])

(schema Rec
  (:f file Int64)
  (:f rel String)
  (:f modId Int64)
  (:f modName String)
  (:f raw String)
  (:f clean String)
  (:f params String)
  (:f symId Int64)
  (:f node Int64)
  (:f code String)
  (:f b Bytes)
  (:f s Int64)
  (:f e Int64))

(schema GraphNode
  (:f id String)
  (:f module String)
  (:f file String)
  (:f symbol String)
  (:f kind String)
  (:f isPure Bool)
  (:f isStub Bool)
  (:f stubKind String)
  (:f stubReason String)
  (:f complexity Int64)
  (:f exprCount Int64)
  (:f fanIn Int64)
  (:f fanOut Int64)
  (:f testCallers Int64)
  (:f index Int64))

(schema Graph
  (:f nodes (List GraphNode))
  (:f modules Int64)
  (:f edges Int64)
  (:f links (List (Pair Int64 Int64))))

(schema Scan
  (:f recs (List Rec))
  (:f files Int64)
  (:f imports (List (Pair Int64 (List Int64))))
  (:f syms tb/Strtab)
  (:f mods tb/Strtab)
  (:f fileMods tb/Strtab)
  (:f keys tb/Strtab)
  (:f keyBuf Bytes))

fn resolveWorkspace! ctx: h/Ctx -> String
  (if (not (stringEmpty? ctx.aslRoot))
    (let [(abs (t/absPath ctx.aslRoot ctx.cwd))] (mt (realPath abs) ((ok q) q) ((err _) abs)))
    (gitProbe! ctx.cwd ctx.cwd))

fn gitProbe! dir: String orig: String -> String
  (cond
    ((fileExists? (t/joinPath dir ".git")) dir)
    ((= (t/dirName dir) dir) orig)
    (else (gitProbe! (t/dirName dir) orig)))

fn nodeOf! keys: tb/Strtab buf: Bytes modId: Int64 symId: Int64 -> Int64
  (do (tb/ivSet! buf 0 modId) (tb/ivSet! buf 1 symId) (tb/lookup keys buf 0 16))

fn importIds! mods: tb/Strtab code: String -> (Pair tb/Strtab (List Int64))
  (mt (c/firstGroup (p/patImportsBlock!) code)
    ((none) (pair mods (list)))
    ((some blk)
      (fold (fn [(acc (Pair tb/Strtab (List Int64))) (nm String)] -> (Pair tb/Strtab (List Int64))
              (let [(q (tb/internStr! (pairFirst acc) nm))] (pair (pairFirst q) (cons (pairSecond q) (pairSecond acc)))))
            (pair mods (list)) (c/allGroups (p/patImportName!) blk))))

fn scanFile! sc: Scan fi: Int64 rel: String code: String -> Scan
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (modName (optionOr (c/firstGroup (p/patModuleId!) code) rel))
        (mq (tb/internStr! sc.mods modName))
        (fm (pairFirst (tb/internStr! sc.fileMods modName)))
        (iq (importIds! (pairFirst mq) code))
        (hs (st/headersOf! code b n))]
    (fold (fn [(acc Scan) (hd st/Header)] -> Scan
            (let [(raw hd.rawName)
                  (clean (t/pyStrip (t/lstripSet raw "!")))
                  (sq (tb/internStr! acc.syms clean))
                  (buf acc.keyBuf)
                  (_k (do (tb/ivSet! buf 0 (pairSecond mq)) (tb/ivSet! buf 1 (pairSecond sq))))
                  (kq (tb/intern! acc.keys buf 0 16))]
              (Scan :recs (cons (Rec :file fi :rel rel :modId (pairSecond mq) :modName modName :raw raw :clean clean
                                     :params hd.params :symId (pairSecond sq) :node (pairSecond kq)
                                     :code code :b b :s hd.bodyStart :e hd.bodyEnd)
                                acc.recs)
                    :files acc.files :imports acc.imports :syms (pairFirst sq) :mods acc.mods
                    :fileMods acc.fileMods :keys (pairFirst kq) :keyBuf buf)))
          (with sc :files (+ sc.files 1) :imports (cons (pair fi (pairSecond iq)) sc.imports) :mods (pairFirst iq) :fileMods fm)
          hs))

fn scanAll! ctx: h/Ctx root: String files: (List String) -> Scan
  (pairSecond
    (fold (fn [(acc (Pair Int64 Scan)) (rel String)] -> (Pair Int64 Scan)
            (mt (h/readText! (if (stringStartsWith? rel "/") rel (t/joinPath root rel)))
              ((err _) acc)
              ((ok code) (pair (+ (pairFirst acc) 1) (scanFile! (pairSecond acc) (pairFirst acc) rel code)))))
          (pair 0 (Scan :recs (list) :files 0 :imports (list) :syms (tb/strtabNew 4096) :mods (tb/strtabNew 1024)
                        :fileMods (tb/strtabNew 1024) :keys (tb/strtabNew 4096) :keyBuf (bytesAlloc 16)))
          files))

fn testPath? rel: String -> Bool
  (or (stringContains? (t/lowerAscii rel) "test") (or (stringContains? rel "/tests/") (stringStartsWith? rel "tests/")))

fn tokTable! -> Bytes
  (let [(tbl (bytesAlloc 256))]
    (do (markRange! tbl 48 57) (markRange! tbl 65 90) (markRange! tbl 97 122)
        (bytesSet tbl 95 1) (bytesSet tbl 63 1) (bytesSet tbl 46 1) (bytesSet tbl 45 1) tbl))

fn markRange! tbl: Bytes a: Int64 z: Int64 -> Unit
  (if (> a z) () (do (bytesSet tbl a 1) (markRange! tbl (+ a 1) z)))

fn tokEnd tbl: Bytes b: Bytes e: Int64 i: Int64 -> Int64
  (if (and (< i e) (= (bytesGet tbl (bytesGet b i)) 1)) (tokEnd tbl b e (+ i 1)) i)

fn wordEnd b: Bytes e: Int64 i: Int64 -> Int64
  (if (and (< i e) (t/isWordByteAscii (bytesGet b i))) (wordEnd b e (+ i 1)) i)

fn decisionTable! -> tb/Strtab
  (fold (fn [(tab tb/Strtab) (w String)] -> tb/Strtab (pairFirst (tb/internStr! tab w)))
        (tb/strtabNew 16) (list "if" "cond" "mt" "fold" "map" "filter" "and" "or" "case" "when"))

(schema Body
  (:f decisions Int64)
  (:f parens Int64)
  (:f sigil Bool)
  (:f callees (List Int64)))

(schema Lx
  (:f tok Bytes)
  (:f dec tb/Strtab)
  (:f syms tb/Strtab)
  (:f seen Bytes)
  (:f sigils (List Bytes)))

fn wholeWord? b: Bytes s: Int64 e: Int64 a: Int64 z: Int64 -> Bool
  (and (or (= a s) (not (t/wordBefore? b e a))) (or (= z e) (not (t/wordAt? b e z))))

fn subruns lx: Lx b: Bytes s: Int64 e: Int64 i: Int64 z: Int64 acc: Body -> Body
  (if (>= i z) acc
    (if (not (t/isWordByteAscii (bytesGet b i))) (subruns lx b s e (+ i 1) z acc)
      (let [(q (wordEnd b z i)) (k (- q i))
            (decCand (and (<= k 6) (and (>= k 2) (>= (tb/lookup lx.dec b i q) 0))))
            (sigCand (and (not decCand) (and (or (= k 4) (or (= k 12) (or (= k 13) (= k 15))))
                                             (listAny? (fn [(w Bytes)] -> Bool (and (= (bytesLength w) k) (= (t/foldIndexOf b q w k i) i))) lx.sigils))))]
        (if (or decCand sigCand)
          (if (wholeWord? b s e i q)
            (subruns lx b s e q z (with acc :decisions (if decCand (+ acc.decisions 1) acc.decisions) :sigil (or acc.sigil sigCand)))
            (subruns lx b s e q z acc))
          (subruns lx b s e q z acc)))))

fn bodyScan! lx: Lx stamp: Int64 b: Bytes s: Int64 e: Int64 i: Int64 acc: Body -> Body
  (if (>= i e) acc
    (let [(x (bytesGet b i))]
      (cond
        ((= (bytesGet lx.tok x) 1)
          (let [(z (tokEnd lx.tok b e i))
                (sym (tb/lookup lx.syms b i z))
                (fresh (and (>= sym 0) (!= (tb/ivGet lx.seen sym) stamp)))
                (_m (if fresh (tb/ivSet! lx.seen sym stamp) ()))
                (a2 (subruns lx b s e i z acc))]
            (bodyScan! lx stamp b s e z
              (if fresh (Body :decisions a2.decisions :parens a2.parens :sigil a2.sigil :callees (cons sym a2.callees)) a2))))
        ((= x 40) (bodyScan! lx stamp b s e (+ i 1) (with acc :parens (+ acc.parens 1))))
        (else (bodyScan! lx stamp b s e (+ i 1) acc)))))

fn stubOf rec: Rec isTest: Bool sigil: Bool -> (Pair String String)
  (let [(b rec.b) (n (bytesLength b)) (code rec.code)
        (bs (t/skipSpace b n rec.s))
        (be (t/trimSpaceBack b n bs rec.e))
        (cl (st/parenTrim b bs be))
        (isConst (or (st/constSpan? code bs be) (st/constSpan? code (pairFirst cl) (pairSecond cl))))
        (body (if isConst (t/sliceStr code bs be) ""))
        (params (if isConst (st/headerParams rec.params) (list)))
        (raw rec.raw)]
    (cond
      ((and (not (listEmpty? params)) isConst)
        (if (listAll? (fn [(q String)] -> Bool (not (t/wordHas? body q))) params)
          (pair "ignored-params" (str "Ignored parameters " (t/pyReprList params) "; returns constant " body))
          (pair "none" "")))
      ((and isTest (and (or (stringStartsWith? raw "test") (stringStartsWith? raw "runTests"))
                        (and (not (stringContains? body "assert")) (and (not (stringContains? body "refute")) isConst))))
        (pair "vacuous-test" "Test returns constant without executed assertions"))
      (sigil (pair "placeholder" "Contains placeholder/unimplemented sigils"))
      (else (pair "none" ""))))

fn finalRecs! recsOldFirst: (List Rec) nodeCount: Int64 -> (List Rec)
  (let [(last (tb/ivNew nodeCount))
        (_w (fold (fn [(r Int64) (rec Rec)] -> Int64 (do (tb/ivSet! last rec.node r) (+ r 1))) 0 recsOldFirst))
        (keep (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List Rec))) (rec Rec)] -> (Pair Int64 (List Rec))
                                                (pair (+ (pairFirst acc) 1) (if (= (tb/ivGet last rec.node) (pairFirst acc)) (cons rec (pairSecond acc)) (pairSecond acc))))
                                              (pair 0 (list)) recsOldFirst))))]
    (tb/sortWith (fn [(a Rec) (x Rec)] -> Bool (< a.node x.node)) keep))

(schema Link
  (:f fanIn Bytes)
  (:f testCallers Bytes)
  (:f cacheFile Bytes)
  (:f cacheVal Bytes)
  (:f symCount Bytes)
  (:f symFirst Bytes))

fn resolve! lk: Link keys: tb/Strtab buf: Bytes imports: (List Int64) fi: Int64 mid: Int64 sym: Int64 -> Int64
  (if (= (tb/ivGet lk.cacheFile sym) (+ fi 1)) (tb/ivGet lk.cacheVal sym)
    (let [(own (nodeOf! keys buf mid sym))
          (target (if (>= own 0) own
                    (let [(m (fold (fn [(best Int64) (im Int64)] -> Int64
                                     (let [(x (nodeOf! keys buf im sym))] (if (and (>= x 0) (or (< best 0) (< x best))) x best)))
                                   -1 imports))]
                      (cond
                        ((>= m 0) m)
                        ((= (tb/ivGet lk.symCount sym) 1) (tb/ivGet lk.symFirst sym))
                        (else -1)))))]
      (do (tb/ivSet! lk.cacheFile sym (+ fi 1)) (tb/ivSet! lk.cacheVal sym target) target)))

fn buildGraph! ctx: h/Ctx root: String keepLinks: Bool -> (Result Graph String)
  (mt (st/trackedAsl! ctx root)
    ((err e) (err e))
    ((ok files)
      (let [(sc (scanAll! ctx root files))
            (recs (listReverse sc.recs))
            (nNodes (tb/strtabCount sc.keys))
            (nSyms (tb/strtabCount sc.syms))
            (finals (finalRecs! recs nNodes))
            (impCsr (importTable! (listReverse sc.imports) sc.files))
            (lk (Link :fanIn (tb/ivNew nNodes) :testCallers (tb/ivNew nNodes) :cacheFile (tb/ivNew nSyms) :cacheVal (tb/ivNew nSyms)
                      :symCount (tb/ivNew nSyms) :symFirst (tb/ivNew nSyms)))
            (_c (map (fn [(rec Rec)] -> Unit
                       (do (if (= (tb/ivGet lk.symCount rec.symId) 0) (tb/ivSet! lk.symFirst rec.symId rec.node) ())
                           (tb/ivAdd! lk.symCount rec.symId 1)))
                     recs))
            (lx (Lx :tok (tokTable!) :dec (decisionTable!) :syms sc.syms :seen (tb/ivNew nSyms) :sigils (map stringToBytes (list "TODO" "UNIMPLEMENTED" "NOT_IMPLEMENTED" "STUB_EVASION"))))
            (pass (fold (fn [(acc (Pair (Pair Int64 (List (Pair Int64 Int64))) (List (Pair Rec (Pair Body Int64))))) (rec Rec)] -> (Pair (Pair Int64 (List (Pair Int64 Int64))) (List (Pair Rec (Pair Body Int64))))
                          (let [(idx rec.node)
                                (isTest (testPath? rec.rel))
                                (body (bodyScan! lx (+ idx 1) rec.b rec.s rec.e rec.s (Body :decisions 0 :parens 0 :sigil false :callees (list))))
                                (imports (importsOf impCsr rec.file))
                                (targets (filter (fn [(x Int64)] -> Bool (and (>= x 0) (!= x idx)))
                                                 (map (fn [(sym Int64)] -> Int64 (resolve! lk sc.keys sc.keyBuf imports rec.file rec.modId sym))
                                                      (listReverse body.callees))))
                                (_e (map (fn [(x Int64)] -> Unit (do (tb/ivAdd! lk.fanIn x 1) (if isTest (tb/ivAdd! lk.testCallers x 1) ()))) targets))
                                (links (if keepLinks (fold (fn [(ls (List (Pair Int64 Int64))) (x Int64)] -> (List (Pair Int64 Int64)) (cons (pair idx x) ls)) (pairSecond (pairFirst acc)) targets) (pairSecond (pairFirst acc))))]
                            (pair (pair (+ (pairFirst (pairFirst acc)) (listLength targets)) links)
                                  (cons (pair rec (pair body (listLength targets))) (pairSecond acc)))))
                        (pair (pair 0 (list)) (list)) finals))
            (nodes (map (fn [(x (Pair Rec (Pair Body Int64)))] -> GraphNode
                          (let [(rec (pairFirst x)) (body (pairFirst (pairSecond x))) (idx rec.node) (isTest (testPath? rec.rel))
                                (sk (stubOf rec isTest body.sigil))]
                            (GraphNode :id (str rec.modName ":" rec.clean) :module rec.modName :file rec.rel :symbol rec.clean
                                   :kind (if isTest "test" "fn") :isPure (not (stringStartsWith? rec.raw "!"))
                                   :isStub (!= (pairFirst sk) "none") :stubKind (pairFirst sk) :stubReason (pairSecond sk)
                                   :complexity (+ 1 body.decisions) :exprCount body.parens
                                   :fanIn (tb/ivGet lk.fanIn idx) :fanOut (pairSecond (pairSecond x)) :testCallers (tb/ivGet lk.testCallers idx)
                                   :index idx)))
                        (listReverse (pairSecond pass))))]
        (ok (Graph :nodes nodes :modules (tb/strtabCount sc.fileMods) :edges (pairFirst (pairFirst pass)) :links (pairSecond (pairFirst pass)))))))

fn importTable! perFile: (List (Pair Int64 (List Int64))) nFiles: Int64 -> (Pair Bytes Bytes)
  (let [(total (fold (fn [(a Int64) (x (Pair Int64 (List Int64)))] -> Int64 (+ a (listLength (pairSecond x)))) 0 perFile))
        (offs (tb/ivNew (+ nFiles 1))) (data (tb/ivNew total))]
    (do (fold (fn [(pos Int64) (x (Pair Int64 (List Int64)))] -> Int64
                (do (tb/ivSet! offs (pairFirst x) pos)
                    (let [(end (fold (fn [(q Int64) (m Int64)] -> Int64 (do (tb/ivSet! data q m) (+ q 1))) pos (pairSecond x)))]
                      (do (tb/ivSet! offs (+ (pairFirst x) 1) end) end))))
              0 perFile)
        (pair offs data)))

fn importsOf csr: (Pair Bytes Bytes) fi: Int64 -> (List Int64)
  (let [(a (tb/ivGet (pairFirst csr) fi)) (z (tb/ivGet (pairFirst csr) (+ fi 1)))]
    (importsLoop (pairSecond csr) a z (list)))

fn importsLoop data: Bytes i: Int64 z: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i z) acc (importsLoop data (+ i 1) z (cons (tb/ivGet data i) acc)))

(schema Rated
  (:f node GraphNode)
  (:f instability Float)
  (:f hotspot Float)
  (:f blast Float)
  (:f callers (List String))
  (:f callees (List String))
  (:f tests (List String)))

(schema GraphSummary
  (:f totalNodes Int64)
  (:f totalEdges Int64)
  (:f totalModules Int64)
  (:f avgComplexity Float)
  (:f hotspotsCount Int64)
  (:f filterMode String)
  (:f limit Int64)
  (:f filteredCount Int64)
  (:f nodes (List Rated)))

fn fl x: Int64 -> Float
  (int64ToFloat64 x)

fn rate total: Int64 n: GraphNode -> Rated
  (let [(fi n.fanIn) (fo n.fanOut)]
    (Rated :node n
           :instability (if (> (+ fi fo) 0) (t/pyRound (/ (fl fo) (fl (+ fi fo))) 3) 0.0)
           :hotspot (t/pyRound (/ (fl (* n.complexity (+ fi 1))) (fl (+ n.testCallers 1))) 2)
           :blast (t/pyRound (/ (* (fl (+ fi fo)) 100.0) (fl (max 1 total))) 3)
           :callers (list) :callees (list) :tests (list)))

fn withLinks g: Graph rated: (List Rated) -> (List Rated)
  (let [(names (map (fn [(n GraphNode)] -> (Pair String String) (pair n.id n.kind)) g.nodes))]
    (map (fn [(x Rated)] -> Rated
           (let [(me x.node.index)
                 (ins (filter (fn [(l (Pair Int64 Int64))] -> Bool (= (pairSecond l) me)) g.links))
                 (outs (filter (fn [(l (Pair Int64 Int64))] -> Bool (= (pairFirst l) me)) g.links))
                 (idOf (fn [(k Int64)] -> String (idAt names k)))]
             (Rated :node x.node :instability x.instability :hotspot x.hotspot :blast x.blast
                    :callers (sortStrings (map (fn [(l (Pair Int64 Int64))] -> String (idOf (pairFirst l))) ins))
                    :callees (sortStrings (map (fn [(l (Pair Int64 Int64))] -> String (idOf (pairSecond l))) outs))
                    :tests (sortStrings (map (fn [(l (Pair Int64 Int64))] -> String (idOf (pairFirst l)))
                                             (filter (fn [(l (Pair Int64 Int64))] -> Bool (= (kindAt names (pairFirst l)) "test")) ins))))))
         rated))

fn idAt names: (List (Pair String String)) k: Int64 -> String
  (mt (listGet names k) ((some q) (pairFirst q)) ((none) ""))

fn kindAt names: (List (Pair String String)) k: Int64 -> String
  (mt (listGet names k) ((some q) (pairSecond q)) ((none) ""))

fn strLess? a: String b: String -> Bool
  (let [(x (stringToBytes a)) (y (stringToBytes b))]
    (bytesLess? x (bytesLength x) y (bytesLength y) 0))

fn bytesLess? x: Bytes nx: Int64 y: Bytes ny: Int64 i: Int64 -> Bool
  (cond
    ((>= i ny) false)
    ((>= i nx) true)
    ((< (bytesGet x i) (bytesGet y i)) true)
    ((> (bytesGet x i) (bytesGet y i)) false)
    (else (bytesLess? x nx y ny (+ i 1))))

fn sortStrings xs: (List String) -> (List String)
  (tb/sortWith strLess? xs)

fn capitalize s: String -> String
  (let [(low (t/lowerAscii s))]
    (if (stringEmpty? low) low (str (t/upperAscii (t/sliceStr low 0 1)) (t/sliceStr low 1 (stringLength low)))))

fn sortDesc key: (Fn Rated Float) xs: (List Rated) -> (List Rated)
  (tb/sortWith (fn [(a Rated) (b Rated)] -> Bool (> (key a) (key b))) xs)

fn analyzeGraph! ctx: h/Ctx mode: String limit: Int64 modF: String symF: String -> (Result GraphSummary String)
  (analyzeGraphAt! ctx (resolveWorkspace! ctx) mode limit modF symF)

fn analyzeGraphAt! ctx: h/Ctx root: String mode: String limit: Int64 modF: String symF: String -> (Result GraphSummary String)
  (mt (buildGraph! ctx root (not (stringEmpty? symF)))
    ((err e) (err e))
    ((ok g)
      (let [(total (listLength g.nodes))
            (totalCc (fold (fn [(a Int64) (n GraphNode)] -> Int64 (+ a n.complexity)) 0 g.nodes))
            (rated (map (fn [(n GraphNode)] -> Rated (rate total n)) g.nodes))
            (symL (t/lowerAscii symF)) (modL (t/lowerAscii modF))
            (filtered (cond
                        ((not (stringEmpty? symF)) (filter (fn [(x Rated)] -> Bool (or (stringContains? (t/lowerAscii x.node.symbol) symL) (stringContains? (t/lowerAscii x.node.id) symL))) rated))
                        ((not (stringEmpty? modF)) (filter (fn [(x Rated)] -> Bool (or (stringContains? (t/lowerAscii x.node.module) modL) (stringContains? (t/lowerAscii x.node.file) modL))) rated))
                        (else rated)))
            (ordered (cond
                       ((= mode "stubs") (sortDesc (fn [(x Rated)] -> Float x.hotspot) (filter (fn [(x Rated)] -> Bool x.node.isStub) filtered)))
                       ((= mode "complex") (sortDesc (fn [(x Rated)] -> Float (fl x.node.complexity)) filtered))
                       ((= mode "coupled") (tb/sortWith (fn [(a Rated) (b Rated)] -> Bool
                                                          (or (> a.node.fanIn b.node.fanIn)
                                                              (and (= a.node.fanIn b.node.fanIn) (> a.node.fanOut b.node.fanOut))))
                                                        filtered))
                       (else (sortDesc (fn [(x Rated)] -> Float x.hotspot) filtered))))
            (hot (listLength (filter (fn [(n GraphNode)] -> Bool (>= (/ (fl (* n.complexity (+ n.fanIn 1))) (fl (+ n.testCallers 1))) 50.0)) g.nodes)))
            (picked (if (> limit 0) (t/takeN ordered limit) ordered))
            (selected (if (stringEmpty? symF) picked (withLinks g picked)))]
        (ok (GraphSummary :totalNodes total :totalEdges g.edges :totalModules g.modules
                         :avgComplexity (t/pyRound (/ (fl totalCc) (fl (max 1 total))) 2)
                         :hotspotsCount hot :filterMode mode :limit limit :filteredCount (listLength ordered) :nodes selected)))))

fn flag x: Bool -> String
  (if x ":true" ":false")

fn formatGraphAsn res: GraphSummary -> String
  (t/joinWith (list "(:codeGraph" "  :status :ok"
                    (str "  :totalNodes " (t/intStr res.totalNodes))
                    (str "  :totalEdges " (t/intStr res.totalEdges))
                    (str "  :totalModules " (t/intStr res.totalModules))
                    (str "  :avgComplexity " (t/floatStr res.avgComplexity))
                    (str "  :hotspotsCount " (t/intStr res.hotspotsCount))
                    (str "  :assertCount " (t/intStr (+ res.totalNodes res.totalEdges)))
                    (if (listEmpty? res.nodes) "  :nodes []"
                      (str "  :nodes [\n    "
                           (t/joinWith (map (fn [(x Rated)] -> String
                                              (let [(n x.node)]
                                                (t/concatAll (list "(:node :id \"" n.id "\" :module \"" n.module "\" :symbol \"" n.symbol
                                                                   "\" :kind \"" n.kind "\" :isPure " (flag n.isPure) " :complexity " (t/intStr n.complexity)
                                                                   " :fanIn " (t/intStr n.fanIn) " :fanOut " (t/intStr n.fanOut) " :instability " (t/floatStr x.instability)
                                                                   " :testCallers " (t/intStr n.testCallers) " :blastRadiusPct " (t/floatStr x.blast)
                                                                   " :hotspotScore " (t/floatStr x.hotspot) ")"))))
                                            res.nodes)
                                       "\n    ")
                           "\n  ]"))
                    ")")
              "\n")

fn fiveOf xs: (List String) -> String
  (let [(k (listLength xs)) (head (t/joinWith (t/takeN xs 5) ", "))]
    (if (> k 5) (str head " ... (+" (t/intStr (- k 5)) " more)") head))

fn formatGraphSummary res: GraphSummary -> String
  (t/joinWith
    (listAppend
      (list "=== ASL MONOREPO CODE GRAPH & ARCHITECTURAL HOTSPOTS ==="
            (str "Total Indexed Symbols: " (t/intStr res.totalNodes))
            (str "Total Resolved Edges:   " (t/intStr res.totalEdges))
            (str "Total Scanned Modules:  " (t/intStr res.totalModules))
            (str "Average Complexity:     " (t/floatStr res.avgComplexity))
            (str "Hotspots (Score >= 50): " (t/intStr res.hotspotsCount))
            (str "Executed Assertions:    " (t/intStr (+ res.totalNodes res.totalEdges))))
      (if (listEmpty? res.nodes) (list)
        (cons "" (cons (str "--- Top Nodes by " (capitalize res.filterMode) " (Showing " (t/intStr (listLength res.nodes)) " of " (t/intStr res.filteredCount) ") ---")
          (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List String))) (x Rated)] -> (Pair Int64 (List String))
                                           (let [(n x.node) (i (pairFirst acc))
                                                 (l1 (str "  " (t/intStr i) ". " n.id " [" n.kind ", " (if n.isPure "pure" "impure(!)") "]"))
                                                 (l2 (t/concatAll (list "     CC: " (t/intStr n.complexity) " | Fan-In: " (t/intStr n.fanIn) " | Fan-Out: " (t/intStr n.fanOut)
                                                                        " | Instab: " (t/floatStr x.instability) " | Tests: " (t/intStr n.testCallers)
                                                                        " | Blast: " (t/floatStr x.blast) "% | RiskScore: " (t/floatStr x.hotspot))))
                                                 (withCallers (if (listEmpty? x.callers) (list) (list (str "     Callers: " (fiveOf x.callers)))))
                                                 (withCallees (if (listEmpty? x.callees) (list) (list (str "     Callees: " (fiveOf x.callees)))))]
                                             (pair (+ i 1) (listAppend (listReverse (listAppend (list l1 l2) (listAppend withCallers withCallees))) (pairSecond acc)))))
                                         (pair 1 (list)) res.nodes)))))))
    "\n")

fn ratedJson x: Rated -> j/Json
  (let [(n x.node)]
    (j/jObj (list (pair "id" (j/jStr n.id)) (pair "module" (j/jStr n.module)) (pair "file" (j/jStr n.file))
                  (pair "symbol" (j/jStr n.symbol)) (pair "kind" (j/jStr n.kind)) (pair "isPure" (j/jBool n.isPure))
                  (pair "isStub" (j/jBool n.isStub)) (pair "stubKind" (j/jStr n.stubKind)) (pair "stubReason" (j/jStr n.stubReason))
                  (pair "complexity" (j/jInt n.complexity)) (pair "expressionCount" (j/jInt n.exprCount))
                  (pair "fanIn" (j/jInt n.fanIn)) (pair "fanOut" (j/jInt n.fanOut)) (pair "instability" (j/jFloat x.instability))
                  (pair "testCallers" (j/jInt n.testCallers)) (pair "blastRadiusPct" (j/jFloat x.blast)) (pair "hotspotScore" (j/jFloat x.hotspot))
                  (pair "callers" (j/jStrs x.callers)) (pair "callees" (j/jStrs x.callees)) (pair "tests" (j/jStrs x.tests)))))

fn graphJson res: GraphSummary -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok")) (pair "totalNodes" (j/jInt res.totalNodes)) (pair "totalEdges" (j/jInt res.totalEdges))
                (pair "totalModules" (j/jInt res.totalModules)) (pair "avgComplexity" (j/jFloat res.avgComplexity))
                (pair "hotspotsCount" (j/jInt res.hotspotsCount)) (pair "assertCount" (j/jInt (+ res.totalNodes res.totalEdges)))
                (pair "filterMode" (j/jStr res.filterMode)) (pair "limit" (j/jInt res.limit))
                (pair "filteredCount" (j/jInt res.filteredCount)) (pair "nodes" (j/jArr (map ratedJson res.nodes)))))

fn runGraph! ctx: h/Ctx fmt: String mode: String limit: Int64 modF: String symF: String -> h/Outcome
  (mt (analyzeGraph! ctx mode limit modF symF)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res) (h/outcome (str (cond ((= fmt "json") (j/dumps (graphJson res))) ((= fmt "summary") (formatGraphSummary res)) (else (formatGraphAsn res))) "\n") "" 0)))
