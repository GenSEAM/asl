(module asl-checker/check :x [InferState Deferred checkModule checkSource checkFile! schemaOfCtor] :i [(types :a ty) (unify :a u) (resolve :a r) (ast :a a) (reader :a rd)])

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
  (mt t ((ty/tyCon name args _ _) (if (listEmpty? args) name (str "(" name " " (stringJoin (map typeText args) " ") ")"))) ((ty/tyVar _ _) "_") ((ty/tyFun _ _) "fn"))

fn expectType st: InferState have: ty/Type want: ty/Type where: String path: String -> InferState
  (let [(st1 (noteMapType (noteMapType st have where) want where))] (mt (u/unify want have st1.subst) ((u/uOk nextSubst) (setSubst st1 nextSubst)) ((u/uErr msg isNum) (let [(code (if isNum "rule-6" "type"))] (addDiag st1 code (str where ": " msg) path)))))

fn qualifyTypesStep types: (List ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(t (optionOr (listGet types idx) (ty/tyCon "" (list) (none) (none))))] (qualifyTypesStep types mod deps (+ idx 1) len (listAppend acc (list (qualifyTypeWithMod t mod deps))))))

fn qualifyTypeWithMod t: ty/Type mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> ty/Type
  (mt t
    ((ty/tyVar _ _) t)
    ((ty/tyCon name args optMod optShown)
      (let [(isLocal (and (not (stringEmpty? mod.name)) (or (some? (r/modSchema mod name)) (some? (r/modEnum mod name)))))
            (nextMod (mt optMod
                      ((some alias) (mt (r/modImport mod alias)
                                     ((some mpath) (mt (r/resolveDepTarget mpath deps) ((ok target) (some target.name)) ((err _) (some mpath))))
                                     ((none) optMod)))
                      ((none) (if isLocal (some mod.name) (importedUnqualifiedTypeModule name mod deps)))))]
        (ty/tyCon name (qualifyTypesStep args mod deps 0 (listLength args) (list)) nextMod optShown)))
    ((ty/tyFun params ret) (ty/tyFun (qualifyTypesStep params mod deps 0 (listLength params) (list)) (qualifyTypeWithMod ret mod deps))))

fn importedUnqualifiedTypeModule name: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option String)
  (fold (fn [(acc (Option String)) (mpath String)] -> (Option String)
          (mt acc
            ((some _) acc)
            ((none)
             (mt (r/resolveDepTarget mpath deps)
               ((ok target)
                (if (and (or (listContains? target.exportedTypes name) (listContains? target.exports name))
                         (or (some? (r/modSchema target name)) (some? (r/modEnum target name))))
                  (some target.name)
                  (none)))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn freshVarsStep typevars: (List String) idx: Int64 len: Int64 vmap: (Map String ty/Type) st: InferState -> (Pair (Map String ty/Type) InferState)
  (if (>= idx len) (pair vmap st) (let [(vname (optionOr (listGet typevars idx) "")) (kind (if (= vname "N") "num" (if (= vname "I") "int" "any"))) (fRes (freshVar st kind)) (nextVmap (mapSet vmap vname (pairFirst fRes))) (nextSt (pairSecond fRes))] (freshVarsStep typevars (+ idx 1) len nextVmap nextSt)))

fn instantiateParamsStep params: (List String) vmap: (Map String ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(p (optionOr (listGet params idx) "")) (pt (qualifyTypeWithMod (substParsedType (ty/parseTypeStr p (list)) vmap) mod deps))] (instantiateParamsStep params vmap mod deps (+ idx 1) len (listAppend acc (list pt)))))

fn instantiateSig params: (List String) ret: String typevars: (List String) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Pair (Pair (List ty/Type) ty/Type) InferState)
  (let [(vRes (freshVarsStep typevars 0 (listLength typevars) (mapEmpty) st)) (vmap (pairFirst vRes)) (st1 (pairSecond vRes)) (instP (instantiateParamsStep params vmap mod deps 0 (listLength params) (list))) (instR (qualifyTypeWithMod (substParsedType (ty/parseTypeStr ret (list)) vmap) mod deps))] (pair (pair instP instR) st1))

fn substParsedTypesStep ts: (List ty/Type) vmap: (Map String ty/Type) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(item (optionOr (listGet ts idx) (ty/tyCon "" (list) (none) (none))))] (substParsedTypesStep ts vmap (+ idx 1) len (listAppend acc (list (substParsedType item vmap))))))

fn substParsedTypes ts: (List ty/Type) vmap: (Map String ty/Type) -> (List ty/Type)
  (substParsedTypesStep ts vmap 0 (listLength ts) (list))

fn substParsedType t: ty/Type vmap: (Map String ty/Type) -> ty/Type
  (mt t ((ty/tyVar _ _) t) ((ty/tyCon name args optMod optShown) (mt (mapGet vmap name) ((some mapped) mapped) ((none) (ty/tyCon name (substParsedTypes args vmap) optMod optShown)))) ((ty/tyFun params ret) (ty/tyFun (substParsedTypes params vmap) (substParsedType ret vmap))))

fn sigResToFun res: (Pair (Pair (List ty/Type) ty/Type) InferState) -> (Option (Pair ty/Type InferState))
  (some (pair (ty/tyFun (pairFirst (pairFirst res)) (pairSecond (pairFirst res))) (pairSecond res)))

fn paramTypesToStrsStep params: (List (Pair String String)) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(p (optionOr (listGet params idx) (pair "" "")))] (paramTypesToStrsStep params (+ idx 1) len (listAppend acc (list (pairSecond p))))))

fn paramTypesToStrs params: (List (Pair String String)) -> (List String)
  (paramTypesToStrsStep params 0 (listLength params) (list))

fn lookupLocalFun sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (mt (r/modFun mod sym) ((some f) (let [(pStrs (paramTypesToStrs f.params)) (tvars (if (listEmpty? f.typevars) (ty/collectTvars pStrs f.ret) f.typevars)) (res (instantiateSig pStrs f.ret tvars mod deps st))] (sigResToFun res))) ((none) (none)))

fn lookupSysBuiltinSig sym: String mod: r/ModuleSummary st: InferState -> (Option (Pair ty/Type InferState))
  (mt (ty/builtinSig sym) ((some bsig) (let [(params (pairFirst bsig)) (ret (pairSecond (pairSecond bsig))) (tvars (ty/collectTvars params ret)) (res (instantiateSig params ret tvars mod (mapEmpty) st))] (sigResToFun res))) ((none) (genericSig sym mod st)))

fn genericSig sym: String mod: r/ModuleSummary st: InferState -> (Option (Pair ty/Type InferState))
  (cond ((ty/genericMulti? sym) (some (freshVar st "any")))
        ((not (stringEmpty? (ty/genericAlias sym))) (lookupSysBuiltinSig (ty/genericAlias sym) mod st))
        (else (none)))

fn lookupLocalCase sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (mt (mapGet mod.caseOwner sym) ((some ename) (mt (r/modEnum mod ename) ((some esum) (let [(matching (filter (fn [(c r/CaseSummary)] -> Bool (= c.name sym)) esum.cases))] (mt (listHead matching) ((some caseNode) (let [(pStrs (paramTypesToStrs caseNode.params)) (tvars esum.typevars) (retStr (if (listEmpty? tvars) ename (str "(" ename " " (stringJoin tvars " ") ")"))) (res (instantiateSig pStrs retStr tvars mod deps st))] (sigResToFun res))) ((none) (none))))) ((none) (none)))) ((none) (none)))

fn lookupLocalSymbol sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (mt (lookupLocalFun sym mod deps st) ((some res) (some res)) ((none) (lookupLocalCase sym mod deps st)))

