(module asl-checker/check :x [InferState Deferred checkModule checkModuleIn checkModuleSource checkSource checkFile! schemaOfCtor elaborateScript needsElaboration?] :i [(types :a ty) (unify :a u) (resolve :a r) (ast :a a) (reader :a rd) (tailPos :a tp) (constAssert :a ca) (foreign :a ff) (numKinds :a nk)])

(schema InferState (:f subst (Map Int64 ty/Type)) (:f nextVar Int64) (:f intSites (List (pair String Int64))) (:f mapSites (List (pair ty/Type String))) (:f diags (List ty/Diagnostic)) (:f deferred (List Deferred)))

(schema Deferred (:f name String) (:f recv ty/Type) (:f args (List ty/Type)) (:f result ty/Type))

fn makeInferState -> InferState
  (InferState :subst (mapEmpty) :nextVar 1 :intSites (list) :mapSites (list) :diags (list) :deferred (list))

fn freshVar st: InferState kind: String -> (Pair ty/Type InferState)
  (let [(nid st.nextVar)] (pair (ty/tyVar nid kind) (with st :nextVar (+ nid 1))))

fn addDiag st: InferState code: String msg: String path: String -> InferState
  (with st :diags (cons (ty/Diagnostic :code code :message msg :msg msg :line 1 :col 1 :path path) st.diags))

fn setDiags st: InferState ds: (List ty/Diagnostic) -> InferState
  (with st :diags ds)

fn placeFresh ds: (List ty/Diagnostic) before: Int64 pos: (Pair Int64 Int64) -> (List ty/Diagnostic)
  (let [(n (listLength ds)) (k (- n before))] (if (<= k 0) ds (listAppend (r/placeDiags (optionOr (listSlice ds 0 k) (list)) pos) (optionOr (listSlice ds k n) (list)))))

fn noteMapType st: InferState t: ty/Type scope: String -> InferState
  (with st :mapSites (cons (pair t scope) st.mapSites))

fn noteIntLiteral st: InferState tok: String vid: Int64 -> InferState
  (with st :intSites (cons (pair tok vid) st.intSites))

fn setSubst st: InferState s: (Map Int64 ty/Type) -> InferState
  (with st :subst s)

fn deferSite st: InferState name: String recv: ty/Type args: (List ty/Type) result: ty/Type -> InferState
  (with st :deferred (cons (Deferred :name name :recv recv :args args :result result) st.deferred))

fn typeText t: ty/Type -> String
  (match t ((ty/tyCon name args _ _) (if (listEmpty? args) name (str "(" name " " (stringJoin (map typeText args) " ") ")"))) ((ty/tyVar _ _) "_") ((ty/tyFun _ _) "fn"))

fn expectType st: InferState have: ty/Type want: ty/Type where: String path: String modName: String -> InferState
  (let [(st1 (noteMapType (noteMapType st have where) want where))] (match (u/unify want have st1.subst modName) ((u/uOk nextSubst) (setSubst st1 nextSubst)) ((u/uErr msg isNum) (let [(code (if isNum "rule-6" "type"))] (addDiag st1 code (str where ": " msg) path)))))

fn qualifyTypeWithMod t: ty/Type mod: r/ModuleSummary deps: r/DepIndex -> ty/Type
  (match t
    ((ty/tyVar _ _) t)
    ((ty/tyCon name args optMod optShown)
      (let [(isLocal (and (not (stringEmpty? mod.name)) (or (some? (r/modSchema mod name)) (some? (r/modEnum mod name)))))
            (nextMod (match optMod
                      ((some alias) (match (r/modImport mod alias)
                                     ((some mpath) (match (r/resolveDepIn mpath deps) ((ok target) (some target.name)) ((err _) (some mpath))))
                                     ((none) optMod)))
                      ((none) (if isLocal (some mod.name) (importedUnqualifiedTypeModule name mod deps)))))]
        (if (knownTypeName? name (listLength args) optMod isLocal nextMod)
          (ty/tyCon name (map (fn [(a ty/Type)] -> ty/Type (qualifyTypeWithMod a mod deps)) args) nextMod optShown)
          (ty/tyCon "?" (list) (none) (some (ty/showType t))))))
    ((ty/tyFun params ret) (ty/tyFun (map (fn [(p ty/Type)] -> ty/Type (qualifyTypeWithMod p mod deps)) params) (qualifyTypeWithMod ret mod deps))))

fn knownTypeName? name: String argc: Int64 optMod: (Option String) isLocal: Bool nextMod: (Option String) -> Bool
  (or (some? optMod)
      (or (ty/isNumericType? name)
          (or (listContains? (list "String" "Bool" "Unit" "Bytes" "Keyword" "IoError" "PreludeMap" "PreludeTree" "HashMap" "ProcessOutput" "SpawnedProc" "PlatformInfo" "Rusage" "FileStat" "F64Array" "I8Array" "I64Array" "SExpr" "ParquetHandle" "Handle") name)
              (or (and (or (= name "List") (= name "Option")) (= argc 1))
                  (or (and (or (= name "Result") (or (= name "Map") (= name "Pair"))) (= argc 2))
                      (or (and (= (stringLength name) 1) (= (stringUpper name) name))
                          (or (stringStartsWith? name "#") (or isLocal (some? nextMod)))))))))

