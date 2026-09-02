(module asl-parser/ast
  :d "Typed AST nodes for the four section-4 heads, parseable from either dialect."
  :x [ModuleNode SchemaNode EnumNode DefunNode EnumCase Param AstField
           TopForm parse render-node]
  :i [(lexer :a lx) (reader :a rd)])

(dfs Param
  (:f name String "Parameter name")
  (:f type String "Type annotation as canonical single-space text"))

(dfs AstField
  (:f name String "Field name")
  (:f type String "Type annotation as canonical single-space text")
  (:f docstring String "Field doc string, as written including quotes")
  (:f default (Option String) ":default literal, as written, or none")
  (:f json (Option String) ":json override string, or none"))

(dfs EnumCase
  (:f name String "Case name")
  (:f fields (List Param) "Case fields from the [ ... ] vector form")
  (:f docstring String "Case doc string, as written including quotes"))

(dfs ModuleNode
  (:f docstring String "Module :doc string, as written including quotes")
  (:f exported (List String) "Names on the :export vector, in source order")
  (:f imports (List (Pair String String)) "Imported module path and alias")
  (:f defs (List TopForm) "Top-level declarations, in source order"))

(dfs SchemaNode
  (:f name String "Schema name")
  (:f type-vars (List String) "Type variables bound in the leading { }")
  (:f fields (List AstField) "Record fields, in source order")
  (:f json-case (Option String) "Schema :json-case, or none meaning kebab"))

(dfs EnumNode
  (:f name String "Enum name")
  (:f type-vars (List String) "Type variables bound in the leading { }")
  (:f cases (List EnumCase) "Enum cases, in source order"))

(dfs DefunNode
  (:f name String "Function name")
  (:f type-vars (List String) "Type variables bound in the leading { }")
  (:f is-exported Bool "True when the owning module :export vector names it")
  (:f effect Bool "True when the signature carries the ! marker")
  (:f params (List Param) "Parameters from the [ ... ] vector form")
  (:f ret-type String "Return type annotation as canonical single-space text")
  (:f docstring String "Doc string, as written including quotes, empty when absent")
  (:f body (List rd/SExpr) "Body forms, retained as generic SExpr"))

(dfe TopForm
  (:c top-module [(node ModuleNode)] "A module declaration")
  (:c top-schema [(node SchemaNode)] "A defschema declaration")
  (:c top-enum   [(node EnumNode)] "A defenum declaration")
  (:c top-defun  [(node DefunNode)] "A defun declaration"))

(df norm-atom [(a String)] -> String
  :d "Map an Ultra-Nano atom to its verbose spelling."
  (let [(nanos (list "df" "dfs" "dfe" "mt" ":f" ":c" ":d" ":x" ":i" ":a"))
        (verbs (list "defun" "defschema" "defenum" "match"
                     ":field" ":case" ":doc" ":export" ":import" ":as"))]
    (mt (list-index-of nanos a)
      ((some i) (mt (list-get verbs i) ((some v) v) ((none) a)))
      ((none) a))))

(df parse [(src String)] -> (List TopForm)
  :d "Tokenize and parse a module source into typed top forms."
  (let [(forms (.-first (read-forms (lx/tokenize src) (list))))]
    (build-module forms)))

(df read-forms [(toks (List lx/Token)) (acc (List rd/SExpr))]
  -> (Pair (List rd/SExpr) (List lx/Token))
  :d "Read every top-level SExpr from a token stream until the EOF token."
  (mt (list-head toks)
    ((some t)
     (if (= (.-raw-text t) "")
       (pair (list-reverse acc) toks)
       (let [(sub (read-one toks))]
         (read-forms (.-second sub) (list-cons (.-first sub) acc)))))
    ((none) (pair (list-reverse acc) (list)))))

(df read-one [(toks (List lx/Token))] -> (Pair rd/SExpr (List lx/Token))
  :d "Read one SExpr and return it with the remaining tokens."
  (mt (list-head toks)
    ((some t)
     (let [(raw (.-raw-text t))]
       (cond
         ((= raw "(") (read-seq-items (tail-toks toks) ")" (list)))
         ((= raw "[") (read-seq-items (tail-toks toks) "]" (list)))
         (:else (pair (rd/make-atom (norm-atom raw)) (tail-toks toks))))))
    ((none) (pair (rd/make-atom "") (list)))))

(df read-seq-items [(toks (List lx/Token)) (close String) (acc (List rd/SExpr))]
  -> (Pair rd/SExpr (List lx/Token))
  :d "Read list or vector items up to the closing delimiter, which is consumed."
  (mt (list-head toks)
    ((some t)
     (if (= (.-raw-text t) close)
       (pair (if (= close ")")
               (rd/make-list (list-reverse acc))
               (rd/make-vect (list-reverse acc)))
             (tail-toks toks))
       (let [(sub (read-one toks))]
         (read-seq-items (.-second sub) close (list-cons (.-first sub) acc)))))
    ((none) (pair (rd/make-atom "") (list)))))

