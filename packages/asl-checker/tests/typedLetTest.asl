(module asl-checker/tests/typedLetTest
  :x [typedLetSource diagCodes runTests]
  :i [(asl-checker/check :a chk) (asl-checker/resolve :a r) (asl-checker/types :a ty) (asl-parser/ast :a a)])

fn typedLetSource -> String
  "(module q/typed :x [main])\n\nfn main -> Int64\n  (let [(x Int64 5) (y (List Int64) (list x 2)) (z (+ x 1))] (+ z (listLength y)))\n"

fn diagCodes ds: (List ty/Diagnostic) -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds)

fn testTypedLetResolves -> Bool
  (let [(ds (chk/checkSource (typedLetSource) (mapEmpty) "q/typed.asl"))
        (unbound (filter (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "rule-1") (= d.code "rule-2"))) ds))]
    (do (assert (listEmpty? unbound) (str "a typed let (x T v) binds x to v, not to its annotation T: " (diagCodes unbound)))
        (assert (listEmpty? ds) (str "the typed-let module checks clean: " (diagCodes ds)))
        true))

fn testResolveOnlyTypedLet -> Bool
  (mt (a/parseForChecker (typedLetSource))
    ((err e) (do (assert false (str "parses: " e.msg)) false))
    ((ok forms) (let [(ds (r/resolveModule (r/collectSummary forms "q/typed.asl") forms (mapEmpty)))]
                  (do (assert (listEmpty? ds) (str "name resolution of a typed let reports nothing: " (diagCodes ds)))
                      true))))

fn testUntypedLetStillChecked -> Bool
  (let [(ds (chk/checkSource "(module q/u :x [main])\n\nfn main -> Int64\n  (let [(x nope)] x)\n" (mapEmpty) "q/u.asl"))]
    (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "rule-1") (= d.code "rule-2"))) ds) (str "an unknown symbol in an untyped let value is still reported: " (diagCodes ds)))
        true))

fn runTests -> Bool
  (do (assert (testTypedLetResolves) "testTypedLetResolves")
      (assert (testResolveOnlyTypedLet) "testResolveOnlyTypedLet")
      (assert (testUntypedLetStillChecked) "testUntypedLetStillChecked")
      true)
