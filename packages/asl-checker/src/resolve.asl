(module asl-checker/resolve :x [FunSummary SchemaSummary EnumSummary CaseSummary FieldSummary ModuleSummary emptyModuleSummary bodyPosAt placeDiags cleanNumSign collectSummary checkTypeTree dottedTypeTree listToSet firstCharStr firstExprEmpty firstExprUnit firstExprVect firstHeadIdent firstVectItems isLiteralAtom? listAppendOne loadModuleDeps! loadModuleClosure! parentDirOf resolveImport! emptyModIndex ModIndex Resolution ResStatus ModuleClosure mapValuesList modEnum modFun modImport matchFamily ctorPatternAtom? unreachableArmDiags modSchema resolveDepTarget resolveDepIn depCandidates depIndexOf depScanOf DepIndex resolveModule resolveModuleIn safeTail secondExprEmpty sexprToList sliceFrom withImports] :i [(types :a ty) (ast :a a) (reader :a rd)])

(schema FunSummary (:f name String) (:f params (List (pair String String))) (:f ret String) (:f typevars (List String)) (:f hasDoc Bool) (:f effect Bool))

(schema FieldSummary (:f name String) (:f type String) (:f hasDefault Bool))

(schema SchemaSummary (:f name String) (:f typevars (List String)) (:f fields (List FieldSummary)))

(schema CaseSummary (:f name String) (:f params (List (pair String String))))

(schema EnumSummary (:f name String) (:f typevars (List String)) (:f cases (List CaseSummary)))

(schema ModuleSummary (:f name String) (:f path String) (:f hasHeader Bool) (:f hasDoc Bool) (:f exports (List String)) (:f exportedTypes (List String)) (:f imports (Map String String)) (:f funs (Map String FunSummary)) (:f schemas (Map String SchemaSummary)) (:f enums (Map String EnumSummary)) (:f caseOwner (Map String String)) (:f exportedCases (Map String String)) (:f exportedFields (Map String Bool)))

fn emptyModuleSummary -> ModuleSummary
  (ModuleSummary :name "" :path "" :hasHeader false :hasDoc false :exports (list) :exportedTypes (list) :imports (mapEmpty) :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty))

fn firstCharStr s: String -> String
  (optionOr (stringSlice s 0 1) "")

fn sliceFrom s: String start: Int64 -> String
  (optionOr (stringSlice s start (stringLength s)) s)

fn isPascalName? s: String -> Bool
  (if (stringEmpty? s) false (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstCharStr s)))

fn isQualifiedName? s: String -> Bool
  (and (not (= s "/")) (and (not (stringStartsWith? s "/")) (stringContains? s "/")))

fn makeDiag code: String msg: String path: String -> ty/Diagnostic
  (ty/Diagnostic :code code :message msg :msg msg :line 1 :col 1 :path path)

fn collectFieldsStep fields: (List a/AstField) -> (List FieldSummary)
  (map (fn [(f a/AstField)] -> FieldSummary (FieldSummary :name f.name :type f.type :hasDefault (some? f.default))) fields)

fn collectFields fields: (List a/AstField) -> (List FieldSummary)
  (collectFieldsStep fields)

fn collectParamsStep params: (List a/Param) -> (List (Pair String String))
  (map (fn [(p a/Param)] -> (Pair String String) (pair p.name p.type)) params)

fn collectCaseParams params: (List a/Param) -> (List (Pair String String))
  (collectParamsStep params)

fn collectCasesStep cases: (List a/EnumCase) -> (List CaseSummary)
  (map (fn [(c a/EnumCase)] -> CaseSummary (CaseSummary :name c.name :params (collectCaseParams c.fields))) cases)

fn collectCases cases: (List a/EnumCase) -> (List CaseSummary)
  (collectCasesStep cases)

fn collectFunParams params: (List a/Param) -> (List (Pair String String))
  (collectParamsStep params)

fn collectSummary forms: (List a/TopForm) path: String -> ModuleSummary
  (let [(modHeader (fold (fn [(acc (Option a/ModuleNode)) (form a/TopForm)] -> (Option a/ModuleNode) (mt form ((a/topModule m) (some m)) (_ acc))) (none) forms)) (hasHdr (mt modHeader ((some _) true) ((none) false))) (hdrDoc (mt modHeader ((some m) (not (stringEmpty? m.docstring))) ((none) false))) (modName (mt modHeader ((some m) (let [(p m.path)] (if (stringEmpty? p) path p))) ((none) path))) (rawExports (mt modHeader ((some m) m.exported) ((none) (list)))) (exports (filter (fn [(e String)] -> Bool (not (isPascalName? e))) rawExports)) (exportedTypes (filter (fn [(e String)] -> Bool (isPascalName? e)) rawExports)) (importsList (mt modHeader ((some m) m.imports) ((none) (list)))) (importsMap (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String) (mapSet acc (pairSecond p) (pairFirst p))) (mapEmpty) importsList)) (funsMap (fold (fn [(acc (Map String FunSummary)) (form a/TopForm)] -> (Map String FunSummary) (mt form ((a/topDefun d) (let [(fparams (collectFunParams d.params)) (pTypes (map pairSecond fparams)) (tvars (if (listEmpty? d.typeVars) (ty/collectTvars pTypes d.retType) d.typeVars))] (mapSet acc d.name (FunSummary :name d.name :params fparams :ret d.retType :typevars tvars :hasDoc (not (stringEmpty? d.docstring)) :effect (markedFn? d))))) (_ acc))) (mapEmpty) forms)) (schemasMap (fold (fn [(acc (Map String SchemaSummary)) (form a/TopForm)] -> (Map String SchemaSummary) (mt form ((a/topSchema s) (mapSet acc s.name (SchemaSummary :name s.name :typevars s.typeVars :fields (collectFields s.fields)))) (_ acc))) (mapEmpty) forms)) (enumsMap (fold (fn [(acc (Map String EnumSummary)) (form a/TopForm)] -> (Map String EnumSummary) (mt form ((a/topEnum e) (mapSet acc e.name (EnumSummary :name e.name :typevars e.typeVars :cases (collectCases e.cases)))) (_ acc))) (mapEmpty) forms)) (caseOwnerMap (fold (fn [(acc (Map String String)) (form a/TopForm)] -> (Map String String) (mt form ((a/topEnum e) (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String) (mapSet cacc c.name e.name)) acc e.cases)) (_ acc))) (mapEmpty) forms)) (expCases (fold (fn [(acc (Map String String)) (tname String)] -> (Map String String) (mt (mapGet enumsMap tname) ((some esum) (fold (fn [(cacc (Map String String)) (c CaseSummary)] -> (Map String String) (mapSet cacc c.name tname)) acc esum.cases)) ((none) acc))) (mapEmpty) exportedTypes)) (expFields (fold (fn [(acc (Map String Bool)) (tname String)] -> (Map String Bool) (mt (mapGet schemasMap tname) ((some ssum) (addFieldsToSet acc ssum.fields)) ((none) acc))) (mapEmpty) exportedTypes))] (ModuleSummary :name modName :path path :hasHeader hasHdr :hasDoc hdrDoc :exports exports :exportedTypes exportedTypes :imports importsMap :funs funsMap :schemas schemasMap :enums enumsMap :caseOwner caseOwnerMap :exportedCases expCases :exportedFields expFields))

fn addFieldsToSet facc: (Map String Bool) fields: (List FieldSummary) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (f FieldSummary)] -> (Map String Bool) (mapSet acc f.name true)) facc fields)

fn safeTail l: (List T) -> (List T)
  (if (listEmpty? l) (list) (mt (listTail l) ((some r) r) ((none) (list))))

fn firstExprEmpty l: (List rd/SExpr) -> rd/SExpr
  (mt (listHead l) ((some h) h) ((none) (rd/makeAtom "")))

fn firstExprUnit l: (List rd/SExpr) -> rd/SExpr
  (mt (listHead l) ((some h) h) ((none) (rd/makeAtom "()")))

fn firstExprVect l: (List rd/SExpr) -> rd/SExpr
  (mt (listHead l) ((some b) b) ((none) (rd/makeVect (list))))

fn sexprToList e: rd/SExpr -> (List rd/SExpr)
  (rd/sexprToList e)

fn isListAtom? e: rd/SExpr -> Bool
  (mt e ((rd/sexprAtom v) (= v "list")) (_ false))

fn bindingItems e: rd/SExpr -> (List rd/SExpr)
  (let [(items (sexprToList e))] (mt e ((rd/sexprList _) (if (isListAtom? (firstExprEmpty items)) (safeTail items) items)) (_ items)))

fn firstVectItems l: (List rd/SExpr) -> (List rd/SExpr)
  (bindingItems (firstExprVect l))

fn secondExprEmpty l: (List rd/SExpr) -> rd/SExpr
  (mt (listGet l 1) ((some v) v) ((none) (rd/makeAtom "")))

fn listAppendOne xs: (List T) x: T -> (List T)
  (listAppend xs (list x))

fn modSchema m: ModuleSummary name: String -> (Option SchemaSummary)
  (mapGet m.schemas name)

fn modEnum m: ModuleSummary name: String -> (Option EnumSummary)
  (mapGet m.enums name)

fn modImport m: ModuleSummary alias: String -> (Option String)
  (mapGet m.imports alias)

fn modFun m: ModuleSummary name: String -> (Option FunSummary)
  (mapGet m.funs name)

(enum ResStatus (:c resOk [] "Exactly one candidate module") (:c resDeprecated [] "A leading ../ path resolved against the importer's directory") (:c resAmbiguous [] "Several candidate modules") (:c resMissing [] "No candidate module"))

(schema IdxMod (:f name String) (:f path String))

(schema IdxPkg (:f name String) (:f base String) (:f dir String) (:f deps (List String)))

(schema ModIndex (:f root String) (:f mods (List IdxMod)) (:f pkgs (List IdxPkg)) (:f skipped Int64) (:f skippedAt String) (:f workspaces (Map String String)))

(schema Cand (:f path String) (:f name String))

(schema Resolution (:f status ResStatus) (:f path String) (:f note String) (:f index ModIndex))

(schema AsnItem (:f kind String) (:f text String) (:f kids (List AsnItem)))

(schema LoadCtx (:f nearest String) (:f outer String) (:f pkg String))

(schema ModuleClosure (:f deps (Map String ModuleSummary)) (:f paths (List String)) (:f unresolved (List String)) (:f errors (List String)) (:f index ModIndex))

(schema ModHeader (:f name String) (:f hasDoc Bool) (:f exports (List String)) (:f imports (List (Pair String String))))

(schema ImportPass (:f imports (Map String String)) (:f targets (List String)) (:f unresolved (List String)) (:f index ModIndex))

fn emptyModIndex -> ModIndex
  (ModIndex :root "" :mods (list) :pkgs (list) :skipped 0 :skippedAt "" :workspaces (mapEmpty))

fn byteAt s: String i: Int64 -> String
  (if (< i 0) "" (optionOr (stringSlice s i (+ i 1)) ""))

fn isSpaceByte? c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? " \t\n\r" c))

fn isNameStop? c: String -> Bool
  (or (stringEmpty? c) (stringContains? " \t\r\n()[]{}\";" c))

fn lastSlashAt s: String i: Int64 -> Int64
  (if (< i 0) -1 (if (= (byteAt s i) "/") i (lastSlashAt s (- i 1))))

fn parentDirOf p: String -> String
  (let [(k (lastSlashAt p (- (stringLength p) 1)))]
    (cond ((= k 0) "/") ((> k 0) (optionOr (stringSlice p 0 k) p)) (else ".")))

fn lastSegOf s: String -> String
  (let [(k (lastSlashAt s (- (stringLength s) 1)))] (if (< k 0) s (sliceFrom s (+ k 1))))

fn isUnder? path: String dir: String -> Bool
  (stringStartsWith? path (str dir "/"))

fn ! realPath! p: String -> (Option String)
  (mt (realPath p) ((ok r) (some r)) ((err _) (none)))

fn ! withinRoot! cand: String root: String -> (Option String)
  (mt (realPath! cand)
    ((none) (none))
    ((some real) (mt (realPath! root)
      ((none) (none))
      ((some rr) (if (or (isUnder? real rr) (= rr "/")) (some real) (none))))))

fn skipSpaces s: String i: Int64 -> Int64
  (if (isSpaceByte? (byteAt s i)) (skipSpaces s (+ i 1)) i)

fn skipLine s: String i: Int64 -> Int64
  (let [(c (byteAt s i))] (if (or (stringEmpty? c) (= c "\n")) i (skipLine s (+ i 1))))

fn skipLeading s: String i: Int64 -> Int64
  (let [(j (skipSpaces s i))] (if (= (byteAt s j) ";") (skipLeading s (skipLine s j)) j))

