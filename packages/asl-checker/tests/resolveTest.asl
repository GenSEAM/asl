(module asl-checker/resolveTest
  :d "Unit tests for asl-checker/resolve"
  :x [testResolve runTests]
  :i [(types :a ty) (ast :a a) (resolve :a r)])

(df checkHasCode [(diags (List ty/Diagnostic)) (wantCode String)] -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool
          (or acc (= (.-code d) wantCode)))
        false
        diags))

(df resolveProbe [(src String) (wantCode String)] -> Bool
  (mt (a/parse src)
    ((err _) false)
    ((ok forms)
     (let [(summary (r/collectSummary forms "test.asl"))
           (diags (r/resolveModule summary forms (map-empty)))]
       (checkHasCode diags wantCode)))))

(df testUnboundProbe [] -> Bool
  (do
    (assert (resolveProbe "(df f [] -> Int64 (+ x 1))" "rule-2") "unbound var rule-2")
    (refute (resolveProbe "(df f [(x Int64)] -> Int64 (+ x 1))" "rule-2") "bound var not rule-2")
    true))

(df testMissingDocProbe [] -> Bool
  (do
    (assert (resolveProbe "(module m :export [f]) (df f [] -> Int64 1)" "rule-8") "missing doc rule-8")
    (refute (resolveProbe "(module m :d \"m\" :x [f]) (df f [] -> Int64 :d \"doc\" 1)" "rule-8") "documented export not rule-8")
    true))

(df testReservedProbe [] -> Bool
  (do
    (assert (resolveProbe "(df agentscript-foo [] -> Int64 1)" "rule-7") "reserved prefix rule-7")
    (refute (resolveProbe "(df user-foo [] -> Int64 1)" "rule-7") "unreserved prefix not rule-7")
    true))

(df testUnboundTypevarProbe [] -> Bool
  (do
    (assert (resolveProbe "(df f [] -> UnknownType 1)" "rule-10") "unknown type rule-10")
    (refute (resolveProbe "(df f [] -> Int64 1)" "rule-10") "known type not rule-10")
    true))

(df testEffectProbe [] -> Bool
  (do
    (assert (resolveProbe "(df f [] -> (Result Unit IoError) (println \"hi\"))" "rule-12") "effectful call in pure df rule-12")
    (refute (resolveProbe "(df f [] -> Int64 42)" "rule-12") "pure function not rule-12")
    true))

(df testArityProbe [] -> Bool
  (do
    (assert (resolveProbe "(df f [(x Int64)] -> Int64 (+ x 1)) (df g [] -> Int64 (f 1 2))" "arity") "excess args trigger arity")
    (refute (resolveProbe "(df f [(x Int64)] -> Int64 (+ x 1)) (df g [] -> Int64 (f 1))" "arity") "matching args do not trigger arity")
    true))

(df testCtorProbe [] -> Bool
  (do
    (assert (resolveProbe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (df f [] -> Pt (Pt :x 1))" "ctor") "missing schema field ctor")
    (refute (resolveProbe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (df f [] -> Pt (Pt :x 1 :y 2))" "ctor") "complete schema fields not ctor")
    true))

(df testNotCallableProbe [] -> Bool
  (do
    (assert (resolveProbe "(df f [] -> Int64 (-1 2))" "not-callable") "invalid head not-callable")
    (refute (resolveProbe "(df f [] -> Int64 (+ 1 2))" "not-callable") "valid head is callable")
    true))

(df testBuiltinRefProbe [] -> Bool
  (do
    (assert (resolveProbe "(df shout [(xs (List String))] -> (List String) (map string-upper xs))" "builtin-reference") "naked builtin in HOF builtin-reference")
    (refute (resolveProbe "(df f [] -> Int64 (+ 1 2))" "builtin-reference") "normal call not builtin-reference")
    true))

(df testResolve [] -> Bool
  :d "Unit tests for resolve"
  (do
    (assert (testUnboundProbe) "unbound probe rule-2")
    (assert (testMissingDocProbe) "missing doc probe rule-8")
    (assert (testReservedProbe) "reserved probe rule-7")
    (assert (testUnboundTypevarProbe) "unbound typevar probe rule-10")
    (assert (testEffectProbe) "effect probe rule-12")
    (assert (testArityProbe) "arity probe")
    (assert (testCtorProbe) "ctor probe")
    (assert (testNotCallableProbe) "not-callable probe")
    (assert (testBuiltinRefProbe) "builtin-ref probe")
    (refute (checkHasCode (list) "rule-2") "empty diagnostics has no error")
    true))

(df runTests [] -> Bool
  :d "Runs resolve test suite"
  (do
    (assert (testResolve) "test-resolve must pass")
    (refute (resolveProbe "(df f [] -> Int64 42)" "rule-2") "pure constant has no rule-2")
    true))
