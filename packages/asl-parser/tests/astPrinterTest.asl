(module asl-parser/astPrinterTest :x [runTests] :i [(astPrinter :a ap) (ast :a a) (astConverter :a cv) (indentParser :a ip) (reader :a rd)])

fn testLiteralsAndIdentifiers -> Bool
  (let [(litI (a/exprLit (a/litInt 42))) (litNeg (a/exprLit (a/litInt -99))) (litF (a/exprLit (a/litFloat 3.1415))) (litS (a/exprLit (a/litString "hello world"))) (litB1 (a/exprLit (a/litBool true))) (litB0 (a/exprLit (a/litBool false))) (litU (a/exprLit (a/litUnit))) (identX (a/exprIdent "x")) (identUser (a/exprIdent "userProfile"))] (let [(sI (ap/printAstExpr litI 0)) (sNeg (ap/printAstExpr litNeg 0)) (sF (ap/printAstExpr litF 0)) (sS (ap/printAstExpr litS 0)) (sB1 (ap/printAstExpr litB1 0)) (sB0 (ap/printAstExpr litB0 0)) (sU (ap/printAstExpr litU 0)) (sX (ap/printAstExpr identX 0)) (sUser (ap/printAstExpr identUser 0))] (assert (= sI "42") "Integer literal 42 must format as 42") (assert (= sNeg "-99") "Negative integer literal must format as -99") (assert (= sF "3.1415") "Float literal must format as 3.1415") (assert (= sS "\"hello world\"") "String literal must be enclosed in double quotes") (assert (= sB1 "true") "True boolean literal must format as true") (assert (= sB0 "false") "False boolean literal must format as false") (assert (= sU "()") "Unit literal must format as ()") (assert (= sX "x") "Identifier x must format as x") (assert (= sUser "userProfile") "Identifier userProfile must format as userProfile") (refute (= sI "43") "Integer 42 must refute 43") (refute (= sB1 "false") "True boolean must refute false") (refute (= sB0 "true") "False boolean must refute true") (refute (= sS "hello world") "String literal must refute unescaped unquoted string") (refute (not (stringStartsWith? sS "\"")) "String literal must refute missing opening quote") (refute (not (stringEndsWith? sS "\"")) "String literal must refute missing closing quote") (refute (= sU "unit") "Unit literal must refute keyword unit") (let [(reI (ip/parseIndented sI)) (reS (ip/parseIndented sS)) (reX (ip/parseIndented sX))] (assert (ok? reI) "Printed int literal must parse back cleanly") (assert (ok? reS) "Printed string literal must parse back cleanly") (assert (ok? reX) "Printed identifier must parse back cleanly") true)))

fn testCallsAndMemberAccess -> Bool
  (let [(callOuter (a/exprCall (a/exprIdent "add") (list (a/exprIdent "x") (a/exprIdent "y")))) (callNested (a/exprCall (a/exprIdent "mul") (list (a/exprIdent "pi") (a/exprCall (a/exprIdent "mul") (list (a/exprIdent "r") (a/exprIdent "r")))))) (callZero (a/exprCall (a/exprIdent "run") (list))) (mem1 (a/exprMember (a/exprIdent "user") "name")) (mem2 (a/exprMember (a/exprMember (a/exprIdent "user") "profile") "email")) (memCall (a/exprMember (a/exprCall (a/exprIdent "getUser") (list (a/exprIdent "id"))) "email"))] (let [(sOuter (ap/printAstExpr callOuter 0)) (sNested (ap/printAstExpr callNested 0)) (sZero (ap/printAstExpr callZero 0)) (sMem1 (ap/printAstExpr mem1 0)) (sMem2 (ap/printAstExpr mem2 0)) (sMemCall (ap/printAstExpr memCall 0))] (assert (= sOuter "add x y") "Outer call must format without enclosing parens") (refute (stringStartsWith? sOuter "(") "Outer call must refute leading paren") (refute (stringEndsWith? sOuter ")") "Outer call must refute trailing paren") (assert (= sNested "mul pi (mul r r)") "Nested call must format as mul pi (mul r r)") (assert (stringContains? sNested "(mul r r)") "Nested call in arg position must have parens") (refute (stringContains? sNested "mul pi mul r r") "Nested call must refute missing parens") (assert (= sZero "(run)") "Zero-argument call must format as (run)") (assert (= sMem1 "user.name") "Simple member access must format as user.name") (assert (= sMem2 "user.profile.email") "Chained member access must format as user.profile.email") (refute (stringContains? sMem2 ".-") "Member access must refute desugared .- accessor") (refute (stringContains? sMem2 "(") "Chained identifier member access must refute parens") (assert (= sMemCall "(getUser id).email") "Member access on call target must format target in parens") (assert (stringContains? sMemCall "(getUser id)") "Call target must be parenthesized") (let [(reOuter (ip/parseIndented sOuter)) (reNested (ip/parseIndented sNested)) (reMem2 (ip/parseIndented sMem2))] (assert (ok? reOuter) "Printed outer call must parse back cleanly") (assert (ok? reNested) "Printed nested call must parse back cleanly") (assert (ok? reMem2) "Printed chained member access must parse back cleanly") true)))

