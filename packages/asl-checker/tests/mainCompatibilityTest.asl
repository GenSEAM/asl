(module asl-checker/mainCompatibilityTest
  :x [runTests]
  :i [(asl-checker/check :a c) (asl-checker/types :a ty) (asl-checker/resolve :a r) (asl-parser/ast :a a)])

fn hasCode ds: (List ty/Diagnostic) wanted: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code wanted)) ds)

fn testExportedDocRule -> Bool
  (let [(ds (c/checkSource "(module m :x [foo]) (fn foo [] -> Int64 42)" (mapEmpty) "m.asl"))]
    (do (refute (hasCode ds "rule-8") "checkSource raises no documentation diagnostic: docs live in doc.asn (D158)") true))

fn testLegacyCheckerCodes -> Bool
  (let [(ds (c/checkSource "(module m :x []) (schema Loc (:f n Int64 \"n\") (:f s String \"s\")) (fn f [] -> Loc (Loc :n 1 :z \"a\"))" (mapEmpty) "m.asl"))]
    (do (assert (hasCode ds "ctor") "checkSource keeps the established constructor diagnostic code") true))

fn testFixedPlusSignature -> Bool
  (let [(sig (ty/builtinSig "+"))]
    (mt sig
      ((none) (do (assert false "plus has a signature") false))
      ((some s) (do (assert (not (pairFirst (pairSecond s))) "plus is fixed-arity in the exported builtin signature")
                    (assert (= (pairSecond (pairSecond s)) "N") "plus retains its numeric result type") true))))

fn testLambdaUnknownTypeRule -> Bool
  (let [(ds (c/checkSource "(module m :x [foo]) (fn foo [] -> Int64 (let [(g (fn [(x (Fn A B))] -> Int64 1))] (g 1)))" (mapEmpty) "m.asl"))]
    (do (assert (hasCode ds "rule-10") "unknown lambda annotation constructors remain rule-10 diagnostics") true))

fn testImportedUnqualifiedSchemaAnnotation -> Bool
  (let [(depSrc "(module depMod :x [Point] :i []) (schema Point (:f x Int64) (:f y Int64))")
        (depForms (mt (a/parse depSrc) ((ok f) f) ((err _) (list))))
        (depSummary (r/collectSummary depForms "/path/to/depMod.asl"))
        (deps (mapSet (mapEmpty) "/path/to/depMod.asl" depSummary))
        (consumerSrc "(module consumer :x [getUnqualifiedX] :i [(depMod :a d)]) (fn getUnqualifiedX [(p Point)] -> Int64 p.x)")
        (ds (c/checkSource consumerSrc deps "consumer.asl"))]
    (do (assert (listEmpty? ds) "unqualified imported schema annotation is resolved") true))

fn runTests -> Bool
  (do (assert (testExportedDocRule) "exported function doc diagnostic")
      (assert (testLegacyCheckerCodes) "legacy checker diagnostic codes")
      (assert (testFixedPlusSignature) "fixed-arity plus signature")
      (assert (testLambdaUnknownTypeRule) "unknown type in lambda annotations")
      (assert (testImportedUnqualifiedSchemaAnnotation) "unqualified imported schema annotation")
      true)
