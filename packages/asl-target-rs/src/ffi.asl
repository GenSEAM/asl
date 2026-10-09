(module asl-target-rs/ffi
  :x [emitRustFfiHeader emitExternCDecls emitFfiPanicBoundary emitFfiDeallocators]
  :i [(asl-target-rs/ast :a ast) (asl-target-rs/types :a t)])

fn emitRustFfiHeader -> String
  (str
    "// Sovereign ASL Rust C-ABI FFI Bridge under ADR D130\n"
    "use std::os::raw::c_char;\n"
    "use std::ffi::{CString, CStr};\n"
    "use std::panic::{catch_unwind, AssertUnwindSafe};\n\n"
    "#[repr(C)]\n"
    "pub struct AslBuffer {\n"
    "    pub ptr: *mut u8,\n"
    "    pub len: usize,\n"
    "    pub cap: usize,\n"
    "}\n\n")

fn emitFfiDeallocators -> String
  (str
    "#[no_mangle]\n"
    "pub unsafe extern \"C\" fn asl_free_string(ptr: *mut c_char) {\n"
    "    if ptr.is_null() { return; }\n"
    "    drop(CString::from_raw(ptr));\n"
    "}\n\n"
    "#[no_mangle]\n"
    "pub unsafe extern \"C\" fn asl_free_buffer(buf: AslBuffer) {\n"
    "    if buf.ptr.is_null() { return; }\n"
    "    drop(Vec::from_raw_parts(buf.ptr, buf.len, buf.cap));\n"
    "}\n\n")

fn emitFfiPanicBoundary fnName: String cParams: String retTy: String innerCall: String errorFallback: String -> String
  (let [(mName (t/rustMangleIdent fnName))]
    (str
      "#[no_mangle]\n"
      "pub extern \"C\" fn " mName "(" cParams ") -> " retTy " {\n"
      "    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {\n"
      "        " innerCall "\n"
      "    }));\n"
      "    match res {\n"
      "        Ok(val) => val,\n"
      "        Err(_) => " errorFallback ",\n"
      "    }\n"
      "}\n\n"))

fn emitExternCDecls decls: (List (Pair String String)) -> String
  (let [(lines (map (fn [(p (pair String String))] -> String
                      (let [(name (pairFirst p))
                            (sig (pairSecond p))]
                        (str "    pub fn " (t/rustMangleIdent name) sig ";\n")))
                    decls))]
    (str "extern \"C\" {\n" (stringJoin lines "") "}\n\n"))
