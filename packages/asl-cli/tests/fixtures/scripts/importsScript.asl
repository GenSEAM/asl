(module scripts/importsScript :x [main] :i [(asl/packages/asl-cli/tests/fixtures/scripts/helper :a helper)])

fn ! main args: (List String) -> (Result Int64 String)
  (do (println "imports a script")
      (ok 0))
