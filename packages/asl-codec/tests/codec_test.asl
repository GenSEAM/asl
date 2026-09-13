(module asl-codec/test
  :d "Unit tests for native JSON codec."
  :x [runTests]
  :i [(asl-codec/core :a c)])

(df testPrimitives [] -> Bool
  :d "Verifies primitive JSON serialization"
  (do
    (assert (= (c/renderJson (c/jsonNull)) "null") "null render")
    (assert (= (c/renderJson (c/jsonBool true)) "true") "true render")
    (assert (= (c/renderJson (c/jsonBool false)) "false") "false render")
    (assert (= (c/renderJson (c/jsonStr "hello")) "\"hello\"") "str render")
    true))

(df testCollections [] -> Bool
  :d "Verifies composite JSON array and object serialization"
  (let [(arr (c/jsonArr (list (c/jsonInt 1) (c/jsonStr "two"))))
        (obj (c/jsonObj (list (c/makeKv "key" (c/jsonStr "val")))))]
    (assert (= (c/renderJson arr) "[1,\"two\"]") "array render")
    (assert (= (c/renderJson obj) "{\"key\":\"val\"}") "object render")
    true))

(df runTests [] -> Bool
  :d "Executes basic verification of codec types"
  (do
    (assert (testPrimitives) "test-primitives must pass")
    (assert (testCollections) "test-collections must pass")
    true))
