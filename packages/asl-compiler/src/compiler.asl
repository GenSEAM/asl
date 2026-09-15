(module asl-compiler/compiler
  :d "Unified 100% self-hosted AgentScript compiler pipeline in pure ASL."
  :x [CompileResult compileSource compileSourceTarget compileStandaloneSource compileStandaloneTarget compileSourceToC99 compilePackageToC99! formatDiagnostic emitWasmBinaryTarget emitWasiBinaryTarget]
  :i [(ast :a a) (reader :a rd) (types :a ty) (check :a chk) (resolve :a r) (emit :a em) (emitC :a emC) (emitWat :a emWat) (emitGo :a emGo) (wasm :a w) (c99Emit :a c99) (c99Mangle :a cm)])

(dfs CompileResult
  (:f ok Bool "True if compilation succeeded without errors")
  (:f code Str "Generated standalone target source code")
  (:f diagnostics (List Str) "List of error messages if compilation failed"))

(df formatDiagnostic [(d ty/Diagnostic)] -> Str
  :d "Formats a checker diagnostic into standard line:col: message format."
  (str (.-path d) ":" (string-from-int64 (.-line d)) ":" (string-from-int64 (.-col d)) ": [" (.-code d) "] " (.-message d)))

(df sexprToAtom [(s rd/SExpr)] -> Str
  :d "Extracts atom string value from SExpr."
  (mt s
    ((sexprAtom v) v)
    ((sexprList items)
     (if (list-empty? items) "" (sexprToAtom (option-or (list-get items 0) (rd/makeAtom "")))))
    ((sexprVect items)
     (if (list-empty? items) "" (sexprToAtom (option-or (list-get items 0) (rd/makeAtom "")))))))

(df lowerBodyInfix [(bodyList (List rd/SExpr))] -> Str
  :d "Lowers S-expression body list into infix expression string."
  (if (list-empty? bodyList)
      ""
      (let [(firstExpr (option-or (list-get bodyList 0) (rd/makeAtom "")))]
        (mt firstExpr
          ((sexprAtom v) v)
          ((sexprList items)
           (cond
             ((>= (list-length items) 3)
              (let [(op (sexprToAtom (option-or (list-get items 0) (rd/makeAtom ""))))
                    (lhs (sexprToAtom (option-or (list-get items 1) (rd/makeAtom ""))))
                    (rhs (sexprToAtom (option-or (list-get items 2) (rd/makeAtom ""))))]
                (str lhs " " op " " rhs)))
             ((= (list-length items) 2)
              (let [(op (sexprToAtom (option-or (list-get items 0) (rd/makeAtom ""))))
                    (arg (sexprToAtom (option-or (list-get items 1) (rd/makeAtom ""))))]
                (str op arg)))
             ((= (list-length items) 1)
              (sexprToAtom (option-or (list-get items 0) (rd/makeAtom ""))))
             (:else "")))
          ((sexprVect _) "")))))

(df lowerBodyWat [(bodyList (List rd/SExpr)) (retTy Str)] -> Str
  :d "Lowers S-expression body list into WebAssembly Text instructions."
  (if (list-empty? bodyList)
      (let [(wRet (emWat/watType retTy))]
        (if (= wRet "void") "" (str "  (" wRet ".const 0)")))
      (let [(firstExpr (option-or (list-get bodyList 0) (rd/makeAtom "")))]
        (mt firstExpr
          ((sexprAtom v)
           (if (or (string-starts-with? v "-")
                   (and (>= (option-or (string-slice v 0 1) "") "0")
                        (<= (option-or (string-slice v 0 1) "") "9")))
               (str "  " (emWat/watConst v retTy))
               (str "  " (emWat/watGet v))))
          ((sexprList items)
           (cond
             ((>= (list-length items) 3)
              (let [(op (sexprToAtom (option-or (list-get items 0) (rd/makeAtom ""))))
                    (lhs (sexprToAtom (option-or (list-get items 1) (rd/makeAtom ""))))
                    (rhs (sexprToAtom (option-or (list-get items 2) (rd/makeAtom ""))))]
                (str "  " (emWat/emitWatExpr op lhs rhs retTy))))
             ((= (list-length items) 1)
              (let [(v (sexprToAtom (option-or (list-get items 0) (rd/makeAtom ""))))]
                (str "  " (emWat/watGet v))))
             (:else
              (let [(wRet (emWat/watType retTy))]
                (if (= wRet "void") "" (str "  (" wRet ".const 0)"))))))
          ((sexprVect _)
           (let [(wRet (emWat/watType retTy))]
             (if (= wRet "void") "" (str "  (" wRet ".const 0)"))))))))

