(module asl-transpile/test :x [runTests] :i [(asl-transpile/core :a c)])

fn testPrimitives -> Bool
  (do (assert (= (c/renderJson (c/jsonNull)) "null") "null render") (assert (= (c/renderJson (c/jsonBool true)) "true") "true render") (assert (= (c/renderJson (c/jsonBool false)) "false") "false render") (assert (= (c/renderJson (c/jsonStr "hello")) "\"hello\"") "str render") true)

fn testCollections -> Bool
  (let [(arr (c/jsonArr (list (c/jsonInt 1) (c/jsonStr "two")))) (obj (c/jsonObj (list (c/makeKv "key" (c/jsonStr "val")))))] (assert (= (c/renderJson arr) "[1,\"two\"]") "array render") (assert (= (c/renderJson obj) "{\"key\":\"val\"}") "object render") true)

fn runTests -> Bool
  (do (assert (testPrimitives) "test-primitives must pass") (assert (testCollections) "test-collections must pass") true)
