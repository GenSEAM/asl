(module asl-parser/ast
  :d "Typed AST nodes for the four section-4 heads, parseable from either dialect."
  :x [ModuleNode SchemaNode EnumNode DefunNode EnumCase Param AstField
           TopForm ParseError parse render-node]
  :i [(lexer :a lx) (reader :a rd)])

(dfs ParseError
  (:f msg String "What the parser could not accept")
  (:f line Int64 "1-based source line of the offending token")
  (:f col Int64 "1-based source column of the offending token"))

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
  (:f path String "Module path as written after the module head")
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

"The Nano projection, mirroring prelude.json's `projection` section. It is
duplicated here because a parser written in AgentScript cannot read the JSON;
`tools/tests/test_native_parity.py` fails if the two tables disagree."
(df head-spellings [] -> (List String)
  :d "Every spelling accepted in head position, aligned with head-verbose-names."
  (list "defun" "def" "df"
        "defschema" "schema" "dfs"
        "defenum" "enum" "dfe"
        "match" "mt"
        ":field" ":f"
        ":case" ":c"))

(df head-verbose-names [] -> (List String)
  :d "The verbose spelling each entry of head-spellings names, in the same order."
  (list "defun" "defun" "defun"
        "defschema" "defschema" "defschema"
        "defenum" "defenum" "defenum"
        "match" "match"
        ":field" ":field"
        ":case" ":case"))

(df option-spellings [] -> (List String)
  :d "Every spelling accepted in an option slot, aligned with option-verbose-names."
  (list ":doc" ":d" ":export" ":x" ":import" ":i" ":as" ":a"))

(df option-verbose-names [] -> (List String)
  :d "The verbose spelling each entry of option-spellings names, in the same order."
  (list ":doc" ":doc" ":export" ":export" ":import" ":import" ":as" ":as"))

(df type-spellings [] -> (List String)
  :d "Every accepted type spelling, aligned with type-verbose-names."
  (list "Int" "I64" "I32" "F64" "F32" "Num" "Str" "Bool" "Unit" "Float"))

(df type-verbose-names [] -> (List String)
  :d "The Core spelling each entry of type-spellings names, in the same order."
  (list "Int64" "Int64" "Int32" "Float64" "Float64" "Float64" "String" "Bool"
        "Unit" "Float64"))

(df alias-lookup [(spellings (List String)) (verbs (List String)) (a String)]
  -> String
  :d "The verbose spelling a names in this table, or a unchanged."
  (mt (list-index-of spellings a)
    ((some i) (mt (list-get verbs i) ((some v) v) ((none) a)))
    ((none) a)))

(df head-verbose [(a String)] -> String
  :d "Resolve a head spelling; an alias is significant in head position only."
  (alias-lookup (head-spellings) (head-verbose-names) a))

(df option-verbose [(a String)] -> String
  :d "Resolve an option keyword; an alias is significant in an option slot only."
  (alias-lookup (option-spellings) (option-verbose-names) a))

(df type-verbose [(a String)] -> String
  :d "Resolve a type spelling; significant in type position only."
  (alias-lookup (type-spellings) (type-verbose-names) a))

(df resolve-type-text [(t String)] -> String
  :d "A rendered type with every name in its Core spelling.

  Done on the rendered text rather than the tree: a type holds nothing but names,
  parens and spaces, so splitting on those reaches every name without a second
  traversal — and without recursing once per type constructor."
  (let [(spaced (string-replace (string-replace t "(" " ( ") ")" " ) "))
        (words (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split spaced " ")))
        (mapped (string-join
                  (map (fn [(w String)] -> String (type-verbose w)) words) " "))]
    (string-replace (string-replace mapped "( " "(") " )" ")")))

(df char-at [(s String) (i Int64)] -> String
  :d "The single character at index i, or the empty string past the end."
  (mt (string-slice s i (+ i 1))
    ((some c) c)
    ((none)   "")))

(df chars-within? [(allowed String) (s String)] -> Bool
  :d "True when every character of s appears in allowed."
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (string-contains? allowed c)))
        true
        (string-chars s)))

