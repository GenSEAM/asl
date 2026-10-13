(module asl-target-llvm/emit
  :x [emitLlvmModule emitLlvmBlock emitLlvmStmt emitLlvmExpr llvmPreamble emitLlvmFunction emitLlvmOperand]
  :i [(asl-ir/types :a irTy)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/types :a llvmTy)])

fn llvmPreamble target: Str -> Str
  (let [(triple (llvmTy/emitLlvmTargetTriple target))
        (typeDefs "%asl_opt_i64_t = type { i1, i64 }\n%asl_opt_unit_t = type { i1 }\n\n")
        (strConstants (str "@.str_panic = private unnamed_addr constant [18 x i8] c\"PANIC: code %lld\\0A\\00\", align 1\n"
                           "@.str_fmt_int = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\", align 1\n"
                           "@.str_fmt_str = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\", align 1\n"
                           "@.str_arg_v = private unnamed_addr constant [10 x i8] c\"--version\\00\", align 1\n"
                           "@.str_arg_h = private unnamed_addr constant [7 x i8] c\"--help\\00\", align 1\n"
                           "@.str_version = private unnamed_addr constant [51 x i8] c\"asl 0.1.0 (pure AgentScript self-hosted toolchain)\\00\", align 1\n"
                           "@.str_help = private unnamed_addr constant [56 x i8] c\"AgentScript Native CLI (Unified S-Expression Toolchain)\\00\", align 1\n\n"))
        (decls (str "declare i32 @printf(ptr, ...)\n"
                    "declare void @exit(i32)\n"
                    "declare ptr @malloc(i64)\n"
                    "declare void @free(ptr)\n"
                    "declare i32 @snprintf(ptr, i64, ptr, ...)\n"
                    "declare i64 @strlen(ptr)\n"
                    "declare i64 @strnlen(ptr, i64)\n"
                    "declare i32 @strcmp(ptr, ptr)\n"
                    "declare i32 @strncmp(ptr, ptr, i64)\n"
                    "declare ptr @strdup(ptr)\n"
                    "declare ptr @strstr(ptr, ptr)\n"
                    "declare i32 @puts(ptr)\n"
                    "declare i32 @dprintf(i32, ptr, ...)\n"
                    "declare ptr @popen(ptr, ptr)\n"
                    "declare i32 @pclose(ptr)\n\n"))
        (helpers (str "define i64 @asl_floor_div(i64 %a, i64 %b) memory(none) nounwind willreturn {\nentry:\n  %b_zero = icmp eq i64 %b, 0\n  br i1 %b_zero, label %div_zero, label %div_chk\ndiv_zero:\n  call void @asl_panic(i64 1)\n  unreachable\ndiv_chk:\n  %a_min = icmp eq i64 %a, -9223372036854775808\n  %b_neg1 = icmp eq i64 %b, -1\n  %is_overflow = and i1 %a_min, %b_neg1\n  br i1 %is_overflow, label %div_overflow, label %div_ok\ndiv_overflow:\n  ret i64 -9223372036854775808\ndiv_ok:\n  %q = sdiv i64 %a, %b\n  %r = srem i64 %a, %b\n  %r_nz = icmp ne i64 %r, 0\n  %a_neg = icmp slt i64 %a, 0\n  %b_neg = icmp slt i64 %b, 0\n  %signs_diff = xor i1 %a_neg, %b_neg\n  %adjust = and i1 %r_nz, %signs_diff\n  %adj_val = select i1 %adjust, i64 1, i64 0\n  %res = sub i64 %q, %adj_val\n  ret i64 %res\n}\n\n"
                      "define i64 @asl_floor_mod(i64 %a, i64 %b) memory(none) nounwind willreturn {\nentry:\n  %b_zero = icmp eq i64 %b, 0\n  br i1 %b_zero, label %mod_zero, label %mod_chk\nmod_zero:\n  call void @asl_panic(i64 1)\n  unreachable\nmod_chk:\n  %a_min2 = icmp eq i64 %a, -9223372036854775808\n  %b_neg2 = icmp eq i64 %b, -1\n  %is_overflow2 = and i1 %a_min2, %b_neg2\n  br i1 %is_overflow2, label %mod_overflow, label %mod_ok\nmod_overflow:\n  ret i64 0\nmod_ok:\n  %r = srem i64 %a, %b\n  %r_nz = icmp ne i64 %r, 0\n  %a_neg = icmp slt i64 %a, 0\n  %b_neg = icmp slt i64 %b, 0\n  %signs_diff = xor i1 %a_neg, %b_neg\n  %adjust = and i1 %r_nz, %signs_diff\n  %adj_val = select i1 %adjust, i64 %b, i64 0\n  %res = add i64 %r, %adj_val\n  ret i64 %res\n}\n\n"
                      "define void @asl_panic(i64 %code) {\nentry:\n  %call = call i32 (ptr, ...) @printf(ptr @.str_panic, i64 %code)\n  %trunc = trunc i64 %code to i32\n  call void @exit(i32 %trunc)\n  unreachable\n}\n\n"
                      "define void @asl_release(ptr %ptr) {\nentry:\n  %is_null = icmp eq ptr %ptr, null\n  br i1 %is_null, label %done, label %do_free\ndo_free:\n  call void @free(ptr %ptr)\n  br label %done\ndone:\n  ret void\n}\n\n"
                      "define i64 @asl_string_len(ptr %s) memory(read) nounwind willreturn {\nentry:\n  %is_null = icmp eq ptr %s, null\n  br i1 %is_null, label %ret_zero, label %do_len\nret_zero:\n  ret i64 0\ndo_len:\n  %len = call i64 @strlen(ptr %s)\n  ret i64 %len\n}\n\n"
                      "define i64 @asl_string_cmp(ptr %a, ptr %b) memory(read) nounwind willreturn {\nentry:\n  %is_a_null = icmp eq ptr %a, null\n  %is_b_null = icmp eq ptr %b, null\n  %both_null = and i1 %is_a_null, %is_b_null\n  br i1 %both_null, label %eq_null, label %chk_a\neq_null:\n  ret i64 0\nchk_a:\n  br i1 %is_a_null, label %lt_null, label %chk_b\nlt_null:\n  ret i64 -1\nchk_b:\n  br i1 %is_b_null, label %gt_null, label %do_cmp\ngt_null:\n  ret i64 1\ndo_cmp:\n  %c = call i32 @strcmp(ptr %a, ptr %b)\n  %sext = sext i32 %c to i64\n  ret i64 %sext\n}\n\n"
                      "define ptr @asl_string_slice(ptr %s, i64 %start, i64 %end) {\nentry:\n  %is_null = icmp eq ptr %s, null\n  br i1 %is_null, label %ret_empty, label %chk_end\nret_empty:\n  %empty = call ptr @malloc(i64 1)\n  store i8 0, ptr %empty\n  ret ptr %empty\nchk_end:\n  %cmp_end_zero = icmp sle i64 %end, 0\n  br i1 %cmp_end_zero, label %ret_empty, label %calc_slice\ncalc_slice:\n  %len = call i64 @strnlen(ptr %s, i64 %end)\n  %cmp_s_neg = icmp slt i64 %start, 0\n  %s_clamped = select i1 %cmp_s_neg, i64 0, i64 %start\n  %cmp_s_len = icmp sgt i64 %s_clamped, %len\n  %s_valid = select i1 %cmp_s_len, i64 %len, i64 %s_clamped\n  %cmp_e_s = icmp slt i64 %end, %s_valid\n  %e_clamped = select i1 %cmp_e_s, i64 %s_valid, i64 %end\n  %cmp_e_len = icmp sgt i64 %e_clamped, %len\n  %e_valid = select i1 %cmp_e_len, i64 %len, i64 %e_clamped\n  %sub_len = sub i64 %e_valid, %s_valid\n  %alloc_sz = add i64 %sub_len, 1\n  %buf = call ptr @malloc(i64 %alloc_sz)\n  %src_ptr = getelementptr inbounds i8, ptr %s, i64 %s_valid\n  br label %copy_loop\ncopy_loop:\n  %idx = phi i64 [ 0, %calc_slice ], [ %next_idx, %copy_step ]\n  %done = icmp eq i64 %idx, %sub_len\n  br i1 %done, label %copy_done, label %copy_step\ncopy_step:\n  %cur_src = getelementptr inbounds i8, ptr %src_ptr, i64 %idx\n  %byte = load i8, ptr %cur_src\n  %cur_dst = getelementptr inbounds i8, ptr %buf, i64 %idx\n  store i8 %byte, ptr %cur_dst\n  %next_idx = add i64 %idx, 1\n  br label %copy_loop\ncopy_done:\n  %null_term = getelementptr inbounds i8, ptr %buf, i64 %sub_len\n  store i8 0, ptr %null_term\n  ret ptr %buf\n}\n\n"
                      "define ptr @asl_string_concat(ptr %a, ptr %b) {\nentry:\n  %la = call i64 @asl_string_len(ptr %a)\n  %lb = call i64 @asl_string_len(ptr %b)\n  %tot = add i64 %la, %lb\n  %alloc_sz = add i64 %tot, 1\n  %buf = call ptr @malloc(i64 %alloc_sz)\n  br label %copy_a\ncopy_a:\n  %ia = phi i64 [ 0, %entry ], [ %nia, %step_a ]\n  %done_a = icmp eq i64 %ia, %la\n  br i1 %done_a, label %copy_b, label %step_a\nstep_a:\n  %src_a = getelementptr inbounds i8, ptr %a, i64 %ia\n  %byte_a = load i8, ptr %src_a\n  %dst_a = getelementptr inbounds i8, ptr %buf, i64 %ia\n  store i8 %byte_a, ptr %dst_a\n  %nia = add i64 %ia, 1\n  br label %copy_a\ncopy_b:\n  %ib = phi i64 [ 0, %copy_a ], [ %nib, %step_b ]\n  %done_b = icmp eq i64 %ib, %lb\n  br i1 %done_b, label %done, label %step_b\nstep_b:\n  %src_b = getelementptr inbounds i8, ptr %b, i64 %ib\n  %byte_b = load i8, ptr %src_b\n  %dst_pos = add i64 %la, %ib\n  %dst_b = getelementptr inbounds i8, ptr %buf, i64 %dst_pos\n  store i8 %byte_b, ptr %dst_b\n  %nib = add i64 %ib, 1\n  br label %copy_b\ndone:\n  %null_term = getelementptr inbounds i8, ptr %buf, i64 %tot\n  store i8 0, ptr %null_term\n  ret ptr %buf\n}\n\n"
                      "define void @asl_println(ptr %s) {\nentry:\n  %is_null = icmp eq ptr %s, null\n  br i1 %is_null, label %print_null, label %do_puts\nprint_null:\n  %call_null = call i32 @puts(ptr @.str_fmt_str)\n  ret void\ndo_puts:\n  %call = call i32 @puts(ptr %s)\n  ret void\n}\n\n"
                      "define void @asl_eprintln(ptr %s) {\nentry:\n  %is_null = icmp eq ptr %s, null\n  br i1 %is_null, label %eprint_null, label %do_eprint\neprint_null:\n  %call_null = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @.str_fmt_str, ptr @.str_panic)\n  ret void\ndo_eprint:\n  %call = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @.str_fmt_str, ptr %s)\n  ret void\n}\n\n"))]
    (str triple typeDefs strConstants decls helpers))

