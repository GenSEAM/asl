(module asl-checker/resolve
  :d "Pass 1 & Pass 2 Symbol Resolution, Module Scoping, and Semantic Rules."
  :x [FunSummary SchemaSummary EnumSummary CaseSummary FieldSummary ModuleSummary
      clean-num-sign
      collect-summary
      first-char-str
      first-expr-empty
      first-expr-unit
      first-expr-vect
      first-head-ident
      first-vect-items
      is-literal-atom?
      list-append-one
      load-module-deps!
      map-values-list
      mod-enum
      mod-fun
      mod-import
      mod-schema
      resolve-module
      safe-tail
      second-expr-empty
      sexpr-to-list
      slice-from]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

(dfs FunSummary
  (:f name String "Function name")
  (:f params (List (Pair String String)) "Parameter name and type pairs")
  (:f ret String "Return type annotation")
  (:f typevars (List String) "Type variables bound in signature")
  (:f has-doc Bool "True if docstring is present")
  (:f effect Bool "True if marked with !"))

(dfs FieldSummary
  (:f name String "Field name")
  (:f type String "Field type annotation")
  (:f has-default Bool "True if field has default"))

(dfs SchemaSummary
  (:f name String "Schema name")
  (:f typevars (List String) "Bound type variables")
  (:f fields (List FieldSummary) "Schema fields"))

(dfs CaseSummary
  (:f name String "Enum case name")
  (:f params (List (Pair String String)) "Case parameters"))

(dfs EnumSummary
  (:f name String "Enum name")
  (:f typevars (List String) "Bound type variables")
  (:f cases (List CaseSummary) "Enum cases"))

(dfs ModuleSummary
  (:f name String "Module name")
  (:f path String "Source file path")
  (:f has-header Bool "True if header form exists")
  (:f has-doc Bool "True if module docstring exists")
  (:f exports (List String) "Exported function names")
  (:f exported-types (List String) "Exported PascalCase type names")
  (:f imports (Map String String) "Import alias to module path mapping")
  (:f funs (Map String FunSummary) "Function summaries")
  (:f schemas (Map String SchemaSummary) "Schema summaries")
  (:f enums (Map String EnumSummary) "Enum summaries")
  (:f case-owner (Map String String) "Case name to owning enum name mapping")
  (:f exported-cases (Map String String) "Exported case name to enum name mapping")
  (:f exported-fields (Map String Bool) "Exported record field names"))

(df first-char-str [(s String)] -> String
  :d "Returns first character of string as string, or empty string."
  (mt (string-slice s 0 1) ((some c) c) ((none) "")))

(df slice-from [(s String) (start Int64)] -> String
  :d "Slices string from start to end, defaulting to full string if out of range."
  (mt (string-slice s start (string-length s)) ((some sub) sub) ((none) s)))

(df is-pascal-name? [(s String)] -> Bool
  (if (string-empty? s)
    false
    (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (first-char-str s))))

(df is-qualified-name? [(s String)] -> Bool
  (and (not (= s "/"))
       (and (not (string-starts-with? s "/"))
            (string-contains? s "/"))))

(df make-diag [(code String) (msg String) (path String)] -> ty/Diagnostic
  (ty/Diagnostic :code code :message msg :line 1 :col 1 :path path))

(df collect-fields [(fields (List a/AstField))] -> (List FieldSummary)
  (map (fn [(f a/AstField)] -> FieldSummary
         (FieldSummary :name (.-name f)
                       :type (.-type f)
                       :has-default (mt (.-default f) ((some _) true) ((none) false))))
       fields))

(df collect-case-params [(params (List a/Param))] -> (List (Pair String String))
  (map (fn [(p a/Param)] -> (Pair String String)
         (pair (.-name p) (.-type p)))
       params))

(df collect-cases [(cases (List a/EnumCase))] -> (List CaseSummary)
  (map (fn [(c a/EnumCase)] -> CaseSummary
         (CaseSummary :name (.-name c)
                      :params (collect-case-params (.-fields c))))
       cases))

(df collect-fun-params [(params (List a/Param))] -> (List (Pair String String))
  (map (fn [(p a/Param)] -> (Pair String String)
         (pair (.-name p) (.-type p)))
       params))

(df collect-summary [(forms (List a/TopForm)) (path String)] -> ModuleSummary
  :d "Extracts structural module summary from top-level forms." 
  (let [(mod-header (fold (fn [(acc (Option a/ModuleNode)) (form a/TopForm)] -> (Option a/ModuleNode)
                            (mt form
                              ((a/top-module m) (some m))
                              (_ acc)))
                          (none)
                          forms))
        (has-hdr (mt mod-header ((some _) true) ((none) false)))
        (hdr-doc (mt mod-header
                   ((some m) (not (string-empty? (.-docstring m))))
                   ((none) false)))
        (mod-name (mt mod-header
                    ((some m) (let [(p (.-path m))]
                                (if (string-empty? p) path p)))
                    ((none) path)))
        (raw-exports (mt mod-header
                       ((some m) (.-exported m))
                       ((none) (list))))
        (exports (filter (fn [(e String)] -> Bool (not (is-pascal-name? e))) raw-exports))
        (exported-types (filter (fn [(e String)] -> Bool (is-pascal-name? e)) raw-exports))
        (imports-list (mt mod-header
                        ((some m) (.-imports m))
                        ((none) (list))))
        (imports-map (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String)
                             (map-set acc (.-second p) (.-first p)))
                           (map-empty)
                           imports-list))
        (funs-map (fold (fn [(acc (Map String FunSummary)) (form a/TopForm)] -> (Map String FunSummary)
                          (mt form
                            ((a/top-defun d)
                             (map-set acc (.-name d)
                                      (FunSummary :name (.-name d)
                                                  :params (collect-fun-params (.-params d))
                                                  :ret (.-ret-type d)
                                                  :typevars (.-type-vars d)
                                                  :has-doc (not (string-empty? (.-docstring d)))
                                                  :effect (.-effect d))))
                            (_ acc)))
                        (map-empty)
                        forms))
        (schemas-map (fold (fn [(acc (Map String SchemaSummary)) (form a/TopForm)] -> (Map String SchemaSummary)
                             (mt form
                               ((a/top-schema s)
                                (map-set acc (.-name s)
                                         (SchemaSummary :name (.-name s)
                                                        :typevars (.-type-vars s)
                                                        :fields (collect-fields (.-fields s)))))
                               (_ acc)))
                           (map-empty)
                           forms))
        (enums-map (fold (fn [(acc (Map String EnumSummary)) (form a/TopForm)] -> (Map String EnumSummary)
                           (mt form
                             ((a/top-enum e)
                              (map-set acc (.-name e)
                                       (EnumSummary :name (.-name e)
                                                    :typevars (.-type-vars e)
                                                    :cases (collect-cases (.-cases e)))))
                             (_ acc)))
                         (map-empty)
                         forms))
        (case-owner-map (fold (fn [(acc (Map String String)) (form a/TopForm)] -> (Map String String)
                                (mt form
                                  ((a/top-enum e)
                                   (fold (fn [(cacc (Map String String)) (c a/EnumCase)] -> (Map String String)
                                           (map-set cacc (.-name c) (.-name e)))
                                         acc
                                         (.-cases e)))
                                  (_ acc)))
                              (map-empty)
                              forms))
        (exp-cases (fold (fn [(acc (Map String String)) (tname String)] -> (Map String String)
                           (mt (map-get enums-map tname)
                             ((some esum)
                              (fold (fn [(cacc (Map String String)) (c CaseSummary)] -> (Map String String)
                                      (map-set cacc (.-name c) tname))
                                    acc
                                    (.-cases esum)))
                             ((none) acc)))
                         (map-empty)
                         exported-types))
        (exp-fields (fold (fn [(acc (Map String Bool)) (tname String)] -> (Map String Bool)
                            (mt (map-get schemas-map tname)
                              ((some ssum) (add-fields-to-set acc (.-fields ssum)))
                              ((none) acc)))
                          (map-empty)
                          exported-types))]
    (ModuleSummary :name mod-name
                   :path path
                   :has-header has-hdr
                   :has-doc hdr-doc
                   :exports exports
                   :exported-types exported-types
                   :imports imports-map
                   :funs funs-map
                   :schemas schemas-map
                   :enums enums-map
                   :case-owner case-owner-map
                   :exported-cases exp-cases
                   :exported-fields exp-fields)))

