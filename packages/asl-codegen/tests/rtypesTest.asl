(module asl-codegen/rtypesTest :x [testRtypes runTests] :i [(rtypes :a cgTy)])

fn testRtypes -> Bool
  (let [(t1 (cgTy/emitTypeStr "Int")) (t2 (cgTy/emitTypeStr "Str")) (t3 (cgTy/emitTypeStr "Bool")) (t4 (cgTy/emitTypeStr "(List Int)")) (t5 (cgTy/emitTypeStr "(Option Str)")) (t6 (cgTy/emitTypeStr "(Result Int IoError)")) (t7 (cgTy/emitTypeStr "(Pair Int Str)")) (t8 (cgTy/emitTypeStr "(Map Str Int)")) (dAll (cgTy/emitDerives false false)) (dFloat (cgTy/emitDerives false true)) (dIo (cgTy/emitDerives true false))] (assert (= t1 "i64") "emit Int") (assert (= t2 "String") "emit Str") (assert (= t3 "bool") "emit Bool") (assert (= t4 "Vec<i64>") "emit List Int") (assert (= t5 "Option<String>") "emit Option Str") (assert (= t6 "Result<i64, rt::IoError>") "emit Result Int IoError") (assert (= t7 "(i64, String)") "emit Pair Int Str") (assert (= t8 "std::collections::BTreeMap<String, i64>") "emit Map Str Int") (assert (= dAll "#[derive(Debug, Clone, PartialEq, PartialOrd)]") "derives all") (assert (= dFloat "#[derive(Debug, Clone, PartialEq, PartialOrd)]") "derives float") (assert (= dIo "#[derive(Debug, Clone, PartialEq)]") "derives io") true)

fn runTests -> Bool
  (do (assert (testRtypes) "test-rtypes must pass") true)
