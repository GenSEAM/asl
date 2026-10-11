(module asl-target-llvm/tests/wasmImportTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)])

fn singleCallProbe name: String arity: Int64 -> ty/SsaModule
  (ty/ssaModule (str "wasm" name "Probe") (list) (list) (list) (list) (list)
    (list (ty/ssaFunction "main" (list) (list) (ty/tyVal)
      (list (ty/ssaBlock "entry" (list)
        (if (<= arity 0)
          (list (ty/ssaInstr "result" (ty/tyVal) (ty/opBuiltin name (list))))
          (list (ty/ssaInstr "arg" (ty/tyVal) (ty/opConst (ty/constUnit)))
                (ty/ssaInstr "result" (ty/tyVal) (ty/opBuiltin name (list "arg")))))
        (ty/termReturn "result"))))))

fn variadicPrintProbe strings: (List String) -> ty/SsaModule
  (ty/ssaModule "wasmVariadicPrintProbe" strings (list) (list) (list) (list)
    (list (ty/ssaFunction "main" (list) (list) (ty/tyVal)
      (list (ty/ssaBlock "entry" (list)
        (list (ty/ssaInstr "emptyPrint" (ty/tyVal) (ty/opBuiltin "print" (list)))
              (ty/ssaInstr "left" (ty/tyVal) (ty/opConst (ty/constUnit)))
              (ty/ssaInstr "right" (ty/tyVal) (ty/opConst (ty/constUnit)))
              (ty/ssaInstr "printed" (ty/tyVal) (ty/opBuiltin "print" (list "left" "right"))))
        (ty/termReturn "printed"))))))

fn wasmFacts -> libc/TripleFacts
  (let [(f (libc/emptyTripleFacts))]
    (libc/TripleFacts :triple "wasm32-wasi" :verified false :errnoAccessor f.errnoAccessor :consts f.consts :variadic f.variadic :structs f.structs))