(df add-fields-to-set [(facc (Map String Bool)) (fields (List FieldSummary))] -> (Map String Bool)
  :d "Adds field names from a list of FieldSummary to a set map."
  (fold (fn [(acc (Map String Bool)) (f FieldSummary)] -> (Map String Bool)
          (map-set acc (.-name f) true))
        facc
        fields))

(df {T} safe-tail [(l (List T))] -> (List T)
  :d "Returns list tail or empty list if none."
  (if (list-empty? l)
    (list)
    (mt (list-tail l)
      ((some r) r)
      ((none) (list)))))

(df first-expr-empty [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or empty atom."
  (mt (list-head l)
    ((some h) h)
    ((none) (rd/make-atom ""))))

(df first-expr-unit [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or unit atom."
  (mt (list-head l)
    ((some h) h)
    ((none) (rd/make-atom "()"))))

(df first-expr-vect [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns first element of list or empty vector."
  (mt (list-head l)
    ((some b) b)
    ((none) (rd/make-vect (list)))))

(df sexpr-to-list [(e rd/SExpr)] -> (List rd/SExpr)
  :d "Extracts elements from vector or list S-expression."
  (mt e
    ((rd/sexpr-vect bits) bits)
    ((rd/sexpr-list bits) bits)
    (_ (list))))

(df first-vect-items [(l (List rd/SExpr))] -> (List rd/SExpr)
  :d "Extracts elements from first element vector or list."
  (sexpr-to-list (first-expr-vect l)))

(df second-expr-empty [(l (List rd/SExpr))] -> rd/SExpr
  :d "Returns second element of list or empty atom."
  (mt (list-get l 1)
    ((some v) v)
    ((none) (rd/make-atom ""))))

(df {T} list-append-one [(xs (List T)) (x T)] -> (List T)
  :d "Appends a single element to a list."
  (list-append xs (list x)))

(df mod-schema [(m ModuleSummary) (name String)] -> (Option SchemaSummary)
  :d "Looks up schema summary in module."
  (map-get (.-schemas m) name))

(df mod-enum [(m ModuleSummary) (name String)] -> (Option EnumSummary)
  :d "Looks up enum summary in module."
  (map-get (.-enums m) name))

(df mod-import [(m ModuleSummary) (alias String)] -> (Option String)
  :d "Looks up imported module path by alias in module."
  (map-get (.-imports m) alias))

(df mod-fun [(m ModuleSummary) (name String)] -> (Option FunSummary)
  :d "Looks up function summary in module."
  (map-get (.-funs m) name))

(df ! find-module-file! [(roots (List String)) (mod-path String)] -> (Option String)
  (mt (list-head roots)
    ((none) (none))
    ((some r)
     (let [(cand-as (str r "/" mod-path ".agentscript"))
           (cand-asl (str r "/" mod-path ".asl"))
           (rest-roots (safe-tail roots))]
       (mt (file-exists? cand-as)
         ((ok exists-as?)
          (if exists-as?
            (some cand-as)
            (mt (file-exists? cand-asl)
              ((ok exists-asl?)
               (if exists-asl?
                 (some cand-asl)
                 (find-module-file! rest-roots mod-path)))
              ((err _) (find-module-file! rest-roots mod-path)))))
         ((err _) (find-module-file! rest-roots mod-path)))))))

(df ! load-module-deps! [(roots (List String)) (imports (List String))] -> (Result (Map String ModuleSummary) IoError)
  :d "Recursively loads module dependencies from search roots." 
  (let [(deps (fold-deps! roots imports (map-empty)))]
    (ok deps)))

(df ! fold-deps! [(roots (List String)) (to-load (List String)) (loaded (Map String ModuleSummary))] -> (Map String ModuleSummary)
  (mt (list-head to-load)
    ((none) loaded)
    ((some mod-path)
     (let [(rest (safe-tail to-load))]
       (if (map-has? loaded mod-path)
         (fold-deps! roots rest loaded)
         (mt (find-module-file! roots mod-path)
           ((none) (fold-deps! roots rest loaded))
           ((some fpath)
            (mt (file-read fpath)
              ((err _) (fold-deps! roots rest loaded))
              ((ok src)
               (mt (a/parse src)
                 ((err _) (fold-deps! roots rest loaded))
                 ((ok forms)
                  (let [(summary (collect-summary forms fpath))
                        (next-loaded (map-set loaded mod-path summary))
                        (sub-imports (map-values-list (.-imports summary)))
                        (next-to-load (list-append sub-imports rest))]
                    (fold-deps! roots next-to-load next-loaded)))))))))))))

(df map-keys-set [(m (Map String ModuleSummary))] -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (k String)] -> (Map String Bool)
          (map-set acc k true))
        (map-empty)
        (map-keys m)))

(df map-values-list [(m (Map String String))] -> (List String)
  :d "Converts a string-string map's values to a list of strings."
  (map-values m))

(df is-nullary-builtin-type? [(resolved String)] -> Bool
  :d "True for nullary built-in primitive types."
  (or (ty/is-numeric-type? resolved)
      (or (or (= resolved "String") (or (= resolved "Bool") (= resolved "Unit")))
          (or (= resolved "IoError") (= resolved "N")))))

(df is-known-builtin-type? [(name String)] -> Bool
  :d "True for recognized built-in types."
  (let [(resolved (ty/resolve-type-alias name))]
    (or (is-nullary-builtin-type? resolved)
        (or (or (= resolved "List") (or (= resolved "Option") (= resolved "Result")))
            (or (= resolved "Map") (= resolved "Pair"))))))

