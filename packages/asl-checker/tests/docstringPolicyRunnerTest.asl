(module asl-checker/tests/docstringPolicyRunnerTest :x [runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty)])

fn runTests -> Bool
  (let [(diags (c/checkSource "(module m :x [f]) (df f [] -> Int64 42)" (mapEmpty) "m.asl")) (first (optionOr (listHead diags) (ty/Diagnostic :code "" :message "" :msg "" :line 1 :col 1 :path "")))] (assert (listEmpty? diags) "m.asl without a source doc produces no diagnostics: docs live in doc.asn (D158)") (refute (= first.code "rule-8") "no rule-8 diagnostic") true)
