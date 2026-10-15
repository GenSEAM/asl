(module asl-checker/resolveTest :x [testResolve runTests RunTests] :i [(types :a ty) (ast :a a) (resolve :a r)])

fn checkHasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn resolveProbe src: String wantCode: String -> Bool
  (mt (a/parse src) ((err _) false) ((ok forms) (let [(summary (r/collectSummary forms "test.asl")) (diags (r/resolveModule summary forms (mapEmpty)))] (checkHasCode diags wantCode))))

fn testUnboundProbe -> Bool
  (do (assert (resolveProbe "(fn foo [] -> Int64 (+ x 1))" "rule-2") "unbound var rule-2") (refute (resolveProbe "(fn foo [(x Int64)] -> Int64 (+ x 1))" "rule-2") "bound var not rule-2") true)

fn testMissingDocProbe -> Bool
  (do (refute (resolveProbe "(module m :export [foo]) (fn foo [] -> Int64 1)" "rule-8") "an export without a source doc is not rule-8: docs live in doc.asn (D158)") (refute (resolveProbe "(module m :x [foo]) (fn foo [] -> Int64 1)" "rule-8") "documented export not rule-8") true)

fn testReservedProbe -> Bool
  (do (assert (resolveProbe "(fn agentslang-foo [] -> Int64 1)" "rule-7") "reserved prefix rule-7") (refute (resolveProbe "(fn user-foo [] -> Int64 1)" "rule-7") "unreserved prefix not rule-7") true)

fn testUnboundTypevarProbe -> Bool
  (do (assert (resolveProbe "(fn foo [] -> UnknownType 1)" "rule-10") "unknown type rule-10") (refute (resolveProbe "(fn foo [] -> Int64 1)" "rule-10") "known type not rule-10") true)

fn testEffectProbe -> Bool
  (do (assert (resolveProbe "(fn foo [] -> (Result Unit IoError) (println \"hi\"))" "rule-12") "effectful call in pure df rule-12") (refute (resolveProbe "(fn foo [] -> Int64 42)" "rule-12") "pure function not rule-12") true)

fn testArityProbe -> Bool
  (do (assert (resolveProbe "(fn foo [(x Int64)] -> Int64 (+ x 1)) (fn bar [] -> Int64 (foo 1 2))" "arity") "excess args trigger arity") (refute (resolveProbe "(fn foo [(x Int64)] -> Int64 (+ x 1)) (fn bar [] -> Int64 (foo 1))" "arity") "matching args do not trigger arity") true)

fn testCtorProbe -> Bool
  (do (assert (resolveProbe "(schema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (fn foo [] -> Pt (Pt :x 1))" "ctor") "missing schema field ctor") (refute (resolveProbe "(schema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (fn foo [] -> Pt (Pt :x 1 :y 2))" "ctor") "complete schema fields not ctor") true)

fn testNotCallableProbe -> Bool
  (do (assert (resolveProbe "(fn foo [] -> Int64 (-1 2))" "not-callable") "invalid head not-callable") (refute (resolveProbe "(fn foo [] -> Int64 (+ 1 2))" "not-callable") "valid head is callable") true)

fn testBuiltinRefProbe -> Bool
  (do (assert (resolveProbe "(fn shout [(xs (List Bool))] -> (List Bool) (map and xs))" "builtin-reference") "naked variadic builtin (and) in HOF builtin-reference") (refute (resolveProbe "(fn shout [(xs (List String))] -> (List String) (map stringUpper xs))" "builtin-reference") "naked fixed-arity builtin (stringUpper) in HOF is typed as a value, not builtin-reference") (refute (resolveProbe "(fn foo [] -> Int64 (+ 1 2))" "builtin-reference") "normal call not builtin-reference") true)

fn testResolve -> Bool
  (do (assert (testUnboundProbe) "unbound probe rule-2") (assert (testMissingDocProbe) "missing doc probe rule-8") (assert (testReservedProbe) "reserved probe rule-7") (assert (testUnboundTypevarProbe) "unbound typevar probe rule-10") (assert (testEffectProbe) "effect probe rule-12") (assert (testArityProbe) "arity probe") (assert (testCtorProbe) "ctor probe") (assert (testNotCallableProbe) "not-callable probe") (assert (testBuiltinRefProbe) "builtin-ref probe") (refute (checkHasCode (list) "rule-2") "empty diagnostics has no error") true)

fn runTests -> Bool
  (do (assert (testResolve) "test-resolve must pass") (refute (resolveProbe "(fn foo [] -> Int64 42)" "rule-2") "pure constant has no rule-2") true)

fn RunTests -> Bool
  (runTests)