fn importedUnqualifiedTypeModule name: String mod: r/ModuleSummary deps: r/DepIndex -> (Option String)
  (fold (fn [(acc (Option String)) (mpath String)] -> (Option String)
          (match acc
            ((some _) acc)
            ((none)
             (match (r/resolveDepIn mpath deps)
               ((ok target)
                (if (and (or (listContains? target.exportedTypes name) (listContains? target.exports name))
                         (or (some? (r/modSchema target name)) (some? (r/modEnum target name))))
                  (some target.name)
                  (none)))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn freshVarsFrom typevars: (List String) vmap: (Map String ty/Type) st: InferState -> (Pair (Map String ty/Type) InferState)
  (match (listHead typevars) ((none) (pair vmap st)) ((some vname) (let [(kind (if (= vname "N") "num" (if (= vname "I") "int" (if (= vname "X") "text" "any")))) (fRes (freshVar st kind))] (freshVarsFrom (optionOr (listTail typevars) (list)) (mapSet vmap vname (pairFirst fRes)) (pairSecond fRes)))))

fn instantiateSig params: (List String) ret: String typevars: (List String) mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Pair (Pair (List ty/Type) ty/Type) InferState)
  (let [(vRes (freshVarsFrom typevars (mapEmpty) st)) (vmap (pairFirst vRes)) (st1 (pairSecond vRes)) (instP (map (fn [(p String)] -> ty/Type (qualifyTypeWithMod (substParsedType (ty/parseTypeStr p (list)) vmap) mod deps)) params)) (instR (qualifyTypeWithMod (substParsedType (ty/parseTypeStr ret (list)) vmap) mod deps))] (pair (pair instP instR) st1))

fn substParsedTypes ts: (List ty/Type) vmap: (Map String ty/Type) -> (List ty/Type)
  (map (fn [(item ty/Type)] -> ty/Type (substParsedType item vmap)) ts)

fn substParsedType t: ty/Type vmap: (Map String ty/Type) -> ty/Type
  (match t ((ty/tyVar _ _) t) ((ty/tyCon name args optMod optShown) (match (mapGet vmap name) ((some mapped) mapped) ((none) (ty/tyCon name (substParsedTypes args vmap) optMod optShown)))) ((ty/tyFun params ret) (ty/tyFun (substParsedTypes params vmap) (substParsedType ret vmap))))

fn sigResToFun res: (Pair (Pair (List ty/Type) ty/Type) InferState) -> (Option (Pair ty/Type InferState))
  (some (pair (ty/tyFun (pairFirst (pairFirst res)) (pairSecond (pairFirst res))) (pairSecond res)))

fn paramTypesToStrs params: (List (Pair String String)) -> (List String)
  (map (fn [(p (Pair String String))] -> String (pairSecond p)) params)

fn lookupLocalFun sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (match (r/modFun mod sym) ((some f) (let [(pStrs (paramTypesToStrs f.params)) (tvars (if (listEmpty? f.typevars) (ty/collectTvars pStrs f.ret) f.typevars)) (res (instantiateSig pStrs f.ret tvars mod deps st))] (sigResToFun res))) ((none) (none)))

fn lookupSysBuiltinSig sym: String mod: r/ModuleSummary st: InferState -> (Option (Pair ty/Type InferState))
  (match (ty/builtinSig sym) ((some bsig) (let [(params (pairFirst bsig)) (ret (pairSecond (pairSecond bsig))) (tvars (ty/collectTvars params ret)) (res (instantiateSig params ret tvars mod (r/depIndexOf (mapEmpty)) st))] (sigResToFun res))) ((none) (genericSig sym mod st)))

; (:m :ref HLFIXB :do "partial's real type (fix the first n params of its function argument, return a function over the rest) has no fixed param-count/single-return shape builtinSig can hold; resolve.asl's isSpecialForm? keeps it from being flagged unbound, and this gives it a fresh any-kind metavariable result so calling it does not crash inference, matching the genericMulti? fallback just above rather than asserting a false signature")
fn genericSig sym: String mod: r/ModuleSummary st: InferState -> (Option (Pair ty/Type InferState))
  (cond ((ty/genericMulti? sym) (some (freshVar st "any")))
        ((= sym "partial") (some (freshVar st "any")))
        ((not (stringEmpty? (ty/genericAlias sym))) (lookupSysBuiltinSig (ty/genericAlias sym) mod st))
        (else (none)))

fn lookupLocalCase sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (match (mapGet mod.caseOwner sym) ((some ename) (match (r/modEnum mod ename) ((some esum) (let [(matching (filter (fn [(c r/CaseSummary)] -> Bool (= c.name sym)) esum.cases))] (match (listHead matching) ((some caseNode) (let [(pStrs (paramTypesToStrs caseNode.params)) (tvars esum.typevars) (retStr (if (listEmpty? tvars) ename (str "(" ename " " (stringJoin tvars " ") ")"))) (res (instantiateSig pStrs retStr tvars mod deps st))] (sigResToFun res))) ((none) (none))))) ((none) (none)))) ((none) (none)))

fn lookupLocalSymbol sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (match (lookupLocalFun sym mod deps st) ((some res) (some res)) ((none) (lookupLocalCase sym mod deps st)))

fn lookupImportedSymbol sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (let [(parts (stringSplit sym "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))] (match (r/modImport mod alias) ((some mpath) (if (= mpath "sys") (lookupSysBuiltinSig member mod st) (match (r/resolveDepIn mpath deps) ((ok target) (lookupLocalSymbol member target deps st)) ((err _) (none))))) ((none) (none))))

fn lookupUnqualifiedCaseInDeps sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (fold (fn [(acc (Option (Pair ty/Type InferState))) (mpath String)] -> (Option (Pair ty/Type InferState))
          (match acc
            ((some _) acc)
            ((none)
             (match (r/resolveDepIn mpath deps)
               ((ok target) (if (mapHas? target.exportedCases sym) (lookupLocalCase sym target deps st) (none)))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn lookupSymbolType sym: String env: (Map String ty/Type) mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Option (Pair ty/Type InferState))
  (match (mapGet env sym) ((some t) (some (pair t st))) ((none) (match (lookupLocalSymbol sym mod deps st) ((some res) (some res)) ((none) (match (lookupSysBuiltinSig sym mod st) ((some res) (some res)) ((none) (if (stringContains? sym "/") (lookupImportedSymbol sym mod deps st) (lookupUnqualifiedCaseInDeps sym mod deps st))))))))

fn mantissaOk? m: String -> Bool
  (if (stringContains? m ".") (let [(parts (stringSplit m "."))] (and (= (listLength parts) 2) (and (isAllDigits (optionOr (listGet parts 0) "")) (isAllDigits (optionOr (listGet parts 1) ""))))) (and (not (stringEmpty? m)) (isAllDigits m)))

fn expOk? e: String -> Bool
  (let [(s (r/cleanNumSign e))] (and (not (stringEmpty? s)) (isAllDigits s)))

fn splitExp s: String -> (Pair String (Option String))
  (if (stringContains? s "e") (let [(parts (stringSplit s "e"))] (if (= (listLength parts) 2) (pair (optionOr (listGet parts 0) "") (some (optionOr (listGet parts 1) ""))) (pair s (none)))) (if (stringContains? s "E") (let [(parts (stringSplit s "E"))] (if (= (listLength parts) 2) (pair (optionOr (listGet parts 0) "") (some (optionOr (listGet parts 1) ""))) (pair s (none)))) (pair s (none))))

fn isFloatLit? v: String -> Bool
  (let [(sp (splitExp (r/cleanNumSign v))) (mant (pairFirst sp)) (expPart (pairSecond sp))] (match expPart ((some e) (and (mantissaOk? mant) (expOk? e))) ((none) (and (stringContains? mant ".") (mantissaOk? mant)))))

fn isIntLit? v: String -> Bool
  (let [(sp (splitExp (r/cleanNumSign v))) (mant (pairFirst sp)) (expPart (pairSecond sp))] (match expPart ((some _) false) ((none) (or (and (not (stringContains? mant ".")) (mantissaOk? mant)) (let [(shape (nk/intLitShape v))] (or (= shape "radix") (= shape "sep")))))))

fn unitType -> ty/Type
  (ty/tyCon "Unit" (list) (none) (none))

fn lastExprUnit l: (List rd/SExpr) -> rd/SExpr
  (match (listHead (listReverse l)) ((some e) e) ((none) (rd/makeAtom "()")))

fn nullaryCaseValue v: String found: (Pair ty/Type InferState) env: (Map String ty/Type) mod: r/ModuleSummary deps: r/DepIndex -> (Pair ty/Type InferState)
  (match (pairFirst found)
    ((ty/tyFun ps r) (if (and (listEmpty? ps) (and (not (mapHas? env v)) (and (none? (r/modFun mod v)) (or (some? (lookupLocalCase v mod deps (pairSecond found))) (or (some? (lookupUnqualifiedCaseInDeps v mod deps (pairSecond found))) (qualifiedCase? v mod deps (pairSecond found)))))))
                       (pair r (pairSecond found))
                       found))
    (_ found))

fn editRow a: Bytes b: Bytes i: Int64 j: Int64 prev: (List Int64) left: Int64 acc: (List Int64) -> (List Int64)
  (if (> j (bytesLength b))
    (listReverse acc)
    (let [(diag (optionOr (listGet prev (- j 1)) 0))
          (up (optionOr (listGet prev j) 0))
          (cost (if (= (bytesGet a (- i 1)) (bytesGet b (- j 1))) 0 1))
          (cell (min (+ diag cost) (min (+ up 1) (+ left 1))))]
      (editRow a b i (+ j 1) prev cell (cons cell acc))))

fn editRows a: Bytes b: Bytes i: Int64 prev: (List Int64) -> Int64
  (if (> i (bytesLength a))
    (optionOr (listGet prev (bytesLength b)) 0)
    (editRows a b (+ i 1) (editRow a b i 1 prev i (list i))))

fn editDistance x: String y: String -> Int64
  (let [(b (stringToBytes (stringLower y)))]
    (editRows (stringToBytes (stringLower x)) b 1 (range 0 (+ (bytesLength b) 1))))

fn helperStem v: String -> String
  (let [(lower (stringLower v))]
    (cond
      ((stringStartsWith? lower "string") (optionOr (stringSlice lower 6 (stringLength lower)) lower))
      ((stringStartsWith? lower "str") (optionOr (stringSlice lower 3 (stringLength lower)) lower))
      (else lower)))

fn helperDistance v: String c: String -> Int64
  (min (editDistance v c) (editDistance (helperStem v) (helperStem c)))

fn stringHelperName? v: String -> Bool
  (let [(lower (stringLower v))] (and (stringStartsWith? lower "str") (not (stringContains? v "/"))))

fn hintVocabulary mod: r/ModuleSummary -> (List String)
  (listAppend (mapKeys mod.funs)
    (listAppend (ty/stringBuiltinNames)
      (listAppend (map (fn [(p (Pair String String))] -> String (optionOr (listHead (stringSplit (pairFirst p) "/")) "")) (ty/genericRows))
                  (ty/genericAliasNames))))

fn nearNames v: String mod: r/ModuleSummary -> (List String)
  (let [(limit (max 1 (/ (stringLength (helperStem v)) 3)))
        (scored (fold (fn [(acc (List (Pair Int64 String))) (c String)] -> (List (Pair Int64 String))
                        (if (or (= c v) (or (stringEmpty? c) (or (not (stringEmpty? (ty/renamedHint c))) (listAny? (fn [(q (Pair Int64 String))] -> Bool (= (pairSecond q) c)) acc))))
                          acc
                          (let [(d (helperDistance v c))] (if (<= d limit) (cons (pair d c) acc) acc))))
                      (list) (hintVocabulary mod)))
        (ordered (listSortBy (fn [(p (Pair Int64 String))] -> String (str (stringFromInt64 (+ 1000 (pairFirst p))) " " (pairSecond p))) scored))]
    (map (fn [(p (Pair Int64 String))] -> String (pairSecond p)) (listTake ordered 3)))

fn builtinNearHint v: String mod: r/ModuleSummary -> String
  (if (or (not (stringHelperName? v)) (not (stringEmpty? (ty/renamedHint v))))
    ""
    (let [(names (nearNames v mod))]
      (if (listEmpty? names) "" (str "; did you mean " (stringJoin names ", ") " (prelude builtins)"))))

fn inferAtom v: String env: (Map String ty/Type) mod: r/ModuleSummary deps: r/DepIndex scope: String path: String st: InferState -> (Pair ty/Type InferState)
  (cond ((stringStartsWith? v "\"") (pair (ty/tyCon "String" (list) (none) (none)) st)) ((or (= v "true") (= v "false")) (pair (ty/tyCon "Bool" (list) (none) (none)) st)) ((and (= v "none") (not (mapHas? env v))) (let [(fRes (freshVar st "any"))] (pair (ty/tyCon "Option" (list (pairFirst fRes)) (none) (none)) (pairSecond fRes)))) ((or (= v "()") (= v "nil")) (pair (unitType) st)) ((= (nk/intLitShape v) "bad") (pair (ty/tyCon "Int64" (list) (none) (none)) (addDiag st "ERR_BAD_NUMBER" (str "malformed number: " v) path))) ((isFloatLit? v) (pair (ty/tyCon "Float64" (list) (none) (none)) st)) ((isIntLit? v) (let [(vid st.nextVar) (fRes (freshVar st "int")) (vty (pairFirst fRes)) (st1 (pairSecond fRes)) (st2 (noteIntLiteral st1 v vid))] (pair vty st2))) ((and (stringStartsWith? v ":") (not (mapHas? env v))) (pair (ty/tyCon "Keyword" (list) (none) (none)) st)) (else (match (lookupSymbolType v env mod deps st) ((some found) (nullaryCaseValue v found env mod deps)) ((none) (let [(st1 (addDiag st "rule-1" (str "unbound symbol: " v (ty/renamedHint v) (builtinNearHint v mod)) path))] (freshVar st1 "any"))))))

fn inferAtomFm fm: FrameMachine v: String st: InferState -> (Pair ty/Type InferState)
  (inferAtom v fm.env fm.mod fm.deps fm.scope fm.path st)

fn asTyVar t: ty/Type -> ty/Type
  t

fn isAllDigits s: String -> Bool
  (if (stringEmpty? s) false (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? "0123456789" c))) true (stringChars s)))

fn parseParamParts parts: (List rd/SExpr) mod: r/ModuleSummary deps: r/DepIndex -> (Pair String (Option ty/Type))
  (let [(h (r/firstHeadIdent parts)) (sub (r/safeTail parts))] (match (listHead sub) ((some tyNode) (pair h (some (qualifyTypeWithMod (ty/parseTypeStr (a/typeNodeText tyNode) (list)) mod deps)))) ((none) (pair h (none)))))

fn parseParamAnn p: rd/SExpr mod: r/ModuleSummary deps: r/DepIndex -> (Pair String (Option ty/Type))
  (match p ((rd/sexprAtom n) (pair n (none))) ((rd/sexprList parts) (parseParamParts parts mod deps)) ((rd/sexprVect parts) (parseParamParts parts mod deps)))

fn paramPartsAnnText parts: (List rd/SExpr) -> String
  (let [(sub (r/safeTail parts))] (match (listHead sub) ((some tyNode) (a/typeNodeText tyNode)) ((none) "")))

fn paramAnnText p: rd/SExpr -> String
  (match p ((rd/sexprAtom _) "") ((rd/sexprList parts) (paramPartsAnnText parts)) ((rd/sexprVect parts) (paramPartsAnnText parts)))

fn lambdaTypeBound paramItems: (List rd/SExpr) retText: String -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (name String)] -> (Map String Bool) (mapSet acc name true)) (mapEmpty) (ty/collectTvars (map paramAnnText paramItems) retText))

fn addTypeTreeDiags st: InferState t: ty/Type bound: (Map String Bool) mod: r/ModuleSummary deps: r/DepIndex where: String path: String -> InferState
  (setDiags st (listAppend st.diags (r/checkTypeTree t bound mod deps.deps where path (list))))

fn letBindValue bparts: (List rd/SExpr) -> rd/SExpr
  (if (= (listLength bparts) 3) (optionOr (listGet bparts 2) (rd/makeAtom "()")) (r/secondExprEmpty bparts))

fn letAnnState st: InferState bparts: (List rd/SExpr) path: String -> InferState
  (match (if (= (listLength bparts) 3) (listGet bparts 1) (none))
    ((some n) (setDiags st (listAppend st.diags (r/dottedTypeTree (ty/parseTypeStr (a/typeNodeText n) (list)) "let binding" path (list)))))
    ((none) st))

; (:m :ref CHECKER-R1GAPS :do "a let binding's type annotation, (name Type value), had its annotation tree validated (letAnnState, above) but was never compared against the value's inferred type: (let [(flag Bool (str \"yes\"))] ...) passed check, exit 0, only to fail at native runtime; letAnnType resolves the annotation to a real ty/Type so fmLetValStep can expectType the bound value against it, the same ERR_TYPE_MISMATCH path every other binding site already uses")
fn letAnnType bparts: (List rd/SExpr) mod: r/ModuleSummary deps: r/DepIndex -> (Option ty/Type)
  (match (if (= (listLength bparts) 3) (listGet bparts 1) (none))
    ((some n) (some (qualifyTypeWithMod (ty/parseTypeStr (a/typeNodeText n) (list)) mod deps)))
    ((none) (none)))

fn checkLambdaAnnText st: InferState annText: String bound: (Map String Bool) mod: r/ModuleSummary deps: r/DepIndex where: String path: String -> InferState
  (if (stringEmpty? annText) st (addTypeTreeDiags st (ty/parseTypeStr annText (list)) bound mod deps where path))

(enum InferFrame (:c fEval [(expr rd/SExpr)] "Evaluate expression next") (:c fCall [(calleeName String) (calleeTy ty/Type) (argsDone (List ty/Type)) (argsPending (List rd/SExpr)) (env (Map String ty/Type))] "Call evaluation continuation") (:c fLetVal [(bname String) (bindingsRest (List rd/SExpr)) (tailExprs (List rd/SExpr)) (env (Map String ty/Type)) (annTy (Option ty/Type))] "Let binding evaluation continuation") (:c fIfCond [(thenE rd/SExpr) (elseE rd/SExpr) (env (Map String ty/Type))] "If condition continuation") (:c fIfThen [(elseE rd/SExpr) (thenTy ty/Type) (env (Map String ty/Type))] "If branches continuation") (:c fTryInner [(valVar ty/Type)] "Try continuation"))

(schema FrameMachine (:f frames (List InferFrame)) (:f values (List ty/Type)) (:f env (Map String ty/Type)) (:f retType (Option ty/Type)) (:f inLambda Bool) (:f scope String) (:f path String) (:f mod r/ModuleSummary) (:f deps r/DepIndex) (:f state InferState))

fn fmPushFresh fm: FrameMachine restFrames: (List InferFrame) st: InferState -> FrameMachine
  (let [(fRes (freshVar st "any"))] (with fm :frames restFrames :values (cons (pairFirst fRes) fm.values) :state (pairSecond fRes)))

fn popValue fm: FrameMachine -> (Pair ty/Type (List ty/Type))
  (pair (optionOr (listHead fm.values) (unitType)) (r/safeTail fm.values))

fn fmTick fm: FrameMachine tickIdx: Int64 -> FrameMachine
  (match (listHead fm.frames) ((none) fm) ((some topFrame) (let [(restFrames (r/safeTail fm.frames))] (match topFrame ((fEval expr) (fmEvalStep expr restFrames fm)) ((fCall cname cty argsDone argsPending cenv) (fmCallStep cname cty argsDone argsPending cenv restFrames fm)) ((fLetVal bname brest tails lenv annTy) (fmLetValStep bname brest tails lenv annTy restFrames fm)) ((fIfCond thenE elseE ienv) (fmIfCondStep thenE elseE ienv restFrames fm)) ((fIfThen elseE thenTy ienv) (fmIfThenStep elseE thenTy ienv restFrames fm)) ((fTryInner valVar) (fmTryStep valVar restFrames fm))))))

fn bindUnknownSubpats pats: (List rd/SExpr) env: (Map String ty/Type) st: InferState -> (Pair (Map String ty/Type) InferState)
  (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (p rd/SExpr)] -> (Pair (Map String ty/Type) InferState)
          (match p
            ((rd/sexprAtom name)
             (if (or (= name "_") (r/isLiteralAtom? name))
               acc
               (let [(fRes (freshVar (pairSecond acc) "any"))]
                 (pair (mapSet (pairFirst acc) name (pairFirst fRes)) (pairSecond fRes)))))
            ((rd/sexprVect items) (bindUnknownSubpats items (pairFirst acc) (pairSecond acc)))
            ((rd/sexprList items)
             (let [(subs (r/safeTail items))]
               (bindUnknownSubpats subs (pairFirst acc) (pairSecond acc))))))
        (pair env st)
        pats)

fn bindMatchPatternList pats: (List rd/SExpr) params: (List ty/Type) env: (Map String ty/Type) st: InferState mod: r/ModuleSummary deps: r/DepIndex -> (Pair (Map String ty/Type) InferState)
  (match (listHead pats) ((none) (pair env st)) ((some pat) (match (listHead params) ((none) (pair env st)) ((some paramTy) (let [(pruned (u/applySubst st.subst paramTy)) (res (bindMatchPattern pat pruned env mod deps st))] (bindMatchPatternList (optionOr (listTail pats) (list)) (optionOr (listTail params) (list)) (pairFirst res) (pairSecond res) mod deps))))))

fn qualifiedCase? sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> Bool
  (if (not (stringContains? sym "/")) false
    (let [(parts (stringSplit sym "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))]
      (match (r/modImport mod alias)
        ((some mpath) (if (= mpath "sys") false
          (match (r/resolveDepIn mpath deps)
            ((ok target) (some? (lookupLocalCase member target deps st)))
            ((err _) false))))
        ((none) false))))

fn patternConstructor? sym: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> Bool
  (or (= sym "pair")
      (or (some? (ty/preludeUnionCases sym))
      (some? (schemaOfCtorIn sym mod deps))
      (some? (lookupLocalCase sym mod deps st))
      (some? (lookupUnqualifiedCaseInDeps sym mod deps st))
      (some? (r/unexportedCaseModule sym mod deps))
      (qualifiedCase? sym mod deps st)))

fn formPatternHead? head: String -> Bool
  (listContains? (list "do" "begin" "if" "cond" "let" "match" "when" "unless" "fn" "lambda" "assert" "refute" "and" "or" "not") head)

fn invalidPatternAtom? head: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> Bool
  (or (formPatternHead? head)
      (and (not (patternConstructor? head mod deps st))
        (or (some? (lookupSysBuiltinSig head mod st))
            (or (some? (lookupLocalFun head mod deps st))
                (and (stringContains? head "/") (some? (lookupImportedSymbol head mod deps st)))))))

fn bindArmPattern pat: rd/SExpr scrutTy: ty/Type env: (Map String ty/Type) mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Pair (Map String ty/Type) InferState)
  (match pat
    ((rd/sexprAtom name)
     (if (and (not (= name "_")) (not (r/isLiteralAtom? name)) (invalidPatternAtom? name mod deps st))
       (pair env (addDiag st "type" (str "invalid mt arm pattern headed by " name) mod.path))
       (bindMatchPattern pat scrutTy env mod deps st)))
    (_ (bindMatchPattern pat scrutTy env mod deps st)))

fn bindMatchPattern pat: rd/SExpr scrutTy: ty/Type env: (Map String ty/Type) mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Pair (Map String ty/Type) InferState)
  (match pat
    ((rd/sexprAtom name) (if (or (= name "_") (r/isLiteralAtom? name)) (pair env st) (pair (mapSet env name scrutTy) st)))
    ((rd/sexprVect items) (bindUnknownSubpats items env st))
    ((rd/sexprList parts)
     (match (listHead parts)
       ((none) (pair env st))
       ((some h)
        (let [(cname (rd/sexprHead h)) (subPats (r/safeTail parts)) (ctorOpt (lookupSymbolType cname env mod deps st))]
          (if (not (patternConstructor? cname mod deps st))
            (let [(st1 (addDiag st "type" (str "unknown constructor in match pattern: " cname "; invalid mt arm pattern headed by " cname) mod.path))]
              (bindUnknownSubpats subPats env st1))
            (match ctorOpt
            ((none)
             (if (some? (r/unexportedCaseModule cname mod deps))
               (bindUnknownSubpats subPats env st)
               (let [(st1 (addDiag st "type" (str "unknown constructor in match pattern: " cname "; invalid mt arm pattern headed by " cname) mod.path))]
                 (bindUnknownSubpats subPats env st1))))
            ((some ctorRes)
             (let [(ctorTy (pairFirst ctorRes)) (st1 (pairSecond ctorRes))]
               (match (u/applySubst st1.subst ctorTy)
                 ((ty/tyFun cparams cret)
                  (let [(st2 (expectType st1 scrutTy cret (str "pattern " cname) mod.path mod.name))
                        (mLen (min (listLength subPats) (listLength cparams)))
                        (res (bindMatchPatternList subPats cparams env st2 mod deps))]
                    (if (> (listLength subPats) mLen)
                      (bindUnknownSubpats (listDrop subPats mLen) (pairFirst res) (pairSecond res))
                      res)))
                 (_ (bindUnknownSubpats subPats env st1))))))))))))

fn retiredTryMessage -> String
  "unbound symbol: try (try is retired; match the Result with match)"

fn buildTypeSubstMap tvars: (List String) targs: (List ty/Type) acc: (Map String ty/Type) -> (Map String ty/Type)
  (match (listHead tvars) ((none) acc) ((some v) (match (listHead targs) ((none) acc) ((some arg) (buildTypeSubstMap (optionOr (listTail tvars) (list)) (optionOr (listTail targs) (list)) (mapSet acc v arg))))))

fn evalStatement fm: FrameMachine expr: rd/SExpr st: InferState -> InferState
  (match expr
    ((rd/sexprList items)
     (match (listHead items)
       ((some h)
        (if (= (rd/sexprHead h) "if")
          (let [(args (r/safeTail items))]
            (if (= (listLength args) 2)
              (let [(condRes (evalFm fm (optionOr (listGet args 0) (rd/makeAtom "true")) st))
                    (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) "if condition" fm.path fm.mod.name))
                    (thenRes (evalFm fm (optionOr (listGet args 1) (rd/makeAtom "()")) st1))]
                (pairSecond thenRes))
              (pairSecond (evalFm fm expr st))))
          (pairSecond (evalFm fm expr st))))
       ((none) (pairSecond (evalFm fm expr st)))))
    (_ (pairSecond (evalFm fm expr st))))

fn evalDoArgs fm: FrameMachine args: (List rd/SExpr) st: InferState -> (Pair ty/Type InferState)
  (match (listHead args)
    ((none) (pair (unitType) st))
    ((some first) (let [(rest (r/safeTail args))]
      (if (listEmpty? rest)
        (evalFm fm first st)
        (evalDoArgs fm rest (evalStatement fm first st))))))

fn fmEvalStep expr: rd/SExpr restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (match expr ((rd/sexprAtom v) (let [(res (inferAtomFm fm v fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (noteMapType (pairSecond res) (pairFirst res) fm.scope)))) ((rd/sexprVect items) (let [(fRes (freshVar fm.state "any")) (elemTy (pairFirst fRes)) (st1 (pairSecond fRes))] (with fm :frames restFrames :values (cons (ty/tyCon "List" (list elemTy) (none) (none)) fm.values) :state st1))) ((rd/sexprList items) (match (listHead items) ((none) (with fm :frames restFrames :values (cons (unitType) fm.values))) ((some h) (let [(headTok (if (rd/isAtom? h) (rd/sexprHead h) "")) (tailArgs (r/safeTail items))] (cond ((and (or (= headTok "quote") (= headTok "quasiquote")) (and (none? (r/modFun fm.mod headTok)) (not (mapHas? fm.env headTok)))) (let [(sexprTy (ty/tyCon "SExpr" (list) (none) (none)))] (with fm :frames restFrames :values (cons sexprTy fm.values)))) ((or (= headTok "assert") (= headTok "refute")) (let [(condRes (evalFm fm (optionOr (listHead tailArgs) (rd/makeAtom "()")) fm.state)) (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) (str headTok " condition") fm.path fm.mod.name)) (st2 (match (listGet tailArgs 1) ((some m) (pairSecond (evalFm fm m st1))) ((none) st1))) (st3 (if (or (listEmpty? tailArgs) (> (listLength tailArgs) 2)) (addDiag st2 "arity" (str headTok " takes a condition and an optional message, given " (stringFromInt64 (listLength tailArgs))) fm.path) st2)) (trap (match (listHead tailArgs) ((some c0) (and (rd/isAtom? c0) (= (rd/sexprHead c0) (if (= headTok "assert") "false" "true")))) ((none) false))) (res (if trap (freshVar st3 "any") (pair (unitType) st3)))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) ((or (= headTok "when") (= headTok "unless")) (let [(condRes (evalFm fm (optionOr (listHead tailArgs) (rd/makeAtom "true")) fm.state)) (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) (str headTok " condition") fm.path fm.mod.name)) (st2 (fold (fn [(acc InferState) (arg rd/SExpr)] -> InferState (pairSecond (evalFm fm arg acc))) st1 (r/safeTail tailArgs)))] (fmPushFresh fm restFrames st2))) ((= headTok "do") (let [(res (evalDoArgs fm tailArgs fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) ((= headTok "let") (let [(bitems (r/firstVectItems tailArgs)) (tails (r/safeTail tailArgs))] (if (listEmpty? bitems) (let [(lastE (lastExprUnit tails))] (with fm :frames (cons (fEval lastE) restFrames))) (let [(firstB (r/firstExprEmpty bitems)) (flat? (match firstB ((rd/sexprAtom _) true) (_ false))) (brest (if flat? (r/safeTail (r/safeTail bitems)) (r/safeTail bitems))) (bparts (if flat? (list firstB (r/secondExprEmpty bitems)) (match firstB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))) (bname (if flat? (rd/sexprHead firstB) (r/firstHeadIdent bparts))) (bval (letBindValue bparts))] (with fm :frames (cons (fEval bval) (cons (fLetVal bname brest tails fm.env (letAnnType bparts fm.mod fm.deps)) restFrames)) :state (letAnnState fm.state bparts fm.path)))))) ((= headTok "with") (let [(res (inferWith fm tailArgs))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) ((= headTok "if") (let [(condE (optionOr (listGet tailArgs 0) (rd/makeAtom "true"))) (thenE (optionOr (listGet tailArgs 1) (rd/makeAtom "()"))) (elseE (optionOr (listGet tailArgs 2) (rd/makeAtom "()")))] (with fm :frames (cons (fEval condE) (cons (fIfCond thenE elseE fm.env) restFrames))))) ((= headTok "cond") (let [(fRes (freshVar fm.state "any")) (outVar (pairFirst fRes)) (stOut (pairSecond fRes)) (stFinal (fold (fn [(stAcc InferState) (clause rd/SExpr)] -> InferState (match clause ((rd/sexprList cparts) (let [(cheadExpr (r/firstExprEmpty cparts)) (chead (rd/sexprHead cheadExpr)) (cbodies (r/safeTail cparts)) (lastB (lastExprUnit cbodies))] (if (= chead "else") (let [(bres (evalFm fm lastB stAcc))] (expectType (pairSecond bres) (pairFirst bres) outVar "cond else clause, branches disagree" fm.path fm.mod.name)) (let [(cres (evalFm fm cheadExpr stAcc)) (stC (expectType (pairSecond cres) (pairFirst cres) (ty/tyCon "Bool" (list) (none) (none)) "cond test" fm.path fm.mod.name)) (bres (evalFm fm lastB stC))] (expectType (pairSecond bres) (pairFirst bres) outVar "cond clause, branches disagree" fm.path fm.mod.name))))) (_ stAcc))) stOut tailArgs))] (with fm :frames restFrames :values (cons (u/applySubst stFinal.subst outVar) fm.values) :state stFinal))) ((= headTok "match") (let [(scrutinee (r/firstExprUnit tailArgs)) (arms (r/safeTail tailArgs)) (scrutRes (evalFm fm scrutinee fm.state)) (scrutTy (pairFirst scrutRes)) (stScrut (pairSecond scrutRes)) (fRes (freshVar stScrut "any")) (outVar (pairFirst fRes)) (stOut (pairSecond fRes)) (family (r/matchFamily arms fm.mod fm.deps.deps)) (stFinal (fold (fn [(stAcc InferState) (arm rd/SExpr)] -> InferState (match arm ((rd/sexprList armParts) (let [(pat (match (listHead armParts) ((some p) p) ((none) (rd/makeAtom "_")))) (bodyExprs (r/safeTail armParts)) (bindRes (if (r/ctorPatternAtom? pat family fm.mod fm.deps.deps) (pair fm.env stAcc) (bindArmPattern pat (u/applySubst stAcc.subst scrutTy) fm.env fm.mod fm.deps stAcc))) (armEnv (pairFirst bindRes)) (stArm (pairSecond bindRes)) (lastBody (lastExprUnit bodyExprs)) (bodyRes (evalWithEnv fm lastBody armEnv stArm)) (bodyTy (pairFirst bodyRes)) (stB (pairSecond bodyRes))] (expectType stB bodyTy outVar "match arm, branches disagree" fm.path fm.mod.name))) (_ stAcc))) stOut arms))] (with fm :frames restFrames :values (cons (u/applySubst stFinal.subst outVar) fm.values) :state stFinal))) ((= headTok "try") (let [(st1 (addDiag fm.state "ERR_UNKNOWN_SYMBOL" (retiredTryMessage) fm.path))] (with fm :frames (cons (fEval (r/firstExprUnit tailArgs)) restFrames) :state st1))) ((= headTok "fn") (let [(isBang (and (not (listEmpty? tailArgs)) (= (r/firstHeadIdent tailArgs) "!"))) (remArgs (if isBang (r/safeTail tailArgs) tailArgs)) (afterParams (r/safeTail remArgs)) (hasRetAnn (and (not (listEmpty? afterParams)) (= (r/firstHeadIdent afterParams) "->"))) (bodyNodes (if hasRetAnn (r/safeTail (r/safeTail afterParams)) afterParams)) (paramItems (r/firstVectItems remArgs)) (afterArrow (if hasRetAnn (r/safeTail afterParams) (list))) (retNodeOpt (listHead afterArrow)) (retAnnText (match retNodeOpt ((some rnode) (a/typeNodeText rnode)) ((none) ""))) (lamBound (lambdaTypeBound paramItems retAnnText)) (pRes (fold (fn [(acc (Pair (Pair (List ty/Type) (Map String ty/Type)) InferState)) (p rd/SExpr)] -> (Pair (Pair (List ty/Type) (Map String ty/Type)) InferState) (let [(pann (parseParamAnn p fm.mod fm.deps)) (pname (pairFirst pann)) (tyRes (match (pairSecond pann) ((some pty) (pair pty (checkLambdaAnnText (pairSecond acc) (paramAnnText p) lamBound fm.mod fm.deps "lambda parameter" fm.path))) ((none) (freshVar (pairSecond acc) "any")))) (pty (pairFirst tyRes))] (pair (pair (cons pty (pairFirst (pairFirst acc))) (mapSet (pairSecond (pairFirst acc)) pname pty)) (pairSecond tyRes)))) (pair (pair (list) fm.env) fm.state) paramItems)) (paramsTy (listReverse (pairFirst (pairFirst pRes)))) (fnEnv (pairSecond (pairFirst pRes))) (st1 (checkLambdaAnnText (pairSecond pRes) retAnnText lamBound fm.mod fm.deps "lambda return" fm.path)) (retInfo (match retNodeOpt ((some rnode) (pair (qualifyTypeWithMod (ty/parseTypeStr (a/typeNodeText rnode) (list)) fm.mod fm.deps) st1)) ((none) (freshVar st1 "any")))) (retTy (pairFirst retInfo)) (st2 (pairSecond retInfo)) (lastBody (lastExprUnit bodyNodes)) (bodyRes (runExprDirect lastBody fnEnv (some retTy) true fm.scope fm.path fm.mod fm.deps st2)) (bodyTy (pairFirst bodyRes)) (st3 (expectType (pairSecond bodyRes) bodyTy retTy "lambda body" fm.path fm.mod.name)) (fnTy (ty/tyFun paramsTy retTy))] (with fm :frames restFrames :values (cons fnTy fm.values) :state st3))) ((stringStartsWith? headTok ".-") (let [(fname (r/sliceFrom headTok 2)) (tgtE (r/firstExprUnit tailArgs)) (tgtRes (evalFm fm tgtE fm.state)) (tgtTy (u/applySubst (pairSecond tgtRes).subst (pairFirst tgtRes))) (st1 (pairSecond tgtRes))] (match tgtTy ((ty/tyCon tname targs toptMod _) (if (= tname "?") (fmPushFresh fm restFrames st1) (if (= tname "Pair") (fmPushFresh fm restFrames (addDiag st1 "type" (notRecordMessage fname tgtTy) fm.path)) (let [(targetMod (match toptMod ((some m) (moduleNamed m fm.mod fm.deps)) ((none) (some fm.mod))))] (match targetMod ((none) (let [(st2 (addDiag st1 "type" (str "unknown module for type " (ty/showType tgtTy)) fm.path))] (fmPushFresh fm restFrames st2))) ((some smod) (match (checkerSchema smod tname) ((some ssum) (let [(fMatch (filter (fn [(f r/FieldSummary)] -> Bool (= f.name fname)) ssum.fields))] (match (listHead fMatch) ((some fdef) (let [(fieldTy (ty/parseTypeStr fdef.type (list))) (substMap (buildTypeSubstMap ssum.typevars targs (mapEmpty))) (instField (qualifyTypeWithMod (substParsedType fieldTy substMap) smod fm.deps))] (with fm :frames restFrames :values (cons instField fm.values) :state st1))) ((none) (let [(st2 (addDiag st1 "type" (str (ty/showType tgtTy) " has no field " fname) fm.path))] (fmPushFresh fm restFrames st2)))))) ((none) (let [(msg (if (some? toptMod) (str "unknown schema " tname " in module " smod.name) (notRecordMessage fname tgtTy))) (st2 (addDiag st1 "type" msg fm.path))] (fmPushFresh fm restFrames st2)))))))))) (_ (fmPushFresh fm restFrames st1))))) ((= headTok "{") (let [(st1 (inferCtorArgs fm (list) fm.mod (mapEmpty) "map literal" tailArgs fm.state)) (fRes (freshVar st1 "any"))] (with fm :frames restFrames :values (cons (pairFirst fRes) fm.values) :state (pairSecond fRes)))) ((and (= headTok "preludeScriptStep") (= (listLength tailArgs) 4)) (scriptStepFm fm restFrames tailArgs)) ((recordCtorHead? headTok tailArgs fm.mod fm.deps) (let [(res (inferCtorForm fm headTok tailArgs fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) (else (let [(calleeRes (if (rd/isAtom? h) (inferAtomFm fm headTok fm.state) (evalFm fm h fm.state))) (calleeTy (pairFirst calleeRes)) (st1 (pairSecond calleeRes))] (if (listEmpty? tailArgs) (match (u/applySubst st1.subst calleeTy) ((ty/tyFun p r) (with fm :frames restFrames :values (cons r fm.values) :state st1)) ((ty/tyVar _ _) (let [(fRes (freshVar st1 "any")) (rTy (pairFirst fRes)) (st2 (expectType (pairSecond fRes) calleeTy (ty/tyFun (list) rTy) "call" fm.path fm.mod.name))] (with fm :frames restFrames :values (cons rTy fm.values) :state st2))) (_ (with fm :frames restFrames :values (cons calleeTy fm.values) :state st1))) (let [(firstArg (r/firstExprUnit tailArgs)) (pendingArgs (r/safeTail tailArgs))] (with fm :frames (cons (fEval firstArg) (cons (fCall (if (rd/isAtom? h) headTok (rd/renderSexpr h)) calleeTy (list) pendingArgs fm.env) restFrames)) :state st1)))))))))))
fn moduleNamed name: String mod: r/ModuleSummary deps: r/DepIndex -> (Option r/ModuleSummary)
  (if (= name mod.name) (some mod) (match (r/modImport mod name) ((some mpath) (match (r/resolveDepIn mpath deps) ((ok m) (some m)) ((err _) (none)))) ((none) (match (r/resolveDepIn name deps) ((ok m) (some m)) ((err _) (none))))))

fn lookupUnqualifiedSchemaInDeps head: String mod: r/ModuleSummary deps: r/DepIndex -> (Option (Pair r/SchemaSummary r/ModuleSummary))
  (fold (fn [(acc (Option (Pair r/SchemaSummary r/ModuleSummary))) (mpath String)] -> (Option (Pair r/SchemaSummary r/ModuleSummary))
          (match acc
            ((some _) acc)
            ((none)
             (match (r/resolveDepIn mpath deps)
               ((ok target)
                (if (not (or (listContains? target.exportedTypes head) (listContains? target.exports head)))
                  (none)
                  (match (r/modSchema target head)
                    ((some s) (some (pair s target)))
                    ((none) (none)))))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn schemaOfCtorIn head: String mod: r/ModuleSummary deps: r/DepIndex -> (Option (Pair r/SchemaSummary r/ModuleSummary))
  (if (stringContains? head "/") (let [(parts (stringSplit head "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))] (match (r/modImport mod alias) ((none) (none)) ((some mpath) (match (r/resolveDepIn mpath deps) ((err _) (none)) ((ok target) (if (not (or (listContains? target.exportedTypes member) (listContains? target.exports member))) (none) (match (r/modSchema target member) ((some s) (some (pair s target))) ((none) (none))))))))) (match (r/modSchema mod head) ((some s) (some (pair s mod))) ((none) (lookupUnqualifiedSchemaInDeps head mod deps))))

fn schemaOfCtor head: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option (Pair r/SchemaSummary r/ModuleSummary))
  (schemaOfCtorIn head mod (r/depIndexOf deps))

fn pascalHead? head: String -> Bool
  (let [(seg (optionOr (listHead (listReverse (stringSplit head "/"))) head))] (and (not (stringEmpty? seg)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (r/firstCharStr seg))))

fn keywordAtom? e: rd/SExpr -> Bool
  (match e ((rd/sexprAtom v) (stringStartsWith? v ":")) (_ false))

fn recordCtorHead? head: String args: (List rd/SExpr) mod: r/ModuleSummary deps: r/DepIndex -> Bool
  (or (some? (schemaOfCtorIn head mod deps)) (and (pascalHead? head) (keywordAtom? (r/firstExprEmpty args))))

fn ctorKey e: rd/SExpr -> String
  (let [(raw (rd/sexprHead e))] (if (stringStartsWith? raw ":") (r/sliceFrom raw 1) raw))

fn fieldTypeIn f: r/FieldSummary vmap: (Map String ty/Type) owner: r/ModuleSummary deps: r/DepIndex -> ty/Type
  (qualifyTypeWithMod (substParsedType (ty/parseTypeStr f.type (list)) vmap) owner deps)

fn builtinFieldSummary ft: (Pair String String) -> r/FieldSummary
  (r/FieldSummary :name (pairFirst ft) :type (pairSecond ft) :hasDefault false)

fn checkerSchema mod: r/ModuleSummary name: String -> (Option r/SchemaSummary)
  (match (r/modSchema mod name)
    ((some schema) (some schema))
    ((none) (match (r/builtinSchemaFieldTypes name)
      ((none) (none))
      ((some fieldTypes) (some (r/SchemaSummary :name name :typevars (list) :fields (map builtinFieldSummary fieldTypes)))))))

fn inferCtorArgs fm: FrameMachine fields: (List r/FieldSummary) owner: r/ModuleSummary vmap: (Map String ty/Type) sname: String args: (List rd/SExpr) st: InferState -> InferState
  (if (< (listLength args) 2) st (let [(kname (ctorKey (r/firstExprEmpty args))) (vres (evalFm fm (r/secondExprEmpty args) st)) (st1 (pairSecond vres)) (st2 (match (listHead (filter (fn [(f r/FieldSummary)] -> Bool (= f.name kname)) fields)) ((none) st1) ((some f) (expectType st1 (pairFirst vres) (fieldTypeIn f vmap owner fm.deps) (str "field " kname " of " sname) fm.path owner.name))))] (inferCtorArgs fm fields owner vmap sname (r/safeTail (r/safeTail args)) st2)))

fn notRecordMessage fname: String t: ty/Type -> String
  (str "operand of .-" fname ": expected record, found " (typeText t) "; " (ty/showType t) " is not a record, so it has no field " fname)

fn withShapeMessage -> String
  "with takes a record and :field value pairs"

fn inferWithPairs fm: FrameMachine fields: (List r/FieldSummary) vmap: (Map String ty/Type) owner: r/ModuleSummary sname: String known: Bool args: (List rd/SExpr) st: InferState -> InferState
  (cond
    ((listEmpty? args) st)
    ((< (listLength args) 2) (addDiag st "ERR_ARITY" (withShapeMessage) fm.path))
    (else
      (let [(raw (rd/sexprHead (r/firstExprEmpty args)))
            (vres (evalFm fm (r/secondExprEmpty args) st))
            (st1 (pairSecond vres))
            (st2 (cond
                   ((not (stringStartsWith? raw ":")) (addDiag st1 "ERR_ARITY" (withShapeMessage) fm.path))
                   ((not known) st1)
                   (else (let [(kname (r/sliceFrom raw 1))]
                           (match (listHead (filter (fn [(f r/FieldSummary)] -> Bool (= f.name kname)) fields))
                             ((none) (addDiag st1 "ERR_FIELD" (str "with: " sname " has no field " kname) fm.path))
                             ((some f) (expectType st1 (pairFirst vres) (fieldTypeIn f vmap owner fm.deps) (str "field " kname " of with") fm.path owner.name)))))))]
        (inferWithPairs fm fields vmap owner sname known (r/safeTail (r/safeTail args)) st2))))

fn inferWith fm: FrameMachine args: (List rd/SExpr) -> (Pair ty/Type InferState)
  (let [(baseRes (evalFm fm (r/firstExprUnit args) fm.state))
        (baseTy (u/applySubst (pairSecond baseRes).subst (pairFirst baseRes)))
        (st1 (pairSecond baseRes))
        (pairs (r/safeTail args))
        (unchecked (fn [(st InferState)] -> (Pair ty/Type InferState) (pair (pairFirst baseRes) (inferWithPairs fm (list) (mapEmpty) fm.mod "" false pairs st))))]
    (match baseTy
      ((ty/tyCon tname targs toptMod _)
        (match (if (= tname "?") (none) (match toptMod ((some m) (moduleNamed m fm.mod fm.deps)) ((none) (some fm.mod))))
          ((none) (unchecked st1))
          ((some smod)
            (match (checkerSchema smod tname)
              ((some ssum) (pair (pairFirst baseRes) (inferWithPairs fm ssum.fields (buildTypeSubstMap ssum.typevars targs (mapEmpty)) smod ssum.name true pairs st1)))
              ((none) (unchecked (addDiag st1 "type" (str "record of with: expected record, found " (typeText baseTy)) fm.path)))))))
      ((ty/tyVar _ kind) (if (= kind "int") (unchecked (addDiag st1 "type" "record of with: expected record, found Int64" fm.path)) (unchecked st1)))
      (_ (unchecked st1))))

fn inferCtorForm fm: FrameMachine head: String args: (List rd/SExpr) st: InferState -> (Pair ty/Type InferState)
  (match (schemaOfCtorIn head fm.mod fm.deps)
    ((none) (freshVar (inferCtorArgs fm (list) fm.mod (mapEmpty) head args st) "any"))
    ((some found) (let [(sch (pairFirst found)) (owner (pairSecond found)) (tvars sch.typevars) (vRes (freshVarsFrom tvars (mapEmpty) st)) (vmap (pairFirst vRes)) (st1 (inferCtorArgs fm sch.fields owner vmap sch.name args (pairSecond vRes))) (targs (map (fn [(v String)] -> ty/Type (optionOr (mapGet vmap v) (unitType))) tvars)) (shown (if (stringContains? head "/") (some head) (none)))] (pair (ty/tyCon sch.name targs (some owner.name) shown) st1))))

fn fmCallStep cname: String cty: ty/Type argsDone: (List ty/Type) argsPending: (List rd/SExpr) cenv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (val (pairFirst pv)) (remValues (pairSecond pv)) (revDone (cons val argsDone))] (if (listEmpty? argsPending) (if (and (ty/genericMulti? cname) (and (not (mapHas? fm.env cname)) (ty/isTyVar? (u/applySubst fm.state.subst cty)))) (genericCallStep cname (listReverse revDone) remValues restFrames fm) (let [(prunedCallee (u/applySubst fm.state.subst cty))] (match prunedCallee ((ty/tyFun params ret) (let [(stUnify (foldExpectArgs (listReverse revDone) params cname fm.path fm.mod.name fm.state))] (with fm :frames restFrames :values (cons (u/applySubst stUnify.subst ret) remValues) :state stUnify))) (_ (let [(fRes (freshVar fm.state "any"))] (with fm :frames restFrames :values (cons (pairFirst fRes) remValues) :state (pairSecond fRes))))))) (let [(nextArg (r/firstExprUnit argsPending)) (remPending (r/safeTail argsPending))] (with fm :frames (cons (fEval nextArg) (cons (fCall cname cty revDone remPending cenv) restFrames)) :values remValues))))

fn genericCallStep cname: String args: (List ty/Type) remValues: (List ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(st fm.state)
        (recv (u/applySubst st.subst (optionOr (listHead args) (unitType))))
        (over (ty/receiverOver recv))
        (concrete (if (or (stringEmpty? over) (= over "?")) "" (ty/genericConcrete cname over)))
        (fr (freshVar st "any"))
        (st1 (cond ((stringEmpty? over) (deferSite (pairSecond fr) cname recv args (pairFirst fr)))
                   ((stringEmpty? concrete) (addDiag (pairSecond fr) "type" (str "argument 1 of " cname ": expected one of " (ty/genericCandidates cname) ", found " (typeText recv)) fm.path))
                   (else (resolveGenericCall cname concrete args (pairFirst fr) fm.mod fm.path (pairSecond fr)))))]
    (with fm :frames restFrames :values (cons (u/applySubst st1.subst (pairFirst fr)) remValues) :state st1))

fn resolveGenericCall cname: String concrete: String args: (List ty/Type) result: ty/Type mod: r/ModuleSummary path: String st: InferState -> InferState
  (match (lookupSysBuiltinSig concrete mod st)
    ((none) st)
    ((some res) (match (pairFirst res)
                  ((ty/tyFun params ret) (expectType (foldExpectArgs args params cname path mod.name (pairSecond res)) ret result (str "result of " cname) path mod.name))
                  (_ (pairSecond res)))))

fn resolveDeferred st: InferState mod: r/ModuleSummary path: String -> InferState
  (fold (fn [(acc InferState) (d Deferred)] -> InferState
          (let [(recv (u/applySubst acc.subst d.recv)) (over (ty/receiverOver recv)) (concrete (if (or (stringEmpty? over) (= over "?")) "" (ty/genericConcrete d.name over)))]
            (cond ((stringEmpty? over) (addDiag acc "ERR_AMBIGUOUS_OVERLOAD" (str d.name ": the receiver type is not known here; candidates " (ty/genericCandidates d.name) "; annotate the receiver") path))
                  ((stringEmpty? concrete) (addDiag acc "type" (str "argument 1 of " d.name ": expected one of " (ty/genericCandidates d.name) ", found " (typeText recv)) path))
                  (else (resolveGenericCall d.name concrete d.args d.result mod path acc)))))
        st (listReverse st.deferred))

fn variadicBuiltin? name: String -> Bool
  (or (= name "and") (or (= name "or") (= name "list")))

; (:m :ref LISTSUM :do "listSum and the sum alias are Int64 only; the hint names the Float64 entry, since the generic dispatch table keys on the receiver kind List and cannot see the element type")
fn sumHint cname: String -> String
  (if (or (= cname "listSum") (= cname "sum")) " (a List Float64 sums with listSumFloat64)" "")

fn foldExpectArgs args: (List ty/Type) params: (List ty/Type) cname: String path: String modName: String st: InferState -> InferState
  (match (listHead args) ((none) st) ((some a) (match (listHead params) ((none) st) ((some p) (let [(nextParams (match (listHead (r/safeTail params)) ((none) (if (variadicBuiltin? cname) params (list))) ((some _) (r/safeTail params)))) (st1 (expectType st a p (argContext cname) path modName))] (foldExpectArgs (r/safeTail args) nextParams cname path modName st1))))))

fn fmLetValStep bname: String brest: (List rd/SExpr) tails: (List rd/SExpr) lenv: (Map String ty/Type) annTy: (Option ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (val (pairFirst pv)) (remValues (pairSecond pv)) (nextEnv (mapSet lenv bname val)) (st0 (match annTy ((some t) (expectType fm.state val t "let binding" fm.path fm.mod.name)) ((none) fm.state)))] (if (listEmpty? brest) (let [(lastE (lastExprUnit tails))] (with fm :frames (cons (fEval lastE) restFrames) :values remValues :env nextEnv :state st0)) (let [(nextB (r/firstExprEmpty brest)) (flat? (match nextB ((rd/sexprAtom _) true) (_ false))) (remBrest (if flat? (r/safeTail (r/safeTail brest)) (r/safeTail brest))) (bparts (if flat? (list nextB (r/secondExprEmpty brest)) (match nextB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))) (nextBname (if flat? (rd/sexprHead nextB) (r/firstHeadIdent bparts))) (nextBval (letBindValue bparts))] (with fm :frames (cons (fEval nextBval) (cons (fLetVal nextBname remBrest tails nextEnv (letAnnType bparts fm.mod fm.deps)) restFrames)) :values remValues :env nextEnv :state (letAnnState st0 bparts fm.path)))))

fn fmIfCondStep thenE: rd/SExpr elseE: rd/SExpr ienv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (condTy (pairFirst pv)) (remValues (pairSecond pv)) (st1 (expectType fm.state condTy (ty/tyCon "Bool" (list) (none) (none)) "if condition" fm.path fm.mod.name))] (with fm :frames (cons (fEval thenE) (cons (fIfThen elseE condTy ienv) restFrames)) :values remValues :env ienv :state st1))

fn fmIfThenStep elseE: rd/SExpr thenTy: ty/Type ienv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (actualThen (pairFirst pv)) (remValues (pairSecond pv)) (elseRes (evalWithEnv fm elseE ienv fm.state)) (elseTy (pairFirst elseRes)) (st1 (expectType (pairSecond elseRes) elseTy actualThen "if branches disagree" fm.path fm.mod.name))] (with fm :frames restFrames :values (cons actualThen remValues) :env ienv :state st1))

fn fmTryStep valVar: ty/Type restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (innerTy (pairFirst pv)) (remValues (pairSecond pv)) (enclosing (match fm.retType ((some r) (u/applySubst fm.state.subst r)) ((none) (ty/tyCon "Result" (list valVar (unitType)) (none) (none))))) (errTy (match enclosing ((ty/tyCon _ rargs _ _) (match (listGet rargs 1) ((some e) e) ((none) (unitType)))) (_ (unitType)))) (wantRes (ty/tyCon "Result" (list valVar errTy) (none) (none))) (st1 (expectType fm.state innerTy wantRes "try" fm.path fm.mod.name))] (with fm :frames restFrames :values (cons valVar remValues) :state st1))

fn fmRun fm: FrameMachine budget: Int64 -> FrameMachine
  (let [(nextFm (fold fmTick fm (range 0 budget)))] (if (listEmpty? nextFm.frames) nextFm (fmRun nextFm (* budget 2))))

fn runExprDirect expr: rd/SExpr env: (Map String ty/Type) retType: (Option ty/Type) inLambda: Bool scope: String path: String mod: r/ModuleSummary deps: r/DepIndex st: InferState -> (Pair ty/Type InferState)
  (let [(initFm (FrameMachine :frames (list (fEval expr)) :values (list) :env env :retType retType :inLambda inLambda :scope scope :path path :mod mod :deps deps :state st))] (let [(finalFm (fmRun initFm 64))] (let [(outTy (match (listHead finalFm.values) ((some t) t) ((none) (unitType)))) (stNoted (noteMapType finalFm.state outTy scope))] (pair outTy stNoted))))

fn evalWithEnv fm: FrameMachine e: rd/SExpr env: (Map String ty/Type) st: InferState -> (Pair ty/Type InferState)
  (runExprDirect e env fm.retType fm.inLambda fm.scope fm.path fm.mod fm.deps st)

; (:m :ref TOP-LEVEL-CODE :do "a script statement is typed where it stands; its fresh diagnostics are pinned to its own line and column (a negative column marks them placed, checkModuleIn flips it back), and a Result-valued statement yields its ok type and leaves a scriptStep note naming its form number for elaborateScript")
fn scriptStepFm fm: FrameMachine restFrames: (List InferFrame) args: (List rd/SExpr) -> FrameMachine
  (let [(n (rd/sexprHead (optionOr (listGet args 0) (rd/makeAtom "0"))))
        (line (optionOr (stringToInt64 (rd/sexprHead (optionOr (listGet args 1) (rd/makeAtom "1")))) 1))
        (col (optionOr (stringToInt64 (rd/sexprHead (optionOr (listGet args 2) (rd/makeAtom "1")))) 1))
        (before (listLength fm.state.diags))
        (res (evalFm fm (optionOr (listGet args 3) (rd/makeAtom "()")) fm.state))
        (st1 (setDiags (pairSecond res) (placeFresh (pairSecond res).diags before (pair line (- 0 col)))))
        (t (u/applySubst st1.subst (pairFirst res)))]
    (match t
      ((ty/tyCon name targs _ _) (if (and (= name "Result") (= (listLength targs) 2))
                                   (with fm :frames restFrames :values (cons (optionOr (listHead targs) t) fm.values) :state (addDiag st1 "scriptStep" n fm.path))
                                   (with fm :frames restFrames :values (cons t fm.values) :state st1)))
      (_ (with fm :frames restFrames :values (cons t fm.values) :state st1))))

fn evalFm fm: FrameMachine e: rd/SExpr st: InferState -> (Pair ty/Type InferState)
  (evalWithEnv fm e fm.env st)

fn checkLiteralRanges intSites: (List (Pair String Int64)) subst: (Map Int64 ty/Type) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair String Int64))] -> (List ty/Diagnostic) (let [(tokStr (pairFirst site)) (vid (pairSecond site)) (wty (u/applySubst subst (ty/tyVar vid "int"))) (tname (match wty ((ty/tyCon n _ _ _) n) (_ "Int64")))] (match (ty/intRangeBounds tname) ((none) a) ((some b) (let [(low (pairFirst b)) (high (pairSecond b)) (numOpt (nk/parseIntLit tokStr)) (badLit? (match numOpt ((none) true) ((some n) (or (< n low) (> n high)))))] (if badLit? (let [(msg (str "the literal " tokStr " does not fit " tname " (" (stringFromInt64 low) ".." (stringFromInt64 high) ")"))] (cons (ty/Diagnostic :code "literal-range" :message msg :msg msg :line 1 :col 1 :path path) a)) a)))))) acc intSites)

fn mapHasKey? m: (Map String Bool) k: String -> Bool
  (match (mapGet m k) ((some _) true) ((none) false))

fn extractMapKeysList types: (List ty/Type) subst: (Map Int64 ty/Type) -> (List ty/Type)
  (fold (fn [(acc (List ty/Type)) (t ty/Type)] -> (List ty/Type) (listAppend (extractMapKeys t subst) acc)) (list) types)

fn extractMapKeys t: ty/Type subst: (Map Int64 ty/Type) -> (List ty/Type)
  (let [(pruned (u/applySubst subst t))] (match pruned ((ty/tyCon name args _ _) (let [(subKeys (extractMapKeysList args subst))] (if (and (= name "Map") (>= (listLength args) 1)) (cons (optionOr (listHead args) pruned) subKeys) subKeys))) ((ty/tyFun params ret) (listAppend (extractMapKeys ret subst) (extractMapKeysList params subst))) ((ty/tyVar _ _) (list))))

fn checkTypeUnordered t: ty/Type subst: (Map Int64 ty/Type) visited: (Map String Bool) mod: r/ModuleSummary deps: r/DepIndex -> (Option String)
  (let [(pruned (u/applySubst subst t))] (match pruned ((ty/tyVar _ _) (none)) ((ty/tyFun _ _) (none)) ((ty/tyCon name args optMod _) (if (ty/unorderedType? name) (some name) (let [(badArg (fold (fn [(acc (Option String)) (a ty/Type)] -> (Option String) (match acc ((some _) acc) ((none) (checkTypeUnordered a subst visited mod deps)))) (none) args))] (match badArg ((some b) (some b)) ((none) (let [(typeKey (str (optionOr optMod mod.name) "/" name))] (if (mapHasKey? visited typeKey) (none) (let [(nextVis (mapSet visited typeKey true)) (targetMod (match optMod ((some m) (moduleNamed m mod deps)) ((none) (some mod))))] (match targetMod ((none) (none)) ((some tmod) (match (r/modSchema tmod name) ((some ssum) (fold (fn [(acc (Option String)) (f r/FieldSummary)] -> (Option String) (match acc ((some _) acc) ((none) (let [(fty (ty/parseTypeStr f.type (list)))] (checkTypeUnordered fty subst nextVis tmod deps))))) (none) ssum.fields)) ((none) (match (r/modEnum tmod name) ((some esum) (fold (fn [(acc (Option String)) (c r/CaseSummary)] -> (Option String) (match acc ((some _) acc) ((none) (fold (fn [(cacc (Option String)) (p (Pair String String))] -> (Option String) (match cacc ((some _) cacc) ((none) (let [(pty (qualifyTypeWithMod (ty/parseTypeStr (pairSecond p) (list)) mod deps))] (checkTypeUnordered pty subst nextVis tmod deps))))) acc c.params)))) (none) esum.cases)) ((none) (none)))))))))))))))))

fn checkMapKeyRules mapSites: (List (Pair ty/Type String)) subst: (Map Int64 ty/Type) mod: r/ModuleSummary deps: r/DepIndex path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair ty/Type String))] -> (List ty/Diagnostic) (let [(tySite (pairFirst site)) (scopeLbl (pairSecond site)) (mkeys (extractMapKeys tySite subst))] (fold (fn [(ka (List ty/Diagnostic)) (k ty/Type)] -> (List ty/Diagnostic) (match (checkTypeUnordered k subst (mapEmpty) mod deps) ((none) ka) ((some bad) (let [(shown (ty/showType k)) (msg (if (= shown bad) (str shown " as a Map key has no total order; mapKeys is specified to return keys sorted") (str "the Map key " shown " reaches " bad ", which has no total order; mapKeys is specified to return keys sorted")))] (cons (ty/Diagnostic :code "map-key-order" :message msg :msg msg :line 1 :col 1 :path path) ka))))) a mkeys))) acc mapSites)

fn bodyDiagPos d: a/DefunNode idx: Int64 ds: (List ty/Diagnostic) -> (Pair Int64 Int64)
  (let [(pos (r/bodyPosAt d idx))
        (expr (optionOr (listGet d.body idx) (rd/makeAtom "")))
        (unknown (listAny? (fn [(diag ty/Diagnostic)] -> Bool (or (= diag.code "rule-1") (= diag.code "rule-2"))) ds))]
    (match expr ((rd/sexprList _) (if (and unknown (> (pairSecond pos) 0)) (pair (pairFirst pos) (+ (pairSecond pos) 1)) pos)) (_ pos)))

fn paramInferType p: a/Param summary: r/ModuleSummary deps: r/DepIndex vmap: (Map String ty/Type) -> ty/Type
  (if (stringEmpty? p.type) (ty/tyCon "?" (list) (none) (none)) (qualifyTypeWithMod (substParsedType (ty/parseTypeStr p.type (list)) vmap) summary deps))

fn defunTvars d: a/DefunNode -> (List String)
  (if (listEmpty? d.typeVars) (ty/collectTvars (map (fn [(p a/Param)] -> String p.type) d.params) d.retType) d.typeVars)

fn checkDefunDiags d: a/DefunNode summary: r/ModuleSummary deps: r/DepIndex path: String -> (List ty/Diagnostic)
  (let [(st00 (makeInferState)) (tvRes (freshVarsFrom (defunTvars d) (mapEmpty) st00)) (vmap (pairFirst tvRes)) (st0 (pairSecond tvRes)) (env0 (fold (fn [(e (Map String ty/Type)) (p a/Param)] -> (Map String ty/Type) (mapSet e p.name (paramInferType p summary deps vmap))) (mapEmpty) d.params)) (retTy (qualifyTypeWithMod (substParsedType (ty/parseTypeStr d.retType (list)) vmap) summary deps)) (scopeName (str "function " d.name)) (stParams (fold (fn [(s InferState) (p a/Param)] -> InferState (noteMapType s (paramInferType p summary deps vmap) scopeName)) st0 d.params)) (stNote (noteMapType stParams retTy scopeName)) (bodyNodes d.body)]
    (if (listEmpty? bodyNodes) (list)
      (let [(allBodyRes (fold (fn [(accRes (Pair ty/Type InferState)) (ie (Pair Int64 rd/SExpr))] -> (Pair ty/Type InferState) (let [(i (pairFirst ie)) (e (pairSecond ie)) (before (listLength (pairSecond accRes).diags)) (res (runExprDirect e env0 (some retTy) false scopeName path summary deps (pairSecond accRes))) (pos (bodyDiagPos d i (pairSecond res).diags))] (pair (pairFirst res) (setDiags (pairSecond res) (placeFresh (pairSecond res).diags before pos))))) (pair (unitType) stNote) (zip (range 0 (listLength bodyNodes)) bodyNodes))) (lastTy (pairFirst allBodyRes)) (st1 (pairSecond allBodyRes)) (placed (listLength st1.diags)) (st2 (resolveDeferred (expectType st1 lastTy retTy (str "return of " d.name) path summary.name) summary path)) (st3Subst st2.subst) (dLit (checkLiteralRanges st2.intSites st3Subst path st2.diags)) (dMap (checkMapKeyRules st2.mapSites st3Subst summary deps path dLit))]
        (placeFresh dMap placed (bodyDiagPos d (- (listLength bodyNodes) 1) st2.diags)))))

fn untypedParamDiags d: a/DefunNode path: String -> (List ty/Diagnostic)
  (let [(pos (r/bodyPosAt d 0))] (map (fn [(p a/Param)] -> ty/Diagnostic (let [(msg (str "function " d.name " parameter " p.name " has no type annotation"))] (ty/Diagnostic :code "ERR_UNTYPED_PARAM" :message msg :msg msg :line (pairFirst pos) :col (pairSecond pos) :path path))) (filter (fn [(p a/Param)] -> Bool (stringEmpty? p.type)) d.params)))

fn typePhaseCode? code: String -> Bool
  (or (= code "ERR_TYPE_MISMATCH") (or (= code "ERR_UNTYPED_PARAM") (= code "ERR_INVALID_MT_ARM")))

fn typeBoundary ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (if (listAny? (fn [(d ty/Diagnostic)] -> Bool (not (or (typePhaseCode? d.code) (or (= d.code "ERR_NOT_EXPORTED") (or (= d.code "ERR_EFFECT_UNMARKED") (= d.code "scriptStep")))))) ds)
    (filter (fn [(d ty/Diagnostic)] -> Bool (not (typePhaseCode? d.code))) ds)
    ds)

; (:m :ref CHECK-OPTION-ARITH-20261016 :do "typeBoundary used to be applied once over the whole module's diagnostics; any unrelated non-type diagnostic anywhere in the file (an unknown symbol in a function nobody is looking at) silently dropped every ERR_TYPE_MISMATCH in the file, including an unguarded Option operand reaching +/-/*// that only fails at native runtime with ERR_TYPE; typeBoundary now scopes to each function's own diagnostics in checkModuleIn's defunDiags fold, so a real type mismatch in one function is no longer hidden by an unrelated resolve error in a different one, while a genuine same-function cascade (an unresolved symbol and the type noise it causes in that same function) still gets the suppression it was built for")
; (:m :ref CHECKER-R1GAPS :do "resolve.asl places every ERR_NOT_EXPORTED at its statement's enclosing position (the only position the resolve walk tracks), never at the offending alias/member, type name or bare case tag; every one of its three message shapes starts 'ERR_NOT_EXPORTED: <name> is not ...', so refineNotExportedDiag recovers <name> from the already-finalized message text (depIndexTest asserts that text verbatim, so it is read here, not changed) and resolves the real position via a/findQualifiedTokenPos from the diagnostic's own (coarse) position as the search floor")
fn extractNotExportedName msg: String -> (Option String)
  (let [(prefix "ERR_NOT_EXPORTED: ")]
    (match (stringIndexOf msg prefix)
      ((none) (none))
      ((some i0)
        (let [(rest (optionOr (stringSlice msg (+ i0 (stringLength prefix)) (stringLength msg)) ""))]
          (match (stringIndexOf rest " is not ")
            ((none) (none))
            ((some j) (some (optionOr (stringSlice rest 0 j) ""))))))))

fn refineNotExportedDiag src: String d: ty/Diagnostic floor: (Pair Int64 Int64) -> ty/Diagnostic
  (let [(pos (a/findQualifiedTokenPos src (pairFirst floor) (pairSecond floor) (optionOr (extractNotExportedName d.message) "")))]
    (ty/Diagnostic :code d.code :message d.message :msg d.msg :line (pairFirst pos) :col (pairSecond pos) :path d.path))

; (:m :ref CHECKER-R1GAPS :do "unexportedBareCtorTest references the same unexported name twice in one function body (a bare value atom, then a bare match-arm pattern); both diagnostics share the function's one coarse floor, so searching for the same needle from the same floor independently landed both on the SAME first occurrence instead of their own; refineNotExportedPositions folds instead of mapping, remembering per distinct name the line:col just past its last match so the next occurrence of that same name searches forward from there, while an unrelated name (or the first occurrence of this one) still searches from the diagnostic's own floor")
fn refineNotExportedPositions src: String ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (listReverse (pairSecond (fold (fn [(acc (Pair (Map String (Pair Int64 Int64)) (List ty/Diagnostic))) (d ty/Diagnostic)] -> (Pair (Map String (Pair Int64 Int64)) (List ty/Diagnostic))
                                    (let [(seen (pairFirst acc)) (outAcc (pairSecond acc))]
                                      (if (= d.code "rule-9")
                                        (match (extractNotExportedName d.message)
                                          ((none) (pair seen (cons d outAcc)))
                                          ((some name)
                                           (let [(floor (optionOr (mapGet seen name) (pair d.line d.col)))
                                                 (nd (refineNotExportedDiag src d floor))]
                                             (pair (mapSet seen name (pair nd.line (+ nd.col 1))) (cons nd outAcc)))))
                                        (pair seen (cons d outAcc)))))
                                  (pair (mapEmpty) (list)) ds)))

; (:m :ref CHECK-DIAG-SYMBOL-POS :do "the checker tracks diagnostics per body statement, so an unknown symbol nested in a let body or a call was reported at the statement; the symbol name is read back from the finalized message (rule-1 'unbound symbol: X', rule-2 'X is not defined') and its real line:col is found in the source from the statement position, the next occurrence of the same name searching from just past the previous one")
fn unknownSymbolName d: ty/Diagnostic -> (Option String)
  (let [(prefix "unbound symbol: ") (suffix " is not defined")]
    (cond
      ((= d.code "rule-1")
       (match (stringIndexOf d.message prefix)
         ((none) (none))
         ((some i0)
           (let [(rest (optionOr (stringSlice d.message (+ i0 (stringLength prefix)) (stringLength d.message)) ""))]
             (some (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ";")) rest) " ")) rest))))))
      ((and (= d.code "rule-2") (stringEndsWith? d.message suffix))
       (some (optionOr (stringSlice d.message 0 (- (stringLength d.message) (stringLength suffix))) "")))
      (else (none))))