fn emitLlvmOperand operand: Str ty: Str -> Str
  (cond
    ((or (= operand "") (= operand "%")) "%0")
    ((stringStartsWith? operand "%") operand)
    ((stringStartsWith? operand "@") operand)
    ((or (stringStartsWith? operand "-")
         (and (>= (optionOr (stringSlice operand 0 1) "") "0")
              (<= (optionOr (stringSlice operand 0 1) "") "9"))) operand)
    ((= operand "true") "1")
    ((= operand "false") "0")
    (else (str "%" operand)))

fn argTypeForCall op: Str isFirst: Bool -> Str
  (cond
    ((or (= op "asl_string_len") (or (= op "asl_println") (or (= op "asl_eprintln") (= op "puts")))) "ptr")
    ((or (= op "asl_string_cmp") (= op "asl_string_concat")) "ptr")
    ((= op "asl_string_slice") (if isFirst "ptr" "i64"))
    ((= op "asl_file_read") "ptr")
    ((= op "asl_file_write") "ptr")
    ((= op "asl_file_exists") "ptr")
    ((= op "asl_release") "ptr")
    (else "i64"))

fn emitLlvmExpr expr: irTy/IrExpr target: Str ty: irTy/IrType -> Str
  (let [(k expr.kind)
        (op expr.op)
        (exprTy expr.ty)
        (exprKind exprTy.kind)
        (isFloat (or (= exprKind "f64") (= (llvmTy/emitLlvmType ty) "double")))
        (operandTy (if isFloat "double" "i64"))
        (l (emitLlvmOperand expr.left operandTy))
        (r (emitLlvmOperand expr.right operandTy))
        (resTy (llvmTy/emitLlvmType ty))]
    (cond
      ((= k "atom")
        (let [(cl expr.codeLabel)]
          (if (= cl "")
            (str "    %" target " = bitcast i64 " l " to i64\n")
            (str "    %" target " = bitcast ptr @" cl " to ptr\n"))))
      ((= k "binop")
        (if isFloat
          (cond
            ((= op "+") (str "    %" target " = fadd double " l ", " r "\n"))
            ((= op "-") (str "    %" target " = fsub double " l ", " r "\n"))
            ((= op "*") (str "    %" target " = fmul double " l ", " r "\n"))
            ((= op "/") (str "    %" target " = fdiv double " l ", " r "\n"))
            (else (str "    %" target " = fadd double " l ", " r "\n")))
          (cond
            ((= op "+") (str "    %" target " = add i64 " l ", " r "\n"))
            ((= op "-") (str "    %" target " = sub i64 " l ", " r "\n"))
            ((= op "*") (str "    %" target " = mul i64 " l ", " r "\n"))
            ((= op "/") (str "    %" target " = call i64 @asl_floor_div(i64 " l ", i64 " r ")\n"))
            ((or (= op "mod") (= op "%")) (str "    %" target " = call i64 @asl_floor_mod(i64 " l ", i64 " r ")\n"))
            ((or (= op "shl") (= op "<<"))
              (str "    %" target "_mask = and i64 " r ", 63\n"
                   "    %" target " = shl i64 " l ", %" target "_mask\n"))
            ((or (= op "shr") (= op ">>"))
              (str "    %" target "_mask = and i64 " r ", 63\n"
                   "    %" target " = ashr i64 " l ", %" target "_mask\n"))
            ((or (= op "&") (= op "and")) (str "    %" target " = and i64 " l ", " r "\n"))
            ((or (= op "|") (= op "or")) (str "    %" target " = or i64 " l ", " r "\n"))
            ((or (= op "^") (= op "xor")) (str "    %" target " = xor i64 " l ", " r "\n"))
            (else (str "    %" target " = add i64 " l ", " r "\n")))))
      ((= k "cmp")
        (if isFloat
          (cond
            ((or (= op "==") (= op "=")) (str "    %" target " = fcmp oeq double " l ", " r "\n"))
            ((= op "!=") (str "    %" target " = fcmp one double " l ", " r "\n"))
            ((= op "<") (str "    %" target " = fcmp olt double " l ", " r "\n"))
            ((= op "<=") (str "    %" target " = fcmp ole double " l ", " r "\n"))
            ((= op ">") (str "    %" target " = fcmp ogt double " l ", " r "\n"))
            ((= op ">=") (str "    %" target " = fcmp oge double " l ", " r "\n"))
            (else (str "    %" target " = fcmp oeq double " l ", " r "\n")))
          (cond
            ((or (= op "==") (= op "=")) (str "    %" target " = icmp eq i64 " l ", " r "\n"))
            ((= op "!=") (str "    %" target " = icmp ne i64 " l ", " r "\n"))
            ((= op "<") (str "    %" target " = icmp slt i64 " l ", " r "\n"))
            ((= op "<=") (str "    %" target " = icmp sle i64 " l ", " r "\n"))
            ((= op ">") (str "    %" target " = icmp sgt i64 " l ", " r "\n"))
            ((= op ">=") (str "    %" target " = icmp sge i64 " l ", " r "\n"))
            (else (str "    %" target " = icmp eq i64 " l ", " r "\n")))))
      ((= k "call")
        (let [(args expr.args)
              (argsStr (fold (fn [(acc Str) (a Str)] -> Str
                               (let [(isFirst (= acc ""))
                                     (argTy (argTypeForCall op isFirst))
                                     (argVal (emitLlvmOperand a argTy))
                                     (argDecl (str argTy " " argVal))]
                                 (if isFirst argDecl (str acc ", " argDecl)))) "" args))]
          (cond
            ((= op "println") (str "    %" target "_call = call i32 (ptr, ...) @printf(ptr @.str_fmt_int, " argsStr ")\n"))
            ((= op "print") (str "    %" target "_call = call i32 (ptr, ...) @printf(ptr @.str_fmt_str, " argsStr ")\n"))
            (else (if (= resTy "void")
                     (str "    call void @" op "(" argsStr ")\n")
                     (str "    %" target " = call " resTy " @" op "(" argsStr ")\n"))))))
      ((= k "alloc") (str "    %" target " = call ptr @malloc(i64 8)\n"))
      ((= k "load") (str "    %" target " = load i64, ptr " l "\n"))
      (else (str "    %" target " = add i64 0, 0\n"))))

