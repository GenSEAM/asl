(module asl-codegen/rtypes-test
  :d "Unit tests for asl-codegen/rtypes"
  :x [test-rtypes]
  :i [(rtypes :a cg-ty)])

(df test-rtypes [] -> String
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
    (cond
      ((not (= t1 "i64")) "fail t1")
      ((not (= t2 "String")) "fail t2")
      ((not (= t3 "bool")) "fail t3")
      ((not (= t4 "Vec<i64>")) "fail t4")
      ((not (= t5 "Option<String>")) "fail t5")
      ((not (= t6 "Result<i64, rt::IoError>")) "fail t6")
      ((not (= t7 "(i64, String)")) "fail t7")
      ((not (= t8 "std::collections::BTreeMap<String, i64>")) "fail t8")
      ((not (= d-all "#[derive(Debug, Clone, PartialEq, PartialOrd, Eq, Ord)]")) "fail d-all")
      ((not (= d-float "#[derive(Debug, Clone, PartialEq, PartialOrd)]")) "fail d-float")
      ((not (= d-io "#[derive(Debug, Clone, PartialEq)]")) "fail d-io")
      (:else "ok"))))
