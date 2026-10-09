(module asl-target-llvm/tests/sourceE2eTest
  :x [fibSource fibGolden testFibSourceToLlvm testUnsupportedReturnsDiagnostic testCompilePackageToLlvmImportsLinked! runTests main]
  :i [(asl-ir/types :a ty)
      (asl-compiler/compiler :a comp)
      (asl-target-llvm :a llvm)])

fn fibSource -> String
  (stringJoin
    (list
      "(module fib :x [fib fibMain])"
      ""
      "(fn fib [(n Int64)] -> Int64"
      "  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))"
      ""
      "(fn fibMain [] -> Int64"
      "  (fib 10))")
    "\n")

fn unsupportedSource -> String
  (stringJoin
    (list
      "(module bad :x [badFn])"
      ""
      "(fn badFn [(x Int64)] -> Int64"
      "  (return x))")
    "\n")

fn fibGolden -> String
  (stringJoin
    (list
      "source_filename = \"fib\""
      ""
      "define tailcc i64 @fib(i64 %n) {"
      "bb.entry:"
      "  %$250 = bitcast i64 2 to i64"
      "  %$251 = icmp slt i64 %n, %$250"
      "  br i1 %$251, label %bb.then0, label %bb.else0"
      "bb.then0:"
      "  br label %bb.join0"
      "bb.else0:"
      "  %$252 = bitcast i64 1 to i64"
      "  %$253.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %n, i64 %$252)"
      "  %$253 = extractvalue {i64, i1} %$253.p.pair, 0"
      "  %$253.p.bad = extractvalue {i64, i1} %$253.p.pair, 1"
      "  br i1 %$253.p.bad, label %$253.p.trap, label %$253.p.ok"
      "$253.p.trap:"
      "  call void @rterr.int(i32 1)"
      "  unreachable"
      "$253.p.ok:"
      "  %$254 = call tailcc i64 @fib(i64 %$253)"
      "  %$255 = bitcast i64 2 to i64"
      "  %$256.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %n, i64 %$255)"
      "  %$256 = extractvalue {i64, i1} %$256.p.pair, 0"
      "  %$256.p.bad = extractvalue {i64, i1} %$256.p.pair, 1"
      "  br i1 %$256.p.bad, label %$256.p.trap, label %$256.p.ok"
      "$256.p.trap:"
      "  call void @rterr.int(i32 1)"
      "  unreachable"
      "$256.p.ok:"
      "  %$257 = call tailcc i64 @fib(i64 %$256)"
      "  %$258.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %$254, i64 %$257)"
      "  %$258 = extractvalue {i64, i1} %$258.p.pair, 0"
      "  %$258.p.bad = extractvalue {i64, i1} %$258.p.pair, 1"
      "  br i1 %$258.p.bad, label %$258.p.trap, label %$258.p.ok"
      "$258.p.trap:"
      "  call void @rterr.int(i32 0)"
      "  unreachable"
      "$258.p.ok:"
      "  br label %bb.join0"
      "bb.join0:"
      "  %$259 = phi i64 [ %n, %bb.then0 ], [ %$258, %$258.p.ok ]"
      "  ret i64 %$259"
      "}"
      ""
      "define tailcc i64 @fibMain() {"
      "bb.entry:"
      "  %$250 = bitcast i64 10 to i64"
      "  %$251 = musttail call tailcc i64 @fib(i64 %$250)"
      "  ret i64 %$251"
      "}"
      ""
      "@.rterr.c.ERR_INTERNAL = private unnamed_addr constant [13 x i8] c\"ERR_INTERNAL\\00\""
      "@.rterr.c.ERR_INT_OVERFLOW = private unnamed_addr constant [17 x i8] c\"ERR_INT_OVERFLOW\\00\""
      "@.rterr.c.ERR_DIV_ZERO = private unnamed_addr constant [13 x i8] c\"ERR_DIV_ZERO\\00\""
      "@.rterr.m.add = private unnamed_addr constant [19 x i8] c\"Int + leaves int64\\00\""
      "@.rterr.m.sub = private unnamed_addr constant [19 x i8] c\"Int - leaves int64\\00\""
      "@.rterr.m.mul = private unnamed_addr constant [19 x i8] c\"Int * leaves int64\\00\""
      "@.rterr.m.div = private unnamed_addr constant [19 x i8] c\"Int / leaves int64\\00\""
      "@.rterr.m.divZero = private unnamed_addr constant [17 x i8] c\"division by zero\\00\""
      "@.rterr.m.modZero = private unnamed_addr constant [12 x i8] c\"mod by zero\\00\""
      "@.rterr.m.narrow = private unnamed_addr constant [24 x i8] c\"Int narrow leaves int32\\00\""
      "@.rterr.m.floatInt = private unnamed_addr constant [26 x i8] c\"Float to Int leaves int64\\00\""
      "@.rterr.m.intKind = private unnamed_addr constant [26 x i8] c\"unknown integer trap %lld\\00\""
      "@.rterr.line = private unnamed_addr constant [9 x i8] c\"%s: %.*s\\00\""
      ""
      "define internal void @rterr.writeAll(i32 %fd, ptr %data, i64 %length) {"
      "entry:"
      "  br label %loop"
      "loop:"
      "  %offset = phi i64 [ 0, %entry ], [ %next, %more ]"
      "  %done = icmp uge i64 %offset, %length"
      "  br i1 %done, label %finish, label %once"
      "once:"
      "  %at = getelementptr i8, ptr %data, i64 %offset"
      "  %rest = sub i64 %length, %offset"
      "  %wrote = call i64 @write(i32 %fd, ptr %at, i64 %rest)"
      "  %progress = icmp sgt i64 %wrote, 0"
      "  br i1 %progress, label %more, label %finish"
      "more:"
      "  %next = add i64 %offset, %wrote"
      "  br label %loop"
      "finish:"
      "  ret void"
      "}"
      ""
      "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {"
      "entry:"
      "  %buf = alloca [4097 x i8]"
      "  %big = icmp ugt i64 %len, 4096"
      "  %clamped = select i1 %big, i64 4096, i64 %len"
      "  %prec = trunc i64 %clamped to i32"
      "  %slot = call ptr @aslHandlerSlot()"
      "  %handler = load ptr, ptr %slot"
      "  %nested = icmp ne ptr %handler, null"
      "  br i1 %nested, label %rethrow, label %report"
      "rethrow:"
      "  %text = call ptr @aslErrorText()"
      "  %kept = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %text, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)"
      "  call void @longjmp(ptr %handler, i32 1)"
      "  unreachable"
      "report:"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)"
      "  %negative = icmp slt i32 %written, 0"
      "  %wide = sext i32 %written to i64"
      "  %over = icmp ugt i64 %wide, 4095"
      "  %cut = select i1 %over, i64 4095, i64 %wide"
      "  %count = select i1 %negative, i64 0, i64 %cut"
      "  %end = getelementptr i8, ptr %buf, i64 %count"
      "  store i8 10, ptr %end"
      "  %total = add i64 %count, 1"
      "  %flushed = call i32 @fflush(ptr null)"
      "  call void @rterr.writeAll(i32 2, ptr %buf, i64 %total)"
      "  call void @exit(i32 1)"
      "  unreachable"
      "}"
      ""
      "define internal void @rterr.raiseNumber(ptr %code, ptr %format, i64 %arg) noreturn {"
      "entry:"
      "  %buf = alloca [4096 x i8]"
      "  store i8 0, ptr %buf"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr %format, i64 %arg)"
      "  %len = call i64 @strlen(ptr %buf)"
      "  call void @rterr.raise(ptr %code, ptr %buf, i64 %len)"
      "  unreachable"
      "}"
      ""
      "define internal void @rterr.int(i32 %kind) noreturn {"
      "entry:"
      "  switch i32 %kind, label %unknown [ i32 0, label %add i32 1, label %sub i32 2, label %mul i32 3, label %div i32 5, label %divZero i32 6, label %modZero i32 7, label %narrow i32 8, label %floatInt ]"
      "add:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.add, i64 18)"
      "  unreachable"
      "sub:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.sub, i64 18)"
      "  unreachable"
      "mul:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.mul, i64 18)"
      "  unreachable"
      "div:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.div, i64 18)"
      "  unreachable"
      "divZero:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_DIV_ZERO, ptr @.rterr.m.divZero, i64 16)"
      "  unreachable"
      "modZero:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_DIV_ZERO, ptr @.rterr.m.modZero, i64 11)"
      "  unreachable"
      "narrow:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.narrow, i64 23)"
      "  unreachable"
      "floatInt:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.floatInt, i64 25)"
      "  unreachable"
      "unknown:"
      "  %wide = sext i32 %kind to i64"
      "  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_INTERNAL, ptr @.rterr.m.intKind, i64 %wide)"
      "  unreachable"
      "}"
      "@.rterr.m.reportFailed = private unnamed_addr constant [37 x i8] c\"cannot register the assertion report\\00\""
      "@rterr.assertCount = weak global i64 0"
      "@rterr.refuteCount = weak global i64 0"
      "@.rterr.reportEnv = private unnamed_addr constant [18 x i8] c\"ASL_ASSERT_REPORT\\00\""
      "@.rterr.reportLine = private unnamed_addr constant [57 x i8] c\"%lld assertion(s) executed, %lld refutation(s) executed\\0A\\00\""
      ""
      "define internal void @rterr.report() {"
      "entry:"
      "  %buf = alloca [128 x i8]"
      "  store i8 0, ptr %buf"
      "  %asserts = load i64, ptr @rterr.assertCount"
      "  %refutes = load i64, ptr @rterr.refuteCount"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 128, ptr @.rterr.reportLine, i64 %asserts, i64 %refutes)"
      "  %len = call i64 @strlen(ptr %buf)"
      "  call void @rterr.writeAll(i32 2, ptr %buf, i64 %len)"
      "  ret void"
      "}"
      ""
      "define internal void @rterr.reportInit() {"
      "entry:"
      "  %env = call ptr @getenv(ptr @.rterr.reportEnv)"
      "  %set = icmp ne ptr %env, null"
      "  br i1 %set, label %check, label %done"
      "check:"
      "  %first = load i8, ptr %env"
      "  %one = icmp eq i8 %first, 49"
      "  br i1 %one, label %install, label %done"
      "install:"
      "  %rc = call i32 @atexit(ptr @rterr.report)"
      "  %failed = icmp ne i32 %rc, 0"
      "  br i1 %failed, label %fail, label %done"
      "fail:"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_INTERNAL, ptr @.rterr.m.reportFailed, i64 36)"
      "  unreachable"
      "done:"
      "  ret void"
      "}"
      "@valrt.handler = weak global ptr null"
      "@valrt.errorMsg = weak global [4096 x i8] zeroinitializer"
      ""
      "define weak ptr @aslHandlerSlot() {"
      "entry:"
      "  ret ptr @valrt.handler"
      "}"
      ""
      "define weak ptr @aslErrorText() {"
      "entry:"
      "  ret ptr @valrt.errorMsg"
      "}"
      "define i32 @main() {"
      "bb.entry:"
      "  call void @rterr.reportInit()"
      "  %result = call tailcc i64 @fibMain()"
      "  %code = trunc i64 %result to i32"
      "  ret i32 %code"
      "}"
      ""
      "declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)"
      "declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)"
      "declare i64 @strlen(ptr)"
      "declare i32 @snprintf(ptr, i64, ptr, ...)"
      "declare i64 @write(i32, ptr, i64)"
      "declare void @exit(i32)"
      "declare i32 @fflush(ptr)"
      "declare ptr @getenv(ptr)"
      "declare i32 @atexit(ptr)"
      "declare void @longjmp(ptr, i32) noreturn"
      "")
    "\n")