fn nameEnd s: String i: Int64 -> Int64
  (if (isNameStop? (byteAt s i)) i (nameEnd s (+ i 1)))

fn headerNameIn s: String -> (Option String)
  (let [(j (skipLeading s 0)) (k (skipSpaces s (+ j 1))) (m (skipSpaces s (+ k 6))) (e (nameEnd s m))]
    (if (and (= (byteAt s j) "(") (and (= (optionOr (stringSlice s k (+ k 6)) "") "module") (isSpaceByte? (byteAt s (+ k 6)))))
      (if (or (= e m) (or (>= (- e m) 512) (>= e (stringLength s)))) (none) (stringSlice s m e))
      (none)))

fn ! headerName! path: String -> (Option String)
  (mt (fileReadString path)
    ((err _) (none))
    ((ok src) (headerNameIn (optionOr (stringSlice src 0 (min (stringLength src) 4095)) src))))

fn strScan s: String i: Int64 start: Int64 pieces: (List String) -> (Pair (List String) Int64)
  (let [(c (byteAt s i)) (piece (optionOr (stringSlice s start i) ""))]
    (cond
      ((stringEmpty? c) (pair pieces -1))
      ((= c "\"") (pair (cons piece pieces) (+ i 1)))
      ((= c "\\") (let [(e (byteAt s (+ i 1))) (dec (cond ((= e "n") "\n") ((= e "t") "\t") (else e)))] (strScan s (+ i 2) (+ i 2) (cons dec (cons piece pieces)))))
      (else (strScan s (+ i 1) start pieces))))

fn atomEnd s: String i: Int64 -> Int64
  (let [(c (byteAt s i))] (if (or (isNameStop? c) (= c ",")) i (atomEnd s (+ i 1))))

fn atomKind t: String -> String
  (let [(c (byteAt t 0)) (d (if (= c "-") (byteAt t 1) c))]
    (cond ((= c ":") "kw") ((and (not (stringEmpty? d)) (stringContains? "0123456789" d)) "num") (else "sym")))

fn closerOf open: String -> String
  (cond ((= open "(") ")") ((= open "[") "]") (else "}"))

fn compoundKind open: String -> String
  (cond ((= open "(") "list") ((= open "[") "vect") (else "map"))

fn parseItem s: String i: Int64 -> (Option (Pair AsnItem Int64))
  (let [(j (skipLeading s i)) (c (byteAt s j))]
    (cond
      ((or (stringEmpty? c) (stringContains? ")]}" c)) (none))
      ((stringContains? "([{" c) (mt (parseSeq s (+ j 1) (closerOf c) (list))
        ((none) (none))
        ((some r) (some (pair (AsnItem :kind (compoundKind c) :text "" :kids (pairFirst r)) (pairSecond r))))))
      ((= c "\"") (let [(r (strScan s (+ j 1) (+ j 1) (list)))] (if (< (pairSecond r) 0) (none) (some (pair (AsnItem :kind "str" :text (stringJoin (listReverse (pairFirst r)) "") :kids (list)) (pairSecond r))))))
      (else (let [(e (atomEnd s j)) (t (optionOr (stringSlice s j e) "")) (kind (atomKind t))]
        (some (pair (AsnItem :kind kind :text (if (= kind "kw") (sliceFrom t 1) t) :kids (list)) e))))))

fn parseSeq s: String i: Int64 close: String acc: (List AsnItem) -> (Option (Pair (List AsnItem) Int64))
  (let [(j (skipLeading s i)) (c (byteAt s j))]
    (cond
      ((= c close) (some (pair (listReverse acc) (+ j 1))))
      ((or (stringEmpty? c) (stringContains? ")]}" c)) (none))
      (else (mt (parseItem s j) ((none) (none)) ((some r) (parseSeq s (pairSecond r) close (cons (pairFirst r) acc)))))))

fn itemAt items: (List AsnItem) i: Int64 -> AsnItem
  (optionOr (listGet items i) (AsnItem :kind "" :text "" :kids (list)))

fn workspaceStep kids: (List AsnItem) i: Int64 -> String
  (if (>= (+ i 1) (listLength kids)) ""
    (let [(k (itemAt kids i)) (v (itemAt kids (+ i 1)))]
      (if (and (= k.kind "kw") (and (= k.text "workspace") (= v.kind "str"))) v.text (workspaceStep kids (+ i 1)))))

fn ! workspaceOf! dir: String ix: ModIndex -> (Pair String ModIndex)
  (mt (mapGet ix.workspaces dir)
    ((some w) (pair w ix))
    ((none) (let [(w (mt (fileReadString (str dir "/.asl.config.asn"))
                      ((err _) "")
                      ((ok src) (mt (parseItem src 0) ((some r) (let [(l (pairFirst r))] (if (= l.kind "list") (workspaceStep l.kids 1) ""))) ((none) "")))))]
      (pair w (with ix :workspaces (mapSet ix.workspaces dir w))))))

fn skipPath path: String ix: ModIndex -> ModIndex
  (with ix :skipped (+ ix.skipped 1) :skippedAt (if (= ix.skipped 0) path ix.skippedAt))

fn nameItemText it: AsnItem -> String
  (if (or (= it.kind "sym") (= it.kind "str")) it.text "")

fn manifestDeps kids: (List AsnItem) i: Int64 acc: (List String) -> (List String)
  (if (>= (+ i 1) (listLength kids)) acc
    (let [(k (itemAt kids i)) (v (itemAt kids (+ i 1)))]
      (if (and (= k.kind "kw") (and (= k.text "dependencies") (or (= v.kind "vect") (= v.kind "list"))))
        (manifestDeps kids (+ i 1) (filter (fn [(d String)] -> Bool (not (stringEmpty? d))) (map nameItemText v.kids)))
        (manifestDeps kids (+ i 1) acc))))

fn ! indexManifest! dir: String path: String ix: ModIndex -> ModIndex
  (mt (fileReadString path)
    ((err _) (skipPath path ix))
    ((ok src) (if (>= (skipLeading src 0) (stringLength src)) ix
      (mt (parseItem src 0)
        ((none) (skipPath path ix))
        ((some r) (let [(l (pairFirst r)) (kids l.kids) (head (itemAt kids 0))]
          (if (and (= l.kind "list") (and (>= (listLength kids) 2) (and (= head.kind "kw") (= head.text "package"))))
            (with ix :pkgs (cons (IdxPkg :name (nameItemText (itemAt kids 1)) :base (lastSegOf dir) :dir dir :deps (manifestDeps kids 2 (list))) ix.pkgs))
            ix)))))))

fn ! walkEntry! dir: String name: String depth: Int64 ix: ModIndex -> ModIndex
  (let [(path (str dir "/" name))]
    (if (or (stringStartsWith? name ".") (= name "node_modules")) ix
      (mt (realPath! path)
        ((none) ix)
        ((some real) (if (!= real path) ix
          (mt (fileStat path)
            ((err _) ix)
            ((ok st) (cond
              (st.isDir (walkDir! path (+ depth 1) ix))
              ((and st.isFile (and (> (stringLength name) 4) (stringEndsWith? name ".asl")))
                (mt (headerName! path) ((none) ix) ((some n) (with ix :mods (cons (IdxMod :name n :path path) ix.mods)))))
              ((and st.isFile (= name "manifest.asn")) (indexManifest! dir path ix))
              (else ix)))))))))

fn ! walkEntries! dir: String names: (List String) depth: Int64 ix: ModIndex -> ModIndex
  (mt (listHead names) ((none) ix) ((some n) (walkEntries! dir (safeTail names) depth (walkEntry! dir n depth ix))))

fn ! walkDir! dir: String depth: Int64 ix: ModIndex -> ModIndex
  (if (>= depth 64) (skipPath dir ix)
    (mt (dirList dir) ((err _) (skipPath dir ix)) ((ok names) (walkEntries! dir names depth ix))))

fn ! ensureIndex! root: String ix: ModIndex -> ModIndex
  (if (= ix.root root) ix
    (let [(built (walkDir! root 0 (with ix :root root :mods (list) :pkgs (list) :skipped 0 :skippedAt "")))]
      (ModIndex :root root :mods (listReverse built.mods) :pkgs (listReverse built.pkgs) :skipped built.skipped :skippedAt built.skippedAt :workspaces built.workspaces)))

fn addCands c: (List Cand) more: (List Cand) -> (List Cand)
  (fold (fn [(acc (List Cand)) (x Cand)] -> (List Cand) (if (listAny? (fn [(y Cand)] -> Bool (= y.path x.path)) acc) acc (listAppendOne acc x))) c more)

fn declaredAt ix: ModIndex path: String -> String
  (mt (listHead (filter (fn [(m IdxMod)] -> Bool (= m.path path)) ix.mods)) ((some m) m.name) ((none) "?"))

fn ! fileCand! ix: ModIndex dir: String mid: String p: String -> (List Cand)
  (let [(f (str dir "/" mid p ".asl"))]
    (if (not (fileExists? f)) (list)
      (mt (withinRoot! f ix.root) ((none) (list)) ((some real) (list (Cand :path real :name (declaredAt ix real)))))))

fn modCands mods: (List IdxMod) -> (List Cand)
  (map (fn [(m IdxMod)] -> Cand (Cand :path m.path :name m.name)) mods)

fn byLastSeg ix: ModIndex dir: (Option String) seg: String -> (List Cand)
  (modCands (filter (fn [(m IdxMod)] -> Bool (and (mt dir ((some d) (isUnder? m.path d)) ((none) true)) (= (lastSegOf m.name) seg))) ix.mods))

fn declaredNamed ix: ModIndex name: String -> (List Cand)
  (modCands (filter (fn [(m IdxMod)] -> Bool (= m.name name)) ix.mods))

fn pkgNamed? p: IdxPkg n: String -> Bool
  (or (and (not (stringEmpty? p.name)) (= p.name n)) (= p.base n))

fn settleStatus c: (List Cand) -> ResStatus
  (let [(n (listLength c))] (cond ((= n 1) (resOk)) ((= n 0) (resMissing)) (else (resAmbiguous))))

fn relToRoot ix: ModIndex path: String -> String
  (if (isUnder? path ix.root) (sliceFrom path (+ (stringLength ix.root) 1)) path)

fn describe ix: ModIndex c: (List Cand) status: ResStatus -> String
  (let [(n (listLength c))
        (prefix (mt status ((resAmbiguous) " ambiguous: ") (_ (if (> n 0) " not declared; candidates: " " not declared"))))
        (shown (stringJoin (map (fn [(x Cand)] -> String (str x.name " at " (relToRoot ix x.path))) (listTake c 8)) ", "))
        (more (if (> n 8) (str ", and " (stringFromInt64 (- n 8)) " more") ""))
        (gap (if (> ix.skipped 0) (str "; the index skipped " (stringFromInt64 ix.skipped) " unreadable path(s), first " ix.skippedAt) ""))]
    (str prefix shown more gap))

fn settled ix: ModIndex c: (List Cand) -> Resolution
  (let [(st (settleStatus c))]
    (Resolution :status st :path (mt st ((resOk) (mt (listHead c) ((some x) x.path) ((none) ""))) (_ "")) :note (mt st ((resAmbiguous) (describe ix c st)) (_ "")) :index ix))

fn missingRes note: String ix: ModIndex -> Resolution
  (Resolution :status (resMissing) :path "" :note note :index ix)

fn isMissing? r: Resolution -> Bool
  (mt r.status ((resMissing) true) (_ false))

fn badSegment? seg: String -> Bool
  (or (stringEmpty? seg) (or (= seg ".") (= seg "..")))

fn countUps p: String n: Int64 -> Int64
  (if (stringStartsWith? (sliceFrom p (* 3 n)) "../") (countUps p (+ n 1)) n)

fn upDirs dir: String n: Int64 -> String
  (if (<= n 0) dir (upDirs (parentDirOf dir) (- n 1)))

fn ! scanUp! dir: String ctx: LoadCtx -> LoadCtx
  (let [(hasCfg (fileExists? (str dir "/.asl.config.asn")))
        (next (LoadCtx :nearest (if (and hasCfg (stringEmpty? ctx.nearest)) dir ctx.nearest) :outer (if hasCfg dir ctx.outer) :pkg (if (and (stringEmpty? ctx.pkg) (fileExists? (str dir "/manifest.asn"))) dir ctx.pkg)))]
    (if (or (= dir "/") (= (parentDirOf dir) dir)) next (scanUp! (parentDirOf dir) next)))

fn ! okIfWithin! cand: String root: String ix: ModIndex -> (Option Resolution)
  (if (not (fileExists? cand)) (none)
    (mt (withinRoot! cand root) ((none) (none)) ((some real) (some (Resolution :status (resOk) :path real :note "" :index ix)))))

