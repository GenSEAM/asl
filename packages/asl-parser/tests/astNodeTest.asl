(module asl-parser/astNodeTest
  :d "Falsifiable test suite for Task 52604 Typed AST Hierarchy AstExpr, AstPattern, and AstType Definitions."
  :x [runTests]
  :i [(asl-parser/ast :a ast)])

(df isLitInt? [(lit ast/AstLit)] -> Bool
  :d "True if AstLit variant is litInt."
  (mt lit
    ((ast/litInt _) true)
    (_ false)))

(df isLitFloat? [(lit ast/AstLit)] -> Bool
  :d "True if AstLit variant is litFloat."
  (mt lit
    ((ast/litFloat _) true)
    (_ false)))

(df isLitString? [(lit ast/AstLit)] -> Bool
  :d "True if AstLit variant is litString."
  (mt lit
    ((ast/litString _) true)
    (_ false)))

(df isLitBool? [(lit ast/AstLit)] -> Bool
  :d "True if AstLit variant is litBool."
  (mt lit
    ((ast/litBool _) true)
    (_ false)))

(df isLitUnit? [(lit ast/AstLit)] -> Bool
  :d "True if AstLit variant is litUnit."
  (mt lit
    ((ast/litUnit) true)
    (_ false)))

(df getLitIntVal [(lit ast/AstLit)] -> Int64
  :d "Extracts Int64 value from litInt variant, defaulting to 0."
  (mt lit
    ((ast/litInt v) v)
    (_ 0)))

(df getLitFloatVal [(lit ast/AstLit)] -> Float64
  :d "Extracts Float64 value from litFloat variant, defaulting to 0.0."
  (mt lit
    ((ast/litFloat v) v)
    (_ 0.0)))

(df getLitStringVal [(lit ast/AstLit)] -> String
  :d "Extracts String value from litString variant, defaulting to empty string."
  (mt lit
    ((ast/litString v) v)
    (_ "")))

(df getLitBoolVal [(lit ast/AstLit)] -> Bool
  :d "Extracts Bool value from litBool variant, defaulting to false."
  (mt lit
    ((ast/litBool v) v)
    (_ false)))

(df testAstLitVariants [] -> Bool
  :d "Verifies construction and pattern matching over all AstLit variants with D77 refutations."
  (let [(lInt (ast/litInt 42))
        (lFloat (ast/litFloat 3.14))
        (lStr (ast/litString "agent-script"))
        (lBool (ast/litBool true))
        (lUnit (ast/litUnit))]
    (assert (isLitInt? lInt) "lInt must match litInt variant")
    (assert (= (getLitIntVal lInt) 42) "lInt must carry value 42")
    (refute (isLitFloat? lInt) "lInt must refute litFloat variant")
    (refute (isLitString? lInt) "lInt must refute litString variant")
    (refute (isLitBool? lInt) "lInt must refute litBool variant")
    (refute (isLitUnit? lInt) "lInt must refute litUnit variant")
    (refute (= (getLitIntVal lInt) 0) "lInt value must refute zero")

    (assert (isLitFloat? lFloat) "lFloat must match litFloat variant")
    (assert (= (getLitFloatVal lFloat) 3.14) "lFloat must carry value 3.14")
    (refute (isLitInt? lFloat) "lFloat must refute litInt variant")
    (refute (isLitString? lFloat) "lFloat must refute litString variant")
    (refute (isLitBool? lFloat) "lFloat must refute litBool variant")
    (refute (isLitUnit? lFloat) "lFloat must refute litUnit variant")

    (assert (isLitString? lStr) "lStr must match litString variant")
    (assert (= (getLitStringVal lStr) "agent-script") "lStr must carry value 'agent-script'")
    (refute (isLitInt? lStr) "lStr must refute litInt variant")
    (refute (isLitFloat? lStr) "lStr must refute litFloat variant")
    (refute (isLitBool? lStr) "lStr must refute litBool variant")
    (refute (string-empty? (getLitStringVal lStr)) "lStr value must refute empty string")

    (assert (isLitBool? lBool) "lBool must match litBool variant")
    (assert (getLitBoolVal lBool) "lBool must carry value true")
    (refute (isLitInt? lBool) "lBool must refute litInt variant")
    (refute (isLitUnit? lBool) "lBool must refute litUnit variant")
    (refute (not (getLitBoolVal lBool)) "lBool value must refute false")

    (assert (isLitUnit? lUnit) "lUnit must match litUnit variant")
    (refute (isLitInt? lUnit) "lUnit must refute litInt variant")
    (refute (isLitFloat? lUnit) "lUnit must refute litFloat variant")
    (refute (isLitString? lUnit) "lUnit must refute litString variant")
    (refute (isLitBool? lUnit) "lUnit must refute litBool variant")
    true))

