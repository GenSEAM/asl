(module asl-compiler/test
  :d "Unit tests for 100% self-hosted compiler pipeline across WASM, Rust, Go, and C targets."
  :x [testCompileCleanFunction
      testCompileWasmTarget
      testCompileGoTarget
      testCompileCleanSchema
      testCompileEmbeddedTarget
      testCompileParseError
      testCompileTypeError
      runTests]
  :i [(compiler :a comp)])

(df testCompileCleanFunction [] -> Bool
  :d "Verifies end-to-end compilation of a valid arithmetic function to Rust platform leaf."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compileStandaloneTarget src "rust" "math.asl"))]
    (assert (.-ok res) "Clean function compilation to rust should succeed")
    (assert (string-contains? (.-code res) "pub fn add") "Generated code should contain pub fn add")
    (assert (not (string-contains? (.-code res) "package main")) "Must not contain Go package")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty for clean function")
    true))

(df testCompileWasmTarget [] -> Bool
  :d "Verifies primary compilation to WebAssembly universal core target."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compileStandaloneSource src "math.asl"))
        (resExplicit (comp/compileStandaloneTarget src "wasm" "math.asl"))]
    (assert (.-ok res) "Default standalone compilation to wasm must succeed")
    (assert (.-ok resExplicit) "Explicit wasm compilation must succeed")
    (assert (string-contains? (.-code res) "(module") "Default output must be WebAssembly module")
    (assert (string-contains? (.-code res) "memory") "WASM output must declare memory")
    (assert (not (string-contains? (.-code res) "pub fn")) "Default output must not be Rust")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty")
    true))

(df testCompileGoTarget [] -> Bool
  :d "Verifies compilation to Go cloud-native platform leaf."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compileStandaloneTarget src "go" "math.asl"))]
    (assert (.-ok res) "Go compilation must succeed")
    (assert (string-contains? (.-code res) "package main") "Go output must declare package main")
    (assert (string-contains? (.-code res) "func Main()") "Go output must declare Main function")
    (assert (not (string-contains? (.-code res) "(module")) "Go output must not be WAT")
    (assert (list-empty? (.-diagnostics res)) "Diagnostics should be empty")
    true))

(df testCompileCleanSchema [] -> Bool
  :d "Verifies end-to-end compilation of a valid schema definition."
  (let [(src "(dfs Point (:f x I64 \"x coord\") (:f y I64 \"y coord\"))")
        (res (comp/compileStandaloneTarget src "rust" "point.asl"))]
    (assert (.-ok res) "Clean schema compilation should succeed")
    (assert (string-contains? (.-code res) "pub struct Point") "Generated code should contain pub struct Point")
    (assert (not (string-contains? (.-code res) "class Point")) "Must not contain class keyword")
    true))

(df testCompileEmbeddedTarget [] -> Bool
  :d "Verifies compilation to embedded C target."
  (let [(src "(df blink [] -> Unit ())")
        (res (comp/compileStandaloneTarget src "c-embedded" "blink.asl"))]
    (assert (.-ok res) "Embedded target compilation should succeed")
    (assert (string-contains? (.-code res) "<stdint.h>") "Generated code should contain <stdint.h>")
    (assert (not (string-contains? (.-code res) "pub fn")) "Must not contain Rust fn")
    true))

(df testCompileParseError [] -> Bool
  :d "Verifies rejection of syntactically malformed code."
  (let [(src "(df broken [)")
        (res (comp/compileStandaloneSource src "syntax_err.asl"))]
    (assert (not (.-ok res)) "Parse error code should not compile successfully")
    (assert (> (list-length (.-diagnostics res)) 0) "Diagnostics should contain parse error messages")
    (assert (string-contains? (list-head (.-diagnostics res)) "parse-error") "Diagnostics must report parse-error")
    true))

(df testCompileTypeError [] -> Bool
  :d "Verifies rejection of type-mismatched code."
  (let [(src "(df type-err [] -> I64 \"not-an-int\")")
        (res (comp/compileStandaloneSource src "type_err.asl"))]
    (assert (not (.-ok res)) "Type error code should not compile successfully")
    (assert (not (list-empty? (.-diagnostics res))) "Diagnostics should contain type error messages")
    (assert (not (= (.-code res) "(module)")) "Code must not be generated on type error")
    true))

(df runTests [] -> Bool
  :d "Runs all compiler pipeline tests."
  (let [(t1 (testCompileCleanFunction))
        (t2 (testCompileWasmTarget))
        (t3 (testCompileGoTarget))
        (t4 (testCompileCleanSchema))
        (t5 (testCompileEmbeddedTarget))
        (t6 (testCompileParseError))
        (t7 (testCompileTypeError))] (and t1 (and t2 (and t3 (and t4 (and t5 (and t6 t7))))))))