fn ! resolveWorkspaceQualified! imp: String rest: String nearest: String outer: String ix: ModIndex -> Resolution
  (mt (okIfWithin! (str nearest "/" rest ".asl") nearest ix)
    ((some r) r)
    ((none) (mt (okIfWithin! (str nearest "/src/" rest ".asl") nearest ix)
      ((some r) r)
      ((none) (let [(ix2 (ensureIndex! outer ix))
                    (c (filter (fn [(x Cand)] -> Bool (isUnder? x.path nearest)) (declaredNamed ix2 imp)))
                    (st (settleStatus c))]
        (mt st
          ((resOk) (settled ix2 c))
          ((resMissing) (let [(c2 (byLastSeg ix2 (some nearest) (lastSegOf imp)))]
            (if (stringEmpty? rest)
              (let [(st2 (settleStatus c2))]
                (mt st2
                  ((resOk) (settled ix2 c2))
                  (_ (Resolution :status st2 :path "" :note (describe ix2 c2 st2) :index ix2))))
              (Resolution :status st :path "" :note (describe ix2 c2 st) :index ix2))))
          (_ (Resolution :status st :path "" :note (describe ix2 c st) :index ix2))))))))

fn ! pkgFileCands! ix: ModIndex pkgs: (List IdxPkg) p: String -> (List Cand)
  (fold (fn [(acc (List Cand)) (k IdxPkg)] -> (List Cand) (addCands acc (addCands (fileCand! ix k.dir "src/" p) (fileCand! ix k.dir "" p)))) (list) pkgs)

fn ! depCands! ix: ModIndex pkgDir: String p: String -> (List Cand)
  (let [(deps (fold (fn [(acc (List String)) (k IdxPkg)] -> (List String) (if (= k.dir pkgDir) (listAppend acc k.deps) acc)) (list) ix.pkgs))]
    (fold (fn [(acc (List Cand)) (dep String)] -> (List Cand)
            (fold (fn [(acc2 (List Cand)) (k IdxPkg)] -> (List Cand) (if (pkgNamed? k dep) (addCands acc2 (addCands (fileCand! ix k.dir "src/" p) (byLastSeg ix (some k.dir) p))) acc2)) acc ix.pkgs))
          (list) deps))

fn ! resolveDeclared! imp: String qualified: Bool pkg: String outer: String ix: ModIndex -> Resolution
  (let [(c0 (addCands (if qualified (list) (fileCand! ix outer "" imp)) (declaredNamed ix imp)))
        (local (filter (fn [(x Cand)] -> Bool (isUnder? x.path pkg)) (declaredNamed ix imp)))
        (c (if (and (> (listLength c0) 1) (= (listLength local) 1)) local c0))
        (r (settled ix c))]
    (if (isMissing? r) (missingRes (describe ix (byLastSeg ix (none) (lastSegOf imp)) (resMissing)) ix) r))

fn ! resolveIndexed! imp: String first: String rest: String qualified: Bool pkg: String outer: String ix0: ModIndex -> Resolution
  (let [(ix (ensureIndex! outer ix0))]
    (if qualified
      (let [(r (settled ix (pkgFileCands! ix (filter (fn [(k IdxPkg)] -> Bool (pkgNamed? k first)) ix.pkgs) rest)))]
        (if (isMissing? r) (resolveDeclared! imp qualified pkg outer ix) r))
      (let [(own (addCands (fileCand! ix pkg "src/" imp) (fileCand! ix pkg "" imp)))
            (r1 (settled ix (if (listEmpty? own) (byLastSeg ix (some pkg) imp) own)))]
        (if (not (isMissing? r1)) r1
          (let [(r2 (settled ix (depCands! ix pkg imp)))]
            (if (not (isMissing? r2)) r2 (resolveDeclared! imp qualified pkg outer ix)))))))

fn ! resolveNamed! imp: String nearest: String outer: String pkg: String ix0: ModIndex -> Resolution
  (let [(slash (stringIndexOf imp "/"))
        (qualified (some? slash))
        (first (mt slash ((some k) (optionOr (stringSlice imp 0 k) imp)) ((none) imp)))
        (rest (mt slash ((some k) (sliceFrom imp (+ k 1))) ((none) "")))
        (wsPair (workspaceOf! nearest ix0))
        (ws (pairFirst wsPair))
        (ix (pairSecond wsPair))]
    (cond
      ((and (not (stringEmpty? ws)) (= ws first)) (resolveWorkspaceQualified! imp rest nearest outer ix))
      (qualified (let [(direct (str outer "/" imp ".asl"))]
        (if (fileExists? direct)
          (mt (withinRoot! direct outer) ((some real) (Resolution :status (resOk) :path real :note "" :index ix)) ((none) (missingRes " names a path that leaves the workspace root" ix)))
          (mt (okIfWithin! (str outer "/" first "/src/" rest ".asl") outer ix)
            ((some r) r)
            ((none) (resolveIndexed! imp first rest qualified pkg outer ix))))))
      (else (resolveIndexed! imp first rest qualified pkg outer ix))))

fn ! resolveImport! importer: String imp: String ix: ModIndex -> Resolution
  (let [(ups (countUps imp 0)) (q (sliceFrom imp (* 3 ups)))]
    (if (listAny? badSegment? (stringSplit q "/")) (missingRes " has an empty, . or .. segment after its leading ../ run" ix)
      (let [(dir (optionOr (realPath! (parentDirOf importer)) (parentDirOf importer)))
            (ctx (scanUp! dir (LoadCtx :nearest "" :outer "" :pkg "")))]
        (mt (if (stringEmpty? ctx.nearest) (none) (realPath! ctx.outer))
          ((none) (missingRes " has no .asl.config.asn above its importer" ix))
          ((some outer) (let [(pkg (if (or (stringEmpty? ctx.pkg) (not (isUnder? ctx.pkg outer))) ctx.nearest ctx.pkg))]
            (if (> ups 0)
              (let [(out (str (upDirs dir ups) "/" q ".asl"))]
                (mt (if (fileExists? out) (withinRoot! out outer) (none))
                  ((none) (missingRes " names no file inside the workspace root" ix))
                  ((some real) (Resolution :status (resDeprecated) :path real :note (optionOr (headerName! real) "no module header") :index ix))))
              (resolveNamed! imp ctx.nearest outer pkg ix))))))))

fn unresolvedLine importer: String imp: String r: Resolution -> String
  (str importer ": ERR_UNRESOLVED_IMPORT " imp r.note)

fn importAlias kids: (List AsnItem) q: Int64 alias: String -> String
  (if (>= (+ q 1) (listLength kids)) alias
    (let [(k (itemAt kids q)) (v (itemAt kids (+ q 1)))]
      (importAlias kids (+ q 1) (if (and (= k.kind "kw") (and (or (= k.text "a") (= k.text "as")) (= v.kind "sym"))) v.text alias))))

fn importEntry it: AsnItem -> (Option (Pair String String))
  (cond
    ((= it.kind "sym") (some (pair (lastSegOf it.text) it.text)))
    ((and (= it.kind "list") (= (itemAt it.kids 0).kind "sym"))
      (let [(p (itemAt it.kids 0).text)] (some (pair (importAlias it.kids 1 (lastSegOf p)) p))))
    (else (none)))

fn headerStep kids: (List AsnItem) i: Int64 h: ModHeader -> ModHeader
  (if (>= (+ i 1) (listLength kids)) h
    (let [(k (itemAt kids i)) (v (itemAt kids (+ i 1))) (isSeq (or (= v.kind "vect") (= v.kind "list")))]
      (cond
        ((!= k.kind "kw") (headerStep kids (+ i 1) h))
        ((and (= k.text "x") isSeq) (headerStep kids (+ i 2) (with h :exports (map (fn [(e AsnItem)] -> String e.text) (filter (fn [(e AsnItem)] -> Bool (= e.kind "sym")) v.kids)))))
        ((and (= k.text "i") isSeq) (headerStep kids (+ i 2) (with h :imports (listReverse (fold (fn [(acc (List (Pair String String))) (e AsnItem)] -> (List (Pair String String)) (mt (importEntry e) ((some p) (cons p acc)) ((none) acc))) (list) v.kids)))))
        ((and (or (= k.text "d") (= k.text "doc")) (= v.kind "str")) (headerStep kids (+ i 2) (with h :hasDoc (not (stringEmpty? v.text)))))
        (else (headerStep kids (+ i 2) h)))))

fn headerScan src: String i: Int64 -> (Option ModHeader)
  (mt (parseItem src i)
    ((none) (none))
    ((some r) (let [(it (pairFirst r)) (kids it.kids)]
      (if (and (= it.kind "list") (and (= (itemAt kids 0).kind "sym") (= (itemAt kids 0).text "module")))
        (some (headerStep kids 2 (ModHeader :name (if (= (itemAt kids 1).kind "sym") (itemAt kids 1).text "") :hasDoc false :exports (list) :imports (list))))
        (headerScan src (pairSecond r))))))

fn headerSummary h: ModHeader hasHeader: Bool path: String imports: (Map String String) -> ModuleSummary
  (ModuleSummary :name (if (stringEmpty? h.name) path h.name) :path path :hasHeader hasHeader :hasDoc h.hasDoc :exports (filter (fn [(e String)] -> Bool (not (isPascalName? e))) h.exports) :exportedTypes (filter (fn [(e String)] -> Bool (isPascalName? e)) h.exports) :imports imports :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty))

fn ! resolveImports! importer: String entries: (List (Pair String String)) pass: ImportPass -> ImportPass
  (mt (listHead entries)
    ((none) pass)
    ((some e) (let [(alias (pairFirst e)) (imp (pairSecond e)) (r (if (= imp "sys") (Resolution :status (resOk) :path "sys" :note "" :index pass.index) (resolveImport! importer imp pass.index)))
                    (found (mt r.status ((resOk) true) ((resDeprecated) true) (_ false)))
                    (next (if found
                      (ImportPass :imports (mapSet pass.imports alias r.path) :targets (if (= r.path "sys") pass.targets (cons r.path pass.targets)) :unresolved pass.unresolved :index r.index)
                      (ImportPass :imports (mapSet pass.imports alias imp) :targets pass.targets :unresolved (cons (unresolvedLine importer imp r) pass.unresolved) :index r.index)))]
      (resolveImports! importer (safeTail entries) next))))

fn markedFn? d: a/DefunNode -> Bool
  (or d.effect (and (> (stringLength d.name) 1) (stringEndsWith? d.name "!")))

fn withImports s: ModuleSummary imports: (Map String String) -> ModuleSummary
  (with s :imports imports)

fn depMatches? m: ModuleSummary mpath: String pathSuffix: String nameSuffix: String -> Bool
  (or (= m.name mpath)
      (or (= m.path mpath)
          (or (and (stringContains? m.path pathSuffix) (stringEndsWith? m.path pathSuffix))
              (and (stringContains? m.name nameSuffix) (stringEndsWith? m.name nameSuffix)))))

(schema DepIndex (:f deps (Map String ModuleSummary)) (:f byKey (Map String (List ModuleSummary))) (:f indexed Bool))

fn slashSuffixes parts: (List String) acc: (List String) -> (List String)
  (mt (listTail parts)
    ((none) acc)
    ((some rest) (if (listEmpty? rest) acc (slashSuffixes rest (cons (stringJoin rest "/") acc)))))

fn depKeys m: ModuleSummary -> (List String)
  (let [(n (stringLength m.path))
        (pathTails (if (stringEndsWith? m.path ".asl") (slashSuffixes (stringSplit (optionOr (stringSlice m.path 0 (- n 4)) "") "/") (list)) (list)))]
    (cons m.name (cons m.path (slashSuffixes (stringSplit m.name "/") pathTails))))

fn depIndexOf deps: (Map String ModuleSummary) -> DepIndex
  (DepIndex :deps deps :indexed true
    :byKey (fold (fn [(acc (Map String (List ModuleSummary))) (m ModuleSummary)] -> (Map String (List ModuleSummary))
                   (fold (fn [(a (Map String (List ModuleSummary))) (k String)] -> (Map String (List ModuleSummary)) (mapSet a k (cons m (optionOr (mapGet a k) (list)))))
                         acc (mapKeys (listToSet (depKeys m)))))
                 (mapEmpty) (listReverse (mapValues deps))))

fn depScanOf deps: (Map String ModuleSummary) -> DepIndex
  (DepIndex :deps deps :byKey (mapEmpty) :indexed false)

fn deduplicateSummaries mods: (List ModuleSummary) -> (List ModuleSummary)
  (let [(folded (fold (fn [(acc (Pair (List ModuleSummary) (Map String Bool))) (m ModuleSummary)] -> (Pair (List ModuleSummary) (Map String Bool))
                        (let [(p m.path) (seen (pairSecond acc))]
                          (if (mapHas? seen p) acc (pair (cons m (pairFirst acc)) (mapSet seen p true)))))
                      (pair (list) (mapEmpty)) mods))]
    (pairFirst folded))