fn testTryOperator -> Bool
  (let [(tryIdent (a/exprTry (a/exprIdent "step"))) (tryMember (a/exprTry (a/exprMember (a/exprMember (a/exprIdent "service") "client") "fetch"))) (tryCall (a/exprTry (a/exprCall (a/exprIdent "queryDb") (list (a/exprIdent "id"))))) (tryOk (a/exprTry (a/exprCall (a/exprIdent "ok") (list (a/exprLit (a/litInt 42))))))] (let [(sTryIdent (ap/printAstExpr tryIdent 0)) (sTryMember (ap/printAstExpr tryMember 0)) (sTryCall (ap/printAstExpr tryCall 0)) (sTryOk (ap/printAstExpr tryOk 0))] (assert (= sTryIdent "step?") "Identifier try must format as step?") (refute (stringStartsWith? sTryIdent "(") "Identifier try must refute parens") (assert (= sTryMember "service.client.fetch?") "Member try must format as service.client.fetch?") (refute (stringContains? sTryMember " ") "Member access try must refute spaces") (assert (= sTryCall "(queryDb id)?") "Call try must format as (queryDb id)?") (assert (stringStartsWith? sTryCall "(") "Call try must start with opening paren") (assert (stringEndsWith? sTryCall ")?") "Call try must end with )?") (refute (= sTryCall "queryDb id?") "Call try must refute question mark attached to argument") (assert (= sTryOk "(ok 42)?") "Ok try must format as (ok 42)?") (let [(reIdent (ip/parseIndented sTryIdent)) (reMember (ip/parseIndented sTryMember)) (reCall (ip/parseIndented sTryCall))] (assert (ok? reIdent) "Printed identifier try must parse back cleanly") (assert (ok? reMember) "Printed member try must parse back cleanly") (assert (ok? reCall) "Printed call try must parse back cleanly") true)))

fn testLetDestructuring -> Bool
  (let [(letList (a/exprLet (list (pair (a/patTuple (list (a/patVar "a") (a/patVar "b"))) (a/exprIdent "pair"))) (list (a/exprCall (a/exprIdent "+") (list (a/exprIdent "a") (a/exprIdent "b")))))) (letRec (a/exprLet (list (pair (a/patRecord (list (pair "name" (a/patVar "name")) (pair "age" (a/patVar "age")))) (a/exprIdent "person"))) (list (a/exprCall (a/exprIdent "format") (list (a/exprIdent "name") (a/exprIdent "age")))))) (letMultiList (a/exprLet (list (pair (a/patTuple (list (a/patVar "x") (a/patVar "y") (a/patVar "z"))) (a/exprIdent "coords"))) (list (a/exprCall (a/exprIdent "+") (list (a/exprIdent "x") (a/exprCall (a/exprIdent "+") (list (a/exprIdent "y") (a/exprIdent "z"))))))))] (let [(sList (ap/printAstExpr letList 0)) (sRec (ap/printAstExpr letRec 0)) (sMulti (ap/printAstExpr letMultiList 0))] (assert (stringContains? sList "let [a b] = pair") "List destructuring must format let [a b] = pair") (assert (stringContains? sList "\n  + a b") "Body of let must be indented by 2 spaces") (refute (stringContains? sList "(listGet") "List destructuring must refute desugared listGet") (refute (stringContains? sList "let a =") "List destructuring must refute decomposed let a =") (assert (stringContains? sRec "let {name age} = person") "Record destructuring must format let {name age} = person") (assert (stringContains? sRec "\n  format name age") "Body of record let must be indented by 2 spaces") (refute (stringContains? sRec "(.-name") "Record destructuring must refute desugared .-name accessor") (refute (stringContains? sRec ",") "Record destructuring must refute commas") (assert (stringContains? sMulti "let [x y z] = coords") "3-element list destructuring must format let [x y z] = coords") (let [(reList (ip/parseIndented sList)) (reRec (ip/parseIndented sRec)) (reMulti (ip/parseIndented sMulti))] (assert (ok? reList) "Printed list destructuring must parse back cleanly") (assert (ok? reRec) "Printed record destructuring must parse back cleanly") (assert (ok? reMulti) "Printed 3-element list destructuring must parse back cleanly") true)))

