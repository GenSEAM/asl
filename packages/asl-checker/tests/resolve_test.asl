(module asl-checker/resolve-test
  :d "Unit tests for asl-checker/resolve"
  :x [test-resolve]
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
  (test-probe "(defun f [] -> Int64 (+ x 1))" "rule-2"))

(df test-missing-doc-probe [] -> Bool
  (test-probe "(module m :export [f]) (defun f [] -> Int64 1)" "rule-8"))

(df test-reserved-probe [] -> Bool
  (test-probe "(defun agentscript-foo [] -> Int64 1)" "rule-7"))

(df test-unbound-typevar-probe [] -> Bool
  (test-probe "(defun f [] -> UnknownType 1)" "rule-10"))

(df test-effect-probe [] -> Bool
  (test-probe "(defun f [] -> (Result Unit IoError) (println \"hi\"))" "rule-12"))

(df test-arity-probe [] -> Bool
  (test-probe "(defun f [(x Int64)] -> Int64 (+ x 1)) (defun g [] -> Int64 (f 1 2))" "arity"))

(df test-ctor-probe [] -> Bool
  (test-probe "(defschema Pt (:field x Int64 \"x\") (:field y Int64 \"y\")) (defun f [] -> Pt (Pt :x 1))" "ctor"))

(df test-not-callable-probe [] -> Bool
  (test-probe "(defun f [] -> Int64 (-1 2))" "not-callable"))

(df test-builtin-ref-probe [] -> Bool
  (test-probe "(defun shout [(xs (List String))] -> (List String) (map string-upper xs))" "builtin-reference"))

(df test-resolve [] -> String
  :d "Unit tests for resolve"
  (cond
    ((not (test-unbound-probe)) "fail unbound probe rule-2")
    ((not (test-missing-doc-probe)) "fail missing doc probe rule-8")
    ((not (test-reserved-probe)) "fail reserved probe rule-7")
    ((not (test-unbound-typevar-probe)) "fail unbound typevar probe rule-10")
    ((not (test-effect-probe)) "fail effect probe rule-12")
    ((not (test-arity-probe)) "fail arity probe")
    ((not (test-ctor-probe)) "fail ctor probe")
    ((not (test-not-callable-probe)) "fail not-callable probe")
    ((not (test-builtin-ref-probe)) "fail builtin-ref probe")
    (:else "ok")))