fn testFibSourceToLlvm -> Bool
  (let [(res (llvm/emitLlvmSource (fibSource) "fibMain"))]
    (do
      (assert (ok? res) "paren-dialect fib compiles to .ll")
      (refute (err? res) "paren-dialect fib refutes err")
      (mt res
        ((err _) false)
        ((ok code)
          (do
            (assert (= code (fibGolden)) "emitted .ll matches golden")
            (assert (stringContains? code "  call void @rterr.int(i32 0)") "add overflow traps through native rterr.int kind 0")
            (refute (stringContains? code "@asl_rt_int_trap") "the deleted abi.c asl_rt_int_trap is neither declared nor called")
            (assert (stringContains? code "define tailcc i64 @fib(i64 %n)") "emitted .ll defines @fib over raw i64, as its Int64 annotations say")
            (assert (stringContains? code "define tailcc i64 @fibMain()") "emitted .ll defines @fibMain returning raw i64")
            (assert (stringContains? code "define i32 @main()") "emitted .ll defines @main wrapper")
            (assert (stringContains? code "%$251 = icmp slt i64 %n, %$250") "emitted .ll compares raw i64 with icmp, no boxed < builtin")
            (assert (stringContains? code "%$259 = phi i64 [ %n, %bb.then0 ], [ %$258, %$258.p.ok ]") "emitted .ll derives a raw phi in bb.join0 from the checked add's continuation")
            true)))))

