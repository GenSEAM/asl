(module asl-parser/astPrinterTest
  :d "Falsifiable test suite for Task 52606 Canonical Indented AST Formatter astPrinter."
  :x [runTests]
  :i [(astPrinter :a ap) (ast :a a) (astConverter :a cv) (indentParser :a ip) (reader :a rd)])

(df testLiteralsAndIdentifiers [] -> Bool
  :d "Verifies canonical indented printing of all AstLit variants and identifiers."
  (let [(litI (a/exprLit (a/litInt 42)))
        (litNeg (a/exprLit (a/litInt -99)))
        (litF (a/exprLit (a/litFloat 3.1415)))
        (litS (a/exprLit (a/litString "hello world")))
        (litB1 (a/exprLit (a/litBool true)))
        (litB0 (a/exprLit (a/litBool false)))
        (litU (a/exprLit (a/litUnit)))
        (identX (a/exprIdent "x"))
        (identUser (a/exprIdent "userProfile"))]

    (let [(sI (ap/printAstExpr litI 0))
          (sNeg (ap/printAstExpr litNeg 0))
          (sF (ap/printAstExpr litF 0))
          (sS (ap/printAstExpr litS 0))
          (sB1 (ap/printAstExpr litB1 0))
          (sB0 (ap/printAstExpr litB0 0))
          (sU (ap/printAstExpr litU 0))
          (sX (ap/printAstExpr identX 0))
          (sUser (ap/printAstExpr identUser 0))]

      (assert (= sI "42") "Integer literal 42 must format as 42")
      (assert (= sNeg "-99") "Negative integer literal must format as -99")
      (assert (= sF "3.1415") "Float literal must format as 3.1415")
      (assert (= sS "\"hello world\"") "String literal must be enclosed in double quotes")
      (assert (= sB1 "true") "True boolean literal must format as true")
      (assert (= sB0 "false") "False boolean literal must format as false")
      (assert (= sU "()") "Unit literal must format as ()")
      (assert (= sX "x") "Identifier x must format as x")
      (assert (= sUser "userProfile") "Identifier userProfile must format as userProfile")

      (refute (= sI "43") "Integer 42 must refute 43")
      (refute (= sB1 "false") "True boolean must refute false")
      (refute (= sB0 "true") "False boolean must refute true")
      (refute (= sS "hello world") "String literal must refute unescaped unquoted string")
      (refute (not (string-starts-with? sS "\"")) "String literal must refute missing opening quote")
      (refute (not (string-ends-with? sS "\"")) "String literal must refute missing closing quote")
      (refute (= sU "unit") "Unit literal must refute keyword unit")

      (let [(reI (ip/parseIndented sI))
            (reS (ip/parseIndented sS))
            (reX (ip/parseIndented sX))]
        (assert (is-ok? reI) "Printed int literal must parse back cleanly")
        (assert (is-ok? reS) "Printed string literal must parse back cleanly")
        (assert (is-ok? reX) "Printed identifier must parse back cleanly")
        true))))

(df testCallsAndMemberAccess [] -> Bool
  :d "Verifies canonical printing of function calls and dot-chain member access."
  (let [(callOuter (a/exprCall (a/exprIdent "add") (list (a/exprIdent "x") (a/exprIdent "y"))))
        (callNested (a/exprCall (a/exprIdent "mul")
                                (list (a/exprIdent "pi")
                                      (a/exprCall (a/exprIdent "mul")
                                                  (list (a/exprIdent "r") (a/exprIdent "r"))))))
        (callZero (a/exprCall (a/exprIdent "run") (list)))
        (mem1 (a/exprMember (a/exprIdent "user") "name"))
        (mem2 (a/exprMember (a/exprMember (a/exprIdent "user") "profile") "email"))
        (memCall (a/exprMember (a/exprCall (a/exprIdent "getUser") (list (a/exprIdent "id"))) "email"))]

    (let [(sOuter (ap/printAstExpr callOuter 0))
          (sNested (ap/printAstExpr callNested 0))
          (sZero (ap/printAstExpr callZero 0))
          (sMem1 (ap/printAstExpr mem1 0))
          (sMem2 (ap/printAstExpr mem2 0))
          (sMemCall (ap/printAstExpr memCall 0))]

      (assert (= sOuter "add x y") "Outer call must format without enclosing parens")
      (refute (string-starts-with? sOuter "(") "Outer call must refute leading paren")
      (refute (string-ends-with? sOuter ")") "Outer call must refute trailing paren")

      (assert (= sNested "mul pi (mul r r)") "Nested call must format as mul pi (mul r r)")
      (assert (string-contains? sNested "(mul r r)") "Nested call in arg position must have parens")
      (refute (string-contains? sNested "mul pi mul r r") "Nested call must refute missing parens")

      (assert (= sZero "(run)") "Zero-argument call must format as (run)")

      (assert (= sMem1 "user.name") "Simple member access must format as user.name")
      (assert (= sMem2 "user.profile.email") "Chained member access must format as user.profile.email")
      (refute (string-contains? sMem2 ".-") "Member access must refute desugared .- accessor")
      (refute (string-contains? sMem2 "(") "Chained identifier member access must refute parens")

      (assert (= sMemCall "(getUser id).email") "Member access on call target must format target in parens")
      (assert (string-starts-with? sMemCall "(getUser id)") "Call target must be parenthesized")

      (let [(reOuter (ip/parseIndented sOuter))
            (reNested (ip/parseIndented sNested))
            (reMem2 (ip/parseIndented sMem2))]
        (assert (is-ok? reOuter) "Printed outer call must parse back cleanly")
        (assert (is-ok? reNested) "Printed nested call must parse back cleanly")
        (assert (is-ok? reMem2) "Printed chained member access must parse back cleanly")
        true))))

