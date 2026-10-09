(module asl-parser/fixtures/nativeAstSuites :x [main] :i [(asl-parser/tests/astConverterTest :a ct) (asl-parser/tests/astPrinterTest :a pt)])

fn ! main args: (List String) -> (Result Int64 String)
  (if (and (ct/runTests) (pt/runTests)) (ok 42) (err "an ast suite failed"))
