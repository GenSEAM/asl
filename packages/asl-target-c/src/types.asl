(module asl-target-c/types
  :d "C11 backend type mapping, closure environment synthesis, and panic generation"
  :x [emitC11Type
      emitC11Closure
      emitC11Panic]
  :i [(asl-ir/types :a irTy)])

(df emitC11Type [(ty irTy/IrType)] -> Str
  :d "Maps an IrType node to its corresponding C11 type signature."
  (let [(k (.-kind ty))
        (r (.-repr ty))]
    (cond
      ((= k "i64") "int64_t")
      ((= k "i32") "int32_t")
      ((= k "f64") "double")
      ((= k "bool") "bool")
      ((= k "unit") "void")
      ((= k "str") "const char*")
      ((= k "buf") "asl_buf_t")
      ((= k "option")
       (if (= r "tagged")
           "asl_opt_i64_t"
           "void*"))
      ((= k "closure") "asl_closure_t")
      ((= k "adt") "void*")
      (:else "int64_t"))))

(df emitC11Closure [(name Str) (envFields (List Str))] -> Str
  :d "Synthesizes a C11 closure environment struct definition."
  (let [(fieldsStr (fold (fn [(acc Str) (f Str)] -> Str (str acc "    int64_t " f ";\n")) "" envFields))]
    (str "typedef struct {\n"
         fieldsStr
         "} asl_env_" name "_t;\n")))

(df emitC11Panic [(code Int64) (msg Str)] -> Str
  :d "Emits a C11 panic invocation terminating execution with fixed exit code."
  (str "fprintf(stderr, \"PANIC: " msg "\\n\");\nexit(" (string-from-int64 code) ");\n"))
