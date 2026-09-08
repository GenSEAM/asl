(module asl-codec/test
  :d "Unit tests for native JSON codec."
  :x [run-tests]
  :i [(asl-codec/core :a c)])

(df test-primitives [] -> Bool
  :d "Verifies primitive JSON serialization"
  (do
    (assert (= (c/render-json (c/json-null)) "null") "null render")
    (assert (= (c/render-json (c/json-bool true)) "true") "true render")
    (assert (= (c/render-json (c/json-bool false)) "false") "false render")
    (assert (= (c/render-json (c/json-str "hello")) "\"hello\"") "str render")
    true))

(df test-collections [] -> Bool
  :d "Verifies composite JSON array and object serialization"
  (let [(arr (c/json-arr (list (c/json-int 1) (c/json-str "two"))))
        (obj (c/json-obj (list (c/make-kv "key" (c/json-str "val")))))]
    (assert (= (c/render-json arr) "[1,\"two\"]") "array render")
    (assert (= (c/render-json obj) "{\"key\":\"val\"}") "object render")
    true))

(df run-tests [] -> Bool
  :d "Executes basic verification of codec types"
  (do
    (assert (test-primitives) "test-primitives must pass")
    (assert (test-collections) "test-collections must pass")
    true))
