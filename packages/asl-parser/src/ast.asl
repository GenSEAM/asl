(module asl-parser/ast
  :d "Typed AST nodes for the four section-4 heads, parseable from either dialect."
  :x [ModuleNode SchemaNode EnumNode DefunNode EnumCase Param AstField
           TopForm ParseError parse renderNode
           AstLit litInt litFloat litString litBool litUnit
           AstPattern patWildcard patVar patLit patTuple patRecord patCtor
           AstMatchArm matchArm makeMatchArm
           AstExpr exprLit exprIdent exprMember exprCall exprLet exprIf exprMatch exprTry exprBlock
           AstType typeNamed typeTuple typeRecord typeFn]
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
  (:f typeVars (List String) "Type variables bound in the leading { }")
  (:f fields (List AstField) "Record fields, in source order")
  (:f jsonCase (Option String) "Schema :json-case, or none meaning kebab"))

(dfs EnumNode
  (:f name String "Enum name")
  (:f typeVars (List String) "Type variables bound in the leading { }")
  (:f cases (List EnumCase) "Enum cases, in source order"))

(dfs DefunNode
  (:f name String "Function name")
  (:f typeVars (List String) "Type variables bound in the leading { }")
  (:f isExported Bool "True when the owning module :export vector names it")
  (:f effect Bool "True when the signature carries the ! marker")
  (:f params (List Param) "Parameters from the [ ... ] vector form")
  (:f retType String "Return type annotation as canonical single-space text")
  (:f docstring String "Doc string, as written including quotes, empty when absent")
  (:f body (List rd/SExpr) "Body forms, retained as generic SExpr"))

(dfe TopForm
  (:c topModule [(node ModuleNode)] "A module declaration")
  (:c topSchema [(node SchemaNode)] "A defschema declaration")
  (:c topEnum   [(node EnumNode)] "A defenum declaration")
  (:c topDefun  [(node DefunNode)] "A defun declaration"))

(dfe AstLit
  (:c litInt    [(val Int64)])
  (:c litFloat  [(val Float64)])
  (:c litString [(val String)])
  (:c litBool   [(val Bool)])
  (:c litUnit   []))

(dfe AstPattern
  (:c patWildcard [] "Wildcard _")
  (:c patVar      [(name String)] "Variable binding")
  (:c patLit      [(lit AstLit)] "Literal pattern")
  (:c patTuple    [(elements (List AstPattern))] "Tuple/list pattern")
  (:c patRecord   [(fields (List (Pair String AstPattern)))] "Record pattern")
  (:c patCtor     [(name String) (arg (Option AstPattern))] "Constructor pattern"))

(dfs AstMatchArm
  (:f pat AstPattern)
  (:f body AstExpr))

(dfe AstExpr
  (:c exprLit    [(lit AstLit)] "Literal constant")
  (:c exprIdent  [(name String)] "Variable or symbol reference")
  (:c exprMember [(target AstExpr) (field String)] "Record/schema field access target.field")
  (:c exprCall   [(func AstExpr) (args (List AstExpr))] "Function or constructor call")
  (:c exprLet    [(bindings (List (Pair AstPattern AstExpr))) (body (List AstExpr))] "Let binding form")
  (:c exprIf     [(cond AstExpr) (thenBranch AstExpr) (elseBranch AstExpr)] "Conditional branch")
  (:c exprMatch  [(target AstExpr) (arms (List AstMatchArm))] "Pattern match form")
  (:c exprTry    [(inner AstExpr)] "Error propagation try operator expr?")
  (:c exprBlock  [(exprs (List AstExpr))] "Block of sequential expressions"))

(dfe AstType
  (:c typeNamed  [(name String)])
  (:c typeTuple  [(elements (List AstType))])
  (:c typeRecord [(fields (List (Pair String AstType)))])
  (:c typeFn     [(paramTypes (List AstType)) (retType AstType)]))

(df matchArm [(pat AstPattern) (body AstExpr)] -> AstMatchArm
  :d "Constructs an AstMatchArm record."
  (AstMatchArm :pat pat :body body))

(df makeMatchArm [(pat AstPattern) (body AstExpr)] -> AstMatchArm
  :d "Constructs an AstMatchArm record."
  (AstMatchArm :pat pat :body body))

