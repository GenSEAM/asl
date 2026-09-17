(module asl-compiler/targets
  :d "Pluggable target dispatch compatibility layer under ADR D93. Non-core backends are decoupled from core compiler."
  :x [compileSourceTarget
      compileSource
      compileStandaloneTarget
      compileStandaloneSource]
  :i [(ast :a a) (reader :a rd) (types :a ty) (check :a chk) (resolve :a r) (compiler :a comp) (c99Emit :a c99)])

(df compileSourceTarget [(src Str) (target Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> comp/CompileResult
  :d "End-to-end compilation with target selection and dependencies under ADR D93."
  (if (or (or (= target "c99") (= target "c")) (= target "c-embedded"))
      (mt (a/parse src)
        ((err pe)
         (let [(msg (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
           (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
        ((ok forms)
         (let [(diags (chk/checkModule forms deps path))]
           (if (not (list-empty? diags))
               (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))]
                 (comp/CompileResult :ok false :code "" :diagnostics formatted))
               (comp/CompileResult :ok true :code (c99/emitCStandalone forms "" (= target "c-embedded")) :diagnostics (list))))))
      (comp/CompileResult :ok false :code "" :diagnostics (list (str "Target '" target "' decoupled from core; use dynamic pluggable backend")))))

(df compileSource [(src Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> comp/CompileResult
  :d "End-to-end compilation defaulting to C99 core target."
  (compileSourceTarget src "c99" deps path))

(df compileStandaloneTarget [(src Str) (target Str) (path Str)] -> comp/CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compileSourceTarget src target (map-empty) path))

(df compileStandaloneSource [(src Str) (path Str)] -> comp/CompileResult
  :d "Compiles a standalone source file defaulting to C99 core target."
  (compileStandaloneTarget src "c99" path))
