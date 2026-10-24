(module asl-target-llvm/tests/nativePerfTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-target-llvm/tests/nativeOracle :a oracle)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): nativeRun and the inline 'asl-host run asl/tools/nativeTest.asl run ...' shells in testTypedFields/testListBuilders/testFloorFix/testBits used asl-host purely as a launcher for asl/tools/nativeTest.asl's native-build-and-run pipeline, never as an oracle; they become '<selfBin> run ...' where selfBin is oracle/selfTestBinary!, a self-compiled native binary of asl/tools/nativeTest.asl itself (confirmed drop-in identical behavior). hostRun, used only in testTraps/testGcStress as the live interpretation oracle compared against native output, has no replacement interpreter left; its results are fixed per case (trapProbe.asl and the bench/native fixtures are deterministic), so they become recordedTrap/recordedGc literal tables captured once from the leftover asl-host binary before HL-DELETE removed it")

(schema Recorded
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn probe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! nativeRun ntBin: String cache: String env: String path: String args: String -> ProcessOutput
  (sh (str "ASL_NATIVE_TEST_CACHE='" cache "' " env " nice -n 15 " ntBin " run " path " " args " </dev/null"))

fn errorTail text: String -> String
  (match (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) (stringLines text)))
    ((none) "")
    ((some line) (match (stringIndexOf line "ERR_")
                   ((some i) (stringReplace (optionOr (stringSlice line i (stringLength line)) line) " (after 0 asserts)" ""))
                   ((none) line))))

fn ! sameOutcome what: String native: ProcessOutput host: Recorded -> Bool
  (do
    (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str what ": native run does not fall back: " native.stderr))
    (assert (= (= native.exitCode 0) (= host.exitCode 0)) (str what ": native exit " native.exitCode " agrees with the recorded asl-host exit " host.exitCode))
    (assert (= native.stdout host.stdout) (str what ": native stdout " native.stdout " equals the recorded asl-host stdout " host.stdout))
    (assert (= (errorTail native.stderr) (errorTail (str host.stdout "\n" host.stderr))) (str what ": native error '" (errorTail native.stderr) "' equals the recorded asl-host's '" (errorTail host.stderr) "'"))
    true)