(df emitWatTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly Text module."
  (let [(fnDefs (fold (fn [(acc (List Str)) (f a/TopForm)]
                         (mt f
                           ((topDefun d)
                            (let [(paramsWat (string-join (map (fn [(p a/Param)] -> Str
                                                                  (str "(param $" (.-name p) " " (emWat/watType (.-type p)) ")"))
                                                                (.-params d)) " "))
                                  (body (lowerBodyWat (.-body d) (.-retType d)))
                                  (fnStr (emWat/watFn (.-name d) paramsWat (.-retType d) body true))]
                              (list-append acc (list (str "  " fnStr)))))
                           (:else acc)))
                       (list)
                       forms))
        (allFuncs (if (list-empty? fnDefs)
                       "  (func $main (result i64)\n    (i64.const 0))\n"
                       (str (string-join fnDefs "\n") "\n")))]
    (emWat/emitWatModule allFuncs true)))

(df emitGoTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to idiomatic Go package."
  (let [(structsList (fold (fn [(acc (List Str)) (f a/TopForm)]
                              (mt f
                                ((topSchema s)
                                 (let [(fields (string-join (map (fn [(fld a/AstField)] -> Str
                                                                   (let [(fname (string-upper (option-or (string-slice (.-name fld) 0 1) "")))]
                                                                     (str "\t" fname (option-or (string-slice (.-name fld) 1 (string-length (.-name fld))) "") " " (emGo/emitGoType (.-type fld)) "\n")))
                                                                 (.-fields s)) ""))
                                       (stDecl (emGo/emitGoStruct (.-name s) fields))]
                                   (list-append acc (list stDecl))))
                                ((topEnum e)
                                 (let [(cases (map (fn [(c a/EnumCase)] -> Str (.-name c)) (.-cases e)))
                                       (enumDecl (emGo/emitGoEnum (.-name e) cases))]
                                   (list-append acc (list enumDecl))))
                                (:else acc)))
                            (list)
                            forms))
        (funcsList (fold (fn [(acc (List Str)) (f a/TopForm)]
                            (mt f
                              ((topDefun d)
                               (let [(pStr (string-join (map (fn [(p a/Param)] -> Str
                                                                (str (.-name p) " " (emGo/emitGoType (.-type p))))
                                                              (.-params d)) ", "))
                                     (rTy (emGo/emitGoType (.-retType d)))
                                     (infix (lowerBodyInfix (.-body d)))
                                     (body (if (= rTy "") "" (if (string-empty? infix) (if (= rTy "bool") "return true" (if (= rTy "string") "return \"\"" "return 0")) (str "return " infix))))
                                     (fnDecl (emGo/emitGoFn (.-name d) pStr (.-retType d) body true))]
                                 (list-append acc (list fnDecl))))
                              (:else acc)))
                          (list)
                          forms))
        (hasMain (fold (fn [(acc Bool) (f a/TopForm)]
                          (or acc (mt f
                                    ((topDefun d) (or (= (string-lower (.-name d)) "main") (= (.-name d) "Main")))
                                    (:else false))))
                        false
                        forms))
        (allFuncs (if hasMain
                       (string-join funcsList "\n")
                       (str (string-join funcsList "\n") (if (list-empty? funcsList) "" "\n") "func Main() int64 {\n\treturn 0\n}\n")))]
    (emGo/emitGoProgram "main" (string-join structsList "\n") allFuncs)))

(df emitCTarget [(forms (List a/TopForm)) (target Str)] -> Str
  :d "Lowers top-level forms to ISO C99, freestanding C, or Arduino sketch source."
  (let [(isArduino (= target "arduino"))
        (isFree (or isArduino (= target "c-embedded")))]
    (if isArduino
        (let [(hasSetup (fold (fn [(acc Bool) (f a/TopForm)]
                               (or acc (mt f ((topDefun d) (= (.-name d) "setup")) (:else false))))
                             false forms))
              (hasLoop (fold (fn [(acc Bool) (f a/TopForm)]
                              (or acc (mt f ((topDefun d) (= (.-name d) "loop")) (:else false))))
                            false forms))]
          (if (and hasSetup hasLoop)
              (c99/emitCStandalone forms "" true)
              (str (emC/emitArduinoHeader) "\n" (c99/emitCStandalone forms "" true))))
        (c99/emitCStandalone forms "" isFree))))