fn lookupImportedSymbol sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (let [(parts (stringSplit sym "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))] (mt (r/modImport mod alias) ((some mpath) (if (= mpath "sys") (lookupSysBuiltinSig member mod st) (mt (r/resolveDepTarget mpath deps) ((ok target) (lookupLocalSymbol member target deps st)) ((err _) (none))))) ((none) (none))))

fn lookupUnqualifiedCaseInDeps sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (fold (fn [(acc (Option (Pair ty/Type InferState))) (mpath String)] -> (Option (Pair ty/Type InferState))
          (mt acc
            ((some _) acc)
            ((none)
             (mt (r/resolveDepTarget mpath deps)
               ((ok target) (lookupLocalCase sym target deps st))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn lookupSymbolType sym: String env: (Map String ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Option (Pair ty/Type InferState))
  (mt (mapGet env sym) ((some t) (some (pair t st))) ((none) (mt (lookupLocalSymbol sym mod deps st) ((some res) (some res)) ((none) (mt (lookupSysBuiltinSig sym mod st) ((some res) (some res)) ((none) (if (stringContains? sym "/") (lookupImportedSymbol sym mod deps st) (lookupUnqualifiedCaseInDeps sym mod deps st))))))))

fn mantissaOk? m: String -> Bool
  (if (stringContains? m ".") (let [(parts (stringSplit m "."))] (and (= (listLength parts) 2) (and (isAllDigits (optionOr (listGet parts 0) "")) (isAllDigits (optionOr (listGet parts 1) ""))))) (and (not (stringEmpty? m)) (isAllDigits m)))

fn expOk? e: String -> Bool
  (let [(s (r/cleanNumSign e))] (and (not (stringEmpty? s)) (isAllDigits s)))

fn splitExp s: String -> (Pair String (Option String))
  (if (stringContains? s "e") (let [(parts (stringSplit s "e"))] (if (= (listLength parts) 2) (pair (optionOr (listGet parts 0) "") (some (optionOr (listGet parts 1) ""))) (pair s (none)))) (if (stringContains? s "E") (let [(parts (stringSplit s "E"))] (if (= (listLength parts) 2) (pair (optionOr (listGet parts 0) "") (some (optionOr (listGet parts 1) ""))) (pair s (none)))) (pair s (none))))

fn isFloatLit? v: String -> Bool
  (let [(sp (splitExp (r/cleanNumSign v))) (mant (pairFirst sp)) (expPart (pairSecond sp))] (mt expPart ((some e) (and (mantissaOk? mant) (expOk? e))) ((none) (and (stringContains? mant ".") (mantissaOk? mant)))))

fn isIntLit? v: String -> Bool
  (let [(sp (splitExp (r/cleanNumSign v))) (mant (pairFirst sp)) (expPart (pairSecond sp))] (mt expPart ((some _) false) ((none) (and (not (stringContains? mant ".")) (mantissaOk? mant)))))

fn unitType -> ty/Type
  (ty/tyCon "Unit" (list) (none) (none))

fn lastExprUnit l: (List rd/SExpr) -> rd/SExpr
  (mt (listHead (listReverse l)) ((some e) e) ((none) (rd/makeAtom "()")))

fn inferAtom v: String env: (Map String ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) scope: String path: String st: InferState -> (Pair ty/Type InferState)
  (cond ((stringStartsWith? v "\"") (pair (ty/tyCon "String" (list) (none) (none)) st)) ((or (= v "true") (= v "false")) (pair (ty/tyCon "Bool" (list) (none) (none)) st)) ((= v "none") (let [(fRes (freshVar st "any"))] (pair (ty/tyCon "Option" (list (pairFirst fRes)) (none) (none)) (pairSecond fRes)))) ((or (= v "()") (= v "nil")) (pair (unitType) st)) ((isFloatLit? v) (pair (ty/tyCon "Float64" (list) (none) (none)) st)) ((isIntLit? v) (let [(vid st.nextVar) (fRes (freshVar st "int")) (vty (pairFirst fRes)) (st1 (pairSecond fRes)) (st2 (noteIntLiteral st1 v vid))] (pair vty st2))) (else (mt (lookupSymbolType v env mod deps st) ((some found) found) ((none) (let [(st1 (addDiag st "rule-1" (str "unbound symbol: " v (ty/renamedHint v)) path))] (freshVar st1 "any"))))))

fn inferAtomFm fm: FrameMachine v: String st: InferState -> (Pair ty/Type InferState)
  (inferAtom v fm.env fm.mod fm.deps fm.scope fm.path st)

fn asTyVar t: ty/Type -> ty/Type
  t

fn isAllDigits s: String -> Bool
  (if (stringEmpty? s) false (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? "0123456789" c))) true (stringChars s)))

fn parseParamParts parts: (List rd/SExpr) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Pair String (Option ty/Type))
  (let [(h (r/firstHeadIdent parts)) (sub (r/safeTail parts))] (mt (listHead sub) ((some tyNode) (pair h (some (qualifyTypeWithMod (ty/parseTypeStr (a/typeNodeText tyNode) (list)) mod deps)))) ((none) (pair h (none)))))

fn parseParamAnn p: rd/SExpr mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Pair String (Option ty/Type))
  (mt p ((rd/sexprAtom n) (pair n (none))) ((rd/sexprList parts) (parseParamParts parts mod deps)) ((rd/sexprVect parts) (parseParamParts parts mod deps)))

fn paramPartsAnnText parts: (List rd/SExpr) -> String
  (let [(sub (r/safeTail parts))] (mt (listHead sub) ((some tyNode) (a/typeNodeText tyNode)) ((none) "")))

fn paramAnnText p: rd/SExpr -> String
  (mt p ((rd/sexprAtom _) "") ((rd/sexprList parts) (paramPartsAnnText parts)) ((rd/sexprVect parts) (paramPartsAnnText parts)))

fn lambdaTypeBound paramItems: (List rd/SExpr) retText: String -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (name String)] -> (Map String Bool) (mapSet acc name true)) (mapEmpty) (ty/collectTvars (map paramAnnText paramItems) retText))

fn addTypeTreeDiags st: InferState t: ty/Type bound: (Map String Bool) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) where: String path: String -> InferState
  (setDiags st (listAppend st.diags (r/checkTypeTree t bound mod deps where path (list))))

fn letBindValue bparts: (List rd/SExpr) -> rd/SExpr
  (if (= (listLength bparts) 3) (optionOr (listGet bparts 2) (rd/makeAtom "()")) (r/secondExprEmpty bparts))

fn letAnnState st: InferState bparts: (List rd/SExpr) path: String -> InferState
  (mt (if (= (listLength bparts) 3) (listGet bparts 1) (none))
    ((some n) (setDiags st (listAppend st.diags (r/dottedTypeTree (ty/parseTypeStr (a/typeNodeText n) (list)) "let binding" path (list)))))
    ((none) st))

fn checkLambdaAnnText st: InferState annText: String bound: (Map String Bool) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) where: String path: String -> InferState
  (if (stringEmpty? annText) st (addTypeTreeDiags st (ty/parseTypeStr annText (list)) bound mod deps where path))

(enum InferFrame (:c fEval [(expr rd/SExpr)] "Evaluate expression next") (:c fCall [(calleeName String) (calleeTy ty/Type) (argsDone (List ty/Type)) (argsPending (List rd/SExpr)) (env (Map String ty/Type))] "Call evaluation continuation") (:c fLetVal [(bname String) (bindingsRest (List rd/SExpr)) (tailExprs (List rd/SExpr)) (env (Map String ty/Type))] "Let binding evaluation continuation") (:c fIfCond [(thenE rd/SExpr) (elseE rd/SExpr) (env (Map String ty/Type))] "If condition continuation") (:c fIfThen [(elseE rd/SExpr) (thenTy ty/Type) (env (Map String ty/Type))] "If branches continuation") (:c fTryInner [(valVar ty/Type)] "Try continuation"))