"The Nano projection, mirroring prelude.json's `projection` section. It is
duplicated here because a parser written in AgentScript cannot read the JSON;
`tools/tests/test_native_parity.py` fails if the two tables disagree."
(df headSpellings [] -> (List String)
  :d "Every spelling accepted in head position, aligned with head-verbose-names."
  (list "defun" "def" "df"
        "defschema" "schema" "dfs"
        "defenum" "enum" "dfe"
        "match" "mt"
        ":field" ":f"
        ":case" ":c"))

(df headVerboseNames [] -> (List String)
  :d "The verbose spelling each entry of head-spellings names, in the same order."
  (list "defun" "defun" "defun"
        "defschema" "defschema" "defschema"
        "defenum" "defenum" "defenum"
        "match" "match"
        ":field" ":field"
        ":case" ":case"))

(df optionSpellings [] -> (List String)
  :d "Every spelling accepted in an option slot, aligned with option-verbose-names."
  (list ":doc" ":d" ":export" ":x" ":import" ":i" ":as" ":a"))

(df optionVerboseNames [] -> (List String)
  :d "The verbose spelling each entry of option-spellings names, in the same order."
  (list ":doc" ":doc" ":export" ":export" ":import" ":import" ":as" ":as"))

(df typeSpellings [] -> (List String)
  :d "Every accepted type spelling, aligned with type-verbose-names."
  (list "Int" "I64" "I32" "F64" "F32" "Num" "Str" "Bool" "Unit" "Float"))

(df typeVerboseNames [] -> (List String)
  :d "The Core spelling each entry of type-spellings names, in the same order."
  (list "Int64" "Int64" "Int32" "Float64" "Float64" "Float64" "String" "Bool"
        "Unit" "Float64"))

(df aliasLookup [(spellings (List String)) (verbs (List String)) (a String)]
  -> String
  :d "The verbose spelling a names in this table, or a unchanged."
  (mt (list-index-of spellings a)
    ((some i) (option-or (list-get verbs i) a))
    ((none) a)))

(df headVerbose [(a String)] -> String
  :d "Resolve a head spelling; an alias is significant in head position only."
  (aliasLookup (headSpellings) (headVerboseNames) a))

(df optionVerbose [(a String)] -> String
  :d "Resolve an option keyword; an alias is significant in an option slot only."
  (aliasLookup (optionSpellings) (optionVerboseNames) a))

(df typeVerbose [(a String)] -> String
  :d "Resolve a type spelling; significant in type position only."
  (aliasLookup (typeSpellings) (typeVerboseNames) a))

(df resolveTypeText [(t String)] -> String
  :d "A rendered type with every name in its Core spelling.

  Done on the rendered text rather than the tree: a type holds nothing but names,
  parens and spaces, so splitting on those reaches every name without a second
  traversal — and without recursing once per type constructor."
  (let [(spaced (string-replace (string-replace t "(" " ( ") ")" " ) "))
        (words (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split spaced " ")))
        (mapped (string-join
                  (map (fn [(w String)] -> String (typeVerbose w)) words) " "))]
    (string-replace (string-replace mapped "( " "(") " )" ")")))

(df charsWithin? [(allowed String) (s String)] -> Bool
  :d "True when every character of s appears in allowed."
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (string-contains? allowed c)))
        true
        (string-chars s)))

(df dropSuffix [(s String)] -> String
  :d "s without a trailing ? or ! marker."
  (if (or (string-ends-with? s "?") (string-ends-with? s "!"))
    (option-or (string-slice s 0 (- (string-length s) 1)) "")
    s))