fn testMatchWithArms -> Bool
  (let [(arm1 (a/makeMatchArm (a/patCtor "Ok" (some (a/patVar "res"))) (a/exprIdent "res"))) (arm2 (a/makeMatchArm (a/patCtor "Err" (some (a/patVar "msg"))) (a/exprCall (a/exprIdent "print") (list (a/exprIdent "msg"))))) (matchExpr (a/exprMatch (a/exprIdent "val") (list arm1 arm2))) (armCircle (a/makeMatchArm (a/patCtor "Circle" (some (a/patVar "r"))) (a/exprCall (a/exprIdent "mul") (list (a/exprIdent "pi") (a/exprCall (a/exprIdent "mul") (list (a/exprIdent "r") (a/exprIdent "r"))))))) (matchShape (a/exprMatch (a/exprIdent "s") (list armCircle)))] (let [(sMatch (ap/printAstExpr matchExpr 0)) (sShape (ap/printAstExpr matchShape 0))] (assert (stringContains? sMatch "mt val") "Match expression must start with mt val") (assert (stringContains? sMatch "((Ok res) res)") "Must format Ok arm as a (pattern body) pair") (assert (stringContains? sMatch "((Err msg) (print msg))") "Must format Err arm as a (pattern body) pair") (refute (stringContains? sMatch " -> ") "Match expression must not use arrow arms, which are not ASL") (refute (stringContains? sMatch "=>") "Match expression must refute fat arrow =>") (refute (stringContains? sMatch "Ok res res") "Match arm must refute missing arrow") (assert (stringContains? sShape "mt s") "Match shape must start with mt s") (assert (stringContains? sShape "((Circle r) (mul pi (mul r r)))") "Match arm must format ((Circle r) (mul pi (mul r r)))") (let [(reMatch (ip/parseIndented sMatch)) (reShape (ip/parseIndented sShape))] (assert (ok? reMatch) "Printed match form must parse back cleanly") (assert (ok? reShape) "Printed shape match form must parse back cleanly") true)))

fn testIfAndBlockExpressions -> Bool
  (let [(ifInline (a/exprIf (a/exprCall (a/exprIdent ">") (list (a/exprIdent "x") (a/exprLit (a/litInt 0)))) (a/exprLit (a/litInt 10)) (a/exprLit (a/litInt 20)))) (blockExpr (a/exprBlock (list (a/exprCall (a/exprIdent "step1") (list (a/exprIdent "a"))) (a/exprCall (a/exprIdent "step2") (list (a/exprIdent "b"))))))] (let [(sIf (ap/printAstExpr ifInline 0)) (sBlock0 (ap/printAstExpr blockExpr 0)) (sBlock1 (ap/printAstExpr blockExpr 1))] (assert (= sIf "if (> x 0) 10 20") "Inline if must format as if (> x 0) 10 20") (refute (stringContains? sIf "\n") "Inline simple if must refute newlines") (assert (= sBlock0 "step1 a\nstep2 b") "Block at level 0 must separate lines by newline") (assert (= sBlock1 "  step1 a\n  step2 b") "Block at level 1 must indent lines by 2 spaces") (refute (stringStartsWith? sBlock0 " ") "Block at level 0 must refute leading spaces") (refute (not (stringStartsWith? sBlock1 "  ")) "Block at level 1 must refute unindented line") (let [(reIf (ip/parseIndented sIf))] (assert (ok? reIf) "Printed if expression must parse back cleanly") true)))

