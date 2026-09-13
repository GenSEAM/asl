(module asl-compiler/compiler
  :d "Unified 100% self-hosted AgentScript compiler pipeline in pure ASL."
  :x [CompileResult compileSource compileSourceTarget compileStandaloneSource compileStandaloneTarget formatDiagnostic emitWasmBinaryTarget emitWasiBinaryTarget]
  :i [(ast :a a) (reader :a rd) (types :a ty) (check :a chk) (resolve :a r) (emit :a em) (emitC :a emC) (emitWat :a emWat) (emitGo :a emGo) (wasm :a w)])

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
  :d "Lowers top-level forms to freestanding C or Arduino sketch source."
  (let [(isArduino (= target "arduino"))
        (hdr (if isArduino (emC/emitArduinoHeader) (emC/emitCHeader)))
        (funcsList (fold (fn [(acc (List Str)) (f a/TopForm)]
                            (mt f
                              ((topDefun d)
                               (let [(infix (lowerBodyInfix (.-body d)))
                                     (body (if (string-empty? infix) "  return;" (str "  return " infix ";")))
                                     (fnDecl (emC/emitCFn (.-name d) (.-retType d) body))]
                                 (list-append acc (list fnDecl))))
                              (:else acc)))
                          (list)
                          forms))
        (hasSetup (fold (fn [(acc Bool) (f a/TopForm)]
                           (or acc (mt f ((topDefun d) (= (.-name d) "setup")) (:else false))))
                         false forms))
        (hasLoop (fold (fn [(acc Bool) (f a/TopForm)]
                          (or acc (mt f ((topDefun d) (= (.-name d) "loop")) (:else false))))
                        false forms))]
    (if isArduino
        (if (and hasSetup hasLoop)
            (str hdr "\n" (string-join funcsList "\n"))
            (str (emC/emitArduinoSketch "" (string-join funcsList "\n"))))
        (str hdr (if (list-empty? funcsList) "" (str "\n" (string-join funcsList "\n")))))))

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
             ((or (or (= target "c-embedded") (= target "arduino")) (= target "c"))
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
  (w/emitWasmBinaryTarget forms))

