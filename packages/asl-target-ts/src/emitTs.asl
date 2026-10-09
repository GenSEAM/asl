(module asl-target-ts/emitTs
  :x [emitTsSource emitTsModule emitTsTopForm emitTsSchema emitTsEnum emitTsDefun emitTsExpr]
  :i [(asl-parser/ast :a a)
      (asl-parser/reader :a rd)
      (asl-target-ts/types :a ty)])

fn emitTsAtom s: String -> String
  (cond
    ((= s "true") "true")
    ((= s "false") "false")
    ((or (= s "()") (or (= s "unit") (or (= s "nil") (= s "none")))) "undefined")
    ((stringStartsWith? s "\"") s)
    ((stringStartsWith? s ":")
      (str "\"" (optionOr (stringSlice s 1 (stringLength s)) "") "\""))
    ((or (stringStartsWith? s "-")
         (and (>= (optionOr (stringSlice s 0 1) "") "0")
              (<= (optionOr (stringSlice s 0 1) "") "9")))
      (ty/tsNumberLiteral s))
    (else (ty/tsMangleIdent s)))

fn emitTsBinop ctx: (List (Pair String (List String))) op: String args: (List rd/SExpr) -> String
  (let [(jsOp (cond
                ((= op "=") "===")
                ((= op "!=") "!==")
                ((= op "and") "&&")
                ((= op "or") "||")
                ((= op "+") "+")
                ((= op "-") "-")
                ((= op "*") "*")
                ((= op "/") "/")
                ((or (= op "mod") (= op "%")) "%")
                ((= op "<") "<")
                ((= op "<=") "<=")
                ((= op ">") ">")
                ((= op ">=") ">=")
                (else op)))]
    (cond
      ((listEmpty? args) "undefined")
      ((= (listLength args) 1)
        (if (= op "-")
          (str "(-" (emitTsExpr ctx (optionOr (listHead args) (rd/sexprAtom ""))) ")")
          (emitTsExpr ctx (optionOr (listHead args) (rd/sexprAtom "")))))
      (else
        (str "(" (stringJoin (map (fn [(x rd/SExpr)] -> String (emitTsExpr ctx x)) args) (str " " jsOp " ")) ")"))))

fn isKeywordPairs? args: (List rd/SExpr) -> Bool
  (and (> (listLength args) 0)
       (= (mod (listLength args) 2) 0)
       (stringStartsWith? (rd/sexprHead (optionOr (listHead args) (rd/sexprAtom ""))) ":"))

fn emitTsObjectProps ctx: (List (Pair String (List String))) args: (List rd/SExpr) -> (List String)
  (if (listEmpty? args)
    (list)
    (let [(k (optionOr (listGet args 0) (rd/sexprAtom "")))
          (v (optionOr (listGet args 1) (rd/sexprAtom "")))
          (rem (optionOr (listSlice args 2 (listLength args)) (list)))
          (kName (rd/sexprHead k))
          (propName (if (stringStartsWith? kName ":") (optionOr (stringSlice kName 1 (stringLength kName)) kName) kName))
          (propStr (str (ty/tsMangleIdent propName) ": " (emitTsExpr ctx v)))]
      (cons propStr (emitTsObjectProps ctx rem))))

fn emitTsBinding ctx: (List (Pair String (List String))) b: rd/SExpr -> String
  (let [(items (rd/sexprToList b))]
    (if (< (listLength items) 2)
      ""
      (let [(name (ty/tsMangleIdent (rd/sexprHead (optionOr (listGet items 0) (rd/sexprAtom "")))))
            (val (emitTsExpr ctx (optionOr (listGet items 1) (rd/sexprAtom "undefined"))))]
        (str "  const " name " = " val ";\n"))))

fn emitTsLet ctx: (List (Pair String (List String))) args: (List rd/SExpr) -> String
  (let [(bindingsSexpr (optionOr (listHead args) (rd/sexprList (list))))
        (bindings (rd/sexprToList bindingsSexpr))
        (bodyForms (optionOr (listTail args) (list)))
        (bindingStrs (stringJoin (map (fn [(b rd/SExpr)] -> String (emitTsBinding ctx b)) bindings) ""))
        (bodyExpr (if (listEmpty? bodyForms) (rd/sexprAtom "undefined") (optionOr (listGet bodyForms (- (listLength bodyForms) 1)) (rd/sexprAtom "undefined"))))]
    (str "(() => {\n" bindingStrs "  return " (emitTsExpr ctx bodyExpr) ";\n})()"))