fn testUnsupportedReturnsDiagnostic -> Bool
  (let [(res (llvm/emitLlvmSource (unsupportedSource) "main"))]
    (do
      (assert (err? res) "unsupported construct must return err")
      (refute (ok? res) "unsupported construct refutes ok")
      (mt res
        ((ok _) false)
        ((err diags)
          (let [(firstDiag (optionOr (listHead diags) (ty/makeIrDiag "" "" "")))]
            (do
              (assert (> (listLength diags) 0) "returns at least one diagnostic")
              (assert (= firstDiag.code "ERR_LOWER_UNSUPPORTED") "diagnostic code is ERR_LOWER_UNSUPPORTED")
              (assert (stringContains? firstDiag.message "'return' is outside the lowered subset") "diagnostic names return as unsupported")
              (assert (= firstDiag.locus "badFn@3:1") "diagnostic locus preserves function and position")
              true))))))

fn testCompilePackageToLlvmImportsLinked! -> Bool
  (let [(res (comp/compilePackageToLlvm! "asl/packages/asl-codegen/src/c99Emit.asl" (list ".")))]
    (do
      (assert (ok? res) "a package with imports is checked and linked, not refused")
      (mt res
        ((err _) false)
        ((ok cr)
          (do
            (refute (stringContains? (stringJoin cr.diagnostics " ") "unimplemented") "no multi-module unimplemented refusal")
            true)))))

