(module asl-target-llvm/tests/abiPrograms
  :x [main]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)])

fn letVal dest: String op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) op)

fn valInt dest: String n: Int64 -> ty/SsaInstr
  (letVal dest (ty/opConst (ty/constInt n)))

fn call dest: String name: String args: (List String) -> ty/SsaInstr
  (letVal dest (ty/opBuiltin name args))

fn edge target: String args: (List String) -> ty/SsaEdge
  (ty/ssaEdge target args)

fn block label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn joinBlock label: String params: (List String) instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (map (fn [(p String)] -> ty/SsaParam (ty/ssaParam p (ty/tyVal))) params) instrs term)

fn valFn name: String captures: (List String) params: (List String) blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction name
    (map (fn [(p String)] -> ty/SsaParam (ty/ssaParam p (ty/tyVal))) captures)
    (map (fn [(p String)] -> ty/SsaParam (ty/ssaParam p (ty/tyVal))) params)
    (ty/tyVal) blocks)

fn optionType -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Option" (list (ty/ssaVariant "some" 1) (ty/ssaVariant "none" 0)))

fn triType -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Tri" (list (ty/ssaVariant "first" 0) (ty/ssaVariant "second" 0) (ty/ssaVariant "third" 0)))

fn addFn -> ty/SsaFunction
  (valFn "add" (list) (list "a" "b") (list (block "entry" (list (call "sum" "+" (list "a" "b"))) (ty/termReturn "sum"))))

fn addKFn -> ty/SsaFunction
  (valFn "addK" (list "k") (list "x") (list (block "entry" (list (call "sum" "+" (list "k" "x"))) (ty/termReturn "sum"))))

fn direct dest: String callee: String args: (List String) -> ty/SsaInstr
  (letVal dest (ty/opCall callee args))

fn listWalk fnName: String captures: (List String) params: (List String) entryInstrs: (List ty/SsaInstr) start: (List String) state: (List String) step: (List ty/SsaInstr) next: (List String) done: String -> ty/SsaFunction
  (valFn fnName captures params
    (list (block "entry" entryInstrs (ty/termJump (edge "loop" start)))
          (joinBlock "loop" state (list (call "h" "listHead" (list (optionOr (listHead state) ""))))
            (ty/termSwitch "h" "Option" (list (ty/ssaCase "some" (edge "body" (list))) (ty/ssaCase "none" (edge "done" (list done)))) (none)))
          (block "body"
            (listAppend (list (letVal "x" (ty/opVariantField "h" 0))
                              (call "t" "listTail" (list (optionOr (listHead state) "")))
                              (letVal "rest" (ty/opVariantField "t" 0)))
                        step)
            (ty/termJump (edge "loop" next)))
          (joinBlock "done" (list "result") (list) (ty/termReturn "result"))))

fn foldValsFn -> ty/SsaFunction
  (listWalk "foldVals" (list) (list "f" "init" "xs") (list) (list "xs" "init") (list "cur" "acc")
    (list (letVal "acc2" (ty/opCallClosure "f" (list "acc" "x")))) (list "rest" "acc2") "acc")

fn revValsFn -> ty/SsaFunction
  (listWalk "revVals" (list) (list "xs") (list (letVal "nil" (ty/opList (list)))) (list "xs" "nil") (list "cur" "out")
    (list (call "out2" "cons" (list "x" "out"))) (list "rest" "out2") "out")

fn mapValsFn -> ty/SsaFunction
  (valFn "mapVals" (list) (list "f" "xs")
    (list (block "entry" (list (letVal "nil" (ty/opList (list)))) (ty/termJump (edge "loop" (list "xs" "nil"))))
          (joinBlock "loop" (list "cur" "out") (list (call "h" "listHead" (list "cur")))
            (ty/termSwitch "h" "Option" (list (ty/ssaCase "some" (edge "body" (list))) (ty/ssaCase "none" (edge "done" (list)))) (none)))
          (block "body"
            (list (letVal "x" (ty/opVariantField "h" 0))
                  (call "t" "listTail" (list "cur"))
                  (letVal "rest" (ty/opVariantField "t" 0))
                  (letVal "y" (ty/opCallClosure "f" (list "x")))
                  (call "out2" "cons" (list "y" "out")))
            (ty/termJump (edge "loop" (list "rest" "out2"))))
          (block "done" (list (direct "r" "revVals" (list "out"))) (ty/termReturn "r"))))