fn emitTsCond ctx: (List (Pair String (List String))) clauses: (List rd/SExpr) -> String
  (mt (listHead clauses)
    ((none) "undefined")
    ((some c)
      (let [(items (rd/sexprToList c))
            (rem (optionOr (listTail clauses) (list)))]
        (if (< (listLength items) 2)
          "undefined"
          (let [(condSexpr (optionOr (listGet items 0) (rd/sexprAtom "true")))
                (valSexpr (optionOr (listGet items 1) (rd/sexprAtom "undefined")))
                (condHead (rd/sexprHead condSexpr))]
            (if (or (= condHead "else") (or (= condHead ":else") (= condHead "true")))
              (emitTsExpr ctx valSexpr)
              (str "(" (emitTsExpr ctx condSexpr) " ? " (emitTsExpr ctx valSexpr) " : " (emitTsCond ctx rem) ")")))))))

fn lookupCaseFields ctx: (List (Pair String (List String))) tag: String -> (List String)
  (mt (listHead ctx)
    ((none) (list))
    ((some p)
      (if (= (pairFirst p) tag)
        (pairSecond p)
        (lookupCaseFields (optionOr (listTail ctx) (list)) tag))))

fn zipCtorBindings targetVar: String bindNames: (List String) fieldNames: (List String) idx: Int64 -> String
  (mt (listHead bindNames)
    ((none) "")
    ((some bn)
      (let [(fieldName (optionOr (listGet fieldNames idx) bn))
            (mangledBind (ty/tsMangleIdent bn))
            (mangledField (ty/tsMangleIdent fieldName))
            (rest (zipCtorBindings targetVar (optionOr (listTail bindNames) (list)) fieldNames (+ idx 1)))]
        (str "const " mangledBind " = " targetVar "." mangledField "; " rest))))

fn emitTsMtArms ctx: (List (Pair String (List String))) targetVar: String arms: (List rd/SExpr) -> String
  (mt (listHead arms)
    ((none) "(() => { throw new Error(\"non-exhaustive match\"); })()")
    ((some arm)
      (let [(rem (optionOr (listTail arms) (list)))
            (armItems (rd/sexprToList arm))]
        (if (< (listLength armItems) 2)
          "undefined"
          (let [(pat (optionOr (listGet armItems 0) (rd/sexprAtom "")))
                (body (optionOr (listGet armItems 1) (rd/sexprAtom "undefined")))
                (patHead (rd/sexprHead pat))
                (mangledTag (ty/tsMangleIdent patHead))]
            (cond
              ((or (= patHead "_") (= patHead "else"))
                (emitTsExpr ctx body))
              ((= patHead "ok")
                (let [(patItems (rd/sexprToList pat))
                      (bindName (if (> (listLength patItems) 1) (ty/tsMangleIdent (rd/sexprHead (optionOr (listGet patItems 1) (rd/sexprAtom "")))) "value"))]
                  (str "(" targetVar ".ok ? ((() => { const " bindName " = " targetVar ".value; return " (emitTsExpr ctx body) "; })()) : " (emitTsMtArms ctx targetVar rem) ")")))
              ((= patHead "err")
                (let [(patItems (rd/sexprToList pat))
                      (bindName (if (> (listLength patItems) 1) (ty/tsMangleIdent (rd/sexprHead (optionOr (listGet patItems 1) (rd/sexprAtom "")))) "error"))]
                  (str "((!" targetVar ".ok) ? ((() => { const " bindName " = " targetVar ".error; return " (emitTsExpr ctx body) "; })()) : " (emitTsMtArms ctx targetVar rem) ")")))
              ((= patHead "some")
                (let [(patItems (rd/sexprToList pat))
                      (bindName (if (> (listLength patItems) 1) (ty/tsMangleIdent (rd/sexprHead (optionOr (listGet patItems 1) (rd/sexprAtom "")))) "value"))]
                  (str "((" targetVar " !== null && " targetVar " !== undefined) ? ((() => { const " bindName " = " targetVar "; return " (emitTsExpr ctx body) "; })()) : " (emitTsMtArms ctx targetVar rem) ")")))
              ((= patHead "none")
                (str "((" targetVar " === null || " targetVar " === undefined) ? " (emitTsExpr ctx body) " : " (emitTsMtArms ctx targetVar rem) ")"))
              (else
                (let [(patItems (rd/sexprToList pat))
                      (bindNames (map rd/sexprHead (optionOr (listTail patItems) (list))))
                      (fieldNames (lookupCaseFields ctx patHead))
                      (bodyStr (emitTsExpr ctx body))
                      (guardedBody (if (listEmpty? bindNames)
                                     bodyStr
                                     (str "((() => { " (zipCtorBindings targetVar bindNames fieldNames 0) "return " bodyStr "; })())")))]
                  (str "(" targetVar ".tag === \"" mangledTag "\" ? " guardedBody " : " (emitTsMtArms ctx targetVar rem) ")")))))))))