fn resolveDepTarget mpath: String deps: (Map String ModuleSummary) -> (Result ModuleSummary String)
  (if (stringEmpty? mpath) (err "ERR_NOT_FOUND: empty module path")
    (let [(pathSuffix (str "/" mpath ".asl")) (nameSuffix (str "/" mpath))]
      (pickDepTarget mpath (deduplicateSummaries (filter (fn [(m ModuleSummary)] -> Bool (depMatches? m mpath pathSuffix nameSuffix)) (mapValues deps))) deps)))

fn pickDepTarget mpath: String allMatches: (List ModuleSummary) deps: (Map String ModuleSummary) -> (Result ModuleSummary String)
  (let [(matchCount (listLength allMatches)) (keyed (mapGet deps mpath))]
    (cond
      ((some? keyed) (ok (optionOr keyed (emptyModuleSummary))))
      ((= matchCount 1) (ok (optionOr (listHead allMatches) (emptyModuleSummary))))
      ((> matchCount 1)
       (let [(names (stringJoin (map (fn [(m ModuleSummary)] -> String (if (!= m.name "") m.name m.path)) allMatches) ", "))]
         (err (str "ERR_AMBIGUOUS_MODULE: ambiguous match for " mpath ": " names))))
      (else (err (str "ERR_NOT_FOUND: no module matches " mpath)))))

fn depCandidates mpath: String ix: DepIndex -> (List ModuleSummary)
  (if ix.indexed (optionOr (mapGet ix.byKey mpath) (list)) (mapValues ix.deps))

fn resolveDepIn mpath: String ix: DepIndex -> (Result ModuleSummary String)
  (if (not ix.indexed) (resolveDepTarget mpath ix.deps)
    (if (stringEmpty? mpath) (err "ERR_NOT_FOUND: empty module path")
      (pickDepTarget mpath (deduplicateSummaries (depCandidates mpath ix)) ix.deps)))

fn ioErrorText e: IoError -> String
  (mt e ((notFound) "not found") ((permissionDenied) "permission denied") ((alreadyExists) "already exists") ((invalidPath) "invalid path") ((interrupted) "interrupted") ((other) "other error"))

fn closureFailed cl: ModuleClosure line: String -> ModuleClosure
  (with cl :unresolved (listAppendOne cl.unresolved line))

fn closureError cl: ModuleClosure line: String -> ModuleClosure
  (with cl :errors (listAppendOne cl.errors line))

fn ! loadModule! real: String src: String rest: (List String) parseBodies: Bool cl: ModuleClosure -> ModuleClosure
  (let [(hOpt (headerScan src 0))
        (h (optionOr hOpt (ModHeader :name "" :hasDoc false :exports (list) :imports (list))))
        (pass (resolveImports! real h.imports (ImportPass :imports (mapEmpty) :targets (list) :unresolved (list) :index cl.index)))
        (headerOnly (headerSummary h (some? hOpt) real pass.imports))
        (built (if parseBodies
                 (mt (a/parseForChecker src)
                   ((ok forms) (pair (withImports (collectSummary forms real) pass.imports) cl.errors))
                   ((err pe) (pair headerOnly (listAppendOne cl.errors (str real ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": ERR_PARSE " pe.msg)))))
                 (pair headerOnly cl.errors)))]
    (loadQueue! (listAppend rest (listReverse pass.targets)) parseBodies
      (ModuleClosure :deps (mapSet cl.deps real (pairFirst built)) :paths (cons real cl.paths) :unresolved (listAppend cl.unresolved (listReverse pass.unresolved)) :errors (pairSecond built) :index pass.index)))

fn ! loadQueue! queue: (List String) parseBodies: Bool cl: ModuleClosure -> ModuleClosure
  (mt (listHead queue)
    ((none) cl)
    ((some real) (let [(rest (safeTail queue))]
      (if (mapHas? cl.deps real) (loadQueue! rest parseBodies cl)
        (mt (fileRead real)
          ((err e) (loadQueue! rest parseBodies (closureError cl (str real ": ERR_IO " (ioErrorText e)))))
          ((ok src) (loadModule! real src rest parseBodies cl)))))))

fn ! resolveTop! importers: (List String) imp: String ix: ModIndex first: (Option Resolution) -> Resolution
  (mt (listHead importers)
    ((none) (optionOr first (missingRes " has no importer directory to resolve against" ix)))
    ((some importer) (let [(r (resolveImport! importer imp ix))]
      (if (isMissing? r) (resolveTop! (safeTail importers) imp r.index (some (optionOr first r))) r))))

fn ! loadTop! importers: (List String) entries: (List (Pair String String)) parseBodies: Bool cl: ModuleClosure keys: (List (Pair String String)) -> ModuleClosure
  (mt (listHead entries)
    ((none) (let [(loaded (loadQueue! (map pairSecond keys) parseBodies cl))]
      (ModuleClosure :deps (fold (fn [(acc (Map String ModuleSummary)) (k (Pair String String))] -> (Map String ModuleSummary) (mt (mapGet acc (pairSecond k)) ((some s) (mapSet acc (pairFirst k) s)) ((none) acc))) loaded.deps keys) :paths (listReverse loaded.paths) :unresolved loaded.unresolved :errors loaded.errors :index loaded.index)))
    ((some e) (let [(imp (pairSecond e))
                    (r (if (= imp "sys") (Resolution :status (resOk) :path "sys" :note "" :index cl.index) (resolveTop! importers imp cl.index (none))))
                    (cl2 (ModuleClosure :deps cl.deps :paths cl.paths :unresolved cl.unresolved :errors cl.errors :index r.index))
                    (found (mt r.status ((resOk) true) ((resDeprecated) true) (_ false)))]
      (if found
        (loadTop! importers (safeTail entries) parseBodies cl2 (if (= imp "sys") keys (listAppendOne keys (pair imp r.path))))
        (loadTop! importers (safeTail entries) parseBodies (closureFailed cl2 (unresolvedLine (optionOr (listHead importers) "") imp r)) keys)))))

fn ! loadModuleClosure! entry: String parseBodies: Bool -> ModuleClosure
  (let [(empty (ModuleClosure :deps (mapEmpty) :paths (list) :unresolved (list) :errors (list) :index (emptyModIndex)))]
    (mt (realPath! entry)
      ((none) (closureError empty (str entry ": ERR_IO cannot open file")))
      ((some real) (mt (fileRead real)
        ((err e) (closureError empty (str real ": ERR_IO " (ioErrorText e))))
        ((ok src) (loadTop! (list real) (mt (headerScan src 0) ((some h) h.imports) ((none) (list))) parseBodies empty (list)))))))

fn ! printLines! lines: (List String) -> Unit
  (mt (listHead lines) ((none) ()) ((some l) (do (eprintln l) (printLines! (safeTail lines)))))

fn ! loadModuleDeps! roots: (List String) imports: (List String) -> (Result (Map String ModuleSummary) IoError)
  (let [(importers (fold (fn [(acc (List String)) (r String)] -> (List String) (mt (realPath! r) ((some d) (listAppendOne acc (str d "/_"))) ((none) acc))) (list) roots))
        (cl (loadTop! importers (map (fn [(p String)] -> (Pair String String) (pair (lastSegOf p) p)) imports) true (ModuleClosure :deps (mapEmpty) :paths (list) :unresolved (list) :errors (list) :index (emptyModIndex)) (list)))]
    (do (printLines! cl.unresolved)
        (printLines! cl.errors)
        (cond ((not (listEmpty? cl.unresolved)) (err (notFound)))
              ((not (listEmpty? cl.errors)) (err (other)))
              (else (ok cl.deps)))))

fn mapKeysSet m: (Map String ModuleSummary) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (k String)] -> (Map String Bool) (mapSet acc k true)) (mapEmpty) (mapKeys m))

fn mapValuesList m: (Map String String) -> (List String)
  (mapValues m)

fn isNullaryBuiltinType? resolved: String -> Bool
  (or (ty/isNumericType? resolved) (listContains? (list "String" "Bool" "Unit" "IoError" "N" "Bytes" "ProcessOutput" "SpawnedProc" "PlatformInfo" "Rusage" "FileStat") resolved))

fn isKnownBuiltinType? name: String -> Bool
  (let [(resolved (ty/resolveTypeAlias name))] (or (isNullaryBuiltinType? resolved) (or (or (= resolved "List") (or (= resolved "Option") (= resolved "Result"))) (or (= resolved "Map") (= resolved "Pair")))))

fn builtinTypeArity name: String -> (Option Int64)
  (let [(resolved (ty/resolveTypeAlias name))] (cond ((= resolved "List") (some 1)) ((= resolved "Option") (some 1)) ((= resolved "Result") (some 2)) ((= resolved "Map") (some 2)) ((= resolved "Pair") (some 2)) ((isNullaryBuiltinType? resolved) (some 0)) (else (none))))

fn checkTypeTrees ts: (List ty/Type) bound: (Map String Bool) mod: ModuleSummary deps: DepIndex where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic) (checkTypeTreeIx item bound mod deps where path a)) acc ts)

fn importedTypeArity name: String mod: ModuleSummary deps: DepIndex -> (Option Int64)
  (fold
    (fn [(acc (Option Int64)) (mpath String)] -> (Option Int64)
      (mt acc
        ((some _) acc)
        ((none)
         (mt (resolveDepIn mpath deps)
           ((err _) (none))
           ((ok target)
            (if (or (listContains? target.exportedTypes name) (listContains? target.exports name))
              (mt (modSchema target name)
                ((some schema) (some (listLength schema.typevars)))
                ((none)
                 (mt (modEnum target name)
                   ((some enum) (some (listLength enum.typevars)))
                   ((none) (none)))))
              (none)))))))
    (none)
    (mapValues mod.imports))

fn dottedTypeDiag t: ty/Type where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt t
    ((ty/tyCon name _ _ _)
      (if (stringContains? name ".")
        (cons (makeDiag "ERR_TYPE_FIELD" (str "a dotted name in type position reads as field access (" name ") in " where ": write alias/Type for an imported type") path) acc)
        acc))
    (_ acc))

fn dottedTypeTree t: ty/Type where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt t
    ((ty/tyCon _ args _ _) (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic) (dottedTypeTree item where path a)) (dottedTypeDiag t where path acc) args))
    ((ty/tyFun params ret) (dottedTypeTree ret where path (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic) (dottedTypeTree item where path a)) acc params)))
    (_ acc))

fn checkTypeTreeIx t: ty/Type bound: (Map String Bool) mod: ModuleSummary deps: DepIndex where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (checkTypeTreeAt t bound mod deps where path (dottedTypeDiag t where path acc))

fn checkTypeTreeAt t: ty/Type bound: (Map String Bool) mod: ModuleSummary deps: DepIndex where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt (chainedTypeTarget t mod deps)
    ((some p) (checkTypeTreeAt (pairFirst p) bound (pairSecond p) deps where path (checkTypeTrees (typeArgsOf t) bound mod deps where path acc)))
    ((none) (checkTypeTreeLocal t bound mod deps where path acc)))

fn typeArgsOf t: ty/Type -> (List ty/Type)
  (mt t ((ty/tyCon _ args _ _) args) (_ (list)))

fn chainedTypeTarget t: ty/Type mod: ModuleSummary deps: DepIndex -> (Option (Pair ty/Type ModuleSummary))
  (mt t
    ((ty/tyCon name args optMod optShown)
     (let [(parts (stringSplit (optionOr optShown "") "/"))]
       (if (< (listLength parts) 3) (none)
         (mt (modImport mod (optionOr (listHead parts) ""))
           ((none) (none))
           ((some mpath)
            (mt (resolveDepIn mpath deps)
              ((err _) (none))
              ((ok target)
               (let [(rest (safeTail parts))]
                 (some (pair (ty/tyCon (optionOr (listGet rest 1) name) (map (fn [(a ty/Type)] -> ty/Type (ty/tyVar 0 "any")) args) (listHead rest) (some (stringJoin rest "/"))) target))))))))))
    (_ (none)))

fn checkTypeTreeLocal t: ty/Type bound: (Map String Bool) mod: ModuleSummary deps: DepIndex where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt t
    ((ty/tyCon name args optMod optShown)
     (mt optMod
       ((some _) (checkTypeTreeRaw t bound mod deps where path acc))
       ((none)
        (mt (importedTypeArity name mod deps)
          ((none) (checkTypeTreeRaw t bound mod deps where path acc))
          ((some expected)
           (let [(checked (checkTypeTrees args bound mod deps where path acc))]
             (if (= expected (listLength args)) checked
               (cons (makeDiag "type-arity" (str name " in " where " takes " (stringFromInt64 expected) " type argument(s), given " (stringFromInt64 (listLength args))) path) checked))))))))
    (_ (checkTypeTreeRaw t bound mod deps where path acc)))