fn formStartLine f: a/TopForm -> Int64
  (match f
    ((a/topDefun d) (match (listHead d.bodyPos) ((some p) p.line) ((none) 0)))
    ((a/topExpr p) p.line)
    (_ 0))

fn regionStarts forms: (List a/TopForm) -> (List Int64)
  (listSort (filter (fn [(k Int64)] -> Bool (> k 0)) (map formStartLine forms)))

fn regionOf starts: (List Int64) line: Int64 -> (Pair Int64 Int64)
  (pair (fold (fn [(best Int64) (k Int64)] -> Int64 (if (<= k line) k best)) 0 starts)
        (fold (fn [(best Int64) (k Int64)] -> Int64 (if (and (> k line) (< k best)) k best)) 9223372036854775807 starts))

fn refineUnknownSymbolPositions forms: (List a/TopForm) src: String ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (let [(starts (regionStarts forms))]
  (listReverse (pairSecond (fold (fn [(acc (Pair (Map String (Pair Int64 Int64)) (List ty/Diagnostic))) (d ty/Diagnostic)] -> (Pair (Map String (Pair Int64 Int64)) (List ty/Diagnostic))
                                    (let [(seen (pairFirst acc)) (outAcc (pairSecond acc))]
                                      (match (unknownSymbolName d)
                                        ((none) (pair seen (cons d outAcc)))
                                        ((some name)
                                          (let [(region (regionOf starts d.line))
                                                (key (str d.code " " name " " (stringFromInt64 (pairFirst region))))
                                                (floor (optionOr (mapGet seen key) (pair d.line d.col)))
                                                (found (a/findTokenPos src (pairFirst floor) (pairSecond floor) name))
                                                (pos (if (>= (pairFirst found) (pairSecond region)) (pair d.line d.col) found))
                                                (nd (ty/Diagnostic :code d.code :message d.message :msg d.msg :line (pairFirst pos) :col (pairSecond pos) :path d.path))]
                                            (pair (mapSet seen key (pair nd.line (+ nd.col 1))) (cons nd outAcc)))))))
                                  (pair (mapEmpty) (list)) ds))))

