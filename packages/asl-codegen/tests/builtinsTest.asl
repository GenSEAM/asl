(module asl-codegen/builtinsTest
  :d "Unit tests for asl-codegen/builtins"
  :x [testBuiltins runTests]
  :i [(builtins :a b)])

(df testBuiltins [] -> Bool
  :d "Verifies builtin lowering templates and placeholder substitution."
  (let [(r1 (b/renderBuiltin "+" (list "1" "2")))
        (r2 (b/renderBuiltin "list-length" (list "xs")))
        (r3 (b/renderBuiltin "str" (list "a" "b" "c")))
        (r4 (b/renderBuiltin "list" (list "1" "2")))
        (r5 (b/renderBuiltin "string-slice" (list "s" "0" "5")))
        (rNone (b/renderBuiltin "not-a-builtin" (list)))]
    (assert (= r1 (some "rt::add(1, 2)")) "r1 add")
    (assert (= r2 (some "(xs.len() as i64)")) "r2 len")
    (assert (= r3 (some "rt::concat(&[a, b, c])")) "r3 concat")
    (assert (= r4 (some "vec![1, 2]")) "r4 vec")
    (assert (= r5 (some "rt::str_slice(&s, 0, 5)")) "r5 str_slice")
    (assert (= rNone (none)) "r-none")
    true))

(df runTests [] -> Bool
  :d "Runs builtins test suite"
  (do
    (assert (testBuiltins) "test-builtins must pass")
    true))