(df compileSourceTarget [(src Str) (target Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "End-to-end compilation with target selection and dependencies."
  (mt (a/parse src)
    ((err pe)
     (let [(msg (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
       (CompileResult :ok false :code "" :diagnostics (list msg))))
    ((ok forms)
     (let [(diags (chk/checkModule forms deps path))]
       (if (not (list-empty? diags))
           (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (formatDiagnostic d)) diags))]
             (CompileResult :ok false :code "" :diagnostics formatted))
           (cond
             ((or (= target "wasm-bin") (= target "wasm-binary"))
              (CompileResult :ok true :code (w/emitWasmBinaryTarget forms) :diagnostics (list)))
             ((= target "wasi")
              (CompileResult :ok true :code (emitWasiBinaryTarget forms) :diagnostics (list)))
             ((or (= target "wasm") (= target "wat"))
              (CompileResult :ok true :code (emitWatTarget forms) :diagnostics (list)))
             ((= target "go")
              (CompileResult :ok true :code (emitGoTarget forms) :diagnostics (list)))
             ((or (or (or (= target "c99") (= target "c-embedded")) (= target "arduino")) (= target "c"))
              (CompileResult :ok true :code (emitCTarget forms target) :diagnostics (list)))
             ((= target "rust")
              (let [(rustSrc (em/emitRustProgram forms (list)))]
                (CompileResult :ok true :code rustSrc :diagnostics (list))))
             (:else
              (CompileResult :ok true :code (emitWatTarget forms) :diagnostics (list)))))))))

(df compileSource [(src Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "End-to-end compilation defaulting to WebAssembly universal core target."
  (compileSourceTarget src "wasm" deps path))

(df compileStandaloneTarget [(src Str) (target Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compileSourceTarget src target (map-empty) path))

(df compileStandaloneSource [(src Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file defaulting to WebAssembly universal core target."
  (compileStandaloneTarget src "wasm" path))

(df emitWasmBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly binary target string."
  (w/emitWasmBinaryTarget forms))

(df emitWasiBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly binary target string for WASI."
  (w/emitWasiBinaryTarget forms))


(df compileSourceToC99 [(src Str) (path Str) (isFreestanding Bool)] -> CompileResult
  :d "Compiles source string to ISO C99 target source code."
  (let [(target (if isFreestanding "c-embedded" "c99"))]
    (compileSourceTarget src target (map-empty) path)))

(df makeExpMacro [(al Str) (fnName Str)] -> Str
  :d "Constructs C macro alias definition for exported function."
  (let [(mFn (cm/mangleCIdent fnName))]
    (if (= fnName "main")
        (str "#define " al "_main dep_main\n#define " al "_asl_main dep_main")
        (str "#define " al "_" mFn " " mFn))))

(df collectExpDefs [(al Str) (exps (List Str)) (idx Int64) (len Int64) (acc (List Str))] -> (List Str)
  :d "Accumulates macro definitions for module export list."
  (if (>= idx len)
      acc
      (let [(fnName (option-or (list-get exps idx) ""))]
        (collectExpDefs al exps (+ idx 1) len (list-append acc (list (makeExpMacro al fnName)))))))

(df collectAliasMacrosStep [(aliases (List Str)) (importsMap (Map Str Str)) (deps (Map Str r/ModuleSummary)) (idx Int64) (len Int64) (acc (List Str))] -> (List Str)
  :d "Iteratively builds macro header aliases for package dependencies."
  (if (>= idx len)
      acc
      (let [(al (option-or (list-get aliases idx) ""))]
        (mt (map-get importsMap al)
          ((none) (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len acc))
          ((some modPath)
           (mt (map-get deps modPath)
             ((none) (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len acc))
             ((some s)
              (let [(exps (.-exports s))
                    (defs (collectExpDefs al exps 0 (list-length exps) (list)))]
                (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len (list-append acc defs))))))))))

(df collectAllAliasMacros [(summaries (List r/ModuleSummary)) (deps (Map Str r/ModuleSummary)) (idx Int64) (len Int64) (acc (List Str))] -> (List Str)
  :d "Collects macro aliases across all module summaries in the package."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get summaries idx) (r/ModuleSummary :name "" :path "" :exports (list) :imports (map-empty) :schemas (map-empty) :enums (map-empty) :funs (map-empty))))
            (impMap (.-imports s))
            (aliases (map-keys impMap))
            (macros (collectAliasMacrosStep aliases impMap deps 0 (list-length aliases) (list)))]
        (collectAllAliasMacros summaries deps (+ idx 1) len (list-append acc macros)))))