fn armCtor? x: String -> Bool
  (or (= x "some") (or (= x "ok") (or (= x "err") (= x "none"))))

fn binderAtom? x: String -> Bool
  (and (not (= x "_")) (and (not (r/isLiteralAtom? x)) (not (stringStartsWith? x ":"))))

fn patternBinders pat: rd/SExpr -> (List String)
  (match pat
    ((rd/sexprAtom x) (if (binderAtom? x) (list x) (list)))
    ((rd/sexprList items) (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String) (listAppend acc (patternBinders it))) (list) (listDrop items 1)))
    ((rd/sexprVect items) (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String) (listAppend acc (patternBinders it))) (list) items)))

fn atomText e: rd/SExpr -> String
  (match e ((rd/sexprAtom x) x) (_ ""))

fn vectorArmHints items: (List rd/SExpr) -> (List (Pair String (Pair String String)))
  (match (optionOr (listHead items) (rd/makeAtom ""))
    ((rd/sexprList pitems)
     (let [(ctor (atomText (optionOr (listHead pitems) (rd/makeAtom ""))))
           (hint (str "; hint: a match arm is a list ((" ctor " v) body), not a vector [(" ctor " v) body]"))]
       (map (fn [(b String)] -> (Pair String (Pair String String)) (pair b (pair (str "[(" ctor) hint))) (patternBinders (rd/makeList pitems)))))
    (_ (list)))