fn recordedTrap args: String -> Recorded
  (cond
    ((= args "add 9223372036854775807 1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "bytesGet 4 -1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_RANGE: bytesGet: slot -1 outside 4 bytes (after 0 asserts)\n"))
    ((= args "bytesGet 4 3") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "bytesGet 4 4") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_RANGE: bytesGet: slot 4 outside 4 bytes (after 0 asserts)\n"))
    ((= args "bytesLength 0") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "bytesLength 9") (Recorded :exitCode 0 :stdout "9\n" :stderr ""))
    ((= args "countUp 9223372036854775800 9223372036854775807") (Recorded :exitCode 0 :stdout "7\n" :stderr ""))
    ((= args "countUp 9223372036854775806 -1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "div -7 -2") (Recorded :exitCode 0 :stdout "3\n" :stderr ""))
    ((= args "div -7 2") (Recorded :exitCode 0 :stdout "-4\n" :stderr ""))
    ((= args "div -8 2") (Recorded :exitCode 0 :stdout "-4\n" :stderr ""))
    ((= args "div -9223372036854775808 -1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int / leaves int64 (after 0 asserts)\n"))
    ((= args "div 7 -2") (Recorded :exitCode 0 :stdout "-4\n" :stderr ""))
    ((= args "div 7 0") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_DIV_ZERO: division by zero (after 0 asserts)\n"))
    ((= args "divConst -9223372036854775808") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int / leaves int64 (after 0 asserts)\n"))
    ((= args "fields -3 5") (Recorded :exitCode 0 :stdout "2 10.0 no fields -3\n" :stderr ""))
    ((= args "fields 40 2") (Recorded :exitCode 0 :stdout "42 4.0 yes fields 40\n" :stderr ""))
    ((= args "fields 9223372036854775807 1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "filterOrder 0 2") (Recorded :exitCode 0 :stdout "()\n" :stderr ""))
    ((= args "filterOrder 7 2") (Recorded :exitCode 0 :stdout "0,1,2,3,4,5,6,(0 2 4 6)\n" :stderr ""))
    ((= args "index 5 -1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_RANGE: i64ArrayGet index -1 outside length 5 (after 0 asserts)\n"))
    ((= args "index 5 4") (Recorded :exitCode 0 :stdout "8\n" :stderr ""))
    ((= args "index 5 5") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_RANGE: i64ArrayGet index 5 outside length 5 (after 0 asserts)\n"))
    ((= args "listOps 0") (Recorded :exitCode 0 :stdout "(none) (none) true\n" :stderr ""))
    ((= args "listOps 3") (Recorded :exitCode 0 :stdout "(some 0) (some (1 2)) false\n" :stderr ""))
    ((= args "mapOrder 0 3") (Recorded :exitCode 0 :stdout "()\n" :stderr ""))
    ((= args "mapOrder 5 3") (Recorded :exitCode 0 :stdout "0,1,2,3,4,(0 3 6 9 12)\n" :stderr ""))
    ((= args "mapTrap 9223372036854775807 1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "mod -6 3") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "mod -7 -3") (Recorded :exitCode 0 :stdout "-1\n" :stderr ""))
    ((= args "mod -7 3") (Recorded :exitCode 0 :stdout "2\n" :stderr ""))
    ((= args "mod -9223372036854775808 -1") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "mod 7 -3") (Recorded :exitCode 0 :stdout "-2\n" :stderr ""))
    ((= args "mod 7 0") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_DIV_ZERO: mod by zero (after 0 asserts)\n"))
    ((= args "modConst -9") (Recorded :exitCode 0 :stdout "5\n" :stderr ""))
    ((= args "modConstMul -1 3037000500") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "modConstMul 3037000499 3037000500") (Recorded :exitCode 0 :stdout "9223372033963249500\n" :stderr ""))
    ((= args "modConstMul 3037000500 3037000500") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "modMul 3037000500 1000 3037000500") (Recorded :exitCode 0 :stdout "1518500250000\n" :stderr ""))
    ((= args "modMul 3037000500 3037000501 3037000500") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "mul 4611686018427387904 2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "neg -9223372036854775808") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int - leaves int64 (after 0 asserts)\n"))
    ((= args "scaled 0 1000") (Recorded :exitCode 0 :stdout "691508967\n" :stderr ""))
    ((= args "stringLength -9223372036854775808") (Recorded :exitCode 0 :stdout "32\n" :stderr ""))
    ((= args "sub -9223372036854775808 1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl: ERR_INT_OVERFLOW: Int - leaves int64 (after 0 asserts)\n"))
    (else (Recorded :exitCode -1 :stdout "" :stderr (str "no recorded trap case: " args))))

fn recordedGc name: String -> Recorded
  (cond
    ((= name "list") (Recorded :exitCode 0 :stdout "1689750\n" :stderr ""))
    ((= name "map") (Recorded :exitCode 0 :stdout "16 1124250\n" :stderr ""))
    ((= name "record") (Recorded :exitCode 0 :stdout "1350 -3\n" :stderr ""))
    ((= name "str") (Recorded :exitCode 0 :stdout "10592 377 9\n" :stderr ""))
    (else (Recorded :exitCode -1 :stdout "" :stderr (str "no recorded gc case: " name))))

fn trapCases -> (List (Pair String String))
  (list (pair "add 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "sub -9223372036854775808 1" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "mul 4611686018427387904 2" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "div 7 0" "ERR_DIV_ZERO: division by zero")
        (pair "mod 7 0" "ERR_DIV_ZERO: mod by zero")
        (pair "div -9223372036854775808 -1" "ERR_INT_OVERFLOW: Int / leaves int64")
        (pair "divConst -9223372036854775808" "ERR_INT_OVERFLOW: Int / leaves int64")
        (pair "neg -9223372036854775808" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "countUp 9223372036854775806 -1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "modMul 3037000500 3037000501 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "modConstMul 3037000500 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "modConstMul -1 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "index 5 5" "ERR_RANGE: i64ArrayGet index 5 outside length 5")
        (pair "index 5 -1" "ERR_RANGE: i64ArrayGet index -1 outside length 5")
        (pair "modConst -9" "")
        (pair "scaled 0 1000" "")
        (pair "modMul 3037000500 1000 3037000500" "")
        (pair "modConstMul 3037000499 3037000500" "")
        (pair "countUp 9223372036854775800 9223372036854775807" "")
        (pair "index 5 4" "")
        (pair "fields 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "fields 40 2" "")
        (pair "fields -3 5" "")
        (pair "mapOrder 5 3" "")
        (pair "mapOrder 0 3" "")
        (pair "filterOrder 7 2" "")
        (pair "filterOrder 0 2" "")
        (pair "mapTrap 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "mod -7 3" "")
        (pair "mod 7 -3" "")
        (pair "mod -7 -3" "")
        (pair "mod -6 3" "")
        (pair "mod -9223372036854775808 -1" "")
        (pair "div -7 2" "")
        (pair "div 7 -2" "")
        (pair "div -7 -2" "")
        (pair "div -8 2" "")
        (pair "listOps 3" "")
        (pair "listOps 0" "")
        (pair "bytesGet 4 3" "")
        (pair "bytesGet 4 4" "ERR_RANGE: bytesGet: slot 4 outside 4 bytes")
        (pair "bytesGet 4 -1" "ERR_RANGE: bytesGet: slot -1 outside 4 bytes")
        (pair "bytesLength 0" "")
        (pair "bytesLength 9" "")
        (pair "stringLength -9223372036854775808" ""))

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "filterNonBool/listOpsVal/stringLengthVal used to live in trapProbe.asl's own failing cond, but each is a genuine static type error (confirmed via asl check in isolation), not a runtime trap like the rest of trapCases; U4-MARKER-PARITY's whole-file gate on nativeTest run rejected the whole trapProbe.asl file over them, blocking every other (well-typed) case in the same file. Each now lives in its own single-purpose probe fixture; testStaticTypeRejections asserts nativeTest run rejects it with the exact static error, in place of the old runtime-trap parity check")
fn typeProbeCases -> (List (Pair String String))
  (list (pair "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/filterNonBoolProbe.asl" "ERR_TYPE_MISMATCH argument to filter: expected Bool, found Int64")
        (pair "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/listOpsValProbe.asl" "ERR_TYPE_MISMATCH argument to (fn (list xs) (listHead xs)): expected (List _), found Int64")
        (pair "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/stringLengthValProbe.asl" "ERR_TYPE_MISMATCH argument to (fn (list s) (stringLength s)): expected String, found Int64"))

fn ! testStaticTypeRejections ntBin: String cache: String -> Bool
  (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
          (let [(path (pairFirst c))
                (want (pairSecond c))
                (native (nativeRun ntBin cache "" path "1 1"))]
            (do (assert (!= native.exitCode 0) (str path ": nativeTest run must reject a statically ill-typed probe, got exit " native.exitCode))
                (assert (= (errorTail native.stderr) want) (str path ": expected '" want "', got '" (errorTail native.stderr) "'"))
                (and acc true))))
        true (typeProbeCases))

fn ! testTraps ntBin: String cache: String -> Bool
  (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
          (let [(args (pairFirst c))
                (native (nativeRun ntBin cache "" (probe) args))
                (host (recordedTrap args))]
            (do (sameOutcome (str "trapProbe " args) native host)
                (assert (= (errorTail native.stderr) (pairSecond c)) (str "trapProbe " args ": native error is '" (pairSecond c) "', got '" (errorTail native.stderr) "'"))
                (and acc true))))
        true (trapCases))

fn ! testGcStress cache: String -> Bool
  (let [(fp (nt/fingerprint))]
    (fold (fn [(acc Bool) (name String)] -> Bool
            (let [(path (str "bench/native/" name ".asl"))
                  (built (nt/prepareRunIn cache path fp))
                  (host (recordedGc name))]
              (match built.binary
                ((none) (do (assert false (str name ": native build falls back: " built.reason)) false))
                ((some bin)
                 (let [(native (sh (str "ASL_GC_STRESS=1 ASL_GC_VERIFY=1 ASL_PRELUDE=asl/host/out/prelude.asl nice -n 15 " bin " 1500 </dev/null")))]
                   (do (sameOutcome (str name " under ASL_GC_STRESS=1 ASL_GC_VERIFY=1") native host)
                       (assert (= native.exitCode 0) (str name ": stressed native run exits 0: " native.stderr))
                       (and acc true)))))))
          true (list "list" "record" "map" "str")))

fn ! testTypedFields ntBin: String cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/typed' ASL_NATIVE_KEEP_LL=1 nice -n 15 " ntBin " run bench/native/record.asl 1000 </dev/null")))
        (step (sh (str "cat $(find '" cache "/typed' -name '*.ll') | awk '/^define .*record[$]2Estep[$]24sr[(]/,/^}/'")))]
    (do (assert (= native.exitCode 0) (str "record bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "820 41") "record bench at 1000 prints 820 41")
        (assert (stringContains? step.stdout "define tailcc %Val @bench$2Fnative$2Frecord$2Estep$24sr(") "the kept IR holds the loop of record.step, its recordScalar worker (RECSROA)")
        (assert (not (stringContains? step.stdout "@opsrt.add(")) "record.step adds its Int64 fields raw, with no @opsrt.add call")
        (assert (stringContains? step.stdout "@llvm.sadd.with.overflow.i64") "the raw add of the fields keeps its overflow check")
        true))

fn ! testListBuilders ntBin: String cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/builders' ASL_NATIVE_KEEP_LL=1 nice -n 15 " ntBin " run bench/native/list.asl 1000 </dev/null")))
        (lls (str "$(find '" cache "/builders' -name '*.ll')"))
        (mapBody (sh (str "cat " lls " | awk '/^define .*@prelude[$]2Emap[(]/,/^}/'")).stdout)
        (filterBody (sh (str "cat " lls " | awk '/^define .*@prelude[$]2Efilter[(]/,/^}/'")).stdout)]
    (do (assert (= native.exitCode 0) (str "list bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "751500") "list bench at 1000 prints 751500")
        (assert (stringContains? mapBody "call ptr @gcAsl.allocFastCons(i32 1, i64 40)") "prelude.map allocates its cells in the loop through the ALLOC-INLINE cons fast path")
        (assert (stringContains? filterBody "call ptr @gcAsl.allocFastCons(i32 1, i64 40)") "prelude.filter allocates its cells in the loop through the ALLOC-INLINE cons fast path")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2EpreludeMapOnto")) "prelude.map does not build a reversed copy")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2EpreludeFilterOnto")) "prelude.filter does not build a reversed copy")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2ElistReverse")) "neither reverses its result")
        true))

fn ! testFloorFix ntBin: String cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/floor' ASL_NATIVE_KEEP_LL=1 nice -n 15 " ntBin " run bench/native/loop.asl 1000 </dev/null")))
        (go (sh (str "cat $(find '" cache "/floor' -name '*.ll') | awk '/^define .*loop[$]2Ego[(]/,/^}/'")).stdout)]
    (do (assert (= native.exitCode 0) (str "loop bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "691508967") "loop bench at 1000 prints 691508967")
        (assert (stringContains? go "call i64 @mathrt.floorModFix(") "loop.go fixes a negative remainder in the cold helper")
        (assert (stringContains? go "@llvm.expect.i1(") "the fix-up branch is marked unlikely")
        (assert (not (stringContains? go ".p.shifted")) "no inline shifted-remainder select remains in loop.go")
        true))

fn bitProbe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/bitProbe.asl"

fn bitCases -> (List (Pair String String))
  (list
        (pair "and -1 9223372036854775807" "9223372036854775807 9223372036854775807")
        (pair "and -9223372036854775808 -1" "-9223372036854775808 -9223372036854775808")
        (pair "and -6 3" "2 2")
        (pair "or -9223372036854775808 9223372036854775807" "-1 -1")
        (pair "or -8 5" "-3 -3")
        (pair "xor -1 9223372036854775807" "-9223372036854775808 -9223372036854775808")
        (pair "xor -6 3" "-7 -7")
        (pair "xor -9223372036854775808 -9223372036854775808" "0 0")
        (pair "not 9223372036854775807" "-9223372036854775808 -9223372036854775808")
        (pair "not -9223372036854775808" "9223372036854775807 9223372036854775807")
        (pair "not 0" "-1 -1")
        (pair "not -6" "5 5")
        (pair "shl 1 63" "-9223372036854775808 -9223372036854775808")
        (pair "shl 1 64" "1 1")
        (pair "shl 3 -1" "-9223372036854775808 -9223372036854775808")
        (pair "shl 9223372036854775807 1" "-2 -2")
        (pair "shl -5 2" "-20 -20")
        (pair "shr -9223372036854775808 63" "-1 -1")
        (pair "shr -16 2" "-4 -4")
        (pair "shr 9223372036854775807 64" "9223372036854775807 9223372036854775807")
        (pair "shr -1 -1" "-1 -1")
        (pair "shr 5 -63" "2 2")
        (pair "shr -9223372036854775808 0" "-9223372036854775808 -9223372036854775808"))

fn ! testBits ntBin: String cache: String -> Bool
  (let [(results (map (fn [(c (Pair String String))] -> Bool
                        (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' ASL_NATIVE_KEEP_LL=1 nice -n 15 " ntBin " run " (bitProbe) " " (pairFirst c) " </dev/null")))]
                          (do (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str "bitProbe " (pairFirst c) ": native run does not fall back: " native.stderr))
                              (assert (= native.exitCode 0) (str "bitProbe " (pairFirst c) " exits 0: " native.stderr))
                              (assert (= (stringTrim native.stdout) (pairSecond c)) (str "bitProbe " (pairFirst c) " prints '" (pairSecond c) "', got '" (stringTrim native.stdout) "'"))
                              true)))
                      (bitCases)))
        (andText (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' nice -n 15 " ntBin " run asl/packages/asl-target-llvm/tests/fixtures/nativePerf/bitAndTextProbe.asl 3 </dev/null")))
        (notText (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' nice -n 15 " ntBin " run asl/packages/asl-target-llvm/tests/fixtures/nativePerf/bitNotTextProbe.asl </dev/null")))
        (rawOp (sh (str "cat $(find '" cache "/bits' -name '*.ll') | awk '/^define .*bitProbe[$]2ErawOp[(]/,/^}/'")).stdout)]
    (do (assert (= (listLength results) (listLength (bitCases))) "every bitProbe case ran")
        (assert (!= andText.exitCode 0) "& over a String Val is rejected statically")
        (assert (= (errorTail andText.stderr) "ERR_TYPE_MISMATCH argument to (fn (list x y) (& x y)): expected Int64, found String") (str "& over a String Val rejected with want()'s text, got '" (errorTail andText.stderr) "'"))
        (assert (!= notText.exitCode 0) "~ over a String Val is rejected statically")
        (assert (= (errorTail notText.stderr) "ERR_TYPE_MISMATCH argument to (fn (list x) (~ x)): expected Int64, found String") (str "~ over a String Val rejected with want()'s text, got '" (errorTail notText.stderr) "'"))
        (assert (stringContains? rawOp "define tailcc i64 @asl$2Dtarget$2Dllvm$2Ftests$2Ffixtures$2FnativePerf$2FbitProbe$2ErawOp(") "the kept IR holds bitProbe.rawOp with a raw i64 signature")
        (assert (stringContains? rawOp " = and i64 %a, %b") "& over raw operands is one and")
        (assert (stringContains? rawOp " = or i64 %a, %b") "| over raw operands is one or")
        (assert (stringContains? rawOp " = xor i64 %a, %b") "^ over raw operands is one xor")
        (assert (stringContains? rawOp " = shl i64 %a, ") "<< over raw operands is one shl behind the count mask")
        (assert (stringContains? rawOp " = ashr i64 %a, ") ">> over raw operands is one ashr behind the count mask")
        (assert (not (stringContains? rawOp "@mathrt.")) "rawOp calls no @mathrt helper")
        true))

fn ! runTests -> Bool
  (match (oracle/selfTestBinary!)
    ((err e) (do (assert false (str "self-building asl/tools/nativeTest.asl: " e)) false))
    ((ok ntBin)
     (let [(made (sh "mktemp -d"))
           (cache (stringTrim made.stdout))]
       (do
         (assert (= made.exitCode 0) "temporary native cache created")
         (testStaticTypeRejections ntBin cache)
         (testTraps ntBin cache)
         (testGcStress cache)
         (testTypedFields ntBin cache)
         (testListBuilders ntBin cache)
         (testFloorFix ntBin cache)
         (testBits ntBin cache)
         (assert (= (sh (str "rm -rf '" cache "'")).exitCode 0) "temporary native cache removed")
         true))))
