(module asl-ir/link :x [LinkUnit LinkAcc loadClosure! linkUnits linkWith! linkEntry! linkWithBare! linkEntryBare! lowerSourceWith lowerSourceLinked! preludePath lowerPrelude importForms firstByName firstRecordByName allFunctions emptyUnit nativeOverlayDir overlayUnit! overlayUnitAt! linkUnitsWith linkUnitsWithBareEntry rewriteModuleBuiltins rewriteModuleBuiltinsAgainst definedNames functionBuiltinRefs] :i [(asl-ir/types :a ty) (asl-ir/lower :a low) (asl-ir/verify :a vfy) (asl-parser/ast :a ast) (asl-checker/resolve :a r)])

(schema LinkUnit
  (:f path String)
  (:f name String)
  (:f forms (List ast/TopForm))
  (:f positions (Map String String))
  (:f imports (List (Pair String String))))

(schema LoadState
  (:f units (List LinkUnit))
  (:f seen (Map String Bool))
  (:f diags (List ty/IrDiag))
  (:f index r/ModIndex))

(schema LinkAcc
  (:f strings (List String))
  (:f modules (List ty/SsaModule))
  (:f requested (List String))
  (:f diags (List ty/IrDiag)))

fn revOnto xs: (List T) acc: (List T) -> (List T)
  (mt (listHead xs) ((some x) (revOnto (optionOr (listTail xs) (list)) (cons x acc))) ((none) acc))

fn concatOnto rlists: (List (List T)) acc: (List T) -> (List T)
  (mt (listHead rlists) ((some xs) (concatOnto (optionOr (listTail rlists) (list)) (listAppend xs acc))) ((none) acc))

fn concatLists lists: (List (List T)) -> (List T)
  (concatOnto (listReverse lists) (list))

fn preludePath -> String
  "asl/prelude/prelude.asl"

fn lastSegment path: String -> String
  (optionOr (listGet (stringSplit path "/") (- (listLength (stringSplit path "/")) 1)) path)

fn importAlias imp: (Pair String String) -> String
  (if (stringEmpty? (pairSecond imp)) (lastSegment (pairFirst imp)) (pairSecond imp))

fn headerOf forms: (List ast/TopForm) -> (Option ast/ModuleNode)
  (fold (fn [(acc (Option ast/ModuleNode)) (t ast/TopForm)] -> (Option ast/ModuleNode)
          (mt acc ((some _) acc) ((none) (mt t ((ast/topModule m) (some m)) ((ast/topSchema _) acc) ((ast/topEnum _) acc) ((ast/topDefun _) acc) ((ast/topExpr _) acc)))))
        (none) forms)

fn ! realOrSelf! path: String -> String
  (mt (realPath path) ((ok p) p) ((err _) path))

fn ! resolveImports! importer: String path: String imps: (List (Pair String String)) acc: (List (Pair String String)) diags: (List ty/IrDiag) ix: r/ModIndex -> (Pair (Result (List (Pair String String)) (List ty/IrDiag)) r/ModIndex)
  (mt (listHead imps)
    ((none) (pair (if (listEmpty? diags) (ok (listReverse acc)) (err (listReverse diags))) ix))
    ((some imp) (let [(rest (optionOr (listTail imps) (list)))]
                  (if (= (pairFirst imp) "sys")
                    (resolveImports! importer path rest acc diags ix)
                    (let [(res (r/resolveImport! importer (pairFirst imp) ix))
                          (found (mt res.status ((r/resOk) true) ((r/resDeprecated) true) (_ false)))]
                      (if found
                        (resolveImports! importer path rest (cons (pair (importAlias imp) res.path) acc) diags res.index)
                        (resolveImports! importer path rest acc
                          (cons (ty/makeIrDiag "ERR_LINK_UNRESOLVED_IMPORT" (str path " imports " (pairFirst imp) res.note) path) diags)
                          res.index)))))))

fn parseDiag pe: ast/ParseError locus: String -> ty/IrDiag
  (if (stringStartsWith? pe.msg "ERR_DEPTH ")
    (ty/makeIrDiag "ERR_DEPTH" (optionOr (stringSlice pe.msg 10 (stringLength pe.msg)) pe.msg) locus)
    (ty/makeIrDiag "ERR_LOWER_PARSE" pe.msg locus))