fn checkTypeTreeRaw t: ty/Type bound: (Map String Bool) mod: ModuleSummary deps: DepIndex where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt t ((ty/tyVar _ _) acc) ((ty/tyFun params ret) (let [(acc1 (checkTypeTrees params bound mod deps where path acc))] (checkTypeTreeIx ret bound mod deps where path acc1))) ((ty/tyCon name args optMod optShown) (let [(accArgs (checkTypeTrees args bound mod deps where path acc)) (givenArity (listLength args)) (expectedArity (mt optMod ((some alias) (mt (modImport mod alias) ((some mpath) (mt (resolveDepIn mpath deps) ((ok target) (mt (modSchema target name) ((some s) (some (listLength s.typevars))) ((none) (mt (modEnum target name) ((some e) (some (listLength e.typevars))) ((none) (none)))))) ((err _) (none)))) ((none) (none)))) ((none) (if (mapHas? bound name) (some 0) (mt (modSchema mod name) ((some s) (some (listLength s.typevars))) ((none) (mt (modEnum mod name) ((some e) (some (listLength e.typevars))) ((none) (builtinTypeArity name))))))))) (accArity (mt expectedArity ((some exp) (if (not (= exp givenArity)) (cons (makeDiag "type-arity" (str name " in " where " takes " (stringFromInt64 exp) " type argument(s), given " (stringFromInt64 givenArity)) path) accArgs) accArgs)) ((none) accArgs)))] (mt optMod ((some alias) (mt (modImport mod alias) ((none) (cons (makeDiag "rule-9" (str alias "/" name ": alias " alias " is not imported") path) accArity)) ((some mpath) (mt (resolveDepIn mpath deps) ((err _) accArity) ((ok target) (if (not (listContains? target.exportedTypes name)) (cons (makeDiag "rule-9" (str "ERR_NOT_EXPORTED: " name " is not an exported type of " target.name) path) accArity) accArity)))))) ((none) (if (or (isKnownBuiltinType? name) (or (mapHas? bound name) (or (mapHas? mod.schemas name) (mapHas? mod.enums name)))) accArity (cons (makeDiag "rule-10" (str name " in " where " is neither a known type nor bound in { }") path) accArity)))))))

fn checkPublicTypeTrees ts: (List ty/Type) bound: (Map String Bool) mod: ModuleSummary where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic) (checkPublicTypeTree item bound mod where path a)) acc ts)

fn checkPublicTypeTree t: ty/Type bound: (Map String Bool) mod: ModuleSummary where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt t ((ty/tyVar _ _) acc) ((ty/tyFun params ret) (let [(acc1 (checkPublicTypeTrees params bound mod where path acc))] (checkPublicTypeTree ret bound mod where path acc1))) ((ty/tyCon name args optMod optShown) (let [(accArgs (checkPublicTypeTrees args bound mod where path acc))] (mt optMod ((some _) accArgs) ((none) (if (or (mapHas? bound name) (listContains? mod.exportedTypes name)) accArgs (if (or (mapHas? mod.schemas name) (mapHas? mod.enums name)) (cons (makeDiag "rule-13" (str name " in " where " is declared here and not exported") path) accArgs) accArgs)))))))

fn addStringsToSet acc: (Map String Bool) xs: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (x String)] -> (Map String Bool) (mapSet m x true)) acc xs)

fn listToSet xs: (List String) -> (Map String Bool)
  (addStringsToSet (mapEmpty) xs)

fn checkModuleRules mod: ModuleSummary poses: (Map String (Pair Int64 Int64)) path: String -> (List ty/Diagnostic)
  (let [(d2 (fold (fn [(acc (List ty/Diagnostic)) (exp String)] -> (List ty/Diagnostic) (mt (modFun mod exp) ((some _) acc) ((none) (cons (makeDiag "rule-2" (str exp " is exported but not defined in this module") path) acc)))) (list) mod.exports)) (d3 (fold (fn [(acc (List ty/Diagnostic)) (tname String)] -> (List ty/Diagnostic) (if (and (not (mapHas? mod.schemas tname)) (not (mapHas? mod.enums tname))) (cons (makeDiag "rule-2" (str tname " is exported but not defined in this module") path) acc) acc)) d2 mod.exportedTypes))] d3)

fn checkCycleDfs cur: String stack: (List String) visited: (Map String Bool) deps: DepIndex modImports: (Map String String) path: String -> (Option (List String))
  (let [(targets (if (= cur (pairSecond (pair "" ""))) (mapValuesList modImports) (mt (resolveDepIn cur deps) ((ok s) (mapValuesList s.imports)) ((err _) (list)))))] (checkCycleEdges targets stack visited deps modImports path))

fn depName deps: DepIndex key: String -> String
  (mt (resolveDepIn key deps) ((ok s) (if (stringEmpty? s.name) key s.name)) ((err _) key))

fn closesAtRoot? stack: (List String) deps: DepIndex target: String -> Bool
  (let [(root (optionOr (listHead stack) ""))] (and (not (stringEmpty? root)) (= (depName deps target) root)))

fn checkCycleEdges edges: (List String) stack: (List String) visited: (Map String Bool) deps: DepIndex modImports: (Map String String) path: String -> (Option (List String))
  (mt (listHead edges) ((none) (none)) ((some edgeTarget) (let [(rest (safeTail edges))] (if (or (= (optionOr (listHead stack) "") edgeTarget) (closesAtRoot? stack deps edgeTarget)) (some (listAppendOne stack edgeTarget)) (if (or (listContains? stack edgeTarget) (mapHas? visited edgeTarget)) (checkCycleEdges rest stack visited deps modImports path) (let [(subRes (checkCycleDfs edgeTarget (listAppendOne stack edgeTarget) (mapSet visited edgeTarget true) deps modImports path))] (mt subRes ((some cyc) (some cyc)) ((none) (checkCycleEdges rest stack visited deps modImports path)))))))))

fn checkUnresolvedImportsStep mod: ModuleSummary deps: DepIndex path: String aliases: (List String) acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt (listHead aliases) ((none) acc) ((some alias) (let [(rest (safeTail aliases)) (mpath (optionOr (modImport mod alias) ""))] (if (or (= mpath "") (= mpath "sys")) (checkUnresolvedImportsStep mod deps path rest acc) (mt (resolveDepIn mpath deps) ((ok _) (checkUnresolvedImportsStep mod deps path rest acc)) ((err errMsg) (let [(code (if (stringStartsWith? errMsg "ERR_AMBIGUOUS_MODULE") "ERR_AMBIGUOUS_MODULE" "unresolved-import")) (msg (if (stringStartsWith? errMsg "ERR_AMBIGUOUS_MODULE") errMsg (str "no module " mpath " on the search path")))] (checkUnresolvedImportsStep mod deps path rest (cons (makeDiag code msg path) acc)))))))))

fn checkImportsAndCycles mod: ModuleSummary deps: DepIndex path: String -> (List ty/Diagnostic)
  (let [(aliases (mapKeys mod.imports)) (unres (checkUnresolvedImportsStep mod deps path aliases (list))) (cycleOpt (checkCycleDfs "" (list mod.name) (mapEmpty) deps mod.imports path))] (mt cycleOpt ((some cyc) (cons (makeDiag "rule-11" (str "import cycle: " (stringJoin (map (fn [(k String)] -> String (depName deps k)) cyc) " -> ")) path) unres)) ((none) unres)))

fn checkExportClosure mod: ModuleSummary path: String -> (List ty/Diagnostic)
  (let [(fDiags (fold (fn [(acc (List ty/Diagnostic)) (fname String)] -> (List ty/Diagnostic) (mt (modFun mod fname) ((some f) (let [(bset (listToSet f.typevars)) (pDiags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic) (let [(pty (ty/parseTypeStr (pairSecond p) (list)))] (checkPublicTypeTree pty bset mod (str "exported function " fname) path pacc))) acc f.params)) (rty (ty/parseTypeStr f.ret (list)))] (checkPublicTypeTree rty bset mod (str "exported function " fname) path pDiags))) ((none) acc))) (list) mod.exports)) (sDiags (fold (fn [(acc (List ty/Diagnostic)) (sname String)] -> (List ty/Diagnostic) (mt (modSchema mod sname) ((some s) (let [(bset (listToSet s.typevars))] (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic) (let [(fty (ty/parseTypeStr f.type (list)))] (checkPublicTypeTree fty bset mod (str "exported field " sname "." f.name) path facc))) acc s.fields))) ((none) acc))) fDiags mod.exportedTypes)) (eDiags (fold (fn [(acc (List ty/Diagnostic)) (ename String)] -> (List ty/Diagnostic) (mt (modEnum mod ename) ((some e) (let [(bset (listToSet e.typevars))] (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic) (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic) (let [(pty (ty/parseTypeStr (pairSecond p) (list)))] (checkPublicTypeTree pty bset mod (str "case " c.name " of exported " ename) path pacc))) cacc c.params)) acc e.cases))) ((none) acc))) sDiags mod.exportedTypes))] eDiags)

fn checkTypeAnnotations mod: ModuleSummary deps: DepIndex poses: (Map String (Pair Int64 Int64)) path: String -> (List ty/Diagnostic)
  (let [(dFuns (fold (fn [(acc (List ty/Diagnostic)) (f FunSummary)] -> (List ty/Diagnostic) (let [(bset (listToSet f.typevars)) (pDiags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic) (let [(pty (ty/parseTypeStr (pairSecond p) (list)))] (checkTypeTreeIx pty bset mod deps (str "function " f.name) path pacc))) (list) f.params)) (rty (ty/parseTypeStr f.ret (list)))] (listAppend (placeDiags (checkTypeTreeIx rty bset mod deps (str "function " f.name) path pDiags) (optionOr (mapGet poses f.name) (pair 1 1))) acc))) (list) (mapValues mod.funs))) (dSchemas (fold (fn [(acc (List ty/Diagnostic)) (s SchemaSummary)] -> (List ty/Diagnostic) (let [(bset (listToSet s.typevars))] (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic) (let [(fty (ty/parseTypeStr f.type (list)))] (checkTypeTreeIx fty bset mod deps (str "field " s.name "." f.name) path facc))) acc s.fields))) dFuns (mapValues mod.schemas))) (dEnums (fold (fn [(acc (List ty/Diagnostic)) (e EnumSummary)] -> (List ty/Diagnostic) (let [(bset (listToSet e.typevars))] (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic) (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic) (let [(pty (ty/parseTypeStr (pairSecond p) (list)))] (checkTypeTreeIx pty bset mod deps (str "case " c.name) path pacc))) cacc c.params)) acc e.cases))) dSchemas (mapValues mod.enums)))] dEnums)

fn isEffectfulBuiltin? name: String -> Bool
  (or (listContains? (list "tcpListen" "tcpConnect" "sockAccept" "sockLocalPort" "unixListen" "unixConnect" "unixSocketPair" "sockSendFd" "sockRecvFd") name) (or (or (= name "println") (or (= name "print") (= name "eprintln"))) (or (or (= name "fileRead") (or (= name "fileWrite") (or (= name "file-append") (or (= name "fileAppend") (or (= name "fileLock") (= name "fileLockWait")))))) (or (or (= name "fileExists?") (or (= name "read-line") (= name "read-all"))) (or (or (= name "dirList") (or (= name "execCmd") (= name "fileStat"))) (= name "pathCanonicalize"))))))

fn isSpecialForm? name: String -> Bool
  (or (or (= name "let") (or (= name "with") (or (= name "if") (= name "cond")))) (or (or (= name "try") (or (= name "fn") (or (= name "match") (= name "mt")))) (or (or (= name "module") (or (= name "defun") (= name "defschema"))) (or (= name "defenum") (or (= name "do") (or (= name "some") (or (= name "none") (or (= name "assert") (or (= name "refute") (or (= name "when") (= name "unless")))))))))))

fn isPreludeTag? name: String -> Bool
  (or (or (= name "some") (or (= name "none") (= name "ok"))) (or (or (= name "err") (or (= name "list") (= name "cons"))) (or (= name "pair") (or (or (= name "notFound") (or (= name "permissionDenied") (= name "alreadyExists"))) (or (or (= name "invalidPath") (= name "interrupted")) (= name "other"))))))

fn cleanNumSign v: String -> String
  (if (and (or (stringStartsWith? v "+") (stringStartsWith? v "-")) (> (stringLength v) 1)) (sliceFrom v 1) v)

fn isLiteralAtom? v: String -> Bool
  (if (or (stringStartsWith? v "\"") (or (= v "true") (or (= v "false") (= v "()")))) true (let [(s (cleanNumSign v))] (if (stringEmpty? s) false (stringContains? "0123456789" (firstCharStr s)))))

