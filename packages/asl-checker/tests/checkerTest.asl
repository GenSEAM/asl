(module asl-checker/checkerTest :x [checkSource checkFile! testCorpusSmoke runTests RunTests] :i [(types :a ty) (resolve :a r) (check :a c) (unify :a u) (ast :a a)])

fn checkSource src: String deps: (Map String r/ModuleSummary) path: String -> (List ty/Diagnostic)
  (c/checkSource src deps path)

fn ! checkFile! path: String roots: (List String) -> (Result (List ty/Diagnostic) IoError)
  (c/checkFile! path roots)

fn testCorpusSmoke -> Bool
  (let [(dOk (c/checkSource "(module m :x [foo]) (fn foo [] -> Int64 42)" (mapEmpty) "m.asl")) (d-bad (c/checkSource "(module m :x [foo]) (fn foo [] -> Int64 \"fail\")" (mapEmpty) "m.asl"))] (assert (listEmpty? dOk) "Smoke test well-typed produces zero diagnostics") (refute (not (listEmpty? dOk)) "Smoke test well-typed must not produce diagnostics") (refute (listEmpty? d-bad) "Smoke test ill-typed produces diagnostics") (assert (not (listEmpty? d-bad)) "Smoke test ill-typed must produce non-empty diagnostics") true)

fn testBareHostVerbRejected -> Bool
  (let [(ds (c/checkSource "(module bareHostVerb :x [run]) (fn run [] -> Int64 (hostVerb (list \"version\")))" (mapEmpty) "bareHostVerb.asl"))]
    (do (assert (not (listEmpty? ds)) (str "unqualified hostVerb is rejected: " (diagText ds))) true))

fn testUnimportedSysHostVerbRejected -> Bool
  (let [(ds (c/checkSource "(module unimportedSysHostVerb :x [run]) (fn run [] -> Int64 (sys/hostVerb (list \"version\")))" (mapEmpty) "unimportedSysHostVerb.asl"))]
    (do (assert (not (listEmpty? ds)) (str "unimported sys/hostVerb is rejected: " (diagText ds))) true))

fn testImportedSysHostVerbRejected -> Bool
  (let [(ds (c/checkSource "(module importedSysHostVerb :x [run] :i [(sys :a s)]) (fn run [] -> Int64 (s/hostVerb (list \"version\")))" (mapEmpty) "importedSysHostVerb.asl"))]
    (do (assert (stringContains? (diagText ds) "unbound symbol: s/hostVerb") (str "imported sys alias hostVerb is an unbound symbol: " (diagText ds))) true))

fn testSysImportBuiltin -> Bool
  (let [(ds (c/checkSource "(module sysCheck :x [size] :i [(sys :a s)]) (fn size [] -> Int64 (s/stringLength \"asl\"))" (mapEmpty) "sysCheck.asl"))]
    (do (assert (listEmpty? ds) (str "sys import alias resolves builtin signatures without module files: " (diagText ds))) true))

fn testUnification -> Bool
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none))) (strTy (ty/tyCon "String" (list) (none) (none))) (v1 (ty/tyVar 1 "any")) (fn1 (ty/tyFun (list v1) v1)) (fn2 (ty/tyFun (list i64) i64))] (assert (u/typeEqual? i64 i64) "Concrete type equality") (refute (u/typeEqual? i64 strTy) "Distinct primitive inequality") (refute (not (u/typeEqual? i64 i64)) "Identical concrete types must not be unequal") (mt (u/unify v1 i64 (mapEmpty)) ((u/uOk s1) (assert (u/typeEqual? (u/applySubst s1 v1) i64) "Metavariable substituted to concrete type") (refute (u/typeEqual? (u/applySubst s1 v1) strTy) "Substituted variable must not equal distinct type")) ((u/uErr _ _) (assert false "Metavariable unification should succeed"))) (mt (u/unify fn1 fn2 (mapEmpty)) ((u/uOk s2) (assert (u/typeEqual? (u/applySubst s2 v1) i64) "HOF parameter type inferred") (refute (u/typeEqual? (u/applySubst s2 v1) strTy) "Inferred HOF parameter type must not equal String")) ((u/uErr _ _) (assert false "HOF unification should succeed"))) (mt (u/unify i64 strTy (mapEmpty)) ((u/uOk _) (assert false "Unifying Int64 and String must fail")) ((u/uErr msg _) (assert (stringContains? msg "expected") "Type error message contains expected") (refute (stringEmpty? msg) "Type error message must not be empty"))) true)