fn ! readUnit! path: String ix: r/ModIndex -> (Pair (Result LinkUnit (List ty/IrDiag)) r/ModIndex)
  (mt (fileRead path)
    ((err _) (pair (err (list (ty/makeIrDiag "ERR_LINK_READ" (str "cannot read " path) path))) ix))
    ((ok src) (mt (ast/parse src)
                ((err pe) (pair (err (list (parseDiag pe (str path ":" pe.line ":" pe.col)))) ix))
                ((ok forms) (mt (headerOf forms)
                              ((none) (pair (err (list (ty/makeIrDiag "ERR_LOWER_NO_MODULE" (str path " has no module header") path))) ix))
                              ((some m) (let [(resolved (resolveImports! (realOrSelf! path) path m.imports (list) (list) ix))]
                                          (pair (mt (pairFirst resolved)
                                                  ((err ds) (err ds))
                                                  ((ok imports) (ok (LinkUnit :path path :name m.path :forms forms :positions (low/declPositions src) :imports imports))))
                                                (pairSecond resolved)))))))))

fn ! visitAll! st: LoadState paths: (List String) -> LoadState
  (mt (listHead paths)
    ((none) st)
    ((some p) (visitAll! (visit! st p) (optionOr (listTail paths) (list)))))

fn ! visit! st: LoadState path: String -> LoadState
  (let [(key (realOrSelf! path))]
    (if (mapHas? st.seen key)
      st
      (let [(read (readUnit! path st.index))
            (marked (with st :seen (mapSet st.seen key true) :index (pairSecond read)))]
        (mt (pairFirst read)
          ((err ds) (LoadState :units marked.units :seen marked.seen :diags (revOnto ds marked.diags) :index marked.index))
          ((ok u) (let [(after (visitAll! marked (map (fn [(imp (Pair String String))] -> String (pairSecond imp)) u.imports)))]
                    (LoadState :units (cons u after.units) :seen after.seen :diags after.diags :index after.index)))))))

fn duplicateModules units: (List LinkUnit) -> (List ty/IrDiag)
  (listReverse
    (pairFirst
      (fold (fn [(st (Pair (List ty/IrDiag) (Map String LinkUnit))) (u LinkUnit)] -> (Pair (List ty/IrDiag) (Map String LinkUnit))
              (mt (mapGet (pairSecond st) u.name)
                ((some v) (pair (cons (ty/makeIrDiag "ERR_LINK_DUPLICATE_MODULE" (str "module " u.name " is declared by both " v.path " and " u.path) u.path) (pairFirst st)) (pairSecond st)))
                ((none) (pair (pairFirst st) (mapSet (pairSecond st) u.name u)))))
            (pair (list) (mapEmpty)) units)))

fn reservedPreludeNameDiags units: (List LinkUnit) -> (List ty/IrDiag)
  (map (fn [(u LinkUnit)] -> ty/IrDiag (ty/makeIrDiag "ERR_LINK_RESERVED_MODULE_NAME" (str "module name 'prelude' is reserved for the designated prelude every module links against; rename the module declared in " u.path) u.path))
       (filter (fn [(u LinkUnit)] -> Bool (and (= u.name "prelude") (not (or (= u.path (preludePath)) (stringEndsWith? u.path (str "/" (preludePath))))))) units))

fn ! loadClosure! entryPath: String -> (Result (List LinkUnit) (List ty/IrDiag))
  (let [(st (visit! (LoadState :units (list) :seen (mapEmpty) :diags (list) :index (r/emptyModIndex)) entryPath))
        (units (listReverse st.units))
        (diags (listAppend (listAppend (listReverse st.diags) (duplicateModules units)) (reservedPreludeNameDiags units)))]
    (if (listEmpty? diags) (ok units) (err diags)))

fn importForms units: (List LinkUnit) u: LinkUnit -> (Map String (List ast/TopForm))
  (fold (fn [(acc (Map String (List ast/TopForm))) (imp (Pair String String))] -> (Map String (List ast/TopForm))
          (mt (listHead (filter (fn [(v LinkUnit)] -> Bool (= v.path (pairSecond imp))) units))
            ((some v) (mapSet acc (pairFirst imp) v.forms))
            ((none) acc)))
        (mapEmpty) u.imports)

