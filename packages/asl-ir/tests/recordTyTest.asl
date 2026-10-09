(module asl-ir/tests/recordTyTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/lower :a low)
      (asl-parser/ast :a ast)])

fn source -> String
  (stringJoin (list
    "(module recordTy :x [getY mk keep joined untyped pass lambda typedLambda same fnValue pick passOn built mixedJoin])"
    "(schema Point (:f x Int64) (:f y Int64))"
    "(fn getY [(p Point)] -> Int64 p.y)"
    "(fn mk [] -> Point (Point :x 1 :y 2))"
    "(fn keep [] -> Point (let [(p Point (mk))] p))"
    "(fn joined [(flag Bool)] -> Point (if flag (mk) (mk)))"
    "(fn untyped [p] -> Int64 0)"
    "(fn consume [p] -> Int64 0)"
    "(fn pass [(p Point)] -> Int64 (consume p))"
    "(fn lambda [] -> Int64 (let [(f (fn [p] -> Int64 0))] 0))"
    "(fn typedLambda [(p Point)] -> Int64 (let [(f (fn [(q Point)] -> Point (if (= q.x 0) p q)))] 0))"
    "(fn same [(p Point)] -> Point p)"
    "(fn fnValue [] -> Int64 (let [(f same)] 0))"
    "(fn pick [(flag Bool) (p Point)] -> Point (if flag p (mk)))"
    "(fn passOn [(flag Bool) (p Point)] -> Point (if flag (do (consume p) p) (mk)))"
    "(fn built [] -> Int64 (let [(p Point (Point :x 1 :y 2))] p.x))"
    "(fn mixedJoin [(flag Bool) (p Point) (r)] -> Int64 (consume (if flag p r)))") "\n")

fn rawLetSource -> String
  (stringJoin (list
    "(module rawLet :x [fromCall fromParam valOnly])"
    "(fn g [(n String)] -> String (str n))"
    "(fn fromCall [(s String)] -> Int64 (let [(x Int64 (g s))] (+ x 1)))"
    "(fn fromParam [(y String)] -> Int64 (let [(x Int64 y)] (+ x 1)))"
    "(fn valOnly [(y String)] -> (List Int64) (let [(x Int64 y)] (list x)))") "\n")

fn libSource -> String
  (stringJoin (list
    "(module rlib :x [Point mk getX])"
    "(schema Point (:f x Int64) (:f y Int64))"
    "(fn mk [] -> Point (Point :x 4 :y 5))"
    "(fn getX [(p Point)] -> Int64 p.x)") "\n")

fn appSource -> String
  (stringJoin (list
    "(module rapp :x [useMk] :i [(rlib :a l)])"
    "(schema Point (:f a Int64))"
    "(fn useMk [] -> Int64 (let [(p (l/mk))] (l/getX p)))") "\n")

fn getFn funcs: (List ty/SsaFunction) name: String -> (Option ty/SsaFunction)
  (fold (fn [(found (Option ty/SsaFunction)) (f ty/SsaFunction)] -> (Option ty/SsaFunction)
          (if (= f.name name) (some f) found)) (none) funcs)

fn fnNamed m: ty/SsaModule name: String -> ty/SsaFunction
  (optionOr (getFn m.functions name) (ty/ssaFunction "" (list) (list) (ty/tyVal) (list)))

fn isRecNamed t: ty/SsaTy name: String -> Bool
  (mt t ((ty/tyRec schema) (= schema name)) (_ false))

fn isPoint t: ty/SsaTy -> Bool
  (isRecNamed t "Point")

fn firstParamIsPoint f: ty/SsaFunction -> Bool
  (mt (listHead f.params) ((none) false) ((some p) (isPoint p.ty)))

fn noRecParam f: ty/SsaFunction -> Bool
  (listAll? (fn [(p ty/SsaParam)] -> Bool (= (ty/ssaTyName p.ty) "val")) f.params)

fn instrs f: ty/SsaFunction -> (List ty/SsaInstr)
  (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn hasPointDest f: ty/SsaFunction -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (and (isPoint i.ty) (mt i.op ((ty/opCall _ _) true) (_ false)))) (instrs f))

fn hasRecCallDest f: ty/SsaFunction name: String -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (and (isRecNamed i.ty name) (mt i.op ((ty/opCall _ _) true) (_ false)))) (instrs f))

fn externNamed m: ty/SsaModule name: String -> ty/SsaExtern
  (optionOr (listHead (filter (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs)) (ty/ssaExtern "" 0))

fn hasPointRecord f: ty/SsaFunction -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (and (isPoint i.ty) (mt i.op ((ty/opRecord _ _ _) true) (_ false)))) (instrs f))

fn hasUnboxTo f: ty/SsaFunction t: ty/SsaTy -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (and (= (ty/ssaTyName i.ty) (ty/ssaTyName t)) (mt i.op ((ty/opUnbox _) true) (_ false)))) (instrs f))

fn hasBoxInstr f: ty/SsaFunction -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (mt i.op ((ty/opBox _) true) (_ false))) (instrs f))

fn closesOver f: ty/SsaFunction callee: String -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (mt i.op ((ty/opMakeClosure c _) (= c callee)) (_ false))) (instrs f))

fn hasPointBlockParam f: ty/SsaFunction -> Bool
  (listAny? (fn [(b ty/SsaBlock)] -> Bool (listAny? (fn [(p ty/SsaParam)] -> Bool (isPoint p.ty)) b.params)) f.blocks)