(schema FrameMachine (:f frames (List InferFrame)) (:f values (List ty/Type)) (:f env (Map String ty/Type)) (:f retType (Option ty/Type)) (:f inLambda Bool) (:f scope String) (:f path String) (:f mod r/ModuleSummary) (:f deps (Map String r/ModuleSummary)) (:f state InferState))

fn fmPushFresh fm: FrameMachine restFrames: (List InferFrame) st: InferState -> FrameMachine
  (let [(fRes (freshVar st "any"))] (with fm :frames restFrames :values (cons (pairFirst fRes) fm.values) :state (pairSecond fRes)))

fn popValue fm: FrameMachine -> (Pair ty/Type (List ty/Type))
  (pair (optionOr (listHead fm.values) (unitType)) (r/safeTail fm.values))

fn fmTick fm: FrameMachine tickIdx: Int64 -> FrameMachine
  (mt (listHead fm.frames) ((none) fm) ((some topFrame) (let [(restFrames (r/safeTail fm.frames))] (mt topFrame ((fEval expr) (fmEvalStep expr restFrames fm)) ((fCall cname cty argsDone argsPending cenv) (fmCallStep cname cty argsDone argsPending cenv restFrames fm)) ((fLetVal bname brest tails lenv) (fmLetValStep bname brest tails lenv restFrames fm)) ((fIfCond thenE elseE ienv) (fmIfCondStep thenE elseE ienv restFrames fm)) ((fIfThen elseE thenTy ienv) (fmIfThenStep elseE thenTy ienv restFrames fm)) ((fTryInner valVar) (fmTryStep valVar restFrames fm))))))

fn bindUnknownSubpats pats: (List rd/SExpr) env: (Map String ty/Type) st: InferState -> (Pair (Map String ty/Type) InferState)
  (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (p rd/SExpr)] -> (Pair (Map String ty/Type) InferState)
          (mt p
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

fn bindMatchPatternList pats: (List rd/SExpr) params: (List ty/Type) idx: Int64 len: Int64 env: (Map String ty/Type) st: InferState mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Pair (Map String ty/Type) InferState)
  (if (>= idx len) (pair env st) (let [(pat (optionOr (listGet pats idx) (rd/sexprAtom "_"))) (paramTy (optionOr (listGet params idx) (unitType))) (pruned (u/applySubst st.subst paramTy)) (res (bindMatchPattern pat pruned env mod deps st))] (bindMatchPatternList pats params (+ idx 1) len (pairFirst res) (pairSecond res) mod deps)))