(df kebabIdent? [(s String)] -> Bool
  :d "True for §2's ident shape: lowercase, digits and hyphens, optional ?/! tail."
  (let [(core (dropSuffix s))]
    (and (not (string-empty? core))
         (and (string-contains? "abcdefghijklmnopqrstuvwxyz" (lx/charAt core 0))
              (charsWithin? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" core)))))

(df pascalName? [(s String)] -> Bool
  :d "True for §2's type-name shape: an uppercase head then alphanumerics."
  (and (not (string-empty? s))
       (and (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (lx/charAt s 0))
            (charsWithin?
              "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" s))))

(df modPath? [(s String)] -> Bool
  :d "True for §2's mod-path shape: one or more kebab idents joined by '/'."
  (and (not (string-empty? s))
       (fold (fn [(acc Bool) (seg String)] -> Bool (and acc (kebabIdent? seg)))
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

(df frameTail [(fs (List Frame))] -> (List Frame)
  :d "The frame stack without its top; empty when absent."
  (option-or (list-tail fs) (list)))

(df tailExprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The SExpr list without its head; empty when absent."
  (option-or (list-tail items) (list)))

(df sexprItems [(s rd/SExpr)] -> (List rd/SExpr)
  :d "The elements of a list or vector SExpr; empty for an atom."
  (mt s
    ((rd/sexprList items) items)
    ((rd/sexprVect items) items)
    ((rd/sexprAtom _)     (list))))

(df nthExpr [(items (List rd/SExpr)) (i Int64)] -> rd/SExpr
  :d "The i-th element of an SExpr list, or an empty atom."
  (mt (list-get items i)
    ((some node) node)
    ((none)      (rd/makeAtom ""))))

(df nthString [(items (List rd/SExpr)) (i Int64)] -> String
  :d "The i-th element rendered to its atom text."
  (rd/sexprHead (nthExpr items i)))

(df listHeadText [(items (List rd/SExpr))] -> String
  :d "The head element's atom text, or the empty string."
  (mt (list-head items)
    ((some h) (rd/sexprHead h))
    ((none)   "")))

(df atomsToStrings [(xs (List rd/SExpr))] -> (List String)
  :d "Map every atom element to its text."
  (map (fn [(x rd/SExpr)] -> String (rd/sexprHead x)) xs))

(df findOpt [(items (List rd/SExpr)) (key String)] -> (Option rd/SExpr)
  :d "The element after the keyword key, or none."
  (mt (list-head items)
    ((some it)
     (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
       (list-head (tailExprs items))
       (findOpt (tailExprs items) key)))
    ((none) (none))))

(dfs OptScan
  (:f acc (List rd/SExpr) "Rewritten items, kept reversed")
  (:f pendingImport Bool "The previous item was the :import keyword"))

(df normImportSpec [(s rd/SExpr)] -> rd/SExpr
  :d "One (path :as alias) spec with its alias keyword spelled verbose."
  (let [(its (sexprItems s))]
    (if (and (= (list-length its) 3) (= (optionVerbose (nthString its 1)) ":as"))
      (rd/makeList (list (nthExpr its 0) (rd/makeAtom ":as") (nthExpr its 2)))
      s)))

(df normImportVect [(v rd/SExpr)] -> rd/SExpr
  :d "The :import vector with every spec normalized; anything else untouched."
  (mt v
    ((rd/sexprVect specs)
     (rd/makeVect (map (fn [(s rd/SExpr)] -> rd/SExpr (normImportSpec s)) specs)))
    ((rd/sexprList _) v)
    ((rd/sexprAtom _) v)))

(df normOptionStep [(st OptScan) (x rd/SExpr)] -> OptScan
  :d "Fold step over a declaration's own items, rewriting option keywords only."
  (if (.-pendingImport st)
    (OptScan :acc (list-cons (normImportVect x) (.-acc st)) :pendingImport false)
    (if (rd/isAtom? x)
      (let [(v (optionVerbose (rd/sexprHead x)))]
        (OptScan :acc (list-cons (rd/makeAtom v) (.-acc st))
                 :pendingImport (= v ":import")))
      (OptScan :acc (list-cons x (.-acc st)) :pendingImport false))))

(df normOptions [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Rewrite the option keywords in one declaration's own slots."
  (list-reverse
    (.-acc (fold normOptionStep (OptScan :acc (list) :pendingImport false) items))))

(df takesOptions? [(head String)] -> Bool
  :d "The two heads whose own slots admit an aliased option keyword."
  (or (= head "module") (= head "defun")))

(df normalizeForm [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Resolve a Nano head, and the option keywords that head's own slots admit.

  Position is the whole point: a record key spelled :x is an ordinary keyword
  because no option slot of a module or defun is where it sits."
  (mt (list-head items)
    ((some h)
     (if (rd/isAtom? h)
       (let [(v (headVerbose (rd/sexprHead h)))
             (rest (tailExprs items))]
         (list-cons (rd/makeAtom v)
                    (if (takesOptions? v) (normOptions rest) rest)))
       items))
    ((none) items)))

(df formDefect [(items (List rd/SExpr))] -> String
  :d "A message when a nested form is illegal where it stands, else empty."
  (if (and (= (listHeadText items) "fn") (= (nthString items 1) "{"))
    "a lambda takes neither type parameters nor :doc"
    ""))

(df readFail [(st ReadState) (msg String) (line Int64) (col Int64)] -> ReadState
  :d "The read state carrying its first error."
  (ReadState :stack (.-stack st) :out (.-out st)
             :fail (some (ParseError :msg msg :line line :col col))))

(df emitNode [(st ReadState) (node rd/SExpr) (line Int64) (col Int64)] -> ReadState
  :d "Add a completed node to the innermost open frame, or to the top level."
  (mt (list-head (.-stack st))
    ((some f)
     (ReadState :stack (list-cons (Frame :items (list-cons node (.-items f))
                                         :paren (.-paren f)
                                         :line (.-line f) :col (.-col f))
                                  (frameTail (.-stack st)))
                :out (.-out st)
                :fail (none)))
    ((none)
     (ReadState :stack (list)
                :out (list-cons (PosForm :expr node :line line :col col) (.-out st))
                :fail (none)))))

(df pushFrame [(st ReadState) (paren Bool) (t lx/Token)] -> ReadState
  :d "Open a frame for a ( or [ delimiter."
  (ReadState :stack (list-cons (Frame :items (list) :paren paren
                                      :line (.-line t) :col (.-col t))
                               (.-stack st))
             :out (.-out st)
             :fail (none)))

(df finishFrame [(st ReadState) (f Frame) (t lx/Token)] -> ReadState
  :d "Close the innermost frame into a node and hand it to its parent."
  (let [(items (list-reverse (.-items f)))
        (defect (if (.-paren f) (formDefect items) ""))
        (node (if (.-paren f)
                (rd/makeList (normalizeForm items))
                (rd/makeVect items)))
        (popped (ReadState :stack (frameTail (.-stack st))
                           :out (.-out st) :fail (none)))]
    (if (= defect "")
      (emitNode popped node (.-line f) (.-col f))
      (readFail st defect (.-line t) (.-col t)))))

(df closeFrame [(st ReadState) (paren Bool) (t lx/Token)] -> ReadState
  :d "Consume a ) or ] delimiter, which must close a frame of the same shape."
  (mt (list-head (.-stack st))
    ((some f)
     (if (= (.-paren f) paren)
       (finishFrame st f t)
       (readFail st (str "mismatched closing delimiter '" (.-rawText t) "'")
                  (.-line t) (.-col t))))
    ((none) (readFail st (str "unexpected closing delimiter '" (.-rawText t) "'")
                       (.-line t) (.-col t)))))

(df finishRead [(st ReadState)] -> ReadState
  :d "At end of input every frame must have been closed."
  (mt (list-head (.-stack st))
    ((some f) (readFail st "unclosed delimiter" (.-line f) (.-col f)))
    ((none)   st)))

(df readToken [(st ReadState) (t lx/Token)] -> ReadState
  :d "One token of the scan: a delimiter moves the frame stack, anything else is an atom."
  (mt (.-kind t)
    ((lx/tokLparen)   (pushFrame st true t))
    ((lx/tokLbracket) (pushFrame st false t))
    ((lx/tokRparen)   (closeFrame st true t))
    ((lx/tokRbracket) (closeFrame st false t))
    ((lx/tokEof)      (finishRead st))
    ((lx/tokError m)  (readFail st m (.-line t) (.-col t)))
    (_ (emitNode st (rd/makeAtom (.-rawText t)) (.-line t) (.-col t)))))

(df readStep [(st ReadState) (t lx/Token)] -> ReadState
  :d "Fold step over the token stream; the first error stops the read."
  (mt (.-fail st)
    ((some _) st)
    ((none)   (readToken st t))))

(df readForms [(toks (List lx/Token))] -> (Result (List PosForm) ParseError)
  :d "Read every top-level form with an explicit frame stack, never by recursion."
  (let [(st (fold readStep
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
  (mt (readForms (lx/tokenize src))
    ((err e) (err e))
    ((ok forms) (buildModule forms))))

(df moduleForm? [(pf PosForm)] -> Bool
  :d "True when a top-level form is the module header."
  (and (rd/isList? (.-expr pf)) (= (rd/sexprHead (.-expr pf)) "module")))

(df secondForm [(forms (List PosForm))] -> (Option PosForm)
  :d "The second element of a form list, or none."
  (mt (list-tail forms)
    ((some r) (list-head r))
    ((none)   (none))))

(df checkModPath [(m PosForm)] -> (Result String ParseError)
  :d "Checks that module form has a valid path."
  (let [(p (nthString (sexprItems (.-expr m)) 1))]
    (if (modPath? p)
      (ok p)
      (err (perr "module header needs a path" m)))))

(df modulePath [(mods (List PosForm))] -> (Result String ParseError)
  :d "The module's declaring path or empty string when omitted.

  A second header is rejected rather than dropped: a file has one module surface,
  and silently keeping the first is how a header stops meaning anything."
  (mt (secondForm mods)
    ((some extra) (err (perr "a second module header" extra)))
    ((none)
     (mt (list-head mods)
       ((some m) (checkModPath m))
       ((none) (ok ""))))))

(df isModulePosForm? [(p PosForm)] -> Bool
  :d "True when a position form wraps a module header."
  (moduleForm? p))

(df isNotModulePosForm? [(p PosForm)] -> Bool
  :d "True when a position form is not a module header."
  (not (moduleForm? p)))

(df modsExported [(mods (List PosForm))] -> (List String)
  :d "Extracts exported names from first module form or returns empty list."
  (mt (list-head mods)
    ((some m) (moduleExported (.-expr m)))
    ((none)   (list))))

(df buildModuleDecls [(mods (List PosForm)) (rest (List PosForm)) (path String)] -> (Result (List TopForm) ParseError)
  :d "Builds module declarations once path is known."
  (let [(exported (modsExported mods))]
    (mt (declForms rest exported)
      ((err e) (err e))
      ((ok decls)
       (mt (list-head mods)
         ((some m) (ok (list-cons (topModule (moduleNode (.-expr m) path decls)) decls)))
         ((none)   (ok decls)))))))

(df buildModule [(forms (List PosForm))] -> (Result (List TopForm) ParseError)
  :d "Wrap the module header, when present, and every declaration into top forms."
  (let [(mods (filter isModulePosForm? forms))
        (rest (filter isNotModulePosForm? forms))]
    (mt (modulePath mods)
      ((err e) (err e))
      ((ok path) (buildModuleDecls mods rest path)))))

(df moduleExported [(m rd/SExpr)] -> (List String)
  :d "The module's exported names from its :export vector."
  (mt (findOpt (sexprItems m) ":export")
    ((some v) (atomsToStrings (sexprItems v)))
    ((none)   (list))))

(df moduleImports [(m rd/SExpr)] -> (List (Pair String String))
  :d "Import path and alias pairs from the :import list."
  (mt (findOpt (sexprItems m) ":import")
    ((some v)
     (map importPair
          (filter rd/isList? (sexprItems v))))
    ((none) (list))))

(df importPair [(t rd/SExpr)] -> (Pair String String)
  :d "One (path :as alias) form as a path/alias pair."
  (let [(items (sexprItems t))]
    (pair (nthString items 0) (nthString items 2))))

(df moduleDocstring [(m rd/SExpr)] -> String
  :d "Extracts module docstring from :doc option or returns empty string."
  (mt (findOpt (sexprItems m) ":doc")
    ((some v) (rd/sexprHead v))
    ((none)   "")))

(df moduleNode [(m rd/SExpr) (path String) (defs (List TopForm))] -> ModuleNode
  :d "The module header as a typed module node."
  (ModuleNode :path path
              :docstring (moduleDocstring m)
              :exported (moduleExported m)
              :imports (moduleImports m)
              :defs defs))

(df isTag? [(s rd/SExpr)] -> Bool
  :d "True when an SExpr is a (:tag ...) metadata form."
  (and (rd/isList? s)
       (let [(h (rd/sexprHead s))]
         (= h ":tag"))))

(df appendDecl [(pf PosForm) (exported (List String)) (xs (List TopForm))] -> (Result (List TopForm) ParseError)
  :d "Parses and appends one decl form if not comment or tag."
  (let [(s (.-expr pf))]
    (if (or (and (rd/isAtom? s) (string-starts-with? (rd/sexprHead s) "\""))
            (isTag? s))
      (ok xs)
      (mt (declForm pf exported)
        ((ok t)  (ok (list-cons t xs)))
        ((err e) (err e))))))

(df declStep [(acc (Result (List TopForm) ParseError)) (pf PosForm) (exported (List String))]
  -> (Result (List TopForm) ParseError)
  :d "Add one converted declaration, keeping the first error. Bare strings are comments."
  (mt acc
    ((err e) (err e))
    ((ok xs) (appendDecl pf exported xs))))

(df declForms [(forms (List PosForm)) (exported (List String))]
  -> (Result (List TopForm) ParseError)
  :d "Convert every declaration to a typed top form, in order, or fail."
  (result-map (fn [(xs (List TopForm))] -> (List TopForm) (list-reverse xs))
              (fold (fn [(acc (Result (List TopForm) ParseError)) (pf PosForm)]
                      -> (Result (List TopForm) ParseError)
                      (declStep acc pf exported))
                    (ok (list))
                    forms)))

(df declForm [(pf PosForm) (exported (List String))] -> (Result TopForm ParseError)
  :d "Dispatch one top-level declaration on its normalized head."
  (let [(s (.-expr pf))
        (h (rd/sexprHead s))]
    (cond
      ((not (rd/isList? s))
       (err (perr "expected a top-level declaration" pf)))
      ((or (= h "defun") (= h "df"))     (funNode s exported pf))
      ((or (= h "defschema") (= h "dfs")) (schemaNode s pf))
      ((or (= h "defenum") (= h "dfe"))   (enumNode s pf))
      (:else (err (perr (str "not a declaration head: '" h "'") pf))))))

(df filterTags [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Remove metadata tag forms from an expression list."
  (filter (fn [(x rd/SExpr)] -> Bool (not (isTag? x))) items))

(df docString [(items (List rd/SExpr))] -> String
  :d "Extracts leading docstring or empty string."
  (mt (list-head items)
    ((some h)
     (cond
       ((isTag? h) (docString (tailExprs items)))
       ((and (rd/isAtom? h) (= (rd/sexprHead h) ":doc"))
        (mt (list-head (tailExprs items))
          ((some d) (rd/sexprHead d))
          ((none) "")))
       (:else "")))
    ((none) "")))

(df docBody [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Extracts body expressions after docstring, dropping tags."
  (mt (list-head items)
    ((some h)
     (cond
       ((isTag? h) (docBody (tailExprs items)))
       ((and (rd/isAtom? h) (= (rd/sexprHead h) ":doc"))
        (filterTags (tailExprs (tailExprs items))))
       (:else (filterTags items))))
    ((none) (list))))

(df paramsVector? [(v (Option rd/SExpr))] -> Bool
  :d "True when a defun's parameter slot holds a [ ] vector."
  (mt v
    ((some node) (rd/isVect? node))
    ((none)   false)))

(df hasEffect? [(firstOpt (Option rd/SExpr))] -> Bool
  :d "True if the first form after defun name is the ! effect marker."
  (mt firstOpt
    ((some h) (and (rd/isAtom? h) (= (rd/sexprHead h) "!")))
    ((none)   false)))

(df funParams [(pslot (Option rd/SExpr))] -> (List Param)
  :d "Extracts parameter list from defun parameter slot."
  (mt pslot
    ((some node) (paramList node))
    ((none)      (list))))

(df funRetType [(rslot (Option rd/SExpr))] -> String
  :d "Resolves return type string from defun return slot."
  (mt rslot
    ((some node) (resolveTypeText (rd/renderSexpr node)))
    ((none)      "")))

(df funNode [(s rd/SExpr) (exported (List String)) (pf PosForm)]
  -> (Result TopForm ParseError)
  :d "Build a typed defun node from its SExpr form, or reject the signature."
  (let [(items (sexprItems s))
        (rest1 (tailExprs items))
        (eff (hasEffect? (list-head rest1)))
        (rest2 (if eff (tailExprs rest1) rest1))
        (name (listHeadText rest2))
        (rest4 (tailExprs rest2))
        (pslot (list-head rest4))
        (params (funParams pslot))
        (rest5 (tailExprs rest4))
        (arrow (listHeadText rest5))
        (ret (funRetType (list-head (tailExprs rest5))))
        (doc (docString (tailExprs (tailExprs rest5))))
        (body (docBody (tailExprs (tailExprs rest5))))]
    (cond
      ((not (kebabIdent? name))
       (err (perr (str "defun name is not kebab-case: '" name "'") pf)))
      ((not (paramsVector? pslot))
       (err (perr "defun parameters must be a [ ] vector" pf)))
      ((not (= arrow "->"))
       (err (perr "defun return type must be introduced by ->" pf)))
      ((string-empty? ret)
       (err (perr "defun has no return type" pf)))
      ((list-empty? body)
       (err (perr "defun has no body" pf)))
      (:else
       (ok (topDefun (DefunNode :name name :typeVars (list)
                                :isExported (list-contains? exported name)
                                :effect eff :params params :retType ret
                                :docstring doc
                                :body body)))))))

(df paramList [(v rd/SExpr)] -> (List Param)
  :d "Parameter records from a params vector."
  (map (fn [(p rd/SExpr)] -> Param (paramNode p)) (sexprItems v)))

(df paramNode [(p rd/SExpr)] -> Param
  :d "One (name Type) parameter as a typed record."
  (let [(items (sexprItems p))]
    (Param :name (nthString items 0)
           :type (resolveTypeText (rd/renderSexpr (nthExpr items 1))))))

(df allHeads? [(forms (List rd/SExpr)) (head String)] -> Bool
  :d "True when every form carries the given head."
  (fold (fn [(acc Bool) (f rd/SExpr)] -> Bool
          (and acc (= (rd/sexprHead f) head)))
        true
        forms))

(df schemaJsonCase [(items (List rd/SExpr))] -> (Option String)
  :d "Extracts json-case option from schema items."
  (mt (findOpt items ":json-case")
    ((some node) (some (rd/sexprHead node)))
    ((none)      (none))))

(df schemaNode [(s rd/SExpr) (pf PosForm)] -> (Result TopForm ParseError)
  :d "Build a typed schema node from its SExpr form, or reject its shape."
  (let [(items (sexprItems s))
        (rest (tailExprs items))
        (name (listHeadText rest))
        (fforms (filter (fn [(f rd/SExpr)] -> Bool (and (rd/isList? f) (not (isTag? f)))) (tailExprs rest)))
        (jc (schemaJsonCase items))]
    (cond
      ((not (pascalName? name))
       (err (perr (str "defschema name is not PascalCase: '" name "'") pf)))
      ((list-empty? fforms)
       (err (perr "defschema needs at least one field" pf)))
      ((not (allHeads? fforms ":field"))
       (err (perr "every defschema member must be a (:field ...) form" pf)))
      (:else
       (ok (topSchema (SchemaNode :name name :typeVars (list)
                                   :fields (map (fn [(f rd/SExpr)] -> AstField
                                                  (fieldNode f))
                                                fforms)
                                   :jsonCase jc)))))))

(df fieldNode [(f rd/SExpr)] -> AstField
  :d "One (:field name Type doc ...) form as a typed record."
  (let [(items (sexprItems f))]
    (AstField :name (nthString items 1)
              :type (resolveTypeText (rd/renderSexpr (nthExpr items 2)))
              :docstring (nthString items 3)
              :default (optAfterKey items ":default")
              :json (optAfterKey items ":json"))))

(df optAfterKey [(items (List rd/SExpr)) (key String)] -> (Option String)
  :d "The value after a field option keyword, or none."
  (mt (findOpt items key)
    ((some v) (some (rd/sexprHead v)))
    ((none)   (none))))

(df enumNode [(s rd/SExpr) (pf PosForm)] -> (Result TopForm ParseError)
  :d "Build a typed enum node from its SExpr form, or reject its shape."
  (let [(items (sexprItems s))
        (rest (tailExprs items))
        (name (listHeadText rest))
        (cforms (filter (fn [(c rd/SExpr)] -> Bool (and (rd/isList? c) (not (isTag? c)))) (tailExprs rest)))]
    (cond
      ((not (pascalName? name))
       (err (perr (str "defenum name is not PascalCase: '" name "'") pf)))
      ((list-empty? cforms)
       (err (perr "defenum needs at least one case" pf)))
      ((not (allHeads? cforms ":case"))
       (err (perr "every defenum member must be a (:case ...) form" pf)))
      (:else
       (ok (topEnum (EnumNode :name name :typeVars (list)
                               :cases (map (fn [(c rd/SExpr)] -> EnumCase (caseNode c))
                                           cforms))))))))

(df caseFields [(items (List rd/SExpr))] -> (List Param)
  :d "Extracts fields parameter list from enum case items."
  (mt (list-get items 2)
    ((some node) (paramList node))
    ((none)      (list))))

(df caseNode [(c rd/SExpr)] -> EnumCase
  :d "One (:case name [fields] doc) form as a typed record."
  (let [(items (sexprItems c))]
    (EnumCase :name (nthString items 1)
              :fields (caseFields items)
              :docstring (nthString items 3))))

(df renderNode [(t TopForm)] -> String
  :d "Canonical verbose rendering of one typed top form."
  (mt t
    ((topModule m) (renderModule m))
    ((topSchema s) (renderSchema s))
    ((topEnum e)   (renderEnum e))
    ((topDefun d)  (renderDefun d))))

(df renderModule [(m ModuleNode)] -> String
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
                                        -> String (renderImport p))
                                      (.-imports m))
                                 " ")
                    "]")))]
    (str "(module " (.-path m) doc exp imp ")")))

(df renderImport [(p (Pair String String))] -> String
  :d "One import spec as canonical text."
  (str "(" (.-first p) " :as " (.-second p) ")"))

(df renderTypeVars [(tv (List String))] -> String
  :d "A leading type-parameter block, empty when there are none."
  (if (list-empty? tv)
    ""
    (str "{" (string-join tv " ") "} ")))

(df renderJoined [(xs (List String)) (prefix String)] -> String
  :d "Prefix plus space-joined items, empty when the list is empty."
  (if (list-empty? xs) "" (str prefix (string-join xs " "))))

(df renderDefun [(d DefunNode)] -> String
  :d "Canonical verbose defun text."
  (let [(mark (if (.-effect d) "! " ""))
        (tv (renderTypeVars (.-typeVars d)))
        (params (if (list-empty? (.-params d))
                  "[]"
                  (str "[" (string-join
                             (map (fn [(p Param)] -> String (renderParam p))
                                  (.-params d))
                             " ") "]")))
        (docp (if (= (.-docstring d) "") "" (str " :doc " (.-docstring d))))
        (body (renderJoined (map (fn [(b rd/SExpr)] -> String (rd/renderSexpr b))
                                  (.-body d))
                             " "))]
    (str "(defun " mark tv (.-name d) " " params " -> " (.-retType d)
         docp body ")")))

(df renderParam [(p Param)] -> String
  :d "One parameter as canonical text."
  (str "(" (.-name p) " " (.-type p) ")"))

(df renderJsonCasePart [(jc (Option String))] -> String
  :d "Renders json-case attribute if present."
  (mt jc
    ((some v) (str " :json-case " v))
    ((none)   "")))

(df renderSchema [(s SchemaNode)] -> String
  :d "Canonical verbose schema text.

  :json-case leads the fields because that is the one place the grammar's
  `schema_opt*` sits; the parser still reads it wherever it was written."
  (let [(tv (renderTypeVars (.-typeVars s)))
        (fields (renderJoined (map (fn [(f AstField)] -> String (renderField f))
                                    (.-fields s))
                               " "))
        (jc (renderJsonCasePart (.-jsonCase s)))]
    (str "(defschema " tv (.-name s) jc fields ")")))

(df renderFieldDefault [(opt (Option String))] -> String
  :d "Renders default attribute if present."
  (mt opt
    ((some v) (str " :default " v))
    ((none)   "")))

(df renderFieldJson [(opt (Option String))] -> String
  :d "Renders json attribute if present."
  (mt opt
    ((some v) (str " :json " v))
    ((none)   "")))

(df renderField [(f AstField)] -> String
  :d "One field as canonical text."
  (let [(defp (renderFieldDefault (.-default f)))
        (jsonp (renderFieldJson (.-json f)))]
    (str "(:field " (.-name f) " " (.-type f) " " (.-docstring f) defp jsonp ")")))

(df renderEnum [(e EnumNode)] -> String
  :d "Canonical verbose enum text."
  (let [(tv (renderTypeVars (.-typeVars e)))
        (cases (renderJoined (map (fn [(c EnumCase)] -> String (renderCase c))
                                   (.-cases e))
                              " "))]
    (str "(defenum " tv (.-name e) cases ")")))

(df renderCase [(c EnumCase)] -> String
  :d "One case as canonical text."
  (let [(fields (if (list-empty? (.-fields c))
                  "[]"
                  (str "[" (string-join
                             (map (fn [(p Param)] -> String (renderParam p))
                                  (.-fields c))
                             " ") "]")))]
    (str "(:case " (.-name c) " " fields " " (.-docstring c) ")")))