(df isPatWildcard? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patWildcard."
  (mt pat
    ((ast/patWildcard) true)
    (_ false)))

(df isPatVar? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patVar."
  (mt pat
    ((ast/patVar _) true)
    (_ false)))

(df isPatLit? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patLit."
  (mt pat
    ((ast/patLit _) true)
    (_ false)))

(df isPatTuple? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patTuple."
  (mt pat
    ((ast/patTuple _) true)
    (_ false)))

(df isPatRecord? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patRecord."
  (mt pat
    ((ast/patRecord _) true)
    (_ false)))

(df isPatCtor? [(pat ast/AstPattern)] -> Bool
  :d "True if AstPattern is patCtor."
  (mt pat
    ((ast/patCtor _ _) true)
    (_ false)))

(df getPatVarName [(pat ast/AstPattern)] -> String
  :d "Extracts binding name from patVar."
  (mt pat
    ((ast/patVar n) n)
    (_ "")))

(df getPatCtorName [(pat ast/AstPattern)] -> String
  :d "Extracts constructor name from patCtor."
  (mt pat
    ((ast/patCtor n _) n)
    (_ "")))

(df getPatCtorArg [(pat ast/AstPattern)] -> (Option ast/AstPattern)
  :d "Extracts optional argument pattern from patCtor."
  (mt pat
    ((ast/patCtor _ arg) arg)
    (_ (none))))

(df getPatTupleElements [(pat ast/AstPattern)] -> (List ast/AstPattern)
  :d "Extracts tuple elements from patTuple."
  (mt pat
    ((ast/patTuple elems) elems)
    (_ (list))))

(df getPatRecordFields [(pat ast/AstPattern)] -> (List (Pair String ast/AstPattern))
  :d "Extracts record fields from patRecord."
  (mt pat
    ((ast/patRecord fields) fields)
    (_ (list))))