fn lengthValsFn -> ty/SsaFunction
  (listWalk "lengthVals" (list) (list "xs") (list (valInt "zero" 0) (valInt "one" 1)) (list "xs" "zero") (list "cur" "n")
    (list (call "n2" "+" (list "n" "one"))) (list "rest" "n2") "n")

fn rangeValsFn -> ty/SsaFunction
  (valFn "rangeVals" (list) (list "lo" "hi")
    (list (block "entry" (list (valInt "one" 1) (letVal "nil" (ty/opList (list))) (call "top" "-" (list "hi" "one"))) (ty/termJump (edge "loop" (list "top" "nil"))))
          (joinBlock "loop" (list "i" "acc") (list (call "more" ">=" (list "i" "lo")))
            (ty/termBranch "more" (edge "body" (list)) (edge "done" (list))))
          (block "body" (list (call "acc2" "cons" (list "i" "acc")) (call "i2" "-" (list "i" "one"))) (ty/termJump (edge "loop" (list "i2" "acc2"))))
          (block "done" (list) (ty/termReturn "acc"))))

fn runFn n: Int64 m: Int64 -> ty/SsaFunction
  (valFn "run" (list) (list)
    (list (block "entry" (list (valInt "n" n) (valInt "m" m) (valInt "zero" 0) (valInt "one" 1) (valInt "k" 3) (letVal "empty" (ty/opList (list))))
            (ty/termJump (edge "build" (list "zero" "empty"))))
          (joinBlock "build" (list "i" "acc") (list (call "more" "<" (list "i" "n")))
            (ty/termBranch "more" (edge "buildBody" (list)) (edge "built" (list))))
          (block "buildBody" (list (call "acc2" "cons" (list "i" "acc")) (call "i2" "+" (list "i" "one")))
            (ty/termJump (edge "build" (list "i2" "acc2"))))
          (block "built"
            (list (letVal "add" (ty/opMakeClosure "add" (list)))
                  (direct "sum1" "foldVals" (list "add" "zero" "acc"))
                  (direct "ys" "rangeVals" (list "zero" "n"))
                  (letVal "addK" (ty/opMakeClosure "addK" (list "k")))
                  (direct "zs" "mapVals" (list "addK" "ys"))
                  (direct "sum3" "foldVals" (list "add" "zero" "zs")))
            (ty/termJump (edge "walk" (list "zs" "zero"))))
          (joinBlock "walk" (list "cur" "total") (list (call "h" "listHead" (list "cur")))
            (ty/termSwitch "h" "Option"
              (list (ty/ssaCase "some" (edge "walkSome" (list)))
                    (ty/ssaCase "none" (edge "walked" (list "total"))))
              (none)))
          (block "walkSome"
            (list (letVal "x" (ty/opVariantField "h" 0))
                  (call "t" "listTail" (list "cur"))
                  (letVal "rest" (ty/opVariantField "t" 0))
                  (call "total2" "+" (list "total" "x")))
            (ty/termJump (edge "walk" (list "rest" "total2"))))
          (joinBlock "walked" (list "sum4")
            (list (letVal "s0" (ty/opConst (ty/constStr 0))) (letVal "piece" (ty/opConst (ty/constStr 1))))
            (ty/termJump (edge "cat" (list "zero" "s0"))))
          (joinBlock "cat" (list "j" "s") (list (call "moreCat" "<" (list "j" "m")))
            (ty/termBranch "moreCat" (edge "catBody" (list)) (edge "catDone" (list))))
          (block "catBody" (list (call "s2" "stringConcat" (list "s" "piece")) (call "j2" "+" (list "j" "one")))
            (ty/termJump (edge "cat" (list "j2" "s2"))))
          (block "catDone"
            (list (call "len" "stringLength" (list "s"))
                  (letVal "p" (ty/opRecord "Point" (list "x" "y") (list "sum1" "len")))
                  (letVal "px" (ty/opField "p" "x"))
                  (letVal "py" (ty/opField "p" "y"))
                  (valInt "seven" 7) (ty/ssaInstr "rawSeven" (ty/tyI64) (ty/opConst (ty/constInt 7)))
                  (letVal "g7" (ty/opEntry "@listGetOr" (list "ys" "rawSeven" "zero")))
                  (letVal "wrapped" (ty/opConstruct "Option" "some" (list "g7")))
                  (letVal "w7" (ty/opVariantField "wrapped" 0))
                  (letVal "space" (ty/opConst (ty/constStr 2)))
                  (call "line" "str" (list "px" "space" "sum3" "space" "sum4" "space" "py" "space" "w7"))
                  (call "printed" "println" (list "line"))
                  (valInt "two" 2)
                  (call "nm1" "-" (list "n" "one"))
                  (call "prod" "*" (list "n" "nm1"))
                  (call "e1" "/" (list "prod" "two"))
                  (call "nk" "*" (list "n" "k"))
                  (call "e3" "+" (list "e1" "nk"))
                  (call "eLen" "*" (list "m" "two"))
                  (call "ok1" "=" (list "px" "e1"))
                  (call "ok2" "=" (list "sum3" "e3"))
                  (call "ok3" "=" (list "sum4" "e3"))
                  (call "ok4" "=" (list "py" "eLen"))
                  (call "ok5" "=" (list "w7" "seven"))
                  (letVal "oks" (ty/opList (list "ok1" "ok2" "ok3" "ok4" "ok5")))
                  (letVal "yes" (ty/opConst (ty/constBool true)))
                  (letVal "want" (ty/opList (list "yes" "yes" "yes" "yes" "yes")))
                  (call "allOk" "=" (list "oks" "want")))
            (ty/termBranch "allOk" (edge "pass" (list)) (edge "fail" (list))))
          (block "pass" (list) (ty/termReturn "zero"))
          (block "fail" (list) (ty/termReturn "one"))))

