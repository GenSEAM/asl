(module asl-target-llvm/types :x [emitLlvmType emitLlvmClosure emitLlvmPanic emitLlvmTargetTriple] :i [(asl-ir/types :a irTy)])

fn emitLlvmType ty: irTy/IrType -> Str
  (let [(k ty.kind) (r ty.repr)] (cond ((= k "i64") "i64") ((= k "i32") "i32") ((= k "f64") "double") ((= k "bool") "i1") ((= k "unit") "void") ((= k "str") "ptr") ((= k "buf") "ptr") ((= k "list") "ptr") ((= k "map") "ptr") ((= k "option") (if (= r "tagged") "{ i1, i64 }" "ptr")) ((= k "closure") "{ ptr, ptr }") ((= k "adt") "ptr") (else "i64")))

fn emitLlvmClosure name: Str envFields: (List Str) -> Str
  (let [(fieldsStr (fold (fn [(acc Str) (f Str)] -> Str (let [(ft (cond ((stringEndsWith? f "ptr") "ptr") ((stringEndsWith? f "double") "double") ((stringEndsWith? f "f64") "double") ((stringEndsWith? f "i1") "i1") ((stringEndsWith? f "bool") "i1") ((stringEndsWith? f "i32") "i32") (else "i64")))] (if (= acc "") ft (str acc ", " ft)))) "" envFields))] (str "%asl_env_" name "_t = type { " fieldsStr " }\n"))

fn emitLlvmPanic code: Int64 msg: Str -> Str
  (str "    call void @asl_panic(i64 " (stringFromInt64 code) ")\n    unreachable\n")

fn emitLlvmTargetTriple target: Str -> Str
  (cond
    ((or (= target "arm64-apple-darwin") (or (= target "arm64-apple-macosx") (or (= target "macos-arm64") (= target "macos-aarch64"))))
      "target triple = \"arm64-apple-macosx15.0.0\"\n")
    ((or (= target "x86_64-apple-darwin") (or (= target "x86_64-apple-macosx") (= target "macos-x64")))
      "target triple = \"x86_64-apple-macosx15.0.0\"\n")
    ((or (= target "x86_64-unknown-linux-gnu") (or (= target "linux-x64") (= target "linux-x86_64")))
      "target triple = \"x86_64-unknown-linux-gnu\"\n")
    ((or (= target "aarch64-unknown-linux-gnu") (or (= target "linux-arm64") (= target "linux-aarch64")))
      "target triple = \"aarch64-unknown-linux-gnu\"\n")
    ((or (= target "x86_64-pc-windows-msvc") (or (= target "windows-x64") (= target "windows-x86_64")))
      "target triple = \"x86_64-pc-windows-msvc\"\n")
    ((or (= target "wasm32-unknown-wasi") (= target "wasm32-wasi"))
      "target triple = \"wasm32-unknown-wasi\"\n")
    ((or (= target "wasm32-unknown-unknown") (= target "browser"))
      "target triple = \"wasm32-unknown-unknown\"\n")
    (else ""))
