(module asl-target-llvm/gcRoute
  :x [collectorModule collectorModuleForTarget collectorText collectorTextForTarget entryNames hostTriple main]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/gcAsl :a gc)
      (asl-target-llvm/target :a target)])

fn diag message: String -> ty/IrDiag
  (ty/makeIrDiag "ERR_LLVM_GCROUTE" message "asl-target-llvm/gcRoute")

fn collectorModule facts: libc/TripleFacts -> (Result ty/SsaModule (List ty/IrDiag))
  (collectorModuleForTarget facts (target/nativeTargetFacts facts.triple))

fn collectorModuleForTarget facts: libc/TripleFacts target: target/TargetFacts -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (gc/gcFactsFor facts target)
    ((err e) (err (list (diag e))))
    ((ok c) (ok (ty/ssaModule "asl-target-llvm/gcAsl" (gc/gcStrings) (list) (list) (gc/gcExterns c) (list) (gc/gcFunctions c)))))

fn sym name: String -> String
  (str "@" (ssa/llvmName (gc/functionName name)))

fn call name: String args: String -> String
  (str "call tailcc i64 " (sym name) "(" args ")")

fn entryNames -> (List String)
  (list "asl_alloc" "asl_alloc_raw" "asl_alloc_cons" "asl_alloc_perm" "asl_gc_collect" "asl_gc_root_push" "asl_gc_root_pop" "gcInit" "gcWillAllocate" "gcAccount"
        "gcRegisterProto" "gcFindObj" "gcFreedObjects" "gcTestFailNextPageSetGrow" "gcScanConservative" "gcStackBase" "gcStackTop" "gcExternalRoots" "asl_gc_state_ptr")

