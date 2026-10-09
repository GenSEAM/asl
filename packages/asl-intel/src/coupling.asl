(module asl-intel/coupling
  :x [ModInfo PkgInfo Scan CouplingResult scanCodebase! analyzeCoupling formatCouplingAsn formatCouplingSummary couplingJson runCoupling! firstGroup allGroups ghostCount cycleCount]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/tab :a tb)
      (asl-intel/host :a h)])

(schema ModInfo
  (:f file String)
  (:f rel String)
  (:f id String)
  (:f exports (List String))
  (:f imports (List String))
  (:f totalDefs Int64))

(schema PkgInfo
  (:f dir String)
  (:f name String)
  (:f entry String)
  (:f deps (List String))
  (:f declMods (List String))
  (:f mods (List ModInfo)))

(schema Scan
  (:f pkgs (List PkgInfo)))

(schema IntraStat
  (:f name String)
  (:f dir String)
  (:f count Int64)
  (:f edges Int64)
  (:f cohesion Float))

(schema InterStat
  (:f name String)
  (:f dir String)
  (:f fanIn Int64)
  (:f fanOut Int64)
  (:f instability Float)
  (:f role String)
  (:f deps (List String)))

(schema Undeclared
  (:f from String)
  (:f file String)
  (:f imported String))

(schema CouplingResult
  (:f packagesTotal Int64)
  (:f modulesTotal Int64)
  (:f avgCohesion Float)
  (:f intra (List IntraStat))
  (:f cycles (List (List String)))
  (:f inter (List InterStat))
  (:f ghosts (List (Pair String String)))
  (:f vacuous (List (Pair String String)))
  (:f undeclared (List Undeclared)))

fn firstGroup rex: r/Rex s: String -> (Option String)
  (let [(b (stringToBytes s))]
    (mt (r/rexSearch rex b (bytesLength b) 0)
      ((none) (none))
      ((some caps) (r/rexGroup s caps 1))))

fn allGroups rex: r/Rex s: String -> (List String)
  (let [(b (stringToBytes s))]
    (map (fn [(caps (List Int64))] -> String (optionOr (r/rexGroup s caps 1) ""))
         (r/rexFindAll rex b (bytesLength b))))

fn declaredList! block: (Option String) key: String wordRex: r/Rex -> (List String)
  (mt block
    ((none) (list))
    ((some g)
      (let [(quoted (allGroups (p/patQuoted!) g))]
        (if (not (listEmpty? quoted)) quoted
          (filter (fn [(w String)] -> Bool (!= w key)) (allGroups wordRex g))))))

fn scanModule! sf: String pkgRoot: String cwd: String -> (Result (Option ModInfo) String)
  (let [(relPkg (t/relPath sf pkgRoot cwd))
        (rel (if (stringStartsWith? relPkg "src/") (t/sliceStr relPkg 4 (stringLength relPkg)) relPkg))]
    (mt (h/readText! sf)
      ((err e) (err (str "cannot read " sf ": " e)))
      ((ok code)
        (let [(b (stringToBytes code)) (n (bytesLength b))
              (modId (firstGroup (p/patModuleId!) code))]
          (if (and (none? modId) (or (stringEndsWith? sf "package.asl") (stringEndsWith? sf "target.asl")))
            (ok (none))
            (let [(exports (mt (firstGroup (p/patExports!) code) ((some g) (t/pySplit g)) ((none) (list))))
                  (imports (mt (firstGroup (p/patImportsBlock!) code) ((some g) (allGroups (p/patImportName!) g)) ((none) (list))))
                  (defs (+ (+ (r/rexCount (p/patFnParen!) b n) (r/rexCount (p/patFnNewline!) b n))
                           (+ (r/rexCount (p/patSchemaParen!) b n) (r/rexCount (p/patMacroParen!) b n))))]
              (ok (some (ModInfo :file sf :rel rel :id (optionOr modId rel) :exports exports :imports imports :totalDefs defs)))))))))