(df tail-toks [(toks (List lx/Token))] -> (List lx/Token)
  :d "The token list without its head; empty when absent."
  (mt (list-tail toks)
    ((some r) r)
    ((none)   (list))))

(df tail-exprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The SExpr list without its head; empty when absent."
  (mt (list-tail items)
    ((some r) r)
    ((none)   (list))))

(df sexpr-items [(s rd/SExpr)] -> (List rd/SExpr)
  :d "The elements of a list or vector SExpr; empty for an atom."
  (mt s
    ((rd/sexpr-list items) items)
    ((rd/sexpr-vect items) items)
    ((rd/sexpr-atom _)     (list))))

(df nth-expr [(items (List rd/SExpr)) (i Int64)] -> rd/SExpr
  :d "The i-th element of an SExpr list, or an empty atom."
  (mt (list-get items i)
    ((some s) s)
    ((none)   (rd/make-atom ""))))

(df nth-string [(items (List rd/SExpr)) (i Int64)] -> String
  :d "The i-th element rendered to its atom text."
  (rd/sexpr-head (nth-expr items i)))

(df atoms-to-strings [(xs (List rd/SExpr))] -> (List String)
  :d "Map every atom element to its text."
  (map (fn [(x rd/SExpr)] -> String (rd/sexpr-head x)) xs))

(df find-opt [(items (List rd/SExpr)) (key String)] -> (Option rd/SExpr)
  :d "The element after the keyword key, or none."
  (mt (list-head items)
    ((some it)
     (if (and (rd/is-atom? it) (= (rd/sexpr-head it) key))
       (list-head (tail-exprs items))
       (find-opt (tail-exprs items) key)))
    ((none) (none))))

(df list-head-text [(items (List rd/SExpr))] -> String
  :d "The head element's atom text, or the empty string."
  (mt (list-head items)
    ((some h) (rd/sexpr-head h))
    ((none)   "")))

(df build-module [(forms (List rd/SExpr))] -> (List TopForm)
  :d "Wrap the module header and every declaration into top forms."
  (mt (list-head forms)
    ((some mform)
     (let [(exported (module-exported mform))
           (decls (decl-forms (tail-exprs forms) exported (list)))
           (m (module-node mform decls))]
       (list-cons (top-module m) decls)))
    ((none) (list))))

(df module-exported [(m rd/SExpr)] -> (List String)
  :d "The module's exported names from its :export vector."
  (mt (find-opt (sexpr-items m) ":export")
    ((some v) (atoms-to-strings (sexpr-items v)))
    ((none)   (list))))

(df module-imports [(m rd/SExpr)] -> (List (Pair String String))
  :d "Import path and alias pairs from the :import list."
  (mt (find-opt (sexpr-items m) ":import")
    ((some v)
     (map (fn [(t rd/SExpr)] -> (Pair String String) (import-pair t))
          (filter (fn [(t rd/SExpr)] -> Bool (rd/is-list? t)) (sexpr-items v))))
    ((none) (list))))

(df import-pair [(t rd/SExpr)] -> (Pair String String)
  :d "One (path :as alias) form as a path/alias pair."
  (let [(items (sexpr-items t))]
    (pair (nth-string items 0) (nth-string items 2))))

(df module-node [(m rd/SExpr) (defs (List TopForm))] -> ModuleNode
  :d "The module header as a typed module node."
  (ModuleNode :docstring (mt (find-opt (sexpr-items m) ":doc")
                     ((some v) (rd/sexpr-head v))
                     ((none)   ""))
              :exported (module-exported m)
              :imports (module-imports m)
              :defs defs))

(df decl-forms [(sexprs (List rd/SExpr)) (exported (List String))
                   (acc (List TopForm))] -> (List TopForm)
  :d "Convert every declaration SExpr to a typed top form, in order."
  (mt (list-head sexprs)
    ((some s)
     (decl-forms (tail-exprs sexprs) exported
                 (list-cons (decl-form s exported) acc)))
    ((none) (list-reverse acc))))

(df decl-form [(s rd/SExpr) (exported (List String))] -> TopForm
  :d "Dispatch one declaration on its dual head."
  (cond
    ((rd/is-dual-head? s "defun" "df")      (top-defun (fun-node s exported)))
    ((rd/is-dual-head? s "defschema" "dfs") (top-schema (schema-node s)))
    ((rd/is-dual-head? s "defenum" "dfe")   (top-enum (enum-node s)))
    (:else (top-defun (retained-defun s)))))

