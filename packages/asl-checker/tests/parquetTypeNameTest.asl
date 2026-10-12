(module asl-checker/tests/parquetTypeNameTest :x [runTests RunTests] :i [(types :a ty) (ast :a a) (resolve :a r)])

fn checkHasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn resolveProbe src: String wantCode: String -> Bool
  (mt (a/parse src) ((err _) false) ((ok forms) (let [(summary (r/collectSummary forms "test.asl")) (diags (r/resolveModule summary forms (mapEmpty)))] (checkHasCode diags wantCode))))

fn testParquetHandleParamNotUnknown -> Bool
  (do (refute (resolveProbe "(fn pqRows [(h ParquetHandle)] -> Int64 1)" "rule-10") "ParquetHandle param is a known builtin type") true)

fn testF64ArrayReturnNotUnknown -> Bool
  (do (refute (resolveProbe "(fn ! pqCol [(h ParquetHandle) (name String)] -> F64Array (parquetReadF64 h name 0))" "rule-10") "F64Array return is a known builtin type") true)

fn testI64ArrayParamNotUnknown -> Bool
  (do (refute (resolveProbe "(fn sumI64 [(values I64Array)] -> Int64 (i64ArraySum values))" "rule-10") "I64Array param is a known builtin type") true)

fn testI8ArrayReturnNotUnknown -> Bool
  (do (refute (resolveProbe "(fn ! pqI8 [(h ParquetHandle) (name String)] -> I8Array (parquetReadI8 h name 0))" "rule-10") "I8Array return is a known builtin type") true)

fn testBogusTypeStillUnknown -> Bool
  (do (assert (resolveProbe "(fn foo [] -> Bogus 1)" "rule-10") "a made-up type name is still rule-10") true)

fn runTests -> Bool
  (do
    (assert (testParquetHandleParamNotUnknown) "ParquetHandle param not rule-10")
    (assert (testF64ArrayReturnNotUnknown) "F64Array return not rule-10")
    (assert (testI64ArrayParamNotUnknown) "I64Array param not rule-10")
    (assert (testI8ArrayReturnNotUnknown) "I8Array return not rule-10")
    (assert (testBogusTypeStillUnknown) "sanity: a made-up type is still flagged")
    true)

fn RunTests -> Bool
  (runTests)
