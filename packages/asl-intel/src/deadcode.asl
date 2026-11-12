(module asl-intel/deadcode
  :x [Def DeadCodeSummary analyzeDeadcode! deadcodeJson formatDeadcodeAsn formatDeadcodeSummary runDeadcode! walkIgnoring! trackedAsl!]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/host :a h)
      (asl-intel/coupling :a c)
      (asl-intel/tab :a tb)])

(schema Def
  (:f file String)
  (:f name String)
  (:f kind String)
  (:f exported Bool))

(schema DeadCodeSummary
  (:f filesScanned Int64)
  (:f totalDefs Int64)
  (:f dead (List Def))
  (:f reach (List Def)))

(schema ReachFn
  (:f file String)
  (:f name String)
  (:f exported Bool)
  (:f body String))

(schema ReachAccum
  (:f scanned Int64)
  (:f total Int64)
  (:f dead (List Def))
  (:f defs (List Def))
  (:f fns (List ReachFn))
  (:f roots (List String)))

(schema ReachEdge
  (:f from Int64)
  (:f to Int64))

; (:m :ref DEADCODE-EXCLUDE-CACHE :do "copies under .asl/cache are build artifacts, so deadcode no longer scans them; they inflated filesScanned and made a private fn look referenced twice")
fn cacheCopy? fpath: String -> Bool
  (or (stringContains? fpath "/.asl/cache/") (stringStartsWith? fpath ".asl/cache/"))

fn walkIgnoring! ctx: h/Ctx root: String -> (Result (List String) String)
  (match (h/findTree! ctx root true (list "*.asl"))
    ((err e) (err e))
    ((ok tree) (ok (filter (fn [(f String)] -> Bool (not (cacheCopy? f))) (h/walkFiles! tree)))))

; (:m :ref MAINFIX14-TRACKEDASL-20261019 :do "walkIgnoring! shells out to find, which has no notion of .gitignore and descends into gitignored dirs such as .asl/cache -- harmless for lint (working tree, no claim of truth) but wrong for any audit that reports a production-truth count: a fixture artifact another suite happens to leave in .asl/cache/<suite>/*.asl (nativeTest.asl, nativeTestReportTest.asl -- both gitignored by .gitignore:9) gets scanned and counted as a real production stub. trackedAsl! asks git ls-files instead, so only committed source is ever in scope; same pattern already proven in asl-intel/stubs.asl trackedAsl!")
fn trackedAsl! ctx: h/Ctx root: String -> (Result (List String) String)
  (match (h/gitLsFiles! ctx root)
    ((ok fs) (ok (filter (fn [(f String)] -> Bool (and (stringEndsWith? f ".asl") (not (stringContains? f "/invalid/")))) fs)))
    ((err _)
      (match (walkIgnoring! ctx root)
        ((err e) (err e))
        ((ok fs) (ok (map (fn [(f String)] -> String (t/relPath f root ctx.cwd)) fs))))))

fn fileDefs! code: String rel: String -> (List Def)
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (exports (match (c/firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))
        (fns (fold (fn [(acc (List Def)) (caps (List Int64))] -> (List Def)
                     (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
                       (if (or (listContains? (list "main" "RunTests" "runTests") name) (stringStartsWith? name "!")) acc
                         (cons (Def :file rel :name name :kind "fn" :exported (listContains? exports name)) acc))))
                   (list) (r/rexFindAll (p/patDeadFn!) b n)))
        (schemas (map (fn [(caps (List Int64))] -> Def
                        (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
                          (Def :file rel :name name :kind "schema" :exported (listContains? exports name))))
                      (r/rexFindAll (p/patSchemaLine!) b n)))]
    (listAppend (listReverse fns) schemas))

fn prodFile? fpath: String -> Bool
  (not (or (stringContains? fpath "/tests/") (or (stringContains? fpath "/fixtures/") (or (stringContains? fpath "corpus/") (stringContains? fpath "/examples/")))))

fn deadIn! code: String defs: (List Def) -> (List Def)
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (priv (filter (fn [(d Def)] -> Bool (not d.exported)) defs))
        (tab (fold (fn [(tb tb/Strtab) (d Def)] -> tb/Strtab (if (allWord? d.name) (pairFirst (tb/internStr! tb d.name)) tb))
                   (tb/strtabNew (listLength priv)) priv))
        (counts (tb/ivNew (tb/strtabCount tab)))]
    (do (runCounts! b n tab counts 0)
        (filter (fn [(d Def)] -> Bool
                  (let [(id (tb/lookupStr tab d.name))]
                    (if (>= id 0) (<= (tb/ivGet counts id) 1)
                      (let [(w (stringToBytes d.name))] (<= (t/wordHits b n w (bytesLength w) 0 2 0) 1)))))
                priv)))