(df retained-defun [(s rd/SExpr)] -> DefunNode
  :d "Hold an unclassified top-level form as a generic body SExpr."
  (DefunNode :name "" :type-vars (list) :is-exported false :effect false
             :params (list) :ret-type "" :docstring "" :body (list s)))

(df read-type-vars [(items (List rd/SExpr))]
  -> (Pair (List String) (List rd/SExpr))
  :d "Consume a leading { ... } type-parameter block, if present."
  (mt (list-head items)
    ((some h)
     (if (and (rd/is-atom? h) (= (rd/sexpr-head h) "{"))
       (collect-vars (tail-exprs items) (list))
       (pair (list) items)))
    ((none) (pair (list) items))))

(df collect-vars [(items (List rd/SExpr)) (acc (List String))]
  -> (Pair (List String) (List rd/SExpr))
  :d "Collect type-parameter names up to the closing brace."
  (mt (list-head items)
    ((some h)
     (if (= (rd/sexpr-head h) "}")
       (pair (list-reverse acc) (tail-exprs items))
       (collect-vars (tail-exprs items) (list-cons (rd/sexpr-head h) acc))))
    ((none) (pair (list-reverse acc) (list)))))

(df split-doc [(items (List rd/SExpr))] -> (Pair String (List rd/SExpr))
  :d "Split a leading :doc pair off a form's remaining items."
  (mt (list-head items)
    ((some h)
     (if (and (rd/is-atom? h) (= (rd/sexpr-head h) ":doc"))
       (mt (list-head (tail-exprs items))
         ((some d) (pair (rd/sexpr-head d) (tail-exprs (tail-exprs items))))
         ((none)   (pair "" (list))))
       (pair "" items)))
    ((none) (pair "" items))))

(df fun-node [(s rd/SExpr) (exported (List String))] -> DefunNode
  :d "Build a typed defun node from its SExpr form."
  (let [(items (sexpr-items s))
        (rest1 (tail-exprs items))
        (eff (mt (list-head rest1)
               ((some h) (and (rd/is-atom? h) (= (rd/sexpr-head h) "!")))
               ((none)   false)))
        (rest2 (if eff (tail-exprs rest1) rest1))
        (tv (read-type-vars rest2))
        (rest3 (.-second tv))
        (name (list-head-text rest3))
        (rest4 (tail-exprs rest3))
        (params (mt (list-head rest4)
                  ((some p) (param-list p))
                  ((none)   (list))))
        (rest5 (tail-exprs rest4))
        (ret (mt (list-head (tail-exprs rest5))
               ((some r) (rd/render-sexpr r))
               ((none)   "")))
        (rest6 (tail-exprs (tail-exprs rest5)))
        (docpart (split-doc rest6))
        (exp (list-contains? exported name))]
    (DefunNode :name name :type-vars (.-first tv) :is-exported exp
               :effect eff :params params :ret-type ret
               :docstring (.-first docpart) :body (.-second docpart))))

(df param-list [(v rd/SExpr)] -> (List Param)
  :d "Parameter records from a params vector."
  (map (fn [(p rd/SExpr)] -> Param (param-node p)) (sexpr-items v)))

(df param-node [(p rd/SExpr)] -> Param
  :d "One (name Type) parameter as a typed record."
  (let [(items (sexpr-items p))]
    (Param :name (nth-string items 0)
           :type (rd/render-sexpr (nth-expr items 1)))))

(df schema-node [(s rd/SExpr)] -> SchemaNode
  :d "Build a typed schema node from its SExpr form."
  (let [(items (sexpr-items s))
        (tv (read-type-vars (tail-exprs items)))
        (rest (.-second tv))
        (name (list-head-text rest))
        (fields (map (fn [(f rd/SExpr)] -> AstField (field-node f))
                     (filter (fn [(f rd/SExpr)] -> Bool (rd/is-list? f))
                             (tail-exprs rest))))
        (jc (mt (find-opt items ":json-case")
              ((some v) (some (rd/sexpr-head v)))
              ((none)   (none))))]
    (SchemaNode :name name :type-vars (.-first tv) :fields fields
                :json-case jc)))

(df field-node [(f rd/SExpr)] -> AstField
  :d "One (:field name Type doc ...) form as a typed record."
  (let [(items (sexpr-items f))]
    (AstField :name (nth-string items 1)
              :type (rd/render-sexpr (nth-expr items 2))
              :docstring (nth-string items 3)
              :default (opt-after-key items ":default")
              :json (opt-after-key items ":json"))))

(df opt-after-key [(items (List rd/SExpr)) (key String)] -> (Option String)
  :d "The value after a field option keyword, or none."
  (mt (find-opt items key)
    ((some v) (some (rd/sexpr-head v)))
    ((none)   (none))))