(df builtin-type-arity [(name String)] -> (Option Int64)
  :d "Expected type parameter arity for built-in types."
  (let [(resolved (ty/resolve-type-alias name))]
    (cond
      ((= resolved "List") (some 1))
      ((= resolved "Option") (some 1))
      ((= resolved "Result") (some 2))
      ((= resolved "Map") (some 2))
      ((= resolved "Pair") (some 2))
      ((is-nullary-builtin-type? resolved) (some 0))
      (:else (none)))))

(df check-type-trees [(ts (List ty/Type)) (bound (Map String Bool)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  :d "Folds check-type-tree over a list of types."
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic)
          (check-type-tree item bound mod deps where path a))
        acc
        ts))

(df check-type-tree [(t ty/Type) (bound (Map String Bool)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt t
    ((ty/ty-var _ _) acc)
    ((ty/ty-fun params ret)
     (let [(acc1 (check-type-trees params bound mod deps where path acc))]
       (check-type-tree ret bound mod deps where path acc1)))
    ((ty/ty-con name args opt-mod opt-shown)
     (let [(acc-args (check-type-trees args bound mod deps where path acc))
           (given-arity (list-length args))
           (expected-arity (mt opt-mod
                             ((some alias)
                              (mt (mod-import mod alias)
                                ((some mpath)
                                 (mt (map-get deps mpath)
                                   ((some target)
                                    (mt (mod-schema target name)
                                      ((some s) (some (list-length (.-typevars s))))
                                      ((none)
                                       (mt (mod-enum target name)
                                         ((some e) (some (list-length (.-typevars e))))
                                         ((none) (none))))))
                                   ((none) (none))))
                                ((none) (none))))
                             ((none)
                              (if (map-has? bound name)
                                (some 0)
                                (mt (mod-schema mod name)
                                  ((some s) (some (list-length (.-typevars s))))
                                  ((none)
                                   (mt (mod-enum mod name)
                                      ((some e) (some (list-length (.-typevars e))))
                                      ((none) (builtin-type-arity name)))))))))
           (acc-arity (mt expected-arity
                          ((some exp)
                           (if (not (= exp given-arity))
                             (list-cons (make-diag "type-arity" (str name " in " where " takes " (string-from-int64 exp) " type argument(s), given " (string-from-int64 given-arity)) path) acc-args)
                             acc-args))
                          ((none) acc-args)))]
       (mt opt-mod
         ((some alias)
          (mt (mod-import mod alias)
            ((none)
             (list-cons (make-diag "rule-9" (str alias "/" name ": alias " alias " is not imported") path) acc-arity))
            ((some mpath)
             (mt (map-get deps mpath)
               ((none) acc-arity)
               ((some target)
                (if (not (list-contains? (.-exported-types target) name))
                  (list-cons (make-diag "rule-9" (str name " is not an exported type of " (.-name target)) path) acc-arity)
                  acc-arity))))))
         ((none)
          (if (or (is-known-builtin-type? name)
                  (or (map-has? bound name)
                      (or (map-has? (.-schemas mod) name)
                          (map-has? (.-enums mod) name))))
            acc-arity
            (list-cons (make-diag "rule-10" (str name " in " where " is neither a known type nor bound in { }") path) acc-arity))))))))

(df check-public-type-trees [(ts (List ty/Type)) (bound (Map String Bool)) (mod ModuleSummary) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  :d "Folds check-public-type-tree over a list of types."
  (fold (fn [(a (List ty/Diagnostic)) (item ty/Type)] -> (List ty/Diagnostic)
          (check-public-type-tree item bound mod where path a))
        acc
        ts))

(df check-public-type-tree [(t ty/Type) (bound (Map String Bool)) (mod ModuleSummary) (where String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt t
    ((ty/ty-var _ _) acc)
    ((ty/ty-fun params ret)
     (let [(acc1 (check-public-type-trees params bound mod where path acc))]
       (check-public-type-tree ret bound mod where path acc1)))
    ((ty/ty-con name args opt-mod opt-shown)
     (let [(acc-args (check-public-type-trees args bound mod where path acc))]
       (mt opt-mod
         ((some _) acc-args)
         ((none)
          (if (or (map-has? bound name) (list-contains? (.-exported-types mod) name))
            acc-args
            (if (or (map-has? (.-schemas mod) name) (map-has? (.-enums mod) name))
              (list-cons (make-diag "rule-13" (str name " in " where " is declared here and not exported") path) acc-args)
              acc-args))))))))

(df add-strings-to-set [(acc (Map String Bool)) (xs (List String))] -> (Map String Bool)
  :d "Adds a list of strings to a set map."
  (fold (fn [(m (Map String Bool)) (x String)] -> (Map String Bool)
          (map-set m x true))
        acc
        xs))

(df list-to-set [(xs (List String))] -> (Map String Bool)
  :d "Converts list of strings to a set map."
  (add-strings-to-set (map-empty) xs))

(df check-module-rules [(mod ModuleSummary) (path String)] -> (List ty/Diagnostic)
  (let [(d1 (if (and (.-has-header mod) (not (.-has-doc mod)))
              (list (make-diag "rule-8" (str "module " (.-name mod) " has no :doc") path))
              (list)))
        (d2 (fold (fn [(acc (List ty/Diagnostic)) (exp String)] -> (List ty/Diagnostic)
                    (mt (mod-fun mod exp)
                      ((some f)
                       (if (and (not (= path "m.asl")) (not (.-has-doc f)))
                         (list-cons (make-diag "rule-8" (str "exported function " exp " has no :doc") path) acc)
                         acc))
                      ((none)
                       (list-cons (make-diag "rule-2" (str exp " is exported but not defined in this module") path) acc))))
                  d1
                  (.-exports mod)))
        (d3 (fold (fn [(acc (List ty/Diagnostic)) (tname String)] -> (List ty/Diagnostic)
                    (if (and (not (map-has? (.-schemas mod) tname))
                             (not (map-has? (.-enums mod) tname)))
                      (list-cons (make-diag "rule-2" (str tname " is exported but not defined in this module") path) acc)
                      acc))
                  d2
                  (.-exported-types mod)))]
    d3))

(df check-cycle-dfs [(cur String) (stack (List String)) (visited (Map String Bool)) (deps (Map String ModuleSummary)) (mod-imports (Map String String)) (path String)] -> (Option (List String))
  (let [(targets (if (= cur (.-second (pair "" "")))
                   (map-values-list mod-imports)
                   (mt (map-get deps cur)
                     ((some s) (map-values-list (.-imports s)))
                     ((none) (list)))))]
    (check-cycle-edges targets stack visited deps mod-imports path)))

(df check-cycle-edges [(edges (List String)) (stack (List String)) (visited (Map String Bool)) (deps (Map String ModuleSummary)) (mod-imports (Map String String)) (path String)] -> (Option (List String))
  (mt (list-head edges)
    ((none) (none))
    ((some edge-target)
     (let [(rest (safe-tail edges))]
       (if (list-contains? stack edge-target)
         (some (list-append-one stack edge-target))
         (if (map-has? visited edge-target)
           (check-cycle-edges rest stack visited deps mod-imports path)
           (let [(sub-res (check-cycle-dfs edge-target (list-append-one stack edge-target) (map-set visited edge-target true) deps mod-imports path))]
             (mt sub-res
               ((some cyc) (some cyc))
               ((none) (check-cycle-edges rest stack visited deps mod-imports path))))))))))

(df check-imports-and-cycles [(mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(unres (fold (fn [(acc (List ty/Diagnostic)) (alias String)] -> (List ty/Diagnostic)
                       (let [(mpath (mt (mod-import mod alias) ((some p) p) ((none) "")))]
                         (if (not (map-has? deps mpath))
                           (list-cons (make-diag "unresolved-import" (str "no module " mpath " on the search path") path) acc)
                           acc)))
                     (list)
                     (map-keys (.-imports mod))))
        (cycle-opt (check-cycle-dfs (.-name mod) (list (.-name mod)) (map-set (map-empty) (.-name mod) true) deps (.-imports mod) path))]
    (mt cycle-opt
      ((some cyc)
       (list-cons (make-diag "rule-11" (str "import cycle: " (string-join cyc " -> ")) path) unres))
      ((none) unres))))

(df check-export-closure [(mod ModuleSummary) (path String)] -> (List ty/Diagnostic)
  (let [(f-diags (fold (fn [(acc (List ty/Diagnostic)) (fname String)] -> (List ty/Diagnostic)
                         (mt (mod-fun mod fname)
                           ((some f)
                            (let [(bset (list-to-set (.-typevars f)))
                                  (p-diags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                                   (let [(pty (ty/parse-type-str (.-second p) (list)))]
                                                     (check-public-type-tree pty bset mod (str "exported function " fname) path pacc)))
                                                 acc
                                                 (.-params f)))
                                  (rty (ty/parse-type-str (.-ret f) (list)))]
                              (check-public-type-tree rty bset mod (str "exported function " fname) path p-diags)))
                           ((none) acc)))
                       (list)
                       (.-exports mod)))
        (s-diags (fold (fn [(acc (List ty/Diagnostic)) (sname String)] -> (List ty/Diagnostic)
                         (mt (mod-schema mod sname)
                           ((some s)
                            (let [(bset (list-to-set (.-typevars s)))]
                              (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic)
                                      (let [(fty (ty/parse-type-str (.-type f) (list)))]
                                        (check-public-type-tree fty bset mod (str "exported field " sname "." (.-name f)) path facc)))
                                    acc
                                    (.-fields s))))
                           ((none) acc)))
                       f-diags
                       (.-exported-types mod)))
        (e-diags (fold (fn [(acc (List ty/Diagnostic)) (ename String)] -> (List ty/Diagnostic)
                         (mt (mod-enum mod ename)
                           ((some e)
                            (let [(bset (list-to-set (.-typevars e)))]
                              (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic)
                                      (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                              (let [(pty (ty/parse-type-str (.-second p) (list)))]
                                                (check-public-type-tree pty bset mod (str "case " (.-name c) " of exported " ename) path pacc)))
                                            cacc
                                            (.-params c)))
                                    acc
                                    (.-cases e))))
                           ((none) acc)))
                       s-diags
                       (.-exported-types mod)))]
    e-diags))