(df testAstPatternVariants [] -> Bool
  :d "Verifies construction and pattern matching over all AstPattern variants with D77 refutations."
  (let [(pWild (ast/patWildcard))
        (pVar (ast/patVar "alpha"))
        (pLit (ast/patLit (ast/litInt 99)))
        (pTup (ast/patTuple (list (ast/patVar "x") (ast/patVar "y"))))
        (pRec (ast/patRecord (list (pair "fieldA" (ast/patVar "a")) (pair "fieldB" (ast/patWildcard)))))
        (pCtorSome (ast/patCtor "Some" (some (ast/patVar "inner"))))
        (pCtorNone (ast/patCtor "None" (none)))]
    (assert (isPatWildcard? pWild) "pWild must match patWildcard")
    (refute (isPatVar? pWild) "pWild must refute patVar")
    (refute (isPatLit? pWild) "pWild must refute patLit")
    (refute (isPatTuple? pWild) "pWild must refute patTuple")
    (refute (isPatRecord? pWild) "pWild must refute patRecord")
    (refute (isPatCtor? pWild) "pWild must refute patCtor")

    (assert (isPatVar? pVar) "pVar must match patVar")
    (assert (= (getPatVarName pVar) "alpha") "pVar name must be alpha")
    (refute (isPatWildcard? pVar) "pVar must refute patWildcard")
    (refute (string-empty? (getPatVarName pVar)) "pVar name must refute empty string")
    (refute (= (getPatVarName pVar) "beta") "pVar name must refute beta")

    (assert (isPatLit? pLit) "pLit must match patLit")
    (mt pLit
      ((ast/patLit innerLit)
       (assert (isLitInt? innerLit) "innerLit must be litInt")
       (assert (= (getLitIntVal innerLit) 99) "innerLit must carry 99")
       (refute (= (getLitIntVal innerLit) 0) "innerLit must refute 0"))
      (_ (refute true "pLit branch unreachable")))

    (assert (isPatTuple? pTup) "pTup must match patTuple")
    (let [(elems (getPatTupleElements pTup))]
      (assert (= (list-length elems) 2) "pTup must have 2 elements")
      (refute (list-empty? elems) "pTup elements must refute empty list")
      (refute (= (list-length elems) 1) "pTup length must refute 1"))

    (assert (isPatRecord? pRec) "pRec must match patRecord")
    (let [(fields (getPatRecordFields pRec))]
      (assert (= (list-length fields) 2) "pRec must have 2 fields")
      (refute (list-empty? fields) "pRec fields must refute empty list")
      (mt (list-head fields)
        ((some f0)
         (assert (= (.-first f0) "fieldA") "First field name must be fieldA")
         (assert (isPatVar? (.-second f0)) "First field pattern must be patVar")
         (refute (= (.-first f0) "fieldB") "First field name must refute fieldB"))
        ((none) (refute true "pRec fields must not be empty"))))

    (assert (isPatCtor? pCtorSome) "pCtorSome must match patCtor")
    (assert (= (getPatCtorName pCtorSome) "Some") "pCtorSome ctor name must be Some")
    (refute (string-empty? (getPatCtorName pCtorSome)) "Constructor name must refute empty string")
    (refute (= (getPatCtorName pCtorSome) "") "pCtorSome name must refute empty literal")
    (mt (getPatCtorArg pCtorSome)
      ((some inner)
       (assert (isPatVar? inner) "pCtorSome inner must be patVar")
       (assert (= (getPatVarName inner) "inner") "pCtorSome inner name must be 'inner'")
       (refute (isPatWildcard? inner) "pCtorSome inner must refute patWildcard"))
      ((none) (refute true "pCtorSome must have argument")))

    (assert (isPatCtor? pCtorNone) "pCtorNone must match patCtor")
    (assert (= (getPatCtorName pCtorNone) "None") "pCtorNone ctor name must be None")
    (refute (string-empty? (getPatCtorName pCtorNone)) "pCtorNone ctor name must refute empty string")
    (mt (getPatCtorArg pCtorNone)
      ((some _) (refute true "pCtorNone must refute carrying an argument"))
      ((none) (assert true "pCtorNone correctly has no argument")))
    true))

(df isExprLit? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprLit."
  (mt expr
    ((ast/exprLit _) true)
    (_ false)))

(df isExprIdent? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprIdent."
  (mt expr
    ((ast/exprIdent _) true)
    (_ false)))

(df isExprMember? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprMember."
  (mt expr
    ((ast/exprMember _ _) true)
    (_ false)))

(df isExprCall? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprCall."
  (mt expr
    ((ast/exprCall _ _) true)
    (_ false)))

(df isExprLet? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprLet."
  (mt expr
    ((ast/exprLet _ _) true)
    (_ false)))

(df isExprIf? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprIf."
  (mt expr
    ((ast/exprIf _ _ _) true)
    (_ false)))

(df isExprMatch? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprMatch."
  (mt expr
    ((ast/exprMatch _ _) true)
    (_ false)))

(df isExprTry? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprTry."
  (mt expr
    ((ast/exprTry _) true)
    (_ false)))

(df isExprBlock? [(expr ast/AstExpr)] -> Bool
  :d "True if AstExpr is exprBlock."
  (mt expr
    ((ast/exprBlock _) true)
    (_ false)))

