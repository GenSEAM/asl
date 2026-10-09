(module asl-compiler/targetsLlvmDiagTest
  :x [testValidProgramCompilesOk testMissingEntryDiagnostic testPreludeProgramCompiles runTests]
  :i [(asl-compiler/compiler :a comp)
      (asl-compiler/targets :a tg)])

fn validProgramSource -> Str
  "(module validApp :x [entry])\n\n(fn entry [] -> Int64\n  42)\n"

fn noMainProgramSource -> Str
  "(module noMainApp :x [foo])\n\n(fn foo [] -> Int64\n  42)\n"

fn definesFunction? code: Str symbol: Str -> Bool
  (listAny? (fn [(l Str)] -> Bool (and (stringStartsWith? l "define ") (stringContains? l (str " " symbol " {")))) (stringLines code))

fn testValidProgramCompilesOk prelude: Str -> Bool
  (let [(res (tg/compileStandaloneTarget (validProgramSource) "llvm" "valid.asl" prelude))]
    (do
      (assert res.ok "valid program compiles ok through llvm target")
      (refute (not res.ok) "valid program compile result ok is not false")
      (assert (> (stringLength res.code) 0) "emitted llvm code is not empty")
      (assert (definesFunction? res.code "@entry()") "emitted llvm code defines entry function")
      (assert (stringContains? res.code "define i32 @main()") "emitted llvm code defines main wrapper")
      (assert (listEmpty? res.diagnostics) "diagnostics list is empty for valid compile")
      true))

fn testMissingEntryDiagnostic prelude: Str -> Bool
  (let [(res (tg/compileStandaloneTarget (noMainProgramSource) "llvm" "noMain.asl" prelude))]
    (do
      (assert (not res.ok) "program missing entry function fails compile")
      (refute res.ok "compile result ok is false")
      (assert (= res.code "") "emitted code is empty on failure")
      (assert (= (listLength res.diagnostics) 1) "exactly one diagnostic returned")
      (let [(diag (optionOr (listHead res.diagnostics) ""))]
        (do
          (assert (stringContains? diag "ERR_LLVM_NO_ENTRY") "diagnostic contains IrDiag code ERR_LLVM_NO_ENTRY")
          (assert (stringContains? diag "entry function entry is not defined") "diagnostic names the entry the llvm target needs")
          true))))

fn mainOnlyProgramSource -> Str
  "(module mainApp :x [main])\n\n(fn main [] -> Int64\n  42)\n"

fn testMainOnlyProgramNamesEntry prelude: Str -> Bool
  (let [(res (tg/compileStandaloneTarget (mainOnlyProgramSource) "llvm" "mainApp.asl" prelude))
        (diag (optionOr (listHead res.diagnostics) ""))]
    (do
      (refute res.ok "a program with only fn main does not compile through the llvm target")
      (assert (stringContains? diag "entry function entry is not defined") (str "the diagnostic asks for fn entry, got " diag))
      true))

fn preludeProgramSource -> Str
  "(module preludeApp :x [entry main])\n\n(fn entry [] -> Int64\n  (+ (fold (fn [acc x] (+ acc x)) 0 (range 0 4)) (stringLength (stringJoin (list \"a\" \"b\") \",\"))))\n\n(fn main [] -> Int64\n  (entry))\n"

fn testPreludeProgramCompiles prelude: Str -> Bool
  (let [(ll (tg/compileStandaloneTarget (preludeProgramSource) "llvm" "preludeApp.asl" prelude))
        (c (tg/compileStandaloneTarget (preludeProgramSource) "c11" "preludeApp.asl" prelude))]
    (do
      (assert ll.ok (str "the llvm target compiles a program calling prelude functions: " (stringJoin ll.diagnostics "; ")))
      (assert (definesFunction? ll.code "@prelude$2Efold(%Val %f, %Val %init, %Val %xs)") "the llvm code defines prelude.fold")
      (assert (stringContains? ll.code "@prelude$2EstringJoin(") "the llvm code calls prelude.stringJoin")
      (assert c.ok (str "the c11 target compiles a program calling prelude functions: " (stringJoin c.diagnostics "; ")))
      (assert (stringContains? c.code "fold") "the c11 code carries prelude.fold")
      true))

fn ! runTests -> Bool
  (let [(prelude (mt (fileRead "asl/prelude/prelude.asl") ((ok text) text) ((err e) (do (assert false (str "asl/prelude/prelude.asl is readable: " e)) ""))))]
    (do
      (assert (testMainOnlyProgramNamesEntry prelude) "testMainOnlyProgramNamesEntry must pass")
      (assert (testValidProgramCompilesOk prelude) "testValidProgramCompilesOk must pass")
      (assert (testMissingEntryDiagnostic prelude) "testMissingEntryDiagnostic must pass")
      (assert (testPreludeProgramCompiles prelude) "testPreludeProgramCompiles must pass")
      true))
