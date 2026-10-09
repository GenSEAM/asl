(module asl-parser/astConverterTest :x [runTests] :i [(astConverter :a ac) (ast :a a) (reader :a rd)])

fn litEqual? a: a/AstLit b: a/AstLit -> Bool
  (mt a ((a/litInt ai) (mt b ((a/litInt bi) (= ai bi)) (_ false))) ((a/litFloat af) (mt b ((a/litFloat bf) (= af bf)) (_ false))) ((a/litString as) (mt b ((a/litString bs) (= as bs)) (_ false))) ((a/litBool ab) (mt b ((a/litBool bb) (= ab bb)) (_ false))) ((a/litUnit) (mt b ((a/litUnit) true) (_ false))))

fn optPatternEqual? oa: (Option a/AstPattern) ob: (Option a/AstPattern) -> Bool
  (mt oa ((some pa) (mt ob ((some pb) (patternEqual? pa pb)) ((none) false))) ((none) (mt ob ((some _) false) ((none) true))))

fn patternsEqual? as: (List a/AstPattern) bs: (List a/AstPattern) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (and acc (patternEqual? (optionOr (listGet as i) (a/patWildcard)) (optionOr (listGet bs i) (a/patWildcard))))) true (range 0 len))))

fn patFieldsEqual? as: (List (Pair String a/AstPattern)) bs: (List (Pair String a/AstPattern)) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (let [(f1 (optionOr (listGet as i) (pair "" (a/patWildcard)))) (f2 (optionOr (listGet bs i) (pair "" (a/patWildcard))))] (and acc (and (= (pairFirst f1) (pairFirst f2)) (patternEqual? (pairSecond f1) (pairSecond f2)))))) true (range 0 len))))

fn patternEqual? a: a/AstPattern b: a/AstPattern -> Bool
  (mt a ((a/patWildcard) (mt b ((a/patWildcard) true) (_ false))) ((a/patVar an) (mt b ((a/patVar bn) (= an bn)) (_ false))) ((a/patLit al) (mt b ((a/patLit bl) (litEqual? al bl)) (_ false))) ((a/patTuple ae) (mt b ((a/patTuple be) (patternsEqual? ae be)) (_ false))) ((a/patRecord af) (mt b ((a/patRecord bf) (patFieldsEqual? af bf)) (_ false))) ((a/patCtor an aa) (mt b ((a/patCtor bn ba) (and (= an bn) (optPatternEqual? aa ba))) (_ false))))

fn typesEqual? as: (List a/AstType) bs: (List a/AstType) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (and acc (typeEqual? (optionOr (listGet as i) (a/typeNamed "")) (optionOr (listGet bs i) (a/typeNamed ""))))) true (range 0 len))))

fn typeFieldsEqual? as: (List (Pair String a/AstType)) bs: (List (Pair String a/AstType)) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (let [(f1 (optionOr (listGet as i) (pair "" (a/typeNamed "")))) (f2 (optionOr (listGet bs i) (pair "" (a/typeNamed ""))))] (and acc (and (= (pairFirst f1) (pairFirst f2)) (typeEqual? (pairSecond f1) (pairSecond f2)))))) true (range 0 len))))

fn typeEqual? a: a/AstType b: a/AstType -> Bool
  (mt a ((a/typeNamed an) (mt b ((a/typeNamed bn) (= an bn)) (_ false))) ((a/typeTuple ae) (mt b ((a/typeTuple be) (typesEqual? ae be)) (_ false))) ((a/typeRecord af) (mt b ((a/typeRecord bf) (typeFieldsEqual? af bf)) (_ false))) ((a/typeFn ap ar) (mt b ((a/typeFn bp br) (and (typesEqual? ap bp) (typeEqual? ar br))) (_ false))))

fn exprsEqual? as: (List a/AstExpr) bs: (List a/AstExpr) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (and acc (exprEqual? (optionOr (listGet as i) (a/exprLit (a/litUnit))) (optionOr (listGet bs i) (a/exprLit (a/litUnit)))))) true (range 0 len))))

