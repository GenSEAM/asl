(module asl-target-c/emit :x [emitC11Module emitC11Block emitC11Stmt emitC11Expr emitC11StandaloneCase emitC11Source emitC11SourceWith c11SMainWrapper] :i [(asl-ir/types :a irTy) (asl-ir/verify :a vfy) (asl-ir/lower :a low) (asl-ir/link :a lk) (asl-target-c/types :a cTy)])

fn c11Preamble -> Str
  (str "#include <stdint.h>\n" "#include <stdbool.h>\n" "#include <stdio.h>\n" "#include <stdlib.h>\n" "#include <string.h>\n\n" "typedef struct { bool is_some; int64_t value; } asl_opt_i64_t;\n" "typedef struct { bool is_some; } asl_opt_unit_t;\n\n" "static inline int64_t asl_floor_div(int64_t a, int64_t b) {\n" "    if (a == INT64_MIN && b == -1) { return INT64_MIN; }\n" "    int64_t q = a / b;\n" "    int64_t r = a % b;\n" "    if ((r != 0) && ((r < 0) ^ (b < 0))) {\n" "        q -= 1;\n" "    }\n" "    return q;\n" "}\n\n" "static inline int64_t asl_floor_mod(int64_t a, int64_t b) {\n" "    if (b == -1) { return 0; }\n" "    int64_t r = a % b;\n" "    if ((r != 0) && ((r < 0) ^ (b < 0))) {\n" "        r += b;\n" "    }\n" "    return r;\n" "}\n\n" "static inline const char* asl_str_from_f64(double v) {\n" "    char* buf = (char*)malloc(32);\n" "    snprintf(buf, 32, \"%.16g\", v);\n" "    return buf;\n" "}\n\n" "static inline const char* asl_str_from_i64(int64_t v) {\n" "    char* buf = (char*)malloc(32);\n" "    snprintf(buf, 32, \"%lld\", (long long)v);\n" "    return buf;\n" "}\n\n" "static inline void asl_release(void* ptr) {\n" "    if (ptr) { free(ptr); }\n" "}\n\n")

fn emitC11Expr expr: irTy/IrExpr -> Str
  (let [(k expr.kind) (op expr.op) (l expr.left) (r expr.right)] (cond ((= k "atom") (if (= expr.codeLabel "") l expr.codeLabel)) ((= k "binop") (cond ((= op "+") (str "((int64_t)((uint64_t)(" l ") + (uint64_t)(" r ")))")) ((= op "-") (str "((int64_t)((uint64_t)(" l ") - (uint64_t)(" r ")))")) ((= op "*") (str "((int64_t)((uint64_t)(" l ") * (uint64_t)(" r ")))")) ((= op "/") (str "asl_floor_div(" l ", " r ")")) ((or (= op "mod") (= op "%")) (str "asl_floor_mod(" l ", " r ")")) ((or (= op "shl") (= op "<<")) (str "((int64_t)((uint64_t)(" l ") << ((" r ") & 63)))")) ((or (= op "shr") (= op ">>")) (str "((int64_t)(" l ") >> ((" r ") & 63))")) (else (str "(" l " " op " " r ")")))) ((= k "cmp") (str "(" l " " op " " r ")")) ((= k "call") (let [(argsStr (fold (fn [(acc Str) (a Str)] -> Str (if (= acc "") a (str acc ", " a))) "" expr.args))] (cond ((= op "println") (str "printf(\"%s\\n\", " argsStr ")")) ((= op "print") (str "printf(\"%s\", " argsStr ")")) ((= op "stringFromInt64") (str "asl_str_from_i64(" argsStr ")")) ((= op "string-from-f64") (str "asl_str_from_f64(" argsStr ")")) (else (str op "(" argsStr ")"))))) ((= k "alloc") (str "malloc(sizeof(int64_t))")) ((= k "load") (str l "->" r)) (else "0")))

fn emitC11Stmt stmt: irTy/IrStmt -> Str
  (let [(k stmt.kind)] (cond ((= k "let") (let [(target stmt.target) (ty (cTy/emitC11Type stmt.ty)) (exprStr (emitC11Expr stmt.expr))] (if (= ty "void") (str "    " exprStr ";\n") (str "    " ty " " target " = " exprStr ";\n")))) ((= k "drop") (str "    asl_release(" stmt.target ");\n")) ((= k "store") (str "    " stmt.target "->" stmt.field " = " stmt.value ";\n")) ((= k "return") (if (= stmt.value "") "    return;\n" (str "    return " stmt.value ";\n"))) ((= k "jump") (str "    goto " stmt.label ";\n")) ((= k "loop") (str "    while (true) {\n" (emitC11Block stmt.loopBody) "    }\n")) ((= k "switch") (let [(casesStr (fold (fn [(acc Str) (c irTy/IrSwitchCase)] -> Str (str acc "        case " c.tag ": {\n" (emitC11Block c.body) "            break;\n        }\n")) "" stmt.cases)) (defStr (str "        default: {\n" (emitC11Block stmt.defaultBody) "            break;\n        }\n"))] (str "    switch (" stmt.scrutinee ") {\n" casesStr defStr "    }\n"))) (else "")))

fn emitC11Block stmts: (List irTy/IrStmt) -> Str
  (fold (fn [(acc Str) (s irTy/IrStmt)] -> Str (str acc (emitC11Stmt s))) "" stmts)