fn hasValBlockParam f: ty/SsaFunction -> Bool
  (listAny? (fn [(b ty/SsaBlock)] -> Bool (listAny? (fn [(p ty/SsaParam)] -> Bool (= (ty/ssaTyName p.ty) "val")) b.params)) f.blocks)

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) ds) "; ")

fn verifyText m: ty/SsaModule -> String
  (mt (vfy/verifySsa m) ((ok _) "") ((err ds) (diagText ds)))

fn testRecordModule -> Bool
  (mt (low/lowerSource (source))
    ((err ds) (assert false (str "record schema source lowers: " (diagText ds))))
    ((ok m)
      (do (assert (firstParamIsPoint (fnNamed m "getY")) "annotated schema parameter retains identity")
          (assert (isPoint (fnNamed m "mk").retTy) "schema return retains identity")
          (assert (hasPointDest (fnNamed m "keep")) "typed let call destination retains identity")
          (assert (hasPointBlockParam (fnNamed m "joined")) "same-schema branch join retains identity")
          (assert (noRecParam (fnNamed m "untyped")) "untyped parameter remains Val")
          (assert (not (listAny? (fn [(f ty/SsaFunction)] -> Bool (and (stringContains? f.name "@lambda") (not (noRecParam f)))) m.functions)) "lambda parameters remain Val")
          (assert (stringContains? (prn/printSsa m) "rec:Point") "printer emits schema identity")
          (assert (stringEmpty? (verifyText m)) (str "verifySsa accepts record Vals at untyped calls and joins: " (verifyText m)))
          (refute (ty/ssaIsRaw? (ty/tyRec "Point")) "a record type is not raw")
          (assert (= (ty/ssaAbiName (ty/tyRec "Point")) "val") "a record type passes as a Val")
          (assert (closesOver (fnNamed m "fnValue") "same") "a function over records only is a closure value directly, no raw wrapper")
          (refute (listAny? (fn [(f ty/SsaFunction)] -> Bool (stringStartsWith? f.name "fnValue@")) m.functions) "no wrapper lambda is lifted for a record-only signature")
          (assert (hasPointBlockParam (fnNamed m "pick")) "a record parameter joined with a record call keeps its identity")
          (assert (hasPointBlockParam (fnNamed m "passOn")) "passing a record to a Val parameter does not erase its identity at a later join")
          (assert (hasPointRecord (fnNamed m "built")) "a typed let tags the record construction it binds")
          (assert (hasPointBlockParam (fnNamed m "typedLambda@lambda0")) "an annotated record lambda parameter and a record capture keep their identity at a join in the lambda body")
          (assert (hasValBlockParam (fnNamed m "mixedJoin")) "a record arm joined with a genuine Val arm (p and r, no shared schema) joins at Val, exercising joinTy's mixed-type path")
          (assert (not (hasBoxInstr (fnNamed m "mixedJoin"))) "convertExit's self-candidate lets a record arm reach a Val join directly, since a record is already a Val in the ABI (ssaAbiName), so no opBox is emitted for it (RT mutant M3)")
          true)))

fn testRawLet -> Bool
  (mt (low/lowerSource (rawLetSource))
    ((err ds) (assert false (str "typed lets with raw annotations lower: " (diagText ds))))
    ((ok m)
      (do (assert (stringEmpty? (verifyText m)) (str "typed lets with raw annotations verify: " (verifyText m)))
          (assert (hasUnboxTo (fnNamed m "fromCall") (ty/tyI64)) "a Val call result bound as Int64 is unboxed")
          (assert (hasUnboxTo (fnNamed m "fromParam") (ty/tyI64)) "a Val parameter bound as Int64 is unboxed")
          (assert (hasUnboxTo (fnNamed m "valOnly") (ty/tyI64)) "a Val bound as Int64 is unboxed where it binds, though only a Val context uses it")
          true)))

fn lowerApp -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (ast/parse (libSource))
    ((err e) (err (list (ty/makeIrDiag "ERR_TEST_PARSE" e.msg "rlib"))))
    ((ok libForms) (mt (ast/parse (appSource))
                     ((err e) (err (list (ty/makeIrDiag "ERR_TEST_PARSE" e.msg "rapp"))))
                     ((ok appForms) (low/lowerLinked appForms (low/declPositions (appSource))
                                                     (low/LinkScope :path "rapp.asl" :imports (mapSet (mapEmpty) "l" libForms) :prelude (list) :strings (list) :only (none)))))))

fn testImportedRecord -> Bool
  (mt (lowerApp)
    ((err ds) (assert false (str "a module importing a record schema lowers: " (diagText ds))))
    ((ok m)
      (do (assert (hasRecCallDest (fnNamed m "rapp.useMk") "rlib.Point") "a call through an import alias returns the imported module's schema, not the importer's same-named one")
          (assert (isRecNamed (externNamed m "rlib.mk").ret "rlib.Point") (str "an extern returning an imported record resolves its schema: " (ty/ssaTyName (externNamed m "rlib.mk").ret)))
          (assert (mt (listHead (externNamed m "rlib.getX").params) ((some t) (isRecNamed t "rlib.Point")) ((none) false)) "an extern taking an imported record resolves its parameter schema")
          true)))

fn runTests -> Bool
  (do (assert (testRecordModule) "testRecordModule")
      (assert (testRawLet) "testRawLet")
      (assert (testImportedRecord) "testImportedRecord")
      true)