fn absorb acc: LinkAcc res: (Result ty/SsaModule (List ty/IrDiag)) -> LinkAcc
  (mt res
    ((ok m) (LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested acc.requested :diags acc.diags))
    ((err ds) (with acc :diags (listAppend acc.diags ds))))

fn lowerUnitAs units: (List LinkUnit) prelude: LinkUnit acc: LinkAcc u: LinkUnit prefix: String -> LinkAcc
  (absorb acc (low/lowerLinkedAs u.forms u.positions
                               (low/LinkScope :path u.path :imports (importForms units u) :prelude prelude.forms :strings acc.strings :only (none)) prefix))

fn lowerUnit units: (List LinkUnit) prelude: LinkUnit acc: LinkAcc u: LinkUnit -> LinkAcc
  (lowerUnitAs units prelude acc u u.name)

fn opRefs op: ty/SsaOp -> (List String)
  (mt op
    ((ty/opCall callee _) (list callee))
    ((ty/opMakeClosure callee _) (list callee))
    (_ (list)))

fn functionRefs f: ty/SsaFunction -> (List String)
  (listReverse
    (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
            (fold (fn [(names (List String)) (i ty/SsaInstr)] -> (List String) (revOnto (opRefs i.op) names)) acc b.instrs))
          (list) f.blocks))

fn allFunctions modules: (List ty/SsaModule) -> (List ty/SsaFunction)
  (concatLists (map (fn [(m ty/SsaModule)] -> (List ty/SsaFunction) m.functions) modules))

fn dedupe names: (List String) -> (List String)
  (listReverse
    (pairFirst
      (fold (fn [(st (Pair (List String) (Map String Bool))) (n String)] -> (Pair (List String) (Map String Bool))
              (if (mapHas? (pairSecond st) n) st (pair (cons n (pairFirst st)) (mapSet (pairSecond st) n true))))
            (pair (list) (mapEmpty)) names)))

fn nameSet names: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (n String)] -> (Map String Bool) (mapSet m n true)) (mapEmpty) names)

fn preludeNeeds preludeName: String acc: LinkAcc -> (List String)
  (let [(prefix (str preludeName "."))
        (refs (concatLists (map functionRefs (allFunctions acc.modules))))
        (defined (nameSet (map (fn [(f ty/SsaFunction)] -> String f.name) (allFunctions (filter (fn [(m ty/SsaModule)] -> Bool (= m.name preludeName)) acc.modules)))))
        (requested (nameSet acc.requested))
        (wanted (filter (fn [(n String)] -> Bool (and (stringStartsWith? n prefix) (not (mapHas? defined n)) (not (mapHas? requested n)))) (dedupe refs)))]
    (map (fn [(n String)] -> String (optionOr (stringSlice n (stringLength prefix) (stringLength n)) "")) wanted))

fn lowerPrelude prelude: LinkUnit acc: LinkAcc -> LinkAcc
  (let [(needs (preludeNeeds prelude.name acc))]
    (if (or (listEmpty? needs) (not (listEmpty? acc.diags)))
      acc
      (lowerPrelude prelude
        (absorb (with acc :requested (listAppend acc.requested (map (fn [(n String)] -> String (str prelude.name "." n)) needs)))
                (low/lowerLinked prelude.forms prelude.positions
                                 (low/LinkScope :path prelude.path :imports (mapEmpty) :prelude (list) :strings acc.strings :only (some needs)))))))

fn nativeOverlayDir -> String
  "asl/prelude/native/"

fn ! overlayTopForms! path: String -> (Result (List ast/TopForm) (List ty/IrDiag))
  (mt (fileRead path)
    ((err _) (err (list (ty/makeIrDiag "ERR_LINK_READ" (str "cannot read native overlay file " path) path))))
    ((ok src) (mt (ast/parse src)
                ((err pe) (err (list (ty/makeIrDiag "ERR_LOWER_PARSE" pe.msg (str path ":" pe.line ":" pe.col)))))
                ((ok forms) (ok (filter (fn [(t ast/TopForm)] -> Bool (mt t ((ast/topModule _) false) ((ast/topExpr _) false) (_ true))) forms))))))

