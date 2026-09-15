(module asl-checker/resolve
  :d "Pass 1 & Pass 2 Symbol Resolution, Module Scoping, and Semantic Rules."
  :x [FunSummary SchemaSummary EnumSummary CaseSummary FieldSummary ModuleSummary
      cleanNumSign
      collectSummary
      firstCharStr
      firstExprEmpty
      firstExprUnit
      firstExprVect
      firstHeadIdent
      firstVectItems
      isLiteralAtom?
      listAppendOne
      loadModuleDeps!
      mapValuesList
      modEnum
      modFun
      modImport
      modSchema
      resolveModule
      safeTail
      secondExprEmpty
      sexprToList
      sliceFrom]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

(dfs FunSummary
  (:f name String "Function name")
  (:f params (List (Pair String String)) "Parameter name and type pairs")
  (:f ret String "Return type annotation")
  (:f typevars (List String) "Type variables bound in signature")
  (:f hasDoc Bool "True if docstring is present")
  (:f effect Bool "True if marked with !"))

(dfs FieldSummary
  (:f name String "Field name")
  (:f type String "Field type annotation")
  (:f hasDefault Bool "True if field has default"))

(dfs SchemaSummary
  (:f name String "Schema name")
  (:f typevars (List String) "Bound type variables")
  (:f fields (List FieldSummary) "Schema fields"))

(dfs CaseSummary
  (:f name String "Enum case name")
  (:f params (List (Pair String String)) "Case parameters"))

(dfs EnumSummary
  (:f name String "Enum name")
  (:f typevars (List String) "Bound type variables")
  (:f cases (List CaseSummary) "Enum cases"))

(dfs ModuleSummary
  (:f name String "Module name")
  (:f path String "Source file path")
  (:f hasHeader Bool "True if header form exists")
  (:f hasDoc Bool "True if module docstring exists")
  (:f exports (List String) "Exported function names")
  (:f exportedTypes (List String) "Exported PascalCase type names")
  (:f imports (Map String String) "Import alias to module path mapping")
  (:f funs (Map String FunSummary) "Function summaries")
  (:f schemas (Map String SchemaSummary) "Schema summaries")
  (:f enums (Map String EnumSummary) "Enum summaries")
  (:f caseOwner (Map String String) "Case name to owning enum name mapping")
  (:f exportedCases (Map String String) "Exported case name to enum name mapping")
  (:f exportedFields (Map String Bool) "Exported record field names"))

(df firstCharStr [(s String)] -> String
  :d "Returns first character of string as string, or empty string."
  (mt (string-slice s 0 1) ((some c) c) ((none) "")))

(df sliceFrom [(s String) (start Int64)] -> String
  :d "Slices string from start to end, defaulting to full string if out of range."
  (mt (string-slice s start (string-length s)) ((some sub) sub) ((none) s)))

(df isPascalName? [(s String)] -> Bool
  (if (string-empty? s)
    false
    (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstCharStr s))))

(df isQualifiedName? [(s String)] -> Bool
  (and (not (= s "/"))
       (and (not (string-starts-with? s "/"))
            (string-contains? s "/"))))

(df makeDiag [(code String) (msg String) (path String)] -> ty/Diagnostic
  (ty/Diagnostic :code code :message msg :msg msg :line 1 :col 1 :path path))

(df collectFields [(fields (List a/AstField))] -> (List FieldSummary)
  (map (fn [(f a/AstField)] -> FieldSummary
         (FieldSummary :name (.-name f)
                       :type (.-type f)
                       :hasDefault (mt (.-default f) ((some _) true) ((none) false))))
       fields))

(df collectCaseParams [(params (List a/Param))] -> (List (Pair String String))
  (map (fn [(p a/Param)] -> (Pair String String)
         (pair (.-name p) (.-type p)))
       params))

(df collectCases [(cases (List a/EnumCase))] -> (List CaseSummary)
  (map (fn [(c a/EnumCase)] -> CaseSummary
         (CaseSummary :name (.-name c)
                      :params (collectCaseParams (.-fields c))))
       cases))

(df collectFunParams [(params (List a/Param))] -> (List (Pair String String))
  (map (fn [(p a/Param)] -> (Pair String String)
         (pair (.-name p) (.-type p)))
       params))

(df collectSummary [(forms (List a/TopForm)) (path String)] -> ModuleSummary
  :d "Extracts structural module summary from top-level forms." 
  (let [(modHeader (fold (fn [(acc (Option a/ModuleNode)) (form a/TopForm)] -> (Option a/ModuleNode)
                            (mt form
                              ((a/topModule m) (some m))
                              (_ acc)))
                          (none)
                          forms))
        (hasHdr (mt modHeader ((some _) true) ((none) false)))
        (hdrDoc (mt modHeader
                   ((some m) (not (string-empty? (.-docstring m))))
                   ((none) false)))
        (modName (mt modHeader
                    ((some m) (let [(p (.-path m))]
                                (if (string-empty? p) path p)))
                    ((none) path)))
        (rawExports (mt modHeader
                       ((some m) (.-exported m))
                       ((none) (list))))
        (exports (filter (fn [(e String)] -> Bool (not (isPascalName? e))) rawExports))
        (exportedTypes (filter (fn [(e String)] -> Bool (isPascalName? e)) rawExports))
        (importsList (mt modHeader
                        ((some m) (.-imports m))
                        ((none) (list))))
        (importsMap (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String)
                             (map-set acc (.-second p) (.-first p)))
                           (map-empty)
                           importsList))
        (funsMap (fold (fn [(acc (Map String FunSummary)) (form a/TopForm)] -> (Map String FunSummary)
                          (mt form
                            ((a/topDefun d)
                             (map-set acc (.-name d)
                                      (FunSummary :name (.-name d)
                                                  :params (collectFunParams (.-params d))
                                                  :ret (.-retType d)
                                                  :typevars (.-typeVars d)
                                                  :hasDoc (not (string-empty? (.-docstring d)))
                                                  :effect (.-effect d))))
                            (_ acc)))
                        (map-empty)
                        forms))
        (schemasMap (fold (fn [(acc (Map String SchemaSummary)) (form a/TopForm)] -> (Map String SchemaSummary)
                             (mt form
                               ((a/topSchema s)
                                (map-set acc (.-name s)
                                         (SchemaSummary :name (.-name s)
                                                        :typevars (.-typeVars s)
                                                        :fields (collectFields (.-fields s)))))
                               (_ acc)))
                           (map-empty)
                           forms))
        (enumsMap (fold (fn [(acc (Map String EnumSummary)) (form a/TopForm)] -> (Map String EnumSummary)
                           (mt form
                             ((a/topEnum e)
                              (map-set acc (.-name e)
                                       (EnumSummary :name (.-name e)
                                                    :typevars (.-typeVars e)
                                                    :cases (collectCases (.-cases e)))))
                             (_ acc)))
                         (map-empty)
                         forms))
        (caseOwnerMap (fold (fn [(acc (Map String String)) (form a/TopForm)] -> (Map String String)
                                (mt form
                                  ((a/topEnum e)
                                   (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                                           (map-set cacc (.-name c) (.-name e)))
                                         acc
                                         (.-cases e)))
                                  (_ acc)))
                              (map-empty)
                              forms))
        (expCases (fold (fn [(acc (Map String String)) (tname String)] -> (Map String String)
                           (mt (map-get enumsMap tname)
                             ((some esum)
                              (fold (fn [(cacc (Map String String)) (c CaseSummary)] -> (Map String String)
                                      (map-set cacc (.-name c) tname))
                                    acc
                                    (.-cases esum)))
                             ((none) acc)))
                         (map-empty)
                         exportedTypes))
        (expFields (fold (fn [(acc (Map String Bool)) (tname String)] -> (Map String Bool)
                            (mt (map-get schemasMap tname)
                              ((some ssum) (addFieldsToSet acc (.-fields ssum)))
                              ((none) acc)))
                          (map-empty)
                          exportedTypes))]
    (ModuleSummary :name modName
                   :path path
                   :hasHeader hasHdr
                   :hasDoc hdrDoc
                   :exports exports
                   :exportedTypes exportedTypes
                   :imports importsMap
                   :funs funsMap
                   :schemas schemasMap
                   :enums enumsMap
                   :caseOwner caseOwnerMap
                   :exportedCases expCases
                   :exportedFields expFields)))

