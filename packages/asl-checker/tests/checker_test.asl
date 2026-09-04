(module asl-checker/checker-test
  :d "Test driver for asl-checker/check"
  :x [check-source
      check-file!
      test-corpus-smoke]
  :i [(types :a ty) (resolve :a r) (check :a c)])

(df check-source [(src String) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Check source string"
  (c/check-source src deps path))

(df ! check-file! [(path String) (roots (List String))] -> (Result (List ty/Diagnostic) IoError)
  :d "Check file on disk"
  (c/check-file! path roots))

(df test-corpus-smoke [] -> String
  :d "Smoke test"
  (let [(res (c/check-source "(module m :d \"d\" :x [f]) (df f [] -> Int64 42)" (map-empty) "m.asl"))]
    (if (list-empty? res)
      "ok"
      "fail smoke")))