fn emitTsMt ctx: (List (Pair String (List String))) args: (List rd/SExpr) -> String
  (if (listEmpty? args)
    "undefined"
    (let [(targetSexpr (optionOr (listHead args) (rd/sexprAtom "undefined")))
          (arms (optionOr (listTail args) (list)))]
      (str "((_m) => { return " (emitTsMtArms ctx "_m" arms) "; })(" (emitTsExpr ctx targetSexpr) ")")))

fn emitTsLambdaParam p: rd/SExpr -> String
  (let [(items (rd/sexprToList p))
        (pName (ty/tsMangleIdent (rd/sexprHead (optionOr (listGet items 0) (rd/sexprAtom "")))))
        (pTypeRaw (if (> (listLength items) 1) (rd/renderSexpr (optionOr (listGet items 1) (rd/sexprAtom "Any"))) "Any"))]
    (str pName ": " (ty/emitTsType pTypeRaw)))

fn vectItems s: rd/SExpr -> (List rd/SExpr)
  (let [(raw (rd/sexprToList s))]
    (if (and (not (listEmpty? raw)) (= (rd/sexprHead (optionOr (listHead raw) (rd/sexprAtom ""))) "list"))
      (optionOr (listTail raw) (list))
      raw))

fn emitTsLambda ctx: (List (Pair String (List String))) args: (List rd/SExpr) -> String
  (let [(paramsNode (optionOr (listHead args) (rd/sexprVect (list))))
        (paramItems (vectItems paramsNode))
        (paramsStr (stringJoin (map emitTsLambdaParam paramItems) ", "))
        (rest (optionOr (listTail args) (list)))
        (hasArrow (and (not (listEmpty? rest)) (= (rd/sexprHead (optionOr (listHead rest) (rd/sexprAtom ""))) "->")))
        (afterArrow (if hasArrow (optionOr (listTail rest) (list)) rest))
        (retTypeStr (if hasArrow (rd/renderSexpr (optionOr (listHead afterArrow) (rd/sexprAtom ""))) ""))
        (bodyForms (if hasArrow (optionOr (listTail afterArrow) (list)) afterArrow))
        (bodyStr (if (listEmpty? bodyForms) "undefined" (emitTsExpr ctx (optionOr (listGet bodyForms (- (listLength bodyForms) 1)) (rd/sexprAtom "undefined")))))
        (retAnnotation (if (stringEmpty? retTypeStr) "" (str ": " (ty/emitTsType retTypeStr))))]
    (str "(" paramsStr ")" retAnnotation " => (" bodyStr ")"))

