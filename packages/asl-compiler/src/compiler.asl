(module asl-compiler/compiler
  :d "Self-hosting AgentScript compiler core: parse, check and lower to ISO C99."
  :x [CompileResult compileSourceToC99 compilePackageToC99! formatDiagnostic compileSourceTarget compileStandaloneTarget verifyPackageCapabilities eliminateDeadCapabilities]
  :i [(ast :a a) (types :a ty) (check :a chk) (resolve :a r) (c99Emit :a c99) (c99Mangle :a cm)])

(dfs CompileResult
  (:f ok Bool "True if compilation succeeded without errors")
  (:f code Str "Generated standalone target source code")
  (:f diagnostics (List Str) "List of error messages if compilation failed"))

(df formatDiagnostic [(d ty/Diagnostic)] -> Str
  :d "Formats a checker diagnostic into standard line:col: message format."
  (str (.-path d) ":" (string-from-int64 (.-line d)) ":" (string-from-int64 (.-col d)) ": [" (.-code d) "] " (.-message d)))

(df formatDiagnosticsStep [(diags (List ty/Diagnostic)) (idx Int64) (len Int64) (acc (List Str))] -> (List Str)
  :d "Formats a slice of diagnostics to strings without relying on higher-order map."
  (if (>= idx len)
      acc
      (mt (list-get diags idx)
        ((some d)
         (formatDiagnosticsStep diags (+ idx 1) len (list-append acc (list (formatDiagnostic d)))))
        ((none)
         (formatDiagnosticsStep diags (+ idx 1) len acc)))))

(df formatDiagnostics [(diags (List ty/Diagnostic))] -> (List Str)
  :d "Formats diagnostic list to string list."
  (formatDiagnosticsStep diags 0 (list-length diags) (list)))

(df compileSourceToC99 [(src Str) (path Str) (isFreestanding Bool)] -> CompileResult
  :d "Compiles a standalone source string to ISO C99, the only target the self-hosting core carries."
  (mt (a/parse src)
    ((err pe)
     (let [(msg (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
       (CompileResult :ok false :code "" :diagnostics (list msg))))
    ((ok forms)
     (let [(diags (chk/checkModule forms (map-empty) path))]
       (if (not (list-empty? diags))
           (let [(formatted (formatDiagnostics diags))]
             (CompileResult :ok false :code "" :diagnostics formatted))
           (CompileResult :ok true :code (c99/emitCStandalone forms "" isFreestanding) :diagnostics (list)))))))

(df compileSourceTarget [(src Str) (target Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "Compiles a standalone source string to the requested target. Core retains C99 backends; non-core targets are decoupled."
  (if (or (or (= target "c99") (= target "c")) (= target "c-embedded"))
      (compileSourceToC99 src path (= target "c-embedded"))
      (CompileResult :ok false :code "" :diagnostics (list (str "Target '" target "' decoupled from core; use dynamic pluggable backend")))))

(df compileStandaloneTarget [(src Str) (target Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compileSourceTarget src target (map-empty) path))

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
      (let [(s (option-or (list-get summaries idx) (r/emptyModuleSummary)))
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
      (let [(s (option-or (list-get depSummaries idx) (r/emptyModuleSummary)))
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
          (do
            (println "--> [Compiler Step A] Entry file parsed successfully")
            (let [(entrySummary (r/collectSummary entryForms entryFile))
                  (importPaths (r/mapValuesList (.-imports entrySummary)))
                  (depsRes (r/loadModuleDeps! roots importPaths))]
              (mt depsRes
                ((err _) (err "Failed to load package dependencies"))
                ((ok deps)
                 (do
                   (println (str "--> [Compiler Step B] Loaded " (string-from-int64 (map-size deps)) " dependencies"))
                   (let [(diags (chk/checkModule entryForms deps entryFile))]
                     (if (not (list-empty? diags))
                         (let [(formatted (formatDiagnostics diags))]
                           (ok (CompileResult :ok false :code "" :diagnostics formatted)))
                         (do
                           (println "--> [Compiler Step C] Module checked, collecting dep forms...")
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
                                (do
                                  (println (str "--> [Compiler Step D] Dep forms collected: " (string-from-int64 (list-length depFormsList)) ", emitting C99..."))
                                  (let [(allForms (list-append depFormsList entryForms))
                                        (cSource (str macroHeader (c99/emitCStandalone allForms "" isFreestanding)))]
                                    (println (str "--> [Compiler Step E] Emitted C99: " (string-from-int64 (string-length cSource)) " chars"))
                                    (ok (CompileResult :ok true :code cSource :diagnostics (list))))))))))))))))))))))

(df verifyPackageCapabilities [(declared (List Str)) (used (List Str))] -> Bool
  :d "Verifies used capabilities against declared package capability row."
  (let [(unauth (fold (fn [(acc (List Str)) (cap Str)] -> (List Str)
                        (if (list-contains? declared cap)
                          acc
                          (list-append acc (list cap))))
                      (list)
                      used))]
    (list-empty? unauth)))

(df eliminateDeadCapabilities [(sourceCode Str) (requestedCaps (List Str))] -> Str
  :d "Eliminates unreferenced platform syscall stubs from emitted C99 translation units."
  (let [(allPlatformCaps (list "netSocket" "procSpawn" "procWait" "procSignal" "fsWatch"))
        (deadCaps (fold (fn [(acc (List Str)) (cap Str)] -> (List Str)
                          (if (list-contains? requestedCaps cap)
                            acc
                            (list-append acc (list cap))))
                        (list)
                        allPlatformCaps))]
    (fold (fn [(code Str) (deadCap Str)] -> Str
            (if (= deadCap "netSocket")
              (string-replace code "asl_platform_darwin_net_socket" "/* dce */ 0")
              (if (= deadCap "procSpawn")
                (string-replace code "asl_platform_darwin_proc_spawn" "/* dce */ 0")
                (if (= deadCap "fsWatch")
                  (string-replace code "asl_platform_darwin_fs_watch" "/* dce */ 0")
                  code))))
          sourceCode
          deadCaps)))