fn hasImport m: ty/SsaModule name: String -> Bool
  (listAny? (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs)

fn importedCall m: ty/SsaModule name: String -> Bool
  (let [(f (optionOr (listHead m.functions) (ty/ssaFunction "missing" (list) (list) (ty/tyVal) (list))))]
    (listAny? (fn [(b ty/SsaBlock)] -> Bool
      (listAny? (fn [(i ty/SsaInstr)] -> Bool
        (mt i.op ((ty/opCall callee _) (= callee name)) (_ false))) b.instrs)) f.blocks))

fn importedExtern m: ty/SsaModule name: String -> (Option ty/SsaExtern)
  (listHead (filter (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs))

fn hasSignature m: ty/SsaModule name: String arity: Int64 -> Bool
  (mt (importedExtern m name)
    ((none) false)
    ((some e) (and (= e.arity arity) (= (listLength e.params) arity)
                   (listAll? (fn [(p ty/SsaTy)] -> Bool (= p (ty/tyVal))) e.params)
                   (= e.ret (ty/tyVal)))))

fn hasAbsentCapability result: (Result rt/Routed (List ty/IrDiag)) name: String -> Bool
  (mt result
    ((ok _) false)
    ((err diags) (listAny? (fn [(d ty/IrDiag)] -> Bool
      (and (= d.code "ERR_CAPABILITY_ABSENT") (stringContains? d.message name) (stringContains? d.message "wasm32-wasi"))) diags)))

fn unverifiableProbe -> ty/SsaModule
  (ty/ssaModule "wasmInvalidProbe" (list) (list) (list) (list) (list)
    (list (ty/ssaFunction "main" (list) (list) (ty/tyVal)
      (list (ty/ssaBlock "entry" (list) (list) (ty/termReturn "missing"))))))

fn preservesVerifierDiagnostics m: ty/SsaModule -> Bool
  (mt (vfy/verifySsa m)
    ((err expected) (mt (rt/routeModule (wasmFacts) m) ((err actual) (= actual expected)) (_ false)))
    (_ false))

fn printCallDests b: ty/SsaBlock -> (List String)
  (fold (fn [(dests (List String)) (i ty/SsaInstr)] -> (List String)
    (mt i.op ((ty/opCall name args) (if (and (= name "print") (= (listLength args) 1)) (listAppend dests (list i.dest)) dests)) (_ dests)))
    (list) b.instrs)

fn printCallArgs b: ty/SsaBlock -> (List String)
  (fold (fn [(argsOut (List String)) (i ty/SsaInstr)] -> (List String)
    (mt i.op ((ty/opCall name args) (if (and (= name "print") (= (listLength args) 1)) (listAppend argsOut args) argsOut)) (_ argsOut)))
    (list) b.instrs)

fn spaceConstant? strings: (List String) dest: String i: ty/SsaInstr -> Bool
  (if (not (= i.dest dest))
    false
    (mt i.op
      ((ty/opConst c) (mt c ((ty/constStr index) (= (listGet strings index) (some " "))) (_ false)))
      (_ false)))

fn hasSpacePrintArg strings: (List String) b: ty/SsaBlock -> Bool
  (let [(args (printCallArgs b)) (spaceArg (optionOr (listGet args 1) ""))]
    (and (= (listLength args) 3)
      (listAny? (fn [(c ty/SsaInstr)] -> Bool (spaceConstant? strings spaceArg c)) b.instrs)))

fn uniquePrintDests m: ty/SsaModule -> Bool
  (mt (listHead m.functions)
    ((none) false)
    ((some f) (mt (listHead f.blocks) ((none) false) ((some b)
      (let [(dests (printCallDests b))]
        (let [(first (optionOr (listGet dests 0) "")) (second (optionOr (listGet dests 1) "")) (third (optionOr (listGet dests 2) ""))]
          (and (= (listLength dests) 3) (not (= first second)) (not (= first third)) (not (= second third)) (= third "printed") (hasSpacePrintArg m.strings b))))))))

fn verifiesModule m: ty/SsaModule -> Bool
  (ok? (vfy/verifySsa m))

fn absentCases -> (List (Pair String Int64))
  (list (pair "nowNs" 0) (pair "nowNs" 1) (pair "monotonicNs" 0) (pair "fileReadString" 1) (pair "fileReadBytes" 1) (pair "envGet" 1) (pair "tcpListen" 0))

fn assertAbsent entry: (Pair String Int64) -> Bool
  (do (assert (hasAbsentCapability (rt/routeModule (wasmFacts) (singleCallProbe (pairFirst entry) (pairSecond entry))) (pairFirst entry))
              (str (pairFirst entry) " (arity " (pairSecond entry) ") is rejected with ERR_CAPABILITY_ABSENT on wasm32-wasi"))
      true)

fn runTests -> Bool
  (let [(printOnly (rt/routeModule (wasmFacts) (singleCallProbe "print" 1)))
        (variadicPrint (rt/routeModule (wasmFacts) (variadicPrintProbe (list))))
        (printWithoutSpace (rt/routeModule (wasmFacts) (variadicPrintProbe (list "existing"))))
        (printWithSpace (rt/routeModule (wasmFacts) (variadicPrintProbe (list "existing" " "))))
        (invalid (unverifiableProbe))]
    (do
      (assert (mt printOnly ((ok r) (hasImport r.result "print")) ((err _) false)) "print is declared as a wasm host import")
      (assert (mt printOnly ((ok r) (importedCall r.result "print")) ((err _) false)) "print builtin call resolves to the import")
      (assert (mt printOnly ((ok r) (hasSignature r.result "print" 1)) ((err _) false)) "print import declares one Val parameter and a Val result")
      (assert (mt printOnly ((ok r) (= (listLength r.result.externs) 1)) ((err _) false)) "a print-only module declares exactly one host import")
      (assert (mt variadicPrint ((ok r) (verifiesModule r.result)) ((err _) false)) "variadic print routed module verifies")
      (assert (mt variadicPrint ((ok r) (uniquePrintDests r.result)) ((err _) false)) "variadic print has spaced one-Val calls with unique destinations")
      (assert (mt printWithoutSpace ((ok r) (and (= r.result.strings (list "existing" " ")) (uniquePrintDests r.result))) ((err _) false)) "variadic print appends and references space after existing strings")
      (assert (mt printWithSpace ((ok r) (and (= r.result.strings (list "existing" " ")) (uniquePrintDests r.result))) ((err _) false)) "variadic print reuses space at its nonzero pool index")
      (map assertAbsent (absentCases))
      (assert (preservesVerifierDiagnostics invalid) "wasm32-wasi returns the verifier diagnostics for an unverifiable module without imports")
      true))