fn emitLlvmStmt stmt: irTy/IrStmt -> Str
  (let [(k stmt.kind)]
    (cond
      ((= k "let")
        (emitLlvmExpr stmt.expr stmt.target stmt.ty))
      ((= k "drop")
        (str "    call void @asl_release(ptr %" stmt.target ")\n"))
      ((= k "store")
        (str "    store i64 %" stmt.value ", ptr %" stmt.target "\n"))
      ((= k "return")
        (let [(v stmt.value)]
          (if (= v "")
            "    ret void\n"
            (let [(vOp (emitLlvmOperand v "i64"))]
              (str "    ret i64 " vOp "\n")))))
      ((= k "jump")
        (str "    br label %" stmt.label "\n"))
      ((= k "loop")
        (let [(loopId (if (!= stmt.label "") stmt.label (if (!= stmt.target "") stmt.target "entry")))
              (entryLabel (if (= loopId "entry") "loop_entry" (str "loop_entry_" loopId)))]
          (str "    br label %" entryLabel "\n" entryLabel ":\n"
               (emitLlvmBlock stmt.loopBody)
               "    br label %" entryLabel "\n")))
      ((= k "switch")
        (let [(sc (emitLlvmOperand stmt.scrutinee "i64"))
              (swId (if (!= stmt.label "") stmt.label (if (!= stmt.scrutinee "") stmt.scrutinee (if (!= stmt.target "") stmt.target "0"))))
              (defLabel (str "switch_default_" swId))
              (exitLabel (str "switch_exit_" swId))
              (cases stmt.cases)
              (armsStr (fold (fn [(acc Str) (c irTy/IrSwitchCase)] -> Str
                               (let [(caseLabel (str "case_" swId "_" c.tag))]
                                 (str acc "    i64 " c.tag ", label %" caseLabel "\n"))) "" cases))
              (caseBodies (fold (fn [(acc Str) (c irTy/IrSwitchCase)] -> Str
                                  (let [(caseLabel (str "case_" swId "_" c.tag))]
                                    (str acc caseLabel ":\n" (emitLlvmBlock c.body) "    br label %" exitLabel "\n"))) "" cases))
              (defBody (str defLabel ":\n" (emitLlvmBlock stmt.defaultBody) "    br label %" exitLabel "\n"))]
          (str "    switch i64 " sc ", label %" defLabel " [\n" armsStr "    ]\n"
               caseBodies defBody exitLabel ":\n")))
      (else "")))