fn armHints arm: rd/SExpr -> (List (Pair String (Pair String String)))
  (match arm
    ((rd/sexprVect items) (vectorArmHints items))
    ((rd/sexprList items)
     (let [(ctor (atomText (optionOr (listHead items) (rd/makeAtom ""))))]
       (if (= ctor "list")
         (vectorArmHints (listDrop items 1))
       (if (and (armCtor? ctor) (>= (listLength items) 2))
         (let [(hint (str "; hint: the arm (" ctor " v) is read as a catch-all binding " ctor " with body v; a match arm wraps its pattern: ((" ctor " v) body)"))]
           (map (fn [(b String)] -> (Pair String (Pair String String)) (pair b (pair (str "(" ctor " " b) hint))) (filter binderAtom? (map atomText (listDrop items 1)))))
         (list)))))
    (_ (list)))

fn exprArmHints e: rd/SExpr -> (List (Pair String (Pair String String)))
  (match e
    ((rd/sexprAtom _) (list))
    ((rd/sexprVect items) (fold (fn [(acc (List (Pair String (Pair String String)))) (it rd/SExpr)] -> (List (Pair String (Pair String String))) (listAppend acc (exprArmHints it))) (list) items))
    ((rd/sexprList items)
     (let [(inner (fold (fn [(acc (List (Pair String (Pair String String)))) (it rd/SExpr)] -> (List (Pair String (Pair String String))) (listAppend acc (exprArmHints it))) (list) items))]
       (if (= (atomText (optionOr (listHead items) (rd/makeAtom ""))) "match")
         (listAppend (fold (fn [(acc (List (Pair String (Pair String String)))) (arm rd/SExpr)] -> (List (Pair String (Pair String String))) (listAppend acc (armHints arm))) (list) (listDrop items 2)) inner)
         inner))))