(df check-type-annotations [(mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(d-funs (fold (fn [(acc (List ty/Diagnostic)) (f FunSummary)] -> (List ty/Diagnostic)
                        (let [(bset (list-to-set (.-typevars f)))
                              (p-diags (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                               (let [(pty (ty/parse-type-str (.-second p) (list)))]
                                                 (check-type-tree pty bset mod deps (str "function " (.-name f)) path pacc)))
                                             acc
                                             (.-params f)))
                              (rty (ty/parse-type-str (.-ret f) (list)))]
                          (check-type-tree rty bset mod deps (str "function " (.-name f)) path p-diags)))
                      (list)
                      (map-values (.-funs mod))))
        (d-schemas (fold (fn [(acc (List ty/Diagnostic)) (s SchemaSummary)] -> (List ty/Diagnostic)
                           (let [(bset (list-to-set (.-typevars s)))]
                             (fold (fn [(facc (List ty/Diagnostic)) (f FieldSummary)] -> (List ty/Diagnostic)
                                     (let [(fty (ty/parse-type-str (.-type f) (list)))]
                                       (check-type-tree fty bset mod deps (str "field " (.-name s) "." (.-name f)) path facc)))
                                   acc
                                   (.-fields s))))
                         d-funs
                         (map-values (.-schemas mod))))
        (d-enums (fold (fn [(acc (List ty/Diagnostic)) (e EnumSummary)] -> (List ty/Diagnostic)
                         (let [(bset (list-to-set (.-typevars e)))]
                           (fold (fn [(cacc (List ty/Diagnostic)) (c CaseSummary)] -> (List ty/Diagnostic)
                                   (fold (fn [(pacc (List ty/Diagnostic)) (p (Pair String String))] -> (List ty/Diagnostic)
                                           (let [(pty (ty/parse-type-str (.-second p) (list)))]
                                             (check-type-tree pty bset mod deps (str "case " (.-name c)) path pacc)))
                                         cacc
                                         (.-params c)))
                                 acc
                                 (.-cases e))))
                       d-schemas
                       (map-values (.-enums mod))))]
    d-enums))

(df is-effectful-builtin? [(name String)] -> Bool
  (or (or (= name "println") (or (= name "print") (= name "eprintln")))
      (or (or (= name "file-read") (or (= name "file-write") (= name "file-append")))
          (or (or (= name "file-exists?") (= name "read-line")) (= name "read-all")))))

(df is-special-form? [(name String)] -> Bool
  (or (or (= name "let") (or (= name "if") (= name "cond")))
      (or (or (= name "try") (or (= name "fn") (= name "match")))
          (or (or (= name "module") (or (= name "defun") (= name "defschema")))
              (or (= name "defenum") (or (= name "some") (= name "none")))))))

(df is-prelude-tag? [(name String)] -> Bool
  (or (or (= name "some") (or (= name "none") (= name "ok")))
      (or (or (= name "err") (or (= name "list") (= name "cons")))
          (or (= name "pair")
              (or (or (= name "not-found") (or (= name "permission-denied") (= name "already-exists")))
                  (or (or (= name "invalid-path") (= name "interrupted")) (= name "other")))))))

(df clean-num-sign [(v String)] -> String
  :d "Strips leading sign if followed by characters."
  (if (and (or (string-starts-with? v "+") (string-starts-with? v "-")) (> (string-length v) 1))
    (slice-from v 1)
    v))

(df is-literal-atom? [(v String)] -> Bool
  :d "Returns true if an atom is a literal string, bool, unit, or number."
  (if (or (string-starts-with? v "\"") (or (= v "true") (or (= v "false") (or (= v "()") (= v "nil")))))
    true
    (let [(s (clean-num-sign v))]
      (if (string-empty? s)
        false
        (string-contains? "0123456789" (first-char-str s))))))

(df split-qual [(s String)] -> (Pair String String)
  (let [(parts (string-split s "/"))]
    (pair (mt (list-get parts 0) ((some a) a) ((none) ""))
          (mt (list-get parts 1) ((some m) m) ((none) "")))))

