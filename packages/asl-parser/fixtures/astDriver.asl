(module asl-parser/astDriver :x [projModule projSchema projEnum projDefun projTopform] :i [(ast :a a) (reader :a rd)])

fn showOpt o: (Option String) -> String
  (mt o ((some v) (str "some " v)) ((none) "none"))

fn projModule -> String
  (let [(m (a/ModuleNode :path "demo/mod" :docstring "\"module docs\"" :exported (list "alpha" "beta") :imports (list (pair "core/x" "cx")) :defs (list)))] (str m.path "|" m.docstring "|" (stringFromInt64 (listLength m.exported)) "|" (stringFromInt64 (listLength m.imports)) "|" (stringFromInt64 (listLength m.defs))))

fn projSchema -> String
  (let [(f (a/AstField :name "x" :type "Int64" :docstring "\"d\"" :default (some (rd/sexprAtom "3")) :json (none))) (s (a/SchemaNode :name "Point" :typeVars (list "T") :fields (list f) :jsonCase (some "camel")))] (str s.name "|" (stringFromInt64 (listLength s.typeVars)) "|" (mt (listHead s.fields) ((some h) h.name) ((none) "no-head")) "|" (showOpt s.jsonCase)))

fn projEnum -> String
  (let [(c (a/EnumCase :name "point" :fields (list) :docstring "\"a dot\"")) (e (a/EnumNode :name "Shape" :typeVars (list) :cases (list c)))] (str e.name "|" (mt (listHead e.cases) ((some h) h.name) ((none) "no-case")) "|" (mt (listHead e.cases) ((some h) h.docstring) ((none) "no-doc"))))

fn projDefun -> String
  (let [(p (a/Param :name "n" :type "Int64")) (d (a/DefunNode :name "twice" :typeVars (list) :isExported true :effect false :params (list p) :retType "Int64" :docstring "\"d\"" :body (list (rd/sexprAtom "n"))))] (str d.name "|" (if d.isExported "T" "F") "|" (if d.effect "T" "F") "|" (stringFromInt64 (listLength d.params)) "|" d.retType "|" (stringFromInt64 (listLength d.body))))

fn projTopform -> String
  (let [(p (a/Param :name "x" :type "Float64")) (d (a/DefunNode :name "id" :typeVars (list) :isExported false :effect false :params (list p) :retType "Float64" :docstring "" :body (list (rd/sexprAtom "x")))) (t (a/topDefun d))] (mt t ((a/topDefun inner) inner.name) ((a/topModule _) "module") ((a/topSchema _) "schema") ((a/topEnum _) "enum") ((a/topExpr _) "expr")))
