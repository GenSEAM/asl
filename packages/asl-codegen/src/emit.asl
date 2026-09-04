(module asl-codegen/emit
  :d "Top-level form emission, module linking, and Rust program assembly."
  :x [emit-defschema
      emit-defenum
      emit-defun
      emit-module
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

(df has-main-fn? [(m a/ModuleNode)] -> Bool
  :d "True if module contains a top-level function named main."
  (let [(defs (.-defs m))
        (mains (filter (fn [(top a/TopForm)] -> Bool
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

(df emit-module [(m a/ModuleNode)] -> String
  :d "Emits all top forms declared in an ASL module."
  (let [(aliases (build-aliases-map (.-imports m)))
        (rendered-defs (map (fn [(top a/TopForm)] -> String
                              (mt top
                                ((a/top-schema s) (emit-defschema s))
                                ((a/top-enum e) (emit-defenum e))
                                ((a/top-defun d) (emit-defun d aliases))
                                ((a/top-module _) "")))
                            (.-defs m)))]
    (string-join rendered-defs "\n")))

(df emit-rust-program [(root a/ModuleNode) (deps (List a/ModuleNode))] -> String
  :d "Assembles complete standalone Rust source file with runtime link and dependencies."
  (let [(header "#![allow(dead_code, unused_variables, unused_mut, unused_parens)]\nmod rt;\n\n")
        (dep-modules (map (fn [(dep a/ModuleNode)] -> String
                            (let [(mod-name (m/rust-mod-name (.-path dep)))
                                  (body (emit-module dep))]
                              (str "pub mod " mod-name " {\n"
                                   "    #![allow(dead_code, unused_variables, unused_mut, unused_parens)]\n"
                                   "    #[allow(unused_imports)]\n"
                                   "    use super::rt;\n\n"
                                   body "\n}\n\n")))
                          deps))
        (root-body (emit-module root))
        (entry (emit-host-entry (has-main-fn? root)))]
    (str header (string-join dep-modules "") root-body entry)))
