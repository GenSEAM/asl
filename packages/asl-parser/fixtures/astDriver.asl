(module asl-parser/astDriver
  :d "Driver for the typed-AST nodes: construct each and project its fields."
  :x [projModule projSchema projEnum projDefun projTopform]
  :i [(ast :a a) (reader :a rd)])

(df showOpt [(o (Option String))] -> String
  :d "Renders an optional string as some-value or none."
  (mt o
    ((some v) (str "some " v))
    ((none)   "none")))

(df projModule [] -> String
  :d "Project path, doc, export/import arity and defs arity of a module node."
  (let [(m (a/ModuleNode :path "demo/mod"
                         :docstring "\"module docs\""
                         :exported (list "alpha" "beta")
                         :imports (list (pair "core/x" "cx"))
                         :defs (list)))]
    (str (.-path m) "|" (.-docstring m) "|"
         (string-from-int64 (list-length (.-exported m)))
         "|" (string-from-int64 (list-length (.-imports m)))
         "|" (string-from-int64 (list-length (.-defs m))))))

(df projSchema [] -> String
  :d "Project name, type-vars, first field name and json-case of a schema node."
  (let [(f (a/AstField :name "x" :type "Int64" :docstring "\"d\""
                       :default (some "3") :json (none)))
        (s (a/SchemaNode :name "Point" :typeVars (list "T")
                         :fields (list f) :jsonCase (some "camel")))]
    (str (.-name s) "|" (string-from-int64 (list-length (.-typeVars s)))
         "|" (mt (list-head (.-fields s))
               ((some h) (.-name h))
               ((none)   "no-head"))
         "|" (showOpt (.-jsonCase s)))))

(df projEnum [] -> String
  :d "Project name, first case name and its doc of an enum node."
  (let [(c (a/EnumCase :name "point" :fields (list) :docstring "\"a dot\""))
        (e (a/EnumNode :name "Shape" :typeVars (list) :cases (list c)))]
    (str (.-name e)
         "|" (mt (list-head (.-cases e))
               ((some h) (.-name h))
               ((none)   "no-case"))
         "|" (mt (list-head (.-cases e))
               ((some h) (.-docstring h))
               ((none)   "no-doc")))))

(df projDefun [] -> String
  :d "Project name, exported/effect flags, param arity, ret-type and body arity."
  (let [(p (a/Param :name "n" :type "Int64"))
        (d (a/DefunNode :name "twice" :typeVars (list)
                        :isExported true :effect false
                        :params (list p) :retType "Int64" :docstring "\"d\""
                        :body (list (rd/sexprAtom "n"))))]
    (str (.-name d) "|" (if (.-isExported d) "T" "F")
         "|" (if (.-effect d) "T" "F")
         "|" (string-from-int64 (list-length (.-params d)))
         "|" (.-retType d) "|" (string-from-int64 (list-length (.-body d))))))

(df projTopform [] -> String
  :d "Wrap a defun node in TopForm and unwrap it by matching the payload."
  (let [(p (a/Param :name "x" :type "Float64"))
        (d (a/DefunNode :name "id" :typeVars (list)
                        :isExported false :effect false
                        :params (list p) :retType "Float64" :docstring ""
                        :body (list (rd/sexprAtom "x"))))
        (t (a/topDefun d))]
    (mt t
      ((a/topDefun inner) (.-name inner))
      ((a/topModule _)    "module")
      ((a/topSchema _)    "schema")
      ((a/topEnum _)      "enum"))))
