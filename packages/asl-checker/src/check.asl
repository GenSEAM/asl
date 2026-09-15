(module asl-checker/check
  :d "Pass 3 Hindley-Milner Type Inference and Unified Checker Entry Points"
  :x [InferState
      checkModule
      checkSource
      checkFile!]
  :i [(types :a ty) (unify :a u) (resolve :a r) (ast :a a) (reader :a rd)])

(dfs InferState
  (:f subst (Map Int64 ty/Type) "Defun-scoped substitution map")
  (:f nextVar Int64 "Defun-scoped next fresh metavar id")
  (:f intSites (List (Pair String Int64)) "Integer literals with metavar id")
  (:f mapSites (List (Pair ty/Type String)) "Inferred types with scope label")
  (:f lambdas (List (Pair (List ty/Type) ty/Type)) "Lambda parameter and return types")
  (:f diags (List ty/Diagnostic) "Pass 3 diagnostics"))

(df makeInferState [] -> InferState
  (InferState :subst (map-empty)
              :nextVar 1
              :intSites (list)
              :mapSites (list)
              :lambdas (list)
              :diags (list)))

(df freshVar [(st InferState) (kind String)] -> (Pair ty/Type InferState)
  (let [(nid (.-nextVar st))]
    (pair (ty/tyVar nid kind)
          (InferState :subst (.-subst st)
                      :nextVar (+ nid 1)
                      :intSites (.-intSites st)
                      :mapSites (.-mapSites st)
                      :lambdas (.-lambdas st)
                      :diags (.-diags st)))))

(df addDiag [(st InferState) (code String) (msg String) (path String)] -> InferState
  (InferState :subst (.-subst st)
              :nextVar (.-nextVar st)
              :intSites (.-intSites st)
              :mapSites (.-mapSites st)
              :lambdas (.-lambdas st)
              :diags (list-cons (ty/Diagnostic :code code :message msg :msg msg :line 1 :col 1 :path path)
                                (.-diags st))))

