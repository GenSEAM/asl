(module asl-target-rs/types
  :x [emitRustType rustMangleIdent emitRustHeader emitRustBinop emitRustAtom isRustKeyword? isNonRawKeyword? sliceOr]
  :i [(asl-checker/types :a ty)])

fn sliceOr s: String start: Int64 end: Int64 fallback: String -> String
  (optionOr (stringSlice s start end) fallback)

fn isNonRawKeyword? s: String -> Bool
  (or (or (= s "self") (= s "crate")) (or (= s "super") (= s "Self")))

fn isRustKeyword? s: String -> Bool
  (or (isNonRawKeyword? s) (listContains? (list "type" "match" "fn" "let" "loop" "move" "ref" "impl" "mod" "use" "const" "static" "struct" "enum" "trait" "where" "for" "while" "return" "break" "continue" "as" "in" "async" "await" "dyn" "try" "unsafe" "pub" "mut" "true" "false") s))

fn rustMangleIdent s: String -> String
  (let [(sLen (stringLength s))
        (base1 (if (and (> sLen 1) (stringEndsWith? s "?")) (str "is_" (sliceOr s 0 (- sLen 1) "")) s))
        (len1 (stringLength base1))
        (base2 (if (and (> len1 1) (stringEndsWith? base1 "!")) (str (sliceOr base1 0 (- len1 1) "") "_mut") base1))
        (snaked (stringReplace base2 "-" "_"))]
    (cond
      ((isNonRawKeyword? snaked) (str snaked "_"))
      ((isRustKeyword? snaked) (str "r#" snaked))
      (else snaked)))

fn primitiveRustType name: String -> (Option String)
  (cond
    ((or (= name "Int") (or (= name "Int64") (= name "I64"))) (some "i64"))
    ((or (= name "Int32") (= name "I32")) (some "i32"))
    ((or (= name "Int16") (= name "I16")) (some "i16"))
    ((or (= name "Int8") (= name "I8")) (some "i8"))
    ((or (= name "UInt64") (= name "U64")) (some "u64"))
    ((or (= name "UInt32") (= name "U32")) (some "u32"))
    ((or (= name "Float") (or (= name "Float64") (or (= name "Double") (= name "F64")))) (some "f64"))
    ((or (= name "Float32") (= name "F32")) (some "f32"))
    ((or (= name "String") (= name "Str")) (some "String"))
    ((or (= name "Bool") (= name "Boolean")) (some "bool"))
    ((or (= name "Void") (or (= name "Unit") (= name "()"))) (some "()"))
    ((= name "Bytes") (some "Vec<u8>"))
    (else (none)))

fn getArgType args: (List ty/Type) idx: I64 -> String
  (emitRustType (optionOr (listGet args idx) (ty/tyCon "Unit" (list) (none) (none))))

fn emitRustType t: ty/Type -> String
  (mt t
    ((ty/tyVar id kind)
      (cond
        ((= kind "int") "i64")
        ((= kind "num") "f64")
        (else (str "T" (stringFromInt64 id)))))
    ((ty/tyFun params ret)
      (let [(paramTys (stringJoin (map emitRustType params) ", "))
            (retTy (emitRustType ret))]
        (str "Box<dyn Fn(" paramTys ") -> " retTy ">")))
    ((ty/tyCon name args modOpt shownOpt)
      (let [(prim (primitiveRustType name))]
        (mt prim
          ((some p) p)
          ((none)
            (cond
              ((= name "List")
                (if (> (listLength args) 0) (str "Vec<" (getArgType args 0) ">") "Vec<()>"))
              ((= name "Option")
                (if (> (listLength args) 0) (str "Option<" (getArgType args 0) ">") "Option<()>"))
              ((= name "Result")
                (if (>= (listLength args) 2)
                  (str "Result<" (getArgType args 0) ", " (getArgType args 1) ">")
                  "Result<(), String>"))
              ((= name "Map")
                (if (>= (listLength args) 2)
                  (str "std::collections::HashMap<" (getArgType args 0) ", " (getArgType args 1) ">")
                  "std::collections::HashMap<String, String>"))
              ((= name "Pair")
                (if (>= (listLength args) 2)
                  (str "(" (getArgType args 0) ", " (getArgType args 1) ")")
                  "((), ())"))
              (else
                (let [(cleanName (rustMangleIdent name))]
                  (if (> (listLength args) 0)
                    (str cleanName "<" (stringJoin (map emitRustType args) ", ") ">")
                    cleanName)))))))))

fn emitRustHeader -> String
  (str
    "// Emitted by AgentScript (asl-target-rs) under ADR D130\n"
    "#![allow(dead_code, unused_variables, unused_mut, unused_parens, non_snake_case)]\n"
    "use std::collections::HashMap;\n"
    "use std::panic::{catch_unwind, AssertUnwindSafe};\n"
    "use std::ffi::{CString, CStr};\n"
    "use std::os::raw::c_char;\n\n")

fn emitRustBinop op: String lhs: String rhs: String -> String
  (cond
    ((= op "+") (str "(" lhs " + " rhs ")"))
    ((= op "-") (str "(" lhs " - " rhs ")"))
    ((= op "*") (str "(" lhs " * " rhs ")"))
    ((= op "/") (str "(" lhs " / " rhs ")"))
    ((= op "%") (str "(" lhs " % " rhs ")"))
    ((= op "==") (str "(" lhs " == " rhs ")"))
    ((= op "!=") (str "(" lhs " != " rhs ")"))
    ((= op "<") (str "(" lhs " < " rhs ")"))
    ((= op "<=") (str "(" lhs " <= " rhs ")"))
    ((= op ">") (str "(" lhs " > " rhs ")"))
    ((= op ">=") (str "(" lhs " >= " rhs ")"))
    ((or (= op "&&") (= op "and")) (str "(" lhs " && " rhs ")"))
    ((or (= op "||") (= op "or")) (str "(" lhs " || " rhs ")"))
    (else (str "(" op "(" lhs ", " rhs "))")))

fn emitRustAtom atom: String -> String
  (cond
    ((or (= atom "nil") (= atom "none")) "None")
    ((= atom "true") "true")
    ((= atom "false") "false")
    ((stringStartsWith? atom "\"") (str atom ".to_string()"))
    (else atom))
