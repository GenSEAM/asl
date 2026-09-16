(module asl-parser/astConverterTest
  :d "Falsifiable test suite for Task 52605 Bidirectional AST Converter and Roundtrip Equivalence."
  :x [runTests]
  :i [(astConverter :a ac) (ast :a a) (reader :a rd)])

(df litEqual? [(a a/AstLit) (b a/AstLit)] -> Bool
  :d "Checks structural equality between two AstLit instances."
  (mt a
    ((a/litInt ai)
     (mt b
       ((a/litInt bi) (= ai bi))
       (_ false)))
    ((a/litFloat af)
     (mt b
       ((a/litFloat bf) (= af bf))
       (_ false)))
    ((a/litString as)
     (mt b
       ((a/litString bs) (= as bs))
       (_ false)))
    ((a/litBool ab)
     (mt b
       ((a/litBool bb) (= ab bb))
       (_ false)))
    ((a/litUnit)
     (mt b
       ((a/litUnit) true)
       (_ false)))))

(df optPatternEqual? [(oa (Option a/AstPattern)) (ob (Option a/AstPattern))] -> Bool
  :d "Checks structural equality between two optional AstPattern instances."
  (mt oa
    ((some pa)
     (mt ob
       ((some pb) (patternEqual? pa pb))
       ((none)    false)))
    ((none)
     (mt ob
       ((some _) false)
       ((none)   true)))))

(df patternsEqual? [(as (List a/AstPattern)) (bs (List a/AstPattern))] -> Bool
  :d "Checks pairwise equality between two lists of AstPattern nodes."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (and acc (patternEqual? (option-or (list-get as i) (a/patWildcard))
                                      (option-or (list-get bs i) (a/patWildcard)))))
            true
            (range 0 len)))))

(df patFieldsEqual? [(as (List (Pair String a/AstPattern))) (bs (List (Pair String a/AstPattern)))] -> Bool
  :d "Checks pairwise equality between two lists of pattern fields."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (let [(f1 (option-or (list-get as i) (pair "" (a/patWildcard))))
                    (f2 (option-or (list-get bs i) (pair "" (a/patWildcard))))]
                (and acc (and (= (.-first f1) (.-first f2))
                              (patternEqual? (.-second f1) (.-second f2))))))
            true
            (range 0 len)))))

(df patternEqual? [(a a/AstPattern) (b a/AstPattern)] -> Bool
  :d "Checks structural equality between two AstPattern nodes."
  (mt a
    ((a/patWildcard)
     (mt b
       ((a/patWildcard) true)
       (_ false)))
    ((a/patVar an)
     (mt b
       ((a/patVar bn) (= an bn))
       (_ false)))
    ((a/patLit al)
     (mt b
       ((a/patLit bl) (litEqual? al bl))
       (_ false)))
    ((a/patTuple ae)
     (mt b
       ((a/patTuple be) (patternsEqual? ae be))
       (_ false)))
    ((a/patRecord af)
     (mt b
       ((a/patRecord bf) (patFieldsEqual? af bf))
       (_ false)))
    ((a/patCtor an aa)
     (mt b
       ((a/patCtor bn ba)
        (and (= an bn) (optPatternEqual? aa ba)))
       (_ false)))))

(df typesEqual? [(as (List a/AstType)) (bs (List a/AstType))] -> Bool
  :d "Checks pairwise equality between two lists of AstType nodes."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (and acc (typeEqual? (option-or (list-get as i) (a/typeNamed ""))
                                   (option-or (list-get bs i) (a/typeNamed "")))))
            true
            (range 0 len)))))

(df typeFieldsEqual? [(as (List (Pair String a/AstType))) (bs (List (Pair String a/AstType)))] -> Bool
  :d "Checks pairwise equality between two lists of type fields."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (let [(f1 (option-or (list-get as i) (pair "" (a/typeNamed ""))))
                    (f2 (option-or (list-get bs i) (pair "" (a/typeNamed ""))))]
                (and acc (and (= (.-first f1) (.-first f2))
                              (typeEqual? (.-second f1) (.-second f2))))))
            true
            (range 0 len)))))