fn moduleArmHints forms: (List a/TopForm) -> (List (Pair String (Pair String String)))
  (fold (fn [(acc (List (Pair String (Pair String String)))) (f a/TopForm)] -> (List (Pair String (Pair String String)))
          (match f
            ((a/topDefun d) (listAppend acc (fold (fn [(xs (List (Pair String (Pair String String)))) (e rd/SExpr)] -> (List (Pair String (Pair String String))) (listAppend xs (exprArmHints e))) (list) d.body)))
            ((a/topExpr p) (listAppend acc (exprArmHints p.expr)))
            (_ acc)))
        (list) forms)

fn armHintAt hints: (List (Pair String (Pair String String))) lines: (List String) name: String line: Int64 -> (Option String)
  (let [(here (optionOr (listGet lines (- line 1)) ""))
        (hit (filter (fn [(h (Pair String (Pair String String)))] -> Bool (and (= (pairFirst h) name) (stringContains? here (pairFirst (pairSecond h))))) hints))]
    (match (listHead hit) ((none) (none)) ((some h) (some (pairSecond (pairSecond h))))))

fn armShapeHints forms: (List a/TopForm) src: String ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (let [(hints (moduleArmHints forms))]
    (if (listEmpty? hints)
      ds
      (let [(lines (stringSplit src "\n"))]
        (map (fn [(d ty/Diagnostic)] -> ty/Diagnostic
               (match (unknownSymbolName d)
                 ((none) d)
                 ((some name) (match (armHintAt hints lines name d.line) ((none) d) ((some h) (with d :message (str d.message h) :msg (str d.msg h)))))))
             ds))))

