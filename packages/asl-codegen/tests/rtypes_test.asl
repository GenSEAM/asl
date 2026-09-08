(module asl-codegen/rtypes-test
  :d "Unit tests for asl-codegen/rtypes"
  :x [test-rtypes run-tests]
  :i [(rtypes :a cg-ty)])

(df test-rtypes [] -> Bool
  :d "Verifies Rust type mappings and derive attributes."
  (let [(t1 (cg-ty/emit-type-str "Int"))
        (t2 (cg-ty/emit-type-str "Str"))
        (t3 (cg-ty/emit-type-str "Bool"))
        (t4 (cg-ty/emit-type-str "(List Int)"))
        (t5 (cg-ty/emit-type-str "(Option Str)"))
        (t6 (cg-ty/emit-type-str "(Result Int IoError)"))
        (t7 (cg-ty/emit-type-str "(Pair Int Str)"))
        (t8 (cg-ty/emit-type-str "(Map Str Int)"))
        (d-all (cg-ty/emit-derives false false))
        (d-float (cg-ty/emit-derives false true))
        (d-io (cg-ty/emit-derives true false))]
    (assert (= t1 "i64") "emit Int")
    (assert (= t2 "String") "emit Str")
    (assert (= t3 "bool") "emit Bool")
    (assert (= t4 "Vec<i64>") "emit List Int")
    (assert (= t5 "Option<String>") "emit Option Str")
    (assert (= t6 "Result<i64, rt::IoError>") "emit Result Int IoError")
    (assert (= t7 "(i64, String)") "emit Pair Int Str")
    (assert (= t8 "std::collections::BTreeMap<String, i64>") "emit Map Str Int")
    (assert (= d-all "#[derive(Debug, Clone, PartialEq, PartialOrd)]") "derives all")
    (assert (= d-float "#[derive(Debug, Clone, PartialEq, PartialOrd)]") "derives float")
    (assert (= d-io "#[derive(Debug, Clone, PartialEq)]") "derives io")
    true))

(df run-tests [] -> Bool
  :d "Runs rtypes test suite"
  (do
    (assert (test-rtypes) "test-rtypes must pass")
    true))