(df testAstExprVariants [] -> Bool
  :d "Verifies construction and pattern matching over all AstExpr variants with D77 refutations."
  (let [(eLit (ast/exprLit (ast/litInt 123)))
        (eIdent (ast/exprIdent "counter"))
        (eMember (ast/exprMember (ast/exprIdent "user") "id"))
        (eCall (ast/exprCall (ast/exprIdent "add") (list (ast/exprIdent "x") (ast/exprLit (ast/litInt 1)))))
        (eLet (ast/exprLet (list (pair (ast/patVar "k") (ast/exprLit (ast/litInt 42))))
                           (list (ast/exprIdent "k"))))
        (eIf (ast/exprIf (ast/exprLit (ast/litBool true))
                         (ast/exprLit (ast/litInt 10))
                         (ast/exprLit (ast/litInt 20))))
        (eArm1 (ast/matchArm (ast/patVar "res") (ast/exprIdent "res")))
        (eArm2 (ast/makeMatchArm (ast/patWildcard) (ast/exprLit (ast/litInt 0))))
        (eMatch (ast/exprMatch (ast/exprIdent "status") (list eArm1 eArm2)))
        (eTry (ast/exprTry (ast/exprCall (ast/exprIdent "read-file") (list (ast/exprLit (ast/litString "data.txt"))))))
        (eBlock (ast/exprBlock (list (ast/exprIdent "init") (ast/exprLit (ast/litUnit)))))]

    (assert (isExprLit? eLit) "eLit must match exprLit")
    (refute (isExprIdent? eLit) "eLit must refute exprIdent")
    (refute (isExprCall? eLit) "eLit must refute exprCall")
    (mt eLit
      ((ast/exprLit innerLit)
       (assert (isLitInt? innerLit) "eLit inner must be litInt")
       (assert (= (getLitIntVal innerLit) 123) "eLit value must be 123")
       (refute (= (getLitIntVal innerLit) 0) "eLit value must refute zero"))
      (_ (refute true "eLit branch unreachable")))

    (assert (isExprIdent? eIdent) "eIdent must match exprIdent")
    (refute (isExprLit? eIdent) "eIdent must refute exprLit")
    (mt eIdent
      ((ast/exprIdent name)
       (assert (= name "counter") "eIdent name must be counter")
       (refute (string-empty? name) "eIdent name must refute empty string")
       (refute (= name "wrong") "eIdent name must refute wrong string"))
      (_ (refute true "eIdent branch unreachable")))

    (assert (isExprMember? eMember) "eMember must match exprMember")
    (refute (isExprCall? eMember) "eMember must refute exprCall")
    (mt eMember
      ((ast/exprMember tgt fld)
       (assert (isExprIdent? tgt) "eMember target must be exprIdent")
       (assert (= fld "id") "eMember field must be id")
       (refute (string-empty? fld) "eMember field must refute empty string")
       (refute (= fld "name") "eMember field must refute name"))
      (_ (refute true "eMember branch unreachable")))

    (assert (isExprCall? eCall) "eCall must match exprCall")
    (refute (isExprMember? eCall) "eCall must refute exprMember")
    (mt eCall
      ((ast/exprCall fnExpr args)
       (assert (isExprIdent? fnExpr) "eCall func must be exprIdent")
       (assert (= (list-length args) 2) "eCall args count must be 2")
       (refute (list-empty? args) "eCall args must refute empty list")
       (refute (= (list-length args) 0) "eCall args count must refute 0"))
      (_ (refute true "eCall branch unreachable")))

    (assert (isExprLet? eLet) "eLet must match exprLet")
    (refute (isExprIf? eLet) "eLet must refute exprIf")
    (mt eLet
      ((ast/exprLet bindings body)
       (assert (= (list-length bindings) 1) "eLet bindings count must be 1")
       (assert (= (list-length body) 1) "eLet body count must be 1")
       (refute (list-empty? bindings) "eLet bindings must refute empty list")
       (refute (list-empty? body) "eLet body must refute empty list"))
      (_ (refute true "eLet branch unreachable")))

    (assert (isExprIf? eIf) "eIf must match exprIf")
    (refute (isExprLet? eIf) "eIf must refute exprLet")
    (mt eIf
      ((ast/exprIf condExpr thenBranch elseBranch)
       (assert (isExprLit? condExpr) "eIf cond must be exprLit")
       (assert (isExprLit? thenBranch) "eIf thenBranch must be exprLit")
       (assert (isExprLit? elseBranch) "eIf elseBranch must be exprLit")
       (refute (isExprIdent? condExpr) "eIf cond must refute exprIdent"))
      (_ (refute true "eIf branch unreachable")))

    (assert (isExprMatch? eMatch) "eMatch must match exprMatch")
    (refute (isExprTry? eMatch) "eMatch must refute exprTry")
    (mt eMatch
      ((ast/exprMatch target arms)
       (assert (isExprIdent? target) "eMatch target must be exprIdent")
       (assert (= (list-length arms) 2) "eMatch arms count must be 2")
       (refute (list-empty? arms) "eMatch arms must refute empty list")
       (refute (= (list-length arms) 0) "eMatch arms count must refute 0"))
      (_ (refute true "eMatch branch unreachable")))

    (assert (isExprTry? eTry) "eTry must match exprTry")
    (refute (isExprBlock? eTry) "eTry must refute exprBlock")
    (mt eTry
      ((ast/exprTry inner)
       (assert (isExprCall? inner) "eTry inner must be exprCall")
       (refute (isExprLit? inner) "eTry inner must refute exprLit"))
      (_ (refute true "eTry branch unreachable")))

    (assert (isExprBlock? eBlock) "eBlock must match exprBlock")
    (refute (isExprTry? eBlock) "eBlock must refute exprTry")
    (mt eBlock
      ((ast/exprBlock exprs)
       (assert (= (list-length exprs) 2) "eBlock exprs count must be 2")
       (refute (list-empty? exprs) "eBlock exprs must refute empty list")
       (refute (= (list-length exprs) 1) "eBlock exprs count must refute 1"))
      (_ (refute true "eBlock branch unreachable")))
    true))