fn keywordCallHeadDiag headTok: String path: String -> (Option ty/Diagnostic)
  (if (stringStartsWith? headTok ":") (some (makeDiag "kw-call" (str headTok " is a keyword literal, not callable; write (SchemaName " headTok " ...) for a record, or {" (sliceFrom headTok 1) " ...} in ASN data") path)) (none))

fn splitQual s: String -> (Pair String String)
  (let [(parts (stringSplit s "/"))] (pair (optionOr (listGet parts 0) "") (optionOr (listGet parts 1) "")))

fn enumFamily m: ModuleSummary ename: String -> (Option (Pair String (List String)))
  (mt (modEnum m ename) ((some esum) (some (pair (str m.name "/" ename) (map (fn [(c CaseSummary)] -> String c.name) esum.cases)))) ((none) (none)))

fn findUnqualifiedCaseInDeps head: String mod: ModuleSummary deps: DepIndex -> (Option (Pair String (List String)))
  (fold (fn [(acc (Option (Pair String (List String)))) (mpath String)] -> (Option (Pair String (List String)))
          (mt acc
            ((some _) acc)
            ((none)
             (mt (resolveDepIn mpath deps)
               ((ok target)
                (mt (mapGet target.exportedCases head)
                  ((some ename) (enumFamily target ename))
                  ((none)
                   (mt (mapGet target.caseOwner head)
                     ((some ename) (enumFamily target ename))
                     ((none) (none))))))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn unionForTag head: String mod: ModuleSummary deps: DepIndex -> (Option (Pair String (List String)))
  (if (= head "pair") (some (pair "Pair" (list "pair"))) (unionForTagRaw head mod deps))

fn preludeUnionForTag head: String -> (Option (Pair String (List String)))
  (mt (ty/preludeUnionCases head)
    ((none) (none))
    ((some uname)
     (cond ((= uname "Option") (some (pair "Option" (list "some" "none"))))
           ((= uname "Result") (some (pair "Result" (list "ok" "err"))))
           ((= uname "List") (some (pair "List" (list "list" "cons"))))
           ((= uname "IoError") (some (pair "IoError" (list "notFound" "permissionDenied" "alreadyExists" "invalidPath" "interrupted" "other"))))
           (else (none)))))

fn importedUnionForTag head: String mod: ModuleSummary deps: DepIndex -> (Option (Pair String (List String)))
  (if (not (isQualifiedName? head))
    (none)
    (let [(qp (splitQual head)) (alias (pairFirst qp)) (member (pairSecond qp))]
      (mt (modImport mod alias)
        ((none) (none))
        ((some mpath)
         (mt (resolveDepIn mpath deps)
           ((err _) (none))
           ((ok target)
            (mt (mapGet target.exportedCases member)
              ((some ename) (enumFamily target ename))
              ((none) (mt (mapGet target.caseOwner member)
                        ((some ename) (enumFamily target ename))
                        ((none) (none)))))))))))

fn unionForTagRaw head: String mod: ModuleSummary deps: DepIndex -> (Option (Pair String (List String)))
  (mt (mapGet mod.caseOwner head)
    ((some ename) (enumFamily mod ename))
    ((none)
      (mt (importedUnionForTag head mod deps)
        ((some found) (some found))
        ((none)
         (if (mapHas? mod.funs head)
           (none)
           (mt (findUnqualifiedCaseInDeps head mod deps)
             ((some found) (some found))
             ((none) (preludeUnionForTag head))))))))

fn armFamily arm: rd/SExpr bare: Bool mod: ModuleSummary deps: DepIndex -> String
  (mt arm
    ((rd/sexprList parts)
     (mt (listHead parts)
       ((none) "")
       ((some pat) (mt pat
                     ((rd/sexprAtom v) (if bare (mt (unionForTag v mod deps) ((some u) (pairFirst u)) ((none) "")) ""))
                     ((rd/sexprList items) (if bare "" (mt (listHead items) ((some h) (mt (unionForTag (rd/sexprHead h) mod deps) ((some u) (pairFirst u)) ((none) ""))) ((none) ""))))
                     (_ "")))))
    (_ ""))

fn matchFamilyIx arms: (List rd/SExpr) mod: ModuleSummary deps: DepIndex -> String
  (let [(firstOf (fn [(bare Bool)] -> String (fold (fn [(acc String) (arm rd/SExpr)] -> String (if (= acc "") (armFamily arm bare mod deps) acc)) "" arms)))
        (applied (firstOf false))]
    (if (= applied "") (firstOf true) applied))

fn ctorPatternAtomIx? pat: rd/SExpr family: String mod: ModuleSummary deps: DepIndex -> Bool
  (mt pat
    ((rd/sexprAtom v) (and (!= family "") (mt (unionForTag v mod deps) ((some u) (= (pairFirst u) family)) ((none) false))))
    (_ false))

fn catchallPatternAtom? pat: rd/SExpr family: String mod: ModuleSummary deps: DepIndex -> Bool
  (mt pat
    ((rd/sexprAtom v) (if (or (= v "_") (= v "else")) true (if (or (isLiteralAtom? v) (stringStartsWith? v ":")) false (not (ctorPatternAtomIx? pat family mod deps)))))
    (_ false))

fn armPatternOf arm: rd/SExpr -> rd/SExpr
  (mt arm
    ((rd/sexprList armParts) (mt (listHead armParts) ((some p) p) ((none) (rd/makeAtom "_"))))
    (_ (rd/makeAtom "_")))

fn elseKeywordPatternAtom? pat: rd/SExpr -> Bool
  (mt pat
    ((rd/sexprAtom v) (= v ":else"))
    (_ false))

fn unreachableArmDiagsIx arms: (List rd/SExpr) family: String mod: ModuleSummary deps: DepIndex path: String seenCatchall: Bool -> (List ty/Diagnostic)
  (mt (listHead arms)
    ((none) (list))
    ((some arm)
     (let [(rest (safeTail arms))
           (pat (armPatternOf arm))
           (isCatchall (catchallPatternAtom? pat family mod deps))
           (dUnreach (if seenCatchall (list (makeDiag "unreachable-arm" "mt arm is unreachable: an earlier arm already binds everything" path)) (list)))
           (d (if (elseKeywordPatternAtom? pat) (cons (makeDiag "else-keyword" "mt pattern :else is a keyword literal, not the catch-all; use else or _" path) dUnreach) dUnreach))]
       (listAppend d (unreachableArmDiagsIx rest family mod deps path (or seenCatchall isCatchall))))))

fn invalidArmHead pat: rd/SExpr mod: ModuleSummary path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt pat
    ((rd/sexprAtom v) (if (or (mapHas? mod.funs v) (or (and (some? (ty/builtinSig v)) (not (or (isPreludeTag? v) (some? (ty/preludeUnionCases v))))) (listContains? (list "do" "begin" "if" "cond" "let" "match" "mt" "when" "unless" "fn" "lambda" "assert" "refute" "and" "or" "not") v))) (cons (makeDiag "ERR_INVALID_MT_ARM" "mt arm has an invalid pattern head" path) acc) acc))
    (_ acc))

fn extractPattern pat: rd/SExpr mod: ModuleSummary deps: DepIndex path: String accDiags: (List ty/Diagnostic) -> (Pair (Pair (List String) (Option String)) (List ty/Diagnostic))
  (mt pat ((rd/sexprAtom v) (if (or (= v "_") (isLiteralAtom? v)) (pair (pair (list) (none)) accDiags) (pair (pair (list v) (none)) accDiags))) ((rd/sexprVect items) (let [(vRes (fold (fn [(acc (Pair (List String) (List ty/Diagnostic))) (sub rd/SExpr)] -> (Pair (List String) (List ty/Diagnostic)) (let [(subRes (extractPattern sub mod deps path (pairSecond acc)))] (pair (listAppend (pairFirst acc) (pairFirst (pairFirst subRes))) (pairSecond subRes)))) (pair (list) accDiags) items))] (pair (pair (pairFirst vRes) (none)) (pairSecond vRes)))) ((rd/sexprList items) (mt (listHead items) ((none) (pair (pair (list) (none)) accDiags)) ((some h) (let [(headTok (rd/sexprHead h)) (subs (safeTail items)) (uInfo (unionForTag headTok mod deps))] (let [(dCheck (mt uInfo ((some _) accDiags) ((none) (cons (makeDiag "rule-2" (str headTok " is not a case of any union") path) accDiags)))) (arityRes (fold (fn [(acc (Pair (List String) (List ty/Diagnostic))) (sub rd/SExpr)] -> (Pair (List String) (List ty/Diagnostic)) (let [(subRes (extractPattern sub mod deps path (pairSecond acc)))] (pair (listAppend (pairFirst acc) (pairFirst (pairFirst subRes))) (pairSecond subRes)))) (pair (list) dCheck) subs))] (pair (pair (pairFirst arityRes) (some headTok)) (pairSecond arityRes))))))))

fn closedEnumFamily? family: String -> Bool
  (not (or (= family "Option") (or (= family "Result") (= family "List"))))

fn checkMatchExhaustiveness heads: (List String) mod: ModuleSummary deps: DepIndex path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (if (listEmpty? heads) acc (let [(firstHead (mt (listHead heads) ((some h) h) ((none) ""))) (uFirst (unionForTag firstHead mod deps))] (mt uFirst ((none) acc) ((some u1) (let [(u1Name (pairFirst u1)) (u1Cases (pairSecond u1)) (mixDiags (fold (fn [(a (List ty/Diagnostic)) (h String)] -> (List ty/Diagnostic) (mt (unionForTag h mod deps) ((none) a) ((some uh) (if (not (= (pairFirst uh) u1Name)) (cons (makeDiag "rule-4" (str "arms mix unions: " u1Name ", " (pairFirst uh)) path) a) a)))) (list) heads))] (if (not (listEmpty? mixDiags)) (listAppend mixDiags acc) (let [(bareHeads (map (fn [(h String)] -> String (if (stringContains? h "/") (let [(p (stringSplit h "/"))] (mt (listGet p 1) ((some m) m) ((none) h))) h)) heads)) (missing (filter (fn [(c String)] -> Bool (not (listContains? bareHeads c))) u1Cases))] (if (and (not (listEmpty? missing)) (closedEnumFamily? u1Name)) (cons (makeDiag "rule-4" (str "match is not exhaustive: " (stringJoin missing ", ") " unhandled") path) acc) acc))))))))

fn hostOperatorArity? head: String given: Int64 -> Bool
  (cond ((or (= head "+") (= head "*")) (>= given 1)) ((= head "-") (= given 1)) (else false))

fn builtinVariadic? name: String -> Bool
  (mt (ty/builtinSig (ty/genericSigName name))
    ((some bsig) (pairFirst (pairSecond bsig)))
    ((none) false))

fn fnHead? h: String mod: ModuleSummary deps: DepIndex -> Bool
  (if (isQualifiedName? h)
    (let [(qp (splitQual h))]
      (mt (modImport mod (pairFirst qp))
        ((some mpath) (mt (resolveDepIn mpath deps) ((ok target) (some? (modFun target (pairSecond qp)))) ((err _) false)))
        ((none) false)))
    (mapHas? mod.funs h))

fn isCtorHead? h: String -> Bool
  (if (isPascalName? h) true (if (isQualifiedName? h) (isPascalName? (pairSecond (splitQual h))) false))

fn findUnqualifiedSchemaInDeps head: String mod: ModuleSummary deps: DepIndex -> (Pair (Option SchemaSummary) (Option ty/Diagnostic))
  (fold (fn [(acc (Pair (Option SchemaSummary) (Option ty/Diagnostic))) (mpath String)] -> (Pair (Option SchemaSummary) (Option ty/Diagnostic))
          (mt (pairFirst acc)
            ((some _) acc)
            ((none)
             (mt (resolveDepIn mpath deps)
               ((ok target)
                (if (not (or (listContains? target.exportedTypes head) (listContains? target.exports head)))
                  acc
                  (mt (modSchema target head)
                    ((some s) (pair (some s) (none)))
                    ((none) acc))))
               ((err _) acc)))))
        (pair (none) (none))
        (mapValues mod.imports))

fn extractCtorValExprs args: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead args) ((none) (list)) ((some _) (let [(valNode (secondExprEmpty args)) (rest (dropTwo args))] (cons valNode (extractCtorValExprs rest)))))

fn exportedFn? target: ModuleSummary member: String -> Bool
  (or (listContains? target.exports member) (and (listContains? target.exportedTypes member) (some? (modFun target member))))

fn checkQualifiedMember v: String alias: String member: String mod: ModuleSummary deps: DepIndex path: String -> (Option ty/Diagnostic)
  (mt (modImport mod alias) ((none) (some (makeDiag "rule-9" (str v ": alias " alias " is not imported") path))) ((some mpath) (mt (resolveDepIn mpath deps) ((err _) (none)) ((ok target) (if (and (not (exportedFn? target member)) (not (mapHas? target.exportedCases member))) (some (makeDiag "rule-9" (str "ERR_NOT_EXPORTED: " member " is not exported by " target.name) path)) (none))))))

fn isReservedIdent? s: String -> Bool
  (or (stringStartsWith? s "agentscript-") (stringContains? s "/agentscript-"))

fn diagReservedPrefix name: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (cons (makeDiag "rule-7" (str name " uses the reserved agentscript- prefix") path) acc)

fn checkHeadExpr headExpr: rd/SExpr scope: (Map String Bool) effectOk: Bool mod: ModuleSummary deps: DepIndex fieldNames: (Map String Bool) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (mt headExpr ((rd/sexprAtom v) (if (isLiteralAtom? v) acc (if (stringStartsWith? v ":") acc (if (stringStartsWith? v ".-") acc (if (isReservedIdent? v) (diagReservedPrefix v path acc) (if (isQualifiedName? v) (let [(qp (splitQual v)) (alias (pairFirst qp)) (member (pairSecond qp))] (mt (checkQualifiedMember v alias member mod deps path) ((some d) (cons d acc)) ((none) acc))) (if (or (mapHas? scope v) (or (mapHas? mod.funs v) (or (mapHas? mod.caseOwner v) (or (some? (findUnqualifiedCaseInDeps v mod deps)) (or (isPreludeTag? v) (or (isSpecialForm? v) (or (some? (ty/builtinSig v)) (ty/genericName? v)))))))) acc (cons (makeDiag "rule-2" (str v " is not defined") path) acc)))))))) (_ acc))

(schema ResolveWorkItem (:f expr rd/SExpr) (:f scope (Map String Bool)) (:f effectOk Bool))

(schema ResolveState (:f work (List ResolveWorkItem)) (:f diags (List ty/Diagnostic)))

fn firstHeadIdent l: (List rd/SExpr) -> String
  (rd/sexprHead (firstExprEmpty l))

fn addLetBinding bparts: (List rd/SExpr) pairAcc: (Pair (Map String Bool) (List ResolveWorkItem)) effectOk: Bool -> (Pair (Map String Bool) (List ResolveWorkItem))
  (let [(bname (firstHeadIdent bparts)) (bval (if (= (listLength bparts) 3) (optionOr (listGet bparts 2) (rd/makeAtom "()")) (secondExprEmpty bparts))) (curSc (pairFirst pairAcc)) (curItems (pairSecond pairAcc))] (pair (mapSet curSc bname true) (cons (ResolveWorkItem :expr bval :scope curSc :effectOk effectOk) curItems)))

fn addLetBindingItems bits: (List rd/SExpr) pairAcc: (Pair (Map String Bool) (List ResolveWorkItem)) effectOk: Bool path: String diags: (List ty/Diagnostic) -> (Pair (Pair (Map String Bool) (List ResolveWorkItem)) (List ty/Diagnostic))
  (let [(res (fold (fn [(st (Pair (Pair (Map String Bool) (List ResolveWorkItem)) (Option String))) (bit rd/SExpr)] -> (Pair (Pair (Map String Bool) (List ResolveWorkItem)) (Option String))
                     (mt (pairSecond st)
                       ((some pending) (pair (addLetBinding (list (rd/makeAtom pending) bit) (pairFirst st) effectOk) (none)))
                       ((none) (mt bit
                                 ((rd/sexprAtom name) (pair (pairFirst st) (some name)))
                                 ((rd/sexprList bparts) (pair (addLetBinding bparts (pairFirst st) effectOk) (none)))
                                 ((rd/sexprVect bparts) (pair (addLetBinding bparts (pairFirst st) effectOk) (none)))
                                 (_ st)))))
                   (pair pairAcc (none)) bits))
        (pairRes (pairFirst res))
        (finalDiags (mt (pairSecond res)
                      ((some _) (cons (makeDiag "ERR_BAD_LET" "odd binding vector" path) diags))
                      ((none) diags)))]
    (pair pairRes finalDiags))

fn enumCaseArity m: ModuleSummary ename: String member: String -> (Option Int64)
  (mt (modEnum m ename) ((some esum) (let [(matching (filter (fn [(c CaseSummary)] -> Bool (= c.name member)) esum.cases))] (mt (listHead matching) ((some mc) (some (listLength mc.params))) ((none) (none))))) ((none) (none)))

fn mapRitems exprs: (List rd/SExpr) scope: (Map String Bool) effectOk: Bool -> (List ResolveWorkItem)
  (map (fn [(e rd/SExpr)] -> ResolveWorkItem (ResolveWorkItem :expr e :scope scope :effectOk effectOk)) exprs)

fn dropTwo l: (List rd/SExpr) -> (List rd/SExpr)
  (safeTail (safeTail l))

fn rResolveTick st: ResolveState tickIdx: Int64 mod: ModuleSummary deps: DepIndex fieldNames: (Map String Bool) path: String -> ResolveState
  (mt (listHead st.work) ((none) st) ((some item) (let [(rest (safeTail st.work)) (expr item.expr) (scope item.scope) (effectOk item.effectOk) (acc st.diags)] (mt expr ((rd/sexprAtom v) (if (isLiteralAtom? v) (ResolveState :work rest :diags acc) (if (stringStartsWith? v ":") (ResolveState :work rest :diags acc) (if (isReservedIdent? v) (ResolveState :work rest :diags (diagReservedPrefix v path acc)) (if (isQualifiedName? v) (let [(qp (splitQual v)) (alias (pairFirst qp)) (member (pairSecond qp))] (mt (checkQualifiedMember v alias member mod deps path) ((some d) (ResolveState :work rest :diags (cons d acc))) ((none) (ResolveState :work rest :diags acc)))) (if (mapHas? scope v) (ResolveState :work rest :diags acc) (if (mapHas? mod.funs v) (ResolveState :work rest :diags acc) (if (mapHas? mod.caseOwner v) (ResolveState :work rest :diags acc) (if (isPreludeTag? v) (ResolveState :work rest :diags acc) (if (isSpecialForm? v) (ResolveState :work rest :diags acc) (mt (ty/builtinSig (ty/genericSigName v)) ((some bsig) (if (pairFirst (pairSecond bsig)) (ResolveState :work rest :diags (cons (makeDiag "builtin-reference" (str v " is a builtin, not a value; wrap it in an fn to pass it") path) acc)) (if (and (isEffectfulBuiltin? v) (not effectOk)) (ResolveState :work rest :diags (cons (makeDiag "rule-12" (str "effectful builtin " v " taken as a value inside a declaration not marked !") path) acc)) (ResolveState :work rest :diags acc)))) ((none) (ResolveState :work rest :diags (cons (if (ty/genericMulti? v) (makeDiag "builtin-reference" (str v " is a builtin, not a value; wrap it in an fn to pass it") path) (makeDiag "rule-2" (str v " is not defined") path)) acc)))))))))))))) ((rd/sexprVect items) (ResolveState :work (listAppend (mapRitems items scope effectOk) rest) :diags acc)) ((rd/sexprList items) (mt (listHead items) ((none) (ResolveState :work rest :diags acc)) ((some h) (let [(headTok (if (rd/isAtom? h) (rd/sexprHead h) "")) (tailArgs (safeTail items))] (cond ((= headTok "let") (let [(bindItems (firstVectItems tailArgs)) (bodyExprs (safeTail tailArgs)) (bindRes (addLetBindingItems bindItems (pair scope (list)) effectOk path acc)) (bindingInfo (pairFirst bindRes)) (dLet (pairSecond bindRes)) (finalLetScope (pairFirst bindingInfo)) (letValItems (listReverse (pairSecond bindingInfo))) (letBodyItems (mapRitems bodyExprs finalLetScope effectOk))] (ResolveState :work (listAppend letValItems (listAppend letBodyItems rest)) :diags dLet))) ((= headTok "if") (ResolveState :work (listAppend (mapRitems tailArgs scope effectOk) rest) :diags acc)) ((= headTok "cond") (let [(condItems (fold (fn [(cacc (List ResolveWorkItem)) (clause rd/SExpr)] -> (List ResolveWorkItem) (mt clause ((rd/sexprList cparts) (let [(chead (firstHeadIdent cparts))] (if (= chead "else") (listAppend cacc (mapRitems (safeTail cparts) scope effectOk)) (listAppend cacc (mapRitems cparts scope effectOk))))) (_ cacc))) (list) tailArgs))] (ResolveState :work (listAppend condItems rest) :diags acc))) ((= headTok "fn") (let [(isBang (and (not (listEmpty? tailArgs)) (= (firstHeadIdent tailArgs) "!"))) (remArgs (if isBang (safeTail tailArgs) tailArgs)) (afterParams (safeTail remArgs)) (bodyNodes (if (and (not (listEmpty? afterParams)) (= (firstHeadIdent afterParams) "->")) (dropTwo afterParams) afterParams)) (paramItems (firstVectItems remArgs)) (fnScope (fold (fn [(sc (Map String Bool)) (p rd/SExpr)] -> (Map String Bool) (mt p ((rd/sexprAtom name) (mapSet sc name true)) ((rd/sexprList parts) (mapSet sc (firstHeadIdent parts) true)) ((rd/sexprVect parts) (mapSet sc (firstHeadIdent parts) true)))) scope paramItems)) (fnBodyItems (mapRitems bodyNodes fnScope (or isBang effectOk)))] (ResolveState :work (listAppend fnBodyItems rest) :diags acc))) ((or (= headTok "match") (= headTok "mt")) (let [(scrutinee (mt (listHead tailArgs) ((some s) s) ((none) (rd/makeAtom "")))) (arms (safeTail tailArgs)) (scrutItem (ResolveWorkItem :expr scrutinee :scope scope :effectOk effectOk)) (family (matchFamilyIx arms mod deps)) (armsRes (fold (fn [(accArms (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List ResolveWorkItem)))) (arm rd/SExpr)] -> (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List ResolveWorkItem))) (mt arm ((rd/sexprList armParts) (let [(pat (mt (listHead armParts) ((some p) p) ((none) (rd/makeAtom "_")))) (armBodies (safeTail armParts)) (patRes (if (ctorPatternAtomIx? pat family mod deps) (pair (pair (list) (some (rd/sexprHead pat))) (pairFirst (pairSecond accArms))) (extractPattern pat mod deps path (invalidArmHead pat mod path (pairFirst (pairSecond accArms)))))) (boundNames (pairFirst (pairFirst patRes))) (optHead (pairSecond (pairFirst patRes))) (hasCatchall (or (pairSecond (pairFirst accArms)) (mt optHead ((none) true) ((some _) false)))) (nextHeads (mt optHead ((some hname) (cons hname (pairFirst (pairFirst accArms)))) ((none) (pairFirst (pairFirst accArms))))) (armScope (addStringsToSet scope boundNames)) (newArmItems (mapRitems armBodies armScope effectOk))] (pair (pair nextHeads hasCatchall) (pair (pairSecond patRes) (listAppend (pairSecond (pairSecond accArms)) newArmItems))))) (_ accArms))) (pair (pair (list) false) (pair acc (list scrutItem))) arms)) (dArms (listAppend (unreachableArmDiagsIx arms family mod deps path false) (if (pairSecond (pairFirst armsRes)) (pairFirst (pairSecond armsRes)) (checkMatchExhaustiveness (pairFirst (pairFirst armsRes)) mod deps path (pairFirst (pairSecond armsRes)))))) (allMatchItems (pairSecond (pairSecond armsRes)))] (ResolveState :work (listAppend allMatchItems rest) :diags dArms))) ((stringStartsWith? headTok ".-") (let [(fname (sliceFrom headTok 2)) (dFname (if (mapHas? fieldNames fname) acc (cons (makeDiag "rule-2" (str "no record in this module has a field " fname) path) acc))) (newItems (mapRitems tailArgs scope effectOk))] (ResolveState :work (listAppend newItems rest) :diags dFname))) ((and (isCtorHead? headTok) (not (fnHead? headTok mod deps))) (let [(schemaInfo (if (isQualifiedName? headTok) (let [(qp (splitQual headTok)) (alias (pairFirst qp)) (member (pairSecond qp))] (mt (modImport mod alias) ((some mpath) (mt (resolveDepIn mpath deps) ((ok target) (if (not (or (listContains? target.exportedTypes member) (mapHas? target.schemas member))) (pair (none) (some (makeDiag "rule-9" (str member " is not an exported type of " target.name) path))) (mt (modSchema target member) ((some s) (pair (some s) (none))) ((none) (pair (none) (some (makeDiag "rule-2" (str member " is not a record type in " target.name) path))))))) ((err _) (pair (none) (none))))) ((none) (pair (none) (some (makeDiag "rule-9" (str headTok ": alias " alias " is not imported") path)))))) (mt (modSchema mod headTok) ((some s) (pair (some s) (none))) ((none) (let [(foundInDeps (findUnqualifiedSchemaInDeps headTok mod deps))] (mt (pairFirst foundInDeps) ((some s) (pair (some s) (none))) ((none) (pair (none) (some (makeDiag "rule-2" (str headTok " is not a record type in this module") path)))))))))) (dCtor (mt (pairSecond schemaInfo) ((some d) (cons d acc)) ((none) acc)))] (mt (pairFirst schemaInfo) ((none) (let [(newItems (mapRitems tailArgs scope effectOk))] (ResolveState :work (listAppend newItems rest) :diags dCtor))) ((some schema) (let [(fieldMap (fold (fn [(fm (Map String FieldSummary)) (f FieldSummary)] -> (Map String FieldSummary) (mapSet fm f.name f)) (mapEmpty) schema.fields)) (fieldsRes (foldCtorArgs tailArgs fieldMap (mapEmpty) schema.name path dCtor)) (givenKeys (pairFirst fieldsRes)) (dFields (pairSecond fieldsRes)) (missing (filter (fn [(f FieldSummary)] -> Bool (and (not f.hasDefault) (not (mapHas? givenKeys f.name)))) schema.fields)) (dMissing (if (not (listEmpty? missing)) (cons (makeDiag "ctor" (str schema.name " is missing " (stringJoin (map (fn [(f FieldSummary)] -> String f.name) missing) ", ")) path) dFields) dFields)) (ctorValExprs (extractCtorValExprs tailArgs)) (newItems (map (fn [(e rd/SExpr)] -> ResolveWorkItem (ResolveWorkItem :expr e :scope scope :effectOk effectOk)) ctorValExprs))] (ResolveState :work (listAppend newItems rest) :diags dMissing)))))) (else (let [(isLiteralCallee (isLiteralAtom? headTok)) (dKwCall (mt (keywordCallHeadDiag headTok path) ((some d) (cons d acc)) ((none) acc))) (dNotCallable (if isLiteralCallee (cons (makeDiag "not-callable" (str headTok " is a literal, not a function") path) dKwCall) dKwCall)) (calleeEffect (if (isEffectfulBuiltin? headTok) true (mt (modFun mod headTok) ((some f) f.effect) ((none) (if (isQualifiedName? headTok) (let [(qp (splitQual headTok)) (alias (pairFirst qp)) (member (pairSecond qp))] (mt (modImport mod alias) ((some mpath) (mt (resolveDepIn mpath deps) ((ok target) (mt (modFun target member) ((some f) f.effect) ((none) false))) ((err _) false))) ((none) false))) false))))) (hasEffectLambda (fold (fn [(ef Bool) (a rd/SExpr)] -> Bool (or ef (mt a ((rd/sexprList aitems) (and (and (= (firstHeadIdent aitems) "fn") (not (listEmpty? (safeTail aitems)))) (= (rd/sexprHead (secondExprEmpty aitems)) "!"))) (_ false)))) false tailArgs)) (totalEffect (or calleeEffect hasEffectLambda)) (dEffect (if (and totalEffect (not effectOk)) (cons (makeDiag "rule-12" "effectful call inside a declaration not marked !" path) dNotCallable) dNotCallable)) (expectedArity (if (mapHas? scope headTok) (none) (mt (modFun mod headTok) ((some f) (some (listLength f.params))) ((none) (if (isQualifiedName? headTok) (let [(qp (splitQual headTok)) (alias (pairFirst qp)) (member (pairSecond qp))] (mt (modImport mod alias) ((some mpath) (mt (resolveDepIn mpath deps) ((ok target) (mt (modFun target member) ((some f) (some (listLength f.params))) ((none) (mt (mapGet target.exportedCases member) ((some ename) (enumCaseArity target ename member)) ((none) (none)))))) ((err _) (none)))) ((none) (none)))) (mt (mapGet mod.caseOwner headTok) ((some ename) (enumCaseArity mod ename headTok)) ((none) (mt (ty/builtinSig (ty/genericSigName headTok)) ((some bsig) (some (if (and (pairFirst (pairSecond bsig)) (= headTok "list")) 0 (listLength (pairFirst bsig))))) ((none) (none)))))))))) (givenCount (listLength tailArgs)) (dArity (mt expectedArity ((some exp) (if (and (if (builtinVariadic? headTok) (< givenCount exp) (not (= exp givenCount))) (not (and (not (mapHas? mod.funs headTok)) (hostOperatorArity? headTok givenCount)))) (cons (makeDiag "arity" (str headTok " takes " (stringFromInt64 exp) " argument(s), given " (stringFromInt64 givenCount)) path) dEffect) dEffect)) ((none) dEffect))) (dHead (checkHeadExpr h scope effectOk mod deps fieldNames path dArity)) (newItems (mapRitems (if (rd/isAtom? h) tailArgs (cons h tailArgs)) scope effectOk))] (ResolveState :work (listAppend newItems rest) :diags dHead))))))))))))