fn ! overlayFormsAll! dir: String names: (List String) -> (Result (List ast/TopForm) (List ty/IrDiag))
  (let [(results (map (fn [(n String)] -> (Result (List ast/TopForm) (List ty/IrDiag)) (overlayTopForms! (str dir n))) names))
        (diags (fold (fn [(acc (List ty/IrDiag)) (r (Result (List ast/TopForm) (List ty/IrDiag)))] -> (List ty/IrDiag) (mt r ((ok _) acc) ((err ds) (listAppend acc ds)))) (list) results))]
    (if (listEmpty? diags)
      (ok (fold (fn [(acc (List ast/TopForm)) (r (Result (List ast/TopForm) (List ty/IrDiag)))] -> (List ast/TopForm) (mt r ((ok fs) (listAppend acc fs)) ((err _) acc))) (list) results))
      (err diags)))

fn nativeModuleHeader -> ast/TopForm
  (ast/topModule (ast/ModuleNode :path "native" :docstring "" :exported (list) :imports (list) :defs (list)))

fn ! overlayUnitAt! dir: String -> (Result LinkUnit (List ty/IrDiag))
  (mt (dirList dir)
    ((err _) (if (fileExists? dir)
               (err (list (ty/makeIrDiag "ERR_LINK_READ" (str "cannot list native overlay directory " dir) dir)))
               (ok (LinkUnit :path dir :name "native" :forms (list (nativeModuleHeader)) :positions (mapEmpty) :imports (list)))))
    ((ok entries) (mt (overlayFormsAll! dir (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) entries))
                    ((err ds) (err ds))
                    ((ok forms) (ok (LinkUnit :path dir :name "native" :forms (cons (nativeModuleHeader) forms) :positions (mapEmpty) :imports (list)))))))

fn ! overlayUnit! -> (Result LinkUnit (List ty/IrDiag))
  (overlayUnitAt! (nativeOverlayDir))


fn builtinRefs op: ty/SsaOp -> (List String)
  (mt op ((ty/opBuiltin name _) (list name)) (_ (list)))

fn functionBuiltinRefs f: ty/SsaFunction -> (List String)
  (listReverse
    (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
            (fold (fn [(names (List String)) (i ty/SsaInstr)] -> (List String) (revOnto (builtinRefs i.op) names)) acc b.instrs))
          (list) f.blocks))

fn topFormName t: ast/TopForm -> (Option String)
  (mt t ((ast/topDefun d) (some d.name)) (_ (none)))

fn definedNames unit: LinkUnit -> (List String)
  (listReverse
    (fold (fn [(acc (List String)) (t ast/TopForm)] -> (List String)
            (mt (topFormName t) ((some n) (cons n acc)) ((none) acc)))
          (list) unit.forms))

fn builtinSeeds unit: LinkUnit acc: LinkAcc -> (List String)
  (let [(defined (nameSet (definedNames unit)))
        (requested (nameSet acc.requested))
        (used (dedupe (concatLists (map functionBuiltinRefs (allFunctions acc.modules)))))]
    (filter (fn [(n String)] -> Bool (and (mapHas? defined n) (not (mapHas? requested (str unit.name "." n))))) used))

fn lowerExtra unit: LinkUnit visible: LinkUnit acc: LinkAcc -> LinkAcc
  (let [(needs (preludeNeeds unit.name acc))]
    (if (or (listEmpty? needs) (not (listEmpty? acc.diags)))
      acc
      (lowerExtra unit visible
        (absorb (with acc :requested (listAppend acc.requested (map (fn [(n String)] -> String (str unit.name "." n)) needs)))
                (low/lowerLinked unit.forms unit.positions
                                 (low/LinkScope :path unit.path :imports (mapEmpty) :prelude visible.forms :strings acc.strings :only (some needs)))))))

fn seedExtend unit: LinkUnit visible: LinkUnit acc: LinkAcc -> (Pair LinkAcc (List String))
  (let [(seeds (builtinSeeds unit acc))]
    (if (or (listEmpty? seeds) (not (listEmpty? acc.diags)))
      (pair acc (list))
      (pair (lowerExtra unit visible
              (absorb (with acc :requested (listAppend acc.requested (map (fn [(n String)] -> String (str unit.name "." n)) seeds)))
                      (low/lowerLinked unit.forms unit.positions
                                       (low/LinkScope :path unit.path :imports (mapEmpty) :prelude visible.forms :strings acc.strings :only (some seeds)))))
            seeds)))

