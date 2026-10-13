(module asl-syntax/tests/llvm/llvmIrTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/llvm/lex :a lx)
      (asl-syntax/llvm/cst :a cst)
      (asl-syntax/llvm/validate :a val)
      (asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/sourceE2eTest :a sE2e)])

fn readOrFail! path: String -> String
  (mt (fileReadString path)
    ((ok content) content)
    ((err msg) (do (assert false (str "failed reading " path ": " msg)) "")))

fn verifyCleanFile! path: String -> Bool
  (let [(text (readOrFail! path))
        (len (stringLength text))
        (tree (cst/parseLlvm text))
        (tiling (tr/checkTiling tree len))
        (printed (pr/printTreeString text tree))
        (valRes (val/llvmValidate text))]
    (do
      (assert (ok? tiling) (str "tiling check passes on " path))
      (assert (= printed text) (str "print roundtrip is byte-identical on " path))
      (assert (ok? valRes) (str "llvmValidate passes on " path))
      true))

fn testGoldenFib! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/fib.ll")

fn testGoldenFibRaw! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/fibRaw.ll")

fn testGoldenLoop! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/loop.ll")

fn testGoldenOps! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/ops.ll")

fn testGoldenPrimCheck! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/primCheck.ll")

fn testGoldenSwitch! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/switch.ll")

fn testGoldenTraps! -> Bool
  (verifyCleanFile! "asl/packages/asl-target-llvm/tests/golden/traps.ll")

fn ! testSourceE2eProgram -> Bool
  (let [(res (llvm/emitLlvmSource (sE2e/fibSource) "fibMain"))]
    (mt res
      ((err e) (do (assert false (str "emitLlvmSource failed: " e)) false))
      ((ok text)
       (let [(len (stringLength text))
             (tree (cst/parseLlvm text))
             (tiling (tr/checkTiling tree len))
             (printed (pr/printTreeString text tree))
             (valRes (val/llvmValidate text))]
         (do
           (assert (ok? tiling) "tiling check passes on emitted sourceE2e text")
           (assert (= printed text) "print roundtrip is byte-identical on emitted sourceE2e text")
           (assert (ok? valRes) "llvmValidate passes on emitted sourceE2e text")
           true)))))


fn testIrE2eProgram! name: String -> Bool
  (let [(cmd (str "bin/asl run asl/packages/asl-target-llvm/tests/irE2eTest.asl " name))
        (runRes (processRun cmd))]
    (if (!= runRes.exitCode 0)
      (do (assert false (str "running irE2eTest " name " failed: " runRes.stderr)) false)
      (let [(text runRes.stdout)
            (len (stringLength text))
            (tree (cst/parseLlvm text))
            (tiling (tr/checkTiling tree len))
            (printed (pr/printTreeString text tree))
            (valRes (val/llvmValidate text))]
        (do
          (assert (ok? tiling) (str "tiling check passes on irE2eTest " name))
          (assert (= printed text) (str "print roundtrip is byte-identical on irE2eTest " name))
          (assert (ok? valRes) (str "llvmValidate passes on irE2eTest " name))
          true))))

