(module asl-compiler/targets
  :d "Non-core multi-target backends: WAT, Go, Rust, Arduino, WASM and WASI. Held outside the self-hosting core so the bootstrap closure carries only the language and its C99 backend."
  :x [emitWatTarget
      emitGoTarget
      emitCTarget
      compileSourceTarget
      compileSource
      compileStandaloneTarget
      compileStandaloneSource
      emitWasmBinaryTarget
      emitWasiBinaryTarget]
  :i [(ast :a a) (reader :a rd) (types :a ty) (check :a chk) (resolve :a r) (compiler :a comp) (emit :a em) (emitC :a emC) (emitWat :a emWat) (emitGo :a emGo) (wasm :a w) (c99Emit :a c99)])

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

(df compileSourceTarget [(src Str) (target Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> comp/CompileResult
  :d "End-to-end compilation with target selection and dependencies."
  (mt (a/parse src)
    ((err pe)
     (let [(msg (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))]
       (comp/CompileResult :ok false :code "" :diagnostics (list msg))))
    ((ok forms)
     (let [(diags (chk/checkModule forms deps path))]
       (if (not (list-empty? diags))
           (let [(formatted (map (fn [(d ty/Diagnostic)] -> Str (comp/formatDiagnostic d)) diags))]
             (comp/CompileResult :ok false :code "" :diagnostics formatted))
           (cond
             ((or (= target "wasm-bin") (= target "wasm-binary"))
              (comp/CompileResult :ok true :code (w/emitWasmBinaryTarget forms) :diagnostics (list)))
             ((= target "wasi")
              (comp/CompileResult :ok true :code (emitWasiBinaryTarget forms) :diagnostics (list)))
             ((or (= target "wasm") (= target "wat"))
              (comp/CompileResult :ok true :code (emitWatTarget forms) :diagnostics (list)))
             ((= target "go")
              (comp/CompileResult :ok true :code (emitGoTarget forms) :diagnostics (list)))
             ((or (or (or (= target "c99") (= target "c-embedded")) (= target "arduino")) (= target "c"))
              (comp/CompileResult :ok true :code (emitCTarget forms target) :diagnostics (list)))
             ((= target "rust")
              (let [(rustSrc (em/emitRustProgram forms (list)))]
                (comp/CompileResult :ok true :code rustSrc :diagnostics (list))))
             (:else
              (comp/CompileResult :ok true :code (emitWatTarget forms) :diagnostics (list)))))))))

(df compileSource [(src Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> comp/CompileResult
  :d "End-to-end compilation defaulting to WebAssembly universal core target."
  (compileSourceTarget src "wasm" deps path))

(df compileStandaloneTarget [(src Str) (target Str) (path Str)] -> comp/CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compileSourceTarget src target (map-empty) path))

(df compileStandaloneSource [(src Str) (path Str)] -> comp/CompileResult
  :d "Compiles a standalone source file defaulting to WebAssembly universal core target."
  (compileStandaloneTarget src "wasm" path))

(df emitWasmBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly binary target string."
  (w/emitWasmBinaryTarget forms))

(df emitWasiBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly binary target string for WASI."
  (w/emitWasiBinaryTarget forms))