fn testTopFormsAndModule -> Bool
  (let [(fnAdd (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list (a/Param :name "x" :type "Int") (a/Param :name "y" :type "Int")) :retType "Int" :docstring "\"Adds x and y\"" :body (list (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y")))) :bodyPos (list))) (pSchema (a/SchemaNode :name "Point" :typeVars (list) :fields (list (a/AstField :name "x" :type "Int64" :docstring "\"Horizontal\"" :default (none) :json (none)) (a/AstField :name "y" :type "Int64" :docstring "\"Vertical\"" :default (none) :json (none))) :jsonCase (none))) (eColor (a/EnumNode :name "Color" :typeVars (list) :cases (list (a/EnumCase :name "Red" :fields (list) :docstring "\"Red case\"") (a/EnumCase :name "Blue" :fields (list) :docstring "\"Blue case\"")))) (tfFn (a/topDefun fnAdd)) (tfSchema (a/topSchema pSchema)) (tfEnum (a/topEnum eColor)) (modNode (a/ModuleNode :path "geometry/shapes" :docstring "\"Geometry service\"" :exported (list "Point" "add") :imports (list (pair "algebra/vector" "vec")) :defs (list tfSchema tfFn)))] (let [(sFn (ap/printTopForm tfFn)) (sSchema (ap/printTopForm tfSchema)) (sEnum (ap/printTopForm tfEnum)) (sMod (ap/printAstModule modNode))] (assert (stringContains? sFn "fn add x: Int y: Int -> Int") "Top function must format fn add signature") (assert (stringContains? sFn "\n  (+ x y)") "Top function body must be indented with 2 spaces and keep its call parenthesized") (refute (stringStartsWith? sFn "(df") "Top function must refute verbose df") (refute (stringStartsWith? sFn (str "(" "defun")) "Top function must refute verbose defun") (refute (not (stringContains? sFn " -> ")) "Top function must refute missing return arrow") (assert (stringContains? sSchema "schema Point") "Schema must format schema Point") (assert (stringContains? sSchema "(:f x Int64 \"Horizontal\")") "Schema must format x field with the corpus :f key") (assert (stringContains? sSchema "(:f y Int64 \"Vertical\")") "Schema must format y field with the corpus :f key") (refute (not (stringContains? sSchema "Point")) "Schema must refute missing name") (assert (stringContains? sEnum "enum Color") "Enum must format enum Color") (assert (stringContains? sEnum "(:c Red [] \"Red case\")") "Enum must format Red case with the corpus :c key") (assert (stringContains? sEnum "(:c Blue [] \"Blue case\")") "Enum must format Blue case with the corpus :c key") (assert (stringContains? sMod "module geometry/shapes") "Module must format module header") (assert (stringContains? sMod ":x [Point add]") "Module must format exports with the corpus :x key") (assert (stringContains? sMod ":i [(algebra/vector :a vec)]") "Module must format imports with the corpus :i and :a keys") (assert (stringContains? sMod "schema Point") "Module text must embed schema") (assert (stringContains? sMod "fn add x: Int y: Int -> Int") "Module text must embed fn add") (refute (stringContains? sMod (str "(" "defun add")) "Module text must refute verbose defun add") (let [(reFn (ip/parseIndented sFn)) (reSchema (ip/parseIndented sSchema)) (reForms (ip/parseIndentedForms (str sSchema "\n" sFn)))] (assert (ok? reFn) "Printed top function must parse back cleanly") (assert (ok? reSchema) "Printed top schema must parse back cleanly") (assert (ok? reForms) "Printed schema and fn sequence must parse back cleanly via parseIndentedForms") (mt reForms ((ok forms) (assert (= (listLength forms) 2) "Sequence must yield exactly 2 parsed forms")) ((err msg) (refute true (str "Failed to parse forms: " msg)))) true)))