(df addFieldsToSet [(facc (Map String Bool)) (fields (List FieldSummary))] -> (Map String Bool)
  :d "Adds field names from a list of FieldSummary to a set map."
  (fold (fn [(acc (Map String Bool)) (f FieldSummary)] -> (Map String Bool)
          (map-set acc (.-name f) true))
        facc
        fields))

(df safeTail [(l (List T))] -> (List T)
  :d "Returns list tail or empty list if none."
  (if (list-empty? l)
    (list)
    (mt (list-tail l)
      ((some r) r)
      ((none) (list)))))

(df firstExprEmpty [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or empty atom."
  (mt (list-head l)
    ((some h) h)
    ((none) (rd/makeAtom ""))))

(df firstExprUnit [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or unit atom."
  (mt (list-head l)
    ((some h) h)
    ((none) (rd/makeAtom "()"))))

(df firstExprVect [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or empty vector."
  (mt (list-head l)
    ((some b) b)
    ((none) (rd/makeVect (list)))))

(df sexprToList [(e rd/SExpr)] -> (List rd/SExpr)
  :d "Extracts elements from vector or list S-expression."
  (rd/sexprToList e))

(df firstVectItems [(l (List rd/SExpr))] -> (List rd/SExpr)
  :d "Extracts elements from first element vector or list."
  (sexprToList (firstExprVect l)))

(df secondExprEmpty [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns second element of list or empty atom."
  (mt (list-get l 1)
    ((some v) v)
    ((none) (rd/makeAtom ""))))

(df listAppendOne [(xs (List T)) (x T)] -> (List T)
  :d "Appends a single element to a list."
  (list-append xs (list x)))

(df modSchema [(m ModuleSummary) (name String)] -> (Option SchemaSummary)
  :d "Looks up schema summary in module."
  (map-get (.-schemas m) name))

(df modEnum [(m ModuleSummary) (name String)] -> (Option EnumSummary)
  :d "Looks up enum summary in module."
  (map-get (.-enums m) name))

(df modImport [(m ModuleSummary) (alias String)] -> (Option String)
  :d "Looks up imported module path by alias in module."
  (map-get (.-imports m) alias))

(df modFun [(m ModuleSummary) (name String)] -> (Option FunSummary)
  :d "Looks up function summary in module."
  (map-get (.-funs m) name))

(df ! findModuleFile! [(roots (List String)) (modPath String)] -> (Option String)
  (mt (list-head roots)
    ((none) (none))
    ((some r)
     (let [(candAsl (str r "/" modPath ".asl"))
           (candSrc (str r "/" (string-replace modPath "/" "/src/") ".asl"))
           (restRoots (safeTail roots))]
       (if (file-exists? candAsl)
         (some candAsl)
         (if (file-exists? candSrc)
           (some candSrc)
           (findModuleFile! restRoots modPath)))))))

(df ! loadModuleDeps! [(roots (List String)) (imports (List String))] -> (Result (Map String ModuleSummary) IoError)
  :d "Recursively loads module dependencies from search roots." 
  (let [(deps (foldDeps! roots imports (map-empty)))]
    (ok deps)))

(df ! foldDeps! [(roots (List String)) (toLoad (List String)) (loaded (Map String ModuleSummary))] -> (Map String ModuleSummary)
  (mt (list-head toLoad)
    ((none) loaded)
    ((some modPath)
     (let [(rest (safeTail toLoad))]
       (if (map-has? loaded modPath)
         (foldDeps! roots rest loaded)
         (mt (findModuleFile! roots modPath)
           ((none) (foldDeps! roots rest loaded))
           ((some fpath)
            (mt (file-read fpath)
              ((err pe) (print (str "PARSE ERROR in " fpath ": " (.-msg pe))) (foldDeps! roots rest loaded))
              ((ok src)
               (mt (a/parse src)
                 ((err pe) (print (str "PARSE ERROR in " fpath ": " (.-msg pe))) (foldDeps! roots rest loaded))
                 ((ok forms)
                  (let [(summary (collectSummary forms fpath))
                        (nextLoaded (map-set loaded modPath summary))
                        (subImports (mapValuesList (.-imports summary)))
                        (nextToLoad (list-append subImports rest))]
                    (foldDeps! roots nextToLoad nextLoaded)))))))))))))

(df mapKeysSet [(m (Map String ModuleSummary))] -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (k String)] -> (Map String Bool)
          (map-set acc k true))
        (map-empty)
        (map-keys m)))

(df mapValuesList [(m (Map String String))] -> (List String)
  :d "Converts a string-string map's values to a list of strings."
  (map-values m))

(df isNullaryBuiltinType? [(resolved String)] -> Bool
  :d "True for nullary built-in primitive types."
  (or (ty/isNumericType? resolved)
      (or (or (= resolved "String") (or (= resolved "Bool") (= resolved "Unit")))
          (or (= resolved "IoError") (= resolved "N")))))

(df isKnownBuiltinType? [(name String)] -> Bool
  :d "True for recognized built-in types."
  (let [(resolved (ty/resolveTypeAlias name))]
    (or (isNullaryBuiltinType? resolved)
        (or (or (= resolved "List") (or (= resolved "Option") (= resolved "Result")))
            (or (= resolved "Map") (= resolved "Pair"))))))

(df builtinTypeArity [(name String)] -> (Option Int64)
  :d "Expected type parameter arity for built-in types."
  (let [(resolved (ty/resolveTypeAlias name))]
    (cond
      ((= resolved "List") (some 1))
      ((= resolved "Option") (some 1))
      ((= resolved "Result") (some 2))
      ((= resolved "Map") (some 2))
      ((= resolved "Pair") (some 2))
      ((isNullaryBuiltinType? resolved) (some 0))
      (:else (none)))))

(df checkTypeTrees [(ts (List ty/Type)) (bound (Map String Bool)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  :d "Folds check-type-tree over a list of types."
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic)
          (checkTypeTree item bound mod deps where path a))
        acc
        ts))