fn allocModule n: Int64 m: Int64 -> ty/SsaModule
  (ty/ssaModule "alloc" (list "" "ab" " ") (list (optionType)) (list (ty/ssaRecordDecl "Point" (list "x" "y"))) (list) (list)
    (list (addFn) (addKFn) (foldValsFn) (revValsFn) (mapValsFn) (rangeValsFn) (runFn n m)))

fn pair2Decl -> ty/SsaRecordDecl
  (ty/ssaRecordDecl "Pair2" (list "a" "b"))

fn fusedVariantFn name: String payload: ty/SsaConst t: ty/SsaTy test: (List ty/SsaInstr) -> ty/SsaFunction
  (valFn name (list) (list)
    (list (block "entry" (list (letVal "v" (ty/opConst payload)) (letVal "opt" (ty/opConstruct "Option" "some" (list "v"))))
            (ty/termSwitch "opt" "Option" (list (ty/ssaCase "some" (edge "someArm" (list))) (ty/ssaCase "none" (edge "noneArm" (list)))) (none)))
          (block "someArm"
            (listAppend (cons (letVal "x" (ty/opVariantField "opt" 0)) (cons (ty/ssaInstr "xi" t (ty/opUnbox "x")) test))
                        (list (valInt "yes" 0) (valInt "no" 1)))
            (ty/termBranch "ok" (edge "pass" (list)) (edge "fail" (list))))
          (block "noneArm" (list (valInt "bad" 1)) (ty/termReturn "bad"))
          (block "pass" (list) (ty/termReturn "yes"))
          (block "fail" (list) (ty/termReturn "no"))))

fn fusedVariantIntFn -> ty/SsaFunction
  (fusedVariantFn "fusedVariantInt" (ty/constInt 41) (ty/tyI64)
    (list (ty/ssaInstr "one" (ty/tyI64) (ty/opConst (ty/constInt 1)))
          (ty/ssaInstr "sum" (ty/tyI64) (ty/opPrim "addInt" (list "xi" "one")))
          (ty/ssaInstr "want" (ty/tyI64) (ty/opConst (ty/constInt 42)))
          (ty/ssaInstr "ok" (ty/tyI1) (ty/opPrim "eqInt" (list "sum" "want")))))

fn fusedVariantFloatFn -> ty/SsaFunction
  (fusedVariantFn "fusedVariantFloat" (ty/constFloat 41.5) (ty/tyF64)
    (list (ty/ssaInstr "half" (ty/tyF64) (ty/opConst (ty/constFloat 0.5)))
          (ty/ssaInstr "sum" (ty/tyF64) (ty/opPrim "addFloat" (list "xi" "half")))
          (ty/ssaInstr "want" (ty/tyF64) (ty/opConst (ty/constFloat 42.0)))
          (ty/ssaInstr "ok" (ty/tyI1) (ty/opPrim "eqFloat" (list "sum" "want")))))

fn fusedVariantBoolFn -> ty/SsaFunction
  (fusedVariantFn "fusedVariantBool" (ty/constBool true) (ty/tyI1) (list (ty/ssaInstr "ok" (ty/tyI1) (ty/opPrim "eqBool" (list "xi" "xi")))))

