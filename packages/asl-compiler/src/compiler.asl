(module asl-compiler/compiler :x [CompileResult compileSourceToC99 compilePackageToC99! compilePackageToLlvm! formatDiagnostic formatIrDiagnostics compileSourceTarget compileStandaloneTarget verifyPackageCapabilities eliminateDeadCapabilities] :i [(asl-parser/ast :a a) (asl-checker/types :a ty) (asl-checker/check :a chk) (asl-checker/resolve :a r) (asl-codegen/c99Emit :a c99) (asl-codegen/c99Mangle :a cm) (asl-target-llvm/main :a llvm) (asl-ir/types :a irTy) (asl-ir/link :a lk)])

(schema CompileResult (:f ok Bool) (:f code Str) (:f diagnostics (List Str)))

fn formatDiagnostic d: ty/Diagnostic -> Str
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": [" d.code "] " d.message)

fn formatDiagnosticsStep diags: (List ty/Diagnostic) idx: Int64 len: Int64 acc: (List Str) -> (List Str)
  (if (>= idx len) acc (mt (listGet diags idx) ((some d) (formatDiagnosticsStep diags (+ idx 1) len (listAppend acc (list (formatDiagnostic d))))) ((none) (formatDiagnosticsStep diags (+ idx 1) len acc))))

fn formatDiagnostics diags: (List ty/Diagnostic) -> (List Str)
  (formatDiagnosticsStep diags 0 (listLength diags) (list))

fn compileSourceToC99 src: Str path: Str isFreestanding: Bool -> CompileResult
  (mt (a/parse src) ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (CompileResult :ok false :code "" :diagnostics (list msg)))) ((ok forms) (let [(diags (chk/checkModule forms (mapEmpty) path)) (fatal diags)] (if (not (listEmpty? fatal)) (let [(formatted (formatDiagnostics fatal))] (CompileResult :ok false :code "" :diagnostics formatted)) (CompileResult :ok true :code (c99/emitCStandalone forms "" isFreestanding) :diagnostics (list))))))

fn compileSourceTarget src: Str target: Str deps: (Map Str r/ModuleSummary) path: Str -> CompileResult
  (if (or (or (= target "c99") (= target "c")) (= target "c-embedded")) (compileSourceToC99 src path (= target "c-embedded")) (CompileResult :ok false :code "" :diagnostics (list (str "Target '" target "' decoupled from core; use dynamic pluggable backend"))))

fn compileStandaloneTarget src: Str target: Str path: Str -> CompileResult
  (compileSourceTarget src target (mapEmpty) path)

fn makeExpMacro al: Str fnName: Str -> Str
  (let [(mFn (cm/mangleCIdent fnName))] (if (= fnName "main") (str "#define " al "_main dep_main\n#define " al "_asl_main dep_main") (str "#define " al "_" mFn " " mFn)))

fn collectExpDefs al: Str exps: (List Str) idx: Int64 len: Int64 acc: (List Str) -> (List Str)
  (if (>= idx len) acc (let [(fnName (optionOr (listGet exps idx) ""))] (collectExpDefs al exps (+ idx 1) len (listAppend acc (list (makeExpMacro al fnName))))))

fn collectAliasMacrosStep aliases: (List Str) importsMap: (Map Str Str) deps: (Map Str r/ModuleSummary) idx: Int64 len: Int64 acc: (List Str) -> (List Str)
  (if (>= idx len) acc (let [(al (optionOr (listGet aliases idx) ""))] (mt (mapGet importsMap al) ((none) (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len acc)) ((some modPath) (mt (mapGet deps modPath) ((none) (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len acc)) ((some s) (let [(exps s.exports) (defs (collectExpDefs al exps 0 (listLength exps) (list)))] (collectAliasMacrosStep aliases importsMap deps (+ idx 1) len (listAppend acc defs)))))))))

fn collectAllAliasMacros summaries: (List r/ModuleSummary) deps: (Map Str r/ModuleSummary) idx: Int64 len: Int64 acc: (List Str) -> (List Str)
  (if (>= idx len) acc (let [(s (optionOr (listGet summaries idx) (r/emptyModuleSummary))) (impMap s.imports) (aliases (mapKeys impMap)) (macros (collectAliasMacrosStep aliases impMap deps 0 (listLength aliases) (list)))] (collectAllAliasMacros summaries deps (+ idx 1) len (listAppend acc macros))))

fn renameTopFormMain tf: a/TopForm -> a/TopForm
  (mt tf ((a/topDefun d) (if (= d.name "main") (a/topDefun (a/DefunNode :name "dep-main" :typeVars d.typeVars :isExported d.isExported :effect d.effect :params d.params :retType d.retType :docstring d.docstring :body d.body :bodyPos d.bodyPos)) tf)) (else tf))