fn testOccurs -> Bool
  (let [(v1 (ty/tyVar 1 "any")) (i64 (ty/tyCon "Int64" (list) (none) (none))) (listV1 (ty/tyCon "List" (list v1) (none) (none))) (fnV1 (ty/tyFun (list v1) i64))] (assert (u/occursIn? 1 listV1 (mapEmpty)) "Metavariable occurs in constructed list") (refute (not (u/occursIn? 1 listV1 (mapEmpty))) "Metavariable must occur in recursive list type") (refute (u/occursIn? 1 i64 (mapEmpty)) "Metavariable does not occur in primitive Int64") (assert (not (u/occursIn? 1 i64 (mapEmpty))) "Metavariable must not occur in non-recursive primitive") (mt (u/unify v1 listV1 (mapEmpty)) ((u/uOk _) (assert false "Occurs check must reject v1 = List[v1]")) ((u/uErr msg _) (assert (stringContains? msg "occurs check") "Error message reports occurs check failure") (refute (stringEmpty? msg) "Occurs check error message must not be empty"))) (mt (u/unify v1 fnV1 (mapEmpty)) ((u/uOk _) (assert false "Occurs check must reject v1 = (fn [v1] -> Int64)")) ((u/uErr msg _) (assert (stringContains? msg "occurs check") "Function occurs check failure reported") (refute (stringEmpty? msg) "Function occurs check error message must not be empty"))) true)

fn testCheckSource -> Bool
  (let [(wellTyped "(module m :x [id foo]) (fn id [(x Int64)] -> Int64 x) (fn foo [] -> Int64 (id 42))") (dOk (c/checkSource wellTyped (mapEmpty) "m.asl")) (illTyped "(module m :x [helper g]) (fn helper [] -> String \"mismatch\") (fn g [] -> Int64 (helper))") (dErr (c/checkSource illTyped (mapEmpty) "m.asl")) (litErr "(module m :x [foo]) (fn foo [] -> Int64 \"bad\")") (dLit (c/checkSource litErr (mapEmpty) "m.asl")) (docErr (c/checkSource "(module m :x [foo]) (fn foo [] -> Int64 42)" (mapEmpty) "m.asl"))] (assert (listEmpty? dOk) "Well-typed source produces zero diagnostics") (refute (not (listEmpty? dOk)) "Well-typed source must not produce diagnostics") (refute (listEmpty? dErr) "Call return mismatch produces diagnostics") (assert (> (listLength dErr) 0) "Diagnostic count >= 1 for mismatch") (refute (listEmpty? dLit) "Literal type mismatch produces diagnostics") (assert (> (listLength dLit) 0) "Literal type mismatch diagnostic count >= 1") (assert (listEmpty? docErr) "an exported function without a source doc produces no diagnostics: docs live in doc.asn (D158)") (refute (> (listLength docErr) 0) "no rule-8 diagnostic for an exported function without a source doc") true)

fn assertModule body: String -> String
  (str "(module m :x [foo]) (fn foo [(n Int64)] -> Bool (do " body " true))")

