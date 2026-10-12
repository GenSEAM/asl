(module asl-target-llvm/tests/nativeRunTest
  :x [runTests]
  :i [(asl-ir/types :a irTy) (asl-ir/lower :a low) (asl-ir/link :a lk) (asl-ir/printer :a prn) (asl-target-llvm :a llvm) (asl-target-llvm/ssa :a ssa) (asl-target-llvm/arrays :a arr) (asl-target-c/emit :a cem)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn irTest -> String
  "asl/packages/asl-target-llvm/tests/irE2eTest.asl"

fn abiTest -> String
  "asl/packages/asl-target-llvm/tests/abiPrograms.asl"

fn sourceTest -> String
  "asl/packages/asl-target-llvm/tests/sourceE2eTest.asl"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn asanLib -> String
  "asl/host/out/libaslrt-asan.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! exitOf cmd: String -> Int64
  (sh cmd).exitCode

fn ! expectExit label: String cmd: String want: Int64 -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " want "; stderr: " out.stderr))
        true))

fn ! emit work: String test: String fixture: String file: String -> Bool
  (expectExit (str file ": asl-host emits .ll") (str (host) " run " test " " fixture " > " work "/" file ".ll") 0)

fn ! link work: String file: String extra: String -> Bool
  (expectExit (str file ": links" extra) (str (clang) " -x ir " work "/" file ".ll -x none " extra " -lm -o " work "/" file) 0)

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (exitOf (str "test -x " c)) 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/opt/homebrew/opt/llvm@22/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listGet known 0)
      ((some o) (some o))
      ((none) (if (= (exitOf "command -v opt >/dev/null 2>&1") 0) (some "opt") (none)))))

fn ! verifyLl label: String work: String file: String -> Bool
  (mt (optBin)
    ((none) (do (println (str label ": opt not found on this host, skipping -passes=verify")) true))
    ((some o) (expectExit (str label ": opt -passes=verify accepts the emitted IR") (str o " -passes=verify -disable-output " work "/" file ".ll") 0)))

fn ! testIrFixtures work: String -> Bool
  (do
    (map (fn [(f String)] -> Bool
           (do (emit work (irTest) f f)
               (expectExit (str f ": .ll equals golden") (str "cmp -s " work "/" f ".ll asl/packages/asl-target-llvm/tests/golden/" f ".ll") 0)
               (expectExit (str f ": clang -c accepts it") (str (clang) " -x ir -c " work "/" f ".ll -o " work "/" f ".o") 0)))
         (list "fib" "loop" "switch" "ops" "fibRaw" "primCheck" "traps"))
    (link work "loop" "")
    (expectExit "loop: raw swap loop" (str work "/loop") 42)
    (link work "fib" (lib))
    (expectExit "fib: fib 10 over Val" (str work "/fib") 55)
    (link work "fibRaw" "")
    (expectExit "fibRaw: raw fib 10" (str work "/fibRaw") 55)
    (link work "primCheck" (lib))
    (expectExit "primCheck: every primitive computes natively" (str work "/primCheck") 0)
    true)

fn ! trapExit work: String entry: String -> Int64
  (do (emit work (irTest) (str "trap:" entry) entry)
      (link work entry (lib))
      (exitOf (str "(" work "/" entry ") 2>/dev/null")))

fn ! trapRun work: String entry: String -> ProcessOutput
  (do (emit work (irTest) (str "trap:" entry) entry)
      (link work entry (lib))
      (sh (str work "/" entry)))

fn ! testTraps work: String -> Bool
  (do (assert (= (trapExit work "control") 3) "control: quot 7 2 exits 3 without trapping")
    (assert (= (trapExit work "floatControl") 253) "floatControl: floatToInt of -3.5 exits 253 without trapping")
    (assert (= (trapExit work "narrowControl") 42) "narrowControl: rawNarrowI32 of 42 exits 42 without trapping")
    (map (fn [(e String)] -> Bool
           (let [(code (trapExit work e))]
             (do (assert (> code 128) (str e ": killed by a signal, got exit " code)) true)))
         (list "quotZero" "quotMin" "remZero" "addOver" "subOver" "mulOver"))
    (let [(nan (trapRun work "floatNan")) (huge (trapRun work "floatHuge")) (narrow (trapRun work "narrowOver"))]
      (do
        (assert (= nan.exitCode 1) (str "floatNan: exit " nan.exitCode))
        (assert (= nan.stderr "ERR_INT_OVERFLOW: Float to Int leaves int64\n") (str "floatNan: exact stderr match, got " nan.stderr))
        (assert (= huge.exitCode 1) (str "floatHuge: exit " huge.exitCode))
        (assert (= huge.stderr "ERR_INT_OVERFLOW: Float to Int leaves int64\n") (str "floatHuge: exact stderr match, got " huge.stderr))
        (assert (= narrow.exitCode 1) (str "narrowOver: exit " narrow.exitCode))
        (assert (= narrow.stderr "ERR_INT_OVERFLOW: Int narrow leaves int32\n") (str "narrowOver: exact stderr match, got " narrow.stderr))
        true))
    true)

fn ! testSourceFib work: String -> Bool
  (do
    (expectExit "sourceE2eTest passes" (str (host) " test " (sourceTest)) 0)
    (expectExit "source fib: asl-host emits .ll" (str (host) " run " (sourceTest) " > " work "/sourceFib.ll") 0)
    (link work "sourceFib" (lib))
    (expectExit "source fib: fib 10 over raw i64" (str work "/sourceFib") 55)
    true)

fn allocLine -> String
  "4999950000 5000250000 5000250000 40000 7\n"

fn smallLine -> String
  "44850 45750 45750 200 7\n"

fn ! expectClean label: String cmd: String line: String -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode 0) (str label ": exit " out.exitCode "; stderr: " out.stderr))
        (assert (= out.stdout line) (str label ": printed " out.stdout))
        (refute (stringContains? out.stderr "Sanitizer") (str label ": sanitizer report " out.stderr))
        true))

fn ! testAlloc work: String -> Bool
  (do
    (emit work (abiTest) "alloc" "alloc")
    (emit work (abiTest) "allocSmall" "allocSmall")
    (link work "alloc" (lib))
    (expectClean "alloc: 100k-element list, closures over fold and map, 20k concatenations" (str work "/alloc") (allocLine))
    (expectExit "ASan host library builds" "bash asl/host/build.sh --sanitize" 0)
    (expectExit "alloc: links against the ASan library" (str (clang) " -fsanitize=address,undefined -x ir " work "/alloc.ll -x none " (asanLib) " -lm -o " work "/allocAsan") 0)
    (expectClean "alloc under ASan" (str work "/allocAsan") (allocLine))
    (expectExit "allocSmall: links against the ASan library" (str (clang) " -fsanitize=address,undefined -x ir " work "/allocSmall.ll -x none " (asanLib) " -lm -o " work "/allocSmallAsan") 0)
    (expectClean "allocSmall under ASan collecting on every allocation" (str "ASL_GC_STRESS=1 " work "/allocSmallAsan") (smallLine))
    true)

fn ! nmNames bin: String -> (List String)
  (let [(out (sh (str "nm " bin)))]
    (do (assert (= out.exitCode 0) (str "nm " bin ": exit " out.exitCode "; stderr: " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listLast (stringSplit (stringTrim line) " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? (stringTrim line)))) (stringSplit out.stdout "\n")))))

fn sysTableSource -> String
  (stringJoin (list
    "(module sysTableMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (mt (fileAppend (optionOr (envGet \"SYS_TABLE_OUT\") \"\") \"sysTable:appended\\n\")"
    "    ((ok _) (ok 0))"
    "    ((err e) (err (str e))))")
    "\n")

fn quotedNames text: String -> (List String)
  (fold (fn [(acc (List String)) (piece String)] -> (List String)
          (mt (stringIndexOf piece "\"")
            ((some end) (if (> end 0) (listAppend acc (list (optionOr (stringSlice piece 0 end) ""))) acc))
            ((none) acc)))
        (list) (optionOr (listTail (stringSplit text "{\"")) (list)))

fn ! cTableText file: String table: String -> String
  (let [(text (fileText (str "asl/host/src/" file)))
        (open (str "const Builtin " table "[] = {"))
        (start (optionOr (stringIndexOf text open) -1))]
    (do (assert (>= start 0) (str file ": defines " open))
        (let [(rest (optionOr (stringSlice text (+ start (- (stringLength open) 1)) (stringLength text)) ""))]
          (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "};") 0)) ""))))

fn ! arrayTableNames -> (List String)
  (let [(text (fileText "asl/host/src/arrays.c"))
        (macro (optionOr (stringSlice text (optionOr (stringIndexOf text "#define ROWS(P)") 0) (stringLength text)) ""))
        (body (optionOr (stringSlice macro 0 (optionOr (stringIndexOf macro "const Builtin arrayBuiltins") 0)) ""))
        (ops (filter (fn [(n String)] -> Bool (stringStartsWith? n "Array")) (quotedNames (stringReplace body "#P \"" "{\""))))
        (rowsLine (cTableText "arrays.c" "arrayBuiltins"))
        (prefixes (fold (fn [(acc (List String)) (piece String)] -> (List String)
                          (mt (stringIndexOf piece ")") ((some end) (listAppend acc (list (optionOr (stringSlice piece 0 end) "")))) ((none) acc)))
                        (list) (optionOr (listTail (stringSplit rowsLine "ROWS(")) (list))))]
    (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (map (fn [(op String)] -> String (str p op)) ops))) (list) prefixes))

fn ! testArrayTableSync -> Bool
  (let [(want (listAppend (arrayTableNames) (quotedNames (cTableText "kernels.c" "kernelBuiltins"))))]
    (do
      (assert (= (listLength (arrayTableNames)) 27) (str "arrays.c's ROWS table parses to 27 names; got " (stringJoin (arrayTableNames) " ")))
      (assert (= (arr/arrayBuiltinNames) want) (str "arrays.asl arrayBuiltinNames lists " (stringJoin (arr/arrayBuiltinNames) " ") "; arrays.c and kernels.c have " (stringJoin want " ")))
      true))

fn ! testBuiltinTableSync -> Bool
  (let [(want (list (pair "sys" (quotedNames (cTableText "sys.c" "sysBuiltins")))
                    (pair "sysNet" (quotedNames (cTableText "sysNet.c" "sysNetBuiltins")))
                    (pair "parallel" (quotedNames (cTableText "parallel.c" "parallelBuiltins")))))]
    (do
      (assert (= (map (fn [(t (Pair String (List String)))] -> String (pairFirst t)) (ssa/builtinTables)) (map (fn [(t (Pair String (List String)))] -> String (pairFirst t)) want)) "builtinTables lists sys sysNet parallel")
      (assert (> (listLength (pairSecond (optionOr (listHead want) (pair "" (list))))) 20) "sys.c's table parses to its rows")
      (map (fn [(t (Pair String (List String)))] -> Bool
             (let [(ours (optionOr (mapGet (mapFromPairs (ssa/builtinTables)) (pairFirst t)) (list)))]
               (do (assert (= ours (pairSecond t)) (str (pairFirst t) ": ssa.asl lists " (stringJoin ours " ") "; the C table has " (stringJoin (pairSecond t) " ")))
                   (assert (listAll? (fn [(n String)] -> Bool (= (ssa/builtinTableSym n) (some (str "asl_rt_builtin_" (pairFirst t))))) ours) (str (pairFirst t) ": every name routes to asl_rt_builtin_" (pairFirst t)))
                   true)))
           want)
      (assert (= (ssa/builtinTableSym "str") (none)) "a core builtin has no by-name runtime entry: asl_rt_builtin left libaslrt.a")
      true))