fn qualifiedCase? sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> Bool
  (if (not (stringContains? sym "/")) false
    (let [(parts (stringSplit sym "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))]
      (mt (r/modImport mod alias)
        ((some mpath) (if (= mpath "sys") false
          (mt (r/resolveDepTarget mpath deps)
            ((ok target) (some? (lookupLocalCase member target deps st)))
            ((err _) false))))
        ((none) false))))

fn patternConstructor? sym: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> Bool
  (or (= sym "pair")
      (or (some? (ty/preludeUnionCases sym))
      (some? (schemaOfCtor sym mod deps))
      (some? (lookupLocalCase sym mod deps st))
      (some? (lookupUnqualifiedCaseInDeps sym mod deps st))
      (qualifiedCase? sym mod deps st)))

fn formPatternHead? head: String -> Bool
  (listContains? (list "do" "begin" "if" "cond" "let" "match" "mt" "when" "unless" "fn" "lambda" "assert" "refute" "and" "or" "not") head)

fn invalidPatternAtom? head: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> Bool
  (or (formPatternHead? head)
      (and (not (patternConstructor? head mod deps st))
        (or (some? (lookupSysBuiltinSig head mod st))
            (or (some? (lookupLocalFun head mod deps st))
                (and (stringContains? head "/") (some? (lookupImportedSymbol head mod deps st)))))))

fn bindArmPattern pat: rd/SExpr scrutTy: ty/Type env: (Map String ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Pair (Map String ty/Type) InferState)
  (mt pat
    ((rd/sexprAtom name)
     (if (and (not (= name "_")) (not (r/isLiteralAtom? name)) (invalidPatternAtom? name mod deps st))
       (pair env (addDiag st "type" (str "invalid mt arm pattern headed by " name) mod.path))
       (bindMatchPattern pat scrutTy env mod deps st)))
    (_ (bindMatchPattern pat scrutTy env mod deps st)))

fn bindMatchPattern pat: rd/SExpr scrutTy: ty/Type env: (Map String ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Pair (Map String ty/Type) InferState)
  (mt pat
    ((rd/sexprAtom name) (if (or (= name "_") (r/isLiteralAtom? name)) (pair env st) (pair (mapSet env name scrutTy) st)))
    ((rd/sexprVect items) (bindUnknownSubpats items env st))
    ((rd/sexprList parts)
     (mt (listHead parts)
       ((none) (pair env st))
       ((some h)
        (let [(cname (rd/sexprHead h)) (subPats (r/safeTail parts)) (ctorOpt (lookupSymbolType cname env mod deps st))]
          (if (not (patternConstructor? cname mod deps st))
            (let [(st1 (addDiag st "type" (str "unknown constructor in match pattern: " cname "; invalid mt arm pattern headed by " cname) mod.path))]
              (bindUnknownSubpats subPats env st1))
            (mt ctorOpt
            ((none)
             (let [(st1 (addDiag st "type" (str "unknown constructor in match pattern: " cname "; invalid mt arm pattern headed by " cname) mod.path))]
               (bindUnknownSubpats subPats env st1)))
            ((some ctorRes)
             (let [(ctorTy (pairFirst ctorRes)) (st1 (pairSecond ctorRes))]
               (mt (u/applySubst st1.subst ctorTy)
                 ((ty/tyFun cparams cret)
                  (let [(st2 (expectType st1 scrutTy cret (str "pattern " cname) mod.path))
                        (mLen (min (listLength subPats) (listLength cparams)))
                        (res (bindMatchPatternList subPats cparams 0 mLen env st2 mod deps))]
                    (if (> (listLength subPats) mLen)
                      (bindUnknownSubpats (listDrop subPats mLen) (pairFirst res) (pairSecond res))
                      res)))
                 (_ (bindUnknownSubpats subPats env st1))))))))))))

fn fmTryOutsideError fm: FrameMachine innerE: rd/SExpr restFrames: (List InferFrame) -> FrameMachine
  (let [(st1 (addDiag fm.state "rule-5" "try outside a defun returning (Result _ E)" fm.path))] (with fm :frames (cons (fEval innerE) restFrames) :state st1))

fn buildTypeSubstMap tvars: (List String) targs: (List ty/Type) idx: Int64 len: Int64 acc: (Map String ty/Type) -> (Map String ty/Type)
  (if (>= idx len) acc (let [(v (optionOr (listGet tvars idx) "")) (arg (optionOr (listGet targs idx) (unitType)))] (buildTypeSubstMap tvars targs (+ idx 1) len (mapSet acc v arg))))

fn evalStatement fm: FrameMachine expr: rd/SExpr st: InferState -> InferState
  (mt expr
    ((rd/sexprList items)
     (mt (listHead items)
       ((some h)
        (if (= (rd/sexprHead h) "if")
          (let [(args (r/safeTail items))]
            (if (= (listLength args) 2)
              (let [(condRes (evalFm fm (optionOr (listGet args 0) (rd/makeAtom "true")) st))
                    (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) "if condition" fm.path))
                    (thenRes (evalFm fm (optionOr (listGet args 1) (rd/makeAtom "()")) st1))]
                (pairSecond thenRes))
              (pairSecond (evalFm fm expr st))))
          (pairSecond (evalFm fm expr st))))
       ((none) (pairSecond (evalFm fm expr st)))))
    (_ (pairSecond (evalFm fm expr st))))

fn evalDoArgs fm: FrameMachine args: (List rd/SExpr) st: InferState -> (Pair ty/Type InferState)
  (mt (listHead args)
    ((none) (pair (unitType) st))
    ((some first) (let [(rest (r/safeTail args))]
      (if (listEmpty? rest)
        (evalFm fm first st)
        (evalDoArgs fm rest (evalStatement fm first st))))))

fn fmEvalStep expr: rd/SExpr restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (mt expr ((rd/sexprAtom v) (let [(res (inferAtomFm fm v fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (noteMapType (pairSecond res) (pairFirst res) fm.scope)))) ((rd/sexprVect items) (let [(fRes (freshVar fm.state "any")) (elemTy (pairFirst fRes)) (st1 (pairSecond fRes))] (with fm :frames restFrames :values (cons (ty/tyCon "List" (list elemTy) (none) (none)) fm.values) :state st1))) ((rd/sexprList items) (mt (listHead items) ((none) (with fm :frames restFrames :values (cons (unitType) fm.values))) ((some h) (let [(headTok (if (rd/isAtom? h) (rd/sexprHead h) "")) (tailArgs (r/safeTail items))] (cond ((or (= headTok "quote") (= headTok "quasiquote")) (let [(sexprTy (ty/tyCon "SExpr" (list) (none) (none)))] (with fm :frames restFrames :values (cons sexprTy fm.values)))) ((or (= headTok "assert") (= headTok "refute")) (let [(condRes (evalFm fm (optionOr (listHead tailArgs) (rd/makeAtom "()")) fm.state)) (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) (str headTok " condition") fm.path)) (st2 (mt (listGet tailArgs 1) ((some m) (pairSecond (evalFm fm m st1))) ((none) st1))) (st3 (if (or (listEmpty? tailArgs) (> (listLength tailArgs) 2)) (addDiag st2 "arity" (str headTok " takes a condition and an optional message, given " (stringFromInt64 (listLength tailArgs))) fm.path) st2))] (with fm :frames restFrames :values (cons (unitType) fm.values) :state st3))) ((or (= headTok "when") (= headTok "unless")) (let [(condRes (evalFm fm (optionOr (listHead tailArgs) (rd/makeAtom "true")) fm.state)) (st1 (expectType (pairSecond condRes) (pairFirst condRes) (ty/tyCon "Bool" (list) (none) (none)) (str headTok " condition") fm.path)) (st2 (fold (fn [(acc InferState) (arg rd/SExpr)] -> InferState (pairSecond (evalFm fm arg acc))) st1 (r/safeTail tailArgs)))] (fmPushFresh fm restFrames st2))) ((= headTok "do") (let [(res (evalDoArgs fm tailArgs fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) ((= headTok "let") (let [(bitems (r/firstVectItems tailArgs)) (tails (r/safeTail tailArgs))] (if (listEmpty? bitems) (let [(lastE (lastExprUnit tails))] (with fm :frames (cons (fEval lastE) restFrames))) (let [(firstB (r/firstExprEmpty bitems)) (flat? (mt firstB ((rd/sexprAtom _) true) (_ false))) (brest (if flat? (r/safeTail (r/safeTail bitems)) (r/safeTail bitems))) (bparts (if flat? (list firstB (r/secondExprEmpty bitems)) (mt firstB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))) (bname (if flat? (rd/sexprHead firstB) (r/firstHeadIdent bparts))) (bval (letBindValue bparts))] (with fm :frames (cons (fEval bval) (cons (fLetVal bname brest tails fm.env) restFrames)) :state (letAnnState fm.state bparts fm.path)))))) ((= headTok "if") (let [(condE (optionOr (listGet tailArgs 0) (rd/makeAtom "true"))) (thenE (optionOr (listGet tailArgs 1) (rd/makeAtom "()"))) (elseE (optionOr (listGet tailArgs 2) (rd/makeAtom "()")))] (with fm :frames (cons (fEval condE) (cons (fIfCond thenE elseE fm.env) restFrames))))) ((= headTok "cond") (let [(fRes (freshVar fm.state "any")) (outVar (pairFirst fRes)) (stOut (pairSecond fRes)) (stFinal (fold (fn [(stAcc InferState) (clause rd/SExpr)] -> InferState (mt clause ((rd/sexprList cparts) (let [(cheadExpr (r/firstExprEmpty cparts)) (chead (rd/sexprHead cheadExpr)) (cbodies (r/safeTail cparts)) (lastB (lastExprUnit cbodies))] (if (= chead "else") (let [(bres (evalFm fm lastB stAcc))] (expectType (pairSecond bres) (pairFirst bres) outVar "cond else clause" fm.path)) (let [(cres (evalFm fm cheadExpr stAcc)) (stC (expectType (pairSecond cres) (pairFirst cres) (ty/tyCon "Bool" (list) (none) (none)) "cond test" fm.path)) (bres (evalFm fm lastB stC))] (expectType (pairSecond bres) (pairFirst bres) outVar "cond clause" fm.path))))) (_ stAcc))) stOut tailArgs))] (with fm :frames restFrames :values (cons (u/applySubst stFinal.subst outVar) fm.values) :state stFinal))) ((or (= headTok "match") (= headTok "mt")) (let [(scrutinee (r/firstExprUnit tailArgs)) (arms (r/safeTail tailArgs)) (scrutRes (evalFm fm scrutinee fm.state)) (scrutTy (pairFirst scrutRes)) (stScrut (pairSecond scrutRes)) (fRes (freshVar stScrut "any")) (outVar (pairFirst fRes)) (stOut (pairSecond fRes)) (family (r/matchFamily arms fm.mod fm.deps)) (stFinal (fold (fn [(stAcc InferState) (arm rd/SExpr)] -> InferState (mt arm ((rd/sexprList armParts) (let [(pat (mt (listHead armParts) ((some p) p) ((none) (rd/makeAtom "_")))) (bodyExprs (r/safeTail armParts)) (bindRes (if (r/ctorPatternAtom? pat family fm.mod fm.deps) (pair fm.env stAcc) (bindArmPattern pat (u/applySubst stAcc.subst scrutTy) fm.env fm.mod fm.deps stAcc))) (armEnv (pairFirst bindRes)) (stArm (pairSecond bindRes)) (lastBody (lastExprUnit bodyExprs)) (bodyRes (evalWithEnv fm lastBody armEnv stArm)) (bodyTy (pairFirst bodyRes)) (stB (pairSecond bodyRes))] (expectType stB bodyTy outVar "match arm" fm.path))) (_ stAcc))) stOut arms))] (with fm :frames restFrames :values (cons (u/applySubst stFinal.subst outVar) fm.values) :state stFinal))) ((= headTok "try") (let [(innerE (r/firstExprUnit tailArgs))] (if fm.inLambda (let [(st1 (addDiag fm.state "rule-5" "try inside fn: it would return from the enclosing defun, not from the lambda" fm.path))] (with fm :frames (cons (fEval innerE) restFrames) :state st1)) (let [(enclosing (mt fm.retType ((some r) (u/applySubst fm.state.subst r)) ((none) (unitType))))] (mt enclosing ((ty/tyCon rname rargs _ _) (if (and (= rname "Result") (= (listLength rargs) 2)) (let [(fRes (freshVar fm.state "any")) (vty (pairFirst fRes)) (st1 (pairSecond fRes))] (with fm :frames (cons (fEval innerE) (cons (fTryInner vty) restFrames)) :state st1)) (fmTryOutsideError fm innerE restFrames))) (_ (fmTryOutsideError fm innerE restFrames))))))) ((= headTok "fn") (let [(isBang (and (not (listEmpty? tailArgs)) (= (r/firstHeadIdent tailArgs) "!"))) (remArgs (if isBang (r/safeTail tailArgs) tailArgs)) (afterParams (r/safeTail remArgs)) (hasRetAnn (and (not (listEmpty? afterParams)) (= (r/firstHeadIdent afterParams) "->"))) (bodyNodes (if hasRetAnn (r/safeTail (r/safeTail afterParams)) afterParams)) (paramItems (r/firstVectItems remArgs)) (afterArrow (if hasRetAnn (r/safeTail afterParams) (list))) (retNodeOpt (listHead afterArrow)) (retAnnText (mt retNodeOpt ((some rnode) (a/typeNodeText rnode)) ((none) ""))) (lamBound (lambdaTypeBound paramItems retAnnText)) (pRes (fold (fn [(acc (Pair (Pair (List ty/Type) (Map String ty/Type)) InferState)) (p rd/SExpr)] -> (Pair (Pair (List ty/Type) (Map String ty/Type)) InferState) (let [(pann (parseParamAnn p fm.mod fm.deps)) (pname (pairFirst pann)) (tyRes (mt (pairSecond pann) ((some pty) (pair pty (checkLambdaAnnText (pairSecond acc) (paramAnnText p) lamBound fm.mod fm.deps "lambda parameter" fm.path))) ((none) (freshVar (pairSecond acc) "any")))) (pty (pairFirst tyRes))] (pair (pair (cons pty (pairFirst (pairFirst acc))) (mapSet (pairSecond (pairFirst acc)) pname pty)) (pairSecond tyRes)))) (pair (pair (list) fm.env) fm.state) paramItems)) (paramsTy (listReverse (pairFirst (pairFirst pRes)))) (fnEnv (pairSecond (pairFirst pRes))) (st1 (checkLambdaAnnText (pairSecond pRes) retAnnText lamBound fm.mod fm.deps "lambda return" fm.path)) (retInfo (mt retNodeOpt ((some rnode) (pair (qualifyTypeWithMod (ty/parseTypeStr (a/typeNodeText rnode) (list)) fm.mod fm.deps) st1)) ((none) (freshVar st1 "any")))) (retTy (pairFirst retInfo)) (st2 (pairSecond retInfo)) (lastBody (lastExprUnit bodyNodes)) (bodyRes (runExprDirect lastBody fnEnv (some retTy) true fm.scope fm.path fm.mod fm.deps st2)) (bodyTy (pairFirst bodyRes)) (st3 (expectType (pairSecond bodyRes) bodyTy retTy "lambda body" fm.path)) (fnTy (ty/tyFun paramsTy retTy))] (with fm :frames restFrames :values (cons fnTy fm.values) :state st3))) ((stringStartsWith? headTok ".-") (let [(fname (r/sliceFrom headTok 2)) (tgtE (r/firstExprUnit tailArgs)) (tgtRes (evalFm fm tgtE fm.state)) (tgtTy (u/applySubst (pairSecond tgtRes).subst (pairFirst tgtRes))) (st1 (pairSecond tgtRes))] (mt tgtTy ((ty/tyCon tname targs toptMod _) (if (and (= tname "Pair") (= (listLength targs) 2)) (let [(outTy (if (= fname "first") (optionOr (listGet targs 0) (unitType)) (optionOr (listGet targs 1) (unitType))))] (with fm :frames restFrames :values (cons outTy fm.values) :state st1)) (let [(targetMod (mt toptMod ((some m) (moduleNamed m fm.mod fm.deps)) ((none) (some fm.mod))))] (mt targetMod ((none) (let [(st2 (addDiag st1 "type" (str "unknown module for type " (ty/showType tgtTy)) fm.path))] (fmPushFresh fm restFrames st2))) ((some smod) (mt (checkerSchema smod tname) ((some ssum) (let [(fMatch (filter (fn [(f r/FieldSummary)] -> Bool (= f.name fname)) ssum.fields))] (mt (listHead fMatch) ((some fdef) (let [(fieldTy (ty/parseTypeStr fdef.type (list))) (mLen (min (listLength ssum.typevars) (listLength targs))) (substMap (buildTypeSubstMap ssum.typevars targs 0 mLen (mapEmpty))) (instField (qualifyTypeWithMod (substParsedType fieldTy substMap) smod fm.deps))] (with fm :frames restFrames :values (cons instField fm.values) :state st1))) ((none) (let [(st2 (addDiag st1 "type" (str (ty/showType tgtTy) " has no field " fname) fm.path))] (fmPushFresh fm restFrames st2)))))) ((none) (let [(msg (if (some? toptMod) (str "unknown schema " tname " in module " smod.name) (str (ty/showType tgtTy) " is not a record, so it has no field " fname))) (st2 (addDiag st1 "type" msg fm.path))] (fmPushFresh fm restFrames st2))))))))) (_ (fmPushFresh fm restFrames st1))))) ((recordCtorHead? headTok tailArgs fm.mod fm.deps) (let [(res (inferCtorForm fm headTok tailArgs fm.state))] (with fm :frames restFrames :values (cons (pairFirst res) fm.values) :state (pairSecond res)))) (else (let [(calleeRes (if (rd/isAtom? h) (inferAtomFm fm headTok fm.state) (evalFm fm h fm.state))) (calleeTy (pairFirst calleeRes)) (st1 (pairSecond calleeRes))] (if (listEmpty? tailArgs) (mt (u/applySubst st1.subst calleeTy) ((ty/tyFun p r) (with fm :frames restFrames :values (cons r fm.values) :state st1)) (_ (with fm :frames restFrames :values (cons calleeTy fm.values) :state st1))) (let [(firstArg (r/firstExprUnit tailArgs)) (pendingArgs (r/safeTail tailArgs))] (with fm :frames (cons (fEval firstArg) (cons (fCall (if (rd/isAtom? h) headTok (rd/renderSexpr h)) calleeTy (list) pendingArgs fm.env) restFrames)) :state st1)))))))))))
fn moduleNamed name: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option r/ModuleSummary)
  (if (= name mod.name) (some mod) (mt (r/modImport mod name) ((some mpath) (mt (r/resolveDepTarget mpath deps) ((ok m) (some m)) ((err _) (none)))) ((none) (mt (r/resolveDepTarget name deps) ((ok m) (some m)) ((err _) (none))))))

fn lookupUnqualifiedSchemaInDeps head: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option (Pair r/SchemaSummary r/ModuleSummary))
  (fold (fn [(acc (Option (Pair r/SchemaSummary r/ModuleSummary))) (mpath String)] -> (Option (Pair r/SchemaSummary r/ModuleSummary))
          (mt acc
            ((some _) acc)
            ((none)
             (mt (r/resolveDepTarget mpath deps)
               ((ok target)
                (if (not (or (listContains? target.exportedTypes head) (listContains? target.exports head)))
                  (none)
                  (mt (r/modSchema target head)
                    ((some s) (some (pair s target)))
                    ((none) (none)))))
               ((err _) (none))))))
        (none)
        (mapValues mod.imports))

fn schemaOfCtor head: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option (Pair r/SchemaSummary r/ModuleSummary))
  (if (stringContains? head "/") (let [(parts (stringSplit head "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) ""))] (mt (r/modImport mod alias) ((none) (none)) ((some mpath) (mt (r/resolveDepTarget mpath deps) ((err _) (none)) ((ok target) (if (not (or (listContains? target.exportedTypes member) (listContains? target.exports member))) (none) (mt (r/modSchema target member) ((some s) (some (pair s target))) ((none) (none))))))))) (mt (r/modSchema mod head) ((some s) (some (pair s mod))) ((none) (lookupUnqualifiedSchemaInDeps head mod deps))))

fn pascalHead? head: String -> Bool
  (let [(seg (optionOr (listHead (listReverse (stringSplit head "/"))) head))] (and (not (stringEmpty? seg)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (r/firstCharStr seg))))

fn keywordAtom? e: rd/SExpr -> Bool
  (mt e ((rd/sexprAtom v) (stringStartsWith? v ":")) (_ false))

fn recordCtorHead? head: String args: (List rd/SExpr) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> Bool
  (or (some? (schemaOfCtor head mod deps)) (and (pascalHead? head) (keywordAtom? (r/firstExprEmpty args))))

fn ctorKey e: rd/SExpr -> String
  (let [(raw (rd/sexprHead e))] (if (stringStartsWith? raw ":") (r/sliceFrom raw 1) raw))

fn fieldTypeIn f: r/FieldSummary vmap: (Map String ty/Type) owner: r/ModuleSummary deps: (Map String r/ModuleSummary) -> ty/Type
  (qualifyTypeWithMod (substParsedType (ty/parseTypeStr f.type (list)) vmap) owner deps)

fn checkerSchema mod: r/ModuleSummary name: String -> (Option r/SchemaSummary)
  (mt (r/modSchema mod name) ((some schema) (some schema)) ((none) (cond ((= name "FileStat") (some (r/SchemaSummary :name name :typevars (list) :fields (list (r/FieldSummary :name "isFile" :type "Bool" :hasDefault false) (r/FieldSummary :name "isDir" :type "Bool" :hasDefault false) (r/FieldSummary :name "size" :type "Int64" :hasDefault false) (r/FieldSummary :name "mtime" :type "Int64" :hasDefault false) (r/FieldSummary :name "mode" :type "Int64" :hasDefault false))))) ((= name "LinkStat") (some (r/SchemaSummary :name name :typevars (list) :fields (list (r/FieldSummary :name "isFile" :type "Bool" :hasDefault false) (r/FieldSummary :name "isDir" :type "Bool" :hasDefault false) (r/FieldSummary :name "isSymlink" :type "Bool" :hasDefault false) (r/FieldSummary :name "size" :type "Int64" :hasDefault false) (r/FieldSummary :name "mtime" :type "Int64" :hasDefault false) (r/FieldSummary :name "mode" :type "Int64" :hasDefault false))))) ((= name "ProcessOutput") (some (r/SchemaSummary :name name :typevars (list) :fields (list (r/FieldSummary :name "exitCode" :type "Int64" :hasDefault false) (r/FieldSummary :name "stdout" :type "String" :hasDefault false) (r/FieldSummary :name "stderr" :type "String" :hasDefault false))))) (else (none)))))

fn inferCtorArgs fm: FrameMachine fields: (List r/FieldSummary) owner: r/ModuleSummary vmap: (Map String ty/Type) sname: String args: (List rd/SExpr) st: InferState -> InferState
  (if (< (listLength args) 2) st (let [(kname (ctorKey (r/firstExprEmpty args))) (vres (evalFm fm (r/secondExprEmpty args) st)) (st1 (pairSecond vres)) (st2 (mt (listHead (filter (fn [(f r/FieldSummary)] -> Bool (= f.name kname)) fields)) ((none) st1) ((some f) (expectType st1 (pairFirst vres) (fieldTypeIn f vmap owner fm.deps) (str "field " kname " of " sname) fm.path))))] (inferCtorArgs fm fields owner vmap sname (r/safeTail (r/safeTail args)) st2)))

fn inferCtorForm fm: FrameMachine head: String args: (List rd/SExpr) st: InferState -> (Pair ty/Type InferState)
  (mt (schemaOfCtor head fm.mod fm.deps)
    ((none) (freshVar (inferCtorArgs fm (list) fm.mod (mapEmpty) head args st) "any"))
    ((some found) (let [(sch (pairFirst found)) (owner (pairSecond found)) (tvars sch.typevars) (vRes (freshVarsStep tvars 0 (listLength tvars) (mapEmpty) st)) (vmap (pairFirst vRes)) (st1 (inferCtorArgs fm sch.fields owner vmap sch.name args (pairSecond vRes))) (targs (map (fn [(v String)] -> ty/Type (optionOr (mapGet vmap v) (unitType))) tvars)) (shown (if (stringContains? head "/") (some head) (none)))] (pair (ty/tyCon sch.name targs (some owner.name) shown) st1))))

fn fmCallStep cname: String cty: ty/Type argsDone: (List ty/Type) argsPending: (List rd/SExpr) cenv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (val (pairFirst pv)) (remValues (pairSecond pv)) (nextDone (r/listAppendOne argsDone val))] (if (listEmpty? argsPending) (if (and (ty/genericMulti? cname) (and (not (mapHas? fm.env cname)) (ty/isTyVar? (u/applySubst fm.state.subst cty)))) (genericCallStep cname nextDone remValues restFrames fm) (let [(prunedCallee (u/applySubst fm.state.subst cty))] (mt prunedCallee ((ty/tyFun params ret) (let [(stUnify (foldExpectArgs nextDone params cname fm.path fm.state))] (with fm :frames restFrames :values (cons (u/applySubst stUnify.subst ret) remValues) :state stUnify))) (_ (let [(fRes (freshVar fm.state "any"))] (with fm :frames restFrames :values (cons (pairFirst fRes) remValues) :state (pairSecond fRes))))))) (let [(nextArg (r/firstExprUnit argsPending)) (remPending (r/safeTail argsPending))] (with fm :frames (cons (fEval nextArg) (cons (fCall cname cty nextDone remPending cenv) restFrames)) :values remValues))))

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
  (mt (lookupSysBuiltinSig concrete mod st)
    ((none) st)
    ((some res) (mt (pairFirst res)
                  ((ty/tyFun params ret) (expectType (foldExpectArgs args params cname path (pairSecond res)) ret result (str "result of " cname) path))
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

fn foldExpectArgs args: (List ty/Type) params: (List ty/Type) cname: String path: String st: InferState -> InferState
  (mt (listHead args) ((none) st) ((some a) (mt (listHead params) ((none) st) ((some p) (let [(nextParams (mt (listHead (r/safeTail params)) ((none) (if (variadicBuiltin? cname) params (list))) ((some _) (r/safeTail params)))) (st1 (expectType st a p (str "argument to " cname) path))] (foldExpectArgs (r/safeTail args) nextParams cname path st1))))))

fn fmLetValStep bname: String brest: (List rd/SExpr) tails: (List rd/SExpr) lenv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (val (pairFirst pv)) (remValues (pairSecond pv)) (nextEnv (mapSet lenv bname val))] (if (listEmpty? brest) (let [(lastE (lastExprUnit tails))] (with fm :frames (cons (fEval lastE) restFrames) :values remValues :env nextEnv)) (let [(nextB (r/firstExprEmpty brest)) (flat? (mt nextB ((rd/sexprAtom _) true) (_ false))) (remBrest (if flat? (r/safeTail (r/safeTail brest)) (r/safeTail brest))) (bparts (if flat? (list nextB (r/secondExprEmpty brest)) (mt nextB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))) (nextBname (if flat? (rd/sexprHead nextB) (r/firstHeadIdent bparts))) (nextBval (letBindValue bparts))] (with fm :frames (cons (fEval nextBval) (cons (fLetVal nextBname remBrest tails nextEnv) restFrames)) :values remValues :env nextEnv :state (letAnnState fm.state bparts fm.path)))))

fn fmIfCondStep thenE: rd/SExpr elseE: rd/SExpr ienv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (condTy (pairFirst pv)) (remValues (pairSecond pv)) (st1 (expectType fm.state condTy (ty/tyCon "Bool" (list) (none) (none)) "if condition" fm.path))] (with fm :frames (cons (fEval thenE) (cons (fIfThen elseE condTy ienv) restFrames)) :values remValues :env ienv :state st1))

fn fmIfThenStep elseE: rd/SExpr thenTy: ty/Type ienv: (Map String ty/Type) restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (actualThen (pairFirst pv)) (remValues (pairSecond pv)) (elseRes (evalWithEnv fm elseE ienv fm.state)) (elseTy (pairFirst elseRes)) (st1 (expectType (pairSecond elseRes) elseTy actualThen "if branches" fm.path))] (with fm :frames restFrames :values (cons actualThen remValues) :env ienv :state st1))

fn fmTryStep valVar: ty/Type restFrames: (List InferFrame) fm: FrameMachine -> FrameMachine
  (let [(pv (popValue fm)) (innerTy (pairFirst pv)) (remValues (pairSecond pv)) (enclosing (mt fm.retType ((some r) (u/applySubst fm.state.subst r)) ((none) (ty/tyCon "Result" (list valVar (unitType)) (none) (none))))) (errTy (mt enclosing ((ty/tyCon _ rargs _ _) (mt (listGet rargs 1) ((some e) e) ((none) (unitType)))) (_ (unitType)))) (wantRes (ty/tyCon "Result" (list valVar errTy) (none) (none))) (st1 (expectType fm.state innerTy wantRes "try" fm.path))] (with fm :frames restFrames :values (cons valVar remValues) :state st1))

fn fmRun fm: FrameMachine budget: Int64 -> FrameMachine
  (let [(nextFm (fold fmTick fm (range 0 budget)))] (if (listEmpty? nextFm.frames) nextFm (fmRun nextFm (* budget 2))))

fn runExprDirect expr: rd/SExpr env: (Map String ty/Type) retType: (Option ty/Type) inLambda: Bool scope: String path: String mod: r/ModuleSummary deps: (Map String r/ModuleSummary) st: InferState -> (Pair ty/Type InferState)
  (let [(initFm (FrameMachine :frames (list (fEval expr)) :values (list) :env env :retType retType :inLambda inLambda :scope scope :path path :mod mod :deps deps :state st))] (let [(finalFm (fmRun initFm 64))] (let [(outTy (mt (listHead finalFm.values) ((some t) t) ((none) (unitType)))) (stNoted (noteMapType finalFm.state outTy scope))] (pair outTy stNoted))))

fn evalWithEnv fm: FrameMachine e: rd/SExpr env: (Map String ty/Type) st: InferState -> (Pair ty/Type InferState)
  (runExprDirect e env fm.retType fm.inLambda fm.scope fm.path fm.mod fm.deps st)

fn evalFm fm: FrameMachine e: rd/SExpr st: InferState -> (Pair ty/Type InferState)
  (evalWithEnv fm e fm.env st)

fn checkLiteralRanges intSites: (List (Pair String Int64)) subst: (Map Int64 ty/Type) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair String Int64))] -> (List ty/Diagnostic) (let [(tokStr (pairFirst site)) (vid (pairSecond site)) (wty (u/applySubst subst (ty/tyVar vid "int"))) (tname (mt wty ((ty/tyCon n _ _ _) n) (_ "Int64")))] (mt (ty/intRangeBounds tname) ((none) a) ((some b) (let [(low (pairFirst b)) (high (pairSecond b)) (numOpt (stringToInt64 tokStr)) (badLit? (mt numOpt ((none) true) ((some n) (or (< n low) (> n high)))))] (if badLit? (let [(msg (str "the literal " tokStr " does not fit " tname " (" (stringFromInt64 low) ".." (stringFromInt64 high) ")"))] (cons (ty/Diagnostic :code "literal-range" :message msg :msg msg :line 1 :col 1 :path path) a)) a)))))) acc intSites)

