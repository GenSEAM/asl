(module asl-codegen/emit
  :d "Top-level form emission, module linking, and Rust program assembly."
  :x [emit-defschema
      emit-defenum
      emit-defun
      emit-top-forms
      emit-rust-program
      merge-maps
      has-main-fn?]
  :i [(ast :a a) (mangle :a m) (rtypes :a cg-ty) (expr :a ex) (types :a ty)])

(df merge-maps [(m1 (Map String String)) (m2 (Map String String))] -> (Map String String)
  :d "Merges two maps."
  (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String)
          (map-set acc (.-first p) (.-second p)))
        m1
        (map-pairs m2)))

(df emit-generic-params [(tvars (List String))] -> String
  :d "Emits generic type parameter clause with Clone bound."
  (if (> (list-length tvars) 0)
      (str "<" (string-join (map (fn [(v String)] -> String (str v ": Clone")) tvars) ", ") ">")
      ""))

(df type-list-flags [(name String) (tys (List ty/Type))] -> (Pair Bool Bool)
  :d "Checks a list of types for IoError and Float64 containment."
  (let [(has-io (fold (fn [(acc Bool) (t ty/Type)] (or acc (cg-ty/type-mentions-io-error? t))) false tys))
        (has-float (or (or (= name "Token") (= name "TokenType"))
                       (fold (fn [(acc Bool) (t ty/Type)] (or acc (cg-ty/type-mentions-float? t))) false tys)))]
    (pair has-io has-float)))

(df schema-flags [(s a/SchemaNode)] -> (Pair Bool Bool)
  :d "Computes IoError and Float64 containment flags for a schema."
  (let [(f-tys (map (fn [(f a/AstField)] -> ty/Type
                      (ty/parse-type-str (.-type f) (list)))
                    (.-fields s)))]
    (type-list-flags (.-name s) f-tys)))

(df enum-flags [(e a/EnumNode)] -> (Pair Bool Bool)
  :d "Computes IoError and Float64 containment flags for an enum."
  (let [(name (.-name e))
        (cases (.-cases e))]
    (fold (fn [(acc (Pair Bool Bool)) (c a/EnumCase)] -> (Pair Bool Bool)
            (let [(p-tys (map (fn [(p a/Param)] -> ty/Type
                                (ty/parse-type-str (.-type p) (list)))
                              (.-fields c)))
                  (c-flags (type-list-flags name p-tys))]
              (pair (or (.-first acc) (.-first c-flags))
                    (or (.-second acc) (.-second c-flags)))))
          (pair false false)
          cases)))

(df emit-defschema [(s a/SchemaNode)] -> String
  :d "Emits a Rust struct definition with derives and fields."
  (let [(name (.-name s))
        (gen-str (emit-generic-params (.-type-vars s)))
        (flags (schema-flags s))
        (derives (cg-ty/emit-derives (.-first flags) (.-second flags)))
        (f-strs (map (fn [(f a/AstField)] -> String
                       (let [(f-name (m/mangle-ident (.-name f)))
                             (f-ty (cg-ty/emit-type-str (.-type f)))]
                         (str "    pub " f-name ": " f-ty ",\n")))
                     (.-fields s)))]
    (str derives "\npub struct " name gen-str " {\n" (string-join f-strs "") "}\n")))

(df emit-defenum [(e a/EnumNode)] -> String
  :d "Emits a Rust enum definition with derives and cases."
  (let [(name (.-name e))
        (gen-str (emit-generic-params (.-type-vars e)))
        (flags (enum-flags e))
        (derives (cg-ty/emit-derives (.-first flags) (.-second flags)))
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
        (gen-str (emit-generic-params (.-type-vars d)))
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

(df collect-module-enums [(m a/ModuleNode)] -> (Map String String)
  :d "Collects all qualified and unqualified enum variant names defined in a module."
  (let [(m-path (.-path m))
        (r-mod (m/rust-mod-name m-path))
        (short-mod (m/short-mod-name m-path))]
    (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String)
            (mt top
              ((a/top-enum e)
               (let [(e-name (m/pascal-ident (.-name e)))
                     (cases (.-cases e))]
                 (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                         (let [(c-name (.-name c))
                               (p-cname (m/pascal-ident c-name))
                               (tgt (str "crate::" r-mod "::" e-name "::" p-cname))
                               (cacc1 (map-set cacc (str m-path "/" c-name) tgt))
                               (cacc2 (map-set cacc1 (str short-mod "/" c-name) tgt))]
                           (map-set cacc2 c-name (str e-name "::" p-cname))))
                       acc
                       cases)))
              (_ acc)))
          (map-empty)
          (.-defs m))))

