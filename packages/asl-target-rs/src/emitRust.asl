(module asl-target-rs/emitRust
  :x [emitRustTypeStr emitRustStruct emitRustEnum emitRustFn emitRustExpr emitRustProgram emitRustSourceFromForms]
  :i [(asl-target-rs/ast :a ast) (asl-target-rs/types :a t) (asl-parser/ast :a a)])

fn emitRustTypeStr ty: ast/RsType -> String
  (let [(base (t/rustMangleIdent ty.name))
        (gens ty.generics)]
    (if (> (listLength gens) 0)
      (let [(genStrs (map emitRustTypeStr gens))]
        (str base "<" (stringJoin genStrs ", ") ">"))
      base))

fn emitDerivesList derives: (List String) -> String
  (if (> (listLength derives) 0)
    (str "#[derive(" (stringJoin derives ", ") ")]\n")
    "#[derive(Debug, Clone, PartialEq)]\n")

fn emitRustStruct s: ast/RsStructDecl -> String
  (let [(dStr (emitDerivesList s.derives))
        (vis (if s.isPub "pub " ""))
        (sName (t/rustMangleIdent s.name))
        (fields s.fields)
        (fLines (map (fn [(f ast/RsField)] -> String
                       (let [(fVis (if f.isPub "pub " ""))
                             (fName (t/rustMangleIdent f.name))
                             (fTy (emitRustTypeStr f.type))]
                         (str "    " fVis fName ": " fTy ",\n")))
                     fields))]
    (str dStr vis "struct " sName " {\n" (stringJoin fLines "") "}\n\n"))

fn emitRustEnum e: ast/RsEnumDecl -> String
  (let [(dStr (emitDerivesList e.derives))
        (vis (if e.isPub "pub " ""))
        (eName (t/rustMangleIdent e.name))
        (cases e.cases)
        (cLines (map (fn [(c ast/RsEnumCase)] -> String
                       (let [(cName (t/rustMangleIdent c.name))
                             (payload c.payload)]
                         (if (> (listLength payload) 0)
                           (let [(pTys (map emitRustTypeStr payload))]
                             (str "    " cName "(" (stringJoin pTys ", ") "),\n"))
                           (str "    " cName ",\n"))))
                     cases))]
    (str dStr vis "enum " eName " {\n" (stringJoin cLines "") "}\n\n"))

fn emitRustExpr e: ast/RsExpr -> String
  (mt e
    ((ast/rsLit v) v)
    ((ast/rsVar n) (t/rustMangleIdent n))
    ((ast/rsBinOp op lhs rhs) (t/emitRustBinop op lhs rhs))
    ((ast/rsCall fnName args)
      (let [(mFn (t/rustMangleIdent fnName))]
        (str mFn "(" (stringJoin args ", ") ")")))
    ((ast/rsLet v val)
      (let [(mV (t/rustMangleIdent v))]
        (str "let " mV " = " val ";\n")))
    ((ast/rsIf cond tb eb)
      (str "if " cond " {\n        " tb "\n    } else {\n        " eb "\n    }"))
    ((ast/rsMatch tgt arms)
      (let [(armLines (map (fn [(p (pair String String))] -> String
                             (let [(lhs (pairFirst p))
                                   (rhs (pairSecond p))]
                               (str "        " lhs " => " rhs ",\n")))
                           arms))]
        (str "match " tgt " {\n" (stringJoin armLines "") "    }"))))

fn emitRustFn f: ast/RsFnDecl -> String
  (let [(vis (if f.isPub "pub " ""))
        (fnName (t/rustMangleIdent f.name))
        (params f.params)
        (pStrs (map (fn [(p ast/RsParam)] -> String
                      (let [(pName (t/rustMangleIdent p.name))
                            (pTy (emitRustTypeStr p.type))]
                        (str pName ": " pTy)))
                    params))
        (paramList (stringJoin pStrs ", "))
        (retTy (emitRustTypeStr f.retType))
        (retPart (if (= retTy "()") "" (str " -> " retTy)))
        (body f.body)
        (bStrs (map (fn [(e ast/RsExpr)] -> String
                      (str "    " (emitRustExpr e)))
                    body))
        (bodyBlock (if (> (listLength bStrs) 0) (stringJoin bStrs "\n") "    ()"))]
    (str vis "fn " fnName "(" paramList ")" retPart " {\n" bodyBlock "\n}\n\n"))

fn emitRustProgram file: ast/RsFile -> String
  (let [(header (t/emitRustHeader))
        (structs (stringJoin (map emitRustStruct file.structs) ""))
        (enums (stringJoin (map emitRustEnum file.enums) ""))
        (functions (stringJoin (map emitRustFn file.functions) ""))]
    (str header structs enums functions))

fn schemaToRsStruct s: a/SchemaNode -> ast/RsStructDecl
  (let [(flds (map (fn [(f a/AstField)] -> ast/RsField
                     (ast/makeRsField f.name (ast/makeRsType f.type (list)) true))
                   s.fields))]
    (ast/makeRsStruct s.name flds (list "Debug" "Clone" "PartialEq") true))

fn enumToRsEnum e: a/EnumNode -> ast/RsEnumDecl
  (let [(cs (map (fn [(c a/EnumCase)] -> ast/RsEnumCase
                   (let [(flds (map (fn [(p a/Param)] -> ast/RsType
                                      (ast/makeRsType p.type (list)))
                                    c.fields))]
                     (ast/makeRsEnumCase c.name flds)))
                 e.cases))]
    (ast/makeRsEnum e.name cs (list "Debug" "Clone" "PartialEq") true))

fn defunToRsFn d: a/DefunNode -> ast/RsFnDecl
  (let [(ps (map (fn [(p a/Param)] -> ast/RsParam
                   (ast/RsParam :name p.name :type (ast/makeRsType p.type (list))))
                 d.params))
        (ret (ast/makeRsType d.retType (list)))]
    (ast/makeRsFn d.name ps ret (list) true))

fn unpackForms forms: (List a/TopForm) -> (List a/TopForm)
  (if (= (listLength forms) 1)
    (mt (listHead forms)
      ((some form)
       (mt form
         ((a/topModule m) m.defs)
         (else forms)))
      (else forms))
    forms)

fn rsFormsHaveTopExpr? forms: (List a/TopForm) -> Bool
  (fold (fn [(acc Bool) (f a/TopForm)] -> Bool (or acc (mt f ((a/topExpr _) true) (else false)))) false forms)

fn emitRustSourceFromForms forms: (List a/TopForm) path: String -> String
  (let [(effForms (unpackForms forms))
        (guard (assert (not (rsFormsHaveTopExpr? effForms)) "ERR_RUST_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook in Rust output"))
        (structs (fold (fn [(acc (List ast/RsStructDecl)) (form a/TopForm)]
                         (mt form ((a/topSchema s) (listAppend acc (list (schemaToRsStruct s)))) (else acc)))
                       (list) effForms))
        (enums (fold (fn [(acc (List ast/RsEnumDecl)) (form a/TopForm)]
                       (mt form ((a/topEnum e) (listAppend acc (list (enumToRsEnum e)))) (else acc)))
                     (list) effForms))
        (fns (fold (fn [(acc (List ast/RsFnDecl)) (form a/TopForm)]
                     (mt form ((a/topDefun d) (listAppend acc (list (defunToRsFn d)))) (else acc)))
                   (list) effForms))
        (file (ast/RsFile :package path :imports (list) :structs structs :enums enums :functions fns))]
    (emitRustProgram file))
