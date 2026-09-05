(module asl-compiler/compiler
  :d "Unified 100% self-hosted AgentScript compiler pipeline in pure ASL."
  :x [CompileResult compile-source compile-source-target compile-standalone-source compile-standalone-target format-diagnostic]
  :i [(ast :a a) (types :a ty) (check :a chk) (resolve :a r) (emit :a em) (emit-c :a em-c)])

(dfs CompileResult
  (:f ok Bool "True if compilation succeeded without errors")
  (:f code Str "Generated standalone target source code")
  (:f diagnostics (List Str) "List of error messages if compilation failed"))

(df format-diagnostic [(d ty/Diagnostic)] -> Str
  :d "Formats a checker diagnostic into standard line:col: message format."
  (str (.-path d) ":" (string-from-int64 (.-line d)) ":" (string-from-int64 (.-col d)) ": [" (.-code d) "] " (.-message d)))

(df compile-source-target [(src Str) (target Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "End-to-end compilation with target selection and dependencies."
  (mt (a/parse src)
    ((err pe)
     (let [(msg (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
       (CompileResult :ok false :code "" :diagnostics (list msg))))
    ((ok forms)
     (let [(diags (chk/check-module forms deps path))]
       (if (not (list-empty? diags))
           (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (format-diagnostic d)) diags))]
             (CompileResult :ok false :code "" :diagnostics formatted))
           (if (or (= target "c-embedded") (= target "arduino"))
               (let [(c-hdr (em-c/emit-c-header))]
                 (CompileResult :ok true :code (str c-hdr "/* ASL Embedded C Target */\n") :diagnostics (list)))
               (let [(rust-src (em/emit-rust-program forms (list)))]
                 (CompileResult :ok true :code rust-src :diagnostics (list)))))))))

(df compile-source [(src Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "End-to-end compilation defaulting to Rust/Wasm target."
  (compile-source-target src "rust" deps path))

(df compile-standalone-target [(src Str) (target Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compile-source-target src target (map-empty) path))

(df compile-standalone-source [(src Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file defaulting to Rust/Wasm target."
  (compile-standalone-target src "rust" path))