fn emitTsCall ctx: (List (Pair String (List String))) fnName: String args: (List rd/SExpr) -> String
  (let [(mangled (ty/tsMangleIdent fnName))
        (argStrs (map (fn [(x rd/SExpr)] -> String (emitTsExpr ctx x)) args))]
    (cond
      ((= fnName "str")
        (str "(\"\" + " (stringJoin (map (fn [(a String)] -> String (str "String(" a ")")) argStrs) " + ") ")"))
      ((= fnName "println")
        (str "console.log(" (stringJoin argStrs ", ") ")"))
      ((= fnName "print")
        (str "process.stdout.write(String(" (stringJoin argStrs ", ") "))"))
      ((= fnName "not")
        (str "(!" (optionOr (listHead argStrs) "false") ")"))
      ((= fnName "list")
        (str "[" (stringJoin argStrs ", ") "]"))
      ((= fnName "fold")
        (str "aslFold(" (stringJoin argStrs ", ") ")"))
      ((= fnName "map")
        (str "aslMap(" (stringJoin argStrs ", ") ")"))
      ((= fnName "filter")
        (str "aslFilter(" (stringJoin argStrs ", ") ")"))
      ((= fnName "listLength")
        (str "BigInt(" (optionOr (listHead argStrs) "[]") ".length)"))
      ((= fnName "listEmpty?")
        (str "(" (optionOr (listHead argStrs) "[]") ".length === 0)"))
      ((= fnName "listContains?")
        (str "(" (optionOr (listHead argStrs) "[]") ".includes(" (optionOr (listGet argStrs 1) "undefined") "))"))
      ((= fnName "stringLength")
        (str "BigInt(" (optionOr (listHead argStrs) "\"\"") ".length)"))
      ((= fnName "stringEmpty?")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".length === 0)"))
      ((= fnName "stringContains?")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".includes(" (optionOr (listGet argStrs 1) "\"\"") "))"))
      ((= fnName "stringStartsWith?")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".startsWith(" (optionOr (listGet argStrs 1) "\"\"") "))"))
      ((= fnName "stringEndsWith?")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".endsWith(" (optionOr (listGet argStrs 1) "\"\"") "))"))
      ((= fnName "stringSplit")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".split(" (optionOr (listGet argStrs 1) "\"\"") "))"))
      ((= fnName "stringJoin")
        (str "(" (optionOr (listHead argStrs) "[]") ".join(" (optionOr (listGet argStrs 1) "\",\"") "))"))
      ((= fnName "stringTrim")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".trim())"))
      ((= fnName "stringLower")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".toLowerCase())"))
      ((= fnName "stringUpper")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".toUpperCase())"))
      ((= fnName "stringReplace")
        (str "(" (optionOr (listHead argStrs) "\"\"") ".split(" (optionOr (listGet argStrs 1) "\"\"") ").join(" (optionOr (listGet argStrs 2) "\"\"") "))"))
      ((= fnName "stringIndexOf")
        (str "aslStringIndexOf(" (optionOr (listHead argStrs) "\"\"") ", " (optionOr (listGet argStrs 1) "\"\"") ")"))
      ((= fnName "stringSlice")
        (str "aslStringSlice(" (stringJoin argStrs ", ") ")"))
      ((or (= fnName "optionSome?") (= fnName "some?"))
        (str "(" (optionOr (listHead argStrs) "null") " !== null && " (optionOr (listHead argStrs) "null") " !== undefined)"))
      ((or (= fnName "optionNone?") (= fnName "none?"))
        (str "(" (optionOr (listHead argStrs) "null") " === null || " (optionOr (listHead argStrs) "null") " === undefined)"))
      ((= fnName "option-unwrap")
        (str "(" (optionOr (listHead argStrs) "null") "!)"))
      ((= fnName "optionOr")
        (str "aslOptionOr(" (stringJoin argStrs ", ") ")"))
      ((= fnName "ok")
        (str "({ ok: true, value: " (optionOr (listHead argStrs) "undefined") " })"))
      ((= fnName "err")
        (str "({ ok: false, error: " (optionOr (listHead argStrs) "\"\"") " })"))
      ((= fnName "assert")
        (str "console.assert(" (stringJoin argStrs ", ") ")"))
      ((= fnName "refute")
        (str "console.assert(!" (optionOr (listHead argStrs) "false") ", " (optionOr (listGet argStrs 1) "\"refuted\"") ")"))
      ((stringStartsWith? fnName ".-")
        (let [(field (ty/tsMangleIdent (optionOr (stringSlice fnName 2 (stringLength fnName)) "")))
              (target (optionOr (listHead argStrs) "{}"))]
          (str target "." field)))
      ((isKeywordPairs? args)
        (str "({ " (stringJoin (emitTsObjectProps ctx args) ", ") " })"))
      (else
        (str mangled "(" (stringJoin argStrs ", ") ")"))))

