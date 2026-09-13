(module asl-codegen/rtypes
  :d "Rust type mapping, generic rendering, and trait derivations for ASL AST."
  :x [primitiveRustType
      emitType
      emitTypeStr
      typeMentionsIoError?
      typeMentionsFloat?
      emitDerives
      anyTrue?
      boxedTypeIfRecursive]
  :i [(types :a ty) (mangle :a m)])

(df anyTrue? [(flags (List Bool))] -> Bool
  :d "True if any boolean in list is true."
  (fold (fn [(acc Bool) (cur Bool)] (or acc cur)) false flags))

(df primitiveRustType [(name String)] -> (Option String)
  :d "Maps primitive Core ASL types to Rust native types."
  (let [(canon (ty/resolveTypeAlias name))]
    (cond
      ((= canon "Int64") (some "i64"))
      ((= canon "Int32") (some "i32"))
      ((= canon "Float64") (some "f64"))
      ((= canon "Float32") (some "f32"))
      ((= canon "String") (some "String"))
      ((= canon "Bool") (some "bool"))
      ((= canon "Unit") (some "()"))
      ((= canon "IoError") (some "rt::IoError"))
      (:else (none)))))

(df getArgType [(args (List ty/Type)) (idx I64)] -> String
  :d "Emits Rust type for the argument at idx or unit if missing."
  (emitType (option-or (list-get args idx) (ty/tyCon "Unit" (list) (none) (none)))))

(df emitType [(t ty/Type)] -> String
  :d "Renders an ASL Type AST into its canonical Rust type spelling."
  (mt t
    ((ty/tyVar id kind)
     (cond
       ((= kind "int") "i64")
       ((= kind "num") "f64")
       (:else (str "T" (string-from-int64 id)))))
    ((ty/tyFun params ret)
     "()")
    ((ty/tyCon name args modOpt shownOpt)
     (let [(prim (primitiveRustType name))]
       (mt prim
         ((some p) p)
         ((none)
          (cond
            ((= name "List")
             (if (> (list-length args) 0)
                 (str "Vec<" (getArgType args 0) ">")
                 "Vec<()>"))
            ((= name "Option")
             (if (> (list-length args) 0)
                 (str "Option<" (getArgType args 0) ">")
                 "Option<()>"))
            ((= name "Result")
             (if (>= (list-length args) 2)
                 (str "Result<" (getArgType args 0) ", " (getArgType args 1) ">")
                 "Result<(), ()>"))
            ((= name "Pair")
             (if (>= (list-length args) 2)
                 (str "(" (getArgType args 0) ", " (getArgType args 1) ")")
                 "((), ())"))
            ((= name "Map")
             (if (>= (list-length args) 2)
                 (str "std::collections::BTreeMap<" (getArgType args 0) ", " (getArgType args 1) ">")
                 "std::collections::BTreeMap<(), ()>"))
            (:else
             (let [(typeBase (mt modOpt
                                ((some mName) (str (m/mangleIdent mName) "::" (m/pascalIdent name)))
                                ((none)
                                 (if (string-contains? name "/")
                                     (let [(parts (string-split name "/"))
                                           (alias (option-or (list-get parts 0) ""))
                                           (mem (option-or (list-get parts 1) name))]
                                       (str (m/mangleIdent alias) "::" (m/pascalIdent mem)))
                                     (m/pascalIdent name)))))]
               (if (> (list-length args) 0)
                   (str typeBase "<" (string-join (map emitType args) ", ") ">")
                   typeBase))))))))))

(df emitTypeStr [(s String)] -> String
  :d "Parses a type string and emits its Rust type representation."
  (let [(t (ty/parseTypeStr s (list)))]
    (emitType t)))

(df typeMentionsIoError? [(t ty/Type)] -> Bool
  :d "Checks if a type transitively mentions rt::IoError."
  (mt t
    ((ty/tyVar id kind) false)
    ((ty/tyFun params ret) false)
    ((ty/tyCon name args modOpt shownOpt)
     (if (or (= name "IoError") (= (ty/resolveTypeAlias name) "IoError"))
         true
         (anyTrue? (map typeMentionsIoError? args))))))

(df typeMentionsFloat? [(t ty/Type)] -> Bool
  :d "Checks if a type transitively mentions Float64."
  (mt t
    ((ty/tyVar id kind) (= kind "num"))
    ((ty/tyFun params ret) false)
    ((ty/tyCon name args modOpt shownOpt)
     (if (or (= name "Float64") (= (ty/resolveTypeAlias name) "Float64"))
         true
         (anyTrue? (map typeMentionsFloat? args))))))

(df emitDerives [(hasIo Bool) (hasFloat Bool)] -> String
  :d "Emits Rust derive attribute according to comparability and orderability."
  (cond
    (hasIo "#[derive(Debug, Clone, PartialEq)]")
    (:else "#[derive(Debug, Clone, PartialEq, PartialOrd)]")))

(df boxedTypeIfRecursive [(renderedType String) (declName String) (isRecursive Bool)] -> String
  :d "Wraps a field type in Box if it is directly recursive."
  (if isRecursive
      (str "::std::boxed::Box<" renderedType ">")
      renderedType))
