(module asl-codegen/tests/goCodegenTest :x [runTests] :i [(asl-target-go/emitGo :a g)])

fn testGoType -> Bool
  (let [(t1 (g/emitGoType "I64")) (t2 (g/emitGoType "I32")) (t3 (g/emitGoType "Bool")) (t4 (g/emitGoType "Str")) (t5 (g/emitGoType "F64")) (t6 (g/emitGoType "Unit")) (t7 (g/emitGoType "CustomType"))] (assert (= t1 "int64") "I64 must map to int64") (assert (= t2 "int32") "I32 must map to int32") (assert (= t3 "bool") "Bool must map to bool") (assert (= t4 "string") "Str must map to string") (assert (= t5 "float64") "F64 must map to float64") (assert (= t6 "") "Unit must map to empty") (assert (= t7 "CustomType") "CustomType must be preserved") (assert (not (= t1 "i64")) "Must not emit Rust style type") (assert (not (= t4 "Str")) "Must not emit ASL style type") true)

fn testGoFn -> Bool
  (let [(fn1 (g/emitGoFn "compute" "x int64, y int64" "I64" "return x + y" true)) (fn2 (g/emitGoFn "helper" "val string" "Bool" "return len(val) > 0" false))] (assert (stringContains? fn1 "func Compute(x int64, y int64) int64 {") "Exported fn must be capitalized") (assert (stringContains? fn1 "return x + y") "Fn body must be included") (assert (stringContains? fn2 "func helper(val string) bool {") "Unexported fn must stay lowercase") (assert (not (stringContains? fn1 "pub fn")) "Must not emit Rust fn keyword") (assert (not (stringContains? fn2 "func Helper")) "Unexported fn must not be capitalized") true)

fn testGoStruct -> Bool
  (let [(fields "\tID int64\n\tName string\n") (sCode (g/emitGoStruct "User" fields))] (assert (stringContains? sCode "type User struct {") "Must declare struct type") (assert (stringContains? sCode "ID int64") "Must contain ID field") (assert (stringContains? sCode "Name string") "Must contain Name field") (assert (not (stringContains? sCode "pub struct")) "Must not emit Rust struct") (assert (not (stringContains? sCode "class User")) "Must not emit class keyword") true)

fn testGoEnum -> Bool
  (let [(cases (list "Active" "Pending" "Terminated")) (eCode (g/emitGoEnum "TaskState" cases))] (assert (stringContains? eCode "type TaskState int") "Must declare enum type alias") (assert (stringContains? eCode "const (") "Must declare const block") (assert (stringContains? eCode "TaskStateActive TaskState = iota") "Must declare iota constant") (assert (stringContains? eCode "TaskStatePending TaskState = iota") "Must declare second variant") (assert (not (stringContains? eCode "pub enum")) "Must not emit Rust enum keyword") (assert (not (stringContains? eCode "enum TaskState {")) "Must not emit C++ style enum") true)

fn testGoProgram -> Bool
  (let [(prog (g/emitGoProgram "main" "type Node struct {}\n" "func Run() {}\n"))] (assert (stringContains? prog "package main") "Must include package declaration") (assert (stringContains? prog "import (") "Must include imports") (assert (stringContains? prog "type Node struct") "Must include struct definition") (assert (stringContains? prog "func Run()") "Must include function definition") (assert (not (stringContains? prog "mod rt;")) "Must not link Rust runtime") (assert (not (stringContains? prog "namespace")) "Must not emit C++ namespace") true)

fn runTests -> Bool
  (do (assert (testGoType) "test-go-type must pass") (assert (testGoFn) "test-go-fn must pass") (assert (testGoStruct) "test-go-struct must pass") (assert (testGoEnum) "test-go-enum must pass") (assert (testGoProgram) "test-go-program must pass") true)