fn testAstTypeAndPatternPrinting -> Bool
  (let [(tNamed (a/typeNamed "Int64")) (tTuple (a/typeTuple (list (a/typeNamed "String") (a/typeNamed "Bool")))) (tRecord (a/typeRecord (list (pair "x" (a/typeNamed "Float64")) (pair "y" (a/typeNamed "Float64"))))) (tFn (a/typeFn (list (a/typeNamed "Int64") (a/typeNamed "Int64")) (a/typeNamed "Bool"))) (pWild (a/patWildcard)) (pVar (a/patVar "myVar")) (pLit (a/patLit (a/litInt 123))) (pTup (a/patTuple (list (a/patVar "a") (a/patVar "b")))) (pRec (a/patRecord (list (pair "width" (a/patVar "width")) (pair "height" (a/patVar "height"))))) (pCtorSome (a/patCtor "Some" (some (a/patVar "v")))) (pCtorNone (a/patCtor "None" (none)))] (let [(stNamed (ap/printAstType tNamed)) (stTuple (ap/printAstType tTuple)) (stRecord (ap/printAstType tRecord)) (stFn (ap/printAstType tFn)) (spWild (ap/printAstPattern pWild)) (spVar (ap/printAstPattern pVar)) (spLit (ap/printAstPattern pLit)) (spTup (ap/printAstPattern pTup)) (spRec (ap/printAstPattern pRec)) (spCtorSome (ap/printAstPattern pCtorSome)) (spCtorNone (ap/printAstPattern pCtorNone))] (assert (= stNamed "Int64") "Named type must format as Int64") (assert (= stTuple "[String Bool]") "Tuple type must format as [String Bool]") (assert (= stRecord "{x: Float64 y: Float64}") "Record type must format as {x: Float64 y: Float64}") (assert (= stFn "fn [Int64 Int64] -> Bool") "Function type must format as fn [Int64 Int64] -> Bool") (refute (= stNamed "Float64") "Int64 must refute Float64") (refute (= stTuple "{String Bool}") "Tuple type must refute curly braces") (refute (stringContains? stRecord ",") "Record type must refute commas") (refute (not (stringContains? stFn " -> ")) "Function type must refute missing arrow") (assert (= spWild "_") "Wildcard pattern must format as _") (assert (= spVar "myVar") "Variable pattern must format as myVar") (assert (= spLit "123") "Literal pattern must format as 123") (assert (= spTup "[a b]") "Tuple pattern must format as [a b]") (assert (= spRec "{width height}") "Record pattern must format as {width height}") (assert (= spCtorSome "Some v") "Constructor pattern must format as Some v") (assert (= spCtorNone "None") "Nullary constructor pattern must format as None") (refute (= spWild "*") "Wildcard must refute asterisk") (refute (stringContains? spTup ",") "Tuple pattern must refute commas") (refute (stringContains? spRec ",") "Record pattern must refute commas") (refute (= spCtorNone "None()") "Nullary constructor must refute trailing parens") true))

fn testHostDialectTopForms -> Bool
  (let [(src "(module probe/hostDialect :x [foo bar] :i [(ast :a a)])\n\nfn foo x: Int64 -> Int64\n  (let [(a 1) (b [x 2])] (listLength (map (fn [(p Int64)] -> Int64 (+ p a)) b)))\n\nfn bar -> Rec\n  (Rec :done? true)\n")
        (parsed (a/parse src))]
    (mt parsed
      ((err e) (do (assert false (str "host dialect probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))]
               (do
                 (assert (stringStartsWith? printed "(module probe/hostDialect :x [foo bar] :i [(ast :a a)])") (str "module header keeps the corpus :x :i keys: " printed))
                 (refute (stringContains? printed ":d \"") (str "a module without source docs prints no :d line: " printed))
                 (assert (stringContains? printed "(let [(a 1) (b (list x 2))] ") (str "let binding slot prints as a bracket vector: " printed))
                 (refute (stringContains? printed "(let (list") (str "let binding slot must not print as a (list ..) call: " printed))
                 (assert (stringContains? printed "(fn [(p Int64)] -> Int64 (+ p a))") (str "fn parameter slot prints as a bracket vector: " printed))
                 (refute (stringContains? printed "(fn (list") (str "fn parameter slot must not print as a (list ..) call: " printed))
                 (assert (stringContains? printed "\n  (Rec :done? true)") (str "a ?-suffixed keyword prints back as written: " printed))
                 (refute (stringContains? printed "(mt :done") (str "a ?-suffixed keyword must not print as a try match: " printed))
                 (assert (ok? reparsed) "printed host dialect module must reparse")
                 (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed host dialect module reparses to the same number of top forms")
                 true)))
            (_ (do (assert false "host dialect probe must parse to a module first") false))))
         ((none) (do (assert false "host dialect probe must yield forms") false))))))

fn testEffectMarkerAndTryGuard -> Bool
  (let [(src "(module probe/effect :x [go!] :i [])\n\nfn ! go! x: (Result Int64 String) -> (Result Int64 String)\n  (mt x ((ok __v) __v) ((err __e) (err __e)))\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "effect probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (again (mt (a/parse printed)
                            ((ok rf) (mt (listHead rf) ((some rtf) (mt rtf ((a/topModule rm) (ap/printAstModule rm)) (_ ""))) ((none) "")))
                            ((err _) "")))]
               (do
                 (assert (stringContains? printed "\nfn ! go! x: (Result Int64 String) -> (Result Int64 String)\n") (str "fn keeps its ! effect marker: " printed))
                 (assert (stringContains? printed "\n  (mt x ((ok __v) __v) ((err __e) (err __e)))") (str "a try match on a symbol target prints as written: " printed))
                 (refute (stringContains? printed "x?") (str "a try match on a symbol target must not print as x?: " printed))
                 (assert (= again printed) (str "printing the reparsed module reproduces the text, marker included: " again))
                 true)))
            (_ (do (assert false "effect probe must parse to a module first") false))))
         ((none) (do (assert false "effect probe must yield forms") false))))))

