(module asl-codegen/rtypes
  :d "Rust type mapping, generic rendering, and trait derivations for ASL AST."
  :x [primitive-rust-type
      emit-type
      emit-type-str
      type-mentions-io-error?
      type-mentions-float?
      emit-derives
      boxed-type-if-recursive]
  :i [(types :a ty) (mangle :a m)])

(df primitive-rust-type [(name String)] -> (Option String)
  :d "Maps primitive Core ASL types to Rust native types."
  (let [(canon (ty/resolve-type-alias name))]
    (cond
      ((= canon "Bool") (some "bool"))
      ((= canon "Int32") (some "i32"))
      ((= canon "Int64") (some "i64"))
      ((= canon "Float64") (some "f64"))
      ((= canon "String") (some "String"))
      ((= canon "Unit") (some "()"))
      ((= canon "IoError") (some "rt::IoError"))
      (:else (none)))))

(df get-arg-type [(args (List ty/Type)) (idx I64)] -> String
  :d "Emits Rust type for the argument at idx or unit if missing."
  (emit-type (option-or (list-get args idx) (ty/ty-con "Unit" (list) (none) (none)))))

(df emit-type [(t ty/Type)] -> String
  :d "Renders an ASL Type AST into its canonical Rust type spelling."
  (mt t
    ((ty/ty-var id kind)
     (cond
       ((= kind "int") "i64")
       ((= kind "num") "f64")
       (:else (str "T" (string-from-int64 id)))))
    ((ty/ty-fun params ret)
     "()")
    ((ty/ty-con name args mod-opt shown-opt)
     (let [(prim (primitive-rust-type name))]
       (mt prim
         ((some p) p)
         ((none)
          (cond
            ((= name "List")
             (if (> (list-length args) 0)
                 (str "Vec<" (get-arg-type args 0) ">")
                 "Vec<()>"))
            ((= name "Option")
             (if (> (list-length args) 0)
                 (str "Option<" (get-arg-type args 0) ">")
                 "Option<()>"))
            ((= name "Result")
             (if (>= (list-length args) 2)
                 (str "Result<" (get-arg-type args 0) ", " (get-arg-type args 1) ">")
                 "Result<(), ()>"))
            ((= name "Pair")
             (if (>= (list-length args) 2)
                 (str "(" (get-arg-type args 0) ", " (get-arg-type args 1) ")")
                 "((), ())"))
            ((= name "Map")
             (if (>= (list-length args) 2)
                 (str "std::collections::BTreeMap<" (get-arg-type args 0) ", " (get-arg-type args 1) ">")
                 "std::collections::BTreeMap<(), ()>"))
            (:else
             (let [(clean-name (if (string-contains? name "/")
                                   (string-replace name "/" "_")
                                   name))]
               (if (> (list-length args) 0)
                   (str clean-name "<" (string-join (map emit-type args) ", ") ">")
                   clean-name))))))))))

(df emit-type-str [(s String)] -> String
  :d "Parses a type string and emits its Rust type representation."
  (let [(t (ty/parse-type-str s (list)))]
    (emit-type t)))

(df type-mentions-io-error? [(t ty/Type)] -> Bool
  :d "Checks if a type transitively mentions rt::IoError."
  (mt t
    ((ty/ty-var id kind) false)
    ((ty/ty-fun params ret) false)
    ((ty/ty-con name args mod-opt shown-opt)
     (if (or (= name "IoError") (= (ty/resolve-type-alias name) "IoError"))
         true
         (let [(checks (map type-mentions-io-error? args))]
           (fold (fn [(acc Bool) (cur Bool)] (or acc cur)) false checks))))))

(df type-mentions-float? [(t ty/Type)] -> Bool
  :d "Checks if a type transitively mentions Float64."
  (mt t
    ((ty/ty-var id kind) (= kind "num"))
    ((ty/ty-fun params ret) false)
    ((ty/ty-con name args mod-opt shown-opt)
     (if (or (= name "Float64") (= (ty/resolve-type-alias name) "Float64"))
         true
         (let [(checks (map type-mentions-float? args))]
           (fold (fn [(acc Bool) (cur Bool)] (or acc cur)) false checks))))))

(df emit-derives [(has-io Bool) (has-float Bool)] -> String
  :d "Emits Rust derive attribute according to comparability and orderability."
  (cond
    (has-io "#[derive(Debug, Clone, PartialEq)]")
    (has-float "#[derive(Debug, Clone, PartialEq, PartialOrd)]")
    (:else "#[derive(Debug, Clone, PartialEq, PartialOrd, Eq, Ord)]")))

(df boxed-type-if-recursive [(rendered-type String) (decl-name String) (is-recursive Bool)] -> String
  :d "Wraps a field type in Box if it is directly recursive."
  (if is-recursive
      (str "::std::boxed::Box<" rendered-type ">")
      rendered-type))