fn negateSource -> String
  (stringJoin
    (list
      "(module neg :x [flip negMain negMin])"
      ""
      "(fn flip [(a Int64)] -> Int64 (- a))"
      ""
      "(fn negMain [] -> Int64 (+ 50 (flip (stringLength \"abc\"))))"
      ""
      "(fn negMin [] -> Int64 (flip (- (- 0 9223372036854775807) (stringLength \"a\"))))")
    "\n")

fn ! main args: (List String) -> (Result Int64 String)
  (mt (mt (listHead args)
        ((some entry) (llvm/emitLlvmSource (negateSource) entry))
        ((none) (llvm/emitLlvmSource (fibSource) "fibMain")))
    ((ok code) (do (print code) (ok 0)))
    ((err diags)
      (err (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) diags) "; "))))

fn testMissingEntryIsDiagnostic -> Bool
  (mt (llvm/emitLlvmSource (fibSource) "main")
    ((ok _) (do (assert false "a source without main must not compile with entry main") false))
    ((err diags)
      (do
        (assert (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_LLVM_NO_ENTRY")) diags) "missing entry reports ERR_LLVM_NO_ENTRY")
        true)))

fn ! runTests -> Bool
  (do
    (assert (testFibSourceToLlvm) "testFibSourceToLlvm")
    (assert (testUnsupportedReturnsDiagnostic) "testUnsupportedReturnsDiagnostic")
    (assert (testCompilePackageToLlvmImportsLinked!) "testCompilePackageToLlvmImportsLinked")
    (assert (testMissingEntryIsDiagnostic) "testMissingEntryIsDiagnostic")
    true)