(df isTypeNamed? [(t ast/AstType)] -> Bool
  :d "True if AstType is typeNamed."
  (mt t
    ((ast/typeNamed _) true)
    (_ false)))

(df isTypeTuple? [(t ast/AstType)] -> Bool
  :d "True if AstType is typeTuple."
  (mt t
    ((ast/typeTuple _) true)
    (_ false)))

(df isTypeRecord? [(t ast/AstType)] -> Bool
  :d "True if AstType is typeRecord."
  (mt t
    ((ast/typeRecord _) true)
    (_ false)))

(df isTypeFn? [(t ast/AstType)] -> Bool
  :d "True if AstType is typeFn."
  (mt t
    ((ast/typeFn _ _) true)
    (_ false)))

(df getTypeNamedName [(t ast/AstType)] -> String
  :d "Extracts type name from typeNamed."
  (mt t
    ((ast/typeNamed n) n)
    (_ "")))

(df testAstTypeVariants [] -> Bool
  :d "Verifies construction and pattern matching over all AstType variants with D77 refutations."
  (let [(tNamed (ast/typeNamed "Int64"))
        (tTuple (ast/typeTuple (list (ast/typeNamed "String") (ast/typeNamed "Bool"))))
        (tRecord (ast/typeRecord (list (pair "x" (ast/typeNamed "Float64")) (pair "y" (ast/typeNamed "Float64")))))
        (tFn (ast/typeFn (list (ast/typeNamed "Int64") (ast/typeNamed "Int64")) (ast/typeNamed "Bool")))]

    (assert (isTypeNamed? tNamed) "tNamed must match typeNamed")
    (assert (= (getTypeNamedName tNamed) "Int64") "tNamed name must be Int64")
    (refute (isTypeTuple? tNamed) "tNamed must refute typeTuple")
    (refute (isTypeRecord? tNamed) "tNamed must refute typeRecord")
    (refute (isTypeFn? tNamed) "tNamed must refute typeFn")
    (refute (string-empty? (getTypeNamedName tNamed)) "tNamed name must refute empty string")
    (refute (= (getTypeNamedName tNamed) "Float64") "tNamed name must refute Float64")

    (assert (isTypeTuple? tTuple) "tTuple must match typeTuple")
    (refute (isTypeNamed? tTuple) "tTuple must refute typeNamed")
    (mt tTuple
      ((ast/typeTuple elems)
       (assert (= (list-length elems) 2) "tTuple elements count must be 2")
       (refute (list-empty? elems) "tTuple elements must refute empty list")
       (refute (= (list-length elems) 1) "tTuple elements count must refute 1"))
      (_ (refute true "tTuple branch unreachable")))

    (assert (isTypeRecord? tRecord) "tRecord must match typeRecord")
    (refute (isTypeNamed? tRecord) "tRecord must refute typeNamed")
    (mt tRecord
      ((ast/typeRecord fields)
       (assert (= (list-length fields) 2) "tRecord fields count must be 2")
       (refute (list-empty? fields) "tRecord fields must refute empty list")
       (mt (list-head fields)
         ((some fld)
          (assert (= (.-first fld) "x") "First field name must be x")
          (assert (isTypeNamed? (.-second fld)) "First field type must be typeNamed")
          (refute (= (.-first fld) "y") "First field name must refute y"))
         ((none) (refute true "tRecord fields must not be empty"))))
      (_ (refute true "tRecord branch unreachable")))

    (assert (isTypeFn? tFn) "tFn must match typeFn")
    (refute (isTypeNamed? tFn) "tFn must refute typeNamed")
    (mt tFn
      ((ast/typeFn params ret)
       (assert (= (list-length params) 2) "tFn params count must be 2")
       (assert (isTypeNamed? ret) "tFn ret must be typeNamed")
       (assert (= (getTypeNamedName ret) "Bool") "tFn ret name must be Bool")
       (refute (list-empty? params) "tFn params must refute empty list")
       (refute (= (getTypeNamedName ret) "Int64") "tFn ret name must refute Int64"))
      (_ (refute true "tFn branch unreachable")))
    true))