fn skippedPart? relPkg: String -> Bool
  (listAny? (fn [(part String)] -> Bool (listContains? (list "tests" "fixtures" "dist" "target" "build" "node_modules") part))
            (stringSplit relPkg "/"))

fn dedupeByRel mods: (List ModInfo) -> (List ModInfo)
  (let [(order (listReverse (fold (fn [(acc (List String)) (m ModInfo)] -> (List String)
                                    (if (listContains? acc m.rel) acc (cons m.rel acc)))
                                  (list) mods)))]
    (fold (fn [(acc (List ModInfo)) (rel String)] -> (List ModInfo)
            (mt (listHead (filter (fn [(x ModInfo)] -> Bool (= x.rel rel)) (listReverse mods)))
              ((some m) (listAppend acc (list m)))
              ((none) acc)))
          (list) order))

fn scanPackage! ctx: h/Ctx root: String tree: h/Tree d: String -> (Result PkgInfo String)
  (let [(pkgRoot (t/joinPath root d))]
    (mt (h/readText! (t/joinPath pkgRoot "manifest.asn"))
      ((err e) (err (str "cannot read manifest of " d ": " e)))
      ((ok c)
        (let [(name (optionOr (firstGroup (p/patPackage!) c) d))
              (entry (optionOr (firstGroup (p/patEntry!) c) "src/main.asl"))
              (deps (declaredList! (firstGroup (p/patDepsBlock!) c) "dependencies" (p/patWordRunDeps!)))
              (declMods (declaredList! (firstGroup (p/patModsBlock!) c) "modules" (p/patWordRunMods!)))
              (srcFiles (filter (fn [(sf String)] -> Bool (not (skippedPart? (t/relPath sf pkgRoot ctx.cwd))))
                                (h/globFiles! tree (t/normPath pkgRoot))))
              (scanned (fold (fn [(acc (Result (List ModInfo) String)) (sf String)] -> (Result (List ModInfo) String)
                               (mt acc
                                 ((err e) (err e))
                                 ((ok ms)
                                   (mt (scanModule! sf pkgRoot ctx.cwd)
                                     ((err e) (err e))
                                     ((ok om) (mt om ((some m) (ok (cons m ms))) ((none) (ok ms))))))))
                             (ok (list)) srcFiles))]
          (mt scanned
            ((err e) (err e))
            ((ok ms) (ok (PkgInfo :dir d :name name :entry entry :deps deps :declMods declMods :mods (dedupeByRel (listReverse ms))))))))))

fn scanCodebase! ctx: h/Ctx -> (Result (Option Scan) String)
  (let [(root0 (t/normPath (t/joinPath ctx.home "asl/packages")))
        (root (if (h/isDir? root0) root0 (t/joinPath (t/joinPath ctx.cwd "asl") "packages")))]
    (if (not (h/isDir? root)) (ok (none))
      (let [(realRoot (mt (realPath root) ((ok x) x) ((err _) root)))
            (dirs (filter (fn [(d String)] -> Bool
                            (and (h/isDir? (t/joinPath root d))
                                 (and (not (h/isLink? realRoot d)) (h/isFile? (t/joinPath (t/joinPath root d) "manifest.asn")))))
                          (h/listSorted! root)))]
        (mt (h/findTree! ctx (t/normPath root) false (list "*.asl"))
          ((err e) (err e))
          ((ok tree)
            (mt (fold (fn [(acc (Result (List PkgInfo) String)) (d String)] -> (Result (List PkgInfo) String)
                        (mt acc
                          ((err e) (err e))
                          ((ok ps) (mt (scanPackage! ctx root tree d) ((err e) (err e)) ((ok pk) (ok (cons pk ps)))))))
                      (ok (list)) dirs)
              ((err e) (err e))
              ((ok ps) (ok (some (Scan :pkgs (listReverse ps)))))))))))