fn fusedVariantRangeFn -> ty/SsaFunction
  (valFn "fusedVariantRange" (list) (list)
    (list (block "entry" (list (letVal "v" (ty/opConst (ty/constInt 1))) (letVal "opt" (ty/opConstruct "Option" "some" (list "v"))) (letVal "x" (ty/opVariantField "opt" 1)) (ty/ssaInstr "xi" (ty/tyI64) (ty/opUnbox "x")) (letVal "boxed" (ty/opBox "xi"))) (ty/termReturn "boxed"))))

fn fusedVariantWrongTagFn -> ty/SsaFunction
  (valFn "fusedVariantWrongTag" (list) (list)
    (list (block "entry" (list (letVal "v" (ty/opConst (ty/constStr 0))) (letVal "opt" (ty/opConstruct "Option" "some" (list "v"))) (letVal "x" (ty/opVariantField "opt" 0)) (ty/ssaInstr "xi" (ty/tyI64) (ty/opUnbox "x")) (letVal "boxed" (ty/opBox "xi"))) (ty/termReturn "boxed"))))

fn fusedRecordIntFn -> ty/SsaFunction
  (valFn "fusedRecordInt" (list) (list)
    (list (block "entry"
            (list (valInt "a" 10) (valInt "b" 32) (letVal "p" (ty/opRecord "Pair2" (list "a" "b") (list "a" "b")))
                  (letVal "xv" (ty/opField "p" "a")) (ty/ssaInstr "xi" (ty/tyI64) (ty/opUnbox "xv"))
                  (letVal "yv" (ty/opField "p" "b")) (ty/ssaInstr "yi" (ty/tyI64) (ty/opUnbox "yv"))
                  (ty/ssaInstr "sum" (ty/tyI64) (ty/opPrim "addInt" (list "xi" "yi")))
                  (ty/ssaInstr "want" (ty/tyI64) (ty/opConst (ty/constInt 42)))
                  (ty/ssaInstr "ok" (ty/tyI1) (ty/opPrim "eqInt" (list "sum" "want")))
                  (valInt "yes" 0) (valInt "no" 1))
            (ty/termBranch "ok" (edge "pass" (list)) (edge "fail" (list))))
          (block "pass" (list) (ty/termReturn "yes"))
          (block "fail" (list) (ty/termReturn "no"))))

fn fusedRecordMissingKeyFn -> ty/SsaFunction
  (valFn "fusedRecordMissingKey" (list) (list)
    (list (block "entry" (list (valInt "a" 10) (valInt "b" 32) (letVal "p" (ty/opRecord "Pair2" (list "a" "b") (list "a" "b"))) (letVal "xv" (ty/opField "p" "missing")) (ty/ssaInstr "xi" (ty/tyI64) (ty/opUnbox "xv")) (letVal "boxed" (ty/opBox "xi"))) (ty/termReturn "boxed"))))

fn staticFieldRecordFn -> ty/SsaFunction
  (valFn "staticFieldRecord" (list) (list)
    (list (block "entry"
            (list (valInt "a" 10) (valInt "b" 32) (letVal "p" (ty/opRecord "Pair2" (list "a" "b") (list "a" "b")))
                  (letVal "xv" (ty/opField "p" "a")) (letVal "yv" (ty/opField "p" "b"))
                  (valInt "wantA" 10) (valInt "wantB" 32)
                  (call "okA" "=" (list "xv" "wantA")) (call "okB" "=" (list "yv" "wantB")))
            (ty/termBranch "okA" (edge "checkB" (list)) (edge "fail" (list))))
          (block "checkB" (list) (ty/termBranch "okB" (edge "pass" (list)) (edge "fail" (list))))
          (block "pass" (list (valInt "zero" 0)) (ty/termReturn "zero"))
          (block "fail" (list (valInt "one" 1)) (ty/termReturn "one"))))

fn staticFieldMissingFn -> ty/SsaFunction
  (valFn "staticFieldMissing" (list) (list)
    (list (block "entry" (list (valInt "a" 10) (valInt "b" 32) (letVal "p" (ty/opRecord "Pair2" (list "a" "b") (list "a" "b"))) (letVal "xv" (ty/opField "p" "missing"))) (ty/termReturn "xv"))))