(df typeEqual? [(a a/AstType) (b a/AstType)] -> Bool
  :d "Checks structural equality between two AstType nodes."
  (mt a
    ((a/typeNamed an)
     (mt b
       ((a/typeNamed bn) (= an bn))
       (_ false)))
    ((a/typeTuple ae)
     (mt b
       ((a/typeTuple be) (typesEqual? ae be))
       (_ false)))
    ((a/typeRecord af)
     (mt b
       ((a/typeRecord bf) (typeFieldsEqual? af bf))
       (_ false)))
    ((a/typeFn ap ar)
     (mt b
       ((a/typeFn bp br)
        (and (typesEqual? ap bp) (typeEqual? ar br)))
       (_ false)))))

(df exprsEqual? [(as (List a/AstExpr)) (bs (List a/AstExpr))] -> Bool
  :d "Checks pairwise equality between two lists of AstExpr nodes."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (and acc (exprEqual? (option-or (list-get as i) (a/exprLit (a/litUnit)))
                                   (option-or (list-get bs i) (a/exprLit (a/litUnit))))))
            true
            (range 0 len)))))

(df bindingsEqual? [(as (List (Pair a/AstPattern a/AstExpr))) (bs (List (Pair a/AstPattern a/AstExpr)))] -> Bool
  :d "Checks pairwise equality between two lists of let bindings."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (let [(p1 (option-or (list-get as i) (pair (a/patWildcard) (a/exprLit (a/litUnit)))))
                    (p2 (option-or (list-get bs i) (pair (a/patWildcard) (a/exprLit (a/litUnit)))))]
                (and acc (and (patternEqual? (.-first p1) (.-first p2))
                              (exprEqual? (.-second p1) (.-second p2))))))
            true
            (range 0 len)))))

(df matchArmsEqual? [(as (List a/AstMatchArm)) (bs (List a/AstMatchArm))] -> Bool
  :d "Checks pairwise equality between two lists of match arms."
  (if (!= (list-length as) (list-length bs))
    false
    (let [(len (list-length as))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (let [(a1 (option-or (list-get as i) (a/matchArm (a/patWildcard) (a/exprLit (a/litUnit)))))
                    (a2 (option-or (list-get bs i) (a/matchArm (a/patWildcard) (a/exprLit (a/litUnit)))))]
                (and acc (and (patternEqual? (.-pat a1) (.-pat a2))
                              (exprEqual? (.-body a1) (.-body a2))))))
            true
            (range 0 len)))))

(df exprEqual? [(a a/AstExpr) (b a/AstExpr)] -> Bool
  :d "Checks structural equality between two AstExpr nodes."
  (mt a
    ((a/exprLit al)
     (mt b
       ((a/exprLit bl) (litEqual? al bl))
       (_ false)))
    ((a/exprIdent an)
     (mt b
       ((a/exprIdent bn) (= an bn))
       (_ false)))
    ((a/exprMember at af)
     (mt b
       ((a/exprMember bt bf)
        (and (= af bf) (exprEqual? at bt)))
       (_ false)))
    ((a/exprCall af aa)
     (mt b
       ((a/exprCall bf ba)
        (and (exprEqual? af bf) (exprsEqual? aa ba)))
       (_ false)))
    ((a/exprLet ab aby)
     (mt b
       ((a/exprLet bb bby)
        (and (bindingsEqual? ab bb) (exprsEqual? aby bby)))
       (_ false)))
    ((a/exprIf ac at ae)
     (mt b
       ((a/exprIf bc bt be)
        (and (exprEqual? ac bc)
             (and (exprEqual? at bt) (exprEqual? ae be))))
       (_ false)))
    ((a/exprMatch at aa)
     (mt b
       ((a/exprMatch bt ba)
        (and (exprEqual? at bt) (matchArmsEqual? aa ba)))
       (_ false)))
    ((a/exprTry ai)
     (mt b
       ((a/exprTry bi) (exprEqual? ai bi))
       (_ false)))
    ((a/exprBlock ae)
     (mt b
       ((a/exprBlock be) (exprsEqual? ae be))
       (_ false)))))

(df checkExprRoundtrip [(expr a/AstExpr)] -> Bool
  :d "Verifies roundtrip equivalence: sexprToAst(astToSexpr(expr)) == expr."
  (let [(sexpr (ac/astToSexpr expr))
        (reconverted (ac/sexprToAst sexpr))]
    (exprEqual? expr reconverted)))

