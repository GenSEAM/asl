(module asl-codegen/tests/go-codegen-test
  :d "Unit tests for Go platform leaf code generator with dual-polarity assertions."
  :x [run-tests]
  :i [(emit-go :a g)])

(df test-go-type [] -> Bool
  :d "Verifies AgentScript to Go type mapping with positive and negative assertions."
  (let [(t1 (g/emit-go-type "I64"))
        (t2 (g/emit-go-type "I32"))
        (t3 (g/emit-go-type "Bool"))
        (t4 (g/emit-go-type "Str"))
        (t5 (g/emit-go-type "F64"))
        (t6 (g/emit-go-type "Unit"))
        (t7 (g/emit-go-type "CustomType"))]
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

(df test-go-fn [] -> Bool
  :d "Verifies Go function declaration and export capitalization with dual polarity."
  (let [(fn1 (g/emit-go-fn "compute" "x int64, y int64" "I64" "return x + y" true))
        (fn2 (g/emit-go-fn "helper" "val string" "Bool" "return len(val) > 0" false))]
    (assert (string-contains? fn1 "func Compute(x int64, y int64) int64 {") "Exported fn must be capitalized")
    (assert (string-contains? fn1 "return x + y") "Fn body must be included")
    (assert (string-contains? fn2 "func helper(val string) bool {") "Unexported fn must stay lowercase")
    (assert (not (string-contains? fn1 "pub fn")) "Must not emit Rust fn keyword")
    (assert (not (string-contains? fn2 "func Helper")) "Unexported fn must not be capitalized")
    true))

(df test-go-struct [] -> Bool
  :d "Verifies Go struct definition with positive and negative assertions."
  (let [(fields "\tID int64\n\tName string\n")
        (s-code (g/emit-go-struct "User" fields))]
    (assert (string-contains? s-code "type User struct {") "Must declare struct type")
    (assert (string-contains? s-code "ID int64") "Must contain ID field")
    (assert (string-contains? s-code "Name string") "Must contain Name field")
    (assert (not (string-contains? s-code "pub struct")) "Must not emit Rust struct")
    (assert (not (string-contains? s-code "class User")) "Must not emit class keyword")
    true))

(df test-go-enum [] -> Bool
  :d "Verifies Go enum const block with positive and negative assertions."
  (let [(cases (list "Active" "Pending" "Terminated"))
        (e-code (g/emit-go-enum "TaskState" cases))]
    (assert (string-contains? e-code "type TaskState int") "Must declare enum type alias")
    (assert (string-contains? e-code "const (") "Must declare const block")
    (assert (string-contains? e-code "TaskStateActive TaskState = iota") "Must declare iota constant")
    (assert (string-contains? e-code "TaskStatePending TaskState = iota") "Must declare second variant")
    (assert (not (string-contains? e-code "pub enum")) "Must not emit Rust enum keyword")
    (assert (not (string-contains? e-code "enum TaskState {")) "Must not emit C++ style enum")
    true))

(df test-go-program [] -> Bool
  :d "Verifies Go package program assembly with positive and negative assertions."
  (let [(prog (g/emit-go-program "main" "type Node struct {}\n" "func Run() {}\n"))]
    (assert (string-contains? prog "package main") "Must include package declaration")
    (assert (string-contains? prog "import (") "Must include imports")
    (assert (string-contains? prog "type Node struct") "Must include struct definition")
    (assert (string-contains? prog "func Run()") "Must include function definition")
    (assert (not (string-contains? prog "mod rt;")) "Must not link Rust runtime")
    (assert (not (string-contains? prog "namespace")) "Must not emit C++ namespace")
    true))

(df run-tests [] -> Bool
  :d "Runs Go codegen test suite"
  (do
    (assert (test-go-type) "test-go-type must pass")
    (assert (test-go-fn) "test-go-fn must pass")
    (assert (test-go-struct) "test-go-struct must pass")
    (assert (test-go-enum) "test-go-enum must pass")
    (assert (test-go-program) "test-go-program must pass")
    true))