fn pairFieldMistake? msg: String -> Bool
  (listAny? (fn [(f String)] -> Bool (or (stringEndsWith? msg (str " field " f)) (stringContains? msg (str " field " f ";"))))
            (list "fst" "snd" "first" "second"))

fn mapEmptyMistake? d: ty/Diagnostic -> Bool
  (or (and (= d.code "ERR_ARITY") (and (stringStartsWith? d.message "map takes ") (stringEndsWith? d.message "given 0")))
      (and (= d.code "ERR_TYPE_MISMATCH") (and (stringContains? d.message "expected (Map ") (stringContains? d.message "found (List _)"))))

fn messageHint d: ty/Diagnostic -> ty/Diagnostic
  (let [(hint (cond
                ((mapEmptyMistake? d) "; hint: the empty map is (mapEmpty); map is the list function")
                ((and (pairFieldMistake? d.message) (or (and (= d.code "ERR_UNKNOWN_SYMBOL") (stringContains? d.message "has a field")) (and (= d.code "ERR_TYPE_MISMATCH") (stringContains? d.message "found (Pair ")))) "; hint: read a pair with (pairFirst p) and (pairSecond p)")
                (else "")))]
    (if (stringEmpty? hint) d (with d :message (str d.message hint) :msg (str d.msg hint))))

fn checkModuleSource forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String src: String -> (List ty/Diagnostic)
  (map messageHint (normalizeCheckDiags (armShapeHints forms src (refineUnknownSymbolPositions forms src (refineNotExportedPositions src (listAppend (checkModule forms deps path) (listAppend (tp/notTailDiags forms src path) (listAppend (ca/constantAssertDiags forms src path) (r/letrecDiags forms path src)))))))))

fn checkDefunWithUntyped d: a/DefunNode summary: r/ModuleSummary deps: r/DepIndex path: String -> (List ty/Diagnostic)
  (listAppend (untypedParamDiags d path) (checkDefunDiags d summary deps path))

fn checkExprDiags p: a/PosForm summary: r/ModuleSummary deps: r/DepIndex path: String -> (List ty/Diagnostic)
  (let [(st0 (makeInferState)) (scopeName "top-level expression") (pos (pair p.line p.col)) (res (runExprDirect p.expr (mapEmpty) (none) false scopeName path summary deps st0)) (st1 (setDiags (pairSecond res) (placeFresh (pairSecond res).diags 0 pos))) (placed (listLength st1.diags)) (st1Subst st1.subst) (dLit (checkLiteralRanges st1.intSites st1Subst path st1.diags)) (dMap (checkMapKeyRules st1.mapSites st1Subst summary deps path dLit))]
    (placeFresh dMap placed pos))

fn checkLintCode? code: String -> Bool
  (or (= code "rule-10")
    (or (= code "rule-13") (= code "type-arity")))

fn isCheckLint d: ty/Diagnostic -> Bool
  (or (checkLintCode? d.code) (lintDiagnosticMessage? d))

fn lintDiagnosticMessage? d: ty/Diagnostic -> Bool
  (or (stringContains? d.message "is exported but not defined in this module") (and (= d.code "builtin-reference") (stringContains? d.message "is a builtin, not a value")))

