(module asl-codegen/tests/goCodegenTest
  :d "Unit tests for Go platform leaf code generator with dual-polarity assertions."
  :x [runTests]
  :i [(emitGo :a g)])

(df testGoType [] -> Bool
  :d "Verifies AgentScript to Go type mapping with positive and negative assertions."
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
    (assert (not (= t1 "i64")) "Must not emit Rust style type")
    (assert (not (= t4 "Str")) "Must not emit ASL style type")
    true))

(df testGoFn [] -> Bool
  :d "Verifies Go function declaration and export capitalization with dual polarity."
  (let [(fn1 (g/emitGoFn "compute" "x int64, y int64" "I64" "return x + y" true))
        (fn2 (g/emitGoFn "helper" "val string" "Bool" "return len(val) > 0" false))]
    (assert (string-contains? fn1 "func Compute(x int64, y int64) int64 {") "Exported fn must be capitalized")
    (assert (string-contains? fn1 "return x + y") "Fn body must be included")
    (assert (string-contains? fn2 "func helper(val string) bool {") "Unexported fn must stay lowercase")
    (assert (not (string-contains? fn1 "pub fn")) "Must not emit Rust fn keyword")
    (assert (not (string-contains? fn2 "func Helper")) "Unexported fn must not be capitalized")
    true))

(df testGoStruct [] -> Bool
  :d "Verifies Go struct definition with positive and negative assertions."
  (let [(fields "\tID int64\n\tName string\n")
        (sCode (g/emitGoStruct "User" fields))]
    (assert (string-contains? sCode "type User struct {") "Must declare struct type")
    (assert (string-contains? sCode "ID int64") "Must contain ID field")
    (assert (string-contains? sCode "Name string") "Must contain Name field")
    (assert (not (string-contains? sCode "pub struct")) "Must not emit Rust struct")
    (assert (not (string-contains? sCode "class User")) "Must not emit class keyword")
    true))

(df testGoEnum [] -> Bool
  :d "Verifies Go enum const block with positive and negative assertions."
  (let [(cases (list "Active" "Pending" "Terminated"))
        (eCode (g/emitGoEnum "TaskState" cases))]
    (assert (string-contains? eCode "type TaskState int") "Must declare enum type alias")
    (assert (string-contains? eCode "const (") "Must declare const block")
    (assert (string-contains? eCode "TaskStateActive TaskState = iota") "Must declare iota constant")
    (assert (string-contains? eCode "TaskStatePending TaskState = iota") "Must declare second variant")
    (assert (not (string-contains? eCode "pub enum")) "Must not emit Rust enum keyword")
    (assert (not (string-contains? eCode "enum TaskState {")) "Must not emit C++ style enum")
    true))

(df testGoProgram [] -> Bool
  :d "Verifies Go package program assembly with positive and negative assertions."
  (let [(prog (g/emitGoProgram "main" "type Node struct {}\n" "func Run() {}\n"))]
    (assert (string-contains? prog "package main") "Must include package declaration")
    (assert (string-contains? prog "import (") "Must include imports")
    (assert (string-contains? prog "type Node struct") "Must include struct definition")
    (assert (string-contains? prog "func Run()") "Must include function definition")
    (assert (not (string-contains? prog "mod rt;")) "Must not link Rust runtime")
    (assert (not (string-contains? prog "namespace")) "Must not emit C++ namespace")
    true))

(df runTests [] -> Bool
  :d "Runs Go codegen test suite"
  (do
    (assert (testGoType) "test-go-type must pass")
    (assert (testGoFn) "test-go-fn must pass")
    (assert (testGoStruct) "test-go-struct must pass")
    (assert (testGoEnum) "test-go-enum must pass")
    (assert (testGoProgram) "test-go-program must pass")
    true))