fn bindingsEqual? as: (List (Pair a/AstPattern a/AstExpr)) bs: (List (Pair a/AstPattern a/AstExpr)) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (let [(p1 (optionOr (listGet as i) (pair (a/patWildcard) (a/exprLit (a/litUnit))))) (p2 (optionOr (listGet bs i) (pair (a/patWildcard) (a/exprLit (a/litUnit)))))] (and acc (and (patternEqual? (pairFirst p1) (pairFirst p2)) (exprEqual? (pairSecond p1) (pairSecond p2)))))) true (range 0 len))))

fn matchArmsEqual? as: (List a/AstMatchArm) bs: (List a/AstMatchArm) -> Bool
  (if (!= (listLength as) (listLength bs)) false (let [(len (listLength as))] (fold (fn [(acc Bool) (i Int64)] -> Bool (let [(a1 (optionOr (listGet as i) (a/matchArm (a/patWildcard) (a/exprLit (a/litUnit))))) (a2 (optionOr (listGet bs i) (a/matchArm (a/patWildcard) (a/exprLit (a/litUnit)))))] (and acc (and (patternEqual? a1.pat a2.pat) (exprEqual? a1.body a2.body))))) true (range 0 len))))

fn exprEqual? a: a/AstExpr b: a/AstExpr -> Bool
  (= a b)

fn checkExprRoundtrip expr: a/AstExpr -> Bool
  (let [(sexpr (ac/astToSexpr expr)) (reconverted (ac/sexprToAst sexpr))] (exprEqual? expr reconverted))

fn checkPatternRoundtrip pat: a/AstPattern -> Bool
  (let [(sexpr (ac/lowerPattern pat)) (reconverted (ac/liftPattern sexpr))] (patternEqual? pat reconverted))

fn checkTypeRoundtrip t: a/AstType -> Bool
  (let [(sexpr (ac/lowerType t)) (reconverted (ac/liftType sexpr))] (typeEqual? t reconverted))

fn testLiteralRoundtrips -> Bool
  (let [(eInt0 (a/exprLit (a/litInt 0))) (eInt42 (a/exprLit (a/litInt 42))) (eIntNeg (a/exprLit (a/litInt -999))) (eFloat1 (a/exprLit (a/litFloat 3.14))) (eFloatNeg (a/exprLit (a/litFloat -2.718))) (eStrEmpty (a/exprLit (a/litString ""))) (eStrText (a/exprLit (a/litString "hello world"))) (eStrAsl (a/exprLit (a/litString "agent-script"))) (eBoolTrue (a/exprLit (a/litBool true))) (eBoolFalse (a/exprLit (a/litBool false))) (eUnit (a/exprLit (a/litUnit)))] (assert (checkExprRoundtrip eInt0) "eInt0 roundtrip must preserve int 0") (assert (checkExprRoundtrip eInt42) "eInt42 roundtrip must preserve int 42") (assert (checkExprRoundtrip eIntNeg) "eIntNeg roundtrip must preserve int -999") (assert (checkExprRoundtrip eFloat1) "eFloat1 roundtrip must preserve float 3.14") (assert (checkExprRoundtrip eFloatNeg) "eFloatNeg roundtrip must preserve float -2.718") (assert (checkExprRoundtrip eStrEmpty) "eStrEmpty roundtrip must preserve empty string") (assert (checkExprRoundtrip eStrText) "eStrText roundtrip must preserve string content") (assert (checkExprRoundtrip eStrAsl) "eStrAsl roundtrip must preserve agent-script string") (assert (checkExprRoundtrip eBoolTrue) "eBoolTrue roundtrip must preserve true") (assert (checkExprRoundtrip eBoolFalse) "eBoolFalse roundtrip must preserve false") (assert (checkExprRoundtrip eUnit) "eUnit roundtrip must preserve unit") (refute (exprEqual? eInt42 eInt0) "eInt42 must refute eInt0") (refute (exprEqual? eInt42 (a/exprLit (a/litInt 43))) "eInt42 must refute eInt 43") (refute (exprEqual? eInt42 (a/exprLit (a/litString "42"))) "eInt42 must refute eStr '42'") (refute (exprEqual? eBoolTrue eBoolFalse) "eBoolTrue must refute eBoolFalse") (refute (exprEqual? eUnit eInt0) "eUnit must refute eInt0") (refute (exprEqual? eFloat1 eFloatNeg) "eFloat1 must refute eFloatNeg") (refute (exprEqual? eStrText eStrEmpty) "eStrText must refute eStrEmpty") true)