fn kebabToCamel s: String -> String
  (let [(parts (stringSplit s "-"))]
    (str (optionOr (listHead parts) "")
         (t/concatAll (map (fn [(w String)] -> String
                             (str (t/upperAscii (t/sliceStr w 0 1)) (t/lowerAscii (t/sliceStr w 1 (stringLength w)))))
                           (optionOr (listTail parts) (list))))))

fn stem k: String -> String
  (stringReplace (t/baseName k) ".asl" "")

fn intraEdges mods: (List ModInfo) -> Int64
  (let [(targets (fold (fn [(acc (List String)) (m ModInfo)] -> (List String)
                         (cons (stem m.rel) (cons (t/splitExtRoot m.rel) (cons m.id acc))))
                       (list) mods))]
    (fold (fn [(acc Int64) (m ModInfo)] -> Int64
            (+ acc (listLength (filter (fn [(imp String)] -> Bool
                                         (or (listContains? targets imp) (listContains? targets (t/baseName imp))))
                                       m.imports))))
          0 mods))

fn cohesionOf count: Int64 edges: Int64 -> Float
  (if (<= count 1) 1.0
    (let [(maxPossible (* count (- count 1)))]
      (if (> maxPossible 0)
        (min 1.0 (t/pyRound (/ (int64ToFloat64 edges) (int64ToFloat64 maxPossible)) 3))
        1.0)))

fn afterSlash dm: String -> String
  (mt (stringIndexOf dm "/")
    ((some i) (t/sliceStr dm (+ i 1) (stringLength dm)))
    ((none) dm))

fn ghostsOf pk: PkgInfo -> (List (Pair String String))
  (let [(keys (map (fn [(m ModInfo)] -> String m.rel) pk.mods))
        (stems (map stem keys))
        (ids (map (fn [(m ModInfo)] -> String m.id) pk.mods))
        (entryBase (t/splitExtRoot (t/baseName pk.entry)))]
    (map (fn [(dm String)] -> (Pair String String) (pair pk.name dm))
      (filter (fn [(dm String)] -> Bool
                (let [(sub (afterSlash dm))
                      (cSub (kebabToCamel sub))
                      (isEntry (or (= dm pk.name) (or (= dm pk.dir) (or (= sub entryBase) (or (= cSub entryBase) (listContains? (list "main" "core" "index") sub))))))
                      (inFiles (or (listContains? keys (str sub ".asl"))
                               (or (listContains? keys (str cSub ".asl"))
                               (or (listContains? stems sub)
                               (or (listContains? stems cSub)
                               (or (listContains? ids dm)
                                   (listAny? (fn [(k String)] -> Bool (or (stringEndsWith? k (str "/" sub ".asl")) (stringEndsWith? k (str "/" cSub ".asl")))) keys)))))))]
                  (not (or isEntry inFiles))))
              pk.declMods)))

fn toDir pkgs: (List PkgInfo) name: String -> String
  (mt (listHead (filter (fn [(pk PkgInfo)] -> Bool (= pk.name name)) (listReverse pkgs)))
    ((some pk) pk.dir)
    ((none) name))

fn toName pkgs: (List PkgInfo) dir: String -> String
  (mt (listHead (filter (fn [(pk PkgInfo)] -> Bool (= pk.dir dir)) pkgs))
    ((some pk) pk.name)
    ((none) dir))

fn squash s: String -> String
  (t/lowerAscii (stringReplace s "-" ""))

fn selfImport? pk: PkgInfo tps: String td: String -> Bool
  (or (= tps pk.dir) (or (= tps pk.name) (or (= td pk.dir) (or (= td pk.name)
  (or (= (squash tps) (squash pk.dir)) (or (= (squash tps) (squash pk.name))
  (or (= (squash td) (squash pk.dir)) (= (squash td) (squash pk.name)))))))))

