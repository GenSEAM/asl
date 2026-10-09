(module asl-compiler/targets :x [compileSourceTarget compileSource compileStandaloneTarget compileStandaloneSource transpileTarget] :i [(asl-parser/ast :a a) (reader :a rd) (asl-checker/types :a ty) (check :a chk) (resolve :a r) (compiler :a comp) (c99Emit :a c99) (asl-target-c :a c11) (asl-target-llvm/main :a llvm) (asl-target-swift/emitSwift :a sw) (asl-target-rs/emitRust :a rsCg) (asl-target-sh/lower :a shLow)])

fn targetEntryName forms: (List a/TopForm) -> Str
  (let [(defNames (fold (fn [(acc (List Str)) (tf a/TopForm)] (mt tf ((a/topDefun d) (listAppend acc (list d.name))) (else acc))) (list) forms))]
    (cond
      ((listContains? defNames "entry") "entry")
      ((listContains? defNames "run") "run")
      (else "entry")))

fn compileSourceTarget src: Str target: Str deps: (Map Str r/ModuleSummary) path: Str preludeSrc: Str -> comp/CompileResult
  (if (or (= target "sh") (= target "shell"))
    (mt (a/parse src)
      ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
      ((ok forms)
        (let [(diags (chk/checkModule forms deps path))]
          (if (not (listEmpty? diags))
            (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
            (comp/CompileResult :ok true :code (shLow/emitShSourceFromForms forms path) :diagnostics (list))))))
    (if (or (= target "rs") (= target "rust"))
      (mt (a/parse src)
        ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
        ((ok forms)
          (let [(diags (chk/checkModule forms deps path))]
            (if (not (listEmpty? diags))
              (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
              (comp/CompileResult :ok true :code (rsCg/emitRustSourceFromForms forms path) :diagnostics (list))))))
    (if (or (= target "swift") (= target "swift6"))
      (mt (a/parse src)
        ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
        ((ok forms)
          (let [(diags (chk/checkModule forms deps path))]
            (if (not (listEmpty? diags))
              (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
              (comp/CompileResult :ok true :code (sw/emitSwiftSourceFromForms forms path) :diagnostics (list))))))
      (if (or (= target "llvm") (= target "ll"))
        (mt (a/parse src)
          ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
          ((ok forms)
            (let [(diags (chk/checkModule forms deps path))]
              (if (not (listEmpty? diags))
                (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
                (let [(entry (targetEntryName forms))]
                  (mt (llvm/emitLlvmSourceWith src preludeSrc entry)
                    ((ok llCode) (comp/CompileResult :ok true :code llCode :diagnostics (list)))
                    ((err errM) (comp/CompileResult :ok false :code "" :diagnostics (comp/formatIrDiagnostics errM)))))))))
        (if (or (or (= target "c99") (= target "c")) (= target "c-embedded"))
          (mt (a/parse src)
            ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
            ((ok forms)
              (let [(diags (chk/checkModule forms deps path))]
                (if (not (listEmpty? diags))
                  (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
                  (comp/CompileResult :ok true :code (c99/emitCStandalone forms "" (= target "c-embedded")) :diagnostics (list))))))
          (if (= target "c11")
            (mt (a/parse src)
              ((err pe) (let [(msg (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))] (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
              ((ok forms)
                (let [(diags (chk/checkModule forms deps path))]
                  (if (not (listEmpty? diags))
                    (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))] (comp/CompileResult :ok false :code "" :diagnostics formatted))
                    (mt (c11/emitC11SourceWith src preludeSrc path)
                      ((ok cCode) (comp/CompileResult :ok true :code cCode :diagnostics (list)))
                      ((err errM) (comp/CompileResult :ok false :code "" :diagnostics (list errM))))))))
            (comp/CompileResult :ok false :code "" :diagnostics (list (str "Target '" target "' decoupled from core; use dynamic pluggable backend")))))))))


fn compileSource src: Str deps: (Map Str r/ModuleSummary) path: Str -> comp/CompileResult
  (compileSourceTarget src "c99" deps path "")

fn compileStandaloneTarget src: Str target: Str path: Str preludeSrc: Str -> comp/CompileResult
  (compileSourceTarget src target (mapEmpty) path preludeSrc)

fn compileStandaloneSource src: Str path: Str -> comp/CompileResult
  (compileStandaloneTarget src "c99" path "")

fn transpileTarget target: Str path: Str src: Str preludeSrc: Str -> Str
  (let [(res (compileSourceTarget src target (mapEmpty) path preludeSrc))]
    (if res.ok
      res.code
      (str "# Compilation Error: " (stringJoin res.diagnostics "\n"))))