fn emitC11Function f: irTy/IrFunction -> Str
  (let [(retTy (cTy/emitC11Type f.retType)) (name f.name) (paramsStr (fold (fn [(acc Str) (p irTy/IrParam)] -> Str (let [(pDecl (str (cTy/emitC11Type p.ty) " " p.name))] (if (= acc "") pDecl (str acc ", " pDecl)))) "" f.params)) (bodyStr (emitC11Block f.body))] (str retTy " " name "(" (if (= paramsStr "") "void" paramsStr) ") {\n" bodyStr "}\n\n"))

fn emitC11Module m: irTy/IrModule -> (Result Str (List irTy/IrDiag))
  (let [(vRes (vfy/verifyIr m))] (mt vRes ((err diags) (err diags)) ((ok _) (let [(funcsStr (fold (fn [(acc Str) (f irTy/IrFunction)] -> Str (str acc (emitC11Function f))) "" m.funcs)) (mainWrapper "int main(void) {\n    asl_main();\n    return 0;\n}\n")] (ok (str (c11Preamble) funcsStr mainWrapper))))))

fn emitC11StandaloneCase caseId: Str -> Str
  (cond ((= caseId "div_mod_positive") (str (c11Preamble) "int main(void) {\n" "    int64_t d = asl_floor_div(14, 3);\n" "    int64_t m = asl_floor_mod(14, 3);\n" "    printf(\"div=%lld mod=%lld\\n\", (long long)d, (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "div_mod_negative") (str (c11Preamble) "int main(void) {\n" "    int64_t d = asl_floor_div(-7, 3);\n" "    int64_t m = asl_floor_mod(-7, 3);\n" "    printf(\"negDiv=%lld negMod=%lld\\n\", (long long)d, (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "div_mod_pos_neg") (str (c11Preamble) "int main(void) {\n" "    int64_t d = asl_floor_div(7, -3);\n" "    int64_t m = asl_floor_mod(7, -3);\n" "    printf(\"posNegDiv=%lld posNegMod=%lld\\n\", (long long)d, (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "div_mod_neg_neg") (str (c11Preamble) "int main(void) {\n" "    int64_t d = asl_floor_div(-7, -3);\n" "    int64_t m = asl_floor_mod(-7, -3);\n" "    printf(\"negNegDiv=%lld negMod=%lld\\n\", (long long)d, (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "div_mod_zero_dividend") (str (c11Preamble) "int main(void) {\n" "    int64_t d = asl_floor_div(0, 5);\n" "    int64_t m = asl_floor_mod(0, 5);\n" "    printf(\"zeroDiv=%lld zeroMod=%lld\\n\", (long long)d, (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "div_mod_bounds") (str (c11Preamble) "int main(void) {\n" "    int64_t m = asl_floor_mod(-9223372036854775807LL, 2);\n" "    printf(\"boundsMod=%lld\\n\", (long long)m);\n" "    return 0;\n" "}\n")) ((= caseId "shift_mask_64") (str (c11Preamble) "int main(void) {\n" "    int64_t v = (int64_t)((uint64_t)1 << (3 & 63));\n" "    printf(\"shl=%lld\\n\", (long long)v);\n" "    return 0;\n" "}\n")) ((= caseId "shift_mask_overflow") (str (c11Preamble) "int main(void) {\n" "    int64_t v = (int64_t)((uint64_t)1 << (67 & 63));\n" "    printf(\"shlMasked=%lld\\n\", (long long)v);\n" "    return 0;\n" "}\n")) ((= caseId "int_wrap_add") (str (c11Preamble) "int main(void) {\n" "    int64_t v = (int64_t)((uint64_t)9223372036854775807LL + (uint64_t)1);\n" "    printf(\"wrapped=%lld\\n\", (long long)v);\n" "    return 0;\n" "}\n")) ((= caseId "int_wrap_mul") (str (c11Preamble) "int main(void) {\n" "    int64_t v = (int64_t)((uint64_t)9223372036854775807LL * (uint64_t)2);\n" "    printf(\"mulWrap=%lld\\n\", (long long)v);\n" "    return 0;\n" "}\n")) ((= caseId "float_roundtrip_precision") (str (c11Preamble) "int main(void) {\n" "    const char* s = asl_str_from_f64(3.141592653589793);\n" "    printf(\"flt=%s\\n\", s);\n" "    return 0;\n" "}\n")) ((= caseId "option_unit_repr") (str (c11Preamble) "int main(void) {\n" "    asl_opt_unit_t v = { .is_some = true };\n" "    if (v.is_some) {\n" "        printf(\"optionUnit=Some\\n\");\n" "    } else {\n" "        printf(\"optionUnit=None\\n\");\n" "    }\n" "    return 0;\n" "}\n")) ((= caseId "option_scalar_repr") (str (c11Preamble) "int main(void) {\n" "    asl_opt_i64_t v = { .is_some = true, .value = 42 };\n" "    if (v.is_some) {\n" "        printf(\"optVal=%lld\\n\", (long long)v.value);\n" "    } else {\n" "        printf(\"none\\n\");\n" "    }\n" "    return 0;\n" "}\n")) (else ""))


(schema C11SEnv (:f functions (Map Str irTy/SsaFunction)) (:f types (Map Str (List irTy/SsaVariant))))

fn c11SIdentByte? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122)) (or (= c 95) (and (>= c 48) (<= c 57)))))

fn c11SHexDigit n: Int64 -> Str
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn c11SHexByte n: Int64 -> Str
  (str (c11SHexDigit (/ n 16)) (c11SHexDigit (mod n 16)))

fn c11SEsc s: Str -> Str
  (let [(bs (stringToBytes s)) (n (stringLength s))]
    (stringJoin (map (fn [(i Int64)] -> Str
                        (let [(c (bytesGet bs i))]
                          (if (c11SIdentByte? c) (optionOr (stringSlice s i (+ i 1)) "_") (str "_" (c11SHexByte c)))))
                      (range 0 n)) ""))

fn c11SVal name: Str -> Str (str "v_" (c11SEsc name))
fn c11SFn name: Str -> Str (if (= name "main") "asl_main_fn" (str "fn_" (c11SEsc name)))
fn c11SLabel name: Str -> Str (str "L_" (c11SEsc name))
fn c11SGlobal name: Str -> Str (str "g_" (c11SEsc name))
fn c11SCode name: Str -> Str (str "code_" (c11SEsc name))
fn c11SInit name: Str -> Str (str "asl_init_" (c11SEsc name))

fn c11SType t: irTy/SsaTy -> Str
  (mt t ((irTy/tyVal) "AslVal") ((irTy/tyRec _) "AslVal") ((irTy/tyI64) "int64_t") ((irTy/tyF64) "double") ((irTy/tyI1) "bool") ((irTy/tyPtr) "void*") ((irTy/tyI32) "int32_t"))

fn c11SOctDigit n: Int64 -> Str
  (optionOr (stringSlice "01234567" n (+ n 1)) "0")

fn c11SOct3 n: Int64 -> Str
  (str (c11SOctDigit (mod (/ n 64) 8)) (c11SOctDigit (mod (/ n 8) 8)) (c11SOctDigit (mod n 8)))

fn c11SStrLit s: Str -> Str
  (let [(bs (stringToBytes s)) (n (stringLength s))]
    (str "\"" (stringJoin (map (fn [(i Int64)] -> Str
                                  (let [(c (bytesGet bs i)) (ch (optionOr (stringSlice s i (+ i 1)) ""))]
                                    (cond
                                      ((= ch "\"") "\\\"")
                                      ((= ch "\\") "\\\\")
                                      ((= c 10) "\\n")
                                      ((= c 9) "\\t")
                                      ((= c 13) "\\r")
                                      ((and (>= c 32) (<= c 126)) ch)
                                      (else (str "\\" (c11SOct3 c))))))
                                (range 0 n)) "") "\""))

fn c11SFloatLit x: Float64 -> Str
  (let [(s (stringFromFloat64 x))]
    (cond
      ((= s "inf") "__builtin_inf()")
      ((= s "-inf") "(-__builtin_inf())")
      ((or (= s "nan") (= s "-nan")) "__builtin_nan(\"\")")
      (else s)))

fn c11SArrayLit ty: Str items: (List Str) -> Str
  (if (listEmpty? items) (str "(" ty "*)0") (str "(" ty "[]){" (stringJoin items ", ") "}"))

fn c11SRefs args: (List Str) -> (List Str) (map c11SVal args)

fn c11SVariantsOf env: C11SEnv typeName: Str -> (List Str)
  (map (fn [(v irTy/SsaVariant)] -> Str v.name) (optionOr (mapGet env.types typeName) (list)))

fn c11SVariantTag env: C11SEnv typeName: Str variant: Str -> Int64
  (optionOr (listIndexOf (c11SVariantsOf env typeName) variant) 0)

fn c11SClosureArity env: C11SEnv callee: Str -> Int64
  (mt (mapGet env.functions callee) ((some f) (listLength f.params)) ((none) 0))

fn c11SConst strings: (List Str) t: irTy/SsaTy c: irTy/SsaConst -> Str
  (let [(tn (irTy/ssaTyName t))]
    (mt c
      ((irTy/constInt n) (if (= tn "i64") (str "INT64_C(" n ")") (str "asl_rt_int(INT64_C(" n "))")))
      ((irTy/constFloat x) (if (= tn "f64") (c11SFloatLit x) (str "asl_rt_float(" (c11SFloatLit x) ")")))
      ((irTy/constBool b) (if (= tn "i1") (if b "true" "false") (str "asl_rt_bool(" (if b "1" "0") ")")))
      ((irTy/constStr i) (let [(s (optionOr (listGet strings i) ""))] (str "asl_rt_str(" (c11SStrLit s) ", INT64_C(" (stringLength s) "))")))
      ((irTy/constUnit) "asl_rt_unit()")
      ((irTy/constKeyword n) (str "asl_rt_keyword(" (c11SStrLit n) ")"))
      ((irTy/constSymbol n) (str "asl_rt_symbol(" (c11SStrLit n) ")"))))

fn c11SBoxExpr srcTy: irTy/SsaTy v: Str -> Str
  (mt srcTy
    ((irTy/tyI64) (str "asl_rt_int(" v ")"))
    ((irTy/tyF64) (str "asl_rt_float(" v ")"))
    ((irTy/tyI1) (str "asl_rt_bool(" v " ? 1 : 0)"))
    (_ v))

fn c11SUnboxExpr dstTy: irTy/SsaTy v: Str -> Str
  (mt dstTy
    ((irTy/tyI64) (str "asl_rt_unbox_int(" v ")"))
    ((irTy/tyF64) (str "asl_rt_unbox_float(" v ")"))
    ((irTy/tyI1) (str "asl_rt_unbox_bool(" v ")"))
    (_ v))

fn c11BuiltinSym b: irTy/SsaBuiltin -> Str
  (if (= b.kind "wrap") (str "asl_rt_b_" b.symbol) b.symbol)

fn c11WrapBuiltinEntries -> (List irTy/SsaBuiltin)
  (filter (fn [(b irTy/SsaBuiltin)] -> Bool (= b.kind "wrap")) (irTy/builtinEntries))

fn c11SOpExpr env: C11SEnv strings: (List Str) defs: (Map Str irTy/SsaTy) t: irTy/SsaTy op: irTy/SsaOp -> Str
  (mt op
    ((irTy/opConst c) (c11SConst strings t c))
    ((irTy/opCall callee args) (str (c11SFn callee) "(" (stringJoin (c11SRefs args) ", ") ")"))
    ((irTy/opBuiltin name args) (str "asl_rt_builtin(" (c11SStrLit name) ", INT64_C(" (listLength args) "), " (c11SArrayLit "AslVal" (c11SRefs args)) ")"))
    ((irTy/opEntry name args) (mt (irTy/builtinEntry name (listLength args))
                                ((some b) (str (c11BuiltinSym b) "(" (stringJoin (c11SRefs args) ", ") ")"))
                                ((none) (str "asl_rt_builtin(" (c11SStrLit name) ", INT64_C(" (listLength args) "), " (c11SArrayLit "AslVal" (c11SRefs args)) ")"))))
    ((irTy/opCallClosure c args) (str "asl_rt_call_closure(" (c11SVal c) ", INT64_C(" (listLength args) "), " (c11SArrayLit "AslVal" (c11SRefs args)) ")"))
    ((irTy/opMakeClosure callee caps) (str "asl_rt_make_closure((void*)" (c11SCode callee) ", INT64_C(" (c11SClosureArity env callee) "), INT64_C(" (listLength caps) "), " (c11SArrayLit "AslVal" (c11SRefs caps)) ")"))
    ((irTy/opConstruct typeName variant fields) (str "asl_rt_construct(" (c11SStrLit typeName) ", " (c11SStrLit variant) ", INT64_C(" (c11SVariantTag env typeName variant) "), INT64_C(" (listLength fields) "), " (c11SArrayLit "AslVal" (c11SRefs fields)) ")"))
    ((irTy/opRecord schema fields values) (str "asl_rt_record(" (c11SStrLit schema) ", INT64_C(" (listLength values) "), " (c11SArrayLit "const char*" (map c11SStrLit fields)) ", " (c11SArrayLit "AslVal" (c11SRefs values)) ")"))
    ((irTy/opField base field) (str "asl_rt_field(" (c11SVal base) ", " (c11SStrLit field) ")"))
    ((irTy/opVariantField base i) (str "asl_rt_variant_field(" (c11SVal base) ", INT64_C(" i "))"))
    ((irTy/opList items) (str "asl_rt_list(INT64_C(" (listLength items) "), " (c11SArrayLit "AslVal" (c11SRefs items)) ")"))
    ((irTy/opGlobal g) (c11SGlobal g))
    ((irTy/opBox v) (c11SBoxExpr (optionOr (mapGet defs v) (irTy/tyVal)) (c11SVal v)))
    ((irTy/opUnbox v) (c11SUnboxExpr t (c11SVal v)))
    (_ ""))

fn c11SPrimStmt dest: Str name: Str args: (List Str) -> Str
  (let [(av (c11SVal (optionOr (listGet args 0) ""))) (bv (c11SVal (optionOr (listGet args 1) ""))) (dv (c11SVal dest))]
    (cond
      ((= name "addInt") (str "  if (__builtin_add_overflow(" av ", " bv ", &" dv ")) { __builtin_trap(); }\n"))
      ((= name "subInt") (str "  if (__builtin_sub_overflow(" av ", " bv ", &" dv ")) { __builtin_trap(); }\n"))
      ((= name "mulInt") (str "  if (__builtin_mul_overflow(" av ", " bv ", &" dv ")) { __builtin_trap(); }\n"))
      ((= name "quotInt") (str "  if ((" bv " == 0) || ((" av " == INT64_MIN) && (" bv " == -1))) { __builtin_trap(); }\n  " dv " = " av " / " bv ";\n"))
      ((= name "remInt") (str "  if (" bv " == 0) { __builtin_trap(); }\n  " dv " = (" bv " == -1) ? 0 : (" av " % " bv ");\n"))
      ((= name "floatToInt") (str "  if (!(" av " >= -9223372036854775808.0 && " av " < 9223372036854775808.0)) { __builtin_trap(); }\n  " dv " = (int64_t)(" av ");\n"))
      ((= name "addIntHost") (str "  if (__builtin_add_overflow(" av ", " bv ", &" dv ")) { asl_rt_int_trap(0); }\n"))
      ((= name "subIntHost") (str "  if (__builtin_sub_overflow(" av ", " bv ", &" dv ")) { asl_rt_int_trap(1); }\n"))
      ((= name "mulIntHost") (str "  if (__builtin_mul_overflow(" av ", " bv ", &" dv ")) { asl_rt_int_trap(2); }\n"))
      ((= name "divIntHost") (str "  if (" bv " == 0) { asl_rt_int_trap(5); }\n  if (" av " == INT64_MIN && " bv " == -1) { asl_rt_int_trap(3); }\n  " dv " = " av " / " bv " - ((" av " % " bv " != 0 && ((" av " % " bv " < 0) != (" bv " < 0))) ? 1 : 0);\n"))
      ((= name "modIntHost") (str "  if (" bv " == 0) { asl_rt_int_trap(6); }\n  " dv " = (" bv " == -1) ? 0 : " av " % " bv ";\n  if (" dv " != 0 && ((" dv " < 0) != (" bv " < 0))) { " dv " += " bv "; }\n"))
      ((= name "negIntHost") (str "  if (" av " == INT64_MIN) { asl_rt_int_trap(1); }\n  " dv " = -" av ";\n"))
      ((= name "negFloat") (str "  " dv " = -(" av ");\n"))
      ((= name "eqBool") (str "  " dv " = (" av " == " bv ");\n"))
      ((= name "neBool") (str "  " dv " = (" av " != " bv ");\n"))
      ((= name "intToFloat") (str "  " dv " = (double)(" av ");\n"))
      ((= name "notBool") (str "  " dv " = !(" av ");\n"))
      ((= name "andBool") (str "  " dv " = (" av " && " bv ");\n"))
      ((= name "orBool") (str "  " dv " = (" av " || " bv ");\n"))
      ((= name "eqInt") (str "  " dv " = (" av " == " bv ");\n"))
      ((= name "neInt") (str "  " dv " = (" av " != " bv ");\n"))
      ((= name "ltInt") (str "  " dv " = (" av " < " bv ");\n"))
      ((= name "leInt") (str "  " dv " = (" av " <= " bv ");\n"))
      ((= name "gtInt") (str "  " dv " = (" av " > " bv ");\n"))
      ((= name "geInt") (str "  " dv " = (" av " >= " bv ");\n"))
      ((= name "addFloat") (str "  " dv " = (" av " + " bv ");\n"))
      ((= name "subFloat") (str "  " dv " = (" av " - " bv ");\n"))
      ((= name "mulFloat") (str "  " dv " = (" av " * " bv ");\n"))
      ((= name "divFloat") (str "  " dv " = (" av " / " bv ");\n"))
      ((= name "eqFloat") (str "  " dv " = (" av " == " bv ");\n"))
      ((= name "neFloat") (str "  " dv " = (" av " != " bv ");\n"))
      ((= name "ltFloat") (str "  " dv " = (" av " < " bv ");\n"))
      ((= name "leFloat") (str "  " dv " = (" av " <= " bv ");\n"))
      ((= name "gtFloat") (str "  " dv " = (" av " > " bv ");\n"))
      ((= name "geFloat") (str "  " dv " = (" av " >= " bv ");\n"))
      (else (str "  /* unreachable: " name " is outside primSignature, verifySsa rejects it */\n"))))

fn c11SInstr env: C11SEnv strings: (List Str) defs: (Map Str irTy/SsaTy) ins: irTy/SsaInstr -> Str
  (let [(d ins.dest) (t ins.ty) (op ins.op)]
    (mt op
      ((irTy/opPrim name args) (c11SPrimStmt d name args))
      (_ (str "  " (c11SVal d) " = " (c11SOpExpr env strings defs t op) ";\n"))))

fn c11SBlockParams blocks: (Map Str irTy/SsaBlock) label: Str -> (List irTy/SsaParam)
  (mt (mapGet blocks label) ((some b) b.params) ((none) (list)))

fn c11SEdgeStmt blocks: (Map Str irTy/SsaBlock) e: irTy/SsaEdge -> Str
  (let [(params (c11SBlockParams blocks e.target)) (args e.args)
        (assigns (stringJoin (map (fn [(i Int64)] -> Str
                                     (str "  " (c11SVal (optionOr (listGet params i) (irTy/ssaParam "" (irTy/tyVal))).name) " = " (c11SVal (optionOr (listGet args i) "")) ";\n"))
                                   (range 0 (listLength args))) ""))]
    (str assigns "  goto " (c11SLabel e.target) ";\n"))

fn c11STerm env: C11SEnv blocks: (Map Str irTy/SsaBlock) fnName: Str defs: (Map Str irTy/SsaTy) term: irTy/SsaTerm -> Str
  (mt term
    ((irTy/termReturn v) (str "  return " (c11SVal v) ";\n"))
    ((irTy/termJump e) (c11SEdgeStmt blocks e))
    ((irTy/termBranch cond thenE elseE)
      (let [(condTy (optionOr (mapGet defs cond) (irTy/tyVal)))
            (condExpr (if (= (irTy/ssaTyName condTy) "i1") (c11SVal cond) (str "asl_rt_unbox_bool(" (c11SVal cond) ")")))]
        (str "  if (" condExpr ") {\n" (c11SEdgeStmt blocks thenE) "  } else {\n" (c11SEdgeStmt blocks elseE) "  }\n")))
    ((irTy/termSwitch scrutinee typeName cases defaultEdge)
      (let [(variants (c11SVariantsOf env typeName))
            (tagExpr (str "asl_rt_tag(" (c11SVal scrutinee) ", INT64_C(" (listLength variants) "), " (c11SArrayLit "const char*" (map c11SStrLit variants)) ")"))
            (caseLines (stringJoin (map (fn [(c irTy/SsaCase)] -> Str (str "    case " (c11SVariantTag env typeName c.variant) ": {\n" (c11SEdgeStmt blocks c.edge) "    }\n")) cases) ""))
            (defLine (mt defaultEdge
                       ((some e) (str "    default: {\n" (c11SEdgeStmt blocks e) "    }\n"))
                       ((none) (str "    default: asl_rt_trap(" (c11SStrLit fnName) ");\n"))))]
        (str "  {\n    int64_t tag = " tagExpr ";\n    switch (tag) {\n" caseLines defLine "    }\n  }\n")))
    ((irTy/termUnreachable) (str "  asl_rt_trap(" (c11SStrLit fnName) ");\n")))

fn c11SBlock env: C11SEnv blocks: (Map Str irTy/SsaBlock) fnName: Str defs: (Map Str irTy/SsaTy) strings: (List Str) b: irTy/SsaBlock -> Str
  (str (c11SLabel b.label) ": ;\n"
       (stringJoin (map (fn [(ins irTy/SsaInstr)] -> Str (c11SInstr env strings defs ins)) b.instrs) "")
       (c11STerm env blocks fnName defs b.term))

fn c11SParamList f: irTy/SsaFunction -> (List irTy/SsaParam)
  (listAppend f.captures f.params)

fn c11SBlocksMap f: irTy/SsaFunction -> (Map Str irTy/SsaBlock)
  (fold (fn [(acc (Map Str irTy/SsaBlock)) (b irTy/SsaBlock)] -> (Map Str irTy/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks)

fn c11SPairsFromParams ps: (List irTy/SsaParam) -> (List (Pair Str irTy/SsaTy))
  (map (fn [(p irTy/SsaParam)] -> (Pair Str irTy/SsaTy) (pair p.name p.ty)) ps)

fn c11SBlockParamPairs f: irTy/SsaFunction -> (List (Pair Str irTy/SsaTy))
  (fold (fn [(acc (List (Pair Str irTy/SsaTy))) (b irTy/SsaBlock)] -> (List (Pair Str irTy/SsaTy)) (listAppend acc (c11SPairsFromParams b.params))) (list) f.blocks)

fn c11SInstrPairs f: irTy/SsaFunction -> (List (Pair Str irTy/SsaTy))
  (fold (fn [(acc (List (Pair Str irTy/SsaTy))) (b irTy/SsaBlock)] -> (List (Pair Str irTy/SsaTy))
          (listAppend acc (map (fn [(ins irTy/SsaInstr)] -> (Pair Str irTy/SsaTy) (pair ins.dest ins.ty)) b.instrs)))
        (list) f.blocks)

fn c11SDefsMap f: irTy/SsaFunction -> (Map Str irTy/SsaTy)
  (fold (fn [(m (Map Str irTy/SsaTy)) (p (Pair Str irTy/SsaTy))] -> (Map Str irTy/SsaTy) (mapSet m (pairFirst p) (pairSecond p)))
        (mapEmpty) (listAppend (c11SPairsFromParams (c11SParamList f)) (listAppend (c11SBlockParamPairs f) (c11SInstrPairs f))))

fn c11SLocalPairs f: irTy/SsaFunction -> (List (Pair Str irTy/SsaTy))
  (let [(paramNames (map (fn [(p irTy/SsaParam)] -> Str p.name) (c11SParamList f)))]
    (filter (fn [(p (Pair Str irTy/SsaTy))] -> Bool (not (listContains? paramNames (pairFirst p))))
            (listAppend (c11SBlockParamPairs f) (c11SInstrPairs f))))

fn c11SProto f: irTy/SsaFunction -> Str
  (let [(ps (c11SParamList f)) (paramTypes (if (listEmpty? ps) "void" (stringJoin (map (fn [(p irTy/SsaParam)] -> Str (c11SType p.ty)) ps) ", ")))]
    (str (c11SType f.retTy) " " (c11SFn f.name) "(" paramTypes ");\n"))

fn c11SExternProto e: irTy/SsaExtern -> Str
  (str "extern AslVal " (c11SFn e.name) "(" (if (= e.arity 0) "void" (stringJoin (map (fn [(i Int64)] -> Str "AslVal") (range 0 e.arity)) ", ")) ");\n")

fn c11SFunction env: C11SEnv strings: (List Str) f: irTy/SsaFunction -> Str
  (let [(blocks (c11SBlocksMap f))
        (defs (c11SDefsMap f))
        (ps (c11SParamList f))
        (paramsStr (if (listEmpty? ps) "void" (stringJoin (map (fn [(p irTy/SsaParam)] -> Str (str (c11SType p.ty) " " (c11SVal p.name))) ps) ", ")))
        (localDecls (stringJoin (map (fn [(p (Pair Str irTy/SsaTy))] -> Str (str "  " (c11SType (pairSecond p)) " " (c11SVal (pairFirst p)) ";\n")) (c11SLocalPairs f)) ""))
        (body (stringJoin (map (fn [(b irTy/SsaBlock)] -> Str (c11SBlock env blocks f.name defs strings b)) f.blocks) ""))]
    (str (c11SType f.retTy) " " (c11SFn f.name) "(" paramsStr ") {\n" localDecls body "}\n"))

fn c11SAllInstrs m: irTy/SsaModule -> (List irTy/SsaInstr)
  (fold (fn [(acc (List irTy/SsaInstr)) (f irTy/SsaFunction)] -> (List irTy/SsaInstr)
          (fold (fn [(a (List irTy/SsaInstr)) (b irTy/SsaBlock)] -> (List irTy/SsaInstr) (listAppend a b.instrs)) acc f.blocks))
        (list) m.functions)

fn c11SDistinct xs: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (x Str)] -> (List Str) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn c11SClosureTargets m: irTy/SsaModule -> (List Str)
  (c11SDistinct (fold (fn [(acc (List Str)) (ins irTy/SsaInstr)] -> (List Str)
                        (mt ins.op ((irTy/opMakeClosure callee _) (listAppend acc (list callee))) (_ acc)))
                      (list) (c11SAllInstrs m)))

fn c11STrampolineProto f: irTy/SsaFunction -> Str
  (str "static AslVal " (c11SCode f.name) "(AslVal env, int64_t argc, AslVal* argv);\n")

fn c11STrampoline f: irTy/SsaFunction -> Str
  (let [(caps (listLength f.captures)) (n (listLength f.params))
        (capLines (stringJoin (map (fn [(i Int64)] -> Str (str "  AslVal cap_" i " = asl_rt_closure_capture(env, INT64_C(" i "));\n")) (range 0 caps)) ""))
        (argLines (stringJoin (map (fn [(i Int64)] -> Str (str "  AslVal arg_" i " = argv[" i "];\n")) (range 0 n)) ""))
        (callArgs (stringJoin (listAppend (map (fn [(i Int64)] -> Str (str "cap_" i)) (range 0 caps)) (map (fn [(i Int64)] -> Str (str "arg_" i)) (range 0 n))) ", "))]
    (str "static AslVal " (c11SCode f.name) "(AslVal env, int64_t argc, AslVal* argv) {\n"
         "  (void)argc; (void)env; (void)argv;\n" capLines argLines
         "  return " (c11SFn f.name) "(" callArgs ");\n}\n"))

fn c11SGlobalDecl g: irTy/SsaGlobal -> Str
  (str "static AslVal " (c11SGlobal g.name) ";\n")

fn c11SInitFn env: C11SEnv m: irTy/SsaModule -> Str
  (let [(globals m.globals)]
    (if (listEmpty? globals) ""
      (str "static void " (c11SInit m.name) "(void) {\n"
           (stringJoin (map (fn [(g irTy/SsaGlobal)] -> Str (str "  asl_rt_global_root(&" (c11SGlobal g.name) ");\n")) globals) "")
           (stringJoin (map (fn [(g irTy/SsaGlobal)] -> Str (str "  " (c11SGlobal g.name) " = " (c11SFn g.init) "();\n")) globals) "")
           "}\n")))

fn c11STakesArgs? f: irTy/SsaFunction -> Bool
  (and (listEmpty? f.captures)
       (and (= (listLength f.params) 1)
            (= (irTy/ssaTyName (optionOr (listHead f.params) (irTy/ssaParam "" (irTy/tyVal))).ty) "val")))

fn c11SValidEntry f: irTy/SsaFunction -> (Option Str)
  (if (or (and (listEmpty? f.captures) (listEmpty? f.params)) (c11STakesArgs? f))
    (none)
    (some (str "entry function '" f.name "' must take no parameters, or one Val parameter (the argument list), and no captures")))

fn c11SInitCall m: irTy/SsaModule -> Str
  (if (listEmpty? m.globals) "" (str "  " (c11SInit m.name) "();\n"))

fn c11SMainWrapper m: irTy/SsaModule f: irTy/SsaFunction -> Str
  (let [(usesArgs (c11STakesArgs? f))
        (header (if usesArgs "int main(int argc, char** argv) {\n" "int main(void) {\n"))
        (init (str "  asl_rt_init();\n" (c11SInitCall m)))
        (argsLine (if usesArgs "  AslVal args = asl_rt_args(argc, argv);\n" ""))
        (callExpr (if usesArgs (str (c11SFn f.name) "(args)") (str (c11SFn f.name) "()")))]
    (mt f.retTy
      ((irTy/tyVal) (str header init argsLine "  AslVal result = " callExpr ";\n  return asl_rt_exit_code(result);\n}\n"))
      ((irTy/tyRec _) (str header init argsLine "  AslVal result = " callExpr ";\n  return asl_rt_exit_code(result);\n}\n"))
      ((irTy/tyI64) (str header init argsLine "  int64_t result = " callExpr ";\n  return (int)result;\n}\n"))
      ((irTy/tyI1)  (str header init argsLine "  bool result = " callExpr ";\n  return result ? 1 : 0;\n}\n"))
      ((irTy/tyF64) (str header init argsLine "  double result = " callExpr ";\n  return (int)result;\n}\n"))
      ((irTy/tyI32) (str header init argsLine "  int32_t result = " callExpr ";\n  return (int)result;\n}\n"))
      ((irTy/tyPtr) (str header init argsLine "  void* result = " callExpr ";\n  return result != NULL ? 0 : 1;\n}\n"))))

fn c11SRuntimePreamble -> Str
  (str "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <math.h>\n\n"
       "typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; void* o; } u; } AslVal;\n\n"
       "extern void asl_rt_init(void);\n"
       "extern AslVal asl_rt_int(int64_t v);\n"
       "extern AslVal asl_rt_float(double v);\n"
       "extern AslVal asl_rt_bool(int v);\n"
       "extern AslVal asl_rt_unit(void);\n"
       "extern int64_t asl_rt_unbox_int(AslVal b);\n"
       "extern double asl_rt_unbox_float(AslVal b);\n"
       "extern bool asl_rt_unbox_bool(AslVal b);\n"
       "extern AslVal asl_rt_str(const char* p, int64_t len);\n"
       "extern AslVal asl_rt_keyword(const char* name);\n"
       "extern AslVal asl_rt_symbol(const char* name);\n"
       "extern AslVal asl_rt_builtin(const char* name, int64_t argc, AslVal* argv);\n"
       "extern AslVal asl_rt_call_closure(AslVal c, int64_t argc, AslVal* argv);\n"
       "extern AslVal asl_rt_make_closure(void* code, int64_t arity, int64_t ncaps, AslVal* argv);\n"
       "extern AslVal asl_rt_closure_capture(AslVal env, int64_t i);\n"
       "extern AslVal asl_rt_construct(const char* typeName, const char* variant, int64_t tag, int64_t n, AslVal* argv);\n"
       "extern AslVal asl_rt_record(const char* schema, int64_t n, const char* const* keys, AslVal* argv);\n"
       "extern AslVal asl_rt_field(AslVal base, const char* field);\n"
       "extern AslVal asl_rt_variant_field(AslVal base, int64_t i);\n"
       "extern int64_t asl_rt_tag(AslVal base, int64_t n, const char* const* variants);\n"
       "extern void asl_rt_global_root(AslVal* slot);\n"
       "extern AslVal asl_rt_list(int64_t n, AslVal* argv);\n"
       "extern _Noreturn void asl_rt_trap(const char* fn);\n"
       "extern AslVal asl_rt_args(int32_t argc, char** argv);\n"
       "extern int32_t asl_rt_exit_code(AslVal result);\n"
       "extern _Noreturn void asl_rt_int_trap(int32_t kind);\n"
       (stringJoin (map c11SEntryProto (c11WrapBuiltinEntries)) "")
       "\n")

fn c11SEntryProto b: irTy/SsaBuiltin -> Str
  (str "extern " (c11SType b.result) " asl_rt_b_" b.symbol "(" (stringJoin (map c11SType b.args) ", ") ");\n")

fn c11SBuildEnv m: irTy/SsaModule -> C11SEnv
  (C11SEnv
    :functions (fold (fn [(acc (Map Str irTy/SsaFunction)) (f irTy/SsaFunction)] -> (Map Str irTy/SsaFunction) (mapSet acc f.name f)) (mapEmpty) m.functions)
    :types (fold (fn [(acc (Map Str (List irTy/SsaVariant))) (d irTy/SsaTypeDecl)] -> (Map Str (List irTy/SsaVariant)) (mapSet acc d.name d.variants)) (mapEmpty) m.types))

fn c11SAssemble m: irTy/SsaModule f: irTy/SsaFunction -> Str
  (let [(env (c11SBuildEnv m))
        (targets (c11SClosureTargets m))
        (tramps (filter (fn [(fn2 irTy/SsaFunction)] -> Bool (listContains? targets fn2.name)) m.functions))
        (fnProtos (stringJoin (map c11SProto m.functions) ""))
        (externProtos (stringJoin (map c11SExternProto m.externs) ""))
        (trampProtos (stringJoin (map c11STrampolineProto tramps) ""))
        (globalDecls (stringJoin (map c11SGlobalDecl m.globals) ""))
        (fnBodies (stringJoin (map (fn [(fn2 irTy/SsaFunction)] -> Str (c11SFunction env m.strings fn2)) m.functions) "\n"))
        (trampBodies (stringJoin (map c11STrampoline tramps) "\n"))
        (initFn (c11SInitFn env m))
        (mainFn (c11SMainWrapper m f))]
    (str (c11SRuntimePreamble) fnProtos externProtos trampProtos globalDecls "\n" fnBodies "\n" trampBodies (if (stringEmpty? initFn) "" (str initFn "\n")) mainFn))

fn c11SDiagsToMsg diags: (List irTy/IrDiag) -> Str
  (stringJoin (map (fn [(d irTy/IrDiag)] -> Str (str d.code ": " d.message " (" d.locus ")")) diags) "; ")

fn c11SFindEntry m: irTy/SsaModule -> (Option irTy/SsaFunction)
  (listHead (filter (fn [(f irTy/SsaFunction)] -> Bool (= f.name "main")) m.functions))

fn emitC11Source src: Str path: Str -> (Result Str Str)
  (c11SFromLowered (low/lowerSource src) path)

fn emitC11SourceWith src: Str preludeSrc: Str path: Str -> (Result Str Str)
  (c11SFromLowered (lk/lowerSourceWith src preludeSrc) path)

fn c11SFromLowered lowered: (Result irTy/SsaModule (List irTy/IrDiag)) path: Str -> (Result Str Str)
  (mt lowered
    ((err diags) (err (str "lowering " path ": " (c11SDiagsToMsg diags))))
    ((ok m)
      (mt (vfy/verifySsa m)
        ((err diags) (err (str "verifying " path ": " (c11SDiagsToMsg diags))))
        ((ok _)
          (mt (c11SFindEntry m)
            ((none) (err (str "entry function 'main' is not defined in " path)))
            ((some f)
              (mt (c11SValidEntry f)
                ((some msg) (err msg))
                ((none) (ok (c11SAssemble m f))))))))))