fn rResolveRun st: ResolveState budget: Int64 mod: ModuleSummary deps: DepIndex fieldNames: (Map String Bool) path: String -> ResolveState
  (let [(next (fold (fn [(s ResolveState) (idx Int64)] -> ResolveState (rResolveTick s idx mod deps fieldNames path)) st (range 0 budget)))] (if (listEmpty? next.work) next (rResolveRun next (* budget 2) mod deps fieldNames path)))

fn foldCtorArgs args: (List rd/SExpr) fieldMap: (Map String FieldSummary) given: (Map String Bool) sname: String path: String acc: (List ty/Diagnostic) -> (Pair (Map String Bool) (List ty/Diagnostic))
  (mt (listHead args) ((none) (pair given acc)) ((some keyNode) (let [(valNode (secondExprEmpty args)) (rest (dropTwo args)) (rawKey (rd/sexprHead keyNode)) (kname (if (stringStartsWith? rawKey ":") (sliceFrom rawKey 1) rawKey))] (let [(dKey (if (not (mapHas? fieldMap kname)) (cons (makeDiag "ctor" (str sname " has no field " kname) path) acc) (if (mapHas? given kname) (cons (makeDiag "ctor" (str sname ": duplicate key " kname) path) acc) acc)))] (foldCtorArgs rest fieldMap (mapSet given kname true) sname path dKey)))))