fn depsOf pkgs: (List PkgInfo) dirs: (List String) pk: PkgInfo -> (Pair (List String) (List Undeclared))
  (let [(declared (fold (fn [(acc (List String)) (d String)] -> (List String)
                          (let [(td (toDir pkgs d))]
                            (if (and (listContains? dirs td) (and (!= td pk.dir) (not (listContains? acc td)))) (cons td acc) acc)))
                        (list) pk.deps))]
    (fold (fn [(acc (Pair (List String) (List Undeclared))) (m ModInfo)] -> (Pair (List String) (List Undeclared))
            (fold (fn [(acc2 (Pair (List String) (List Undeclared))) (imp String)] -> (Pair (List String) (List Undeclared))
                    (if (or (not (stringContains? imp "/")) (stringStartsWith? imp ".")) acc2
                      (let [(tps (optionOr (listHead (stringSplit imp "/")) imp))
                            (td (toDir pkgs tps))]
                        (if (or (selfImport? pk tps td) (not (and (listContains? dirs td) (!= td pk.dir)))) acc2
                          (pair (if (listContains? (pairFirst acc2) td) (pairFirst acc2) (cons td (pairFirst acc2)))
                                (if (or (listContains? pk.deps tps) (listContains? pk.deps td)) (pairSecond acc2)
                                  (cons (Undeclared :from pk.name :file m.rel :imported tps) (pairSecond acc2))))))))
                  acc m.imports))
          (pair declared (list)) pk.mods))

fn succOf graph: (List (Pair String (List String))) node: String -> (List String)
  (mt (listHead (filter (fn [(e (Pair String (List String)))] -> Bool (= (pairFirst e) node)) graph))
    ((some e) (pairSecond e))
    ((none) (list)))

fn colourOf seen: (List (Pair String Int64)) node: String -> Int64
  (mt (listHead (filter (fn [(e (Pair String Int64))] -> Bool (= (pairFirst e) node)) seen))
    ((some e) (pairSecond e))
    ((none) 0))

fn fromNode path: (List String) node: String -> (List String)
  (mt (listHead path)
    ((none) (list))
    ((some x) (if (= x node) path (fromNode (optionOr (listTail path) (list)) node))))

fn dfs graph: (List (Pair String (List String))) pkgs: (List PkgInfo) node: String path: (List String) st: (Pair (List (Pair String Int64)) (List (List String))) -> (Pair (List (Pair String Int64)) (List (List String)))
  (let [(st1 (pair (cons (pair node 1) (pairFirst st)) (pairSecond st)))
        (st2 (fold (fn [(acc (Pair (List (Pair String Int64)) (List (List String)))) (nxt String)] -> (Pair (List (Pair String Int64)) (List (List String)))
                     (let [(c (colourOf (pairFirst acc) nxt))]
                       (cond
                         ((= c 1) (pair (pairFirst acc) (cons (map (fn [(x String)] -> String (toName pkgs x)) (listAppend (fromNode path nxt) (list nxt))) (pairSecond acc))))
                         ((= c 0) (dfs graph pkgs nxt (listAppend path (list nxt)) acc))
                         (else acc))))
                   st1 (listSort (succOf graph node))))]
    (pair (cons (pair node 2) (pairFirst st2)) (pairSecond st2)))

fn interStat pkgs: (List PkgInfo) graph: (List (Pair String (List String))) pk: PkgInfo -> InterStat
  (let [(ce (listLength (succOf graph pk.dir)))
        (ca (listLength (filter (fn [(e (Pair String (List String)))] -> Bool (listContains? (pairSecond e) pk.dir)) graph)))
        (inst (if (> (+ ca ce) 0) (t/pyRound (/ (int64ToFloat64 ce) (int64ToFloat64 (+ ca ce))) 3) 0.0))]
    (InterStat :name pk.name :dir pk.dir :fanIn ca :fanOut ce :instability inst
               :role (if (<= inst 0.25) "foundation" (if (>= inst 0.75) "orchestrator" "bridge"))
               :deps (listSort (map (fn [(x String)] -> String (toName pkgs x)) (succOf graph pk.dir)))))