(df checkPatternRoundtrip [(pat a/AstPattern)] -> Bool
  :d "Verifies pattern roundtrip: liftPattern(lowerPattern(pat)) == pat."
  (let [(sexpr (ac/lowerPattern pat))
        (reconverted (ac/liftPattern sexpr))]
    (patternEqual? pat reconverted)))

(df checkTypeRoundtrip [(t a/AstType)] -> Bool
  :d "Verifies type roundtrip: liftType(lowerType(t)) == t."
  (let [(sexpr (ac/lowerType t))
        (reconverted (ac/liftType sexpr))]
    (typeEqual? t reconverted)))

(df testLiteralRoundtrips [] -> Bool
  :d "Tests roundtrip equivalence and D77 refutations for all AstLit variants."
  (let [(eInt0 (a/exprLit (a/litInt 0)))
        (eInt42 (a/exprLit (a/litInt 42)))
        (eIntNeg (a/exprLit (a/litInt -999)))
        (eFloat1 (a/exprLit (a/litFloat 3.14)))
        (eFloatNeg (a/exprLit (a/litFloat -2.718)))
        (eStrEmpty (a/exprLit (a/litString "")))
        (eStrText (a/exprLit (a/litString "hello world")))
        (eStrAsl (a/exprLit (a/litString "agent-script")))
        (eBoolTrue (a/exprLit (a/litBool true)))
        (eBoolFalse (a/exprLit (a/litBool false)))
        (eUnit (a/exprLit (a/litUnit)))]

    (assert (checkExprRoundtrip eInt0) "eInt0 roundtrip must preserve int 0")
    (assert (checkExprRoundtrip eInt42) "eInt42 roundtrip must preserve int 42")
    (assert (checkExprRoundtrip eIntNeg) "eIntNeg roundtrip must preserve int -999")
    (assert (checkExprRoundtrip eFloat1) "eFloat1 roundtrip must preserve float 3.14")
    (assert (checkExprRoundtrip eFloatNeg) "eFloatNeg roundtrip must preserve float -2.718")
    (assert (checkExprRoundtrip eStrEmpty) "eStrEmpty roundtrip must preserve empty string")
    (assert (checkExprRoundtrip eStrText) "eStrText roundtrip must preserve string content")
    (assert (checkExprRoundtrip eStrAsl) "eStrAsl roundtrip must preserve agent-script string")
    (assert (checkExprRoundtrip eBoolTrue) "eBoolTrue roundtrip must preserve true")
    (assert (checkExprRoundtrip eBoolFalse) "eBoolFalse roundtrip must preserve false")
    (assert (checkExprRoundtrip eUnit) "eUnit roundtrip must preserve unit")

    (refute (exprEqual? eInt42 eInt0) "eInt42 must refute eInt0")
    (refute (exprEqual? eInt42 (a/exprLit (a/litInt 43))) "eInt42 must refute eInt 43")
    (refute (exprEqual? eInt42 (a/exprLit (a/litString "42"))) "eInt42 must refute eStr '42'")
    (refute (exprEqual? eBoolTrue eBoolFalse) "eBoolTrue must refute eBoolFalse")
    (refute (exprEqual? eUnit eInt0) "eUnit must refute eInt0")
    (refute (exprEqual? eFloat1 eFloatNeg) "eFloat1 must refute eFloatNeg")
    (refute (exprEqual? eStrText eStrEmpty) "eStrText must refute eStrEmpty")
    true))

