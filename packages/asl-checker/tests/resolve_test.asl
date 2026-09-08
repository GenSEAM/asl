(module asl-checker/resolve-test
  :d "Unit tests for asl-checker/resolve"
  :x [test-resolve run-tests]
  :i [(types :a ty) (ast :a a) (resolve :a r)])

(df check-has-code [(diags (List ty/Diagnostic)) (want-code String)] -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool
          (or acc (= (.-code d) want-code)))
        false
        diags))

(df resolve-probe [(src String) (want-code String)] -> Bool
  (mt (a/parse src)
    ((err _) false)
    ((ok forms)
     (let [(summary (r/collect-summary forms "test.asl"))
           (diags (r/resolve-module summary forms (map-empty)))]
       (check-has-code diags want-code)))))

(df test-unbound-probe [] -> Bool
  (do
    (assert (resolve-probe "(df f [] -> Int64 (+ x 1))" "rule-2") "unbound var rule-2")
    (assert (not (resolve-probe "(df f [(x Int64)] -> Int64 (+ x 1))" "rule-2")) "bound var not rule-2")
    true))

(df test-missing-doc-probe [] -> Bool
  (do
    (assert (resolve-probe "(module m :export [f]) (df f [] -> Int64 1)" "rule-8") "missing doc rule-8")
    (assert (not (resolve-probe "(module m :d \"m\" :x [f]) (df f [] -> Int64 :d \"doc\" 1)" "rule-8")) "documented export not rule-8")
    true))

(df test-reserved-probe [] -> Bool
  (do
    (assert (resolve-probe "(df agentscript-foo [] -> Int64 1)" "rule-7") "reserved prefix rule-7")
    (assert (not (resolve-probe "(df user-foo [] -> Int64 1)" "rule-7")) "unreserved prefix not rule-7")
    true))

(df test-unbound-typevar-probe [] -> Bool
  (do
    (assert (resolve-probe "(df f [] -> UnknownType 1)" "rule-10") "unknown type rule-10")
    (assert (not (resolve-probe "(df f [] -> Int64 1)" "rule-10")) "known type not rule-10")
    true))

(df test-effect-probe [] -> Bool
  (do
    (assert (resolve-probe "(df f [] -> (Result Unit IoError) (println \"hi\"))" "rule-12") "effectful call in pure df rule-12")
    (assert (not (resolve-probe "(df f [] -> Int64 42)" "rule-12")) "pure function not rule-12")
    true))

(df test-arity-probe [] -> Bool
  (do
    (assert (resolve-probe "(df f [(x Int64)] -> Int64 (+ x 1)) (df g [] -> Int64 (f 1 2))" "arity") "excess args trigger arity")
    (assert (not (resolve-probe "(df f [(x Int64)] -> Int64 (+ x 1)) (df g [] -> Int64 (f 1))" "arity")) "matching args do not trigger arity")
    true))

(df test-ctor-probe [] -> Bool
  (do
    (assert (resolve-probe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (df f [] -> Pt (Pt :x 1))" "ctor") "missing schema field ctor")
    (assert (not (resolve-probe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (df f [] -> Pt (Pt :x 1 :y 2))" "ctor")) "complete schema fields not ctor")
    true))

(df test-not-callable-probe [] -> Bool
  (do
    (assert (resolve-probe "(df f [] -> Int64 (-1 2))" "not-callable") "invalid head not-callable")
    (assert (not (resolve-probe "(df f [] -> Int64 (+ 1 2))" "not-callable")) "valid head is callable")
    true))

(df test-builtin-ref-probe [] -> Bool
  (do
    (assert (resolve-probe "(df shout [(xs (List String))] -> (List String) (map string-upper xs))" "builtin-reference") "naked builtin in HOF builtin-reference")
    (assert (not (resolve-probe "(df f [] -> Int64 (+ 1 2))" "builtin-reference")) "normal call not builtin-reference")
    true))

(df test-resolve [] -> Bool
  :d "Unit tests for resolve"
  (do
    (assert (test-unbound-probe) "unbound probe rule-2")
    (assert (test-missing-doc-probe) "missing doc probe rule-8")
    (assert (test-reserved-probe) "reserved probe rule-7")
    (assert (test-unbound-typevar-probe) "unbound typevar probe rule-10")
    (assert (test-effect-probe) "effect probe rule-12")
    (assert (test-arity-probe) "arity probe")
    (assert (test-ctor-probe) "ctor probe")
    (assert (test-not-callable-probe) "not-callable probe")
    (assert (test-builtin-ref-probe) "builtin-ref probe")
    (assert (not (check-has-code (list) "rule-2")) "empty diagnostics has no error")
    true))

(df run-tests [] -> Bool
  :d "Runs resolve test suite"
  (do
    (assert (test-resolve) "test-resolve must pass")
    (assert (not (resolve-probe "(df f [] -> Int64 42)" "rule-2")) "pure constant has no rule-2")
    true))