fn entryText target: target/TargetFacts -> String
  (stringJoin
    (filter (fn [(line String)] -> Bool (not (= line "")))
    (list
      (str "define ptr @asl_alloc(i32 %t, i64 %n) {\n  %t64 = sext i32 %t to i64\n  %r = " (call "alloc" "i64 %t64, i64 %n") "\n  %p = inttoptr i64 %r to ptr\n  ret ptr %p\n}")
      (str "define ptr @asl_alloc_raw(i32 %t, i64 %n) {\n  %t64 = sext i32 %t to i64\n  %r = " (call "allocRaw" "i64 %t64, i64 %n") "\n  %p = inttoptr i64 %r to ptr\n  ret ptr %p\n}")
      (str "define ptr @asl_alloc_cons() {\n  %r = " (call "allocCons" "") "\n  %p = inttoptr i64 %r to ptr\n  ret ptr %p\n}")
      (str "define ptr @asl_alloc_perm(i32 %t, i64 %n) {\n  %t64 = sext i32 %t to i64\n  %r = " (call "allocPerm" "i64 %t64, i64 %n") "\n  %p = inttoptr i64 %r to ptr\n  ret ptr %p\n}")
      (str "define void @asl_gc_root_push(ptr %v) {\n  %i = ptrtoint ptr %v to i64\n  %r = " (call "rootPush" "i64 %i") "\n  ret void\n}")
      (str "define void @asl_gc_root_pop(i32 %n) {\n  %n64 = sext i32 %n to i64\n  %r = " (call "rootPop" "i64 %n64") "\n  ret void\n}")
      (str "define void @gcInit() {\n  %r = " (call "init" "") "\n  ret void\n}")
      (str "define void @gcWillAllocate(i64 %n) {\n  %r = " (call "willAllocate" "i64 %n") "\n  ret void\n}")
      (str "define void @gcAccount(ptr %o, i64 %n) {\n  %i = ptrtoint ptr %o to i64\n  %r = " (call "account" "i64 %i, i64 %n") "\n  ret void\n}")
      (str "define void @gcRegisterProto(ptr %p) {\n  %i = ptrtoint ptr %p to i64\n  %r = " (call "registerProto" "i64 %i") "\n  ret void\n}")
      (str "define ptr @gcFindObj(i64 %w) {\n  %r = " (call "findObj" "i64 %w") "\n  %p = inttoptr i64 %r to ptr\n  ret ptr %p\n}")
      (str "define i64 @gcFreedObjects() {\n  %r = " (call "freedObjects" "") "\n  ret i64 %r\n}")
      (str "define void @gcTestFailNextPageSetGrow() {\n  %r = " (call "failNextGrow" "") "\n  ret void\n}")
      (str "define void @gcScanConservative(ptr %lo, ptr %hi) {\n  %l = ptrtoint ptr %lo to i64\n  %h = ptrtoint ptr %hi to i64\n  %r = " (call "scanConservative" "i64 %l, i64 %h") "\n  ret void\n}")
      (if (target/isWasm32 target)
        (str "define void @asl_gc_collect() {\nentry:\n  %t0 = " (call "begin" "") "\n  %m = " (call "markPhase" "") "\n"
             "  %s = " (call "sweepPhase" "i64 %t0, i64 0, i64 0") "\n  ret void\n}")
      (str "define void @asl_gc_collect() {\nentry:\n  %jb = alloca [128 x i64], align 16\n  %fe = alloca [4096 x i8], align 16\n  %t0 = " (call "begin" "") "\n"
           "  %g = load ptr, ptr @gcFloorGuard\n  %gi = ptrtoint ptr %g to i64\n  %fei = ptrtoint ptr %fe to i64\n  store i8 0, ptr %fe\n"
           "  %plain = icmp eq ptr %g, null\n  br i1 %plain, label %unguarded, label %guarded\n"
           "unguarded:\n  %m0 = " (call "markPhase" "") "\n  br label %sweep\n"
           "guarded:\n  %get = load ptr, ptr %g\n  %setp = getelementptr inbounds i8, ptr %g, i64 8\n  %set = load ptr, ptr %setp\n  %prev = call ptr %get()\n"
           "  %jumped = call i32 @setjmp(ptr %jb)\n  %first = icmp eq i32 %jumped, 0\n  br i1 %first, label %armed, label %caught\n"
           "armed:\n  call void %set(ptr %jb)\n  %m1 = " (call "markPhase" "") "\n  call void %set(ptr %prev)\n  br label %sweep\n"
           "caught:\n  %a = " (call "abortMark" "") "\n  call void %set(ptr %prev)\n  %rp = getelementptr inbounds i8, ptr %g, i64 16\n  %rethrow = load ptr, ptr %rp\n"
           "  call void %rethrow()\n  unreachable\n"
           "sweep:\n  %s = " (call "sweepPhase" "i64 %t0, i64 %gi, i64 %fei") "\n  ret void\n}"))
      (str "define internal void @gcAslMarkRootC({ i64, i64 } %v) {\n  %w0 = extractvalue { i64, i64 } %v, 0\n  %w1 = extractvalue { i64, i64 } %v, 1\n  %r = "
           (call "markRoot" "i64 %w0, i64 %w1") "\n  ret void\n}")
      (if (target/isWasm32 target) "" (str "define internal void @gcAslPrintStatsC() {\n  %r = " (call "printStats" "") "\n  ret void\n}"))
      "define internal i32 @gcAslLargeCmp(ptr %a, ptr %b) {\n  %x = load ptr, ptr %a\n  %y = load ptr, ptr %b\n  %xi = ptrtoint ptr %x to i64\n  %yi = ptrtoint ptr %y to i64\n  %lt = icmp ult i64 %xi, %yi\n  %gt = icmp ugt i64 %xi, %yi\n  %g = zext i1 %gt to i32\n  %r = select i1 %lt, i32 -1, i32 %g\n  ret i32 %r\n}"
      "@gcStackBase = global ptr null, align 8"
      "@gcStackTop = global ptr null, align 8"
      "@gcExternalRoots = global ptr null, align 8"
      (if (target/isWasm32 target) "@asl_gc_shadow_top = global i64 0, align 8" "")
      (gc/stateBlockText target)
      (gc/statePtrText)
      "@gcAsl.failBuf = internal global [1024 x i8] zeroinitializer, align 1")
    )
    "\n")

fn extraDecls target: target/TargetFacts -> (List String)
  (if (target/isWasm32 target)
    (list "declare void @gcMutatorRoots(ptr)" "declare void @qsort(ptr, i64, i64, ptr)" "declare i64 @llvm.cttz.i64(i64, i1)")
    (list "@gcFloorGuard = external global ptr" "declare i32 @setjmp(ptr) returns_twice" "declare void @gcMutatorRoots(ptr)" "declare void @qsort(ptr, i64, i64, ptr)"
          "declare i32 @atexit(ptr)" "declare i64 @llvm.cttz.i64(i64, i1)"))

