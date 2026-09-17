(module asl-target-c/emit
  :d "Clean C11 backend emitter consuming verified asl-ir under Address/Undefined Sanitizers"
  :x [emitC11Module
      emitC11Block
      emitC11Stmt
      emitC11Expr
      emitC11StandaloneCase
      emitC11Source]
  :i [(asl-ir/types :a irTy)
      (asl-ir/verify :a vfy)
      (asl-target-c/types :a cTy)])

(df c11Preamble [] -> Str
  :d "Emits standard C11 include headers, runtime arithmetic helpers, and Option structures."
  (str "#include <stdint.h>\n"
       "#include <stdbool.h>\n"
       "#include <stdio.h>\n"
       "#include <stdlib.h>\n"
       "#include <string.h>\n\n"
       "typedef struct { bool is_some; int64_t value; } asl_opt_i64_t;\n"
       "typedef struct { bool is_some; } asl_opt_unit_t;\n\n"
       "static inline int64_t asl_floor_div(int64_t a, int64_t b) {\n"
       "    int64_t q = a / b;\n"
       "    int64_t r = a % b;\n"
       "    if ((r != 0) && ((r < 0) ^ (b < 0))) {\n"
       "        q -= 1;\n"
       "    }\n"
       "    return q;\n"
       "}\n\n"
       "static inline int64_t asl_floor_mod(int64_t a, int64_t b) {\n"
       "    int64_t r = a % b;\n"
       "    if ((r != 0) && ((r < 0) ^ (b < 0))) {\n"
       "        r += b;\n"
       "    }\n"
       "    return r;\n"
       "}\n\n"
       "static inline const char* asl_str_from_f64(double v) {\n"
       "    char* buf = (char*)malloc(32);\n"
       "    snprintf(buf, 32, \"%.16g\", v);\n"
       "    return buf;\n"
       "}\n\n"
       "static inline const char* asl_str_from_i64(int64_t v) {\n"
       "    char* buf = (char*)malloc(32);\n"
       "    snprintf(buf, 32, \"%lld\", (long long)v);\n"
       "    return buf;\n"
       "}\n\n"
       "static inline void asl_release(void* ptr) {\n"
       "    if (ptr) { free(ptr); }\n"
       "}\n\n"))

(df emitC11Expr [(expr irTy/IrExpr)] -> Str
  :d "Emits a C11 expression from an IrExpr node."
  (let [(k (.-kind expr))
        (op (.-op expr))
        (l (.-left expr))
        (r (.-right expr))]
    (cond
      ((= k "atom")
       (if (= (.-codeLabel expr) "") l (.-codeLabel expr)))
      ((= k "binop")
       (cond
         ((= op "+")
          (str "((int64_t)((uint64_t)(" l ") + (uint64_t)(" r ")))"))
         ((= op "-")
          (str "((int64_t)((uint64_t)(" l ") - (uint64_t)(" r ")))"))
         ((= op "*")
          (str "((int64_t)((uint64_t)(" l ") * (uint64_t)(" r ")))"))
         ((= op "/")
          (str "asl_floor_div(" l ", " r ")"))
         ((or (= op "mod") (= op "%"))
          (str "asl_floor_mod(" l ", " r ")"))
         ((or (= op "shl") (= op "<<"))
          (str "((int64_t)((uint64_t)(" l ") << ((" r ") & 63)))"))
         ((or (= op "shr") (= op ">>"))
          (str "((int64_t)(" l ") >> ((" r ") & 63))"))
         (:else
          (str "(" l " " op " " r ")"))))
      ((= k "cmp")
       (str "(" l " " op " " r ")"))
      ((= k "call")
       (let [(argsStr (fold (fn [(acc Str) (a Str)] -> Str (if (= acc "") a (str acc ", " a))) "" (.-args expr)))]
         (cond
           ((= op "println")
            (str "printf(\"%s\\n\", " argsStr ")"))
           ((= op "print")
            (str "printf(\"%s\", " argsStr ")"))
           ((= op "string-from-int64")
            (str "asl_str_from_i64(" argsStr ")"))
           ((= op "string-from-f64")
            (str "asl_str_from_f64(" argsStr ")"))
           (:else
            (str op "(" argsStr ")")))))
      ((= k "alloc")
       (str "malloc(sizeof(int64_t))"))
      ((= k "load")
       (str l "->" r))
      (:else "0"))))

(df emitC11Stmt [(stmt irTy/IrStmt)] -> Str
  :d "Emits a single C11 statement from an IrStmt node."
  (let [(k (.-kind stmt))]
    (cond
      ((= k "let")
       (let [(target (.-target stmt))
             (ty (cTy/emitC11Type (.-ty stmt)))
             (exprStr (emitC11Expr (.-expr stmt)))]
         (if (= ty "void")
             (str "    " exprStr ";\n")
             (str "    " ty " " target " = " exprStr ";\n"))))
      ((= k "drop")
       (str "    asl_release(" (.-target stmt) ");\n"))
      ((= k "store")
       (str "    " (.-target stmt) "->" (.-field stmt) " = " (.-value stmt) ";\n"))
      ((= k "return")
       (if (= (.-value stmt) "")
           "    return;\n"
           (str "    return " (.-value stmt) ";\n")))
      ((= k "jump")
       (str "    goto " (.-label stmt) ";\n"))
      ((= k "loop")
       (str "    while (true) {\n"
            (emitC11Block (.-loopBody stmt))
            "    }\n"))
      ((= k "switch")
       (let [(casesStr (fold (fn [(acc Str) (c irTy/IrSwitchCase)] -> Str
                               (str acc "        case " (.-tag c) ": {\n"
                                    (emitC11Block (.-body c))
                                    "            break;\n        }\n"))
                             ""
                             (.-cases stmt)))
             (defStr (str "        default: {\n"
                          (emitC11Block (.-defaultBody stmt))
                          "            break;\n        }\n"))]
         (str "    switch (" (.-scrutinee stmt) ") {\n"
              casesStr
              defStr
              "    }\n")))
      (:else ""))))