fn collectRenamedForms fList: (List a/TopForm) idx: Int64 len: Int64 acc: (List a/TopForm) -> (List a/TopForm)
  (if (>= idx len) acc (let [(tf (optionOr (listGet fList idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))] (collectRenamedForms fList (+ idx 1) len (listAppend acc (list (renameTopFormMain tf))))))

fn ! collectDepFormsStep depSummaries: (List r/ModuleSummary) entryFile: Str idx: Int64 len: Int64 acc: (List a/TopForm) -> (Result (List a/TopForm) Str)
  (if (>= idx len) (ok acc) (let [(s (optionOr (listGet depSummaries idx) (r/emptyModuleSummary))) (p s.path)] (if (or (= p "") (= p entryFile)) (collectDepFormsStep depSummaries entryFile (+ idx 1) len acc) (mt (fileRead p) ((err _) (err (str "Failed to read dependency file: " p))) ((ok sSrc) (mt (a/parse sSrc) ((err pe) (err (str p ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))) ((ok fList) (let [(renamedList (collectRenamedForms fList 0 (listLength fList) (list)))] (collectDepFormsStep depSummaries entryFile (+ idx 1) len (listAppend acc renamedList))))))))))

fn ! compilePackageToC99! entryFile: Str roots: (List Str) isFreestanding: Bool -> (Result CompileResult Str)
  (let [(readRes (fileRead entryFile))] (mt readRes ((err _) (err (str "Failed to read entry file: " entryFile))) ((ok entrySrc) (mt (a/parse entrySrc) ((err pe) (let [(msg (str entryFile ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (ok (CompileResult :ok false :code "" :diagnostics (list msg))))) ((ok entryForms) (let [(entrySummary (r/collectSummary entryForms entryFile)) (importPaths (r/mapValuesList entrySummary.imports)) (depsRes (r/loadModuleDeps! (cons (r/parentDirOf entryFile) roots) importPaths))] (mt depsRes ((err _) (err "Failed to load package dependencies")) ((ok deps) (let [(diags (chk/checkModule entryForms deps entryFile)) (fatal diags)] (if (not (listEmpty? fatal)) (let [(formatted (formatDiagnostics fatal))] (ok (CompileResult :ok false :code "" :diagnostics formatted))) (let [(depSummaries (mapValues deps)) (allSummaries (listAppend depSummaries (list entrySummary))) (aliasMacros (collectAllAliasMacros allSummaries deps 0 (listLength allSummaries) (list))) (macroHeader (if (listEmpty? aliasMacros) "" (str (stringJoin aliasMacros "\n") "\n\n"))) (depFormsRes (collectDepFormsStep depSummaries entryFile 0 (listLength depSummaries) (list)))] (mt depFormsRes ((err msg) (ok (CompileResult :ok false :code "" :diagnostics (list msg)))) ((ok depFormsList) (let [(allForms (listAppend depFormsList entryForms)) (cSource (str macroHeader (c99/emitCStandalone allForms "" isFreestanding)))] (ok (CompileResult :ok true :code cSource :diagnostics (list)))))))))))))))))

fn ! compilePackageToLlvm! entryFile: Str roots: (List Str) -> (Result CompileResult Str)
  (let [(readRes (fileRead entryFile))]
    (mt readRes
      ((err _) (err (str "Failed to read entry file: " entryFile)))
      ((ok entrySrc)
        (mt (a/parse entrySrc)
          ((err pe) (let [(msg (str entryFile ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (ok (CompileResult :ok false :code "" :diagnostics (list msg)))))
          ((ok entryForms)
            (let [(entrySummary (r/collectSummary entryForms entryFile))
                  (importPaths (r/mapValuesList entrySummary.imports))]
              (mt (r/loadModuleDeps! (cons (r/parentDirOf entryFile) roots) importPaths)
                ((err _) (err (str "Failed to load package dependencies of " entryFile)))
                ((ok deps)
                  (let [(diags (chk/checkModule entryForms deps entryFile)) (fatal diags)]
                    (if (not (listEmpty? fatal))
                      (ok (CompileResult :ok false :code "" :diagnostics (formatDiagnostics fatal)))
                      (mt (lk/linkEntry! entryFile)
                        ((err irDiags) (ok (CompileResult :ok false :code "" :diagnostics (formatIrDiagnostics irDiags))))
                        ((ok m)
                          (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
                            ((err irDiags) (ok (CompileResult :ok false :code "" :diagnostics (formatIrDiagnostics irDiags))))
                            ((ok llCode) (ok (CompileResult :ok true :code llCode :diagnostics (list)))))))))))))))))

fn formatIrDiagnostics diags: (List irTy/IrDiag) -> (List Str)
  (map (fn [(d irTy/IrDiag)] -> Str (str d.locus ": [" d.code "] " d.message)) diags)

fn verifyPackageCapabilities declared: (List Str) used: (List Str) -> Bool
  (let [(unauth (fold (fn [(acc (List Str)) (cap Str)] -> (List Str) (if (listContains? declared cap) acc (listAppend acc (list cap)))) (list) used))] (listEmpty? unauth))

fn eliminateDeadCapabilities sourceCode: Str requestedCaps: (List Str) -> Str
  (let [(allPlatformCaps (list "netSocket" "procSpawn" "procWait" "procSignal" "fsWatch")) (deadCaps (fold (fn [(acc (List Str)) (cap Str)] -> (List Str) (if (listContains? requestedCaps cap) acc (listAppend acc (list cap)))) (list) allPlatformCaps))] (fold (fn [(code Str) (deadCap Str)] -> Str (if (= deadCap "netSocket") (stringReplace code "asl_platform_darwin_net_socket" "/* dce */ 0") (if (= deadCap "procSpawn") (stringReplace code "asl_platform_darwin_proc_spawn" "/* dce */ 0") (if (= deadCap "fsWatch") (stringReplace code "asl_platform_darwin_fs_watch" "/* dce */ 0") code)))) sourceCode deadCaps))