fn testTypedBindingPrinting -> Bool
  (let [(atomOf (fn [(t String)] -> rd/SExpr (rd/makeAtom t)))
        (typed (cv/lift (rd/makeList (list (atomOf "let") (rd/makeList (list (rd/makeList (list (rd/makeVect (list (atomOf "a") (atomOf "b"))) (rd/makeList (list (atomOf "List") (atomOf "Int64"))) (atomOf "pr"))))) (atomOf "a")))))
        (printed (ap/printAstExpr typed 0))]
    (do (refute (stringContains? printed ":typed") (str "the internal typed marker never reaches printed text: " printed))
        (assert (stringContains? printed "(List Int64) pr") (str "the typed binding prints its type then its value: " printed))
        true))

fn testUntypedParamBeforeTyped -> Bool
  (let [(src "(module probe/untypedParam :x [f] :i [])\n\nfn f text n: Int64 -> Int64\n  n\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "untyped-param probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (mt (listHead m.defs)
               ((some tfDefun)
                (mt tfDefun
                  ((a/topDefun d)
                   (let [(params d.params)
                         (printed (ap/printAstModule m))
                         (reparsed (a/parse printed))]
                     (do
                       (assert (= (listLength params) 2) (str "fn f must keep both params, got " (stringFromInt64 (listLength params))))
                       (assert (= (optionOr (listGet params 0) (a/Param :name "" :type "")).name "text") "first param name must stay text")
                       (assert (= (optionOr (listGet params 0) (a/Param :name "" :type "")).type "Any") (str "untyped first param must infer type Any; got '" (optionOr (listGet params 0) (a/Param :name "" :type "")).type "'"))
                       (assert (= (optionOr (listGet params 1) (a/Param :name "" :type "")).name "n") "second param name must stay n, not folded away")
                       (assert (= (optionOr (listGet params 1) (a/Param :name "" :type "")).type "Int64") "second param keeps its explicit type Int64")
                       (assert (stringContains? printed "fn f text: Any n: Int64 -> Int64") (str "printed signature must keep both params: " printed))
                       (assert (ok? reparsed) (str "printed untyped-param module must reparse: " printed))
                       (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed untyped-param module reparses to the same number of top forms")
                       true)))
                  (_ (do (assert false "untyped-param probe's first def must be a fn") false))))
               ((none) (do (assert false "untyped-param probe module must have a def") false))))
            (_ (do (assert false "untyped-param probe must parse to a module first") false))))
         ((none) (do (assert false "untyped-param probe must yield forms") false))))))

fn testInferredReturnTypeNoArrow -> Bool
  (let [(src "(module probe/inferredRet :x [f] :i [])\n\nfn f x: Any\n  (str \"hi \" x)\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "inferred-return probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (mt (listHead m.defs)
               ((some tfDefun)
                (mt tfDefun
                  ((a/topDefun d)
                   (let [(printed (ap/printAstModule m))
                         (reparsed (a/parse printed))]
                     (do
                       (assert (= d.retType ":inferredUnit") (str "a no-arrow fn header must be marked :inferredUnit, got " d.retType))
                       (assert (stringContains? printed "\nfn f x: Any\n") (str "printed header must drop the arrow and type entirely: " printed))
                       (refute (stringContains? printed "-> Unit") (str "printed header must refute a false -> Unit: " printed))
                       (refute (stringContains? printed "-> :inferredUnit") (str "printed header must refute leaking the internal sentinel: " printed))
                       (assert (ok? reparsed) (str "printed no-arrow module must reparse: " printed))
                       (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed no-arrow module reparses to the same number of top forms")
                       true)))
                  (_ (do (assert false "inferred-return probe's first def must be a fn") false))))
               ((none) (do (assert false "inferred-return probe module must have a def") false))))
            (_ (do (assert false "inferred-return probe must parse to a module first") false))))
         ((none) (do (assert false "inferred-return probe must yield forms") false))))))

