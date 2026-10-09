(module asl-codegen/rtypes :x [primitiveRustType emitType emitTypeStr typeMentionsIoError? typeMentionsFloat? emitDerives anyTrue? boxedTypeIfRecursive] :i [(asl-checker/types :a ty) (mangle :a m)])

fn anyTrue? flags: (List Bool) -> Bool
  (fold (fn [(acc Bool) (cur Bool)] (or acc cur)) false flags)

fn primitiveRustType name: String -> (Option String)
  (let [(canon (ty/resolveTypeAlias name))] (cond ((= canon "Int64") (some "i64")) ((= canon "Int32") (some "i32")) ((= canon "Float64") (some "f64")) ((= canon "Float32") (some "f32")) ((= canon "String") (some "String")) ((= canon "Bool") (some "bool")) ((= canon "Unit") (some "()")) ((= canon "IoError") (some "rt::IoError")) (else (none))))

fn getArgType args: (List ty/Type) idx: I64 -> String
  (emitType (optionOr (listGet args idx) (ty/tyCon "Unit" (list) (none) (none))))

fn emitType t: ty/Type -> String
  (mt t ((ty/tyVar id kind) (cond ((= kind "int") "i64") ((= kind "num") "f64") (else (str "T" (stringFromInt64 id))))) ((ty/tyFun params ret) "()") ((ty/tyCon name args modOpt shownOpt) (let [(prim (primitiveRustType name))] (mt prim ((some p) p) ((none) (cond ((= name "List") (if (> (listLength args) 0) (str "Vec<" (getArgType args 0) ">") "Vec<()>")) ((= name "Option") (if (> (listLength args) 0) (str "Option<" (getArgType args 0) ">") "Option<()>")) ((= name "Result") (if (>= (listLength args) 2) (str "Result<" (getArgType args 0) ", " (getArgType args 1) ">") "Result<(), ()>")) ((= name "Pair") (if (>= (listLength args) 2) (str "(" (getArgType args 0) ", " (getArgType args 1) ")") "((), ())")) ((= name "Map") (if (>= (listLength args) 2) (str "std::collections::BTreeMap<" (getArgType args 0) ", " (getArgType args 1) ">") "std::collections::BTreeMap<(), ()>")) (else (let [(typeBase (mt modOpt ((some mName) (str (m/mangleIdent mName) "::" (m/pascalIdent name))) ((none) (if (stringContains? name "/") (let [(parts (stringSplit name "/")) (alias (optionOr (listGet parts 0) "")) (mem (optionOr (listGet parts 1) name))] (str (m/mangleIdent alias) "::" (m/pascalIdent mem))) (m/pascalIdent name)))))] (if (> (listLength args) 0) (str typeBase "<" (stringJoin (map emitType args) ", ") ">") typeBase)))))))))

fn emitTypeStr s: String -> String
  (let [(t (ty/parseTypeStr s (list)))] (emitType t))

fn typeMentionsIoError? t: ty/Type -> Bool
  (mt t ((ty/tyVar id kind) false) ((ty/tyFun params ret) false) ((ty/tyCon name args modOpt shownOpt) (if (or (= name "IoError") (= (ty/resolveTypeAlias name) "IoError")) true (anyTrue? (map typeMentionsIoError? args)))))

fn typeMentionsFloat? t: ty/Type -> Bool
  (mt t ((ty/tyVar id kind) (= kind "num")) ((ty/tyFun params ret) false) ((ty/tyCon name args modOpt shownOpt) (if (or (= name "Float64") (= (ty/resolveTypeAlias name) "Float64")) true (anyTrue? (map typeMentionsFloat? args)))))

fn emitDerives hasIo: Bool hasFloat: Bool -> String
  (cond (hasIo "#[derive(Debug, Clone, PartialEq)]") (else "#[derive(Debug, Clone, PartialEq, PartialOrd)]"))

fn boxedTypeIfRecursive renderedType: String declName: String isRecursive: Bool -> String
  (if isRecursive (str "::std::boxed::Box<" renderedType ">") renderedType)