fn hostCheckCode code: String -> String
  (cond ((= code "rule-1") "ERR_UNKNOWN_SYMBOL") ((= code "rule-2") "ERR_UNKNOWN_SYMBOL") ((= code "rule-12") "ERR_EFFECT_UNMARKED") ((= code "unresolved-import") "ERR_UNRESOLVED_IMPORT") ((= code "arity") "ERR_ARITY") ((= code "ctor") "ERR_BAD_CONSTRUCTOR") ((= code "type") "ERR_TYPE_MISMATCH") ((= code "rule-6") "ERR_TYPE_MISMATCH") ((= code "rule-4") "ERR_MATCH_NONEXHAUSTIVE") ((= code "literal-range") "ERR_INT_RANGE") ((= code "else-keyword") "ERR_ELSE_KEYWORD") ((= code "unreachable-arm") "ERR_UNREACHABLE_ARM") (else code))

fn hostCheckDiagCode d: ty/Diagnostic -> String
  (if (= d.code "rule-9") (if (stringContains? d.message "ERR_NOT_EXPORTED") "ERR_NOT_EXPORTED" "ERR_UNRESOLVED_IMPORT") (hostCheckCode d.code))

fn normalizeCheckDiag d: ty/Diagnostic -> ty/Diagnostic
  (ty/Diagnostic :code (hostCheckDiagCode d) :message d.message :msg d.msg :line d.line :col d.col :path d.path)

fn redundantUnknownRule2? d: ty/Diagnostic ds: (List ty/Diagnostic) -> Bool
  (and (= d.code "rule-2") (listAny? (fn [(other ty/Diagnostic)] -> Bool (and (= other.code "rule-1") (and (= other.path d.path) (and (= other.line d.line) (<= (- other.col d.col) 1) (<= (- d.col other.col) 1))))) ds))

fn normalizeCheckDiags ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (map normalizeCheckDiag (filter (fn [(d ty/Diagnostic)] -> Bool (and (not (isCheckLint d)) (not (redundantUnknownRule2? d ds)))) ds))

fn checkModule forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (checkModuleIn forms (r/depIndexOf deps) path)

fn unpinned d: ty/Diagnostic -> ty/Diagnostic
  (if (< d.col 0) (with d :col (- 0 d.col)) d)

fn okZero -> rd/SExpr
  (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "0")))

fn scriptFail sp: (List rd/SExpr) -> rd/SExpr
  (let [(n (rd/sexprHead (optionOr (listGet sp 0) (rd/makeAtom "0")))) (e (str "__scriptErr" n))]
    (rd/makeList (list (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom e)))
                       (rd/makeList (list (rd/makeAtom "preludeScriptFail") (optionOr (listGet sp 0) (rd/makeAtom "0")) (optionOr (listGet sp 1) (rd/makeAtom "0")) (rd/makeList (list (rd/makeAtom "str") (rd/makeAtom e))))))))

fn scriptCheck sp: (List rd/SExpr) binder: rd/SExpr body: rd/SExpr -> rd/SExpr
  (rd/makeList (list (rd/makeAtom "match") (optionOr (listGet sp 3) (rd/makeAtom "()")) (rd/makeList (list (rd/makeList (list (rd/makeAtom "ok") binder)) body)) (scriptFail sp)))

fn stepResult? steps: (Map String Bool) sp: (List rd/SExpr) -> Bool
  (mapHas? steps (rd/sexprHead (optionOr (listGet sp 0) (rd/makeAtom "0"))))

fn doCons x: rd/SExpr rest: rd/SExpr -> rd/SExpr
  (if (= (rd/sexprHead rest) "do") (rd/makeList (cons (rd/makeAtom "do") (cons x (r/safeTail (rd/sexprToList rest))))) (rd/makeList (list (rd/makeAtom "do") x rest)))

fn elabSeq steps: (Map String Bool) xs: (List rd/SExpr) -> rd/SExpr
  (match (listHead xs)
    ((none) (okZero))
    ((some x) (let [(rest (r/safeTail xs))]
                (if (listEmpty? rest)
                  (elabSpine steps x)
                  (match (a/scriptStepParts x)
                    ((none) (doCons x (elabSeq steps rest)))
                    ((some sp) (if (stepResult? steps sp)
                                 (scriptCheck sp (rd/makeAtom (str "__scriptOk" (rd/sexprHead (optionOr (listHead sp) (rd/makeAtom "0"))))) (elabSeq steps rest))
                                 (doCons (optionOr (listGet sp 3) x) (elabSeq steps rest)))))))))

fn letOne b: rd/SExpr body: rd/SExpr -> rd/SExpr
  (rd/makeList (list (rd/makeAtom "let") (rd/makeVect (list b)) body))

fn elabBinds steps: (Map String Bool) bs: (List rd/SExpr) body: rd/SExpr -> rd/SExpr
  (match (listHead bs)
    ((none) (elabSpine steps body))
    ((some b) (let [(items (rd/sexprToList b)) (k (listLength items)) (inner (elabBinds steps (r/safeTail bs) body))
                    (front (listTake items (- k 1))) (v (optionOr (listGet items (- k 1)) (rd/makeAtom "()")))]
                (match (a/scriptStepParts v)
                  ((none) (letOne b inner))
                  ((some sp) (if (stepResult? steps sp)
                               (let [(tmp (rd/makeAtom (str "__scriptOk" (rd/sexprHead (optionOr (listHead sp) (rd/makeAtom "0"))))))]
                                 (scriptCheck sp tmp (letOne (rd/makeList (listAppend front (list tmp))) inner)))
                               (letOne (rd/makeList (listAppend front (list (optionOr (listGet sp 3) v)))) inner)))))))

fn pairBinds items: (List rd/SExpr) -> (List rd/SExpr)
  (if (rd/isAtom? (optionOr (listHead items) (rd/makeAtom "")))
    (map (fn [(i Int64)] -> rd/SExpr (rd/makeList (list (optionOr (listGet items (* i 2)) (rd/makeAtom "_")) (optionOr (listGet items (+ (* i 2) 1)) (rd/makeAtom "()"))))) (range 0 (/ (listLength items) 2)))
    items)

fn elabSpine steps: (Map String Bool) e: rd/SExpr -> rd/SExpr
  (let [(items (rd/sexprToList e)) (h (rd/sexprHead e))]
    (cond ((and (rd/isList? e) (= h "do")) (elabSeq steps (r/safeTail items)))
          ((and (rd/isList? e) (and (= h "let") (= (listLength items) 3))) (elabBinds steps (pairBinds (rd/sexprToList (optionOr (listGet items 1) (rd/makeVect (list))))) (optionOr (listGet items 2) (okZero))))
          (else (match (a/scriptStepParts e) ((some sp) (optionOr (listGet sp 3) e)) ((none) e)))))

fn spineHasStep? e: rd/SExpr -> Bool
  (let [(items (rd/sexprToList e)) (h (rd/sexprHead e))]
    (cond ((some? (a/scriptStepParts e)) true)
          ((and (rd/isList? e) (= h "do")) (listAny? spineHasStep? (r/safeTail items)))
          ((and (rd/isList? e) (= h "let")) (or (listAny? (fn [(b rd/SExpr)] -> Bool (listAny? spineHasStep? (rd/sexprToList b))) (rd/sexprToList (optionOr (listGet items 1) (rd/makeVect (list))))) (spineHasStep? (optionOr (listGet items 2) (okZero)))))
          (else false)))

; (:m :ref SCRIPT-ENTRY :do "the parser ends a sugared main in preludeMainDone to check its last statement as Unit; a mismatch there names the statement, not the hook")
fn argContext cname: String -> String
  (if (= cname "preludeMainDone") "the last statement of main" (str "argument to " cname (sumHint cname)))

; (:m :ref SCRIPT-ENTRY :do "a sugared main (no ->) gets the script rule for its statements before the last: each is marked with its number and position, so one that checks as a Result exits through preludeScriptFail on err; the parser keeps the plain body so printers and tools never see the markers")
fn sugaredMain? d: a/DefunNode -> Bool
  (and (= d.name "main") (and (= d.retType "(Result Unit String)") (and (> (listLength d.body) 1)
    (and (not (listAny? spineHasStep? d.body)) (= (rd/sexprHead (optionOr (listGet d.body (- (listLength d.body) 1)) (rd/makeAtom ""))) "preludeMainDone")))))

fn markStatement d: a/DefunNode i: Int64 -> rd/SExpr
  (let [(e (optionOr (listGet d.body i) (rd/makeAtom "()")))]
    (if (= i (- (listLength d.body) 1)) e (a/scriptStepAt (+ i 1) (optionOr (listGet d.bodyPos i) (a/PosForm :expr e :line 0 :col 0)) e)))

fn markSugared t: a/TopForm -> a/TopForm
  (match t ((a/topDefun d) (if (sugaredMain? d) (a/topDefun (withBody d (map (fn [(i Int64)] -> rd/SExpr (markStatement d i)) (range 0 (listLength d.body))))) t)) (_ t))

fn needsElaboration? forms: (List a/TopForm) -> Bool
  (listAny? (fn [(t a/TopForm)] -> Bool (or (scriptMainOf? t) (match t ((a/topDefun d) (sugaredMain? d)) (_ false)))) forms)

fn scriptMainOf? t: a/TopForm -> Bool
  (match t ((a/topDefun d) (and (= d.name "main") (listAny? spineHasStep? d.body))) (_ false))

fn withBody d: a/DefunNode body: (List rd/SExpr) -> a/DefunNode
  (with d :body body)

; (:m :ref TOP-LEVEL-CODE :do "elaborateScript is the one type-directed rewrite of a script's synthesised main: every preludeScriptStep marker whose statement checks as a Result becomes a match that binds its ok value and otherwise calls preludeScriptFail with the form number and line; every other marker is dropped; the linker runs it, so no marker reaches lowering")
fn elaborateScript forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String -> (List a/TopForm)
  (if (not (needsElaboration? forms))
    forms
    (elaborateMarked (map markSugared forms) deps path))

fn elaborateMarked forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String -> (List a/TopForm)
  (let [(notes (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "scriptStep")) (checkModuleNoted forms (r/depIndexOf deps) path)))
          (steps (fold (fn [(m (Map String Bool)) (d ty/Diagnostic)] -> (Map String Bool) (mapSet m d.message true)) (mapEmpty) notes))]
      (map (fn [(t a/TopForm)] -> a/TopForm (match t ((a/topDefun d) (if (scriptMainOf? t) (a/topDefun (withBody d (list (elabSeq steps d.body)))) t)) (_ t))) forms))

fn checkModuleIn forms: (List a/TopForm) deps: r/DepIndex path: String -> (List ty/Diagnostic)
  (filter (fn [(d ty/Diagnostic)] -> Bool (!= d.code "scriptStep")) (checkModuleNoted forms deps path))

fn checkModuleNoted forms: (List a/TopForm) deps: r/DepIndex path: String -> (List ty/Diagnostic)
  (let [(summary0 (r/collectSummary forms path))
        (existingMod (match (mapGet deps.deps path)
                       ((some m) (some m))
                       ((none) (match (r/resolveDepIn path deps)
                                 ((ok m) (some m))
                                 ((err _) (none))))))
        (summary (match existingMod
                   ((some m) (r/withImports summary0 m.imports))
                   ((none) summary0)))
        (p12Diags (r/resolveModuleIn summary forms deps)) (defunDiags (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic) (match form ((a/topDefun d) (listAppend (typeBoundary (checkDefunWithUntyped d summary deps path)) acc)) ((a/topExpr p) (listAppend (typeBoundary (checkExprDiags p summary deps path)) acc)) (_ acc))) (list) forms))] (map unpinned (listAppend p12Diags (listAppend (ff/foreignDiags forms path) defunDiags))))

fn parseErrDiag pe: a/ParseError path: String -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message pe.msg :msg pe.msg :line pe.line :col pe.col :path path))

fn checkSource src: String deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (match (a/parseForChecker src) ((ok forms) (checkModule forms deps path)) ((err pe) (parseErrDiag pe path)))

fn ! checkFile! path: String roots: (List String) -> (Result (List ty/Diagnostic) String)
  (match (fileReadString path) ((err ioErr) (err ioErr)) ((ok src) (match (a/parseForTypeCheck src) ((err pe) (ok (parseErrDiag pe path))) ((ok forms) (let [(summary (r/collectSummary forms path)) (importPaths (r/mapValuesList summary.imports)) (allRoots (cons (optionOr (parentDir path) ".") roots))] (match (r/loadModuleDeps! allRoots importPaths) ((err ioErr2) (err ioErr2)) ((ok deps) (ok (checkModuleSource forms deps path src)))))))))

fn parentDir p: String -> (Option String)
  (if (stringContains? p "/") (let [(parts (stringSplit p "/")) (segs (listReverse (r/safeTail (listReverse parts))))] (if (listEmpty? segs) (some ".") (some (stringJoin segs "/")))) (some "."))
