(module asl-target-c/types :x [emitC11Type emitC11Closure emitC11Panic] :i [(asl-ir/types :a irTy)])

fn emitC11Type ty: irTy/IrType -> Str
  (let [(k ty.kind) (r ty.repr)] (cond ((= k "i64") "int64_t") ((= k "i32") "int32_t") ((= k "f64") "double") ((= k "bool") "bool") ((= k "unit") "void") ((= k "str") "const char*") ((= k "buf") "asl_buf_t") ((= k "option") (if (= r "tagged") "asl_opt_i64_t" "void*")) ((= k "closure") "asl_closure_t") ((= k "adt") "void*") (else "int64_t")))

fn emitC11Closure name: Str envFields: (List Str) -> Str
  (let [(fieldsStr (fold (fn [(acc Str) (f Str)] -> Str (str acc "    int64_t " f ";\n")) "" envFields))] (str "typedef struct {\n" fieldsStr "} asl_env_" name "_t;\n"))

fn emitC11Panic code: Int64 msg: Str -> Str
  (str "fprintf(stderr, \"PANIC: " msg "\\n\");\nexit(" (stringFromInt64 code) ");\n")