fn testDottedModulePath -> Bool
  (let [(src "(module bench.aep.tests.ablationTest :x [f] :i [(bench.aep.ablation :a abl)])\n\nfn f -> Int64\n  1\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "dotted-path probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))
                   (imports m.imports)]
               (do
                 (assert (= m.path "bench.aep.tests.ablationTest") (str "module path must keep every dotted segment, got " m.path))
                 (assert (= (listLength imports) 1) (str "module must keep its one import, got " (stringFromInt64 (listLength imports))))
                 (assert (= (pairFirst (optionOr (listHead imports) (pair "" ""))) "bench.aep.ablation") (str "import path must keep every dotted segment, got " (pairFirst (optionOr (listHead imports) (pair "" "")))))
                 (assert (= (pairSecond (optionOr (listHead imports) (pair "" ""))) "abl") "import alias must stay abl")
                 (assert (stringStartsWith? printed "(module bench.aep.tests.ablationTest") (str "printed header must keep the dotted module path: " printed))
                 (assert (stringContains? printed ":i [(bench.aep.ablation :a abl)]") (str "printed header must keep the dotted import path: " printed))
                 (refute (stringContains? printed ".-") (str "printed module header must refute a leaked member-access accessor: " printed))
                 (assert (ok? reparsed) (str "printed dotted-path module must reparse: " printed))
                 (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed dotted-path module reparses to the same number of top forms")
                 true)))
            (_ (do (assert false "dotted-path probe must parse to a module first") false))))
         ((none) (do (assert false "dotted-path probe must yield forms") false))))))

fn testInlineEnumCasePrinting -> Bool
  (let [(src "(module probe/inlineEnum :x [f] :i [])\n\nenum TestColor (colorRed) (colorGreen) (colorBlue)\n\nfn f -> Int64\n  1\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "inline enum probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))]
               (do
                 (assert (stringContains? printed "(:c colorRed [] \"\")") (str "inline enum case must print as a canonical :c form: " printed))
                 (assert (stringContains? printed "(:c colorGreen [] \"\")") (str "inline enum case must print as a canonical :c form: " printed))
                 (assert (stringContains? printed "(:c colorBlue [] \"\")") (str "inline enum case must print as a canonical :c form: " printed))
                 (refute (stringContains? printed "(colorRed)") (str "inline enum case must not print as a bare uncanonicalized group: " printed))
                 (assert (ok? reparsed) (str "printed inline-enum module must reparse: " printed))
                 (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed inline-enum module reparses to the same number of top forms")
                 true)))
            (_ (do (assert false "inline enum probe must parse to a module first") false))))
         ((none) (do (assert false "inline enum probe must yield forms") false))))))

fn testInlineSchemaFieldPrinting -> Bool
  (let [(src "(module probe/inlineSchema :x [f] :i [])\n\nschema Point x: Int64 (y Int64)\n\nfn f -> Int64\n  1\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "inline schema probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))]
               (do
                 (assert (stringContains? printed "(:f x Int64 \"\")") (str "inline schema field must print as a canonical :f form: " printed))
                 (assert (stringContains? printed "(:f y Int64 \"\")") (str "inline schema field must print as a canonical :f form: " printed))
                 (refute (stringContains? printed "(y Int64)") (str "inline schema field must not print as a bare uncanonicalized group: " printed))
                 (assert (ok? reparsed) (str "printed inline-schema module must reparse: " printed))
                 (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed inline-schema module reparses to the same number of top forms")
                 true)))
            (_ (do (assert false "inline schema probe must parse to a module first") false))))
         ((none) (do (assert false "inline schema probe must yield forms") false))))))

fn testInlineEnumCaseFieldsDocOrder -> Bool
  (let [(src "(module probe/inlineEnumFields :x [f] :i [])\n\nenum Box (box value: Int64 label: String) \"a box\" (empty) \"nothing\" spare \"extra\"\n\nfn f -> Int64\n  1\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "inline enum fields probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))
                   (boxAt (optionOr (stringIndexOf printed "(:c box ") -1))
                   (emptyAt (optionOr (stringIndexOf printed "(:c empty ") -1))
                   (spareAt (optionOr (stringIndexOf printed "(:c spare ") -1))]
               (do
                 (assert (stringContains? printed "(:c box [(value Int64) (label String)] \"a box\")") (str "inline enum case must keep typed fields in order and its doc: " printed))
                 (assert (stringContains? printed "(:c empty [] \"nothing\")") (str "inline paren case without fields must keep its doc: " printed))
                 (assert (stringContains? printed "(:c spare [] \"extra\")") (str "inline bare case must keep its doc: " printed))
                 (refute (stringContains? printed "(Int64 Any)") (str "a field type must not print as a field name: " printed))
                 (assert (and (>= boxAt 0) (< boxAt emptyAt)) (str "inline enum cases must keep source order (box before empty): " printed))
                 (assert (< emptyAt spareAt) (str "inline enum cases must keep source order (empty before spare): " printed))
                 (assert (ok? reparsed) (str "printed inline-enum-fields module must reparse: " printed))
                 true)))
            (_ (do (assert false "inline enum fields probe must parse to a module first") false))))
         ((none) (do (assert false "inline enum fields probe must yield forms") false))))))