fn preludeInlineFn -> ty/SsaFunction
  (ty/ssaFunction "preludeInline" (list) (list) (ty/tyI64)
    (list (block "entry"
            (list (valInt "n1" 1) (valInt "n2" 2) (valInt "n3" 3)
                  (letVal "nilList" (ty/opList (list)))
                  (letVal "c3" (ty/opEntry "cons" (list "n3" "nilList")))
                  (letVal "c2" (ty/opEntry "cons" (list "n2" "c3")))
                  (letVal "xs" (ty/opEntry "cons" (list "n1" "c2")))
                  (letVal "h" (ty/opEntry "listHead" (list "xs")))
                  (letVal "hv" (ty/opVariantField "h" 0))
                  (ty/ssaInstr "hvi" (ty/tyI64) (ty/opUnbox "hv"))
                  (letVal "t" (ty/opEntry "listTail" (list "xs")))
                  (letVal "tv" (ty/opVariantField "t" 0))
                  (direct "tlen" "lengthVals" (list "tv"))
                  (ty/ssaInstr "tleni" (ty/tyI64) (ty/opUnbox "tlen"))
                  (ty/ssaInstr "e1" (ty/tyI1) (ty/opEntry "listEmpty?" (list "nilList")))
                  (ty/ssaInstr "e2" (ty/tyI1) (ty/opEntry "listEmpty?" (list "xs"))))
            (ty/termBranch "e1" (edge "checkE2" (list)) (edge "listFail" (list))))
          (block "checkE2" (list) (ty/termBranch "e2" (edge "listFail" (list)) (edge "listOk" (list))))
          (block "listFail" (list (ty/ssaInstr "bad" (ty/tyI64) (ty/opConst (ty/constInt -1)))) (ty/termReturn "bad"))
          (block "listOk"
            (list (ty/ssaInstr "sumHT" (ty/tyI64) (ty/opPrim "addInt" (list "hvi" "tleni")))
                  (ty/ssaInstr "bsz" (ty/tyI64) (ty/opConst (ty/constInt 4)))
                  (ty/ssaInstr "idx0" (ty/tyI64) (ty/opConst (ty/constInt 0)))
                  (ty/ssaInstr "idx3" (ty/tyI64) (ty/opConst (ty/constInt 3)))
                  (ty/ssaInstr "byteA" (ty/tyI64) (ty/opConst (ty/constInt 65)))
                  (ty/ssaInstr "byteB" (ty/tyI64) (ty/opConst (ty/constInt 200)))
                  (letVal "bAlloc" (ty/opEntry "bytesAlloc" (list "bsz")))
                  (letVal "u1" (ty/opEntry "bytesSet" (list "bAlloc" "idx0" "byteA")))
                  (letVal "u2" (ty/opEntry "bytesSet" (list "bAlloc" "idx3" "byteB")))
                  (ty/ssaInstr "blen" (ty/tyI64) (ty/opEntry "bytesLength" (list "bAlloc")))
                  (ty/ssaInstr "v0" (ty/tyI64) (ty/opEntry "bytesGet" (list "bAlloc" "idx0")))
                  (ty/ssaInstr "v3" (ty/tyI64) (ty/opEntry "bytesGet" (list "bAlloc" "idx3")))
                  (ty/ssaInstr "bv" (ty/tyI64) (ty/opPrim "addInt" (list "v0" "v3")))
                  (ty/ssaInstr "bsum" (ty/tyI64) (ty/opPrim "addInt" (list "blen" "bv")))
                  (ty/ssaInstr "total" (ty/tyI64) (ty/opPrim "addInt" (list "sumHT" "bsum"))))
            (ty/termReturn "total"))))

fn preludeInlineConsBadFn -> ty/SsaFunction
  (valFn "preludeInlineConsBad" (list) (list)
    (list (block "entry" (list (valInt "n1" 1) (valInt "n2" 2) (letVal "r" (ty/opEntry "cons" (list "n1" "n2")))) (ty/termReturn "r"))))

fn preludeInlineListHeadBadFn -> ty/SsaFunction
  (valFn "preludeInlineListHeadBad" (list) (list)
    (list (block "entry" (list (valInt "n1" 1) (letVal "r" (ty/opEntry "listHead" (list "n1")))) (ty/termReturn "r"))))

fn preludeInlineListTailBadFn -> ty/SsaFunction
  (valFn "preludeInlineListTailBad" (list) (list)
    (list (block "entry" (list (valInt "n1" 1) (letVal "r" (ty/opEntry "listTail" (list "n1")))) (ty/termReturn "r"))))