fn collectAllFieldNames mod: ModuleSummary deps: DepIndex -> (Map String Bool)
  (let [(s1 (addStringsToSet (mapSet (mapSet (mapEmpty) "first" true) "second" true) (list "isFile" "isDir" "isSymlink" "size" "mtime" "mode" "exitCode" "stdout" "stderr"))) (s2 (fold (fn [(acc (Map String Bool)) (s SchemaSummary)] -> (Map String Bool) (addFieldsToSet acc s.fields)) s1 (mapValues mod.schemas))) (s3 (fold (fn [(acc (Map String Bool)) (target ModuleSummary)] -> (Map String Bool) (let [(acc1 (addStringsToSet acc (mapKeys target.exportedFields)))] (fold (fn [(facc (Map String Bool)) (s SchemaSummary)] -> (Map String Bool) (addFieldsToSet facc s.fields)) acc1 (mapValues target.schemas)))) s2 (mapValues deps.deps)))] s3)

fn bodyPosAt d: a/DefunNode idx: Int64 -> (Pair Int64 Int64)
  (mt (listGet d.bodyPos idx) ((some p) (pair p.line p.col)) ((none) (pair 1 1)))

fn placeDiags ds: (List ty/Diagnostic) pos: (Pair Int64 Int64) -> (List ty/Diagnostic)
  (map (fn [(d ty/Diagnostic)] -> ty/Diagnostic (ty/Diagnostic :code d.code :message d.message :msg d.msg :line (pairFirst pos) :col (pairSecond pos) :path d.path)) ds)

fn resolveBodyDiagPos expr: rd/SExpr pos: (Pair Int64 Int64) ds: (List ty/Diagnostic) -> (Pair Int64 Int64)
  (let [(calleeDiag (listAny? (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "rule-2") (= d.code "rule-12"))) ds))]
    (mt expr ((rd/sexprList _) (if (and calleeDiag (> (pairSecond pos) 0)) (pair (pairFirst pos) (+ (pairSecond pos) 1)) pos)) (_ pos)))

fn checkDefunBody d: a/DefunNode mod: ModuleSummary deps: DepIndex fieldNames: (Map String Bool) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (let [(paramScope (fold (fn [(sc (Map String Bool)) (p a/Param)] -> (Map String Bool) (mapSet sc p.name true)) (mapEmpty) d.params))]
    (fold (fn [(a (List ty/Diagnostic)) (ie (Pair Int64 rd/SExpr))] -> (List ty/Diagnostic)
            (let [(i (pairFirst ie)) (bodyE (pairSecond ie))
                  (finalSt (rResolveRun (ResolveState :work (list (ResolveWorkItem :expr bodyE :scope paramScope :effectOk (markedFn? d))) :diags (list)) 64 mod deps fieldNames path))
                  (pos (resolveBodyDiagPos bodyE (bodyPosAt d i) finalSt.diags))]
              (listAppend (placeDiags finalSt.diags pos) a)))
          acc (zip (range 0 (listLength d.body)) d.body)))

fn defunPositions forms: (List a/TopForm) -> (Map String (Pair Int64 Int64))
  (fold (fn [(m (Map String (Pair Int64 Int64))) (form a/TopForm)] -> (Map String (Pair Int64 Int64)) (mt form ((a/topDefun d) (mapSet m d.name (bodyPosAt d 0))) (_ m))) (mapEmpty) forms)

fn checkBodies forms: (List a/TopForm) mod: ModuleSummary deps: DepIndex path: String -> (List ty/Diagnostic)
  (let [(fieldNames (collectAllFieldNames mod deps))] (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic) (mt form ((a/topDefun d) (checkDefunBody d mod deps fieldNames path acc)) (_ acc))) (list) forms))

fn checkReservedName name: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (if (isReservedIdent? name) (diagReservedPrefix name path acc) acc)

fn checkNamedItems names: (List String) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (n String)] -> (List ty/Diagnostic) (checkReservedName n path a)) acc names)

fn checkReservedNames forms: (List a/TopForm) path: String -> (List ty/Diagnostic)
  (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic) (mt form ((a/topDefun d) (checkNamedItems (map (fn [(p a/Param)] -> String p.name) d.params) path (checkReservedName d.name path acc))) ((a/topSchema s) (checkNamedItems (map (fn [(f a/AstField)] -> String f.name) s.fields) path (checkReservedName s.name path acc))) ((a/topEnum e) (fold (fn [(a (List ty/Diagnostic)) (c a/EnumCase)] -> (List ty/Diagnostic) (checkNamedItems (map (fn [(p a/Param)] -> String p.name) c.fields) path (checkReservedName c.name path a))) (checkReservedName e.name path acc) e.cases)) ((a/topModule m) (checkNamedItems m.exported path acc)) (_ acc))) (list) forms)

fn resolveModuleIn mod: ModuleSummary forms: (List a/TopForm) deps: DepIndex -> (List ty/Diagnostic)
  (if (not deps.indexed) (list (makeDiag "ERR_INTERNAL" "resolveModuleIn needs an indexed DepIndex (depIndexOf), got a scan" mod.path))
    (let [(p mod.path) (poses (defunPositions forms))] (listAppend (checkReservedNames forms p) (listAppend (checkModuleRules mod poses p) (listAppend (checkImportsAndCycles mod deps p) (listAppend (checkExportClosure mod p) (listAppend (checkTypeAnnotations mod deps poses p) (checkBodies forms mod deps p))))))))

fn resolveModule mod: ModuleSummary forms: (List a/TopForm) deps: (Map String ModuleSummary) -> (List ty/Diagnostic)
  (resolveModuleIn mod forms (depIndexOf deps))

fn checkTypeTree t: ty/Type bound: (Map String Bool) mod: ModuleSummary deps: (Map String ModuleSummary) where: String path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (checkTypeTreeIx t bound mod (depScanOf deps) where path acc)

fn matchFamily arms: (List rd/SExpr) mod: ModuleSummary deps: (Map String ModuleSummary) -> String
  (matchFamilyIx arms mod (depScanOf deps))

fn ctorPatternAtom? pat: rd/SExpr family: String mod: ModuleSummary deps: (Map String ModuleSummary) -> Bool
  (ctorPatternAtomIx? pat family mod (depScanOf deps))

fn unreachableArmDiags arms: (List rd/SExpr) family: String mod: ModuleSummary deps: (Map String ModuleSummary) path: String seenCatchall: Bool -> (List ty/Diagnostic)
  (unreachableArmDiagsIx arms family mod (depScanOf deps) path seenCatchall)