fn testSeededMissingTerminator -> Bool
  (let [(bad "define i64 @f(i64 %a) {\nbb.entry:\n  %b = add i64 %a, 1\n}\n")]
    (mt (val/llvmValidate bad)
      ((ok _) (do (assert false "missing terminator must fail validation") false))
      ((err items)
       (do
         (assert (= (listLength items) 1) "missing terminator yields exactly 1 item")
         (let [(item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
           (do
             (assert (= (val/itemLine item) 3) "missing terminator item is at line 3")
             (assert (stringContains? (val/itemExpected item) "terminator") "expected mentions terminator")
             (assert (= (val/itemKind item) "llvm") "item kind is llvm")
             true))))))

fn testSeededUndefinedValue -> Bool
  (let [(bad "define i64 @f(i64 %a) {\nbb.entry:\n  %b = add i64 %ghost, 1\n  ret i64 %b\n}\n")]
    (mt (val/llvmValidate bad)
      ((ok _) (do (assert false "undefined local must fail validation") false))
      ((err items)
       (do
         (assert (= (listLength items) 1) "undefined local yields exactly 1 item")
         (let [(item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
           (do
             (assert (= (val/itemLine item) 3) "undefined local item is at line 3")
             (assert (stringContains? (val/itemExpected item) "ghost") "expected mentions ghost")
             (assert (= (val/itemKind item) "llvm") "item kind is llvm")
             true))))))

fn testSeededPhiMidBlock -> Bool
  (let [(bad "define i64 @f(i64 %a) {\nbb.entry:\n  %b = add i64 %a, 1\n  %p = phi i64 [ %b, %bb.entry ]\n  ret i64 %p\n}\n")]
    (mt (val/llvmValidate bad)
      ((ok _) (do (assert false "phi mid-block must fail validation") false))
      ((err items)
       (do
         (assert (= (listLength items) 1) "phi mid-block yields exactly 1 item")
         (let [(item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
           (do
             (assert (= (val/itemLine item) 4) "phi mid-block item is at line 4")
             (assert (stringContains? (val/itemExpected item) "phi") "expected mentions phi")
             (assert (= (val/itemKind item) "llvm") "item kind is llvm")
             true))))))

fn testSeededArityMismatch -> Bool
  (let [(bad "declare ptr @asl_rt_int(i64)\n\ndefine ptr @f() {\nbb.entry:\n  %x = call ptr @asl_rt_int(i64 1, i64 2)\n  ret ptr %x\n}\n")]
    (mt (val/llvmValidate bad)
      ((ok _) (do (assert false "arity mismatch must fail validation") false))
      ((err items)
       (do
         (assert (= (listLength items) 1) "arity mismatch yields exactly 1 item")
         (let [(item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
           (do
             (assert (= (val/itemLine item) 5) "arity mismatch item is at line 5")
             (assert (stringContains? (val/itemExpected item) "arguments") "expected mentions arguments")
             (assert (= (val/itemKind item) "llvm") "item kind is llvm")
             true))))))

fn testSeededDuplicateValue -> Bool
  (let [(bad "define i64 @f(i64 %a) {\nbb.entry:\n  %b = add i64 %a, 1\n  %b = add i64 %a, 2\n  ret i64 %b\n}\n")]
    (mt (val/llvmValidate bad)
      ((ok _) (do (assert false "duplicate value must fail validation") false))
      ((err items)
       (do
         (assert (= (listLength items) 1) "duplicate value yields exactly 1 item")
         (let [(item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
           (do
             (assert (= (val/itemLine item) 4) "duplicate value item is at line 4")
             (assert (stringContains? (val/itemExpected item) "defined more than once") "expected mentions defined more than once")
             (assert (= (val/itemKind item) "llvm") "item kind is llvm")
             true))))))

fn testReceiptFormatting -> Bool
  (let [(i1 (val/makeItem "llvm" 10 2 "expected term" "ret void"))
        (i2 (val/makeItem "llvm" 20 4 "expected phi" "%p = phi"))
        (i3 (val/makeItem "llvm" 30 1 "undefined %x" "%x = 1"))
        (i4 (val/makeItem "llvm" 40 1 "undefined %y" "%y = 1"))
        (i5 (val/makeItem "llvm" 50 1 "undefined %z" "%z = 1"))
        (i6 (val/makeItem "llvm" 60 1 "undefined %w" "%w = 1"))
        (all6 (list i1 i2 i3 i4 i5 i6))
        (receipt (val/formatReceipt all6))]
    (do
      (assert (stringContains? receipt "(:left (") "receipt starts with left list")
      (assert (stringContains? receipt ":more 1") "receipt caps at 5 and reports :more 1")
      (assert (stringContains? receipt ":kind \"llvm\"") "receipt contains kind llvm")
      true))

fn testLlvmAsOracle! -> Bool
  (let [(whichRes (processRun "which llvm-as"))]
    (if (= whichRes.exitCode 0)
      (let [(runRes (processRun "llvm-as -o /dev/null asl/packages/asl-target-llvm/tests/golden/fib.ll"))]
        (do
          (assert (= runRes.exitCode 0) "llvm-as oracle validates fib.ll")
          true))
      (do
        (print "llvm-as not on PATH, skipped cross-check oracle\n")
        true)))

fn itemsOf text: String -> (List val/Item)
  (mt (val/llvmValidate text)
    ((ok _) (list))
    ((err items) items))

fn expectClean text: String label: String -> Bool
  (let [(tree (cst/parseLlvm text))
        (items (itemsOf text))]
    (do
      (assert (ok? (tr/checkTiling tree (stringLength text))) (str "tiling check passes on " label))
      (assert (= (pr/printTreeString text tree) text) (str "print roundtrip is byte-identical on " label))
      (assert (listEmpty? items) (str "llvmValidate passes on " label ": " (val/formatReceipt items)))
      true))

fn expectOneItem text: String line: Int64 needle: String label: String -> Bool
  (let [(tree (cst/parseLlvm text))
        (items (itemsOf text))
        (item (optionOr (listHead items) (val/makeItem "" 0 0 "" "")))]
    (do
      (assert (ok? (tr/checkTiling tree (stringLength text))) (str "tiling check passes on " label))
      (assert (= (pr/printTreeString text tree) text) (str "print roundtrip is byte-identical on " label))
      (assert (= (listLength items) 1) (str label " yields exactly 1 item: " (val/formatReceipt items)))
      (assert (= (val/itemLine item) line) (str label " item is at line " (stringFromInt64 line)))
      (assert (stringContains? (val/itemExpected item) needle) (str label " item mentions " needle))
      true))

fn testTerminatorMidBlock -> Bool
  (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  br label %next\n  ret i64 %a\nnext:\n  ret i64 %a\n}\n"
                 3 "terminator" "br before ret in one block")

fn testSyntaxErrors -> Bool
  (do
    (expectOneItem "hello world this is not IR\n" 1 "top-level" "prose line")
    (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  ret i64 %a\n" 3 "'}'" "define without closing brace")
    (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  ret i64 %a\n\ndefine i64 @g(i64 %b) {\nentry:\n  ret i64 %b\n}\n" 3 "'}'" "unclosed define followed by define"))

fn testUseBeforeDef -> Bool
  (do
    (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  %b = add i64 %c, 1\n  %c = add i64 %a, 1\n  ret i64 %b\n}\n"
                   3 "'%c'" "use before def in one block")
    (expectOneItem "define i64 @f(i1 %p, i64 %a) {\nentry:\n  br i1 %p, label %left, label %right\nleft:\n  %x = add i64 %a, 1\n  br label %join\nright:\n  br label %join\njoin:\n  ret i64 %x\n}\n"
                   10 "'%x'" "use not dominated by def")
    (expectClean "define i64 @f(i64 %a) {\nentry:\n  br label %def\nuse:\n  ret i64 %x\ndef:\n  %x = add i64 %a, 1\n  br label %use\n}\n"
                 "def dominates a textually earlier use"))

fn testMetadata -> Bool
  (let [(text "define void @f() !dbg !3 {\nentry:\n  ret void, !dbg !4\n}\n\n!llvm.dbg.cu = !{!0}\n!0 = distinct !{!1, !\"x\", i32 2}\n")
        (toks (lx/tokenize text))
        (meta (map (fn [(t tr/Token)] -> String (lx/tokenSlice t text))
                   (filter (fn [(t tr/Token)] -> Bool (or (= (tr/tokenKind t) "metadata") (= (tr/tokenKind t) "!"))) toks)))]
    (do
      (assert (= meta (list "!dbg" "!3" "!dbg" "!4" "!llvm.dbg.cu" "!" "!0" "!0" "!" "!1" "!"))
              (str "metadata tokens in order: " (stringJoin meta " ")))
      (assert (= (stringJoin (map (fn [(t tr/Token)] -> String (lx/tokenSlice t text)) toks) "") text) "tokens concatenate to the text")
      (expectClean text "metadata module")))

fn testStructParams -> Bool
  (do
    (expectClean "define i64 @f({ i64, i64 } %s) {\nentry:\n  %a = extractvalue { i64, i64 } %s, 0\n  ret i64 %a\n}\n" "struct parameter")
    (expectClean "define { i64, i64 } @g(i64 %x) {\nentry:\n  %p = insertvalue { i64, i64 } undef, i64 %x, 0\n  ret { i64, i64 } %p\n}\n\ndefine i64 @h() {\nentry:\n  ret i64 0\n}\n" "struct return then second define")
    (expectOneItem "define i64 @f({ i64, i64 } %s) {\nentry:\n  ret i64 %t\n}\n" 3 "'%t'" "struct parameter still checks uses"))

fn testNamedTypes -> Bool
  (do
    (expectClean "%struct.P = type { i64, i64 }\n\ndefine i64 @f() {\nentry:\n  %p = alloca %struct.P, align 8\n  %q = getelementptr inbounds %struct.P, ptr %p, i32 0, i32 1\n  %v = load i64, ptr %q, align 8\n  ret i64 %v\n}\n" "named struct type")
    (expectOneItem "%struct.P = type { i64, i64 }\n\ndefine i64 @f() {\nentry:\n  %p = alloca %struct.Q, align 8\n  ret i64 0\n}\n" 5 "'%struct.Q'" "undeclared named type"))

fn testVarargs -> Bool
  (let [(decl "@s = private constant [3 x i8] c\"%d\\00\"\ndeclare i32 @printf(ptr, ...)\n\n")]
    (do
      (expectClean (str decl "define i32 @f() {\nentry:\n  %r = call i32 (ptr, ...) @printf(ptr @s, i64 1, i64 2)\n  ret i32 %r\n}\n") "varargs call with extra args")
      (expectClean (str decl "define i32 @f() {\nentry:\n  %r = call i32 (ptr, ...) @printf(ptr @s)\n  ret i32 %r\n}\n") "varargs call with fixed args only")
      (expectOneItem (str decl "define i32 @f() {\nentry:\n  %r = call i32 (ptr, ...) @printf()\n  ret i32 %r\n}\n") 6 "at least 1" "varargs call below fixed args")))

fn testImplicitEntryNumber -> Bool
  (do
    (expectClean "define i32 @f(i32 %0) {\n  br label %2\n\n2:\n  %3 = phi i32 [ %0, %1 ]\n  ret i32 %3\n}\n" "implicit entry %1")
    (expectClean "define i32 @g(i32 %a, i32 %0) {\n  %2 = add i32 %0, 1\n  br label %3\n\n3:\n  %4 = phi i32 [ %2, %1 ]\n  ret i32 %4\n}\n" "named param does not consume a number")
    (expectOneItem "define i32 @f(i32 %0) {\n  br label %2\n\n2:\n  %3 = phi i32 [ %0, %5 ]\n  ret i32 %3\n}\n" 5 "label '%5'" "phi from unknown block"))

fn testIndirectCall -> Bool
  (do
    (expectClean "@g = global i64 0\ndeclare void @h(i64, i64)\n\ndefine i64 @f(ptr %fp) {\nentry:\n  %r = call i64 %fp(ptr @h)\n  call void @h(i64 %r, i64 1)\n  ret i64 %r\n}\n" "indirect call with global argument")
    (expectOneItem "declare void @h(i64, i64)\n\ndefine void @f(ptr %fp) {\nentry:\n  call void @h(ptr %fp)\n  ret void\n}\n" 5 "expects 2" "direct call arity still checked"))

fn testLabelValueNamespaces -> Bool
  (do
    (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  br label %x\nx:\n  ret i64 %x\n}\n" 5 "'%x'" "label used as value")
    (expectOneItem "define i64 @f(i64 %a) {\nentry:\n  br label %a\n}\n" 3 "label '%a'" "value used as label"))

fn expectEmitted res: (Result String (List ty/IrDiag)) label: String -> Bool
  (mt res
    ((err ds) (do (assert false (str "emitLlvmProgram failed on " label ": " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
    ((ok text) (expectClean text label)))

fn rawI dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opConst (ty/constInt n)))

fn primI dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn blk label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn modOf name: String fns: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule name (list) (list) (list) (list) (list) fns)

fn gcdModule -> ty/SsaModule
  (modOf "gcd"
    (list (ty/ssaFunction "gcd" (list) (list (ty/ssaParam "a" (ty/tyI64)) (ty/ssaParam "b" (ty/tyI64))) (ty/tyI64)
            (list (blk "entry" (list) (ty/termJump (ty/ssaEdge "head" (list "a" "b"))))
                  (ty/ssaBlock "head" (list (ty/ssaParam "x" (ty/tyI64)) (ty/ssaParam "y" (ty/tyI64)))
                    (list (rawI "zero" 0) (primI "done" (ty/tyI1) "eqInt" (list "y" "zero")))
                    (ty/termBranch "done" (ty/ssaEdge "exit" (list "x")) (ty/ssaEdge "body" (list))))
                  (blk "body" (list (primI "r" (ty/tyI64) "remInt" (list "x" "y"))) (ty/termJump (ty/ssaEdge "head" (list "y" "r"))))
                  (ty/ssaBlock "exit" (list (ty/ssaParam "out" (ty/tyI64))) (list) (ty/termReturn "out"))))
          (ty/ssaFunction "gcdMain" (list) (list) (ty/tyI64)
            (list (blk "entry" (list (rawI "p" 48) (rawI "q" 18) (ty/ssaInstr "g" (ty/tyI64) (ty/opCall "gcd" (list "p" "q")))) (ty/termReturn "g"))))))

fn sumModule -> ty/SsaModule
  (let [(v (fn [(n String)] -> ty/SsaParam (ty/ssaParam n (ty/tyVal))))]
    (modOf "sum"
      (list (ty/ssaFunction "sumTo" (list) (list (v "n")) (ty/tyVal)
              (list (blk "entry" (list (ty/ssaInstr "zero" (ty/tyVal) (ty/opConst (ty/constInt 0)))) (ty/termJump (ty/ssaEdge "head" (list "zero" "zero"))))
                    (ty/ssaBlock "head" (list (v "i") (v "acc"))
                      (list (ty/ssaInstr "more" (ty/tyVal) (ty/opBuiltin "<" (list "i" "n"))))
                      (ty/termBranch "more" (ty/ssaEdge "step" (list)) (ty/ssaEdge "exit" (list))))
                    (blk "step" (list (ty/ssaInstr "one" (ty/tyVal) (ty/opConst (ty/constInt 1)))
                                      (ty/ssaInstr "next" (ty/tyVal) (ty/opBuiltin "+" (list "i" "one")))
                                      (ty/ssaInstr "acc2" (ty/tyVal) (ty/opBuiltin "+" (list "acc" "next"))))
                         (ty/termJump (ty/ssaEdge "head" (list "next" "acc2"))))
                    (blk "exit" (list) (ty/termReturn "acc"))))
            (ty/ssaFunction "sumMain" (list) (list) (ty/tyVal)
              (list (blk "entry" (list (ty/ssaInstr "ten" (ty/tyVal) (ty/opConst (ty/constInt 10))) (ty/ssaInstr "s" (ty/tyVal) (ty/opCall "sumTo" (list "ten")))) (ty/termReturn "s")))))))

fn parityModule -> ty/SsaModule
  (let [(step (fn [(name String) (other String) (base Bool)] -> ty/SsaFunction
                (ty/ssaFunction name (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI1)
                  (list (blk "entry" (list (rawI "zero" 0) (primI "isZero" (ty/tyI1) "eqInt" (list "n" "zero")))
                          (ty/termBranch "isZero" (ty/ssaEdge "base" (list)) (ty/ssaEdge "recur" (list))))
                        (blk "base" (list (ty/ssaInstr "b" (ty/tyI1) (ty/opConst (ty/constBool base)))) (ty/termReturn "b"))
                        (blk "recur" (list (rawI "one" 1) (primI "m" (ty/tyI64) "subInt" (list "n" "one"))
                                           (ty/ssaInstr "r" (ty/tyI1) (ty/opCall other (list "m"))))
                             (ty/termReturn "r"))))))]
    (modOf "parity"
      (list (step "isEven" "isOdd" true)
            (step "isOdd" "isEven" false)
            (ty/ssaFunction "parityMain" (list) (list) (ty/tyI64)
              (list (blk "entry" (list (rawI "k" 7) (ty/ssaInstr "e" (ty/tyI1) (ty/opCall "isEven" (list "k"))))
                      (ty/termBranch "e" (ty/ssaEdge "yes" (list)) (ty/ssaEdge "no" (list))))
                    (blk "yes" (list (rawI "one" 1)) (ty/termReturn "one"))
                    (blk "no" (list (rawI "two" 2)) (ty/termReturn "two")))))))

fn clampModule -> ty/SsaModule
  (let [(f (fn [(n String)] -> ty/SsaParam (ty/ssaParam n (ty/tyF64))))
        (fc (fn [(d String) (x Float64)] -> ty/SsaInstr (ty/ssaInstr d (ty/tyF64) (ty/opConst (ty/constFloat x)))))]
    (modOf "clamp"
      (list (ty/ssaFunction "clamp" (list) (list (f "x") (f "lo") (f "hi")) (ty/tyF64)
              (list (blk "entry" (list (primI "below" (ty/tyI1) "ltFloat" (list "x" "lo")))
                      (ty/termBranch "below" (ty/ssaEdge "join" (list "lo")) (ty/ssaEdge "upper" (list))))
                    (blk "upper" (list (primI "above" (ty/tyI1) "gtFloat" (list "x" "hi")))
                      (ty/termBranch "above" (ty/ssaEdge "join" (list "hi")) (ty/ssaEdge "join" (list "x"))))
                    (ty/ssaBlock "join" (list (f "out")) (list) (ty/termReturn "out"))))
            (ty/ssaFunction "clampMain" (list) (list) (ty/tyI64)
              (list (blk "entry" (list (fc "x" 7.5) (fc "lo" 0.0) (fc "hi" 5.0)
                                       (ty/ssaInstr "c" (ty/tyF64) (ty/opCall "clamp" (list "x" "lo" "hi")))
                                       (primI "i" (ty/tyI64) "floatToInt" (list "c")))
                      (ty/termReturn "i")))))))

fn optionModule -> ty/SsaModule
  (let [(v (fn [(n String)] -> ty/SsaParam (ty/ssaParam n (ty/tyVal))))]
    (ty/ssaModule "option" (list) (list (ty/ssaTypeDecl "Opt" (list (ty/ssaVariant "some" 1) (ty/ssaVariant "none" 0)))) (list) (list) (list)
      (list (ty/ssaFunction "orZero" (list) (list (v "o")) (ty/tyVal)
              (list (blk "entry" (list (ty/ssaInstr "zero" (ty/tyVal) (ty/opConst (ty/constInt 0))))
                      (ty/termSwitch "o" "Opt" (list (ty/ssaCase "some" (ty/ssaEdge "onSome" (list))) (ty/ssaCase "none" (ty/ssaEdge "join" (list "zero")))) (none)))
                    (blk "onSome" (list (ty/ssaInstr "inner" (ty/tyVal) (ty/opVariantField "o" 0))) (ty/termJump (ty/ssaEdge "join" (list "inner"))))
                    (ty/ssaBlock "join" (list (v "out")) (list) (ty/termReturn "out"))))
            (ty/ssaFunction "optionMain" (list) (list) (ty/tyVal)
              (list (blk "entry" (list (ty/ssaInstr "five" (ty/tyVal) (ty/opConst (ty/constInt 5)))
                                       (ty/ssaInstr "o" (ty/tyVal) (ty/opConstruct "Opt" "some" (list "five")))
                                       (ty/ssaInstr "r" (ty/tyVal) (ty/opCall "orZero" (list "o"))))
                      (ty/termReturn "r")))))))

fn testEmittedPrograms -> Bool
  (do
    (expectEmitted (llvm/emitLlvmProgram (gcdModule) "gcdMain") "emitted gcd")
    (expectEmitted (llvm/emitLlvmProgram (sumModule) "sumMain") "emitted sum")
    (expectEmitted (llvm/emitLlvmProgram (parityModule) "parityMain") "emitted parity")
    (expectEmitted (llvm/emitLlvmProgram (clampModule) "clampMain") "emitted clamp")
    (expectEmitted (llvm/emitLlvmProgram (optionModule) "optionMain") "emitted option"))

fn testClangSample! path: String -> Bool
  (let [(text (readOrFail! path))
        (items (itemsOf text))]
    (do
      (assert (listEmpty? items) (str "llvmValidate passes on " path ": " (val/formatReceipt items)))
      true))

fn testTailccAndDollarLabels -> Bool
  (let [(good "define tailcc i1 @even(i64 %n, double %a) {\nbb.entry:\n  %z = icmp eq i64 %n, 0\n  br i1 %z, label %$1.p.done, label %$1.p.more\n$1.p.done:\n  ret i1 true\n$1.p.more:\n  %m = sub i64 %n, 1\n  %r = musttail call tailcc i1 @odd(i64 %m, ptr null)\n  ret i1 %r\n}\n\ndefine tailcc i1 @odd(i64 %n, ptr %s) {\nbb.entry:\n  %r = musttail call tailcc i1 @even(i64 %n, double 1.5)\n  ret i1 %r\n}\n\ndefine i32 @main() {\nbb.entry:\n  %r = call tailcc i1 @even(i64 10, double 0.0)\n  %c = zext i1 %r to i32\n  ret i32 %c\n}\n")]
    (do (assert (ok? (val/llvmValidate good)) (str "tailcc defines, musttail between differing tailcc prototypes and $-labels validate: " (val/llvmValidate good)))
        true))

fn testMusttailRules -> Bool
  (do
    (expectOneItem "define tailcc i64 @f(i64 %n) {\nbb.entry:\n  %r = musttail call tailcc i64 @f(i64 %n)\n  %s = add i64 %r, 1\n  ret i64 %s\n}\n" 3 "followed by ret" "musttail without ret")
    (expectOneItem "define tailcc i64 @f(i64 %n) {\nbb.entry:\n  %r = musttail call tailcc i64 @f(i64 %n)\n  ret i64 %n\n}\n" 3 "followed by ret" "musttail ret of another value")
    (expectOneItem "define tailcc i64 @g(i64 %n) {\nbb.entry:\n  ret i64 %n\n}\n\ndefine i64 @f(i64 %n) {\nbb.entry:\n  %r = musttail call tailcc i64 @g(i64 %n)\n  ret i64 %r\n}\n" 8 "calling convention" "musttail convention mismatch")
    (expectOneItem "define i64 @g(i64 %a, i64 %b) {\nbb.entry:\n  ret i64 %a\n}\n\ndefine i64 @f(i64 %n) {\nbb.entry:\n  %r = musttail call i64 @g(i64 %n, i64 %n)\n  ret i64 %r\n}\n" 8 "arguments" "musttail ccc arity mismatch")
    true)

fn ! runTests -> Bool
  (do
    (testGoldenFib!)
    (testGoldenFibRaw!)
    (testGoldenLoop!)
    (testGoldenOps!)
    (testGoldenPrimCheck!)
    (testGoldenSwitch!)
    (testGoldenTraps!)
    (testSourceE2eProgram)
    (testIrE2eProgram! "fib")
    (testIrE2eProgram! "loop")
    (testIrE2eProgram! "fibRaw")
    (testIrE2eProgram! "primCheck")
    (testSeededMissingTerminator)
    (testSeededUndefinedValue)
    (testSeededPhiMidBlock)
    (testSeededArityMismatch)
    (testSeededDuplicateValue)
    (testReceiptFormatting)
    (testLlvmAsOracle!)
    (testTerminatorMidBlock)
    (testSyntaxErrors)
    (testUseBeforeDef)
    (testMetadata)
    (testStructParams)
    (testNamedTypes)
    (testVarargs)
    (testImplicitEntryNumber)
    (testIndirectCall)
    (testLabelValueNamespaces)
    (testEmittedPrograms)
    (testTailccAndDollarLabels)
    (testMusttailRules)
    (testClangSample! "asl/packages/asl-syntax/tests/llvm/fixtures/c1O0.ll.sample")
    (testClangSample! "asl/packages/asl-syntax/tests/llvm/fixtures/c1O2.ll.sample")
    true)