fn preludeInlineListEmptyBadFn -> ty/SsaFunction
  (ty/ssaFunction "preludeInlineListEmptyBad" (list) (list) (ty/tyI1)
    (list (block "entry" (list (valInt "n1" 1) (ty/ssaInstr "r" (ty/tyI1) (ty/opEntry "listEmpty?" (list "n1")))) (ty/termReturn "r"))))

fn preludeInlineBytesLengthBadFn -> ty/SsaFunction
  (ty/ssaFunction "preludeInlineBytesLengthBad" (list) (list) (ty/tyI64)
    (list (block "entry" (list (valInt "n1" 1) (ty/ssaInstr "r" (ty/tyI64) (ty/opEntry "bytesLength" (list "n1")))) (ty/termReturn "r"))))

fn failModule -> ty/SsaModule
  (ty/ssaModule "fail" (list "boom") (list (optionType) (triType)) (list (pair2Decl)) (list) (list)
    (list (addFn)
          (fusedVariantIntFn) (fusedVariantFloatFn) (fusedVariantBoolFn)
          (fusedVariantRangeFn) (fusedVariantWrongTagFn)
          (fusedRecordIntFn) (fusedRecordMissingKeyFn)
          (staticFieldRecordFn) (staticFieldMissingFn)
          (valFn "switchPick" (list) (list)
            (list (block "entry" (list (letVal "t" (ty/opConstruct "Tri" "third" (list))) (letVal "u" (ty/opConstruct "Tri" "second" (list))))
                    (ty/termSwitch "t" "Tri" (list (ty/ssaCase "first" (edge "one" (list))) (ty/ssaCase "second" (edge "two" (list))) (ty/ssaCase "third" (edge "check" (list)))) (none)))
                  (block "check" (list) (ty/termSwitch "u" "Tri" (list (ty/ssaCase "first" (edge "one" (list))) (ty/ssaCase "second" (edge "three" (list))) (ty/ssaCase "third" (edge "two" (list)))) (none)))
                  (block "one" (list (valInt "r1" 1)) (ty/termReturn "r1"))
                  (block "two" (list (valInt "r2" 2)) (ty/termReturn "r2"))
                  (block "three" (list (valInt "r3" 3)) (ty/termReturn "r3"))))
          (valFn "switchInt" (list) (list)
            (list (block "entry" (list (valInt "one" 1)) (ty/termSwitch "one" "Option" (list (ty/ssaCase "some" (edge "yes" (list)))) (some (edge "no" (list)))))
                  (block "yes" (list) (ty/termReturn "one"))
                  (block "no" (list) (ty/termReturn "one"))))
          (valFn "switchForeign" (list) (list)
            (list (block "entry" (list (letVal "t" (ty/opConstruct "Tri" "first" (list)))) (ty/termSwitch "t" "Option" (list (ty/ssaCase "some" (edge "yes" (list)))) (some (edge "no" (list)))))
                  (block "yes" (list) (ty/termReturn "t"))
                  (block "no" (list) (ty/termReturn "t"))))
          (valFn "noMatch" (list) (list)
            (list (block "entry" (list (letVal "n" (ty/opConstruct "Option" "none" (list))))
                    (ty/termSwitch "n" "Option" (list (ty/ssaCase "some" (edge "onSome" (list)))) (some (edge "nomatch" (list)))))
                  (block "onSome" (list (letVal "x" (ty/opVariantField "n" 0))) (ty/termReturn "x"))
                  (block "nomatch" (list) (ty/termUnreachable))))
          (valFn "negate" (list) (list)
            (list (block "entry" (list (valInt "seven" 7) (valInt "fortyNine" 49) (call "neg" "-" (list "seven")) (call "r" "+" (list "neg" "fortyNine"))) (ty/termReturn "r"))))
          (valFn "negateFloat" (list) (list)
            (list (block "entry" (list (letVal "x" (ty/opConst (ty/constFloat 2.5))) (letVal "want" (ty/opConst (ty/constFloat -2.5))) (call "neg" "-" (list "x")) (call "same" "=" (list "neg" "want")) (valInt "zero" 0) (valInt "one" 1))
                    (ty/termBranch "same" (edge "yes" (list)) (edge "no" (list))))
                  (block "yes" (list) (ty/termReturn "zero"))
                  (block "no" (list) (ty/termReturn "one"))))
          (valFn "negateMin" (list) (list)
            (list (block "entry" (list (valInt "min" -9223372036854775807) (valInt "one" 1) (call "m" "-" (list "min" "one")) (call "neg" "-" (list "m"))) (ty/termReturn "neg"))))
          (valFn "negateText" (list) (list)
            (list (block "entry" (list (letVal "s" (ty/opConst (ty/constUnit))) (call "neg" "-" (list "s"))) (ty/termReturn "neg"))))
          (valFn "asserts" (list) (list)
            (list (block "entry" (list (letVal "yes" (ty/opConst (ty/constBool true))) (letVal "no" (ty/opConst (ty/constBool false)))
                                       (letVal "why" (ty/opConst (ty/constStr 0)))
                                       (call "a1" "assert" (list "yes")) (call "a2" "assert" (list "yes" "why")) (call "r1" "refute" (list "no" "why"))
                                       (call "a3" "assert" (list "no" "why")))
                    (ty/termReturn "a3"))))
          (valFn "divZero" (list) (list) (list (block "entry" (list (valInt "one" 1) (valInt "zero" 0) (call "q" "/" (list "one" "zero"))) (ty/termReturn "q"))))
          (valFn "headNone" (list) (list)
            (list (block "entry" (list (letVal "empty" (ty/opList (list))) (call "h" "listHead" (list "empty")) (letVal "x" (ty/opVariantField "h" 0))) (ty/termReturn "x"))))
          (lengthValsFn) (preludeInlineFn)
          (preludeInlineConsBadFn) (preludeInlineListHeadBadFn) (preludeInlineListTailBadFn)
          (preludeInlineListEmptyBadFn) (preludeInlineBytesLengthBadFn)
          (valFn "arity" (list) (list)
            (list (block "entry" (list (valInt "one" 1) (letVal "add" (ty/opMakeClosure "add" (list))) (letVal "r" (ty/opCallClosure "add" (list "one")))) (ty/termReturn "r"))))
          (valFn "notBool" (list) (list)
            (list (block "entry" (list (valInt "one" 1)) (ty/termBranch "one" (edge "yes" (list)) (edge "no" (list))))
                  (block "yes" (list) (ty/termReturn "one"))
                  (block "no" (list) (ty/termReturn "one"))))))