fn ! testRuntimeLink work: String -> Bool
  (let [(alloc (nmNames (str work "/alloc")))
        (src (str work "/sysTableMod.asl"))
        (ll (str work "/sysTableMod.ll"))]
    (do
      (assert (listContains? alloc "asl_rt_init") "alloc: nm lists the runtime ABI (asl_rt_init)")
      (assert (listContains? alloc "asl_alloc") "alloc: nm lists the collector (asl_alloc)")
      (refute (listContains? alloc "vmCall") "alloc: no evaluator (vmCall) is linked")
      (refute (listContains? alloc "vmRunProto") "alloc: no evaluator (vmRunProto) is linked")
      (refute (listContains? alloc "compileModule") "alloc: no bytecode compiler (compileModule) is linked")
      (refute (listContains? alloc "cmdHostVerb") "alloc: no host verb (cmdHostVerb) is linked")
      (refute (listContains? alloc "bFdRead") "alloc: no sys.c builtin (bFdRead) is linked")
      (refute (listContains? alloc "asl_rt_builtin_sys") "alloc: the sys table is not linked when unused")
      (assert (ok? (fileWrite src (sysTableSource))) "sysTableMod: source written")
      (expectExit "sysTableMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (refute (stringContains? (fileText ll) "@asl_rt_builtin_sys(") "sysTableMod: fileAppend is routed to its sysRoute wrapper, with no asl_rt_builtin_sys call")
      (link work "sysTableMod" (lib))
      (let [(names (nmNames (str work "/sysTableMod")))
            (native (sh (str "SYS_TABLE_OUT=" work "/native.txt " work "/sysTableMod")))
            (interp (sh (str "SYS_TABLE_OUT=" work "/interp.txt " (host) " run " src)))]
        (do
          (refute (listContains? names "bFileAppend") "sysTableMod: no sys.c builtin (bFileAppend) is linked")
          (refute (listContains? names "asl_rt_builtin_sys") "sysTableMod: the sys table (asl_rt_builtin_sys) is not linked")
          (refute (listContains? names "vmCall") "sysTableMod: still no evaluator (vmCall)")
          (refute (listContains? names "cmdHostVerb") "sysTableMod: still no host verb (cmdHostVerb)")
          (assert (= native.exitCode interp.exitCode) (str "sysTableMod: native exit " native.exitCode " equals host run exit " interp.exitCode "; stderr " native.stderr))
          (assert (= native.exitCode 0) (str "sysTableMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= (fileText (str work "/native.txt")) "sysTable:appended\n") (str "sysTableMod: native appends through fileAppend; got " (fileText (str work "/native.txt"))))
          (assert (= (fileText (str work "/native.txt")) (fileText (str work "/interp.txt"))) "sysTableMod: native file equals host run file")))
      true))

fn ! fileText path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err e) (str "unreadable " path ": " e)))

fn ! testByValueAbi work: String -> Bool
  (let [(ops (fileText (str work "/ops.ll")))
        (all (str ops (fileText (str work "/alloc.ll")) (fileText (str work "/fib.ll"))))
        (abi (fileText "asl/host/src/abi.c"))]
    (do (assert (stringContains? ops "%Val = type { i64, i64 }") "ops: Val is the by-value {i64, i64}")
        (assert (stringContains? ops "define tailcc %Val @demo(%Val %url)") "ops: functions take and return Val by value")
        (assert (stringContains? ops "%five = insertvalue %Val { i64 2, i64 0 }, i64 %rawFive, 1") "ops: an Int boxes inline")
        (assert (not (stringContains? all "@asl_rt_int(")) "ops and alloc: no IR calls asl_rt_int")
        (assert (not (stringContains? all "tailcc ptr")) "ops and alloc: no function takes or returns a Val as a Box pointer")
        (assert (not (stringContains? all "call ptr @asl_rt_")) "ops and alloc: no runtime call returns a Box pointer")
        (assert (not (stringContains? abi "Box")) "abi.c has no Box identifier")
        (refute (stringContains? all "call i64 @asl_rt_unbox_int") "ops, alloc and fib: no IR calls asl_rt_unbox_int (RT-MEMORY M2)")
        (refute (stringContains? all "call double @asl_rt_unbox_float") "ops, alloc and fib: no IR calls asl_rt_unbox_float (RT-MEMORY M2)")
        (refute (stringContains? all "call i1 @asl_rt_unbox_bool") "ops, alloc and fib: no IR calls asl_rt_unbox_bool (RT-MEMORY M2)")
        (refute (stringContains? all "call %Val @asl_rt_construct(") "ops, alloc and fib: no IR calls asl_rt_construct, opConstruct allocates its Ctor directly (RT-MEMORY M5)")
        (refute (stringContains? all "call %Val @asl_rt_record(") "ops, alloc and fib: no IR calls asl_rt_record, opRecord allocates its Rec directly (RT-MEMORY M5)")
        (refute (stringContains? all "call %Val @asl_rt_make_closure(") "ops, alloc and fib: no IR calls asl_rt_make_closure, opMakeClosure allocates its Closure directly (RT-MEMORY M5)")
        true))

fn ! testInlineVariantAndCapture work: String -> Bool
  (let [(ll (fileText (str work "/alloc.ll")))]
    (do (assert (stringContains? ll "x.fast:\n  %x.fp = getelementptr inbounds i8, ptr %x.obj, i64 16\n  %x.fastval = load %Val, ptr %x.fp\n  br label %x.join\n")
                "alloc: a non-fused opVariantField's fast block is just the address, the Val load and the jump to join, no runtime call inside it")
        (assert (stringContains? ll "x.slow:\n  %x.slowval = call %Val @objrt.variantField(%Val %h, i64 0)\n  br label %x.join\n")
                "alloc: its miss falls to rtObject's objrt.variantField, on its own slow block unreachable from the fast path")
        (assert (stringContains? ll "cap0.fast:\n  %cap0.fp = getelementptr inbounds i8, ptr %cap0.obj, i64 24\n  %cap0.fastval = load %Val, ptr %cap0.fp\n  br label %cap0.join\n")
                "alloc: addK's capture 0 reads Closure.up[0] inline on the fast block, no call")
        (assert (stringContains? ll "cap0.slow:\n  %cap0.slowval = call %Val @objrt.capture(%Val %env, i64 0)\n  br label %cap0.join\n")
                "alloc: its miss falls to rtObject's objrt.capture, on its own slow block unreachable from the fast path")
        true))

fn ! expectTrap work: String entry: String message: String -> Bool
  (do (emit work (abiTest) entry entry)
      (link work entry (lib))
      (let [(out (sh (str work "/" entry)))]
        (do (assert (= out.exitCode 1) (str entry ": exit " out.exitCode ", want 1"))
            (assert (= out.stderr (str message "\n")) (str entry ": stderr " out.stderr))
            true)))

fn ! testRuntimeErrors work: String -> Bool
  (do
    (expectTrap work "divZero" "ERR_DIV_ZERO: division by zero")
    (expectTrap work "headNone" "ERR_RANGE: variant none has 0 field(s), no field 0")
    (expectTrap work "arity" "ERR_ARITY: add expects 2 argument(s), got 1")
    (let [(out (sh (str (host) " run " (abiTest) " unknown")))]
      (do (refute (= out.exitCode 0) "unknown: a builtin no native code defines emits no IR")
          (assert (stringContains? out.stderr "ERR_LOWER_UNSUPPORTED unknown: builtin 'no-such-builtin' of 1 operand(s) has no native definition")
                  (str "unknown: emission fails at build time naming no-such-builtin, got " out.stderr))))
    (expectTrap work "notBool" "ERR_TYPE: condition must be Bool, got Int")
    (expectTrap work "noMatch" "ERR_MATCH_NONEXHAUSTIVE: no arm matches (none) in noMatch")
    (expectTrap work "negateMin" "ERR_INT_OVERFLOW: Int - leaves int64")
    (expectTrap work "negateText" "ERR_TYPE: - expects Int or Float, got Unit")
    (expectTrap work "asserts" "ERR_ASSERT: assertion failed: boom")
    (let [(out (sh (str "ASL_ASSERT_REPORT=1 " work "/asserts")))]
      (assert (= out.stderr "ERR_ASSERT: assertion failed: boom\n3 assertion(s) executed, 1 refutation(s) executed\n")
              (str "asserts: counts reported at exit as asl-host test counts them; stderr " out.stderr)))
    true)

fn ! testInlineTag work: String -> Bool
  (do
    (emit work (abiTest) "switchPick" "switchPick")
    (link work "switchPick" (lib))
    (let [(ll (mt (fileReadString (str work "/switchPick.ll")) ((ok t) t) ((err e) e)))]
      (do (assert (stringContains? ll "%bb.entry.ctorp = getelementptr inbounds i8, ptr %bb.entry.obj, i64 8") "switchPick: the constructor id is read inline by getelementptr")
          (assert (stringContains? ll "%bb.entry.tag = select i1 %bb.entry.eq0, i64 0, i64 %bb.entry.sel1") "switchPick: the tag is selected inline against @variantIds.Tri")
          (refute (stringContains? ll "@asl_rt_tag") "switchPick: no emitted program IR declares or calls asl_rt_tag")
          (assert (= (exitOf (str work "/switchPick")) 3) "switchPick: third then second variant dispatch, exit 3")))
    (expectTrap work "switchInt" "ERR_TYPE: match expects a variant, got Int")
    true)

fn ! testFusedFields work: String -> Bool
  (do
    (map (fn [(f String)] -> Bool (do (emit work (abiTest) f f) (link work f (lib)) true))
         (list "fusedVariantInt" "fusedVariantFloat" "fusedVariantBool" "fusedRecordInt"))
    (expectExit "fusedVariantInt: Int field of a variant reads inline, no box; 41 + 1 = 42" (str work "/fusedVariantInt") 0)
    (expectExit "fusedVariantFloat: Float field of a variant reads inline, no box; 41.5 + 0.5 = 42.0" (str work "/fusedVariantFloat") 0)
    (expectExit "fusedVariantBool: Bool field of a variant reads inline, no box" (str work "/fusedVariantBool") 0)
    (expectExit "fusedRecordInt: two Int fields of a record each read inline, sum matches the closed form" (str work "/fusedRecordInt") 0)
    (let [(ll (mt (fileReadString (str work "/fusedVariantInt.ll")) ((ok t) t) ((err e) e)))]
      (do (assert (stringContains? ll "%xi.rightTag = icmp eq i32 %xi.ftag, 2") "fusedVariantInt: the field's own Val tag is checked inline against T_INT")
          (assert (stringContains? ll "%xi.fastval = load i64, ptr %xi.valp") "fusedVariantInt: the raw i64 is loaded inline on the fast path")
          (assert (stringContains? ll "xi.fast:\n  %xi.valp = getelementptr inbounds i8, ptr %xi.obj, i64 24\n  %xi.fastval = load i64, ptr %xi.valp\n  br label %xi.join\n")
                  "fusedVariantInt: the fast block's whole body is the address, the load and the jump to join, no runtime call inside it")))
    (let [(ll (mt (fileReadString (str work "/fusedRecordInt.ll")) ((ok t) t) ((err e) e)))]
      (do (assert (stringContains? ll "%xi.keysp = getelementptr inbounds i8, ptr %xi.obj, i64 16") "fusedRecordInt: Rec.keys is read inline at offset 16")
          (assert (stringContains? ll "%xi.valoff = add i64 32, %xi.off") "fusedRecordInt: a record field's Val is addressed inline at v[idx], offset 24 + idx*16 + 8")))
    (expectTrap work "fusedVariantRange" "ERR_RANGE: variant some has 1 field(s), no field 1")
    (expectTrap work "fusedVariantWrongTag" "ERR_TYPE: compiled code expects Int, got String")
    (expectTrap work "fusedRecordMissingKey" "ERR_FIELD: record has no field missing")
    true)

fn functionIr ll: String name: String -> String
  (let [(at (optionOr (stringIndexOf ll (str "@" name "(")) (stringLength ll)))
        (tail (optionOr (stringSlice ll at (stringLength ll)) ""))
        (endIdx (optionOr (stringIndexOf tail "\ndefine") (stringLength tail)))]
    (optionOr (stringSlice tail 0 endIdx) tail))

fn ! testStaticFields work: String -> Bool
  (do
    (emit work (abiTest) "staticFieldRecord" "staticFieldRecord")
    (link work "staticFieldRecord" (lib))
    (expectExit "staticFieldRecord: two record fields read straight as Val equal what was stored" (str work "/staticFieldRecord") 0)
    (let [(ll (mt (fileReadString (str work "/staticFieldRecord.ll")) ((ok t) t) ((err e) e)))
          (frag (functionIr ll "staticFieldRecord"))]
      (do (assert (stringContains? frag "%xv.isRec = icmp eq i32 %xv.vtag, 7") "staticFieldRecord: the base's Val tag is checked inline against T_REC")
          (assert (stringContains? frag "%xv.slotp = getelementptr inbounds i8, ptr %xv.obj, i64 24") "staticFieldRecord: field a's static slot is addressed at offset 24 (index 0)")
          (assert (stringContains? frag "%yv.slotp = getelementptr inbounds i8, ptr %yv.obj, i64 40") "staticFieldRecord: field b's static slot is addressed at offset 40 (index 1)")
          (assert (stringContains? frag "%xv = load %Val, ptr %xv.slotp") "staticFieldRecord: field a's %Val is loaded straight from its static slot, defined at the load, no phi")
          (assert (stringContains? frag "xv.bad:\n  call void @rterr.match(ptr @name.staticFieldRecord)\n  unreachable\n") "staticFieldRecord: a tag or bound mismatch traps by function name instead of calling objrt.field, defence in depth never reached here")
          (assert (stringContains? ll "@name.staticFieldRecord = private unnamed_addr constant") "staticFieldRecord: the function's own name constant is emitted for the trap even though it has no match statement")
          (refute (stringContains? frag "call %Val @objrt.field(") "staticFieldRecord: no call to objrt.field anywhere in this function's IR")))
    (expectTrap work "staticFieldMissing" "ERR_FIELD: record has no field missing")
    true)

fn typedFieldSource -> String
  (stringJoin (list
    "(module typedFieldMod"
    "  :x [main getY nameOf]"
    "  :i [])"
    ""
    "(schema Point"
    "  (:f x Int64)"
    "  (:f y Int64))"
    ""
    "(schema Person"
    "  (:f age Int64)"
    "  (:f name String))"
    ""
    "(schema Other"
    "  (:f z Int64))"
    ""
    "fn getY p: Point -> Int64"
    "  p.y"
    ""
    "fn nameOf p: Person -> String"
    "  p.name"
    ""
    "fn asAny v: Any -> Any"
    "  v"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(mode (mt (listHead args) ((some a) a) ((none) \"read\")))]"
    "    (cond"
    "      ((= mode \"nonRecordY\") (do (println (str (getY (asAny 7)))) (ok 0)))"
    "      ((= mode \"nonRecordName\") (do (println (nameOf (asAny 7))) (ok 0)))"
    "      ((= mode \"missingY\") (do (println (str (getY (asAny (Other :z 3))))) (ok 0)))"
    "      (else (do (println (str (getY (Point :x 1 :y 2)) \"|\" (nameOf (Person :age 36 :name \"Ada\")))) (ok 0)))))")
    "\n")

fn variantBoundarySource -> String
  (stringJoin (list
    "(module variantBoundaryMod"
    "  :x [main switchForeign asAny]"
    "  :i [])"
    ""
    "(enum Expected (:c expected [] \"Expected value\"))"
    "(enum Foreign (:c first [] \"Foreign value\"))"
    ""
    "fn switchForeign x: Expected -> Int64"
    "  (mt x ((expected) 1))"
    ""
    "fn asAny x: Any -> Any"
    "  x"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (ok (switchForeign (asAny (first))))"
    "") "\n")

fn ! testVariantBoundary work: String -> Bool
  (let [(src (str work "/variantBoundary.asl"))]
    (do
      (assert (ok? (fileWrite src (variantBoundarySource))) "variant boundary: source written")
      (let [(hosted (sh (str (host) " run " src " 2>&1")))
            (want (hostErrorLine hosted))]
        (do
          (assert (= hosted.exitCode 1) (str "variant boundary: asl-host exit " hosted.exitCode ", want 1; output " hosted.stdout hosted.stderr))
          (assert (stringStartsWith? want "ERR_MATCH_NONEXHAUSTIVE:") (str "variant boundary: asl-host reports unmatched foreign variant; got " hosted.stdout hosted.stderr))
          (mt (low/lowerSource (variantBoundarySource))
            ((err ds) (assert false (str "variant boundary: the source lowers: " (diagText ds))))
            ((ok m) (mt (llvm/emitLlvmProgram m "main")
                      ((err ds) (assert false (str "variant boundary: emitLlvmProgram emits the program: " (diagText ds))))
                      ((ok ll) (do (assert (ok? (fileWrite (str work "/variantBoundary.ll") ll)) "variant boundary: .ll written")
                                   (refute (stringContains? ll "@asl_rt_tag") "variant boundary: the source program's IR neither declares nor calls asl_rt_tag")
                                   (link work "variantBoundary" (lib))
                                   (let [(native (sh (str work "/variantBoundary")))]
                                     (do (assert (= native.exitCode 1) (str "variant boundary: native exit " native.exitCode ", want 1; stderr " native.stderr))
                                         (assert (= native.stderr (str want "\n")) (str "variant boundary: native stderr is asl-host's own error line " want "; got " native.stderr))
                                         true)))))))
          (expectTrap work "switchForeign" want)
          true))))

fn typedFieldFixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/typedFieldRec.c"

fn hostErrorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn defineIr ll: String header: String -> String
  (mt (stringIndexOf ll header)
    ((none) "")
    ((some at) (let [(tail (optionOr (stringSlice ll at (stringLength ll)) ""))]
                 (optionOr (stringSlice tail 0 (optionOr (stringIndexOf tail "\n}\n") (stringLength tail))) tail))))

fn beforeSlow frag: String -> String
  (optionOr (stringSlice frag 0 (optionOr (stringIndexOf frag ".slow:\n") (stringLength frag))) frag)

fn probeBranch frag: String miss: String -> String
  (let [(mark ".sIn = icmp slt i32 1, %")]
    (mt (stringIndexOf frag mark)
      ((none) "<no .sIn bound compare>")
      ((some at) (let [(tail (optionOr (stringSlice frag (+ at (stringLength mark)) (stringLength frag)) ""))
                       (r (optionOr (stringSlice tail 0 (optionOr (stringIndexOf tail ".n\n") 0)) ""))]
                   (str "  br i1 %" r ".sIn, label %" r ".sprobe, label %" r "." miss "\n")))))

fn ! expectSameError work: String bin: String src: String mode: String want: String -> Bool
  (let [(native (sh (str work "/" bin " " mode)))
        (hosted (sh (str (host) " run " src " " mode)))]
    (do (assert (= (hostErrorLine hosted) want) (str "typedField " mode ": asl-host run fails with " want "; got " hosted.stdout hosted.stderr))
        (assert (= native.exitCode 1) (str "typedField " mode ": native exit " native.exitCode ", want 1; stderr " native.stderr))
        (assert (= native.stderr (str (hostErrorLine hosted) "\n")) (str "typedField " mode ": native stderr is asl-host's own error line; got " native.stderr))
        true))

fn ! testTypedFields work: String -> Bool
  (let [(src (str work "/typedFieldMod.asl"))]
    (do
      (assert (ok? (fileWrite src (typedFieldSource))) "typedField: source written")
      (mt (low/lowerSource (typedFieldSource))
        ((err ds) (assert false (str "typedField: the source lowers: " (diagText ds))))
        ((ok m)
          (do
            (mt (llvm/emitLlvmProgram m "main")
              ((err ds) (assert false (str "typedField: emitLlvmProgram emits the program: " (diagText ds))))
              ((ok ll) (let [(getY (defineIr ll "define tailcc i64 @getY("))
                             (nameOf (defineIr ll "define tailcc %Val @nameOf("))]
                         (do (assert (ok? (fileWrite (str work "/typedFieldMod.ll") ll)) "typedField: .ll written")
                             (assert (stringContains? getY ".skeyp = getelementptr inbounds i32, ptr ") (str "typedField getY: keys[1] is addressed at y's static index:\n" getY))
                             (assert (stringContains? getY ".keys, i64 1\n") (str "typedField getY: the probed key is keys[1], y's declared index in Point:\n" getY))
                             (assert (stringContains? getY ".sIn = icmp slt i32 1, %") (str "typedField getY: y's index 1 is bound-checked against Rec.n before keys[1] is read:\n" getY))
                             (assert (and (stringContains? getY ".n\n  br i1 %") (stringContains? getY ".sIn, label %")) (str "typedField getY: the bound check's result guards the branch to the probe:\n" getY))
                             (assert (stringContains? getY (probeBranch getY "loop")) (str "typedField getY: an index past Rec.n skips the probe for the key scan (.loop), never reading keys[1]:\n" getY))
                             (assert (stringContains? getY ".skeyOk = icmp eq i32 ") (str "typedField getY: keys[i] is compared with @fieldId.y:\n" getY))
                             (assert (stringContains? getY "@fieldId.y") (str "typedField getY: the compare reads the cached interned id of y:\n" getY))
                             (refute (stringContains? (beforeSlow getY) "@objrt.field(") (str "typedField getY: no call to objrt.field before the cold .slow block:\n" getY))
                             (assert (stringContains? nameOf ".keys, i64 1\n") (str "typedField nameOf: the probed key is keys[1], name's declared index in Person:\n" nameOf))
                             (assert (stringContains? nameOf ".sIn = icmp slt i32 1, %") (str "typedField nameOf: name's index 1 is bound-checked against Rec.n before keys[1] is read:\n" nameOf))
                             (assert (and (stringContains? nameOf ".n\n  br i1 %") (stringContains? nameOf ".sIn, label %")) (str "typedField nameOf: the bound check's result guards the branch to the probe:\n" nameOf))
                             (assert (stringContains? nameOf (probeBranch nameOf "slow")) (str "typedField nameOf: an index past Rec.n goes to the cold .slow block, never reading keys[1]:\n" nameOf))
                             (assert (stringContains? nameOf ".skeyOk = icmp eq i32 ") (str "typedField nameOf: keys[i] is compared with @fieldId.name:\n" nameOf))
                             (assert (stringContains? nameOf ".slotp = getelementptr inbounds i8, ptr ") (str "typedField nameOf: the static slot is addressed:\n" nameOf))
                             (assert (stringContains? nameOf ", i64 40\n") (str "typedField nameOf: name's static slot is at offset 40 (index 1):\n" nameOf))
                             (refute (stringContains? (beforeSlow nameOf) "@objrt.field(") (str "typedField nameOf: no call to objrt.field before the cold .slow block:\n" nameOf))
                             (link work "typedFieldMod" (lib))
                             (let [(native (sh (str work "/typedFieldMod")))
                                   (hosted (sh (str (host) " run " src)))]
                               (do (assert (and (= native.exitCode 0) (= native.stdout "2|Ada\n")) (str "typedField: native prints 2|Ada, got " native.stdout " exit " native.exitCode "; stderr " native.stderr))
                                   (assert (= native.stdout hosted.stdout) (str "typedField: native stdout equals asl-host run's, got " hosted.stdout hosted.stderr))))
                             (expectSameError work "typedFieldMod" src "nonRecordY" "ERR_TYPE: .-y expects a record, got Int")
                             (expectSameError work "typedFieldMod" src "nonRecordName" "ERR_TYPE: .-name expects a record, got Int")
                             (expectSameError work "typedFieldMod" src "missingY" "ERR_FIELD: record has no field y")
                             true))))
            (mt (ssa/emitLlvmModule m)
              ((err ds) (assert false (str "typedField: emitLlvmModule emits the functions: " (diagText ds))))
              ((ok ll) (do (assert (ok? (fileWrite (str work "/typedFieldLib.ll") ll)) "typedField: library .ll written")
                           (assert (ok? (fileWrite (str work "/valrtC.ll") (ssa/cRuntimeModule))) "typedField: the C main's intern and C floor definitions written")
                           (expectExit "typedField: clang links the C fixture with the typed functions" (str (clang) " -x ir " work "/typedFieldLib.ll " work "/valrtC.ll -x c " (typedFieldFixture) " -x none " (lib) " -lm -o " work "/typedFieldRec") 0)
                           (let [(out (sh (str work "/typedFieldRec")))]
                             (assert (and (= out.exitCode 0) (= out.stdout "orderedY=2 swappedY=20 orderedName=same swappedName=same\n"))
                                     (str "typedField: host-built records in declared and swapped key order read the right field; got " out.stdout " exit " out.exitCode "; stderr " out.stderr)))
                           true)))
            true)))
      true))

fn ! testUnaryMinus work: String -> Bool
  (do
    (emit work (abiTest) "negate" "negate")
    (link work "negate" (lib))
    (expectExit "negate: (+ (- 7) 49) with a one-operand - builtin" (str work "/negate") 42)
    (emit work (abiTest) "negateFloat" "negateFloat")
    (link work "negateFloat" (lib))
    (expectExit "negateFloat: (- 2.5) equals -2.5" (str work "/negateFloat") 0)
    true)

fn ! testMainArgs work: String -> Bool
  (do
    (emit work (abiTest) "joined" "joined")
    (link work "joined" (lib))
    (expectExit "joined: main receives the arguments after the program name and exits with (ok 42)" (str work "/joined ab cde") 42)
    (expectExit "joined: other arguments join differently, (ok 3)" (str work "/joined ab") 3)
    (expectTrap work "failed" "ERR_MAIN_FAILED: main returned (err \"boom\"), not (ok ...)")
    (expectTrap work "tooBig" "ERR_RANGE: main returned (ok 256), exit codes are 0..255")
    true)

fn ! testTailCalls work: String -> Bool
  (do
    (emit work (abiTest) "deepTail" "deepTail")
    (link work "deepTail" (lib))
    (expectExit "deepTail: a million self tail calls run in constant stack" (str work "/deepTail") 42)
    (emit work (abiTest) "nestedTail" "nestedTail")
    (link work "nestedTail" (lib))
    (expectExit "nestedTail: self tail calls in arms three deep run a million deep" (str work "/nestedTail") 42)
    true)

fn hostArithmeticSource -> String
  (stringJoin (list
    "(module hostTraps"
    "  :x [main]"
    "  :i [])"
    ""
    "fn compute op: String n: Int64 -> Int64"
    "  (cond"
    "    ((= op \"addOver\") (+ 9223372036854775807 n))"
    "    ((= op \"subOver\") (- (- 0 9223372036854775807) (+ n 1)))"
    "    ((= op \"mulOver\") (* 4611686018427387904 (+ n 1)))"
    "    ((= op \"divZero\") (/ 7 (- n 1)))"
    "    ((= op \"modZero\") (mod 7 (- n 1)))"
    "    ((= op \"divMin\") (/ (- (- 0 9223372036854775807) n) (- 0 n)))"
    "    ((= op \"floor\") (let [(d (+ n 2))] (+ (* 10 (/ -7 d)) (+ (mod -7 d) (+ (* 3 (/ 7 (- 0 d))) (mod 7 (- 0 d)))))))"
    "    ((= op \"minusOne\") (+ (mod -9223372036854775807 (- 0 n)) (/ -5 (- 0 n))))"
    "    ((= op \"float\") (let [(z (int64ToFloat64 (- n 1)))] (if (and (> (/ 1.0 z) 1000.0) (not (= (/ z z) (/ z z)))) 7 9)))"
    "    (else 3))"
    ""
    "fn fused n: Int64 -> String"
    "  (let [(xs (list 10 20 30))"
    "        (s \"hello\")"
    "        (ints (list (optionOr (listHead xs) -1) (optionOr (listHead (list)) -1)"
    "                    (listLength (optionOr (listTail xs) (list))) (listLength (optionOr (listTail (list)) (list 7 7)))"
    "                    (optionOr (listGet xs (+ n 1)) -1) (optionOr (listGet xs (- 0 n)) -1) (optionOr (listGet xs 5) -1)"
    "                    (mt (listHead xs) ((some x) x) ((none) 0)) (mt (listTail (list)) ((some t) (listLength t)) (_ 99))))]"
    "    (str (stringJoin (map (fn [(i Int64)] -> String (stringFromInt64 i)) ints) \" \") \"|\""
    "         (optionOr (stringSlice s n (+ n 1)) \"?\") (optionOr (stringSlice s 1 4) \"?\") (optionOr (stringSlice s 3 9) \"?\") (optionOr (stringSlice s 2 2) \"?\")))"
    ""
    "fn evenF n: Int64 acc: Float64 -> Bool"
    "  (if (= n 0) true (oddS (- n 1) \"x\"))"
    ""
    "fn oddS n: Int64 s: String -> Bool"
    "  (if (= n 0) false (evenF (- n 1) 1.5))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(op (optionOr (listHead args) \"\"))"
    "        (n (listLength args))]"
    "    (do (println (cond ((= op \"fused\") (fused n)) ((= op \"mutual\") (if (evenF 1000000 0.0) \"true\" \"false\")) (else (stringFromInt64 (compute op n)))))"
    "        (ok 0)))")
    "\n")

fn hostTrapCases -> (List (Pair String String))
  (list (pair "addOver" "ERR_INT_OVERFLOW: Int + leaves int64") (pair "subOver" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "mulOver" "ERR_INT_OVERFLOW: Int * leaves int64") (pair "divMin" "ERR_INT_OVERFLOW: Int / leaves int64")
        (pair "divZero" "ERR_DIV_ZERO: division by zero") (pair "modZero" "ERR_DIV_ZERO: mod by zero"))

fn hostValueCases -> (List (Pair String String))
  (list (pair "floor" "-39\n") (pair "minusOne" "5\n") (pair "float" "7\n") (pair "fused" "10 -1 2 2 30 -1 -1 10 99|eell?\n") (pair "mutual" "true\n"))

fn ! runOp work: String op: String -> ProcessOutput
  (sh (str work "/hostArithmetic " op))

fn ! hostOp src: String op: String -> ProcessOutput
  (sh (str (host) " run " src " " op " 2>&1"))

fn ! testHostArithmetic work: String -> Bool
  (let [(src (str work "/hostArithmetic.asl"))
        (ll (str work "/hostArithmetic.ll"))]
    (do
      (assert (ok? (fileWrite src (hostArithmeticSource))) "hostArithmetic: source written")
      (expectExit "hostArithmetic: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "hostArithmetic" (lib))
      (let [(text (resultOr (fileRead ll) ""))]
        (do (assert (stringContains? text "@llvm.sadd.with.overflow.i64") "hostArithmetic: + over Int64 is a raw overflow-checked add")
            (assert (stringContains? text "call void @rterr.int(i32 6)") "hostArithmetic: mod fails through the native rterr.int on a zero divisor")
            (refute (stringContains? text "@asl_rt_builtin(ptr @name.$2B") "hostArithmetic: no + goes through the builtin by name")))
      (map (fn [(c (Pair String String))] -> Bool
             (let [(out (runOp work (pairFirst c)))
                   (want (pairSecond c))]
               (do (assert (= out.exitCode 1) (str (pairFirst c) ": native exit " out.exitCode ", want 1; stdout " out.stdout))
                   (assert (= out.stderr (str want "\n")) (str (pairFirst c) ": native stderr " out.stderr ", want " want))
                   (assert (stringContains? (hostOp src (pairFirst c)).stdout want) (str (pairFirst c) ": asl-host reports " want " too"))
                   true)))
           (hostTrapCases))
      (map (fn [(c (Pair String String))] -> Bool
             (let [(out (runOp work (pairFirst c)))]
               (do (assert (and (= out.exitCode 0) (= out.stdout (pairSecond c))) (str (pairFirst c) ": native prints " out.stdout " exit " out.exitCode ", want " (pairSecond c) "; stderr " out.stderr))
                   (assert (= (hostOp src (pairFirst c)).stdout (pairSecond c)) (str (pairFirst c) ": asl-host prints the same"))
                   true)))
           (hostValueCases))
      true))

fn readlinkFixtureSource -> String
  (stringJoin (list
    "(module readlinkFixture"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(path (optionOr (listHead args) \"\"))]"
    "    (do (println (mt (fileReadlink path) ((ok t) (str \"ok:\" t)) ((err e) (str \"err:\" e))))"
    "        (ok 0)))")
    "\n")

fn ! testFileReadlink work: String -> Bool
  (let [(src (str work "/readlinkFixture.asl"))
        (ll (str work "/readlinkFixture.ll"))
        (scratch (str work "/readlinkScratch"))
        (file (str scratch "/target.txt"))
        (symlinkPath (str scratch "/link"))
        (missing (str scratch "/missing"))]
    (do
      (assert (= (exitOf (str "mkdir -p " scratch)) 0) "readlinkFixture: scratch dir made")
      (assert (ok? (fileWrite file "payload")) "readlinkFixture: target file written")
      (assert (ok? (pathSymlink "target.txt" symlinkPath)) "readlinkFixture: symlink made")
      (assert (ok? (fileWrite src (readlinkFixtureSource))) "readlinkFixture: source written")
      (expectExit "readlinkFixture: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "readlinkFixture" (lib))
      (map (fn [(p String)] -> Bool
             (let [(out (sh (str work "/readlinkFixture '" p "'")))
                   (vmOut (sh (str (host) " run " src " '" p "'")))]
               (do (assert (= out.exitCode 0) (str p ": native exit " out.exitCode "; stderr " out.stderr))
                   (assert (= out.stdout vmOut.stdout) (str p ": native stdout " out.stdout ", vm stdout " vmOut.stdout))
                   true)))
           (list symlinkPath file missing))
      (assert (stringContains? (sh (str work "/readlinkFixture '" symlinkPath "'")).stdout "ok:target.txt") "readlinkFixture: symlink resolves to its relative target")
      (assert (stringContains? (sh (str work "/readlinkFixture '" file "'")).stdout "err:invalidPath") "readlinkFixture: a non-link path is err invalidPath")
      (assert (stringContains? (sh (str work "/readlinkFixture '" missing "'")).stdout "err:notFound") "readlinkFixture: a missing path is err notFound")
      true))

fn frontEndSource -> String
  (stringJoin (list
    "(module frontEnd"
    "  :x [main]"
    "  :i [])"
    ""
    "schema Table { id: String \"anchor\" cols: (List String) \"names\" rows: (List (List String)) \"cells\" }"
    ""
    "fn sq x: Int64 -> Int64"
    "  (* x x)"
    ""
    "fn exprHead n: Int64 -> Int64"
    "  (let [(fs (list sq))]"
    "    ((optionOr (listGet fs 1) sq) n))"
    ""
    "fn twice f: (fn [Int64] -> Int64) x: Int64 -> Int64"
    "  (f (f x))"
    ""
    "fn adder k: Int64 -> (fn [Int64] -> Int64)"
    "  (fn [(y Int64)] -> Int64 (+ y k))"
    ""
    "fn neg z: Float64 -> Float64"
    "  (- z)"
    ""
    "fn sumBy pipeline: (fn [Int64] -> Int64)"
    "          xs: (List Int64)"
    "          acc: Int64 -> Int64"
    "  (mt (listHead xs)"
    "    ((none) acc)"
    "    ((some x) (sumBy pipeline (optionOr (listTail xs) (list)) (+ acc (pipeline x)))))"
    ""
    "fn table -> String"
    "  (let [(t (Table :id \"t\" :cols (list \"a\" \"b\") :rows (list (list \"1\" \"2\") (list \"3\"))))]"
    "    (str t.id (stringFromInt64 (+ (* 10 (listLength t.cols)) (listLength t.rows)))))"
    ""
    "fn ! files dir: String -> String"
    "  (let [(t0 (monotonicNs))"
    "        (made (mt (dirCreate dir) ((ok _) \"made\") ((err _) \"notMade\")))"
    "        (again (mt (dirCreate dir) ((ok _) \"again\") ((err _) \"exists\")))"
    "        (moved (mt (pathRename dir (str dir \"2\")) ((ok _) \"moved\") ((err _) \"stuck\")))"
    "        (gone (mt (pathRemove (str dir \"2\")) ((ok _) \"removed\") ((err _) \"kept\")))"
    "        (t1 (monotonicNs))]"
    "    (do (when (>= t1 t0) (print \"monotonic \"))"
    "        (stringJoin (list made again moved gone) \" \")))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (stringFromInt64 (exprHead 3)))"
    "      (println (stringFromInt64 (twice (adder 5) 1)))"
    "      (println (stringFromFloat64 (neg 2.5)))"
    "      (println (stringFromInt64 (sumBy (fn [(x Int64)] -> Int64 (* x 2)) (list 1 2 3) 0)))"
    "      (println (table))"
    "      (println (files (optionOr (listHead args) \"\")))"
    "      (ok 0))")
    "\n")

fn frontEndLines -> String
  "9\n11\n-2.5\n12\nt22\nmonotonic made again moved removed\n"

fn ! testFrontEnd work: String -> Bool
  (let [(src (str work "/frontEnd.asl"))
        (ll (str work "/frontEnd.ll"))
        (dir (str work "/frontEndDir"))]
    (do
      (assert (ok? (fileWrite src (frontEndSource))) "frontEnd: source written")
      (let [(hosted (sh (str (host) " run " src " " dir " 2>&1")))]
        (assert (= hosted.stdout (frontEndLines)) (str "frontEnd: asl-host prints the expected lines, got " hosted.stdout)))
      (expectExit "frontEnd: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "frontEnd" (lib))
      (let [(out (sh (str work "/frontEnd " dir)))]
        (assert (and (= out.exitCode 0) (= out.stdout (frontEndLines))) (str "frontEnd: native prints " out.stdout " exit " out.exitCode ", as asl-host does; stderr " out.stderr)))
      true))

fn hostFloatSource -> String
  (stringJoin (list
    "(module hostFloat"
    "  :x [main]"
    "  :i [])"
    ""
    "fn optF o: (Option Float64) -> String"
    "  (mt o ((some x) (str \"some \" (stringFromFloat64 x))) ((none) \"none\"))"
    ""
    "fn optI o: (Option Int64) -> String"
    "  (mt o ((some n) (str \"some \" (stringFromInt64 n))) ((none) \"none\"))"
    ""
    "fn parsed s: String -> Float64"
    "  (optionOr (stringToFloat64 s) 0.0)"
    ""
    "fn modPairs xs: (List String) -> (List String)"
    "  (mt (listHead xs)"
    "    ((none) (list))"
    "    ((some a) (mt (listGet xs 1)"
    "                ((none) (list))"
    "                ((some b) (cons (stringFromFloat64 (mod (parsed a) (parsed b))) (modPairs (optionOr (listTail (optionOr (listTail xs) (list))) (list))))))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(op (optionOr (listHead args) \"\"))"
    "        (rest (optionOr (listTail args) (list)))]"
    "    (do (println (stringJoin (cond ((= op \"parse\") (map (fn [(s String)] -> String (optF (stringToFloat64 s))) rest))"
    "                                   ((= op \"trunc\") (map (fn [(s String)] -> String (optI (float64ToInt64 (parsed s)))) rest))"
    "                                   (else (modPairs rest)))"
    "                             \" \"))"
    "        (ok 0)))")
    "\n")

fn hostFloatCases -> (List (Pair String String))
  (list (pair "parse abc '' 2.5 nan -inf 1e400 1.5x" "none none some 2.5 some nan some -inf some inf none\n")
        (pair "trunc nan inf -inf 1e19 -9223372036854775808.0 9223372036854775807.0 -3.9 3.9 1e18" "none none none none some -9223372036854775808 none some -3 some 3 some 1000000000000000000\n")
        (pair "mod -7.0 3.0 7.0 -3.0 -7.0 -3.0 -6.0 3.0 6.0 -3.0 5.5 2.0 1.0 0.0 -1.0 inf 1.0 -inf inf 2.0 nan 2.0" "2.0 -2.0 -1.0 0.0 -0.0 1.5 nan inf -inf nan nan\n"))

fn ! testHostFloat work: String -> Bool
  (let [(src (str work "/hostFloat.asl"))
        (ll (str work "/hostFloat.ll"))]
    (do
      (assert (ok? (fileWrite src (hostFloatSource))) "hostFloat: source written")
      (expectExit "hostFloat: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "hostFloat" (lib))
      (let [(text (resultOr (fileRead ll) ""))]
        (do (assert (stringContains? text "@asl_rt_format_parse_value(") "hostFloat: stringToFloat64 calls the native parser")
            (refute (stringContains? text "@asl_rt_b_stringToFloat64(") "hostFloat: stringToFloat64 avoids its C wrapper")
            (assert (stringContains? text "call %Val @mathrt.float64ToInt64(") "hostFloat: float64ToInt64 calls its native @mathrt helper")
            (refute (stringContains? text "@asl_rt_b_float64ToInt64(") "hostFloat: float64ToInt64 avoids its C wrapper")
            (assert (stringContains? text "call %Val @opsrt.mod(") "hostFloat: Float mod calls the native @opsrt.mod helper")))
      (map (fn [(c (Pair String String))] -> Bool
             (let [(out (sh (str work "/hostFloat " (pairFirst c))))
                   (hosted (sh (str (host) " run " src " " (pairFirst c) " 2>&1")))]
               (do (assert (and (= out.exitCode 0) (= out.stdout (pairSecond c))) (str "hostFloat " (pairFirst c) ": native prints " out.stdout " exit " out.exitCode ", want " (pairSecond c) "; stderr " out.stderr))
                   (assert (= hosted.stdout (pairSecond c)) (str "hostFloat " (pairFirst c) ": asl-host prints " hosted.stdout))
                   true)))
           (hostFloatCases))
      true))

fn floatExponentLiteralSource -> String
  (stringJoin
    (list "(module floatExponentLiteral :x [main] :i [])"
          ""
          "fn ! main -> (Result Int64 String)"
          "  (do (println (stringFromFloat64 1e22))"
          "      (println (stringFromFloat64 1.5e-3))"
          "      (println (stringFromFloat64 -2E+5))"
          "      (ok 0))")
    "\n")

fn ! testFloatExponentLiteral work: String -> Bool
  (let [(src (str work "/floatExponentLiteral.asl"))
        (ll (str work "/floatExponentLiteral.ll"))]
    (do
      (assert (ok? (fileWrite src (floatExponentLiteralSource))) "floatExponentLiteral: source written")
      (expectExit "floatExponentLiteral: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "floatExponentLiteral" (lib))
      (let [(out (sh (str work "/floatExponentLiteral")))
            (hosted (sh (str (host) " run " src)))]
        (do (assert (= out.exitCode 0) (str "floatExponentLiteral: native exit " out.exitCode "; stderr " out.stderr))
            (assert (= out.stdout "1e+22\n0.0015\n-200000.0\n") (str "floatExponentLiteral: native prints " out.stdout))
            (assert (= hosted.stdout out.stdout) (str "floatExponentLiteral: asl-host run prints " hosted.stdout ", native prints " out.stdout))
            true))))

fn escapeBodies -> (List String)
  (list "plain" "\\n\\t\\r" "\\\\" "\\\"" "\\x41" "\\xff" "\\x01" "\\u0041" "\\u00e9" "\\uD7FF" "\\uE000" "\\uFFFF"
        "\\u{62}" "\\u{1}" "\\u{00e9}" "\\u{000041}" "\\u{7FF}" "\\u{800}" "\\u{10000}" "\\u{1F600}" "\\u{10FFFF}" "a\\u{62}b\\x41\\n")

fn badEscapeBodies -> (List String)
  (list "\\u{1g}" "\\u{110000}" "\\u{}" "\\u{D800}" "\\u{1234567}" "\\xZZ" "\\x-1" "\\a" "\\q" "\\0" "\\e" "\\{" "\\u +1a" "\\uD800")

fn escapeSource -> String
  (stringJoin (listAppend (list
    "(module escapeBytes"
    "  :x [main]"
    "  :i [])"
    ""
    "fn codes s: String -> String"
    "  (str (stringFromInt64 (stringLength s)) \":[\" s \"]\")"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do")
    (listAppend (map (fn [(b String)] -> String (str "    (println (codes \"" b "\"))")) (escapeBodies)) (list "    (ok 0))")))
    "\n")

fn badEscapeSource body: String -> String
  (stringJoin (list "(module badEscape" "  :x []" "  :i [])" "" "fn bad -> String" (str "  \"" body "\"") "") "\n")

fn ! badEscapeRejected work: String index: Int64 body: String -> Bool
  (let [(src (str work "/badEscape" (stringFromInt64 index) ".asl"))
        (written (fileWrite src (badEscapeSource body)))
        (built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " work "/badEscape.ll 2>&1")))]
    (do (assert (ok? written) (str body ": source written"))
        (assert (!= built.exitCode 0) (str body ": asl1 refuses to build it"))
        (assert (stringContains? built.stdout "ERR_BAD_ESCAPE") (str body ": asl1 names ERR_BAD_ESCAPE, got " built.stdout))
        (assert (!= (exitOf (str (host) " check " src)) 0) (str body ": asl-host check rejects it too"))
        true))

fn ! testEscapeBytes work: String -> Bool
  (let [(src (str work "/escapeBytes.asl"))]
    (do
      (assert (ok? (fileWrite src (escapeSource))) "escapeBytes: source written")
      (expectExit "escapeBytes: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " work "/escapeBytes.ll") 0)
      (link work "escapeBytes" (lib))
      (let [(native (sh (str work "/escapeBytes")))
            (interp (sh (str (host) " run " src)))
            (lines (listDrop (stringSplit native.stdout ":[") 1))]
        (do (assert (= native.exitCode 0) (str "escapeBytes: native exit " native.exitCode "; stderr " native.stderr))
            (assert (= interp.exitCode 0) (str "escapeBytes: asl-host run exit " interp.exitCode "; stderr " interp.stderr))
            (assert (= (listLength lines) (listLength (escapeBodies))) (str "escapeBytes: one line per literal, got " native.stdout))
            (assert (= native.stdout interp.stdout) (str "escapeBytes: native bytes equal asl-host run bytes; native " native.stdout " host " interp.stdout))))
      (map (fn [(i Int64)] -> Bool (badEscapeRejected work i (optionOr (listGet (badEscapeBodies) i) ""))) (range 0 (listLength (badEscapeBodies))))
      true))

fn ! testNegation work: String -> Bool
  (do
    (emit work (sourceTest) "negMain" "negMain")
    (link work "negMain" (lib))
    (expectExit "negMain: (- a) of an Int64 negates raw" (str work "/negMain") 47)
    (emit work (sourceTest) "negMin" "negMin")
    (link work "negMin" (lib))
    (let [(out (sh (str work "/negMin")))]
      (do (assert (= out.exitCode 1) (str "negMin: exit " out.exitCode ", want 1"))
          (assert (= out.stderr "ERR_INT_OVERFLOW: Int - leaves int64\n") (str "negMin: negating INT64_MIN fails as asl-host does; stderr " out.stderr))
          true)))

fn ! testSharedArithmeticSuite work: String -> Bool
  (let [(src "tests/conformance/host/arithmeticTest.asl")
        (ll (str work "/arithmeticTest.ll"))
        (bin (str work "/arithmeticTest"))]
    (do
      (expectExit "arithmeticTest: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "arithmeticTest" (lib))
      (let [(out (sh (str "ASL_TEST_BINARY=" bin " ASL_ASSERT_REPORT=1 " bin)))]
        (do (assert (= out.exitCode 0) (str "arithmeticTest native exit " (stringFromInt64 out.exitCode) "; stderr " out.stderr))
            (assert (stringContains? out.stderr "104 assertion(s) executed") (str "arithmeticTest reports 104 asserts; got " out.stderr))
            true))))

fn topLevelInitSource -> String
  (stringJoin (list
    "(module topInitMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(println \"init:first\")"
    "(println \"init:second\")"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println \"main:entry\")"
    "      (ok 0))")
    "\n")

fn ! testTopLevelInit work: String -> Bool
  (let [(src (str work "/topInitMod.asl"))
        (ll (str work "/topInitMod.ll"))]
    (do
      (assert (ok? (fileWrite src (topLevelInitSource))) "topInitMod: source written")
      (expectExit "topInitMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "topInitMod" (lib))
      (let [(native (sh (str work "/topInitMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "topInitMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "topInitMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "init:first\ninit:second\nmain:entry\n") (str "topInitMod: native output matches expected; got " native.stdout))
          (assert (= native.stdout interp.stdout) (str "topInitMod: native stdout equals host stdout; native: " native.stdout " host: " interp.stdout))))
      true))

fn spillSource -> String
  (stringJoin (list
    "(module spillMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn wide a: String b: String c: String d: String e: String f: String -> String"
    "  (str a b c d e f)"
    ""
    "fn wideInts i: Int64 j: Int64 k: Int64 l: Int64 m: Int64 n: Int64 o: Int64 p: Int64 -> Int64"
    "  (+ (+ (+ i (* 2 j)) (+ (* 3 k) (* 4 l))) (+ (+ (* 5 m) (* 6 n)) (+ (* 7 o) (* 8 p))))"
    ""
    "fn rotate n: Int64 a: String b: String c: String d: String -> String"
    "  (if (= n 0) (str a b c d) (rotate (- n 1) b c d a))"
    ""
    "(schema Item (:f name String) (:f tag String))"
    ""
    "fn probe a: String b: String c: String d: String it: Item -> String"
    "  (let [(x it.name) (y (wide a b c d it.tag it.name)) (z it.name) (t it.tag)]"
    "    (str x y z t))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(s1 \"1\") (s2 \"2\") (s3 \"3\") (s4 \"4\")"
    "        (w (wide \"a\" \"b\" \"c\" \"d\" \"e\" \"f\"))"
    "        (after (str w \"|\" s1))"
    "        (folded (fold (fn [(acc String) (x String)] -> String (str acc x s1 s2 s3 s4)) \"\" (list \"p\" \"q\")))]"
    "    (do (println after)"
    "        (println (probe \"a\" \"b\" \"c\" \"d\" (Item :name \"N\" :tag \"T\")))"
    "        (println (stringFromInt64 (wideInts 1 2 3 4 5 6 7 8)))"
    "        (println (rotate 200001 \"w\" \"x\" \"y\" \"z\"))"
    "        (println folded)"
    "        (ok 0)))")
    "\n")

fn ! testSpillArgs work: String -> Bool
  (let [(src (str work "/spillMod.asl"))
        (ll (str work "/spillMod.ll"))]
    (do
      (assert (ok? (fileWrite src (spillSource))) "spillMod: source written")
      (expectExit "spillMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (assert (stringContains? (fileText ll) "@asl_rt_spill = external global [1024 x %Val]") "spillMod: overflow arguments pass through asl_rt_spill")
      (link work "spillMod" (lib))
      (let [(native (sh (str work "/spillMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "spillMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= native.stdout "abcdef|1\nNabcdTNNT\n204\nxyzw\np1234q1234\n") (str "spillMod: native output; got " native.stdout))
          (assert (= native.stdout interp.stdout) (str "spillMod: native stdout equals host stdout; host: " interp.stdout))))
      true))

fn clocksSource -> String
  (stringJoin (list
    "(module clocksMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(t1 (nowNs))"
    "        (t2 (monotonicNs))]"
    "    (do (if (and (> t1 1000000) (> t2 1000000))"
    "          (println \"clocks:valid\")"
    "          (println \"clocks:invalid\"))"
    "        (ok 0)))")
    "\n")

fn ! testClocks work: String -> Bool
  (let [(src (str work "/clocksMod.asl"))
        (ll (str work "/clocksMod.ll"))]
    (do
      (assert (ok? (fileWrite src (clocksSource))) "clocksMod: source written")
      (expectExit "clocksMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "clocksMod" (lib))
      (let [(native (sh (str work "/clocksMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "clocksMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "clocksMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "clocks:valid\n") (str "clocksMod: native output valid; got " native.stdout))
          (assert (= native.stdout interp.stdout) "clocksMod: native stdout equals host stdout")))
      true))

fn schemaDefaultsSource -> String
  (stringJoin (list
    "(module schemaDefaultsMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(schema Person"
    "  (:f name String)"
    "  (:f age Int64 :default 30)"
    "  (:f nickname (Option String) :default (none))"
    "  (:f verified Bool :default false)"
    "  (:f code String :default \"\\u{62}\"))"
    ""
    "fn optStr o: (Option String) -> String"
    "  (mt o ((some s) s) ((none) \"none\"))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(p (Person :name \"Alice\"))]"
    "    (do (println (str p.name \"|\""
    "                      (stringFromInt64 p.age) \"|\""
    "                      (optStr p.nickname) \"|\""
    "                      (if p.verified \"true\" \"false\") \"|\""
    "                      p.code))"
    "        (ok 0)))")
    "\n")

fn ! testSchemaDefaults work: String -> Bool
  (let [(src (str work "/schemaDefaultsMod.asl"))
        (ll (str work "/schemaDefaultsMod.ll"))]
    (do
      (assert (ok? (fileWrite src (schemaDefaultsSource))) "schemaDefaultsMod: source written")
      (expectExit "schemaDefaultsMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "schemaDefaultsMod" (lib))
      (let [(native (sh (str work "/schemaDefaultsMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "schemaDefaultsMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "schemaDefaultsMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "Alice|30|none|false|b\n") (str "schemaDefaultsMod: native output matches expected; got " native.stdout))
          (assert (= native.stdout interp.stdout) "schemaDefaultsMod: native stdout equals host stdout")))
      true))

fn schemaDefaultsShadowSource -> String
  (stringJoin (list
    "(module schemaDefaultsShadowMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn tagText -> String"
    "  \"module-tag\""
    ""
    "(schema Widget"
    "  (:f name String)"
    "  (:f tag String :default (tagText)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(tagText (fn [] \"local-shadow\")) (w (Widget :name \"gadget\"))]"
    "    (do (println (str w.name \"|\" w.tag))"
    "        (ok 0)))")
    "\n")

fn ! testSchemaDefaultsShadow work: String -> Bool
  (let [(src (str work "/schemaDefaultsShadowMod.asl"))
        (ll (str work "/schemaDefaultsShadowMod.ll"))]
    (do
      (assert (ok? (fileWrite src (schemaDefaultsShadowSource))) "schemaDefaultsShadowMod: source written")
      (expectExit "schemaDefaultsShadowMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "schemaDefaultsShadowMod" (lib))
      (let [(native (sh (str work "/schemaDefaultsShadowMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "schemaDefaultsShadowMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "schemaDefaultsShadowMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "gadget|module-tag\n") (str "schemaDefaultsShadowMod: a caller-local of the same name must not change the default; got " native.stdout))
          (assert (= native.stdout interp.stdout) "schemaDefaultsShadowMod: native stdout equals host stdout")))
      true))

fn schemaDefaultsScopeLibSource -> String
  (stringJoin (list
    "(module schemaDefaultsScopeLib"
    "  :x [Widget]"
    "  :i [])"
    ""
    "fn tagText -> String"
    "  \"lib-tag\""
    ""
    "(schema Widget"
    "  (:f name String)"
    "  (:f tag String :default (tagText)))")
    "\n")

fn schemaDefaultsScopeModSource -> String
  (stringJoin (list
    "(module schemaDefaultsScopeMod"
    "  :x [main]"
    "  :i [(schemaDefaultsScopeLib :a lib)])"
    ""
    "fn tagText -> String"
    "  \"caller-tag\""
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(w (lib/Widget :name \"gadget\"))]"
    "    (do (println (str w.name \"|\" w.tag))"
    "        (ok 0)))")
    "\n")

fn ! testSchemaDefaultsScope work: String -> Bool
  (let [(cfg (str work "/.asl.config.asn"))
        (libSrc (str work "/schemaDefaultsScopeLib.asl"))
        (src (str work "/schemaDefaultsScopeMod.asl"))
        (ll (str work "/schemaDefaultsScopeMod.ll"))]
    (do
      (assert (ok? (fileWrite cfg "(:aslConfig :workspace \"schemaDefaultsScope\")")) "schemaDefaultsScope: config marker written")
      (assert (ok? (fileWrite libSrc (schemaDefaultsScopeLibSource))) "schemaDefaultsScopeLib: source written")
      (assert (ok? (fileWrite src (schemaDefaultsScopeModSource))) "schemaDefaultsScopeMod: source written")
      (expectExit "schemaDefaultsScopeMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "schemaDefaultsScopeMod" (lib))
      (let [(native (sh (str work "/schemaDefaultsScopeMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "schemaDefaultsScopeMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "schemaDefaultsScopeMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "gadget|lib-tag\n") (str "schemaDefaultsScopeMod: the importer's own same-named private fn must not be used; got " native.stdout))
          (assert (= native.stdout interp.stdout) "schemaDefaultsScopeMod: native stdout equals host stdout")))
      true))

fn schemaDefaultsCollideLibASource -> String
  (stringJoin (list
    "(module schemaDefaultsCollideLibA"
    "  :x [Widget]"
    "  :i [])"
    ""
    "fn tagText -> String"
    "  \"tag-a\""
    ""
    "(schema Widget"
    "  (:f name String)"
    "  (:f tag String :default (tagText)))")
    "\n")

fn schemaDefaultsCollideLibBSource -> String
  (stringJoin (list
    "(module schemaDefaultsCollideLibB"
    "  :x [Widget]"
    "  :i [])"
    ""
    "fn tagText -> String"
    "  \"tag-b\""
    ""
    "(schema Widget"
    "  (:f name String)"
    "  (:f tag String :default (tagText)))")
    "\n")

fn schemaDefaultsCollideModSource -> String
  (stringJoin (list
    "(module schemaDefaultsCollideMod"
    "  :x [main]"
    "  :i [(schemaDefaultsCollideLibA :a la) (schemaDefaultsCollideLibB :a lb)])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(wa (la/Widget :name \"alpha\")) (wb (lb/Widget :name \"beta\"))]"
    "    (do (println (str wa.name \"|\" wa.tag \"|\" wb.name \"|\" wb.tag))"
    "        (ok 0)))")
    "\n")

fn ! testSchemaDefaultsCollision work: String -> Bool
  (let [(cfg (str work "/.asl.config.asn"))
        (libASrc (str work "/schemaDefaultsCollideLibA.asl"))
        (libBSrc (str work "/schemaDefaultsCollideLibB.asl"))
        (src (str work "/schemaDefaultsCollideMod.asl"))
        (ll (str work "/schemaDefaultsCollideMod.ll"))]
    (do
      (assert (ok? (fileWrite cfg "(:aslConfig :workspace \"schemaDefaultsCollide\")")) "schemaDefaultsCollide: config marker written")
      (assert (ok? (fileWrite libASrc (schemaDefaultsCollideLibASource))) "schemaDefaultsCollideLibA: source written")
      (assert (ok? (fileWrite libBSrc (schemaDefaultsCollideLibBSource))) "schemaDefaultsCollideLibB: source written")
      (assert (ok? (fileWrite src (schemaDefaultsCollideModSource))) "schemaDefaultsCollideMod: source written")
      (expectExit "schemaDefaultsCollideMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (link work "schemaDefaultsCollideMod" (lib))
      (let [(native (sh (str work "/schemaDefaultsCollideMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "schemaDefaultsCollideMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "schemaDefaultsCollideMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "alpha|tag-a|beta|tag-b\n") (str "schemaDefaultsCollideMod: each library's Widget must get its own default, not the other's; got " native.stdout))
          (assert (= native.stdout interp.stdout) "schemaDefaultsCollideMod: native stdout equals host stdout")))
      true))

fn mathBuiltinsSource -> String
  (stringJoin (list
    "(module mathBuiltinsMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(s1 (sqrt 16.0))"
    "        (s2 (sqrt 2.25))"
    "        (f1 (floor 3.7))"
    "        (f2 (floor -3.2))"
    "        (c1 (ceil 3.2))"
    "        (c2 (ceil -3.7))"
    "        (r1 (round 3.5))"
    "        (r2 (round -3.5))"
    "        (p1 (pow 2.0 10.0))"
    "        (e1 (exp 1.0))"
    "        (l1 (log 2.718281828459045))"
    "        (l2 (log2 8.0))"
    "        (l3 (log10 1000.0))"
    "        (t1 (sin 0.0))"
    "        (t2 (cos 0.0))"
    "        (t3 (tan 0.0))"
    "        (a1 (atan2 1.0 1.0))]"
    "    (do (println (str (stringFromFloat64 s1) \" \""
    "                      (stringFromFloat64 s2) \" \""
    "                      (stringFromFloat64 f1) \" \""
    "                      (stringFromFloat64 f2) \" \""
    "                      (stringFromFloat64 c1) \" \""
    "                      (stringFromFloat64 c2) \" \""
    "                      (stringFromFloat64 r1) \" \""
    "                      (stringFromFloat64 r2) \" \""
    "                      (stringFromFloat64 p1) \" \""
    "                      (stringFromFloat64 e1) \" \""
    "                      (stringFromFloat64 l1) \" \""
    "                      (stringFromFloat64 l2) \" \""
    "                      (stringFromFloat64 l3) \" \""
    "                      (stringFromFloat64 t1) \" \""
    "                      (stringFromFloat64 t2) \" \""
    "                      (stringFromFloat64 t3) \" \""
    "                      (stringFromFloat64 a1)))"
    "        (ok 0)))")
    "\n")

fn preludeSource -> String
  (stringJoin (list
    "(module preludeNative"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (let [(parts (stringSplit \"a,bb,ccc\" \",\"))"
    "        (m (mapSet (mapSet (mapEmpty) \"k\" 7) \"j\" 5))"
    "        (sorted (listSort (list 3 1 2)))]"
    "    (do (println (stringJoin parts \"|\"))"
    "        (println (str (optionOr (mapGet m \"j\") 0) (optionOr (mapGet m \"z\") -1)))"
    "        (println (str sorted))"
    "        (ok 0)))")
    "\n")

fn builtinCallIr -> String
  (stringJoin (list
    "%Val = type { i64, i64 }"
    "@name = private constant [12 x i8] c\"stringSplit\\00\""
    "@text = private constant [3 x i8] c\"a,b\""
    "@sep = private constant [1 x i8] c\",\""
    "declare void @asl_rt_init()"
    "declare %Val @mkStr(ptr, i64)"
    "declare %Val @asl_rt_builtin(ptr, i64, ptr)"
    "define i32 @main() {"
    "  call void @asl_rt_init()"
    "  %s = call %Val @mkStr(ptr @text, i64 3)"
    "  %p = call %Val @mkStr(ptr @sep, i64 1)"
    "  %argv = alloca [2 x %Val]"
    "  %a0 = getelementptr [2 x %Val], ptr %argv, i64 0, i64 0"
    "  store %Val %s, ptr %a0"
    "  %a1 = getelementptr [2 x %Val], ptr %argv, i64 0, i64 1"
    "  store %Val %p, ptr %a1"
    "  %r = call %Val @asl_rt_builtin(ptr @name, i64 2, ptr %argv)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn ! testPreludeNative work: String -> Bool
  (let [(src (str work "/preludeNative.asl"))
        (ll (str work "/preludeNative.ll"))
        (want "a|bb|ccc\n5-1\n(1 2 3)\n")]
    (do
      (assert (ok? (fileWrite src (preludeSource))) "preludeNative: source written")
      (let [(hosted (sh (str (host) " run " src)))]
        (assert (= hosted.stdout want) (str "preludeNative: asl-host prints the expected lines, got " hosted.stdout hosted.stderr)))
      (expectExit "preludeNative: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (let [(ir (fileText ll))]
        (map (fn [(f String)] -> Bool
               (do (assert (stringContains? ir (str "define tailcc %Val @prelude$2E" f "(")) (str "preludeNative: the module defines prelude " f))
                   (refute (stringContains? ir (str "@name." f ",")) (str "preludeNative: no asl_rt_builtin call names " f))
                   true))
             (list "stringSplit" "mapGet" "mapSet" "mapEmpty" "listSort")))
      (link work "preludeNative" (lib))
      (let [(out (sh (str "ASL_PRELUDE=" work "/absent.asl " work "/preludeNative")))]
        (assert (and (= out.exitCode 0) (= out.stdout want)) (str "preludeNative: native prints " out.stdout " exit " out.exitCode " with prelude.asl absent; stderr " out.stderr)))
      (assert (ok? (fileWrite (str work "/builtinCall.ll") (builtinCallIr))) "builtinCall: IR written")
      (let [(out (sh (str (clang) " -x ir " work "/builtinCall.ll -x none " (lib) " -lm -o " work "/builtinCall")))]
        (do (refute (= out.exitCode 0) "builtinCall: a program calling asl_rt_builtin does not link against libaslrt.a")
            (assert (stringContains? out.stderr "asl_rt_builtin") (str "builtinCall: the link error names asl_rt_builtin, got " out.stderr))))
      true))

fn p3aMovedSource -> String
  (stringJoin (list
    "(module p3aMovedMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (do"
    "    (println (str (min 3 7) \" \" (max 3 7) \" \" (min 2.5 1.5) \" \" (max 2.5 1.5)))"
    "    (println (stringFromInt64 -9223372036854775808))"
    "    (println (str (stringStartsWith? \"hello\" \"he\") \" \" (stringStartsWith? \"hello\" \"lo\") \" \" (stringContains? \"hello\" \"ell\") \" \" (stringContains? \"hello\" \"\")))"
    "    (println (str (resultOr (ok 5) 0) \" \" (resultOr (err \"x\") 9)))"
    "    (println (str (resultMap (ok 5) (fn [x] (+ x 1))) \" \" (resultMap (err \"e\") (fn [x] (+ x 1)))))"
    "    (ok 0))")
    "\n")

fn ! testP3aMoved work: String -> Bool
  (let [(src (str work "/p3aMovedMod.asl"))
        (ll (str work "/p3aMovedMod.ll"))]
    (do
      (assert (ok? (fileWrite src (p3aMovedSource))) "p3aMoved: source written")
      (expectExit "p3aMoved: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (let [(ir (fileText ll))]
        (map (fn [(mangled (Pair String String))] -> Bool
               (let [(f (pairFirst mangled)) (sym (pairSecond mangled))]
                 (do (assert (stringContains? ir (str "@prelude$2E" sym "(")) (str "p3aMoved: the module defines prelude " f))
                     (refute (stringContains? ir (str "@asl_rt_b_" sym)) (str "p3aMoved: no asl_rt_b_" f " wrapper"))
                     true)))
             (list (pair "resultOr" "resultOr") (pair "resultMap" "resultMap"))))
      (link work "p3aMovedMod" (lib))
      (let [(native (sh (str work "/p3aMovedMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "p3aMoved: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "p3aMoved: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout interp.stdout) (str "p3aMoved: native stdout equals host stdout; native: " native.stdout " host: " interp.stdout))))
      true))

fn p3bMovedSource -> String
  (stringJoin (list
    "(module p3bMovedMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (let [(xs (range 1 6))"
    "        (k 10)]"
    "    (do"
    "      (println (str (map (fn [x] (* x k)) xs) \" \" (filter (fn [x] (= (mod x 2) 1)) xs) \" \" (listReverse xs) \" \" (listLength xs)))"
    "      (println (str (fold (fn [acc x] (+ acc x)) 0 xs) \" \" (range 3 3) \" \" (range 5 2) \" \" (listLength (list))))"
    "      (println (str (fold (fn [acc x] (+ acc x)) 0 (range 0 1000000))))"
    "      (ok 0)))")
    "\n")

fn ! testP3bMoved work: String -> Bool
  (let [(src (str work "/p3bMovedMod.asl"))
        (ll (str work "/p3bMovedMod.ll"))
        (want "(10 20 30 40 50) (1 3 5) (5 4 3 2 1) 5\n15 () () 0\n499999500000\n")]
    (do
      (assert (ok? (fileWrite src (p3bMovedSource))) "p3bMoved: source written")
      (expectExit "p3bMoved: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (let [(ir (fileText ll))]
        (map (fn [(f String)] -> Bool
               (do (assert (or (stringContains? ir (str "define tailcc %Val @prelude$2E" f "(")) (stringContains? ir (str "define tailcc i64 @prelude$2E" f "("))) (str "p3bMoved: the module defines prelude " f))
                   (refute (stringContains? ir (str "@asl_rt_b_" f)) (str "p3bMoved: no asl_rt_b_" f " entry"))
                   true))
             (list "map" "filter" "fold" "listLength" "listReverse" "range")))
      (link work "p3bMovedMod" (lib))
      (let [(native (sh (str "ASL_PRELUDE=" work "/absent.asl " work "/p3bMovedMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "p3bMoved: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "p3bMoved: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= interp.stdout want) (str "p3bMoved: host prints the pinned text; got " interp.stdout))
          (assert (= native.stdout interp.stdout) (str "p3bMoved: native stdout equals host stdout; native: " native.stdout " host: " interp.stdout))))
      true))

fn ! testMathBuiltins work: String -> Bool
  (let [(src (str work "/mathBuiltinsMod.asl"))
        (ll (str work "/mathBuiltinsMod.ll"))]
    (do
      (assert (ok? (fileWrite src (mathBuiltinsSource))) "mathBuiltinsMod: source written")
      (expectExit "mathBuiltinsMod: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0)
      (let [(llText (fileText ll))]
        (do
          (assert (stringContains? llText "@llvm.sqrt.f64") "mathBuiltinsMod: .ll calls @llvm.sqrt.f64, no asl_rt_b_sqrt")
          (refute (not (stringContains? llText "@llvm.sqrt.f64")) "mathBuiltinsMod: refutes missing @llvm.sqrt.f64")
          (assert (not (stringContains? llText "asl_rt_b_sqrt")) "mathBuiltinsMod: refutes asl_rt_b_sqrt wrapper")
          (assert (stringContains? llText "declare double @pow(double, double)") "mathBuiltinsMod: .ll declares libm @pow directly")))
      (link work "mathBuiltinsMod" (lib))
      (let [(native (sh (str work "/mathBuiltinsMod")))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "mathBuiltinsMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "mathBuiltinsMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout "4.0 1.5 3.0 -4.0 4.0 -3.0 4.0 -4.0 1024.0 2.718281828459045 1.0 3.0 3.0 0.0 1.0 0.0 0.7853981633974483\n")
                  (str "mathBuiltinsMod: native output matches expected; got " native.stdout))
          (assert (= native.stdout interp.stdout) "mathBuiltinsMod: native stdout equals host stdout")))
      true))

fn preludeInlineBadCases -> (List (Pair String String))
  (list (pair "preludeInlineConsBad" "ERR_TYPE: cons expects List, got Int")
        (pair "preludeInlineListHeadBad" "ERR_TYPE: listHead expects List, got Int")
        (pair "preludeInlineListTailBad" "ERR_TYPE: listTail expects List, got Int")
        (pair "preludeInlineListEmptyBad" "ERR_TYPE: listEmpty? expects List, got Int")
        (pair "preludeInlineBytesLengthBad" "ERR_TYPE: bytesLength expects Bytes, got Int"))

fn ! testPreludeInline work: String -> Bool
  (do
    (emit work (abiTest) "preludeInline" "preludeInline")
    (verifyLl "preludeInline" work "preludeInline")
    (link work "preludeInline" (lib))
    (let [(native (sh (str work "/preludeInline")))]
      (assert (= native.exitCode 16) (str "preludeInline: native exit matches the closed form (1 + listLength [2 3]) + (4 + (65 + 200)) = 272, truncated to 16; got " native.exitCode "; stderr " native.stderr)))
    (map (fn [(c (Pair String String))] -> Bool
           (let [(name (pairFirst c)) (want (pairSecond c))]
             (do (emit work (abiTest) name name)
                 (verifyLl name work name)
                 (link work name (lib))
                 (let [(bad (sh (str work "/" name)))]
                   (do (assert (= bad.exitCode 1) (str name ": exits 1 on the forced type mismatch, got " bad.exitCode))
                       (assert (stringContains? bad.stderr want) (str name ": reports the host's own error text " want "; got " bad.stderr))
                       true)))))
         (preludeInlineBadCases))
    (do
      (assert (ok? (fileWrite (str work "/preludeInlineRange.asl")
                              (stringJoin (list "(module preludeInlineRangeMod" "  :x [main]" "  :i [])" ""
                                                 "fn ! main args: (List String) -> (Result Int64 String)"
                                                 "  (let [(b (bytesAlloc 4))]"
                                                 "    (do (bytesGet b 99) (ok 0)))") "\n")))
              "preludeInlineRangeMod: source written")
      (expectExit "preludeInlineRangeMod: asl1 builds it"
                  (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " work "/preludeInlineRange.asl -o " work "/preludeInlineRange.ll") 0)
      (link work "preludeInlineRange" (lib))
      (let [(rangeNative (sh (str work "/preludeInlineRange")))
            (rangeInterp (sh (str (host) " run " work "/preludeInlineRange.asl")))]
        (do
          (assert (= rangeNative.exitCode 1) (str "preludeInlineRangeMod: an out-of-range bytesGet still exits 1, got " rangeNative.exitCode))
          (assert (stringContains? rangeNative.stderr "ERR_RANGE: bytesGet: slot 99 outside 4 bytes")
                  (str "preludeInlineRangeMod: native raises the host's exact ERR_RANGE text from its cold block; got " rangeNative.stderr))
          (assert (stringContains? rangeInterp.stderr "ERR_RANGE: bytesGet: slot 99 outside 4 bytes")
                  (str "preludeInlineRangeMod: asl-host run reports the same ERR_RANGE text; got " rangeInterp.stderr))))
      true))

fn numericGenericLibSource -> String
  (stringJoin (list
    "(module numericGenericLib"
    "  :x [gabs gabsCond gabsAny]"
    "  :i [])"
    ""
    "fn isFloat x: N -> Bool"
    "  (let [s (str (+ x x))]"
    "    (or (stringContains? s \".\") (or (stringContains? s \"e\") (stringContains? s \"n\"))))"
    ""
    "fn gabs x: N -> N"
    "  (if (isFloat x) (if (< x 0.0) (- x) (+ x 0.0)) (if (< x 0) (- x) x))"
    ""
    "fn gabsCond x: N -> N"
    "  (cond ((isFloat x) (if (< x 0.0) (- x) (+ x 0.0))) ((< x 0) (- x)) (else x))"
    ""
    "fn gabsAny x: T -> T"
    "  (if (isFloat x) (if (< x 0.0) (- x) (+ x 0.0)) (if (< x 0) (- x) x))")
    "\n")

fn numericGenericCases -> (List (Pair String String))
  (list (pair "numericGenericInt" "(str (g/gabs -5) \" \" (g/gabs 4) \" \" (g/gabs 0) \" \" (g/gabsCond -7) \" \" (g/gabsCond 3) \" \" (g/gabsAny -6))")
        (pair "numericGenericFloat" "(str (g/gabs -2.5) \" \" (g/gabs 1.5) \" \" (g/gabs -0.0) \" \" (g/gabsCond -0.5) \" \" (g/gabsCond 2.0) \" \" (g/gabsAny -1.25))")
        (pair "numericGenericBoth" "(str (g/gabs -5) \" \" (g/gabs -2.5) \" \" (g/gabsCond 3) \" \" (g/gabsCond -0.5) \" \" (g/gabsAny -6) \" \" (g/gabsAny -1.25))"))

fn numericGenericWant name: String -> String
  (cond ((= name "numericGenericInt") "5 4 0 7 3 6\n")
        ((= name "numericGenericFloat") "2.5 1.5 0.0 0.5 2.0 1.25\n")
        (else "5 2.5 3 0.5 6 1.25\n"))

fn ! testNumericGeneric work: String -> Bool
  (do
    (assert (ok? (fileWrite (str work "/.asl.config.asn") "(:aslConfig :workspace \"numericGeneric\")")) "numericGeneric: config marker written")
    (assert (ok? (fileWrite (str work "/numericGenericLib.asl") (numericGenericLibSource))) "numericGenericLib: source written")
    (map (fn [(c (Pair String String))] -> Bool
           (let [(name (pairFirst c))
                 (src (str work "/" name ".asl"))]
             (do
               (assert (ok? (fileWrite src (stringJoin (list (str "(module " name) "  :x [main]" "  :i [(numericGenericLib :a g)])" ""
                                                            "fn ! main -> (Result Int64 String)"
                                                            (str "  (do (println " (pairSecond c) ") (ok 0))")) "\n")))
                       (str name ": source written"))
               (expectExit (str name ": asl1 builds it") (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " work "/" name ".ll") 0)
               (verifyLl name work name)
               (link work name (lib))
               (let [(native (sh (str work "/" name)))
                     (interp (sh (str (host) " run " src)))]
                 (do
                   (assert (= native.exitCode 0) (str name ": native exit " native.exitCode "; stderr " native.stderr))
                   (assert (= interp.exitCode 0) (str name ": host run exit " interp.exitCode "; stderr " interp.stderr))
                   (assert (= interp.stdout (numericGenericWant name)) (str name ": host prints the pinned text; got " interp.stdout))
                   (assert (= native.stdout interp.stdout) (str name ": native stdout equals host stdout; native: " native.stdout " host: " interp.stdout))
                   true)))))
         (numericGenericCases))
    true)

fn preludeSingleSource -> String
  (stringJoin (list
    "(module preludeSingleMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (do"
    "    (println (stringJoin (stringSplit \"a,bb,ccc\" \",\") \"|\"))"
    "    (println (str (resultOr (err \"x\") 9) \" \" (resultOr (ok 4) 0) \" \" (listContains? (list 1 2 3) 2)))"
    "    (ok 0))")
    "\n")

fn diagText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) ds) "; ")

fn ! testPreludeSingleModule work: String -> Bool
  (let [(src (str work "/preludeSingleMod.asl"))
        (want "a|bb|ccc\n9 4 true\n")
        (preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do
      (assert (ok? (fileWrite src (preludeSingleSource))) "preludeSingle: source written")
      (refute (stringEmpty? preludeText) (str "preludeSingle: " (lk/preludePath) " is readable"))
      (let [(hosted (sh (str (host) " run " src)))]
        (assert (and (= hosted.exitCode 0) (= hosted.stdout want)) (str "preludeSingle: asl-host prints the expected lines, got " hosted.stdout hosted.stderr)))
      (mt (low/lowerSource (preludeSingleSource))
        ((ok _) (assert false "preludeSingle: plain lowerSource has no prelude, so stringJoin is outside its subset"))
        ((err ds) (assert (stringContains? (diagText ds) "'stringJoin' is neither a module function nor a builtin") (str "preludeSingle: plain lowerSource rejects stringJoin: " (diagText ds)))))
      (mt (lk/lowerSourceLinked! (preludeSingleSource))
        ((err ds) (assert false (str "preludeSingle: lowerSourceLinked! lowers the module: " (diagText ds))))
        ((ok m) (let [(text (prn/printSsa m))]
                  (do (assert (stringContains? text "(fn main ") (str "preludeSingle: the module's main stays unqualified:\n" text))
                      (map (fn [(f String)] -> Bool
                             (do (assert (stringContains? text (str "(fn prelude." f " ")) (str "preludeSingle: the closure defines prelude." f))
                                 true))
                           (list "stringSplit" "stringJoin" "resultOr" "listContains?" "preludeSplit" "preludeSlice"))
                      (refute (stringContains? text "(fn prelude.listSort ") "preludeSingle: an unreached prelude function stays out")
                      true))))
      (mt (llvm/emitLlvmSourceWith (preludeSingleSource) preludeText "main")
        ((err ds) (assert false (str "preludeSingle: emitLlvmSourceWith emits the program: " (diagText ds))))
        ((ok ll) (do (assert (ok? (fileWrite (str work "/preludeSingleLl.ll") ll)) "preludeSingle: .ll written")
                     (assert (stringContains? ll "@prelude$2EstringSplit(") "preludeSingle: the .ll defines prelude.stringSplit")
                     (refute (stringContains? ll "@asl_rt_b_stringSplit") "preludeSingle: no C entry for stringSplit")
                     (link work "preludeSingleLl" (lib))
                     (let [(out (sh (str "ASL_PRELUDE=" work "/absent.asl " work "/preludeSingleLl")))]
                       (assert (and (= out.exitCode 0) (= out.stdout want)) (str "preludeSingle: LLVM native prints " out.stdout " exit " out.exitCode " with prelude.asl absent; stderr " out.stderr))))))
      (mt (cem/emitC11SourceWith (preludeSingleSource) preludeText src)
        ((err m) (assert false (str "preludeSingle: emitC11SourceWith emits the program: " m)))
        ((ok code) (do (assert (ok? (fileWrite (str work "/preludeSingleC.c") code)) "preludeSingle: .c written")
                       (assert (stringContains? code "fn_prelude_2estringSplit(") (str "preludeSingle: the C11 program carries prelude.stringSplit; its native link retired with the C backend (ruling TARGETC, ABIVAL-2 deletes the abi.c entries it calls)")))))
      true))

; (:m :ref NATIVE-SIGPIPE :do "a native binary used to die on SIGPIPE (exit 141) when its stdout reader closed early, unlike asl-host which ignores SIGPIPE at startup (main.c) so a write past a closed pipe returns EPIPE instead; rtAbi.asl's asl_rt_main now ignores SIGPIPE the same way, and every fork+exec child (processRun's shell, processSpawn, procSpawnv) resets it back to SIG_DFL before exec so an ordinary pipeline run through processRun (e.g. 'yes | head') still terminates its own upstream normally. Exit code compared directly against the identical source run under asl-host, which was already correct")

fn sigpipeSource -> String
  (stringJoin (list
    "(module sigpipeFixture :x [main] :i [])"
    ""
    "fn ! loop n: Int64 -> Int64"
    "  (if (<= n 0) 0"
    "    (do (print \"line-0123456789abcdefghijklmnopqrstuvwxyz\\n\")"
    "        (loop (- n 1))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (loop 50000)"
    "      (ok 0))") "\n")

fn ! earlyCloseExit! bin: String -> Int64
  (let [(tag (str (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (fifo (str "/tmp/sigpipeFifo-" tag))
        (marker (str "/tmp/sigpipeExit-" tag))
        (script (str "rm -f " fifo " " marker "; mkfifo " fifo "; "
                     "(" bin " > " fifo " 2>/dev/null; echo $? > " marker ") & "
                     "dd if=" fifo " bs=1 count=1 of=/dev/null 2>/dev/null; "
                     "exec 9<" fifo "; exec 9<&-; wait; cat " marker "; rm -f " fifo " " marker))
        (out (sh script))]
    (optionOr (stringToInt64 (stringTrim out.stdout)) -1))

fn nestedPipelineSource -> String
  (stringJoin (list
    "(module sigpipeNestedFixture :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(out (processRun \"yes 2>/dev/null | head -1\"))]"
    "    (do (print out.stdout)"
    "        (ok out.exitCode)))") "\n")

fn ! testSigpipeIgnored work: String -> Bool
  (let [(src (str work "/sigpipeFixture.asl"))
        (wrote (ok? (fileWrite src (sigpipeSource))))]
    (do
      (assert wrote "sigpipe: source written")
      (expectExit "sigpipeFixture: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " work "/sigpipeFixture.ll") 0)
      (link work "sigpipeFixture" (lib))
      (let [(nativeExit (earlyCloseExit! (str work "/sigpipeFixture")))
            (hostExit (earlyCloseExit! (str (host) " run " src)))]
        (do (assert (= nativeExit 0) (str "sigpipe: native exits 0 when the reader closes early (same as asl-host), got " nativeExit))
            (assert (= hostExit 0) (str "sigpipe: asl-host exits 0 when the reader closes early, got " hostExit))))
      true))

fn ! testSigpipeChildResetsToDefault work: String -> Bool
  (let [(src (str work "/sigpipeNestedFixture.asl"))
        (wrote (ok? (fileWrite src (nestedPipelineSource))))]
    (do
      (assert wrote "sigpipeNested: source written")
      (expectExit "sigpipeNestedFixture: asl1 builds it" (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " work "/sigpipeNestedFixture.ll") 0)
      (link work "sigpipeNestedFixture" (lib))
      (let [(watchScript (str "( " work "/sigpipeNestedFixture >/tmp/sigpipeNestedOut 2>/dev/null ; echo done >/tmp/sigpipeNestedDone ) & "
                               "BG=$!; sleep 2; "
                               "if kill -0 $BG 2>/dev/null; then echo HUNG; kill -9 $BG; else echo FINISHED; fi"))
            (watch (sh watchScript))]
        (assert (stringContains? watch.stdout "FINISHED")
                (str "sigpipeNested: processRun's own 'yes | head -1' child resets SIGPIPE to SIG_DFL before exec, so it terminates within 2s instead of inheriting the ignored disposition and hanging: " watch.stdout)))
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testIrFixtures work)
      (testTraps work)
      (testSourceFib work)
      (testAlloc work)
      (testBuiltinTableSync)
      (testArrayTableSync)
      (testRuntimeLink work)
      (testByValueAbi work)
      (testInlineVariantAndCapture work)
      (testSpillArgs work)
      (testRuntimeErrors work)
      (testInlineTag work)
      (testVariantBoundary work)
      (testFusedFields work)
      (testStaticFields work)
      (testTypedFields work)
      (testUnaryMinus work)
      (testMainArgs work)
      (testTailCalls work)
      (testHostArithmetic work)
      (testFileReadlink work)
      (testHostFloat work)
      (testFloatExponentLiteral work)
      (testNegation work)
      (testFrontEnd work)
      (testEscapeBytes work)
      (testSharedArithmeticSuite work)
      (testTopLevelInit work)
      (testClocks work)
      (testSchemaDefaults work)
      (testSchemaDefaultsShadow work)
      (testSchemaDefaultsScope work)
      (testSchemaDefaultsCollision work)
      (testMathBuiltins work)
      (testPreludeNative work)
      (testP3aMoved work)
      (testP3bMoved work)
      (testPreludeInline work)
      (testNumericGeneric work)
      (testPreludeSingleModule work)
      (testSigpipeIgnored work)
      (testSigpipeChildResetsToDefault work)
      (let [(formatGate (sh (str (host) " test asl/packages/asl-target-llvm/tests/nativeFormatTest.asl")))]
        (assert (and (= formatGate.exitCode 0)
                     (stringContains? formatGate.stdout "16 assertion(s) executed, 4 refutation(s) executed"))
                (str "nativeFormatTest: driver ran the standalone formatting gate: " formatGate.stdout formatGate.stderr)))
      (assert (= (exitOf (str "rm -rf " work)) 0) "work directory removed")
      true))