(df collect-all-enums [(root-defs (List a/TopForm)) (deps (List a/TopForm))] -> (Map String String)
  :d "Collects enum variants across root declarations and dependencies."
  (let [(dep-maps (map (fn [(top a/TopForm)] -> (Map String String)
                         (mt top
                           ((a/top-module m) (collect-module-enums m))
                           (_ (map-empty))))
                       deps))
        (root-map (fold (fn [(acc (Map String String)) (top a/TopForm)] -> (Map String String)
                          (mt top
                            ((a/top-enum e)
                             (let [(e-name (m/pascal-ident (.-name e)))
                                   (cases (.-cases e))]
                               (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                                       (let [(c-name (.-name c))
                                             (p-cname (m/pascal-ident c-name))]
                                         (map-set cacc c-name (str e-name "::" p-cname))))
                                     acc
                                     cases)))
                            (_ acc)))
                        (map-empty)
                        root-defs))]
    (fold (fn [(acc (Map String String)) (m (Map String String))] -> (Map String String)
            (merge-maps acc m))
          root-map
          dep-maps)))

(df emit-module [(m a/ModuleNode) (all-enums (Map String String))] -> String
  :d "Emits a nested Rust module for a dependency."
  (let [(modname (m/rust-mod-name (.-path m)))
        (mod-aliases (build-aliases-map (.-imports m)))
        (merged-aliases (merge-maps all-enums mod-aliases))
        (use-aliases (map (fn [(im (Pair String String))] -> String
                            (let [(mpath (.-first im))
                                  (alias (.-second im))
                                  (r-mod (m/rust-mod-name mpath))]
                              (if (not (= alias r-mod))
                                  (str "    #[allow(unused_imports)]\n    pub use crate::" r-mod " as " (m/mangle-ident alias) ";\n")
                                  "")))
                          (.-imports m)))
        (body (emit-top-forms (.-defs m) merged-aliases all-enums))]
    (str "pub mod " modname " {\n"
         "    #![allow(dead_code, unused_variables, unused_mut, unused_parens)]\n"
         "    #[allow(unused_imports)]\n"
         "    use super::rt;\n"
         (string-join use-aliases "")
         "\n"
         body
         "\n}\n")))

(df emit-top-forms [(defs (List a/TopForm)) (aliases (Map String String)) (all-enums (Map String String))] -> String
  :d "Emits all top forms declared in a list of TopForm."
  (let [(rendered-defs (map (fn [(top a/TopForm)] -> String
                              (mt top
                                ((a/top-schema s) (emit-defschema s))
                                ((a/top-enum e) (emit-defenum e))
                                ((a/top-defun d) (emit-defun d aliases))
                                ((a/top-module m) (emit-module m all-enums))))
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

(df emit-use-alias [(src-mod String) (tgt-alias String)] -> String
  :d "Emits a pub use self statement if alias differs from source module."
  (if (not (= src-mod tgt-alias))
      (str "#[allow(unused_imports)]\npub use self::" src-mod " as " tgt-alias ";\n")
      ""))

(df emit-rust-program [(root-forms (List a/TopForm)) (deps (List a/TopForm))] -> String
  :d "Assembles complete standalone Rust source file with runtime link."
  (let [(header "#![allow(dead_code, unused_variables, unused_mut, unused_parens)]\nmod rt;\n\n")
        (info (extract-module-info root-forms))
        (root-aliases (.-first info))
        (defs (.-first (.-second info)))
        (has-main (.-second (.-second info)))
        (all-enums (collect-all-enums defs deps))
        (merged-root-aliases (merge-maps all-enums root-aliases))
        (dep-rendered (if (> (list-length deps) 0)
                          (str (emit-top-forms deps (map-empty) all-enums) "\n\n")
                          ""))
        (root-use-aliases (if (> (list-length deps) 0)
                              (let [(use-lines (map (fn [(top a/TopForm)] -> String
                                                      (mt top
                                                        ((a/top-module m)
                                                         (let [(r-mod (m/rust-mod-name (.-path m)))
                                                               (s-mod (m/short-mod-name (.-path m)))]
                                                           (str "#[allow(unused_imports)]\npub use self::" r-mod "::*;\n"
                                                                (emit-use-alias r-mod s-mod))))
                                                        (_ "")))
                                                    deps))
                                    (alias-lines (map (fn [(p (Pair String String))] -> String
                                                        (emit-use-alias (m/short-mod-name (.-second p))
                                                                        (m/mangle-ident (.-first p))))
                                                      (map-pairs root-aliases)))]
                                (str (string-join use-lines "") (string-join alias-lines "") "\n"))
                              ""))
        (root-body (emit-top-forms defs merged-root-aliases all-enums))
        (entry (emit-host-entry has-main))]
    (str header dep-rendered root-use-aliases root-body entry)))