fn analyzeCoupling scan: Scan -> CouplingResult
  (let [(pkgs scan.pkgs)
        (dirs (map (fn [(pk PkgInfo)] -> String pk.dir) pkgs))
        (intra0 (map (fn [(pk PkgInfo)] -> IntraStat
                       (let [(cnt (listLength pk.mods)) (edges (if (<= cnt 1) 0 (intraEdges pk.mods)))]
                         (IntraStat :name pk.name :dir pk.dir :count cnt :edges edges :cohesion (cohesionOf cnt edges))))
                     pkgs))
        (total (fold (fn [(acc Float) (s IntraStat)] -> Float (+ acc s.cohesion)) 0.0 intra0))
        (avg (t/pyRound (/ total (int64ToFloat64 (max 1 (listLength pkgs)))) 3))
        (vacuous (fold (fn [(acc (List (Pair String String))) (pk PkgInfo)] -> (List (Pair String String))
                         (listAppend acc (map (fn [(m ModInfo)] -> (Pair String String) (pair pk.name m.rel))
                                              (filter (fn [(m ModInfo)] -> Bool (and (= m.totalDefs 0) (listEmpty? m.exports))) pk.mods))))
                       (list) pkgs))
        (ghosts (fold (fn [(acc (List (Pair String String))) (pk PkgInfo)] -> (List (Pair String String)) (listAppend acc (ghostsOf pk))) (list) pkgs))
        (depInfo (map (fn [(pk PkgInfo)] -> (Pair String (Pair (List String) (List Undeclared))) (pair pk.dir (depsOf pkgs dirs pk))) pkgs))
        (graph (map (fn [(e (Pair String (Pair (List String) (List Undeclared))))] -> (Pair String (List String)) (pair (pairFirst e) (pairFirst (pairSecond e)))) depInfo))
        (undeclared (fold (fn [(acc (List Undeclared)) (e (Pair String (Pair (List String) (List Undeclared))))] -> (List Undeclared)
                            (listAppend acc (listReverse (pairSecond (pairSecond e)))))
                          (list) depInfo))
        (inter0 (map (fn [(pk PkgInfo)] -> InterStat (interStat pkgs graph pk)) pkgs))
        (cyc (fold (fn [(st (Pair (List (Pair String Int64)) (List (List String)))) (d String)] -> (Pair (List (Pair String Int64)) (List (List String)))
                     (if (= (colourOf (pairFirst st) d) 0) (dfs graph pkgs d (list d) st) st))
                   (pair (list) (list)) dirs))]
    (CouplingResult
      :packagesTotal (listLength pkgs)
      :modulesTotal (fold (fn [(acc Int64) (pk PkgInfo)] -> Int64 (+ acc (listLength pk.mods))) 0 pkgs)
      :avgCohesion avg
      :intra (tb/sortWith (fn [(a IntraStat) (b IntraStat)] -> Bool (> a.cohesion b.cohesion)) intra0)
      :cycles (listReverse (pairSecond cyc))
      :inter (tb/sortWith (fn [(a InterStat) (b InterStat)] -> Bool
                            (or (> a.fanIn b.fanIn) (and (= a.fanIn b.fanIn) (< a.instability b.instability))))
                          inter0)
      :ghosts ghosts
      :vacuous vacuous
      :undeclared undeclared))

fn cycleCount res: CouplingResult -> Int64
  (listLength res.cycles)

fn ghostCount res: CouplingResult -> Int64
  (listLength res.ghosts)