fn builtinRounds native: LinkUnit prelude: LinkUnit acc: LinkAcc -> LinkAcc
  (let [(nativeSeeded (seedExtend native prelude acc))
        (preludeSeeded (seedExtend prelude prelude (lowerPrelude prelude (pairFirst nativeSeeded))))
        (next (pairFirst preludeSeeded))]
    (if (or (not (listEmpty? next.diags)) (and (listEmpty? (pairSecond nativeSeeded)) (listEmpty? (pairSecond preludeSeeded))))
      next
      (builtinRounds native prelude next)))

fn builtinTargets native: LinkUnit prelude: LinkUnit acc: LinkAcc -> (Map String String)
  (let [(functions (allFunctions acc.modules))
        (linked (nameSet (map (fn [(f ty/SsaFunction)] -> String f.name) functions)))
        (used (dedupe (concatLists (map functionBuiltinRefs functions))))
        (nativeDefined (nameSet (definedNames native)))
        (preludeDefined (nameSet (definedNames prelude)))
        (claim (fn [(unitName String) (defined (Map String Bool)) (n String)] -> (Option String)
                 (let [(q (str unitName "." n))] (if (and (mapHas? defined n) (mapHas? linked q)) (some q) (none)))))]
    (fold (fn [(m (Map String String)) (n String)] -> (Map String String)
            (mt (claim native.name nativeDefined n)
              ((some q) (mapSet m n q))
              ((none) (mt (claim prelude.name preludeDefined n) ((some q) (mapSet m n q)) ((none) m)))))
          (mapEmpty) used))

(schema RewriteAcc (:f instrs (List ty/SsaInstr)) (:f next Int64))

fn freshTemp n: Int64 -> String
  (str "%ovl" (stringFromInt64 n))

fn coerceArgRewrite acc: RewriteAcc v: String want: ty/SsaTy -> (Pair RewriteAcc String)
  (if (not (ty/ssaIsRaw? want))
    (pair acc v)
    (let [(dest (freshTemp acc.next))]
      (pair (RewriteAcc :instrs (cons (ty/ssaInstr dest want (ty/opUnbox v)) acc.instrs) :next (+ acc.next 1)) dest)))

fn coerceArgsFrom acc: RewriteAcc args: (List String) params: (List ty/SsaParam) out: (List String) -> (Pair RewriteAcc (List String))
  (mt (listHead args)
    ((none) (pair acc (listReverse out)))
    ((some a) (let [(p (optionOr (listHead params) (ty/ssaParam "" (ty/tyVal))))
                    (c (coerceArgRewrite acc a p.ty))]
                (coerceArgsFrom (pairFirst c) (optionOr (listTail args) (list)) (optionOr (listTail params) (list)) (cons (pairSecond c) out)))))

fn coerceArgsRewrite acc: RewriteAcc args: (List String) params: (List ty/SsaParam) -> (Pair RewriteAcc (List String))
  (coerceArgsFrom acc args params (list))


fn rewriteOne resolved: (Map String String) fnMap: (Map String ty/SsaFunction) acc: RewriteAcc ins: ty/SsaInstr -> RewriteAcc
  (mt ins.op
    ((ty/opBuiltin name args)
      (mt (mapGet resolved name)
        ((none) (with acc :instrs (cons ins acc.instrs)))
        ((some callee)
          (mt (mapGet fnMap callee)
            ((none) (with acc :instrs (cons ins acc.instrs)))
            ((some f)
              (let [(cargs (coerceArgsRewrite acc args f.params))
                    (afterArgs (pairFirst cargs))
                    (newArgs (pairSecond cargs))]
                (if (ty/ssaIsRaw? f.retTy)
                  (let [(tmp (freshTemp afterArgs.next))]
                    (RewriteAcc :instrs (cons (ty/ssaInstr ins.dest ins.ty (ty/opBox tmp))
                                          (cons (ty/ssaInstr tmp f.retTy (ty/opCall callee newArgs)) afterArgs.instrs))
                                :next (+ afterArgs.next 1)))
                  (RewriteAcc :instrs (cons (ty/ssaInstr ins.dest ins.ty (ty/opCall callee newArgs)) afterArgs.instrs)
                              :next afterArgs.next))))))))
    (_ (with acc :instrs (cons ins acc.instrs))))