(df testAstMatchArmDirectAndHelpers [] -> Bool
  :d "Verifies AstMatchArm construction via record literal, matchArm helper, and makeMatchArm helper."
  (let [(armLit (ast/AstMatchArm :pat (ast/patWildcard) :body (ast/exprLit (ast/litInt 0))))
        (armFn (ast/matchArm (ast/patVar "v") (ast/exprIdent "v")))
        (armMake (ast/makeMatchArm (ast/patLit (ast/litBool true)) (ast/exprLit (ast/litString "yes"))))]
    (assert (isPatWildcard? (.-pat armLit)) "armLit pat must be patWildcard")
    (assert (isExprLit? (.-body armLit)) "armLit body must be exprLit")
    (refute (isPatVar? (.-pat armLit)) "armLit pat must refute patVar")

    (assert (isPatVar? (.-pat armFn)) "armFn pat must be patVar")
    (assert (isExprIdent? (.-body armFn)) "armFn body must be exprIdent")
    (refute (isPatWildcard? (.-pat armFn)) "armFn pat must refute patWildcard")

    (assert (isPatLit? (.-pat armMake)) "armMake pat must be patLit")
    (assert (isExprLit? (.-body armMake)) "armMake body must be exprLit")
    (refute (isExprIdent? (.-body armMake)) "armMake body must refute exprIdent")
    true))

(df runTests [] -> Bool
  :d "Runs all falsifiable unit tests and D77 refutations for Typed AST Hierarchy."
  (do
    (assert (testAstLitVariants) "testAstLitVariants passed")
    (assert (testAstPatternVariants) "testAstPatternVariants passed")
    (assert (testAstExprVariants) "testAstExprVariants passed")
    (assert (testAstTypeVariants) "testAstTypeVariants passed")
    (assert (testAstMatchArmDirectAndHelpers) "testAstMatchArmDirectAndHelpers passed")
    true))