(df noteMapType [(st InferState) (t ty/Type) (scope String)] -> InferState
  (InferState :subst (.-subst st)
              :nextVar (.-nextVar st)
              :intSites (.-intSites st)
              :mapSites (list-cons (pair t scope) (.-mapSites st))
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df noteIntLiteral [(st InferState) (tok String) (vid Int64)] -> InferState
  (InferState :subst (.-subst st)
              :nextVar (.-nextVar st)
              :intSites (list-cons (pair tok vid) (.-intSites st))
              :mapSites (.-mapSites st)
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df noteLambda [(st InferState) (params (List ty/Type)) (ret ty/Type)] -> InferState
  (InferState :subst (.-subst st)
              :nextVar (.-nextVar st)
              :intSites (.-intSites st)
              :mapSites (.-mapSites st)
              :lambdas (list-cons (pair params ret) (.-lambdas st))
              :diags (.-diags st)))

(df setSubst [(st InferState) (s (Map Int64 ty/Type))] -> InferState
  (InferState :subst s
              :nextVar (.-nextVar st)
              :intSites (.-intSites st)
              :mapSites (.-mapSites st)
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df expectType [(st InferState) (have ty/Type) (want ty/Type) (where String) (path String)] -> InferState
  (let [(st1 (noteMapType (noteMapType st have where) want where))]
    (mt (u/unify have want (.-subst st1))
      ((u/uOk nextSubst) (setSubst st1 nextSubst))
      ((u/uErr msg isNum)
       (let [(code (if isNum "rule-6" "type"))]
         (addDiag st1 code (str where ": " msg) path))))))

(df qualifyTypeWithMod [(t ty/Type) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> ty/Type
  (mt t
    ((ty/tyVar _ _) t)
    ((ty/tyCon name args optMod optShown)
     (let [(isLocal (and (not (string-empty? (.-name mod)))
                          (or (mt (r/modSchema mod name) ((some _) true) ((none) false))
                              (mt (r/modEnum mod name) ((some _) true) ((none) false)))))
           (nextMod (mt optMod
                       ((some alias)
                        (mt (r/modImport mod alias)
                          ((some mpath)
                           (mt (map-get deps mpath)
                             ((some target) (some (.-name target)))
                             ((none) (some mpath))))
                          ((none) optMod)))
                       ((none)
                        (if isLocal
                          (some (.-name mod))
                          (none)))))]
        (ty/tyCon name (map (fn [(a ty/Type)] -> ty/Type (qualifyTypeWithMod a mod deps)) args) nextMod optShown)))
    ((ty/tyFun params ret)
     (ty/tyFun (map (fn [(p ty/Type)] -> ty/Type (qualifyTypeWithMod p mod deps)) params)
                (qualifyTypeWithMod ret mod deps)))))

(df instantiateSig [(params (List String)) (ret String) (typevars (List String)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair (Pair (List ty/Type) ty/Type) InferState)
  (let [(vRes (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (vname String)] -> (Pair (Map String ty/Type) InferState)
                       (let [(kind (if (= vname "N") "num" (if (= vname "I") "int" "any")))
                             (fRes (freshVar (.-second acc) kind))]
                         (pair (map-set (.-first acc) vname (.-first fRes))
                               (.-second fRes))))
                     (pair (map-empty) st)
                     typevars))]
    (let [(vmap (.-first vRes))
          (st1 (.-second vRes))
          (instP (map (fn [(p String)] -> ty/Type
                         (qualifyTypeWithMod (substParsedType (ty/parseTypeStr p (list)) vmap) mod deps))
                       params))
          (instR (qualifyTypeWithMod (substParsedType (ty/parseTypeStr ret (list)) vmap) mod deps))]
      (pair (pair instP instR) st1))))

(df substParsedTypes [(ts (List ty/Type)) (vmap (Map String ty/Type))] -> (List ty/Type)
  :d "Applies type variable mapping to a list of parsed types."
  (map (fn [(item ty/Type)] -> ty/Type (substParsedType item vmap)) ts))

(df substParsedType [(t ty/Type) (vmap (Map String ty/Type))] -> ty/Type
  :d "Substitutes concrete type variables in parsed types with fresh metavariables."
  (mt t
    ((ty/tyVar _ _) t)
    ((ty/tyCon name args optMod optShown)
     (mt (map-get vmap name)
       ((some mapped) mapped)
       ((none)
        (ty/tyCon name
                   (substParsedTypes args vmap)
                   optMod
                   optShown))))
    ((ty/tyFun params ret)
     (ty/tyFun (substParsedTypes params vmap)
                (substParsedType ret vmap)))))

(df sigResToFun [(res (Pair (Pair (List ty/Type) ty/Type) InferState))] -> (Option (Pair ty/Type InferState))
  (some (pair (ty/tyFun (.-first (.-first res)) (.-second (.-first res))) (.-second res))))

(df paramTypesToStrs [(params (List (Pair String String)))] -> (List String)
  (map (fn [(p (Pair String String))] -> String (.-second p)) params))

(df lookupLocalFun [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (r/modFun mod sym)
    ((some f)
     (let [(pStrs (paramTypesToStrs (.-params f)))
           (res (instantiateSig pStrs (.-ret f) (.-typevars f) mod deps st))]
       (sigResToFun res)))
    ((none) (none))))

(df lookupBuiltinSig [(sym String) (mod r/ModuleSummary) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (ty/builtinSig sym)
    ((some bsig)
     (let [(params (.-first bsig))
           (ret (.-second (.-second bsig)))
           (tvars (collectTvars params ret))
           (res (instantiateSig params ret tvars mod (map-empty) st))]
       (sigResToFun res)))
    ((none) (none))))

(df lookupLocalCase [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (map-get (.-caseOwner mod) sym)
    ((some ename)
     (mt (r/modEnum mod ename)
       ((some esum)
        (let [(matching (filter (fn [(c r/CaseSummary)] -> Bool (= (.-name c) sym)) (.-cases esum)))]
          (mt (list-head matching)
            ((some caseNode)
             (let [(pStrs (paramTypesToStrs (.-params caseNode)))
                   (tvars (.-typevars esum))
                   (retStr (if (list-empty? tvars)
                                ename
                                (str "(" ename " " (string-join tvars " ") ")")))
                   (res (instantiateSig pStrs retStr tvars mod deps st))]
               (sigResToFun res)))
            ((none) (none)))))
       ((none) (none))))
    ((none) (none))))

(df lookupLocalSymbol [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (lookupLocalFun sym mod deps st)
    ((some res) (some res))
    ((none) (lookupLocalCase sym mod deps st))))

(df lookupImportedSymbol [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (let [(parts (string-split sym "/"))
        (alias (mt (list-get parts 0) ((some a) a) ((none) "")))
        (member (mt (list-get parts 1) ((some m) m) ((none) "")))]
    (mt (r/modImport mod alias)
      ((some mpath)
       (mt (map-get deps mpath)
         ((some target) (lookupLocalSymbol member target deps st))
         ((none) (none))))
      ((none) (none)))))

(df lookupSymbolType [(sym String) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (map-get env sym)
    ((some t) (some (pair t st)))
    ((none)
     (mt (lookupLocalSymbol sym mod deps st)
       ((some res) (some res))
       ((none)
        (mt (lookupBuiltinSig sym mod st)
          ((some res) (some res))
          ((none)
           (if (string-contains? sym "/")
             (lookupImportedSymbol sym mod deps st)
             (none)))))))))

(df collectTvars [(params (List String)) (ret String)] -> (List String)
  (let [(allStrs (list-cons ret params))]
    (fold (fn [(acc (List String)) (s String)] -> (List String)
            (fold (fn [(aacc (List String)) (w String)] -> (List String)
                    (if (and (= (string-length w) 1) (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" w))
                      (if (list-contains? aacc w) aacc (list-cons w aacc))
                      aacc))
                  acc
                  (string-split (string-replace (string-replace (string-replace (string-replace s "(" " ") ")" " ") "[" " ") "]" " ") " ")))
          (list)
          allStrs)))

(df isFloatLit? [(v String)] -> Bool
  (let [(s (r/cleanNumSign v))]
    (if (string-contains? s ".")
      (let [(parts (string-split s "."))]
        (and (= (list-length parts) 2)
             (and (isAllDigits (mt (list-get parts 0) ((some d) d) ((none) "")))
                  (isAllDigits (mt (list-get parts 1) ((some d) d) ((none) ""))))))
      false)))

(df isIntLit? [(v String)] -> Bool
  (let [(s (r/cleanNumSign v))]
    (and (not (string-empty? s)) (isAllDigits s))))

(df unitType [] -> ty/Type
  (ty/tyCon "Unit" (list) (none) (none)))

(df lastExprUnit [(l (List rd/SExpr))] -> rd/SExpr
  (mt (list-head (list-reverse l))
    ((some e) e)
    ((none) (rd/makeAtom "()"))))

(df inferAtom [(v String) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (scope String) (path String) (st InferState)] -> (Pair ty/Type InferState)
  (cond
    ((string-starts-with? v "\"")
     (pair (ty/tyCon "String" (list) (none) (none)) st))
    ((or (= v "true") (= v "false"))
     (pair (ty/tyCon "Bool" (list) (none) (none)) st))
    ((or (= v "()") (= v "nil"))
     (pair (unitType) st))
    ((isFloatLit? v)
     (pair (ty/tyCon "Float64" (list) (none) (none)) st))
    ((isIntLit? v)
     (let [(vid (.-nextVar st))
           (fRes (freshVar st "int"))
           (vty (.-first fRes))
           (st1 (.-second fRes))
           (st2 (noteIntLiteral st1 v vid))]
       (pair vty st2)))
    (:else
     (mt (lookupSymbolType v env mod deps st)
       ((some found) found)
       ((none)
        (let [(st1 (addDiag st "rule-1" (str "unbound symbol: " v) path))]
          (freshVar st1 "any")))))))

(df inferAtomFm [(fm FrameMachine) (v String) (st InferState)] -> (Pair ty/Type InferState)
  (inferAtom v (.-env fm) (.-mod fm) (.-deps fm) (.-scope fm) (.-path fm) st))

(df asTyVar [(t ty/Type)] -> ty/Type
  t)

(df isAllDigits [(s String)] -> Bool
  (if (string-empty? s)
    false
    (fold (fn [(acc Bool) (c String)] -> Bool
            (and acc (string-contains? "0123456789" c)))
          true
          (string-chars s))))

(df parseParamParts [(parts (List rd/SExpr)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Pair String (Option ty/Type))
  (let [(h (r/firstHeadIdent parts))
        (sub (r/safeTail parts))]
    (mt (list-head sub)
      ((some tyNode)
       (pair h (some (qualifyTypeWithMod (ty/parseTypeStr (rd/renderSexpr tyNode) (list)) mod deps))))
      ((none) (pair h (none))))))

(df parseParamAnn [(p rd/SExpr) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Pair String (Option ty/Type))
  (mt p
    ((rd/sexprAtom n) (pair n (none)))
    ((rd/sexprList parts) (parseParamParts parts mod deps))
    ((rd/sexprVect parts) (parseParamParts parts mod deps))))

(dfe InferFrame
  (:c fEval [(expr rd/SExpr)] "Evaluate expression next")
  (:c fCall [(calleeName String) (calleeTy ty/Type) (argsDone (List ty/Type)) (argsPending (List rd/SExpr)) (env (Map String ty/Type))] "Call evaluation continuation")
  (:c fLetVal [(bname String) (bindingsRest (List rd/SExpr)) (tailExprs (List rd/SExpr)) (env (Map String ty/Type))] "Let binding evaluation continuation")
  (:c fIfCond [(thenE rd/SExpr) (elseE rd/SExpr) (env (Map String ty/Type))] "If condition continuation")
  (:c fIfThen [(elseE rd/SExpr) (thenTy ty/Type) (env (Map String ty/Type))] "If branches continuation")
  (:c fTryInner [(valVar ty/Type)] "Try continuation"))

(dfs FrameMachine
  (:f frames (List InferFrame) "Pending evaluation frame stack")
  (:f values (List ty/Type) "Evaluated type values stack")
  (:f env (Map String ty/Type) "Current lexical type environment")
  (:f retType (Option ty/Type) "Enclosing defun return type")
  (:f inLambda Bool "True when evaluating inside fn")
  (:f scope String "Current scope label")
  (:f path String "Source file path")
  (:f mod r/ModuleSummary "Module summary")
  (:f deps (Map String r/ModuleSummary) "Dependency summaries")
  (:f state InferState "Inference state carrying substitution"))

(df fmPushFresh [(fm FrameMachine) (restFrames (List InferFrame)) (st InferState)] -> FrameMachine
  (let [(fRes (freshVar st "any"))]
    (FrameMachine :frames restFrames
                  :values (list-cons (.-first fRes) (.-values fm))
                  :env (.-env fm)
                  :retType (.-retType fm)
                  :inLambda (.-inLambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state (.-second fRes))))

(df popValue [(fm FrameMachine)] -> (Pair ty/Type (List ty/Type))
  (pair (mt (list-head (.-values fm)) ((some v) v) ((none) (unitType)))
        (r/safeTail (.-values fm))))

(df fmTick [(fm FrameMachine) (tickIdx Int64)] -> FrameMachine
  (mt (list-head (.-frames fm))
    ((none) fm)
    ((some topFrame)
     (let [(restFrames (r/safeTail (.-frames fm)))]
       (mt topFrame
         ((fEval expr)
          (fmEvalStep expr restFrames fm))
         ((fCall cname cty argsDone argsPending cenv)
          (fmCallStep cname cty argsDone argsPending cenv restFrames fm))
         ((fLetVal bname brest tails lenv)
          (fmLetValStep bname brest tails lenv restFrames fm))
         ((fIfCond thenE elseE ienv)
          (fmIfCondStep thenE elseE ienv restFrames fm))
         ((fIfThen elseE thenTy ienv)
          (fmIfThenStep elseE thenTy ienv restFrames fm))
         ((fTryInner valVar)
          (fmTryStep valVar restFrames fm)))))))

(df bindMatchPattern [(pat rd/SExpr) (scrutTy ty/Type) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair (Map String ty/Type) InferState)
  (mt pat
    ((rd/sexprAtom name)
     (if (or (= name "_") (r/isLiteralAtom? name))
       (pair env st)
       (pair (map-set env name scrutTy) st)))
    ((rd/sexprVect _)
     (pair env st))
    ((rd/sexprList parts)
     (mt (list-head parts)
       ((none) (pair env st))
       ((some h)
        (let [(cname (rd/sexprHead h))
              (subPats (r/safeTail parts))
              (ctorOpt (lookupSymbolType cname env mod deps st))]
          (mt ctorOpt
            ((none)
             (let [(st1 (addDiag st "type" (str "unknown constructor in match pattern: " cname) (.-path mod)))]
               (pair env st1)))
            ((some ctorRes)
             (let [(ctorTy (.-first ctorRes))
                   (st1 (.-second ctorRes))]
               (mt (u/applySubst (.-subst st1) ctorTy)
                 ((ty/tyFun cparams cret)
                  (let [(st2 (expectType st1 scrutTy cret (str "pattern " cname) (.-path mod)))]
                    (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (pairItem (Pair rd/SExpr ty/Type))] -> (Pair (Map String ty/Type) InferState)
                            (bindMatchPattern (.-first pairItem)
                                                (u/applySubst (.-subst (.-second acc)) (.-second pairItem))
                                                (.-first acc)
                                                mod
                                                deps
                                                (.-second acc)))
                          (pair env st2)
                          (zip subPats cparams))))
                 (_ (pair env st1))))))))))))

(df fmTryOutsideError [(fm FrameMachine) (innerE rd/SExpr) (restFrames (List InferFrame))] -> FrameMachine
  (let [(st1 (addDiag (.-state fm) "rule-5" "try outside a defun returning (Result _ E)" (.-path fm)))]
    (FrameMachine :frames (list-cons (fEval innerE) restFrames)
                  :values (.-values fm)
                  :env (.-env fm)
                  :retType (.-retType fm)
                  :inLambda (.-inLambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fmEvalStep [(expr rd/SExpr) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (mt expr
    ((rd/sexprAtom v)
     (let [(res (inferAtomFm fm v (.-state fm)))]
       (FrameMachine :frames restFrames
                     :values (list-cons (.-first res) (.-values fm))
                     :env (.-env fm)
                     :retType (.-retType fm)
                     :inLambda (.-inLambda fm)
                     :scope (.-scope fm)
                     :path (.-path fm)
                     :mod (.-mod fm)
                     :deps (.-deps fm)
                     :state (noteMapType (.-second res) (.-first res) (.-scope fm)))))
    ((rd/sexprVect items)
     (let [(fRes (freshVar (.-state fm) "any"))
           (elemTy (.-first fRes))
           (st1 (.-second fRes))]
       (FrameMachine :frames restFrames
                     :values (list-cons (ty/tyCon "List" (list elemTy) (none) (none)) (.-values fm))
                     :env (.-env fm)
                     :retType (.-retType fm)
                     :inLambda (.-inLambda fm)
                     :scope (.-scope fm)
                     :path (.-path fm)
                     :mod (.-mod fm)
                     :deps (.-deps fm)
                     :state st1)))
    ((rd/sexprList items)
     (mt (list-head items)
       ((none)
        (FrameMachine :frames restFrames
                      :values (list-cons (unitType) (.-values fm))
                      :env (.-env fm)
                      :retType (.-retType fm)
                      :inLambda (.-inLambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm)))
       ((some h)
        (let [(headTok (rd/sexprHead h))
              (tailArgs (r/safeTail items))]
          (cond
            ((or (= headTok "quote") (= headTok "quasiquote"))
             (let [(sexprTy (ty/tyCon "SExpr" (list) (none) (none)))]
               (FrameMachine :frames restFrames
                             :values (list-cons sexprTy (.-values fm))
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state (.-state fm))))

            ((= headTok "do")
             (if (list-empty? tailArgs)
               (FrameMachine :frames restFrames
                             :values (list-cons (unitType) (.-values fm))
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state (.-state fm))
               (let [(res (fold (fn [(acc (Pair ty/Type InferState)) (arg rd/SExpr)] -> (Pair ty/Type InferState)
                                  (evalFm fm arg (.-second acc)))
                                (pair (unitType) (.-state fm))
                                tailArgs))]
                 (FrameMachine :frames restFrames
                               :values (list-cons (.-first res) (.-values fm))
                               :env (.-env fm)
                               :retType (.-retType fm)
                               :inLambda (.-inLambda fm)
                               :scope (.-scope fm)
                               :path (.-path fm)
                               :mod (.-mod fm)
                               :deps (.-deps fm)
                               :state (.-second res)))))

            ((= headTok "let")
             (let [(bitems (r/firstVectItems tailArgs))
                   (tails (r/safeTail tailArgs))]
               (if (list-empty? bitems)
                 (let [(lastE (lastExprUnit tails))]
                   (FrameMachine :frames (list-cons (fEval lastE) restFrames)
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :retType (.-retType fm)
                                 :inLambda (.-inLambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state (.-state fm)))
                 (let [(firstB (r/firstExprEmpty bitems))
                       (brest (r/safeTail bitems))
                       (bparts (mt firstB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))
                       (bname (r/firstHeadIdent bparts))
                       (bval (r/secondExprEmpty bparts))]
                   (FrameMachine :frames (list-cons (fEval bval) (list-cons (fLetVal bname brest tails (.-env fm)) restFrames))
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :retType (.-retType fm)
                                 :inLambda (.-inLambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state (.-state fm))))))

            ((= headTok "if")
             (let [(condE (option-or (list-get tailArgs 0) (rd/makeAtom "true")))
                   (thenE (option-or (list-get tailArgs 1) (rd/makeAtom "()")))
                   (elseE (option-or (list-get tailArgs 2) (rd/makeAtom "()")))]
               (FrameMachine :frames (list-cons (fEval condE) (list-cons (fIfCond thenE elseE (.-env fm)) restFrames))
                             :values (.-values fm)
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state (.-state fm))))

            ((= headTok "cond")
             (let [(fRes (freshVar (.-state fm) "any"))
                   (outVar (.-first fRes))
                   (stOut (.-second fRes))
                   (stFinal (fold (fn [(stAcc InferState) (clause rd/SExpr)] -> InferState
                                     (mt clause
                                       ((rd/sexprList cparts)
                                        (let [(cheadExpr (r/firstExprEmpty cparts))
                                               (chead (rd/sexprHead cheadExpr))
                                               (cbodies (r/safeTail cparts))
                                               (lastB (lastExprUnit cbodies))]
                                           (if (= chead ":else")
                                             (let [(bres (evalFm fm lastB stAcc))]
                                               (expectType (.-second bres) (.-first bres) outVar "cond else clause" (.-path fm)))
                                             (let [(cres (evalFm fm cheadExpr stAcc))
                                                   (stC (expectType (.-second cres) (.-first cres) (ty/tyCon "Bool" (list) (none) (none)) "cond test" (.-path fm)))
                                                   (bres (evalFm fm lastB stC))]
                                               (expectType (.-second bres) (.-first bres) outVar "cond clause" (.-path fm))))))
                                        (_ stAcc)))
                                   stOut
                                   tailArgs))]
               (FrameMachine :frames restFrames
                             :values (list-cons (u/applySubst (.-subst stFinal) outVar) (.-values fm))
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state stFinal)))

            ((or (= headTok "match") (= headTok "mt"))
             (let [(scrutinee (r/firstExprUnit tailArgs))
                   (arms (r/safeTail tailArgs))
                   (scrutRes (evalFm fm scrutinee (.-state fm)))
                   (scrutTy (.-first scrutRes))
                   (stScrut (.-second scrutRes))
                   (fRes (freshVar stScrut "any"))
                   (outVar (.-first fRes))
                   (stOut (.-second fRes))
                   (stFinal (fold (fn [(stAcc InferState) (arm rd/SExpr)] -> InferState
                                     (mt arm
                                       ((rd/sexprList armParts)
                                        (let [(pat (mt (list-head armParts) ((some p) p) ((none) (rd/makeAtom "_"))))
                                              (bodyExprs (r/safeTail armParts))
                                              (bindRes (bindMatchPattern pat (u/applySubst (.-subst stAcc) scrutTy) (.-env fm) (.-mod fm) (.-deps fm) stAcc))
                                              (armEnv (.-first bindRes))
                                              (stArm (.-second bindRes))
                                              (lastBody (lastExprUnit bodyExprs))
                                              (bodyRes (evalWithEnv fm lastBody armEnv stArm))
                                              (bodyTy (.-first bodyRes))
                                              (stB (.-second bodyRes))]
                                          (expectType stB bodyTy outVar "match arm" (.-path fm))))
                                       (_ stAcc)))
                                   stOut
                                   arms))]
               (FrameMachine :frames restFrames
                             :values (list-cons (u/applySubst (.-subst stFinal) outVar) (.-values fm))
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state stFinal)))

            ((= headTok "try")
             (let [(innerE (r/firstExprUnit tailArgs))]
               (if (.-inLambda fm)
                 (let [(st1 (addDiag (.-state fm) "rule-5" "try inside fn: it would return from the enclosing defun, not from the lambda" (.-path fm)))]
                   (FrameMachine :frames (list-cons (fEval innerE) restFrames)
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :retType (.-retType fm)
                                 :inLambda (.-inLambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state st1))
                 (let [(enclosing (mt (.-retType fm)
                                    ((some r) (u/applySubst (.-subst (.-state fm)) r))
                                    ((none) (unitType))))]
                   (mt enclosing
                     ((ty/tyCon rname rargs _ _)
                      (if (and (= rname "Result") (= (list-length rargs) 2))
                        (let [(fRes (freshVar (.-state fm) "any"))
                              (vty (.-first fRes))
                              (st1 (.-second fRes))]
                          (FrameMachine :frames (list-cons (fEval innerE) (list-cons (fTryInner vty) restFrames))
                                        :values (.-values fm)
                                        :env (.-env fm)
                                        :retType (.-retType fm)
                                        :inLambda (.-inLambda fm)
                                        :scope (.-scope fm)
                                        :path (.-path fm)
                                        :mod (.-mod fm)
                                        :deps (.-deps fm)
                                        :state st1))
                        (fmTryOutsideError fm innerE restFrames)))
                     (_
                      (fmTryOutsideError fm innerE restFrames)))))))

            ((= headTok "fn")
             (let [(isBang (and (not (list-empty? tailArgs))
                                 (= (r/firstHeadIdent tailArgs) "!")))
                   (remArgs (if isBang (r/safeTail tailArgs) tailArgs))
                   (afterParams (r/safeTail remArgs))
                   (hasRetAnn (and (not (list-empty? afterParams))
                                     (= (r/firstHeadIdent afterParams) "->")))
                   (bodyNodes (if hasRetAnn
                                 (r/safeTail (r/safeTail afterParams))
                                 afterParams))
                   (paramItems (r/firstVectItems remArgs))
                   (pRes (fold (fn [(acc (Pair (Pair (List ty/Type) (Map String ty/Type)) (Pair InferState Bool))) (p rd/SExpr)] -> (Pair (Pair (List ty/Type) (Map String ty/Type)) (Pair InferState Bool))
                                  (let [(pann (parseParamAnn p (.-mod fm) (.-deps fm)))
                                        (pname (.-first pann))
                                        (optTy (.-second pann))]
                                    (mt optTy
                                      ((some pty)
                                       (pair (pair (list-cons pty (.-first (.-first acc)))
                                                   (map-set (.-second (.-first acc)) pname pty))
                                             (pair (.-first (.-second acc)) (.-second (.-second acc)))))
                                      ((none)
                                       (let [(fRes (freshVar (.-first (.-second acc)) "any"))
                                             (pty (.-first fRes))
                                             (st1 (.-second fRes))]
                                         (pair (pair (list-cons pty (.-first (.-first acc)))
                                                     (map-set (.-second (.-first acc)) pname pty))
                                               (pair st1 true)))))))
                                (pair (pair (list) (.-env fm)) (pair (.-state fm) false))
                                paramItems))
                    (paramsTy (list-reverse (.-first (.-first pRes))))
                    (fnEnv (.-second (.-first pRes)))
                    (st1 (.-first (.-second pRes)))
                    (hasPElided (.-second (.-second pRes)))
                    (afterArrow (if hasRetAnn (r/safeTail afterParams) (list)))
                    (retNodeOpt (list-head afterArrow))
                    (retInfo (mt retNodeOpt
                                ((some rnode)
                                 (pair (qualifyTypeWithMod (ty/parseTypeStr (rd/renderSexpr rnode) (list)) (.-mod fm) (.-deps fm))
                                       (pair st1 hasPElided)))
                                ((none)
                                 (let [(fRet (freshVar st1 "any"))]
                                   (pair (.-first fRet) (pair (.-second fRet) true))))))
                    (retTy (.-first retInfo))
                    (st2 (.-first (.-second retInfo)))
                    (hasElided (.-second (.-second retInfo)))
                    (lastBody (lastExprUnit bodyNodes))
                    (bodyRes (runExprDirect lastBody fnEnv (some retTy) true (.-scope fm) (.-path fm) (.-mod fm) (.-deps fm) st2))
                    (bodyTy (.-first bodyRes))
                    (st3 (expectType (.-second bodyRes) bodyTy retTy "lambda body" (.-path fm)))
                    (st4 (if hasElided (noteLambda st3 paramsTy retTy) st3))
                    (fnTy (ty/tyFun paramsTy retTy))]
               (FrameMachine :frames restFrames
                             :values (list-cons fnTy (.-values fm))
                             :env (.-env fm)
                             :retType (.-retType fm)
                             :inLambda (.-inLambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state st4)))

            ((string-starts-with? headTok ".-")
             (let [(fname (r/sliceFrom headTok 2))
                   (tgtE (r/firstExprUnit tailArgs))
                   (tgtRes (evalFm fm tgtE (.-state fm)))
                   (tgtTy (u/applySubst (.-subst (.-second tgtRes)) (.-first tgtRes)))
                   (st1 (.-second tgtRes))]
               (mt tgtTy
                 ((ty/tyCon tname targs toptMod _)
                  (if (and (= tname "Pair") (= (list-length targs) 2))
                    (let [(outTy (if (= fname "first")
                                    (mt (list-get targs 0) ((some f) f) ((none) (unitType)))
                                    (mt (list-get targs 1) ((some s) s) ((none) (unitType)))))]
                      (FrameMachine :frames restFrames
                                    :values (list-cons outTy (.-values fm))
                                    :env (.-env fm)
                                    :retType (.-retType fm)
                                    :inLambda (.-inLambda fm)
                                    :scope (.-scope fm)
                                    :path (.-path fm)
                                    :mod (.-mod fm)
                                    :deps (.-deps fm)
                                    :state st1))
                    (let [(targetMod (mt toptMod
                                        ((some alias)
                                         (mt (r/modImport (.-mod fm) alias)
                                           ((some mpath) (map-get (.-deps fm) mpath))
                                           ((none) (none))))
                                        ((none) (some (.-mod fm)))))]
                      (mt targetMod
                        ((none)
                         (let [(st2 (addDiag st1 "type" (str "unknown module for type " (ty/showType tgtTy)) (.-path fm)))]
                           (fmPushFresh fm restFrames st2)))
                        ((some smod)
                         (mt (r/modSchema smod tname)
                           ((some ssum)
                            (let [(fMatch (filter (fn [(f r/FieldSummary)] -> Bool (= (.-name f) fname)) (.-fields ssum)))]
                              (mt (list-head fMatch)
                                ((some fdef)
                                 (let [(fieldTy (ty/parseTypeStr (.-type fdef) (list)))
                                       (substMap (fold (fn [(acc (Map String ty/Type)) (p (Pair String ty/Type))] -> (Map String ty/Type)
                                                          (map-set acc (.-first p) (.-second p)))
                                                        (map-empty)
                                                        (zip (.-typevars ssum) targs)))
                                       (instField (substParsedType fieldTy substMap))]
                                   (FrameMachine :frames restFrames
                                                 :values (list-cons instField (.-values fm))
                                                 :env (.-env fm)
                                                 :retType (.-retType fm)
                                                 :inLambda (.-inLambda fm)
                                                 :scope (.-scope fm)
                                                 :path (.-path fm)
                                                 :mod (.-mod fm)
                                                 :deps (.-deps fm)
                                                 :state st1)))
                                ((none)
                                 (let [(st2 (addDiag st1 "type" (str (ty/showType tgtTy) " has no field " fname) (.-path fm)))]
                                   (fmPushFresh fm restFrames st2))))))
                            ((none)
                             (let [(st2 (addDiag st1 "type" (str "unknown schema " tname " in module " (.-name smod)) (.-path fm)))]
                               (fmPushFresh fm restFrames st2)))))))))
                 (_
                  (fmPushFresh fm restFrames st1)))))

            (:else
             (let [(calleeRes (inferAtomFm fm headTok (.-state fm)))
                   (calleeTy (.-first calleeRes))
                   (st1 (.-second calleeRes))]
               (if (list-empty? tailArgs)
                 (mt (u/applySubst (.-subst st1) calleeTy)
                   ((ty/tyFun p r)
                    (FrameMachine :frames restFrames
                                  :values (list-cons r (.-values fm))
                                  :env (.-env fm)
                                  :retType (.-retType fm)
                                  :inLambda (.-inLambda fm)
                                  :scope (.-scope fm)
                                  :path (.-path fm)
                                  :mod (.-mod fm)
                                  :deps (.-deps fm)
                                  :state st1))
                   (_
                    (FrameMachine :frames restFrames
                                  :values (list-cons calleeTy (.-values fm))
                                  :env (.-env fm)
                                  :retType (.-retType fm)
                                  :inLambda (.-inLambda fm)
                                  :scope (.-scope fm)
                                  :path (.-path fm)
                                  :mod (.-mod fm)
                                  :deps (.-deps fm)
                                  :state st1)))
                 (let [(firstArg (r/firstExprUnit tailArgs))
                       (pendingArgs (r/safeTail tailArgs))]
                   (FrameMachine :frames (list-cons (fEval firstArg) (list-cons (fCall headTok calleeTy (list) pendingArgs (.-env fm)) restFrames))
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :retType (.-retType fm)
                                 :inLambda (.-inLambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state st1))))))))))))

(df fmCallStep [(cname String) (cty ty/Type) (argsDone (List ty/Type)) (argsPending (List rd/SExpr)) (cenv (Map String ty/Type)) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (popValue fm))
        (val (.-first pv))
        (remValues (.-second pv))
        (nextDone (r/listAppendOne argsDone val))]
    (if (list-empty? argsPending)
      (let [(prunedCallee (u/applySubst (.-subst (.-state fm)) cty))]
        (mt prunedCallee
          ((ty/tyFun params ret)
           (let [(stUnify (foldExpectArgs nextDone params cname (.-path fm) (.-state fm)))]
             (FrameMachine :frames restFrames
                           :values (list-cons (u/applySubst (.-subst stUnify) ret) remValues)
                           :env (.-env fm)
                           :retType (.-retType fm)
                           :inLambda (.-inLambda fm)
                           :scope (.-scope fm)
                           :path (.-path fm)
                           :mod (.-mod fm)
                           :deps (.-deps fm)
                           :state stUnify)))
          (_
           (let [(fRes (freshVar (.-state fm) "any"))]
             (FrameMachine :frames restFrames
                           :values (list-cons (.-first fRes) remValues)
                           :env (.-env fm)
                           :retType (.-retType fm)
                           :inLambda (.-inLambda fm)
                           :scope (.-scope fm)
                           :path (.-path fm)
                           :mod (.-mod fm)
                           :deps (.-deps fm)
                           :state (.-second fRes))))))
      (let [(nextArg (r/firstExprUnit argsPending))
            (remPending (r/safeTail argsPending))]
        (FrameMachine :frames (list-cons (fEval nextArg) (list-cons (fCall cname cty nextDone remPending cenv) restFrames))
                      :values remValues
                      :env (.-env fm)
                      :retType (.-retType fm)
                      :inLambda (.-inLambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm))))))

(df foldExpectArgs [(args (List ty/Type)) (params (List ty/Type)) (cname String) (path String) (st InferState)] -> InferState
  (mt (list-head args)
    ((none) st)
    ((some a)
     (mt (list-head params)
       ((none) st)
       ((some p)
        (let [(st1 (expectType st a p (str "argument to " cname) path))]
          (foldExpectArgs (r/safeTail args)
                            (r/safeTail params)
                            cname
                            path
                            st1)))))))

(df fmLetValStep [(bname String) (brest (List rd/SExpr)) (tails (List rd/SExpr)) (lenv (Map String ty/Type)) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (popValue fm))
        (val (.-first pv))
        (remValues (.-second pv))
        (nextEnv (map-set lenv bname val))]
    (if (list-empty? brest)
      (let [(lastE (lastExprUnit tails))]
        (FrameMachine :frames (list-cons (fEval lastE) restFrames)
                      :values remValues
                      :env nextEnv
                      :retType (.-retType fm)
                      :inLambda (.-inLambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm)))
      (let [(nextB (r/firstExprEmpty brest))
            (remBrest (r/safeTail brest))
            (bparts (mt nextB ((rd/sexprList bp) bp) ((rd/sexprVect bp) bp) (_ (list))))
            (nextBname (r/firstHeadIdent bparts))
            (nextBval (r/secondExprEmpty bparts))]
        (FrameMachine :frames (list-cons (fEval nextBval) (list-cons (fLetVal nextBname remBrest tails nextEnv) restFrames))
                      :values remValues
                      :env nextEnv
                      :retType (.-retType fm)
                      :inLambda (.-inLambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm))))))

(df fmIfCondStep [(thenE rd/SExpr) (elseE rd/SExpr) (ienv (Map String ty/Type)) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (popValue fm))
        (condTy (.-first pv))
        (remValues (.-second pv))
        (st1 (expectType (.-state fm) condTy (ty/tyCon "Bool" (list) (none) (none)) "if condition" (.-path fm)))]
    (FrameMachine :frames (list-cons (fEval thenE) (list-cons (fIfThen elseE condTy ienv) restFrames))
                  :values remValues
                  :env ienv
                  :retType (.-retType fm)
                  :inLambda (.-inLambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fmIfThenStep [(elseE rd/SExpr) (thenTy ty/Type) (ienv (Map String ty/Type)) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (popValue fm))
        (actualThen (.-first pv))
        (remValues (.-second pv))
        (elseRes (evalWithEnv fm elseE ienv (.-state fm)))
        (elseTy (.-first elseRes))
        (st1 (expectType (.-second elseRes) elseTy actualThen "if branches" (.-path fm)))]
    (FrameMachine :frames restFrames
                  :values (list-cons actualThen remValues)
                  :env ienv
                  :retType (.-retType fm)
                  :inLambda (.-inLambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fmTryStep [(valVar ty/Type) (restFrames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (popValue fm))
        (innerTy (.-first pv))
        (remValues (.-second pv))
        (enclosing (mt (.-retType fm)
                     ((some r) (u/applySubst (.-subst (.-state fm)) r))
                     ((none) (ty/tyCon "Result" (list valVar (unitType)) (none) (none)))))
        (errTy (mt enclosing
                  ((ty/tyCon _ rargs _ _)
                   (mt (list-get rargs 1) ((some e) e) ((none) (unitType))))
                  (_ (unitType))))
        (wantRes (ty/tyCon "Result" (list valVar errTy) (none) (none)))
        (st1 (expectType (.-state fm) innerTy wantRes "try" (.-path fm)))]
    (FrameMachine :frames restFrames
                  :values (list-cons valVar remValues)
                  :env (.-env fm)
                  :retType (.-retType fm)
                  :inLambda (.-inLambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fmRun [(fm FrameMachine) (budget Int64)] -> FrameMachine
  :d "Iterative doubling budget worklist execution loop."
  (let [(nextFm (fold fmTick fm (range 0 budget)))]
    (if (list-empty? (.-frames nextFm))
      nextFm
      (fmRun nextFm (* budget 2)))))

(df runExprDirect [(expr rd/SExpr) (env (Map String ty/Type)) (retType (Option ty/Type)) (inLambda Bool) (scope String) (path String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair ty/Type InferState)
  (let [(initFm (FrameMachine :frames (list (fEval expr))
                               :values (list)
                               :env env
                               :retType retType
                               :inLambda inLambda
                               :scope scope
                               :path path
                               :mod mod
                               :deps deps
                               :state st))]
    (let [(finalFm (fmRun initFm 64))]
      (let [(outTy (mt (list-head (.-values finalFm))
                      ((some t) t)
                      ((none) (unitType))))
            (stNoted (noteMapType (.-state finalFm) outTy scope))]
        (pair outTy stNoted)))))

(df evalWithEnv [(fm FrameMachine) (e rd/SExpr) (env (Map String ty/Type)) (st InferState)] -> (Pair ty/Type InferState)
  (runExprDirect e env (.-retType fm) (.-inLambda fm) (.-scope fm) (.-path fm) (.-mod fm) (.-deps fm) st))

(df evalFm [(fm FrameMachine) (e rd/SExpr) (st InferState)] -> (Pair ty/Type InferState)
  (evalWithEnv fm e (.-env fm) st))

(df checkUndeterminedLambdas [(lambdas (List (Pair (List ty/Type) ty/Type))) (subst (Map Int64 ty/Type)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (lam (Pair (List ty/Type) ty/Type))] -> (List ty/Diagnostic)
          (let [(params (.-first lam))
                (ret (.-second lam))
                (allTys (list-cons ret params))
                (hasUnbound (fold (fn [(accU Bool) (t ty/Type)] -> Bool
                                     (or accU
                                         (let [(pruned (u/applySubst subst t))]
                                           (mt pruned
                                             ((ty/tyVar _ _) true)
                                             (_ false)))))
                                   false
                                   allTys))]
            (if hasUnbound
              (list-cons (ty/Diagnostic :code "annotation" :message "nothing in this position determines the lambda's types; write them" :line 1 :col 1 :path path) a)
              a)))
        acc
        lambdas))

(df checkLiteralRanges [(intSites (List (Pair String Int64))) (subst (Map Int64 ty/Type)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair String Int64))] -> (List ty/Diagnostic)
          (let [(tokStr (.-first site))
                (vid (.-second site))
                (wty (u/applySubst subst (ty/tyVar vid "int")))
                (tname (mt wty
                         ((ty/tyCon n _ _ _) n)
                         (_ "Int64")))]
            (mt (ty/intRangeBounds tname)
              ((none) a)
              ((some b)
               (let [(low (.-first b))
                     (high (.-second b))
                     (numOpt (string-to-int64 tokStr))
                     (badLit? (mt numOpt ((none) true) ((some n) (or (< n low) (> n high)))))]
                 (if badLit?
                   (list-cons (ty/Diagnostic :code "literal-range" :message (str "the literal " tokStr " does not fit " tname " (" (string-from-int64 low) ".." (string-from-int64 high) ")") :line 1 :col 1 :path path) a)
                   a))))))
        acc
        intSites))

(df mapHasKey? [(m (Map String Bool)) (k String)] -> Bool
  (mt (map-get m k)
    ((some _) true)
    ((none) false)))

(df extractMapKeysList [(types (List ty/Type)) (subst (Map Int64 ty/Type))] -> (List ty/Type)
  (fold (fn [(acc (List ty/Type)) (t ty/Type)] -> (List ty/Type)
          (list-append (extractMapKeys t subst) acc))
        (list)
        types))

(df extractMapKeys [(t ty/Type) (subst (Map Int64 ty/Type))] -> (List ty/Type)
  (let [(pruned (u/applySubst subst t))]
    (mt pruned
      ((ty/tyCon name args _ _)
       (let [(subKeys (extractMapKeysList args subst))]
         (if (and (= name "Map") (>= (list-length args) 1))
           (list-cons (mt (list-head args) ((some k) k) ((none) pruned)) subKeys)
           subKeys)))
      ((ty/tyFun params ret)
       (list-append (extractMapKeys ret subst) (extractMapKeysList params subst)))
      ((ty/tyVar _ _) (list)))))

(df checkTypeUnordered [(t ty/Type) (subst (Map Int64 ty/Type)) (visited (Map String Bool)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Option String)
  (let [(pruned (u/applySubst subst t))]
    (mt pruned
      ((ty/tyVar _ _) (none))
      ((ty/tyFun _ _) (none))
      ((ty/tyCon name args optMod _)
       (if (ty/unorderedType? name)
         (some name)
         (let [(badArg (fold (fn [(acc (Option String)) (a ty/Type)] -> (Option String)
                                (mt acc
                                  ((some _) acc)
                                  ((none) (checkTypeUnordered a subst visited mod deps))))
                              (none)
                              args))]
           (mt badArg
             ((some b) (some b))
             ((none)
              (let [(typeKey (str (mt optMod ((some m) m) ((none) (.-name mod))) "/" name))]
                (if (mapHasKey? visited typeKey)
                  (none)
                  (let [(nextVis (map-set visited typeKey true))
                        (targetMod (mt optMod
                                      ((some m)
                                        (if (= m (.-name mod))
                                          (some mod)
                                          (mt (r/modImport mod m)
                                            ((some mpath) (map-get deps mpath))
                                            ((none) (map-get deps m)))))
                                       ((none) (some mod))))]
                    (mt targetMod
                      ((none) (none))
                      ((some tmod)
                       (mt (r/modSchema tmod name)
                         ((some ssum)
                          (fold (fn [(acc (Option String)) (f r/FieldSummary)] -> (Option String)
                                  (mt acc
                                    ((some _) acc)
                                    ((none)
                                     (let [(fty (ty/parseTypeStr (.-type f) (list)))]
                                       (checkTypeUnordered fty subst nextVis tmod deps)))))
                                (none)
                                (.-fields ssum)))
                         ((none)
                          (mt (r/modEnum tmod name)
                            ((some esum)
                             (fold (fn [(acc (Option String)) (c r/CaseSummary)] -> (Option String)
                                     (mt acc
                                       ((some _) acc)
                                       ((none)
                                        (fold (fn [(cacc (Option String)) (p (Pair String String))] -> (Option String)
                                                (mt cacc
                                                  ((some _) cacc)
                                                  ((none)
                                                   (let [(pty (qualifyTypeWithMod (ty/parseTypeStr (.-second p) (list)) mod deps))]
                                                     (checkTypeUnordered pty subst nextVis tmod deps)))))
                                              acc
                                              (.-params c)))))
                                   (none)
                                   (.-cases esum)))
                            ((none) (none))))))))))))))))))

(df checkMapKeyRules [(mapSites (List (Pair ty/Type String))) (subst (Map Int64 ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair ty/Type String))] -> (List ty/Diagnostic)
          (let [(tySite (.-first site))
                (scopeLbl (.-second site))
                (mkeys (extractMapKeys tySite subst))]
            (fold (fn [(ka (List ty/Diagnostic)) (k ty/Type)] -> (List ty/Diagnostic)
                    (mt (checkTypeUnordered k subst (map-empty) mod deps)
                      ((none) ka)
                      ((some bad)
                       (let [(shown (ty/showType k))
                             (msg (if (= shown bad)
                                    (str shown " as a Map key has no total order; map-keys is specified to return keys sorted")
                                    (str "the Map key " shown " reaches " bad ", which has no total order; map-keys is specified to return keys sorted")))]
                         (list-cons (ty/Diagnostic :code "map-key-order" :message msg :line 1 :col 1 :path path) ka)))))
                  a
                  mkeys)))
        acc
        mapSites))

(df checkModule [(forms (List a/TopForm)) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Purely functional semantic type checker for an AST module."
  (let [(summary (r/collectSummary forms path))
        (p12Diags (r/resolveModule summary forms deps))
        (defunDiags (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
                             (mt form
                               ((a/topDefun d)
                                (let [(st0 (makeInferState))
                                      (env0 (fold (fn [(e (Map String ty/Type)) (p a/Param)] -> (Map String ty/Type)
                                                    (map-set e (.-name p) (qualifyTypeWithMod (ty/parseTypeStr (.-type p) (list)) summary deps)))
                                                  (map-empty)
                                                  (.-params d)))
                                      (retTy (qualifyTypeWithMod (ty/parseTypeStr (.-retType d) (list)) summary deps))
                                      (scopeName (str "function " (.-name d)))
                                      (stParams (fold (fn [(s InferState) (p a/Param)] -> InferState
                                                         (noteMapType s (qualifyTypeWithMod (ty/parseTypeStr (.-type p) (list)) summary deps) scopeName))
                                                       st0
                                                       (.-params d)))
                                      (stNote (noteMapType stParams retTy scopeName))
                                      (bodyNodes (.-body d))]
                                  (if (list-empty? bodyNodes)
                                    acc
                                    (let [(allBodyRes (fold (fn [(accRes (Pair ty/Type InferState)) (e rd/SExpr)] -> (Pair ty/Type InferState)
                                                              (runExprDirect e env0 (some retTy) false scopeName path summary deps (.-second accRes)))
                                                            (pair (unitType) stNote)
                                                            bodyNodes))
                                          (lastTy (.-first allBodyRes))
                                          (st1 (.-second allBodyRes))
                                          (st2 (expectType st1 lastTy retTy (str "return of " (.-name d)) path))
                                          (st3Subst (.-subst st2))
                                          (dLam (checkUndeterminedLambdas (.-lambdas st2) st3Subst path (.-diags st2)))
                                          (dLit (checkLiteralRanges (.-intSites st2) st3Subst path dLam))
                                          (dMap (checkMapKeyRules (.-mapSites st2) st3Subst summary deps path dLit))]
                                      (list-append dMap acc)))))
                               (_ acc)))
                           (list)
                           forms))]
    (list-append p12Diags defunDiags)))

(df parseErrDiag [(pe a/ParseError) (path String)] -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message (.-msg pe) :line (.-line pe) :col (.-col pe) :path path)))

(df checkSource [(src String) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Parses and semantically checks an AgentScript source string."
  (mt (a/parse src)
    ((ok forms) (checkModule forms deps path))
    ((err pe) (parseErrDiag pe path))))

(df ! checkFile! [(path String) (roots (List String))] -> (Result (List ty/Diagnostic) IoError)
  :d "Effectful entry point: loads source and dependencies from filesystem and checks."
  (mt (file-read path)
    ((err ioErr) (err ioErr))
    ((ok src)
     (mt (a/parse src)
       ((err pe) (ok (parseErrDiag pe path)))
       ((ok forms)
        (let [(summary (r/collectSummary forms path))
              (importPaths (r/mapValuesList (.-imports summary)))
              (allRoots (list-cons (option-or (parentDir path) ".") roots))]
          (mt (r/loadModuleDeps! allRoots importPaths)
            ((err ioErr2) (err ioErr2))
            ((ok deps) (ok (checkModule forms deps path))))))))))

(df parentDir [(p String)] -> (Option String)
  (if (string-contains? p "/")
    (let [(parts (string-split p "/"))
          (segs (list-reverse (r/safeTail (list-reverse parts))))]
      (if (list-empty? segs)
        (some ".")
        (some (string-join segs "/"))))
    (some ".")))
