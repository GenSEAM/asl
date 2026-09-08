(module asl-checker/resolve-test
  :d "Unit tests for asl-checker/resolve"
  :x [test-resolve run-tests]
  :i [(types :a ty) (ast :a a) (resolve :a r)])

(df check-has-code [(diags (List ty/Diagnostic)) (want-code String)] -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool
          (or acc (= (.-code d) want-code)))
        false
        diags))

(df test-probe [(src String) (want-code String)] -> Bool
  (mt (a/parse src)
    ((err _) false)
    ((ok forms)
     (let [(summary (r/collect-summary forms "test.asl"))
           (diags (r/resolve-module summary forms (map-empty)))]
       (check-has-code diags want-code)))))

(df test-unbound-probe [] -> Bool
  (test-probe "(df f [] -> Int64 (+ x 1))" "rule-2"))

(df test-missing-doc-probe [] -> Bool
  (test-probe "(module m :export [f]) (df f [] -> Int64 1)" "rule-8"))

(df test-reserved-probe [] -> Bool
  (test-probe "(df agentscript-foo [] -> Int64 1)" "rule-7"))

(df test-unbound-typevar-probe [] -> Bool
  (test-probe "(df f [] -> UnknownType 1)" "rule-10"))

(df test-effect-probe [] -> Bool
  (test-probe "(df f [] -> (Result Unit IoError) (println \"hi\"))" "rule-12"))

(df test-arity-probe [] -> Bool
  (test-probe "(df f [(x Int64)] -> Int64 (+ x 1)) (df g [] -> Int64 (f 1 2))" "arity"))

(df test-ctor-probe [] -> Bool
  (test-probe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (df f [] -> Pt (Pt :x 1))" "ctor"))

(df test-not-callable-probe [] -> Bool
  (test-probe "(df f [] -> Int64 (-1 2))" "not-callable"))

(df test-builtin-ref-probe [] -> Bool
  (test-probe "(df shout [(xs (List String))] -> (List String) (map string-upper xs))" "builtin-reference"))

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
    true))

(df run-tests [] -> Bool
  :d "Runs resolve test suite"
  (do
    (assert (test-resolve) "test-resolve must pass")
    true))