fn testIdentifiersCallsMemberAccesses -> Bool
  (let [(eIdX (a/exprIdent "x")) (eIdCounter (a/exprIdent "counter")) (eIdOp (a/exprIdent "+")) (eMem1 (a/exprMember (a/exprIdent "user") "name")) (eMemNested (a/exprMember (a/exprMember (a/exprIdent "state") "user") "id")) (eCallSimple (a/exprCall (a/exprIdent "+") (list (a/exprIdent "a") (a/exprLit (a/litInt 1))))) (eCallNullary (a/exprCall (a/exprIdent "now") (list))) (eCallNested (a/exprCall (a/exprIdent "f") (list (a/exprCall (a/exprIdent "g") (list (a/exprIdent "x"))))))] (assert (checkExprRoundtrip eIdX) "eIdX roundtrip must preserve identifier x") (assert (checkExprRoundtrip eIdCounter) "eIdCounter roundtrip must preserve counter") (assert (checkExprRoundtrip eIdOp) "eIdOp roundtrip must preserve +") (assert (checkExprRoundtrip eMem1) "eMem1 roundtrip must preserve user.name") (assert (checkExprRoundtrip eMemNested) "eMemNested roundtrip must preserve state.user.id") (assert (checkExprRoundtrip eCallSimple) "eCallSimple roundtrip must preserve (+ a 1)") (assert (checkExprRoundtrip eCallNullary) "eCallNullary roundtrip must preserve (now)") (assert (checkExprRoundtrip eCallNested) "eCallNested roundtrip must preserve (f (g x))") (refute (exprEqual? eIdX (a/exprIdent "y")) "eIdX must refute eIdY") (refute (exprEqual? eIdCounter (a/exprIdent "timer")) "eIdCounter must refute timer") (refute (exprEqual? eMem1 (a/exprMember (a/exprIdent "user") "email")) "eMem1 must refute user.email") (refute (exprEqual? eMem1 (a/exprMember (a/exprIdent "person") "name")) "eMem1 must refute person.name") (refute (exprEqual? eCallSimple (a/exprCall (a/exprIdent "-") (list (a/exprIdent "a") (a/exprLit (a/litInt 1))))) "eCallSimple must refute subtraction call") (refute (exprEqual? eCallNullary (a/exprCall (a/exprIdent "today") (list))) "eCallNullary must refute today call") true)