fn emitTsList ctx: (List (Pair String (List String))) items: (List rd/SExpr) -> String
  (if (listEmpty? items)
    "undefined"
    (let [(head (rd/sexprHead (optionOr (listHead items) (rd/sexprAtom ""))))
          (args (optionOr (listTail items) (list)))]
      (cond
        ((or (= head "+") (or (= head "-") (or (= head "*") (= head "/"))))
          (emitTsBinop ctx head args))
        ((or (= head "=") (or (= head "==") (or (= head "!=") (or (= head "<") (or (= head "<=") (or (= head ">") (= head ">=")))))))
          (emitTsBinop ctx head args))
        ((or (= head "and") (or (= head "or") (= head "mod")))
          (emitTsBinop ctx head args))
        ((= head "if")
          (let [(c (optionOr (listGet args 0) (rd/sexprAtom "true")))
                (t (optionOr (listGet args 1) (rd/sexprAtom "undefined")))
                (e (optionOr (listGet args 2) (rd/sexprAtom "undefined")))]
            (str "(" (emitTsExpr ctx c) " ? " (emitTsExpr ctx t) " : " (emitTsExpr ctx e) ")")))
        ((= head "do")
          (str "((" (stringJoin (map (fn [(x rd/SExpr)] -> String (emitTsExpr ctx x)) args) ", ") "))"))
        ((= head "cond")
          (emitTsCond ctx args))
        ((or (= head "mt") (= head "match"))
          (emitTsMt ctx args))
        ((= head "let")
          (emitTsLet ctx args))
        ((or (= head "fn") (= head "lambda"))
          (emitTsLambda ctx args))
        ((isKeywordPairs? args)
          (str "({ " (stringJoin (emitTsObjectProps ctx args) ", ") " })"))
        (else
          (emitTsCall ctx head args)))))

fn emitTsExpr ctx: (List (Pair String (List String))) e: rd/SExpr -> String
  (mt e
    ((rd/sexprAtom v) (emitTsAtom v))
    ((rd/sexprList items) (emitTsList ctx items))
    ((rd/sexprVect items) (str "[" (stringJoin (map (fn [(x rd/SExpr)] -> String (emitTsExpr ctx x)) items) ", ") "]")))

fn emitTsField f: a/AstField -> String
  (let [(fName (ty/tsMangleIdent f.name))
        (fType (ty/emitTsType f.type))]
    (str "  " fName ": " fType ";\n"))

fn emitTsSchema s: a/SchemaNode -> String
  (let [(name (ty/tsMangleIdent s.name))
        (fieldsStr (stringJoin (map emitTsField s.fields) ""))]
    (str "export interface " name " {\n" fieldsStr "}\n\n"))

fn emitTsEnumCasePayload enumName: String c: a/EnumCase -> String
  (let [(cName (ty/tsMangleIdent c.name))
        (fields c.fields)
        (fieldDecls (map (fn [(p a/Param)] -> String
                           (str "; " (ty/tsMangleIdent p.name) ": " (ty/emitTsType p.type)))
                         fields))]
    (str "  | { tag: \"" cName "\"" (stringJoin fieldDecls "") " }\n"))

fn emitTsEnumConstructor enumName: String c: a/EnumCase -> String
  (let [(cName (ty/tsMangleIdent c.name))
        (fnName (str "make" enumName (stringUpper (optionOr (stringSlice cName 0 1) "")) (optionOr (stringSlice cName 1 (stringLength cName)) "")))
        (fields c.fields)
        (params (map (fn [(p a/Param)] -> String
                       (str (ty/tsMangleIdent p.name) ": " (ty/emitTsType p.type)))
                     fields))
        (bodyAssigns (map (fn [(p a/Param)] -> String
                            (let [(pn (ty/tsMangleIdent p.name))]
                              (str ", " pn)))
                          fields))
        (c1 (str "export function " fnName "(" (stringJoin params ", ") "): " enumName " {\n"
                 "  return { tag: \"" cName "\"" (stringJoin bodyAssigns "") " };\n"
                 "}\n\n"))
        (c2 (str "export function " cName "(" (stringJoin params ", ") "): " enumName " {\n"
                 "  return { tag: \"" cName "\"" (stringJoin bodyAssigns "") " };\n"
                 "}\n\n"))]
    (str c1 c2))

fn emitTsEnum e: a/EnumNode -> String
  (let [(name (ty/tsMangleIdent e.name))
        (cases e.cases)
        (typeUnion (stringJoin (map (fn [(c a/EnumCase)] -> String (emitTsEnumCasePayload name c)) cases) ""))
        (constructors (stringJoin (map (fn [(c a/EnumCase)] -> String (emitTsEnumConstructor name c)) cases) ""))]
    (str "export type " name " =\n" typeUnion ";\n\n" constructors))

fn emitTsParam p: a/Param -> String
  (let [(pName (ty/tsMangleIdent p.name))
        (pType (ty/emitTsType p.type))]
    (str pName ": " pType))