fn declares? lines: (List String) decl: String -> Bool
  (let [(at (optionOr (stringIndexOf decl "@") 0))
        (rest (optionOr (stringSlice decl at (stringLength decl)) decl))
        (name (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "(") (optionOr (stringIndexOf rest " ") (stringLength rest)))) rest))]
    (listAny? (fn [(l String)] -> Bool (and (or (stringStartsWith? l "declare ") (stringStartsWith? l "@")) (or (stringContains? l (str name "(")) (stringStartsWith? l (str name " ="))))) lines))

fn inlinedNames -> (List String)
  (list "poolAlloc" "markObj" "markVal")

fn internal line: String -> String
  (if (stringStartsWith? line "define tailcc ")
    (let [(local (stringReplace line "define tailcc " "define internal tailcc "))]
      (if (and (listAny? (fn [(n String)] -> Bool (stringStartsWith? line (str "define tailcc i64 " (sym n) "("))) (inlinedNames)) (stringEndsWith? line ") {"))
        (str (optionOr (stringSlice local 0 (- (stringLength local) 1)) local) "alwaysinline {")
        local))
    line)

fn finishLines lines: (List String) target: target/TargetFacts -> (Result (List String) String)
  (let [(helpers (gc/helperDefinitionsFor target))
        (missing (filter (fn [(d (Pair String String))] -> Bool (!= (listLength (filter (fn [(l String)] -> Bool (= l (pairFirst d))) lines)) 1)) helpers))
        (clashes (filter (fn [(n String)] -> Bool (listAny? (fn [(l String)] -> Bool (or (stringContains? l (str " @" n "(")) (stringStartsWith? l (str "@" n " ")))) lines)) (entryNames)))]
    (cond
      ((not (listEmpty? missing))
        (err (str "the emitted text does not declare exactly once: " (stringJoin (map (fn [(d (Pair String String))] -> String (pairFirst d)) missing) "; "))))
      ((not (listEmpty? clashes))
        (err (str "the emitted text already names " (stringJoin clashes " "))))
      (else
        (let [(replaced (map (fn [(l String)] -> String
                               (fold (fn [(acc String) (d (Pair String String))] -> String (if (= l (pairFirst d)) (pairSecond d) acc)) (internal l) helpers))
                             lines))]
          (ok (listAppend (listAppend replaced (list "" (entryText target) ""))
                          (filter (fn [(d String)] -> Bool (not (declares? lines d))) (extraDecls target))))))))

fn collectorText facts: libc/TripleFacts -> (Result String (List ty/IrDiag))
  (collectorTextForTarget facts (target/nativeTargetFacts facts.triple))

fn collectorTextForTarget facts: libc/TripleFacts target: target/TargetFacts -> (Result String (List ty/IrDiag))
  (mt (collectorModuleForTarget facts target)
    ((err ds) (err ds))
    ((ok m)
      (mt (ssa/emitLlvmModule m)
        ((err ds) (err ds))
        ((ok text)
          (mt (finishLines (stringSplit text "\n") target)
            ((err e) (err (list (diag e))))
            ((ok lines) (ok (ssa/trapLowering (target/lowerLlvmText (str (stringJoin lines "\n") "\n") target) target))))))))

fn hostTriple uname: String -> String
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace uname "\n" " ") " ")))
        (os (optionOr (listGet words 0) ""))
        (machine (optionOr (listGet words 1) ""))]
    (cond
      ((!= (listLength words) 2) "")
      ((and (= os "Darwin") (= machine "arm64")) "darwin-arm64")
      ((and (= os "Linux") (= machine "x86_64")) "linux-x86_64")
      ((and (= os "Linux") (or (= machine "aarch64") (= machine "arm64"))) "linux-aarch64")
      (else "")))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(out (processRun "uname -s -m"))
        (triple (if (= out.exitCode 0) (hostTriple out.stdout) ""))]
    (mt (libc/libcFacts triple)
      ((none) (err (str "ERR_LLVM_GCROUTE: libc.asl covers no host printing '" out.stdout "' for uname -s -m")))
      ((some facts)
        (mt (collectorText facts)
          ((err ds) (err (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code ": " d.message)) ds) "; ")))
          ((ok text)
            (mt (listHead args)
              ((none) (do (print text) (ok 0)))
              ((some path) (mt (fileWrite path text)
                             ((ok _) (ok 0))
                             ((err e) (err (str "ERR_LLVM_GCROUTE: cannot write " path ": " e)))))))))))
