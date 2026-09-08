(module asl-codegen/builtins-test
  :d "Unit tests for asl-codegen/builtins"
  :x [test-builtins run-tests]
  :i [(builtins :a b)])

(df test-builtins [] -> Bool
  :d "Verifies builtin lowering templates and placeholder substitution."
  (let [(r1 (b/render-builtin "+" (list "1" "2")))
        (r2 (b/render-builtin "list-length" (list "xs")))
        (r3 (b/render-builtin "str" (list "a" "b" "c")))
        (r4 (b/render-builtin "list" (list "1" "2")))
        (r5 (b/render-builtin "string-slice" (list "s" "0" "5")))
        (r-none (b/render-builtin "not-a-builtin" (list)))]
    (assert (= r1 (some "rt::add(1, 2)")) "r1 add")
    (assert (= r2 (some "(xs.len() as i64)")) "r2 len")
    (assert (= r3 (some "rt::concat(&[a, b, c])")) "r3 concat")
    (assert (= r4 (some "vec![1, 2]")) "r4 vec")
    (assert (= r5 (some "rt::str_slice(&s, 0, 5)")) "r5 str_slice")
    (assert (= r-none (none)) "r-none")
    true))

(df run-tests [] -> Bool
  :d "Runs builtins test suite"
  (do
    (assert (test-builtins) "test-builtins must pass")
    true))