fn mapHasKey? m: (Map String Bool) k: String -> Bool
  (mt (mapGet m k) ((some _) true) ((none) false))

fn extractMapKeysList types: (List ty/Type) subst: (Map Int64 ty/Type) -> (List ty/Type)
  (fold (fn [(acc (List ty/Type)) (t ty/Type)] -> (List ty/Type) (listAppend (extractMapKeys t subst) acc)) (list) types)

fn extractMapKeys t: ty/Type subst: (Map Int64 ty/Type) -> (List ty/Type)
  (let [(pruned (u/applySubst subst t))] (mt pruned ((ty/tyCon name args _ _) (let [(subKeys (extractMapKeysList args subst))] (if (and (= name "Map") (>= (listLength args) 1)) (cons (optionOr (listHead args) pruned) subKeys) subKeys))) ((ty/tyFun params ret) (listAppend (extractMapKeys ret subst) (extractMapKeysList params subst))) ((ty/tyVar _ _) (list))))

fn checkTypeUnordered t: ty/Type subst: (Map Int64 ty/Type) visited: (Map String Bool) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Option String)
  (let [(pruned (u/applySubst subst t))] (mt pruned ((ty/tyVar _ _) (none)) ((ty/tyFun _ _) (none)) ((ty/tyCon name args optMod _) (if (ty/unorderedType? name) (some name) (let [(badArg (fold (fn [(acc (Option String)) (a ty/Type)] -> (Option String) (mt acc ((some _) acc) ((none) (checkTypeUnordered a subst visited mod deps)))) (none) args))] (mt badArg ((some b) (some b)) ((none) (let [(typeKey (str (optionOr optMod mod.name) "/" name))] (if (mapHasKey? visited typeKey) (none) (let [(nextVis (mapSet visited typeKey true)) (targetMod (mt optMod ((some m) (moduleNamed m mod deps)) ((none) (some mod))))] (mt targetMod ((none) (none)) ((some tmod) (mt (r/modSchema tmod name) ((some ssum) (fold (fn [(acc (Option String)) (f r/FieldSummary)] -> (Option String) (mt acc ((some _) acc) ((none) (let [(fty (ty/parseTypeStr f.type (list)))] (checkTypeUnordered fty subst nextVis tmod deps))))) (none) ssum.fields)) ((none) (mt (r/modEnum tmod name) ((some esum) (fold (fn [(acc (Option String)) (c r/CaseSummary)] -> (Option String) (mt acc ((some _) acc) ((none) (fold (fn [(cacc (Option String)) (p (Pair String String))] -> (Option String) (mt cacc ((some _) cacc) ((none) (let [(pty (qualifyTypeWithMod (ty/parseTypeStr (pairSecond p) (list)) mod deps))] (checkTypeUnordered pty subst nextVis tmod deps))))) acc c.params)))) (none) esum.cases)) ((none) (none)))))))))))))))))