fn allWord? s: String -> Bool
  (let [(b (stringToBytes s))]
    (allWordLoop b (bytesLength b) 0))

fn allWordLoop b: Bytes n: Int64 i: Int64 -> Bool
  (cond
    ((>= i n) (> n 0))
    ((t/isWordByteAscii (bytesGet b i)) (allWordLoop b n (+ i 1)))
    (else false))

fn runCounts! b: Bytes n: Int64 tab: tb/Strtab counts: Bytes i: Int64 -> Unit
  (cond
    ((>= i n) ())
    ((t/wordAt? b n i)
      (let [(j (runStop b n i))]
        (do (let [(id (tb/lookup tab b i j))] (if (>= id 0) (tb/ivAdd! counts id 1) ()))
            (runCounts! b n tab counts j))))
    (else (runCounts! b n tab counts (+ i (max 1 (t/utf8Len (bytesGet b i)))))))

fn runStop b: Bytes n: Int64 i: Int64 -> Int64
  (if (t/wordAt? b n i) (runStop b n (+ i (max 1 (t/utf8Len (bytesGet b i))))) i)

; (:m :ref DEADCODE-REACH :do "report exported-unused and test-only symbols using transitive production/test roots, including string dispatch entries")
fn reachNextDecl! -> r/Rx
  (r/rxSeq (list (p/lit "\n") (p/ws0!)
                 (r/rxAlt (list (p/lit "fn") (p/lit "defn") (p/lit "schema") (p/lit "macro")
                                (p/lit "(module") (p/lit "(schema") (p/lit "(macro") (r/rxEos)))))

fn reachFnPat! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (r/rxAlt (list (r/rxBos) (p/lit "\n"))) (p/ws0!)
                   (r/rxAlt (list (p/lit "fn") (p/lit "defn"))) (p/ws1!)
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (p/lit "!")) (p/ws0!) (p/idRun! "a-zA-Z0-9_?!.-"))))
                   (r/rxRep (r/clsNot! "\n") 0 true) (p/ws0!) (p/lit "->") (p/ws0!)
                   (r/rxRep (r/clsNot! "\n") 1 true) (p/ws0!) (p/lit "\n")
                   (r/rxGroup 2 (r/rxRep (r/clsAny) 0 false))
                   (r/rxLook (reachNextDecl!))))
    2 (r/preNewline) 0 (list "fn" "defn") false)

fn reachRefPat! -> r/Rex
  (r/rexCompile! (r/rxGroup 1 (p/idRun! "a-zA-Z0-9_?!./-")) 1 (r/preAny) 0)

fn reachRefNames! text: String -> (List String)
  (let [(b (stringToBytes text))]
    (map (fn [(caps (List Int64))] -> String
           (t/pyStrip (optionOr (r/rexGroup text caps 1) "")))
         (r/rexFindAll (reachRefPat!) b (bytesLength b))))