(df drop-suffix [(s String)] -> String
  :d "s without a trailing ? or ! marker."
  (if (or (string-ends-with? s "?") (string-ends-with? s "!"))
    (mt (string-slice s 0 (- (string-length s) 1))
      ((some p) p)
      ((none)   ""))
    s))

(df kebab-ident? [(s String)] -> Bool
  :d "True for §2's ident shape: lowercase, digits and hyphens, optional ?/! tail."
  (let [(core (drop-suffix s))]
    (and (not (string-empty? core))
         (and (string-contains? "abcdefghijklmnopqrstuvwxyz" (char-at core 0))
              (chars-within? "abcdefghijklmnopqrstuvwxyz0123456789-" core)))))

(df pascal-name? [(s String)] -> Bool
  :d "True for §2's type-name shape: an uppercase head then alphanumerics."
  (and (not (string-empty? s))
       (and (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (char-at s 0))
            (chars-within?
              "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" s))))

(df mod-path? [(s String)] -> Bool
  :d "True for §2's mod-path shape: one or more kebab idents joined by '/'."
  (and (not (string-empty? s))
       (fold (fn [(acc Bool) (seg String)] -> Bool (and acc (kebab-ident? seg)))
             true
             (string-split s "/"))))

(dfs PosForm
  (:f expr rd/SExpr "One top-level form")
  (:f line Int64 "Line of the form's first token")
  (:f col Int64 "Column of the form's first token"))

(dfs Frame
  (:f items (List rd/SExpr) "Completed children, kept reversed")
  (:f paren Bool "True for a ( ) list, false for a [ ] vector")
  (:f line Int64 "Line of the opening delimiter")
  (:f col Int64 "Column of the opening delimiter"))

(dfs ReadState
  (:f stack (List Frame) "Open frames, innermost first")
  (:f out (List PosForm) "Completed top-level forms, kept reversed")
  (:f fail (Option ParseError) "The first error; once set nothing else is read"))

(df frame-tail [(fs (List Frame))] -> (List Frame)
  :d "The frame stack without its top; empty when absent."
  (option-or (list-tail fs) (list)))

(df tail-exprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The SExpr list without its head; empty when absent."
  (option-or (list-tail items) (list)))

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

(df list-head-text [(items (List rd/SExpr))] -> String
  :d "The head element's atom text, or the empty string."
  (mt (list-head items)
    ((some h) (rd/sexpr-head h))
    ((none)   "")))

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

(dfs OptScan
  (:f acc (List rd/SExpr) "Rewritten items, kept reversed")
  (:f pending-import Bool "The previous item was the :import keyword"))

(df norm-import-spec [(s rd/SExpr)] -> rd/SExpr
  :d "One (path :as alias) spec with its alias keyword spelled verbose."
  (let [(its (sexpr-items s))]
    (if (and (= (list-length its) 3) (= (option-verbose (nth-string its 1)) ":as"))
      (rd/make-list (list (nth-expr its 0) (rd/make-atom ":as") (nth-expr its 2)))
      s)))

(df norm-import-vect [(v rd/SExpr)] -> rd/SExpr
  :d "The :import vector with every spec normalized; anything else untouched."
  (mt v
    ((rd/sexpr-vect specs)
     (rd/make-vect (map (fn [(s rd/SExpr)] -> rd/SExpr (norm-import-spec s)) specs)))
    ((rd/sexpr-list _) v)
    ((rd/sexpr-atom _) v)))

(df norm-option-step [(st OptScan) (x rd/SExpr)] -> OptScan
  :d "Fold step over a declaration's own items, rewriting option keywords only."
  (if (.-pending-import st)
    (OptScan :acc (list-cons (norm-import-vect x) (.-acc st)) :pending-import false)
    (if (rd/is-atom? x)
      (let [(v (option-verbose (rd/sexpr-head x)))]
        (OptScan :acc (list-cons (rd/make-atom v) (.-acc st))
                 :pending-import (= v ":import")))
      (OptScan :acc (list-cons x (.-acc st)) :pending-import false))))