(df testTryOperator [] -> Bool
  :d "Verifies error propagation try operator postfix '?' formatting."
  (let [(tryIdent (a/exprTry (a/exprIdent "step")))
        (tryMember (a/exprTry (a/exprMember (a/exprMember (a/exprIdent "service") "client") "fetch")))
        (tryCall (a/exprTry (a/exprCall (a/exprIdent "queryDb") (list (a/exprIdent "id")))))
        (tryOk (a/exprTry (a/exprCall (a/exprIdent "ok") (list (a/exprLit (a/litInt 42))))))]

    (let [(sTryIdent (ap/printAstExpr tryIdent 0))
          (sTryMember (ap/printAstExpr tryMember 0))
          (sTryCall (ap/printAstExpr tryCall 0))
          (sTryOk (ap/printAstExpr tryOk 0))]

      (assert (= sTryIdent "step?") "Identifier try must format as step?")
      (refute (string-starts-with? sTryIdent "(") "Identifier try must refute parens")

      (assert (= sTryMember "service.client.fetch?") "Member try must format as service.client.fetch?")
      (refute (string-contains? sTryMember " ") "Member access try must refute spaces")

      (assert (= sTryCall "(queryDb id)?") "Call try must format as (queryDb id)?")
      (assert (string-starts-with? sTryCall "(") "Call try must start with opening paren")
      (assert (string-ends-with? sTryCall ")?") "Call try must end with )?")
      (refute (= sTryCall "queryDb id?") "Call try must refute question mark attached to argument")

      (assert (= sTryOk "(ok 42)?") "Ok try must format as (ok 42)?")

      (let [(reIdent (ip/parseIndented sTryIdent))
            (reMember (ip/parseIndented sTryMember))
            (reCall (ip/parseIndented sTryCall))]
        (assert (is-ok? reIdent) "Printed identifier try must parse back cleanly")
        (assert (is-ok? reMember) "Printed member try must parse back cleanly")
        (assert (is-ok? reCall) "Printed call try must parse back cleanly")
        true))))