(df checkTypeTree [(t ty/Type) (bound (Map String Bool)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt t
    ((ty/tyVar _ _) acc)
    ((ty/tyFun params ret)
     (let [(acc1 (checkTypeTrees params bound mod deps where path acc))]
       (checkTypeTree ret bound mod deps where path acc1)))
    ((ty/tyCon name args optMod optShown)
     (let [(accArgs (checkTypeTrees args bound mod deps where path acc))
           (givenArity (list-length args))
           (expectedArity (mt optMod
                             ((some alias)
                              (mt (modImport mod alias)
                                ((some mpath)
                                 (mt (map-get deps mpath)
                                   ((some target)
                                    (mt (modSchema target name)
                                      ((some s) (some (list-length (.-typevars s))))
                                      ((none)
                                       (mt (modEnum target name)
                                         ((some e) (some (list-length (.-typevars e))))
                                         ((none) (none))))))
                                   ((none) (none))))
                                ((none) (none))))
                             ((none)
                              (if (map-has? bound name)
                                (some 0)
                                (mt (modSchema mod name)
                                  ((some s) (some (list-length (.-typevars s))))
                                  ((none)
                                   (mt (modEnum mod name)
                                      ((some e) (some (list-length (.-typevars e))))
                                      ((none) (builtinTypeArity name)))))))))
           (accArity (mt expectedArity
                          ((some exp)
                           (if (not (= exp givenArity))
                             (list-cons (makeDiag "type-arity" (str name " in " where " takes " (string-from-int64 exp) " type argument(s), given " (string-from-int64 givenArity)) path) accArgs)
                             accArgs))
                          ((none) accArgs)))]
       (mt optMod
         ((some alias)
          (mt (modImport mod alias)
            ((none)
             (list-cons (makeDiag "rule-9" (str alias "/" name ": alias " alias " is not imported") path) accArity))
            ((some mpath)
             (mt (map-get deps mpath)
               ((none) accArity)
               ((some target)
                (if (not (list-contains? (.-exportedTypes target) name))
                  (list-cons (makeDiag "rule-9" (str name " is not an exported type of " (.-name target)) path) accArity)
                  accArity))))))
         ((none)
          (if (or (isKnownBuiltinType? name)
                  (or (map-has? bound name)
                      (or (map-has? (.-schemas mod) name)
                          (map-has? (.-enums mod) name))))
            accArity
            (list-cons (makeDiag "rule-10" (str name " in " where " is neither a known type nor bound in { }") path) accArity))))))))

(df checkPublicTypeTrees [(ts (List ty/Type)) (bound (Map String Bool)) (mod ModuleSummary) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  :d "Folds check-public-type-tree over a list of types."
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic)
          (checkPublicTypeTree item bound mod where path a))
        acc
        ts))

(df checkPublicTypeTree [(t ty/Type) (bound (Map String Bool)) (mod ModuleSummary) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt t
    ((ty/tyVar _ _) acc)
    ((ty/tyFun params ret)
     (let [(acc1 (checkPublicTypeTrees params bound mod where path acc))]
       (checkPublicTypeTree ret bound mod where path acc1)))
    ((ty/tyCon name args optMod optShown)
     (let [(accArgs (checkPublicTypeTrees args bound mod where path acc))]
       (mt optMod
         ((some _) accArgs)
         ((none)
          (if (or (map-has? bound name) (list-contains? (.-exportedTypes mod) name))
            accArgs
            (if (or (map-has? (.-schemas mod) name) (map-has? (.-enums mod) name))
              (list-cons (makeDiag "rule-13" (str name " in " where " is declared here and not exported") path) accArgs)
              accArgs))))))))

(df addStringsToSet [(acc (Map String Bool)) (xs (List String))] -> (Map String Bool)
  :d "Adds a list of strings to a set map."
  (fold (fn [(m (Map String Bool)) (x String)] -> (Map String Bool)
          (map-set m x true))
        acc
        xs))

(df listToSet [(xs (List String))] -> (Map String Bool)
  :d "Converts list of strings to a set map."
  (addStringsToSet (map-empty) xs))

(df checkModuleRules [(mod ModuleSummary) (path String)] -> (List ty/Diagnostic)
  (let [(d1 (if (and (.-hasHeader mod) (not (.-hasDoc mod)))
              (list (makeDiag "rule-8" (str "module " (.-name mod) " has no :doc") path))
              (list)))
        (d2 (fold (fn [(acc (List ty/Diagnostic)) (exp String)] -> (List ty/Diagnostic)
                    (mt (modFun mod exp)
                      ((some f)
                       (if (not (.-hasDoc f))
                         (list-cons (makeDiag "rule-8" (str "exported function " exp " has no :doc") path) acc)
                         acc))
                      ((none)
                       (list-cons (makeDiag "rule-2" (str exp " is exported but not defined in this module") path) acc))))
                  d1
                  (.-exports mod)))
        (d3 (fold (fn [(acc (List ty/Diagnostic)) (tname String)] -> (List ty/Diagnostic)
                    (if (and (not (map-has? (.-schemas mod) tname))
                             (not (map-has? (.-enums mod) tname)))
                      (list-cons (makeDiag "rule-2" (str tname " is exported but not defined in this module") path) acc)
                      acc))
                  d2
                  (.-exportedTypes mod)))]
    d3))

(df checkCycleDfs [(cur String) (stack (List String)) (visited (Map String Bool)) (deps (Map String ModuleSummary)) (modImports (Map String String)) (path String)] -> (Option (List String))
  (let [(targets (if (= cur (.-second (pair "" "")))
                   (mapValuesList modImports)
                   (mt (map-get deps cur)
                     ((some s) (mapValuesList (.-imports s)))
                     ((none) (list)))))]
    (checkCycleEdges targets stack visited deps modImports path)))

(df checkCycleEdges [(edges (List String)) (stack (List String)) (visited (Map String Bool)) (deps (Map String ModuleSummary)) (modImports (Map String String)) (path String)] -> (Option (List String))
  (mt (list-head edges)
    ((none) (none))
    ((some edgeTarget)
     (let [(rest (safeTail edges))]
       (if (list-contains? stack edgeTarget)
         (some (listAppendOne stack edgeTarget))
         (if (map-has? visited edgeTarget)
           (checkCycleEdges rest stack visited deps modImports path)
           (let [(subRes (checkCycleDfs edgeTarget (listAppendOne stack edgeTarget) (map-set visited edgeTarget true) deps modImports path))]
             (mt subRes
               ((some cyc) (some cyc))
               ((none) (checkCycleEdges rest stack visited deps modImports path))))))))))

