(module asl-compiler/compiler
  :d "Unified 100% self-hosted AgentScript compiler pipeline in pure ASL."
  :x [CompileResult compile-source compile-source-target compile-standalone-source compile-standalone-target format-diagnostic]
  :i [(ast :a a) (reader :a rd) (types :a ty) (check :a chk) (resolve :a r) (emit :a em) (emit-c :a em-c) (emit-wat :a em-wat) (emit-go :a em-go)])

(dfs CompileResult
  (:f ok Bool "True if compilation succeeded without errors")
  (:f code Str "Generated standalone target source code")
  (:f diagnostics (List Str) "List of error messages if compilation failed"))

(df format-diagnostic [(d ty/Diagnostic)] -> Str
  :d "Formats a checker diagnostic into standard line:col: message format."
  (str (.-path d) ":" (string-from-int64 (.-line d)) ":" (string-from-int64 (.-col d)) ": [" (.-code d) "] " (.-message d)))

(df sexpr-to-atom [(s rd/SExpr)] -> Str
  :d "Extracts atom string value from SExpr."
  (mt s
    ((sexpr-atom v) v)
    ((sexpr-list items)
     (if (list-empty? items) "" (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom "")))))
    ((sexpr-vect items)
     (if (list-empty? items) "" (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom "")))))))

(df lower-body-infix [(body-list (List rd/SExpr))] -> Str
  :d "Lowers S-expression body list into infix expression string."
  (if (list-empty? body-list)
      ""
      (let [(first-expr (option-or (list-get body-list 0) (rd/make-atom "")))]
        (mt first-expr
          ((sexpr-atom v) v)
          ((sexpr-list items)
           (cond
             ((>= (list-length items) 3)
              (let [(op (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom ""))))
                    (lhs (sexpr-to-atom (option-or (list-get items 1) (rd/make-atom ""))))
                    (rhs (sexpr-to-atom (option-or (list-get items 2) (rd/make-atom ""))))]
                (str lhs " " op " " rhs)))
             ((= (list-length items) 2)
              (let [(op (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom ""))))
                    (arg (sexpr-to-atom (option-or (list-get items 1) (rd/make-atom ""))))]
                (str op arg)))
             ((= (list-length items) 1)
              (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom ""))))
             (:else "")))
          ((sexpr-vect _) "")))))

(df lower-body-wat [(body-list (List rd/SExpr)) (ret-ty Str)] -> Str
  :d "Lowers S-expression body list into WebAssembly Text instructions."
  (if (list-empty? body-list)
      (let [(w-ret (em-wat/wat-type ret-ty))]
        (if (= w-ret "void") "" (str "  (" w-ret ".const 0)")))
      (let [(first-expr (option-or (list-get body-list 0) (rd/make-atom "")))]
        (mt first-expr
          ((sexpr-atom v)
           (if (or (string-starts-with? v "-")
                   (and (>= (option-or (string-slice v 0 1) "") "0")
                        (<= (option-or (string-slice v 0 1) "") "9")))
               (str "  " (em-wat/wat-const v ret-ty))
               (str "  " (em-wat/wat-get v))))
          ((sexpr-list items)
           (cond
             ((>= (list-length items) 3)
              (let [(op (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom ""))))
                    (lhs (sexpr-to-atom (option-or (list-get items 1) (rd/make-atom ""))))
                    (rhs (sexpr-to-atom (option-or (list-get items 2) (rd/make-atom ""))))]
                (str "  " (em-wat/emit-wat-expr op lhs rhs ret-ty))))
             ((= (list-length items) 1)
              (let [(v (sexpr-to-atom (option-or (list-get items 0) (rd/make-atom ""))))]
                (str "  " (em-wat/wat-get v))))
             (:else
              (let [(w-ret (em-wat/wat-type ret-ty))]
                (if (= w-ret "void") "" (str "  (" w-ret ".const 0)"))))))
          ((sexpr-vect _)
           (let [(w-ret (em-wat/wat-type ret-ty))]
             (if (= w-ret "void") "" (str "  (" w-ret ".const 0)"))))))))

