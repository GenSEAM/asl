(module asl-target-rs/tests/emitRustTest
  :x [runTests]
  :i [(asl-target-rs/types :a t) (asl-checker/types :a ty)])

fn testRustTypes -> Bool
  (let [(t1 (t/emitRustType (ty/tyCon "Int" (list) (none) (none))))
        (t2 (t/emitRustType (ty/tyCon "Int32" (list) (none) (none))))
        (t3 (t/emitRustType (ty/tyCon "Float" (list) (none) (none))))
        (t4 (t/emitRustType (ty/tyCon "String" (list) (none) (none))))
        (t5 (t/emitRustType (ty/tyCon "Bool" (list) (none) (none))))
        (t6 (t/emitRustType (ty/tyCon "Void" (list) (none) (none))))
        (t7 (t/emitRustType (ty/tyCon "Bytes" (list) (none) (none))))
        (t8 (t/emitRustType (ty/tyCon "List" (list (ty/tyCon "String" (list) (none) (none))) (none) (none))))
        (t9 (t/emitRustType (ty/tyCon "Option" (list (ty/tyCon "Int" (list) (none) (none))) (none) (none))))
        (t10 (t/emitRustType (ty/tyCon "Map" (list (ty/tyCon "String" (list) (none) (none)) (ty/tyCon "Int" (list) (none) (none))) (none) (none))))
        (t11 (t/emitRustType (ty/tyCon "Result" (list (ty/tyCon "String" (list) (none) (none)) (ty/tyCon "Int" (list) (none) (none))) (none) (none))))]
    (assert (= t1 "i64") "Int must map to Rust i64")
    (assert (= t2 "i32") "Int32 must map to Rust i32")
    (assert (= t3 "f64") "Float must map to Rust f64")
    (assert (= t4 "String") "String must map to Rust String")
    (assert (= t5 "bool") "Bool must map to Rust bool")
    (assert (= t6 "()") "Void must map to Rust ()")
    (assert (= t7 "Vec<u8>") "Bytes must map to Rust Vec<u8>")
    (assert (= t8 "Vec<String>") "List String must map to Rust Vec<String>")
    (assert (= t9 "Option<i64>") "Option Int must map to Rust Option<i64>")
    (assert (= t10 "std::collections::HashMap<String, i64>") "Map String Int must map to Rust HashMap")
    (assert (= t11 "Result<String, i64>") "Result String Int must map to Rust Result<String, i64>")
    (refute (= t1 "int64") "Must refute Go int64")
    (refute (= t4 "str") "Must refute Python str")
    (refute (= t5 "boolean") "Must refute Java boolean")
    (refute (= t6 "None") "Must refute Python None")
    true)

fn testRustMangle -> Bool
  (let [(m1 (t/rustMangleIdent "userProfile"))
        (m2 (t/rustMangleIdent "match"))
        (m3 (t/rustMangleIdent "type"))
        (m4 (t/rustMangleIdent "self"))
        (m5 (t/rustMangleIdent "crate"))
        (m6 (t/rustMangleIdent "super"))
        (m7 (t/rustMangleIdent "Self"))
        (m8 (t/rustMangleIdent "user-id"))
        (m9 (t/rustMangleIdent "valid?"))]
    (assert (= m1 "userProfile") "Standard ident preserved")
    (assert (= m2 "r#match") "Reserved keyword match mangled as raw identifier")
    (assert (= m3 "r#type") "Reserved keyword type mangled as raw identifier")
    (assert (= m4 "self_") "Non-raw keyword self mangled with trailing underscore")
    (assert (= m5 "crate_") "Non-raw keyword crate mangled with trailing underscore")
    (assert (= m6 "super_") "Non-raw keyword super mangled with trailing underscore")
    (assert (= m7 "Self_") "Non-raw keyword Self mangled with trailing underscore")
    (assert (= m8 "user_id") "Hyphen replaced with underscore")
    (assert (= m9 "is_valid") "Predicate question mark converted to is_ prefix")
    (refute (= m2 "match") "Must refute unescaped keyword match")
    (refute (= m4 "r#self") "Must refute invalid raw identifier r#self")
    (refute (= m5 "r#crate") "Must refute invalid raw identifier r#crate")
    true)

