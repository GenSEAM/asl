(module asl-codegen/codegen-test
  :d "Unit tests for asl-codegen/emit"
  :x [test-codegen]
  :i [(emit :a em) (ast :a a) (reader :a rd)])

(df test-codegen [] -> String
  :d "Verifies top-level forms emission and program assembly."
  (let [(f1 (a/AstField :name "x" :type "Int" :docstring "" :default (none) :json (none)))
        (f2 (a/AstField :name "y" :type "Int" :docstring "" :default (none) :json (none)))
        (schema (a/SchemaNode :name "Point" :type-vars (list) :fields (list f1 f2) :json-case (none)))
        (s-out (em/emit-defschema schema))
        (c1 (a/EnumCase :name "active" :fields (list) :docstring ""))
        (c2 (a/EnumCase :name "inactive" :fields (list) :docstring ""))
        (en (a/EnumNode :name "Status" :type-vars (list) :cases (list c1 c2)))
        (e-out (em/emit-defenum en))
        (p1 (a/Param :name "x" :type "Int"))
        (p2 (a/Param :name "y" :type "Int"))
        (body (list (rd/sexpr-list (list (rd/sexpr-atom "+") (rd/sexpr-atom "x") (rd/sexpr-atom "y")))))
        (defun-node (a/DefunNode :name "add" :type-vars (list) :is-exported true :effect false :params (list p1 p2) :ret-type "Int" :docstring "" :body body))
        (aliases (map-empty))
        (d-out (em/emit-defun defun-node aliases))
        (mod-node (a/ModuleNode :path "calc" :docstring "" :exported (list "add") :imports (list) :defs (list (a/top-schema schema) (a/top-enum en) (a/top-defun defun-node))))
        (prog-out (em/emit-rust-program mod-node (list)))]
    (cond
      ((not (string-contains? s-out "pub struct Point")) "fail struct name")
      ((not (string-contains? s-out "pub x: i64,")) "fail struct field x")
      ((not (string-contains? e-out "pub enum Status")) "fail enum name")
      ((not (string-contains? e-out "Active,")) "fail enum case active")
      ((not (string-contains? d-out "pub fn add(x: i64, y: i64) -> i64")) "fail fn signature")
      ((not (string-contains? prog-out "mod rt;")) "fail runtime link")
      ((not (string-contains? prog-out "pub struct Point")) "fail prog struct")
      ((not (string-contains? prog-out "pub fn add")) "fail prog fn")
      (:else "ok"))))