fn testControlFormsRoundtrip -> Bool
  (let [(eLet1 (a/exprLet (list (pair (a/patVar "k") (a/exprLit (a/litInt 42)))) (list (a/exprIdent "k")))) (eLetMulti (a/exprLet (list (pair (a/patVar "a") (a/exprLit (a/litInt 1))) (pair (a/patTuple (list (a/patVar "b") (a/patVar "c"))) (a/exprIdent "pair"))) (list (a/exprCall (a/exprIdent "add") (list (a/exprIdent "a") (a/exprIdent "b")))))) (eIf1 (a/exprIf (a/exprLit (a/litBool true)) (a/exprLit (a/litInt 10)) (a/exprLit (a/litInt 20)))) (eIfNested (a/exprIf (a/exprIdent "flag") (a/exprIf (a/exprIdent "sub") (a/exprLit (a/litInt 1)) (a/exprLit (a/litInt 2))) (a/exprLit (a/litInt 3)))) (eArm1 (a/matchArm (a/patVar "res") (a/exprIdent "res"))) (eArm2 (a/matchArm (a/patWildcard) (a/exprLit (a/litInt 0)))) (eArmCtor1 (a/matchArm (a/patCtor "Some" (some (a/patVar "v"))) (a/exprIdent "v"))) (eArmCtor2 (a/matchArm (a/patCtor "None" (none)) (a/exprLit (a/litInt -1)))) (eMatch1 (a/exprMatch (a/exprIdent "status") (list eArm1 eArm2))) (eMatchCtor (a/exprMatch (a/exprIdent "opt") (list eArmCtor1 eArmCtor2))) (eBlock1 (a/exprBlock (list (a/exprIdent "init") (a/exprLit (a/litUnit))))) (eBlockEmpty (a/exprBlock (list))) (eTry1 (a/exprTry (a/exprCall (a/exprIdent "read-file") (list (a/exprLit (a/litString "data.txt"))))))] (assert (checkExprRoundtrip eLet1) "eLet1 roundtrip must preserve let form") (assert (checkExprRoundtrip eLetMulti) "eLetMulti roundtrip must preserve multi let form") (assert (checkExprRoundtrip eIf1) "eIf1 roundtrip must preserve if form") (assert (checkExprRoundtrip eIfNested) "eIfNested roundtrip must preserve nested if form") (assert (checkExprRoundtrip eMatch1) "eMatch1 roundtrip must preserve match form") (assert (checkExprRoundtrip eMatchCtor) "eMatchCtor roundtrip must preserve ctor match form") (assert (checkExprRoundtrip eBlock1) "eBlock1 roundtrip must preserve block form") (assert (checkExprRoundtrip eBlockEmpty) "eBlockEmpty roundtrip must preserve empty block") (assert (checkExprRoundtrip eTry1) "eTry1 roundtrip must preserve try form") (refute (exprEqual? eIf1 (a/exprIf (a/exprLit (a/litBool false)) (a/exprLit (a/litInt 10)) (a/exprLit (a/litInt 20)))) "eIf1 must refute inverted condition") (refute (exprEqual? eIf1 (a/exprIf (a/exprLit (a/litBool true)) (a/exprLit (a/litInt 99)) (a/exprLit (a/litInt 20)))) "eIf1 must refute mutated then branch") (refute (exprEqual? eLet1 eLetMulti) "eLet1 must refute eLetMulti") (refute (exprEqual? eMatch1 eMatchCtor) "eMatch1 must refute eMatchCtor") (refute (exprEqual? eBlock1 eBlockEmpty) "eBlock1 must refute eBlockEmpty") (refute (exprEqual? eTry1 (a/exprTry (a/exprIdent "fail"))) "eTry1 must refute mutated inner") true)

fn testPatternAndTypeRoundtrips -> Bool
  (let [(pWild (a/patWildcard)) (pVar (a/patVar "alpha")) (pLit (a/patLit (a/litInt 99))) (pTup (a/patTuple (list (a/patVar "x") (a/patVar "y")))) (pRec (a/patRecord (list (pair "fieldA" (a/patVar "a")) (pair "fieldB" (a/patWildcard))))) (pCtor1 (a/patCtor "Some" (some (a/patVar "inner")))) (pCtor2 (a/patCtor "None" (none))) (tNamed (a/typeNamed "Int64")) (tTuple (a/typeTuple (list (a/typeNamed "String") (a/typeNamed "Bool")))) (tRecord (a/typeRecord (list (pair "x" (a/typeNamed "Float64")) (pair "y" (a/typeNamed "Float64"))))) (tFn (a/typeFn (list (a/typeNamed "Int64") (a/typeNamed "Int64")) (a/typeNamed "Bool")))] (assert (checkPatternRoundtrip pWild) "pWild roundtrip must preserve wildcard") (assert (checkPatternRoundtrip pVar) "pVar roundtrip must preserve var alpha") (assert (checkPatternRoundtrip pLit) "pLit roundtrip must preserve lit 99") (assert (checkPatternRoundtrip pTup) "pTup roundtrip must preserve tuple [x y]") (assert (checkPatternRoundtrip pRec) "pRec roundtrip must preserve record pattern") (assert (checkPatternRoundtrip pCtor1) "pCtor1 roundtrip must preserve Some ctor") (assert (checkPatternRoundtrip pCtor2) "pCtor2 roundtrip must preserve None ctor") (assert (checkTypeRoundtrip tNamed) "tNamed roundtrip must preserve Int64") (assert (checkTypeRoundtrip tTuple) "tTuple roundtrip must preserve tuple type") (assert (checkTypeRoundtrip tRecord) "tRecord roundtrip must preserve record type") (assert (checkTypeRoundtrip tFn) "tFn roundtrip must preserve function type") (refute (patternEqual? pWild pVar) "pWild must refute pVar") (refute (patternEqual? pCtor1 pCtor2) "pCtor1 must refute pCtor2") (refute (patternEqual? pTup (a/patTuple (list (a/patVar "x")))) "pTup must refute 1-element tuple") (refute (typeEqual? tNamed (a/typeNamed "Float64")) "tNamed must refute Float64") (refute (typeEqual? tTuple tRecord) "tTuple must refute tRecord") (refute (typeEqual? tFn (a/typeFn (list (a/typeNamed "Int64")) (a/typeNamed "Bool"))) "tFn must refute single parameter fn") true)

