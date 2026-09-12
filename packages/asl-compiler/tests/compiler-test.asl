(module asl-compiler/test
  :d "Unit tests for 100% self-hosted compiler pipeline across WASM, Rust, Go, and C targets."
  :x [test-compile-clean-function
      test-compile-wasm-target
      test-compile-go-target
      test-compile-clean-schema
      test-compile-embedded-target
      test-compile-parse-error
      test-compile-type-error
      run-tests]
  :i [(compiler :a comp)])

(df test-compile-clean-function [] -> Bool
  :d "Verifies end-to-end compilation of a valid arithmetic function to Rust platform leaf."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compile-standalone-target src "rust" "math.asl"))]
    (assert (.-ok res) "Clean function compilation to rust should succeed")
    (assert (string-contains? (.-code res) "pub fn add") "Generated code should contain pub fn add")
    (assert (not (string-contains? (.-code res) "package main")) "Must not contain Go package")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty for clean function")
    true))

(df test-compile-wasm-target [] -> Bool
  :d "Verifies primary compilation to WebAssembly universal core target."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compile-standalone-source src "math.asl"))
        (res-explicit (comp/compile-standalone-target src "wasm" "math.asl"))]
    (assert (.-ok res) "Default standalone compilation to wasm must succeed")
    (assert (.-ok res-explicit) "Explicit wasm compilation must succeed")
    (assert (string-contains? (.-code res) "(module") "Default output must be WebAssembly module")
    (assert (string-contains? (.-code res) "memory") "WASM output must declare memory")
    (assert (not (string-contains? (.-code res) "pub fn")) "Default output must not be Rust")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty")
    true))

(df test-compile-go-target [] -> Bool
  :d "Verifies compilation to Go cloud-native platform leaf."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compile-standalone-target src "go" "math.asl"))]
    (assert (.-ok res) "Go compilation must succeed")
    (assert (string-contains? (.-code res) "package main") "Go output must declare package main")
    (assert (string-contains? (.-code res) "func Main()") "Go output must declare Main function")
    (assert (not (string-contains? (.-code res) "(module")) "Go output must not be WAT")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty")
    true))

(df test-compile-clean-schema [] -> Bool
  :d "Verifies end-to-end compilation of a valid schema definition."
  (let [(src "(dfs Point (:f x I64 \"x coord\") (:f y I64 \"y coord\"))")
        (res (comp/compile-standalone-target src "rust" "point.asl"))]
    (assert (.-ok res) "Clean schema compilation should succeed")
    (assert (string-contains? (.-code res) "pub struct Point") "Generated code should contain pub struct Point")
    (assert (not (string-contains? (.-code res) "class Point")) "Must not contain class keyword")
    true))

(df test-compile-embedded-target [] -> Bool
  :d "Verifies compilation to embedded C target."
  (let [(src "(df blink [] -> Unit ())")
        (res (comp/compile-standalone-target src "c-embedded" "blink.asl"))]
    (assert (.-ok res) "Embedded target compilation should succeed")
    (assert (string-contains? (.-code res) "<stdint.h>") "Generated code should contain <stdint.h>")
    (assert (not (string-contains? (.-code res) "pub fn")) "Must not contain Rust fn")
    true))

(df test-compile-parse-error [] -> Bool
  :d "Verifies rejection of syntactically malformed code."
  (let [(src "(df broken [)")
        (res (comp/compile-standalone-source src "syntax_err.asl"))]
    (assert (not (.-ok res)) "Parse error code should not compile successfully")
    (assert (> (list-length (.-diagnostics res)) 0) "Diagnostics should contain parse error messages")
    (assert (string-contains? (list-head (.-diagnostics res)) "parse-error") "Diagnostics must report parse-error")
    true))

(df test-compile-type-error [] -> Bool
  :d "Verifies rejection of type-mismatched code."
  (let [(src "(df type-err [] -> I64 \"not-an-int\")")
        (res (comp/compile-standalone-source src "type_err.asl"))]
    (assert (not (.-ok res)) "Type error code should not compile successfully")
    (assert (not (list-empty? (.-diagnostics res))) "Diagnostics should contain type error messages")
    (assert (not (= (.-code res) "(module)")) "Code must not be generated on type error")
    true))

(df run-tests [] -> Bool
  :d "Runs all compiler pipeline tests."
  (let [(t1 (test-compile-clean-function))
        (t2 (test-compile-wasm-target))
        (t3 (test-compile-go-target))
        (t4 (test-compile-clean-schema))
        (t5 (test-compile-embedded-target))
        (t6 (test-compile-parse-error))
        (t7 (test-compile-type-error))] (and t1 (and t2 (and t3 (and t4 (and t5 (and t6 t7))))))))
