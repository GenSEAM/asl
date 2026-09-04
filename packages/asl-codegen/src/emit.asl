(module asl-codegen/emit
  :d "Top-level form emission, module linking, and Rust program assembly."
  :x [emit-defschema
      emit-defenum
      emit-defun
      emit-top-forms
      emit-rust-program
      has-main-fn?]
  :i [(ast :a a) (mangle :a m) (rtypes :a cg-ty) (expr :a ex)])

(df emit-defschema [(s a/SchemaNode)] -> String
  :d "Emits a Rust struct definition with derives and fields."
  (let [(name (.-name s))
        (tvars (.-type-vars s))
        (gen-str (if (> (list-length tvars) 0)
                     (str "<" (string-join (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">")
                     ""))
        (derives (cg-ty/emit-derives false false))
        (f-strs (map (fn [(f a/AstField)] -> String
                       (let [(f-name (m/mangle-ident (.-name f)))
                             (f-ty (cg-ty/emit-type-str (.-type f)))]
                         (str "    pub " f-name ": " f-ty ",\n")))
                     (.-fields s)))]
    (str derives "\npub struct " name gen-str " {\n" (string-join f-strs "") "}\n")))

(df emit-defenum [(e a/EnumNode)] -> String
  :d "Emits a Rust enum definition with derives and cases."
  (let [(name (.-name e))
        (tvars (.-type-vars e))
        (gen-str (if (> (list-length tvars) 0)
                     (str "<" (string-join (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">")
                     ""))
        (derives (cg-ty/emit-derives false false))
        (case-strs (map (fn [(c a/EnumCase)] -> String
                          (let [(c-name (m/pascal-ident (.-name c)))
                                (fields (.-fields c))]
                            (if (<= (list-length fields) 0)
                                (str "    " c-name ",\n")
                                (let [(f-tys (map (fn [(p a/Param)] -> String
                                                    (cg-ty/emit-type-str (.-type p)))
                                                  fields))]
                                  (str "    " c-name "(" (string-join f-tys ", ") "),\n")))))
                        (.-cases e)))]
    (str derives "\npub enum " name gen-str " {\n" (string-join case-strs "") "}\n")))

(df emit-defun [(d a/DefunNode) (aliases (Map String String))] -> String
  :d "Emits a Rust public function with parameter types and body."
  (let [(name (m/mangle-ident (.-name d)))
        (tvars (.-type-vars d))
        (gen-str (if (> (list-length tvars) 0)
                     (str "<" (string-join (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">")
                     ""))
        (params (map (fn [(p a/Param)] -> String
                       (let [(p-name (m/mangle-ident (.-name p)))
                             (p-ty (cg-ty/emit-type-str (.-type p)))]
                         (str p-name ": " p-ty)))
                     (.-params d)))
        (args-str (string-join params ", "))
        (ret-str (cg-ty/emit-type-str (.-ret-type d)))
        (body-str (ex/emit-body-seq (.-body d) aliases))]
    (str "pub fn " name gen-str "(" args-str ") -> " ret-str " {\n    " body-str "\n}\n")))

(df has-main-fn? [(defs (List a/TopForm))] -> Bool
  :d "True if declarations contain a top-level function named main."
  (let [(mains (filter (fn [(top a/TopForm)] -> Bool
                         (mt top
                           ((a/top-defun d) (= (.-name d) "main"))
                           (_ false)))
                       defs))]
    (> (list-length mains) 0)))

(df emit-host-entry [(has-main Bool)] -> String
  :d "Emits standard process entry point if program defines main."
  (if has-main
      "\nfn main() {\n    let args: Vec<String> = std::env::args().skip(1).collect();\n    std::process::exit(rt::main_exit(main_(args)));\n}\n"
      ""))

(df build-aliases-map [(imports (List (Pair String String)))] -> (Map String String)
  :d "Constructs alias -> module path lookup map from module imports."
  (fold (fn [(acc (Map String String)) (im (Pair String String))] -> (Map String String)
          (map-set acc (.-second im) (.-first im)))
        (map-empty)
        imports))

(df emit-top-forms [(defs (List a/TopForm)) (aliases (Map String String))] -> String
  :d "Emits all top forms declared in a list of TopForm."
  (let [(rendered-defs (map (fn [(top a/TopForm)] -> String
                              (mt top
                                ((a/top-schema s) (emit-defschema s))
                                ((a/top-enum e) (emit-defenum e))
                                ((a/top-defun d) (emit-defun d aliases))
                                ((a/top-module m) (emit-top-forms (.-defs m) (build-aliases-map (.-imports m))))))
                            defs))]
    (string-join rendered-defs "\n")))

(df extract-module-info [(forms (List a/TopForm))] -> (Pair (Map String String) (Pair (List a/TopForm) Bool))
  :d "Extracts aliases, declarations, and has-main flag from forms."
  (if (<= (list-length forms) 0)
      (pair (map-empty) (pair (list) false))
      (let [(first-form (option-or (list-get forms 0) (a/top-schema (a/SchemaNode :name "" :type-vars (list) :fields (list) :json-case (none)))))]
        (mt first-form
          ((a/top-module m)
           (let [(aliases (build-aliases-map (.-imports m)))
                 (defs (.-defs m))
                 (hm (has-main-fn? defs))]
             (pair aliases (pair defs hm))))
          (_
           (let [(defs forms)
                 (hm (has-main-fn? defs))]
             (pair (map-empty) (pair defs hm))))))))

(df emit-rust-program [(root-forms (List a/TopForm)) (deps (List a/TopForm))] -> String
  :d "Assembles complete standalone Rust source file with runtime link."
  (let [(header "#![allow(dead_code, unused_variables, unused_mut, unused_parens)]\nmod rt;\n\n")
        (dep-rendered (if (> (list-length deps) 0)
                          (str (emit-top-forms deps (map-empty)) "\n\n")
                          ""))
        (info (extract-module-info root-forms))
        (aliases (.-first info))
        (defs (.-first (.-second info)))
        (has-main (.-second (.-second info)))
        (root-body (emit-top-forms defs aliases))
        (entry (emit-host-entry has-main))]
    (str header dep-rendered root-body entry)))