(df checkImportsAndCycles [(mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(unres (fold (fn [(acc (List ty/Diagnostic)) (alias String)] -> (List ty/Diagnostic)
                       (let [(mpath (mt (modImport mod alias) ((some p) p) ((none) "")))]
                         (if (not (map-has? deps mpath))
                           (list-cons (makeDiag "unresolved-import" (str "no module " mpath " on the search path") path) acc)
                           acc)))
                     (list)
                     (map-keys (.-imports mod))))
        (cycleOpt (checkCycleDfs (.-name mod) (list (.-name mod)) (map-set (map-empty) (.-name mod) true) deps (.-imports mod) path))]
    (mt cycleOpt
      ((some cyc)
       (list-cons (makeDiag "rule-11" (str "import cycle: " (string-join cyc " -> ")) path) unres))
      ((none) unres))))

(df checkExportClosure [(mod ModuleSummary) (path String)] -> (List ty/Diagnostic)
  (let [(fDiags (fold (fn [(acc (List ty/Diagnostic)) (fname String)] -> (List ty/Diagnostic)
                         (mt (modFun mod fname)
                           ((some f)
                            (let [(bset (listToSet (.-typevars f)))
                                  (pDiags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                                   (let [(pty (ty/parseTypeStr (.-second p) (list)))]
                                                     (checkPublicTypeTree pty bset mod (str "exported function " fname) path pacc)))
                                                 acc
                                                 (.-params f)))
                                  (rty (ty/parseTypeStr (.-ret f) (list)))]
                              (checkPublicTypeTree rty bset mod (str "exported function " fname) path pDiags)))
                           ((none) acc)))
                       (list)
                       (.-exports mod)))
        (sDiags (fold (fn [(acc (List ty/Diagnostic)) (sname String)] -> (List ty/Diagnostic)
                         (mt (modSchema mod sname)
                           ((some s)
                            (let [(bset (listToSet (.-typevars s)))]
                              (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic)
                                      (let [(fty (ty/parseTypeStr (.-type f) (list)))]
                                        (checkPublicTypeTree fty bset mod (str "exported field " sname "." (.-name f)) path facc)))
                                    acc
                                    (.-fields s))))
                           ((none) acc)))
                       fDiags
                       (.-exportedTypes mod)))
        (eDiags (fold (fn [(acc (List ty/Diagnostic)) (ename String)] -> (List ty/Diagnostic)
                         (mt (modEnum mod ename)
                           ((some e)
                            (let [(bset (listToSet (.-typevars e)))]
                              (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic)
                                      (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                              (let [(pty (ty/parseTypeStr (.-second p) (list)))]
                                                (checkPublicTypeTree pty bset mod (str "case " (.-name c) " of exported " ename) path pacc)))
                                            cacc
                                            (.-params c)))
                                    acc
                                    (.-cases e))))
                           ((none) acc)))
                       sDiags
                       (.-exportedTypes mod)))]
    eDiags))

(df checkTypeAnnotations [(mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(dFuns (fold (fn [(acc (List ty/Diagnostic)) (f FunSummary)] -> (List ty/Diagnostic)
                        (let [(bset (listToSet (.-typevars f)))
                              (pDiags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                               (let [(pty (ty/parseTypeStr (.-second p) (list)))]
                                                 (checkTypeTree pty bset mod deps (str "function " (.-name f)) path pacc)))
                                             acc
                                             (.-params f)))
                              (rty (ty/parseTypeStr (.-ret f) (list)))]
                          (checkTypeTree rty bset mod deps (str "function " (.-name f)) path pDiags)))
                      (list)
                      (map-values (.-funs mod))))
        (dSchemas (fold (fn [(acc (List ty/Diagnostic)) (s SchemaSummary)] -> (List ty/Diagnostic)
                           (let [(bset (listToSet (.-typevars s)))]
                             (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic)
                                     (let [(fty (ty/parseTypeStr (.-type f) (list)))]
                                       (checkTypeTree fty bset mod deps (str "field " (.-name s) "." (.-name f)) path facc)))
                                   acc
                                   (.-fields s))))
                         dFuns
                         (map-values (.-schemas mod))))
        (dEnums (fold (fn [(acc (List ty/Diagnostic)) (e EnumSummary)] -> (List ty/Diagnostic)
                         (let [(bset (listToSet (.-typevars e)))]
                           (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic)
                                   (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                           (let [(pty (ty/parseTypeStr (.-second p) (list)))]
                                             (checkTypeTree pty bset mod deps (str "case " (.-name c)) path pacc)))
                                         cacc
                                         (.-params c)))
                                 acc
                                 (.-cases e))))
                       dSchemas
                       (map-values (.-enums mod))))]
    dEnums))

(df isEffectfulBuiltin? [(name String)] -> Bool
  (or (or (= name "println") (or (= name "print") (= name "eprintln")))
      (or (or (= name "file-read") (or (= name "file-write") (= name "file-append")))
          (or (or (= name "file-exists?") (or (= name "read-line") (= name "read-all")))
              (or (or (= name "dirList") (or (= name "execCmd") (= name "fileStat")))
                  (= name "pathCanonicalize"))))))

(df isSpecialForm? [(name String)] -> Bool
  (or (or (= name "let") (or (= name "if") (= name "cond")))
      (or (or (= name "try") (or (= name "fn") (= name "match")))
          (or (or (= name "module") (or (= name "defun") (= name "defschema")))
              (or (= name "defenum") (or (= name "some") (= name "none")))))))

(df isPreludeTag? [(name String)] -> Bool
  (or (or (= name "some") (or (= name "none") (= name "ok")))
      (or (or (= name "err") (or (= name "list") (= name "cons")))
          (or (= name "pair")
              (or (or (= name "not-found") (or (= name "permission-denied") (= name "already-exists")))
                  (or (or (= name "invalid-path") (= name "interrupted")) (= name "other")))))))

(df cleanNumSign [(v String)] -> String
  :d "Strips leading sign if followed by characters."
  (if (and (or (string-starts-with? v "+") (string-starts-with? v "-")) (> (string-length v) 1))
    (sliceFrom v 1)
    v))

(df isLiteralAtom? [(v String)] -> Bool
  :d "Returns true if an atom is a literal string, bool, unit, or number."
  (if (or (string-starts-with? v "\"") (or (= v "true") (or (= v "false") (or (= v "()") (= v "nil")))))
    true
    (let [(s (cleanNumSign v))]
      (if (string-empty? s)
        false
        (string-contains? "0123456789" (firstCharStr s))))))

(df splitQual [(s String)] -> (Pair String String)
  (let [(parts (string-split s "/"))]
    (pair (mt (list-get parts 0) ((some a) a) ((none) ""))
          (mt (list-get parts 1) ((some m) m) ((none) "")))))

(df enumFamily [(m ModuleSummary) (ename String)] -> (Option (Pair String (List String)))
  (mt (modEnum m ename)
    ((some esum)
     (some (pair (str (.-name m) "/" ename)
                 (map (fn [(c CaseSummary)] -> String (.-name c)) (.-cases esum)))))
    ((none) (none))))