(df norm-options [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Rewrite the option keywords in one declaration's own slots."
  (list-reverse
    (.-acc (fold norm-option-step (OptScan :acc (list) :pending-import false) items))))

(df takes-options? [(head String)] -> Bool
  :d "The two heads whose own slots admit an aliased option keyword."
  (or (= head "module") (= head "defun")))

(df normalize-form [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Resolve a Nano head, and the option keywords that head's own slots admit.

  Position is the whole point: a record key spelled :x is an ordinary keyword
  because no option slot of a module or defun is where it sits."
  (mt (list-head items)
    ((some h)
     (if (rd/is-atom? h)
       (let [(v (head-verbose (rd/sexpr-head h)))
             (rest (tail-exprs items))]
         (list-cons (rd/make-atom v)
                    (if (takes-options? v) (norm-options rest) rest)))
       items))
    ((none) items)))

(df form-defect [(items (List rd/SExpr))] -> String
  :d "A message when a nested form is illegal where it stands, else empty."
  (if (and (= (list-head-text items) "fn") (= (nth-string items 1) "{"))
    "a lambda takes neither type parameters nor :doc"
    ""))

(df read-fail [(st ReadState) (msg String) (line Int64) (col Int64)] -> ReadState
  :d "The read state carrying its first error."
  (ReadState :stack (.-stack st) :out (.-out st)
             :fail (some (ParseError :msg msg :line line :col col))))

(df emit-node [(st ReadState) (node rd/SExpr) (line Int64) (col Int64)] -> ReadState
  :d "Add a completed node to the innermost open frame, or to the top level."
  (mt (list-head (.-stack st))
    ((some f)
     (ReadState :stack (list-cons (Frame :items (list-cons node (.-items f))
                                         :paren (.-paren f)
                                         :line (.-line f) :col (.-col f))
                                  (frame-tail (.-stack st)))
                :out (.-out st)
                :fail (none)))
    ((none)
     (ReadState :stack (list)
                :out (list-cons (PosForm :expr node :line line :col col) (.-out st))
                :fail (none)))))

(df push-frame [(st ReadState) (paren Bool) (t lx/Token)] -> ReadState
  :d "Open a frame for a ( or [ delimiter."
  (ReadState :stack (list-cons (Frame :items (list) :paren paren
                                      :line (.-line t) :col (.-col t))
                               (.-stack st))
             :out (.-out st)
             :fail (none)))

(df finish-frame [(st ReadState) (f Frame) (t lx/Token)] -> ReadState
  :d "Close the innermost frame into a node and hand it to its parent."
  (let [(items (list-reverse (.-items f)))
        (defect (if (.-paren f) (form-defect items) ""))
        (node (if (.-paren f)
                (rd/make-list (normalize-form items))
                (rd/make-vect items)))
        (popped (ReadState :stack (frame-tail (.-stack st))
                           :out (.-out st) :fail (none)))]
    (if (= defect "")
      (emit-node popped node (.-line f) (.-col f))
      (read-fail st defect (.-line t) (.-col t)))))

(df close-frame [(st ReadState) (paren Bool) (t lx/Token)] -> ReadState
  :d "Consume a ) or ] delimiter, which must close a frame of the same shape."
  (mt (list-head (.-stack st))
    ((some f)
     (if (= (.-paren f) paren)
       (finish-frame st f t)
       (read-fail st (str "mismatched closing delimiter '" (.-raw-text t) "'")
                  (.-line t) (.-col t))))
    ((none) (read-fail st (str "unexpected closing delimiter '" (.-raw-text t) "'")
                       (.-line t) (.-col t)))))

(df finish-read [(st ReadState)] -> ReadState
  :d "At end of input every frame must have been closed."
  (mt (list-head (.-stack st))
    ((some f) (read-fail st "unclosed delimiter" (.-line f) (.-col f)))
    ((none)   st)))

(df read-token [(st ReadState) (t lx/Token)] -> ReadState
  :d "One token of the scan: a delimiter moves the frame stack, anything else is an atom."
  (mt (.-kind t)
    ((lx/tok-lparen)   (push-frame st true t))
    ((lx/tok-lbracket) (push-frame st false t))
    ((lx/tok-rparen)   (close-frame st true t))
    ((lx/tok-rbracket) (close-frame st false t))
    ((lx/tok-eof)      (finish-read st))
    ((lx/tok-error m)  (read-fail st m (.-line t) (.-col t)))
    (_ (emit-node st (rd/make-atom (.-raw-text t)) (.-line t) (.-col t)))))

(df read-step [(st ReadState) (t lx/Token)] -> ReadState
  :d "Fold step over the token stream; the first error stops the read."
  (mt (.-fail st)
    ((some _) st)
    ((none)   (read-token st t))))

(df read-forms [(toks (List lx/Token))] -> (Result (List PosForm) ParseError)
  :d "Read every top-level form with an explicit frame stack, never by recursion."
  (let [(st (fold read-step
                  (ReadState :stack (list) :out (list) :fail (none))
                  toks))]
    (mt (.-fail st)
      ((some e) (err e))
      ((none)   (ok (list-reverse (.-out st)))))))

(df perr [(msg String) (pf PosForm)] -> ParseError
  :d "An error located at the start of the form that carries it."
  (ParseError :msg msg :line (.-line pf) :col (.-col pf)))

(df parse [(src String)] -> (Result (List TopForm) ParseError)
  :d "Tokenize and parse a module source into typed top forms."
  (let [(forms (try (read-forms (lx/tokenize src))))]
    (build-module forms)))

(df module-form? [(pf PosForm)] -> Bool
  :d "True when a top-level form is the module header."
  (and (rd/is-list? (.-expr pf)) (= (rd/sexpr-head (.-expr pf)) "module")))

(df second-form [(forms (List PosForm))] -> (Option PosForm)
  :d "The second element of a form list, or none."
  (mt (list-tail forms)
    ((some r) (list-head r))
    ((none)   (none))))

(df module-path [(mods (List PosForm))] -> (Result String ParseError)
  :d "The module path, or an error when no header names one.

  A second header is rejected rather than dropped: a file has one module surface,
  and silently keeping the first is how a header stops meaning anything."
  (mt (second-form mods)
    ((some extra) (err (perr "a second module header" extra)))
    ((none)
     (mt (list-head mods)
       ((some m)
        (let [(p (nth-string (sexpr-items (.-expr m)) 1))]
          (if (mod-path? p)
            (ok p)
            (err (perr "module header needs a path" m)))))
       ((none) (ok ""))))))

(df build-module [(forms (List PosForm))] -> (Result (List TopForm) ParseError)
  :d "Wrap the module header, when present, and every declaration into top forms."
  (let [(mods (filter (fn [(p PosForm)] -> Bool (module-form? p)) forms))
        (rest (filter (fn [(p PosForm)] -> Bool (not (module-form? p))) forms))
        (path (try (module-path mods)))
        (exported (mt (list-head mods)
                    ((some m) (module-exported (.-expr m)))
                    ((none)   (list))))
        (decls (try (decl-forms rest exported)))]
    (mt (list-head mods)
      ((some m) (ok (list-cons (top-module (module-node (.-expr m) path decls)) decls)))
      ((none)   (ok decls)))))

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

(df module-node [(m rd/SExpr) (path String) (defs (List TopForm))] -> ModuleNode
  :d "The module header as a typed module node."
  (ModuleNode :path path
              :docstring (mt (find-opt (sexpr-items m) ":doc")
                           ((some v) (rd/sexpr-head v))
                           ((none)   ""))
              :exported (module-exported m)
              :imports (module-imports m)
              :defs defs))

(df is-tag? [(s rd/SExpr)] -> Bool
  :d "True when an SExpr is a (:tag ...) or (@tag ...) metadata form."
  (and (rd/is-list? s)
       (let [(h (rd/sexpr-head s))]
         (or (= h ":tag") (= h "@tag")))))

(df decl-step [(acc (Result (List TopForm) ParseError)) (pf PosForm)
                  (exported (List String))]
  -> (Result (List TopForm) ParseError)
  :d "Add one converted declaration, keeping the first error. Bare strings are comments."
  (mt acc
    ((err e) (err e))
    ((ok xs)
     (let [(s (.-expr pf))]
       (if (or (and (rd/is-atom? s) (string-starts-with? (rd/sexpr-head s) "\""))
               (is-tag? s))
         (ok xs)
         (mt (decl-form pf exported)
           ((ok t)  (ok (list-cons t xs)))
           ((err e) (err e))))))))

(df decl-forms [(forms (List PosForm)) (exported (List String))]
  -> (Result (List TopForm) ParseError)
  :d "Convert every declaration to a typed top form, in order, or fail."
  (result-map (fn [(xs (List TopForm))] -> (List TopForm) (list-reverse xs))
              (fold (fn [(acc (Result (List TopForm) ParseError)) (pf PosForm)]
                      -> (Result (List TopForm) ParseError)
                      (decl-step acc pf exported))
                    (ok (list))
                    forms)))

(df decl-form [(pf PosForm) (exported (List String))] -> (Result TopForm ParseError)
  :d "Dispatch one top-level declaration on its normalized head."
  (let [(s (.-expr pf))
        (h (rd/sexpr-head s))]
    (cond
      ((not (rd/is-list? s))
       (err (perr "expected a top-level declaration" pf)))
      ((= h "defun")     (fun-node s exported pf))
      ((= h "defschema") (schema-node s pf))
      ((= h "defenum")   (enum-node s pf))
      (:else (err (perr (str "not a declaration head: '" h "'") pf))))))

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

(df filter-tags [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Remove metadata tag forms from an expression list."
  (filter (fn [(x rd/SExpr)] -> Bool (not (is-tag? x))) items))

(df split-doc [(items (List rd/SExpr))] -> (Pair String (List rd/SExpr))
  :d "Split a leading :doc pair off a form's remaining items, dropping tags."
  (mt (list-head items)
    ((some h)
     (cond
       ((is-tag? h) (split-doc (tail-exprs items)))
       ((and (rd/is-atom? h) (= (rd/sexpr-head h) ":doc"))
        (mt (list-head (tail-exprs items))
          ((some d) (pair (rd/sexpr-head d) (filter-tags (tail-exprs (tail-exprs items)))))
          ((none)   (pair "" (list)))))
       (:else (pair "" (filter-tags items)))))
    ((none) (pair "" (list)))))

(df params-vector? [(v (Option rd/SExpr))] -> Bool
  :d "True when a defun's parameter slot holds a [ ] vector."
  (mt v
    ((some p) (rd/is-vect? p))
    ((none)   false)))

(df fun-node [(s rd/SExpr) (exported (List String)) (pf PosForm)]
  -> (Result TopForm ParseError)
  :d "Build a typed defun node from its SExpr form, or reject the signature."
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
        (pslot (list-head rest4))
        (params (mt pslot
                  ((some p) (param-list p))
                  ((none)   (list))))
        (rest5 (tail-exprs rest4))
        (arrow (list-head-text rest5))
        (ret (mt (list-head (tail-exprs rest5))
               ((some r) (resolve-type-text (rd/render-sexpr r)))
               ((none)   "")))
        (docpart (split-doc (tail-exprs (tail-exprs rest5))))]
    (cond
      ((not (kebab-ident? name))
       (err (perr (str "defun name is not kebab-case: '" name "'") pf)))
      ((not (params-vector? pslot))
       (err (perr "defun parameters must be a [ ] vector" pf)))
      ((not (= arrow "->"))
       (err (perr "defun return type must be introduced by ->" pf)))
      ((string-empty? ret)
       (err (perr "defun has no return type" pf)))
      ((list-empty? (.-second docpart))
       (err (perr "defun has no body" pf)))
      (:else
       (ok (top-defun (DefunNode :name name :type-vars (.-first tv)
                                 :is-exported (list-contains? exported name)
                                 :effect eff :params params :ret-type ret
                                 :docstring (.-first docpart)
                                 :body (.-second docpart))))))))

(df param-list [(v rd/SExpr)] -> (List Param)
  :d "Parameter records from a params vector."
  (map (fn [(p rd/SExpr)] -> Param (param-node p)) (sexpr-items v)))

(df param-node [(p rd/SExpr)] -> Param
  :d "One (name Type) parameter as a typed record."
  (let [(items (sexpr-items p))]
    (Param :name (nth-string items 0)
           :type (resolve-type-text (rd/render-sexpr (nth-expr items 1))))))

(df all-heads? [(forms (List rd/SExpr)) (head String)] -> Bool
  :d "True when every form carries the given head."
  (fold (fn [(acc Bool) (f rd/SExpr)] -> Bool
          (and acc (= (rd/sexpr-head f) head)))
        true
        forms))

(df schema-node [(s rd/SExpr) (pf PosForm)] -> (Result TopForm ParseError)
  :d "Build a typed schema node from its SExpr form, or reject its shape."
  (let [(items (sexpr-items s))
        (tv (read-type-vars (tail-exprs items)))
        (rest (.-second tv))
        (name (list-head-text rest))
        (fforms (filter (fn [(f rd/SExpr)] -> Bool (and (rd/is-list? f) (not (is-tag? f)))) (tail-exprs rest)))
        (jc (mt (find-opt items ":json-case")
              ((some v) (some (rd/sexpr-head v)))
              ((none)   (none))))]
    (cond
      ((not (pascal-name? name))
       (err (perr (str "defschema name is not PascalCase: '" name "'") pf)))
      ((list-empty? fforms)
       (err (perr "defschema needs at least one field" pf)))
      ((not (all-heads? fforms ":field"))
       (err (perr "every defschema member must be a (:field ...) form" pf)))
      (:else
       (ok (top-schema (SchemaNode :name name :type-vars (.-first tv)
                                   :fields (map (fn [(f rd/SExpr)] -> AstField
                                                  (field-node f))
                                                fforms)
                                   :json-case jc)))))))

(df field-node [(f rd/SExpr)] -> AstField
  :d "One (:field name Type doc ...) form as a typed record."
  (let [(items (sexpr-items f))]
    (AstField :name (nth-string items 1)
              :type (resolve-type-text (rd/render-sexpr (nth-expr items 2)))
              :docstring (nth-string items 3)
              :default (opt-after-key items ":default")
              :json (opt-after-key items ":json"))))

(df opt-after-key [(items (List rd/SExpr)) (key String)] -> (Option String)
  :d "The value after a field option keyword, or none."
  (mt (find-opt items key)
    ((some v) (some (rd/sexpr-head v)))
    ((none)   (none))))

(df enum-node [(s rd/SExpr) (pf PosForm)] -> (Result TopForm ParseError)
  :d "Build a typed enum node from its SExpr form, or reject its shape."
  (let [(items (sexpr-items s))
        (tv (read-type-vars (tail-exprs items)))
        (rest (.-second tv))
        (name (list-head-text rest))
        (cforms (filter (fn [(c rd/SExpr)] -> Bool (and (rd/is-list? c) (not (is-tag? c)))) (tail-exprs rest)))]
    (cond
      ((not (pascal-name? name))
       (err (perr (str "defenum name is not PascalCase: '" name "'") pf)))
      ((list-empty? cforms)
       (err (perr "defenum needs at least one case" pf)))
      ((not (all-heads? cforms ":case"))
       (err (perr "every defenum member must be a (:case ...) form" pf)))
      (:else
       (ok (top-enum (EnumNode :name name :type-vars (.-first tv)
                               :cases (map (fn [(c rd/SExpr)] -> EnumCase (case-node c))
                                           cforms))))))))

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
  (let [(doc (if (string-empty? (.-docstring m))
               ""
               (str " :doc " (.-docstring m))))
        (exp (if (list-empty? (.-exported m))
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
    (str "(module " (.-path m) doc exp imp ")")))

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
  :d "Canonical verbose schema text.

  :json-case leads the fields because that is the one place the grammar's
  `schema_opt*` sits; the parser still reads it wherever it was written."
  (let [(tv (render-type-vars (.-type-vars s)))
        (fields (render-joined (map (fn [(f AstField)] -> String (render-field f))
                                    (.-fields s))
                               " "))
        (jc (mt (.-json-case s)
              ((some v) (str " :json-case " v))
              ((none)   "")))]
    (str "(defschema " tv (.-name s) jc fields ")")))

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