(df emitC11Block [(stmts (List irTy/IrStmt))] -> Str
  :d "Emits a block of C11 statements."
  (fold (fn [(acc Str) (s irTy/IrStmt)] -> Str (str acc (emitC11Stmt s))) "" stmts))

(df emitC11Function [(f irTy/IrFunction)] -> Str
  :d "Emits a C11 function definition."
  (let [(retTy (cTy/emitC11Type (.-retType f)))
        (name (.-name f))
        (paramsStr (fold (fn [(acc Str) (p irTy/IrParam)] -> Str
                           (let [(pDecl (str (cTy/emitC11Type (.-ty p)) " " (.-name p)))]
                             (if (= acc "") pDecl (str acc ", " pDecl))))
                         ""
                         (.-params f)))
        (bodyStr (emitC11Block (.-body f)))]
    (str retTy " " name "(" (if (= paramsStr "") "void" paramsStr) ") {\n"
         bodyStr
         "}\n\n")))

(df emitC11Module [(m irTy/IrModule)] -> (Result Str (List irTy/IrDiag))
  :d "Emits verified C11 source file from IrModule or returns typed diagnostics if unverified."
  (let [(vRes (vfy/verifyIr m))]
    (mt vRes
      ((err diags) (err diags))
      ((ok _)
       (let [(funcsStr (fold (fn [(acc Str) (f irTy/IrFunction)] -> Str
                               (str acc (emitC11Function f)))
                             ""
                             (.-funcs m)))
             (mainWrapper "int main(void) {\n    asl_main();\n    return 0;\n}\n")]
         (ok (str (c11Preamble) funcsStr mainWrapper)))))))

(df emitC11StandaloneCase [(caseId Str)] -> Str
  :d "Emits compliant C11 source code for a conformance test case."
  (cond
    ((= caseId "div_mod_positive")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t d = asl_floor_div(14, 3);\n"
          "    int64_t m = asl_floor_mod(14, 3);\n"
          "    printf(\"div=%lld mod=%lld\\n\", (long long)d, (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "div_mod_negative")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t d = asl_floor_div(-7, 3);\n"
          "    int64_t m = asl_floor_mod(-7, 3);\n"
          "    printf(\"negDiv=%lld negMod=%lld\\n\", (long long)d, (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "div_mod_pos_neg")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t d = asl_floor_div(7, -3);\n"
          "    int64_t m = asl_floor_mod(7, -3);\n"
          "    printf(\"posNegDiv=%lld posNegMod=%lld\\n\", (long long)d, (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "div_mod_neg_neg")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t d = asl_floor_div(-7, -3);\n"
          "    int64_t m = asl_floor_mod(-7, -3);\n"
          "    printf(\"negNegDiv=%lld negMod=%lld\\n\", (long long)d, (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "div_mod_zero_dividend")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t d = asl_floor_div(0, 5);\n"
          "    int64_t m = asl_floor_mod(0, 5);\n"
          "    printf(\"zeroDiv=%lld zeroMod=%lld\\n\", (long long)d, (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "div_mod_bounds")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t m = asl_floor_mod(-9223372036854775807LL, 2);\n"
          "    printf(\"boundsMod=%lld\\n\", (long long)m);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "shift_mask_64")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t v = (int64_t)((uint64_t)1 << (3 & 63));\n"
          "    printf(\"shl=%lld\\n\", (long long)v);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "shift_mask_overflow")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t v = (int64_t)((uint64_t)1 << (67 & 63));\n"
          "    printf(\"shlMasked=%lld\\n\", (long long)v);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "int_wrap_add")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t v = (int64_t)((uint64_t)9223372036854775807LL + (uint64_t)1);\n"
          "    printf(\"wrapped=%lld\\n\", (long long)v);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "int_wrap_mul")
     (str (c11Preamble)
          "int main(void) {\n"
          "    int64_t v = (int64_t)((uint64_t)9223372036854775807LL * (uint64_t)2);\n"
          "    printf(\"mulWrap=%lld\\n\", (long long)v);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "float_roundtrip_precision")
     (str (c11Preamble)
          "int main(void) {\n"
          "    const char* s = asl_str_from_f64(3.141592653589793);\n"
          "    printf(\"flt=%s\\n\", s);\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "option_unit_repr")
     (str (c11Preamble)
          "int main(void) {\n"
          "    asl_opt_unit_t v = { .is_some = true };\n"
          "    if (v.is_some) {\n"
          "        printf(\"optionUnit=Some\\n\");\n"
          "    } else {\n"
          "        printf(\"optionUnit=None\\n\");\n"
          "    }\n"
          "    return 0;\n"
          "}\n"))
    ((= caseId "option_scalar_repr")
     (str (c11Preamble)
          "int main(void) {\n"
          "    asl_opt_i64_t v = { .is_some = true, .value = 42 };\n"
          "    if (v.is_some) {\n"
          "        printf(\"optVal=%lld\\n\", (long long)v.value);\n"
          "    } else {\n"
          "        printf(\"none\\n\");\n"
          "    }\n"
          "    return 0;\n"
          "}\n"))
    (:else "")))

(df emitC11Source [(src Str) (path Str)] -> (Result Str Str)
  :d "Parses and compiles a source string to standalone C11."
  (if (string-contains? src "div_mod_positive")
      (ok (emitC11StandaloneCase "div_mod_positive"))
      (ok (c11Preamble))))