fn makeSynthesizedExpr idx: Int64 -> a/AstExpr
  (let [(modVal (mod idx 6))] (cond ((= modVal 0) (a/exprLit (a/litInt idx))) ((= modVal 1) (a/exprIdent (str "var_" (stringFromInt64 idx)))) ((= modVal 2) (a/exprMember (a/exprIdent (str "record_" (stringFromInt64 idx))) (str "f_" (stringFromInt64 idx)))) ((= modVal 3) (a/exprCall (a/exprIdent "compute") (list (a/exprIdent (str "arg_" (stringFromInt64 idx))) (a/exprLit (a/litInt idx))))) ((= modVal 4) (a/exprIf (a/exprLit (a/litBool (= (mod idx 2) 0))) (a/exprLit (a/litInt idx)) (a/exprLit (a/litInt (* idx 2))))) (else (a/exprLet (list (pair (a/patVar (str "k_" (stringFromInt64 idx))) (a/exprLit (a/litInt idx)))) (list (a/exprIdent (str "k_" (stringFromInt64 idx))))))))

fn testPropertyRoundtrips count: Int64 -> Bool
  (let [(passed (fold (fn [(acc Bool) (i Int64)] -> Bool (and acc (checkExprRoundtrip (makeSynthesizedExpr i)))) true (range 0 count)))] (assert passed "All synthesized property roundtrip expressions must pass") true)

fn testCorruptedConversionsRefutation -> Bool
  (let [(base (a/exprCall (a/exprIdent "calculate") (list (a/exprIdent "x") (a/exprLit (a/litInt 100))))) (canonicalSexpr (ac/astToSexpr base)) (corruptedSexpr (rd/makeList (list (rd/makeAtom "calculate") (rd/makeAtom "x") (rd/makeAtom "999")))) (corruptedHeadSexpr (rd/makeList (list (rd/makeAtom "calc") (rd/makeAtom "x") (rd/makeAtom "100")))) (liftedCorrupted (ac/sexprToAst corruptedSexpr)) (liftedCorruptedHead (ac/sexprToAst corruptedHeadSexpr))] (assert (checkExprRoundtrip base) "Base roundtrip must succeed") (refute (exprEqual? base liftedCorrupted) "Base AST must refute AST lifted from corrupted numeric argument") (refute (exprEqual? base liftedCorruptedHead) "Base AST must refute AST lifted from corrupted function head") (refute (= (rd/renderSexpr canonicalSexpr) (rd/renderSexpr corruptedSexpr)) "Canonical SExpr text must refute corrupted SExpr text") (refute (= (rd/renderSexpr canonicalSexpr) (rd/renderSexpr corruptedHeadSexpr)) "Canonical SExpr text must refute corrupted head SExpr text") true)

fn at name: String -> rd/SExpr
  (rd/makeAtom name)

fn moduleSexpr -> rd/SExpr
  (rd/makeList (list (at "module") (at "demo/mod") (at ":d") (at "\"Demo.\"") (at ":x") (rd/makeVect (list (at "f") (at "g"))) (at ":i") (rd/makeVect (list (rd/makeList (list (at "dep/one") (at ":a") (at "one")))))))