(df testLetDestructuring [] -> Bool
  :d "Verifies canonical indented printing of let list and record destructuring."
  (let [(letList (a/exprLet (list (pair (a/patTuple (list (a/patVar "a") (a/patVar "b")))
                                        (a/exprIdent "pair")))
                            (list (a/exprCall (a/exprIdent "+")
                                              (list (a/exprIdent "a") (a/exprIdent "b"))))))
        (letRec (a/exprLet (list (pair (a/patRecord (list (pair "name" (a/patVar "name"))
                                                          (pair "age" (a/patVar "age"))))
                                       (a/exprIdent "person")))
                           (list (a/exprCall (a/exprIdent "format")
                                             (list (a/exprIdent "name") (a/exprIdent "age"))))))
        (letMultiList (a/exprLet (list (pair (a/patTuple (list (a/patVar "x") (a/patVar "y") (a/patVar "z")))
                                             (a/exprIdent "coords")))
                                 (list (a/exprCall (a/exprIdent "+")
                                                   (list (a/exprIdent "x")
                                                         (a/exprCall (a/exprIdent "+")
                                                                     (list (a/exprIdent "y") (a/exprIdent "z"))))))))]

    (let [(sList (ap/printAstExpr letList 0))
          (sRec (ap/printAstExpr letRec 0))
          (sMulti (ap/printAstExpr letMultiList 0))]

      (assert (string-contains? sList "let [a b] = pair") "List destructuring must format let [a b] = pair")
      (assert (string-contains? sList "\n  + a b") "Body of let must be indented by 2 spaces")
      (refute (string-contains? sList "(list-get") "List destructuring must refute desugared list-get")
      (refute (string-contains? sList "let a =") "List destructuring must refute decomposed let a =")

      (assert (string-contains? sRec "let {name age} = person") "Record destructuring must format let {name age} = person")
      (assert (string-contains? sRec "\n  format name age") "Body of record let must be indented by 2 spaces")
      (refute (string-contains? sRec "(.-name") "Record destructuring must refute desugared .-name accessor")
      (refute (string-contains? sRec ",") "Record destructuring must refute commas")

      (assert (string-contains? sMulti "let [x y z] = coords") "3-element list destructuring must format let [x y z] = coords")

      (let [(reList (ip/parseIndented sList))
            (reRec (ip/parseIndented sRec))
            (reMulti (ip/parseIndented sMulti))]
        (assert (is-ok? reList) "Printed list destructuring must parse back cleanly")
        (assert (is-ok? reRec) "Printed record destructuring must parse back cleanly")
        (assert (is-ok? reMulti) "Printed 3-element list destructuring must parse back cleanly")
        true))))

(df testMatchWithArms [] -> Bool
  :d "Verifies match target with indented arms pat -> body formatting."
  (let [(arm1 (a/makeMatchArm (a/patCtor "Ok" (some (a/patVar "res")))
                              (a/exprIdent "res")))
        (arm2 (a/makeMatchArm (a/patCtor "Err" (some (a/patVar "msg")))
                              (a/exprCall (a/exprIdent "print") (list (a/exprIdent "msg")))))
        (matchExpr (a/exprMatch (a/exprIdent "val") (list arm1 arm2)))

        (armCircle (a/makeMatchArm (a/patCtor "Circle" (some (a/patVar "r")))
                                   (a/exprCall (a/exprIdent "mul")
                                               (list (a/exprIdent "pi")
                                                     (a/exprCall (a/exprIdent "mul")
                                                                 (list (a/exprIdent "r") (a/exprIdent "r")))))))
        (matchShape (a/exprMatch (a/exprIdent "s") (list armCircle)))]

    (let [(sMatch (ap/printAstExpr matchExpr 0))
          (sShape (ap/printAstExpr matchShape 0))]

      (assert (string-contains? sMatch "match val") "Match expression must start with match val")
      (assert (string-contains? sMatch "  Ok res -> res") "Must format Ok arm with arrow and 2-space indent")
      (assert (string-contains? sMatch "  Err msg -> print msg") "Must format Err arm with arrow and 2-space indent")
      (refute (not (string-contains? sMatch " -> ")) "Match expression must refute missing arrows")
      (refute (string-contains? sMatch "=>") "Match expression must refute fat arrow =>")
      (refute (string-contains? sMatch "Ok res res") "Match arm must refute missing arrow")

      (assert (string-contains? sShape "match s") "Match shape must start with match s")
      (assert (string-contains? sShape "  Circle r -> mul pi (mul r r)") "Match arm must format Circle r -> mul pi (mul r r)")

      (let [(reMatch (ip/parseIndented sMatch))
            (reShape (ip/parseIndented sShape))]
        (assert (is-ok? reMatch) "Printed match form must parse back cleanly")
        (assert (is-ok? reShape) "Printed shape match form must parse back cleanly")
        true))))

