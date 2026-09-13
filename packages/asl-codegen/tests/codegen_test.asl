(module asl-codegen/codegenTest
  :d "Unit tests for asl-codegen/emit"
  :x [testCodegen runTests]
  :i [(emit :a em) (ast :a a) (reader :a rd)])

(df testCodegen [] -> Bool
  :d "Verifies top-level forms emission and program assembly."
  (let [(f1 (a/AstField :name "x" :type "Int" :docstring "" :default (none) :json (none)))
        (f2 (a/AstField :name "y" :type "Int" :docstring "" :default (none) :json (none)))
        (sNode (a/SchemaNode :name "Point" :typeVars (list) :fields (list f1 f2) :jsonCase (none)))
        (sOut (em/emitDefschema sNode))
        (c1 (a/EnumCase :name "active" :fields (list) :docstring ""))
        (c2 (a/EnumCase :name "inactive" :fields (list) :docstring ""))
        (en (a/EnumNode :name "Status" :typeVars (list) :cases (list c1 c2)))
        (eOut (em/emitDefenum en))
        (p1 (a/Param :name "x" :type "Int"))
        (p2 (a/Param :name "y" :type "Int"))
        (body (list (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "x") (rd/sexprAtom "y")))))
        (defunNode (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list p1 p2) :retType "Int" :docstring "" :body body))
        (aliases (map-empty))
        (dOut (em/emitDefun defunNode aliases))
        (forms (list (a/topSchema sNode) (a/topEnum en) (a/topDefun defunNode)))
        (progOut (em/emitRustProgram forms (list)))]
    (assert (string-contains? sOut "pub struct Point") "struct name")
    (assert (string-contains? sOut "pub x: i64,") "struct field x")
    (assert (string-contains? eOut "pub enum Status") "enum name")
    (assert (string-contains? eOut "Active,") "enum case active")
    (assert (string-contains? dOut "pub fn add(x: i64, y: i64) -> i64") "fn signature")
    (assert (string-contains? progOut "mod rt;") "runtime link")
    (assert (string-contains? progOut "pub struct Point") "prog struct")
    (assert (string-contains? progOut "pub fn add") "prog fn")
    true))

(df runTests [] -> Bool
  :d "Runs codegen test suite"
  (do
    (assert (testCodegen) "test-codegen must pass")
    true))
