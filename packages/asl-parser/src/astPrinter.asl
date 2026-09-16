(module asl-parser/astPrinter
  :d "Pure ASL v0.4 Canonical Indented AST Formatter."
  :x [printAstModule printAstExpr printAstPattern printAstType printTopForm]
  :i [(ast :a a) (astConverter :a cv) (reader :a rd) (indentPrinter :a ip)])

(df indentPrefix [(level Int64)] -> String
  :d "Generates 2-space indentation prefix for given nesting level."
  (string-repeat "  " level))

(df printAstLit [(lit a/AstLit)] -> String
  :d "Formats an AstLit variant into canonical string representation."
  (mt lit
    ((a/litInt i)    (string-from-int64 i))
    ((a/litFloat f)  (string-from-float64 f))
    ((a/litString s) (str "\"" s "\""))
    ((a/litBool b)   (if b "true" "false"))
    ((a/litUnit)     "()")))

(df printFieldPattern [(f (Pair String a/AstPattern))] -> String
  :d "Formats a record field pattern key or key: pattern."
  (let [(k (.-first f))
        (p (.-second f))]
    (mt p
      ((a/patVar v)
       (if (= v k) k (str k ": " v)))
      ((a/patWildcard)
       k)
      (_
       (str k ": " (printAstPattern p))))))

(df printAstPattern [(pat a/AstPattern)] -> String
  :d "Formats an AstPattern node into canonical indented pattern syntax."
  (mt pat
    ((a/patWildcard)
     "_")
    ((a/patVar name)
     name)
    ((a/patLit lit)
     (printAstLit lit))
    ((a/patTuple elements)
     (str "[" (string-join (map (fn [(p a/AstPattern)] -> String (printAstPattern p)) elements) " ") "]"))
    ((a/patRecord fields)
     (str "{" (string-join (map (fn [(f (Pair String a/AstPattern))] -> String (printFieldPattern f)) fields) " ") "}"))
    ((a/patCtor name arg)
     (mt arg
       ((none)
        name)
       ((some a)
        (mt a
          ((a/patTuple elements)
           (if (list-empty? elements)
             name
             (str name " " (string-join (map (fn [(p a/AstPattern)] -> String (printAstPattern p)) elements) " "))))
          (_
           (str name " " (printAstPattern a)))))))))

(df printRecordFieldType [(f (Pair String a/AstType))] -> String
  :d "Formats a record field type name: Type."
  (str (.-first f) ": " (printAstType (.-second f))))

(df printAstType [(t a/AstType)] -> String
  :d "Formats an AstType node into canonical representation."
  (mt t
    ((a/typeNamed name)
     name)
    ((a/typeTuple elements)
     (str "[" (string-join (map (fn [(e a/AstType)] -> String (printAstType e)) elements) " ") "]"))
    ((a/typeRecord fields)
     (str "{" (string-join (map (fn [(f (Pair String a/AstType))] -> String (printRecordFieldType f)) fields) " ") "}"))
    ((a/typeFn paramTypes retType)
     (str "fn [" (string-join (map (fn [(p a/AstType)] -> String (printAstType p)) paramTypes) " ") "] -> " (printAstType retType)))))

(df isBlockExpr? [(e a/AstExpr)] -> Bool
  :d "Checks if an expression is a block."
  (mt e
    ((a/exprBlock _) true)
    (_ false)))

(df callFunc [(e a/AstExpr)] -> a/AstExpr
  :d "Extracts the function expression from a call, or returns self."
  (mt e
    ((a/exprCall f _) f)
    (_ e)))

(df callArgs [(e a/AstExpr)] -> (List a/AstExpr)
  :d "Extracts argument list from a call, or empty list."
  (mt e
    ((a/exprCall _ args) args)
    (_ (list))))

(df printCallBody [(func a/AstExpr) (args (List a/AstExpr))] -> String
  :d "Formats the body of a call expression without enclosing parentheses."
  (let [(fnStr (printAstExpr func 0))]
    (if (list-empty? args)
      fnStr
      (let [(argStrs (map (fn [(a a/AstExpr)] -> String (printAstExprInArg a)) args))]
        (str fnStr " " (string-join argStrs " "))))))

(df printAstExprInArg [(expr a/AstExpr)] -> String
  :d "Formats an expression appearing in argument position, parenthesizing calls and if forms."
  (mt expr
    ((a/exprCall func args)
     (str "(" (printCallBody func args) ")"))
    ((a/exprIf _ _ _)
     (str "(" (printAstExpr expr 0) ")"))
    (_
     (printAstExpr expr 0))))

(df printAstCall [(func a/AstExpr) (args (List a/AstExpr)) (indent Int64)] -> String
  :d "Formats a call expression with appropriate indentation and argument parentheses."
  (let [(pfx (indentPrefix indent))]
    (if (list-empty? args)
      (str pfx "(" (printAstExpr func 0) ")")
      (str pfx (printCallBody func args)))))

(df printMemberChain [(expr a/AstExpr)] -> String
  :d "Formats dot-access chains target.field recursively."
  (mt expr
    ((a/exprMember target field)
     (str (printMemberChain target) "." field))
    (_
     (printAstExprInArg expr))))