fn testRustHeader -> Bool
  (let [(h (t/emitRustHeader))]
    (assert (stringContains? h "use std::collections::HashMap;") "Header includes HashMap")
    (assert (stringContains? h "use std::panic::{catch_unwind, AssertUnwindSafe};") "Header includes catch_unwind and AssertUnwindSafe")
    (assert (stringContains? h "use std::ffi::{CString, CStr};") "Header includes CString and CStr")
    (refute (stringContains? h "import Foundation") "Refutes Swift Foundation")
    (refute (stringContains? h "package main") "Refutes Go package main")
    true)

fn testRustBinop -> Bool
  (let [(b1 (t/emitRustBinop "+" "a" "b"))
        (b2 (t/emitRustBinop "==" "x" "y"))
        (b3 (t/emitRustBinop "&&" "c1" "c2"))
        (b4 (t/emitRustBinop "or" "f1" "f2"))
        (b5 (t/emitRustBinop "!=" "u" "v"))]
    (assert (= b1 "(a + b)") "Addition binary op")
    (assert (= b2 "(x == y)") "Equality binary op")
    (assert (= b3 "(c1 && c2)") "Conjunction binary op")
    (assert (= b4 "(f1 || f2)") "Disjunction binary op")
    (assert (= b5 "(u != v)") "Inequality binary op")
    (refute (= b4 "(f1 or f2)") "Refutes Python or")
    true)

fn testRustAtom -> Bool
  (let [(a1 (t/emitRustAtom "true"))
        (a2 (t/emitRustAtom "false"))
        (a3 (t/emitRustAtom "nil"))
        (a4 (t/emitRustAtom "none"))
        (a5 (t/emitRustAtom "\"hello\""))
        (a6 (t/emitRustAtom "42"))]
    (assert (= a1 "true") "true preserved")
    (assert (= a2 "false") "false preserved")
    (assert (= a3 "None") "nil mapped to None")
    (assert (= a4 "None") "none mapped to None")
    (assert (= a5 "\"hello\".to_string()") "string literal gets to_string()")
    (assert (= a6 "42") "number literal preserved")
    (refute (= a3 "nil") "Refutes Lisp nil")
    (refute (= a4 "null") "Refutes JS null")
    true)

fn rsTopExprProbeSource -> String
  "(module rsTopExprProbe :x [main] :i [(asl-parser/ast :a a) (asl-target-rs/emitRust :a r)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (mt (a/parse \"(df f [] -> I64 1) (f)\")\n    ((ok forms) (do (println (r/emitRustSourceFromForms forms \"probe\")) (ok 0)))\n    ((err _) (ok 1)))\n"

fn testTopExprNotSilentlyDropped! -> Bool
  (let [(probePath "asl/packages/asl-target-rs/tests/tmpRsTopExprProbe.asl") (wRes (fileWrite probePath (rsTopExprProbeSource))) (res (processRun (str "asl/host/out/asl-host run " probePath))) (rmRes (pathRemove probePath))] (do (assert (ok? wRes) "probe source must write") (assert (!= res.exitCode 0) (str "emitRustSourceFromForms on a bare top-level expression must fail, got exit " (stringFromInt64 res.exitCode) " stdout " res.stdout)) (assert (stringContains? res.stderr "ERR_RUST_TOPLEVEL_EXPR") (str "failure must name the error, got stderr: " res.stderr)) (assert (ok? rmRes) "probe source must be removed") true))

fn ! runTests -> Bool
  (do
    (assert (testTopExprNotSilentlyDropped!) "testTopExprNotSilentlyDropped must pass")
    (assert (testRustTypes) "testRustTypes must pass")
    (assert (testRustMangle) "testRustMangle must pass")
    (assert (testRustHeader) "testRustHeader must pass")
    (assert (testRustBinop) "testRustBinop must pass")
    (assert (testRustAtom) "testRustAtom must pass")
    true)
