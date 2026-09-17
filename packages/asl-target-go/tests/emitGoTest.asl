(module asl-target-go/tests/emitGoTest
  :d "Unit tests for standalone Go platform leaf code generator with dual-polarity D77 refutations."
  :x [runTests]
  :i [(asl-target-go/emitGo :a g)])

(df testGoType [] -> Bool
  :d "Verifies AgentScript to Go type mapping with positive assertions and D77 refutations."
  (let [(t1 (g/emitGoType "I64"))
        (t2 (g/emitGoType "I32"))
        (t3 (g/emitGoType "Bool"))
        (t4 (g/emitGoType "Str"))
        (t5 (g/emitGoType "F64"))
        (t6 (g/emitGoType "Unit"))
        (t7 (g/emitGoType "CustomType"))]
    (assert (= t1 "int64") "I64 must map to int64")
    (assert (= t2 "int32") "I32 must map to int32")
    (assert (= t3 "bool") "Bool must map to bool")
    (assert (= t4 "string") "Str must map to string")
    (assert (= t5 "float64") "F64 must map to float64")
    (assert (= t6 "") "Unit must map to empty")
    (assert (= t7 "CustomType") "CustomType must be preserved")
    (refute (= t1 "i64") "Must refute Rust-style i64")
    (refute (= t4 "Str") "Must refute ASL-style Str")
    (refute (= t3 "boolean") "Must refute Java-style boolean")
    (refute (= t5 "f64") "Must refute Rust-style f64")
    (refute (= t6 "void") "Must refute C-style void")
    true))

(df testGoFn [] -> Bool
  :d "Verifies Go function declaration and export capitalization with D77 refutations."
  (let [(fn1 (g/emitGoFn "compute" "x int64, y int64" "I64" "return x + y" true))
        (fn2 (g/emitGoFn "helper" "val string" "Bool" "return len(val) > 0" false))]
    (assert (string-contains? fn1 "func Compute(x int64, y int64) int64 {") "Exported fn must be capitalized")
    (assert (string-contains? fn1 "return x + y") "Fn body must be included")
    (assert (string-contains? fn2 "func helper(val string) bool {") "Unexported fn must stay lowercase")
    (refute (string-contains? fn1 "pub fn") "Must refute Rust fn syntax")
    (refute (string-contains? fn2 "func Helper") "Unexported fn must not be capitalized")
    (refute (string-contains? fn1 "def Compute") "Must refute Python def syntax")
    (refute (string-contains? fn1 "fn Compute") "Must refute ASL fn keyword")
    true))

(df testGoStruct [] -> Bool
  :d "Verifies Go struct definition with positive assertions and D77 refutations."
  (let [(fields "\tID int64\n\tName string\n")
        (sCode (g/emitGoStruct "User" fields))]
    (assert (string-contains? sCode "type User struct {") "Must declare struct type")
    (assert (string-contains? sCode "ID int64") "Must contain ID field")
    (assert (string-contains? sCode "Name string") "Must contain Name field")
    (refute (string-contains? sCode "pub struct") "Must refute Rust struct")
    (refute (string-contains? sCode "class User") "Must refute class keyword")
    (refute (string-contains? sCode "interface User") "Must refute interface keyword")
    true))

(df testGoEnum [] -> Bool
  :d "Verifies Go enum const block with positive assertions and D77 refutations."
  (let [(cases (list "Active" "Pending" "Terminated"))
        (eCode (g/emitGoEnum "TaskState" cases))]
    (assert (string-contains? eCode "type TaskState int") "Must declare enum type alias")
    (assert (string-contains? eCode "const (") "Must declare const block")
    (assert (string-contains? eCode "TaskStateActive TaskState = iota") "Must declare iota constant")
    (assert (string-contains? eCode "TaskStatePending TaskState = iota") "Must declare second variant")
    (assert (string-contains? eCode "TaskStateTerminated TaskState = iota") "Must declare third variant")
    (refute (string-contains? eCode "pub enum") "Must refute Rust enum keyword")
    (refute (string-contains? eCode "enum TaskState {") "Must refute C++ style enum")
    (refute (string-contains? eCode "enum class") "Must refute C++ scoped enum")
    true))

(df testGoProgram [] -> Bool
  :d "Verifies Go package program assembly with positive assertions and D77 refutations."
  (let [(prog (g/emitGoProgram "main" "type Node struct {}\n" "func Run() {}\n"))]
    (assert (string-contains? prog "package main") "Must include package declaration")
    (assert (string-contains? prog "import (") "Must include imports")
    (assert (string-contains? prog "type Node struct") "Must include struct definition")
    (assert (string-contains? prog "func Run()") "Must include function definition")
    (refute (string-contains? prog "mod rt") "Must refute Rust runtime link")
    (refute (string-contains? prog "namespace") "Must refute C++ namespace")
    (refute (string-contains? prog "#include") "Must refute C preprocessor")
    true))

(df runTests [] -> Bool
  :d "Runs Go codegen test suite."
  (do
    (assert (testGoType) "testGoType must pass")
    (assert (testGoFn) "testGoFn must pass")
    (assert (testGoStruct) "testGoStruct must pass")
    (assert (testGoEnum) "testGoEnum must pass")
    (assert (testGoProgram) "testGoProgram must pass")
    true))