(df testIdentifiersCallsMemberAccesses [] -> Bool
  :d "Tests roundtrip of identifiers, calls, and member accesses with D77 refutations."
  (let [(eIdX (a/exprIdent "x"))
        (eIdCounter (a/exprIdent "counter"))
        (eIdOp (a/exprIdent "+"))
        (eMem1 (a/exprMember (a/exprIdent "user") "name"))
        (eMemNested (a/exprMember (a/exprMember (a/exprIdent "state") "user") "id"))
        (eCallSimple (a/exprCall (a/exprIdent "+")
                                 (list (a/exprIdent "a") (a/exprLit (a/litInt 1)))))
        (eCallNullary (a/exprCall (a/exprIdent "now") (list)))
        (eCallNested (a/exprCall (a/exprIdent "f")
                                 (list (a/exprCall (a/exprIdent "g") (list (a/exprIdent "x"))))))]

    (assert (checkExprRoundtrip eIdX) "eIdX roundtrip must preserve identifier x")
    (assert (checkExprRoundtrip eIdCounter) "eIdCounter roundtrip must preserve counter")
    (assert (checkExprRoundtrip eIdOp) "eIdOp roundtrip must preserve +")
    (assert (checkExprRoundtrip eMem1) "eMem1 roundtrip must preserve user.name")
    (assert (checkExprRoundtrip eMemNested) "eMemNested roundtrip must preserve state.user.id")
    (assert (checkExprRoundtrip eCallSimple) "eCallSimple roundtrip must preserve (+ a 1)")
    (assert (checkExprRoundtrip eCallNullary) "eCallNullary roundtrip must preserve (now)")
    (assert (checkExprRoundtrip eCallNested) "eCallNested roundtrip must preserve (f (g x))")

    (refute (exprEqual? eIdX (a/exprIdent "y")) "eIdX must refute eIdY")
    (refute (exprEqual? eIdCounter (a/exprIdent "timer")) "eIdCounter must refute timer")
    (refute (exprEqual? eMem1 (a/exprMember (a/exprIdent "user") "email")) "eMem1 must refute user.email")
    (refute (exprEqual? eMem1 (a/exprMember (a/exprIdent "person") "name")) "eMem1 must refute person.name")
    (refute (exprEqual? eCallSimple (a/exprCall (a/exprIdent "-")
                                                (list (a/exprIdent "a") (a/exprLit (a/litInt 1)))))
            "eCallSimple must refute subtraction call")
    (refute (exprEqual? eCallNullary (a/exprCall (a/exprIdent "today") (list)))
            "eCallNullary must refute today call")
    true))

(df testControlFormsRoundtrip [] -> Bool
  :d "Tests roundtrip of let bindings, if expressions, match expressions, and blocks."
  (let [(eLet1 (a/exprLet (list (pair (a/patVar "k") (a/exprLit (a/litInt 42))))
                          (list (a/exprIdent "k"))))
        (eLetMulti (a/exprLet (list (pair (a/patVar "a") (a/exprLit (a/litInt 1)))
                                    (pair (a/patTuple (list (a/patVar "b") (a/patVar "c")))
                                          (a/exprIdent "pair")))
                              (list (a/exprCall (a/exprIdent "add")
                                                (list (a/exprIdent "a") (a/exprIdent "b"))))))
        (eIf1 (a/exprIf (a/exprLit (a/litBool true))
                        (a/exprLit (a/litInt 10))
                        (a/exprLit (a/litInt 20))))
        (eIfNested (a/exprIf (a/exprIdent "flag")
                             (a/exprIf (a/exprIdent "sub")
                                       (a/exprLit (a/litInt 1))
                                       (a/exprLit (a/litInt 2)))
                             (a/exprLit (a/litInt 3))))
        (eArm1 (a/matchArm (a/patVar "res") (a/exprIdent "res")))
        (eArm2 (a/matchArm (a/patWildcard) (a/exprLit (a/litInt 0))))
        (eArmCtor1 (a/matchArm (a/patCtor "Some" (some (a/patVar "v"))) (a/exprIdent "v")))
        (eArmCtor2 (a/matchArm (a/patCtor "None" (none)) (a/exprLit (a/litInt -1))))
        (eMatch1 (a/exprMatch (a/exprIdent "status") (list eArm1 eArm2)))
        (eMatchCtor (a/exprMatch (a/exprIdent "opt") (list eArmCtor1 eArmCtor2)))
        (eBlock1 (a/exprBlock (list (a/exprIdent "init") (a/exprLit (a/litUnit)))))
        (eBlockEmpty (a/exprBlock (list)))
        (eTry1 (a/exprTry (a/exprCall (a/exprIdent "read-file")
                                      (list (a/exprLit (a/litString "data.txt"))))))]

    (assert (checkExprRoundtrip eLet1) "eLet1 roundtrip must preserve let form")
    (assert (checkExprRoundtrip eLetMulti) "eLetMulti roundtrip must preserve multi let form")
    (assert (checkExprRoundtrip eIf1) "eIf1 roundtrip must preserve if form")
    (assert (checkExprRoundtrip eIfNested) "eIfNested roundtrip must preserve nested if form")
    (assert (checkExprRoundtrip eMatch1) "eMatch1 roundtrip must preserve match form")
    (assert (checkExprRoundtrip eMatchCtor) "eMatchCtor roundtrip must preserve ctor match form")
    (assert (checkExprRoundtrip eBlock1) "eBlock1 roundtrip must preserve block form")
    (assert (checkExprRoundtrip eBlockEmpty) "eBlockEmpty roundtrip must preserve empty block")
    (assert (checkExprRoundtrip eTry1) "eTry1 roundtrip must preserve try form")

    (refute (exprEqual? eIf1 (a/exprIf (a/exprLit (a/litBool false))
                                       (a/exprLit (a/litInt 10))
                                       (a/exprLit (a/litInt 20))))
            "eIf1 must refute inverted condition")
    (refute (exprEqual? eIf1 (a/exprIf (a/exprLit (a/litBool true))
                                       (a/exprLit (a/litInt 99))
                                       (a/exprLit (a/litInt 20))))
            "eIf1 must refute mutated then branch")
    (refute (exprEqual? eLet1 eLetMulti) "eLet1 must refute eLetMulti")
    (refute (exprEqual? eMatch1 eMatchCtor) "eMatch1 must refute eMatchCtor")
    (refute (exprEqual? eBlock1 eBlockEmpty) "eBlock1 must refute eBlockEmpty")
    (refute (exprEqual? eTry1 (a/exprTry (a/exprIdent "fail"))) "eTry1 must refute mutated inner")
    true))