fn formatCouplingAsn res: CouplingResult -> String
  (let [(topDense (map (fn [(s IntraStat)] -> String (str "(:pkg \"" s.name "\" :modules " (t/intStr s.count) " :cohesion " (t/floatStr s.cohesion) ")")) (t/takeN res.intra 5)))
        (topIn (map (fn [(s InterStat)] -> String (str "(:pkg \"" s.name "\" :fanIn " (t/intStr s.fanIn) " :fanOut " (t/intStr s.fanOut) " :instability " (t/floatStr s.instability) ")")) (t/takeN res.inter 5)))
        (nG (listLength res.ghosts)) (nV (listLength res.vacuous)) (nU (listLength res.undeclared))
        (sample (if (= nU 0) (list)
                  (list (str "    :sampleUndeclared [" (t/joinWith (map (fn [(u Undeclared)] -> String (str "(:from \"" u.from "\" :file \"" u.file "\" :imported \"" u.imported "\")")) (t/takeN res.undeclared 5)) " ") "]"))))]
    (t/joinWith (listAppend
                  (list "(:couplingAudit" "  :status :ok"
                        (str "  :packagesTotal " (t/intStr res.packagesTotal))
                        (str "  :modulesTotal " (t/intStr res.modulesTotal))
                        "  :intraPackage ("
                        (str "    :averageCohesion " (t/floatStr res.avgCohesion))
                        (str "    :topCohesive [" (t/joinWith topDense " ") "]")
                        "  )"
                        "  :interPackage ("
                        (str "    :cyclesCount " (t/intStr (listLength res.cycles)))
                        (str "    :topFoundations [" (t/joinWith topIn " ") "]")
                        "  )"
                        "  :moduleFictions ("
                        (str "    :totalFictions " (t/intStr (+ nG (+ nV nU))))
                        (str "    :ghostModulesCount " (t/intStr nG))
                        (str "    :vacuousModulesCount " (t/intStr nV))
                        (str "    :undeclaredImportsCount " (t/intStr nU)))
                  (listAppend sample (list "  )" (str "  :assertCount " (t/intStr res.packagesTotal) ")"))))
                "\n"))

fn statRow s: InterStat -> String
  (str (t/padRight s.name 24) " " (t/padRight (t/intStr s.fanIn) 12) " " (t/padRight (t/intStr s.fanOut) 12) " "
       (t/padRight (t/fmtFixed s.instability 3) 16) " " s.role)

fn statHeader -> String
  (str (t/padRight "Package" 24) " " (t/padRight "Fan-In (Ca)" 12) " " (t/padRight "Fan-Out (Ce)" 12) " " (t/padRight "Instability (I)" 16) " Role")

fn formatCouplingSummary res: CouplingResult -> String
  (let [(nG (listLength res.ghosts)) (nV (listLength res.vacuous)) (nU (listLength res.undeclared))
        (byFanOut (tb/sortWith (fn [(a InterStat) (b InterStat)] -> Bool (> a.fanOut b.fanOut)) res.inter))
        (head (list "=== ASL MONOREPO COUPLING & MODULE FICTION AUDIT ==="
                    (str "Packages Analyzed:  " (t/intStr res.packagesTotal))
                    (str "Source Modules:     " (t/intStr res.modulesTotal))
                    (str "Average Cohesion:   " (t/fmtFixed res.avgCohesion 3) " (Intra-Package Short-Range)")
                    (str "Dependency Cycles:  " (t/intStr (listLength res.cycles)) " (Acyclic DAG Invariant)")
                    (str "Module Fictions:    " (t/intStr (+ nG (+ nV nU))) " (" (t/intStr nU) " undeclared imports, " (t/intStr nG) " ghosts)")
                    ""
                    "--- Top 5 Architectural Foundations (Highest Fan-In, Low Instability) ---"
                    (statHeader) (stringRepeat "-" 75)))
        (t1 (map statRow (t/takeN res.inter 5)))
        (mid (list "" "--- Top 5 Orchestrator / Volatile Packages (Highest Fan-Out) ---" (statHeader) (stringRepeat "-" 75)))
        (t2 (map statRow (t/takeN byFanOut 5)))
        (tail (if (= nU 0) (list)
                (cons "" (cons "--- Sample Undeclared Cross-Package Imports ---"
                  (map (fn [(u Undeclared)] -> String (str "  • " u.from " [" u.file "] imports \"" u.imported "\" (not in manifest.asn)"))
                       (t/takeN res.undeclared 8))))))]
    (t/joinWith (listAppend head (listAppend t1 (listAppend mid (listAppend t2 tail)))) "\n"))