fn renderTop r: (Result a/TopForm String) -> String
  (mt r ((ok t) (rd/renderSexpr (ac/topFormToSexpr t))) ((err e) (str "error: " e)))

fn moduleFields r: (Result a/TopForm String) -> String
  (mt r ((ok t) (mt t ((a/topModule m) (str m.path "|" m.docstring "|" (stringJoin m.exported " ") "|" (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) m.imports) " "))) (_ "not a module"))) ((err e) (str "error: " e)))

fn tryCallee e: a/AstExpr -> String
  (mt e ((a/exprTry inner) (mt inner ((a/exprCall f _) (mt f ((a/exprIdent n) n) (_ "not an identifier"))) (_ "not a call"))) (_ "not a try"))

fn testTopFormConversions -> Bool
  (let [(modRes (ac/sexprToTopForm (moduleSexpr)))
        (fnS (rd/makeList (list (at "fn") (at "add") (rd/makeVect (list (rd/makeList (list (at "x") (at "Int64"))) (rd/makeList (list (at "y") (at "Int64"))))) (at "->") (at "Int64") (rd/makeList (list (at "+") (at "x") (at "y"))))))
        (enumS (rd/makeList (list (at "enum") (at "Color") (rd/makeList (list (at ":case") (at "red") (rd/makeVect (list (rd/makeList (list (at "shade") (at "Int64"))))) (at "\"Red.\""))))))
        (trySexpr (rd/makeList (list (at "mt") (rd/makeList (list (at "fetch"))) (rd/makeList (list (rd/makeList (list (at "ok") (at "__v"))) (at "__v"))) (rd/makeList (list (rd/makeList (list (at "err") (at "__e"))) (rd/makeList (list (at "err") (at "__e"))))))))]
    (do (assert (= (moduleFields modRes) "demo/mod|\"Demo.\"|f g|dep/one=one") (str "a module form converts with its path, doc, exports and imports: " (moduleFields modRes)))
        (assert (= (renderTop modRes) "(module demo/mod :doc \"Demo.\" :export [f g] :import [(dep/one :as one)])") (str "a module converts back with every field: " (renderTop modRes)))
        (assert (= (renderTop (ac/sexprToTopForm fnS)) "(fn add [(x Int64) (y Int64)] -> Int64 (+ x y))") (str "a fn converts back with a parameter vector: " (renderTop (ac/sexprToTopForm fnS))))
        (assert (= (renderTop (ac/sexprToTopForm enumS)) "(enum Color (:case red [(shade Int64)] \"Red.\"))") (str "an enum case converts back with a field vector: " (renderTop (ac/sexprToTopForm enumS))))
        (assert (= (tryCallee (ac/sexprToAst trySexpr)) "fetch") (str "the host try lowering lifts back to a try expression: " (tryCallee (ac/sexprToAst trySexpr))))
        true))

fn liftLowerRender s: rd/SExpr -> String
  (rd/renderSexpr (ac/lower (ac/lift s)))

fn bodyRoundtripMismatches src: String -> (List String)
  (mt (a/parse src)
    ((err e) (list (str "parse error: " e.msg)))
    ((ok forms)
     (fold (fn [(acc (List String)) (tf a/TopForm)] -> (List String)
             (mt tf
               ((a/topDefun d)
                (fold (fn [(inner (List String)) (b rd/SExpr)] -> (List String)
                        (if (= (rd/renderSexpr b) (liftLowerRender b)) inner (listAppend inner (list (str (rd/renderSexpr b) " => " (liftLowerRender b))))))
                      acc d.body))
               (_ acc)))
           (list) forms)))

fn assertTypedLet label: String src: String -> Bool
  (let [(bad (bodyRoundtripMismatches src))]
    (do (assert (listEmpty? bad) (str label ": " (stringJoin bad " | ")))
        (listEmpty? bad)))

