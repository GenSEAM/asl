(module asl-parser/ast-driver
  :d "Driver for the typed-AST nodes: construct each and project its fields."
  :x [proj-module proj-schema proj-enum proj-defun proj-topform]
  :i [(ast :a a) (reader :a rd)])

(df show-opt [(o (Option String))] -> String
  :d "Renders an optional string as some-value or none."
  (mt o
    ((some v) (str "some " v))
    ((none)   "none")))

(df proj-module [] -> String
  :d "Project doc, export/import arity and defs arity of a module node."
  (let [(m (a/ModuleNode :docstring "\"module docs\""
                         :exported (list "alpha" "beta")
                         :imports (list (pair "core/x" "cx"))
                         :defs (list)))]
    (str (.-docstring m) "|" (string-from-int64 (list-length (.-exported m)))
         "|" (string-from-int64 (list-length (.-imports m)))
         "|" (string-from-int64 (list-length (.-defs m))))))

(df proj-schema [] -> String
  :d "Project name, type-vars, first field name and json-case of a schema node."
  (let [(f (a/AstField :name "x" :type "Int64" :docstring "\"d\""
                       :default (some "3") :json (none)))
        (s (a/SchemaNode :name "Point" :type-vars (list "T")
                         :fields (list f) :json-case (some "camel")))]
    (str (.-name s) "|" (string-from-int64 (list-length (.-type-vars s)))
         "|" (mt (list-head (.-fields s))
               ((some h) (.-name h))
               ((none)   "no-head"))
         "|" (show-opt (.-json-case s)))))

(df proj-enum [] -> String
  :d "Project name, first case name and its doc of an enum node."
  (let [(c (a/EnumCase :name "point" :fields (list) :docstring "\"a dot\""))
        (e (a/EnumNode :name "Shape" :type-vars (list) :cases (list c)))]
    (str (.-name e)
         "|" (mt (list-head (.-cases e))
               ((some h) (.-name h))
               ((none)   "no-case"))
         "|" (mt (list-head (.-cases e))
               ((some h) (.-docstring h))
               ((none)   "no-doc")))))

(df proj-defun [] -> String
  :d "Project name, exported/effect flags, param arity, ret-type and body arity."
  (let [(p (a/Param :name "n" :type "Int64"))
        (d (a/DefunNode :name "twice" :type-vars (list)
                        :is-exported true :effect false
                        :params (list p) :ret-type "Int64" :docstring "\"d\""
                        :body (list (rd/sexpr-atom "n"))))]
    (str (.-name d) "|" (if (.-is-exported d) "T" "F")
         "|" (if (.-effect d) "T" "F")
         "|" (string-from-int64 (list-length (.-params d)))
         "|" (.-ret-type d) "|" (string-from-int64 (list-length (.-body d))))))

(df proj-topform [] -> String
  :d "Wrap a defun node in TopForm and unwrap it by matching the payload."
  (let [(p (a/Param :name "x" :type "Float64"))
        (d (a/DefunNode :name "id" :type-vars (list)
                        :is-exported false :effect false
                        :params (list p) :ret-type "Float64" :docstring ""
                        :body (list (rd/sexpr-atom "x"))))
        (t (a/top-defun d))]
    (mt t
      ((a/top-defun inner) (.-name inner))
      ((a/top-module _)    "module")
      ((a/top-schema _)    "schema")
      ((a/top-enum _)      "enum"))))