(df printTryExpr [(inner a/AstExpr)] -> String
  :d "Formats postfix error propagation try operator expr?."
  (mt inner
    ((a/exprCall _ _)
     (str "(" (printCallBody (callFunc inner) (callArgs inner)) ")?"))
    (_
     (str (printAstExpr inner 0) "?"))))

(df printLetBindingLine [(b (Pair a/AstPattern a/AstExpr)) (indent Int64)] -> String
  :d "Formats a single let destructuring line let pat = expr."
  (let [(pat (.-first b))
        (val (.-second b))]
    (str (indentPrefix indent) "let " (printAstPattern pat) " = " (printAstExpr val 0))))

(df printLetExpr [(bindings (List (Pair a/AstPattern a/AstExpr))) (body (List a/AstExpr)) (indent Int64)] -> String
  :d "Formats a let destructuring form with indented body."
  (let [(bindingLines (map (fn [(b (Pair a/AstPattern a/AstExpr))] -> String
                             (printLetBindingLine b indent))
                           bindings))]
    (if (list-empty? body)
      (string-join bindingLines "\n")
      (let [(bodyLines (map (fn [(e a/AstExpr)] -> String
                              (printAstExpr e (+ indent 1)))
                            body))]
        (str (string-join bindingLines "\n") "\n" (string-join bodyLines "\n"))))))

(df printMatchArm [(arm a/AstMatchArm) (indent Int64)] -> String
  :d "Formats a single match arm pat -> body."
  (let [(pat (.-pat arm))
        (body (.-body arm))]
    (str (indentPrefix indent) (printAstPattern pat) " -> " (printAstExpr body 0))))

(df printMatchExpr [(target a/AstExpr) (arms (List a/AstMatchArm)) (indent Int64)] -> String
  :d "Formats a match expression with indented arms."
  (let [(hdr (str (indentPrefix indent) "match " (printAstExpr target 0)))]
    (if (list-empty? arms)
      hdr
      (let [(armLines (map (fn [(a a/AstMatchArm)] -> String
                             (printMatchArm a (+ indent 1)))
                           arms))]
        (str hdr "\n" (string-join armLines "\n"))))))

(df printBlockExpr [(exprs (List a/AstExpr)) (indent Int64)] -> String
  :d "Formats sequential expressions indented by 2 spaces per level."
  (let [(lines (map (fn [(e a/AstExpr)] -> String
                      (printAstExpr e indent))
                    exprs))]
    (string-join lines "\n")))

(df printAstExpr [(expr a/AstExpr) (indent Int64)] -> String
  :d "Formats typed AstExpr into canonical ASL indented text."
  (mt expr
    ((a/exprLit lit)
     (str (indentPrefix indent) (printAstLit lit)))
    ((a/exprIdent name)
     (str (indentPrefix indent) name))
    ((a/exprMember _ _)
     (str (indentPrefix indent) (printMemberChain expr)))
    ((a/exprCall func args)
     (printAstCall func args indent))
    ((a/exprIf cond thenBranch elseBranch)
     (if (or (isBlockExpr? thenBranch) (isBlockExpr? elseBranch))
       (str (indentPrefix indent) "if " (printAstExprInArg cond) "\n"
            (printAstExpr thenBranch (+ indent 1)) "\n"
            (printAstExpr elseBranch (+ indent 1)))
       (str (indentPrefix indent) "if " (printAstExprInArg cond) " "
            (printAstExprInArg thenBranch) " "
            (printAstExprInArg elseBranch))))
    ((a/exprLet bindings body)
     (printLetExpr bindings body indent))
    ((a/exprMatch target arms)
     (printMatchExpr target arms indent))
    ((a/exprTry inner)
     (str (indentPrefix indent) (printTryExpr inner)))
    ((a/exprBlock exprs)
     (printBlockExpr exprs indent))))

(df printTopDefun [(d a/DefunNode)] -> String
  :d "Formats a DefunNode into fn name params -> retType with indented body."
  (let [(paramsText (string-join (map (fn [(p a/Param)] -> String (str (.-name p) ": " (.-type p)))
                                      (.-params d))
                                 " "))
        (sig (if (string-empty? paramsText)
               (str "fn " (.-name d) " -> " (.-retType d))
               (str "fn " (.-name d) " " paramsText " -> " (.-retType d))))]
    (if (list-empty? (.-body d))
      sig
      (let [(bodyLines (map (fn [(b rd/SExpr)] -> String
                              (let [(ast (cv/liftExpr b))]
                                (printAstExpr ast 1)))
                            (.-body d)))]
        (str sig "\n" (string-join bodyLines "\n"))))))

(df printTopForm [(tf a/TopForm)] -> String
  :d "Formats a top-level declaration node."
  (mt tf
    ((a/topDefun d)  (printTopDefun d))
    ((a/topSchema _) (a/renderNode tf))
    ((a/topEnum _)   (a/renderNode tf))
    ((a/topModule _) (a/renderNode tf))))

(df printAstModule [(mod a/ModuleNode)] -> String
  :d "Formats a full typed ModuleNode including header and declarations."
  (let [(header (a/renderNode (a/topModule mod)))]
    (if (list-empty? (.-defs mod))
      header
      (let [(renderedDefs (map (fn [(tf a/TopForm)] -> String (printTopForm tf)) (.-defs mod)))]
        (str header "\n\n" (string-join renderedDefs "\n\n"))))))