fn resultType -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Result" (list (ty/ssaVariant "ok" 1) (ty/ssaVariant "err" 1)))

fn unknownModule -> ty/SsaModule
  (ty/ssaModule "unknown" (list) (list) (list) (list) (list)
    (list (valFn "unknown" (list) (list)
            (list (block "entry" (list (valInt "one" 1) (call "r" "no-such-builtin" (list "one"))) (ty/termReturn "r"))))))

fn mainModule -> ty/SsaModule
  (ty/ssaModule "mainArgs" (list "(\"ab\" \"cde\")" "boom") (list (resultType)) (list) (list) (list)
    (list (valFn "joined" (list) (list "args")
            (list (block "entry" (list (letVal "want" (ty/opConst (ty/constStr 0)))
                                       (call "text" "str" (list "args")) (call "same" "=" (list "text" "want"))
                                       (valInt "yes" 42) (valInt "no" 3))
                    (ty/termBranch "same" (edge "pass" (list)) (edge "fail" (list))))
                  (block "pass" (list (letVal "r" (ty/opConstruct "Result" "ok" (list "yes")))) (ty/termReturn "r"))
                  (block "fail" (list (letVal "r3" (ty/opConstruct "Result" "ok" (list "no")))) (ty/termReturn "r3"))))
          (valFn "failed" (list) (list "args")
            (list (block "entry" (list (letVal "msg" (ty/opConst (ty/constStr 1))) (letVal "r" (ty/opConstruct "Result" "err" (list "msg")))) (ty/termReturn "r"))))
          (valFn "tooBig" (list) (list "args")
            (list (block "entry" (list (valInt "n" 256) (letVal "r" (ty/opConstruct "Result" "ok" (list "n")))) (ty/termReturn "r"))))))