fn reachFns! code: String rel: String -> (List ReachFn)
  (let [(b (stringToBytes code))
        (exports (match (c/firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))]
    (map (fn [(caps (List Int64))] -> ReachFn
           (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
             (ReachFn :file rel :name name :exported (listContains? exports name)
                      :body (optionOr (r/rexGroup code caps 2) ""))))
         (r/rexFindAll (reachFnPat!) b (bytesLength b))))

fn reachDefs! code: String rel: String fns: (List ReachFn) -> (List Def)
  (let [(b (stringToBytes code)) (n (bytesLength b))
        (exports (match (c/firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))
        (fd (map (fn [(f ReachFn)] -> Def (Def :file rel :name f.name :kind "fn" :exported f.exported)) fns))
        (sd (map (fn [(caps (List Int64))] -> Def
                   (let [(name (t/pyStrip (optionOr (r/rexGroup code caps 1) "")))]
                     (Def :file rel :name name :kind "schema" :exported (listContains? exports name))))
                 (r/rexFindAll (p/patSchemaLine!) b n)))]
    (listAppend fd sd))

fn reachRootNames! code: String -> (List String)
  (fold (fn [(acc (List String)) (line String)] -> (List String)
          (if (or (stringContains? line "\"")
                  (or (stringContains? line "(:tools") (stringContains? line ":op ")))
            (listAppend (reachRefNames! line) acc)
            acc))
        (list) (stringSplit code "\n"))

fn reachProdFile? file: String -> Bool
  (prodFile? (str "/" file))

fn reachBaseName name: String -> String
  (let [(parts (stringSplit name "/"))]
    (optionOr (listGet parts (- (listLength parts) 1)) name))

fn reachId tab: tb/Strtab name: String -> Int64
  (let [(base (tb/lookupStr tab (reachBaseName name)))]
    (if (>= base 0) base (tb/lookupStr tab name)))

fn reachRefIds! text: String tab: tb/Strtab -> (List Int64)
  (fold (fn [(acc (List Int64)) (name String)] -> (List Int64)
          (let [(id (reachId tab name))]
            (if (and (>= id 0) (not (listContains? acc id))) (cons id acc) acc)))
        (list) (reachRefNames! text))

fn reachTab! defs: (List Def) -> tb/Strtab
  (fold (fn [(tab tb/Strtab) (d Def)] -> tb/Strtab
          (pairFirst (tb/internStr! tab d.name)))
        (tb/strtabNew (listLength defs)) defs)

fn reachEdges! fns: (List ReachFn) tab: tb/Strtab -> (List ReachEdge)
  (fold (fn [(acc (List ReachEdge)) (f ReachFn)] -> (List ReachEdge)
          (let [(from (reachId tab f.name))]
            (if (< from 0) acc
              (fold (fn [(es (List ReachEdge)) (to Int64)] -> (List ReachEdge)
                      (cons (ReachEdge :from from :to to) es))
                    acc (reachRefIds! f.body tab)))))
        (list) fns)

fn reachAdj! edges: (List ReachEdge) -> (Map Int64 (List Int64))
  (fold (fn [(adj (Map Int64 (List Int64))) (e ReachEdge)] -> (Map Int64 (List Int64))
          (mapSet adj e.from (cons e.to (optionOr (mapGet adj e.from) (list)))))
        (mapEmpty) edges)

fn reachEntryName? name: String -> Bool
  (listContains? (list "main" "RunTests" "runTests") name)

fn reachRoots! fns: (List ReachFn) names: (List String) tab: tb/Strtab prod: Bool -> (List Int64)
  (let [(named (fold (fn [(acc (List Int64)) (name String)] -> (List Int64)
                       (let [(id (reachId tab name))]
                         (if (and prod (and (>= id 0) (not (listContains? acc id)))) (cons id acc) acc)))
                     (list) names))]
    (fold (fn [(acc (List Int64)) (f ReachFn)] -> (List Int64)
            (let [(isProd (reachProdFile? f.file))
                  (entry (if prod
                           (and isProd (= f.name "main"))
                           (and (not isProd)
                                (or (reachEntryName? f.name) (stringStartsWith? f.name "test")))))
                  (id (reachId tab f.name))]
              (if (and entry (and (>= id 0) (not (listContains? acc id)))) (cons id acc) acc)))
          named fns))

fn reachWalk! adj: (Map Int64 (List Int64)) todo: (List Int64) seen: Bytes -> Unit
  (match (listHead todo)
    ((none) ())
    ((some id)
      (let [(rest (optionOr (listTail todo) (list)))]
        (if (> (tb/ivGet seen id) 0)
          (reachWalk! adj rest seen)
          (do (tb/ivAdd! seen id 1)
              (reachWalk! adj (listAppend rest (optionOr (mapGet adj id) (list))) seen))))))

fn reachFindings! defs: (List Def) tab: tb/Strtab prodSeen: Bytes testSeen: Bytes -> (List Def)
  (listReverse
    (fold (fn [(acc (List Def)) (d Def)] -> (List Def)
            (if (and d.exported (and (reachProdFile? d.file) (not (reachEntryName? d.name))))
              (let [(id (reachId tab d.name))]
                (if (< id 0) acc
                  (cond
                    ((> (tb/ivGet prodSeen id) 0) acc)
                    ((> (tb/ivGet testSeen id) 0) (cons (with d :kind "testOnly") acc))
                    (else (cons (with d :kind "exportedUnused") acc)))))
              acc))
          (list) defs))

fn analyzeDeadcode! ctx: h/Ctx root: String pkgFilter: String -> (Result DeadCodeSummary String)
  (match (walkIgnoring! ctx root)
    ((err e) (err e))
    ((ok files)
      (let [(st (fold (fn [(st ReachAccum) (f String)] -> ReachAccum
                        (match (h/readText! f)
                          ((err _) st)
                          ((ok code)
                            (let [(scanned (+ st.scanned 1)) (rel (t/relPath f root ctx.cwd))
                                  (fns (reachFns! code rel)) (defs (reachDefs! code rel fns))
                                  (base (with st :scanned scanned
                                          :defs (listAppend defs st.defs)
                                          :fns (listAppend fns st.fns)
                                          :roots (if (prodFile? f) (listAppend (reachRootNames! code) st.roots) st.roots)))]
                              (if (or (not (prodFile? f)) (and (not (stringEmpty? pkgFilter)) (not (stringContains? rel pkgFilter))))
                                base
                                (let [(oldDefs (fileDefs! code rel))]
                                  (with base :total (+ st.total (listLength oldDefs))
                                        :dead (listAppend (listReverse (deadIn! code oldDefs)) st.dead))))))))
                      (ReachAccum :scanned 0 :total 0 :dead (list) :defs (list) :fns (list) :roots (list)) files))
            (tab (reachTab! st.defs))
            (adj (reachAdj! (reachEdges! st.fns tab)))
            (prodSeen (tb/ivNew (tb/strtabCount tab)))
            (testSeen (tb/ivNew (tb/strtabCount tab)))]
        (do (reachWalk! adj (reachRoots! st.fns st.roots tab true) prodSeen)
            (reachWalk! adj (reachRoots! st.fns (list) tab false) testSeen)
            (ok (DeadCodeSummary :filesScanned st.scanned :totalDefs st.total :dead (listReverse st.dead)
                                 :reach (reachFindings! st.defs tab prodSeen testSeen)))))))

fn reachDefAsn d: Def -> String
  (str "(:file \"" d.file "\" :name \"" d.name "\" :kind \"" d.kind "\")")

fn formatDeadcodeAsn res: DeadCodeSummary -> String
  (t/joinWith (list "(:deadCodeAudit" "  :status :ok"
                    (str "  :filesScanned " (t/intStr res.filesScanned))
                    (str "  :totalDefinitions " (t/intStr res.totalDefs))
                    (str "  :deadPrivateCount " (t/intStr (listLength res.dead)))
                    (if (listEmpty? res.dead) "  :sampleDeadSymbols []"
                      (str "  :sampleDeadSymbols [\n    "
                           (t/joinWith (map (fn [(d Def)] -> String (reachDefAsn d)) (t/takeN res.dead 25)) "\n    ")
                           "\n  ]"))
                    (str "  :reachabilityCount " (t/intStr (listLength res.reach)))
                    (if (listEmpty? res.reach) "  :reachability []"
                      (str "  :reachability [\n    "
                           (t/joinWith (map (fn [(d Def)] -> String (reachDefAsn d)) res.reach) "\n    ")
                           "\n  ]"))
                    ")")
              "\n")

fn reachKindCount res: DeadCodeSummary kind: String -> Int64
  (listLength (filter (fn [(d Def)] -> Bool (= d.kind kind)) res.reach))

fn formatDeadcodeSummary res: DeadCodeSummary -> String
  (t/joinWith (listAppend
                (list "=== ASL DEAD CODE & UNREFERENCED SYMBOLS AUDIT ==="
                      (str "Files Scanned:       " (t/intStr res.filesScanned))
                      (str "Source Definitions:  " (t/intStr res.totalDefs))
                      (str "Dead Private Funcs:  " (t/intStr (listLength res.dead)))
                      (str "Exported Unused:     " (t/intStr (reachKindCount res "exportedUnused")))
                      (str "Test Only:           " (t/intStr (reachKindCount res "testOnly"))))
                (if (listEmpty? res.dead) (list)
                  (cons "" (cons "--- Detected Unreferenced Private Symbols (Sample) ---"
                    (map (fn [(d Def)] -> String (str "  • " d.file ": " d.kind " " d.name)) (t/takeN res.dead 25))))))
              "\n")

fn deadcodeJson res: DeadCodeSummary -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok"))
                (pair "filesScanned" (j/jInt res.filesScanned))
                (pair "totalDefinitions" (j/jInt res.totalDefs))
                (pair "deadPrivateCount" (j/jInt (listLength res.dead)))
                (pair "deadPrivateSymbols" (j/jArr (map (fn [(d Def)] -> j/Json (j/jObj (list (pair "file" (j/jStr d.file)) (pair "name" (j/jStr d.name)) (pair "kind" (j/jStr d.kind))))) res.dead)))
                (pair "reachabilityCount" (j/jInt (listLength res.reach)))
                (pair "reachability" (j/jArr (map (fn [(d Def)] -> j/Json (j/jObj (list (pair "file" (j/jStr d.file)) (pair "name" (j/jStr d.name)) (pair "kind" (j/jStr d.kind))))) res.reach)))))

fn runDeadcode! ctx: h/Ctx fmt: String pkgFilter: String -> h/Outcome
  (match (analyzeDeadcode! ctx ctx.home pkgFilter)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res)
      (h/outcome (str (cond ((= fmt "json") (j/dumps (deadcodeJson res))) ((= fmt "summary") (formatDeadcodeSummary res)) (else (formatDeadcodeAsn res))) "\n") "" 0)))