(df testIfAndBlockExpressions [] -> Bool
  :d "Verifies formatting of if conditionals and sequential block expressions."
  (let [(ifInline (a/exprIf (a/exprCall (a/exprIdent ">") (list (a/exprIdent "x") (a/exprLit (a/litInt 0))))
                            (a/exprLit (a/litInt 10))
                            (a/exprLit (a/litInt 20))))
        (blockExpr (a/exprBlock (list (a/exprCall (a/exprIdent "step1") (list (a/exprIdent "a")))
                                      (a/exprCall (a/exprIdent "step2") (list (a/exprIdent "b"))))))]

    (let [(sIf (ap/printAstExpr ifInline 0))
          (sBlock0 (ap/printAstExpr blockExpr 0))
          (sBlock1 (ap/printAstExpr blockExpr 1))]

      (assert (= sIf "if (> x 0) 10 20") "Inline if must format as if (> x 0) 10 20")
      (refute (string-contains? sIf "\n") "Inline simple if must refute newlines")

      (assert (= sBlock0 "step1 a\nstep2 b") "Block at level 0 must separate lines by newline")
      (assert (= sBlock1 "  step1 a\n  step2 b") "Block at level 1 must indent lines by 2 spaces")
      (refute (string-starts-with? sBlock0 " ") "Block at level 0 must refute leading spaces")
      (refute (not (string-starts-with? sBlock1 "  ")) "Block at level 1 must refute unindented line")

      (let [(reIf (ip/parseIndented sIf))]
        (assert (is-ok? reIf) "Printed if expression must parse back cleanly")
        true))))

(df testTopFormsAndModule [] -> Bool
  :d "Verifies printing of top-level function declarations, schemas, enums, and modules."
  (let [(fnAdd (a/DefunNode :name "add"
                            :typeVars (list)
                            :isExported true
                            :effect false
                            :params (list (a/Param :name "x" :type "Int")
                                          (a/Param :name "y" :type "Int"))
                            :retType "Int"
                            :docstring "\"Adds x and y\""
                            :body (list (rd/makeList (list (rd/makeAtom "+")
                                                          (rd/makeAtom "x")
                                                          (rd/makeAtom "y"))))))
        (pSchema (a/SchemaNode :name "Point"
                               :typeVars (list)
                               :fields (list (a/AstField :name "x" :type "Int64" :docstring "\"Horizontal\"" :default (none) :json (none))
                                             (a/AstField :name "y" :type "Int64" :docstring "\"Vertical\"" :default (none) :json (none)))
                               :jsonCase (none)))
        (eColor (a/EnumNode :name "Color"
                            :typeVars (list)
                            :cases (list (a/EnumCase :name "Red" :fields (list) :docstring "\"Red case\"")
                                         (a/EnumCase :name "Blue" :fields (list) :docstring "\"Blue case\""))))
        (tfFn (a/topDefun fnAdd))
        (tfSchema (a/topSchema pSchema))
        (tfEnum (a/topEnum eColor))
        (modNode (a/ModuleNode :path "geometry/shapes"
                               :docstring "\"Geometry service\""
                               :exported (list "Point" "add")
                               :imports (list (pair "algebra/vector" "vec"))
                               :defs (list tfSchema tfFn)))]

    (let [(sFn (ap/printTopForm tfFn))
          (sSchema (ap/printTopForm tfSchema))
          (sEnum (ap/printTopForm tfEnum))
          (sMod (ap/printAstModule modNode))]

      (assert (string-contains? sFn "fn add x: Int y: Int -> Int") "Top function must format fn add signature")
      (assert (string-contains? sFn "\n  + x y") "Top function body must be indented with 2 spaces")
      (refute (string-starts-with? sFn "(df") "Top function must refute verbose df")
      (refute (string-starts-with? sFn "(defun") "Top function must refute verbose defun")
      (refute (not (string-contains? sFn " -> ")) "Top function must refute missing return arrow")

      (assert (string-contains? sSchema "defschema Point") "Schema must format defschema Point")
      (assert (string-contains? sSchema ":field x Int64") "Schema must format x field")
      (assert (string-contains? sSchema ":field y Int64") "Schema must format y field")
      (refute (not (string-contains? sSchema "Point")) "Schema must refute missing name")

      (assert (string-contains? sEnum "defenum Color") "Enum must format defenum Color")
      (assert (string-contains? sEnum ":case Red") "Enum must format Red case")
      (assert (string-contains? sEnum ":case Blue") "Enum must format Blue case")

      (assert (string-contains? sMod "module geometry/shapes") "Module must format module header")
      (assert (string-contains? sMod ":export [Point add]") "Module must format exports")
      (assert (string-contains? sMod "(algebra/vector :as vec)") "Module must format imports")
      (assert (string-contains? sMod "defschema Point") "Module text must embed schema")
      (assert (string-contains? sMod "fn add x: Int y: Int -> Int") "Module text must embed fn add")
      (refute (string-contains? sMod "(defun add") "Module text must refute verbose defun add")

      (let [(reFn (ip/parseIndented sFn))
            (reSchema (ip/parseIndented sSchema))
            (reForms (ip/parseIndentedForms (str sSchema "\n" sFn)))]
        (assert (is-ok? reFn) "Printed top function must parse back cleanly")
        (assert (is-ok? reSchema) "Printed top schema must parse back cleanly")
        (assert (is-ok? reForms) "Printed schema and fn sequence must parse back cleanly via parseIndentedForms")
        (mt reForms
          ((ok forms)
           (assert (= (list-length forms) 2) "Sequence must yield exactly 2 parsed forms"))
          ((err msg)
           (refute true (str "Failed to parse forms: " msg))))
        true))))