fn tailModule -> ty/SsaModule
  (ty/ssaModule "tail" (list) (list) (list) (list) (list)
    (list (valFn "countDown" (list) (list "n" "acc")
            (list (block "entry" (list (valInt "zero" 0) (call "done" "=" (list "n" "zero")))
                    (ty/termBranch "done" (edge "base" (list)) (edge "step" (list))))
                  (block "base" (list) (ty/termJump (edge "join" (list "acc"))))
                  (block "step" (list (valInt "one" 1) (call "n1" "-" (list "n" "one")) (call "acc1" "+" (list "acc" "one"))
                                      (letVal "r" (ty/opCall "countDown" (list "n1" "acc1"))))
                    (ty/termJump (edge "join" (list "r"))))
                  (joinBlock "join" (list "res") (list) (ty/termReturn "res"))))
          (valFn "spin" (list) (list "n")
            (list (block "entry" (list (valInt "zero" 0) (call "done" "=" (list "n" "zero")))
                    (ty/termBranch "done" (edge "base" (list)) (edge "step" (list))))
                  (block "base" (list) (ty/termReturn "n"))
                  (block "step" (list (valInt "one" 1) (call "n1" "-" (list "n" "one")) (letVal "r" (ty/opCall "spin" (list "n1"))))
                    (ty/termReturn "r"))))
          (valFn "nestDown" (list) (list "n" "acc")
            (list (block "entry" (list (valInt "zero" 0) (call "done" "=" (list "n" "zero")))
                    (ty/termBranch "done" (edge "base" (list)) (edge "step" (list))))
                  (block "base" (list) (ty/termJump (edge "outer" (list "acc"))))
                  (block "step" (list (valInt "one" 1) (call "n1" "-" (list "n" "one")) (call "acc1" "+" (list "acc" "one"))
                                      (letVal "r" (ty/opCall "nestDown" (list "n1" "acc1"))))
                    (ty/termJump (edge "inner" (list "r"))))
                  (joinBlock "inner" (list "ir") (list) (ty/termJump (edge "outer" (list "ir"))))
                  (joinBlock "outer" (list "res") (list) (ty/termReturn "res"))))
          (valFn "deepTail" (list) (list)
            (list (block "entry" (list (valInt "deep" 1000000) (valInt "zero" 0)
                                       (letVal "a" (ty/opCall "countDown" (list "deep" "zero")))
                                       (letVal "b" (ty/opCall "spin" (list "deep")))
                                       (letVal "c" (ty/opCall "nestDown" (list "deep" "zero")))
                                       (letVal "got" (ty/opList (list "a" "b" "c"))) (letVal "want" (ty/opList (list "deep" "zero" "deep")))
                                       (call "ok" "=" (list "got" "want")) (valInt "yes" 42) (valInt "no" 1))
                    (ty/termBranch "ok" (edge "pass" (list)) (edge "fail" (list))))
                  (block "pass" (list) (ty/termReturn "yes"))
                  (block "fail" (list) (ty/termReturn "no"))))))

fn nestedTailSource -> String
  (stringJoin
    (list
      "(module nested :x [walk nestedMain])"
      ""
      "(fn walk [(n Int64) (acc Int64)] -> Int64"
      "  (if (= n 0)"
      "    acc"
      "    (mt (some (mod n 2))"
      "      ((some r) (if (= r 0)"
      "                  (if (= (mod n 3) 0) (walk (- n 1) (+ acc 1)) (walk (- n 1) acc))"
      "                  (walk (- n 1) acc)))"
      "      ((none) acc))))"
      ""
      "(fn nestedMain [] -> Int64"
      "  (if (= (walk 1000000 0) 166666) 42 1))")
    "\n")

fn program name: String -> (Result String (List ty/IrDiag))
  (cond
    ((= name "deepTail") (llvm/emitLlvmProgram (tailModule) name))
    ((= name "unknown") (llvm/emitLlvmProgram (unknownModule) name))
    ((= name "nestedTail") (llvm/emitLlvmSource (nestedTailSource) "nestedMain"))
    ((listContains? (list "joined" "failed" "tooBig") name) (llvm/emitLlvmProgram (mainModule) name))
    ((= name "alloc") (llvm/emitLlvmProgram (allocModule 100000 20000) "run"))
    ((= name "allocSmall") (llvm/emitLlvmProgram (allocModule 300 100) "run"))
    (else (llvm/emitLlvmProgram (failModule) name)))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listHead args)
    ((none) (err "usage: abiPrograms.asl alloc|allocSmall|divZero|headNone|preludeInline|preludeInlineConsBad|preludeInlineListHeadBad|preludeInlineListTailBad|preludeInlineListEmptyBad|preludeInlineBytesLengthBad|arity|unknown|notBool|noMatch|asserts|negate|negateFloat|negateMin|negateText|joined|failed|tooBig|deepTail|nestedTail|fusedVariantInt|fusedVariantFloat|fusedVariantBool|fusedVariantRange|fusedVariantWrongTag|fusedRecordInt|fusedRecordMissingKey|staticFieldRecord|staticFieldMissing"))
    ((some name) (mt (program name)
                   ((ok text) (do (print text) (ok 0)))
                   ((err diags) (err (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) diags) "; "))))))