fn diagText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn testAssertForms -> Bool
  (let [(ok (c/checkSource (assertModule "(assert (> n 0)) (refute (< n 0) \"negative\") (assert true n)") (mapEmpty) "m.asl"))
        (notBool (c/checkSource (assertModule "(assert n \"m\")") (mapEmpty) "m.asl"))
        (tooMany (c/checkSource (assertModule "(refute false \"a\" \"b\")") (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? ok) (str "assert and refute are special forms taking a Bool and an optional message of any type: " (diagText ok)))
        (assert (stringContains? (diagText notBool) "Bool") (str "an assert condition that is not Bool is a type error: " (diagText notBool)))
        (assert (stringContains? (diagText tooMany) "refute takes a condition and an optional message") (str "refute with three operands is an arity error: " (diagText tooMany)))
        true))

fn testTypedLetBindsValue -> Bool
  (let [(mismatch (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [(x Int64 \"hello\")] (+ x 1)))" (mapEmpty) "m.asl"))
        (ok (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [(x Int64 5)] (+ x 1)))" (mapEmpty) "m.asl"))]
    (do (assert (stringContains? (diagText mismatch) "argument to +: expected a number, found String")
                (str "a typed let (x Int64 v) types x from v, not from the annotation Int64, so a mismatched v surfaces at its use: " (diagText mismatch)))
        (assert (not (stringContains? (diagText ok) "argument to +"))
                (str "a typed let whose v agrees with its use produces no + mismatch: " (diagText ok)))
        true))

fn testRed3BuiltinsAndQualifiedCtors -> Bool
  (let [(builtinOk (c/checkSource "(module m :x [f]) (fn f [(s String)] -> (List Int64) (let [(b (stringToBytes s)) (x (bytesGet b 0)) (l (list x 2 3))] (listDrop l 1)))" (mapEmpty) "m.asl"))
        (badBytesGet (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (bytesGet \"not-bytes\" 0))" (mapEmpty) "m.asl"))
        (badStrToBytes (c/checkSource "(module m :x [f]) (fn f [] -> Bytes (stringToBytes 42))" (mapEmpty) "m.asl"))
        (badListDrop (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (listDrop \"not-a-list\" 1))" (mapEmpty) "m.asl"))
        (bytesSetOk (c/checkSource "(module m :x [f]) (fn f [] -> Unit (bytesSet (bytesAlloc 4) 0 65))" (mapEmpty) "m.asl"))
        (badBytesSet (c/checkSource "(module m :x [f]) (fn f [] -> Unit (bytesSet \"not-bytes\" 0 65))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? builtinOk) (str "bytesGet, stringToBytes, listDrop well-typed: " (diagText builtinOk)))
        (assert (> (listLength badBytesGet) 0) "bytesGet type mismatch detected")
        (assert (> (listLength badStrToBytes) 0) "stringToBytes type mismatch detected")
        (assert (> (listLength badListDrop) 0) "listDrop type mismatch detected")
        (assert (listEmpty? bytesSetOk) (str "bytesSet (Bytes, Int64, Int64) -> Unit well-typed: " (diagText bytesSetOk)))
        (assert (> (listLength badBytesSet) 0) "bytesSet type mismatch on non-Bytes first arg detected")
        (let [(depSrc "(module depMod :x [Point Color red green] :i []) (schema Point (:f x Int64 \"x\") (:f y Int64 \"y\")) (enum Color (:c red [] \"red\") (:c green [(code Int64)] \"green\")) (schema Secret (:f val Int64 \"secret\"))")
              (depForms (mt (a/parse depSrc) ((ok f) f) ((err _) (list))))
              (depSummary (r/collectSummary depForms "/path/to/depMod.asl"))
              (deps (mapSet (mapEmpty) "/path/to/depMod.asl" depSummary))
              (consumerSrc "(module consumer :x [makeGreen matchColor makePoint] :i [(depMod :a d)]) (fn makeGreen [] -> d/Color (d/green 42)) (fn matchColor [(c d/Color)] -> Int64 (mt c ((d/red) 0) ((d/green code) code))) (fn makePoint [(pt d/Point)] -> Int64 (let [(p2 (d/Point :x 10 :y 20))] (+ pt.x p2.y)))")
              (consumerOk (c/checkSource consumerSrc deps "consumer.asl"))
              (badArgSrc "(module consumer :x [makeGreen] :i [(depMod :a d)]) (fn makeGreen [] -> d/Color (d/green \"not-int\"))")
              (consumerBadArg (c/checkSource badArgSrc deps "consumer.asl"))
              (badCtorSrc "(module consumer :x [matchColor] :i [(depMod :a d)]) (fn matchColor [(c d/Color)] -> Int64 (mt c ((d/blue) 0) ((d/red) 1)))")
              (consumerBadCtor (c/checkSource badCtorSrc deps "consumer.asl"))
              (badSchemaFieldSrc "(module consumer :x [makePoint] :i [(depMod :a d)]) (fn makePoint [] -> d/Point (d/Point :x \"not-int\" :y 20))")
              (consumerBadSchemaField (c/checkSource badSchemaFieldSrc deps "consumer.asl"))
              (badSchemaMissingSrc "(module consumer :x [makePoint] :i [(depMod :a d)]) (fn makePoint [] -> d/Point (d/Point :x 10))")
              (consumerBadSchemaMissing (c/checkSource badSchemaMissingSrc deps "consumer.asl"))
              (badSchemaUnexportedSrc "(module consumer :x [leakSecret] :i [(depMod :a d)]) (fn leakSecret [] -> d/Secret (d/Secret :val 42))")
              (consumerBadSchemaUnexported (c/checkSource badSchemaUnexportedSrc deps "consumer.asl"))
              (consumerSummary (r/collectSummary (mt (a/parse badSchemaUnexportedSrc) ((ok f) f) ((err _) (list))) "consumer.asl"))
              (badEnumAritySrc "(module consumer :x [makeGreen] :i [(depMod :a d)]) (fn makeGreen [] -> d/Color (d/green 1 2))")
              (consumerBadEnumArity (c/checkSource badEnumAritySrc deps "consumer.asl"))
              (depModA "(module pkgA/util :x [foo] :i []) (fn foo [] -> Int64 1)")
              (summaryA (r/collectSummary (mt (a/parse depModA) ((ok f) f) ((err _) (list))) "/pkgA/util.asl"))
              (depModB "(module pkgB/util :x [bar] :i []) (fn bar [] -> Int64 2)")
              (summaryB (r/collectSummary (mt (a/parse depModB) ((ok f) f) ((err _) (list))) "/pkgB/util.asl"))
              (collidingDeps (mapSet (mapSet (mapEmpty) "/pkgA/util.asl" summaryA) "/pkgB/util.asl" summaryB))
              (ambigRes (r/resolveDepTarget "util" collidingDeps))
              (consumerCollisionSrc "(module consumer :x [callUtil] :i [(util :a u)]) (fn callUtil [] -> Int64 (u/foo))")
              (consumerCollision (c/checkSource consumerCollisionSrc collidingDeps "consumer.asl"))
              (nameOnlyMod "(module vendor/tool :x [go] :i []) (fn go [] -> Int64 1)")
              (nameOnlySummary (r/collectSummary (mt (a/parse nameOnlyMod) ((ok f) f) ((err _) (list))) "/custom/store.asl"))
              (nameOnlyDeps (mapSet (mapEmpty) "/custom/store.asl" nameOnlySummary))
              (nameOnlyRes (r/resolveDepTarget "tool" nameOnlyDeps))
              (pathOnlyMod "(module Standalone :x [go] :i []) (fn go [] -> Int64 2)")
              (pathOnlySummary (r/collectSummary (mt (a/parse pathOnlyMod) ((ok f) f) ((err _) (list))) "/some/path/helper.asl"))
              (pathOnlyDeps (mapSet (mapEmpty) "/some/path/helper.asl" pathOnlySummary))
              (pathOnlyRes (r/resolveDepTarget "helper" pathOnlyDeps))
              (dupDeps (mapSet (mapSet (mapEmpty) "/some/path/helper.asl" pathOnlySummary) "aliasKey" pathOnlySummary))
              (dupRes (r/resolveDepTarget "helper" dupDeps))
              (emptyRes (r/resolveDepTarget "" collidingDeps))]
          (do (assert (listEmpty? consumerOk) (str "qualified constructor in expr and match pattern well-typed: " (diagText consumerOk)))
              (assert (> (listLength consumerBadArg) 0) "qualified constructor argument type mismatch detected")
              (assert (> (listLength consumerBadCtor) 0) "unknown qualified constructor in match pattern detected")
              (assert (> (listLength consumerBadSchemaField) 0) "qualified schema constructor field type mismatch detected")
              (assert (> (listLength consumerBadSchemaMissing) 0) "qualified schema constructor missing field detected")
              (assert (> (listLength consumerBadSchemaUnexported) 0) "unexported qualified schema constructor rejected")
              (assert (stringContains? (diagText consumerBadSchemaUnexported) "ERR_NOT_EXPORTED") "unexported schema error names ERR_NOT_EXPORTED")
              (assert (none? (c/schemaOfCtor "d/Secret" consumerSummary deps)) "schemaOfCtor returns none for unexported schema")
              (assert (> (listLength consumerBadEnumArity) 0) "qualified enum constructor arity mismatch detected")
              (assert (err? ambigRes) "ambiguous dependency match returns err")
              (assert (stringContains? (mt ambigRes ((err msg) msg) ((ok _) "")) "ERR_AMBIGUOUS_MODULE") "ambiguous dependency error names ERR_AMBIGUOUS_MODULE")
              (assert (> (listLength consumerCollision) 0) "ambiguous module import produces diagnostic")
              (assert (stringContains? (diagText consumerCollision) "ERR_AMBIGUOUS_MODULE") "collision diagnostic names ERR_AMBIGUOUS_MODULE")
              (assert (ok? nameOnlyRes) "module name suffix matches dependency target")
              (assert (ok? pathOnlyRes) "file path suffix matches dependency target")
              (assert (ok? dupRes) "duplicate summaries for same module are deduplicated without ambiguity")
              (assert (err? emptyRes) "empty module path returns err")
              true))))

fn testRed4Class1EnumSchemaAndAmbiguousTarget -> Bool
  (let [(mod1 (r/ModuleSummary :name "pkg1/util" :path "/a/pkg1/util.asl" :hasHeader true :hasDoc true :exports (list) :exportedTypes (list) :imports (mapEmpty) :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty)))
        (mod2 (r/ModuleSummary :name "pkg2/util" :path "/b/pkg2/util.asl" :hasHeader true :hasDoc true :exports (list) :exportedTypes (list) :imports (mapEmpty) :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty)))
        (mod3 (r/ModuleSummary :name "pkg3/unique" :path "/c/pkg3/unique.asl" :hasHeader true :hasDoc true :exports (list) :exportedTypes (list) :imports (mapEmpty) :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty)))
        (depsAmb (mapSet (mapSet (mapSet (mapEmpty) "/a/pkg1/util.asl" mod1) "/b/pkg2/util.asl" mod2) "/c/pkg3/unique.asl" mod3))
        (ambRes (r/resolveDepTarget "util" depsAmb))
        (uniqRes (r/resolveDepTarget "unique" depsAmb))]
    (do (assert (err? ambRes) "ambiguous suffix match returns err")
        (assert (ok? uniqRes) "unique suffix match succeeds")
        (assert (= (resultOr uniqRes mod1).name "pkg3/unique") "unique match resolved correct module")
        (let [(depSrc "(module depMod :x [Color Point] :i []) (enum Color (:c red [] \"red\") (:c green [(code Int64)] \"green\")) (schema Point (:f x Int64) (:f y Int64))")
              (depForms (mt (a/parse depSrc) ((ok f) f) ((err _) (list))))
              (depSummary (r/collectSummary depForms "/path/to/depMod.asl"))
              (deps (mapSet (mapEmpty) "/path/to/depMod.asl" depSummary))
              (consumerSrc "(module consumer :x [matchColor makePoint getX] :i [(depMod :a d)]) (fn matchColor [(c d/Color)] -> Int64 (mt c ((red) 0) ((green code) code))) (fn makePoint [] -> d/Point (Point :x 10 :y 20)) (fn getX [(p d/Point)] -> Int64 p.x)")
              (consumerDiags (c/checkSource consumerSrc deps "consumer.asl"))
              (badPointSrc "(module consumer :x [makePoint] :i [(depMod :a d)]) (fn makePoint [] -> d/Point (Point :x \"not-int\" :y 20))")
              (badPointDiags (c/checkSource badPointSrc deps "consumer.asl"))]
          (do (assert (listEmpty? consumerDiags) (str "unqualified imported enum cases and schema ctor should produce zero diags: " (diagText consumerDiags)))
              (assert (> (listLength badPointDiags) 0) "unqualified schema constructor argument type mismatch detected")
              true))))

fn testRed4Class2ScopeTracking -> Bool
  (let [(src "(module m :x [foo bar]) (fn foo [(x Int64)] -> Int64 (mt x ((unknownCtor a b) (+ a b)) ((otherCtor [v1 v2]) (+ v1 v2)) ([w1 w2] (+ w1 w2)) (_ 0))) (fn bar [(opt (Option Int64))] -> Int64 (mt opt ((some y z) (+ y z)) (_ 0)))")
        (diags (c/checkSource src (mapEmpty) "m.asl"))
        (dStr (diagText diags))]
    (do (assert (stringContains? dStr "unknown constructor in match pattern: unknownCtor") "reports unknown constructor")
        (assert (not (stringContains? dStr "rule-1")) (str "match pattern bindings must not produce rule-1 unbound symbol: " dStr))
        (assert (not (stringContains? dStr "is not defined")) (str "match pattern bindings must not produce rule-2 undefined symbol: " dStr))
        true))

fn testRed4Class3PolymorphicHelpers -> Bool
  (let [(src "(module m :x [myTail caller]) (fn myTail [(l (List T))] -> (List T) l) (fn caller [(xs (List Int64))] -> (List Int64) (myTail xs))")
        (diags (c/checkSource src (mapEmpty) "m.asl"))
        (dStr (diagText diags))
        (badCallerSrc "(module m :x [myTail badCaller]) (fn myTail [(l (List T))] -> (List T) l) (fn badCaller [(xs (List Int64))] -> (List String) (myTail xs))")
        (badDiags (c/checkSource badCallerSrc (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? diags) (str "polymorphic helper and caller should produce zero diags: " dStr))
        (assert (> (listLength badDiags) 0) "polymorphic helper return type mismatch detected")
        true))

fn testRed7Builtins -> Bool
  (let [(ok (c/checkSource "(module m :x [f]) (fn f [(xs (List Int64))] -> Bool (and true (or false true) (listAny? (fn [(x Int64)] -> Bool (> x 0)) (listTake xs 2))))" (mapEmpty) "m.asl")) (bad (c/checkSource "(module m :x [f]) (fn f [(xs (List Int64))] -> Bool (listAny? (fn [(x String)] -> Bool (> (stringLength x) 0)) xs))" (mapEmpty) "m.asl"))]
    (let [(badAnd (c/checkSource "(module m :x [f]) (fn f [] -> Bool (and true 1))" (mapEmpty) "m.asl")) (badOr (c/checkSource "(module m :x [f]) (fn f [] -> Bool (or false true \"x\"))" (mapEmpty) "m.asl"))] (do (assert (listEmpty? ok) (str "host prelude and variadic booleans typecheck: " (diagText ok))) (assert (> (listLength bad) 0) "incorrect listAny predicate remains diagnostic") (assert (stringContains? (diagText badAnd) "Bool") (str "and checks every variadic argument: " (diagText badAnd))) (assert (stringContains? (diagText badOr) "Bool") (str "or checks every variadic argument: " (diagText badOr))) (assert (listEmpty? (c/checkSource "(module m :x [f]) (fn f [(n Int64)] -> String (str n \" of \" 2.5 \" \" true))" (mapEmpty) "m.asl")) "str interpolates arguments of any type, as bStr does at runtime") true)))

fn testRed7FileStat -> Bool
  (let [(good (c/checkSource "(module m :x [f]) (fn ! f [(p String)] -> Int64 (mt (fileStat p) ((ok st) st.size) ((err _) 0)))" (mapEmpty) "m.asl")) (bad (c/checkSource "(module m :x [f]) (fn ! f [(p String)] -> Bool (mt (fileStat p) ((ok st) st.size) ((err _) false)))" (mapEmpty) "m.asl"))] (do (assert (listEmpty? good) (str "FileStat size field resolves: " (diagText good))) (assert (> (listLength bad) 0) "FileStat size Int64 shape rejects Bool return") true))

fn testHostRecordProcessOutput -> Bool
  (let [(good (c/checkSource "(module m :x [f g]) (fn ! f [(c String)] -> Int64 (processRun c).exitCode) (fn g [(r ProcessOutput)] -> String (str r.stdout r.stderr))" (mapEmpty) "m.asl")) (bad (c/checkSource "(module m :x [f]) (fn ! f [(c String)] -> Int64 (processRun c).stdout)" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? good) (str "ProcessOutput fields and annotation resolve: " (diagText good))) (assert (> (listLength bad) 0) "ProcessOutput stdout is String, so an Int64 return rejects it") true))

fn testFileExistsIsBool -> Bool
  (let [(good (c/checkSource "(module m :x [f]) (fn ! f [(p String)] -> Str (if (fileExists? p) \"file\" \"text\"))" (mapEmpty) "m.asl")) (bad (c/checkSource "(module m :x [f]) (fn ! f [(p String)] -> Int64 (fileExists? p))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? good) (str "fileExists? is a Bool condition: " (diagText good))) (assert (> (listLength bad) 0) "fileExists? Bool is not an Int64") true))

fn testTopExprTypeError -> Bool
  (let [(wellTyped "(module m :x []) (+ 1 2)") (dOk (c/checkSource wellTyped (mapEmpty) "m.asl")) (illTyped "(module m :x []) (+ 1 \"bad\")") (dBad (c/checkSource illTyped (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? dOk) (str "a well-typed top-level expression produces zero diagnostics: " (diagText dOk)))
        (refute (not (listEmpty? dOk)) "a well-typed top-level expression must not produce diagnostics")
        (refute (listEmpty? dBad) (str "a type error inside a bare top-level expression must be caught: " (diagText dBad)))
        (assert (> (listLength dBad) 0) "top-level expression type mismatch diagnostic count >= 1")
        true))

fn testSwappedExpectedFound -> Bool
  (let [(litSrc "(module m :x [f]) (fn f [] -> Int64 (stringLength 1))")
        (nonLitSrc "(module m :x [f]) (fn f [] -> Int64 (stringLength (+ 1 2)))")
        (dLit (c/checkSource litSrc (mapEmpty) "m.asl"))
        (dNonLit (c/checkSource nonLitSrc (mapEmpty) "m.asl"))]
    (do (refute (listEmpty? dLit) (str "(stringLength 1) must be a diagnostic: " (diagText dLit)))
        (assert (stringContains? (diagText dLit) "expected String, found an integer") (str "literal argument: expected/found must name the parameter as expected and the literal as found, got " (diagText dLit)))
        (refute (stringContains? (diagText dLit) "expected an integer, found String") (str "literal argument: must not swap expected/found, got " (diagText dLit)))
        (refute (listEmpty? dNonLit) (str "(stringLength (+ 1 2)) must be a diagnostic: " (diagText dNonLit)))
        (assert (stringContains? (diagText dNonLit) "expected String, found an integer") (str "non-literal argument: expected/found must name the parameter as expected and the expression's kind as found, got " (diagText dNonLit)))
        (refute (stringContains? (diagText dNonLit) "expected an integer, found String") (str "non-literal argument: must not swap expected/found, got " (diagText dNonLit)))
        true))

fn arrayProgram body: String -> String
  (str "(module arrays :x [run]) (fn run [] -> Int64 (let [(fs (f64ArrayGenerate 4 (fn [(i Int64)] -> Float64 (int64ToFloat64 i)))) (is (i64ArrayGenerate 4 (fn [(i Int64)] -> Int64 i))) (bs (i8ArrayGenerate 4 (fn [(i Int64)] -> Int64 i)))] " body "))")

fn testArrayBuiltins -> Bool
  (let [(good (c/checkSource (arrayProgram "(+ (f64ArrayFold (fn [(n Int64) (x Float64)] -> Int64 (if (> x 0.0) (+ n 1) n)) 0 fs) (+ (i64ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 (i64ArraySlice is 1 3)) (+ (i8ArraySum (i8ArrayConcat (list bs bs))) (+ (f64ArrayCountEq (f64ArrayScan (fn [(a Float64) (x Float64)] -> Float64 (+ a x)) 0.0 fs) 1.0) (i64ArrayLen (i64ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 is))))))") (mapEmpty) "arrays.asl"))
        (floatAcc (c/checkSource (arrayProgram "(f64ArrayCountEq (axpy (dot fs fs) fs fs) (f64ArrayFold (fn [(s Float64) (x Float64)] -> Float64 (+ s x)) 0.0 fs))") (mapEmpty) "arrays.asl"))
        (wrongArray (c/checkSource (arrayProgram "(f64ArrayFold (fn [(n Int64) (x Float64)] -> Int64 n) 0 is)") (mapEmpty) "arrays.asl"))
        (wrongAccumulator (c/checkSource (arrayProgram "(i64ArrayLen (i64ArrayGenerate (i64ArrayFold (fn [(s Float64) (x Int64)] -> Float64 s) 0.0 is) (fn [(i Int64)] -> Int64 i)))") (mapEmpty) "arrays.asl"))]
    (do (assert (listEmpty? good) (str "an Int64 accumulator folds an F64Array and the array family checks: " (diagText good)))
        (assert (listEmpty? floatAcc) (str "a Float64 accumulator folds an F64Array and the dot and axpy kernels check: " (diagText floatAcc)))
        (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message "f64ArrayFold")) wrongArray) (str "an I64Array passed to f64ArrayFold is rejected: " (diagText wrongArray)))
        (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message "i64ArrayFold")) wrongAccumulator) (str "a Float64 accumulator for i64ArrayFold is rejected, as the host does: " (diagText wrongAccumulator)))
        true))

fn clampProgram args: String -> String
  (str "(module m :x [f]) (fn f [] -> Float64 (clamp " args "))")

fn testClampBuiltin -> Bool
  (let [(floatOk (c/checkSource (clampProgram "0.0 10.0 5.0") (mapEmpty) "m.asl"))
        (intBad (c/checkSource (clampProgram "0 10 5") (mapEmpty) "m.asl"))
        (arityBad (c/checkSource (clampProgram "0.0 10.0") (mapEmpty) "m.asl"))
        (typeBad (c/checkSource (clampProgram "\"a\" \"b\" \"c\"") (mapEmpty) "m.asl"))
        (intBound (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [(r (clamp 0 10 5))] 0))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? floatOk) (str "clamp on three Float64 arguments is well-typed: " (diagText floatOk)))
        (refute (listEmpty? intBad) (str "clamp on three Int64 arguments must be a diagnostic, since the host's bClamp wants Float64: " (diagText intBad)))
        (assert (stringContains? (diagText intBad) "Float64") (str "clamp on Int64 must report the expected Float64: " (diagText intBad)))
        (refute (listEmpty? arityBad) (str "clamp given two arguments must be a diagnostic: " (diagText arityBad)))
        (assert (stringContains? (diagText arityBad) "arity") (str "clamp given two arguments must report an arity diagnostic: " (diagText arityBad)))
        (refute (listEmpty? typeBad) (str "clamp on three strings must be a diagnostic: " (diagText typeBad)))
        (refute (listEmpty? intBound) (str "clamp on Int64 bound in a let of an Int64 function, free of any Float64 return annotation, must still be a diagnostic from clamp's own signature: " (diagText intBound)))
        (assert (stringContains? (diagText intBound) "Float64") (str "clamp on Int64 in an Int64 function must report clamp's expected Float64: " (diagText intBound)))
        true))

fn builtinValueProgram name: String -> String
  (str "(module m :x [f]) (fn f [] -> Int64 (let [(g " name ")] 0))")

fn hasBuiltinRefDiag ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "builtin-reference")) ds)