(df testAstTypeAndPatternPrinting [] -> Bool
  :d "Verifies standalone AstType and AstPattern canonical printing."
  (let [(tNamed (a/typeNamed "Int64"))
        (tTuple (a/typeTuple (list (a/typeNamed "String") (a/typeNamed "Bool"))))
        (tRecord (a/typeRecord (list (pair "x" (a/typeNamed "Float64"))
                                     (pair "y" (a/typeNamed "Float64")))))
        (tFn (a/typeFn (list (a/typeNamed "Int64") (a/typeNamed "Int64"))
                       (a/typeNamed "Bool")))
        (pWild (a/patWildcard))
        (pVar (a/patVar "myVar"))
        (pLit (a/patLit (a/litInt 123)))
        (pTup (a/patTuple (list (a/patVar "a") (a/patVar "b"))))
        (pRec (a/patRecord (list (pair "width" (a/patVar "width"))
                                 (pair "height" (a/patVar "height")))))
        (pCtorSome (a/patCtor "Some" (some (a/patVar "v"))))
        (pCtorNone (a/patCtor "None" (none)))]

    (let [(stNamed (ap/printAstType tNamed))
          (stTuple (ap/printAstType tTuple))
          (stRecord (ap/printAstType tRecord))
          (stFn (ap/printAstType tFn))
          (spWild (ap/printAstPattern pWild))
          (spVar (ap/printAstPattern pVar))
          (spLit (ap/printAstPattern pLit))
          (spTup (ap/printAstPattern pTup))
          (spRec (ap/printAstPattern pRec))
          (spCtorSome (ap/printAstPattern pCtorSome))
          (spCtorNone (ap/printAstPattern pCtorNone))]

      (assert (= stNamed "Int64") "Named type must format as Int64")
      (assert (= stTuple "[String Bool]") "Tuple type must format as [String Bool]")
      (assert (= stRecord "{x: Float64 y: Float64}") "Record type must format as {x: Float64 y: Float64}")
      (assert (= stFn "fn [Int64 Int64] -> Bool") "Function type must format as fn [Int64 Int64] -> Bool")

      (refute (= stNamed "Float64") "Int64 must refute Float64")
      (refute (= stTuple "{String Bool}") "Tuple type must refute curly braces")
      (refute (string-contains? stRecord ",") "Record type must refute commas")
      (refute (not (string-contains? stFn " -> ")) "Function type must refute missing arrow")

      (assert (= spWild "_") "Wildcard pattern must format as _")
      (assert (= spVar "myVar") "Variable pattern must format as myVar")
      (assert (= spLit "123") "Literal pattern must format as 123")
      (assert (= spTup "[a b]") "Tuple pattern must format as [a b]")
      (assert (= spRec "{width height}") "Record pattern must format as {width height}")
      (assert (= spCtorSome "Some v") "Constructor pattern must format as Some v")
      (assert (= spCtorNone "None") "Nullary constructor pattern must format as None")

      (refute (= spWild "*") "Wildcard must refute asterisk")
      (refute (string-contains? spTup ",") "Tuple pattern must refute commas")
      (refute (string-contains? spRec ",") "Record pattern must refute commas")
      (refute (= spCtorNone "None()") "Nullary constructor must refute trailing parens")
      true)))

(df runTests [] -> Bool
  :d "Executes all falsifiable unit tests and D77 refutations for astPrinter."
  (do
    (assert (testLiteralsAndIdentifiers) "testLiteralsAndIdentifiers passed")
    (assert (testCallsAndMemberAccess) "testCallsAndMemberAccess passed")
    (assert (testTryOperator) "testTryOperator passed")
    (assert (testLetDestructuring) "testLetDestructuring passed")
    (assert (testMatchWithArms) "testMatchWithArms passed")
    (assert (testIfAndBlockExpressions) "testIfAndBlockExpressions passed")
    (assert (testTopFormsAndModule) "testTopFormsAndModule passed")
    (assert (testAstTypeAndPatternPrinting) "testAstTypeAndPatternPrinting passed")
    true))