fn checkMapKeyRules mapSites: (List (Pair ty/Type String)) subst: (Map Int64 ty/Type) mod: r/ModuleSummary deps: (Map String r/ModuleSummary) path: String acc: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair ty/Type String))] -> (List ty/Diagnostic) (let [(tySite (pairFirst site)) (scopeLbl (pairSecond site)) (mkeys (extractMapKeys tySite subst))] (fold (fn [(ka (List ty/Diagnostic)) (k ty/Type)] -> (List ty/Diagnostic) (mt (checkTypeUnordered k subst (mapEmpty) mod deps) ((none) ka) ((some bad) (let [(shown (ty/showType k)) (msg (if (= shown bad) (str shown " as a Map key has no total order; mapKeys is specified to return keys sorted") (str "the Map key " shown " reaches " bad ", which has no total order; mapKeys is specified to return keys sorted")))] (cons (ty/Diagnostic :code "map-key-order" :message msg :msg msg :line 1 :col 1 :path path) ka))))) a mkeys))) acc mapSites)

fn bodyDiagPos d: a/DefunNode idx: Int64 ds: (List ty/Diagnostic) -> (Pair Int64 Int64)
  (let [(pos (r/bodyPosAt d idx))
        (expr (optionOr (listGet d.body idx) (rd/makeAtom "")))
        (unknown (listAny? (fn [(diag ty/Diagnostic)] -> Bool (or (= diag.code "rule-1") (= diag.code "rule-2"))) ds))]
    (mt expr ((rd/sexprList _) (if (and unknown (> (pairSecond pos) 0)) (pair (pairFirst pos) (+ (pairSecond pos) 1)) pos)) (_ pos)))