fn assertBuiltinIsTypeableValue name: String -> Bool
  (let [(ds (c/checkSource (builtinValueProgram name) (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? ds) (str name " bound as a bare value must typecheck cleanly: " (diagText ds)))
        (refute (hasBuiltinRefDiag ds) (str name " as a bare value must not be rejected as a non-value builtin-reference"))
        true))

fn testBuiltinsAsValues -> Bool
  (do (assert (assertBuiltinIsTypeableValue "abs") "abs as a value")
      (assert (assertBuiltinIsTypeableValue "min") "min as a value")
      (assert (assertBuiltinIsTypeableValue "max") "max as a value")
      (assert (assertBuiltinIsTypeableValue "int64ToFloat64") "int64ToFloat64 as a value")
      (assert (assertBuiltinIsTypeableValue "float64ToInt64") "float64ToInt64 as a value")
      (assert (assertBuiltinIsTypeableValue "floor") "floor as a value")
      (assert (assertBuiltinIsTypeableValue "ceil") "ceil as a value")
      (assert (assertBuiltinIsTypeableValue "round") "round as a value")
      (assert (assertBuiltinIsTypeableValue "sqrt") "sqrt as a value")
      (assert (assertBuiltinIsTypeableValue "sin") "sin as a value")
      (assert (assertBuiltinIsTypeableValue "cos") "cos as a value")
      (assert (assertBuiltinIsTypeableValue "exp") "exp as a value")
      (assert (assertBuiltinIsTypeableValue "log") "log as a value")
      (assert (assertBuiltinIsTypeableValue "pow") "pow as a value")
      (assert (assertBuiltinIsTypeableValue "atan2") "atan2 as a value")
      (assert (assertBuiltinIsTypeableValue "clamp") "clamp as a value")
      (assert (assertBuiltinIsTypeableValue "nowNs") "nowNs as a value")
      (assert (assertBuiltinIsTypeableValue "monotonicNs") "monotonicNs as a value")
      (let [(dsPure (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [(g println) (u (g \"x\"))] 0))" (mapEmpty) "m.asl"))
            (dsBang (c/checkSource "(module m :x [f]) (fn ! f [] -> Int64 (let [(g println) (u (g \"x\"))] 0))" (mapEmpty) "m.asl"))
            (dsSleep (c/checkSource "(module m :x [f]) (fn ! f [] -> Int64 (let [(g sleepMs) (u (g 5))] 0))" (mapEmpty) "m.asl"))]
        (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-12")) dsPure) (str "an effectful builtin bound as a bare value in a function not marked ! is the same rule-12 effect violation as calling it: " (diagText dsPure)))
            (refute (hasBuiltinRefDiag dsPure) (str "println as a bare value is an effect violation, not a builtin-reference: " (diagText dsPure)))
            (assert (listEmpty? dsBang) (str "println bound as a bare value inside a function marked ! is clean: " (diagText dsBang)))
            (assert (listEmpty? dsSleep) (str "sleepMs bound as a bare value inside a function marked ! is clean: " (diagText dsSleep)))))
      (let [(dsMap (c/checkSource "(module m :x [f]) (fn f [] -> (List Float64) (map sqrt (list 1.0 4.0 9.0)))" (mapEmpty) "m.asl"))]
        (assert (listEmpty? dsMap) (str "(map sqrt xs) is well-typed end to end: " (diagText dsMap))))
      (let [(dsVariadic (c/checkSource "(module m :x [f]) (fn f [(xs (List Bool))] -> (List Bool) (map and xs))" (mapEmpty) "m.asl"))]
        (assert (hasBuiltinRefDiag dsVariadic) (str "a variadic builtin like and has no single function type and stays rejected as a value: " (diagText dsVariadic))))
      true)

fn hasDiagCode ds: (List ty/Diagnostic) code: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code code)) ds)

fn kwCallProgram body: String -> String
  (str "(module m :x [f]) (fn f [] -> Int64 " body ")")

fn testKeywordCallRejected -> Bool
  (let [(valuePos (c/checkSource (kwCallProgram "(:k 1)") (mapEmpty) "m.asl"))
        (statementPos (c/checkSource (kwCallProgram "(do (:k 1) 2)") (mapEmpty) "m.asl"))
        (nestedLet (c/checkSource (kwCallProgram "(let [(x (:k 1))] 0)") (mapEmpty) "m.asl"))
        (nestedArg (c/checkSource (kwCallProgram "(+ 1 (:k 2))") (mapEmpty) "m.asl"))
        (nestedCond (c/checkSource (kwCallProgram "(cond ((:k 1) 0) (else 1))") (mapEmpty) "m.asl"))
        (depSrc "(module depMod :x [Point] :i []) (schema Point (:f x Int64 \"x\") (:f y Int64 \"y\"))")
        (depForms (mt (a/parse depSrc) ((ok f) f) ((err _) (list))))
        (depSummary (r/collectSummary depForms "/path/to/depMod.asl"))
        (deps (mapSet (mapEmpty) "/path/to/depMod.asl" depSummary))
        (realCtor (c/checkSource "(module consumer :x [f] :i [(depMod :a d)]) (fn f [] -> d/Point (d/Point :x 10 :y 20))" deps "consumer.asl"))
        (bareArg (c/checkSource (kwCallProgram "(let [(m (mapSet (mapEmpty) :a 1))] 0)") (mapEmpty) "m.asl"))]
    (do (assert (hasDiagCode valuePos "kw-call") (str "keyword call head in value (tail) position is rejected: " (diagText valuePos)))
        (assert (hasDiagCode statementPos "kw-call") (str "keyword call head in discarded statement position is rejected: " (diagText statementPos)))
        (assert (hasDiagCode nestedLet "kw-call") (str "keyword call head nested inside a let binding value is rejected: " (diagText nestedLet)))
        (assert (hasDiagCode nestedArg "kw-call") (str "keyword call head nested inside a builtin call argument is rejected: " (diagText nestedArg)))
        (assert (hasDiagCode nestedCond "kw-call") (str "keyword call head nested inside a cond test is rejected: " (diagText nestedCond)))
        (assert (stringContains? (diagText valuePos) ":k is a keyword literal, not callable") (str "diagnostic names the rule clearly: " (diagText valuePos)))
        (assert (stringContains? (diagText valuePos) "{k ...}") (str "diagnostic suggests the ASN record form: " (diagText valuePos)))
        (assert (listEmpty? realCtor) (str "a real schema constructor call, headed by the schema name, is untouched: " (diagText realCtor)))
        (refute (hasDiagCode bareArg "kw-call") (str "a bare keyword passed as an ordinary argument, not a call head, must not be flagged kw-call: " (diagText bareArg)))
        true))

fn runTests -> Bool
  (do (assert (testKeywordCallRejected) "keyword literal in call-head position is rejected")
      (assert (testBareHostVerbRejected) "bare hostVerb is rejected") (assert (testUnimportedSysHostVerbRejected) "unimported sys/hostVerb is rejected") (assert (testImportedSysHostVerbRejected) "imported sys alias hostVerb is rejected") (assert (testSysImportBuiltin) "sys import aliases expose checker builtin signatures") (assert (testRed7Builtins) "RED7 builtin and variadic regression") (assert (testHostRecordProcessOutput) "host record ProcessOutput is typed") (assert (testFileExistsIsBool) "fileExists? is typed Bool") (assert (testRed7FileStat) "RED7 FileStat shape regression") (assert (testRed4Class3PolymorphicHelpers) "RED4 Class 3 generic T in polymorphic helpers check") (assert (testRed4Class2ScopeTracking) "RED4 Class 2 pattern subpattern scope tracking check") (assert (testRed4Class1EnumSchemaAndAmbiguousTarget) "RED4 Class 1 unqualified enum/schema and ambiguous suffix fallback check") (assert (testRed3BuiltinsAndQualifiedCtors) "RED3 builtins and qualified constructors check") (assert (testAssertForms) "assert and refute forms check") (assert (testTypedLetBindsValue) "typed let (x T v) types x from v, not T") (assert (testCorpusSmoke) "Smoke test passes") (refute (not (testCorpusSmoke)) "Smoke test must not fail") (assert (testUnification) "HM unification tests pass") (refute (not (testUnification)) "HM unification must not fail") (assert (testOccurs) "Occurs-check tests pass") (refute (not (testOccurs)) "Occurs-check must not fail") (assert (testCheckSource) "Source checking tests pass") (refute (not (testCheckSource)) "Source checking must not fail") (assert (testTopExprTypeError) "Top-level expression type checking tests pass") (refute (not (testTopExprTypeError)) "Top-level expression type checking must not fail") (assert (testSwappedExpectedFound) "expected/found orientation check") (refute (not (testSwappedExpectedFound)) "expected/found orientation must not fail") (assert (testArrayBuiltins) "array builtin signatures check") (assert (testClampBuiltin) "clamp builtin signature check") (assert (testBuiltinsAsValues) "builtins as first-class values check") true)

fn RunTests -> Bool
  (runTests)