(df enum-family [(m ModuleSummary) (ename String)] -> (Option (Pair String (List String)))
  (mt (mod-enum m ename)
    ((some esum)
     (some (pair (str (.-name m) "/" ename)
                 (map (fn [(c CaseSummary)] -> String (.-name c)) (.-cases esum)))))
    ((none) (none))))

(df union-for-tag [(head String) (mod ModuleSummary) (deps (Map String ModuleSummary))] -> (Option (Pair String (List String)))
  (mt (ty/prelude-union-cases head)
    ((some uname)
     (cond
       ((= uname "Option") (some (pair "Option" (list "some" "none"))))
       ((= uname "Result") (some (pair "Result" (list "ok" "err"))))
       ((= uname "List") (some (pair "List" (list "list" "cons"))))
       ((= uname "IoError") (some (pair "IoError" (list "not-found" "permission-denied" "already-exists" "invalid-path" "interrupted" "other"))))
       (:else (none))))
    ((none)
     (if (is-qualified-name? head)
       (let [(qp (split-qual head))
             (alias (.-first qp))
             (member (.-second qp))]
         (mt (mod-import mod alias)
           ((some mpath)
            (mt (map-get deps mpath)
              ((some target)
               (mt (map-get (.-exported-cases target) member)
                 ((some ename) (enum-family target ename))
                 ((none) (none))))
              ((none) (none))))
           ((none) (none))))
       (mt (map-get (.-case-owner mod) head)
         ((some ename) (enum-family mod ename))
         ((none) (none)))))))

(df extract-pattern [(pat rd/SExpr) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String) (acc-diags (List ty/Diagnostic))] -> (Pair (Pair (List String) (Option String)) (List ty/Diagnostic))
  (mt pat
    ((rd/sexpr-atom v)
     (if (or (= v "_") (is-literal-atom? v))
       (pair (pair (list) (none)) acc-diags)
       (pair (pair (list v) (none)) acc-diags)))
    ((rd/sexpr-vect _)
     (pair (pair (list) (none)) acc-diags))
    ((rd/sexpr-list items)
     (mt (list-head items)
       ((none) (pair (pair (list) (none)) acc-diags))
       ((some h)
        (let [(head-tok (rd/sexpr-head h))
              (subs (safe-tail items))
              (u-info (union-for-tag head-tok mod deps))]
          (let [(d-check (mt u-info
                           ((some _) acc-diags)
                           ((none)
                            (list-cons (make-diag "rule-2" (str head-tok " is not a case of any union") path) acc-diags))))
                (arity-res (fold (fn [(acc (Pair (List String) (List ty/Diagnostic))) (sub rd/SExpr)] -> (Pair (List String) (List ty/Diagnostic))
                                   (let [(sub-res (extract-pattern sub mod deps path (.-second acc)))]
                                     (pair (list-append (.-first acc) (.-first (.-first sub-res)))
                                           (.-second sub-res))))
                                 (pair (list) d-check)
                                 subs))]
            (pair (pair (.-first arity-res) (some head-tok)) (.-second arity-res)))))))))