(df testPatternAndTypeRoundtrips [] -> Bool
  :d "Tests roundtrip of pattern and type converters with D77 refutations."
  (let [(pWild (a/patWildcard))
        (pVar (a/patVar "alpha"))
        (pLit (a/patLit (a/litInt 99)))
        (pTup (a/patTuple (list (a/patVar "x") (a/patVar "y"))))
        (pRec (a/patRecord (list (pair "fieldA" (a/patVar "a"))
                                 (pair "fieldB" (a/patWildcard)))))
        (pCtor1 (a/patCtor "Some" (some (a/patVar "inner"))))
        (pCtor2 (a/patCtor "None" (none)))
        (tNamed (a/typeNamed "Int64"))
        (tTuple (a/typeTuple (list (a/typeNamed "String") (a/typeNamed "Bool"))))
        (tRecord (a/typeRecord (list (pair "x" (a/typeNamed "Float64"))
                                     (pair "y" (a/typeNamed "Float64")))))
        (tFn (a/typeFn (list (a/typeNamed "Int64") (a/typeNamed "Int64"))
                       (a/typeNamed "Bool")))]

    (assert (checkPatternRoundtrip pWild) "pWild roundtrip must preserve wildcard")
    (assert (checkPatternRoundtrip pVar) "pVar roundtrip must preserve var alpha")
    (assert (checkPatternRoundtrip pLit) "pLit roundtrip must preserve lit 99")
    (assert (checkPatternRoundtrip pTup) "pTup roundtrip must preserve tuple [x y]")
    (assert (checkPatternRoundtrip pRec) "pRec roundtrip must preserve record pattern")
    (assert (checkPatternRoundtrip pCtor1) "pCtor1 roundtrip must preserve Some ctor")
    (assert (checkPatternRoundtrip pCtor2) "pCtor2 roundtrip must preserve None ctor")

    (assert (checkTypeRoundtrip tNamed) "tNamed roundtrip must preserve Int64")
    (assert (checkTypeRoundtrip tTuple) "tTuple roundtrip must preserve tuple type")
    (assert (checkTypeRoundtrip tRecord) "tRecord roundtrip must preserve record type")
    (assert (checkTypeRoundtrip tFn) "tFn roundtrip must preserve function type")

    (refute (patternEqual? pWild pVar) "pWild must refute pVar")
    (refute (patternEqual? pCtor1 pCtor2) "pCtor1 must refute pCtor2")
    (refute (patternEqual? pTup (a/patTuple (list (a/patVar "x")))) "pTup must refute 1-element tuple")
    (refute (typeEqual? tNamed (a/typeNamed "Float64")) "tNamed must refute Float64")
    (refute (typeEqual? tTuple tRecord) "tTuple must refute tRecord")
    (refute (typeEqual? tFn (a/typeFn (list (a/typeNamed "Int64")) (a/typeNamed "Bool")))
            "tFn must refute single parameter fn")
    true))