fn rewriteBlock resolved: (Map String String) fnMap: (Map String ty/SsaFunction) next: Int64 b: ty/SsaBlock -> (Pair ty/SsaBlock Int64)
  (let [(res (fold (fn [(a RewriteAcc) (i ty/SsaInstr)] -> RewriteAcc (rewriteOne resolved fnMap a i)) (RewriteAcc :instrs (list) :next next) b.instrs))]
    (pair (ty/ssaBlock b.label b.params (listReverse res.instrs) b.term) res.next))

fn rewriteFunction resolved: (Map String String) fnMap: (Map String ty/SsaFunction) f: ty/SsaFunction -> ty/SsaFunction
  (let [(res (fold (fn [(st (Pair (List ty/SsaBlock) Int64)) (b ty/SsaBlock)] -> (Pair (List ty/SsaBlock) Int64)
                     (let [(rb (rewriteBlock resolved fnMap (pairSecond st) b))]
                       (pair (cons (pairFirst rb) (pairFirst st)) (pairSecond rb))))
                   (pair (list) 0) f.blocks))]
    (ty/ssaFunction f.name f.captures f.params f.retTy (listReverse (pairFirst res))))

fn fnMapOf m: ty/SsaModule -> (Map String ty/SsaFunction)
  (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (mapSet acc f.name f)) (mapEmpty) m.functions)

fn rewriteModuleBuiltins resolved: (Map String String) m: ty/SsaModule -> ty/SsaModule
  (if (listEmpty? (mapKeys resolved))
    m
    (let [(fnMap (fnMapOf m))]
      (ty/ssaModule m.name m.strings m.types m.records m.externs m.globals
                    (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rewriteFunction resolved fnMap f)) m.functions))))

fn rewriteModuleBuiltinsAgainst resolved: (Map String String) callees: (List ty/SsaFunction) m: ty/SsaModule -> ty/SsaModule
  (if (listEmpty? (mapKeys resolved))
    m
    (let [(fnMap (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (mapSet acc f.name f)) (fnMapOf m) callees))]
      (ty/ssaModule m.name m.strings m.types m.records m.externs m.globals
                    (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rewriteFunction resolved fnMap f)) m.functions))))

fn typesUsed functions: (List ty/SsaFunction) -> (List String)
  (listReverse
    (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
            (fold (fn [(names (List String)) (b ty/SsaBlock)] -> (List String)
                    (revOnto (mt b.term ((ty/termSwitch _ tn _ _) (list tn)) (_ (list)))
                             (fold (fn [(ns (List String)) (i ty/SsaInstr)] -> (List String) (mt i.op ((ty/opConstruct tn _ _) (cons tn ns)) (_ ns))) names b.instrs)))
                  acc f.blocks))
          (list) functions))

fn firstByName decls: (List ty/SsaTypeDecl) -> (List ty/SsaTypeDecl)
  (listReverse
    (pairFirst
      (fold (fn [(st (Pair (List ty/SsaTypeDecl) (Map String Bool))) (d ty/SsaTypeDecl)] -> (Pair (List ty/SsaTypeDecl) (Map String Bool))
              (if (mapHas? (pairSecond st) d.name) st (pair (cons d (pairFirst st)) (mapSet (pairSecond st) d.name true))))
            (pair (list) (mapEmpty)) decls)))

fn firstRecordByName decls: (List ty/SsaRecordDecl) -> (List ty/SsaRecordDecl)
  (listReverse
    (pairFirst
      (fold (fn [(st (Pair (List ty/SsaRecordDecl) (Map String Bool))) (d ty/SsaRecordDecl)] -> (Pair (List ty/SsaRecordDecl) (Map String Bool))
              (if (mapHas? (pairSecond st) d.name) st (pair (cons d (pairFirst st)) (mapSet (pairSecond st) d.name true))))
            (pair (list) (mapEmpty)) decls)))

fn firstExternByName decls: (List ty/SsaExtern) -> (List ty/SsaExtern)
  (listReverse
    (pairFirst
      (fold (fn [(st (Pair (List ty/SsaExtern) (Map String Bool))) (d ty/SsaExtern)] -> (Pair (List ty/SsaExtern) (Map String Bool))
              (if (mapHas? (pairSecond st) d.name) st (pair (cons d (pairFirst st)) (mapSet (pairSecond st) d.name true))))
            (pair (list) (mapEmpty)) decls)))