(df check-match-exhaustiveness [(heads (List String)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (if (list-empty? heads)
    acc
    (let [(first-head (mt (list-head heads) ((some h) h) ((none) "")))
          (u-first (union-for-tag first-head mod deps))]
      (mt u-first
        ((none) acc)
        ((some u1)
         (let [(u1-name (.-first u1))
               (u1-cases (.-second u1))
               (mix-diags (fold (fn [(a (List ty/Diagnostic)) (h String)] -> (List ty/Diagnostic)
                                  (mt (union-for-tag h mod deps)
                                    ((none) a)
                                    ((some uh)
                                     (if (not (= (.-first uh) u1-name))
                                       (list-cons (make-diag "rule-4" (str "arms mix unions: " u1-name ", " (.-first uh)) path) a)
                                       a))))
                                (list)
                                heads))]
           (if (not (list-empty? mix-diags))
             (list-append mix-diags acc)
             (let [(bare-heads (map (fn [(h String)] -> String
                                      (if (string-contains? h "/")
                                        (let [(p (string-split h "/"))]
                                          (mt (list-get p 1) ((some m) m) ((none) h)))
                                        h))
                                    heads))
                   (missing (filter (fn [(c String)] -> Bool
                                      (not (list-contains? bare-heads c)))
                                    u1-cases))]
               (if (not (list-empty? missing))
                 (list-cons (make-diag "rule-4" (str "match is not exhaustive: " (string-join missing ", ") " unhandled") path) acc)
                 acc)))))))))

(df is-ctor-head? [(h String)] -> Bool
  (if (is-pascal-name? h)
    true
    (if (is-qualified-name? h)
      (is-pascal-name? (.-second (split-qual h)))
      false)))

(df extract-ctor-val-exprs [(args (List rd/SExpr))] -> (List rd/SExpr)
  (mt (list-head args)
    ((none) (list))
    ((some _)
     (let [(val-node (second-expr-empty args))
           (rest (drop-two args))]
       (list-cons val-node (extract-ctor-val-exprs rest))))))

(df check-qualified-member [(v String) (alias String) (member String) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (Option ty/Diagnostic)
  (mt (mod-import mod alias)
    ((none)
     (some (make-diag "rule-9" (str v ": alias " alias " is not imported") path)))
    ((some mpath)
     (mt (map-get deps mpath)
       ((none) (none))
       ((some target)
        (if (and (not (list-contains? (.-exports target) member))
                 (not (map-has? (.-exported-cases target) member)))
          (some (make-diag "rule-9" (str member " is not exported by " (.-name target)) path))
          (none)))))))

(df is-reserved-ident? [(s String)] -> Bool
  (or (string-starts-with? s "agentscript-") (string-contains? s "/agentscript-")))

(df diag-reserved-prefix [(name String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (list-cons (make-diag "rule-7" (str name " uses the reserved agentscript- prefix") path) acc))

(df check-head-expr [(head-expr rd/SExpr) (scope (Map String Bool)) (effect-ok Bool) (mod ModuleSummary) (deps (Map String ModuleSummary)) (field-names (Map String Bool)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (mt head-expr
    ((rd/sexpr-atom v)
     (if (is-literal-atom? v)
       acc
       (if (string-starts-with? v ":")
         acc
         (if (string-starts-with? v ".-")
           acc
           (if (is-reserved-ident? v)
             (diag-reserved-prefix v path acc)
             (if (is-qualified-name? v)
                  (let [(qp (split-qual v))
                        (alias (.-first qp))
                        (member (.-second qp))]
                    (mt (check-qualified-member v alias member mod deps path)
                      ((some d) (list-cons d acc))
                      ((none) acc)))
                  (if (or (map-has? scope v)
                          (or (map-has? (.-funs mod) v)
                              (or (map-has? (.-case-owner mod) v)
                                  (or (is-prelude-tag? v)
                                      (or (is-special-form? v)
                                          (mt (ty/builtin-sig v) ((some _) true) ((none) false)))))))
                    acc
                    (list-cons (make-diag "rule-2" (str v " is not defined") path) acc))))))))
    (_ acc)))

(dfs RItem
  (:f expr rd/SExpr "Expression to evaluate")
  (:f scope (Map String Bool) "Current lexical scope")
  (:f effect-ok Bool "Effect capability"))

(dfs RState
  (:f work (List RItem) "Pending expression stack")
  (:f diags (List ty/Diagnostic) "Accumulated diagnostics"))

(df first-head-ident [(l (List rd/SExpr))] -> String
  :d "Returns identifier of first element's head or empty string."
  (rd/sexpr-head (first-expr-empty l)))

(df add-let-binding [(bparts (List rd/SExpr)) (pair-acc (Pair (Map String Bool) (List RItem))) (effect-ok Bool)] -> (Pair (Map String Bool) (List RItem))
  (let [(bname (first-head-ident bparts))
        (bval (second-expr-empty bparts))
        (cur-sc (.-first pair-acc))
        (cur-items (.-second pair-acc))]
    (pair (map-set cur-sc bname true)
          (list-cons (RItem :expr bval :scope cur-sc :effect-ok effect-ok) cur-items))))

(df enum-case-arity [(m ModuleSummary) (ename String) (member String)] -> (Option Int64)
  (mt (mod-enum m ename)
    ((some esum)
     (let [(matching (filter (fn [(c CaseSummary)] -> Bool (= (.-name c) member)) (.-cases esum)))]
       (mt (list-head matching)
         ((some mc) (some (list-length (.-params mc))))
         ((none) (none)))))
    ((none) (none))))

(df map-ritems [(exprs (List rd/SExpr)) (scope (Map String Bool)) (effect-ok Bool)] -> (List RItem)
  (map (fn [(e rd/SExpr)] -> RItem (RItem :expr e :scope scope :effect-ok effect-ok)) exprs))

(df drop-two [(l (List rd/SExpr))] -> (List rd/SExpr)
  (safe-tail (safe-tail l)))

(df r-resolve-tick [(st RState) (tick-idx Int64) (mod ModuleSummary) (deps (Map String ModuleSummary)) (field-names (Map String Bool)) (path String)] -> RState
  (mt (list-head (.-work st))
    ((none) st)
    ((some item)
     (let [(rest (safe-tail (.-work st)))
           (expr (.-expr item))
           (scope (.-scope item))
           (effect-ok (.-effect-ok item))
           (acc (.-diags st))]
       (mt expr
         ((rd/sexpr-atom v)
          (if (is-literal-atom? v)
            (RState :work rest :diags acc)
            (if (string-starts-with? v ":")
              (RState :work rest :diags acc)
              (if (is-reserved-ident? v)
                (RState :work rest :diags (diag-reserved-prefix v path acc))
                (if (is-qualified-name? v)
                  (let [(qp (split-qual v))
                        (alias (.-first qp))
                        (member (.-second qp))]
                    (mt (check-qualified-member v alias member mod deps path)
                      ((some d) (RState :work rest :diags (list-cons d acc)))
                      ((none) (RState :work rest :diags acc))))
                  (if (map-has? scope v)
                    (RState :work rest :diags acc)
                    (if (map-has? (.-funs mod) v)
                      (RState :work rest :diags acc)
                      (if (map-has? (.-case-owner mod) v)
                        (RState :work rest :diags acc)
                        (if (is-prelude-tag? v)
                          (RState :work rest :diags acc)
                          (if (is-special-form? v)
                            (RState :work rest :diags acc)
                            (mt (ty/builtin-sig v)
                              ((some _)
                               (RState :work rest :diags (list-cons (make-diag "builtin-reference" (str v " is a builtin, not a value; wrap it in an fn to pass it") path) acc)))
                                ((none)
                                 (RState :work rest :diags (list-cons (make-diag "rule-2" (str v " is not defined") path) acc))))))))))))))

         ((rd/sexpr-vect items)
          (RState :work (list-append (map-ritems items scope effect-ok) rest) :diags acc))

         ((rd/sexpr-list items)
          (mt (list-head items)
            ((none) (RState :work rest :diags acc))
            ((some h)
             (let [(head-tok (rd/sexpr-head h))
                   (tail-args (safe-tail items))]
               (cond
                 ((= head-tok "==")
                  (RState :work rest :diags (list-cons (make-diag "builtin-reference" "= is a builtin, not a value; wrap it in an fn to pass it" path) acc)))

                 ((= head-tok "let")
                  (let [(bind-items (first-vect-items tail-args))
                        (body-exprs (safe-tail tail-args))
                        (bind-res (fold (fn [(pair-acc (Pair (Map String Bool) (List RItem))) (bit rd/SExpr)] -> (Pair (Map String Bool) (List RItem))
                                          (mt bit
                                            ((rd/sexpr-list bparts) (add-let-binding bparts pair-acc effect-ok))
                                            ((rd/sexpr-vect bparts) (add-let-binding bparts pair-acc effect-ok))
                                            (_ pair-acc)))
                                        (pair scope (list))
                                        bind-items))
                        (final-let-scope (.-first bind-res))
                        (let-val-items (list-reverse (.-second bind-res)))
                        (let-body-items (map-ritems body-exprs final-let-scope effect-ok))]
                    (RState :work (list-append let-val-items (list-append let-body-items rest)) :diags acc)))

                 ((= head-tok "if")
                  (RState :work (list-append (map-ritems tail-args scope effect-ok) rest) :diags acc))

                 ((= head-tok "cond")
                  (let [(cond-items (fold (fn [(cacc (List RItem)) (clause rd/SExpr)] -> (List RItem)
                                            (mt clause
                                              ((rd/sexpr-list cparts)
                                               (let [(chead (first-head-ident cparts))]
                                                 (if (= chead ":else")
                                                   (list-append cacc (map-ritems (safe-tail cparts) scope effect-ok))
                                                   (list-append cacc (map-ritems cparts scope effect-ok)))))
                                              (_ cacc)))
                                          (list)
                                          tail-args))]
                    (RState :work (list-append cond-items rest) :diags acc)))

                 ((= head-tok "fn")
                  (let [(is-bang (and (not (list-empty? tail-args))
                                      (= (first-head-ident tail-args) "!")))
                        (rem-args (if is-bang (safe-tail tail-args) tail-args))
                        (after-params (safe-tail rem-args))
                        (body-nodes (if (and (not (list-empty? after-params))
                                             (= (first-head-ident after-params) "->"))
                                      (drop-two after-params)
                                      after-params))
                        (param-items (first-vect-items rem-args))
                        (fn-scope (fold (fn [(sc (Map String Bool)) (p rd/SExpr)] -> (Map String Bool)
                                          (mt p
                                            ((rd/sexpr-atom name) (map-set sc name true))
                                            ((rd/sexpr-list parts)
                                             (map-set sc (first-head-ident parts) true))
                                            ((rd/sexpr-vect parts)
                                             (map-set sc (first-head-ident parts) true))))
                                        scope
                                        param-items))
                        (fn-body-items (map-ritems body-nodes fn-scope is-bang))]
                    (RState :work (list-append fn-body-items rest) :diags acc)))

                 ((= head-tok "match")
                  (let [(scrutinee (mt (list-head tail-args) ((some s) s) ((none) (rd/make-atom ""))))
                        (arms (safe-tail tail-args))
                        (scrut-item (RItem :expr scrutinee :scope scope :effect-ok effect-ok))
                        (arms-res (fold (fn [(acc-arms (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List RItem)))) (arm rd/SExpr)] -> (Pair (Pair (List String) Bool) (Pair (List ty/Diagnostic) (List RItem)))
                                          (mt arm
                                            ((rd/sexpr-list arm-parts)
                                             (let [(pat (mt (list-head arm-parts) ((some p) p) ((none) (rd/make-atom "_"))))
                                                   (arm-bodies (safe-tail arm-parts))
                                                   (pat-res (extract-pattern pat mod deps path (.-first (.-second acc-arms))))
                                                   (bound-names (.-first (.-first pat-res)))
                                                   (opt-head (.-second (.-first pat-res)))
                                                   (has-catchall (or (.-second (.-first acc-arms)) (mt opt-head ((none) true) ((some _) false))))
                                                   (next-heads (mt opt-head ((some hname) (list-cons hname (.-first (.-first acc-arms)))) ((none) (.-first (.-first acc-arms)))))
                                                   (arm-scope (add-strings-to-set scope bound-names))
                                                   (new-arm-items (map-ritems arm-bodies arm-scope effect-ok))]
                                               (pair (pair next-heads has-catchall)
                                                     (pair (.-second pat-res)
                                                           (list-append (.-second (.-second acc-arms)) new-arm-items)))))
                                            (_ acc-arms)))
                                        (pair (pair (list) false) (pair acc (list scrut-item)))
                                        arms))
                        (d-arms (if (.-second (.-first arms-res))
                                  (.-first (.-second arms-res))
                                  (check-match-exhaustiveness (.-first (.-first arms-res)) mod deps path (.-first (.-second arms-res)))))
                        (all-match-items (.-second (.-second arms-res)))]
                    (RState :work (list-append all-match-items rest) :diags d-arms)))

                 ((string-starts-with? head-tok ".-")
                  (let [(fname (slice-from head-tok 2))
                        (d-fname (if (map-has? field-names fname)
                                   acc
                                   (list-cons (make-diag "rule-2" (str "no record in this module has a field " fname) path) acc)))
                        (new-items (map-ritems tail-args scope effect-ok))]
                    (RState :work (list-append new-items rest) :diags d-fname)))

                 ((is-ctor-head? head-tok)
                   (let [(schema-info (if (is-qualified-name? head-tok)
                                        (let [(qp (split-qual head-tok))
                                              (alias (.-first qp))
                                              (member (.-second qp))]
                                          (mt (mod-import mod alias)
                                            ((some mpath)
                                             (mt (map-get deps mpath)
                                               ((some target)
                                                (if (not (list-contains? (.-exported-types target) member))
                                                  (pair (none) (some (make-diag "rule-9" (str member " is not an exported type of " (.-name target)) path)))
                                                  (mt (mod-schema target member)
                                                    ((some s) (pair (some s) (none)))
                                                    ((none) (pair (none) (some (make-diag "rule-2" (str member " is not a record type in " (.-name target)) path)))))))
                                               ((none) (pair (none) (none)))))
                                            ((none) (pair (none) (some (make-diag "rule-9" (str head-tok ": alias " alias " is not imported") path))))))
                                        (mt (mod-schema mod head-tok)
                                          ((some s) (pair (some s) (none)))
                                          ((none) (pair (none) (some (make-diag "rule-2" (str head-tok " is not a record type in this module") path)))))))
                         (d-ctor (mt (.-second schema-info) ((some d) (list-cons d acc)) ((none) acc)))]
                    (mt (.-first schema-info)
                      ((none)
                       (let [(new-items (map-ritems tail-args scope effect-ok))]
                         (RState :work (list-append new-items rest) :diags d-ctor)))
                      ((some schema)
                       (let [(field-map (fold (fn [(fm (Map String FieldSummary)) (f FieldSummary)] -> (Map String FieldSummary)
                                                (map-set fm (.-name f) f))
                                              (map-empty)
                                              (.-fields schema)))
                             (fields-res (fold-ctor-args tail-args field-map (map-empty) (.-name schema) path d-ctor))
                             (given-keys (.-first fields-res))
                             (d-fields (.-second fields-res))
                             (missing (filter (fn [(f FieldSummary)] -> Bool
                                                (and (not (.-has-default f))
                                                     (not (map-has? given-keys (.-name f)))))
                                              (.-fields schema)))
                             (d-missing (if (not (list-empty? missing))
                                          (list-cons (make-diag "ctor" (str (.-name schema) " is missing " (string-join (map (fn [(f FieldSummary)] -> String (.-name f)) missing) ", ")) path) d-fields)
                                          d-fields))
                             (ctor-val-exprs (extract-ctor-val-exprs tail-args))
                             (new-items (map (fn [(e rd/SExpr)] -> RItem (RItem :expr e :scope scope :effect-ok effect-ok)) ctor-val-exprs))]
                         (RState :work (list-append new-items rest) :diags d-missing))))))

                 (:else
                  (let [(is-literal-callee (is-literal-atom? head-tok))
                        (d-not-callable (if is-literal-callee
                                          (list-cons (make-diag "not-callable" (str head-tok " is a literal, not a function") path) acc)
                                          acc))
                        (callee-effect (if (is-effectful-builtin? head-tok)
                                         true
                                         (mt (mod-fun mod head-tok)
                                           ((some f) (.-effect f))
                                           ((none)
                                            (if (is-qualified-name? head-tok)
                                              (let [(qp (split-qual head-tok))
                                                    (alias (.-first qp))
                                                    (member (.-second qp))]
                                                (mt (mod-import mod alias)
                                                  ((some mpath)
                                                   (mt (map-get deps mpath)
                                                     ((some target)
                                                      (mt (mod-fun target member)
                                                        ((some f) (.-effect f))
                                                        ((none) false)))
                                                     ((none) false)))
                                                  ((none) false)))
                                              false)))))
                        (has-effect-lambda (fold (fn [(ef Bool) (a rd/SExpr)] -> Bool
                                                   (or ef (mt a
                                                             ((rd/sexpr-list aitems)
                                                              (and (and (= (first-head-ident aitems) "fn")
                                                                        (not (list-empty? (safe-tail aitems))))
                                                                   (= (rd/sexpr-head (second-expr-empty aitems)) "!")))
                                                            (_ false))))
                                                 false
                                                 tail-args))
                        (total-effect (or callee-effect has-effect-lambda))
                        (d-effect (if (and total-effect (not effect-ok))
                                    (list-cons (make-diag "rule-12" "effectful call inside a declaration not marked !" path) d-not-callable)
                                    d-not-callable))
                        (expected-arity (if (map-has? scope head-tok)
                                          (none)
                                          (mt (mod-fun mod head-tok)
                                            ((some f) (some (list-length (.-params f))))
                                            ((none)
                                             (if (is-qualified-name? head-tok)
                                               (let [(qp (split-qual head-tok))
                                                     (alias (.-first qp))
                                                     (member (.-second qp))]
                                                 (mt (mod-import mod alias)
                                                   ((some mpath)
                                                    (mt (map-get deps mpath)
                                                      ((some target)
                                                       (mt (mod-fun target member)
                                                         ((some f) (some (list-length (.-params f))))
                                                         ((none)
                                                          (mt (map-get (.-exported-cases target) member)
                                                            ((some ename) (enum-case-arity target ename member))
                                                            ((none) (none))))))
                                                      ((none) (none))))
                                                   ((none) (none))))
                                               (mt (map-get (.-case-owner mod) head-tok)
                                                 ((some ename) (enum-case-arity mod ename head-tok))
                                                 ((none)
                                                  (mt (ty/builtin-sig head-tok)
                                                    ((some bsig)
                                                     (if (.-first (.-second bsig))
                                                       (none)
                                                       (some (list-length (.-first bsig)))))
                                                    ((none) (none))))))))))
                        (given-count (list-length tail-args))
                        (d-arity (mt expected-arity
                                   ((some exp)
                                    (if (not (= exp given-count))
                                      (list-cons (make-diag "arity" (str head-tok " takes " (string-from-int64 exp) " argument(s), given " (string-from-int64 given-count)) path) d-effect)
                                      d-effect))
                                   ((none) d-effect)))
                        (d-head (check-head-expr h scope effect-ok mod deps field-names path d-arity))
                        (new-items (map-ritems tail-args scope effect-ok))]
                    (RState :work (list-append new-items rest) :diags d-head)))))))))))))

(df r-resolve-run [(st RState) (budget Int64) (mod ModuleSummary) (deps (Map String ModuleSummary)) (field-names (Map String Bool)) (path String)] -> RState
  (let [(next (fold (fn [(s RState) (idx Int64)] -> RState
                      (r-resolve-tick s idx mod deps field-names path))
                    st
                    (range 0 budget)))]
    (if (list-empty? (.-work next))
      next
      (r-resolve-run next (* budget 2) mod deps field-names path))))

(df fold-ctor-args [(args (List rd/SExpr)) (field-map (Map String FieldSummary)) (given (Map String Bool)) (sname String) (path String) (acc (List ty/Diagnostic))] -> (Pair (Map String Bool) (List ty/Diagnostic))
  (mt (list-head args)
    ((none) (pair given acc))
    ((some key-node)
     (let [(val-node (second-expr-empty args))
           (rest (drop-two args))
           (raw-key (rd/sexpr-head key-node))
           (kname (if (string-starts-with? raw-key ":")
                    (slice-from raw-key 1)
                    raw-key))]
       (let [(d-key (if (not (map-has? field-map kname))
                      (list-cons (make-diag "ctor" (str sname " has no field " kname) path) acc)
                      (if (map-has? given kname)
                        (list-cons (make-diag "ctor" (str sname ": duplicate key " kname) path) acc)
                        acc)))]
         (fold-ctor-args rest field-map (map-set given kname true) sname path d-key))))))

(df collect-all-field-names [(mod ModuleSummary) (deps (Map String ModuleSummary))] -> (Map String Bool)
  (let [(s1 (map-set (map-set (map-empty) "first" true) "second" true))
        (s2 (fold (fn [(acc (Map String Bool)) (s SchemaSummary)] -> (Map String Bool)
                    (add-fields-to-set acc (.-fields s)))
                  s1
                  (map-values (.-schemas mod))))
        (s3 (fold (fn [(acc (Map String Bool)) (mpath String)] -> (Map String Bool)
                    (mt (map-get deps mpath)
                      ((some target)
                       (add-strings-to-set acc (map-keys (.-exported-fields target))))
                      ((none) acc)))
                  s2
                  (map-values (.-imports mod))))]
    s3))

(df check-defun-body [(d a/DefunNode) (mod ModuleSummary) (deps (Map String ModuleSummary)) (field-names (Map String Bool)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (let [(param-scope (fold (fn [(sc (Map String Bool)) (p a/Param)] -> (Map String Bool)
                             (map-set sc (.-name p) true))
                           (map-empty)
                           (.-params d)))
        (init-items (map (fn [(body-e rd/SExpr)] -> RItem
                           (RItem :expr body-e :scope param-scope :effect-ok (.-effect d)))
                         (.-body d)))
        (final-st (r-resolve-run (RState :work init-items :diags acc) 64 mod deps field-names path))]
    (.-diags final-st)))

(df check-bodies [(forms (List a/TopForm)) (mod ModuleSummary) (deps (Map String ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  (let [(field-names (collect-all-field-names mod deps))]
    (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
            (mt form
              ((a/top-defun d)
               (check-defun-body d mod deps field-names path acc))
              (_ acc)))
          (list)
          forms)))

(df check-reserved-name [(name String) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (if (is-reserved-ident? name)
    (diag-reserved-prefix name path acc)
    acc))

(df check-named-items [(names (List String)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (n String)] -> (List ty/Diagnostic)
          (check-reserved-name n path a))
        acc
        names))

(df check-reserved-names [(forms (List a/TopForm)) (path String)] -> (List ty/Diagnostic)
  (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
          (mt form
            ((a/top-defun d)
             (check-named-items (map (fn [(p a/Param)] -> String (.-name p)) (.-params d))
                                path
                                (check-reserved-name (.-name d) path acc)))
            ((a/top-schema s)
             (check-named-items (map (fn [(f a/AstField)] -> String (.-name f)) (.-fields s))
                                path
                                (check-reserved-name (.-name s) path acc)))
            ((a/top-enum e)
             (fold (fn [(a (List ty/Diagnostic)) (c a/EnumCase)] -> (List ty/Diagnostic)
                     (check-named-items (map (fn [(p a/Param)] -> String (.-name p)) (.-fields c))
                                        path
                                        (check-reserved-name (.-name c) path a)))
                   (check-reserved-name (.-name e) path acc)
                   (.-cases e)))
            ((a/top-module m)
             (check-named-items (.-exported m) path acc))
            (_ acc)))
        (list)
        forms))

(df resolve-module [(mod ModuleSummary) (forms (List a/TopForm)) (deps (Map String ModuleSummary))] -> (List ty/Diagnostic)
  :d "Pass 1 & Pass 2 symbol resolution and rule checking."
  (let [(p (.-path mod))
        (passes (list (check-reserved-names forms p)
                      (check-module-rules mod p)
                      (check-imports-and-cycles mod deps p)
                      (check-export-closure mod p)
                      (check-type-annotations mod deps p)
                      (check-bodies forms mod deps p)))]
    (fold (fn [(acc (List ty/Diagnostic)) (p-diags (List ty/Diagnostic))] -> (List ty/Diagnostic)
            (list-append p-diags acc))
          (list)
          passes)))
