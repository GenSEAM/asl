(module asl-codegen/builtins-test
  :d "Unit tests for asl-codegen/builtins"
  :x [test-builtins]
  :i [(builtins :a b)])

(df test-builtins [] -> String
  :d "Verifies builtin lowering templates and placeholder substitution."
  (let [(r1 (b/render-builtin "+" (list "1" "2")))
        (r2 (b/render-builtin "list-length" (list "xs")))
        (r3 (b/render-builtin "str" (list "a" "b" "c")))
        (r4 (b/render-builtin "list" (list "1" "2")))
        (r5 (b/render-builtin "string-slice" (list "s" "0" "5")))
        (r-none (b/render-builtin "not-a-builtin" (list)))]
    (cond
      ((not (= r1 (some "rt::add(1, 2)"))) "fail r1")
      ((not (= r2 (some "(xs.len() as i64)"))) "fail r2")
      ((not (= r3 (some "rt::concat(&[a, b, c])"))) "fail r3")
      ((not (= r4 (some "vec![1, 2]"))) "fail r4")
      ((not (= r5 (some "rt::str_slice(&s, 0, 5)"))) "fail r5")
      ((not (= r-none (none))) "fail r-none")
      (:else "ok"))))