(df enum-node [(s rd/SExpr)] -> EnumNode
  :d "Build a typed enum node from its SExpr form."
  (let [(items (sexpr-items s))
        (tv (read-type-vars (tail-exprs items)))
        (rest (.-second tv))
        (name (list-head-text rest))
        (cases (filter (fn [(c rd/SExpr)] -> Bool (rd/is-list? c))
                       (tail-exprs rest)))]
    (EnumNode :name name :type-vars (.-first tv)
              :cases (map (fn [(c rd/SExpr)] -> EnumCase (case-node c)) cases))))

(df case-node [(c rd/SExpr)] -> EnumCase
  :d "One (:case name [fields] doc) form as a typed record."
  (let [(items (sexpr-items c))]
    (EnumCase :name (nth-string items 1)
              :fields (mt (list-get items 2)
                        ((some v) (param-list v))
                        ((none)   (list)))
              :docstring (nth-string items 3))))

(df render-node [(t TopForm)] -> String
  :d "Canonical verbose rendering of one typed top form."
  (mt t
    ((top-module m) (render-module m))
    ((top-schema s) (render-schema s))
    ((top-enum e)   (render-enum e))
    ((top-defun d)  (render-defun d))))

(df render-module [(m ModuleNode)] -> String
  :d "Canonical verbose module header text."
  (let [(exp (if (list-empty? (.-exported m))
               ""
               (str " :export [" (string-join (.-exported m) " ") "]")))
        (imp (if (list-empty? (.-imports m))
               ""
               (str " :import ["
                    (string-join (map (fn [(p (Pair String String))]
                                        -> String (render-import p))
                                      (.-imports m))
                                 " ")
                    "]")))]
    (str "(module :doc " (.-docstring m) exp imp ")")))

(df render-import [(p (Pair String String))] -> String
  :d "One import spec as canonical text."
  (str "(" (.-first p) " :as " (.-second p) ")"))

(df render-type-vars [(tv (List String))] -> String
  :d "A leading type-parameter block, empty when there are none."
  (if (list-empty? tv)
    ""
    (str "{" (string-join tv " ") "} ")))

(df render-joined [(xs (List String)) (prefix String)] -> String
  :d "Prefix plus space-joined items, empty when the list is empty."
  (if (list-empty? xs) "" (str prefix (string-join xs " "))))

(df render-defun [(d DefunNode)] -> String
  :d "Canonical verbose defun text."
  (let [(mark (if (.-effect d) "! " ""))
        (tv (render-type-vars (.-type-vars d)))
        (params (if (list-empty? (.-params d))
                  "[]"
                  (str "[" (string-join
                             (map (fn [(p Param)] -> String (render-param p))
                                  (.-params d))
                             " ") "]")))
        (docp (if (= (.-docstring d) "") "" (str " :doc " (.-docstring d))))
        (body (render-joined (map (fn [(b rd/SExpr)] -> String (rd/render-sexpr b))
                                  (.-body d))
                             " "))]
    (str "(defun " mark tv (.-name d) " " params " -> " (.-ret-type d)
         docp body ")")))

(df render-param [(p Param)] -> String
  :d "One parameter as canonical text."
  (str "(" (.-name p) " " (.-type p) ")"))

(df render-schema [(s SchemaNode)] -> String
  :d "Canonical verbose schema text."
  (let [(tv (render-type-vars (.-type-vars s)))
        (fields (render-joined (map (fn [(f AstField)] -> String (render-field f))
                                    (.-fields s))
                               " "))
        (jc (mt (.-json-case s)
              ((some v) (str " :json-case " v))
              ((none)   "")))]
    (str "(defschema " tv (.-name s) fields jc ")")))

(df render-field [(f AstField)] -> String
  :d "One field as canonical text."
  (let [(defp (mt (.-default f)
                ((some v) (str " :default " v))
                ((none)   "")))
        (jsonp (mt (.-json f)
                 ((some v) (str " :json " v))
                 ((none)   "")))]
    (str "(:field " (.-name f) " " (.-type f) " " (.-docstring f) defp jsonp ")")))

(df render-enum [(e EnumNode)] -> String
  :d "Canonical verbose enum text."
  (let [(tv (render-type-vars (.-type-vars e)))
        (cases (render-joined (map (fn [(c EnumCase)] -> String (render-case c))
                                   (.-cases e))
                              " "))]
    (str "(defenum " tv (.-name e) cases ")")))

(df render-case [(c EnumCase)] -> String
  :d "One case as canonical text."
  (let [(fields (if (list-empty? (.-fields c))
                  "[]"
                  (str "[" (string-join
                             (map (fn [(p Param)] -> String (render-param p))
                                  (.-fields c))
                             " ") "]")))]
    (str "(:case " (.-name c) " " fields " " (.-docstring c) ")")))