(df unionForTag [(head String) (mod ModuleSummary) (deps (Map String ModuleSummary))] -> (Option (Pair String (List String)))
  (mt (ty/preludeUnionCases head)
    ((some uname)
     (cond
       ((= uname "Option") (some (pair "Option" (list "some" "none"))))
       ((= uname "Result") (some (pair "Result" (list "ok" "err"))))
       ((= uname "List") (some (pair "List" (list "list" "cons"))))
       ((= uname "IoError") (some (pair "IoError" (list "not-found" "permission-denied" "already-exists" "invalid-path" "interrupted" "other"))))
       (:else (none))))
    ((none)
     (if (isQualifiedName? head)
       (let [(qp (splitQual head))
             (alias (.-first qp))
             (member (.-second qp))]
         (mt (modImport mod alias)
           ((some mpath)
            (mt (map-get deps mpath)
              ((some target)
               (mt (map-get (.-exportedCases target) member)
                 ((some ename) (enumFamily target ename))
                 ((none) (none))))
              ((none) (none))))
           ((none) (none))))
       (mt (map-get (.-caseOwner mod) head)
         ((some ename) (enumFamily mod ename))
         ((none) (none)))))))

(df extractPattern [(pat rd/SExpr) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String) (accDiags (List ty/Diagnostic))] -> (Pair (Pair (List String) (Option String)) (List ty/Diagnostic))
  (mt pat
    ((rd/sexprAtom v)
     (if (or (= v "_") (isLiteralAtom? v))
       (pair (pair (list) (none)) accDiags)
       (pair (pair (list v) (none)) accDiags)))
    ((rd/sexprVect _)
     (pair (pair (list) (none)) accDiags))
    ((rd/sexprList items)
     (mt (list-head items)
       ((none) (pair (pair (list) (none)) accDiags))
       ((some h)
        (let [(headTok (rd/sexprHead h))
              (subs (safeTail items))
              (uInfo (unionForTag headTok mod deps))]
          (let [(dCheck (mt uInfo
                           ((some _) accDiags)
                           ((none)
                            (list-cons (makeDiag "rule-2" (str headTok " is not a case of any union") path) accDiags))))
                (arityRes (fold (fn [(acc (Pair (List String) (List ty/Diagnostic))) (sub rd/SExpr)] -> (Pair (List String) (List ty/Diagnostic))
                                   (let [(subRes (extractPattern sub mod deps path (.-second acc)))]
                                     (pair (list-append (.-first acc) (.-first (.-first subRes)))
                                           (.-second subRes))))
                                 (pair (list) dCheck)
                                 subs))]
            (pair (pair (.-first arityRes) (some headTok)) (.-second arityRes)))))))))