fn merge name: String preludeName: String acc: LinkAcc -> ty/SsaModule
  (let [(modules acc.modules)
        (functions (allFunctions modules))
        (fnNames (nameSet (map (fn [(f ty/SsaFunction)] -> String f.name) functions)))
        (used (nameSet (typesUsed functions)))
        (declared (concatLists (map (fn [(m ty/SsaModule)] -> (List ty/SsaTypeDecl)
                                      (if (= m.name preludeName) (filter (fn [(d ty/SsaTypeDecl)] -> Bool (mapHas? used d.name)) m.types) m.types))
                                    modules)))
        (records (concatLists (map (fn [(m ty/SsaModule)] -> (List ty/SsaRecordDecl) m.records) modules)))
        (externs (concatLists (map (fn [(m ty/SsaModule)] -> (List ty/SsaExtern) m.externs) modules)))
        (filteredExterns (firstExternByName (filter (fn [(e ty/SsaExtern)] -> Bool (not (mapHas? fnNames e.name))) externs)))
        (globals (concatLists (map (fn [(m ty/SsaModule)] -> (List ty/SsaGlobal) m.globals) modules)))]
    (ty/ssaModule name acc.strings (firstByName declared) (firstRecordByName records) filteredExterns globals functions))

fn duplicateFunctions acc: LinkAcc -> (List ty/IrDiag)
  (let [(names (map (fn [(f ty/SsaFunction)] -> String f.name) (allFunctions acc.modules)))
        (counts (fold (fn [(m (Map String Int64)) (n String)] -> (Map String Int64) (mapSet m n (+ (optionOr (mapGet m n) 0) 1))) (mapEmpty) names))]
    (map (fn [(n String)] -> ty/IrDiag (ty/makeIrDiag "ERR_LINK_DUPLICATE_FUNCTION" (str "function " n " is defined more than once in the linked module") n))
         (filter (fn [(n String)] -> Bool (> (optionOr (mapGet counts n) 0) 1)) (dedupe names))))

fn preludeCouldResolve? d: ty/IrDiag -> Bool
  (or (= d.code "ERR_LOWER_UNSUPPORTED") (= d.code "ERR_LOWER_UNKNOWN_SYMBOL"))

fn emptyUnit name: String -> LinkUnit
  (LinkUnit :path "" :name name :forms (list) :positions (mapEmpty) :imports (list))

fn preludeDiagsOf preludeRes: (Result LinkUnit (List ty/IrDiag)) -> (List ty/IrDiag)
  (mt preludeRes ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> ty/IrDiag (ty/makeIrDiag "ERR_LINK_PRELUDE" (str "prelude functions are not visible: " d.code " " d.message) d.locus)) ds)))

fn ! linkUnits units: (List LinkUnit) preludeRes: (Result LinkUnit (List ty/IrDiag)) -> (Result ty/SsaModule (List ty/IrDiag))
  (linkUnitsWith units preludeRes (overlayUnit!))

fn finishLink units: (List LinkUnit) prelude: LinkUnit entry: LinkUnit lowered: LinkAcc overlayRes: (Result LinkUnit (List ty/IrDiag)) preludeRes: (Result LinkUnit (List ty/IrDiag)) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(withPrelude (lowerPrelude prelude lowered))
        (native (mt overlayRes ((ok u) u) ((err _) (emptyUnit "native"))))
        (withBuiltin (builtinRounds native prelude withPrelude))
        (resolved (builtinTargets native prelude withBuiltin))
        (preludeDiags (preludeDiagsOf preludeRes))]
    (cond
      ((err? overlayRes) (err (mt overlayRes ((ok _) (list)) ((err ds) ds))))
      ((not (listEmpty? withBuiltin.diags))
        (err (listAppend withBuiltin.diags (if (listAny? preludeCouldResolve? withBuiltin.diags) preludeDiags (list)))))
      ((not (listEmpty? (duplicateFunctions withBuiltin))) (err (duplicateFunctions withBuiltin)))
      (else (let [(m (rewriteModuleBuiltins resolved (merge entry.name prelude.name withBuiltin)))]
               (mt (vfy/verifySsa m)
                 ((err ds) (err ds))
                 ((ok _) (ok m)))))))