fn checkDefunDiags d: a/DefunNode summary: r/ModuleSummary deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (let [(st0 (makeInferState)) (env0 (fold (fn [(e (Map String ty/Type)) (p a/Param)] -> (Map String ty/Type) (mapSet e p.name (qualifyTypeWithMod (ty/parseTypeStr p.type (list)) summary deps))) (mapEmpty) d.params)) (retTy (qualifyTypeWithMod (ty/parseTypeStr d.retType (list)) summary deps)) (scopeName (str "function " d.name)) (stParams (fold (fn [(s InferState) (p a/Param)] -> InferState (noteMapType s (qualifyTypeWithMod (ty/parseTypeStr p.type (list)) summary deps) scopeName)) st0 d.params)) (stNote (noteMapType stParams retTy scopeName)) (bodyNodes d.body)]
    (if (listEmpty? bodyNodes) (list)
      (let [(allBodyRes (fold (fn [(accRes (Pair ty/Type InferState)) (i Int64)] -> (Pair ty/Type InferState) (let [(e (optionOr (listGet bodyNodes i) (rd/makeAtom "()"))) (before (listLength (pairSecond accRes).diags)) (res (runExprDirect e env0 (some retTy) false scopeName path summary deps (pairSecond accRes))) (pos (bodyDiagPos d i (pairSecond res).diags))] (pair (pairFirst res) (setDiags (pairSecond res) (placeFresh (pairSecond res).diags before pos))))) (pair (unitType) stNote) (range 0 (listLength bodyNodes)))) (lastTy (pairFirst allBodyRes)) (st1 (pairSecond allBodyRes)) (placed (listLength st1.diags)) (st2 (resolveDeferred (expectType st1 lastTy retTy (str "return of " d.name) path) summary path)) (st3Subst st2.subst) (dLit (checkLiteralRanges st2.intSites st3Subst path st2.diags)) (dMap (checkMapKeyRules st2.mapSites st3Subst summary deps path dLit))]
        (placeFresh dMap placed (bodyDiagPos d (- (listLength bodyNodes) 1) st2.diags)))))

