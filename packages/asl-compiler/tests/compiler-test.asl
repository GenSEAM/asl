(module asl-compiler/test
  :d "Unit tests for 100% self-hosted compiler pipeline"
  :x [test-compile-clean-function test-compile-clean-schema test-compile-embedded-target test-compile-parse-error test-compile-type-error run-tests]
  :i [(compiler :a comp)])

(df test-compile-clean-function [] -> Bool
  :d "Verifies end-to-end compilation of a valid arithmetic function."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compile-standalone-source src "math.asl"))]
    (assert (.-ok res) "Clean function compilation should succeed")
    (assert (string-contains? (.-code res) "pub fn add") "Generated code should contain pub fn add")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty for clean function")
    true))

(df test-compile-clean-schema [] -> Bool
  :d "Verifies end-to-end compilation of a valid schema definition."
  (let [(src "(dfs Point (:f x I64 \"x coord\") (:f y I64 \"y coord\"))")
        (res (comp/compile-standalone-source src "point.asl"))]
    (assert (.-ok res) "Clean schema compilation should succeed")
    (assert (string-contains? (.-code res) "pub struct Point") "Generated code should contain pub struct Point")
    true))

(df test-compile-embedded-target [] -> Bool
  :d "Verifies compilation to embedded C target."
  (let [(src "(df blink [] -> Unit ())")
        (res (comp/compile-standalone-target src "c-embedded" "blink.asl"))]
    (assert (.-ok res) "Embedded target compilation should succeed")
    (assert (string-contains? (.-code res) "<stdint.h>") "Generated code should contain <stdint.h>")
    true))

(df test-compile-parse-error [] -> Bool
  :d "Verifies rejection of syntactically malformed code."
  (let [(src "(df broken [)")
        (res (comp/compile-standalone-source src "syntax_err.asl"))]
    (assert (not (.-ok res)) "Parse error code should not compile successfully")
    (assert (> (list-length (.-diagnostics res)) 0) "Diagnostics should contain parse error messages")
    true))

(df test-compile-type-error [] -> Bool
  :d "Verifies rejection of type-mismatched code."
  (let [(src "(df type-err [] -> I64 \"not-an-int\")")
        (res (comp/compile-standalone-source src "type_err.asl"))]
    (assert (not (.-ok res)) "Type error code should not compile successfully")
    (assert (not (list-empty? (.-diagnostics res))) "Diagnostics should contain type error messages")
    true))

(df run-tests [] -> Bool
  :d "Runs all compiler pipeline tests."
  (let [(_t1 (test-compile-clean-function))
        (_t2 (test-compile-clean-schema))
        (_t3 (test-compile-embedded-target))
        (_t4 (test-compile-parse-error))
        (_t5 (test-compile-type-error))]
    true))