fn emitLlvmBlock stmts: (List irTy/IrStmt) -> Str
  (fold (fn [(acc Str) (s irTy/IrStmt)] -> Str (str acc (emitLlvmStmt s))) "" stmts)

fn emitLlvmFunction f: irTy/IrFunction -> Str
  (let [(retTy (llvmTy/emitLlvmType f.retType))
        (rawName f.name)
        (name (if (= rawName "main") "asl_main" rawName))
        (paramsStr (fold (fn [(acc Str) (p irTy/IrParam)] -> Str
                           (let [(pDecl (str (llvmTy/emitLlvmType p.ty) " %" p.name))]
                             (if (= acc "") pDecl (str acc ", " pDecl)))) "" f.params))
        (bodyStr (emitLlvmBlock f.body))]
    (str "define " retTy " @" name "(" paramsStr ") {\nentry:\n" bodyStr "}\n\n"))

fn emitLlvmModule m: irTy/IrModule -> (Result Str (List irTy/IrDiag))
  (let [(vRes (vfy/verifyIr m))]
    (mt vRes
      ((err diags) (err diags))
      ((ok _)
        (let [(funcsStr (fold (fn [(acc Str) (f irTy/IrFunction)] -> Str
                               (str acc (emitLlvmFunction f))) "" m.funcs))
              (mainWrapper (str "define i32 @main(i32 %argc, ptr %argv) {\nentry:\n"
                                "    %res = call i64 @asl_main()\n"
                                "    %code = trunc i64 %res to i32\n"
                                "    ret i32 %code\n}\n"))]
          (ok (str (llvmPreamble "arm64-apple-macosx") funcsStr mainWrapper))))))