fn untypedParamDiags d: a/DefunNode path: String -> (List ty/Diagnostic)
  (let [(pos (r/bodyPosAt d 0))] (map (fn [(p a/Param)] -> ty/Diagnostic (let [(msg (str "function " d.name " parameter " p.name " has no type annotation"))] (ty/Diagnostic :code "ERR_UNTYPED_PARAM" :message msg :msg msg :line (pairFirst pos) :col (pairSecond pos) :path path))) (filter (fn [(p a/Param)] -> Bool (stringEmpty? p.type)) d.params)))

fn checkModuleSource forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String src: String -> (List ty/Diagnostic)
  (normalizeCheckDiags (checkModule forms deps path))

fn checkDefunWithUntyped d: a/DefunNode summary: r/ModuleSummary deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (listAppend (untypedParamDiags d path) (checkDefunDiags d summary deps path))

fn checkExprDiags p: a/PosForm summary: r/ModuleSummary deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
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
  (cond ((= code "rule-1") "ERR_UNKNOWN_SYMBOL") ((= code "rule-2") "ERR_UNKNOWN_SYMBOL") ((= code "rule-12") "ERR_EFFECT_UNMARKED") ((= code "unresolved-import") "ERR_UNRESOLVED_IMPORT") ((= code "arity") "ERR_ARITY") ((= code "ctor") "ERR_BAD_CONSTRUCTOR") ((= code "type") "ERR_TYPE_MISMATCH") ((= code "rule-6") "ERR_TYPE_MISMATCH") ((= code "rule-4") "ERR_MATCH_NONEXHAUSTIVE") (else code))

fn hostCheckDiagCode d: ty/Diagnostic -> String
  (if (= d.code "rule-9") (if (stringContains? d.message "ERR_NOT_EXPORTED") "ERR_NOT_EXPORTED" "ERR_UNRESOLVED_IMPORT") (hostCheckCode d.code))

fn normalizeCheckDiag d: ty/Diagnostic -> ty/Diagnostic
  (ty/Diagnostic :code (hostCheckDiagCode d) :message d.message :msg d.msg :line d.line :col d.col :path d.path)

fn redundantUnknownRule2? d: ty/Diagnostic ds: (List ty/Diagnostic) -> Bool
  (and (= d.code "rule-2") (listAny? (fn [(other ty/Diagnostic)] -> Bool (and (= other.code "rule-1") (and (= other.path d.path) (and (= other.line d.line) (<= (- other.col d.col) 1) (<= (- d.col other.col) 1))))) ds))

fn normalizeCheckDiags ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (map normalizeCheckDiag (filter (fn [(d ty/Diagnostic)] -> Bool (and (not (isCheckLint d)) (not (redundantUnknownRule2? d ds)))) ds))

fn checkModule forms: (List a/TopForm) deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (let [(summary0 (r/collectSummary forms path))
        (existingMod (mt (mapGet deps path)
                       ((some m) (some m))
                       ((none) (mt (r/resolveDepTarget path deps)
                                 ((ok m) (some m))
                                 ((err _) (none))))))
        (summary (mt existingMod
                   ((some m) (r/withImports summary0 m.imports))
                   ((none) summary0)))
        (p12Diags (r/resolveModule summary forms deps)) (defunDiags (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic) (mt form ((a/topDefun d) (listAppend (checkDefunWithUntyped d summary deps path) acc)) ((a/topExpr p) (listAppend (checkExprDiags p summary deps path) acc)) (_ acc))) (list) forms))] (listAppend p12Diags defunDiags))

fn parseErrDiag pe: a/ParseError path: String -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message pe.msg :msg pe.msg :line pe.line :col pe.col :path path))

fn checkSource src: String deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (mt (a/parseForChecker src) ((ok forms) (checkModule forms deps path)) ((err pe) (parseErrDiag pe path)))

fn ! checkFile! path: String roots: (List String) -> (Result (List ty/Diagnostic) IoError)
  (mt (fileRead path) ((err ioErr) (err ioErr)) ((ok src) (mt (a/parse src) ((err pe) (ok (parseErrDiag pe path))) ((ok forms) (let [(summary (r/collectSummary forms path)) (importPaths (r/mapValuesList summary.imports)) (allRoots (cons (optionOr (parentDir path) ".") roots))] (mt (r/loadModuleDeps! allRoots importPaths) ((err ioErr2) (err ioErr2)) ((ok deps) (ok (checkModuleSource forms deps path src)))))))))

fn parentDir p: String -> (Option String)
  (if (stringContains? p "/") (let [(parts (stringSplit p "/")) (segs (listReverse (r/safeTail (listReverse parts))))] (if (listEmpty? segs) (some ".") (some (stringJoin segs "/")))) (some "."))