(df emit-wat-target [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to WebAssembly Text module."
  (let [(fn-defs (fold (fn [(acc (List Str)) (f a/TopForm)]
                         (mt f
                           ((top-defun d)
                            (let [(params-wat (string-join (map (fn [(p a/Param)] -> Str
                                                                  (str "(param $" (.-name p) " " (em-wat/wat-type (.-type p)) ")"))
                                                                (.-params d)) " "))
                                  (body (lower-body-wat (.-body d) (.-ret-type d)))
                                  (fn-str (em-wat/wat-fn (.-name d) params-wat (.-ret-type d) body true))]
                              (list-append acc (list (str "  " fn-str)))))
                           (:else acc)))
                       (list)
                       forms))
        (all-funcs (if (list-empty? fn-defs)
                       "  (func $main (result i64)\n    (i64.const 0))\n"
                       (str (string-join fn-defs "\n") "\n")))]
    (em-wat/emit-wat-module all-funcs true)))

(df emit-go-target [(forms (List a/TopForm))] -> Str
  :d "Lowers top-level forms to idiomatic Go package."
  (let [(structs-list (fold (fn [(acc (List Str)) (f a/TopForm)]
                              (mt f
                                ((top-schema s)
                                 (let [(fields (string-join (map (fn [(fld a/AstField)] -> Str
                                                                   (let [(fname (string-upper (option-or (string-slice (.-name fld) 0 1) "")))]
                                                                     (str "\t" fname (option-or (string-slice (.-name fld) 1 (string-length (.-name fld))) "") " " (em-go/emit-go-type (.-type fld)) "\n")))
                                                                 (.-fields s)) ""))
                                       (st-decl (em-go/emit-go-struct (.-name s) fields))]
                                   (list-append acc (list st-decl))))
                                ((top-enum e)
                                 (let [(cases (map (fn [(c a/EnumCase)] -> Str (.-name c)) (.-cases e)))
                                       (enum-decl (em-go/emit-go-enum (.-name e) cases))]
                                   (list-append acc (list enum-decl))))
                                (:else acc)))
                            (list)
                            forms))
        (funcs-list (fold (fn [(acc (List Str)) (f a/TopForm)]
                            (mt f
                              ((top-defun d)
                               (let [(p-str (string-join (map (fn [(p a/Param)] -> Str
                                                                (str (.-name p) " " (em-go/emit-go-type (.-type p))))
                                                              (.-params d)) ", "))
                                     (r-ty (em-go/emit-go-type (.-ret-type d)))
                                     (infix (lower-body-infix (.-body d)))
                                     (body (if (= r-ty "") "" (if (string-empty? infix) (if (= r-ty "bool") "return true" (if (= r-ty "string") "return \"\"" "return 0")) (str "return " infix))))
                                     (fn-decl (em-go/emit-go-fn (.-name d) p-str (.-ret-type d) body true))]
                                 (list-append acc (list fn-decl))))
                              (:else acc)))
                          (list)
                          forms))
        (has-main (fold (fn [(acc Bool) (f a/TopForm)]
                          (or acc (mt f
                                    ((top-defun d) (or (= (string-lower (.-name d)) "main") (= (.-name d) "Main")))
                                    (:else false))))
                        false
                        forms))
        (all-funcs (if has-main
                       (string-join funcs-list "\n")
                       (str (string-join funcs-list "\n") (if (list-empty? funcs-list) "" "\n") "func Main() int64 {\n\treturn 0\n}\n")))]
    (em-go/emit-go-program "main" (string-join structs-list "\n") all-funcs)))

(df emit-c-target [(forms (List a/TopForm)) (target Str)] -> Str
  :d "Lowers top-level forms to freestanding C or Arduino sketch source."
  (let [(is-arduino (= target "arduino"))
        (hdr (if is-arduino (em-c/emit-arduino-header) (em-c/emit-c-header)))
        (funcs-list (fold (fn [(acc (List Str)) (f a/TopForm)]
                            (mt f
                              ((top-defun d)
                               (let [(infix (lower-body-infix (.-body d)))
                                     (body (if (string-empty? infix) "  return;" (str "  return " infix ";")))
                                     (fn-decl (em-c/emit-c-fn (.-name d) (.-ret-type d) body))]
                                 (list-append acc (list fn-decl))))
                              (:else acc)))
                          (list)
                          forms))
        (has-setup (fold (fn [(acc Bool) (f a/TopForm)]
                           (or acc (mt f ((top-defun d) (= (.-name d) "setup")) (:else false))))
                         false forms))
        (has-loop (fold (fn [(acc Bool) (f a/TopForm)]
                          (or acc (mt f ((top-defun d) (= (.-name d) "loop")) (:else false))))
                        false forms))]
    (if is-arduino
        (if (and has-setup has-loop)
            (str hdr "\n" (string-join funcs-list "\n"))
            (str (em-c/emit-arduino-sketch "" (string-join funcs-list "\n"))))
        (str hdr (if (list-empty? funcs-list) "" (str "\n" (string-join funcs-list "\n")))))))

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
           (cond
             ((or (= target "wasm") (= target "wat"))
              (CompileResult :ok true :code (emit-wat-target forms) :diagnostics (list)))
             ((= target "go")
              (CompileResult :ok true :code (emit-go-target forms) :diagnostics (list)))
             ((or (or (= target "c-embedded") (= target "arduino")) (= target "c"))
              (CompileResult :ok true :code (emit-c-target forms target) :diagnostics (list)))
             ((= target "rust")
              (let [(rust-src (em/emit-rust-program forms (list)))]
                (CompileResult :ok true :code rust-src :diagnostics (list))))
             (:else
              (CompileResult :ok true :code (emit-wat-target forms) :diagnostics (list)))))))))

(df compile-source [(src Str) (deps (Map Str r/ModuleSummary)) (path Str)] -> CompileResult
  :d "End-to-end compilation defaulting to WebAssembly universal core target."
  (compile-source-target src "wasm" deps path))

(df compile-standalone-target [(src Str) (target Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file for a specific target with no external dependencies."
  (compile-source-target src target (map-empty) path))

(df compile-standalone-source [(src Str) (path Str)] -> CompileResult
  :d "Compiles a standalone source file defaulting to WebAssembly universal core target."
  (compile-standalone-target src "wasm" path))