(df renameTopFormMain [(tf a/TopForm)] -> a/TopForm
  :d "Renames top-level defun main to dep-main to prevent collision."
  (mt tf
    ((a/topDefun d)
     (if (= (.-name d) "main")
         (a/topDefun (a/DefunNode :name "dep-main" :typeVars (.-typeVars d) :isExported (.-isExported d) :effect (.-effect d) :params (.-params d) :retType (.-retType d) :docstring (.-docstring d) :body (.-body d)))
         tf))
    (:else tf)))

(df collectRenamedForms [(fList (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/TopForm))] -> (List a/TopForm)
  :d "Accumulates forms with renamed main function."
  (if (>= idx len)
      acc
      (let [(tf (option-or (list-get fList idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (collectRenamedForms fList (+ idx 1) len (list-append acc (list (renameTopFormMain tf)))))))

(df collectDepFormsStep [(depSummaries (List r/ModuleSummary)) (entryFile Str) (idx Int64) (len Int64) (acc (List a/TopForm))] -> (Result (List a/TopForm) Str)
  :d "Accumulates all top-level forms from dependency modules."
  (if (>= idx len)
      (ok acc)
      (let [(s (option-or (list-get depSummaries idx) (r/ModuleSummary :name "" :path "" :hasHeader false :hasDoc false :exports (list) :exportedTypes (list) :imports (map-empty) :funs (map-empty) :schemas (map-empty) :enums (map-empty) :caseOwner (map-empty))))
            (p (.-path s))]
        (if (or (= p "") (= p entryFile))
            (collectDepFormsStep depSummaries entryFile (+ idx 1) len acc)
            (mt (file-read p)
              ((err _) (err (str "Failed to read dependency file: " p)))
              ((ok sSrc)
               (mt (a/parse sSrc)
                 ((err pe)
                  (err (str p ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
                 ((ok fList)
                  (let [(renamedList (collectRenamedForms fList 0 (list-length fList) (list)))]
                    (collectDepFormsStep depSummaries entryFile (+ idx 1) len (list-append acc renamedList)))))))))))

(df ! compilePackageToC99! [(entryFile Str) (roots (List Str)) (isFreestanding Bool)] -> (Result CompileResult Str)
  :d "Compiles a complete package and all its dependencies into a single standalone ISO C99 translation unit."
  (let [(readRes (file-read entryFile))]
    (mt readRes
      ((err _) (err (str "Failed to read entry file: " entryFile)))
      ((ok entrySrc)
       (mt (a/parse entrySrc)
         ((err pe)
          (let [(msg (str entryFile ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
            (ok (CompileResult :ok false :code "" :diagnostics (list msg)))))
         ((ok entryForms)
          (let [(entrySummary (r/collectSummary entryForms entryFile))
                (importPaths (r/mapValuesList (.-imports entrySummary)))
                (depsRes (r/loadModuleDeps! roots importPaths))]
            (mt depsRes
              ((err _) (err "Failed to load package dependencies"))
              ((ok deps)
               (let [(diags (chk/checkModule entryForms deps entryFile))]
                 (if (not (list-empty? diags))
                     (let [(formatted (map formatDiagnostic diags))]
                       (ok (CompileResult :ok false :code "" :diagnostics formatted)))
                     (let [(depSummaries (map-values deps))
                           (allSummaries (list-append depSummaries (list entrySummary)))
                           (aliasMacros (collectAllAliasMacros allSummaries deps 0 (list-length allSummaries) (list)))
                           (macroHeader (if (list-empty? aliasMacros)
                                            ""
                                            (str (string-join aliasMacros "\n") "\n\n")))
                           (depFormsRes (collectDepFormsStep depSummaries entryFile 0 (list-length depSummaries) (list)))]
                       (mt depFormsRes
                         ((err msg) (ok (CompileResult :ok false :code "" :diagnostics (list msg))))
                         ((ok depFormsList)
                          (let [(allForms (list-append depFormsList entryForms))
                                (cSource (str macroHeader (c99/emitCStandalone allForms "" isFreestanding)))]
                            (ok (CompileResult :ok true :code cSource :diagnostics (list))))))))))))))))))