(df makeSynthesizedExpr [(idx Int64)] -> a/AstExpr
  :d "Generates diverse AST expression variants parameterized by index."
  (let [(modVal (mod idx 6))]
    (cond
      ((= modVal 0)
       (a/exprLit (a/litInt idx)))
      ((= modVal 1)
       (a/exprIdent (str "var_" (string-from-int64 idx))))
      ((= modVal 2)
       (a/exprMember (a/exprIdent (str "record_" (string-from-int64 idx)))
                     (str "f_" (string-from-int64 idx))))
      ((= modVal 3)
       (a/exprCall (a/exprIdent "compute")
                   (list (a/exprIdent (str "arg_" (string-from-int64 idx)))
                         (a/exprLit (a/litInt idx)))))
      ((= modVal 4)
       (a/exprIf (a/exprLit (a/litBool (= (mod idx 2) 0)))
                 (a/exprLit (a/litInt idx))
                 (a/exprLit (a/litInt (* idx 2)))))
      (:else
       (a/exprLet (list (pair (a/patVar (str "k_" (string-from-int64 idx)))
                              (a/exprLit (a/litInt idx))))
                  (list (a/exprIdent (str "k_" (string-from-int64 idx)))))))))

(df testPropertyRoundtrips [(count Int64)] -> Bool
  :d "Runs parameterized roundtrip equivalence property across synthesized AST expressions."
  (let [(passed (fold (fn [(acc Bool) (i Int64)] -> Bool
                        (and acc (checkExprRoundtrip (makeSynthesizedExpr i))))
                      true
                      (range 0 count)))]
    (assert passed "All synthesized property roundtrip expressions must pass")
    true))

(df testCorruptedConversionsRefutation [] -> Bool
  :d "Dual-polarity D77 refutations verifying that corrupted conversions are rejected."
  (let [(base (a/exprCall (a/exprIdent "calculate")
                          (list (a/exprIdent "x") (a/exprLit (a/litInt 100)))))
        (canonicalSexpr (ac/astToSexpr base))
        (corruptedSexpr (rd/makeList (list (rd/makeAtom "calculate")
                                           (rd/makeAtom "x")
                                           (rd/makeAtom "999"))))
        (corruptedHeadSexpr (rd/makeList (list (rd/makeAtom "calc")
                                               (rd/makeAtom "x")
                                               (rd/makeAtom "100"))))
        (liftedCorrupted (ac/sexprToAst corruptedSexpr))
        (liftedCorruptedHead (ac/sexprToAst corruptedHeadSexpr))]

    (assert (checkExprRoundtrip base) "Base roundtrip must succeed")
    (refute (exprEqual? base liftedCorrupted)
            "Base AST must refute AST lifted from corrupted numeric argument")
    (refute (exprEqual? base liftedCorruptedHead)
            "Base AST must refute AST lifted from corrupted function head")
    (refute (= (rd/renderSexpr canonicalSexpr) (rd/renderSexpr corruptedSexpr))
            "Canonical SExpr text must refute corrupted SExpr text")
    (refute (= (rd/renderSexpr canonicalSexpr) (rd/renderSexpr corruptedHeadSexpr))
            "Canonical SExpr text must refute corrupted head SExpr text")
    true))

(df runTests [] -> Bool
  :d "Executes all falsifiable unit tests, property tests, and D77 refutations for astConverter."
  (do
    (assert (testLiteralRoundtrips) "testLiteralRoundtrips passed")
    (assert (testIdentifiersCallsMemberAccesses) "testIdentifiersCallsMemberAccesses passed")
    (assert (testControlFormsRoundtrip) "testControlFormsRoundtrip passed")
    (assert (testPatternAndTypeRoundtrips) "testPatternAndTypeRoundtrips passed")
    (assert (testPropertyRoundtrips 60) "60 synthesized property roundtrips passed")
    (assert (testCorruptedConversionsRefutation) "testCorruptedConversionsRefutation passed")
    true))