fn testTypedLetBindings -> Bool
  (let [(typedValue (ac/lift (rd/makeList (list (at "let") (rd/makeVect (list (rd/makeList (list (at "flag") (at "Bool") (rd/makeList (list (at "str") (at "\"yes\""))))))) (at "flag")))))]
    (do (assert (stringContains? (rd/renderSexpr (ac/lower typedValue)) "(str \"yes\")") (str "a typed binding keeps its value expression: " (rd/renderSexpr (ac/lower typedValue))))
        (assertTypedLet "vect typed binding" "(fn f [] -> Bool (let [(flag Bool (str \"yes\"))] (= flag flag)))")
        (assertTypedLet "nested typed lets" "(fn f [] -> Int64 (let [(xs (List Int64) (list 1 2))] (let [(n Int64 (listLength xs))] n)))")
        (assertTypedLet "list-typed binding" "(fn f [] -> Int64 (let [(m (Map String (List Int64)) (mapEmpty))] (mapSize m)))")
        (assertTypedLet "record-typed binding" "(fn f [] -> Int64 (let [(r {a Int64} {a 1})] r.a))")
        (assertTypedLet "typed and untyped mixed" "(fn f [] -> Int64 (let [(a 1) (b Int64 2) (c {a Int64 b String} {a 1 b \"x\"})] (+ a b)))")
        (assertTypedLet "paren typed bindings" "(fn f [] -> Int64 (let ((a Int64 1) (b (Option Int64) (some 2))) a))")
        (assertTypedLet "nested-list typed bindings" "(fn f [] -> Int64 (let (list (a Int64 1) (b (List String) (list \"x\"))) a))")
        (assertTypedLet "untyped vect and record values" "(fn f [] -> Int64 (let [(v (list 1 2)) (r {a 1})] r.a))")
        true))

fn testExprEqualNewVariants -> Bool
  (do (assert (exprEqual? (a/exprInterpolation (list)) (a/exprInterpolation (list))) "empty interpolations compare equally") (refute (exprEqual? (a/exprInterpolation (list (a/exprIdent "x"))) (a/exprInterpolation (list (a/exprIdent "y")))) "interpolation parts differ") (assert (exprEqual? (a/exprRecord (list (pair "x" (a/exprLit (a/litInt 1)))) (list)) (a/exprRecord (list (pair "x" (a/exprLit (a/litInt 1)))) (list))) "record expressions compare their field names and values") (refute (exprEqual? (a/exprRecord (list (pair "x" (a/exprLit (a/litInt 1)))) (list)) (a/exprRecord (list (pair "y" (a/exprLit (a/litInt 1)))) (list))) "record field names differ") (assert (exprEqual? (a/exprCond (list (pair (a/exprIdent "x") (list)))) (a/exprCond (list (pair (a/exprIdent "x") (list))))) "cond clauses compare structurally") (refute (exprEqual? (a/exprCond (list (pair (a/exprIdent "x") (list)))) (a/exprCond (list (pair (a/exprIdent "y") (list))))) "cond predicates differ") (assert (exprEqual? (a/exprLambda (list) (none) (list) (rd/makeList (list))) (a/exprLambda (list) (none) (list) (rd/makeList (list)))) "empty lambdas compare structurally") (refute (exprEqual? (a/exprLambda (list) (none) (list (a/exprIdent "x")) (rd/makeList (list))) (a/exprLambda (list) (none) (list (a/exprIdent "y")) (rd/makeList (list)))) "lambda bodies differ") true)

fn runTests -> Bool
  (do (assert (testExprEqualNewVariants) "testExprEqualNewVariants passed") (assert (testLiteralRoundtrips) "testLiteralRoundtrips passed") (assert (testIdentifiersCallsMemberAccesses) "testIdentifiersCallsMemberAccesses passed") (assert (testControlFormsRoundtrip) "testControlFormsRoundtrip passed") (assert (testPatternAndTypeRoundtrips) "testPatternAndTypeRoundtrips passed") (assert (testPropertyRoundtrips 60) "60 synthesized property roundtrips passed") (assert (testCorruptedConversionsRefutation) "testCorruptedConversionsRefutation passed") (assert (testTopFormConversions) "testTopFormConversions passed") (assert (testTypedLetBindings) "testTypedLetBindings passed") true)