(df checkMatchExhaustiveness [(heads (List String)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (if (list-empty? heads)
    acc
    (let [(firstHead (mt (list-head heads) ((some h) h) ((none) "")))
          (uFirst (unionForTag firstHead mod deps))]
      (mt uFirst
        ((none) acc)
        ((some u1)
         (let [(u1Name (.-first u1))
               (u1Cases (.-second u1))
               (mixDiags (fold (fn [(a (List ty/Diagnostic)) (h String)] -> (List ty/Diagnostic)
                                  (mt (unionForTag h mod deps)
                                    ((none) a)
                                    ((some uh)
                                     (if (not (= (.-first uh) u1Name))
                                       (list-cons (makeDiag "rule-4" (str "arms mix unions: " u1Name ", " (.-first uh)) path) a)
                                       a))))
                                (list)
                                heads))]
           (if (not (list-empty? mixDiags))
             (list-append mixDiags acc)
             (let [(bareHeads (map (fn [(h String)] -> String
                                      (if (string-contains? h "/")
                                        (let [(p (string-split h "/"))]
                                          (mt (list-get p 1) ((some m) m) ((none) h)))
                                        h))
                                    heads))
                   (missing (filter (fn [(c String)] -> Bool
                                      (not (list-contains? bareHeads c)))
                                    u1Cases))]
               (if (not (list-empty? missing))
                 (list-cons (makeDiag "rule-4" (str "match is not exhaustive: " (string-join missing ", ") " unhandled") path) acc)
                 acc)))))))))

(df isCtorHead? [(h String)] -> Bool
  (if (isPascalName? h)
    true
    (if (isQualifiedName? h)
      (isPascalName? (.-second (splitQual h)))
      false)))

(df extractCtorValExprs [(args (List rd/SExpr))] -> (List rd/SExpr)
  (mt (list-head args)
    ((none) (list))
    ((some _)
     (let [(valNode (secondExprEmpty args))
           (rest (dropTwo args))]
       (list-cons valNode (extractCtorValExprs rest))))))

(df checkQualifiedMember [(v String) (alias String) (member String) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (Option ty/Diagnostic)
  (mt (modImport mod alias)
    ((none)
     (some (makeDiag "rule-9" (str v ": alias " alias " is not imported") path)))
    ((some mpath)
     (mt (map-get deps mpath)
       ((none) (none))
       ((some target)
        (if (and (not (list-contains? (.-exports target) member))
                 (not (map-has? (.-exportedCases target) member)))
          (some (makeDiag "rule-9" (str member " is not exported by " (.-name target)) path))
          (none)))))))

(df isReservedIdent? [(s String)] -> Bool
  (or (string-starts-with? s "agentscript-") (string-contains? s "/agentscript-")))

(df diagReservedPrefix [(name String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (list-cons (makeDiag "rule-7" (str name " uses the reserved agentscript- prefix") path) acc))

(df checkHeadExpr [(headExpr rd/SExpr) (scope (Map String Bool)) (effectOk Bool) (mod ModuleSummary) (deps (Map String ModuleSummary)) (fieldNames (Map String Bool)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt headExpr
    ((rd/sexprAtom v)
     (if (isLiteralAtom? v)
       acc
       (if (string-starts-with? v ":")
         acc
         (if (string-starts-with? v ".-")
           acc
           (if (isReservedIdent? v)
             (diagReservedPrefix v path acc)
             (if (isQualifiedName? v)
                  (let [(qp (splitQual v))
                        (alias (.-first qp))
                        (member (.-second qp))]
                    (mt (checkQualifiedMember v alias member mod deps path)
                      ((some d) (list-cons d acc))
                      ((none) acc)))
                  (if (or (map-has? scope v)
                          (or (map-has? (.-funs mod) v)
                              (or (map-has? (.-caseOwner mod) v)
                                  (or (isPreludeTag? v)
                                      (or (isSpecialForm? v)
                                          (mt (ty/builtinSig v) ((some _) true) ((none) false)))))))
                    acc
                    (list-cons (makeDiag "rule-2" (str v " is not defined") path) acc))))))))
    (_ acc)))

(dfs ResolveWorkItem
  (:f expr rd/SExpr "Expression to evaluate")
  (:f scope (Map String Bool) "Current lexical scope")
  (:f effectOk Bool "Effect capability"))

(dfs ResolveState
  (:f work (List ResolveWorkItem) "Pending expression stack")
  (:f diags (List ty/Diagnostic) "Accumulated diagnostics"))

(df firstHeadIdent [(l (List rd/SExpr))] -> String
  :d "Returns identifier of first element's head or empty string."
  (rd/sexprHead (firstExprEmpty l)))

(df addLetBinding [(bparts (List rd/SExpr)) (pairAcc (Pair (Map String Bool) (List ResolveWorkItem))) (effectOk Bool)] -> (Pair (Map String Bool) (List ResolveWorkItem))
  (let [(bname (firstHeadIdent bparts))
        (bval (secondExprEmpty bparts))
        (curSc (.-first pairAcc))
        (curItems (.-second pairAcc))]
    (pair (map-set curSc bname true)
          (list-cons (ResolveWorkItem :expr bval :scope curSc :effectOk effectOk) curItems))))

(df enumCaseArity [(m ModuleSummary) (ename String) (member String)] -> (Option Int64)
  (mt (modEnum m ename)
    ((some esum)
     (let [(matching (filter (fn [(c CaseSummary)] -> Bool (= (.-name c) member)) (.-cases esum)))]
       (mt (list-head matching)
         ((some mc) (some (list-length (.-params mc))))
         ((none) (none)))))
    ((none) (none))))

(df mapRitems [(exprs (List rd/SExpr)) (scope (Map String Bool)) (effectOk Bool)] -> (List ResolveWorkItem)
  (map (fn [(e rd/SExpr)] -> ResolveWorkItem (ResolveWorkItem :expr e :scope scope :effectOk effectOk)) exprs))

(df dropTwo [(l (List rd/SExpr))] -> (List rd/SExpr)
  (safeTail (safeTail l)))

(df rResolveTick [(st ResolveState) (tickIdx Int64) (mod ModuleSummary) (deps (Map String ModuleSummary)) (fieldNames (Map String Bool)) (path String)] -> ResolveState
  (mt (list-head (.-work st))
    ((none) st)
    ((some item)
     (let [(rest (safeTail (.-work st)))
           (expr (.-expr item))
           (scope (.-scope item))
           (effectOk (.-effectOk item))
           (acc (.-diags st))]
       (mt expr
         ((rd/sexprAtom v)
          (if (isLiteralAtom? v)
            (ResolveState :work rest :diags acc)
            (if (string-starts-with? v ":")
              (ResolveState :work rest :diags acc)
              (if (isReservedIdent? v)
                (ResolveState :work rest :diags (diagReservedPrefix v path acc))
                (if (isQualifiedName? v)
                  (let [(qp (splitQual v))
                        (alias (.-first qp))
                        (member (.-second qp))]
                    (mt (checkQualifiedMember v alias member mod deps path)
                      ((some d) (ResolveState :work rest :diags (list-cons d acc)))
                      ((none) (ResolveState :work rest :diags acc))))
                  (if (map-has? scope v)
                    (ResolveState :work rest :diags acc)
                    (if (map-has? (.-funs mod) v)
                      (ResolveState :work rest :diags acc)
                      (if (map-has? (.-caseOwner mod) v)
                        (ResolveState :work rest :diags acc)
                        (if (isPreludeTag? v)
                          (ResolveState :work rest :diags acc)
                          (if (isSpecialForm? v)
                            (ResolveState :work rest :diags acc)
                            (mt (ty/builtinSig v)
                              ((some _)
                               (ResolveState :work rest :diags (list-cons (makeDiag "builtin-reference" (str v " is a builtin, not a value; wrap it in an fn to pass it") path) acc)))
                                ((none)
                                 (ResolveState :work rest :diags (list-cons (makeDiag "rule-2" (str v " is not defined") path) acc))))))))))))))

         ((rd/sexprVect items)
          (ResolveState :work (list-append (mapRitems items scope effectOk) rest) :diags acc))

         ((rd/sexprList items)
          (mt (list-head items)
            ((none) (ResolveState :work rest :diags acc))
            ((some h)
             (let [(headTok (rd/sexprHead h))
                   (tailArgs (safeTail items))]
               (cond
                 ((= headTok "==")
                  (ResolveState :work rest :diags (list-cons (makeDiag "builtin-reference" "= is a builtin, not a value; wrap it in an fn to pass it" path) acc)))

                 ((= headTok "let")
                  (let [(bindItems (firstVectItems tailArgs))
                        (bodyExprs (safeTail tailArgs))
                        (bindRes (fold (fn [(pairAcc (Pair (Map String Bool) (List ResolveWorkItem))) (bit rd/SExpr)] -> (Pair (Map String Bool) (List ResolveWorkItem))
                                          (mt bit
                                            ((rd/sexprList bparts) (addLetBinding bparts pairAcc effectOk))
                                            ((rd/sexprVect bparts) (addLetBinding bparts pairAcc effectOk))
                                            (_ pairAcc)))
                                        (pair scope (list))
                                        bindItems))
                        (finalLetScope (.-first bindRes))
                        (letValItems (list-reverse (.-second bindRes)))
                        (letBodyItems (mapRitems bodyExprs finalLetScope effectOk))]
                    (ResolveState :work (list-append letValItems (list-append letBodyItems rest)) :diags acc)))

                 ((= headTok "if")
                  (ResolveState :work (list-append (mapRitems tailArgs scope effectOk) rest) :diags acc))

                 ((= headTok "cond")
                  (let [(condItems (fold (fn [(cacc (List ResolveWorkItem)) (clause rd/SExpr)] -> (List ResolveWorkItem)
                                            (mt clause
                                              ((rd/sexprList cparts)
                                               (let [(chead (firstHeadIdent cparts))]
                                                 (if (= chead ":else")
                                                   (list-append cacc (mapRitems (safeTail cparts) scope effectOk))
                                                   (list-append cacc (mapRitems cparts scope effectOk)))))
                                              (_ cacc)))
                                          (list)
                                          tailArgs))]
                    (ResolveState :work (list-append condItems rest) :diags acc)))

                 ((= headTok "fn")
                  (let [(isBang (and (not (list-empty? tailArgs))
                                      (= (firstHeadIdent tailArgs) "!")))
                        (remArgs (if isBang (safeTail tailArgs) tailArgs))
                        (afterParams (safeTail remArgs))
                        (bodyNodes (if (and (not (list-empty? afterParams))
                                             (= (firstHeadIdent afterParams) "->"))
                                      (dropTwo afterParams)
                                      afterParams))
                        (paramItems (firstVectItems remArgs))
                        (fnScope (fold (fn [(sc (Map String Bool)) (p rd/SExpr)] -> (Map String Bool)
                                          (mt p
                                            ((rd/sexprAtom name) (map-set sc name true))
                                            ((rd/sexprList parts)
                                             (map-set sc (firstHeadIdent parts) true))
                                            ((rd/sexprVect parts)
                                             (map-set sc (firstHeadIdent parts) true))))
                                        scope
                                        paramItems))
                        (fnBodyItems (mapRitems bodyNodes fnScope isBang))]
                    (ResolveState :work (list-append fnBodyItems rest) :diags acc)))

                 ((= headTok "match")
                  (let [(scrutinee (mt (list-head tailArgs) ((some s) s) ((none) (rd/makeAtom ""))))
                        (arms (safeTail tailArgs))
                        (scrutItem (ResolveWorkItem :expr scrutinee :scope scope :effectOk effectOk))
                        (armsRes (fold (fn [(accArms (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List ResolveWorkItem)))) (arm rd/SExpr)] -> (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List ResolveWorkItem)))
                                          (mt arm
                                            ((rd/sexprList armParts)
                                             (let [(pat (mt (list-head armParts) ((some p) p) ((none) (rd/makeAtom "_"))))
                                                   (armBodies (safeTail armParts))
                                                   (patRes (extractPattern pat mod deps path (.-first (.-second accArms))))
                                                   (boundNames (.-first (.-first patRes)))
                                                   (optHead (.-second (.-first patRes)))
                                                   (hasCatchall (or (.-second (.-first accArms)) (mt optHead ((none) true) ((some _) false))))
                                                   (nextHeads (mt optHead ((some hname) (list-cons hname (.-first (.-first accArms)))) ((none) (.-first (.-first accArms)))))
                                                   (armScope (addStringsToSet scope boundNames))
                                                   (newArmItems (mapRitems armBodies armScope effectOk))]
                                               (pair (pair nextHeads hasCatchall)
                                                     (pair (.-second patRes)
                                                           (list-append (.-second (.-second accArms)) newArmItems)))))
                                            (_ accArms)))
                                        (pair (pair (list) false) (pair acc (list scrutItem)))
                                        arms))
                        (dArms (if (.-second (.-first armsRes))
                                  (.-first (.-second armsRes))
                                  (checkMatchExhaustiveness (.-first (.-first armsRes)) mod deps path (.-first (.-second armsRes)))))
                        (allMatchItems (.-second (.-second armsRes)))]
                    (ResolveState :work (list-append allMatchItems rest) :diags dArms)))

                 ((string-starts-with? headTok ".-")
                  (let [(fname (sliceFrom headTok 2))
                        (dFname (if (map-has? fieldNames fname)
                                   acc
                                   (list-cons (makeDiag "rule-2" (str "no record in this module has a field " fname) path) acc)))
                        (newItems (mapRitems tailArgs scope effectOk))]
                    (ResolveState :work (list-append newItems rest) :diags dFname)))

                 ((isCtorHead? headTok)
                   (let [(schemaInfo (if (isQualifiedName? headTok)
                                        (let [(qp (splitQual headTok))
                                              (alias (.-first qp))
                                              (member (.-second qp))]
                                          (mt (modImport mod alias)
                                            ((some mpath)
                                             (mt (map-get deps mpath)
                                               ((some target)
                                                (if (not (list-contains? (.-exportedTypes target) member))
                                                  (pair (none) (some (makeDiag "rule-9" (str member " is not an exported type of " (.-name target)) path)))
                                                  (mt (modSchema target member)
                                                    ((some s) (pair (some s) (none)))
                                                    ((none) (pair (none) (some (makeDiag "rule-2" (str member " is not a record type in " (.-name target)) path)))))))
                                               ((none) (pair (none) (none)))))
                                            ((none) (pair (none) (some (makeDiag "rule-9" (str headTok ": alias " alias " is not imported") path))))))
                                        (mt (modSchema mod headTok)
                                          ((some s) (pair (some s) (none)))
                                          ((none) (pair (none) (some (makeDiag "rule-2" (str headTok " is not a record type in this module") path)))))))
                         (dCtor (mt (.-second schemaInfo) ((some d) (list-cons d acc)) ((none) acc)))]
                    (mt (.-first schemaInfo)
                      ((none)
                       (let [(newItems (mapRitems tailArgs scope effectOk))]
                         (ResolveState :work (list-append newItems rest) :diags dCtor)))
                      ((some schema)
                       (let [(fieldMap (fold (fn [(fm (Map String FieldSummary)) (f FieldSummary)] -> (Map String FieldSummary)
                                                (map-set fm (.-name f) f))
                                              (map-empty)
                                              (.-fields schema)))
                             (fieldsRes (foldCtorArgs tailArgs fieldMap (map-empty) (.-name schema) path dCtor))
                             (givenKeys (.-first fieldsRes))
                             (dFields (.-second fieldsRes))
                             (missing (filter (fn [(f FieldSummary)] -> Bool
                                                (and (not (.-hasDefault f))
                                                     (not (map-has? givenKeys (.-name f)))))
                                              (.-fields schema)))
                             (dMissing (if (not (list-empty? missing))
                                          (list-cons (makeDiag "ctor" (str (.-name schema) " is missing " (string-join (map (fn [(f FieldSummary)] -> String (.-name f)) missing) ", ")) path) dFields)
                                          dFields))
                             (ctorValExprs (extractCtorValExprs tailArgs))
                             (newItems (map (fn [(e rd/SExpr)] -> ResolveWorkItem (ResolveWorkItem :expr e :scope scope :effectOk effectOk)) ctorValExprs))]
                         (ResolveState :work (list-append newItems rest) :diags dMissing))))))

                 (:else
                  (let [(isLiteralCallee (isLiteralAtom? headTok))
                        (dNotCallable (if isLiteralCallee
                                          (list-cons (makeDiag "not-callable" (str headTok " is a literal, not a function") path) acc)
                                          acc))
                        (calleeEffect (if (isEffectfulBuiltin? headTok)
                                         true
                                         (mt (modFun mod headTok)
                                           ((some f) (.-effect f))
                                           ((none)
                                            (if (isQualifiedName? headTok)
                                              (let [(qp (splitQual headTok))
                                                    (alias (.-first qp))
                                                    (member (.-second qp))]
                                                (mt (modImport mod alias)
                                                  ((some mpath)
                                                   (mt (map-get deps mpath)
                                                     ((some target)
                                                      (mt (modFun target member)
                                                        ((some f) (.-effect f))
                                                        ((none) false)))
                                                     ((none) false)))
                                                  ((none) false)))
                                              false)))))
                        (hasEffectLambda (fold (fn [(ef Bool) (a rd/SExpr)] -> Bool
                                                   (or ef (mt a
                                                             ((rd/sexprList aitems)
                                                              (and (and (= (firstHeadIdent aitems) "fn")
                                                                        (not (list-empty? (safeTail aitems))))
                                                                   (= (rd/sexprHead (secondExprEmpty aitems)) "!")))
                                                            (_ false))))
                                                 false
                                                 tailArgs))
                        (totalEffect (or calleeEffect hasEffectLambda))
                        (dEffect (if (and totalEffect (not effectOk))
                                    (list-cons (makeDiag "rule-12" "effectful call inside a declaration not marked !" path) dNotCallable)
                                    dNotCallable))
                        (expectedArity (if (map-has? scope headTok)
                                          (none)
                                          (mt (modFun mod headTok)
                                            ((some f) (some (list-length (.-params f))))
                                            ((none)
                                             (if (isQualifiedName? headTok)
                                               (let [(qp (splitQual headTok))
                                                     (alias (.-first qp))
                                                     (member (.-second qp))]
                                                 (mt (modImport mod alias)
                                                   ((some mpath)
                                                    (mt (map-get deps mpath)
                                                      ((some target)
                                                       (mt (modFun target member)
                                                         ((some f) (some (list-length (.-params f))))
                                                         ((none)
                                                          (mt (map-get (.-exportedCases target) member)
                                                            ((some ename) (enumCaseArity target ename member))
                                                            ((none) (none))))))
                                                      ((none) (none))))
                                                   ((none) (none))))
                                               (mt (map-get (.-caseOwner mod) headTok)
                                                 ((some ename) (enumCaseArity mod ename headTok))
                                                 ((none)
                                                  (mt (ty/builtinSig headTok)
                                                    ((some bsig)
                                                     (if (.-first (.-second bsig))
                                                       (none)
                                                       (some (list-length (.-first bsig)))))
                                                    ((none) (none))))))))))
                        (givenCount (list-length tailArgs))
                        (dArity (mt expectedArity
                                   ((some exp)
                                    (if (not (= exp givenCount))
                                      (list-cons (makeDiag "arity" (str headTok " takes " (string-from-int64 exp) " argument(s), given " (string-from-int64 givenCount)) path) dEffect)
                                      dEffect))
                                   ((none) dEffect)))
                        (dHead (checkHeadExpr h scope effectOk mod deps fieldNames path dArity))
                        (newItems (mapRitems tailArgs scope effectOk))]
                    (ResolveState :work (list-append newItems rest) :diags dHead)))))))))))))

(df rResolveRun [(st ResolveState) (budget Int64) (mod ModuleSummary) (deps (Map String ModuleSummary)) (fieldNames (Map String Bool)) (path String)] -> ResolveState
  (let [(next (fold (fn [(s ResolveState) (idx Int64)] -> ResolveState
                      (rResolveTick s idx mod deps fieldNames path))
                    st
                    (range 0 budget)))]
    (if (list-empty? (.-work next))
      next
      (rResolveRun next (* budget 2) mod deps fieldNames path))))

(df foldCtorArgs [(args (List rd/SExpr)) (fieldMap (Map String FieldSummary)) (given (Map String Bool)) (sname String) (path String) (acc (List ty/Diagnostic))] -> (Pair (Map String Bool) (List ty/Diagnostic))
  (mt (list-head args)
    ((none) (pair given acc))
    ((some keyNode)
     (let [(valNode (secondExprEmpty args))
           (rest (dropTwo args))
           (rawKey (rd/sexprHead keyNode))
           (kname (if (string-starts-with? rawKey ":")
                    (sliceFrom rawKey 1)
                    rawKey))]
       (let [(dKey (if (not (map-has? fieldMap kname))
                      (list-cons (makeDiag "ctor" (str sname " has no field " kname) path) acc)
                      (if (map-has? given kname)
                        (list-cons (makeDiag "ctor" (str sname ": duplicate key " kname) path) acc)
                        acc)))]
         (foldCtorArgs rest fieldMap (map-set given kname true) sname path dKey))))))

(df collectAllFieldNames [(mod ModuleSummary) (deps (Map String ModuleSummary))] -> (Map String Bool)
  (let [(s1 (map-set (map-set (map-empty) "first" true) "second" true))
        (s2 (fold (fn [(acc (Map String Bool)) (s SchemaSummary)] -> (Map String Bool)
                    (addFieldsToSet acc (.-fields s)))
                  s1
                  (map-values (.-schemas mod))))
        (s3 (fold (fn [(acc (Map String Bool)) (mpath String)] -> (Map String Bool)
                    (mt (map-get deps mpath)
                      ((some target)
                       (addStringsToSet acc (map-keys (.-exportedFields target))))
                      ((none) acc)))
                  s2
                  (map-values (.-imports mod))))]
    s3))

(df checkDefunBody [(d a/DefunNode) (mod ModuleSummary) (deps (Map String ModuleSummary)) (fieldNames (Map String Bool)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (let [(paramScope (fold (fn [(sc (Map String Bool)) (p a/Param)] -> (Map String Bool)
                             (map-set sc (.-name p) true))
                           (map-empty)
                           (.-params d)))
        (initItems (map (fn [(bodyE rd/SExpr)] -> ResolveWorkItem
                           (ResolveWorkItem :expr bodyE :scope paramScope :effectOk (.-effect d)))
                         (.-body d)))
        (finalSt (rResolveRun (ResolveState :work initItems :diags acc) 64 mod deps fieldNames path))]
    (.-diags finalSt)))

(df checkBodies [(forms (List a/TopForm)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(fieldNames (collectAllFieldNames mod deps))]
    (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
            (mt form
              ((a/topDefun d)
               (checkDefunBody d mod deps fieldNames path acc))
              (_ acc)))
          (list)
          forms)))

(df checkReservedName [(name String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (if (isReservedIdent? name)
    (diagReservedPrefix name path acc)
    acc))

(df checkNamedItems [(names (List String)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (n String)] -> (List ty/Diagnostic)
          (checkReservedName n path a))
        acc
        names))

(df checkReservedNames [(forms (List a/TopForm)) (path String)] -> (List ty/Diagnostic)
  (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
          (mt form
            ((a/topDefun d)
             (checkNamedItems (map (fn [(p a/Param)] -> String (.-name p)) (.-params d))
                                path
                                (checkReservedName (.-name d) path acc)))
            ((a/topSchema s)
             (checkNamedItems (map (fn [(f a/AstField)] -> String (.-name f)) (.-fields s))
                                path
                                (checkReservedName (.-name s) path acc)))
            ((a/topEnum e)
             (fold (fn [(a (List ty/Diagnostic)) (c a/EnumCase)] -> (List ty/Diagnostic)
                     (checkNamedItems (map (fn [(p a/Param)] -> String (.-name p)) (.-fields c))
                                        path
                                        (checkReservedName (.-name c) path a)))
                   (checkReservedName (.-name e) path acc)
                   (.-cases e)))
            ((a/topModule m)
             (checkNamedItems (.-exported m) path acc))
            (_ acc)))
        (list)
        forms))

(df resolveModule [(mod ModuleSummary) (forms (List a/TopForm)) (deps (Map String ModuleSummary))] -> (List ty/Diagnostic)
  :d "Pass 1 & Pass 2 symbol resolution and rule checking."
  (let [(p (.-path mod))
        (passes (list (checkReservedNames forms p)
                      (checkModuleRules mod p)
                      (checkImportsAndCycles mod deps p)
                      (checkExportClosure mod p)
                      (checkTypeAnnotations mod deps p)
                      (checkBodies forms mod deps p)))]
    (fold (fn [(acc (List ty/Diagnostic)) (pDiags (List ty/Diagnostic))] -> (List ty/Diagnostic)
            (list-append pDiags acc))
          (list)
          passes)))