fn testInlineEnumCaseFormPassthrough -> Bool
  (let [(src "(module probe/inlineEnumForms :x [f] :i [])\n\nenum Tint : (:case red [] \"r\") (:c green [(n Int64)] \"g\")\n\nfn f -> Int64\n  1\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "inline enum case-form probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))]
               (do
                 (assert (stringContains? printed "(:c red [] \"r\")") (str "inline (:case ...) case must pass through: " printed))
                 (assert (stringContains? printed "(:c green [(n Int64)] \"g\")") (str "inline (:c ...) case must pass through with its fields: " printed))
                 (refute (stringContains? printed "(:c :case") (str "the :case keyword must not become a case name: " printed))
                 (refute (stringContains? printed "(:c : ") (str "a standalone : after the enum name must not become a case: " printed))
                 (assert (ok? reparsed) (str "printed inline-enum case-form module must reparse: " printed))
                 true)))
            (_ (do (assert false "inline enum case-form probe must parse to a module first") false))))
         ((none) (do (assert false "inline enum case-form probe must yield forms") false))))))

fn testArraySugarParamPrinting -> Bool
  (let [(src "(module probe/arrParam :x [f] :i [])\n\nfn f args: [Str] n: Int64 -> Int64\n  (+ (listLength args) n)\n")]
    (mt (a/parse src)
      ((err e) (do (assert false (str "array-sugar param probe source must parse: " e.msg)) false))
      ((ok forms)
       (mt (listHead forms)
         ((some tf)
          (mt tf
            ((a/topModule m)
             (let [(printed (ap/printAstModule m))
                   (reparsed (a/parse printed))]
               (do
                 (assert (stringContains? printed "fn f args: [Str] n: Int64 -> Int64") (str "array-sugar param must keep its name and [Str] type, and parsing must resume at the next param n: Int64: " printed))
                 (refute (stringContains? printed "Int64: Any") (str "the param after the [Str] group must not lose its name: " printed))
                 (refute (stringContains? printed "Str: Any") (str "array-sugar param must not split into bogus stray params such as Str: Any: " printed))
                 (refute (stringContains? printed "]: Any") (str "array-sugar param must not split into a bogus ']' typed param: " printed))
                 (assert (ok? reparsed) (str "printed array-sugar-param module must reparse: " printed))
                 (assert (= (mt reparsed ((ok rf) (listLength rf)) ((err _) -1)) (listLength forms)) "printed array-sugar-param module reparses to the same number of top forms")
                 true)))
            (_ (do (assert false "array-sugar param probe must parse to a module first") false))))
         ((none) (do (assert false "array-sugar param probe must yield forms") false))))))

fn runTests -> Bool
  (do (assert (testLiteralsAndIdentifiers) "testLiteralsAndIdentifiers passed") (assert (testCallsAndMemberAccess) "testCallsAndMemberAccess passed") (assert (testTryOperator) "testTryOperator passed") (assert (testLetDestructuring) "testLetDestructuring passed") (assert (testMatchWithArms) "testMatchWithArms passed") (assert (testIfAndBlockExpressions) "testIfAndBlockExpressions passed") (assert (testTopFormsAndModule) "testTopFormsAndModule passed") (assert (testAstTypeAndPatternPrinting) "testAstTypeAndPatternPrinting passed") (assert (testHostDialectTopForms) "testHostDialectTopForms passed") (assert (testEffectMarkerAndTryGuard) "testEffectMarkerAndTryGuard passed") (assert (testTypedBindingPrinting) "testTypedBindingPrinting passed") (assert (testUntypedParamBeforeTyped) "testUntypedParamBeforeTyped passed") (assert (testInferredReturnTypeNoArrow) "testInferredReturnTypeNoArrow passed") (assert (testDottedModulePath) "testDottedModulePath passed") (assert (testInlineEnumCasePrinting) "testInlineEnumCasePrinting passed") (assert (testInlineSchemaFieldPrinting) "testInlineSchemaFieldPrinting passed") (assert (testInlineEnumCaseFieldsDocOrder) "testInlineEnumCaseFieldsDocOrder passed") (assert (testInlineEnumCaseFormPassthrough) "testInlineEnumCaseFormPassthrough passed") (assert (testArraySugarParamPrinting) "testArraySugarParamPrinting passed") true)