fn emitTsDefunCtx ctx: (List (Pair String (List String))) d: a/DefunNode -> String
  (let [(name (ty/tsMangleIdent d.name))
        (paramsStr (stringJoin (map emitTsParam d.params) ", "))
        (retType (ty/emitTsType d.retType))
        (bodyForms d.body)
        (bodyExpr (if (listEmpty? bodyForms) "undefined" (emitTsExpr ctx (optionOr (listGet bodyForms (- (listLength bodyForms) 1)) (rd/sexprAtom "undefined")))))]
    (str "export function " name "(" paramsStr "): " retType " {\n"
         "  return " bodyExpr ";\n"
         "}\n\n"))

fn emitTsDefun d: a/DefunNode -> String
  (emitTsDefunCtx (list) d)

fn extractBasename path: String -> String
  (if (not (stringContains? path "/"))
    path
    (let [(parts (stringSplit path "/"))
          (last (optionOr (listGet parts (- (listLength parts) 1)) path))]
      last))

fn emitTsImport p: (Pair String String) -> String
  (let [(modPath (pairFirst p))
        (alias (pairSecond p))
        (base (extractBasename modPath))
        (mangledAlias (ty/tsMangleIdent alias))]
    (str "import * as " mangledAlias " from \"./" base ".js\";\n"))

fn emitTsModuleImports m: a/ModuleNode -> String
  (let [(imps m.imports)]
    (if (listEmpty? imps)
      ""
      (str (stringJoin (map emitTsImport imps) "") "\n")))

fn emitTsTopForm ctx: (List (Pair String (List String))) tf: a/TopForm -> String
  (mt tf
    ((a/topSchema s) (emitTsSchema s))
    ((a/topEnum e) (emitTsEnum e))
    ((a/topDefun d) (emitTsDefunCtx ctx d))
    ((a/topModule m) (emitTsModuleImports m))
    ((a/topExpr p) (str (emitTsExpr ctx p.expr) ";\n")))

fn caseFieldEntry c: a/EnumCase -> (Pair String (List String))
  (pair c.name (map (fn [(p a/Param)] -> String p.name) c.fields))

fn topFormCaseEntries tf: a/TopForm -> (List (Pair String (List String)))
  (mt tf
    ((a/topEnum e) (map caseFieldEntry e.cases))
    (_ (list)))

fn buildCaseFieldCtx forms: (List a/TopForm) -> (List (Pair String (List String)))
  (fold (fn [(acc (List (Pair String (List String)))) (tf a/TopForm)] -> (List (Pair String (List String)))
          (listAppend acc (topFormCaseEntries tf)))
        (list) forms)

fn findMainDefunLoop forms: (List a/TopForm) -> (Option a/DefunNode)
  (mt (listHead forms)
    ((none) (none))
    ((some tf)
      (let [(rest (optionOr (listTail forms) (list)))]
        (mt tf
          ((a/topDefun d) (if (= d.name "main") (some d) (findMainDefunLoop rest)))
          (_ (findMainDefunLoop rest))))))

fn mainEntrySnippet retType: String -> String
  (let [(clean (stringTrim retType))]
    (cond
      ((stringContains? clean "Result")
        (str "\nconst __aslResult = main();\n"
             "if (!__aslResult.ok) {\n"
             "  console.error(String(__aslResult.error));\n"
             "  process.exitCode = 1;\n"
             "} else {\n"
             (if (or (stringContains? clean "Unit") (stringContains? clean "()"))
               "  process.exitCode = 0;\n"
               "  process.exitCode = Number(__aslResult.value);\n")
             "}\n"))
      ((or (= clean "Unit") (or (= clean "()") (= clean "Void")))
        "\nmain();\nprocess.exitCode = 0;\n")
      (else
        "\nprocess.exitCode = Number(main());\n")))

fn mainEntryPoint forms: (List a/TopForm) -> String
  (mt (findMainDefunLoop forms)
    ((none) "")
    ((some d) (mainEntrySnippet d.retType)))

fn emitTsModule forms: (List a/TopForm) -> String
  (let [(ctx (buildCaseFieldCtx forms))
        (header (ty/emitTsHeader))
        (decls (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
                       (map (fn [(tf a/TopForm)] -> String (emitTsTopForm ctx tf)) forms)))
        (entry (mainEntryPoint forms))]
    (str header (stringJoin decls "") entry))

fn emitTsSource forms: (List a/TopForm) -> String
  (emitTsModule forms)