fn linkUnitsWith units: (List LinkUnit) preludeRes: (Result LinkUnit (List ty/IrDiag)) overlayRes: (Result LinkUnit (List ty/IrDiag)) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(prelude (mt preludeRes ((ok p) p) ((err _) (emptyUnit "prelude"))))
        (entry (optionOr (listGet units (- (listLength units) 1)) prelude))
        (lowered (fold (fn [(acc LinkAcc) (u LinkUnit)] -> LinkAcc (lowerUnit units prelude acc u)) (LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))]
    (finishLink units prelude entry lowered overlayRes preludeRes))

fn linkUnitsWithBareEntry units: (List LinkUnit) preludeRes: (Result LinkUnit (List ty/IrDiag)) overlayRes: (Result LinkUnit (List ty/IrDiag)) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(prelude (mt preludeRes ((ok p) p) ((err _) (emptyUnit "prelude"))))
        (entry (optionOr (listGet units (- (listLength units) 1)) prelude))
        (lowered (fold (fn [(acc LinkAcc) (u LinkUnit)] -> LinkAcc (lowerUnitAs units prelude acc u (if (= u.path entry.path) "" u.name))) (LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))]
    (finishLink units prelude entry lowered overlayRes preludeRes))

fn ! linkWith! entryPath: String preludeFile: String -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (loadClosure! entryPath)
    ((err ds) (err ds))
    ((ok units) (linkUnits units (pairFirst (readUnit! preludeFile (r/emptyModIndex))))))

fn ! linkEntry! entryPath: String -> (Result ty/SsaModule (List ty/IrDiag))
  (linkWith! entryPath (preludePath))

fn ! linkWithBare! entryPath: String preludeFile: String -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (loadClosure! entryPath)
    ((err ds) (err ds))
    ((ok units) (linkUnitsWithBareEntry units (pairFirst (readUnit! preludeFile (r/emptyModIndex))) (overlayUnit!))))

fn ! linkEntryBare! entryPath: String -> (Result ty/SsaModule (List ty/IrDiag))
  (linkWithBare! entryPath (preludePath))

fn preludeUnitOf preludeSrc: String -> (Result LinkUnit (List ty/IrDiag))
  (mt (ast/parse preludeSrc)
    ((err pe) (err (list (ty/makeIrDiag "ERR_LOWER_PARSE" pe.msg (str (preludePath) ":" pe.line ":" pe.col)))))
    ((ok forms) (mt (headerOf forms)
                  ((none) (err (list (ty/makeIrDiag "ERR_LOWER_NO_MODULE" (str (preludePath) " has no module header") (preludePath)))))
                  ((some m) (ok (LinkUnit :path (preludePath) :name m.path :forms forms :positions (low/declPositions preludeSrc) :imports (list)))))))

fn lowerSourceAgainst src: String preludeRes: (Result LinkUnit (List ty/IrDiag)) -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (ast/parse src)
    ((err e) (err (list (ty/makeIrDiag "ERR_LOWER_PARSE" e.msg (str e.line ":" e.col)))))
    ((ok forms) (let [(prelude (mt preludeRes ((ok p) p) ((err _) (emptyUnit "prelude"))))
                      (lowered (absorb (LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) (low/lowerWithPrelude forms (low/declPositions src) prelude.forms)))
                      (withPrelude (lowerPrelude prelude lowered))
                      (name (mt (headerOf forms) ((some m) m.path) ((none) "")))]
                  (cond
                    ((not (listEmpty? withPrelude.diags))
                      (err (listAppend withPrelude.diags (if (listAny? preludeCouldResolve? withPrelude.diags) (preludeDiagsOf preludeRes) (list)))))
                    ((not (listEmpty? (duplicateFunctions withPrelude))) (err (duplicateFunctions withPrelude)))
                    (else (ok (merge name prelude.name withPrelude)))))))

fn lowerSourceWith src: String preludeSrc: String -> (Result ty/SsaModule (List ty/IrDiag))
  (lowerSourceAgainst src (preludeUnitOf preludeSrc))

fn ! lowerSourceLinked! src: String -> (Result ty/SsaModule (List ty/IrDiag))
  (lowerSourceAgainst src (mt (fileRead (preludePath))
                            ((ok text) (preludeUnitOf text))
                            ((err _) (err (list (ty/makeIrDiag "ERR_LINK_READ" (str "cannot read " (preludePath)) (preludePath)))))))