fn intraJson s: IntraStat -> j/Json
  (j/jObj (list (pair "package" (j/jStr s.name)) (pair "dir" (j/jStr s.dir))
                (pair "modulesCount" (j/jInt s.count)) (pair "intraEdges" (j/jInt s.edges))
                (pair "cohesion" (j/jFloat s.cohesion))))

fn interJson s: InterStat -> j/Json
  (j/jObj (list (pair "package" (j/jStr s.name)) (pair "dir" (j/jStr s.dir))
                (pair "fanIn" (j/jInt s.fanIn)) (pair "fanOut" (j/jInt s.fanOut))
                (pair "instability" (j/jFloat s.instability)) (pair "role" (j/jStr s.role))
                (pair "dependencies" (j/jStrs s.deps))))

fn couplingJson res: CouplingResult -> j/Json
  (j/jObj (list
    (pair "packagesTotal" (j/jInt res.packagesTotal))
    (pair "modulesTotal" (j/jInt res.modulesTotal))
    (pair "intraPackage" (j/jObj (list (pair "averageCohesion" (j/jFloat res.avgCohesion))
                                       (pair "packages" (j/jArr (map intraJson res.intra))))))
    (pair "interPackage" (j/jObj (list (pair "cyclesCount" (j/jInt (listLength res.cycles)))
                                       (pair "cycles" (j/jArr (map j/jStrs res.cycles)))
                                       (pair "packages" (j/jArr (map interJson res.inter))))))
    (pair "moduleFictions" (j/jObj (list
      (pair "ghostModules" (j/jArr (map (fn [(g (Pair String String))] -> j/Json (j/jObj (list (pair "package" (j/jStr (pairFirst g))) (pair "declaredModule" (j/jStr (pairSecond g)))))) res.ghosts)))
      (pair "vacuousModules" (j/jArr (map (fn [(g (Pair String String))] -> j/Json (j/jObj (list (pair "package" (j/jStr (pairFirst g))) (pair "file" (j/jStr (pairSecond g)))))) res.vacuous)))
      (pair "undeclaredImports" (j/jArr (map (fn [(u Undeclared)] -> j/Json (j/jObj (list (pair "fromPackage" (j/jStr u.from)) (pair "file" (j/jStr u.file)) (pair "importedPackage" (j/jStr u.imported))))) res.undeclared))))))))

fn runCoupling! ctx: h/Ctx fmt: String strict: Bool -> h/Outcome
  (mt (scanCodebase! ctx)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok os)
      (mt os
        ((none) (h/outcome "" "Error: Could not locate asl/packages directory.\n" 1))
        ((some scan)
          (let [(res (analyzeCoupling scan))
                (out (str (cond ((= fmt "json") (j/dumps (couplingJson res))) ((= fmt "summary") (formatCouplingSummary res)) (else (formatCouplingAsn res))) "\n"))
                (nCyc (listLength res.cycles)) (nG (listLength res.ghosts))]
            (cond
              ((and strict (> nCyc 0)) (h/outcome out (str "Error: " (t/intStr nCyc) " circular dependency cycles detected!\n") 1))
              ((and strict (> nG 0)) (h/outcome out (str "Error: " (t/intStr nG) " ghost modules detected!\n") 1))
              (else (h/outcome out "" 0))))))))
